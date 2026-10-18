import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig, loadEnv } from 'vite'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  // Load all environment variables from system and .env files
  const env = loadEnv(mode, process.cwd(), '')

  // Resolve Supabase URL and Public Anon Key from any integration format (Vite, Next.js, or Vercel Supabase integration)
  const resolvedSupabaseUrl =
    env.VITE_SUPABASE_URL ||
    env.NEXT_PUBLIC_SUPABASE_URL ||
    env.SUPABASE_URL ||
    ''

  const resolvedSupabaseKey =
    env.VITE_SUPABASE_PUBLISHABLE_KEY ||
    env.VITE_SUPABASE_ANON_KEY ||
    env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
    env.SUPABASE_ANON_KEY ||
    ''

  return {
    plugins: [react(), tailwindcss()],
    envPrefix: ['VITE_', 'NEXT_PUBLIC_'],
    define: {
      'import.meta.env.VITE_SUPABASE_URL': JSON.stringify(resolvedSupabaseUrl),
      'import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY': JSON.stringify(resolvedSupabaseKey),
    },
  }
})
