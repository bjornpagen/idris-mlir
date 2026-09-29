# Limits audit: every implicit width, count and budget, and which ones fail silently

Stream: limits-audit. Experiments are in
`scratchpad/research/limits-audit/` (compiled with the built compiler through
`tools/compile.sh`, and with `idris-mlir-opt`/`idris-mlir-cc` on generated
MLIR). Already known, and not re-derived here: the cell header packs the tag in
16 bits and `objs` in 8, unchecked (`Lower/Layout.h:21`, `Layout.cc:159`;
mlir-idioms.md §1.2 reproduced 256 counted fields), and closure tags are
module-wide label ids (`Layout.cc:36-53`).

## The questions

For each implicit limit in the compiler, the runtime and the tools:

1. Where is it (file:line), and what happens past it?
2. Which Idris program reaches it? Does it fail loudly (a named error, a
   remark, a clean crash) or silently (corruption, a miscompile, lost output,
   an unbounded compile)?
3. What representation makes the out-of-range state impossible to express?

## The global maximum first

The root cause is the same for most of the silent cases. The compiler
computes facts about the program: counts, tags, sizes, label ids, addresses,
the target. It then writes them into fixed-width fields that the runtime
chose, and no type carries the width. So no verifier ever sees a value outside
its range. The information word alone is built in eight places
(`Lower/Patterns.cc:19`, `Lower/Counting.cc:67`, `Stack/Cell.cc:27-29`,
`Lower/Runtime.cc:235, 286, 335, 344`, `Lower/Closures.cc:24`), plus the
runtime's own two (`strings.cc` `stringInfo`, `big.cc` `idris_rt_info`).

The global maximum has one idea: **a limit exists once, as a type, at the
place where it is decided, and everything downstream reads that type.**

1. **Layouts are data in the IR, not recomputed C++.** Each `idr.data` (and
   each closure label set, in the JIT) carries a typed layout attribute:
   `#idr.layout<tag: u16, objs: u8, kind: ..., size: ...>`, or better
   representation.md R2(b)'s layout id into a per-program table. Its
   storage parameters have bounded C++ types, and it uses `genVerifyDecl`
   with `getChecked` (docs/DefiningDialects/AttributesAndTypes.md,
   "Verification"). An out-of-range layout then cannot be parsed or built.
   The layout pass is the one place that says `unsupported (layout): <type>
   has N counted fields; a cell holds at most 255`. Lowering, the stack pass,
   the reifier and the runtime's `idris_rt_info` all read that one attribute.
   `Layouts` stops being a second source of truth, which is what "idr-lower
   and idr-eval compute the same numbers" (`Layout.h:99-103`) only promises
   today.
2. **The code pointer is the closure's label.** In the JIT the header's label
   is read only by the reifier (`Eval/Reify.cc:98, 105`). The code address
   already names the label one-to-one (`__idr_code_<id>`), and the JIT knows
   every address. Reverse-map it, and closure cells need no label field at
   all: the 16-bit limit is gone rather than checked.
3. **The target is a module attribute.** Set `llvm.target_triple` and a
   `dlti.dl_spec` once (`LLVMDialect.td:85` names the attribute;
   `mlir/Interfaces/DataLayoutInterfaces.h`). `Layout.cc:12` `sizeOf` then
   becomes `mlir::DataLayout::getTypeSize`. The link step and the runtime
   bitcode's triple are checked against it, instead of three hardcoded
   copies of `x86_64-unknown-linux-musl`.
4. **Every budget is metered where its cost is spent, and ends in a named
   outcome.** That includes the one idr-eval does not meter today: turning a
   result into IR. Results travel as a DAG through MLIR bytecode, not as
   tree-shaped text (below).
5. **Program stack.** TRMC (destination passing on the owned stage) removes
   the common overflow. What remains runs on a reserved stack with a guard
   and a named crash. The runtime already has that mechanism twice: the eval
   child (`Eval/Child.cc:23-60`) and `idris-mlir-cc` (`idris-mlir-cc.cc:536-570`).

