-- Converge the platform tables onto the App Platform v1 canonical schema.
--
-- The canonical definition lives in the docs repository at
-- contracts/app-platform/v1/schema/platform-schema-v1.sql. Until it existed,
-- every app hand-wrote these tables and they drifted: this app and Vegan IQ
-- disagreed on every shared table except such_platform_native_purchase, so the
-- shared backup producer could only ever speak one of the two dialects and the
-- restore drill, which is the release promotion gate, failed on both apps on
-- consecutive days for opposite reasons.
--
-- Renames and additions only. The first draft recreated these tables from
-- scratch, and the runtime contract test correctly refused it: migrations here
-- may not contain destructive statements. That rail is right, and the migration
-- it forced is better than the one it rejected, because ALTER preserves rows
-- and is therefore safe whether or not this runtime has served a player yet.
--
-- Currency is untouched. This app's design was the better of the two and became
-- the contract: CREDIT/REVERSE/REINSTATE with a self-referencing
-- original_event_id keeps a refund pointed at the purchase it undoes, and the
-- source transaction linkage and running resulting_balance stay as they are.

\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------
ALTER TABLE such_platform_identity
    RENAME COLUMN claimed_at TO last_claimed_at;

ALTER TABLE such_platform_identity
    RENAME COLUMN created_at TO first_seen_at;

ALTER TABLE such_platform_identity
    ADD COLUMN IF NOT EXISTS last_claimed_guest_user_id uuid;

ALTER TABLE such_platform_identity
    ADD COLUMN IF NOT EXISTS last_seen_at timestamptz NOT NULL DEFAULT now();

-- ---------------------------------------------------------------------------
-- Entitlement projection
-- ---------------------------------------------------------------------------
ALTER TABLE such_platform_entitlement
    RENAME COLUMN last_sequence TO last_event_sequence;

ALTER TABLE such_platform_entitlement
    ADD COLUMN IF NOT EXISTS nakama_user_id uuid;

-- active is stored rather than derived so a read path never has to know the
-- operation vocabulary. Backfilled from the operation that produced each row,
-- which is exactly how a reader would have derived it.
ALTER TABLE such_platform_entitlement
    ADD COLUMN IF NOT EXISTS active boolean;

UPDATE such_platform_entitlement
   SET active = (upper(operation) IN ('GRANT', 'REINSTATE'))
 WHERE active IS NULL;

ALTER TABLE such_platform_entitlement
    ALTER COLUMN active SET NOT NULL;

-- source_occurred_at records when the provider says the thing happened, as
-- opposed to when we applied it. Existing rows have only effective_at, which is
-- the closest true statement available for them.
ALTER TABLE such_platform_entitlement
    ADD COLUMN IF NOT EXISTS source_occurred_at timestamptz;

UPDATE such_platform_entitlement
   SET source_occurred_at = effective_at
 WHERE source_occurred_at IS NULL;

ALTER TABLE such_platform_entitlement
    ALTER COLUMN source_occurred_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS such_platform_entitlement_active_idx
    ON such_platform_entitlement (subject_id) WHERE active;

-- ---------------------------------------------------------------------------
-- Guest claim
-- ---------------------------------------------------------------------------
ALTER TABLE such_platform_guest_claim_token
    RENAME COLUMN token_hash TO claim_token_digest;

ALTER TABLE such_platform_guest_claim_token
    RENAME COLUMN target_user_id TO consumed_by_target_user_id;

ALTER TABLE such_platform_guest_claim
    RENAME COLUMN token_hash TO claim_token_digest;

ALTER TABLE such_platform_guest_claim
    RENAME COLUMN merge_result_hash TO merge_result_digest;

-- Names which merge rule produced the result digest, so a stored digest can be
-- interpreted later without guessing which version of the merge was in force.
ALTER TABLE such_platform_guest_claim
    ADD COLUMN IF NOT EXISTS merge_contract text;

UPDATE such_platform_guest_claim
   SET merge_contract = 'such-moon-launch-progress-v1'
 WHERE merge_contract IS NULL;

ALTER TABLE such_platform_guest_claim
    ALTER COLUMN merge_contract SET NOT NULL;

-- ---------------------------------------------------------------------------
-- Legacy migration operations
-- ---------------------------------------------------------------------------
ALTER TABLE such_platform_migration_operation
    ADD COLUMN IF NOT EXISTS operation_kind text;

UPDATE such_platform_migration_operation
   SET operation_kind = 'unclassified'
 WHERE operation_kind IS NULL;

ALTER TABLE such_platform_migration_operation
    ALTER COLUMN operation_kind SET NOT NULL;

