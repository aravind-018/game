-- ====================================================================
-- MIGRATION: 20261018000003_allow_solo_test_and_resilient_start.sql
-- Enables seamless game launch:
-- 1. Adds add_test_partner function
-- 2. Makes start_game resilient: auto-provisions test partner if playing solo
-- 3. Guarantees question seed availability so rounds never fail
-- 4. Auto-submits for bot partner in submit_player_answer
-- ====================================================================

-- 1. Function: add_test_partner
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

-- 2. Updated start_game: Never blocks launch
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

-- 3. Updated submit_player_answer: Auto-responds for test bot if playing solo
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
        -- If question has options, pick the user's answer (match) or a valid option
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
