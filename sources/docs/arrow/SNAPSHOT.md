# Snapshot: Apache Arrow columnar format specification

- **Upstream:** `apache/arrow` on GitHub (rendered at https://arrow.apache.org/docs/format/Columnar.html).
- **Revision:** tag `apache-arrow-26.0.0`, commit `446167169a0dc547e00e1bc29f417a40c0ca267a`
  (the annotated tag object is `3771b4ca6e0de72d85979afeaefb85dc2a69b931`; `main` was at
  `5ef3c5200359bc8e2375daf5f989369b0c8c089b` on 2026-10-09). The specification there is
  "Version: 1.5" of the columnar format.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/apache/arrow/446167169a0dc547e00e1bc29f417a40c0ca267a/<path>`;
  the file list was chosen from the tree at that commit
  (`https://api.github.com/repos/apache/arrow/git/trees/446167169a0dc547e00e1bc29f417a40c0ca267a?recursive=1`).
- **Paths:** relative to the repository root (so `docs/source/format/Columnar.rst`).
- **Files:** 26 (plus this file).
- **Licence:** Apache-2.0 (`LICENSE.txt`, `NOTICE.txt`, copied from the repository root; every
  `.rst` and `.fbs` carries the ASF header).
- **Topic:** Flattened data: packed, columnar and nested layouts.
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `docs/source/format/Columnar.rst` | the normative specification: terminology, data types and their physical layouts, alignment and padding, validity bitmaps, fixed-size primitive, variable-size binary and binary view, list, large list, list view, fixed-size list, struct (and struct validity), dense and sparse union, null, dictionary-encoded and run-end-encoded layouts, the buffer listing per layout, and IPC (record batches flattened by a pre-order walk of the fields, variadic buffers, dictionary messages, extension types) |
| `docs/source/format/Intro.rst` | the explanatory introduction to the same layouts (map as a list of key/value structs, "German strings") |
| `docs/source/format/images/*.svg` (17) | the layout diagrams `Intro.rst` includes (`all-diagrams.svg`, 685 KB, the union of them, not taken) |
| `docs/source/format/Glossary.rst`, `index.rst`, `Versioning.rst` | vocabulary, the format docs' table of contents, the format's version and compatibility rules |
| `format/Schema.fbs` | the authoritative type definitions: `Field` (name, nullable, type, dictionary, children), `Union` with `UnionMode` and `typeIds`, `Map` as `List<entries: Struct<key, value>>`, `ListView`, `RunEndEncoded`, `DictionaryEncoding` |
| `format/Message.fbs` | `FieldNode` (length, null count per flattened field), `Buffer`, `RecordBatch`, `DictionaryBatch` |
| `LICENSE.txt`, `NOTICE.txt` | licence |

Not taken: the C data interface (`CDataInterface.rst`, `CDeviceDataInterface.rst`,
`CStreamInterface.rst`), Flight and Flight SQL, ADBC, `CanonicalExtensions.rst`,
`StatisticsSchema.rst`, `Integration.rst`, `File.fbs`, `Tensor.fbs`, `SparseTensor.fbs`.

**How to fetch more.**

```bash
rev=446167169a0dc547e00e1bc29f417a40c0ca267a
p=docs/source/format/CanonicalExtensions.rst
mkdir -p "docs/arrow/$(dirname $p)"
curl -sL --fail -o "docs/arrow/$p" "https://raw.githubusercontent.com/apache/arrow/$rev/$p"
```

## File manifest

Every stored file except this one: 26 files, 721,090 bytes in all. Computed 2026-10-09 over
the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
cd03925a27219d326d622609fbcae6567279af8b8885c33d5969a9e4ef5d7525     110383  LICENSE.txt
afd895d61a00101f6d5a41cf518c83865d815e8109e956f512a0ce4ea9738c06       2916  NOTICE.txt
95994432d8cf3e70fe9176dde78d80cf4b10d8a13f1a65bf16cfc4b902554215      74468  docs/source/format/Columnar.rst
dc406f74769749cff1bf97bd3ba41023ad0da9da53a988b2c6d7dae614fe68a5       8181  docs/source/format/Glossary.rst
253b1298770693072abe127b4c3780472e115c3d882722c54120aa8e2bdc7168      21305  docs/source/format/Intro.rst
7cbacf937c33c169782f5459a5f94ddf31b4b0bacc58b4bf6b917b1ef071fb59       3897  docs/source/format/Versioning.rst
9be59359cfa6f7a63cd32c7410082111635bd0e8efdfd0ce421da680d6af38c0      13618  docs/source/format/images/bool-diagram.svg
f2e508779ec00622734a8f83f37e61920bd2dc84083c7ad84696e0ea16e6486b      32527  docs/source/format/images/columnar-diagram_1.svg
3b77f826dc626c2cb7443a6348229275dafedbfb7d3ad312406e636bffc12beb      25903  docs/source/format/images/columnar-diagram_2.svg
eaf9695c99b566703fd4437d83cb1ff0ed314da80f5552dbeaf937db86340c68      25937  docs/source/format/images/columnar-diagram_3.svg
c89fa1b45f055fc7f5e3aa1c5c1195e5fcc44e2d337b687951e2b9e17767b0cb      32934  docs/source/format/images/dense-union-diagram.svg
4a9ff93793d5bbe90fb5e5a43bcd524f0aa6968137ce565503ddf88712b7052e      30034  docs/source/format/images/dictionary-diagram.svg
c2c1e56d39ce2bf5086a495c8f7ea9ffc971de93bd34dda4550380d0f40f5ccb      28934  docs/source/format/images/fixed-list-diagram.svg
a940167aa4ab21672d3f29552c43baf944fe9da96a88937384ed494ac282422a      11776  docs/source/format/images/fixed-string-diagram.svg
11f5b2ddfbd780f81a35846b9f3b46e34336115629a6e0ca955face5a2231c76      28952  docs/source/format/images/map-diagram.svg
51372f24821dc188857efb3a07533b6fbea2e719562fae9a2d761cfcedf1e642      22532  docs/source/format/images/primitive-diagram.svg
384aeecb02f60fe09eb775faf16ea63901ec225d3c27ae8480863c7a8e737a08      27969  docs/source/format/images/ree-diagram.svg
a0a045e894b9677d73b429bbbbeae3499b1a56dd5d33efe007d83a7f7353520d      33035  docs/source/format/images/sparse-union-diagram.svg
ad4f947327d2e2aeffdc53ac29737eec78a7ec3d92f9bbc4442f83871be8617f      27871  docs/source/format/images/struct-diagram.svg
021620ee5e34e2ef1c776e64a03cefe296dea19cf8b27c0d484516785ccd805e      29971  docs/source/format/images/var-list-diagram.svg
30f3ca7e5b3d4211db9b344223d11123ab8cd564cf67d70a95838975f4d9e188      31754  docs/source/format/images/var-list-view-diagram.svg
ba25cc27eeefddc1619837752598dfb113fc9c58bb3a8817073ec4790b04005f      14529  docs/source/format/images/var-string-diagram.svg
874c5cc0c15b0b26efcd3e92b923e3003d38823a0eea62c52782ea180b2c346e      52160  docs/source/format/images/var-string-view-diagram.svg
deaf51eecf5159123d1a5274fbbb5dd7abbe9cb5abb9b06019807faf305e413a       1121  docs/source/format/index.rst
ec4274d76bfeb959b4a1961fa7ddb07dd06aa4a4a4960832c9fecec61f3bce53       6580  format/Message.fbs
c5187ee92f011736e3877f22372869aaf11930fb176eb63fa942d39a9a11be8d      21803  format/Schema.fbs
```
