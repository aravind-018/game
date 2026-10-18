-- ====================================================================
-- TWO OF US: ONE-CLICK CONSOLIDATED DATABASE REPAIR & SETUP SCRIPT
-- Paste this entire script into your Supabase Dashboard -> SQL Editor -> Run
-- ====================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. RELAX FOREIGN KEYS ON USER_ID & NOT NULL CONSTRAINTS
ALTER TABLE IF EXISTS room_participants DROP CONSTRAINT IF EXISTS room_participants_user_id_fkey;
ALTER TABLE IF EXISTS scores DROP CONSTRAINT IF EXISTS scores_user_id_fkey;
ALTER TABLE IF EXISTS player_answers DROP CONSTRAINT IF EXISTS player_answers_user_id_fkey;
ALTER TABLE IF EXISTS game_rounds DROP CONSTRAINT IF EXISTS game_rounds_target_player_id_fkey;
ALTER TABLE IF EXISTS game_rounds ALTER COLUMN started_at DROP NOT NULL;

-- 3. HELPER FUNCTIONS (SECURITY DEFINER to avoid RLS recursion 42P17)
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

-- 4. DROP ALL EXISTING RLS POLICIES TO AVOID CONFLICTS
DROP POLICY IF EXISTS "Participants can view their room" ON rooms;
DROP POLICY IF EXISTS "Host can insert room" ON rooms;
DROP POLICY IF EXISTS "Host can update room" ON rooms;
DROP POLICY IF EXISTS "Anyone authenticated can view questions" ON question_banks;
DROP POLICY IF EXISTS "Participants can view room members" ON room_participants;
DROP POLICY IF EXISTS "Users can join as participant" ON room_participants;
DROP POLICY IF EXISTS "Users can update their own participant record" ON room_participants;
DROP POLICY IF EXISTS "Users or Host can remove participant" ON room_participants;
DROP POLICY IF EXISTS "Room participants can view custom questions" ON custom_questions;
DROP POLICY IF EXISTS "Room participants can insert custom questions" ON custom_questions;
DROP POLICY IF EXISTS "Room participants can view game sessions" ON game_sessions;
DROP POLICY IF EXISTS "Room participants can view game rounds" ON game_rounds;
DROP POLICY IF EXISTS "Answer privacy policy" ON player_answers;
DROP POLICY IF EXISTS "Users can insert their own answer" ON player_answers;
DROP POLICY IF EXISTS "Room participants can view scores" ON scores;

-- 5. RECREATE CLEAN ROW LEVEL SECURITY POLICIES

-- ROOMS
CREATE POLICY "Participants can view their room"
ON rooms FOR SELECT
TO authenticated, anon
USING (
    host_id = auth.uid()
    OR is_room_participant(id, auth.uid())
);

CREATE POLICY "Host can insert room"
ON rooms FOR INSERT
TO authenticated, anon
WITH CHECK (host_id = auth.uid());

CREATE POLICY "Host can update room"
ON rooms FOR UPDATE
TO authenticated, anon
USING (host_id = auth.uid() OR is_room_participant(id, auth.uid()));

-- ROOM PARTICIPANTS (Safe non-recursive policies)
CREATE POLICY "Participants can view room members"
ON room_participants FOR SELECT
TO authenticated, anon
USING (
    user_id = auth.uid()
    OR is_room_participant(room_id, auth.uid())
    OR is_room_host(room_id, auth.uid())
);

CREATE POLICY "Users can join as participant"
ON room_participants FOR INSERT
TO authenticated, anon
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own participant record"
ON room_participants FOR UPDATE
TO authenticated, anon
USING (user_id = auth.uid());

CREATE POLICY "Users or Host can remove participant"
ON room_participants FOR DELETE
TO authenticated, anon
USING (
    user_id = auth.uid()
    OR is_room_host(room_id, auth.uid())
);

-- QUESTION BANKS
CREATE POLICY "Anyone can view questions"
ON question_banks FOR SELECT
TO authenticated, anon
USING (true);

-- CUSTOM QUESTIONS
CREATE POLICY "Room participants can view custom questions"
ON custom_questions FOR SELECT
TO authenticated, anon
USING (
    created_by = auth.uid()
    OR is_room_participant(room_id, auth.uid())
);

CREATE POLICY "Room participants can insert custom questions"
ON custom_questions FOR INSERT
TO authenticated, anon
WITH CHECK (
    created_by = auth.uid()
    AND is_room_participant(room_id, auth.uid())
);

-- GAME SESSIONS
CREATE POLICY "Room participants can view game sessions"
ON game_sessions FOR SELECT
TO authenticated, anon
USING (
    is_room_participant(room_id, auth.uid())
    OR is_room_host(room_id, auth.uid())
);

