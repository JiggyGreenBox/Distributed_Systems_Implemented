You absolutely should experiment on your local PostgreSQL Docker instance.

In fact, I think it's one of the **highest ROI activities** you can do right now.

And no, it's not particularly time-consuming.

---

# What You Should NOT Do

Don't spend two weeks reading about:

* B+ trees
* index internals
* query planners

without touching a database.

You'll retain maybe 20%.

---

# What You SHOULD Do

Spend 30–60 minutes running experiments.

You'll retain far more.

---

# Example Learning Session (1 Hour)

Create a table:

```sql
CREATE TABLE users(
    id SERIAL PRIMARY KEY,
    email TEXT,
    country TEXT,
    age INT
);
```

Insert:

```text
100,000 rows
```

or

```text
1,000,000 rows
```

(using a Python script).

---

Now run:

```sql
EXPLAIN ANALYZE
SELECT *
FROM users
WHERE email='user50000@gmail.com';
```

Observe:

```text
Seq Scan
```

---

Create an index:

```sql
CREATE INDEX idx_email
ON users(email);
```

Run again:

```sql
EXPLAIN ANALYZE
SELECT *
FROM users
WHERE email='user50000@gmail.com';
```

Observe:

```text
Index Scan
```

Suddenly:

* indexes are real
* B+ trees are real
* query planning is real

---

# What Makes This Valuable

You'll start asking questions like:

> Why did PostgreSQL choose Seq Scan?

instead of:

> What is an index?

That's a much more advanced question.

---

# A Great Experiment Sequence

I would do these in order.

---

## Experiment 1

Primary key lookup

```sql
SELECT *
FROM users
WHERE id = 500000;
```

Observe:

```text
Index Scan
```

---

## Experiment 2

No index

```sql
SELECT *
FROM users
WHERE email='abc@gmail.com';
```

Observe:

```text
Seq Scan
```

---

## Experiment 3

Add email index

```sql
CREATE INDEX idx_email
ON users(email);
```

Observe:

```text
Index Scan
```

---

## Experiment 4

Range query

```sql
SELECT *
FROM users
WHERE id BETWEEN 1000 AND 5000;
```

Observe how indexes help range scans.

This is one of the reasons databases love B+ trees.

---

## Experiment 5

Composite index

```sql
CREATE INDEX idx_country_age
ON users(country, age);
```

Try:

```sql
WHERE country='India'
```

and:

```sql
WHERE country='India'
AND age=30
```

and:

```sql
WHERE age=30
```

Now you'll discover the famous:

```text
Leftmost Prefix Rule
```

---

# This Is Interview Gold

Many candidates know:

> Composite indexes exist.

Very few understand:

> Why a query on age alone might not use (country, age).

---

# Experiment 6

Insert Performance

Create:

```text
No indexes
```

Insert:

```text
100,000 rows
```

Measure.

---

Now add:

```text
5 indexes
```

Insert:

```text
100,000 rows
```

again.

You'll discover:

```text
Reads faster
Writes slower
```

which is one of the most important database tradeoffs.

---

# Experiment 7

Low Selectivity

Create:

```text
country
```

with values:

```text
India
US
UK
```

for a million rows.

Create index:

```sql
CREATE INDEX idx_country
ON users(country);
```

Run:

```sql
SELECT *
FROM users
WHERE country='India';
```

You may see PostgreSQL choose:

```text
Seq Scan
```

even though an index exists.

This is a fascinating lesson.

---

# The Real Goal

Don't try to become a database internals expert yet.

Your goal is:

When somebody says:

```text
Create an index.
```

you should immediately think:

```text
What kind?

How selective?

What queries?

What write cost?

What execution plan?
```

That's backend-engineer thinking.

---

# How Much Time Should You Spend?

Honestly:

### Week 1

Indexes

* primary
* secondary
* composite

---

### Week 2

EXPLAIN ANALYZE

* Seq Scan
* Index Scan
* Bitmap Scan

---

### Week 3

Joins

* Nested Loop
* Hash Join
* Merge Join

---

### Week 4

Transactions

* ACID
* isolation levels
* locking

At that point you'll know more about databases than many interview candidates.

---

For your specific goal (system design + backend engineering), I'd choose **one evening of hands-on PostgreSQL experiments** over **three evenings reading database theory**. The theory becomes much easier to understand once you've actually watched PostgreSQL switch between a sequential scan and an index scan on your own machine.
