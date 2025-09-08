-- MySQL benchmark schema initialization
-- This file is automatically executed when MySQL containers start

USE benchmark_db;

-- Table for INSERT heavy workloads
CREATE TABLE IF NOT EXISTS benchmark_inserts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    uuid VARCHAR(36) NOT NULL,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    random_int INT NOT NULL,
    random_float DECIMAL(10,4) NOT NULL,
    text_data TEXT NOT NULL,
    json_data JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_timestamp (timestamp),
    INDEX idx_uuid (uuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table for mixed read/write workloads
CREATE TABLE IF NOT EXISTS benchmark_mixed (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    session_id VARCHAR(64) NOT NULL,
    action_type VARCHAR(32) NOT NULL,
    action_data JSON,
    ip_address VARCHAR(45),
    user_agent TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed BOOLEAN DEFAULT FALSE,
    INDEX idx_user_id (user_id),
    INDEX idx_timestamp (timestamp),
    INDEX idx_session_id (session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table for transaction heavy workloads (bank-like)
CREATE TABLE IF NOT EXISTS accounts (
    account_id INT AUTO_INCREMENT PRIMARY KEY,
    account_number VARCHAR(20) UNIQUE NOT NULL,
    balance DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    account_type VARCHAR(20) NOT NULL DEFAULT 'checking',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_account_number (account_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS transactions (
    transaction_id INT AUTO_INCREMENT PRIMARY KEY,
    from_account INT,
    to_account INT,
    amount DECIMAL(15,2) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,
    description TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'completed',
    INDEX idx_from_account (from_account),
    INDEX idx_to_account (to_account),
    INDEX idx_timestamp (timestamp),
    FOREIGN KEY (from_account) REFERENCES accounts(account_id),
    FOREIGN KEY (to_account) REFERENCES accounts(account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table for bulk import testing
CREATE TABLE IF NOT EXISTS bulk_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    batch_id INT NOT NULL,
    sequence_num INT NOT NULL,
    data_category VARCHAR(50) NOT NULL,
    payload TEXT NOT NULL,
    checksum VARCHAR(64),
    imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_batch_id (batch_id),
    INDEX idx_sequence (batch_id, sequence_num)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed some initial data
INSERT IGNORE INTO accounts (account_number, balance, account_type) 
VALUES 
    ('ACC001', 1000.00, 'checking'),
    ('ACC002', 2500.00, 'savings'),
    ('ACC003', 500.00, 'checking'),
    ('ACC004', 10000.00, 'business'),
    ('ACC005', 750.00, 'checking');

-- Create stored procedures for benchmark operations
DELIMITER //

CREATE PROCEDURE IF NOT EXISTS transfer_funds(
    IN p_from_account INT,
    IN p_to_account INT,
    IN p_amount DECIMAL(15,2),
    IN p_description TEXT,
    OUT p_success BOOLEAN
)
BEGIN
    DECLARE from_balance DECIMAL(15,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_success = FALSE;
    END;
    
    START TRANSACTION;
    
    -- Check source account balance
    SELECT balance INTO from_balance 
    FROM accounts 
    WHERE account_id = p_from_account 
    FOR UPDATE;
    
    IF from_balance < p_amount THEN
        ROLLBACK;
        SET p_success = FALSE;
    ELSE
        -- Debit from source account
        UPDATE accounts 
        SET balance = balance - p_amount, updated_at = CURRENT_TIMESTAMP
        WHERE account_id = p_from_account;
        
        -- Credit to destination account
        UPDATE accounts 
        SET balance = balance + p_amount, updated_at = CURRENT_TIMESTAMP
        WHERE account_id = p_to_account;
        
        -- Record transaction
        INSERT INTO transactions (from_account, to_account, amount, transaction_type, description)
        VALUES (p_from_account, p_to_account, p_amount, 'transfer', p_description);
        
        COMMIT;
        SET p_success = TRUE;
    END IF;
END //

DELIMITER ;

-- Create view for reporting
CREATE OR REPLACE VIEW account_summary AS
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

-- Grant permissions to benchmark user
GRANT ALL PRIVILEGES ON benchmark_db.* TO 'benchmark_user'@'%';
FLUSH PRIVILEGES;