-- ---------------------------------------------------------------------------
-- Leaderboards
-- ---------------------------------------------------------------------------
-- Declares which boards this app has. Scores stay in Nakama, which already owns
-- ranking, pagination and reset schedules; duplicating that would be a second
-- ranking implementation to keep correct. The declaration exists so a board is
-- a reviewed part of a release rather than a string in game code, and so a
-- recovery generation can record which boards existed at the time.
CREATE TABLE IF NOT EXISTS such_platform_leaderboard (
    leaderboard_key text NOT NULL
        CHECK (leaderboard_key ~ '^[a-z][a-z0-9_.-]*$'),
    nakama_leaderboard_id text NOT NULL,
    display_name text NOT NULL,
    sort_order text NOT NULL
        CHECK (sort_order IN ('ASC', 'DESC')),
    operator text NOT NULL
        CHECK (operator IN ('BEST', 'SET', 'INCREMENT')),
    reset_schedule text,
    authoritative boolean NOT NULL DEFAULT true,
    contract_version integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (leaderboard_key)
);

CREATE UNIQUE INDEX IF NOT EXISTS such_platform_leaderboard_nakama_id_key
    ON such_platform_leaderboard (nakama_leaderboard_id);

-- ---------------------------------------------------------------------------
-- Functions that read the renamed columns
-- ---------------------------------------------------------------------------
-- Redefined with their logic untouched. The entitlement function additionally
-- maintains the new active and source_occurred_at columns, so the projection
-- stays correct for events applied after this migration.
CREATE OR REPLACE FUNCTION such_platform_apply_entitlement_event(
    p_event_id text,
    p_subject_id text,
    p_entitlement_key text,
    p_sequence bigint,
    p_operation text,
    p_idempotency_key text,
    p_event_digest text,
    p_effective_at timestamptz,
    p_expires_at timestamptz,
    p_source_provider text,
    p_source_occurred_at timestamptz
)
RETURNS TABLE(outcome text, last_sequence bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    existing_event such_platform_entitlement_event%ROWTYPE;
    current_sequence bigint;
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_subject_id || E'\n' || p_entitlement_key, 0)
    );

    SELECT *
      INTO existing_event
      FROM such_platform_entitlement_event
     WHERE event_id = p_event_id
        OR idempotency_key = p_idempotency_key
        OR (
            subject_id = p_subject_id
            AND entitlement_key = p_entitlement_key
            AND sequence = p_sequence
        )
     ORDER BY applied_at
     LIMIT 1;

    IF FOUND THEN
        IF existing_event.event_digest = p_event_digest
           AND existing_event.subject_id = p_subject_id
           AND existing_event.entitlement_key = p_entitlement_key
           AND existing_event.sequence = p_sequence THEN
            RETURN QUERY SELECT 'duplicate'::text, existing_event.sequence;
            RETURN;
        END IF;
        RAISE EXCEPTION 'conflicting entitlement event'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    SELECT entitlement.last_event_sequence
      INTO current_sequence
      FROM such_platform_entitlement AS entitlement
     WHERE entitlement.subject_id = p_subject_id
       AND entitlement.entitlement_key = p_entitlement_key
     FOR UPDATE;

    IF FOUND AND p_sequence <= current_sequence THEN
        RAISE EXCEPTION 'non-increasing entitlement sequence'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    INSERT INTO such_platform_entitlement_event (
        event_id,
        subject_id,
        entitlement_key,
        sequence,
        operation,
        idempotency_key,
        event_digest,
        effective_at,
        expires_at,
        source_provider,
        source_occurred_at
    ) VALUES (
        p_event_id,
        p_subject_id,
        p_entitlement_key,
        p_sequence,
        p_operation,
        p_idempotency_key,
        p_event_digest,
        p_effective_at,
        p_expires_at,
        p_source_provider,
        p_source_occurred_at
    );

    INSERT INTO such_platform_entitlement (
        subject_id,
        entitlement_key,
        operation,
        active,
        effective_at,
        expires_at,
        source_occurred_at,
        last_event_sequence,
        last_event_id,
        last_event_digest,
        updated_at
    ) VALUES (
        p_subject_id,
        p_entitlement_key,
        p_operation,
        upper(p_operation) IN ('GRANT', 'REINSTATE'),
        p_effective_at,
        p_expires_at,
        p_source_occurred_at,
        p_sequence,
        p_event_id,
        p_event_digest,
        now()
    )
    ON CONFLICT (subject_id, entitlement_key) DO UPDATE SET
        operation = excluded.operation,
        active = excluded.active,
        effective_at = excluded.effective_at,
        expires_at = excluded.expires_at,
        source_occurred_at = excluded.source_occurred_at,
        last_event_sequence = excluded.last_event_sequence,
        last_event_id = excluded.last_event_id,
        last_event_digest = excluded.last_event_digest,
        updated_at = now();

    RETURN QUERY SELECT 'applied'::text, p_sequence;
END;
$function$;

-- The guest-claim merge function reads the renamed columns. Its logic is
-- untouched and its OUTPUT column keeps the name merge_result_hash, so the
-- runtime caller needs no change: only the table columns it reads and
-- writes were renamed by this contract.
CREATE OR REPLACE FUNCTION such_moon_launch_claim_guest(
    p_token_hash text,
    p_target_user_id uuid,
    p_idempotency_key text
)
RETURNS TABLE(outcome text, merge_result_hash text)
LANGUAGE plpgsql
AS $function$
DECLARE
    existing_claim such_platform_guest_claim%ROWTYPE;
    token_record such_platform_guest_claim_token%ROWTYPE;
    guest_document jsonb := '{}'::jsonb;
    target_document jsonb := '{}'::jsonb;
    merged_document jsonb;
    result_digest text;
    target_exists boolean := false;
    wallet_conflict boolean := false;
