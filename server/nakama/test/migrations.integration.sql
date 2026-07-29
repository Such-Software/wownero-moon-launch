\set ON_ERROR_STOP on

BEGIN;

DO $test$
DECLARE
    result record;
    conflict_rejected boolean := false;
BEGIN
    SELECT *
      INTO result
      FROM such_platform_apply_entitlement_event(
          '01MOONLAUNCHPGGRANT',
          'usr_01MOONLAUNCHPGSUBJECT',
          'premium',
          1,
          'GRANT',
          'test:moon:pg:grant:premium',
          repeat('a', 64),
          '2026-07-29T15:00:00Z',
          NULL,
          'test',
          '2026-07-29T14:59:58Z'
      );
    IF result.outcome <> 'APPLIED' OR result.last_sequence <> 1 THEN
        RAISE EXCEPTION 'initial entitlement projection did not apply';
    END IF;

    SELECT *
      INTO result
      FROM such_platform_apply_entitlement_event(
          '01MOONLAUNCHPGGRANT',
          'usr_01MOONLAUNCHPGSUBJECT',
          'premium',
          1,
          'GRANT',
          'test:moon:pg:grant:premium',
          repeat('a', 64),
          '2026-07-29T15:00:00Z',
          NULL,
          'test',
          '2026-07-29T14:59:58Z'
      );
    IF result.outcome <> 'DUPLICATE' OR result.last_sequence <> 1 THEN
        RAISE EXCEPTION 'byte-identical entitlement replay was not idempotent';
    END IF;

    BEGIN
        PERFORM *
          FROM such_platform_apply_entitlement_event(
              '01MOONLAUNCHPGCONFLICT',
              'usr_01MOONLAUNCHPGSUBJECT',
              'premium',
              1,
              'REVOKE',
              'test:moon:pg:conflict:premium',
              repeat('b', 64),
              '2026-07-29T15:01:00Z',
              NULL,
              'test',
              '2026-07-29T15:00:58Z'
          );
    EXCEPTION WHEN integrity_constraint_violation THEN
        conflict_rejected := true;
    END;
    IF NOT conflict_rejected THEN
        RAISE EXCEPTION 'same-sequence conflicting event was accepted';
    END IF;

    PERFORM *
      FROM such_platform_apply_entitlement_event(
          '01MOONLAUNCHPGREVOKE',
          'usr_01MOONLAUNCHPGSUBJECT',
          'premium',
          2,
          'REVOKE',
          'test:moon:pg:revoke:premium',
          repeat('c', 64),
          '2026-07-29T15:02:00Z',
          NULL,
          'test',
          '2026-07-29T15:01:58Z'
      );
    PERFORM *
      FROM such_platform_apply_entitlement_event(
          '01MOONLAUNCHPGREINSTATE',
          'usr_01MOONLAUNCHPGSUBJECT',
          'premium',
          3,
          'REINSTATE',
          'test:moon:pg:reinstate:premium',
          repeat('d', 64),
          '2026-07-29T15:03:00Z',
          NULL,
          'test',
          '2026-07-29T15:02:58Z'
      );
END;
$test$;

DO $test$
DECLARE
    current_operation text;
    current_sequence bigint;
BEGIN
    SELECT operation, last_sequence
      INTO current_operation, current_sequence
      FROM such_platform_entitlement
     WHERE subject_id = 'usr_01MOONLAUNCHPGSUBJECT'
       AND entitlement_key = 'premium';
    IF current_operation <> 'REINSTATE' OR current_sequence <> 3 THEN
        RAISE EXCEPTION 'entitlement replay did not converge';
    END IF;
END;
$test$;

INSERT INTO such_platform_identity (
    subject_id,
    canonical_auth_id,
    nakama_user_id,
    linked_at
) VALUES (
    'usr_01MOONLAUNCHTARGET',
    'moon-launch-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    '11111111-1111-4111-8111-111111111111',
    now()
);

INSERT INTO such_platform_guest_claim_token (
    token_hash,
    guest_user_id,
    expires_at
) VALUES (
    repeat('e', 64),
    '22222222-2222-4222-8222-222222222222',
    now() + interval '10 minutes'
);

INSERT INTO such_moon_launch_progress (user_id, projection)
VALUES (
    '22222222-2222-4222-8222-222222222222',
    '{
      "level": 6,
      "highest_completed": 5,
      "wallet": 99,
      "upgrades": {"thrust": 4, "shield": 2},
      "best_times": {"1": 18.5, "2": 30.0},
      "best_stars": {"1": 3, "2": 2},
      "nickname": "GuestPilot",
      "owned_skins": ["default", "wownero"],
      "selected_skin": "wownero",
      "endless_best_wave": 8,
      "total_crypto_earned": 1200,
      "total_deaths": 12,
      "landings_since_install": 20,
      "ads_removed": true
    }'::jsonb
), (
    '11111111-1111-4111-8111-111111111111',
    '{
      "level": 4,
      "highest_completed": 3,
      "wallet": 10,
      "upgrades": {"thrust": 2, "armor": 3},
      "best_times": {"1": 20.0, "2": 25.0},
      "best_stars": {"1": 2, "2": 3},
      "nickname": "TargetPilot",
      "owned_skins": ["default", "retro"],
      "selected_skin": "retro",
      "endless_best_wave": 3,
      "total_crypto_earned": 500,
      "total_deaths": 30,
      "landings_since_install": 4,
      "ads_removed": false
    }'::jsonb
);

