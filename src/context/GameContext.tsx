import React, { createContext, useContext, useEffect, useState, useCallback, useRef } from 'react';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase, isSupabaseConfigured } from '../lib/supabase';
import { useAuth } from './AuthContext';
import type {
  GameType,
  Room,
  Participant,
  GameSession,
  GameRound,
  PlayerAnswer,
  Score,
} from '../types/game';

interface GameContextType {
  room: Room | null;
  participants: Participant[];
  session: GameSession | null;
  currentRound: GameRound | null;
  answers: PlayerAnswer[];
  scores: Score[];
  isHost: boolean;
  mySlot: 1 | 2 | null;
  partner: Participant | null;
  myAnswer: PlayerAnswer | null;
  partnerSubmitted: boolean;
  isRoundRevealed: boolean;
  isGameFinished: boolean;
  loading: boolean;
  error: string | null;
  createRoom: (displayName: string, selectedGame?: GameType) => Promise<boolean>;
  joinRoom: (roomCode: string, displayName: string) => Promise<boolean>;
  startGame: (gameType: GameType, totalRounds?: number) => Promise<boolean>;
  submitAnswer: (answerText: string, partnerPrediction?: string) => Promise<boolean>;
  advanceRound: () => Promise<boolean>;
  resetGame: () => Promise<boolean>;
  leaveRoom: () => void;
  clearError: () => void;
  addTestPartner: () => Promise<boolean>;
  refreshRoomState: () => Promise<void>;
}

const getErrorMessage = (err: unknown, fallback: string): string => {
  if (!err) return fallback;
  if (typeof err === 'object') {
    const obj = err as Record<string, unknown>;
    if (typeof obj.message === 'string') return obj.message;
    if (typeof obj.error_description === 'string') return obj.error_description;
  }
  if (err instanceof Error) return err.message;
  return fallback;
};

const GameContext = createContext<GameContextType | undefined>(undefined);