The per-limit sections below are the path to it.

## The answers, ranked by severity

Severity:
- **S1**: silent corruption or a miscompile.
- **S2**: silent wrong observable behaviour, but memory-safe.
- **S3**: the compile hangs or blows up with no named error.
- **S4**: loud but unnamed, or latent.
- **OK**: already a named error or safe by construction.

### S1-a. `objs` overflow has three more failure modes than the known one (measured)

The known case is 256 counted fields, where `kind` becomes closure. The
packing `tag | objs << 16 | kind << 24` (`idris_rt.h:72-77`) lets `objs >> 8`
land in `kind` and `objs >> 15` land in the stack bit. With `genobjs.py N` (a
record of N `String` fields in a list, built from input and then freed):

| N counted fields | header decodes as | observed |
| --- | --- | --- |
| 10 | box, objs 10 | `6`, live cells 0 |
| 512 | **string**, objs 0 | prints `6`, exit 0, `IDRIS_RT_LIVE=1` reports **live cells 3**: every record leaks, silently |
| 768 | **bignum**, objs 0 | **SIGSEGV** inside `__libc_free` via `__gmp_*`: `releaseOwned` calls `clearBignum` (`rc.cc:83-84`, `big.cc:274`), which frees the record's *field pointer* as a limb array |
| ≥ 32768 | the stack bit is set | the cell is never freed and never exclusive (`rc.cc:25-29`); not run |

So the same unchecked shift gives a leak, a free of live memory, or a closure
free, depending on `N / 256`. A record of 512 fields is unusual, but it is
reachable: an unboxed sum is inlined into every cell that holds it
(representation.md), so 100 fields of a 3-pointer sum reach 300.

- **Fix:** global-maximum item 1. The minimal form is mlir-idioms' checked
  `CellInfo`, plus one `unsupported (layout)` error in `Layouts::box` and
  `Layouts::closure` when `objs > 255`.

### S1-b. A closure label ≥ 65536 reifies as a different function (miscompile, in idr-eval)

- **Where.** `Lower/Closures.cc:24` and `Runtime.cc:344` pack
  `labelId(label)` into the 16-bit tag with no check. The reifier reads the
  label back as `info & 0xFFFF` (`Reify.cc:98`) and indexes the label table
  with it, unchecked (`Reify.cc:105`, `Layout.h:106`).
- **Past it.** Label 65536 + k writes k into the tag and adds 1 to `objs`.
  The evaluated call's constant then becomes `#idr.closure<@<label k>>`:
  silently the wrong function, with the wrong captures. The JIT's own calls
  are right, because `idr.apply` loads the code pointer (`Closures.cc:49`).
  Only the value read back is wrong.
- **Reaching it.** The labels are counted over the scratch module of one
  round: every `(callee, #captures)` pair reachable from the evaluated calls
  (`Eval.cc:159-201`). Idris programs do not normally reach 65536, but
  specialization clones and partial applications at several arities
  multiply them.
- **Experiment.** `labels/gen2.py 8193` makes 8193 functions of 8
  parameters, and one total `@pick` that builds a closure of each at 0–7
  captures (65544 labels) and returns the last. The expected wrong result is
  `#idr.closure<@f0, [5 x7]>` instead of `@f8192`. See the result note at
  the end: the run is dominated by S3-c.
- **Fix:** global-maximum item 2. Map the code address to the label, and the
  label field disappears. With the field kept, `Layouts` must return
  `FailureOr` past 65536 labels, and the reifier must check `tag <
  numLabels()`.

### S1-c. More than 65536 constructors in a boxed type bleed the tag into `objs`

- **Where.** A box's tag is its index (`DataOp::verify`, `Ops.cc:164-175`),
  packed unchecked (`Patterns.cc:19`, `Counting.cc:67`, `Stack/Cell.cc:27`,
  `Runtime.cc:335`). `loadTag` masks it with `0xFFFF` (`Runtime.cc:142-145`),
  while `TagOp::inferResultRanges` promises `[0, n-1]` (`Ops.cc:442-447`).
  Unboxed sums are right: they widen to i32 past 65536 (`Layout.cc:65`).
