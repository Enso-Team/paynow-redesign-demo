CREATE TABLE IF NOT EXISTS accounts (
  id VARCHAR(64) PRIMARY KEY,
  user_id VARCHAR(64) NOT NULL,
  name VARCHAR(128) NOT NULL,
  number_masked VARCHAR(32) NOT NULL,
  balance DECIMAL(15,2) NOT NULL,
  currency CHAR(3) NOT NULL
);
CREATE TABLE IF NOT EXISTS holds (
  payment_id VARCHAR(64) PRIMARY KEY,
  account_id VARCHAR(64) NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  status VARCHAR(16) NOT NULL
);
CREATE TABLE IF NOT EXISTS paynow_usage (
  user_id VARCHAR(64) NOT NULL,
  day DATE NOT NULL,
  used DECIMAL(15,2) NOT NULL,
  PRIMARY KEY (user_id, day)
);
CREATE TABLE IF NOT EXISTS transactions (
  id VARCHAR(64) PRIMARY KEY,
  account_id VARCHAR(64) NOT NULL,
  type VARCHAR(64) NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  posted_at DATETIME(3) NOT NULL,
  INDEX transactions_account_posted (account_id, posted_at)
);
