TRUNCATE bank_accounts;

INSERT INTO bank_accounts VALUES
(1,'Alice',1000),
(2,'Bob',500);


-- Tab A
BEGIN;

UPDATE bank_accounts
SET balance = balance - 100
WHERE account_id = 1;
    -- Alice row lock

    -- Tab B
    BEGIN;

    UPDATE bank_accounts
    SET balance = balance - 50
    WHERE account_id = 2;
        -- Bob row lock

-- Tab A
UPDATE bank_accounts
SET balance = balance - 100
WHERE account_id = 2;


    -- Tab B
    UPDATE bank_accounts
    SET balance = balance - 50
    WHERE account_id = 1;

"ERROR:  deadlock detected
Process 49 waits for ShareLock on transaction 777; blocked by process 42.
Process 42 waits for ShareLock on transaction 778; blocked by process 49. 

SQL state: 40P01
Detail: Process 49 waits for ShareLock on transaction 777; blocked by process 42.
Process 42 waits for ShareLock on transaction 778; blocked by process 49.
Hint: See server log for query details.
Context: while updating tuple (0,1) in relation "bank_accounts""


MVCC helps:
    Readers vs Writers

NOT
    Writer vs Writer

-- ============================================================================
-- Inspect the locks
SELECT
    pid,
    locktype,
    relation::regclass,
    mode,
    granted
FROM pg_locks
WHERE locktype <> 'virtualxid';

    "pid"	"locktype"	"relation"	"mode"	"granted"
    42	"relation"	"pg_locks"	"AccessShareLock"	true
    42	"relation"	"bank_accounts_pkey"	"RowExclusiveLock"	true
    42	"relation"	"bank_accounts"	"RowExclusiveLock"	true
    42	"transactionid"		"ExclusiveLock"	true


Deadlock detection is basically:
graph = waits-for graph

if graph contains cycle
{
    choose victim
    abort victim
}

Always acquire locks
in a deterministic order.

    BAD
        lock(from_account)
        lock(to_account)
    GOOD
        lock(min(from,to))
        lock(max(from,to))