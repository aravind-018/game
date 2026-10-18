import React, { useState } from 'react';
import { Heart, Copy, Check, LogOut, Radio } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { useGame } from '../context/GameContext';

export const Navbar: React.FC = () => {
  const { displayName } = useAuth();
  const { room, leaveRoom, participants } = useGame();
  const [copied, setCopied] = useState(false);

  const handleCopyCode = () => {
    if (!room?.code) return;
    navigator.clipboard.writeText(room.code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <header className="border-b border-rose-500/20 bg-slate-900/80 backdrop-blur-md sticky top-0 z-50">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
        {/* Brand */}
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-full bg-gradient-to-tr from-pink-500 to-rose-600 flex items-center justify-center shadow-lg shadow-rose-500/30">
            <Heart className="w-5 h-5 text-white fill-white animate-pulse" />
          </div>
          <div>
            <h1 className="text-xl font-bold bg-gradient-to-r from-pink-400 via-rose-300 to-amber-200 bg-clip-text text-transparent my-0">
              Two of Us
            </h1>
            <p className="text-xs text-rose-300/70">Couples Multiplayer Sanctuary</p>
          </div>
        </div>

        {/* Room Info / Actions */}
        <div className="flex items-center gap-3">
          {room && (
            <>
              {/* Room Code Badge */}
              <button
                onClick={handleCopyCode}
                title="Click to copy Room Code"
                className="flex items-center gap-2 bg-slate-800/90 hover:bg-slate-700 border border-rose-500/30 px-3 py-1.5 rounded-full text-xs font-medium text-slate-200 transition-all cursor-pointer shadow-sm hover:border-rose-400"
              >
                <span className="text-rose-400 font-mono font-semibold">ROOM: {room.code}</span>
                {copied ? (
                  <Check className="w-3.5 h-3.5 text-emerald-400" />
                ) : (
                  <Copy className="w-3.5 h-3.5 text-slate-400" />
                )}
              </button>

              {/* Connected Players Count */}
              <div className="hidden sm:flex items-center gap-1.5 bg-slate-800/70 border border-slate-700 px-2.5 py-1.5 rounded-full text-xs text-slate-300">
                <Radio className="w-3.5 h-3.5 text-emerald-400 animate-pulse" />
                <span>{participants.length}/2 Connected</span>
              </div>

              {/* Exit Room */}
              <button
                onClick={leaveRoom}
                title="Leave Room"
                className="flex items-center gap-1 text-xs text-slate-400 hover:text-rose-400 bg-slate-800/40 hover:bg-slate-800 p-2 rounded-lg transition-colors border border-slate-700/50"
              >
                <LogOut className="w-4 h-4" />
                <span className="hidden md:inline">Exit</span>
              </button>
            </>
          )}

          {/* User Display Badge */}
          {displayName && !room && (
            <div className="flex items-center gap-2 bg-slate-800/80 border border-slate-700 px-3 py-1.5 rounded-full text-xs text-slate-200">
              <span className="w-2 h-2 rounded-full bg-emerald-400" />
              <span className="font-medium text-rose-300">{displayName}</span>
            </div>
          )}
        </div>
      </div>
    </header>
  );
};
