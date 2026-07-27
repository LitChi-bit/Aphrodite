BEGIN;

DROP TABLE IF EXISTS refresh_tokens;
DROP TABLE IF EXISTS auth_sessions;
DROP TABLE IF EXISTS authorization_codes;
DROP TABLE IF EXISTS login_challenges;
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS accounts;

COMMIT;
