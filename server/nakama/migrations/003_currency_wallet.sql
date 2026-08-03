\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS such_platform_currency_balance (
    subject_id text NOT NULL
        CHECK (octet_length(subject_id) BETWEEN 8 AND 255),
    currency_key varchar(64) NOT NULL
        CHECK (currency_key ~ '^[a-z][a-z0-9_.-]*$'),
    balance bigint NOT NULL DEFAULT 0
        CHECK (balance BETWEEN -9007199254740991 AND 9007199254740991),
    last_sequence bigint NOT NULL DEFAULT 0 CHECK (last_sequence >= 0),
    last_event_id text,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (subject_id, currency_key),
    CHECK (
        (last_sequence = 0 AND last_event_id IS NULL)
        OR (last_sequence > 0 AND last_event_id IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS such_platform_currency_event (
    event_id text PRIMARY KEY
        CHECK (octet_length(event_id) BETWEEN 16 AND 128),
    subject_id text NOT NULL
        CHECK (octet_length(subject_id) BETWEEN 8 AND 255),
    currency_key varchar(64) NOT NULL
        CHECK (currency_key ~ '^[a-z][a-z0-9_.-]*$'),
    sequence bigint NOT NULL CHECK (sequence >= 1),
    operation varchar(16) NOT NULL
        CHECK (operation IN ('CREDIT', 'REVERSE', 'REINSTATE')),
    amount bigint NOT NULL
        CHECK (amount BETWEEN 1 AND 9007199254740991),
    original_event_id text REFERENCES such_platform_currency_event(event_id),
    idempotency_key text NOT NULL UNIQUE
        CHECK (octet_length(idempotency_key) BETWEEN 16 AND 512),
    event_digest char(64) NOT NULL
        CHECK (event_digest ~ '^[0-9a-f]{64}$'),
    effective_at timestamptz NOT NULL,
    source_provider varchar(32) NOT NULL
        CHECK (source_provider IN (
            'apple', 'google', 'medusa_stripe', 'medusa_crypto',
            'migration', 'admin', 'test'
        )),
    source_transaction_id text NOT NULL
        CHECK (octet_length(source_transaction_id) BETWEEN 1 AND 512),
    source_line_id text NOT NULL
        CHECK (octet_length(source_line_id) BETWEEN 1 AND 255),
    source_occurred_at timestamptz NOT NULL,
    resulting_balance bigint NOT NULL
        CHECK (resulting_balance BETWEEN -9007199254740991 AND 9007199254740991),
    applied_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (subject_id, currency_key, sequence),
    CHECK (
        (operation = 'CREDIT' AND original_event_id IS NULL)
        OR (operation <> 'CREDIT' AND original_event_id IS NOT NULL)
    ),
    CHECK (
        (source_line_id = 'moonrocks_10k_v1' AND amount = 10000)
        OR (source_line_id = 'moonrocks_50k_v1' AND amount = 50000)
    )
);

CREATE INDEX IF NOT EXISTS such_platform_currency_event_original_idx
    ON such_platform_currency_event (original_event_id, sequence);

CREATE OR REPLACE FUNCTION such_platform_apply_currency_event(
    p_event_id text,
    p_subject_id text,
    p_currency_key text,
    p_sequence bigint,
    p_operation text,
    p_amount bigint,
    p_original_event_id text,
    p_idempotency_key text,
    p_event_digest text,
    p_effective_at timestamptz,
    p_source_provider text,
    p_source_transaction_id text,
    p_source_line_id text,
    p_source_occurred_at timestamptz
)
RETURNS TABLE(outcome text, balance bigint, last_sequence bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    existing_event such_platform_currency_event%ROWTYPE;
    original_credit such_platform_currency_event%ROWTYPE;
    current_balance bigint := 0;
    current_sequence bigint := 0;
    lifecycle_operation text;
    delta bigint;
    next_balance numeric;
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_subject_id || E'\n' || p_currency_key, 0)
    );

    SELECT *
      INTO existing_event
      FROM such_platform_currency_event
     WHERE event_id = p_event_id
        OR idempotency_key = p_idempotency_key
        OR (
            subject_id = p_subject_id
            AND currency_key = p_currency_key
            AND sequence = p_sequence
        )
     ORDER BY applied_at
     LIMIT 1;

    IF FOUND THEN
        IF existing_event.event_digest = p_event_digest
           AND existing_event.subject_id = p_subject_id
           AND existing_event.currency_key = p_currency_key
           AND existing_event.sequence = p_sequence THEN
            RETURN QUERY SELECT
                'DUPLICATE'::text,
                existing_event.resulting_balance,
                existing_event.sequence;
            RETURN;
        END IF;
        RAISE EXCEPTION 'conflicting currency event'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    SELECT wallet.balance, wallet.last_sequence
      INTO current_balance, current_sequence
      FROM such_platform_currency_balance AS wallet
     WHERE wallet.subject_id = p_subject_id
       AND wallet.currency_key = p_currency_key
     FOR UPDATE;

    IF NOT FOUND THEN
        current_balance := 0;
        current_sequence := 0;
    END IF;
    IF p_sequence <= current_sequence THEN
        RAISE EXCEPTION 'non-increasing currency sequence'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    IF p_operation = 'CREDIT' THEN
        IF p_original_event_id IS NOT NULL THEN
            RAISE EXCEPTION 'credit cannot reference an original event'
                USING ERRCODE = 'integrity_constraint_violation';
        END IF;
        delta := p_amount;
    ELSIF p_operation IN ('REVERSE', 'REINSTATE') THEN
        SELECT *
          INTO original_credit
          FROM such_platform_currency_event
         WHERE event_id = p_original_event_id
           AND operation = 'CREDIT'
           AND subject_id = p_subject_id
           AND currency_key = p_currency_key
           AND amount = p_amount;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'currency lifecycle original is invalid'
                USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        SELECT event.operation
          INTO lifecycle_operation
          FROM such_platform_currency_event AS event
         WHERE event.event_id = p_original_event_id
            OR event.original_event_id = p_original_event_id
         ORDER BY event.sequence DESC
         LIMIT 1;

        IF p_operation = 'REVERSE'
           AND lifecycle_operation NOT IN ('CREDIT', 'REINSTATE') THEN
            RAISE EXCEPTION 'currency credit is already reversed'
                USING ERRCODE = 'integrity_constraint_violation';
        ELSIF p_operation = 'REINSTATE'
              AND lifecycle_operation <> 'REVERSE' THEN
            RAISE EXCEPTION 'currency credit is not reversed'
                USING ERRCODE = 'integrity_constraint_violation';
        END IF;
        delta := CASE WHEN p_operation = 'REVERSE' THEN -p_amount ELSE p_amount END;
    ELSE
        RAISE EXCEPTION 'currency operation is invalid'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    next_balance := current_balance::numeric + delta::numeric;
    IF next_balance < -9007199254740991 OR next_balance > 9007199254740991 THEN
        RAISE EXCEPTION 'currency balance is out of range'
            USING ERRCODE = 'numeric_value_out_of_range';
    END IF;

    INSERT INTO such_platform_currency_event (
        event_id,
        subject_id,
        currency_key,
        sequence,
        operation,
        amount,
        original_event_id,
        idempotency_key,
        event_digest,
        effective_at,
        source_provider,
        source_transaction_id,
        source_line_id,
        source_occurred_at,
        resulting_balance
    ) VALUES (
        p_event_id,
        p_subject_id,
        p_currency_key,
        p_sequence,
        p_operation,
        p_amount,
        p_original_event_id,
        p_idempotency_key,
        p_event_digest,
        p_effective_at,
        p_source_provider,
        p_source_transaction_id,
        p_source_line_id,
        p_source_occurred_at,
        next_balance::bigint
    );

    INSERT INTO such_platform_currency_balance (
        subject_id,
        currency_key,
        balance,
        last_sequence,
        last_event_id,
        updated_at
    ) VALUES (
        p_subject_id,
        p_currency_key,
        next_balance::bigint,
        p_sequence,
        p_event_id,
        now()
    )
    ON CONFLICT (subject_id, currency_key) DO UPDATE SET
        balance = EXCLUDED.balance,
        last_sequence = EXCLUDED.last_sequence,
        last_event_id = EXCLUDED.last_event_id,
        updated_at = now();

    RETURN QUERY SELECT 'APPLIED'::text, next_balance::bigint, p_sequence;
END;
$function$;

INSERT INTO such_platform_schema_migration (
    schema_version,
    migration_id,
    contract_version
) VALUES (
    3,
    '003_currency_wallet',
    1
)
ON CONFLICT (schema_version) DO NOTHING;

COMMIT;
