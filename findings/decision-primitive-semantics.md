# Decision: where a primitive's meaning comes from

The user took this decision on 2026-10-02, on finding the runtime
justifying behaviour by "as Chez does it". The runtime (`runtime/`) is
the one meaning of every primitive, which the folders and compile-time
evaluation call too. The stock Chez backend is the oracle that catches our
bugs, not the specification.

## The order

A primitive's meaning comes from, in this order:

1. **Idris's own definition**, where the language defines it: the
   Prelude's documented meaning, and the compiler's evaluator where it is
   backend-independent. `tests/TwoLevels.idr` compares our compiled
   programs with the evaluator.
2. **The standard the primitive implements**: Unicode for text, IEEE 754
   for Double, POSIX and C for I/O.
3. **Only then a decision of ours**, written down here.

## Chez is the oracle

- Where we differ from Chez on purpose, `tests/lib/chez-divergences` names
  the class and the reason. A fixture that shows it carries `chez-differs`
  (the class) and `chez-stdout` (what Chez prints); `tests/testutils.sh`
  lists the marks.
- Idris's evaluator runs on Chez itself. Where it computes a value through
  a Chez quirk, the two-levels corpus marks the term `-- idris-differs:`
  with the reason.
- Where we claim the backends disagree, we checked upstream's other
  backend, RefC (`third_party/Idris2/support/refc`), and say so below.

## The runtime's behaviours

### Bytes from outside, as text: Unicode

- **Authority:** the Unicode Standard, chapter 3, its recommended practice
  of U+FFFD substitution of maximal subparts. A maximal subpart is the
  longest prefix of a well-formed sequence at that point, or one byte when
  no prefix is; each becomes one U+FFFD. The WHATWG Encoding Standard's
  UTF-8 decoder requires the same.
- **Was:** one U+FFFD per ill-formed byte, "as Chez's decoder replaces
  it". That was false. Chez replaces each ill-formed sequence with one
  U+FFFD.

  | bytes in the line | Unicode's rule | we did | Chez |
  | --- | ---: | ---: | ---: |
  | `61 E2 82 62`, truncated 3-byte | 1 | 2 | 1 |
  | `F0 9F 98 63`, truncated 4-byte | 1 | 3 | 1 |
  | `C0 80 64`, overlong | 2 | 2 | 1 |
  | `ED A0 80 65`, encoded surrogate | 3 | 3 | 1 |
  | `E9 66`, lone lead byte | 1 | 1 | 1 |

- **Now:** `idris_rt_str_from_bytes` (`runtime/strings.cc`) is the one
  decoder of outside bytes. getLine is its only caller today; any later
  conversion of bytes or C strings goes through it. simdutf still
  validates the well-formed runs. The new code is only the table of
  well-formed byte ranges, which yields each maximal subpart.
- **Divergence:** `utf8-maximal-subparts`, for the overlong form and the
  surrogate.
- **Tests:**
  - `tests/programs/io/getline-ill-formed`: the five lines and
    well-formed text;
  - `tests/toolchain/runtime-api`: the Unicode Standard's example of
    U+FFFD in UTF-8 conversion, and more;
  - `tests/programs/io/prelude-getline`.

### getLine's line end: the Prelude, POSIX

- **Authority:** the Prelude documents getLine as one line "without the
  trailing newline". POSIX ends a line at `'\n'`.
- **Ours:** a `"\r\n"` ending is removed whole too, since text written
  elsewhere ends its lines so.
- **Was:** the line cut at its first `'\r'` anywhere, so `wor\rld` read
  as `wor`. That comes from upstream's C support (`idris2_getStr` in
  `support/c/idris_support.c`): it nulls every `'\r'` and `'\n'`, though
  its own comment says it removes the trailing newline. Chez and RefC both
  call it. Node's getLine keeps the `'\n'`.
- **Now:** only a trailing `'\n'` or `"\r\n"` is removed. A line at the end
  of input without one is read whole.
- **Divergence:** `getline-carriage-return`, from both upstream C-backed
  backends.
- **Test:** `tests/programs/io/prelude-getline`.
