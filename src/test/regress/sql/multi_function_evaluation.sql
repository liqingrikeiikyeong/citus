--
-- MULTI_FUNCTION_EVALUATION
--

ALTER SEQUENCE pg_catalog.pg_dist_shardid_seq RESTART 1190000;
ALTER SEQUENCE pg_catalog.pg_dist_jobid_seq RESTART 1190000;

-- fields with SERIAL work

CREATE TABLE example (key INT, value SERIAL);
SELECT master_create_distributed_table('example', 'key', 'hash');
\c - - - :worker_1_port
CREATE SEQUENCE example_value_seq;
\c - - - :worker_2_port
CREATE SEQUENCE example_value_seq;
\c - - - :master_port
SELECT master_create_worker_shards('example', 1, 2);
INSERT INTO example VALUES (1);
SELECT * FROM example;

-- functions called by prepared statements are also evaluated

PREPARE stmt AS INSERT INTO example VALUES (2);
EXECUTE stmt;
EXECUTE stmt;
SELECT * FROM example;

-- non-immutable functions inside CASE/COALESCE aren't allowed

ALTER TABLE example DROP value;
ALTER TABLE example ADD value timestamp;

-- this is allowed because there are no mutable funcs in the CASE
UPDATE example SET value = (CASE WHEN value > timestamp '12-12-1991' THEN timestamp '12-12-1991' ELSE value + interval '1 hour' END) WHERE key = 1;

-- this is allowed because the planner strips away the CASE during constant evaluation
UPDATE example SET value = CASE WHEN true THEN now() ELSE now() + interval '1 hour' END WHERE key = 1;

-- this is not allowed because there're mutable functions in a CaseWhen clause
-- (which we can't easily evaluate on the master)
UPDATE example SET value = (CASE WHEN now() > timestamp '12-12-1991' THEN now() ELSE timestamp '10-24-1190' END) WHERE key = 1;

-- make sure we also check defresult (the ELSE clause)
UPDATE example SET value = (CASE WHEN now() > timestamp '12-12-1991' THEN timestamp '12-12-1191' ELSE now() END) WHERE key = 1;

-- COALESCE is allowed
UPDATE example SET value = COALESCE(null, null, timestamp '10-10-1000') WHERE key = 1;

-- COALESCE is not allowed if there are any mutable functions
UPDATE example SET value = COALESCE(now(), timestamp '10-10-1000') WHERE key = 1;
UPDATE example SET value = COALESCE(timestamp '10-10-1000', now()) WHERE key = 1;

-- RowCompareExpr's are checked for mutability. These are allowed:

ALTER TABLE example DROP value;
ALTER TABLE example ADD value boolean;
ALTER TABLE example ADD time_col timestamptz;

UPDATE example SET value = NULLIF(ROW(1, 2) < ROW(2, 3), true) WHERE key = 1;
UPDATE example SET value = NULLIF(ROW(true, 2) < ROW(value, 3), true) WHERE key = 1;

-- But this RowCompareExpr is not (it passes Var into STABLE)

UPDATE example SET value = NULLIF(
	ROW(date '10-10-1000', 2) < ROW(time_col, 3), true
) WHERE key = 1;

DROP TABLE example;

-- Test RowCompareExpr?
