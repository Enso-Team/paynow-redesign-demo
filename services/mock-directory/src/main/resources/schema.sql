CREATE TABLE IF NOT EXISTS proxies (
  type VARCHAR(8) NOT NULL,
  value VARCHAR(16) NOT NULL,
  masked_name VARCHAR(128) NOT NULL,
  bank_code VARCHAR(16) NOT NULL,
  latency_ms INT NOT NULL DEFAULT 0,
  PRIMARY KEY (type, value)
);
