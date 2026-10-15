## C21 Names from content: the Idris half and the shared test vectors

Producer of this half: U14. The C++ half (the helper over
`llvm::xxh3_128bits`) is U01's, in its own C21 file; both halves
implement the one rule below and are checked against the one table of
vectors below. Authority: 0004 §4 stage 1 and D18, 0007 §4.4, §4.5 and
D16, 0009 §4.10.

### The rule (both halves)

- The hash is XXH3's 128-bit variant with seed 0 and the default
  192-byte secret, the algorithm of
  `.toolchain/build/llvm-project/llvm/lib/Support/xxhash.cpp:480-956`
  (`llvm::xxh3_128bits`), over the bytes of the key. A key given as text
  is hashed as its UTF-8 bytes.
- A generated name carries `low`, the low 64 bits (`XXH128_hash_t::low64`),
  written as exactly 16 lowercase hexadecimal digits, most significant
  first, zero-padded. A key carries all 128 bits where it is stored.
- A generated function's symbol is `<owner>.<kind>.<hex16>`: `owner` the
  symbol of the function it is made from, `kind` one lowercase word
  saying what it is, `hex16` the low half of the hash of its structural
  key. The frontend's kinds are `lam` and `delay` (emission, U15); the
  C++ kinds are U01's helper's callers' (`.spec`, `.raise`, `.capture`,
  `.acc`, `.trmc`, `.excl`, by their lanes).
- An instance's symbol is C20's `keyText`: its key printed, followed by
  `;` and `hex16` of its identity hash exactly when the print dropped
  part of the identity (0009 §4.10).
- Two different keys whose names meet are caught where the name is
  interned, by full equality of the keys, and that is an internal error:
  never a merge, never a counter, never a widened name.
- Names are made only from keys. No counter, insertion order, thread or
  arrival order reaches a name.

### The Idris declarations (U14, `compiler/src/IdrisMLIR/Ids.idr`, module `IdrisMLIR.Ids`)

```idris
||| XXH3's 128-bit hash of a byte sequence: its low and high 64 bits.
public export
record Hash128 where
  constructor MkHash128
  low : Bits64
  high : Bits64

||| XXH3's 128-bit hash, seed 0 and the default secret, of the bytes.
export
xxh3_128 : List Bits8 -> Hash128

||| The UTF-8 bytes of a string, each character encoded by its scalar
||| value in one to four bytes.
export
utf8 : String -> List Bits8

||| A word as exactly 16 lowercase hexadecimal digits, most significant
||| first.
export
hex16 : Bits64 -> String

||| The low half of the hash of a key's text, as 16 hex digits.
export
contentHash : String -> String
contentHash key = hex16 (xxh3_128 (utf8 key)).low

||| The symbol of what `key` denotes, generated from `owner`:
||| `<owner>.<kind>.<hex16>`.
export
contentName : (owner : String) -> (kind : String) -> (key : String) -> String
contentName owner kind key = owner ++ "." ++ kind ++ "." ++ contentHash key
```

Invariants: every function is total and pure, in plain Idris over
`Bits8` and `Bits64` (base's modular arithmetic, `Data.Bits`), with no
`%foreign`, no primitive of ours and no IO, so the frontend computes the
same values on Chez at stage 0 and natively after (0007 D16). The port
follows the reference's length classes exactly: 0, 1 to 3, 4 to 8, 9 to
16, 17 to 128, 129 to 240, and the long hash in blocks of 16 stripes of
64 bytes with the secret's last stripe for the scramble. The 64 by 64
to 128-bit product is computed by 32-bit halves, as the reference's
portable path writes it (`xxhash.cpp:600-620`).

### Shared test vectors

The published values: LLVM's `llvm/unittests/Support/xxhashTest.cpp:78-130`,
which are xxHash's own sanity check. The input of length `n` is the first
`n` bytes of the sanity buffer: start with `g = 2654435761` (a 64-bit
word); for each byte, emit `g >> 56` and set `g = g * 11400714785074694797`
modulo 2^64 (`xxhashTest.cpp:15-31`).

| n | low | high |
| --- | --- | --- |
| 0 | `6001c324468d497f` | `99aa06d3014798d8` |
| 1 | `c44bdff4074eecdb` | `a6cd5e9392000f6a` |
| 6 | `3e7039bdda43cfc6` | `082afe0b8162d12a` |
| 12 | `061a192713f69ad9` | `6e3efd8fc7802b18` |
| 24 | `1e7044d28b1b901d` | `0ce966e4678d3761` |
| 48 | `f942219aed80f67b` | `a002ac4e5478227e` |
| 81 | `5e8bafb9f95fb803` | `4952f58181ab0042` |
| 222 | `f1aebd597cec6b3a` | `337e09641b948717` |
| 403 | `cdeb804d65c6dea4` | `1b6de21e332dd73d` |
| 512 | `617e49599013cb6b` | `18d2d110dcc9bca1` |
| 2048 | `dd59e2c3a5f038e0` | `f736557fd47073a5` |
| 2240 | `6e73a90539cf2948` | `ccb134fbfa7ce49d` |
| 2367 | `cb37aeb9e5d361ed` | `e89c0f6ff369b427` |

Three text vectors, the UTF-8 bytes of the string, computed by a
reference port that reproduces every row above (the empty string is
row 0):

| key | low | high | `contentHash key` |
| --- | --- | --- | --- |
| `a` | `e6c632b61e964e1f` | `a96faf705af16834` | `e6c632b61e964e1f` |
| `abc` | `78af5f94892f3950` | `06b05ab6733a6185` | `78af5f94892f3950` |
| `Prelude.Types.List[Int]` | `7accdea12f15d0f3` | `5239c24bd2494372` | `7accdea12f15d0f3` |

So `contentName "main" "lam" "abc"` is `main.lam.78af5f94892f3950`.

### Who checks what

- U18 commits the frontend's check: a test under `tests/compiler` that
  runs `IdrisMLIR.Ids.xxh3_128` on the sanity buffer at every `n` of
  the first table and on the three texts, and compares with the tables
  as its committed expected file. It lists that test as
  `NEEDS-ACCEPTANCE` only if it cannot build an Idris program over the
  package's modules from the suite.
- U01's C++ helper is checked by the same two tables (its own test, by
  U17 or U18 as its contract says); `llvm::xxh3_128bits` is upstream's
  and already passes the first table.

### Consumers

- U15: the names of lambdas and delays in symbol form
  (`contentName <owner symbol> "lam" <key>` and `"delay"`), and the
  dump's structural text of a Core term, `Term.showBody` with the
  module's `Names`, which prints no location and no binder name, as the
  key text it may hash.
- U14 itself: `Translate/Keys.idr` suffixes a lossy key's symbol with
  `hex16 (xxh3_128 (utf8 (identityText …))).low` (C20).
- U01: the vectors for its helper.
- U18: the test above.
