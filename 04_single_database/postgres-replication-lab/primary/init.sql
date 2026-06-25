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