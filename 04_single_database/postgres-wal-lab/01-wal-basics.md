# WAL basics
 * what we thought
```text
UPDATE row
    ↓
row changes
```
 * what really happens
```text
UPDATE row
    ↓
Create WAL record
    ↓
Flush WAL to disk
    ↓
COMMIT succeeds
    ↓
Actual table page can be written later
```

```text
The WAL is the source of truth.

The heap page is eventually updated.
```

## Lab 1: Explore WAL Configuration
```sql
SHOW data_directory;
    -- /var/lib/postgresql/data

SHOW wal_level;
    -- replica

SHOW max_wal_size;
    -- 1GB

SHOW min_wal_size;
    -- 80MB

SHOW checkpoint_timeout;
    -- 5min
SHOW shared_buffers;
    -- 128MB
```

## Lab 2: Observe the Current WAL Position
 - Think of WAL as one giant append-only file.
 - PostgreSQL tracks position using: `LSN (Log Sequence Number)`
```sql
SELECT pg_current_wal_lsn();
    -- 0/195FCC8
        -- Current byte offset
        -- inside WAL stream
```

## Lab 3: Create a Table
```sql
CREATE TABLE wal_demo (
    id SERIAL PRIMARY KEY,
    message TEXT
);
```

## Lab 4: Measure WAL Growth
```sql
SELECT pg_current_wal_lsn();
    -- 0/1987568


-- insert data
INSERT INTO wal_demo(message)
SELECT 'row-' || g
FROM generate_series(1,100000) g;

SELECT pg_current_wal_lsn();
    -- 0/2717FB0


-- Calculate generated WAL:
SELECT pg_wal_lsn_diff(
    pg_current_wal_lsn(),
    'YOUR_OLD_LSN'
);

-- 14224000
    --  13.57 MB
```

```text
Why did WAL grow?

Insert row
Insert row
Insert row
Insert row
...
...
```

## Lab 5: Small Change, Small WAL
```sql
-- Record LSN:
SELECT pg_current_wal_lsn();
    -- 0/2717FE8

UPDATE wal_demo
SET message = 'updated'
WHERE id = 1;

SELECT pg_current_wal_lsn();
    -- 0/2718130

SELECT pg_wal_lsn_diff(
    pg_current_wal_lsn(),
    'OLD_LSN'
);
    -- 0.328 kb
```

## Lab 6: Observe WAL Files
```sh
docker ps

docker exec -it postgres_durability bash
# OR
docker exec -it postgres_durability sh

cd $PGDATA/pg_wal

ls -lh
```

```text
75e01cd407ac:/# cd $PGDATA/pg_wal
75e01cd407ac:/var/lib/postgresql/data/pg_wal# ls -lh
total 32M    
-rw-------    1 postgres postgres   16.0M Jun 19 09:11 000000010000000000000002
-rw-------    1 postgres postgres   16.0M Jun 19 09:05 000000010000000000000003
drwx------    2 postgres postgres    4.0K Jun 19 08:55 archive_status
```

## WAL file
 - WAL records look more like:
```text
Modify page X

Insert tuple Y

Split B-Tree page

Delete tuple

Commit transaction
```

```sql
INSERT INTO bank_accounts
VALUES (1,'Alice',1000);
```

```text
BEGIN TX 100

Insert tuple
  relation = bank_accounts
  page = 0
  offset = 1

COMMIT TX 100
```

```sh
# Page Split

Split page 100

Create page 101

Move keys

Update parent page
```

### Why LSN Exists
* Every WAL record gets an address.
```
LSN 0/100000
INSERT

LSN 0/100200
UPDATE

LSN 0/100300
COMMIT
```

## First check if pg_waldump exists
```sh
which pg_waldump

# /usr/local/bin/pg_waldump

OR

pg_waldump --help
```
```sh
pg_waldump /var/lib/postgresql/data/pg_wal/000000010000000000000002 | head -10
```