DO $test$
DECLARE
    result record;
    merged jsonb;
    tombstone_target uuid;
BEGIN
    SELECT *
      INTO result
      FROM such_moon_launch_claim_guest(
          repeat('e', 64),
          '11111111-1111-4111-8111-111111111111',
          'claim:moon:postgres:integration'
      );
    IF result.outcome <> 'APPLIED'
       OR result.merge_result_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'guest claim did not apply';
    END IF;

    SELECT *
      INTO result
      FROM such_moon_launch_claim_guest(
          repeat('e', 64),
          '11111111-1111-4111-8111-111111111111',
          'claim:moon:postgres:integration'
      );
    IF result.outcome <> 'DUPLICATE' THEN
        RAISE EXCEPTION 'guest claim replay was not idempotent';
    END IF;

    SELECT projection
      INTO merged
      FROM such_moon_launch_progress
     WHERE user_id = '11111111-1111-4111-8111-111111111111';

    IF merged ->> 'highest_completed' <> '5'
       OR merged ->> 'wallet' <> '10'
       OR merged #>> '{upgrades,thrust}' <> '4'
       OR merged #>> '{best_times,1}' <> '18.5'
       OR merged #>> '{best_stars,2}' <> '3'
       OR merged ->> 'endless_best_wave' <> '8'
       OR merged ->> 'total_deaths' <> '30'
       OR NOT (merged -> 'owned_skins' ? 'wownero')
       OR NOT (merged -> 'owned_skins' ? 'retro')
       OR merged ->> 'selected_skin' <> 'retro'
       OR merged ? 'ads_removed' THEN
        RAISE EXCEPTION 'guest merge invariants failed: %', merged;
    END IF;

    SELECT claimed_to_user_id
      INTO tombstone_target
      FROM such_moon_launch_progress
     WHERE user_id = '22222222-2222-4222-8222-222222222222'
       AND claim_state = 'RECOVERABLE_TOMBSTONE';
    IF tombstone_target <> '11111111-1111-4111-8111-111111111111' THEN
        RAISE EXCEPTION 'recoverable guest tombstone was not preserved';
    END IF;
END;
$test$;

DO $test$
DECLARE
    guest_count integer;
    second_guest_count integer;
    invalid_room_rejected boolean := false;
BEGIN
    INSERT INTO such_moon_launch_friendly_room (
        room_code,
        match_id,
        host_user_id,
        protocol_version,
        max_players,
        expires_at
    ) VALUES (
        'MN2P42',
        'relayed.match-postgres',
        '11111111-1111-4111-8111-111111111111',
        1,
        2,
        now() + interval '10 minutes'
    );

    UPDATE such_moon_launch_friendly_room
       SET guest_user_id = COALESCE(
               guest_user_id,
               '22222222-2222-4222-8222-222222222222'
           ),
           updated_at = now()
     WHERE room_code = 'MN2P42'
       AND state = 'OPEN'
       AND expires_at > now()
       AND host_user_id <> '22222222-2222-4222-8222-222222222222'
       AND (
           guest_user_id IS NULL
           OR guest_user_id = '22222222-2222-4222-8222-222222222222'
       );
    GET DIAGNOSTICS guest_count = ROW_COUNT;

    UPDATE such_moon_launch_friendly_room
       SET guest_user_id = COALESCE(
               guest_user_id,
               '33333333-3333-4333-8333-333333333333'
           ),
           updated_at = now()
     WHERE room_code = 'MN2P42'
       AND state = 'OPEN'
       AND expires_at > now()
       AND host_user_id <> '33333333-3333-4333-8333-333333333333'
       AND (
           guest_user_id IS NULL
           OR guest_user_id = '33333333-3333-4333-8333-333333333333'
       );
    GET DIAGNOSTICS second_guest_count = ROW_COUNT;

    IF guest_count <> 1 OR second_guest_count <> 0 THEN
        RAISE EXCEPTION 'friendly room guest reservation was not atomic';
    END IF;

    UPDATE such_moon_launch_friendly_room
       SET state = 'EXPIRED',
           closed_at = COALESCE(closed_at, now()),
           updated_at = now()
     WHERE room_code = 'MN2P42';

    BEGIN
        INSERT INTO such_moon_launch_friendly_room (
            room_code,
            match_id,
            host_user_id,
            expires_at
        ) VALUES (
            'IO0110',
            'relayed.match-invalid',
            '11111111-1111-4111-8111-111111111111',
            now() + interval '10 minutes'
        );
    EXCEPTION WHEN check_violation THEN
        invalid_room_rejected := true;
    END;
    IF NOT invalid_room_rejected THEN
        RAISE EXCEPTION 'ambiguous room code alphabet was accepted';
    END IF;
END;
$test$;

ROLLBACK;

\echo 'PASS PostgreSQL migration and replay integration'
