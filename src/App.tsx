import React from 'react';
import { AuthProvider } from './context/AuthContext';
import { GameProvider, useGame } from './context/GameContext';
import { Navbar } from './components/Navbar';
import { Lobby } from './components/Lobby';
import { WaitingRoom } from './components/WaitingRoom';
import { GameArena } from './components/GameArena';
import { GameOver } from './components/GameOver';

const GameContent: React.FC = () => {
  const { room, session, isGameFinished } = useGame();


  // If room is completed or session finished
  if (room && isGameFinished) {
    return <GameOver />;
  }

  // If in an active game session
  if (room && session && session.status === 'active') {
    return <GameArena />;
  }

  // If in room waiting to start
  if (room) {
    return <WaitingRoom />;
  }

  // Otherwise, in lobby
  return <Lobby />;
};

export function App() {
  return (
    <AuthProvider>
      <GameProvider>
        <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col relative selection:bg-rose-500 selection:text-white">
          {/* Subtle Ambient Glows */}
          <div className="fixed top-0 left-1/4 w-96 h-96 bg-rose-600/10 rounded-full blur-3xl pointer-events-none -z-10" />
          <div className="fixed bottom-0 right-1/4 w-96 h-96 bg-purple-600/10 rounded-full blur-3xl pointer-events-none -z-10" />

          {/* Navigation Bar */}
          <Navbar />

          {/* Main Container */}
          <main className="flex-1 flex flex-col justify-center">
            <GameContent />
          </main>

          {/* Footer */}
          <footer className="py-6 border-t border-slate-900 text-center text-xs text-slate-500">
            <p className="flex items-center justify-center gap-1">
              <span>Two of Us &bull; Built with Supabase PostgreSQL, Auth & Realtime</span>
            </p>
          </footer>
        </div>
      </GameProvider>
    </AuthProvider>
  );
}

export default App;
