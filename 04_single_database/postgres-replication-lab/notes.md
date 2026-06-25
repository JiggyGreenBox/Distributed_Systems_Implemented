# Setup for primary and replica
## step 0: make this dir structure
```sh
tree postgres-replication-lab/
postgres-replication-lab/
├── docker-compose.yml
├── notes.md
├── primary
│   └── init.sql
└── replica

```
## step 1: start the primary
```sh
services:
  postgres_primary:
    image: postgres:16-alpine
    container_name: postgres_primary

    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: replication_lab

    ports:
      - "5432:5432"

    volumes:
      - primary_data:/var/lib/postgresql/data
      - ./primary/init.sql:/docker-entrypoint-initdb.d/init.sql

    command:
      - postgres
      - -c
      - wal_level=replica
      - -c
      - max_wal_senders=10
      - -c
      - max_replication_slots=10

  pgadmin:
    image: dpage/pgadmin4
    container_name: pgadmin_replication

    environment:
      PGADMIN_DEFAULT_EMAIL: admin@replication.com
      PGADMIN_DEFAULT_PASSWORD: admin

    ports:
      - "5050:80"

    depends_on:
      - postgres_primary

volumes:
  primary_data:
```
Notice the first replication settings:
```text
wal_level=replica
max_wal_senders=10
max_replication_slots=10
```

## step 2: init.sql
```sql
CREATE ROLE replicator
WITH REPLICATION
LOGIN
PASSWORD 'replica_pass';

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name TEXT
);

INSERT INTO users(name)
VALUES ('alice');
``` 

## Step 3: Start
```sh
docker compose up -d
docker ps
```

## step 4: connect
```sh
docker exec -it postgres_primary psql -U postgres -d replication_lab
```

## Step 5: Verify Replication Settings
```sh
http://localhost:5050

Email:    admin@replication.com
Password: admin

Host: postgres_primary
Port: 5432
Database: replication_lab
Username: postgres
Password: postgres
```
```sql
SHOW wal_level;
    -- replica

SHOW max_wal_senders;
    -- 10

SHOW max_replication_slots;
    -- 10


SELECT pg_current_wal_lsn();
    -- 0/19658B8
```

## Step 6: Allow Replication Connections
```sh
docker exec -it postgres_primary sh

# Find pg_hba.conf:
find $PGDATA -name pg_hba.conf
    # /var/lib/postgresql/data/pg_hba.conf

vi $PGDATA/pg_hba.conf
cat $PGDATA/pg_hba.conf
```
Add:
```sh
host replication replicator 0.0.0.0/0 scram-sha-256
```
This means:
```sh
host         = TCP connection
replication  = replication protocol
replicator   = replication user
0.0.0.0/0    = anywhere on docker network
scram-sha-256 = password auth
```

```sql
SELECT pg_reload_conf();

SHOW hba_file;
```

## Step 7: Create a Place for Replica Data
```sh
mkdir -p replica/data
# or use gui from vscode

postgres-replication-lab/

├── docker-compose.yml
├── primary/
│   └── init.sql
└── replica/
    └── data/
```

## Step 8: Take a Base Backup
```sh
docker exec -it postgres_primary bash

export PGPASSWORD=replica_pass
pg_basebackup \
  -h localhost \
  -D /tmp/replica_backup \
  -U replicator \
  -Fp \
  -Xs \
  -P

# It should ask for:
    # replica_pass                                                              
``` 

check
```text
ls -lah /tmp/replica_backup
```

lets check some files
#### backup_label
```sh
cat /tmp/replica_backup/backup_label
```
```text
START WAL LOCATION: 0/4000028 (file 000000010000000000000004)
CHECKPOINT LOCATION: 0/4000060
BACKUP METHOD: streamed
BACKUP FROM: primary
START TIME: 2026-06-25 08:12:41 UTC
LABEL: pg_basebackup base backup
START TIMELINE: 1
```
#### pg_wal
```sh
ls -lh /tmp/replica_backup/pg_wal
```

### At this moment it is not a replica. Its A snapshot of the primary

```text
Crash Recovery
    WAL already on disk

Replication
    WAL arrives over network
```