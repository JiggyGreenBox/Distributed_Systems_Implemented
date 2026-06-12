Absolutely. This is where PostgreSQL becomes really interesting.

The lock experiment taught you:

```text
Writers block writers
```

Now you're about to learn:

```text
Writers do NOT block readers
```

and that's the magic of MVCC.

---

# First: Observe xmin and xmax

Run:

```sql
SELECT
    xmin,
    xmax,
    ctid,
    *
FROM bank_accounts
WHERE account_id = 1;
```

You might see:

```text
xmin | xmax | ctid
------------------
725  | 0    | (0,3)
```

Interpretation:

```text
xmin = transaction that created this row version
xmax = transaction that deleted/updated this row version
```

The important thing:

```text
xmax = 0
```

means:

```text
This row version is currently alive
```

---

# Now let's create multiple versions

Run:

```sql
UPDATE bank_accounts
SET balance = balance - 100
WHERE account_id = 1;
```

Now check again:

```sql
SELECT
    xmin,
    xmax,
    ctid,
    *
FROM bank_accounts
WHERE account_id = 1;
```

You may see:

```text
xmin | xmax | ctid
------------------
731  | 0    | (0,5)
```

Notice:

```text
xmin changed
ctid changed
```

This is the first mind-bending part.

---

# PostgreSQL did NOT update the row

Conceptually it did:

```text
OLD VERSION

balance = 1000
xmin = 725
xmax = 731
```

and created:

```text
NEW VERSION

balance = 900
xmin = 731
xmax = 0
```

The old row still exists.

The new row exists too.

This is MVCC.

---

# Let's prove it

Install:

```sql
CREATE EXTENSION pageinspect;
```

Then find the table page:

```sql
SELECT ctid, *
FROM bank_accounts;
```

Suppose:

```text
ctid = (0,5)
```

The page number is:

```text
0
```

Inspect the page:

```sql
SELECT *
FROM heap_page_items(get_raw_page('bank_accounts', 0));
```

Now you'll literally see multiple row versions.

Something like:

```text
lp | t_xmin | t_xmax
--------------------
1  | 725    | 731
2  | 731    | 0
```

That's the actual MVCC chain.

---

# The big experiment

Open:

```text
Tab A
Tab B
```

---

## Tab A

```sql
BEGIN;

UPDATE bank_accounts
SET balance = 700
WHERE account_id = 1;
```

DO NOT COMMIT.

---

## Tab A sees

```sql
SELECT balance
FROM bank_accounts
WHERE account_id = 1;
```

Result:

```text
700
```

---

## Tab B sees

```sql
SELECT balance
FROM bank_accounts
WHERE account_id = 1;
```

Result:

```text
900
```

Not blocked.

Not waiting.

Immediately returns.

---

# Why?

Because Tab B ignores the uncommitted version.

Think of the page as:

```text
Version A
balance=900
xmin=731
xmax=740
```

and

```text
Version B
balance=700
xmin=740
xmax=0
```

Transaction 740 has not committed.

So Tab B says:

```text
I cannot see version B.
```

and continues reading version A.

---

# This is the key insight

Many databases historically used:

```text
Readers block writers
Writers block readers
```

Postgres largely avoids that.

Instead:

```text
Readers read old versions
Writers create new versions
```

Hence:

```text
Multi-Version Concurrency Control
```

---

# Next experiment (very important)

After you've observed xmin/xmax, run:

```sql
SELECT
    pid,
    usename,
    state,
    query
FROM pg_stat_activity;
```

and

```sql
SELECT *
FROM pg_locks;
```

while one transaction is open.

You'll start seeing:

```text
Row locks
Transaction locks
Relation locks
```

This is where MVCC and locking meet.

The progression I'd recommend is:

```text
1. xmin/xmax
2. heap_page_items()
3. Readers seeing old versions
4. pg_locks
5. Repeatable Read
6. Serializable
7. Deadlocks
8. VACUUM cleaning old row versions
```

The moment you see `heap_page_items()` showing both the old and new row versions on the same page, MVCC usually "clicks" permanently. That's one of the most valuable PostgreSQL internals experiments you can do.
