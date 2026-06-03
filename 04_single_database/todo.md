Moving straight into the relational database tier is the absolute right call to round out your system design mastery.

For someone with your technical background, **do not spend weeks reading pure academic database theory first.** Standard textbook theory (like normalization forms or manual relational algebra) doesn’t match the high-leverage architectural patterns tested in Senior IC system design loops.

Instead, the most effective approach is a **Hybrid Strategy**: learn a slice of core physical storage theory, and immediately implement it practically in your sandbox using PostgreSQL to see how it breaks under multi-instance traffic.

Here is the exact roadmap I recommend for your database tier, moving from core mechanics to advanced distributed scale.

---

## Phase 1: Storage Internals & The "Single Node" Performance

Before you can replicate data across multiple database servers, you must understand exactly how a single PostgreSQL instance handles data under the hood. Interviewers love to drill down into database performance bottlenecks.

* **The Theory to Learn:** * **How Indexes Work:** Understand B-Trees vs. LSM-Trees (Postgres uses B-Trees for standard indexes). Learn what a "Sequential Scan" vs. an "Index Scan" looks like.
* **The Write-Ahead Log (WAL):** Understand how Postgres guarantees ACID compliance by writing transactions to an append-only log on disk *before* updating the actual table files.


* **The Sandbox Implementation:**
* Spin up a PostgreSQL container in your `docker-compose.yml`.
* Write a script to seed it with 1 million mock user request logs.
* Run complex queries and use `EXPLAIN ANALYZE` in Postgres to visually read the query planner's execution path. Learn how adding a composite index drastically optimizes lookup times.



---

## Phase 2: Connection Isolation & Race Conditions

Since your sandbox already has multiple application replicas (`rate_limiter_1`, `rate_limiter_2`, etc.) hammering the system simultaneously, you need to learn how databases prevent concurrent users from overwriting each other's data.

* **The Theory to Learn:**
* **Transaction Isolation Levels:** Read Committed, Repeatable Read, and Serializable. Understand what *Dirty Reads*, *Non-repeatable Reads*, and *Phantom Reads* are.
* **Pessimistic vs. Optimistic Locking:** When to use explicit row locks (`SELECT ... FOR UPDATE`) vs. version checking.


* **The Sandbox Implementation:**
* Modify your FastAPI app so that every time a request is allowed, it logs a row into Postgres.
* Simulate concurrent traffic and intentionally induce a "Lost Update" or a dead-lock scenario by forcing two replicas to update the same row at the exact same millisecond.
* Solve it using Postgres transaction isolation blocks.



---

## Phase 3: Scaling Out (Replication & High Availability)

Once your single PostgreSQL instance is perfectly optimized, you simulate what happens when that instance runs out of CPU or disk I/O under massive global load.

* **The Theory to Learn:**
* **Primary-Replica (Master-Slave) Architecture:** How data flows from the write-heavy Primary node to read-only nodes.
* **Synchronous vs. Asynchronous Replication:** The ultimate trade-off between data safety (consistency) and write latency (availability).


* **The Sandbox Implementation:**
* Update your `docker-compose.yml` to spin up **one Primary Postgres container** and **two Read-Replica Postgres containers**.
* Configure your FastAPI app to execute a clean **Read/Write Split**: point all `POST /request` logging writes to the Primary node, and configure your `GET /stats` endpoint to read exclusively from the Read-Replicas.



---

## Phase 4: Distributed Horizons (Sharding & Consistency)

This is the final frontier where you learn how companies scale when a database becomes too large to physically fit on a single server's hard drive.

* **The Theory to Learn:**
* **Horizontal Partitioning (Sharding):** Splitting a table across entirely different machine clusters using a Sharding Key (e.g., routing users A-M to Database 1, and N-Z to Database 2).
* **The CAP Theorem & PACELC:** Deeply understanding why a system cannot achieve perfect consistency and perfect availability simultaneously over a network partition.


* **The Sandbox Implementation:**
* Explore how to handle distributed data routing, or integrate an architectural proxy layer like Citus Data or Vitess to see how automated sharding looks in a modern enterprise pipeline.



---

## Where to start today?

I highly recommend starting at **Phase 1**. Let's add PostgreSQL to your existing Docker stack so you can see it running right alongside your rate-limiter and Redis.

Would you like the updated `docker-compose.yml` configuration and the basic Python code to establish a resilient Postgres connection pool from your backend replicas?