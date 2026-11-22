INSERT IGNORE INTO accounts (id, user_id, name, number_masked, balance, currency) VALUES
  ('acc-1', 'user-1', 'Everyday Savings', '•••• 1234', 2345.67, 'SGD'),
  ('acc-2', 'user-1', 'Bonus Savings', '•••• 5678', 10120.00, 'SGD');
INSERT INTO transactions (id, account_id, type, amount, posted_at) VALUES
  ('seed-1', 'acc-1', 'FAST Payment / Receipt', 500.00, UTC_TIMESTAMP(3) - INTERVAL 2 DAY),
  ('seed-2', 'acc-1', 'NETS Purchase', -8.40, UTC_TIMESTAMP(3) - INTERVAL 4 DAY),
  ('seed-3', 'acc-1', 'PayNow Transfer', -25.00, UTC_TIMESTAMP(3) - INTERVAL 9 DAY),
  ('seed-4', 'acc-1', 'GIRO Payment', -60.00, UTC_TIMESTAMP(3) - INTERVAL 41 DAY)
ON DUPLICATE KEY UPDATE posted_at = VALUES(posted_at);
