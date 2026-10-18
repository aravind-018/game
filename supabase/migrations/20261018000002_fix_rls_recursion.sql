-- ====================================================================
-- MIGRATION: 20261018000002_fix_rls_recursion.sql
-- Fix: Prevent infinite recursion in room_participants RLS policies (Error 42P17)
-- ====================================================================

-- 1. Helper functions that run with SECURITY DEFINER to bypass RLS recursion
CREATE OR REPLACE FUNCTION is_room_participant(p_room_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM room_participants
    WHERE room_id = p_room_id AND user_id = p_user_id
  );
$$;

CREATE OR REPLACE FUNCTION is_room_host(p_room_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM rooms
    WHERE id = p_room_id AND host_id = p_user_id
  );
$$;

-- 2. Drop the recursive policies
DROP POLICY IF EXISTS "Participants can view their room" ON rooms;
DROP POLICY IF EXISTS "Participants can view room members" ON room_participants;
DROP POLICY IF EXISTS "Users or Host can remove participant" ON room_participants;
DROP POLICY IF EXISTS "Room participants can view custom questions" ON custom_questions;
DROP POLICY IF EXISTS "Room participants can insert custom questions" ON custom_questions;
DROP POLICY IF EXISTS "Room participants can view game sessions" ON game_sessions;
DROP POLICY IF EXISTS "Room participants can view game rounds" ON game_rounds;
DROP POLICY IF EXISTS "Answer privacy policy" ON player_answers;
DROP POLICY IF EXISTS "Users can insert their own answer" ON player_answers;
DROP POLICY IF EXISTS "Room participants can view scores" ON scores;

-- 3. Re-create non-recursive policies

-- ROOMS: Safe check via Host ID or helper function
CREATE POLICY "Participants can view their room"
ON rooms FOR SELECT
TO authenticated
USING (
    host_id = auth.uid()
    OR is_room_participant(id, auth.uid())
);

-- ROOM PARTICIPANTS: Non-recursive check
CREATE POLICY "Participants can view room members"
ON room_participants FOR SELECT
TO authenticated
USING (
    user_id = auth.uid()
    OR is_room_participant(room_id, auth.uid())
    OR is_room_host(room_id, auth.uid())
);

CREATE POLICY "Users or Host can remove participant"
ON room_participants FOR DELETE
TO authenticated
USING (
    user_id = auth.uid()
    OR is_room_host(room_id, auth.uid())
);

-- CUSTOM QUESTIONS
CREATE POLICY "Room participants can view custom questions"
ON custom_questions FOR SELECT
TO authenticated
USING (
    created_by = auth.uid()
    OR is_room_participant(room_id, auth.uid())
);

CREATE POLICY "Room participants can insert custom questions"
ON custom_questions FOR INSERT
TO authenticated
WITH CHECK (
    created_by = auth.uid()
    AND is_room_participant(room_id, auth.uid())
);

-- GAME SESSIONS
CREATE POLICY "Room participants can view game sessions"
ON game_sessions FOR SELECT
TO authenticated
USING (
    is_room_participant(room_id, auth.uid())
    OR is_room_host(room_id, auth.uid())
);

-- GAME ROUNDS
CREATE POLICY "Room participants can view game rounds"
ON game_rounds FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM game_sessions gs
        WHERE gs.id = game_rounds.session_id
          AND (is_room_participant(gs.room_id, auth.uid()) OR is_room_host(gs.room_id, auth.uid()))
    )
);

-- PLAYER ANSWERS: Privacy protected without recursion
CREATE POLICY "Answer privacy policy"
ON player_answers FOR SELECT
TO authenticated
USING (
    user_id = auth.uid()
    OR (
        EXISTS (
            SELECT 1 FROM game_rounds gr
            JOIN game_sessions gs ON gs.id = gr.session_id
            WHERE gr.id = player_answers.round_id
              AND gr.status = 'revealed'
              AND (is_room_participant(gs.room_id, auth.uid()) OR is_room_host(gs.room_id, auth.uid()))
        )
    )
);

CREATE POLICY "Users can insert their own answer"
ON player_answers FOR INSERT
TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM game_rounds gr
        JOIN game_sessions gs ON gs.id = gr.session_id
        WHERE gr.id = player_answers.round_id
          AND gr.status = 'in_progress'
          AND is_room_participant(gs.room_id, auth.uid())
    )
);

-- SCORES
CREATE POLICY "Room participants can view scores"
ON scores FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM game_sessions gs
        WHERE gs.id = scores.session_id
          AND (is_room_participant(gs.room_id, auth.uid()) OR is_room_host(gs.room_id, auth.uid()))
    )
);
