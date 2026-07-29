\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS such_moon_launch_friendly_room (
    room_code char(6) PRIMARY KEY
        CHECK (room_code ~ '^[A-HJ-NP-Z2-9]{6}$'),
    match_id varchar(256) NOT NULL UNIQUE
        CHECK (
            octet_length(match_id) BETWEEN 8 AND 256
            AND match_id ~ '^[A-Za-z0-9._:-]+$'
        ),
    host_user_id uuid NOT NULL,
    guest_user_id uuid,
    protocol_version integer NOT NULL DEFAULT 1
        CHECK (protocol_version = 1),
    max_players integer NOT NULL DEFAULT 2
        CHECK (max_players = 2),
    state varchar(16) NOT NULL DEFAULT 'OPEN'
        CHECK (state IN ('OPEN', 'CLOSED', 'EXPIRED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    closed_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (guest_user_id IS NULL OR guest_user_id <> host_user_id),
    CHECK (expires_at > created_at),
    CHECK (
        (state = 'OPEN' AND closed_at IS NULL)
        OR (state <> 'OPEN' AND closed_at IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS such_moon_launch_friendly_room_expiry_idx
    ON such_moon_launch_friendly_room (state, expires_at);

INSERT INTO such_platform_schema_migration (
    schema_version,
    migration_id,
    contract_version
) VALUES (
    2,
    '002_friendly_room',
    1
)
ON CONFLICT (schema_version) DO NOTHING;

COMMIT;