- **Past it.** Constructor 65536 + k matches as constructor k: a
  miscompile, and `objs` is off by one.
- **Reaching it.** A generated data type, or a boxed defunctionalized
  `@fn$n` with more than 65536 labels (one constructor per label,
  `Defunctionalize.cc:14-32`). Not run: the Idris frontend cannot elaborate
  a declaration that large in reasonable time (below).
- **Fix.** The constructor's position is its tag, so delete `idr.ctor`'s
  `tag` attribute (`IdrOps.td:272`). `DataOp::verify` only checks that it
  equals the index, so it carries no information and can only disagree. The
  layout attribute then carries a tag width chosen from the constructor
  count, as unboxed sums already do. A box that needs more than 16 bits
  gets `unsupported (layout)`, or R2(b)'s layout id.

### S1-d. The dying list assumes 48-bit addresses (`rc.cc:32-57`)

- **Where.** `Dying::push` stores `next` in the dead count (32 bits) and the
  tag (16 bits). The comment says "below 2^47"; the encoding holds 48 bits.
- **Past it.** Silent: a truncated pointer, then a free of wild memory. It is
  not reachable on Linux x86-64 today, where 5-level paging hands out
  addresses above 2^47 only on an mmap hint. snmalloc gives no such hint,
  and stacks are below 2^47. Lean's `lean_del_core` makes the same
  assumption.
- **Fix.** Make it a stated fact of the allocator configuration: a
  `static_assert` on snmalloc's address bits (its pagemap covers the
  platform's address width) next to `Dying`, and a check of the main
  stack's address at startup. Alternatively encode `next >> 3`, since cells
  are 8-aligned, which gives 51 bits. It costs nothing on the free path.

### S2-a. Program stack overflow is a bare SIGSEGV, and buffered output is lost (measured)

- `nontail/`: `total' (build (ord c * 100000))`, non-tail on both sides,
  gives exit 139 with no message for input `1` (4.9 M deep).
- `nontail2/`: `putStrLn "started"`, then `getChar`, then `putStrLn "read"`,
  then the deep call. Stdout holds only `started`. The `read` line was
  written into the runtime's buffer (`idris_rt.h:189-190`: flushed "before
  every read, before exit and a crash's message") and **lost**, because a
  signal is none of those. The program's observable output differs from
  what it did, and nothing says why. Chez prints both lines.
- **The representation-level answer has two parts.**
  1. **TRMC removes the overflow where the stack is not essential.** For
     `build`/`map`/`append`-shaped recursion (a constructor around the
     recursive call), use destination passing. The fresh cell is unique by
     construction, and its hole is an owned-stage `!idr.cell` (memory-theory,
     architecture.md §7, Koka's "tail recursion modulo context", Leijen and
     Lorenzen 2023, not in `sources/`). For `x + f xs` over `Int` or `Bits`,
     addition wraps and is associative and commutative, so accumulator
     introduction is sound. It is not sound for `Double`.
  2. **What remains gets a stack as large as the machine allows, and a named
     crash.** `idris_rt` should run `main` on a reserved stack with a guard,
     plus a `sigaltstack` SIGSEGV handler that checks the guard range,
     flushes output and writes `idris-mlir: stack exhausted` (status 1, as
     `idris_rt_crash`). The code exists twice already (`Eval/Child.cc:38-60`,
     `idris-mlir-cc.cc:549-570`). Move it into the runtime once, and all
     three use it.
