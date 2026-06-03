-- 1. Create a table simulating millions of API traffic logs
CREATE TABLE api_request_logs (
    id SERIAL,
    user_id VARCHAR(50) NOT NULL,
    endpoint VARCHAR(100) NOT NULL,
    http_status INT NOT NULL,
    execution_time_ms FLOAT NOT NULL,
    created_at TIMESTAMP NOT NULL
);

-- 2. Seed exactly 1,000,000 randomized rows
INSERT INTO api_request_logs (user_id, endpoint, http_status, execution_time_ms, created_at)
SELECT 
    'user_' || floor(random() * 50000 + 1)::int AS user_id,                  -- 50,000 unique users
    CASE floor(random() * 3)::int 
        WHEN 0 THEN '/request'
        WHEN 1 THEN '/stats'
        ELSE '/login'
    END AS endpoint,                                                         -- 3 endpoints
    CASE floor(random() * 10)::int 
        WHEN 0 THEN 429                                                      -- 10% rate limited
        WHEN 1 THEN 500                                                      -- 10% server errors
        ELSE 200                                                             -- 80% successful
    END AS http_status,
    (random() * 120 + 5)::numeric(5,2) AS execution_time_ms,                 -- Latency between 5ms and 125ms
    NOW() - (random() * 30 * INTERVAL '1 day')                               -- Random times over last 30 days
FROM generate_series(1, 1000000);


-- checking the output of this without indexes
EXPLAIN ANALYZE 
SELECT * FROM api_request_logs 
WHERE user_id = 'user_12345';

"Gather  (cost=1000.00..15554.43 rows=21 width=41) (actual time=5.305..52.798 rows=16 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Parallel Seq Scan on api_request_logs  (cost=0.00..14552.33 rows=9 width=41) (actual time=8.357..26.451 rows=5 loops=3)"
"        Filter: ((user_id)::text = 'user_12345'::text)"
"        Rows Removed by Filter: 333328"
"Planning Time: 0.260 ms"
"Execution Time: 52.828 ms"

-- adding an index
CREATE INDEX idx_logs_user_id ON api_request_logs(user_id);


EXPLAIN ANALYZE 
SELECT * FROM api_request_logs 
WHERE user_id = 'user_12345';

"Bitmap Heap Scan on api_request_logs  (cost=4.59..85.86 rows=21 width=41) (actual time=0.074..0.094 rows=16 loops=1)"
"  Recheck Cond: ((user_id)::text = 'user_12345'::text)"
"  Heap Blocks: exact=16"
"  ->  Bitmap Index Scan on idx_logs_user_id  (cost=0.00..4.58 rows=21 width=0) (actual time=0.066..0.066 rows=16 loops=1)"
"        Index Cond: ((user_id)::text = 'user_12345'::text)"
"Planning Time: 0.304 ms"
"Execution Time: 0.136 ms"



-- Now that you see how a single index works, let’s test a realistic 
-- scenario where a single index fails. Run this new query that filters 
-- by two columns simultaneously:
EXPLAIN ANALYZE 
SELECT * FROM api_request_logs 
WHERE user_id = 'user_12345' AND http_status = 429;

"Bitmap Heap Scan on api_request_logs  (cost=4.58..85.91 rows=2 width=41) (actual time=0.071..0.091 rows=1 loops=1)"
"  Recheck Cond: ((user_id)::text = 'user_12345'::text)"
"  Filter: (http_status = 429)"
"  Rows Removed by Filter: 15"
"  Heap Blocks: exact=16"
"  ->  Bitmap Index Scan on idx_logs_user_id  (cost=0.00..4.58 rows=21 width=0) (actual time=0.046..0.046 rows=16 loops=1)"
"        Index Cond: ((user_id)::text = 'user_12345'::text)"
"Planning Time: 0.105 ms"
"Execution Time: 0.179 ms"

    -- While an execution time of 0.179 ms is still blazing fast for 1 
    -- million rows, imagine if 'user_12345' was a massive enterprise client 
    -- with 500,000 log rows.

    -- The database would use the index to grab all 500,000 rows, load them 
    -- into memory, and then manually loop through and filter out 499,999 of 
    -- them just to find the rate-limited ones. That would completely thrash 
    -- your server's memory and CPU.

-- The Composite Index
CREATE INDEX idx_logs_user_http ON api_request_logs(user_id, http_status);

"Index Scan using idx_logs_user_http on api_request_logs  (cost=0.42..12.46 rows=2 width=41) (actual time=0.076..0.077 rows=1 loops=1)"
"  Index Cond: (((user_id)::text = 'user_12345'::text) AND (http_status = 429))"
"Planning Time: 0.425 ms"
"Execution Time: 0.103 ms"      

-- Column order matters immensely in a composite index.

-- see the indexes
SELECT 
    indexname AS index_name,
    indexdef AS index_definition
FROM 
    pg_indexes
WHERE 
    tablename = 'api_request_logs';



-- High Cardinality (High Uniqueness)
-- High cardinality columns are the absolute best candidates for B-Tree 
-- indexes. Because the values are highly unique, the database engine 
-- can use the index tree to instantly eliminate $99.99\%$ of the table 
-- and pinpoint the exact row you are looking for in microseconds.


-- Setup the Low-Cardinality Experiment
CREATE INDEX idx_logs_low_card_status ON api_request_logs(http_status);

EXPLAIN ANALYZE 
SELECT * FROM api_request_logs 
WHERE http_status = 200;

"Seq Scan on api_request_logs  (cost=0.00..21844.00 rows=798233 width=41) (actual time=0.010..85.366 rows=799896 loops=1)"
"  Filter: (http_status = 200)"
"  Rows Removed by Filter: 200104"
"Planning Time: 0.354 ms"
"Execution Time: 106.632 ms"

-- seq scan happened because 200 is 80% of the data, not worth the index and page scan
EXPLAIN ANALYZE 
SELECT * FROM api_request_logs 
WHERE http_status = 429;

-- partial index
CREATE INDEX idx_logs_errors_only 
ON api_request_logs (http_status) 
WHERE http_status IN (429, 500);

EXPLAIN ANALYZE 
SELECT * FROM api_request_logs 
WHERE user_id = 'user_12345' AND http_status = 429;