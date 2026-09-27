# 10. Lowering

Lowering changes representation. It makes no decisions that need Idris
facts: all of those are made before or recorded in the contract.
- `idr-lower` is our C++ lowering pass.
- Everything after it is upstream MLIR and LLVM.

## Loops

Loops are syntax of first-order Core: a self tail call is a jump to a join
point (`CORE-LOOP-1`), which `Emit` writes as a block its own body branches
back to. There is no loop-making pass in MLIR.

- **LOW-TAIL-1 (v0 only; withdrawn in v3).** self tail calls are recognised in
  first-order Core (`CORE-LOOP-1`), not in MLIR.
- **LOW-TAIL-2 (v0 only; withdrawn in v3).** `idr-tail-loops` is gone; the loop
  exists before MLIR sees the program (`CORE-LOOP-1`).
- **LOW-TAIL-3 (v0).** Mutual and non-self tail calls get no guarantee. LLVM
  may still optimize them, and does when inlining makes them self calls.
- **LOW-TAIL-4 (v0).** A loop is a cycle of blocks, which no MLIR pass
  deletes, and the LLVM functions this pipeline makes never assert forward
  progress (no `mustprogress`), so LLVM keeps a loop that may not terminate
  (`SEM-EVAL-5`). *Revised in v3:* `idr.may_loop` and its `llvm.sideeffect`
  are gone with the region loops they protected.
  - Test: `tests/idr/pipeline/emit-llvm.mlir`

## Type conversion (`idr-lower`)

`idr-lower` is a dialect conversion with one `TypeConverter`:
- builtin integer types map to themselves;
- `!idr.erased` and `!idr.world` map to no values (1:0);
- `!idr.str` maps to `(!llvm.ptr, i64)`: the address and byte length of
  its UTF-8 data (1:2);
- `!idr.data<@T>` maps to `layout(T)` (1:N).

It applies upstream's structural conversions:
- `func.func` signatures, `func.call` and `func.return`;
- `cf.br` and `cf.cond_br`, and the block arguments they pass;
- `scf.if` and `scf.yield`, which its own division and cast lowering make.

- **LOW-SWITCH-1 (v0).** *Revised in v3:* `cf.switch` is converted 1:N by a
  pattern of our own. Upstream's structural conversion of `cf.switch` in the
  pinned MLIR 23.1.2 converts one value to one value
  (`SwitchOpConversion` takes an `OpAdaptor`), and an idr value becomes
  several.
  - Test: `tests/idr/lower/data-layout.mlir`, `tests/e2e/v3/prelude-lists`
- **LOW-BLOCK-1 (v3).** A function's blocks after the entry are converted
  with the branches to them: `func.func` is legal once its signature and
  entry block are.
  - Test: `tests/idr/lower/select.mlir`

### Data layout

- **LOW-DATA-1 (v0).** `layout(T)` for `idr.data @T` with constructors
  `C_0 … C_{n-1}` is computed as follows:
  1. **Components of a field.** An integer or `f64` field is one component. A
     `!idr.str` field is two (pointer and length). An `!idr.erased` or
     `!idr.world` field has none. An `!idr.data<@U>` field contributes the
     components of `layout(U)`, recursively (flattening). Recursion is
     finite by `IDR-DATA-4`.
  2. **Slots.** Start with an empty slot list. For each constructor in tag
     order, and each of its components in field order, assign the component
     to the first slot of the same type that this constructor has not
     already used, or append a new slot of that type.
  3. **Tag.** If `n ≥ 2`, the layout starts with a tag, followed by the slots.
     The tag type is `i8` if `n ≤ 2^8`, `i16` if `n ≤ 2^16`, and `i32`
     otherwise. If `n = 1` there is no tag. If `n = 0` the layout is empty.
  - So an enum is just its tag, a record is just its fields, and different
    constructors reuse slots of the same type. Distinct constructors are
    distinguished by the tag alone ("no confusion", as in Chataing, Dolan,
    Scherer, Yallop, POPL 2024).
- **LOW-DATA-2 (v0).** The ops lower as follows:
  - `idr.con @T::@C` gives the tag constant and the constructor's components
    in their slots. Slots the constructor does not use get `ub.poison`.
  - `idr.tag` gives the tag slot, extended to `i64` (`arith.extui`), or the
    constant `0` when `n = 1`.
  - `idr.field %v[@C, i]` gives the components of field `i` from `C`'s
    slots.
  - Test: `tests/idr/lower/data-*.mlir` (FileCheck against hand-computed
    layouts)
- **LOW-ERASE-1 (v0).** `!idr.erased` values, parameters, arguments and fields
  disappear through the 1:0 conversion. `idr.erased` ops are removed.