-- GAME ROUNDS
CREATE POLICY "Room participants can view game rounds"
ON game_rounds FOR SELECT
TO authenticated, anon
USING (
    EXISTS (
        SELECT 1 FROM game_sessions gs
        WHERE gs.id = game_rounds.session_id
          AND (is_room_participant(gs.room_id, auth.uid()) OR is_room_host(gs.room_id, auth.uid()))
    )
);

-- PLAYER ANSWERS (CRUCIAL PRIVACY RULE)
CREATE POLICY "Answer privacy policy"
ON player_answers FOR SELECT
TO authenticated, anon
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
TO authenticated, anon
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
TO authenticated, anon
USING (
    EXISTS (
        SELECT 1 FROM game_sessions gs
        WHERE gs.id = scores.session_id
          AND (is_room_participant(gs.room_id, auth.uid()) OR is_room_host(gs.room_id, auth.uid()))
    )
);

-- 6. RPC FUNCTION: create_room
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
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result TEXT;
    i INT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated. Please sign in as a guest.';
    END IF;

    IF trim(p_display_name) = '' THEN
        RAISE EXCEPTION 'Display name cannot be empty.';
    END IF;

    LOOP
        result := '';
        FOR i IN 1..6 LOOP
            result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
        END LOOP;
        v_room_code := result;
        EXIT WHEN NOT EXISTS (SELECT 1 FROM rooms WHERE code = v_room_code) OR v_retries > 10;
        v_retries := v_retries + 1;
    END LOOP;

    INSERT INTO rooms (code, host_id, selected_game, status)
    VALUES (v_room_code, v_user_id, p_selected_game, 'waiting')
    RETURNING id INTO v_room_id;

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

-- 7. RPC FUNCTION: join_room
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
    v_room_status TEXT;
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

    SELECT id, host_id, status INTO v_room_id, v_host_id, v_room_status
    FROM rooms
    WHERE upper(code) = upper(trim(p_room_code));

    IF v_room_id IS NULL THEN
        RAISE EXCEPTION 'Room code not found.';
    END IF;

    IF v_room_status = 'completed' THEN
        RAISE EXCEPTION 'This game room has already ended.';
    END IF;

    SELECT role_slot, is_host INTO v_existing_slot, v_existing_is_host
    FROM room_participants
    WHERE room_id = v_room_id AND user_id = v_user_id;

    IF v_existing_slot IS NOT NULL THEN
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

    SELECT count(*) INTO v_participant_count
    FROM room_participants
    WHERE room_id = v_room_id;

    IF v_participant_count >= 2 THEN
        RAISE EXCEPTION 'Room is full (maximum 2 players).';
    END IF;

    IF EXISTS (SELECT 1 FROM room_participants WHERE room_id = v_room_id AND role_slot = 1) THEN
        v_slot_to_assign := 2;
    ELSE
        v_slot_to_assign := 1;
    END IF;

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

-- 8. RPC FUNCTION: add_test_partner
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

