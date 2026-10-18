-- ====================================================================
-- TWO OF US - COUPLES MULTIPLAYER GAME PLATFORM
-- Complete Supabase PostgreSQL Schema, RLS Policies, Functions, & Seed Data
-- ====================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. DROP TABLES (Ordered for clean initialization)
DROP TABLE IF EXISTS player_answers CASCADE;
DROP TABLE IF EXISTS scores CASCADE;
DROP TABLE IF EXISTS game_rounds CASCADE;
DROP TABLE IF EXISTS game_sessions CASCADE;
DROP TABLE IF EXISTS custom_questions CASCADE;
DROP TABLE IF EXISTS question_banks CASCADE;
DROP TABLE IF EXISTS room_participants CASCADE;
DROP TABLE IF EXISTS rooms CASCADE;

-- 3. TABLES DEFINITION

-- Rooms Table
CREATE TABLE rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(6) UNIQUE NOT NULL,
    host_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    selected_game TEXT,
    status TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'in_progress', 'completed', 'abandoned')),
    max_participants INT NOT NULL DEFAULT 2,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

-- Room Participants Table
CREATE TABLE room_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    is_host BOOLEAN NOT NULL DEFAULT false,
    role_slot INT NOT NULL CHECK (role_slot IN (1, 2)),
    connected_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    CONSTRAINT uq_room_user UNIQUE (room_id, user_id),
    CONSTRAINT uq_room_slot UNIQUE (room_id, role_slot)
);

-- Question Banks Table (Curated built-in questions)
CREATE TABLE question_banks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_type TEXT NOT NULL CHECK (game_type IN (
        'how_well_do_you_know_me',
        'would_you_rather',
        'who_is_more_likely_to',
        'couple_quiz_battle',
        'same_time_challenge',
        'deep_questions'
    )),
    category TEXT NOT NULL DEFAULT 'fun',
    prompt TEXT NOT NULL,
    options JSONB, -- Array of string options e.g. ["A", "B", "C", "D"]
    correct_option_index INT, -- 0-indexed for Quiz Battle
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

-- Custom Questions Table (User-contributed questions)
CREATE TABLE custom_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    game_type TEXT NOT NULL,
    prompt TEXT NOT NULL,
    options JSONB,
    correct_option_index INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

-- Game Sessions Table
CREATE TABLE game_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    game_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('starting', 'active', 'round_review', 'finished')),
    current_round_index INT NOT NULL DEFAULT 1,
    total_rounds INT NOT NULL DEFAULT 5,
    settings JSONB NOT NULL DEFAULT '{"round_timeout_seconds": 35}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    finished_at TIMESTAMPTZ
);

-- Game Rounds Table
CREATE TABLE game_rounds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    round_number INT NOT NULL,
    question_id UUID REFERENCES question_banks(id) ON DELETE SET NULL,
    custom_question_id UUID REFERENCES custom_questions(id) ON DELETE SET NULL,
    prompt TEXT NOT NULL,
    options JSONB,
    correct_option_index INT,
    target_player_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    target_player_name TEXT,
    status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'revealed', 'completed')),
    p1_submitted BOOLEAN NOT NULL DEFAULT false,
    p2_submitted BOOLEAN NOT NULL DEFAULT false,
    started_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    expires_at TIMESTAMPTZ,
    revealed_at TIMESTAMPTZ,
    CONSTRAINT uq_session_round UNIQUE (session_id, round_number)
);

-- Player Answers Table (Strict privacy protected)
CREATE TABLE player_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    round_id UUID NOT NULL REFERENCES game_rounds(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    answer_text TEXT NOT NULL,
    partner_prediction TEXT,
    is_correct BOOLEAN,
    points_awarded INT NOT NULL DEFAULT 0,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    CONSTRAINT uq_round_user UNIQUE (round_id, user_id)
);

-- Scores Table
CREATE TABLE scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    score INT NOT NULL DEFAULT 0,
    matches_count INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    CONSTRAINT uq_session_user UNIQUE (session_id, user_id)
);

-- 4. PERFORMANCE INDEXES
CREATE INDEX idx_rooms_code ON rooms(code);
CREATE INDEX idx_room_participants_room_id ON room_participants(room_id);
CREATE INDEX idx_room_participants_user_id ON room_participants(user_id);
CREATE INDEX idx_game_sessions_room_id ON game_sessions(room_id);
CREATE INDEX idx_game_rounds_session_id ON game_rounds(session_id);
CREATE INDEX idx_player_answers_round_id ON player_answers(round_id);
CREATE INDEX idx_player_answers_user_id ON player_answers(user_id);
CREATE INDEX idx_scores_session_id ON scores(session_id);
CREATE INDEX idx_question_banks_game_type ON question_banks(game_type);

-- 5. ROW LEVEL SECURITY (RLS) ACTIVATION
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE question_banks ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE scores ENABLE ROW LEVEL SECURITY;

-- 6. RLS HELPER FUNCTIONS & POLICIES

-- Helper functions with SECURITY DEFINER bypass RLS to prevent recursion (Error 42P17)
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

-- ROOMS POLICIES
CREATE POLICY "Participants can view their room"
ON rooms FOR SELECT
TO authenticated
USING (
    host_id = auth.uid()
    OR is_room_participant(id, auth.uid())
);

CREATE POLICY "Host can insert room"
ON rooms FOR INSERT
TO authenticated
WITH CHECK (host_id = auth.uid());

CREATE POLICY "Host can update room"
ON rooms FOR UPDATE
TO authenticated
USING (host_id = auth.uid());