- **LOW-SEL-1 (v2).** Upstream `canonicalize` turns a branch that only
  chooses between two values into `arith.select`, also for idr types. An
  `arith.select` of an idr type lowers to one `arith.select` per component.
  - Test: `tests/idr/lower/select.mlir`
- **LOW-DATA-3 (v0).** `idr-lower` erases all `idr.data` ops. After it, no
  `idr` op or type remains.
  - Check: conversion legality (the `idr` dialect is illegal)

### Static strings and characters (v1)

- **LOW-STR-1 (v1).** Each distinct `idr.str.lit` byte sequence becomes one
  private constant global (`llvm.mlir.global internal constant`) holding its
  UTF-8 bytes. The op lowers to that global's address and the byte length.
  Equal literals share one global. Strings never touch the heap.
- **LOW-CHAR-1 (v1).** `idr.to_char` lowers to a range check and a `select`,
  giving the value if it is a scalar value and `0` otherwise
  (`SEM-CHAR-3`).

### IO (v1)

- **LOW-IO-1 (v1).** Standard output goes through one fixed-size buffer in
  static storage (`.bss`), never the heap. The buffer is flushed with a loop
  over `write(1, …)` that handles partial writes. A failed write abandons
  the rest of that output (`SEM-IO-6`). `EINTR` needs no handling: the
  program installs no signal handlers, so `write` is never interrupted
  with it, and reading `errno` would need a libc symbol (`LOW-EXT-1`). The
  buffer is flushed:
  - when it fills;
  - before every read from standard input;
  - before `exit`;
  - before a crash's message;
  - when `main` returns.

  This gives `SEM-IO-4`.
- **LOW-IO-2 (v1).** The IO ops lower as follows:

  | Op | Lowering |
  | --- | --- |
  | `put_str` | append the bytes to the buffer, or write them through if they exceed it |
  | `put_char` | append the UTF-8 encoding of the character |
  | `put_int` | write the decimal digits into a 20-byte stack buffer, then append them |
  | `get_char` | flush, then decode one UTF-8 scalar from `read(0, …)` through a fixed-size static input buffer (`SEM-IO-3`: `'\0'` at end of input, U+FFFD for malformed input) |
  | `exit` | flush, then `_exit(code)` |

  The helper routines are private functions generated by `idr-lower` into the
  module. There is no runtime library.
- **LOW-IO-4 (v3).** `get_byte` flushes output, then takes one byte from the
  same static input buffer as `get_char`, or returns `255` at the end of
  input (`SEM-IO-7`).
  - Test: `tests/idr/lower/get-byte.mlir`
- **LOW-IO-3 (v1).** `!idr.world` values disappear through the 1:0 conversion.
  Effect order is kept because each `idr.io` op has IO-resource effects
  (`IDR-EFF-2`), and lowering emits the calls in the same order.

### Doubles (v2)

- **LOW-DBL-1 (v2).** `idr.to_int` lowers to a `math.isfinite` check that
  branches to a crash ("cast of a non-finite Double", `LOW-CRASH-1`) unless
  the operand is a finite constant, then a call of the helper
  `__idr_f64_to_i64`, then `arith.trunci` to the result width. The helper
  takes the value apart into sign, exponent and mantissa and shifts, so the
  64-bit result is the truncated value modulo 2^64 for every finite double
  (`arith.fptosi` is poison out of range). Wrapping to a narrower width is
  truncation (`SEM-DBL-4`).
  - Test: `tests/idr/lower/double.mlir`, `tests/e2e/v2/double-*`
- **LOW-DBL-2 (v2).** `idr.io.put_double` calls the helper
  `__idr_put_double`, which writes the text of `SEM-DBL-5` through a stack
  buffer. The digits come from Ryu (Adams, PLDI 2018), in its general form,
  with one change: an exact tie rounds up, as the reference does. Its two
  tables of 128-bit powers of five are static constants that
  `tools/GenRyuTables.idr` computes with exact integers (`make ryu-tables`);
  `make check` verifies that the checked-in tables match.
  - Test: `tests/e2e/v2/double-print-fuzz` (45,000 values against Chez,
    including decimal ties), `tests/spec/ryu-tables`
- **LOW-DBL-3 (v2).** The `arith` float ops and the `math` ops pass through
  `idr-lower` unchanged, and `convert-to-llvm` turns them into LLVM
  instructions and intrinsics. LLVM's back end turns the intrinsics that
  have no instruction on the target into calls of the `libm` functions of
  the same name (`SEM-DBL-3`, `SEM-DEV-2`). Nothing sets fast-math flags, and
  LLVM does not contract `a * b + c` into a fused multiply-add without them.
  - Test: `tests/e2e/v2/double-basics`

