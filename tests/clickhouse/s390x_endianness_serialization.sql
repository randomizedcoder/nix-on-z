-- Test: s390x endianness in column serialization
-- Exercises serializeValueIntoArena/serializeValueIntoMemory for
-- ColumnString, ColumnArray, ColumnVariant, ColumnDynamic, ColumnObject.
-- On big-endian systems without the fix, these produce 256/512 PiB
-- allocation attempts or ATTEMPT_TO_READ_AFTER_EOF.

-- ColumnString serialization via GROUP BY with string keys
SELECT 'test_string_groupby';
SELECT toString(number % 3) AS key, count() FROM numbers(9) GROUP BY key ORDER BY key;

-- ColumnString serialization via groupArray with tuples (01025 repro)
SELECT 'test_grouparray_tuples';
SELECT arrayCompact(x -> x.2, groupArray((toString(number), toString(intDiv(number, 3) % 3)))) FROM numbers(10);

-- ColumnArray serialization via GROUP BY with array keys
SELECT 'test_array_groupby';
SELECT [number % 2, number % 3] AS key, count() FROM numbers(6) GROUP BY key ORDER BY key;

-- ColumnString + GROUP BY + sorted array aggregation (03100 repro)
SELECT 'test_group_sorted_array';
SELECT number % 3 AS n, arraySort(groupUniqArray(toString(number))) AS vals FROM numbers(9) GROUP BY n ORDER BY n;

-- Grouping function (02534 repro)
SELECT 'test_grouping_function';
DROP TABLE IF EXISTS test_grouping_endian;
CREATE TABLE test_grouping_endian (id UInt32, value String) ENGINE = MergeTree ORDER BY id;
INSERT INTO test_grouping_endian VALUES (1, 'a'), (2, 'b'), (3, 'a');
SELECT id, value, count() FROM test_grouping_endian GROUP BY id, value ORDER BY id, value;
DROP TABLE test_grouping_endian;

-- GROUP BY with LIMIT BY (03408 repro)
SELECT 'test_limit_by';
DROP TABLE IF EXISTS test_limitby_endian;
CREATE TABLE test_limitby_endian (id UInt32, val String) ENGINE = MergeTree ORDER BY id;
INSERT INTO test_limitby_endian VALUES (1, 'a'), (1, 'b'), (2, 'c'), (2, 'd'), (3, 'e');
SELECT id, val FROM test_limitby_endian GROUP BY id, val ORDER BY id, val LIMIT 1 BY id;
DROP TABLE test_limitby_endian;

-- WITH ROLLUP on string (03977 repro simplified)
SELECT 'test_rollup_string';
DROP TABLE IF EXISTS test_rollup_endian;
CREATE TABLE test_rollup_endian (value String) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO test_rollup_endian VALUES ('a'), ('b'), ('a');
SELECT value, count() FROM test_rollup_endian GROUP BY value WITH ROLLUP ORDER BY value;
DROP TABLE test_rollup_endian;

-- Dynamic type (03037/03249 repro)
SELECT 'test_dynamic_type';
DROP TABLE IF EXISTS test_dynamic_endian;
CREATE TABLE test_dynamic_endian (d Dynamic) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO test_dynamic_endian VALUES (42), ('hello'), (3.14), (42), ('hello');
SELECT count(), dynamicType(d) FROM test_dynamic_endian GROUP BY dynamicType(d) ORDER BY dynamicType(d);
DROP TABLE test_dynamic_endian;

-- Negative case: large groupArray (verifies no silent corruption)
SELECT 'test_large_grouparray';
SELECT length(groupArray(toString(number))) FROM numbers(1000);

-- Negative case: nested arrays (exercises ColumnArray recursion)
SELECT 'test_nested_arrays';
SELECT groupArray([toString(number), toString(number * 10)]) FROM numbers(3);

-- Negative case: empty strings in GROUP BY
SELECT 'test_empty_strings';
SELECT val, count() FROM (
    SELECT arrayJoin(['', 'a', '', 'b', 'a']) AS val
) GROUP BY val ORDER BY val;

-- Negative case: GROUP BY with many distinct string keys
-- Forces aggregation spill and re-merge, exercising serialize/deserialize round-trip
SELECT 'test_many_keys';
SELECT count() FROM (
    SELECT toString(number) AS key, count() FROM numbers(10000) GROUP BY key
);
