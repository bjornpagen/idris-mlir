# 10. Lowering

Lowering changes representation. It makes no decisions that need Idris
facts: all of those are made before or recorded in the contract.
- `idr-tail-loops` makes loops, and `idr-lower` is our C++ lowering pass.
- Everything after it is upstream MLIR and LLVM.
- Every helper a lowering calls is a function of the runtime (`LOW-RT-1`).

*Revised at the cutover:* lowering starts from regions, not blocks: matches
become switches here, loops are made here, and closures, boxes, bigs and
strings have layouts. In the heap-free profile, those values exist at
runtime only as constants, in static data (`LOW-CONST-1`), and in JIT mode
also in the arena (`LOW-JIT-1`); allocating ops that survive are rejected
before lowering (`PROF-HEAP-*`).

## Loops

- **LOW-TAIL-1 (v0 only; withdrawn in v3).** self tail calls are recognised in
  first-order Core (`CORE-LOOP-1`), not in MLIR. *Since the cutover*, they
  are recognised in MLIR again (`LOW-TAIL-5`).
- **LOW-TAIL-2 (v0 only; withdrawn in v3).** `idr-tail-loops` was gone; the loop
  existed before MLIR saw the program (`CORE-LOOP-1`). *Since the cutover*,
  `idr-tail-loops` is back, under `LOW-TAIL-5`.
- **LOW-TAIL-3 (v0).** Mutual and non-self tail calls get no guarantee. LLVM
  may still optimize them, and does when inlining makes them self calls.
- **LOW-TAIL-4 (v0).** A loop in a function that is not total (no
  `idr.total`) carries `idr.may_loop` once per iteration, whose effects
  keep the loop even when its results are unused, and keep output on its
  side of it (`IDR-EFF-1`). It lowers to an effect that LLVM keeps too.
  The LLVM functions this pipeline makes never assert forward progress (no
  `mustprogress`), so LLVM keeps a loop that may not terminate
  (`SEM-EVAL-5`). *Revised at the cutover:* loops are `scf.while` from
  `idr-tail-loops` again; from v3 to the cutover they were cycles of blocks,
  which no MLIR pass deletes, and `idr.may_loop` was gone.
  - Test: `tests/idr/effects/loop.mlir`, `tests/idr/pipeline/emit-llvm.mlir`
- **LOW-TAIL-5 (v3). `idr-tail-loops`.** After the simplify loop and
  `idr-defunctionalize`, a function that calls itself in tail position,
  with the call's results returned unchanged (directly, or as the result
  of the match that the call ends a region of), becomes an `scf.while`
  whose iteration is the body and whose each such call starts the next
  iteration. Such a function runs in constant stack (`SEM-RES-2`). This is
  the only place loops are made.
  - Check: the pass `idr-tail-loops`
  - Test: `tests/e2e/v0/tail-loop-deep` (10^8 iterations with the stack
    limited to 1 MiB), `tests/profile/v0/accept/PROF-FN-6-tail-loop.idr`

## Type conversion (`idr-lower`)

`idr-lower` is a dialect conversion with one `TypeConverter`:
- builtin integer types and `f64` map to themselves;
- `!idr.erased` and `!idr.world` map to no values (1:0);
- `!idr.data<@T>` maps to `layout(T)` (1:N, `LOW-DATA-1`);
- `!idr.box<@T>`, `!idr.fn<...>` and `!idr.str` map to one pointer, and
  `!idr.big` to one `i64` (`LOW-BOX-1`, `LOW-CLOS-1`, `LOW-STR-2`,
  `LOW-BIG-1`).

It applies upstream's structural conversions of `func.func` signatures,
`func.call`, `func.return`, and the `scf` ops that it and `idr-tail-loops`
make. It uses `allowPatternRollback = false` where every pattern permits it.

- **LOW-SWITCH-1.** *Withdrawn at the cutover:* `cf.switch` over idr values
  was converted 1:N by a pattern of our own, because upstream's converts
  one value to one value. The contract has no `cf` any more; a match lowers
  to `scf.index_switch` on its tag (`LOW-MATCH-1`), and
  `convert-scf-to-cf` builds the blocks after types are converted.
- **LOW-BLOCK-1.** *Withdrawn at the cutover:* a function's blocks after
  the entry were converted with the branches to them. Functions from `Emit`
  have one block.

### Matches

- **LOW-MATCH-1 (v3).** `idr.match` lowers to `idr.tag` of its scrutinee and
  an `scf.index_switch` on it, with one case per region; each region's
  arguments become `idr.field` reads of the scrutinee. A match without a
  default, whose regions do not name every constructor, takes the last
  region as the switch's default: Idris proved the missing constructors
  cannot occur (`IDR-MATCH-2`), so no default block is ever unreachable.
  `idr.match_lit` on an integer lowers to `scf.index_switch` on its value;
  on a string or a big, to a chain of `scf.if` on runtime comparisons, each
  made only where the one before failed (`LOW-RT-1`). A region that ends
  in a crash yields values of its results that are never used, since the
  crash does not return. `convert-scf-to-cf` then builds the control flow.
  - Check: `idr-lower`