```text
75e01cd407ac:/var/lib/postgresql/data/pg_wal# pg_waldump /var/lib/postgresql/data/pg_wal/000000010000000000000002 | head -10
rmgr: Heap        len (rec/tot):     69/    69, tx:        744, lsn: 0/02000058, prev 0/01FFFFF0, desc: INSERT off: 123, flags: 0x00, blkref #0: rel 1663/16384/16390 blk 258
rmgr: Btree       len (rec/tot):     64/    64, tx:        744, lsn: 0/020000A0, prev 0/02000058, desc: INSERT_LEAF off: 273, blkref #0: rel 1663/16384/16396 blk 132
rmgr: Heap        len (rec/tot):     69/    69, tx:        744, lsn: 0/020000E0, prev 0/020000A0, desc: INSERT off: 124, flags: 0x00, blkref #0: rel 1663/16384/16390 blk 258
rmgr: Btree       len (rec/tot):     64/    64, tx:        744, lsn: 0/02000128, prev 0/020000E0, desc: INSERT_LEAF off: 274, blkref #0: rel 1663/16384/16396 blk 132
rmgr: Heap        len (rec/tot):     69/    69, tx:        744, lsn: 0/02000168, prev 0/02000128, desc: INSERT off: 125, flags: 0x00, blkref #0: rel 1663/16384/16390 blk 258
rmgr: Btree       len (rec/tot):     64/    64, tx:        744, lsn: 0/020001B0, prev 0/02000168, desc: INSERT_LEAF off: 275, blkref #0: rel 1663/16384/16396 blk 132
rmgr: Heap        len (rec/tot):     69/    69, tx:        744, lsn: 0/020001F0, prev 0/020001B0, desc: INSERT off: 126, flags: 0x00, blkref #0: rel 1663/16384/16390 blk 258
rmgr: Btree       len (rec/tot):     64/    64, tx:        744, lsn: 0/02000238, prev 0/020001F0, desc: INSERT_LEAF off: 276, blkref #0: rel 1663/16384/16396 blk 132
rmgr: Heap        len (rec/tot):     69/    69, tx:        744, lsn: 0/02000278, prev 0/02000238, desc: INSERT off: 127, flags: 0x00, blkref #0: rel 1663/16384/16390 blk 258
rmgr: Btree       len (rec/tot):     64/    64, tx:        744, lsn: 0/020002C0, prev 0/02000278, desc: INSERT_LEAF off: 277, blkref #0: rel 1663/16384/16396 blk 132
```
```text
rmgr: Heap
len (rec/tot): 69/69
tx: 744
lsn: 0/02000058
prev: 0/01FFFFF0
desc: INSERT
off: 123
flags: 0x00
blkref #0: rel 1663/16384/16390
blk: 258

rmgr: Btree
len (rec/tot): 64/64
tx: 744
lsn: 0/020000A0
prev: 0/02000058
desc: INSERT_LEAF
off: 273
blkref #0: rel 1663/16384/16396
blk: 132
```

```text
blk: 258
Table page number 258


1. Insert row into table
2. Insert key into index                    

Heap INSERT
Btree INSERT

Do this operation
on this page
at this slot
```

## Lab 7: Generate a transaction and isolate its WAL
```sql
SELECT pg_current_wal_lsn();
    -- 0/2718218
INSERT INTO wal_demo(message)
VALUES ('hello wal');

SELECT pg_current_wal_lsn();
    -- 0/2719B98
```

```sh

pg_waldump \
-s 0/2718218 \
-e 0/2719B98
```

```text
rmgr: Sequence    len (rec/tot):     99/    99, tx:        747, lsn: 0/02718218, prev 0/027181E0, desc: LOG rel 1663/16384/16389, blkref #0: rel 1663/16384/16389 blk 0
rmgr: Heap        len (rec/tot):     54/  4566, tx:        747, lsn: 0/02718280, prev 0/02718218, desc: INSERT off: 102, flags: 0x00, blkref #0: rel 1663/16384/16390 blk 540 FPW
rmgr: Btree       len (rec/tot):     53/  1753, tx:        747, lsn: 0/02719458, prev 0/02718280, desc: INSERT_LEAF off: 83, blkref #0: rel 1663/16384/16396 blk 275 FPW
rmgr: Transaction len (rec/tot):     34/    34, tx:        747, lsn: 0/02719B38, prev 0/02719458, desc: COMMIT 2026-06-19 10:09:04.425907 UTC
rmgr: Standby     len (rec/tot):     50/    50, tx:          0, lsn: 0/02719B60, prev 0/02719B38, desc: RUNNING_XACTS nextXid 748 latestCompletedXid 747 oldestRunningXid 748
```

```text
rmgr: Sequence
    id SERIAL PRIMARY KEY
        primary key increment   
    
Heap INSERT
    actual table data
Btree INSERT
    for primary key index
COMMIT
    rmgr: Transaction
    desc: COMMIT
```

```text
FPW

notice, its a full page write
it is a crash protection mechanism
```