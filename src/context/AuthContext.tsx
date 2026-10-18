import React, { createContext, useContext, useEffect, useState } from 'react';
import type { User } from '@supabase/supabase-js';
import { supabase, isSupabaseConfigured } from '../lib/supabase';

interface AuthContextType {
  user: User | null;
  displayName: string;
  loading: boolean;
  error: string | null;
  signInAsGuest: (name: string) => Promise<{ success: boolean; error?: string }>;
  signOut: () => Promise<void>;
  updateDisplayName: (name: string) => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [displayName, setDisplayNameState] = useState<string>(() => {
    return localStorage.getItem('two_of_us_display_name') || '';
  });
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;

    async function initSession() {
      if (!isSupabaseConfigured) {
        setLoading(false);
        return;
      }

      try {
        const { data: { session }, error: sessionError } = await supabase.auth.getSession();
        if (sessionError) {
          console.error('Session retrieval error:', sessionError);
        }

        if (session?.user && mounted) {
          setUser(session.user);
          const metaName = session.user.user_metadata?.display_name;
          if (metaName && !displayName) {
            setDisplayNameState(metaName);
            localStorage.setItem('two_of_us_display_name', metaName);
          }
        }
      } catch (err: unknown) {
        console.error('Auth initialization error:', err);
      } finally {
        if (mounted) setLoading(false);
      }
    }

    initSession();

    // Listen for auth changes
    const { data: authListener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (mounted) {
        setUser(session?.user ?? null);
        if (session?.user?.user_metadata?.display_name) {
          setDisplayNameState(session.user.user_metadata.display_name);
        }
      }
    });

    return () => {
      mounted = false;
      authListener?.subscription.unsubscribe();
    };
  }, []);

  const updateDisplayName = (name: string) => {
    const trimmed = name.trim();
    setDisplayNameState(trimmed);
    localStorage.setItem('two_of_us_display_name', trimmed);
  };

  const signInAsGuest = async (name: string): Promise<{ success: boolean; error?: string }> => {
    const trimmed = name.trim();
    if (!trimmed) {
      return { success: false, error: 'Please enter your nickname or name.' };
    }

    setError(null);
    updateDisplayName(trimmed);

    if (!isSupabaseConfigured) {
      return { 
        success: false, 
        error: 'Supabase credentials are not configured. Please add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY to .env.local.' 
      };
    }

    try {
      // If already signed in, update user metadata
      if (user) {
        await supabase.auth.updateUser({
          data: { display_name: trimmed },
        });
        return { success: true };
      }

      // Anonymous sign in
      const { data, error: signInError } = await supabase.auth.signInAnonymously({
        options: {
          data: {
            display_name: trimmed,
          },
        },
      });

      if (signInError) {
        console.error('Anonymous sign-in error:', signInError);
        // Special helpful error message if anonymous provider is not enabled in Supabase dashboard
        if (signInError.message.toLowerCase().includes('anonymous') || signInError.status === 400) {
          const helperMsg = 'Anonymous sign-in is disabled in your Supabase project. Enable it under: Authentication -> Providers -> Anonymous.';
          setError(helperMsg);
          return { success: false, error: helperMsg };
        }
        setError(signInError.message);
        return { success: false, error: signInError.message };
      }

      setUser(data.user);
      return { success: true };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed to sign in as guest';
      setError(msg);
      return { success: false, error: msg };
    }
  };

  const signOut = async () => {
    if (isSupabaseConfigured) {
      await supabase.auth.signOut();
    }
    setUser(null);
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        displayName,
        loading,
        error,
        signInAsGuest,
        signOut,
        updateDisplayName,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