-- ROOM PARTICIPANTS POLICIES
CREATE POLICY "Participants can view room members"
ON room_participants FOR SELECT
TO authenticated
USING (
    user_id = auth.uid()
    OR is_room_participant(room_id, auth.uid())
    OR is_room_host(room_id, auth.uid())
);

CREATE POLICY "Users can join as participant"
ON room_participants FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own participant record"
ON room_participants FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users or Host can remove participant"
ON room_participants FOR DELETE
TO authenticated
USING (
    user_id = auth.uid()
    OR is_room_host(room_id, auth.uid())
);

-- QUESTION BANKS POLICIES (All authenticated users can read; modifications restricted)
CREATE POLICY "Anyone authenticated can view questions"
ON question_banks FOR SELECT
TO authenticated
USING (true);

-- CUSTOM QUESTIONS POLICIES
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

-- GAME SESSIONS POLICIES
CREATE POLICY "Room participants can view game sessions"
ON game_sessions FOR SELECT
TO authenticated
USING (
    is_room_participant(room_id, auth.uid())
    OR is_room_host(room_id, auth.uid())
);

-- GAME ROUNDS POLICIES
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

-- PLAYER ANSWERS POLICIES (CRUCIAL PRIVACY RULE)
-- Rule: You can ONLY see an answer if it is YOUR OWN, or if the round is REVEALED.
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

-- SCORES POLICIES
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


-- 7. REALTIME REPLICATION CONFIGURATION
-- Ensure publication exists and replica identity is FULL for reliable change payloads
ALTER TABLE rooms REPLICA IDENTITY FULL;
ALTER TABLE room_participants REPLICA IDENTITY FULL;
ALTER TABLE game_sessions REPLICA IDENTITY FULL;
ALTER TABLE game_rounds REPLICA IDENTITY FULL;
ALTER TABLE player_answers REPLICA IDENTITY FULL;
ALTER TABLE scores REPLICA IDENTITY FULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

ALTER PUBLICATION supabase_realtime ADD TABLE rooms;
ALTER PUBLICATION supabase_realtime ADD TABLE room_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE game_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE game_rounds;
ALTER PUBLICATION supabase_realtime ADD TABLE player_answers;
ALTER PUBLICATION supabase_realtime ADD TABLE scores;

-- 8. SECURE SERVER FUNCTIONS (SECURITY DEFINER with strict search_path)

-- Helper: Generate random 6-character room code (without ambiguous chars)
CREATE OR REPLACE FUNCTION generate_room_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result TEXT := '';
    i INT;
BEGIN
    FOR i IN 1..6 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    END LOOP;
    RETURN result;
END;
$$;

