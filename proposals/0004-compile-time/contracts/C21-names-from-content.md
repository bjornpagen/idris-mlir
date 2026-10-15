## C21 Names from content

Producers: U01 (the C++ helper) and U14 (the Idris function), with the
shared test vectors below. Decision: 0004 D18 (as 0006 D16 decided), §4
stage 1, §6's row "Names from counters and module order".

### 1. The hash and the name

- The hash of a key is XXH3's 128-bit variant of the key's bytes (the
  UTF-8 of its text, no terminator), seed 0: LLVM's
  `llvm::xxh3_128bits` (`L/include/llvm/Support/xxhash.h:58-70`,
  `L/include/llvm/ADT/ArrayRef.h:561-563`). Only `low64` is used.
- Written as exactly 16 lower-case hexadecimal digits, most significant
  first, zero-padded: `low64 = 0x6001C324468D497F` is `6001c324468d497f`.
- A generated name is `<owner>.<kind>.<hash>`: the owner's symbol (or the
  data type's identifier), a `.`, the kind, a `.`, the 16 digits. The kind
  is a fixed lower-case word per mechanism, named by the contract of the
  lane that names: `lam`, `delay` (U14, C20, C22); `sum` with the owners
  `fn$` and `lazy$`, and `defun` for the remade user types (U02, C06);
  `spec`, `raise` (U04, C09); `buffers` (U12, C15); `box` (U01's
  `layout::fit`); `capture` (U03), `acc`, `trmc` (U09), `excl` (U08). A
  kind is never a counter.
- The key is the text of what the name is a function of, chosen by the
  lane that names (a printed key attribute, a label set, a body as C01 §7
  writes it). Nothing created earlier in the run, no counter and no module
  position is part of it.
- Static data under `__idr.` (§5.3 item 3) uses the hash alone after its
  prefix (`__idr.<what>.<hash>`, U10).

### 2. C++ (`include/idr/IR/Symbols.h`, defined in `lib/IR/Symbols.cpp`)

```cpp
namespace idr {
// The low 64 bits of XXH3-128 of `key`, as 16 lower-case hex digits.
std::string contentHash(llvm::StringRef key);
// `<owner>.<kind>.<contentHash(key)>`.
std::string contentName(llvm::StringRef owner, llvm::StringRef kind, llvm::StringRef key);

// The names one pass makes, each with the key it was made from, so that a
// second key with the same name is caught where the name is interned: an
// internal error at `at`, never a merge and never a longer name.
class ContentNames {
public:
  // contentName(owner, kind, key) as a StringAttr; failure, after the
  // internal error, when the name was interned from another key.
  mlir::FailureOr<mlir::StringAttr> intern(mlir::Location at, llvm::StringRef owner,
                                           llvm::StringRef kind, llvm::StringRef key);
private:
  llvm::StringMap<std::string> keys;   // name -> key
};
}
```

The internal error reads `internal error: two keys name <name>: <key1> and
<key2>`. A symbol that already exists under a name with the same key is
the same thing made again: the caller reuses it.

### 3. Idris (U14)

A plain-Idris XXH3-128 over `Bits64` in the frontend (U14 names its module,
under `compiler/src/IdrisMLIR/`), with `contentHash : String -> String` and
`contentName : String -> String -> String -> String` of §1's definitions
over the UTF-8 bytes of the string. Its test (U18's program tests or U14's
own, as U14's part says) checks the vectors of §4 as committed expected
values.

### 4. Test vectors

The published XXH3 sanity buffer: byte `i` of the buffer is the top byte
of `g_i`, where `g_0 = 2654435761` (PRIME32) and `g_{i+1} = g_i *
11400714785074694797` (PRIME64) mod 2^64; the vector for length `n` is the
first `n` bytes (`L/unittests/Support/xxhashTest.cpp:16-33, 78-125`). The
expected `low64`, written as §1 writes it:

| length | contentHash |
| --- | --- |
| 0 | `6001c324468d497f` |
| 1 | `c44bdff4074eecdb` |
| 6 | `3e7039bdda43cfc6` |
| 12 | `061a192713f69ad9` |
| 24 | `1e7044d28b1b901d` |
| 48 | `f942219aed80f67b` |
| 81 | `5e8bafb9f95fb803` |
| 222 | `f1aebd597cec6b3a` |
| 403 | `cdeb804d65c6dea4` |
| 512 | `617e49599013cb6b` |
| 2048 | `dd59e2c3a5f038e0` |
| 2240 | `6e73a90539cf2948` |
| 2367 | `cb37aeb9e5d361ed` |

Text vectors, the UTF-8 of the string (U14's reference port, C21's Idris
half, which reproduces every row above):

| key | contentHash |
| --- | --- |
| `a` | `e6c632b61e964e1f` |
| `abc` | `78af5f94892f3950` |
| `Prelude.Types.List[Int]` | `7accdea12f15d0f3` |

Name vectors: `contentName("Main.foo", "lam", "")` is
`Main.foo.lam.6001c324468d497f`; `contentName("main", "lam", "abc")` is
`main.lam.78af5f94892f3950`.

### 5. Consumers

U02, U03, U04, U08, U09, U10 (the C++ helper); U14 (the Idris function,
its own names and instance symbols, which take `contentHash` of the
instance's identity, 0008 §4.10); U17, U18 (fixtures check a name's
owner prefix and kind, never its digits).
