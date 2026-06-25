# Create the Replica Container

## Create a Replica Volume
```sh
volumes:
  primary_data:
  replica_data:
```

add to service
```sh
postgres_replica:
  image: postgres:16-alpine
  container_name: postgres_replica

  ports:
    - "5436:5432"

  environment:
    POSTGRES_PASSWORD: postgres

  volumes:
    - replica_data:/var/lib/postgresql/data

  depends_on:
    - postgres_primary
```

### Easiest Lab Approach
Create the volume:
```sh
# Create the volume:
docker volume create postgres-replication-lab_replica_data

# Find its path:
docker volume inspect postgres-replication-lab_replica_data
    # "Mountpoint": "/var/lib/docker/volumes/postgres-replication-lab_replica_data/_data",


# copy from primary
docker cp \
postgres_primary:/tmp/replica_backup/. \
/tmp/replica_bootstrap

# check host
ls /tmp/replica_bootstrap

# Then copy into the replica volume:
sudo cp -R \
/tmp/replica_bootstrap/. \
/var/lib/docker/volumes/postgres-replication-lab_replica_data/_data/

```

### Make It A Standby
```sh
sudo touch \
/var/lib/docker/volumes/postgres-replication-lab_replica_data/_data/standby.signal
```
This file is magical. Means Start as a replica

### Configure Primary Connection
```sh
sudo nano \
/var/lib/docker/volumes/postgres-replication-lab_replica_data/_data/postgresql.auto.conf
```
append:
```sh
primary_conninfo = 'host=postgres_primary port=5432 user=replicator password=replica_pass'
```

### What Happens On Startup?
```sh
1. standby.signal exists

2. Enter recovery mode

3. Connect to postgres_primary

4. Request WAL after
    0/4000028

5. Replay WAL forever

```

### connect to replica via pgadmin
```sh
docker exec -it postgres_replica psql -U postgres -d replication_lab
```

on primary:
```sql
INSERT INTO users(name)
VALUES ('wal_replication_test');
```

on replica:
```sql
SELECT * FROM users;
```

on primary:
```sql
SELECT
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;

"client_addr"	"state"	"sent_lsn"	"write_lsn"	"flush_lsn"	"replay_lsn"
"172.21.0.3"	"streaming"	"0/50005D0"	"0/50005D0"	"0/50005D0"	"0/50005D0"

```

```sh
# Primary has sent WAL up to this point over the network.
sent_lsn = 0/50005D0

# Replica received the WAL and wrote it to its WAL files.
write_lsn = 0/50005D0

# Replica has fsync'ed WAL to disk.
flush_lsn = 0/50005D0

# The startup process has actually applied the WAL changes to the 
# replica's table/index pages.
replay_lsn = 0/50005D0

sent_lsn =
write_lsn =
flush_lsn =
replay_lsn

so  
replication lag = 0
```

## create lag intentionally
### Stop replay on replica
on replica
```sh
SELECT pg_wal_replay_pause();
```

on primary
```sh
INSERT INTO users(name)
VALUES ('lag_test');
```

```
"client_addr"	"state"	"sent_lsn"	"write_lsn"	"flush_lsn"	"replay_lsn"
"172.21.0.3"	"streaming"	"0/5000820"	"0/5000820"	"0/5000820"	"0/50005D0"

Replica has received WAL
but has not applied it.
```

on replica
```sh
SELECT * FROM users;
SELECT pg_wal_replay_resume();
SELECT * FROM users;
```

# synchronous replication
the tradeoff
```text
Async replication (what we have now)

Client COMMIT
      |
      v
Primary WAL fsync
      |
      v
Return success
      |
      v
Replica catches up later

Risk:
Primary dies before replica receives WAL
```
vs
```text
Sync replication

Client COMMIT
      |
      v
Primary WAL fsync
      |
      v
Replica confirms WAL received/flushed
      |
      v
Return success

Benefit:
No acknowledged data loss
Cost:
Higher latency + replica failure can block writes
```

### Step 1: Convert your setup to synchronous replication
```sh
docker exec -it postgres_replica bash

vi /var/lib/postgresql/data/postgresql.auto.conf

# change
primary_conninfo = 'host=postgres_primary port=5432 user=replicator password=replica_pass'
# to
primary_conninfo = 'host=postgres_primary port=5432 user=replicator password=replica_pass application_name=replica1'

docker restart postgres_replica
```
```text
application_name=replica1
is how primary identifies the standby.
```

### Step 2 — Configure primary
```sh
docker exec -it postgres_primary bash

vi /var/lib/postgresql/data/postgresql.conf
    synchronous_standby_names = 'replica1'

docker restart postgres_primary
```

### Step 3 — Verify
```sql
SELECT
application_name,
state,
sync_state
FROM pg_stat_replication;

"replica1"	"streaming"	"sync"
```

### Step 4 — Test the blocking behavior
On primary:
```sql
BEGIN;

INSERT INTO users(name)
VALUES ('sync_test');

COMMIT;
```

Now stop replica:
```sh
docker stop postgres_replica
```

```sql
BEGIN;
INSERT INTO users(name)
VALUES ('will_wait');
COMMIT;
```

### Step 5 — Bring replica back
```sh
docker start postgres_replica
```

there are 3 levels:
```text
synchronous_commit = off
    |
    v
don't wait for local WAL flush
    The WAL may not even be flushed to disk yet.
        Power failure, Last few committed transactions disappear

synchronous_commit = on
    |
    v
wait for primary WAL flush
    WAL exists on disk, Recovery can replay it


synchronous_commit = remote_apply
    |
    v
wait until replica has replayed the transaction
```
```text
remote_write vs remote_flush vs remote_apply

    remote_write
        replicas RAM, not fdisk
            fast
        
    remote_flush
        WAL to replica disk
            remote_flush is the gold standard for mission-critical corporate operations.

    remote_apply
        WAL is applied on replica
        no lag

        very slow
            used in per transactions
                If an admin revokes a user's API access, that change must become 
                instantly visible across all read-replicas globally to block 
                malicious traffic immediately.

```