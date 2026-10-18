import { createClient } from '@supabase/supabase-js';

const supabaseUrl =
  import.meta.env.VITE_SUPABASE_URL ||
  import.meta.env.NEXT_PUBLIC_SUPABASE_URL;

const supabasePublishableKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  import.meta.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
  import.meta.env.VITE_SUPABASE_ANON_KEY;

export const isSupabaseConfigured = Boolean(
  supabaseUrl && 
  supabasePublishableKey && 
  !supabaseUrl.includes('your-project-ref') &&
  !supabasePublishableKey.includes('your-supabase-publishable') &&
  !supabasePublishableKey.includes('placeholder')
);

if (!isSupabaseConfigured) {
  console.warn(
    'Supabase environment variables are missing or using placeholders. ' +
    'Please verify your Supabase integration in Vercel or configure .env.local locally.'
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
