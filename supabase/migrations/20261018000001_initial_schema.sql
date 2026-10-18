-- ====================================================================
-- MIGRATION: 20261018000001_initial_schema.sql
-- Two of Us - Initial Schema, RLS Policies, Functions, & Seeds
-- Note: If you already ran schema.sql in the Supabase SQL Editor,
-- this migration matches the initial state and should not be re-run manually.
-- ====================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. TABLES DEFINITION
CREATE TABLE IF NOT EXISTS rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(6) UNIQUE NOT NULL,
    host_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    selected_game TEXT,
    status TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'in_progress', 'completed', 'abandoned')),
    max_participants INT NOT NULL DEFAULT 2,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE TABLE IF NOT EXISTS room_participants (
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

CREATE TABLE IF NOT EXISTS question_banks (
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
    options JSONB,
    correct_option_index INT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE TABLE IF NOT EXISTS custom_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    game_type TEXT NOT NULL,
    prompt TEXT NOT NULL,
    options JSONB,
    correct_option_index INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE TABLE IF NOT EXISTS game_sessions (
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

CREATE TABLE IF NOT EXISTS game_rounds (
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

CREATE TABLE IF NOT EXISTS player_answers (
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

CREATE TABLE IF NOT EXISTS scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    score INT NOT NULL DEFAULT 0,
    matches_count INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    CONSTRAINT uq_session_user UNIQUE (session_id, user_id)
);

-- 3. INDEXES
CREATE INDEX IF NOT EXISTS idx_rooms_code ON rooms(code);
CREATE INDEX IF NOT EXISTS idx_room_participants_room_id ON room_participants(room_id);
CREATE INDEX IF NOT EXISTS idx_room_participants_user_id ON room_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_game_sessions_room_id ON game_sessions(room_id);
CREATE INDEX IF NOT EXISTS idx_game_rounds_session_id ON game_rounds(session_id);
CREATE INDEX IF NOT EXISTS idx_player_answers_round_id ON player_answers(round_id);
CREATE INDEX IF NOT EXISTS idx_player_answers_user_id ON player_answers(user_id);
CREATE INDEX IF NOT EXISTS idx_scores_session_id ON scores(session_id);
CREATE INDEX IF NOT EXISTS idx_question_banks_game_type ON question_banks(game_type);

-- 4. ROW LEVEL SECURITY
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE question_banks ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE scores ENABLE ROW LEVEL SECURITY;

-- 5. REPLICA IDENTITY FOR REALTIME
ALTER TABLE rooms REPLICA IDENTITY FULL;
ALTER TABLE room_participants REPLICA IDENTITY FULL;
ALTER TABLE game_sessions REPLICA IDENTITY FULL;
ALTER TABLE game_rounds REPLICA IDENTITY FULL;
ALTER TABLE player_answers REPLICA IDENTITY FULL;
ALTER TABLE scores REPLICA IDENTITY FULL;
