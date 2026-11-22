INSERT IGNORE INTO proxies (type, value, masked_name, bank_code, latency_ms) VALUES
  ('MOBILE', '91234567', 'TAN ** **NG', 'OCBC', 0),
  ('MOBILE', '98765432', 'LIM ** **AH', 'UOB', 0),
  ('UEN', '201912345K', 'KOPI **** PTE LTD', 'DBS', 0),
  ('MOBILE', '90000001', 'SLOW ** **ER', 'OCBC', 3000),
  ('MOBILE', '90000002', 'REJ ** **ED', 'REJECT', 0);
