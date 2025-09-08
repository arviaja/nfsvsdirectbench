-- SQLite benchmark schema initialization
-- This file is used to initialize SQLite databases

-- Enable foreign key constraints
PRAGMA foreign_keys = ON;

-- Set performance optimizations
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = 10000;
PRAGMA temp_store = MEMORY;

-- Table for INSERT heavy workloads
CREATE TABLE IF NOT EXISTS benchmark_inserts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    random_int INTEGER NOT NULL,
    random_float REAL NOT NULL,
    text_data TEXT NOT NULL,
    json_data TEXT, -- SQLite doesn't have native JSON, using TEXT
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Table for mixed read/write workloads
CREATE TABLE IF NOT EXISTS benchmark_mixed (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    session_id TEXT NOT NULL,
    action_type TEXT NOT NULL,
    action_data TEXT, -- JSON stored as TEXT
    ip_address TEXT,
    user_agent TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed INTEGER DEFAULT 0 -- SQLite uses INTEGER for BOOLEAN
);

-- Table for transaction heavy workloads (bank-like)
CREATE TABLE IF NOT EXISTS accounts (
    account_id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_number TEXT UNIQUE NOT NULL,
    balance REAL NOT NULL DEFAULT 0.00,
    account_type TEXT NOT NULL DEFAULT 'checking',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transactions (
    transaction_id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_account INTEGER,
    to_account INTEGER,
    amount REAL NOT NULL,
    transaction_type TEXT NOT NULL,
    description TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    status TEXT DEFAULT 'completed',
    FOREIGN KEY (from_account) REFERENCES accounts(account_id),
    FOREIGN KEY (to_account) REFERENCES accounts(account_id)
);

-- Table for bulk import testing
CREATE TABLE IF NOT EXISTS bulk_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER NOT NULL,
    sequence_num INTEGER NOT NULL,
    data_category TEXT NOT NULL,
    payload TEXT NOT NULL,
    checksum TEXT,
    imported_at DATETIME DEFAULT CURRENT_TIMESTAMP
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
INSERT OR IGNORE INTO accounts (account_number, balance, account_type) 
VALUES 
    ('ACC001', 1000.00, 'checking'),
    ('ACC002', 2500.00, 'savings'),
    ('ACC003', 500.00, 'checking'),
    ('ACC004', 10000.00, 'business'),
    ('ACC005', 750.00, 'checking');

-- Create trigger to update timestamp (SQLite doesn't have ON UPDATE CURRENT_TIMESTAMP)
CREATE TRIGGER IF NOT EXISTS update_accounts_timestamp 
AFTER UPDATE ON accounts
BEGIN
    UPDATE accounts SET updated_at = CURRENT_TIMESTAMP WHERE account_id = NEW.account_id;
END;

-- Create view for reporting
CREATE VIEW IF NOT EXISTS account_summary AS
SELECT 
    a.account_id,
    a.account_number,
    a.balance,
    a.account_type,
    COUNT(DISTINCT t1.transaction_id) as outgoing_transactions,
    COUNT(DISTINCT t2.transaction_id) as incoming_transactions,
    a.created_at,
    a.updated_at
FROM accounts a
LEFT JOIN transactions t1 ON a.account_id = t1.from_account
LEFT JOIN transactions t2 ON a.account_id = t2.to_account
GROUP BY a.account_id, a.account_number, a.balance, a.account_type, a.created_at, a.updated_at;