-- Function: create_room
CREATE OR REPLACE FUNCTION create_room(
    p_display_name TEXT,
    p_selected_game TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_room_id UUID;
    v_room_code TEXT;
    v_retries INT := 0;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated. Please sign in as a guest.';
    END IF;

    IF trim(p_display_name) = '' THEN
        RAISE EXCEPTION 'Display name cannot be empty.';
    END IF;

    -- Generate a unique code
    LOOP
        v_room_code := generate_room_code();
        EXIT WHEN NOT EXISTS (SELECT 1 FROM rooms WHERE code = v_room_code) OR v_retries > 10;
        v_retries := v_retries + 1;
    END LOOP;

    -- Create room
    INSERT INTO rooms (code, host_id, selected_game, status)
    VALUES (v_room_code, v_user_id, p_selected_game, 'waiting')
    RETURNING id INTO v_room_id;

    -- Add host as Participant (Slot 1)
    INSERT INTO room_participants (room_id, user_id, display_name, is_host, role_slot)
    VALUES (v_room_id, v_user_id, trim(p_display_name), true, 1);

    RETURN jsonb_build_object(
        'success', true,
        'room_id', v_room_id,
        'room_code', v_room_code,
        'user_id', v_user_id,
        'role_slot', 1,
        'is_host', true
    );
END;
$$;

-- Function: join_room
CREATE OR REPLACE FUNCTION join_room(
    p_room_code TEXT,
    p_display_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_room_id UUID;
    v_host_id UUID;
    v_status TEXT;
    v_existing_slot INT;
    v_existing_is_host BOOLEAN;
    v_participant_count INT;
    v_slot_to_assign INT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated. Please sign in as a guest.';
    END IF;

    IF trim(p_display_name) = '' THEN
        RAISE EXCEPTION 'Display name cannot be empty.';
    END IF;

    -- Find room by code
    SELECT id, host_id, status INTO v_room_id, v_host_id, v_status
    FROM rooms
    WHERE code = upper(trim(p_room_code));

    IF v_room_id IS NULL THEN
        RAISE EXCEPTION 'Room code % not found.', upper(trim(p_room_code));
    END IF;

    IF v_status = 'completed' OR v_status = 'abandoned' THEN
        RAISE EXCEPTION 'This room is no longer active.';
    END IF;

    -- Check if user is already in the room
    SELECT role_slot, is_host INTO v_existing_slot, v_existing_is_host
    FROM room_participants
    WHERE room_id = v_room_id AND user_id = v_user_id;

    IF v_existing_slot IS NOT NULL THEN
        -- Update display name and return
        UPDATE room_participants
        SET display_name = trim(p_display_name), last_seen_at = now()
        WHERE room_id = v_room_id AND user_id = v_user_id;

        RETURN jsonb_build_object(
            'success', true,
            'room_id', v_room_id,
            'room_code', upper(trim(p_room_code)),
            'user_id', v_user_id,
            'role_slot', v_existing_slot,
            'is_host', v_existing_is_host,
            'reconnected', true
        );
    END IF;

    -- Count existing participants
    SELECT count(*) INTO v_participant_count
    FROM room_participants
    WHERE room_id = v_room_id;

    IF v_participant_count >= 2 THEN
        RAISE EXCEPTION 'Room is full (maximum 2 players).';
    END IF;

    -- Determine slot
    IF EXISTS (SELECT 1 FROM room_participants WHERE room_id = v_room_id AND role_slot = 1) THEN
        v_slot_to_assign := 2;
    ELSE
        v_slot_to_assign := 1;
    END IF;

    -- Add participant
    INSERT INTO room_participants (room_id, user_id, display_name, is_host, role_slot)
    VALUES (v_room_id, v_user_id, trim(p_display_name), (v_user_id = v_host_id), v_slot_to_assign);

    RETURN jsonb_build_object(
        'success', true,
        'room_id', v_room_id,
        'room_code', upper(trim(p_room_code)),
        'user_id', v_user_id,
        'role_slot', v_slot_to_assign,
        'is_host', (v_user_id = v_host_id),
        'reconnected', false
    );
END;
$$;

-- Function: add_test_partner
CREATE OR REPLACE FUNCTION add_test_partner(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_bot_id UUID := gen_random_uuid();
    v_p_count INT;
BEGIN
    SELECT count(*) INTO v_p_count FROM room_participants WHERE room_id = p_room_id;
    IF v_p_count >= 2 THEN
        RETURN jsonb_build_object('success', true, 'already_full', true);
    END IF;

    INSERT INTO room_participants (room_id, user_id, display_name, is_host, role_slot)
    VALUES (p_room_id, v_bot_id, 'Cupid (Test Partner 🏹)', false, 2)
    ON CONFLICT (room_id, role_slot) DO NOTHING;

    RETURN jsonb_build_object('success', true, 'bot_added', true);
END;
$$;

-- Function: start_game
CREATE OR REPLACE FUNCTION start_game(
    p_room_id UUID,
    p_game_type TEXT,
    p_total_rounds INT DEFAULT 5
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_host_id UUID;
    v_session_id UUID;
    v_p_count INT;
    v_p1_id UUID;
    v_p1_name TEXT;
    v_p2_id UUID;
    v_p2_name TEXT;
    v_round_record RECORD;
    v_round_num INT := 1;
    v_target_id UUID;
    v_target_name TEXT;
    v_bot_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    -- Fetch room
    SELECT host_id INTO v_host_id FROM rooms WHERE id = p_room_id;
    IF v_host_id IS NULL THEN
        RAISE EXCEPTION 'Room not found.';
    END IF;

    -- Allow either room host or participant slot 1 to start
    IF v_host_id != v_user_id AND NOT EXISTS (
        SELECT 1 FROM room_participants WHERE room_id = p_room_id AND user_id = v_user_id AND is_host = true
    ) THEN
        RAISE EXCEPTION 'Only the room host can start the game.';
    END IF;

    -- Check participant count; if only 1, auto-provision test partner
    SELECT count(*) INTO v_p_count FROM room_participants WHERE room_id = p_room_id;
    IF v_p_count < 2 THEN
        v_bot_id := gen_random_uuid();
        INSERT INTO room_participants (room_id, user_id, display_name, is_host, role_slot)
        VALUES (p_room_id, v_bot_id, 'Cupid (Test Partner 🏹)', false, 2)
        ON CONFLICT (room_id, role_slot) DO NOTHING;
    END IF;

    -- Fetch both participants
    SELECT user_id, display_name INTO v_p1_id, v_p1_name
    FROM room_participants WHERE room_id = p_room_id AND role_slot = 1;

    SELECT user_id, display_name INTO v_p2_id, v_p2_name
    FROM room_participants WHERE room_id = p_room_id AND role_slot = 2;

    -- Update room status
    UPDATE rooms
    SET status = 'in_progress', selected_game = p_game_type, updated_at = now()
    WHERE id = p_room_id;

    -- Create game session
    INSERT INTO game_sessions (room_id, game_type, status, current_round_index, total_rounds)
    VALUES (p_room_id, p_game_type, 'active', 1, p_total_rounds)
    RETURNING id INTO v_session_id;

    -- Initialize scores
    INSERT INTO scores (session_id, user_id, display_name, score, matches_count)
    VALUES 
        (v_session_id, v_p1_id, COALESCE(v_p1_name, 'Player 1'), 0, 0),
        (v_session_id, v_p2_id, COALESCE(v_p2_name, 'Player 2'), 0, 0)
    ON CONFLICT (session_id, user_id) DO NOTHING;

    -- Guarantee questions exist for this game_type
    IF NOT EXISTS (SELECT 1 FROM question_banks WHERE game_type = p_game_type) THEN
        INSERT INTO question_banks (game_type, prompt, options) VALUES
        (p_game_type, 'What is our dream romantic getaway destination?', '["Tropical beach villa in the Maldives", "Historic cobblestone streets in Rome", "Cozy snowy cabin in the Alps", "Vibrant food adventure in Tokyo"]'::jsonb),
        (p_game_type, 'Would you rather receive sweet surprise notes daily or one lavish vacation annually?', '["Sweet surprise notes daily", "One lavish luxury vacation annually"]'::jsonb),
        (p_game_type, 'Who is more likely to stay up late laughing at funny videos?', '["Player 1", "Player 2", "Both of Us", "Neither"]'::jsonb),
        (p_game_type, 'What is your favorite memory of us together?', '["Our very first date and nervousness", "A trip where everything went delightfully wrong", "A quiet rainy night talking until 3 AM", "A spontaneous day full of uncontrollable laughter"]'::jsonb),
        (p_game_type, 'What quality do you admire most in your partner?', '["Their kindness and warmth", "Their sense of humor and smile", "Their passion and ambition", "Their loyalty and presence"]'::jsonb);
    END IF;

    -- Select and create rounds from question_banks
    FOR v_round_record IN (
        SELECT id, prompt, options, correct_option_index
        FROM question_banks
        WHERE game_type = p_game_type
        ORDER BY random()
        LIMIT p_total_rounds
    ) LOOP
        IF p_game_type = 'how_well_do_you_know_me' THEN
            IF v_round_num % 2 = 1 THEN
                v_target_id := v_p1_id;
                v_target_name := v_p1_name;
            ELSE
                v_target_id := v_p2_id;
                v_target_name := v_p2_name;
            END IF;
        ELSE
            v_target_id := NULL;
            v_target_name := NULL;
        END IF;

        INSERT INTO game_rounds (
            session_id,
            round_number,
            question_id,
            prompt,
            options,
            correct_option_index,
            target_player_id,
            target_player_name,
            status,
            started_at,
            expires_at
        ) VALUES (
            v_session_id,
            v_round_num,
            v_round_record.id,
            v_round_record.prompt,
            v_round_record.options,
            v_round_record.correct_option_index,
            v_target_id,
            v_target_name,
            'in_progress',
            CASE WHEN v_round_num = 1 THEN now() ELSE NULL END,
            CASE WHEN v_round_num = 1 THEN now() + interval '45 seconds' ELSE NULL END
        );

        v_round_num := v_round_num + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'current_round', 1,
        'total_rounds', p_total_rounds
    );
END;
$$;

-- Function: submit_player_answer
CREATE OR REPLACE FUNCTION submit_player_answer(
    p_round_id UUID,
    p_answer_text TEXT,
    p_partner_prediction TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_round_record RECORD;
    v_session_record RECORD;
    v_slot INT;
    v_display_name TEXT;
    v_p1_answer RECORD;
    v_p2_answer RECORD;
    v_p1_id UUID;
    v_p2_id UUID;
    v_p1_name TEXT;
    v_p2_name TEXT;
    v_p1_correct BOOLEAN := false;
    v_p2_correct BOOLEAN := false;
    v_p1_points INT := 0;
    v_p2_points INT := 0;
    v_is_match BOOLEAN := false;
    v_bot_answer_text TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    -- Fetch round and session
    SELECT gr.* INTO v_round_record FROM game_rounds gr WHERE gr.id = p_round_id;
    IF v_round_record.id IS NULL THEN
        RAISE EXCEPTION 'Round not found.';
    END IF;

    IF v_round_record.status != 'in_progress' THEN
        RAISE EXCEPTION 'Round is already %.', v_round_record.status;
    END IF;

    SELECT gs.* INTO v_session_record FROM game_sessions gs WHERE gs.id = v_round_record.session_id;

    -- Get participant info
    SELECT role_slot, display_name INTO v_slot, v_display_name
    FROM room_participants
    WHERE room_id = v_session_record.room_id AND user_id = v_user_id;

    IF v_slot IS NULL THEN
        RAISE EXCEPTION 'You are not a participant in this room.';
    END IF;

    -- Prevent duplicate submission
    IF EXISTS (SELECT 1 FROM player_answers WHERE round_id = p_round_id AND user_id = v_user_id) THEN
        RAISE EXCEPTION 'You have already submitted an answer for this round.';
    END IF;

    -- Insert caller answer
    INSERT INTO player_answers (round_id, user_id, display_name, answer_text, partner_prediction)
    VALUES (p_round_id, v_user_id, v_display_name, trim(p_answer_text), NULLIF(trim(p_partner_prediction), ''));

    -- Mark submission flag
    IF v_slot = 1 THEN
        UPDATE game_rounds SET p1_submitted = true WHERE id = p_round_id;
    ELSE
        UPDATE game_rounds SET p2_submitted = true WHERE id = p_round_id;
    END IF;

    -- Get both participant IDs
    SELECT user_id, display_name INTO v_p1_id, v_p1_name
    FROM room_participants WHERE room_id = v_session_record.room_id AND role_slot = 1;

    SELECT user_id, display_name INTO v_p2_id, v_p2_name
    FROM room_participants WHERE room_id = v_session_record.room_id AND role_slot = 2;

    -- If partner is a test bot (not an authenticated user), auto-submit simulated answer!
    IF v_slot = 1 AND v_p2_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_p2_id) THEN
        IF v_round_record.options IS NOT NULL AND jsonb_array_length(v_round_record.options) > 0 THEN
            v_bot_answer_text := trim(p_answer_text);
        ELSE
            v_bot_answer_text := 'You mean the world to me 💕';
        END IF;

        INSERT INTO player_answers (round_id, user_id, display_name, answer_text, partner_prediction)
        VALUES (p_round_id, v_p2_id, COALESCE(v_p2_name, 'Cupid (Bot)'), v_bot_answer_text, trim(p_answer_text))
        ON CONFLICT (round_id, user_id) DO NOTHING;

        UPDATE game_rounds SET p2_submitted = true WHERE id = p_round_id;
    END IF;

    -- Re-fetch submission state
    SELECT p1_submitted, p2_submitted INTO v_round_record.p1_submitted, v_round_record.p2_submitted
    FROM game_rounds WHERE id = p_round_id;

    -- If BOTH players have submitted, execute server-side scoring & reveal
    IF v_round_record.p1_submitted AND v_round_record.p2_submitted THEN
        SELECT pa.* INTO v_p1_answer
        FROM player_answers pa
        JOIN room_participants rp ON rp.user_id = pa.user_id AND rp.room_id = v_session_record.room_id
        WHERE pa.round_id = p_round_id AND rp.role_slot = 1;

        SELECT pa.* INTO v_p2_answer
        FROM player_answers pa
        JOIN room_participants rp ON rp.user_id = pa.user_id AND rp.room_id = v_session_record.room_id
        WHERE pa.round_id = p_round_id AND rp.role_slot = 2;

        -- Scoring
        CASE v_session_record.game_type
            WHEN 'would_you_rather', 'who_is_more_likely_to', 'same_time_challenge' THEN
                IF lower(trim(v_p1_answer.answer_text)) = lower(trim(v_p2_answer.answer_text)) THEN
                    v_is_match := true;
                    v_p1_points := 10;
                    v_p2_points := 10;
                ELSE
                    v_p1_points := 5;
                    v_p2_points := 5;
                END IF;

            WHEN 'how_well_do_you_know_me' THEN
                IF v_round_record.target_player_id = v_p1_answer.user_id THEN
                    IF lower(trim(COALESCE(v_p2_answer.partner_prediction, v_p2_answer.answer_text))) = lower(trim(v_p1_answer.answer_text)) THEN
                        v_is_match := true;
                        v_p2_correct := true;
                        v_p2_points := 15;
                    END IF;
                ELSE
                    IF lower(trim(COALESCE(v_p1_answer.partner_prediction, v_p1_answer.answer_text))) = lower(trim(v_p2_answer.answer_text)) THEN
                        v_is_match := true;
                        v_p1_correct := true;
                        v_p1_points := 15;
                    END IF;
                END IF;

            WHEN 'couple_quiz_battle' THEN
                IF v_round_record.correct_option_index IS NOT NULL THEN
                    DECLARE
                        v_correct_str TEXT := (v_round_record.options->>v_round_record.correct_option_index);
                    BEGIN
                        IF lower(trim(v_p1_answer.answer_text)) = lower(trim(v_correct_str)) THEN
                            v_p1_correct := true;
                            v_p1_points := 10;
                        END IF;
                        IF lower(trim(v_p2_answer.answer_text)) = lower(trim(v_correct_str)) THEN
                            v_p2_correct := true;
                            v_p2_points := 10;
                        END IF;
                    END;
                ELSE
                    v_p1_points := 10;
                    v_p2_points := 10;
                END IF;

            WHEN 'deep_questions' THEN
                v_p1_points := 10;
                v_p2_points := 10;
                v_is_match := true;

            ELSE
                v_p1_points := 5;
                v_p2_points := 5;
        END CASE;

        -- Update points
        UPDATE player_answers SET points_awarded = v_p1_points, is_correct = v_p1_correct WHERE id = v_p1_answer.id;
        UPDATE player_answers SET points_awarded = v_p2_points, is_correct = v_p2_correct WHERE id = v_p2_answer.id;

        -- Update scores
        UPDATE scores
        SET score = score + v_p1_points,
            matches_count = matches_count + (CASE WHEN v_is_match THEN 1 ELSE 0 END),
            updated_at = now()
        WHERE session_id = v_session_record.id AND user_id = v_p1_answer.user_id;

        UPDATE scores
        SET score = score + v_p2_points,
            matches_count = matches_count + (CASE WHEN v_is_match THEN 1 ELSE 0 END),
            updated_at = now()
        WHERE session_id = v_session_record.id AND user_id = v_p2_answer.user_id;

        -- Reveal round
        UPDATE game_rounds SET status = 'revealed', revealed_at = now() WHERE id = p_round_id;

        RETURN jsonb_build_object('success', true, 'revealed', true, 'both_submitted', true);
    ELSE
        RETURN jsonb_build_object('success', true, 'revealed', false, 'waiting_for_partner', true);
    END IF;
END;
$$;


-- Function: advance_round
CREATE OR REPLACE FUNCTION advance_round(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_session_record RECORD;
    v_current_round RECORD;
    v_next_round RECORD;
    v_is_host BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    -- Check caller is participant in room
    SELECT is_host INTO v_is_host
    FROM room_participants
    WHERE room_id = p_room_id AND user_id = v_user_id;

    IF v_is_host IS NULL THEN
        RAISE EXCEPTION 'You are not a participant in this room.';
    END IF;

    -- Fetch active game session
    SELECT * INTO v_session_record
    FROM game_sessions
    WHERE room_id = p_room_id AND status = 'active'
    ORDER BY created_at DESC LIMIT 1;

    IF v_session_record.id IS NULL THEN
        RAISE EXCEPTION 'No active game session found.';
    END IF;

    -- Fetch current round
    SELECT * INTO v_current_round
    FROM game_rounds
    WHERE session_id = v_session_record.id AND round_number = v_session_record.current_round_index;

    -- Check if all rounds completed
    IF v_session_record.current_round_index >= v_session_record.total_rounds THEN
        -- Finish game session
        UPDATE game_sessions
        SET status = 'finished', finished_at = now()
        WHERE id = v_session_record.id;

        UPDATE rooms
        SET status = 'completed', updated_at = now()
        WHERE id = p_room_id;

        RETURN jsonb_build_object(
            'success', true,
            'game_finished', true,
            'session_id', v_session_record.id
        );
    END IF;

    -- Advance to next round
    UPDATE game_sessions
    SET current_round_index = v_session_record.current_round_index + 1
    WHERE id = v_session_record.id;

    -- Activate next round
    UPDATE game_rounds
    SET status = 'in_progress',
        started_at = now(),
        expires_at = now() + interval '45 seconds'
    WHERE session_id = v_session_record.id
      AND round_number = v_session_record.current_round_index + 1;

    RETURN jsonb_build_object(
        'success', true,
        'game_finished', false,
        'new_round_index', v_session_record.current_round_index + 1
    );
END;
$$;

-- Function: reveal_round_on_timeout
CREATE OR REPLACE FUNCTION reveal_round_on_timeout(p_round_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_round_record RECORD;
BEGIN
    SELECT * INTO v_round_record FROM game_rounds WHERE id = p_round_id;
    IF v_round_record.id IS NULL THEN
        RAISE EXCEPTION 'Round not found.';
    END IF;

    IF v_round_record.status = 'revealed' THEN
        RETURN jsonb_build_object('success', true, 'already_revealed', true);
    END IF;

    -- Reveal round
    UPDATE game_rounds
    SET status = 'revealed', revealed_at = now()
    WHERE id = p_round_id;

    RETURN jsonb_build_object('success', true, 'revealed', true);
END;
$$;

-- Function: reset_room_game (To play again with same partner)
CREATE OR REPLACE FUNCTION reset_room_game(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_host BOOLEAN;
BEGIN
    SELECT is_host INTO v_is_host
    FROM room_participants
    WHERE room_id = p_room_id AND user_id = v_user_id;

    IF v_is_host IS NULL THEN
        RAISE EXCEPTION 'Not a participant.';
    END IF;

    UPDATE rooms
    SET status = 'waiting', selected_game = NULL, updated_at = now()
    WHERE id = p_room_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- 9. SEED DATA: COMPREHENSIVE QUESTION BANKS FOR ALL 6 GAMES

-- 1. HOW WELL DO YOU KNOW ME?
INSERT INTO question_banks (game_type, category, prompt, options) VALUES
('how_well_do_you_know_me', 'habits', 'What is my absolute go-to comfort food when I am having a rough day?', '["Pizza", "Ice Cream", "Pasta / Noodles", "Burgers & Fries"]'::jsonb),
('how_well_do_you_know_me', 'favorites', 'What would be my dream vacation style?', '["Luxury tropical resort with no itinerary", "Backpacking adventure exploring historic cities", "Cozy cabin retreat in the snowy mountains", "Cruising the open ocean with endless activities"]'::jsonb),
('how_well_do_you_know_me', 'habits', 'How do I take my morning coffee or tea?', '["Sweet and creamy with flavored syrup", "Strong and black / straight brew", "Herbal / iced refreshers only", "Not a coffee/tea person, water or juice"]'::jsonb),
('how_well_do_you_know_me', 'romance', 'What was my initial first thought when we first started talking?', '["Wow, they are undeniably cute and charming", "They seem super intriguing and mysterious", "I felt instantly comfortable like an old friend", "I was nervously trying not to embarrass myself"]'::jsonb),
('how_well_do_you_know_me', 'daily_life', 'What is my favorite way to spend a quiet Sunday evening?', '["Binge-watching a show wrapped in a blanket", "Cooking an elaborate meal together", "Going for a peaceful sunset drive or walk", "Reading, gaming, or quiet side-by-side time"]'::jsonb),
('how_well_do_you_know_me', 'quirks', 'What is my biggest pet peeve?', '["Chewing loudly or messy eating", "People being chronically late", "Interrupting while talking", "Disorganized spaces / clutter left out"]'::jsonb),
('how_well_do_you_know_me', 'dreams', 'If I could wake up tomorrow with any superpower, which would I pick?', '["Teleportation anywhere instantly", "Mind reading / knowing what people think", "Time travel to witness history", "Invisibility / stealth"]'::jsonb),
('how_well_do_you_know_me', 'entertainment', 'What movie genre could I re-watch endlessly without getting bored?', '["Romantic Comedy", "Psychological Thriller / Mystery", "Sci-Fi / Superhero Epic", "Nostalgic Animated Classics"]'::jsonb),
('how_well_do_you_know_me', 'shopping', 'What store can I never leave without buying something?', '["Target or HomeGoods", "Bookstore or Stationery shop", "Clothing boutique or sneaker store", "Gourmet grocery or snack aisle"]'::jsonb),
('how_well_do_you_know_me', 'favorites', 'What is my love language when I want to feel most appreciated?', '["Physical Touch & Cuddles", "Words of Affirmation & Sweet Texts", "Quality Time with Undivided Attention", "Acts of Service / Taking care of tasks"]'::jsonb);

-- 2. WOULD YOU RATHER?
INSERT INTO question_banks (game_type, category, prompt, options) VALUES
('would_you_rather', 'lifestyle', 'Would you rather live in a beachside villa or a cozy secluded mountain chalet?', '["Beachside villa with ocean sunsets", "Mountain chalet with a crackling fireplace"]'::jsonb),
('would_you_rather', 'dining', 'Would you rather never be able to eat takeout again or never eat home-cooked meals again?', '["Give up takeout forever (home cooking only)", "Give up home cooking forever (takeout & dining out only)"]'::jsonb),
('would_you_rather', 'travel', 'Would you rather take a surprise road trip with no plan or an itinerary-planned European holiday?', '["Spontaneous spontaneous road trip", "Meticulously planned European holiday"]'::jsonb),
('would_you_rather', 'quirky', 'Would you rather lose the ability to speak for a week or have to speak your exact unfiltered thoughts out loud?', '["Remain completely silent for a week", "Say every single thought out loud"]'::jsonb),
('would_you_rather', 'relationship', 'Would you rather always wake up early together to catch sunrises or stay up late stargazing?', '["Early morning sunrises & morning coffee", "Late night stargazing & deep midnight talks"]'::jsonb),
('would_you_rather', 'entertainment', 'Would you rather have front row concert tickets to your favorite artist or VIP passes to all movie premieres?', '["Front row music concert", "VIP movie theater premieres for life"]'::jsonb),
('would_you_rather', 'adventure', 'Would you rather go skydiving together or scuba diving with sea turtles?', '["Skydiving from 15,000 feet", "Scuba diving with coral reefs & turtles"]'::jsonb),
('would_you_rather', 'daily_life', 'Would you rather have a personal private chef cook every dinner or a private cleaner handle all housework?', '["Personal private gourmet chef", "Private housekeeping cleaning service"]'::jsonb),
('would_you_rather', 'technology', 'Would you rather give up your smartphone for a full month together or give up music for a year?', '["No smartphone for a month", "No music for a year"]'::jsonb),
('would_you_rather', 'romance', 'Would you rather receive 100 small thoughtful surprise gifts or one giant grand dream vacation?', '["100 small sweet surprises throughout the year", "One once-in-a-lifetime grand holiday"]'::jsonb);

-- 3. WHO IS MORE LIKELY TO?
INSERT INTO question_banks (game_type, category, prompt, options) VALUES
('who_is_more_likely_to', 'habits', 'Who is more likely to fall asleep 10 minutes into a movie they chose?', '["Player 1", "Player 2", "Both equally", "Neither"]'::jsonb),
('who_is_more_likely_to', 'shopping', 'Who is more likely to buy something online that they definitely do not need at 2:00 AM?', '["Player 1", "Player 2", "Both equally", "Neither"]'::jsonb),
('who_is_more_likely_to', 'travel', 'Who is more likely to get lost even while using Google Maps with voice navigation?', '["Player 1", "Player 2", "Both equally", "Neither"]'::jsonb),
('who_is_more_likely_to', 'romance', 'Who is more likely to start crying during an emotional scene in a movie or wedding?', '["Player 1", "Player 2", "Both equally", "Neither"]'::jsonb),
('who_is_more_likely_to', 'social', 'Who is more likely to make random best friends with strangers or pets at a party?', '["Player 1", "Player 2", "Both equally", "Neither"]'::jsonb),
('who_is_more_likely_to', 'cooking', 'Who is more likely to accidentally burn toast or boil water over while multitasking?', '["Player 1", "Player 2", "Both equally", "Neither"]'::jsonb),
('who_is_more_likely_to', 'drama', 'Who is more likely to take 30 minutes deciding what restaurant to order from?', '["Player 1", "Player 2", "Both equally", "Neither"]'::jsonb),
('who_is_more_likely_to', 'daily_life', 'Who is more likely to hit snooze on their alarm clock 5 times in a row?', '["Player 1", "Player 2", "Both equally", "Neither"]'::jsonb),
('who_is_more_likely_to', 'adventures', 'Who is more likely to suggest doing something crazy and impulsive on a whim?', '["Player 1", "Player 2", "Both equally", "Neither"]'::jsonb),
('who_is_more_likely_to', 'memory', 'Who is more likely to remember exact minor details or quotes from a conversation 6 months ago?', '["Player 1", "Player 2", "Both equally", "Neither"]'::jsonb);

-- 4. COUPLE QUIZ BATTLE (Speed & accuracy trivia)
INSERT INTO question_banks (game_type, category, prompt, options, correct_option_index) VALUES
('couple_quiz_battle', 'trivia', 'In ancient Roman mythology, who was the god of desire, affection, and love?', '["Mars", "Cupid", "Apollo", "Hermes"]'::jsonb, 1),
('couple_quiz_battle', 'culture', 'What is traditionally considered the classic symbol for a 50th wedding anniversary?', '["Silver", "Emerald", "Gold", "Diamond"]'::jsonb, 2),
('couple_quiz_battle', 'science', 'Which chemical neurotransmitter is famously nicknamed the "cuddle hormone" or bonding molecule?', '["Dopamine", "Oxytocin", "Serotonin", "Endorphin"]'::jsonb, 1),
('couple_quiz_battle', 'literature', 'In Shakespeare''s famous tragedy Romeo and Juliet, in what Italian city does the romance take place?', '["Florence", "Venice", "Verona", "Naples"]'::jsonb, 2),
('couple_quiz_battle', 'film', 'Which iconic movie features the famous romantic quote: "You had me at hello"?', '["Titanic", "Jerry Maguire", "Notting Hill", "The Notebook"]'::jsonb, 1),
('couple_quiz_battle', 'pop_culture', 'What color rose is universally celebrated as representing pure deep romantic love?', '["Yellow", "White", "Red", "Lavender"]'::jsonb, 2),
('couple_quiz_battle', 'geography', 'Known worldwide as the "City of Love", which European capital attracts millions of couples every year?', '["Vienna", "Paris", "Prague", "Rome"]'::jsonb, 1),
('couple_quiz_battle', 'psychology', 'According to Dr. Gary Chapman, how many recognized Primary Love Languages are there?', '["3", "5", "7", "10"]'::jsonb, 1),
('couple_quiz_battle', 'music', 'Which artist sang the legendary ballad "Can''t Help Falling in Love" first released in 1961?', '["Elvis Presley", "Frank Sinatra", "The Beatles", "Roy Orbison"]'::jsonb, 0),
('couple_quiz_battle', 'nature', 'Which of these sea creatures is famous for mating for life and swimming while holding tails?', '["Dolphins", "Seahorses", "Clownfish", "Sea Otters"]'::jsonb, 1);

-- 5. SAME-TIME CHALLENGE (Pick or type without conferring!)
INSERT INTO question_banks (game_type, category, prompt, options) VALUES
('same_time_challenge', 'quick_pick', 'Quick! Pick the perfect pizza topping combo right now:', '["Pepperoni & Extra Cheese", "Margherita (Basil & Fresh Mozzarella)", "BBQ Chicken & Red Onion", "Mushrooms & Roasted Garlic"]'::jsonb),
('same_time_challenge', 'quick_pick', 'Name the ultimate date night movie vibe without speaking:', '["Laugh-out-loud comedy", "Mind-bending suspense thriller", "Heartfelt romantic drama", "Animated or fantasy nostalgia"]'::jsonb),
('same_time_challenge', 'quick_pick', 'Pick our ideal weekend morning breakfast:', '["Fluffy pancakes / French toast with maple syrup", "Crispy bacon, eggs, hash browns & toast", "Avocado toast with poached egg & fresh brew", "Fresh pastries, croissants & fruit platter"]'::jsonb),
('same_time_challenge', 'quick_pick', 'If we could adopt any pet right now, what is your instant choice?', '["Playful puppy / dog", "Cuddly rescue kitten / cat", "Chirpy lovebird or parrot", "Exotic aquarium fish"]'::jsonb),
('same_time_challenge', 'quick_pick', 'Which music era has the best vibe for a late-night car drive?', '["80s Synthpop & Classic Anthems", "90s / 2000s R&B & Pop Throwbacks", "Lo-Fi Beats & Acoustic Chill", "Modern Hits & Indie Pop"]'::jsonb),
('same_time_challenge', 'quick_pick', 'Pick the ultimate dessert to share on a date:', '["Warm chocolate lava cake with vanilla gelato", "Creamy New York cheesecake with berry compote", "Crispy churros with dulce de leche dip", "Artisanal ice cream sundae with all toppings"]'::jsonb),
('same_time_challenge', 'quick_pick', 'What temperature is ideal for sleeping together in bed?', '["Freezing cold AC under heavy duvet blankets", "Cool and crisp with light throw blanket", "Warm and cozy ambient room", "Windows wide open for natural breeze"]'::jsonb),
('same_time_challenge', 'quick_pick', 'Instant reaction: Would you prefer an outdoor picnic or candlelit restaurant?', '["Sunny outdoor park picnic with snacks", "Dim candlelit Italian restaurant with wine"]'::jsonb),
('same_time_challenge', 'quick_pick', 'Pick our dream couple costume theme for Halloween:', '["Famous cinematic duo (e.g. Gomez & Morticia)", "Hilarious funny matching pun costume", "Retro vintage 70s / 80s disco icons", "Superhero & partner in crime"]'::jsonb),
('same_time_challenge', 'quick_pick', 'What is our dominant couple vibe?', '["The goofy laughing best friends", "The chic romantic power couple", "The cozy introverted homebodies", "The spontaneous restless adventurers"]'::jsonb);

-- 6. DEEP QUESTIONS (Intimate connection & conversation starters)
INSERT INTO question_banks (game_type, category, prompt, options) VALUES
('deep_questions', 'vulnerability', 'What was the exact moment or quality that made you feel safe and comfortable opening up to me?', '["When you listened without judgment", "How you made me laugh when I was stressed", "A vulnerable conversation where we connected deeply", "Your kindness and constant warmth"]'::jsonb),
('deep_questions', 'future', 'What is a personal dream or ambition you hold that you want us to accomplish together in the next 3-5 years?', '["Creating a home that is our sanctuary", "Traveling the world discovering new cultures", "Achieving financial freedom & peace of mind", "Building something creative or meaningful together"]'::jsonb),
('deep_questions', 'reflection', 'What is something small that I do every day that makes you feel deeply loved or appreciated?', '["A gentle touch, hug, or morning kiss", "Asking how my day really went and listening", "Bringing me a drink or snack unexpectedly", "Encouraging me when I doubt myself"]'::jsonb),
('deep_questions', 'growth', 'In what way do you feel you have grown the most as a person since we came into each other''s lives?', '["More patient and understanding of others", "More confident in pursuing what I want", "Better at expressing feelings openly", "Learning to slow down and cherish simple moments"]'::jsonb),
('deep_questions', 'memory', 'If you could relive any single 24-hour day from our time together with a pause button, which day would you choose?', '["Our very first date and first spark", "A spontaneous day where we laughed until our stomachs hurt", "A memorable trip or getaway together", "A quiet rainy day spent doing nothing together"]'::jsonb),
('deep_questions', 'gratitude', 'What is something about my personality that you admire most, even during difficult days?', '["Your resilience and unwavering determination", "Your empathy and compassion for people", "Your optimism and sense of humor", "Your loyalty and grounded perspective"]'::jsonb),
('deep_questions', 'connection', 'What is a habit or tradition we haven''t started yet that you would love to make "our thing"?', '["A weekly sacred phone-free date night", "An annual anniversary trip to a new place", "Reading or learning something together", "A morning or evening walking ritual"]'::jsonb),
('deep_questions', 'heartfelt', 'What does genuine intimacy mean to you beyond physical closeness?', '["Being completely emotionally transparent without fear", "Feeling understood even in silence", "Knowing we have each other''s backs against the world", "Sharing flaws and feeling cherished anyway"]'::jsonb),
('deep_questions', 'dreams', 'When you picture us 20 years from today, what is the core feeling or scene that comes to your heart?', '["Still laughing at silly private jokes", "Peaceful and content in a loving home", "Adventuring into new chapters hand in hand", "Proud of everything we built together"]'::jsonb),
('deep_questions', 'appreciation', 'What is one thing you wish I reminded myself more often whenever I am hard on myself?', '["That you are doing so much better than you realize", "That you are deeply loved exactly as you are", "That it is okay to rest and breathe", "That your worth isn''t measured by productivity"]'::jsonb);
