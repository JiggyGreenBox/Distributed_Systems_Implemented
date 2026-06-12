-- READ_COMMITTED_vs_REPEATABLE_READ

TRUNCATE bank_accounts;

INSERT INTO bank_accounts VALUES
(1,'Alice',1000);   

-- ================================================================
-- Scenario 1: Triggering a Non-Repeatable Read (READ COMMITTED)   

    -- allows data to change right in 
    -- the middle  of an open transaction
-- ================================================================
    

-- Tab A (Time T1): Start a standard transaction.
BEGIN;
SELECT balance FROM bank_accounts WHERE account_id = 1;

-- Tab B (Time T2)
BEGIN;
UPDATE bank_accounts SET balance = 400.00 WHERE account_id = 1;
COMMIT;

-- Tab A (Time T3):
SELECT balance FROM bank_accounts WHERE account_id = 1;
400

-- Tab A (Time T4):
COMMIT;

400 was the value mid transaction

-- ================================================================
-- Scenario 2: Triggering a Serialization Failure (REPEATABLE READ)

    -- forces a hard crash when you try to write to data 
    -- that changed behind your back    
-- ================================================================

UPDATE bank_accounts SET balance = 1000.00 WHERE account_id = 1;

-- Tab A (Time T1):
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT balance FROM bank_accounts WHERE account_id = 1;

-- Tab B (Time T2)
BEGIN;
UPDATE bank_accounts SET balance = 800.00 WHERE account_id = 1;
COMMIT;

-- Tab A (Time T3):
SELECT balance FROM bank_accounts WHERE account_id = 1;
    1000

-- Tab A (Time T4)
UPDATE bank_accounts SET balance = balance - 100 WHERE account_id = 1;

    "ERROR:  could not serialize access due to concurrent update 
    SQL state: 40001"

-- Tab A (Time T5)
ROLLBACK;
SELECT balance FROM bank_accounts WHERE account_id = 1;
    800



/*
If a system design question involves high-concurrency writes (like a 
ticket booking system, flash sales, or high-frequency ledger 
processing), you need to talk about how you handle this error.

Under READ COMMITTED, the application waits in a queue. Under 
REPEATABLE READ or SERIALIZABLE, the database throws the error back 
to your application code.

if you choose higher isolation levels to prevent data corruption, 
your application layer must implement an explicit Retry Loop.
*/

-- # A typical high-concurrency application pattern
def update_balance_with_retry(account_id, amount):
    max_retries = 3
    for attempt in range(max_retries):
        try:
            with database.transaction(isolation_level="REPEATABLE_READ") as tx:
                current_balance = tx.query("SELECT balance FROM bank_accounts WHERE id = %s", account_id)
                new_balance = current_balance - amount
                tx.execute("UPDATE bank_accounts SET balance = %s WHERE id = %s", new_balance, account_id)
                return True
        except SerializationFailureError:
            # Catch the Postgres code 40001 under the hood
            time.sleep(0.1 * attempt) # Exponential backoff
            continue # Retry the entire transaction with a fresh snapshot
    raise Exception("Transaction failed after max retries due to high contention")



-- ================================================================
update creates a new version
when we update:
    READ REPEATABLE: Am I updating the latest version?
        NO - error (latest xmin != my xmin)
    READ COMMITED: i take the lastest version  
        update lastest xmin



-- ================================================================
UPDATE

1. Find visible row version according to my snapshot

2. Follow version chain to current version

3. Check whether somebody committed a newer version
   after my snapshot

4. If yes:
       REPEATABLE READ -> error
       READ COMMITTED -> use newest version


-- ================================================================
READ COMMITTED

UPDATE:
    Find latest committed version
    Update it

REPEATABLE READ

UPDATE:
    If row changed since my snapshot,
    abort transaction
-- ================================================================


Alice

    Alice=1000
    ↓ UPDATE
    Alice=900
    ↓ UPDATE
    Alice=700

    Alice v1
    Alice v2
    Alice v3

    lp=1  Alice=1000
    lp=3  Alice=900
    lp=4  Alice=700

2. Transaction (TX)
    TX 750
    INSERT Alice=1000

    TX 751
    UPDATE Alice=900

    TX 752
    UPDATE Alice=700


xmin = Who created me?
xmax = Who invalidated me?



ctid
    (block, offset)
        Physical location of this tuple
    (0,4)
        Page 0
        Slot 4


a live tuple
    xmin=752
    xmax=0
    ctid=(0,4)
        ctid points to itself.

ctid points to itself.
    xmin=751
    xmax=752
    ctid=(0,4)
        ctid points to the newer version

lp
    Slot number inside the page.


lp | xmin | xmax | ctid
-------------------------
1  | 750  | 751  | (0,3)        create alice  (updated by,(0,3))
2  | 750  | 0    | (0,2)        create bob      LIVE
3  | 751  | 752  | (0,4)        updated alice   (updated by,(0,4))
4  | 752  | 0    | (0,4)        updated alice LIVE




Repeatable Read SELECT
    while(tuple != nullptr)
    {
        if(isVisible(tuple, snapshot))
            return tuple;

        tuple = olderVersion(tuple);
    }

Repeatable Read UPDATE
    visible = tupleVisibleInMySnapshot();
    latest  = newestTupleVersion(); 

    if(visible != latest)
    {
        ERROR;
    }


-- ================================================================
READ COMMITTED

snapshot = new Snapshot()
           for every statement


REPEATABLE READ

snapshot = new Snapshot()
           once per transaction