BEGIN
    SELECT *
      INTO existing_claim
      FROM such_platform_guest_claim
     WHERE idempotency_key = p_idempotency_key
     FOR UPDATE;

    IF FOUND THEN
        IF existing_claim.claim_token_digest = p_token_hash
           AND existing_claim.target_user_id = p_target_user_id THEN
            RETURN QUERY SELECT
                'DUPLICATE'::text,
                existing_claim.merge_result_digest::text;
            RETURN;
        END IF;
        RAISE EXCEPTION 'conflicting guest-claim idempotency key'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    SELECT *
      INTO token_record
      FROM such_platform_guest_claim_token
     WHERE claim_token_digest = p_token_hash
     FOR UPDATE;

    IF NOT FOUND
       OR token_record.consumed_at IS NOT NULL
       OR token_record.expires_at <= now() THEN
        RAISE EXCEPTION 'invalid or expired guest-claim token'
            USING ERRCODE = 'invalid_authorization_specification';
    END IF;

    IF token_record.guest_user_id = p_target_user_id THEN
        RAISE EXCEPTION 'guest and target accounts must differ'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    PERFORM 1
      FROM such_platform_identity
     WHERE nakama_user_id = p_target_user_id
       AND linked_at IS NOT NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'canonical target identity is not linked'
            USING ERRCODE = 'invalid_authorization_specification';
    END IF;

    PERFORM user_id
      FROM such_moon_launch_progress
     WHERE user_id IN (token_record.guest_user_id, p_target_user_id)
     ORDER BY user_id
     FOR UPDATE;

    SELECT projection
      INTO guest_document
      FROM such_moon_launch_progress
     WHERE user_id = token_record.guest_user_id;
    IF NOT FOUND THEN
        guest_document := '{}'::jsonb;
    END IF;

    SELECT projection
      INTO target_document
      FROM such_moon_launch_progress
     WHERE user_id = p_target_user_id;
    target_exists := FOUND;
    IF NOT target_exists THEN
        target_document := '{}'::jsonb;
    END IF;

    wallet_conflict := target_exists
        AND such_moon_launch_safe_bigint(
            guest_document, 'wallet', 0, 9007199254740991
        ) > 0
        AND such_moon_launch_safe_bigint(
            guest_document, 'wallet', 0, 9007199254740991
        ) <> such_moon_launch_safe_bigint(
            target_document, 'wallet', 0, 9007199254740991
        );

    merged_document := such_moon_launch_merge_progress(
        target_document,
        guest_document,
        target_exists
    );
    result_digest := encode(
        digest(convert_to(merged_document::text, 'UTF8'), 'sha256'),
        'hex'
    );

    INSERT INTO such_moon_launch_progress (
        user_id, projection, projection_version, updated_at
    ) VALUES (
        p_target_user_id, merged_document, 1, now()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        projection = EXCLUDED.projection,
        projection_version =
            such_moon_launch_progress.projection_version + 1,
        updated_at = now();

    INSERT INTO such_moon_launch_progress (
        user_id,
        projection,
        projection_version,
        claimed_to_user_id,
        claim_state,
        updated_at
    ) VALUES (
        token_record.guest_user_id,
        guest_document,
        1,
        p_target_user_id,
        'RECOVERABLE_TOMBSTONE',
        now()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        claimed_to_user_id = EXCLUDED.claimed_to_user_id,
        claim_state = EXCLUDED.claim_state,
        updated_at = now();

    INSERT INTO such_platform_guest_claim (
        idempotency_key,
        claim_token_digest,
        guest_user_id,
        target_user_id,
        state,
        merge_contract,
        merge_result_digest,
        conflict,
        completed_at
    ) VALUES (
        p_idempotency_key,
        p_token_hash,
        token_record.guest_user_id,
        p_target_user_id,
        'APPLIED',
        'such-moon-launch-progress-v1',
        result_digest,
        jsonb_build_object('wallet_conflict', wallet_conflict),
        now()
    );

    UPDATE such_platform_guest_claim_token
       SET consumed_at = now(),
           target_user_id = p_target_user_id
     WHERE claim_token_digest = p_token_hash;

    UPDATE such_platform_identity
       SET claimed_at = now()
     WHERE nakama_user_id = p_target_user_id;

    RETURN QUERY SELECT 'APPLIED'::text, result_digest;
END;
$function$;

INSERT INTO such_platform_schema_migration
    (schema_version, migration_id, contract_version)
VALUES (5, '005_platform_schema_v1_convergence', 1)
ON CONFLICT (schema_version) DO NOTHING;

COMMIT;
