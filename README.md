# 💖 Two of Us — Realtime Multiplayer Couples Platform

An intimate, playful realtime multiplayer website designed exclusively for couples to deepen their bond, spark laughter, and test their connection across 6 tailored games.

Powered by **React**, **Vite**, **TypeScript**, **Supabase PostgreSQL**, **Supabase Auth (Anonymous Guest Access)**, and **Supabase Realtime**.

---

## 🎮 The Six Games

1. **How Well Do You Know Me?** — One partner answers about themselves; the other predicts their answer. Reveal and discover how well your minds align!
2. **Would You Rather?** — Couples dilemma choices. Compare choices to see if you share matching wavelengths or delightful opposites!
3. **Who Is More Likely To?** — Playful blame-game for quirky couple habits. Pick Player 1, Player 2, Both, or Neither!
4. **Couple Quiz Battle** — Head-to-head speed trivia on world romance, pop culture, and fun relationship science.
5. **Same-Time Challenge** — Synchronized countdown! Count down to zero and make your pick simultaneously without conferring.
6. **Deep Questions** — Soulful vulnerability prompts designed to open up heartfelt feelings, cherished memories, and dreams for your future.

---

## 🛡️ Security & Privacy Architecture

- **True Answer Privacy via Row Level Security (RLS)**: Player answers are protected in PostgreSQL. While a round is in progress, players cannot query their partner's unrevealed answer. The server only reveals both answers once both participants have submitted (or timeout occurs).
- **Server-Side Scoring & Authorization**: Room creation, participant slot allocation, answer submission, scoring formulas, and round advancement are executed via strict `SECURITY DEFINER` PostgreSQL functions (`SET search_path = public, auth`).
- **No Secret Keys in Frontend**: Uses only `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
- **Guest Access**: Seamless Supabase Anonymous Authentication lets users join immediately with just a nickname.

---

## 🚀 Quick Start

### 1. Install Dependencies
```powershell
npm install
```

### 2. Configure Environment Variables
Copy `.env.example` to `.env.local`:
```env
VITE_SUPABASE_URL=https://your-project-ref.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-supabase-anon-or-publishable-key
```

### 3. Setup Supabase Database & Auth
Follow the step-by-step guide in **[SUPABASE_SETUP.md](./SUPABASE_SETUP.md)** to:
- Enable **Anonymous Sign-Ins** under *Authentication -> Providers*.
- Run `supabase/schema.sql` in the **SQL Editor**.

### 4. Run Development Server
```powershell
npm run dev
```

Visit `http://localhost:5173`. Open an Incognito window to play as Player 2 simultaneously!
