\set ON_ERROR_STOP on

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS such_platform_schema_migration (
    schema_version integer PRIMARY KEY CHECK (schema_version >= 1),
    migration_id text NOT NULL UNIQUE,
    contract_version integer NOT NULL CHECK (contract_version >= 1),
    applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS such_platform_identity (
    subject_id text PRIMARY KEY
        CHECK (octet_length(subject_id) BETWEEN 1 AND 255),
    canonical_auth_id varchar(128) NOT NULL UNIQUE
        CHECK (canonical_auth_id ~ '^[a-z0-9-]{6,128}$'),
    nakama_user_id uuid UNIQUE,
    idp_verified_at timestamptz NOT NULL DEFAULT now(),
    linked_at timestamptz,
    claimed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
        (nakama_user_id IS NULL AND linked_at IS NULL)
        OR (nakama_user_id IS NOT NULL AND linked_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS such_platform_entitlement (
    subject_id text NOT NULL,
    entitlement_key varchar(128) NOT NULL
        CHECK (entitlement_key ~ '^[a-z][a-z0-9_.-]*$'),
    operation varchar(16) NOT NULL
        CHECK (operation IN ('GRANT', 'REVOKE', 'REINSTATE')),
    effective_at timestamptz NOT NULL,
    expires_at timestamptz,
    last_sequence bigint NOT NULL CHECK (last_sequence >= 1),
    last_event_id text NOT NULL,
    last_event_digest char(64) NOT NULL
        CHECK (last_event_digest ~ '^[0-9a-f]{64}$'),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (subject_id, entitlement_key)
);

CREATE TABLE IF NOT EXISTS such_platform_entitlement_event (
    event_id text PRIMARY KEY,
    subject_id text NOT NULL,
    entitlement_key varchar(128) NOT NULL,
    sequence bigint NOT NULL CHECK (sequence >= 1),
    operation varchar(16) NOT NULL
        CHECK (operation IN ('GRANT', 'REVOKE', 'REINSTATE')),
    idempotency_key text NOT NULL UNIQUE,
    event_digest char(64) NOT NULL
        CHECK (event_digest ~ '^[0-9a-f]{64}$'),
    effective_at timestamptz NOT NULL,
    expires_at timestamptz,
    source_provider varchar(32) NOT NULL,
    source_occurred_at timestamptz NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (subject_id, entitlement_key, sequence)
);

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
            RETURN QUERY SELECT 'DUPLICATE'::text, existing_event.sequence;
            RETURN;
        END IF;
        RAISE EXCEPTION 'conflicting entitlement event'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    SELECT entitlement.last_sequence
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
        effective_at,
        expires_at,
        last_sequence,
        last_event_id,
        last_event_digest,
        updated_at
    ) VALUES (
        p_subject_id,
        p_entitlement_key,
        p_operation,
        p_effective_at,
        p_expires_at,
        p_sequence,
        p_event_id,
        p_event_digest,
        now()
    )
    ON CONFLICT (subject_id, entitlement_key) DO UPDATE SET
        operation = EXCLUDED.operation,
        effective_at = EXCLUDED.effective_at,
        expires_at = EXCLUDED.expires_at,
        last_sequence = EXCLUDED.last_sequence,
        last_event_id = EXCLUDED.last_event_id,
        last_event_digest = EXCLUDED.last_event_digest,
        updated_at = now();

    RETURN QUERY SELECT 'APPLIED'::text, p_sequence;
END;
$function$;

CREATE TABLE IF NOT EXISTS such_platform_guest_claim_token (
    token_hash char(64) PRIMARY KEY
        CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    guest_user_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz,
    target_user_id uuid,
    CHECK (
        (consumed_at IS NULL AND target_user_id IS NULL)
        OR (consumed_at IS NOT NULL AND target_user_id IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS such_platform_guest_claim (
    idempotency_key text PRIMARY KEY,
    token_hash char(64) NOT NULL UNIQUE,
    guest_user_id uuid NOT NULL,
    target_user_id uuid NOT NULL,
    state varchar(16) NOT NULL CHECK (state IN ('APPLIED', 'CONFLICT')),
    merge_result_hash char(64) NOT NULL
        CHECK (merge_result_hash ~ '^[0-9a-f]{64}$'),
    conflict jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz NOT NULL DEFAULT now(),
    CHECK (guest_user_id <> target_user_id)
);

CREATE TABLE IF NOT EXISTS such_moon_launch_progress (
    user_id uuid PRIMARY KEY,
    projection jsonb NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(projection) = 'object'),
    projection_version bigint NOT NULL DEFAULT 1
        CHECK (projection_version >= 1),
    claimed_to_user_id uuid,
    claim_state varchar(24),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
        (claimed_to_user_id IS NULL AND claim_state IS NULL)
        OR (
            claimed_to_user_id IS NOT NULL
            AND claim_state = 'RECOVERABLE_TOMBSTONE'
        )
    )
);

CREATE OR REPLACE FUNCTION such_moon_launch_safe_bigint(
    p_document jsonb,
    p_key text,
    p_default bigint,
    p_maximum bigint
)
RETURNS bigint
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
    raw_value text;
    parsed_value numeric;
BEGIN
    IF jsonb_typeof(p_document) <> 'object' THEN
        RETURN p_default;
    END IF;
    raw_value := p_document ->> p_key;
    IF raw_value IS NULL OR raw_value !~ '^[0-9]{1,24}$' THEN
        RETURN p_default;
    END IF;
    parsed_value := raw_value::numeric;
    RETURN LEAST(parsed_value, p_maximum)::bigint;
EXCEPTION WHEN numeric_value_out_of_range THEN
    RETURN p_default;
END;
$function$;

CREATE OR REPLACE FUNCTION such_moon_launch_safe_double(
    p_document jsonb,
    p_key text,
    p_default double precision,
    p_maximum double precision
)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
    raw_value text;
    parsed_value double precision;
BEGIN
    IF jsonb_typeof(p_document) <> 'object' THEN
        RETURN p_default;
    END IF;
    raw_value := p_document ->> p_key;
    IF raw_value IS NULL
       OR raw_value !~ '^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$' THEN
        RETURN p_default;
    END IF;
    parsed_value := raw_value::double precision;
    IF parsed_value <= 0 THEN
        RETURN p_default;
    END IF;
    RETURN LEAST(parsed_value, p_maximum);
EXCEPTION WHEN numeric_value_out_of_range THEN
    RETURN p_default;
END;
$function$;

CREATE OR REPLACE FUNCTION such_moon_launch_safe_boolean(
    p_document jsonb,
    p_key text,
    p_default boolean
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT CASE
        WHEN jsonb_typeof(p_document) <> 'object' THEN p_default
        WHEN jsonb_typeof(p_document -> p_key) = 'boolean'
            THEN (p_document ->> p_key)::boolean
        ELSE p_default
    END
$function$;

CREATE OR REPLACE FUNCTION such_moon_launch_merge_progress(
    p_target jsonb,
    p_guest jsonb,
    p_target_exists boolean
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
    target_document jsonb := COALESCE(p_target, '{}'::jsonb);
    guest_document jsonb := COALESCE(p_guest, '{}'::jsonb);
    merged_stars jsonb := '{}'::jsonb;
    merged_times jsonb := '{}'::jsonb;
    merged_upgrades jsonb := '{}'::jsonb;
    merged_skins jsonb;
    merged_hints jsonb;
    allowed_skins text[] := ARRAY[
        'default', 'retro', 'stealth', 'gold', 'alien', 'wownero',
        'monero', 'bitcoin', 'litecoin', 'champion', 'skull',
        'crystalbeetle', 'steamboat'
    ];
    upgrade_keys text[] := ARRAY[
        'thrust', 'fuel_capacity', 'fuel_efficiency', 'armor',
        'landing_gear', 'shield', 'rotation', 'reverse_thrust',
        'magnet', 'cannon', 'missile', 'laser', 'emp'
    ];
    key_name text;
    level_number integer;
    target_integer bigint;
    guest_integer bigint;
    target_time double precision;
    guest_time double precision;
    chosen_time double precision;
    selected_skin text;
    nickname text;
    settings_document jsonb;
BEGIN
    IF jsonb_typeof(target_document) <> 'object' THEN
        target_document := '{}'::jsonb;
    END IF;
    IF jsonb_typeof(guest_document) <> 'object' THEN
        guest_document := '{}'::jsonb;
    END IF;

    FOR level_number IN 1..12 LOOP
        key_name := level_number::text;
        target_integer := such_moon_launch_safe_bigint(
            COALESCE(target_document -> 'best_stars', '{}'::jsonb),
            key_name, 0, 3
        );
        guest_integer := such_moon_launch_safe_bigint(
            COALESCE(guest_document -> 'best_stars', '{}'::jsonb),
            key_name, 0, 3
        );
        IF GREATEST(target_integer, guest_integer) > 0 THEN
            merged_stars := jsonb_set(
                merged_stars,
                ARRAY[key_name],
                to_jsonb(GREATEST(target_integer, guest_integer)),
                true
            );
        END IF;

        target_time := such_moon_launch_safe_double(
            COALESCE(target_document -> 'best_times', '{}'::jsonb),
            key_name, 0, 86400
        );
        guest_time := such_moon_launch_safe_double(
            COALESCE(guest_document -> 'best_times', '{}'::jsonb),
            key_name, 0, 86400
        );
        chosen_time := CASE
            WHEN target_time > 0 AND guest_time > 0
                THEN LEAST(target_time, guest_time)
            ELSE GREATEST(target_time, guest_time)
        END;
        IF chosen_time > 0 THEN
            merged_times := jsonb_set(
                merged_times,
                ARRAY[key_name],
                to_jsonb(chosen_time),
                true
            );
        END IF;
    END LOOP;

    FOREACH key_name IN ARRAY upgrade_keys LOOP
        target_integer := such_moon_launch_safe_bigint(
            COALESCE(target_document -> 'upgrades', '{}'::jsonb),
            key_name, 0, 5
        );
        guest_integer := such_moon_launch_safe_bigint(
            COALESCE(guest_document -> 'upgrades', '{}'::jsonb),
            key_name, 0, 5
        );
        merged_upgrades := jsonb_set(
            merged_upgrades,
            ARRAY[key_name],
            to_jsonb(GREATEST(target_integer, guest_integer)),
            true
        );
    END LOOP;

    WITH skin_candidates AS (
        SELECT skin
          FROM jsonb_array_elements_text(
              CASE WHEN jsonb_typeof(target_document -> 'owned_skins') = 'array'
                  THEN target_document -> 'owned_skins' ELSE '[]'::jsonb END
          ) AS target_skin(skin)
        UNION
        SELECT skin
          FROM jsonb_array_elements_text(
              CASE WHEN jsonb_typeof(guest_document -> 'owned_skins') = 'array'
                  THEN guest_document -> 'owned_skins' ELSE '[]'::jsonb END
          ) AS guest_skin(skin)
        UNION
        SELECT 'default'
    )
    SELECT jsonb_agg(skin ORDER BY skin)
      INTO merged_skins
      FROM (
          SELECT DISTINCT skin
            FROM skin_candidates
           WHERE skin = ANY(allowed_skins)
      ) AS valid_skins;

    WITH hint_candidates AS (
        SELECT hint
          FROM jsonb_array_elements_text(
              CASE WHEN jsonb_typeof(target_document -> 'seen_hints') = 'array'
                  THEN target_document -> 'seen_hints' ELSE '[]'::jsonb END
          ) AS target_hint(hint)
        UNION
        SELECT hint
          FROM jsonb_array_elements_text(
              CASE WHEN jsonb_typeof(guest_document -> 'seen_hints') = 'array'
                  THEN guest_document -> 'seen_hints' ELSE '[]'::jsonb END
          ) AS guest_hint(hint)
    )
    SELECT COALESCE(jsonb_agg(hint ORDER BY hint), '[]'::jsonb)
      INTO merged_hints
      FROM (
          SELECT DISTINCT hint
            FROM hint_candidates
           WHERE length(hint) BETWEEN 1 AND 128
             AND hint ~ '^[A-Za-z0-9_.-]+$'
           ORDER BY hint
           LIMIT 128
      ) AS valid_hints;

    selected_skin := CASE
        WHEN p_target_exists
             AND target_document ->> 'selected_skin' IS NOT NULL
             AND merged_skins ? (target_document ->> 'selected_skin')
            THEN target_document ->> 'selected_skin'
        WHEN guest_document ->> 'selected_skin' IS NOT NULL
             AND merged_skins ? (guest_document ->> 'selected_skin')
            THEN guest_document ->> 'selected_skin'
        ELSE 'default'
    END;

    nickname := CASE
        WHEN p_target_exists
             AND length(COALESCE(target_document ->> 'nickname', '')) BETWEEN 1 AND 64
            THEN target_document ->> 'nickname'
        WHEN length(COALESCE(guest_document ->> 'nickname', '')) BETWEEN 1 AND 64
            THEN guest_document ->> 'nickname'
        ELSE 'Cosmonaut'
    END;

    settings_document := CASE WHEN p_target_exists
        THEN target_document ELSE guest_document END;

    RETURN jsonb_build_object(
        'level', LEAST(12, GREATEST(
            such_moon_launch_safe_bigint(target_document, 'level', 1, 12),
            such_moon_launch_safe_bigint(guest_document, 'level', 1, 12)
        )),
        'highest_completed', LEAST(12, GREATEST(
            such_moon_launch_safe_bigint(
                target_document, 'highest_completed', 0, 12
            ),
            such_moon_launch_safe_bigint(
                guest_document, 'highest_completed', 0, 12
            )
        )),
        'completed',
            such_moon_launch_safe_boolean(target_document, 'completed', false)
            OR such_moon_launch_safe_boolean(
                guest_document, 'completed', false
            ),
        'wallet', CASE WHEN p_target_exists
            THEN such_moon_launch_safe_bigint(
                target_document, 'wallet', 0, 9007199254740991
            )
            ELSE such_moon_launch_safe_bigint(
                guest_document, 'wallet', 0, 9007199254740991
            ) END,
        'upgrades', merged_upgrades,
        'best_times', merged_times,
        'best_stars', merged_stars,
        'nickname', nickname,
        'tutorial_shown',
            such_moon_launch_safe_boolean(
                target_document, 'tutorial_shown', false
            )
            OR such_moon_launch_safe_boolean(
                guest_document, 'tutorial_shown', false
            ),
        'welcome_shown',
            such_moon_launch_safe_boolean(
                target_document, 'welcome_shown', false
            )
            OR such_moon_launch_safe_boolean(
                guest_document, 'welcome_shown', false
            ),
        'seen_hints', merged_hints,
        'difficulty', LEAST(2, such_moon_launch_safe_bigint(
            settings_document, 'difficulty', 1, 2
        )),
        'control_scheme', LEAST(2, such_moon_launch_safe_bigint(
            settings_document, 'control_scheme', 0, 2
        )),
        'orientation_pref', LEAST(1, such_moon_launch_safe_bigint(
            settings_document, 'orientation_pref', 0, 1
        )),
        'desktop_control', LEAST(1, such_moon_launch_safe_bigint(
            settings_document, 'desktop_control', 0, 1
        )),
        'tilt_sensitivity', LEAST(4, GREATEST(1,
            such_moon_launch_safe_double(
                settings_document, 'tilt_sensitivity', 2, 4
            )
        )),
        'music_enabled', such_moon_launch_safe_boolean(
            settings_document, 'music_enabled', true
        ),
        'selected_skin', selected_skin,
        'owned_skins', merged_skins,
        'endless_best_wave', GREATEST(
            such_moon_launch_safe_bigint(
                target_document, 'endless_best_wave', 0, 9007199254740991
            ),
            such_moon_launch_safe_bigint(
                guest_document, 'endless_best_wave', 0, 9007199254740991
            )
        ),
        'levels_unlocked',
            such_moon_launch_safe_boolean(
                target_document, 'levels_unlocked', false
            )
            OR such_moon_launch_safe_boolean(
                guest_document, 'levels_unlocked', false
            ),
        'total_crypto_earned', GREATEST(
            such_moon_launch_safe_bigint(
                target_document, 'total_crypto_earned', 0, 9007199254740991
            ),
            such_moon_launch_safe_bigint(
                guest_document, 'total_crypto_earned', 0, 9007199254740991
            )
        ),
        'total_deaths', GREATEST(
            such_moon_launch_safe_bigint(
                target_document, 'total_deaths', 0, 9007199254740991
            ),
            such_moon_launch_safe_bigint(
                guest_document, 'total_deaths', 0, 9007199254740991
            )
        ),
        'landings_since_install', GREATEST(
            such_moon_launch_safe_bigint(
                target_document, 'landings_since_install', 0, 9007199254740991
            ),
            such_moon_launch_safe_bigint(
                guest_document, 'landings_since_install', 0, 9007199254740991
            )
        ),
        'rate_prompt_shown',
            such_moon_launch_safe_boolean(
                target_document, 'rate_prompt_shown', false
            )
            OR such_moon_launch_safe_boolean(
                guest_document, 'rate_prompt_shown', false
            )
    );
END;
$function$;

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
        IF existing_claim.token_hash = p_token_hash
           AND existing_claim.target_user_id = p_target_user_id THEN
            RETURN QUERY SELECT
                'DUPLICATE'::text,
                existing_claim.merge_result_hash::text;
            RETURN;
        END IF;
        RAISE EXCEPTION 'conflicting guest-claim idempotency key'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    SELECT *
      INTO token_record
      FROM such_platform_guest_claim_token
     WHERE token_hash = p_token_hash
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
        token_hash,
        guest_user_id,
        target_user_id,
        state,
        merge_result_hash,
        conflict
    ) VALUES (
        p_idempotency_key,
        p_token_hash,
        token_record.guest_user_id,
        p_target_user_id,
        'APPLIED',
        result_digest,
        jsonb_build_object('wallet_conflict', wallet_conflict)
    );

    UPDATE such_platform_guest_claim_token
       SET consumed_at = now(),
           target_user_id = p_target_user_id
     WHERE token_hash = p_token_hash;

    UPDATE such_platform_identity
       SET claimed_at = now()
     WHERE nakama_user_id = p_target_user_id;

    RETURN QUERY SELECT 'APPLIED'::text, result_digest;
END;
$function$;

CREATE TABLE IF NOT EXISTS such_platform_migration_operation (
    operation_id text PRIMARY KEY,
    legacy_source text NOT NULL,
    source_record_id text NOT NULL,
    payload_digest char(64) NOT NULL
        CHECK (payload_digest ~ '^[0-9a-f]{64}$'),
    state varchar(24) NOT NULL
        CHECK (state IN ('PENDING', 'APPLIED', 'RETRY', 'CONFLICT')),
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    last_error_code text,
    reconciliation_digest char(64),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (legacy_source, source_record_id)
);

INSERT INTO such_platform_schema_migration (
    schema_version,
    migration_id,
    contract_version
) VALUES (
    1,
    '001_app_platform_v1',
    1
)
ON CONFLICT (schema_version) DO NOTHING;

COMMIT;