- **LOW-DBL-4 (v3).** `idr.double_head` calls the helper
  `__idr_double_head`, which decides the sign and the special values as
  `__idr_put_double` does and otherwise returns the leading digit of the
  Ryu digits: the same text's first character, without writing it.
  - Test: `tests/e2e/v3/show-values`, `tests/idr/lower/double-head.mlir`

### Division and modulus

- **LOW-DIV-1 (v0).** `idr.div` and `idr.mod` lower to `arith` and `scf`,
  computing exactly `SEM-INT-3`:
  - **Zero divisor.** If the divisor may be zero (it is not a nonzero
    constant), branch to a crash (`LOW-CRASH-1`) when it is zero.
  - **Signed overflow case.** If the divisor may be `-1`, handle
    `MIN div -1` as `MIN` and `MIN mod -1` as `0` before using
    `arith.divsi`/`arith.remsi`, which are undefined for that pair.
  - **Signed rounding.** Compute `q = divsi(a, b)` and `r = remsi(a, b)`.
    - If `r < 0`, adjust: `div` gives `q - 1` when `b > 0` and `q + 1`
      otherwise; `mod` gives `r + b` when `b > 0` and `r - b` otherwise.
    - Upstream `arith.floordivsi` is floor division, not Euclidean, and is
      not used.
  - **Unsigned.** Use `arith.divui` and `arith.remui` after the zero check.
  - Test: `tests/e2e/v0/SEM-INT-*` (the edge-case tables of `tests/Sem.idr`,
    with `Refl` oracles);
    `tests/e2e/v0/crash-*` (crashes); `tests/idr/lower/crash.mlir`

### Crashes

- **LOW-CRASH-1 (v0).** A crash lowers to a call to the generated private
  function `__idr_crash(msg, len)`, which:
  1. flushes the output buffer (`LOW-IO-1`);
  2. writes `msg` to file descriptor 2;
  3. calls `_exit(1)`, which is declared `noreturn`, so LLVM treats the
     code after the call as unreachable.

  `msg` is an internal constant global (static data, not heap). The message
  names the cause and the Idris source location of the operation. The call
  sits inside an `scf.if` branch, which needs a terminator, so the
  `llvm.unreachable` of draft 2 is not emitted; `noreturn` gives LLVM the
  same fact.
- **LOW-CRASH-2 (v3).** `idr.crash` lowers to `__idr_crash` with its message
  and location, like `LOW-CRASH-1`, and each of its results to `ub.poison`
  of each component.
  - Test: `tests/idr/lower/crash-op.mlir`
- **LOW-EXT-1 (v0).** The only external symbols the object file may
  reference are `write` and `_exit`, from v1 also `read`, and from v2 the
  `libm` functions `exp`, `log`, `pow`, `sin`, `cos`, `tan`, `asin`,
  `acos`, `atan`, `sqrt`, `floor`, `ceil`, and `exp2` and `ldexp`, which
  LLVM substitutes for some calls of `pow` (`SEM-DEV-2`). None of them
  allocates. The driver links `libm` (`-lm`). The toolchain's `crt` files
  provide the process entry.
  - Test: every e2e fixture checks the object's undefined symbols
    (`TEST-HEAP-1`)

### Entry point

- **LOW-ENTRY-1 (v0).** `idr-lower` generates a public
  `func.func @main() -> i32`:
  - **`int` entry:** it calls the root, truncates the `i64` result to `i32`
    (`arith.trunci`), and returns it. The process exit status is therefore
    the low 8 bits of the result (`SEM-PROG-1`).
  - **`io` entry (v1):** it calls the root, whose world argument has
    disappeared, discards the result, flushes output, and returns 0
    (`SEM-PROG-2`).

## Upstream lowering and code generation

- **LOW-UP-1 (v0).** After `idr-lower`, the module contains only `func`,
  `arith`, `scf`, `cf`, `ub` and `llvm` ops. Upstream `convert-scf-to-cf`,
  `convert-to-llvm` and `reconcile-unrealized-casts` take it to the LLVM
  dialect. No other lowering pass is ours.
- **LOW-TARGET-1 (v0).** The LLVM module is compiled in process for the host
  target triple:
  - the generic CPU for that triple (no `-march=native`), so objects are
    reproducible;
  - position-independent code;
  - optimization level O2.
- **LOW-ATTR-1 (v0).** No LLVM function attribute or metadata that asserts
  termination or forward progress is added (`SEM-EVAL-5`).
- **LOW-CC-1 (v0).** All functions use the C calling convention. Internal
  functions are private, so LLVM may change their calling convention itself.
