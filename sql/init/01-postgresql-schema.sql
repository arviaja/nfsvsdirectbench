-- PostgreSQL benchmark schema initialization
-- This file is automatically executed when PostgreSQL containers start

-- Create benchmark tables for various test scenarios

-- Table for INSERT heavy workloads
CREATE TABLE IF NOT EXISTS benchmark_inserts (
    id SERIAL PRIMARY KEY,
    uuid VARCHAR(36) NOT NULL,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    random_int INTEGER NOT NULL,
    random_float DECIMAL(10,4) NOT NULL,
    text_data TEXT NOT NULL,
    json_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Table for mixed read/write workloads
CREATE TABLE IF NOT EXISTS benchmark_mixed (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    session_id VARCHAR(64) NOT NULL,
    action_type VARCHAR(32) NOT NULL,
    action_data JSONB,
    ip_address INET,
    user_agent TEXT,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    processed BOOLEAN DEFAULT FALSE
);

-- Table for transaction heavy workloads (bank-like)
CREATE TABLE IF NOT EXISTS accounts (
    account_id SERIAL PRIMARY KEY,
    account_number VARCHAR(20) UNIQUE NOT NULL,
    balance DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    account_type VARCHAR(20) NOT NULL DEFAULT 'checking',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transactions (
    transaction_id SERIAL PRIMARY KEY,
    from_account INTEGER REFERENCES accounts(account_id),
    to_account INTEGER REFERENCES accounts(account_id),
    amount DECIMAL(15,2) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,
    description TEXT,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'completed'
);

-- Table for bulk import testing
CREATE TABLE IF NOT EXISTS bulk_data (
    id SERIAL PRIMARY KEY,
    batch_id INTEGER NOT NULL,
    sequence_num INTEGER NOT NULL,
    data_category VARCHAR(50) NOT NULL,
    payload TEXT NOT NULL,
    checksum VARCHAR(64),
    imported_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance testing
CREATE INDEX IF NOT EXISTS idx_benchmark_inserts_timestamp ON benchmark_inserts(timestamp);
CREATE INDEX IF NOT EXISTS idx_benchmark_inserts_uuid ON benchmark_inserts(uuid);
CREATE INDEX IF NOT EXISTS idx_benchmark_mixed_user_id ON benchmark_mixed(user_id);
CREATE INDEX IF NOT EXISTS idx_benchmark_mixed_timestamp ON benchmark_mixed(timestamp);
CREATE INDEX IF NOT EXISTS idx_accounts_account_number ON accounts(account_number);
CREATE INDEX IF NOT EXISTS idx_transactions_from_account ON transactions(from_account);
CREATE INDEX IF NOT EXISTS idx_transactions_to_account ON transactions(to_account);
CREATE INDEX IF NOT EXISTS idx_transactions_timestamp ON transactions(timestamp);
CREATE INDEX IF NOT EXISTS idx_bulk_data_batch_id ON bulk_data(batch_id);

-- Seed some initial data
INSERT INTO accounts (account_number, balance, account_type) 
VALUES 
    ('ACC001', 1000.00, 'checking'),
    ('ACC002', 2500.00, 'savings'),
    ('ACC003', 500.00, 'checking'),
    ('ACC004', 10000.00, 'business'),
    ('ACC005', 750.00, 'checking')
ON CONFLICT (account_number) DO NOTHING;

-- Create stored procedures for benchmark operations
CREATE OR REPLACE FUNCTION transfer_funds(
    p_from_account INTEGER,
    p_to_account INTEGER,
    p_amount DECIMAL(15,2),
    p_description TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    from_balance DECIMAL(15,2);
BEGIN
    -- Start transaction
    BEGIN
        -- Check source account balance
        SELECT balance INTO from_balance 
        FROM accounts 
        WHERE account_id = p_from_account 
        FOR UPDATE;
        
        IF from_balance < p_amount THEN
            RETURN FALSE;
        END IF;
        
        -- Debit from source account
        UPDATE accounts 
        SET balance = balance - p_amount, updated_at = NOW()
        WHERE account_id = p_from_account;
        
        -- Credit to destination account
        UPDATE accounts 
        SET balance = balance + p_amount, updated_at = NOW()
        WHERE account_id = p_to_account;
        
        -- Record transaction
        INSERT INTO transactions (from_account, to_account, amount, transaction_type, description)
        VALUES (p_from_account, p_to_account, p_amount, 'transfer', p_description);
        
        RETURN TRUE;
    EXCEPTION WHEN OTHERS THEN
        RETURN FALSE;
    END;
END;
$$ LANGUAGE plpgsql;

-- Create view for reporting
CREATE OR REPLACE VIEW account_summary AS
SELECT 
    a.account_id,
    a.account_number,
    a.balance,
    a.account_type,
    COUNT(t1.transaction_id) as outgoing_transactions,
    COUNT(t2.transaction_id) as incoming_transactions,
    a.created_at,
    a.updated_at
FROM accounts a
LEFT JOIN transactions t1 ON a.account_id = t1.from_account
LEFT JOIN transactions t2 ON a.account_id = t2.to_account
GROUP BY a.account_id, a.account_number, a.balance, a.account_type, a.created_at, a.updated_at;

-- Grant permissions to benchmark user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO benchmark_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO benchmark_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO benchmark_user;
