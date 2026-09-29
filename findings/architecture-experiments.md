# Architecture stream: experiments

These are the runs behind `findings/architecture.md`. Everything ran in
`$S = /tmp/claude-0/-home-user-idris-mlir/<session>/scratchpad/research/architecture/`
with the built compiler (`build/dev`) and under the shared lock. Nothing in
the repository was changed.

## How

```sh
# compile an IO program; the .mlir stays in build/exec/<name>.mlir
flock -s build/.tree.lock tools/compile.sh --io [-p base] $S/<p>/Main.idr <p>
CC=build/dev/foreign/idr/idris-mlir-cc
# after O3, with the runtime linked
$CC $S/<p>/build/exec/<p>.mlir --emit=llvm -o $S/<p>/<p>.O3.ll
# before O3: the final LLVM-dialect module, translated
$CC … --emit=mlir -o <p>.llvmdialect.mlir
.toolchain/llvm-musl/bin/mlir-translate --mlir-to-llvmir <p>.llvmdialect.mlir -o <p>.pre.ll
# the module after each pipeline step
$CC … --emit=mlir -o /dev/null --dump-after=all --dump-dir=$S/<p>/dump
```

Chez comparisons used `.toolchain/idris2/bin/idris2 -o …` on the same
source. Timings are wall clock (`date +%s.%N`), one run each, on a
container. They are orders of magnitude, not benchmarks.

## Programs

The programs: `bench/ackdyn`, plus these, written for this stream.

| Dir | What it exercises |
|---|---|
| `lists/` | `upto`, `bump` (a non-tail map: `x*3+1 :: bump xs`), `total'` (a tail fold), all on `List Int` |
| `crash/` | a partial `firstOf`, `safeDiv` guarding `div`, a partial loop |
| `tree/` | BST `insert` with `if x < y then Node (insert x l) y r else …`, and `sumT` |
| `vect/` | `index (toFin4 n) v` on `Vect 4 Int`; `dot` on `Vect 3 Double` |
| `nat/` | `count (S k) acc = count k (acc + 2)` on `Nat` |
| `mutual/` | the tail-recursive `ev`/`od` on Int |
| `mutual3/` | a 4-cycle of tail-recursive functions with 13-way case bodies |

## Results

### Nat arithmetic is quadratic (`nat/`)

`count` before O3 (`nat.pre.ll`):

```llvm
%6 = call i32 @idris_rt_big_cmp(i64 %4, i64 1)      ; Z test, a runtime call
%13 = call i64 @idris_rt_big_sub(i64 %4, i64 3)      ; predecessor
%15 = call i64 @Prelude.Types.plus(i64 %5)           ; acc + 2
```

`Prelude.Types.plus` is the unary recursion, and it is not a tail call:

```llvm
define i64 @Prelude.Types.plus(i64 %0) {
  %2 = call i32 @idris_rt_big_cmp(i64 %0, i64 1)
  ...
  %6 = call i64 @idris_rt_big_sub(i64 %0, i64 3)
  %7 = call i64 @Prelude.Types.plus(i64 %6)
  ...
  %9 = call i64 @idris_rt_big_add(i64 %7, i64 3)
```

| n | idris-mlir | Chez |
|---|---|---|
| 10,000 | 1.95 s | |
| 20,000 | 7.98 s | |
| 40,000 | 39.2 s | 0.11 s |
| 80,000 | > 60 s (timeout) | |
| 10,000,000 | | 0.13 s |

Upstream maps `plus`/`mult`/`minus`/`equalNat`/`compareNat` to Integer ops
for every backend (`third_party/Idris2/src/Compiler/Opts/Constructor.idr:81-93`,
"natHack", applied to CExp). idris-mlir reads TT and does not apply it.

### Deep non-tail recursion overflows the stack (`lists/`)

| n | idris-mlir (8 MiB stack) | Chez |
|---|---|---|
| 100,000 | ok | |
| 200,000 | ok | |
| 400,000 | **SIGSEGV** | |
| 1,000,000 | SIGSEGV (ok with `ulimit -s unlimited`) | 0.24 s |
| 10,000,000 | SIGSEGV | 2.3 s |

`bump` before O3 is not a loop. It makes a recursive call, then builds the
cell (`%34 = call ptr @Main.bump(ptr %21)`, then `store ptr %34, ptr %44`).

The reuse test on every node:

```llvm
%22 = load i32, ptr %0, align 4
%23 = load i32, ptr %2, align 4
%24 = icmp eq i32 %22, 1
%25 = and i32 %23, -2147483648
%26 = icmp eq i32 %25, 0
%27 = and i1 %24, %26
```

