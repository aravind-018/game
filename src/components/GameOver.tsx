import React, { useEffect } from 'react';
import confetti from 'canvas-confetti';
import { Trophy, RotateCcw, Sparkles, ArrowLeft } from 'lucide-react';
import { useGame } from '../context/GameContext';
import { useAuth } from '../context/AuthContext';

export const GameOver: React.FC = () => {
  const { room, session, scores, participants, resetGame, leaveRoom, loading, refreshRoomState } = useGame();
  const { user } = useAuth();

  // Poll room state every 2 seconds while on game over so partner automatically transitions back to waiting room
  useEffect(() => {
    if (!room?.id) return;
    const interval = setInterval(() => {
      refreshRoomState();
    }, 2000);
    return () => clearInterval(interval);
  }, [room?.id, refreshRoomState]);

  useEffect(() => {
    // Fire celebration confetti
    try {
      confetti({
        particleCount: 80,
        spread: 70,
        origin: { y: 0.6 },
        colors: ['#f43f5e', '#ec4899', '#a855f7', '#fbbf24'],
      });
    } catch (e) {
      console.warn('Confetti animation error:', e);
    }
  }, []);

  const p1 = participants.find((p) => p.role_slot === 1);
  const p2 = participants.find((p) => p.role_slot === 2);

  const p1Score = scores.find((s) => s.user_id === p1?.user_id)?.score || 0;
  const p2Score = scores.find((s) => s.user_id === p2?.user_id)?.score || 0;
  const matchesCount = Math.max(...scores.map((s) => s.matches_count || 0), 0);

  // Relationship compatibility determination
  const totalRounds = session?.total_rounds || 5;
  const matchPercentage = Math.min(100, Math.round((matchesCount / totalRounds) * 100));

  let compatibilityVerdict = 'Passionate Companions 💕';
  let verdictDescription = 'You bring unique flavors and fun contrasts to each other’s worlds.';

  if (matchPercentage >= 80) {
    compatibilityVerdict = 'Cosmic Soulmates 🔥';
    verdictDescription = 'Your minds and hearts are practically in telepathic sync!';
  } else if (matchPercentage >= 50) {
    compatibilityVerdict = 'Dynamic Power Couple ✨';
    verdictDescription = 'A wonderful blend of shared harmony and playful surprises.';
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 text-center">
      {/* Trophy Icon */}
      <div className="w-20 h-20 mx-auto mb-6 rounded-3xl bg-gradient-to-tr from-amber-500 via-pink-500 to-rose-600 flex items-center justify-center shadow-xl shadow-rose-950/60 animate-bounce">
        <Trophy className="w-10 h-10 text-white" />
      </div>

      <span className="text-xs font-semibold uppercase tracking-widest text-rose-400 mb-2 block">
        Session Finished
      </span>
      <h2 className="text-4xl font-black text-white mb-3">
        Game Complete!
      </h2>
      <p className="text-slate-300 text-sm max-w-md mx-auto mb-8">
        You completed all {totalRounds} rounds together! Here is your relationship connection breakdown:
      </p>

      {/* Compatibility Banner */}
      <div className="p-6 rounded-3xl bg-gradient-to-b from-rose-950/50 to-slate-900 border border-rose-500/40 shadow-2xl mb-8">
        <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-rose-500/20 text-rose-300 text-xs font-semibold mb-3">
          <Sparkles className="w-3.5 h-3.5" />
          <span>Compatibility Rating</span>
        </div>
        <div className="text-5xl font-black text-transparent bg-clip-text bg-gradient-to-r from-pink-400 via-rose-300 to-amber-200 mb-2">
          {matchPercentage}% Match
        </div>
        <h3 className="text-xl font-bold text-white mb-1">{compatibilityVerdict}</h3>
        <p className="text-xs text-slate-400 max-w-sm mx-auto">{verdictDescription}</p>

        <div className="mt-4 pt-4 border-t border-slate-800 flex items-center justify-around text-xs text-slate-300">
          <div>
            <span className="text-slate-500 block">Total Matches</span>
            <span className="text-lg font-bold text-rose-300">{matchesCount}</span>
          </div>
          <div>
            <span className="text-slate-500 block">Rounds Played</span>
            <span className="text-lg font-bold text-rose-300">{totalRounds}</span>
          </div>
        </div>
      </div>

      {/* Player Scores Side-by-Side */}
      <div className="grid grid-cols-2 gap-4 mb-8">
        {/* Player 1 */}
        <div className="p-5 rounded-2xl bg-slate-900/80 border border-slate-800 text-left">
          <div className="flex items-center gap-2 mb-2">
            <div className="w-7 h-7 rounded-full bg-pink-500 flex items-center justify-center text-xs font-bold text-white">
              {p1?.display_name?.charAt(0) || '1'}
            </div>
            <span className="text-sm font-semibold text-slate-200 truncate">
              {p1?.display_name}
              {p1?.user_id === user?.id && ' (You)'}
            </span>
          </div>
          <div className="text-3xl font-black text-white">{p1Score} <span className="text-xs text-slate-500 font-normal">pts</span></div>
        </div>

        {/* Player 2 */}
        <div className="p-5 rounded-2xl bg-slate-900/80 border border-slate-800 text-left">
          <div className="flex items-center gap-2 mb-2">
            <div className="w-7 h-7 rounded-full bg-indigo-500 flex items-center justify-center text-xs font-bold text-white">
              {p2?.display_name?.charAt(0) || '2'}
            </div>
            <span className="text-sm font-semibold text-slate-200 truncate">
              {p2?.display_name || 'Partner'}
              {p2?.user_id === user?.id && ' (You)'}
            </span>
          </div>
          <div className="text-3xl font-black text-white">{p2Score} <span className="text-xs text-slate-500 font-normal">pts</span></div>
        </div>
      </div>

      {/* Action Buttons */}
      <div className="space-y-3">
        <button
          onClick={() => resetGame()}
          disabled={loading}
          className="w-full py-4 px-6 bg-gradient-to-r from-pink-500 via-rose-500 to-rose-600 hover:from-pink-600 hover:to-rose-700 text-white font-bold rounded-2xl shadow-xl shadow-rose-600/30 transition-all flex items-center justify-center gap-2 cursor-pointer text-base disabled:opacity-50"
        >
          <RotateCcw className="w-5 h-5" />
          <span>Play Another Game (Same Room)</span>
        </button>

        <button
          onClick={leaveRoom}
          className="w-full py-3 px-4 bg-slate-800/80 hover:bg-slate-700 border border-slate-700 text-slate-300 font-medium rounded-xl text-xs transition-colors cursor-pointer flex items-center justify-center gap-2"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>Exit to Main Lobby</span>
        </button>
      </div>
    </div>
  );
};