-- 9. RPC FUNCTION: start_game (Resilient & foolproof)
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
    v_created_rounds INT := 0;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM rooms WHERE id = p_room_id) THEN
        RAISE EXCEPTION 'Room not found.';
    END IF;

    -- Allow ANY participant in this room to launch
    IF NOT EXISTS (SELECT 1 FROM room_participants WHERE room_id = p_room_id AND user_id = v_user_id) THEN
        RAISE EXCEPTION 'Only room participants can start the game.';
    END IF;

    -- If solo, auto-provision test partner
    SELECT count(*) INTO v_p_count FROM room_participants WHERE room_id = p_room_id;
    IF v_p_count < 2 THEN
        v_bot_id := gen_random_uuid();
        INSERT INTO room_participants (room_id, user_id, display_name, is_host, role_slot)
        VALUES (p_room_id, v_bot_id, 'Cupid (Test Partner 🏹)', false, 2)
        ON CONFLICT (room_id, role_slot) DO NOTHING;
    END IF;

    -- Fetch participants
    SELECT user_id, display_name INTO v_p1_id, v_p1_name
    FROM room_participants WHERE room_id = p_room_id AND role_slot = 1;

    SELECT user_id, display_name INTO v_p2_id, v_p2_name
    FROM room_participants WHERE room_id = p_room_id AND role_slot = 2;

    IF v_p1_id IS NULL THEN
        v_p1_id := v_user_id;
        v_p1_name := 'Player 1';
    END IF;
    IF v_p2_id IS NULL THEN
        v_p2_id := gen_random_uuid();
        v_p2_name := 'Player 2';
    END IF;

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

    -- Ensure questions exist for this game_type
    IF NOT EXISTS (SELECT 1 FROM question_banks WHERE game_type = p_game_type) THEN
        INSERT INTO question_banks (game_type, prompt, options) VALUES
        (p_game_type, 'What is our dream romantic getaway destination?', '["Tropical beach villa in the Maldives", "Historic cobblestone streets in Rome", "Cozy snowy cabin in the Alps", "Vibrant food adventure in Tokyo"]'::jsonb),
        (p_game_type, 'Would you rather receive sweet surprise notes daily or one lavish vacation annually?', '["Sweet surprise notes daily", "One lavish luxury vacation annually"]'::jsonb),
        (p_game_type, 'Who is more likely to stay up late laughing at funny videos?', '["Player 1", "Player 2", "Both of Us", "Neither"]'::jsonb),
        (p_game_type, 'What is your favorite memory of us together?', '["Our very first date and nervousness", "A trip where everything went delightfully wrong", "A quiet rainy night talking until 3 AM", "A spontaneous day full of uncontrollable laughter"]'::jsonb),
        (p_game_type, 'What quality do you admire most in your partner?', '["Their kindness and warmth", "Their sense of humor and smile", "Their passion and ambition", "Their loyalty and presence"]'::jsonb),
        (p_game_type, 'Quick! Pick the perfect pizza topping combo right now:', '["Pepperoni & Extra Cheese", "Margherita (Basil & Fresh Mozzarella)", "BBQ Chicken & Red Onion", "Mushrooms & Roasted Garlic"]'::jsonb),
        (p_game_type, 'What is something small that makes you feel deeply loved?', '["A gentle hug or kiss", "Bringing me a drink unexpectedly", "Asking about my day", "Encouraging me when in doubt"]'::jsonb);
    END IF;

    -- Create rounds
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
            now(),
            now() + interval '45 seconds'
        );

        v_created_rounds := v_created_rounds + 1;
        v_round_num := v_round_num + 1;
    END LOOP;

    -- Fallback safety check if fewer rounds were created
    IF v_created_rounds = 0 THEN
        INSERT INTO game_rounds (
            session_id, round_number, prompt, options, status, started_at, expires_at
        ) VALUES (
            v_session_id, 1, 'What is our favorite couple memory together?',
            '["Our first date", "Our favorite trip", "A late night talk", "Laughing together"]'::jsonb,
            'in_progress', now(), now() + interval '45 seconds'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'current_round', 1,
        'total_rounds', p_total_rounds
    );
END;
$$;

-- 10. RPC FUNCTION: submit_player_answer
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

    SELECT gr.* INTO v_round_record FROM game_rounds gr WHERE gr.id = p_round_id;
    IF v_round_record.id IS NULL THEN
        RAISE EXCEPTION 'Round not found.';
    END IF;

    IF v_round_record.status != 'in_progress' THEN
        RAISE EXCEPTION 'Round is already %.', v_round_record.status;
    END IF;

    SELECT gs.* INTO v_session_record FROM game_sessions gs WHERE gs.id = v_round_record.session_id;

    SELECT role_slot, display_name INTO v_slot, v_display_name
    FROM room_participants
    WHERE room_id = v_session_record.room_id AND user_id = v_user_id;

    IF v_slot IS NULL THEN
        RAISE EXCEPTION 'You are not a participant in this room.';
    END IF;

    IF EXISTS (SELECT 1 FROM player_answers WHERE round_id = p_round_id AND user_id = v_user_id) THEN
        RAISE EXCEPTION 'You have already submitted an answer for this round.';
    END IF;

    INSERT INTO player_answers (round_id, user_id, display_name, answer_text, partner_prediction)
    VALUES (p_round_id, v_user_id, v_display_name, trim(p_answer_text), NULLIF(trim(p_partner_prediction), ''));

    IF v_slot = 1 THEN
        UPDATE game_rounds SET p1_submitted = true WHERE id = p_round_id;
    ELSE
        UPDATE game_rounds SET p2_submitted = true WHERE id = p_round_id;
    END IF;

    SELECT user_id, display_name INTO v_p1_id, v_p1_name
    FROM room_participants WHERE room_id = v_session_record.room_id AND role_slot = 1;

    SELECT user_id, display_name INTO v_p2_id, v_p2_name
    FROM room_participants WHERE room_id = v_session_record.room_id AND role_slot = 2;

    -- Auto-answer for test bot if playing solo
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

    SELECT p1_submitted, p2_submitted INTO v_round_record.p1_submitted, v_round_record.p2_submitted
    FROM game_rounds WHERE id = p_round_id;

    IF v_round_record.p1_submitted AND v_round_record.p2_submitted THEN
        SELECT pa.* INTO v_p1_answer
        FROM player_answers pa
        JOIN room_participants rp ON rp.user_id = pa.user_id AND rp.room_id = v_session_record.room_id
        WHERE pa.round_id = p_round_id AND rp.role_slot = 1;

        SELECT pa.* INTO v_p2_answer
        FROM player_answers pa
        JOIN room_participants rp ON rp.user_id = pa.user_id AND rp.room_id = v_session_record.room_id
        WHERE pa.round_id = p_round_id AND rp.role_slot = 2;

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

        UPDATE player_answers SET points_awarded = v_p1_points, is_correct = v_p1_correct WHERE id = v_p1_answer.id;
        UPDATE player_answers SET points_awarded = v_p2_points, is_correct = v_p2_correct WHERE id = v_p2_answer.id;

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

        UPDATE game_rounds SET status = 'revealed', revealed_at = now() WHERE id = p_round_id;

        RETURN jsonb_build_object('success', true, 'revealed', true, 'both_submitted', true);
    ELSE
        RETURN jsonb_build_object('success', true, 'revealed', false, 'waiting_for_partner', true);
    END IF;
