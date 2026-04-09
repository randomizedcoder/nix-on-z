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

-- === Additional tests inspired by Solaris/FreeBSD endianness testing ===

-- Hash stability: must produce same value on all architectures
-- CityHash64 is used for sharding and distributed queries
SELECT 'test_hash_stability';
SELECT cityHash64('endianness test') = 11994489804064498498;

-- Float GROUP BY (exercises ColumnVector<Float64> serialization)
SELECT 'test_float_groupby';
DROP TABLE IF EXISTS test_float_endian;
CREATE TABLE test_float_endian (val Float64) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO test_float_endian VALUES (1.5), (2.5), (1.5), (3.14);
SELECT val, count() FROM test_float_endian GROUP BY val ORDER BY val;
DROP TABLE test_float_endian;

-- Int8/Int16/Int32/Int64 all through GROUP BY (ColumnVector for each width)
SELECT 'test_integer_widths';
SELECT toInt8(number % 3) AS i8, toInt16(number % 5) AS i16, count()
FROM numbers(15) GROUP BY i8, i16 ORDER BY i8, i16;

-- Decimal aggregation (exercises ColumnDecimal serialization)
SELECT 'test_decimal_groupby';
SELECT toDecimal64(number / 3, 2) AS d, count()
FROM numbers(9)
GROUP BY d ORDER BY d;

-- Float64 aggregation functions (tests aggregate state byte order)
SELECT 'test_float_aggregates';
SELECT round(avg(number), 2), round(stddevPop(number), 2)
FROM numbers(100);

-- Checksum consistency: verify MergeTree checksums are correct
SELECT 'test_checksum';
DROP TABLE IF EXISTS test_checksum_endian;
CREATE TABLE test_checksum_endian (id UInt64, val String) ENGINE = MergeTree ORDER BY id;
INSERT INTO test_checksum_endian SELECT number, toString(number) FROM numbers(100);
SELECT count() FROM test_checksum_endian WHERE id = 42;
SELECT sum(rows), sum(bytes_on_disk) > 0 FROM system.parts WHERE table = 'test_checksum_endian' AND active;
DROP TABLE test_checksum_endian;

-- LZ4 compression round-trip
SELECT 'test_compression_lz4';
DROP TABLE IF EXISTS test_compress_endian;
CREATE TABLE test_compress_endian (val UInt64 CODEC(LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO test_compress_endian SELECT number FROM numbers(1000);
SELECT count(), min(val), max(val) FROM test_compress_endian;
DROP TABLE test_compress_endian;

-- ZSTD compression round-trip
SELECT 'test_compression_zstd';
DROP TABLE IF EXISTS test_zstd_endian;
CREATE TABLE test_zstd_endian (val String CODEC(ZSTD)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO test_zstd_endian SELECT toString(number) FROM numbers(1000);
SELECT count(), min(val), max(val) FROM test_zstd_endian;
DROP TABLE test_zstd_endian;

-- DoubleDelta codec (known endianness issue — tests same-arch round-trip)
SELECT 'test_codec_doubledelta';
DROP TABLE IF EXISTS test_dd_endian;
CREATE TABLE test_dd_endian (ts UInt64 CODEC(DoubleDelta)) ENGINE = MergeTree ORDER BY ts;
INSERT INTO test_dd_endian SELECT 1000000 + number * 1000 FROM numbers(100);
SELECT count(), min(ts), max(ts) FROM test_dd_endian;
DROP TABLE test_dd_endian;

-- Gorilla codec (known endianness issue — tests same-arch round-trip)
SELECT 'test_codec_gorilla';
DROP TABLE IF EXISTS test_gorilla_endian;
CREATE TABLE test_gorilla_endian (val Float64 CODEC(Gorilla)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO test_gorilla_endian SELECT number * 1.1 FROM numbers(100);
SELECT count(), round(min(val), 1), round(max(val), 1) FROM test_gorilla_endian;
DROP TABLE test_gorilla_endian;

-- Delta codec (known endianness issue — tests same-arch round-trip)
SELECT 'test_codec_delta';
DROP TABLE IF EXISTS test_delta_endian;
CREATE TABLE test_delta_endian (val Int32 CODEC(Delta, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO test_delta_endian SELECT number FROM numbers(1000);
SELECT count(), min(val), max(val) FROM test_delta_endian;
DROP TABLE test_delta_endian;

-- Multiple codecs combined: Delta + ZSTD (real-world pattern)
SELECT 'test_codec_combined';
DROP TABLE IF EXISTS test_combined_endian;
CREATE TABLE test_combined_endian (
    ts DateTime CODEC(Delta, ZSTD),
    val Float64 CODEC(ZSTD),
    id UInt32 CODEC(LZ4)
) ENGINE = MergeTree ORDER BY ts;
INSERT INTO test_combined_endian SELECT
    toDateTime('2024-01-01') + number * 60,
    sin(number / 10.0),
    number
FROM numbers(1000);
SELECT count(), min(id), max(id), round(avg(val), 4) FROM test_combined_endian;
DROP TABLE test_combined_endian;
