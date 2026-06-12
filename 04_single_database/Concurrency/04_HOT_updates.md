HOT updates are one of PostgreSQL's smartest optimizations.

You actually observed them earlier:

```text
HEAP_HOT_UPDATED
HEAP_ONLY_TUPLE
```

in the tuple flags.

---

# The Problem

Suppose you have:

```sql
CREATE TABLE users (
    id INT PRIMARY KEY,
    name TEXT,
    last_seen TIMESTAMP
);

CREATE INDEX idx_name ON users(name);
```

Notice:

```text
Indexed:
    id
    name

Not indexed:
    last_seen
```

---

Now run:

```sql
UPDATE users
SET last_seen = NOW()
WHERE id = 1;
```

MVCC says:

```text
Old tuple remains

New tuple created
```

So PostgreSQL creates:

```text
v1 -> v2
```

---

# Without HOT

PostgreSQL would also need to update every index.

Why?

Because indexes contain pointers to tuple locations.

Old tuple:

```text
ctid=(0,1)
```

New tuple:

```text
ctid=(0,2)
```

The index would still point at:

```text
(0,1)
```

which is obsolete.

Therefore PostgreSQL would have to:

```text
Delete old index entry

Insert new index entry
```

for every index.

Expensive.

---

# HOT Optimization

HOT means:

```text
Heap Only Tuple
```

If the UPDATE does **not modify indexed columns**, PostgreSQL can avoid touching indexes.

Example:

```sql
UPDATE users
SET last_seen = NOW()
WHERE id = 1;
```

No indexed column changed.

So PostgreSQL does:

```text
Old tuple
    ↓
New tuple
```

inside the heap page.

And leaves the index alone.

---

# Conceptual Picture

Without HOT:

```text
Index
  ↓
Tuple v1

UPDATE

Index
  ↓
Tuple v2
```

Index maintenance required.

---

With HOT:

```text
Index
  ↓
Tuple v1
    ↓
Tuple v2
    ↓
Tuple v3
```

The index still points to v1.

PostgreSQL follows the HOT chain to reach the newest version.

No index updates needed.

---

# Why it works

Suppose index lookup finds:

```text
(0,1)
```

PostgreSQL lands on:

```text
Alice=1000
```

and sees:

```text
ctid=(0,3)
```

meaning:

```text
newer version exists
```

Then it walks:

```text
v1 -> v2 -> v3
```

until it finds the visible version.

Sound familiar?

That's exactly what you were already observing with:

```text
ctid
xmin
xmax
```

---

# Conditions for HOT

HOT can happen only when:

### 1. Indexed columns are unchanged

Good:

```sql
UPDATE users
SET last_seen = NOW();
```

Bad:

```sql
UPDATE users
SET name = 'Bob';
```

because:

```text
name
```

is indexed.

---

### 2. Enough free space exists on the page

PostgreSQL wants the new tuple version on the same page.

If page is full:

```text
HOT impossible
```

---

# Why HOT matters

Imagine:

```sql
UPDATE sessions
SET last_accessed = NOW();
```

millions of times per day.

Without HOT:

```text
Heap writes
+
Index writes
```

With HOT:

```text
Heap writes only
```

Much cheaper.

---

# Why system designers care

Workloads like:

```text
user activity
session updates
timestamps
counters
status flags
```

often update non-indexed columns.

HOT can dramatically reduce:

```text
CPU
IO
Index bloat
VACUUM work
```

---

# Relating to your experiment

Earlier you saw:

```text
lp=1
Alice=1000

lp=3
Alice=900

lp=4
Alice=700
```

and flags:

```text
HEAP_HOT_UPDATED
HEAP_ONLY_TUPLE
```

That happened because:

```text
balance
```

was not indexed.

So PostgreSQL could create:

```text
1000 -> 900 -> 700
```

without modifying any indexes.

You accidentally built a perfect HOT update example.

---

# Interview-level summary

```text
HOT (Heap Only Tuple) Update

When an UPDATE changes only non-indexed columns,
PostgreSQL creates a new tuple version on the same heap page
and avoids updating indexes.

Benefits:
    Less index maintenance
    Less I/O
    Better update performance
    Reduced index bloat
```

Once you understand HOT, you can immediately see why database schema design matters: adding an index can speed up reads, but it can also make many updates more expensive because HOT updates become impossible for changes to that indexed column.
