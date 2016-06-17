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

-- this is allowed because the planner strips away the CASE
UPDATE example SET value = CASE WHEN true THEN now() ELSE now() + interval '1 hour' END WHERE key = 1;

UPDATE example SET value = (CASE WHEN now() > timestamp '12-12-1991' THEN now() ELSE now() + interval '1 hour' END) WHERE key = 1;

DROP TABLE example;