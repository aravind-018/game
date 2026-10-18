import React, { useState } from 'react';
import { Copy, Check, Share2, Users, Heart, AlertCircle, Shield } from 'lucide-react';
import { useGame } from '../context/GameContext';
import { useAuth } from '../context/AuthContext';
import { GameSelector } from './GameSelector';
import type { GameType } from '../types/game';

export const WaitingRoom: React.FC = () => {
  const { room, participants, startGame, loading, error, clearError } = useGame();
  const { user } = useAuth();
  const [copiedCode, setCopiedCode] = useState(false);
  const [copiedLink, setCopiedLink] = useState(false);

  const handleCopyCode = () => {
    if (!room?.code) return;
    navigator.clipboard.writeText(room.code);
    setCopiedCode(true);
    setTimeout(() => setCopiedCode(false), 2000);
  };

  const handleCopyLink = () => {
    if (!room?.code) return;
    const shareUrl = `${window.location.origin}?room=${room.code}`;
    navigator.clipboard.writeText(shareUrl);
    setCopiedLink(true);
    setTimeout(() => setCopiedLink(false), 2000);
  };

  const handleStartGame = async (gameType: GameType, rounds: number) => {
    clearError();
    await startGame(gameType, rounds);
  };

  const p1 = participants.find((p) => p.role_slot === 1);
  const p2 = participants.find((p) => p.role_slot === 2);
  const isBothConnected = participants.length >= 2;

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      {/* Error alert */}
      {error && (
        <div className="mb-6 p-4 rounded-2xl bg-rose-950/60 border border-rose-500/50 flex items-center gap-3 text-rose-300 text-sm">
          <AlertCircle className="w-5 h-5 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {/* Header Info */}
      <div className="text-center mb-8">
        <span className="text-xs font-semibold uppercase tracking-widest text-rose-400 mb-2 block">
          Private Couple Room
        </span>
        <h2 className="text-3xl font-extrabold text-white mb-2">
          {isBothConnected ? 'Both Connected & Ready!' : 'Waiting for Your Partner'}
        </h2>
        <p className="text-sm text-slate-400 max-w-lg mx-auto">
          Share this room code or direct link with your partner so they can join you.
        </p>
      </div>

      {/* Room Code Showcase Box */}
      <div className="max-w-md mx-auto bg-slate-900/90 border border-rose-500/30 rounded-3xl p-6 shadow-xl mb-8 backdrop-blur-md">
        <span className="text-xs text-slate-400 font-medium uppercase tracking-wider block mb-2">
          Your Room Code
        </span>
        <div className="flex items-center justify-center gap-2 mb-4">
          <div className="text-4xl md:text-5xl font-mono font-black tracking-widest text-transparent bg-clip-text bg-gradient-to-r from-pink-400 via-rose-300 to-amber-200">
            {room?.code}
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={handleCopyCode}
            className="flex items-center justify-center gap-2 py-2.5 px-3 rounded-xl bg-slate-800 hover:bg-slate-700 border border-slate-700 text-xs font-semibold text-slate-200 transition-all cursor-pointer"
          >
            {copiedCode ? (
              <>
                <Check className="w-4 h-4 text-emerald-400" />
                <span className="text-emerald-400">Code Copied!</span>
              </>
            ) : (
              <>
                <Copy className="w-4 h-4 text-rose-400" />
                <span>Copy Code</span>
              </>
            )}
          </button>

          <button
            onClick={handleCopyLink}
            className="flex items-center justify-center gap-2 py-2.5 px-3 rounded-xl bg-rose-500/20 hover:bg-rose-500/30 border border-rose-500/40 text-xs font-semibold text-rose-200 transition-all cursor-pointer"
          >
            {copiedLink ? (
              <>
                <Check className="w-4 h-4 text-emerald-400" />
                <span className="text-emerald-400">Link Copied!</span>
              </>
            ) : (
              <>
                <Share2 className="w-4 h-4 text-rose-400" />
                <span>Copy Invite Link</span>
              </>
            )}
          </button>
        </div>
      </div>

      {/* Connected Players Slots */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-xl mx-auto mb-10">
        {/* Player 1 Card */}
        <div className="p-5 rounded-2xl bg-slate-900/80 border border-slate-800 text-left relative overflow-hidden">
          <div className="flex items-center justify-between mb-3">
            <span className="text-xs font-mono text-slate-400">Player 1 (Host)</span>
            {p1 && <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse" />}
          </div>
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-full bg-gradient-to-tr from-pink-500 to-rose-600 flex items-center justify-center font-bold text-white text-lg shadow-md shadow-rose-900/40">
              {p1?.display_name?.charAt(0).toUpperCase() || '1'}
            </div>
            <div>
              <h4 className="font-bold text-slate-100 text-base">
                {p1?.display_name || 'Host'}
                {p1?.user_id === user?.id && <span className="text-xs text-rose-400 ml-1.5">(You)</span>}
              </h4>
              <p className="text-xs text-slate-400 flex items-center gap-1 mt-0.5">
                <Shield className="w-3 h-3 text-rose-400" />
                <span>Room Creator</span>
              </p>
            </div>
          </div>
        </div>

        {/* Player 2 Card */}
        <div className={`p-5 rounded-2xl border text-left relative overflow-hidden transition-all ${
          p2
            ? 'bg-slate-900/80 border-slate-800'
            : 'bg-slate-900/40 border-dashed border-slate-700/80'
        }`}>
          <div className="flex items-center justify-between mb-3">
            <span className="text-xs font-mono text-slate-400">Player 2 (Partner)</span>
            {p2 ? (
              <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse" />
            ) : (
              <span className="text-[11px] text-amber-400 font-mono">Awaiting...</span>
            )}
          </div>
          <div className="flex items-center gap-3">
            <div className={`w-12 h-12 rounded-full flex items-center justify-center font-bold text-lg ${
              p2
                ? 'bg-gradient-to-tr from-purple-500 to-indigo-600 text-white shadow-md'
                : 'bg-slate-800 text-slate-500 border border-slate-700'
            }`}>
              {p2 ? p2.display_name.charAt(0).toUpperCase() : <Heart className="w-5 h-5 animate-pulse text-rose-400/60" />}
            </div>
            <div>
              <h4 className="font-bold text-slate-100 text-base">
                {p2 ? (
                  <>
                    {p2.display_name}
                    {p2.user_id === user?.id && <span className="text-xs text-rose-400 ml-1.5">(You)</span>}
                  </>
                ) : (
                  'Waiting for Partner...'
                )}
              </h4>
              <p className="text-xs text-slate-400 mt-0.5">
                {p2 ? 'Connected & Ready' : 'Share the 6-letter room code'}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Game Selection Section (Active when 2 players present) */}
      {isBothConnected ? (
        <div className="bg-slate-900/80 border border-slate-800 rounded-3xl p-6 sm:p-8 backdrop-blur-md">
          <div className="text-left mb-6 pb-4 border-b border-slate-800">
            <h3 className="text-xl font-bold text-white flex items-center gap-2">
              <Users className="w-5 h-5 text-rose-400" />
              <span>Choose Your Game</span>
            </h3>
            <p className="text-xs text-slate-400 mt-1">
              Select one of the 6 game experiences to begin this session.
            </p>
          </div>
          <GameSelector onStart={handleStartGame} disabled={loading} />
        </div>
      ) : (
        <div className="max-w-md mx-auto p-4 rounded-2xl bg-slate-900/60 border border-slate-800/80 text-xs text-slate-400">
          <p>
            💡 <strong className="text-slate-300">Quick tip:</strong> Open a second browser window (or Incognito mode) and join with code <span className="text-rose-400 font-mono font-bold">{room?.code}</span> to test multiplayer simultaneously on this device!
          </p>
        </div>
      )}
    </div>
  );
};