export const GameProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user, signInAsGuest } = useAuth();
  const [room, setRoom] = useState<Room | null>(null);
  const [participants, setParticipants] = useState<Participant[]>([]);
  const [session, setSession] = useState<GameSession | null>(null);
  const [currentRound, setCurrentRound] = useState<GameRound | null>(null);
  const [answers, setAnswers] = useState<PlayerAnswer[]>([]);
  const [scores, setScores] = useState<Score[]>([]);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const channelRef = useRef<RealtimeChannel | null>(null);

  const clearError = () => setError(null);

  // Derived state: host is recognized by participant record OR room.host_id matching current user
  const myParticipant = participants.find((p) => p.user_id === user?.id);
  const isHost = Boolean(myParticipant?.is_host || (room && user && room.host_id === user.id));
  const mySlot = myParticipant?.role_slot ?? (room?.host_id === user?.id ? 1 : null);
  const partner = participants.find((p) => p.user_id !== user?.id) ?? null;

  const myAnswer = answers.find((a) => a.user_id === user?.id) ?? null;

  const partnerSubmitted = mySlot === 1 ? Boolean(currentRound?.p2_submitted) : Boolean(currentRound?.p1_submitted);
  const isRoundRevealed = currentRound?.status === 'revealed' || answers.length >= 2;
  const isGameFinished = session?.status === 'finished' || room?.status === 'completed';

  // Cleanup helper
  const unsubscribeChannel = useCallback(() => {
    if (channelRef.current) {
      supabase.removeChannel(channelRef.current);
      channelRef.current = null;
    }
  }, []);

  // Fetch full state for a given room
  const fetchRoomState = useCallback(async (roomId: string) => {
    if (!isSupabaseConfigured) return;

    try {
      // 1. Fetch Room
      const { data: roomData, error: roomError } = await supabase
        .from('rooms')
        .select('*')
        .eq('id', roomId)
        .single();

      if (roomError) throw roomError;
      setRoom(roomData);

      // 2. Fetch Participants
      const { data: partData, error: partError } = await supabase
        .from('room_participants')
        .select('*')
        .eq('room_id', roomId)
        .order('role_slot', { ascending: true });

      if (partError) throw partError;
      setParticipants(partData || []);

      // 3. Fetch Active Game Session
      const { data: sessionData, error: sessError } = await supabase
        .from('game_sessions')
        .select('*')
        .eq('room_id', roomId)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (sessError) throw sessError;
      setSession(sessionData ?? null);

      if (sessionData) {
        // 4. Fetch Scores
        const { data: scoreData } = await supabase
          .from('scores')
          .select('*')
          .eq('session_id', sessionData.id);
        setScores(scoreData || []);

        // 5. Fetch Current Round
        const { data: roundData, error: roundError } = await supabase
          .from('game_rounds')
          .select('*')
          .eq('session_id', sessionData.id)
          .eq('round_number', sessionData.current_round_index)
          .maybeSingle();

        if (roundError) throw roundError;
        setCurrentRound(roundData ?? null);

        // 6. Fetch Answers for this round
        if (roundData) {
          const { data: answersData } = await supabase
            .from('player_answers')
            .select('*')
            .eq('round_id', roundData.id);
          setAnswers(answersData || []);
        } else {
          setAnswers([]);
        }
      } else {
        setCurrentRound(null);
        setAnswers([]);
        setScores([]);
      }
    } catch (err: unknown) {
      console.error('Error fetching room state:', err);
      const msg = getErrorMessage(err, '');
      if (msg) setError(msg);
    }
  }, []);

  // Setup Realtime Subscription
  const setupRealtimeSubscription = useCallback((roomId: string) => {
    unsubscribeChannel();

    const channel = supabase
      .channel(`room-realtime-${roomId}`)
      // Listen to rooms changes
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` },
        (payload) => {
          if (payload.eventType === 'UPDATE' || payload.eventType === 'INSERT') {
            setRoom(payload.new as Room);
          }
        }
      )
      // Listen to room_participants changes
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'room_participants', filter: `room_id=eq.${roomId}` },
        () => {
          fetchRoomState(roomId);
        }
      )
      // Listen to game_sessions changes
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'game_sessions', filter: `room_id=eq.${roomId}` },
        (payload) => {
          if (payload.eventType === 'INSERT' || payload.eventType === 'UPDATE') {
            const updatedSession = payload.new as GameSession;
            setSession(updatedSession);
            fetchRoomState(roomId);
          }
        }
      )
      // Listen to game_rounds changes
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'game_rounds' },
        (payload) => {
          if (payload.eventType === 'UPDATE' || payload.eventType === 'INSERT') {
            const updatedRound = payload.new as GameRound;
            setCurrentRound((prev) => {
              if (prev && prev.id === updatedRound.id) {
                return updatedRound;
              }
              return prev;
            });

            // If round became revealed, reload answers so second player's answer is fetched
            if (updatedRound.status === 'revealed') {
              supabase
                .from('player_answers')
                .select('*')
                .eq('round_id', updatedRound.id)
                .then(({ data }) => {
                  if (data) setAnswers(data);
                });
            }
          }
        }
      )
      // Listen to player_answers changes
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'player_answers' },
        (payload) => {
          if (payload.eventType === 'INSERT' || payload.eventType === 'UPDATE') {
            const newAnswer = payload.new as PlayerAnswer;
            setAnswers((prev) => {
              const existingIdx = prev.findIndex((a) => a.id === newAnswer.id);
              if (existingIdx >= 0) {
                const next = [...prev];
                next[existingIdx] = newAnswer;
                return next;
              }
              return [...prev, newAnswer];
            });
          }
        }
      )
      // Listen to scores changes
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'scores' },
        () => {
          if (session?.id) {
            supabase
              .from('scores')
              .select('*')
              .eq('session_id', session.id)
              .then(({ data }) => {
                if (data) setScores(data);
              });
          }
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log(`Realtime subscribed to room ${roomId}`);
        }
      });

    channelRef.current = channel;
  }, [fetchRoomState, session?.id, unsubscribeChannel]);

  // Create Room RPC
  const createRoom = async (displayName: string, selectedGame?: GameType): Promise<boolean> => {
    setLoading(true);
    setError(null);

    try {
      let activeUser = user;
      if (!activeUser) {
        const authRes = await signInAsGuest(displayName);
        if (!authRes.success || !authRes.error) {
          activeUser = (await supabase.auth.getUser()).data.user;
        }
      }

      if (!activeUser) {
        throw new Error('Could not establish guest session. Please check your Supabase Anonymous auth settings.');
      }

      const { data, error: rpcError } = await supabase.rpc('create_room', {
        p_display_name: displayName,
        p_selected_game: selectedGame || null,
      });

      if (rpcError) throw rpcError;

      const createdRoomId = data.room_id;
      localStorage.setItem('two_of_us_active_room', createdRoomId);

      await fetchRoomState(createdRoomId);
      setupRealtimeSubscription(createdRoomId);
      return true;
    } catch (err: unknown) {
      const msg = getErrorMessage(err, 'Failed to create room');
      setError(msg);
      return false;
    } finally {
      setLoading(false);
    }
  };

  // Join Room RPC
  const joinRoom = async (roomCode: string, displayName: string): Promise<boolean> => {
    setLoading(true);
    setError(null);

    try {
      let activeUser = user;
      if (!activeUser) {
        const authRes = await signInAsGuest(displayName);
        if (!authRes.success) {
          throw new Error(authRes.error || 'Failed to authenticate guest.');
        }
        activeUser = (await supabase.auth.getUser()).data.user;
      }

      if (!activeUser) {
        throw new Error('Could not establish guest session.');
      }

      const { data, error: rpcError } = await supabase.rpc('join_room', {
        p_room_code: roomCode.trim().toUpperCase(),
        p_display_name: displayName.trim(),
      });

      if (rpcError) throw rpcError;

      const joinedRoomId = data.room_id;
      localStorage.setItem('two_of_us_active_room', joinedRoomId);

      await fetchRoomState(joinedRoomId);
      setupRealtimeSubscription(joinedRoomId);
      return true;
    } catch (err: unknown) {
      const msg = getErrorMessage(err, 'Failed to join room');
      setError(msg);
      return false;
    } finally {
      setLoading(false);
    }
  };

  // Start Game RPC
  const startGame = async (gameType: GameType, totalRounds: number = 5): Promise<boolean> => {
    if (!room) return false;
    setLoading(true);
    setError(null);

    try {
      const { error: rpcError } = await supabase.rpc('start_game', {
        p_room_id: room.id,
        p_game_type: gameType,
        p_total_rounds: totalRounds,
      });

      if (rpcError) {
        console.error('start_game RPC returned error:', rpcError);
        throw rpcError;
      }

      await fetchRoomState(room.id);
      return true;
    } catch (err: unknown) {
      console.error('startGame failed:', err);
      const msg = getErrorMessage(err, 'Failed to start game');
      setError(msg);
      return false;
    } finally {
      setLoading(false);
    }
  };

  // Submit Answer RPC
  const submitAnswer = async (answerText: string, partnerPrediction?: string): Promise<boolean> => {
    if (!currentRound) return false;
    setLoading(true);
    setError(null);

    try {
      const { error: rpcError } = await supabase.rpc('submit_player_answer', {
        p_round_id: currentRound.id,
        p_answer_text: answerText,
        p_partner_prediction: partnerPrediction || null,
      });

      if (rpcError) throw rpcError;

      // Refresh round and answers immediately
      const { data: roundData } = await supabase
        .from('game_rounds')
        .select('*')
        .eq('id', currentRound.id)
        .single();

      if (roundData) setCurrentRound(roundData);

      const { data: answersData } = await supabase
        .from('player_answers')
        .select('*')
        .eq('round_id', currentRound.id);

      if (answersData) setAnswers(answersData);

      if (session?.id) {
        const { data: scoreData } = await supabase
          .from('scores')
          .select('*')
          .eq('session_id', session.id);
        if (scoreData) setScores(scoreData);
      }

      return true;
    } catch (err: unknown) {
      const msg = getErrorMessage(err, 'Failed to submit answer');
      setError(msg);
      return false;
    } finally {
      setLoading(false);
    }
  };

  // Advance Round RPC
  const advanceRound = async (): Promise<boolean> => {
    if (!room) return false;
    setLoading(true);
    setError(null);

    try {
      const { error: rpcError } = await supabase.rpc('advance_round', {
        p_room_id: room.id,
      });

      if (rpcError) throw rpcError;

      await fetchRoomState(room.id);
      return true;
    } catch (err: unknown) {
      const msg = getErrorMessage(err, 'Failed to advance round');
      setError(msg);
      return false;
    } finally {
      setLoading(false);
    }
  };

  // Reset Game RPC (Play Again)
  const resetGame = async (): Promise<boolean> => {
    if (!room) return false;
    setLoading(true);
    setError(null);

    try {
      const { error: rpcError } = await supabase.rpc('reset_room_game', {
        p_room_id: room.id,
      });

      if (rpcError) throw rpcError;

      await fetchRoomState(room.id);
      return true;
    } catch (err: unknown) {
      const msg = getErrorMessage(err, 'Failed to reset room');
      setError(msg);
      return false;
    } finally {
      setLoading(false);
    }
  };

  // Add Test Partner (for solo play / quick testing)
  const addTestPartner = async (): Promise<boolean> => {
    if (!room) return false;
    setLoading(true);
    setError(null);

    try {
      const { error: rpcError } = await supabase.rpc('add_test_partner', {
        p_room_id: room.id,
      });

      if (rpcError) throw rpcError;

      await fetchRoomState(room.id);
      return true;
    } catch (err: unknown) {
      const msg = getErrorMessage(err, 'Failed to add test partner');
      setError(msg);
      return false;
    } finally {
      setLoading(false);
    }
  };

  // Manual refresh room state
  const refreshRoomState = async (): Promise<void> => {
    if (room?.id) {
      await fetchRoomState(room.id);
    }
  };

  // Leave Room
  const leaveRoom = () => {
    unsubscribeChannel();
    localStorage.removeItem('two_of_us_active_room');
    setRoom(null);
    setParticipants([]);
    setSession(null);
    setCurrentRound(null);
    setAnswers([]);
    setScores([]);
  };

  // Auto-restore room on refresh
  useEffect(() => {
    const savedRoomId = localStorage.getItem('two_of_us_active_room');
    if (savedRoomId && user && !room) {
      fetchRoomState(savedRoomId);
      setupRealtimeSubscription(savedRoomId);
    }
  }, [user, room, fetchRoomState, setupRealtimeSubscription]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      unsubscribeChannel();
    };
  }, [unsubscribeChannel]);

  return (
    <GameContext.Provider
      value={{
        room,
        participants,
        session,
        currentRound,
        answers,
        scores,
        isHost,
        mySlot,
        partner,
        myAnswer,
        partnerSubmitted,
        isRoundRevealed,
        isGameFinished,
        loading,
        error,
        createRoom,
        joinRoom,
        startGame,
        submitAnswer,
        advanceRound,
        resetGame,
        leaveRoom,
        clearError,
        addTestPartner,
        refreshRoomState,
      }}
    >
      {children}
    </GameContext.Provider>
  );
};

export const useGame = () => {
  const context = useContext(GameContext);
  if (!context) {
    throw new Error('useGame must be used within a GameProvider');
  }
  return context;
};
