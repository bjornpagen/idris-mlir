# 10. Lowering

Lowering changes representation. It makes no decisions that need Idris
facts: all of those are made before or recorded in the contract.
- `idr-tail-loops` and `idr-lower` are our C++ passes.
- Everything after them is upstream MLIR and LLVM.

## Self tail calls (`idr-tail-loops`)

- **LOW-TAIL-1 (v0).** A `func.call @f` inside `func.func @f` is a *self tail
  call* when its results are the function's results unchanged. That means
  either:
  - `func.return` returns exactly its results, immediately after the call;
    or
  - `scf.yield` yields exactly its results, immediately after the call, and
    the enclosing `scf.if` or `scf.index_switch` is itself in tail position.
    Tail position is: immediately followed by a `func.return` of its results,
    or yielded in turn by an enclosing region in tail position.
- **LOW-TAIL-2 (v0).** `idr-tail-loops` rewrites every function that contains
  a self tail call into a loop (`scf.while`) that carries the arguments,
  including `!idr.erased` ones. After the pass, no self tail call remains.
  Other calls are unchanged.
  - Check: a post-condition assertion in the pass
  - Test: `tests/idr/tail-loops/*.mlir`; `tests/e2e/v0/tail-loop-deep.idr`
    runs 10^8 iterations with the stack limited to 1 MiB (`SEM-RES-2`)
- **LOW-TAIL-3 (v0).** Mutual and non-self tail calls get no guarantee in v0.
  LLVM may still optimize them.

## Type conversion (`idr-lower`)

`idr-lower` is a dialect conversion with one `TypeConverter`:
- builtin integer types map to themselves;
- `!idr.erased` and `!idr.world` map to no values (1:0);
- `!idr.str` maps to `(!llvm.ptr, i64)`: the address and byte length of
  its UTF-8 data (1:2);
- `!idr.data<@T>` maps to `layout(T)` (1:N).

It applies upstream's structural conversions:
- `func.func` signatures, `func.call` and `func.return`;
- `scf.if`, `scf.while`, `scf.yield`.

It also applies our own pattern for `scf.index_switch`. Upstream
`populateSCFStructuralTypeConversions` covers `for`, `if`, `while` and
`condition` but not `index_switch` (verified in the pinned source). So:
- **LOW-SWITCH-1 (v0).** `idr-lower` includes a 1:N structural conversion
  pattern for `scf.index_switch`, equivalent to upstream's `scf.if` pattern.
  - Test: `tests/idr/lower/switch-1n.mlir`

### Data layout

- **LOW-DATA-1 (v0).** `layout(T)` for `idr.data @T` with constructors
  `C_0 … C_{n-1}` is computed as follows:
  1. **Components of a field.** An integer field is one component. A
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
  - `idr.tag` gives the tag slot, converted to `index`
    (`arith.index_castui`), or the constant `0` when `n = 1`.
  - `idr.field %v[@C, i]` gives the components of field `i` from `C`'s
    slots.
  - Test: `tests/idr/lower/data-*.mlir` (FileCheck against hand-computed
    layouts)
- **LOW-ERASE-1 (v0).** `!idr.erased` values, parameters, arguments and fields
  disappear through the 1:0 conversion. `idr.erased` ops are removed.
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
  over `write(1, …)` that handles partial writes and `EINTR`:
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
- **LOW-IO-3 (v1).** `!idr.world` values disappear through the 1:0 conversion.
  Effect order is kept because each `idr.io` op has IO-resource effects
  (`IDR-EFF-2`), and lowering emits the calls in the same order.

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
  - Test: `tests/e2e/v0/SEM-INT-3-*.idr` (the edge-case table, with `Refl`
    oracles); `tests/e2e/v0/SEM-INT-4-*.idr` (crashes)

### Crashes

- **LOW-CRASH-1 (v0).** A crash lowers to three `llvm` ops, preceded from v1
  by flushing the output buffer (`LOW-IO-1`):
  1. a call to `write(2, msg, len)`;
  2. a call to `_exit(1)`;
  3. `llvm.unreachable`.

  `msg` is an internal constant global (static data, not heap). `_exit` is
  declared `noreturn`. The message names the cause and the Idris source
  location of the operation.
- **LOW-EXT-1 (v0).** The only external symbols the object file may
  reference are `write` and `_exit`, and from v1 also `read`. The toolchain's `crt` files provide the
  process entry.
  - Test: `tests/e2e/v0/heap-free`, which checks the object's undefined
    symbols (`TEST-HEAP-1`)

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