Field loads carry `align 4` on 8-aligned cells (`%19 = load i64, ptr %18,
align 4`), and no function or parameter has an attribute. After O3:
`define internal fastcc ptr @Main.bump(ptr %0) unnamed_addr #0`, with
`attributes #0 = { nounwind }`. The runtime's inlined counting code carries
its own TBAA (`!tbaa !9816`), while the generated field loads carry none.

### The case block is not inlined, and reuse is lost (`tree/`)

After idr-simplify (`tree/dump/01-idr-simplify.mlir`, locations removed):

```mlir
func.func private @Main.insert(...) attributes {idr.effects = #idr.effects<none>, idr.total, no_inline} {
  ...
  case @Node(%arg2, %arg3, %arg4) {
    %4 = arith.cmpi slt, %arg0, %arg3 : i64
    %5 = arith.extui %4 : i1 to i64
    %6 = idr.match_lit %5 : i64 -> (!idr.box<@Main.Tree>) {
    case 0 {
      %7 = func.call @Main.case$32$block$32$841$32$in$32$insert(%arg4, %arg3, %arg2, %arg0, %1)   // %1 = False
    default {
      %7 = func.call @Main.case$32$block$32$841$32$in$32$insert(%arg4, %arg3, %arg2, %arg0, %2)   // %2 = True
func.func private @Main.case$32$block$32$841$32$in$32$insert(...) attributes {..., idr.total} {
  %0 = idr.match %arg4 : !idr.data<@Prelude.Basics.Bool> ... {
  case @True()  { %1 = func.call @Main.insert(%arg3, %arg2) ... idr.con @Main.Tree::@Node(%1, %arg1, %arg0) }
  case @False() { %1 = func.call @Main.insert(%arg3, %arg0) ... idr.con @Main.Tree::@Node(%arg2, %arg1, %1) }
```

The pinned inliner refuses to inline any callee that calls its caller back:

```cpp
// Don't allow inlining if the call graph is like A->B->A.
```

That is `.toolchain/llvm-project/mlir/lib/Transforms/Utils/Inliner.cpp:709-715`.

Lowered (`tree.pre.ll`), `insert` resets the old node and frees it, and the
case block allocates a new one:

```llvm
38:
  call void @idris_rt_free_cell(ptr %35)
  ...
  %42 = call ptr @"Main.case$32$block$32$841$32$in$32$insert"(ptr %28, i64 %26, ptr %24, i64 %0, i8 0)
```

### Mutual tail recursion stays as calls in MLIR (`mutual/`, `mutual3/`)

`06-idr-tail-loops.mlir` still shows `@Main.ev` calling `@Main.od` and back.
Both programs ran 10^8 iterations correctly: LLVM's sibling-call
optimization turns those calls into jumps, because the arguments fit in
registers. Nothing in idr guarantees it.

### Crash paths and redundant tests (`crash/`)

In `crash.pre.ll`, inside the default region of `switch i64 %4 [0 → …]`:

```llvm
%9 = icmp eq i64 %4, 0              ; n == 0, known false here
...
call void @idris_rt_crash(ptr @__idr_msg_1, i64 29)
br label %14                        ; the call is noreturn, but the lowering continues
14:
%15 = select i1 %9, i64 1, i64 %4   ; a guard so the sdiv is not UB
%16 = sdiv i64 1000000, %15
```

`declare void @idris_rt_crash(ptr, i64) #0` with `#0 = { noreturn }`, and no
`cold`. O3 cleans all of this (`crash.O3.ll`: the loop is unrolled 4x, with
bare `sdiv`s).

### Vect and Fin with a static index (`vect/`)

`index (toFin4 n) v` became `switch i64 %8, label %12 [0, 1, 2]` over the
four elements, with no bounds check, and the `Vect 3 Double` `dot` folded to
scalar arithmetic (`vect.pre.ll`). Specialization works when `n` is static.

### ack (`ackdyn/`)

After O3, `ack` is a loop with one recursive call and an `llvm.sideeffect`,
since `ack` on `Int` is not total. It is tight. MLton's 2.3x (README) is
probably frame and calling-convention cost; not investigated.

## Sources fetched to scratch (not in `sources/`)

- MLton `mlton/ssa/{simplify,contify,flatten,local-flatten,known-case,redundant-tests,shrink,deep-flatten,ref-flatten}.fun`
  at `aa2fd1ad…`, the revision of `sources/code/mlton/SNAPSHOT.md`.
- Lean 4 `src/Lean/Compiler/LCNF/{Passes,PassManager,FixedParams,Specialize,SpecInfo,ElimDeadBranches,FloatLetIn,JoinPoints,Simp,ReduceArity}.lean`
  at `master` on 2026-09-29. The commit could not be recorded: the GitHub
  API is not enabled for this session.