- Not a fix: raising `ulimit -s`, or trusting the stack budgets
  (`Stack/Pass.cc:36-38`: 256 B per cell, 1 KiB per frame, 64 B per
  recursive frame). Those are decided at idr-stack time and not kept in the
  IR, so LLVM's inliner can add up to `TotalAllocaSizeRecursiveCaller = 1024`
  bytes (`llvm/Analysis/InlineCost.h:55`) to a recursive frame afterwards.
  No lifetime markers are emitted either (no `llvm.lifetime` in `lib/`), so
  stack coloring cannot overlap the slots. `memref.alloca_scope` or lifetime
  markers would carry the fact through (mlir-idioms.md table, "AutomaticAllocationScope").

### S2-b. `main : Int`'s result is its low 8 bits

- `Lower/Pass.cc:19-20`: `main = 256` exits 0, which the check flow reads
  as success. This is by design (tests read `%status`), but it is a width
  limit that aliases failure to success, and readability.md already found a
  test whose status is "a sum mod 256".
- **Fix.** A `main : Int` program prints its result, or the check flow's
  root is typed as the value it is, and only `IO`'s `exitWith` touches the
  8-bit status. `idr.io.exit` (`IdrOps.td:851`, `io.cc:196-199`) masks with
  `0xFF`, but nothing in `compiler/src` emits it. That is a dead op by the
  dialect's own standard.

### S2-c. The default CPU is x86-64-v3, and an older CPU gets SIGILL

`idris-mlir-cc.cc:98-104` defaults to x86-64-v3 (AVX2, BMI2, FMA), and the
executable has no startup check. On a pre-Haswell CPU the first AVX2
instruction is a SIGILL with no message.

- **Fix.** A named check at the program's entry: `__builtin_cpu_supports`
  over the features the module was compiled for, read from the target
  attribute (global-maximum item 3). Or default to `x86-64` and keep v3 as a
  choice.

### S3-a. idr-eval's result loses sharing: exponential compile time, no budget (measured)

- **Where.** The call runs metered, then `idris_rt_eval_unmetered()`
  (`Child.cc:108`). The reifier builds the attribute with no memo on cell
  addresses (`Reify.cc:59-115`) and prints it as text (`Eval.cc:272`). The
  parent parses the text back (`Eval.cc:283`). Text is a tree, so a DAG of n
  nodes becomes a tree of up to 2^n nodes. Several walks recurse over it
  without a memo: `verifyConstant` (`Ops.cc:264-323`), `constantSize` and
  `keyOfConstant` (`Specialize/Pattern.cc:31-60`).
- **Experiment.** `share<n>/`: `mk (S k) = let t = mk k in N t t`, with the
  result used at runtime behind an input test. It is total, so it is
  evaluated. Compile time is 3.5 s at n = 10, 8.9 s at n = 14 and 49 s at
  n = 17. It doubles per level, so n = 30 is days. The executable stays the
  same size, because static cells are keyed by the uniqued attribute
  (`Runtime.cc:328-353`). The DAG exists at both ends and is lost only in
  transport.
