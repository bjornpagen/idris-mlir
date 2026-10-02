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
  with the reason. Where it only writes a Double through Chez's printer, the
  test reads its output as it reads the Chez build's.
- That reading is `tests/lib/chez-doubles.ss`: Chez's text of a double
  becomes ours, where a `double-*` class says the printers differ. The
  comparisons of whole outputs line by line use it: the fuzzer, the two
  levels, the runtime's printer and its API test. A fixture that shows a
  class names it instead.
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

### The text of a Double: IEEE 754, then ours

- **Idris:** defines none.
  - The Prelude's `show` is the backend's `prim__cast_DoubleString`.
  - Chez writes `number->string`.
  - RefC writes `printf("%f")`, so 0.1 is `0.100000`.
  - The evaluator uses the `show` of the Chez the compiler runs on.
- **IEEE 754 requires** that:
  - the text of a double read back as the double, under correct
    rounding, ties to even by default;
  - the infinities be spelled `inf` or `infinity`, NaN `nan`, in any case.
- **Ours:**
  - Digits: the fewest significant digits that read back, the nearest of
    those, and of two equally near the even one. These are Ryu's digits.
  - Layout: positional from 1e-3 up to 1e10 with a digit after the point,
    else `d.ddde-x`. It is the Chez backend's layout, so that the oracle
    compares every other text.
  - Specials: `inf`, `-inf` and `nan`. A NaN's sign is not written:
    IEEE 754 gives it no meaning, and x86-64 and arm64 make NaNs of
    opposite sign for the same operation.
- **Was**, Chez's printer copied in three places; now IEEE 754 or ours:

  | class | Chez's printer | ours |
  | --- | --- | --- |
  | `double-subnormal-suffix` | R6RS's mantissa width on a subnormal, `5e-324\|1`; no Idris reader needs it | `5e-324` |
  | `double-tie-even` | ties to the larger candidate, `12.886856079101563` | ties to even, `12.886856079101562`, as Ryu itself breaks them |
  | `double-special-text` | Scheme's `+inf.0`, `-inf.0`, `+nan.0` | `inf`, `-inf`, `nan` |

- **Tests:**
  - `tests/programs/prelude/double-subnormals`, `double-ties` and
    `double-infinities-nan`; `double-basics` and `show-values` keep their
    other lines, compared with Chez;
  - `tests/toolchain/double-print`: 176,000 doubles, equal to Chez's text
    read through the classes, each class seen;
  - `tests/toolchain/runtime-api`: 30,013 doubles read back from their
    text;
  - `tests/idr/eval/fold-vs-jit.mlir` and `tests/idr/e2e/doubles.mlir`.
- **Also:** `idr.double_head`'s range is now `'-'` to `'n'`.

### Casts from String: Idris's literals, IEEE 754

- **Idris:** defines none.
  - The Prelude documents no syntax.
  - The evaluator hands a string to the `cast` of the Chez it runs on
    (`Core/Primitives.idr`: `castInteger [Str i] = BI (cast i)`), and does
    not reduce a cast to Int8 through Bits64 at all.
  - The backends disagree. Chez reads a Scheme number with
    `string->number` and truncates it: 12.7 is 12 as an Int, and `"1/2"`
    is 0.5 as a Double. Casting `"+inf.0"` to Int crashes it. RefC reads
    a prefix with `atoi` and `atof`, so `"12abc"` is 12 as an Int, and an
    Integer with `mpz_set_str`.
- **Ours:** the whole string is an optional sign and a literal of the
  target type as Idris's lexer writes it (`Parser/Lexer/Source.idr`).
  Anything else is 0, since a cast is total.
  - Every number type reads an integer literal: decimal, `0b`, `0o`, `0x`
    or `0X`, with single underscores between digits. An integer type
    takes it modulo its width.
  - Double also reads a decimal literal (`digits.digits`, optional
    exponent `e`, sign, digits), correctly rounded.
  - Double also reads digits with an exponent and no point, which is how
    `show` writes a double with one significant digit (`1e21`). IEEE 754
    requires a double's text to read back.
  - Double also reads IEEE 754's `inf`, `infinity` and `nan`, in any case.
- **So:** 12.7 is 0 as an Int, being no literal of one, and `.5`, `5.`,
  `1E3` and surrounding spaces are no number.
- **Divergence:** `cast-string-literal`.
- **Tests:**
  - `tests/programs/prelude/cast-from-string`, with accepted and refused
    strings, cast at run time and folded;
  - the table in `tests/toolchain/runtime-api`;
  - `tests/idr/eval/fold-vs-jit.mlir`.
- **Also:** the two-levels casts of literals are compared with Idris's
  evaluator again, no longer set aside as host-dependent.

### Kept, with their authority

- **Integer div and mod are Euclidean**, the remainder in [0, |b|).
  - Authority: Idris's own definition. Upstream's test suite requires it
    of every backend (`tests/{chez,refc,node}/integers`: a `mod` by a
    negative divisor is not negative).
  - Each backend computes it its own way: Chez `blodwen-euclidMod`, RefC
    `mpz_mod`, Node `_mod`.
- **Integer's bitwise operations are those of infinite two's complement.**
  - Authority: the same tests, on negative Integers.
  - RefC's `mpz_and`, `mpz_ior` and `mpz_xor` agree.
- **Integer to Double is the nearest double, ties to even**, an infinity
  past the largest.
  - Authority: IEEE 754's conversion under its default rounding.
  - RefC truncates (`mpz_get_d`), which IEEE 754's default does not allow.
    We follow IEEE 754.
- **Strings compare in code point order**, which is UTF-8's byte order.
  - Authority: Unicode.
  - Chez's `string<?` and RefC's `strcmp` agree. Node compares UTF-16
    code units, which puts supplementary characters before U+E000.
- **`substr` clamps.**
  - Authority: the Prelude documents it. An index past the end gives `""`,
    and a length past the end is cut.
  - A negative start or length, which only a call of the primitive itself
    passes, counts as 0: ours.
  - RefC's `strSubstr` neither clamps nor counts characters, only bytes.
- **putChar writes UTF-8** (`put-char-utf8`). The decision predates this
  policy; see below.

## Left for the user

- **putChar.**
  - The Prelude declares it as C's `putchar` (`%foreign "C:putchar"`) and
    documents it as writing "one single-byte character", with
    `putCharLn` for a multi-byte one.
  - By the order above, that makes its meaning the low byte, which both
    stock backends write.
  - This compiler writes UTF-8 (`put-char-utf8`), a decision taken
    before this policy. Reversing it needs a byte-writing op for putChar
    beside `idr.io.put_char`, which output fusion uses for the characters
    of strings.
- **Casting NaN or an infinity to an integer crashes** (`idr.to_int`), as
  Chez's `exact-truncate` raises. Idris's casts are total. IEEE 754 makes
  the conversion invalid, with a result it leaves to the language.
- **Outside the runtime:** the compiler still cites Chez for a buffer
  write of an Int outside 0 to 255, which crashes "as Chez's
  bytevector-u8-set! refuses it" (`IdrOps.td`,
  `Registry/Primitives.idr`). Its authority is base's `Data.Buffer`,
  which this audit did not cover.
