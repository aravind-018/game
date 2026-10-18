import React, { useState } from 'react';
import { Heart, PlusCircle, LogIn, Sparkles, AlertCircle, ShieldCheck, Zap } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { useGame } from '../context/GameContext';
import { isSupabaseConfigured } from '../lib/supabase';
import { GAMES_CATALOG } from '../types/game';

export const Lobby: React.FC = () => {
  const { displayName, updateDisplayName } = useAuth();
  const { createRoom, joinRoom, loading, error, clearError } = useGame();

  const [inputName, setInputName] = useState(displayName);
  const [roomCodeInput, setRoomCodeInput] = useState('');
  const [activeTab, setActiveTab] = useState<'create' | 'join'>('create');
  const [localError, setLocalError] = useState<string | null>(null);

  const handleNameChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setInputName(e.target.value);
    updateDisplayName(e.target.value);
    setLocalError(null);
    clearError();
  };

  const handleCreateRoom = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputName.trim()) {
      setLocalError('Please enter your name or nickname to continue.');
      return;
    }
    setLocalError(null);
    await createRoom(inputName.trim());
  };

  const handleJoinRoom = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputName.trim()) {
      setLocalError('Please enter your name or nickname.');
      return;
    }
    if (!roomCodeInput.trim() || roomCodeInput.trim().length < 4) {
      setLocalError('Please enter a valid 6-character room code.');
      return;
    }
    setLocalError(null);
    await joinRoom(roomCodeInput.trim(), inputName.trim());
  };

  return (
    <div className="max-w-5xl mx-auto px-4 py-8">
      {/* Missing Env Banner */}
      {!isSupabaseConfigured && (
        <div className="mb-8 p-4 rounded-2xl bg-amber-950/40 border border-amber-500/40 flex items-start gap-3.5 shadow-lg">
          <AlertCircle className="w-6 h-6 text-amber-400 shrink-0 mt-0.5" />
          <div className="text-left text-sm text-amber-200">
            <h4 className="font-semibold text-amber-300 mb-1">Supabase Setup Required</h4>
            <p className="text-amber-200/90 leading-relaxed mb-2">
              Your Supabase credentials are not configured yet. Copy <code className="bg-amber-900/60 px-1.5 py-0.5 rounded text-amber-300">.env.example</code> to <code className="bg-amber-900/60 px-1.5 py-0.5 rounded text-amber-300">.env.local</code> and enter your Project URL and Publishable/Anon key from your Supabase dashboard.
            </p>
            <p className="text-xs text-amber-300/80">
              Check out <strong className="underline">SUPABASE_SETUP.md</strong> in your project folder for quick step-by-step instructions.
            </p>
          </div>
        </div>
      )}

      {/* Hero Header */}
      <div className="text-center max-w-2xl mx-auto mb-10">
        <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-rose-500/10 border border-rose-500/30 text-rose-300 text-xs font-medium mb-4">
          <Sparkles className="w-3.5 h-3.5" />
          <span>Realtime Private Multiplayer for Couples</span>
        </div>
        <h2 className="text-4xl md:text-5xl font-extrabold tracking-tight bg-gradient-to-r from-pink-300 via-rose-200 to-amber-100 bg-clip-text text-transparent mb-4">
          Two of Us
        </h2>
        <p className="text-slate-300 text-base md:text-lg leading-relaxed">
          Deepen your intimacy, spark playful laughter, and discover new sides of each other across 6 bespoke games made exclusively for two.
        </p>
      </div>

      {/* Main Action Card */}
      <div className="max-w-md mx-auto bg-slate-900/90 border border-rose-500/30 rounded-3xl p-6 sm:p-8 shadow-2xl shadow-rose-950/50 backdrop-blur-xl mb-14">
        {/* Tab Toggle */}
        <div className="grid grid-cols-2 p-1 bg-slate-800/80 rounded-2xl mb-6 border border-slate-700/60">
          <button
            type="button"
            onClick={() => {
              setActiveTab('create');
              clearError();
              setLocalError(null);
            }}
            className={`py-2.5 text-sm font-semibold rounded-xl transition-all cursor-pointer flex items-center justify-center gap-2 ${
              activeTab === 'create'
                ? 'bg-gradient-to-r from-pink-500 to-rose-600 text-white shadow-md'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <PlusCircle className="w-4 h-4" />
            <span>Create Room</span>
          </button>
          <button
            type="button"
            onClick={() => {
              setActiveTab('join');
              clearError();
              setLocalError(null);
            }}
            className={`py-2.5 text-sm font-semibold rounded-xl transition-all cursor-pointer flex items-center justify-center gap-2 ${
              activeTab === 'join'
                ? 'bg-gradient-to-r from-pink-500 to-rose-600 text-white shadow-md'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <LogIn className="w-4 h-4" />
            <span>Join Room</span>
          </button>
        </div>

        {/* Error Alert */}
        {(localError || error) && (
          <div className="mb-5 p-3 rounded-xl bg-rose-950/60 border border-rose-500/50 flex items-center gap-2.5 text-rose-300 text-xs">
            <AlertCircle className="w-4 h-4 shrink-0" />
            <span>{localError || error}</span>
          </div>
        )}

        {/* Display Name Input */}
        <div className="mb-5 text-left">
          <label className="block text-xs font-semibold uppercase tracking-wider text-rose-300/90 mb-2">
            Your Nickname or Name
          </label>
          <div className="relative">
            <input
              type="text"
              value={inputName}
              onChange={handleNameChange}
              placeholder="e.g. Juliet, Romeo, Honey..."
              maxLength={25}
              className="w-full px-4 py-3 bg-slate-950/70 border border-slate-700 focus:border-rose-400 rounded-xl text-slate-100 placeholder-slate-500 text-sm focus:outline-none focus:ring-2 focus:ring-rose-500/20 transition-all"
            />
          </div>
          <p className="text-[11px] text-slate-400 mt-1.5 flex items-center gap-1">
            <ShieldCheck className="w-3 h-3 text-rose-400" />
            <span>Instant guest login. No email registration required.</span>
          </p>
        </div>

        {/* Create Form */}
        {activeTab === 'create' && (
          <form onSubmit={handleCreateRoom} className="space-y-4">
            <button
              type="submit"
              disabled={loading}
              className="w-full py-3.5 px-4 bg-gradient-to-r from-pink-500 via-rose-500 to-rose-600 hover:from-pink-600 hover:to-rose-700 text-white font-semibold rounded-xl shadow-lg shadow-rose-600/30 hover:shadow-rose-600/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 cursor-pointer text-sm"
            >
              {loading ? (
                <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              ) : (
                <>
                  <Heart className="w-4 h-4 fill-white" />
                  <span>Create Private Couple Room</span>
                </>
              )}
            </button>
            <p className="text-xs text-slate-400 text-center">
              You will receive a 6-letter room code to share with your partner.
            </p>
          </form>
        )}

        {/* Join Form */}
        {activeTab === 'join' && (
          <form onSubmit={handleJoinRoom} className="space-y-4">
            <div className="text-left">
              <label className="block text-xs font-semibold uppercase tracking-wider text-rose-300/90 mb-2">
                Room Code (6 Letters)
              </label>
              <input
                type="text"
                value={roomCodeInput}
                onChange={(e) => setRoomCodeInput(e.target.value.toUpperCase())}
                placeholder="e.g. LOVE88"
                maxLength={6}
                className="w-full px-4 py-3 bg-slate-950/70 border border-slate-700 focus:border-rose-400 rounded-xl text-slate-100 placeholder-slate-500 text-center font-mono text-lg tracking-widest uppercase focus:outline-none focus:ring-2 focus:ring-rose-500/20 transition-all"
              />
            </div>
            <button
              type="submit"
              disabled={loading}
              className="w-full py-3.5 px-4 bg-gradient-to-r from-rose-600 to-pink-600 hover:from-rose-700 hover:to-pink-700 text-white font-semibold rounded-xl shadow-lg shadow-pink-600/30 hover:shadow-pink-600/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 cursor-pointer text-sm"
            >
              {loading ? (
                <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              ) : (
                <>
                  <LogIn className="w-4 h-4" />
                  <span>Join Partner's Room</span>
                </>
              )}
            </button>
          </form>
        )}
      </div>

      {/* Six Games Showcase */}
      <div>
        <div className="flex items-center justify-between mb-6">
          <div className="text-left">
            <h3 className="text-2xl font-bold text-white flex items-center gap-2">
              <Zap className="w-5 h-5 text-rose-400" />
              <span>Six Tailored Experiences</span>
            </h3>
            <p className="text-sm text-slate-400">Pick any game once you and your partner enter the room.</p>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 text-left">
          {GAMES_CATALOG.map((game, idx) => (
            <div
              key={game.id}
              className="group relative p-6 rounded-2xl bg-slate-900/60 border border-slate-800 hover:border-rose-500/40 hover:bg-slate-900/90 transition-all duration-300 flex flex-col justify-between shadow-lg hover:shadow-rose-950/30"
            >
              <div>
                <div className="flex items-center justify-between mb-3">
                  <span className="text-xs font-mono text-rose-400/80">0{idx + 1}</span>
                  <span className="text-[11px] font-medium px-2.5 py-0.5 rounded-full bg-rose-500/10 border border-rose-500/30 text-rose-300">
                    {game.badge}
                  </span>
                </div>
                <h4 className="text-lg font-bold text-slate-100 mb-1 group-hover:text-rose-300 transition-colors">
                  {game.title}
                </h4>
                <p className="text-xs text-rose-400/90 font-medium mb-2.5">
                  {game.tagline}
                </p>
                <p className="text-xs text-slate-400 leading-relaxed">
                  {game.description}
                </p>
              </div>
              <div className="mt-4 pt-3 border-t border-slate-800/80 flex items-center justify-between text-xs text-slate-500 group-hover:text-rose-400/80 transition-colors">
                <span>Multiplayer Realtime</span>
                <span>2 Players</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
