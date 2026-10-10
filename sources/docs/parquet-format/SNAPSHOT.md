# Snapshot: Apache Parquet format specification

- **Upstream:** `apache/parquet-format` on GitHub.
- **Revision:** tag `apache-parquet-format-2.14.0`, commit
  `04d56f291ff963e98bc37ab8100e2fc133ff583c` (annotated tag object
  `804b5773fe25b19e945372888a44d91031eae26d`; `master` was at
  `bf0993925ccf41b1fb4b1ae241af4a66e8adf1fe` on 2026-10-09).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/apache/parquet-format/04d56f291ff963e98bc37ab8100e2fc133ff583c/<path>`;
  the file list was chosen from the tree at that commit.
- **Paths:** relative to the repository root (so `LogicalTypes.md`, `src/main/thrift/parquet.thrift`).
- **Files:** 9 (plus this file).
- **Licence:** Apache-2.0 (`LICENSE`, `NOTICE`).
- **Topic:** Flattened data: packed, columnar and nested layouts.
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `README.md` | the file format (row groups, column chunks, pages), the minimal physical types, "Nested Encoding" (Dremel definition and repetition levels, whose maxima the schema determines) and "Nulls" (nullity only in definition levels, nulls not stored) |
| `LogicalTypes.md` | logical annotations over physical types; "Nested Types": the required 3-level `LIST` and `MAP` structures and the backward-compatibility rules for 2-level lists |
| `Encodings.md` | PLAIN, dictionary (`RLE_DICTIONARY`), the RLE/bit-packing hybrid used for levels and dictionary indices, delta and byte-stream-split encodings |
| `VariantShredding.md`, `VariantEncoding.md` | the semi-structured `VARIANT`: a self-describing binary `value` beside a `typed_value` that "shreds" the fields that match a chosen type into ordinary columns |
| `src/main/thrift/parquet.thrift` | the metadata schema: `SchemaElement` (repetition `REQUIRED`/`OPTIONAL`/`REPEATED`, `num_children`: the schema is a flattened pre-order tree), `PageHeader`, `ColumnMetaData` |
| `doc/images/FileLayout.gif` | the file-layout diagram `README.md` shows |
| `LICENSE`, `NOTICE` | licence |

Not taken: `AlpEncoding.md`, `BloomFilter.md`, `Encryption.md`, `Geospatial.md`,
`PageIndex.md`, `Compression.md`, `BinaryProtocolExtensions.md`, `proposals/`.

**How to fetch more:** as in `docs/arrow/SNAPSHOT.md`, with
`https://raw.githubusercontent.com/apache/parquet-format/04d56f291ff963e98bc37ab8100e2fc133ff583c/<path>`.

## File manifest

Every stored file except this one: 9 files, 240,041 bytes in all. Computed 2026-10-09 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
b6b980c67acc14d3e9e4b592c582523b5dc2cc09ad9f90bc2b1912df461e5c88      20218  Encodings.md
8c6db340475136df3c1201d458fa5755698eace76e510471ecc9d857d6083dac      11359  LICENSE
93c93aab76af82522609603950f2ed582dba96177c7c225e3cc2372e7b8e540e      44203  LogicalTypes.md
28768ced5daf23a48a7fa7da0a16846c8c254e0a065cf29d5b17ef7fbad2e5fd        172  NOTICE
692afb37e07e752376006765729794cf358b4aae0582aef6a42deff1f19ca7de      14977  README.md
5b2ac5a0996576d6e3c30ff4133d2fc39afee95beee1e5300d47a82de94e6cfd      29705  VariantEncoding.md
a8e3730f75aaf85dd499aea0349ee266322ecbca47efb5fd19e789ef3dd67734      23143  VariantShredding.md
21672a68f1749847017420356abc71f8399f419f96a4e533467127ea521bc210      43589  doc/images/FileLayout.gif
d1d9a663d5543789b63d7168179d9849db06958b02c70ba96ba46ffde9278f61      52675  src/main/thrift/parquet.thrift
```
