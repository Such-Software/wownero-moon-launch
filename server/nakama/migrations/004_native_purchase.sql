\set ON_ERROR_STOP on

BEGIN;

-- Local record of native (Apple/Google) purchases this instance has validated
-- and the ledger has accepted. One row per provider transaction line. Used by
-- app_platform_validate_iap to decide GRANT vs REINSTATE (a transaction seen
-- again after a REVOKE is a reinstatement, not a fresh grant) and to make
-- client retries idempotent without a second ledger round trip. The ledger
-- remains the authority; this table is a projection of what it accepted, keyed
-- by its returned event sequence.
CREATE TABLE IF NOT EXISTS such_platform_native_purchase (
    provider text NOT NULL
        CHECK (provider IN ('apple', 'google')),
    transaction_id text NOT NULL
        CHECK (octet_length(transaction_id) BETWEEN 1 AND 512),
    line_id text NOT NULL
        CHECK (octet_length(line_id) BETWEEN 1 AND 512),
    subject_id text NOT NULL
        CHECK (octet_length(subject_id) BETWEEN 8 AND 255),
    product_id text NOT NULL
        CHECK (octet_length(product_id) BETWEEN 1 AND 256),
    last_operation text NOT NULL
        CHECK (last_operation IN ('GRANT', 'REVOKE', 'REINSTATE')),
    last_validated_at timestamptz NOT NULL,
    last_event_sequence bigint
        CHECK (last_event_sequence IS NULL OR last_event_sequence >= 1),
    PRIMARY KEY (provider, transaction_id, line_id)
);

CREATE INDEX IF NOT EXISTS idx_native_purchase_subject
    ON such_platform_native_purchase (subject_id);

INSERT INTO such_platform_schema_migration (
    schema_version,
    migration_id,
    contract_version
) VALUES (
    4,
    '004_native_purchase',
    1
)
ON CONFLICT (schema_version) DO NOTHING;

COMMIT;