### Data layout

- **LOW-DATA-1 (v0).** `layout(T)` for an unboxed `idr.data @T` with
  constructors `C_0 … C_{n-1}` is computed as follows:
  1. **Components of a field.** An integer or `f64` field is one component.
     A `!idr.str`, `!idr.box`, `!idr.fn` or `!idr.big` field is one
     (*revised at the cutover*: a string was two, pointer and length). An
     `!idr.erased` or `!idr.world` field has none. An `!idr.data<@U>` field
     contributes the components of `layout(U)`, recursively (flattening).
     Recursion is finite by `IDR-DATA-4`.
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
  disappear through the 1:0 conversion; so do the `idr.constant`s of
  `#idr.erased`.
- **LOW-SEL-1 (v2).** Upstream `canonicalize` turns a branch that only
  chooses between two values into `arith.select`, also for idr types. An
  `arith.select` of an idr type lowers to one `arith.select` per component.
  *Since the cutover* it may be dead code: an `scf.if` becomes `select`
  only after types are converted.
  - Test: `tests/idr/lower/select.mlir`
- **LOW-DATA-3 (v0).** `idr-lower` erases all `idr.data` ops. After it, no
  `idr` op or type remains.
  - Check: conversion legality (the `idr` dialect is illegal)

### Boxes, closures, bigs and strings

A heap object (a box, a closure, a large big, a string) starts with a
header holding a reference count and a word that depends on the object
([the plan](../plan.md), sections 3 and 4.3). A count of 0 marks static
data, which is never freed (`LOW-CONST-1`). These layouts are shared by
`idr-lower`, the runtime and `idr-eval`'s child, which reads results back
through the same code.

