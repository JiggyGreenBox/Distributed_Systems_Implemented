This is an incredible next step. Diving into `pageinspect` is exactly how you separate the Senior Engineers from the staff-level database architects. Instead of just treating a B-Tree like an academic whiteboard drawing, you are going to peel back the disk layer and look at the exact binary bytes Postgres writes to your storage engine.

Let’s get your environment configured with `pageinspect` and walk through how to dissect the index root, internal nodes, and leaf pages.

---

## 1. Setting Up the Deep-Dive Environment

Since your previous table already has 1 million rows and the composite index `idx_logs_user_http` loaded, we can reuse that container!

Open your pgAdmin Query Tool, connect to `system_design_db`, and run the following command to enable the low-level disk inspection extension:

```sql
CREATE EXTENSION IF NOT EXISTS pageinspect;

```

---

## 2. Reading the Index Meta-Page (`bt_metap`)

Every B-Tree index in Postgres allocates a hidden page at the very beginning called the **Metapage (Block 0)**. This page acts as the entry map for the database engine to find where the tree starts.

Run this query to inspect your composite index's metapage:

```sql
SELECT * FROM bt_metap('idx_logs_user_http');

```

### The Output Fields to Decipher:

* **`magic`**: A verification number (usually `0x00053162`) ensuring Postgres that this file is indeed a valid B-Tree index.
* **`version`**: The internal layout version of the index.
* **`root`**: **The most important number here.** This tells you the physical block number (Page ID) on disk where the **Root Node** of your B-Tree lives. (e.g., if it says `3`, Block 3 is your root entry point).
* **`level`**: The height of your B-Tree. If `level = 2`, your tree has a root page, one layer of intermediate pages, and a layer of leaf pages.
* **`fastroot`**: The page where searches should actually begin if optimization shortcuts are available.

---

## 3. Profiling Page Layout Metrics (`bt_page_stats`)

Now that you know the `root` block number from the previous step (let's assume your root is block `3` for this example), you can check the structural stats of that specific disk page using `bt_page_stats`.

Run this query (replace `3` with your actual `root` block integer from the step above):

```sql
SELECT * FROM bt_page_stats('idx_logs_user_http', 3);

```

### Understanding the Structural Node DNA:

* **`type`**: Tells you what role this disk page plays in the B-Tree topology:
* `'r'`: **Root Page** (The master entry node).
* `'i'`: **Internal Page** (The middle guideposts pointing to lower pages).
* `'l'`: **Leaf Page** (The bottom layer containing actual pointers to table data rows).


* **`live_items`**: The number of valid index keys stored inside this specific 8KB page block.
* **`free_size`**: How many bytes remain unused on this 8KB page. If this number drops close to 0, Postgres will trigger a **Page Split**, cutting the page in half and allocating a new block to make room for more data.

---

## 4. Reading the Leaf Content: Connecting Theory to RAM

The final step of the inspection is looking at the actual items inside a **Leaf Page** (`type = 'l'`). Leaf pages are the final destination of a B-Tree search; they store the mapped index values alongside a `ctid` (the precise physical physical block and tuple slot of the row in the main table heap).

To find a leaf page, look at the page stats of your internal nodes, or pass a known leaf block ID (e.g., Block 1 or 2) into `bt_page_items`:

```sql
SELECT * FROM bt_page_items('idx_logs_user_http', 1) LIMIT 10;

```

### Connecting B+ Tree Theory to reality:

Look at the results table:

* **`itemoffset`**: The slot position inside this 8KB disk page.
* **`ctid`**: Format `(block_number, tuple_index)`. This is the exact physical coordinate of the row in your main table. When you run an index scan, Postgres grabs this `ctid` and instantly goes to that exact sector on your hard drive to pull your data.
* **`data`**: The hex-encoded value of your indexed keys (`user_id` and `http_status`).

---

## Phase 1.5 Experiment: Tracking B+ Tree Size Explosions

Now let's execute your script matrix. We want to see how the physical disk footprint grows and how the B-Tree handles the transition from **100K** to **1M** to **10M** records.

Run this script block sequentially to build the comparison dataset:

```sql
-- 1. Create the benchmark tracking table
CREATE TABLE scale_benchmark_logs (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(50),
    http_status INT
);

-- 2. Create the composite B-Tree index
CREATE INDEX idx_benchmark_scale ON scale_benchmark_logs(user_id, http_status);

```

### The Measurement Queries

Every time you load data into this table, run these two tracking queries to collect your benchmark report points:

```sql
-- Measure the absolute physical size of the Index vs the main Table on disk (in MB)
SELECT 
    pg_size_pretty(pg_relation_size('scale_benchmark_logs')) AS table_disk_size,
    pg_size_pretty(pg_relation_size('idx_benchmark_scale')) AS index_disk_size;

-- Check the depth and structure changes of your tree via the Metapage
SELECT level, root, fastroot FROM bt_metap('idx_benchmark_scale');

```

### The Data Ingestion Run Steps:

* **Step A: Run at 100,000 Rows**
```sql
INSERT INTO scale_benchmark_logs (user_id, http_status)
SELECT 'user_' || floor(random() * 5000)::int, (ARRAY[200, 429, 500])[floor(random() * 3 + 1)]
FROM generate_series(1, 100000);

```


*(Run your measurement queries. Note the `index_disk_size` and tree `level`).*
* **Step B: Scale to 1,000,000 Rows (Add 900k)**
```sql
INSERT INTO scale_benchmark_logs (user_id, http_status)
SELECT 'user_' || floor(random() * 5000)::int, (ARRAY[200, 429, 500])[floor(random() * 3 + 1)]
FROM generate_series(1, 900000);

```


*(Run your measurement queries. Watch how the tree splits).*
* **Step C: Scale to 10,000,000 Rows (Add 9M — Note: This may take 20-30 seconds to generate)**
```sql
INSERT INTO scale_benchmark_logs (user_id, http_status)
SELECT 'user_' || floor(random() * 5000)::int, (ARRAY[200, 429, 500])[floor(random() * 3 + 1)]
FROM generate_series(1, 9000000);

```



---

## What to watch for during your run:

As you scale from 100K to 10M rows, watch the `level` column inside `bt_metap`.

A textbook B+ Tree scales logarithmically ($O(\log N)$). You will watch Postgres handle millions of entries while keeping the `level` depth incredibly flat (likely moving from level 1 to level 2 or 3 max). This proves why B+ Trees are chosen for disk storage: no matter how huge the dataset grows, the database engine only needs to jump through 2 or 3 page blocks to find any row!

Fire up your pgAdmin tool, load the extension, and let me know what your `bt_metap` stats report back for the 100K vs 1M row allocations!



Total Rows,Table Disk Size,Index Disk Size,Index-to-Table Space Ratio
100k,5.0 MB,1.5 MB,~30%
1M,50.0 MB,8.7 MB,~17.4%
10M,497.0 MB,99.0 MB,~19.9%