-- Test: s390x endianness in compression codecs
-- Tests every codec with multiple data types to verify round-trip correctness.
-- Expected behavior: data written and read on the same architecture must
-- produce identical results regardless of byte order.
--
-- Codecs known to be endian-safe: LZ4, ZSTD, LZ4HC, NONE
-- Codecs known to use LE I/O: DoubleDelta, Gorilla, Delta
-- Codecs with endianness bugs: GCD (native load/store), T64 (asymmetric),
--   FPC (native memcpy in importChunk/exportChunk)

-- === LZ4 (endian-safe, byte-stream codec) ===

SELECT 'lz4_uint32';
DROP TABLE IF EXISTS t_lz4_u32;
CREATE TABLE t_lz4_u32 (val UInt32 CODEC(LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_lz4_u32 SELECT number FROM numbers(1000);
SELECT count(), min(val), max(val), sum(val) FROM t_lz4_u32;
DROP TABLE t_lz4_u32;

SELECT 'lz4_int64';
DROP TABLE IF EXISTS t_lz4_i64;
CREATE TABLE t_lz4_i64 (val Int64 CODEC(LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_lz4_i64 SELECT number - 500 FROM numbers(1000);
SELECT count(), min(val), max(val), sum(val) FROM t_lz4_i64;
DROP TABLE t_lz4_i64;

SELECT 'lz4_float64';
DROP TABLE IF EXISTS t_lz4_f64;
CREATE TABLE t_lz4_f64 (val Float64 CODEC(LZ4)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_lz4_f64 SELECT number * 1.1 FROM numbers(100);
SELECT count(), round(min(val), 1), round(max(val), 1), round(sum(val), 1) FROM t_lz4_f64;
DROP TABLE t_lz4_f64;

SELECT 'lz4_string';
DROP TABLE IF EXISTS t_lz4_str;
CREATE TABLE t_lz4_str (val String CODEC(LZ4)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_lz4_str SELECT toString(number) FROM numbers(1000);
SELECT count(), min(val), max(val) FROM t_lz4_str;
DROP TABLE t_lz4_str;

-- === ZSTD (endian-safe, byte-stream codec) ===

SELECT 'zstd_uint64';
DROP TABLE IF EXISTS t_zstd_u64;
CREATE TABLE t_zstd_u64 (val UInt64 CODEC(ZSTD)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_zstd_u64 SELECT number * 1000 FROM numbers(1000);
SELECT count(), min(val), max(val), sum(val) FROM t_zstd_u64;
DROP TABLE t_zstd_u64;

-- === Delta (uses LE I/O — should be portable) ===

SELECT 'delta_uint32';
DROP TABLE IF EXISTS t_delta_u32;
CREATE TABLE t_delta_u32 (val UInt32 CODEC(Delta, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_delta_u32 SELECT number FROM numbers(1000);
SELECT count(), min(val), max(val), sum(val) FROM t_delta_u32;
DROP TABLE t_delta_u32;

SELECT 'delta_int64';
DROP TABLE IF EXISTS t_delta_i64;
CREATE TABLE t_delta_i64 (val Int64 CODEC(Delta, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_delta_i64 SELECT number - 500 FROM numbers(1000);
SELECT count(), min(val), max(val), sum(val) FROM t_delta_i64;
DROP TABLE t_delta_i64;

SELECT 'delta_uint16';
DROP TABLE IF EXISTS t_delta_u16;
CREATE TABLE t_delta_u16 (val UInt16 CODEC(Delta, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_delta_u16 SELECT number FROM numbers(1000);
SELECT count(), min(val), max(val), sum(val) FROM t_delta_u16;
DROP TABLE t_delta_u16;

-- === DoubleDelta (uses LE I/O — should be portable) ===

SELECT 'doubledelta_uint32';
DROP TABLE IF EXISTS t_dd_u32;
CREATE TABLE t_dd_u32 (val UInt32 CODEC(DoubleDelta)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_dd_u32 SELECT 1000000 + number * 1000 FROM numbers(100);
SELECT count(), min(val), max(val), sum(val) FROM t_dd_u32;
DROP TABLE t_dd_u32;

SELECT 'doubledelta_uint64';
DROP TABLE IF EXISTS t_dd_u64;
CREATE TABLE t_dd_u64 (val UInt64 CODEC(DoubleDelta)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_dd_u64 SELECT 1000000000 + number * 1000 FROM numbers(100);
SELECT count(), min(val), max(val), sum(val) FROM t_dd_u64;
DROP TABLE t_dd_u64;

-- === Gorilla (uses LE I/O — should be portable) ===

SELECT 'gorilla_float32';
DROP TABLE IF EXISTS t_gor_f32;
CREATE TABLE t_gor_f32 (val Float32 CODEC(Gorilla)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_gor_f32 SELECT number * 1.5 FROM numbers(100);
SELECT count(), round(min(val), 1), round(max(val), 1), round(sum(val), 1) FROM t_gor_f32;
DROP TABLE t_gor_f32;

SELECT 'gorilla_float64';
DROP TABLE IF EXISTS t_gor_f64;
CREATE TABLE t_gor_f64 (val Float64 CODEC(Gorilla)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_gor_f64 SELECT sin(number / 10.0) FROM numbers(100);
SELECT count(), round(min(val), 4), round(max(val), 4), round(sum(val), 4) FROM t_gor_f64;
DROP TABLE t_gor_f64;

-- === GCD (uses native unalignedLoad/Store — KNOWN BUG on big-endian) ===
-- Same-arch round-trip should still work because compress/decompress
-- both use native byte order consistently.

SELECT 'gcd_uint32';
DROP TABLE IF EXISTS t_gcd_u32;
CREATE TABLE t_gcd_u32 (val UInt32 CODEC(GCD, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_gcd_u32 SELECT number * 6 FROM numbers(100);
SELECT count(), min(val), max(val), sum(val) FROM t_gcd_u32;
DROP TABLE t_gcd_u32;

SELECT 'gcd_uint64';
DROP TABLE IF EXISTS t_gcd_u64;
CREATE TABLE t_gcd_u64 (val UInt64 CODEC(GCD, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_gcd_u64 SELECT number * 12 FROM numbers(100);
SELECT count(), min(val), max(val), sum(val) FROM t_gcd_u64;
DROP TABLE t_gcd_u64;

-- === T64 (load is LE-aware, store is native — KNOWN BUG on big-endian) ===
-- The asymmetric load/store means data may be corrupted on big-endian.

SELECT 't64_uint32';
DROP TABLE IF EXISTS t_t64_u32;
CREATE TABLE t_t64_u32 (val UInt32 CODEC(T64, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_t64_u32 SELECT number FROM numbers(1000);
SELECT count(), min(val), max(val), sum(val) FROM t_t64_u32;
DROP TABLE t_t64_u32;

SELECT 't64_uint64';
DROP TABLE IF EXISTS t_t64_u64;
CREATE TABLE t_t64_u64 (val UInt64 CODEC(T64, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_t64_u64 SELECT number * 1000 FROM numbers(1000);
SELECT count(), min(val), max(val), sum(val) FROM t_t64_u64;
DROP TABLE t_t64_u64;

SELECT 't64_int16';
DROP TABLE IF EXISTS t_t64_i16;
CREATE TABLE t_t64_i16 (val Int16 CODEC(T64, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_t64_i16 SELECT number - 500 FROM numbers(1000);
SELECT count(), min(val), max(val), sum(val) FROM t_t64_i16;
DROP TABLE t_t64_i16;

-- === FPC (hardcoded LE constant, native memcpy — KNOWN BUG on big-endian) ===

SELECT 'fpc_float32';
DROP TABLE IF EXISTS t_fpc_f32;
CREATE TABLE t_fpc_f32 (val Float32 CODEC(FPC)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_fpc_f32 SELECT number * 0.1 FROM numbers(1000);
SELECT count(), round(min(val), 1), round(max(val), 1), round(sum(val), 1) FROM t_fpc_f32;
DROP TABLE t_fpc_f32;

SELECT 'fpc_float64';
DROP TABLE IF EXISTS t_fpc_f64;
CREATE TABLE t_fpc_f64 (val Float64 CODEC(FPC)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_fpc_f64 SELECT sin(number / 100.0) FROM numbers(1000);
SELECT count(), round(min(val), 6), round(max(val), 6), round(sum(val), 6) FROM t_fpc_f64;
DROP TABLE t_fpc_f64;

-- === Combined codecs (real-world patterns) ===

SELECT 'combined_delta_zstd';
DROP TABLE IF EXISTS t_combined;
CREATE TABLE t_combined (
    ts DateTime CODEC(Delta, ZSTD),
    val Float64 CODEC(Gorilla, LZ4),
    id UInt32 CODEC(LZ4),
    metric String CODEC(ZSTD)
) ENGINE = MergeTree ORDER BY ts;
INSERT INTO t_combined SELECT
    toDateTime('2024-01-01') + number * 60,
    sin(number / 10.0),
    number,
    concat('metric_', toString(number % 10))
FROM numbers(1000);
SELECT count(), min(id), max(id), round(avg(val), 4),
    countDistinct(metric) FROM t_combined;
DROP TABLE t_combined;

-- === Edge cases ===

SELECT 'edge_single_value';
DROP TABLE IF EXISTS t_edge_single;
CREATE TABLE t_edge_single (val UInt64 CODEC(GCD, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_edge_single VALUES (42);
SELECT count(), min(val), max(val) FROM t_edge_single;
DROP TABLE t_edge_single;

SELECT 'edge_all_zeros';
DROP TABLE IF EXISTS t_edge_zeros;
CREATE TABLE t_edge_zeros (val UInt32 CODEC(GCD, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_edge_zeros SELECT 0 FROM numbers(100);
SELECT count(), min(val), max(val), sum(val) FROM t_edge_zeros;
DROP TABLE t_edge_zeros;

SELECT 'edge_all_same';
DROP TABLE IF EXISTS t_edge_same;
CREATE TABLE t_edge_same (val UInt64 CODEC(T64, LZ4)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_edge_same SELECT 12345 FROM numbers(100);
SELECT count(), min(val), max(val), sum(val) FROM t_edge_same;
DROP TABLE t_edge_same;

SELECT 'edge_max_values';
DROP TABLE IF EXISTS t_edge_max;
CREATE TABLE t_edge_max (val UInt32 CODEC(Delta, LZ4)) ENGINE = MergeTree ORDER BY val;
INSERT INTO t_edge_max SELECT 4294967295 - number FROM numbers(100);
SELECT count(), min(val), max(val) FROM t_edge_max;
DROP TABLE t_edge_max;

SELECT 'edge_negative_floats';
DROP TABLE IF EXISTS t_edge_neg;
CREATE TABLE t_edge_neg (val Float64 CODEC(Gorilla, LZ4)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_edge_neg SELECT -1.0 * number * number FROM numbers(100);
SELECT count(), round(min(val), 0), round(max(val), 0), round(sum(val), 0) FROM t_edge_neg;
DROP TABLE t_edge_neg;

-- === Float64 precision tests (IEEE 754 must be bit-identical across architectures) ===

-- Exact round-trip: every value must survive codec compression unchanged
SELECT 'f64_exact_lz4';
DROP TABLE IF EXISTS t_f64_exact_lz4;
CREATE TABLE t_f64_exact_lz4 (val Float64 CODEC(LZ4)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_f64_exact_lz4 SELECT number * 0.1 FROM numbers(1000);
SELECT count(), sum(val) = (SELECT sum(number * 0.1) FROM numbers(1000)) AS exact_match FROM t_f64_exact_lz4;
DROP TABLE t_f64_exact_lz4;

SELECT 'f64_exact_gorilla';
DROP TABLE IF EXISTS t_f64_exact_gor;
CREATE TABLE t_f64_exact_gor (val Float64 CODEC(Gorilla)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_f64_exact_gor SELECT number * 0.1 FROM numbers(1000);
SELECT count(), sum(val) = (SELECT sum(number * 0.1) FROM numbers(1000)) AS exact_match FROM t_f64_exact_gor;
DROP TABLE t_f64_exact_gor;

SELECT 'f64_exact_fpc';
DROP TABLE IF EXISTS t_f64_exact_fpc;
CREATE TABLE t_f64_exact_fpc (val Float64 CODEC(FPC)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_f64_exact_fpc SELECT number * 0.1 FROM numbers(1000);
SELECT count(), sum(val) = (SELECT sum(number * 0.1) FROM numbers(1000)) AS exact_match FROM t_f64_exact_fpc;
DROP TABLE t_f64_exact_fpc;

-- Special IEEE 754 values: NaN, Inf, -Inf, denormals, zero, neg zero
SELECT 'f64_special_values';
DROP TABLE IF EXISTS t_f64_special;
CREATE TABLE t_f64_special (val Float64 CODEC(LZ4)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_f64_special VALUES (0.0), (-0.0), (inf), (-inf), (nan);
INSERT INTO t_f64_special SELECT exp(-745.0); -- denormal
SELECT count(), sum(isNaN(val)), sum(isInfinite(val)), sum(val = 0) FROM t_f64_special;
DROP TABLE t_f64_special;

SELECT 'f64_special_gorilla';
DROP TABLE IF EXISTS t_f64_spec_gor;
CREATE TABLE t_f64_spec_gor (val Float64 CODEC(Gorilla)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_f64_spec_gor VALUES (0.0), (-0.0), (inf), (-inf), (nan);
INSERT INTO t_f64_spec_gor SELECT exp(-745.0); -- denormal
SELECT count(), sum(isNaN(val)), sum(isInfinite(val)), sum(val = 0) FROM t_f64_spec_gor;
DROP TABLE t_f64_spec_gor;

SELECT 'f64_special_fpc';
DROP TABLE IF EXISTS t_f64_spec_fpc;
CREATE TABLE t_f64_spec_fpc (val Float64 CODEC(FPC)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_f64_spec_fpc VALUES (0.0), (-0.0), (inf), (-inf), (nan);
INSERT INTO t_f64_spec_fpc SELECT exp(-745.0); -- denormal
SELECT count(), sum(isNaN(val)), sum(isInfinite(val)), sum(val = 0) FROM t_f64_spec_fpc;
DROP TABLE t_f64_spec_fpc;

-- Bit-exact round-trip using reinterpretAsUInt64 (verifies no bit flips)
SELECT 'f64_bitexact_lz4';
DROP TABLE IF EXISTS t_f64_bits_lz4;
CREATE TABLE t_f64_bits_lz4 (idx UInt32, val Float64 CODEC(LZ4)) ENGINE = MergeTree ORDER BY idx;
INSERT INTO t_f64_bits_lz4 SELECT number, sin(number) FROM numbers(100);
SELECT sum(reinterpretAsUInt64(val) = reinterpretAsUInt64(sin(idx))) AS all_match FROM t_f64_bits_lz4;
DROP TABLE t_f64_bits_lz4;

SELECT 'f64_bitexact_gorilla';
DROP TABLE IF EXISTS t_f64_bits_gor;
CREATE TABLE t_f64_bits_gor (idx UInt32, val Float64 CODEC(Gorilla)) ENGINE = MergeTree ORDER BY idx;
INSERT INTO t_f64_bits_gor SELECT number, sin(number) FROM numbers(100);
SELECT sum(reinterpretAsUInt64(val) = reinterpretAsUInt64(sin(idx))) AS all_match FROM t_f64_bits_gor;
DROP TABLE t_f64_bits_gor;

SELECT 'f64_bitexact_fpc';
DROP TABLE IF EXISTS t_f64_bits_fpc;
CREATE TABLE t_f64_bits_fpc (idx UInt32, val Float64 CODEC(FPC)) ENGINE = MergeTree ORDER BY idx;
INSERT INTO t_f64_bits_fpc SELECT number, sin(number) FROM numbers(100);
SELECT sum(reinterpretAsUInt64(val) = reinterpretAsUInt64(sin(idx))) AS all_match FROM t_f64_bits_fpc;
DROP TABLE t_f64_bits_fpc;

-- Float32 precision: same tests for 32-bit
SELECT 'f32_exact_gorilla';
DROP TABLE IF EXISTS t_f32_exact_gor;
CREATE TABLE t_f32_exact_gor (val Float32 CODEC(Gorilla)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_f32_exact_gor SELECT toFloat32(number * 0.1) FROM numbers(1000);
SELECT count(), sum(val) = (SELECT sum(toFloat32(number * 0.1)) FROM numbers(1000)) AS exact_match FROM t_f32_exact_gor;
DROP TABLE t_f32_exact_gor;

SELECT 'f32_exact_fpc';
DROP TABLE IF EXISTS t_f32_exact_fpc;
CREATE TABLE t_f32_exact_fpc (val Float32 CODEC(FPC)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_f32_exact_fpc SELECT toFloat32(number * 0.1) FROM numbers(1000);
SELECT count(), sum(val) = (SELECT sum(toFloat32(number * 0.1)) FROM numbers(1000)) AS exact_match FROM t_f32_exact_fpc;
DROP TABLE t_f32_exact_fpc;

-- High-precision trig functions through codecs
SELECT 'f64_trig_delta_zstd';
DROP TABLE IF EXISTS t_f64_trig;
CREATE TABLE t_f64_trig (s Float64 CODEC(ZSTD), c Float64 CODEC(ZSTD)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_f64_trig SELECT sin(number * 0.01), cos(number * 0.01) FROM numbers(1000);
SELECT count(),
    round(sum(s * s + c * c), 6) AS pythagorean_sum,
    round(min(s * s + c * c), 15) AS pythagorean_min,
    round(max(s * s + c * c), 15) AS pythagorean_max
FROM t_f64_trig;
DROP TABLE t_f64_trig;
