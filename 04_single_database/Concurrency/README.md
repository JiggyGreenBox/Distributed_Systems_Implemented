That makes total sense. Keeping your architectural environments separated avoids any risk of lock leaking or schema pollution from the previous exercises.

Let's spin down the previous setup and create a brand-new container stack dedicated entirely to **Week 4: Concurrency, MVCC, and Locking Dynamics**.

---

## 1. Setting Up the pristine Concurrency Lab

Create a fresh directory for this module and save this file as `docker-compose.yml`. We will map this instance to a different port (`5434`) and label the database `concurrency_safari_db`.

```yaml
version: '3.8'

services:
  postgres_concurrency:
    image: postgres:16-alpine
    container_name: postgres_concurrency
    environment:
      - POSTGRES_USER=tx_user
      - POSTGRES_PASSWORD=tx_password
      - POSTGRES_DB=concurrency_safari_db
    ports:
      - "5434:5432"  # Shifting port to 5434 to keep it clean
    volumes:
      - concurrency_data:/var/lib/postgresql/data

  pgadmin_concurrency:
    image: dpage/pgadmin4
    container_name: pgadmin_concurrency
    environment:
      - PGADMIN_DEFAULT_EMAIL=admin@concurrency.com
      - PGADMIN_DEFAULT_PASSWORD=admin_password
    ports:
      - "5052:80"   # Shifting port to 5052
    depends_on:
      - postgres_concurrency

volumes:
  concurrency_data:

```

### Connection Details for pgAdmin (`http://localhost:5052`):

* **Host name/address:** `postgres_concurrency`
* **Port:** `5432`
* **Maintenance database:** `concurrency_safari_db`
* **Username / Password:** `tx_user` / `tx_password`

---

## 2. Seeding the High-Contention Ledger

Once you are connected via pgAdmin, open up a Query Tool window against `concurrency_safari_db` and run this script to build our target infrastructure:

```sql
-- Create a financial ledger table to track race conditions
CREATE TABLE bank_accounts (
    account_id INT PRIMARY KEY,
    owner_name VARCHAR(50),
    balance NUMERIC(12, 2)
);

-- Seed two target accounts
INSERT INTO bank_accounts (account_id, owner_name, balance) VALUES
(1, 'Alice', 1000.00),
(2, 'Bob', 500.00);

```

---

## 3. Preparing Your Interface for Concurrency

To actually witness locks and isolation anomalies, **you need to act as two different application instances simultaneously.** In pgAdmin, look at the top toolbar and click the **Query Tool** icon twice to open up two completely distinct, side-by-side transaction tabs:

* **Tab A** (Will act as Microservice Instance A)
* **Tab B** (Will act as Microservice Instance B)

---

## Lab Experiment 1: The Classic Write-Lock Block

By default, PostgreSQL operates under the **Read Committed** isolation level. This means a transaction cannot see changes made by other transactions until those changes are officially committed. However, if two updates try to modify the *same physical row*, a lock conflict occurs.

Let's execute a race condition. Follow these steps precisely:

### Step 1: Start a Transaction in Tab A

Paste this into **Tab A** and execute it. This opens a transaction block and alters Alice's balance, but does **not** commit yet.

```sql
BEGIN;
UPDATE bank_accounts 
SET balance = balance - 100 
WHERE account_id = 1;

-- Check your local state inside this transaction
SELECT * FROM bank_accounts WHERE account_id = 1;

```

*(You will see Alice's balance drop to 900.00 locally inside Tab A).*

### Step 2: Attempt a Concurrent Update in Tab B

Switch over to **Tab B** (representing a completely separate thread) and attempt to run this transaction immediately:

```sql
BEGIN;
UPDATE bank_accounts 
SET balance = balance - 50 
WHERE account_id = 1;

```

**Observe the state of Tab B:** The query does not finish. The execution spinner keeps spinning indefinitely.

### What is happening under the hood?

Because Tab A modified the row where `account_id = 1`, Postgres attached an exclusive **Row-Level Write Lock (X-Lock)** to that row. When Tab B came along trying to write to that exact same row, Postgres forced Tab B's session into a queue. Tab B is completely frozen, waiting for Tab A to release its lock.

---

## Testing the Release

To unblock the system, go back to **Tab A** and type:

```sql
COMMIT;

```

Once you execute that commit in Tab A, instantly look back at **Tab B**.

* You will notice Tab B's spinner immediately stops and completes successfully!
* Run `COMMIT;` in **Tab B** as well to clear its transaction.

Let me know once you have successfully spun up this isolated container stack and verified that Tab B successfully waited for Tab A. Once this baseline works, we can look at **MVCC Hidden Columns (`xmin`, `xmax`)** to see how Postgres tracks these changes under the hood without blocking readers!