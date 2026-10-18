# 💖 Supabase Setup Guide for "Two of Us"

Welcome! This beginner-friendly guide walks you through connecting your Supabase project **`two-of-us`** to this couples multiplayer game platform step-by-step.

---

## 📋 Overview of What We Will Do
1. **Find your Supabase Project URL and Publishable (anon) Key**
2. **Configure your `.env.local` file**
3. **Enable Anonymous Sign-Ins in the Supabase Dashboard**
4. **Apply the Database Schema (`supabase/schema.sql`) in the SQL Editor**
5. **Verify Supabase Realtime**
6. **Start the local server and test with two browser sessions**

---

## Step 1: Find Your Supabase Project Credentials

> [!IMPORTANT]
> **Never** share or commit your database password or `service_role` secret key. Frontend apps only ever use the **Project URL** and the **`anon` (public) key**.

1. Log into your account at [supabase.com/dashboard](https://supabase.com/dashboard).
2. Click on your project: **`two-of-us`**.
3. In the left navigation sidebar, click on the **Settings** (gear icon) at the bottom.
4. Click on **API** (or **Data API** in newer dashboards).
5. Locate the **Project URL**:
   - It will look like: `https://abcdefghijklm.supabase.co`
6. Locate the **Project API Keys**:
   - Look for the key labeled **`anon` `public`** (or `publishable`).
   - Copy this key. (Do **not** use the `service_role` key).

---

## Step 2: Configure Environment Variables

1. In your project root folder (`c:\couples`), create a new file named:
   ```text
   .env.local
   ```
2. Paste the following lines into `.env.local`:
   ```env
   VITE_SUPABASE_URL=https://your-project-ref.supabase.co
   VITE_SUPABASE_PUBLISHABLE_KEY=your-actual-anon-public-key
   ```
   *(Replace the values with your actual Project URL and Anon key from Step 1)*.

3. **Verify Git Exclusion**:
   - `.env.local` is already included in `.gitignore`. Your keys will never be accidentally committed to GitHub.
   - A placeholder reference is kept in `.env.example`.

---

## Step 3: Enable Anonymous Authentication (Guest Access)

The game allows couples to enter their nickname and jump right into a room without typing an email or password. Supabase supports this via **Anonymous Sign-Ins**.

1. In the Supabase Dashboard, click on **Authentication** (the user icon) in the left sidebar.
2. In the Authentication submenu, click on **Providers**.
3. Scroll down or search for **Anonymous**.
4. Toggle **Enable Anonymous Sign-Ins** to **ON** (enabled).
5. Click **Save**.

---

## Step 4: Apply Database Schema (`supabase/schema.sql`)

We have generated an initial setup file: `supabase/schema.sql`. It configures all 8 tables, Row-Level Security (RLS) policies, database RPC functions, Realtime publications, and 60+ initial questions across all 6 games.

1. Open `supabase/schema.sql` in your IDE or text editor.
2. Select all and copy the entire file contents (`Ctrl+A`, then `Ctrl+C`).
3. In your Supabase Dashboard, click on **SQL Editor** in the left sidebar.
4. Click **New Query** (green button).
5. Paste the copied SQL into the editor query pane.
6. Click the green **Run** button (or press `Ctrl+Enter`).
7. You should see a success message: `Success. No rows returned`.

### ⚠️ Note on `schema.sql` vs `supabase/migrations/`:
- **`supabase/schema.sql`**: The consolidated, all-in-one setup file designed to be run **once** in the Supabase Dashboard SQL Editor for quick initial provisioning.
- **`supabase/migrations/`**: Kept for version control and for teams who use the Supabase CLI (`supabase db push`).
- **Do not run both!** If you executed `supabase/schema.sql` in the SQL Editor, you have already initialized the database.

---

## Step 5: Verify Supabase Realtime

Realtime allows both partners to see answers lock in, reveals, and scores update simultaneously without refreshing.

1. In the Supabase Dashboard, click on **Database** in the left sidebar.
2. Click on **Publications**.
3. Select `supabase_realtime`.
4. Ensure the following tables are listed as enabled:
   - `rooms`
   - `room_participants`
   - `game_sessions`
   - `game_rounds`
   - `player_answers`
   - `scores`
5. *(The script in Step 4 automatically added these with `REPLICA IDENTITY FULL`).*

---

## Step 6: Run Locally and Test Multiplayer

1. Open PowerShell or Terminal in `c:\couples`.
2. Start the development server:
   ```powershell
   npm run dev
   ```
3. Open your browser and navigate to:
   ```text
   http://localhost:5173
   ```

### 🧪 Two-Player Testing Procedure:
1. **Window 1 (Host)**:
   - Open normal browser window (`http://localhost:5173`).
   - Enter your nickname (e.g., `Romeo`).
   - Click **Create Private Couple Room**.
   - You will see your 6-letter room code (e.g., `LOVE88`).
2. **Window 2 (Partner)**:
   - Open an **Incognito / Private Window** (or a different browser like Edge/Chrome) at `http://localhost:5173`.
   - Enter partner nickname (e.g., `Juliet`).
   - Select **Join Room**, enter the 6-letter room code, and click **Join Partner's Room**.
3. **Synchronized Lobby**:
   - Both windows immediately update to show `2/2 Connected`!
   - Window 1 (Host) selects a game (e.g., *Would You Rather?* or *How Well Do You Know Me?*) and clicks **Launch Game**.
4. **Answer Privacy & Reveal Test**:
   - In Window 1, select an option and click **Lock In My Answer**.
   - Notice Window 1 displays "Answer Locked In 🔒 Waiting for partner...".
   - Notice Window 2 displays "Partner has locked in their choice ✓" — but Window 2 **cannot** see what was chosen! (Guaranteed by Postgres RLS).
   - In Window 2, select an answer.
   - The moment both submit, the round is revealed on both screens simultaneously!
   - Scores are calculated and displayed on the server.
5. **Advancement & Final Summary**:
   - Click **Advance to Next Round** to progress through the rounds.
   - At the end of round 5, enjoy the confetti celebration and compatibility match rating!

---

## 🛠️ Troubleshooting Common Errors

### 1. `Anonymous sign-ins are disabled for this project`
- **Cause**: Supabase project has not enabled the Anonymous provider.
- **Fix**: Go to **Authentication -> Providers -> Anonymous**, switch toggle to **ON**, and save.

### 2. `Supabase environment variables are missing`
- **Cause**: `.env.local` is missing or variables are named incorrectly.
- **Fix**: Ensure your file is named precisely `.env.local` in `c:\couples` with:
  ```env
  VITE_SUPABASE_URL=https://<your-ref>.supabase.co
  VITE_SUPABASE_PUBLISHABLE_KEY=<your-anon-key>
  ```
  Restart `npm run dev` after editing `.env.local`.

### 3. `function create_room(...) does not exist` or `relation rooms does not exist`
- **Cause**: `supabase/schema.sql` was not run in the SQL Editor.
- **Fix**: Open Supabase Dashboard -> **SQL Editor** -> paste `supabase/schema.sql` -> click **Run**.

### 4. `Room code not found`
- **Cause**: Typo in code or room has expired/completed.
- **Fix**: Double check that the 6-character code matches the host's screen.
