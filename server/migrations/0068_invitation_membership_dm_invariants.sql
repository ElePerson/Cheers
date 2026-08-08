-- Invitation/notification expansion and workspace-first membership enforcement.
--
-- A bot remains channel-scoped.  Inviting a bot owned by somebody else creates
-- one pending owner approval here; accepting it materializes the ordinary
-- channel_memberships row and primary session.
CREATE TABLE IF NOT EXISTS bot_channel_invites (
    channel_id          VARCHAR(36) NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    bot_id              VARCHAR(36) NOT NULL REFERENCES bot_accounts(bot_id) ON DELETE CASCADE,
    owner_user_id       VARCHAR(36) NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    invited_by          VARCHAR(36) NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    role                VARCHAR(16) NOT NULL DEFAULT 'member',
    cwd                 TEXT,
    additional_dirs     JSONB NOT NULL DEFAULT '[]'::jsonb,
    invited_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (channel_id, bot_id),
    CONSTRAINT chk_bot_channel_invites_role CHECK (role IN ('member', 'readonly')),
    CONSTRAINT chk_bot_channel_invites_additional_dirs_array
        CHECK (jsonb_typeof(additional_dirs) = 'array')
);

CREATE INDEX IF NOT EXISTS ix_bot_channel_invites_owner
    ON bot_channel_invites(owner_user_id, invited_at DESC);

-- Remove legacy human channel access that outlived (or pre-dated) active
-- workspace membership.  Pending channel invitations grant no access and are
-- intentionally retained: the two-stage private-channel flow queues them until
-- the workspace invitation is accepted.
DELETE FROM approval_delegations ad
WHERE EXISTS (
    SELECT 1
    FROM channel_memberships cm
    JOIN channels c ON c.channel_id = cm.channel_id
    LEFT JOIN workspace_memberships wm
      ON wm.workspace_id = c.workspace_id
     AND wm.user_id = cm.member_id
     AND wm.status = 'active'
    WHERE cm.channel_id = ad.channel_id
      AND cm.member_id = ad.user_id
      AND cm.member_type = 'user'
      AND c.type <> 'dm'
      AND wm.user_id IS NULL
);

DELETE FROM bot_event_access bea
WHERE bea.subject_kind = 'user'
  AND EXISTS (
    SELECT 1
    FROM channel_memberships cm
    JOIN channels c ON c.channel_id = cm.channel_id
    LEFT JOIN workspace_memberships wm
      ON wm.workspace_id = c.workspace_id
     AND wm.user_id = cm.member_id
     AND wm.status = 'active'
    WHERE cm.channel_id = bea.channel_id
      AND cm.member_id = bea.subject_id
      AND cm.member_type = 'user'
      AND c.type <> 'dm'
      AND wm.user_id IS NULL
  );

DELETE FROM channel_memberships cm
USING channels c
WHERE cm.channel_id = c.channel_id
  AND cm.member_type = 'user'
  AND c.type <> 'dm'
  AND NOT EXISTS (
      SELECT 1 FROM workspace_memberships wm
      WHERE wm.workspace_id = c.workspace_id
        AND wm.user_id = cm.member_id
        AND wm.status = 'active'
  );

-- A channel made ownerless by the legacy cleanup is kept for audit/recovery but
-- removed from normal listings.  Account-compliance cleanup already uses the
-- same archived_at contract.
UPDATE channels c
SET archived_at = COALESCE(c.archived_at, NOW())
WHERE c.type <> 'dm'
  AND c.archived_at IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM channel_memberships cm
      WHERE cm.channel_id = c.channel_id
        AND cm.member_type = 'user'
        AND cm.role = 'owner'
  );

-- Cross-table invariants cannot be expressed as a CHECK constraint.  A deferred
-- constraint trigger lets application transactions remove channel memberships
-- before removing the workspace row while still rejecting an invalid final
-- state at COMMIT.
CREATE OR REPLACE FUNCTION enforce_human_channel_workspace_membership()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM channel_memberships cm
        JOIN channels c ON c.channel_id = cm.channel_id
        LEFT JOIN workspace_memberships wm
          ON wm.workspace_id = c.workspace_id
         AND wm.user_id = cm.member_id
         AND wm.status = 'active'
        WHERE cm.member_type = 'user'
          AND c.type <> 'dm'
          AND wm.user_id IS NULL
    ) THEN
        RAISE EXCEPTION 'human non-DM channel membership requires active workspace membership'
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_channel_membership_workspace_invariant ON channel_memberships;
CREATE CONSTRAINT TRIGGER trg_channel_membership_workspace_invariant
AFTER INSERT OR UPDATE OR DELETE ON channel_memberships
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_human_channel_workspace_membership();

DROP TRIGGER IF EXISTS trg_workspace_membership_channel_invariant ON workspace_memberships;
CREATE CONSTRAINT TRIGGER trg_workspace_membership_channel_invariant
AFTER INSERT OR UPDATE OR DELETE ON workspace_memberships
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_human_channel_workspace_membership();

DROP TRIGGER IF EXISTS trg_channel_workspace_invariant ON channels;
CREATE CONSTRAINT TRIGGER trg_channel_workspace_invariant
AFTER INSERT OR UPDATE OR DELETE ON channels
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_human_channel_workspace_membership();
