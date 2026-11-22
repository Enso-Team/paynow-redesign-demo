CREATE TABLE IF NOT EXISTS payments (
  id VARCHAR(64) PRIMARY KEY,
  idempotency_key VARCHAR(64) NOT NULL UNIQUE,
  user_id VARCHAR(64) NOT NULL,
  from_account_id VARCHAR(64) NOT NULL,
  proxy_type VARCHAR(8) NOT NULL,
  proxy_value VARCHAR(16) NOT NULL,
  masked_name VARCHAR(128) NOT NULL,
  bank_code VARCHAR(16) NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  reference VARCHAR(140) NULL,
  status VARCHAR(16) NOT NULL,
  reason VARCHAR(64) NULL,
  created_at DATETIME(3) NOT NULL,
  settled_at DATETIME(3) NULL
);
