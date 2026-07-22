-- Task-claim confirmations are normal timeline messages whose type name is
-- longer than the original VARCHAR(16) baseline allowed. Widen the protocol
-- column so the durable message record and its realtime shape agree.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'messages'
          AND column_name = 'msg_type'
          AND character_maximum_length < 64
    ) THEN
        ALTER TABLE messages ALTER COLUMN msg_type TYPE VARCHAR(64);
    END IF;
END $$;
