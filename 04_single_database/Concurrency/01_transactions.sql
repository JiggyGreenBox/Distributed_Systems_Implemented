TRUNCATE bank_accounts;

INSERT INTO bank_accounts VALUES
(1, 'Alice', 1000),
(2, 'Bob', 500);

SELECT xmin, xmax, ctid, *
FROM bank_accounts;

"xmin"	"xmax"	"ctid"	"account_id"	"owner_name"	"balance"
"750"	"0"	"(0,1)"	1	"Alice"	1000.00
"750"	"0"	"(0,2)"	2	"Bob"	500.00


SELECT
    lp,
    t_xmin,
    t_xmax,
    t_ctid
FROM heap_page_items(get_raw_page('bank_accounts', 0));

"lp"	"t_xmin"	"t_xmax"	"t_ctid"
1	"750"	"0"	"(0,1)"
2	"750"	"0"	"(0,2)"


UPDATE bank_accounts
SET balance = 900
WHERE account_id = 1;

"lp"	"t_xmin"	"t_xmax"	"t_ctid"
1	"750"	"751"	"(0,3)"
2	"750"	"0"	"(0,2)"
3	"751"	"0"	"(0,3)"

"xmin"	"xmax"	"ctid"	"account_id"	"owner_name"	"balance"
"750"	"0"	"(0,2)"	2	"Bob"	500.00
"751"	"0"	"(0,3)"	1	"Alice"	900.00


-- ===================================================================
-- Tab A
BEGIN;

UPDATE bank_accounts
SET balance = 700
WHERE account_id = 1;


SELECT balance
FROM bank_accounts
WHERE account_id = 1;

700.00

-- Tab B sees

SELECT balance
FROM bank_accounts
WHERE account_id = 1;

900.00

1	"750"	"751"	"(0,3)"
2	"750"	"0"	"(0,2)"
3	"751"	"752"	"(0,4)"
4	"752"	"0"	"(0,4)"

-- TAB B
SELECT txid_current();


-- UPDATE does not overwrite a row.
-- UPDATE creates a new row version.
-- The old row version remains until it can be safely removed by VACUUM.

-- a transaction always sees its own changes.
-- others see latest committed version


-- ===================================================================
VACUUM
SELECT
    lp,
    t_xmin,
    t_xmax,
    t_ctid
FROM heap_page_items(get_raw_page('bank_accounts',0));

"lp"	"t_xmin"	"t_xmax"	"t_ctid"
1	"750"	"751"	"(0,3)"     DEAD
2	"750"	"0"	"(0,2)"
3	"751"	"752"	"(0,4)"     DEAD
4	"752"	"0"	"(0,4)"

VACUUM bank_accounts;

1			
2	"750"	"0"	"(0,2)"
3			
4	"752"	"0"	"(0,4)"

-- vaccum on fresh data
TRUNCATE bank_accounts;

INSERT INTO bank_accounts VALUES
(1,'Alice',1000);

UPDATE bank_accounts SET balance=900 WHERE account_id=1;
UPDATE bank_accounts SET balance=800 WHERE account_id=1;
UPDATE bank_accounts SET balance=700 WHERE account_id=1;
UPDATE bank_accounts SET balance=600 WHERE account_id=1;
UPDATE bank_accounts SET balance=500 WHERE account_id=1;

SELECT
    lp,
    t_xmin,
    t_xmax,
    t_ctid
FROM heap_page_items(get_raw_page('bank_accounts',0));


SELECT
    relname,
    n_live_tup,
    n_dead_tup
FROM pg_stat_user_tables
WHERE relname='bank_accounts';

"relname"	"n_live_tup"	"n_dead_tup"
"bank_accounts"	1	10


VACUUM bank_accounts;

"bank_accounts"	1	0


-- VACUUM
--     Fast
--     Online
--     Allows reads/writes
--     Marks space reusable

-- VACUUM FULL
--     Rewrites table
--     Compacts everything
--     Returns disk space
--     Takes exclusive lock
--     Expensive


-- vaccum vs vaccum full

SELECT *
FROM heap_page_items(get_raw_page('bank_accounts',0));

VACUUM FULL bank_accounts

SELECT *
FROM heap_page_items(get_raw_page('bank_accounts',0));