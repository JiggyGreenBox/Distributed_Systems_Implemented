# Replication Slots
### Step 0: See current state
First make sure we are in asynchronous state
```sql
SHOW synchronous_standby_names;
    -- replica1
    -- this is synchronous
ROLLBACK;
ALTER SYSTEM SET synchronous_standby_names = '';
SELECT pg_reload_conf();

-- verfiy
SHOW synchronous_standby_names;
```
On primary:
```sql
SELECT
    application_name,
    state,
    sent_lsn,
    replay_lsn
FROM pg_stat_replication;

"application_name"	"state"	"sent_lsn"	"replay_lsn"
"replica1"	"streaming"	"0/5000FE0"	"0/5000FE0"

SELECT * FROM pg_replication_slots;
    -- 0 rows
```
### Step 1: Create a physical replication slot
```sql
SELECT *
FROM pg_create_physical_replication_slot('replica_slot');
"slot_name"	"lsn"
"replica_slot"	

SELECT
    slot_name,
    slot_type,
    active,
    restart_lsn
FROM pg_replication_slots;

"slot_name"	"slot_type"	"active"	"restart_lsn"
"replica_slot"	"physical"	false	

```
### Step 2: Tell replica to use the slot
```sh
docker exec -it postgres_replica bash

vi /var/lib/postgresql/data/postgresql.auto.conf
# add
primary_slot_name = 'replica_slot'

docker restart postgres_replica
```
### Step 3: Verify slot is active
On primary:
```sql
SELECT
    slot_name,
    active,
    restart_lsn
FROM pg_replication_slots;

"slot_name"	"active"	"restart_lsn"
"replica_slot"	true	"0/50010C8"
```
### Step 4: Stop replica
```sh
docker stop postgres_replica
```
on primary:
```sql
SELECT
    slot_name,
    active,
    restart_lsn
FROM pg_replication_slots;
"slot_name"	"active"	"restart_lsn"
"replica_slot"	false	"0/50010C8"

active = false
```

### Step 5: Generate WAL on primary
```sql
CREATE TABLE wal_test (
    id SERIAL PRIMARY KEY,
    payload TEXT
);

INSERT INTO wal_test(payload)
SELECT repeat('x', 1000)
FROM generate_series(1,50000);
```
This creates WAL while the replica is offline.

### Step 6: Observe retained WAL
```sql
SELECT
    slot_name,
    restart_lsn,
    pg_current_wal_lsn()
FROM pg_replication_slots;

-- restart_lsn       far behind
-- current_wal_lsn   much newer
```
You can quantify it:
```sql
SELECT
    slot_name,
    pg_size_pretty(
        pg_wal_lsn_diff(
            pg_current_wal_lsn(),
            restart_lsn
        )
    ) AS retained_wal
FROM pg_replication_slots;

"slot_name"	"retained_wal"
"replica_slot"	"164 MB"
```

### Step 7: Inspect pg_wal
```sh
docker exec -it postgres_primary bash
ls -lh $PGDATA/pg_wal
```
```text
You should notice WAL segments accumulating.

Normally PostgreSQL would recycle some of them.

The slot prevents that.
```
### Step 8: Restart replica
```sh
docker start postgres_replica
# watch logs
docker logs -f postgres_replica
```

### Step 9: Watch slot recover
```sql
SELECT
    slot_name,
    active,
    restart_lsn,
    pg_size_pretty(
        pg_wal_lsn_diff(
            pg_current_wal_lsn(),
            restart_lsn
        )
    ) AS retained_wal
FROM pg_replication_slots;

"slot_name"	"active"	"restart_lsn"	"retained_wal"
"replica_slot"	true	"0/F41A288"	"0 bytes"
```
```text
without a slot the local system might delete its WAL
if we have a slot it will wait for replica

now issue is if replica is down for a long time
we might fill up the disk
```