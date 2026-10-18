import React, { useState, useEffect } from 'react';
import { 
  Sparkles, 
  Clock, 
  CheckCircle, 
  ArrowRight, 
  Lock, 
  AlertCircle 
} from 'lucide-react';
import { useGame } from '../context/GameContext';
import { useAuth } from '../context/AuthContext';
import { GAMES_CATALOG } from '../types/game';

export const GameArena: React.FC = () => {
  const { 
    room, 
    session, 
    currentRound, 
    answers, 
    scores, 
    participants,
    myAnswer, 

    partnerSubmitted,
    isRoundRevealed, 
    submitAnswer, 
    advanceRound, 
    loading, 
    error,
    clearError 
  } = useGame();
  
  const { user } = useAuth();

  const [selectedOption, setSelectedOption] = useState<string>('');
  const [customText, setCustomText] = useState<string>('');
  const [timeLeft, setTimeLeft] = useState<number>(45);

  const myParticipant = participants.find((p) => p.user_id === user?.id);
  const partner = participants.find((p) => p.user_id !== user?.id);
  const isP1 = myParticipant?.role_slot === 1;

  const p1 = participants.find((p) => p.role_slot === 1);
  const p2 = participants.find((p) => p.role_slot === 2);
  const p1Score = scores.find((s) => s.user_id === p1?.user_id)?.score || 0;
  const p2Score = scores.find((s) => s.user_id === p2?.user_id)?.score || 0;

  const gameInfo = GAMES_CATALOG.find((g) => g.id === session?.game_type);

  // Reset local inputs when round changes
  useEffect(() => {
    setSelectedOption('');
    setCustomText('');
    clearError();
  }, [currentRound?.id, clearError]);

  // Countdown timer derived from round started_at
  useEffect(() => {
    if (!currentRound || isRoundRevealed) return;

    const timer = setInterval(() => {
      if (currentRound.expires_at) {
        const diff = Math.max(0, Math.floor((new Date(currentRound.expires_at).getTime() - Date.now()) / 1000));
        setTimeLeft(diff);
      } else {
        setTimeLeft((prev) => Math.max(0, prev - 1));
      }
    }, 1000);

    return () => clearInterval(timer);
  }, [currentRound, isRoundRevealed]);

  // Handle Answer Lock-in
  const handleSubmit = async (answerVal?: string) => {
    const finalAnswer = answerVal || selectedOption || customText.trim();
    if (!finalAnswer) return;

    // For How Well Do You Know Me, pass prediction if partner is guessing
    let prediction: string | undefined = undefined;
    if (session?.game_type === 'how_well_do_you_know_me' && currentRound?.target_player_id !== user?.id) {
      prediction = finalAnswer;
    }

    await submitAnswer(finalAnswer, prediction);
  };

  const handleAdvance = async () => {
    await advanceRound();
  };

  if (!session || !currentRound) {
    return (
      <div className="max-w-md mx-auto py-20 text-center">
        <div className="w-8 h-8 border-2 border-rose-500 border-t-transparent rounded-full animate-spin mx-auto mb-4" />
        <p className="text-slate-400 text-sm">Preparing next round...</p>
      </div>
    );
  }

  // Determine whose question it is in "How Well Do You Know Me"
  const isTargetPlayer = currentRound.target_player_id === user?.id;
  const targetPlayerName = currentRound.target_player_name || partner?.display_name || 'Partner';

  // Compute option list
  let displayOptions: string[] = [];
  if (session.game_type === 'who_is_more_likely_to') {
    displayOptions = [
      p1?.display_name || 'Player 1',
      p2?.display_name || 'Player 2',
      'Both of Us',
      'Neither of Us',
    ];
  } else if (currentRound.options && Array.isArray(currentRound.options)) {
    displayOptions = currentRound.options;
  }

  // Answer matching evaluation when revealed
  const partnerAnswer = answers.find((a) => a.user_id !== user?.id);
  const isMatch = isRoundRevealed && (
    (myAnswer?.points_awarded && myAnswer.points_awarded > 0) ||
    (myAnswer?.answer_text?.toLowerCase().trim() === partnerAnswer?.answer_text?.toLowerCase().trim())
  );

  return (
    <div className="max-w-3xl mx-auto px-4 py-6">
      {/* Error alert */}
      {error && (
        <div className="mb-4 p-3.5 rounded-2xl bg-rose-950/70 border border-rose-500/50 flex items-center gap-2.5 text-rose-300 text-xs">
          <AlertCircle className="w-4 h-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {/* Top Arena Header: Scores & Round Counter */}
      <div className="flex items-center justify-between gap-4 p-4 rounded-2xl bg-slate-900/90 border border-slate-800 mb-6 shadow-md">
        {/* Player 1 Score */}
        <div className="flex items-center gap-2 text-left">
          <div className="w-8 h-8 rounded-full bg-pink-500/90 flex items-center justify-center font-bold text-xs text-white shadow-sm">
            {p1?.display_name?.charAt(0) || '1'}
          </div>
          <div>
            <span className="text-xs font-semibold text-slate-200 block truncate max-w-[100px]">
              {p1?.display_name} {isP1 && '(You)'}
            </span>
            <span className="text-xs text-rose-400 font-bold">{p1Score} pts</span>
          </div>
        </div>

        {/* Round Badge & Timer */}
        <div className="text-center">
          <span className="text-[11px] font-mono uppercase tracking-widest text-slate-400 block">
            Round {session.current_round_index} of {session.total_rounds}
          </span>
          <div className="flex items-center justify-center gap-1.5 mt-0.5">
            <Clock className={`w-3.5 h-3.5 ${timeLeft <= 10 ? 'text-rose-500 animate-bounce' : 'text-slate-400'}`} />
            <span className={`text-sm font-mono font-bold ${timeLeft <= 10 ? 'text-rose-400 animate-pulse' : 'text-slate-200'}`}>
              {timeLeft}s
            </span>
          </div>
        </div>

        {/* Player 2 Score */}
        <div className="flex items-center gap-2 text-right justify-end">
          <div>
            <span className="text-xs font-semibold text-slate-200 block truncate max-w-[100px]">
              {p2?.display_name} {!isP1 && '(You)'}
            </span>
            <span className="text-xs text-rose-400 font-bold">{p2Score} pts</span>
          </div>
          <div className="w-8 h-8 rounded-full bg-indigo-500/90 flex items-center justify-center font-bold text-xs text-white shadow-sm">
            {p2?.display_name?.charAt(0) || '2'}
          </div>
        </div>
      </div>

      {/* Main Question Card */}
      <div className="bg-slate-900/95 border border-rose-500/30 rounded-3xl p-6 sm:p-8 shadow-2xl backdrop-blur-xl mb-6 text-center relative overflow-hidden">
        {/* Game Mode Pill */}
        <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-rose-500/10 border border-rose-500/30 text-rose-300 text-xs font-medium mb-4">
          <Sparkles className="w-3.5 h-3.5" />
          <span>{gameInfo?.title || 'Couples Challenge'}</span>
        </div>

        {/* Role Hint for "How Well Do You Know Me?" */}
        {session.game_type === 'how_well_do_you_know_me' && (
          <div className="mb-4 p-2.5 rounded-xl bg-slate-800/80 border border-slate-700/60 max-w-md mx-auto text-xs">
            {isTargetPlayer ? (
              <span className="text-pink-300 font-semibold">
                🌟 This question is about YOU! Pick your honest answer:
              </span>
            ) : (
              <span className="text-indigo-300 font-semibold">
                🎯 Guess what <strong className="text-white">{targetPlayerName}</strong> will pick:
              </span>
            )}
          </div>
        )}

        {/* Question Prompt */}
        <h3 className="text-xl sm:text-2xl font-bold text-slate-100 leading-snug max-w-xl mx-auto mb-6">
          {currentRound.prompt}
        </h3>

        {/* UNREVEALED STATE: Interactive Answer Selection */}
        {!isRoundRevealed ? (
          <div>
            {/* If user ALREADY submitted: Locked-in status banner */}
            {myAnswer ? (
              <div className="p-6 rounded-2xl bg-slate-950/60 border border-slate-800 max-w-md mx-auto">
                <div className="w-12 h-12 rounded-full bg-emerald-500/20 border border-emerald-500/40 flex items-center justify-center text-emerald-400 mx-auto mb-3">
                  <CheckCircle className="w-6 h-6" />
                </div>
                <h4 className="font-bold text-white text-base mb-1">
                  Answer Locked In! 🔒
                </h4>
                <p className="text-xs text-slate-400 mb-4">
                  You selected: <span className="text-rose-300 font-semibold">"{myAnswer.answer_text}"</span>
                </p>
                <div className="pt-3 border-t border-slate-800/80 flex items-center justify-center gap-2 text-xs">
                  {partnerSubmitted ? (
                    <span className="text-emerald-400 font-medium flex items-center gap-1.5">
                      <CheckCircle className="w-4 h-4" />
                      <span>{partner?.display_name || 'Partner'} has submitted! Revealing...</span>
                    </span>
                  ) : (
                    <span className="text-amber-300 font-medium flex items-center gap-1.5 animate-pulse">
                      <Clock className="w-4 h-4" />
                      <span>Waiting for {partner?.display_name || 'partner'} to lock in...</span>
                    </span>
                  )}
                </div>
              </div>
            ) : (
              /* User has NOT yet submitted: Interactive Options Grid */
              <div className="space-y-4 max-w-xl mx-auto">
                {/* Two Large Choices for "Would You Rather" */}
                {session.game_type === 'would_you_rather' && displayOptions.length >= 2 ? (
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    {displayOptions.map((opt, i) => (
                      <button
                        key={i}
                        type="button"
                        onClick={() => {
                          setSelectedOption(opt);
                          handleSubmit(opt);
                        }}
                        disabled={loading}
                        className={`p-5 rounded-2xl border text-left flex flex-col justify-between transition-all cursor-pointer min-h-[140px] ${
                          i === 0
                            ? 'bg-rose-950/30 hover:bg-rose-950/60 border-rose-500/40 hover:border-rose-400 hover:scale-[1.02]'
                            : 'bg-indigo-950/30 hover:bg-indigo-950/60 border-indigo-500/40 hover:border-indigo-400 hover:scale-[1.02]'
                        }`}
                      >
                        <span className="text-xs font-bold uppercase tracking-widest text-slate-400 mb-2">
                          Option {i === 0 ? 'A' : 'B'}
                        </span>
                        <span className="text-base font-semibold text-white leading-snug">
                          {opt}
                        </span>
                        <div className="mt-3 flex items-center gap-1 text-xs text-rose-300">
                          <span>Pick this choice</span>
                          <ArrowRight className="w-3.5 h-3.5" />
                        </div>
                      </button>
                    ))}
                  </div>
                ) : displayOptions.length > 0 ? (
                  /* Standard Options List */
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    {displayOptions.map((opt, idx) => {
                      const isSelected = selectedOption === opt;
                      return (
                        <button
                          key={idx}
                          type="button"
                          onClick={() => setSelectedOption(opt)}
                          className={`p-4 rounded-xl border text-left text-sm font-medium transition-all cursor-pointer flex items-center justify-between ${
                            isSelected
                              ? 'bg-rose-600/30 border-rose-400 text-white ring-2 ring-rose-500/30 shadow-md'
                              : 'bg-slate-800/60 border-slate-700/80 hover:bg-slate-800 hover:border-slate-600 text-slate-200'
                          }`}
                        >
                          <span>{opt}</span>
                          {isSelected && <CheckCircle className="w-4 h-4 text-rose-400 shrink-0" />}
                        </button>
                      );
                    })}
                  </div>
                ) : (
                  /* Custom Free-form Text Input (Deep Questions / custom) */
                  <div className="space-y-3">
                    <textarea
                      value={customText}
                      onChange={(e) => setCustomText(e.target.value)}
                      rows={3}
                      placeholder="Type your heartfelt response here..."
                      className="w-full p-4 rounded-2xl bg-slate-950/80 border border-slate-700 focus:border-rose-400 text-slate-100 placeholder-slate-500 text-sm focus:outline-none focus:ring-2 focus:ring-rose-500/20"
                    />
                  </div>
                )}

                {/* Submit / Lock In Button */}
                {session.game_type !== 'would_you_rather' && (
                  <button
                    type="button"
                    onClick={() => handleSubmit()}
                    disabled={(!selectedOption && !customText.trim()) || loading}
                    className="w-full sm:w-auto px-8 py-3.5 bg-gradient-to-r from-pink-500 to-rose-600 hover:from-pink-600 hover:to-rose-700 text-white font-bold rounded-xl shadow-lg shadow-rose-600/30 transition-all cursor-pointer text-sm disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
                  >
                    <Lock className="w-4 h-4" />
                    <span>Lock In My Answer</span>
                  </button>
                )}
              </div>
            )}
          </div>
        ) : (
          /* REVEALED STATE: Answers Revealed Side-by-Side */
          <div className="space-y-6 max-w-xl mx-auto">
            {/* Match or Verdict Banner */}
            <div className={`p-4 rounded-2xl border text-center ${
              isMatch
                ? 'bg-gradient-to-r from-pink-950/60 via-rose-950/60 to-slate-900 border-rose-500/50 text-rose-200'
                : 'bg-slate-950/70 border-slate-800 text-slate-300'
            }`}>
              <div className="text-2xl mb-1">
                {isMatch ? '🎉 It’s a Match! 💕' : '✨ Different Perspectives!'}
              </div>
              <p className="text-xs">
                {isMatch 
                  ? 'Your answers synchronized! Bonus relationship points awarded.' 
                  : 'Opposites attract! You each shared unique answers.'}
              </p>
            </div>

            {/* Both Answers Comparison Grid */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-left">
              {/* My Answer */}
              <div className="p-4 rounded-2xl bg-slate-950/80 border border-slate-800">
                <span className="text-[11px] font-mono uppercase tracking-wider text-slate-400 block mb-1">
                  Your Answer
                </span>
                <p className="text-base font-bold text-white mb-2">
                  {myAnswer?.answer_text || '(No response)'}
                </p>
                <div className="flex items-center justify-between text-xs pt-2 border-t border-slate-800 text-slate-400">
                  <span>Points</span>
                  <span className="text-emerald-400 font-bold">+{myAnswer?.points_awarded || 0} pts</span>
                </div>
              </div>

              {/* Partner Answer (Guaranteed private until revealed) */}
              <div className="p-4 rounded-2xl bg-slate-950/80 border border-slate-800">
                <span className="text-[11px] font-mono uppercase tracking-wider text-slate-400 block mb-1">
                  {partner?.display_name || 'Partner'}'s Answer
                </span>
                <p className="text-base font-bold text-white mb-2">
                  {partnerAnswer?.answer_text || '(No response)'}
                </p>
                <div className="flex items-center justify-between text-xs pt-2 border-t border-slate-800 text-slate-400">
                  <span>Points</span>
                  <span className="text-emerald-400 font-bold">+{partnerAnswer?.points_awarded || 0} pts</span>
                </div>
              </div>
            </div>

            {/* Advance Round Action */}
            <div className="pt-2">
              <button
                type="button"
                onClick={handleAdvance}
                disabled={loading}
                className="w-full py-3.5 px-6 bg-gradient-to-r from-pink-500 via-rose-500 to-rose-600 hover:from-pink-600 hover:to-rose-700 text-white font-bold rounded-xl shadow-xl shadow-rose-600/30 transition-all flex items-center justify-center gap-2 cursor-pointer text-sm disabled:opacity-50"
              >
                <span>
                  {session.current_round_index >= session.total_rounds
                    ? 'View Final Results 🏆'
                    : 'Advance to Next Round ➔'}
                </span>
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Partner Connection Status Bar */}
      <div className="flex items-center justify-between px-4 py-2.5 rounded-xl bg-slate-900/60 border border-slate-800 text-xs text-slate-400">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-emerald-400" />
          <span>Connected with <strong className="text-slate-200">{partner?.display_name || 'Partner'}</strong></span>
        </div>
        <span className="text-slate-500 font-mono">Room: {room?.code}</span>
      </div>
    </div>
  );
};