- **LOW-BOX-1 (v3).** A value of `!idr.box<@T>` is a pointer to a cell: the
  header, whose second word is the constructor's tag, then the
  constructor's fields. `idr.con` of a box allocates the cell through the
  runtime (`idris_rt_cell`), `idr.tag` reads the header, and `idr.field`
  reads a field. In the heap-free profile only constants and JIT mode's
  arena hold cells.
  - *planned* (the cutover's lowering): the fields' offsets, written here
    from the implementation when it lands.
  - Check: `idr-lower`
- **LOW-CLOS-1 (v3).** A value of `!idr.fn<...>` that remains after
  `idr-defunctionalize` (in JIT mode, or as a constant) is a pointer to a
  cell: the header, whose second word is the closure's label (a number
  `idr-lower` gives each function that closures name), then the code
  pointer, then the captures. `idr.apply` calls the code pointer with the
  cell's captures and its arguments.
  - *planned* (the cutover's lowering): the numbering of labels and the
    captures' offsets, written here from the implementation when it lands.
  - Check: `idr-lower`
- **LOW-BIG-1 (v3).** A value of `!idr.big` is one 64-bit word: an integer
  small enough is held in the word itself, tagged, and any other is a
  pointer to a counted GMP integer (Lean's scalar `Nat`, GHC's `IS`/`IP`).
  An integer is small exactly when it fits, so each integer has one
  representation. The `idr.big.*` ops call the runtime (`LOW-RT-1`), which
  has a fast path for small integers and uses GMP otherwise.
  - *planned* (the cutover's lowering): the tagging, written here from the
    implementation when it lands.
  - Check: `idr-lower`, the runtime
- **LOW-STR-2 (v3).** A value of `!idr.str` is a pointer to a string: the
  header, whose second word says whether every byte is ASCII, the length
  in bytes, the number of scalar values, then the UTF-8 bytes. The
  `idr.str.*` ops call the runtime, over simdutf; the ops that may crash
  check their condition first and crash through `LOW-CRASH-1`.
  `idr.str.length` is the stored count, and indexing an ASCII string is
  O(1).
  - *planned* (the cutover's lowering): the exact field widths, written
    here from the implementation when it lands.
  - Check: `idr-lower`, the runtime
- **LOW-STR-1.** *Withdrawn at the cutover:* each distinct string literal
  became a private constant global of its bytes. Every constant is static
  data now, strings included (`LOW-CONST-1`).

### Constants

- **LOW-CONST-1 (v3).** Every `idr.constant` that remains (a sum, a box, a
  closure, a string, a big) is static data: a private constant global in
  the layout its type has, with a reference count of 0, so no code ever
  frees or writes it. A constant of an unboxed sum becomes its components
  as constants; the others are the global's address. Equal constants share
  one global. So no constant costs an allocation or any code at runtime.
  - Check: `idr-lower`

### Characters

- **LOW-CHAR-1 (v1).** `idr.to_char` lowers to a range check and a `select`,
  giving the value if it is a scalar value and `0` otherwise
  (`SEM-CHAR-3`).

### IO (v1)

- **LOW-IO-1 (v1).** Standard output goes through one fixed-size buffer in
  static storage (`.bss`), never the heap. The buffer is flushed with a loop
  over `write(1, …)` that handles partial writes. A failed write abandons
  the rest of that output (`SEM-IO-6`). `EINTR` needs no handling: the
  program installs no signal handlers, so `write` is never interrupted
  with it. The buffer is flushed:
  - when it fills;
  - before every read from standard input;
  - before `exit`;
  - before a crash's message;
  - when `main` returns.

  This gives `SEM-IO-4`.
- **LOW-IO-2 (v1).** The IO ops lower to calls of the runtime (`LOW-RT-1`):

  | Op | The runtime |
  | --- | --- |
  | `put_str` | appends the string's bytes to the buffer, or writes them through if they exceed it |
  | `put_char` | appends the UTF-8 encoding of the character |
  | `put_int` | writes the decimal digits through a stack buffer, then appends them |
  | `get_char` | flushes, then decodes one UTF-8 scalar from `read(0, …)` through a fixed-size static input buffer (`SEM-IO-3`: `'\0'` at end of input, U+FFFD for malformed input) |
  | `exit` | flushes, then `_exit(code)` |

  *Revised at the cutover:* the helpers are C functions of the runtime,
  not private functions that `idr-lower` generated into the module, and
  "there is no runtime library" no longer holds.
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
  the operand is a finite constant, then a call of the runtime's
  truncation, then `arith.trunci` to the result width. The runtime takes
  the value apart into sign, exponent and mantissa and shifts, so the
  64-bit result is the truncated value modulo 2^64 for every finite double
  (`arith.fptosi` is poison out of range). Wrapping to a narrower width is
  truncation (`SEM-DBL-4`). *Revised at the cutover:* the helper is C.
  - Test: `tests/idr/lower/double.mlir`, `tests/e2e/v2/double-*`
- **LOW-DBL-2 (v2).** `idr.io.put_double` calls the runtime, which writes
  the text of `SEM-DBL-5` through a stack buffer. *Revised at the cutover:*
  the digits come from Ryu (Adams, PLDI 2018), vendored as the pinned
  submodule `third_party/ryu`, with its own tables, and a wrapper that
  checks with exact digits whether the shortest candidate is a tie and, if
  so, takes the larger, as the reference does. Before, a port of Ryu to
  MLIR text used tables that `tools/GenRyuTables.idr` computed.
  - Test: `tests/e2e/v2/double-print-fuzz` (45,000 values against Chez,
    including decimal ties)
- **LOW-DBL-3 (v2).** The `arith` float ops and the `math` ops pass through
  `idr-lower` unchanged, and `convert-to-llvm` turns them into LLVM
  instructions and intrinsics. LLVM's back end turns the intrinsics that
  have no instruction on the target into calls of the `libm` functions of
  the same name (`SEM-DBL-3`, `SEM-DEV-2`). Nothing sets fast-math flags, and
  LLVM does not contract `a * b + c` into a fused multiply-add without them.
  - Test: `tests/e2e/v2/double-basics`
- **LOW-DBL-4 (v3).** `idr.double_head` calls the runtime, which decides the
  sign and the special values as `put_double` does and otherwise returns
  the leading digit of the Ryu digits: the same text's first character,
  without writing it. *Revised at the cutover:* `idr.int_head` joins it,
  with the first character of an integer's decimal text.
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

- **LOW-CRASH-1 (v0).** A crash lowers to a call of the runtime's crash
  function with a message, which:
  1. flushes the output buffer (`LOW-IO-1`);
  2. writes the message to file descriptor 2;
  3. calls `_exit(1)`. The function is declared `noreturn`, so LLVM treats
     the code after the call as unreachable.

  The message is static data. It names the cause and the Idris source
  location of the operation. *Revised at the cutover:* the crash function
  is C, and in JIT mode it reports the crash to `idr-eval`'s parent
  instead of exiting (`LOW-JIT-1`).
- **LOW-CRASH-2 (v3).** `idr.crash` lowers to the crash function with its
  message and location, like `LOW-CRASH-1`. *Revised at the cutover:* it has
  no results; the `ub.unreachable` after it stays, and a match region it
  ends yields values that are never used (`LOW-MATCH-1`).
  - Test: `tests/idr/lower/crash-op.mlir`
- **LOW-EXT-1 (v0).** The only external symbols the object file may
  reference are `write` and `_exit`, from v1 also `read`, and from v2 the
  `libm` functions `exp`, `log`, `pow`, `sin`, `cos`, `tan`, `asin`,
  `acos`, `atan`, `sqrt`, `floor`, `ceil`, and `exp2` and `ldexp`, which
  LLVM substitutes for some calls of `pow` (`SEM-DEV-2`). None of them
  allocates. The executable is linked statically against musl, whose
  `libc.a` holds these `libm` functions too, and musl's `rcrt1.o` provides
  the process entry (`TC-LINK-2`). *Revised at the cutover:* the runtime's
  code joins the object where the program reaches it (`TC-LINK-1`), and
  what joins still calls only these symbols.
  - Test: every e2e fixture checks the object's undefined symbols
    (`TEST-HEAP-1`)

### Entry point

- **LOW-ENTRY-1 (v0).** `idr-lower` generates a public
  `func.func @main() -> i32` and makes the root private:
  - **a root of type `() -> i64`** (`main : Int`): `main` calls it,
    truncates the result to `i32` (`arith.trunci`), and returns it. The
    process exit status is therefore the low 8 bits of the result
    (`SEM-PROG-1`).
  - **a root that takes a world** (v1): `main` calls it, whose world
    argument has disappeared, discards the result, flushes output, and
    returns 0 (`SEM-PROG-2`).

  *Revised at the cutover:* the root is the module's only public function,
  and its type is its kind (`IDR-FN-1`); `idr.entry`, `idr.entry_kind` and
  the pass `idr-entry` are gone.
  - Test: `tests/idr/e2e/shapes.mlir`, `tests/idr/lower/io.mlir`

## The runtime and JIT mode

- **LOW-RT-1 (v3).** Every helper that a lowering calls is a function of
  the runtime's C interface (`runtime/idris_rt.h`, `TC-RT-1`), named after
  its op (`idr.str.append` calls `idris_rt_str_append`): the ops that call
  the runtime say so in the dialect (`Idr_CallsRuntime`, `IdrOps.td`).
  Executables join the runtime's bitcode by LTO (`TC-LINK-1`), and
  `idris-mlir-cc` links the same code natively, so the folders of the
  string, big and `Double`-printing ops and the code `idr-eval` runs call
  the same functions as the executable: one implementation of each
  primitive. `idr-lower` generates no helper of its own.
  - Check: `idr-lower`; the runtime's link check (`TC-RT-2`)
- **LOW-JIT-1 (v3).** `idr-lower` has a JIT mode, which `idr-eval` uses
  (`ELIM-EVAL-1`). It differs from the executable's lowering in two things
  only:
  - allocation (a box, a closure, a string or a big made at compile time)
    takes memory from an arena that is dropped after the evaluation, since
    memory management is not observable (`SEM-EVAL-7`);
  - a crash reports its message to `idr-eval`'s parent and ends the child,
    instead of writing it and exiting (`LOW-CRASH-1`).

  The JIT compiles for the host CPU, which no result depends on
  (`LOW-TARGET-1`).
  - Check: `idr-lower`, the runtime

## Upstream lowering and code generation

- **LOW-UP-1 (v0).** After `idr-lower`, the module contains only `func`,
  `arith`, `math`, `scf`, `cf`, `ub` and `llvm` ops. Upstream
  `convert-scf-to-cf`, `convert-to-llvm` and `reconcile-unrealized-casts`
  take it to the LLVM dialect. No other lowering pass is ours.
- **LOW-TARGET-1 (v0).** The LLVM module is compiled in process for
  `x86_64-unknown-linux-musl` ([the plan](../plan.md), section 5.7):
  - the CPU `x86-64-v3` (AVX2, BMI2, FMA; every x86-64 CPU since Haswell and
    Zen) unless `idris-mlir-cc --cpu` names another: `native` (the machine
    that compiles), `x86-64` (the baseline), or any x86-64 CPU LLVM knows;
    a name it does not know is a usage error. Objects are reproducible for a
    given `--cpu` other than `native`;
  - position-independent code, for a static-PIE executable (`TC-LINK-2`);
  - optimization level O3, with no fast-math flags and no FP contraction:
    `+` and `*` stay separate IEEE operations, never fused;
  - one section per function and per datum, so the link keeps only what is
    reached.

  JIT mode (`LOW-JIT-1`) compiles for the host CPU instead; no result
  depends on the CPU.
- **LOW-ATTR-1 (v0).** No LLVM function attribute or metadata that asserts
  termination or forward progress is added (`SEM-EVAL-5`).
- **LOW-CC-1 (v0).** All functions use the C calling convention. Internal
  functions are private, so LLVM may change their calling convention itself.