- **Fix, with MLIR mechanisms:**
  - The reifier memoizes on the cell address, so the child builds the DAG
    in linear time. MLIR attributes are uniqued, so the attribute is a DAG
    in memory already.
  - The transport is MLIR bytecode. Bytecode writes each attribute once,
    so sharing survives. Its reader parses deep nesting from a heap
    worklist, not the stack (`BytecodeReader.cpp:842-857`, `maxAttrTypeDepth
    = 5` at `:1082`). This needs a `BytecodeDialectInterface` for `#idr.con`,
    `#idr.closure` and `#idr.big`. Without one, the bytecode falls back to
    the textual form per attribute (BytecodeFormat.md "Assembly Format
    Fallback", l. 256), and that recurses again.
  - Walks over constants use `AttrTypeWalker`, which keeps a visited set.
  - An `OpAsmDialectInterface::getAlias` for `ConAttr` makes dumps DAG-sized
    too.
  - **Metering:** the reify step counts DAG nodes and bytes against the
    call's budget. A result that is too large is a `Missed` remark, and the
    call stays, as an over-budget call does.

### S3-b. A result's size is bounded only by the 4 GiB arena budget (measured)

- `bigstr/`: `rep 24 "x"`, where `rep (S k) s = rep k (s ++ s)`, compiled in
  17 s to a **17.8 MB** executable holding a 16 MiB string literal from a
  14-line source. The total-code budget allows 2^32 arena bytes
  (`Eval.cc:67-70`), so about 2 GiB of `.rodata` is in reach. Near that, the
  compile time, the textual IR and an eventual relocation overflow in the
  static-PIE link are the only feedback.
- Upstream Idris evaluates such calls too, but it never serializes the
  result into the program.
- **Fix.** The size of the result against the size of the call is part of
  the decision: "evaluate if the constant is not larger than K× the code it
  replaces, or than N bytes". Record the choice as a remark. Large byte
  strings belong in `DenseResourceElementsAttr` blobs (`dense_resource`),
  not in `StringAttr` text.

### S3-c. Quadratic symbol lookups (measured)

`ModuleOp::lookupSymbol` without a `SymbolTable` is a linear scan, and it
runs per op:
- `Runtime::call` (`Runtime.cc:60`), for every runtime call idr-lower
  emits;
- `Runtime::emitCode` (`Runtime.cc:387`), for every label;
- `lookupCtor`/`lookupData` through the static
  `SymbolTable::lookupNearestSymbolFrom` (`Dialect.cc:187, 199`), per node of
  every constant in `Runtime::constant`. `verifyConstant` already uses a
  `SymbolTableCollection`; it is only memo-less (S3-a);
- `llvm::is_contained(usedCode, id)` (`Runtime.cc:372`), a vector scan.

Measured:
- `deep<n>/` evaluates `build n : List Int`. n = 1000 compiles in 2 s;
  n = 20000 takes 48 s, 40 s of it in `IdrEval`. gdb samples are in
  `lookupSymbolIn` from `Runtime::constant` → `lookupCtor`, and in
  `verifyConstant`'s walk. n = 200000 did not finish in 600 s.
- `labels/l65536.mlir` (65537 one-line functions) spent more than 8 minutes
  in the JIT's idr-lower, sampled in `Runtime::call → lookupSymbol` and
  `mayLoop`.

**Fix.** `SymbolTableCollection` for the pass, declared once
(mlir-idioms.md already asks for it elsewhere). With global-maximum item 1,
a constant's layout is read from its type, not looked up per node.

### S4-a. Compiler recursion: `idris-mlir-cc` is safe, the other tools are not (measured)

- `idris-mlir-cc` runs the whole compilation on a thread with a stack of up
  to 2^44 bytes (`idris-mlir-cc.cc:536-570`), and the eval child on one of up
  to 2^46 bytes (`Child.cc:38-49`). So nesting is bounded by memory. That is
  a workaround for upstream MLIR's recursive parser, printer and walks, and
  it has no `PINS.md` entry or `upstream/` report. Only `musl-thread-stacks`
  (8 MiB) is recorded.
- `idris-mlir-opt` has no such stack. Parsing a `#idr.con` list nested 1500
  deep works; 2000 deep is SIGSEGV (dev build, 8 MiB stack; `nest/gen.py`).
  With `ulimit -s unlimited`, 7000 deep works. The gdb trace is about 10
  frames per level: `ConAttr::parse` → `parseAttribute`.
- Tests and `idris-mlir-reduce` run through `idris-mlir-opt`, so a test
  over an evaluated list of about 2000 elements crashes the tool, not the
  compiler.
- `Passes/Scc.h:30` is a recursive Tarjan. Its depth is the longest call
  chain, and it is safe only on cc's stack.
- The Idris frontend runs on Chez, whose stack grows on the heap.
- Deep source nesting is limited upstream first: upstream `idris2 --check`
  on a 500-deep `if … else if` chain did not finish in 300 s (`ifcheck/`).
- **Fix.**
  - Use `llvm::scc_iterator` over `mlir::CallGraph`'s `GraphTraits`
    (`mlir/Analysis/CallGraph.h`): it is iterative, and it deletes ours.
  - Carry the large-stack runner in `idris-mlir-opt`/`-reduce` too. Better,
    move it to one support function next to the runtime's (S2-a).
  - Record the workaround in `PINS.md` with a reduced upstream reproducer: a
    deeply nested builtin `ArrayAttr` crashes `mlir-opt`.

### S4-b. The eval stack budget is in host-CPU bytes

`Child.h:9-10` claims "the same call spends the same on every machine". That
holds for ticks and arena bytes. The stack is measured in bytes of JITed
frames (`eval.cc:39-55`), and the JIT targets `detectHost()` (`Jit.cc:81`).
Frame sizes, and so whether a call near the 256 MiB or 1 GiB stack budget is
evaluated, depend on the compiling machine, and with them the binary.

- **Fix.** JIT for a pinned CPU (the same `--cpu` as the output, or plain
  `x86-64`), or meter depth in frames at the existing function-entry tick
  (`Lower/Pass.cc:87-92`) plus a return hook.

### S4-c. The triple, musl and static-PIE are hardcoded in three places

`idris-mlir-cc.cc:119`, `Frontend/Main.idr:351` and `tools/compile.sh:158`
all say `x86_64-unknown-linux-musl`. `Layout.cc:12-17` assumes 8-byte
pointers and naturally aligned integers. The JIT uses the host
(`Jit.cc:81, 99-100`). Consistency today comes from `Layouts`, whose offsets
both the JIT and the reifier use, not from the target.

- **Fix:** global-maximum item 3. One module attribute; `Layout` asks
  `mlir::DataLayout`; the link reads the triple from the module or object,
  and the runtime archive's bitcode triple is checked against it (it is
  already read in `idris-mlir-cc.cc` `readMembers`).