END;
$$;

-- 11. RPC FUNCTION: advance_round
CREATE OR REPLACE FUNCTION advance_round(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_session_record RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    SELECT gs.* INTO v_session_record
    FROM game_sessions gs
    WHERE gs.room_id = p_room_id AND gs.status = 'active'
    ORDER BY gs.created_at DESC
    LIMIT 1;

    IF v_session_record.id IS NULL THEN
        RAISE EXCEPTION 'No active game session found for this room.';
    END IF;

    IF v_session_record.current_round_index >= v_session_record.total_rounds THEN
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

    UPDATE game_sessions
    SET current_round_index = v_session_record.current_round_index + 1
    WHERE id = v_session_record.id;

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

-- 12. RPC FUNCTION: reset_room
CREATE OR REPLACE FUNCTION reset_room(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    UPDATE rooms
    SET status = 'waiting', selected_game = NULL, updated_at = now()
    WHERE id = p_room_id;

    UPDATE game_sessions
    SET status = 'finished', finished_at = now()
    WHERE room_id = p_room_id AND status = 'active';

    RETURN jsonb_build_object('success', true);
END;
$$;

-- Alias reset_room_game
CREATE OR REPLACE FUNCTION reset_room_game(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    RETURN reset_room(p_room_id);
END;
$$;

-- 13. GRANT EXECUTE ON ALL RPC FUNCTIONS
GRANT EXECUTE ON FUNCTION is_room_participant(UUID, UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION is_room_host(UUID, UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION create_room(TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION join_room(TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION add_test_partner(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION start_game(UUID, TEXT, INT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION submit_player_answer(UUID, TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION advance_round(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION reset_room(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION reset_room_game(UUID) TO authenticated, anon;

-- 14. REALTIME PUBLICATION (Safely check if already added)
DO $$
DECLARE
    tbl text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;

    FOR tbl IN SELECT unnest(ARRAY['rooms', 'room_participants', 'game_sessions', 'game_rounds', 'player_answers', 'scores', 'room_messages'])
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = tbl
        ) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I', tbl);
        END IF;
    END LOOP;
END $$;

-- 15. ROOM MESSAGES (In-room chat)
CREATE TABLE IF NOT EXISTS room_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    display_name TEXT NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_room_messages_room_id ON room_messages(room_id, created_at);

ALTER TABLE room_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_messages REPLICA IDENTITY FULL;

DROP POLICY IF EXISTS "Participants can view room messages" ON room_messages;
CREATE POLICY "Participants can view room messages"
ON room_messages FOR SELECT
TO authenticated, anon
USING (
    is_room_participant(room_id, auth.uid())
    OR is_room_host(room_id, auth.uid())
);

DROP POLICY IF EXISTS "Participants can insert room messages" ON room_messages;
CREATE POLICY "Participants can insert room messages"
ON room_messages FOR INSERT
TO authenticated, anon
WITH CHECK (
    is_room_participant(room_id, auth.uid())
    OR is_room_host(room_id, auth.uid())
);

CREATE OR REPLACE FUNCTION send_room_message(
    p_room_id UUID,
    p_message TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_display_name TEXT;
    v_msg_row RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    IF trim(p_message) = '' THEN
        RAISE EXCEPTION 'Message cannot be empty.';
    END IF;

    SELECT display_name INTO v_display_name
    FROM room_participants
    WHERE room_id = p_room_id AND user_id = v_user_id;

    IF v_display_name IS NULL THEN
        v_display_name := 'Player';
    END IF;

    INSERT INTO room_messages (room_id, user_id, display_name, message)
    VALUES (p_room_id, v_user_id, v_display_name, trim(p_message))
    RETURNING * INTO v_msg_row;

    RETURN jsonb_build_object(
        'id', v_msg_row.id,
        'room_id', v_msg_row.room_id,
        'user_id', v_msg_row.user_id,
        'display_name', v_msg_row.display_name,
        'message', v_msg_row.message,
        'created_at', v_msg_row.created_at
    );
END;
$$;

GRANT EXECUTE ON FUNCTION send_room_message(UUID, TEXT) TO authenticated, anon;

