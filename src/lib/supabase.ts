import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

export const isSupabaseConfigured = Boolean(
  supabaseUrl && 
  supabasePublishableKey && 
  !supabaseUrl.includes('your-project-ref') &&
  !supabasePublishableKey.includes('your-supabase-publishable')
);

if (!isSupabaseConfigured) {
  console.warn(
    'Supabase environment variables (VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY) are missing or using placeholders. ' +
    'Please copy .env.example to .env.local and add your real Supabase project credentials.'
  );
}

// Create Supabase client using client-safe publishable/anon key
export const supabase = createClient(
  supabaseUrl || 'https://placeholder-project.supabase.co',
  supabasePublishableKey || 'placeholder-publishable-key',
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storageKey: 'two-of-us-auth-token',
    },
    realtime: {
      params: {
        eventsPerSecond: 10,
      },
    },
  }
);
