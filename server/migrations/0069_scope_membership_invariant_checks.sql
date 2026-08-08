-- Replace the global scan installed by 0068 with checks scoped to the row that
-- fired each deferred constraint trigger. The final database state is still
-- validated at COMMIT, but bulk membership changes no longer rescan every
-- channel membership once per affected row.
CREATE OR REPLACE FUNCTION enforce_human_channel_workspace_membership()
RETURNS TRIGGER AS $$
DECLARE
    affected_workspace_id VARCHAR(36);
    affected_user_id VARCHAR(36);
BEGIN
    IF TG_TABLE_NAME = 'channel_memberships' THEN
        IF TG_OP = 'DELETE' OR NEW.member_type <> 'user' THEN
            RETURN NULL;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM channel_memberships cm
            JOIN channels c ON c.channel_id = cm.channel_id
            WHERE cm.channel_id = NEW.channel_id
              AND cm.member_id = NEW.member_id
              AND cm.member_type = 'user'
              AND c.type <> 'dm'
              AND NOT EXISTS (
                  SELECT 1
                  FROM workspace_memberships wm
                  WHERE wm.workspace_id = c.workspace_id
                    AND wm.user_id = cm.member_id
                    AND wm.status = 'active'
              )
        ) THEN
            RAISE EXCEPTION 'human non-DM channel membership requires active workspace membership'
                USING ERRCODE = '23514';
        END IF;
        RETURN NULL;
    END IF;

    IF TG_TABLE_NAME = 'workspace_memberships' THEN
        IF TG_OP = 'DELETE' THEN
            affected_workspace_id := OLD.workspace_id;
            affected_user_id := OLD.user_id;
        ELSE
            affected_workspace_id := NEW.workspace_id;
            affected_user_id := NEW.user_id;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM channel_memberships cm
            JOIN channels c ON c.channel_id = cm.channel_id
            WHERE c.workspace_id = affected_workspace_id
              AND cm.member_id = affected_user_id
              AND cm.member_type = 'user'
              AND c.type <> 'dm'
              AND NOT EXISTS (
                  SELECT 1
                  FROM workspace_memberships wm
                  WHERE wm.workspace_id = affected_workspace_id
                    AND wm.user_id = affected_user_id
                    AND wm.status = 'active'
              )
        ) THEN
            RAISE EXCEPTION 'human non-DM channel membership requires active workspace membership'
                USING ERRCODE = '23514';
        END IF;

        -- A primary-key-changing UPDATE also removes the OLD workspace/user
        -- pairing, so validate that side independently.
        IF TG_OP = 'UPDATE'
           AND (OLD.workspace_id, OLD.user_id) IS DISTINCT FROM
               (NEW.workspace_id, NEW.user_id)
           AND EXISTS (
               SELECT 1
               FROM channel_memberships cm
               JOIN channels c ON c.channel_id = cm.channel_id
               WHERE c.workspace_id = OLD.workspace_id
                 AND cm.member_id = OLD.user_id
                 AND cm.member_type = 'user'
                 AND c.type <> 'dm'
                 AND NOT EXISTS (
                     SELECT 1
                     FROM workspace_memberships wm
                     WHERE wm.workspace_id = OLD.workspace_id
                       AND wm.user_id = OLD.user_id
                       AND wm.status = 'active'
                 )
           )
        THEN
            RAISE EXCEPTION 'human non-DM channel membership requires active workspace membership'
                USING ERRCODE = '23514';
        END IF;
        RETURN NULL;
    END IF;

    IF TG_TABLE_NAME = 'channels' THEN
        IF TG_OP = 'DELETE' THEN
            RETURN NULL;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM channels c
            JOIN channel_memberships cm ON cm.channel_id = c.channel_id
            WHERE c.channel_id = NEW.channel_id
              AND c.type <> 'dm'
              AND cm.member_type = 'user'
              AND NOT EXISTS (
                  SELECT 1
                  FROM workspace_memberships wm
                  WHERE wm.workspace_id = c.workspace_id
                    AND wm.user_id = cm.member_id
                    AND wm.status = 'active'
              )
        ) THEN
            RAISE EXCEPTION 'human non-DM channel membership requires active workspace membership'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