### OK, or within a contract: checked, named, or safe by construction

- **The count's saturation** (`rc.cc:12, 23, 119-128`, `idris_rt.h:32-36`):
  - Every entry point treats `UINT32_MAX` as saturated and never decrements
    it. The inline `exclusive` test is `count == 1` (`Runtime.cc:147-154`),
    which a saturated count never passes.
  - Reaching 2^32 references to one cell needs 2^32 holders, over 100 GB
    even for 24-byte cells. The failure is a leak, which is safe.
  - `idris_rt_inc_n` has no caller in `foreign/` (it is only
    `idris_rt_inc`'s body). That is dead API surface.
- **The stack bit** (`idris_rt.h:48-54`, `Stack/Cell.cc:29`): sound except
  when `objs >= 2^15` overflows into it (S1-a).
- **String lengths:** 64-bit byte and scalar counts (`idris_rt.h:82-86`).
  `str.index` checks with an unsigned compare (`Patterns.cc:317-321`), and
  the folder checks too (`Fold.cc:211-213`). `substr` of a Nat ≥ 2^63 wraps
  to a negative `Int` and clamps to 0, as the Chez backend's `cast` does.
- **The ASCII bit** is one-sided: `slice` and `tail` keep the parent's flag
  (`strings.cc:80`), so an ASCII substring of a non-ASCII string has flag 0.
  It is only a fast-path hint, and nothing compares headers. But
  `idris_rt.h:79-80` says "tag 1 when every byte is ASCII"; it should say
  "only when".
- **Char:**
  - `to_char` maps non-scalars to 0 (`Patterns.cc:261-284`, `Ops.cc:849-858`).
  - A surrogate literal `'\xD800'` breaks upstream elaboration itself: the
    Chez backend reports "undefined name Main.main". Ours says
    `unsupported (definition): not a pattern-matching definition`, which is
    loud but blames the wrong thing.
  - `getChar` returns 255 at end of input (`idris_rt.h:211`). That sentinel
    is in-band, as Chez's 8-bit `char` FFI return is: a contract limit, not
    ours.
- **Small bigs:** one representation, `[-2^62, 2^62-1]` (`big.cc:25-33`).
  The only compiler-side assumption is `bigZero` = word 1 (`Patterns.cc:334-337`),
  which the unique representation makes sound. Static bignums store `size`
  in i32, as GMP does, and GMP aborts beyond it.
- **Int/Bits widths and casts:**
  - Literals are reduced with `twos` (`MLIR.idr:133-137`).
  - Casts are trunc, ext or a relabel with Chez's semantics
    (`Emit/Operations.idr:149-162`).
  - `to_int` is mod 2^64 exactly (`double.cc:158-169`).
  - Division guards MIN/-1 (`Patterns.cc:229-239`).
  - Match keys and scrutinees are both zero-extended (`Matches.cc:85-96`).
  - Shifts are rejected by name ("unsupported (primitive): shift left",
    `shift/`).
- **The eval arena and ticks** (`eval.cc:49-76`, `Eval.cc:60-70`): the
  budget is 2^25 ticks, 256 MiB and 256 MiB of stack for partial code, and
  2^31, 4 GiB and 1 GiB for total code. Every function entry ticks. Stack
  exhaustion hits the guard, and the call stays with a `Missed` remark. The
  holes are after the call (S3-a, S3-b) and in reproducibility (S4-b).
- **Counts of functions, clones and SCCs:**
  - Every counter is `unsigned` or `size_t`.
  - The clone budget is named (`Clones.cc:89`, `kClonesPerOwner = 1024`,
    `clone-limit = 4096`), and so are the simplify rounds
    (`Simplify.cc:97`).
  - The real limit is compile time: S3-c.

## What it means for idris-mlir

Here is the change set, in order of payoff. Each item replaces guards with a
representation.

1. **`#idr.layout` on `idr.data`**, built by `getChecked` with bounded
   storage types, as the only input to lowering, stack, reify and the
   runtime's packer. It fixes S1-a and S1-c and deletes `idr.ctor`'s
   redundant `tag`. The `unsupported (layout)` error is decided once, in
   the layout pass.
2. **Closures identified by code address in the JIT.** This deletes the
   label field and fixes S1-b.
3. **idr-eval transport as bytecode with a DAG-memoized reifier, and a
   metered reify.** This fixes S3-a and S3-b, and removes the parse
   recursion from the eval path.
4. **One reserved-stack runner in the runtime:** the program's `main`, the
   eval child and the tools. Guard page, flush, and `idris-mlir: stack
   exhausted`. This fixes S2-a's lost output and its unnamed crash, with
   TRMC as the representation-level removal of the common case.
5. **`SymbolTableCollection` everywhere a pass looks symbols up per op.**
   This fixes S3-c.
6. **The target as `llvm.target_triple` + `dlti.dl_spec`,** read by
   `Layout` through `mlir::DataLayout`, by the link and by the JIT (pinned
   CPU). This fixes S2-c, S4-b and S4-c.
7. Small ones:
   - a `static_assert` for the 48-bit dying-list encoding (S1-d);
   - `llvm::scc_iterator` for `Scc.h`;
   - delete the unused `idris_rt_inc_n` and `idr.io.exit`, or wire exit up;
   - fix the ASCII-flag comment.

## Open questions

- Should S1-c be `unsupported`, or should boxes switch to R2(b)'s layout id
  table, which has no per-cell width at all? The layout id also frees the
  pointer's low bits for R3.
- Is 16 MiB of evaluated string (S3-b) ever what the programmer wants? A
  size rule changes results only in size and speed, never in value, so any
  threshold is safe. Which threshold matches upstream Idris's intent
  ("evaluate closed calls")?
- For TRMC on `Int` sums (S2-a), is accumulator introduction a registry
  meaning of the `+` context, or a general "modulo associative operator"
  pass on `arith.addi`/`muli` with a size-change proof?
- Does upstream MLIR want a depth-safe textual attribute parser (a
  worklist, as the bytecode reader has)? A reduced `mlir-opt` reproducer
  over nested builtin `ArrayAttr` would say.
