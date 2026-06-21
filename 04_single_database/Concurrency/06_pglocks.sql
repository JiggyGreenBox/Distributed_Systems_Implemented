-- -----------------------------------------------
-- setup
-- -----------------------------------------------
DROP TABLE IF EXISTS bank_accounts;

CREATE TABLE bank_accounts (
    account_id INT PRIMARY KEY,
    owner_name TEXT,
    balance NUMERIC(12,2)
);

INSERT INTO bank_accounts VALUES
(1, 'Alice', 1000),
(2, 'Bob', 500),
(3, 'Charlie', 2000);

SELECT * FROM bank_accounts;

-- -----------------------------------------------
-- Experiment 1: FOR UPDATE
-- -----------------------------------------------
-- Read + lock row
-- Other writers wait

-- Tab A
BEGIN;

SELECT *
FROM bank_accounts
WHERE account_id = 1
FOR UPDATE;

-- Tab B
BEGIN;

UPDATE bank_accounts
SET balance = balance - 100
WHERE account_id = 1;

-- Tab C
SELECT
    pid,
    wait_event_type,
    wait_event,
    state,
    query
FROM pg_stat_activity
WHERE datname = current_database();

-- -----------------------------------------------
-- Experiment 2: FOR UPDATE NOWAIT
-- -----------------------------------------------
-- Fail immediately instead of waiting.

-- Tab A
BEGIN;

SELECT *
FROM bank_accounts
WHERE account_id = 1
FOR UPDATE;

-- Tab B
SELECT *
FROM bank_accounts
WHERE account_id = 1
FOR UPDATE NOWAIT;

-- then
ROLLBACK;

-- -----------------------------------------------
-- Experiment 3: FOR UPDATE SKIP LOCKED
-- -----------------------------------------------

-- Setup
DROP TABLE IF EXISTS jobs;

CREATE TABLE jobs (
    id SERIAL PRIMARY KEY,
    payload TEXT,
    status TEXT DEFAULT 'pending'
);

INSERT INTO jobs(payload)
SELECT 'Job-' || g
FROM generate_series(1,10) g;

SELECT * FROM jobs;


-- Worker A (Tab A)
BEGIN;

SELECT *
FROM jobs
WHERE status = 'pending'
ORDER BY id
LIMIT 1
FOR UPDATE SKIP LOCKED;

-- Worker B (Tab B)
BEGIN;

SELECT *
FROM jobs
WHERE status = 'pending'
ORDER BY id
LIMIT 1
FOR UPDATE SKIP LOCKED;

-- Worker C
BEGIN;

SELECT *
FROM jobs
WHERE status = 'pending'
ORDER BY id
LIMIT 1
FOR UPDATE SKIP LOCKED;

-- -----------------------------------------------
-- Experiment 4: FOR SHARE
-- -----------------------------------------------
-- Multiple readers
-- No writers


-- Tab A
BEGIN;

SELECT *
FROM bank_accounts
WHERE account_id = 1
FOR SHARE;

-- Tab B
BEGIN;

SELECT *
FROM bank_accounts
WHERE account_id = 1
FOR SHARE;

-- Tab C
    -- Try update:
UPDATE bank_accounts
SET balance = 1234
WHERE account_id = 1;
    -- Blocks.



/*
FOR UPDATE
    Exclusive row lock

FOR UPDATE NOWAIT
    Exclusive row lock or fail

FOR UPDATE SKIP LOCKED
    Exclusive row lock or skip

FOR SHARE
    Shared read lock

pg_locks
    Current lock ownership

pg_stat_activity
    Who is waiting on whom
*/