-- Tracking B+ Tree Size Explosions

-- 1. Create the benchmark tracking table
CREATE TABLE scale_benchmark_logs (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(50),
    http_status INT
);

-- 2. Create the composite B-Tree index
CREATE INDEX idx_benchmark_scale ON scale_benchmark_logs(user_id, http_status);


-- Measure the absolute physical size of the Index vs the main Table on disk (in MB)
SELECT 
    pg_size_pretty(pg_relation_size('scale_benchmark_logs')) AS table_disk_size,
    pg_size_pretty(pg_relation_size('idx_benchmark_scale')) AS index_disk_size;

-- Check the depth and structure changes of your tree via the Metapage
SELECT level, root, fastroot FROM bt_metap('idx_benchmark_scale');

-- Step A: Run at 100,000 Rows
INSERT INTO scale_benchmark_logs (user_id, http_status)
SELECT 'user_' || floor(random() * 5000)::int, (ARRAY[200, 429, 500])[floor(random() * 3 + 1)]
FROM generate_series(1, 100000);

    "table_disk_size"	"index_disk_size"
    "5096 kB"	"1552 kB"
    "level"	"root"	"fastroot"
    1	3	3

-- Step B: Scale to 1,000,000 Rows (Add 900k)
INSERT INTO scale_benchmark_logs (user_id, http_status)
SELECT 'user_' || floor(random() * 5000)::int, (ARRAY[200, 429, 500])[floor(random() * 3 + 1)]
FROM generate_series(1, 900000);
    "table_disk_size"	"index_disk_size"
    "50 MB"	"8768 kB"

    "level"	"root"	"fastroot"
    2	297	297


-- Step C: Scale to 10,000,000 Rows (Add 9M — Note: This may take 20-30 seconds to generate)
INSERT INTO scale_benchmark_logs (user_id, http_status)
SELECT 'user_' || floor(random() * 5000)::int, (ARRAY[200, 429, 500])[floor(random() * 3 + 1)]
FROM generate_series(1, 9000000);

    "table_disk_size"	"index_disk_size"
    "497 MB"	"99 MB"
    "level"	"root"	"fastroot"
    2	297	297


-- 10M	497.0 MB	99.0 MB	~19.9%
-- At 10 million rows, your index takes up roughly $20% of the size of 
-- your primary table. This is an optimal, highly balanced real-world 
-- ratio. The entire 99MB index tree can easily fit inside your database 
-- server's shared buffers (RAM cache), ensuring that lookups avoid 
-- hitting the actual hard drive altogether.