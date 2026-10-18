import React, { useState } from 'react';
import { Sparkles, Play, CheckCircle2, Flame, HeartHandshake, Users, Trophy, Zap } from 'lucide-react';
import { GAMES_CATALOG, type GameType } from '../types/game';
import { useGame } from '../context/GameContext';

interface GameSelectorProps {
  onStart: (gameType: GameType, rounds: number) => void;
  disabled?: boolean;
}

const getGameIcon = (iconName: string) => {
  switch (iconName) {
    case 'HeartHandshake':
      return <HeartHandshake className="w-5 h-5" />;
    case 'Sparkles':
      return <Sparkles className="w-5 h-5" />;
    case 'Users':
      return <Users className="w-5 h-5" />;
    case 'Trophy':
      return <Trophy className="w-5 h-5" />;
    case 'Zap':
      return <Zap className="w-5 h-5" />;
    case 'Flame':
      return <Flame className="w-5 h-5" />;
    default:
      return <Sparkles className="w-5 h-5" />;
  }
};

export const GameSelector: React.FC<GameSelectorProps> = ({ onStart, disabled = false }) => {
  const { isHost, participants } = useGame();
  const [selectedGame, setSelectedGame] = useState<GameType>('how_well_do_you_know_me');
  const [rounds, setRounds] = useState<number>(5);

  const canLaunch = isHost || participants.length >= 2;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (disabled || !canLaunch) return;
    onStart(selectedGame, rounds);
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6 text-left">
      <div>
        <div className="flex items-center justify-between mb-3">
          <label className="text-sm font-semibold text-rose-200">
            Select Game Experience
          </label>
          <span className="text-xs text-slate-400">
            {canLaunch ? 'Pick any game mode to begin' : 'Waiting for host to start'}
          </span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5">
          {GAMES_CATALOG.map((game) => {
            const isSelected = selectedGame === game.id;
            return (
              <div
                key={game.id}
                onClick={() => !disabled && setSelectedGame(game.id)}
                className={`p-4 rounded-2xl border transition-all cursor-pointer flex flex-col justify-between relative ${
                  isSelected
                    ? 'bg-rose-950/40 border-rose-500 ring-2 ring-rose-500/30 shadow-lg shadow-rose-950/40'
                    : 'bg-slate-900/60 border-slate-800 hover:border-slate-700 hover:bg-slate-900/90'
                } ${disabled ? 'opacity-70 cursor-not-allowed' : ''}`}
              >
                {isSelected && (
                  <div className="absolute top-3 right-3 text-rose-400">
                    <CheckCircle2 className="w-5 h-5 fill-rose-500/20" />
                  </div>
                )}
                <div>
                  <div className="flex items-center gap-2.5 mb-2 text-rose-400">
                    <div className="p-2 rounded-xl bg-slate-800/80 border border-slate-700/60">
                      {getGameIcon(game.icon)}
                    </div>
                    <span className="text-[11px] font-medium px-2 py-0.5 rounded-full bg-rose-500/10 text-rose-300">
                      {game.badge}
                    </span>
                  </div>
                  <h4 className="text-sm font-bold text-slate-100 mb-1">
                    {game.title}
                  </h4>
                  <p className="text-xs text-slate-400 line-clamp-2">
                    {game.tagline}
                  </p>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Rounds Configuration */}
      <div className="flex flex-col sm:flex-row items-center justify-between gap-4 p-4 rounded-2xl bg-slate-900/80 border border-slate-800">
        <div>
          <span className="text-xs font-semibold uppercase tracking-wider text-rose-300">
            Game Length
          </span>
          <p className="text-xs text-slate-400 mt-0.5">
            Total number of rounds in this session
          </p>
        </div>

        <div className="flex items-center gap-2">
          {[3, 5, 8, 10].map((num) => (
            <button
              key={num}
              type="button"
              disabled={disabled}
              onClick={() => setRounds(num)}
              className={`px-4 py-1.5 rounded-xl text-xs font-semibold transition-all cursor-pointer ${
                rounds === num
                  ? 'bg-gradient-to-r from-pink-500 to-rose-600 text-white shadow-md'
                  : 'bg-slate-800 text-slate-400 hover:text-white hover:bg-slate-700'
              }`}
            >
              {num} Rounds
            </button>
          ))}
        </div>
      </div>

      {/* Start Button */}
      {canLaunch ? (
        <button
          type="submit"
          disabled={disabled}
          className="w-full py-4 px-6 bg-gradient-to-r from-pink-500 via-rose-500 to-rose-600 hover:from-pink-600 hover:to-rose-700 text-white font-bold rounded-2xl shadow-xl shadow-rose-600/30 hover:shadow-rose-600/50 transition-all flex items-center justify-center gap-2 cursor-pointer text-base disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <Play className="w-5 h-5 fill-white" />
          <span>Launch Game</span>
        </button>
      ) : (
        <div className="p-4 rounded-2xl bg-slate-900/90 border border-slate-800 text-center text-sm text-slate-300">
          <p className="animate-pulse text-rose-300">
            Waiting for host to pick a game and begin...
          </p>
        </div>
      )}
    </form>
  );
};
