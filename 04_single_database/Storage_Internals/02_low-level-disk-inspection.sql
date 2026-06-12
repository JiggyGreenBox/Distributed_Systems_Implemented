-- low-level disk inspection

-- 1. Setting Up the Deep-Dive Environment
CREATE EXTENSION IF NOT EXISTS pageinspect;

-- 2. Reading the Index Meta-Page (bt_metap)
SELECT * FROM bt_metap('idx_logs_user_http');

-- 3. Profiling Page Layout Metrics (bt_page_stats)
SELECT * FROM bt_page_stats('idx_logs_user_id', 209); -- 209 is root

        -- btpo_level = 2
        -- Leaf pages      level 0
        -- Internal pages  level 1
        -- Root page       level 2   <-- your case

        --         Root (209)
        --             |
        --     -------------------
        --     |   |   |   |   |
        -- Int Int Int Int Int
        --     |   |   |   |   |
        --     Leaf Leaf Leaf ...



    -- find leaf and internal pages
    SELECT pg_relation_size('idx_logs_user_id');
        8454144 / 8192 = 1032 pages
    SELECT
        page,
        (bt_page_stats('idx_logs_user_id', page)).*
    FROM generate_series(1, 1031) page;

-- 4. Reading the Leaf Content: Connecting Theory to RAM
SELECT * FROM bt_page_items('idx_logs_user_id', 245) LIMIT 10;

-- leaf page
SELECT * FROM bt_page_items('idx_logs_user_id', 245) LIMIT 2;
"itemoffset"	"ctid"	"itemlen"	"nulls"	"vars"	"data"	"dead"	"htid"	"tids"
1	"(24,1)"	24	false	true	"17 75 73 65 72 5f 32 30 36 35 38 00 00 00 00 00"			
2	"(24,8203)"	96	false	true	"17 75 73 65 72 5f 32 30 36 31 32 00 00 00 00 00"	false	"(58,83)"	"["(58,83)","(563,49)","(2307,70)","(2404,54)","(2657,52)","(4502,28)","(4602,14)","(7130,26)","(7604,42)","(9084,58)","(9189,5)"]"


-- CTID
-- (block_number, row_number)
    -- (24,1)
    -- table page 24
    -- tuple 1