This is the perfect way to kick off **Week 3: Joins**. Moving to a clean container and database will let us isolate our join metrics without any noise from our previous scaling experiments.

To understand how a database joins tables, you must move past the conceptual Venn diagrams taught in school. Databases do not think in Venn diagrams; they think in **Execution Algorithms**.

When you write `SELECT * FROM table_a JOIN table_b`, the PostgreSQL query planner evaluates your tables' sizes, indexes, and cardinality, and picks one of three concrete join strategies: **Nested Loop**, **Hash Join**, or **Merge Join**.

Let's set up your new clean sandbox and generate the exact data distributions required to trigger all three join types.

---

## 1. The Clean Environment (`docker-compose.yml`)

Create a new directory for this week's work and drop in this fresh Compose file. We will use a pristine database called `join_mechanics_db`.

```yaml
version: '3.8'

services:
  postgres_joins:
    image: postgres:16-alpine
    container_name: postgres_joins
    environment:
      - POSTGRES_USER=join_user
      - POSTGRES_PASSWORD=join_password
      - POSTGRES_DB=join_mechanics_db
    ports:
      - "5433:5432"  # Shifting port to 5433 to avoid conflicts with Week 2
    volumes:
      - join_data:/var/lib/postgresql/data

  pgadmin_joins:
    image: dpage/pgadmin4
    container_name: pgadmin_joins
    environment:
      - PGADMIN_DEFAULT_EMAIL=admin@join.com
      - PGADMIN_DEFAULT_PASSWORD=admin_password
    ports:
      - "5051:80"   # Shifting port to 5051
    depends_on:
      - postgres_joins

volumes:
  join_data:

```

### How to connect in pgAdmin:

* URL: `http://localhost:5051`
* Host name: `postgres_joins`
* Port: `5432`
* Username/Password: `join_user` / `join_password`

---

## 2. Seed the Core Relational Architecture

Once you open the Query Tool on `join_mechanics_db`, run the script below. We are creating two tables: `users` (small) and `api_keys` (medium).

```sql
-- 1. Create a core Users table
CREATE TABLE users (
    user_id INT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    account_tier VARCHAR(20) NOT NULL
);

-- 2. Create an API Keys table linked back to users
CREATE TABLE api_keys (
    key_id INT PRIMARY KEY,
    user_id INT, -- Intentionally NO foreign key or index yet to see raw behaviors
    api_key_string VARCHAR(64) NOT NULL,
    is_active BOOLEAN NOT NULL
);

-- 3. Seed 1,000 Users (Small table)
INSERT INTO users (user_id, username, account_tier)
SELECT 
    i,
    'user_name_' || i,
    (ARRAY['FREE', 'PREMIUM', 'ENTERPRISE'])[floor(random() * 3 + 1)]
FROM generate_series(1, 1000) AS i;

-- 4. Seed 50,000 API Keys (Medium table - multiple keys per user)
INSERT INTO api_keys (key_id, user_id, api_key_string, is_active)
SELECT 
    s,
    floor(random() * 1000 + 1)::int, -- Maps perfectly back to our 1,000 users
    md5(random()::text),
    (random() > 0.1) -- 90% active
FROM generate_series(1, 50000) AS s;

```

---

## 3. Dissecting the 3 Join Algorithms

Now that the data is seeded, we will write specific queries to force Postgres to showcase each algorithmic strategy.

### Algorithm A: The Hash Join

A **Hash Join** is chosen when joining a smaller table to a much larger table, and neither side is ordered.

Run this query:

```sql
EXPLAIN ANALYZE
SELECT u.username, k.api_key_string 
FROM users u
JOIN api_keys k ON u.user_id = k.user_id;

```

* **How it works:** Postgres reads the smaller table (`users`) entirely into RAM and builds an in-memory **Hash Table** using the join key (`user_id`). Then, it streams the larger table (`api_keys`) row-by-row, hashes its `user_id`, and instantly checks the hash table for a match ($O(1)$ lookup).

---

### Algorithm B: The Nested Loop

A **Nested Loop** is chosen when one side of the join is extremely small (e.g., looking up a single specific user) and the other side has an index it can use to do precision point-lookups.

Let's simulate this by providing a tight filter. Run this query:

```sql
EXPLAIN ANALYZE
SELECT u.username, k.api_key_string 
FROM users u
JOIN api_keys k ON u.user_id = k.user_id
WHERE u.user_id = 42;

```

* **How it works:** It acts exactly like a nested `for` loop in code. The database grabs the outer row (`users` where ID is 42) and then runs an inner loop against the second table to grab matching keys.

```python
for user_row in users_filter:
    # If an index exists on api_keys.user_id, this inner lookup is O(log N)
    for key_row in api_keys.find(user_id=user_row.user_id):
        emit(user_row, key_row)

```

---

### Algorithm C: The Merge Join

A **Merge Join** is chosen when both datasets are exceptionally large, but they are **already sorted** by the join key (usually because of an index or an explicit `ORDER BY`).

To see a Merge Join in action right now without adding indexes, we have to force Postgres to sort the tables first. Run this query:

```sql
EXPLAIN ANALYZE
SELECT u.username, k.api_key_string 
FROM users u
JOIN api_keys k ON u.user_id = k.user_id
ORDER BY u.user_id;

```

* **How it works:** If both tables are sorted by `user_id`, Postgres sets two pointers at the top of both tables. It compares them: if they match, it emits the row. If one pointer has a smaller ID, it advances that pointer forward. It marches through both tables in a single, highly efficient linear scan ($O(N + M)$).

---

## The Week 3 Sandbox Challenge

Boot up your new stack and run these three `EXPLAIN ANALYZE` scripts.

Take a close look at the output structures. For the **Hash Join**, what does it say about the `Buckets` and `Batches` it allocated in memory? For the **Merge Join**, did Postgres have to perform an explicit `Sort` operation on the `api_keys` table before merging?