# checkpoints
```text
A checkpoint is the bridge that syncs your fast, sequential in-memory 
changes back down into the slow, random-access 8KB table data pages 
on disk.
```

### Dirty Pages
 1. You run an `INSERT` or `UPDATE`.
 2. Postgres writes the change to the sequential WAL file on disk, but it updates the actual 8KB data page only in shared memory (RAM).
 3. These modified pages sitting in RAM are called **Dirty Pages**.


## the cycle:
 1. dirty files are flushed to disk by the checkpointer.
 2. latest LSN is updated int pg_control. 
 3. old wal files are now safely deleted. 

## how we know which pages are dirty?
```text
When PostgreSQL boots up, it allocates a massive chunk of your system 
RAM called the Shared Buffers (typically configured to 25% to 40% of 
total system memory). This RAM is divided into a massive grid of 
individual 8KB slots, called Buffer Pages.
```

```text
To manage this grid without constantly scanning raw bytes, Postgres 
maintains an internal array of lightweight metadata structs called 
Buffer Headers. Every single 8KB page in RAM has an associated header.
```

```text
[ Shared Buffers RAM ]
┌────────────────────────────────────────┐
│ Buffer Header:                         │
│  ├── Tag: Table 16390, Blk 258         │
│  ├── LSN: 0/02000058                   │
│  └── Flags: [ BM_DIRTY = 1 ] ◄─── Dirty│
├────────────────────────────────────────┤
│ 8KB Page Content (Modified Data)       │
└────────────────────────────────────────┘
```

## When is it safe to delete WAL?
```text
Once every single buffer header pointing to an LSN older than the 
checkpoint boundary has its BM_DIRTY bit successfully cleared back to 
0 and flushed.
```

## Redo LSN
```text
The checkpoint boundary LSN is officially called the Redo LSN. It is 
the absolute line in the sand that determines where Postgres must 
start replaying history if the database crashes.

It represents a guarantee: Every data mutation that happened before 
the Redo LSN has been safely and permanently flushed from RAM down 
into the 8KB table files on disk.
```

```sh
docker ps

docker exec -it postgres_durability bash
# OR
docker exec -it postgres_durability sh

pg_controldata -D /var/lib/postgresql/data
```

```text
Latest checkpoint location:           0/2719C80
Latest checkpoint's REDO location:    0/2719C80
Latest checkpoint's REDO WAL file:    000000010000000000000002
```

## Crash Recovery
```text
1. Read pg_control
2. Find latest checkpoint
3. Read Redo LSN
4. Start scanning WAL from Redo LSN
5. Replay all committed changes
6. Rebuild database state
7. Open database for clients
```

# Crash Simulation
Create some data:
```sql
INSERT INTO wal_demo(message)
SELECT 'crash-test-' || g
FROM generate_series(1,10000) g;
```

Force a checkpoint:
```sql
CHECKPOINT;
```

Insert more rows:
```sql
INSERT INTO wal_demo(message)
SELECT 'after-checkpoint-' || g
FROM generate_series(1,10000) g;
```

kill db
```sh
docker kill postgres_durability
docker start postgres_durability
docker logs postgres_durability
```

Logs:
```text
database system was not properly shut down; automatic recovery in progress
...
redo starts at 0/288A240
...
redo done at 0/2A0C2D8
```
Everything between those two LSNs was reconstructed.
```text
Recovery replayed WAL records
from:
0/288A240
to:
0/2A0C2D8
```

Conceptually
```text
read pg_control

redo_lsn = 0/288A240

open WAL

while(records exist)
{
    replay record
}
```