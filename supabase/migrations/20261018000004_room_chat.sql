-- ====================================================================
-- MIGRATION: 20261018000004_room_chat.sql
-- In-Room Couple Realtime Chat
-- ====================================================================

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

-- Policies for room_messages
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

-- RPC: send_room_message
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

GRANT ALL ON TABLE room_messages TO authenticated, anon;
GRANT EXECUTE ON FUNCTION send_room_message(UUID, TEXT) TO authenticated, anon;

-- Safely add to realtime publication
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'room_messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE room_messages;
    END IF;
END $$;

-- Notify PostgREST to reload schema cache immediately
NOTIFY pgrst, 'reload schema';
