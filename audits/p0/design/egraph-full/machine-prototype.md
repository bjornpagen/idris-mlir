<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: what QTT facts buy in generated code, from a staged Idris prototype

Status: D107 (the owner, 2026-10-21) reversed D86's route, so P0 has no
Idris engine printed as MLIR. The optimizer's e-graph is built from MLIR's
mechanisms in C++. This file was written when the prototype stopped. It
records what was measured before the reversal, as evidence about what the
facts Idris's types carry (an index below a capacity, a buffer with one
owner, an update in place) buy, or fail to buy, once printed as MLIR.
That still bears on `libs/mlir-array`, `libs/mlir-linear` and the
frontend. It reverses nothing.

Grounds: *measured* (a command I ran, named with its build and input),
*read* (path:line), *recalled*, *conjecture*. Tools: the stock Idris
`0.8.0-1c630e67c` on the pinned Chez under `.toolchain/`; Apple clang
21.0.0; Homebrew's LLVM 22.1.8. That LLVM is not the pin (7208ba24), and
every result from it is labelled 22.1.8. It sits at
`/opt/homebrew/opt/llvm@22/bin`; the path `/opt/homebrew/opt/llvm/bin`
does not exist on this machine. Machine: Apple M2 Max (virtual), 8 cores,
32 GB, load average 10-12 during the session. All code is outside the
repository, in `/tmp/eg-machine-proto/` (§5). Nothing in the repository
was built or run.

## 0. In plain words

- **No speed was measured.** The comparison with speed.md's dense engine,
  the phase times, the memory figures, the check that both engines build
  the same graph, the Chez timing and the nanoseconds each fact buys were
  all still ahead when D107 stopped the work. No figure here compares the
  printed code with C++.
- **What is measured.** A staged Idris library with linear buffers and
  bounded indices type-checks on the stock host. It prints MLIR that
  upstream's 22.1.8 tools lower and that runs correctly (`find` with path
  halving, §2.2). Three findings carry beyond the e-graph:
  1. The aliasing fact does not reach LLVM through a `func.func` memref
     argument. Upstream's FuncToLLVM drops it (read at the pin; the 22.1.8
     IR shows it). Carrying it needs an upstream patch (§2.4).
  2. A staged branch with linear state must leave its state's type
     unchanged. A printer prints both branches by threading the one state
     through them in turn, and cannot copy a linear value (§2.5).
  3. On the stock host, QTT-heavy Idris pays in elaboration time.
     One 60-line function with nested linear-pair patterns in lambdas took
     about 184 s to check. Flattened into top-level functions over one
     linear record, the whole module checks in 3.5 s. A later addition
     with nested constructor patterns in lambdas did not finish in 600 s
     (§3).
- **The bug table D97 asked for is designed, not demonstrated.** The
  kernel's types are written to refuse five classic e-graph bugs (§4), but
  no misuse was compiled against them, so no error is quoted.

## 1. What was built

- **The interface** (`idris/EG/Kernel.idr`, 995 lines):
  - A tagless-final `Machine v b m`, written once, with two intended
    interpretations. The printer was written; the running interpretation
    was not.
  - Scalar types carry erased facts: `Ix n` (below capacity `n`), `Cnt n`
    (at most `n`), `Cls g n` (a class id of graph `g`), `Can g e n`
    (canonical in epoch `e`), and `Opt t`, a staged option.
  - Buffers are linear handles `b n el`, and every load and store takes an
    `Ix n` for the buffer's own `n`.
  - A linear monad (`bind1 : (1 _ : m a) -> (1 _ : (1 _ : a) -> m c) -> m
    c`) threads buffers. Results pair a linear resource with unrestricted
    values (`Got`, constructor `:&`).
  - Control flow is structured: `forUp`, `whileDo`, `cond`, `caseOpt`,
    `switch`, and `compact` (rewrite a table, keeping some rows).
  - Kernel-only retags take an erased witness, `Trusted`, whose
    constructor is private (`:79`).
- **The kernel** (same module, because Idris 2 has no friend modules,
  §3):
  - the union-find `findP` with path halving (`:221`), and union by
    least id;
  - the hash-cons, open addressing with eg.cpp's hash and growth rule;
  - lookup-or-insert `node` (`:642`), which returns `Opt (Can g e n)`:
    none when a table is full, so no client ever holds an id that was
    not made;
  - `unite` (`:619`), which returns the graph in a fresh epoch;
  - eg.cpp's full-scan rebuild, through `compact`;
  - counting-sort indexes.
  - The graph is `EG b g n r h k e p`, its brand, capacities, epoch and
    phase all erased (`:293`).
  - The rebuild and index section was written but never finished
    checking (§3). The matcher, the rules and the entries were not
    written.
- **The printer** (`idris/EG/Print.idr`, 496 lines): upstream dialects
  only (func, arith, scf, memref, cf). It has three switches, one per fact
  to be measured:
  - `bounded`: print no bounds check for an `Ix`-typed access (`:146`);
  - `linear`: print `{llvm.noalias}` on a linear buffer argument
    (`:476`);
  - `inPlace`: print `compact` in place, or into a fresh `memref.alloc`
    copied back (`:368`).
  - It also prints `overflow<nuw>` where an index type proves no wrap.

## 2. Findings

### 2.1 Linear handles on the stock checker

- *measured* (`idris2 --check idris/probe/LinTest.idr`): a constructor
  field declared unrestricted stays unrestricted after a linear match, so
  `dupB : (1 _ : Box) -> LPair Box Box; dupB (MkBox s) = MkBox s # MkBox
  s` type-checks.
- So a handle can carry a name or a pointer and still be threaded
  linearly, as long as its constructor is private. Privacy is what stops
  a client from duplicating one, not the multiplicity. This holds for any
  library of linear buffers on the stock host (*conjecture*, from the
  probe).

### 2.2 Printed code runs

- *measured* (22.1.8): `T/T1.idr` printed `findP` as an entry
  (`out/t1.mlir`). `scripts/lower.sh` lowered it with `mlir-opt`
  (scf-to-cf, arith, index, memref and func to llvm), then
  `mlir-translate`, then `clang -O2`. A C caller ran it on the chain
  5→4→3→2→1→0 and printed `find(5)=0 parents: 0 0 1 1 3 3`, which is path
  halving's result.
- With `bounded` on, the loads lower to `getelementptr inbounds nuw` with
  no compare (`out/t1.ll`). The cost of the checks the switch would add
  was not measured.

### 2.3 Copies a linear table avoids

- *read*: eg.cpp allocates a fresh row vector on every rebuild pass
  (`/tmp/eg-machine-proto/ref/eg.cpp:140-141`) and a `pos` copy of each
  index's offsets on every index build (`:84`).
- The prototype's `compact` and counting sort need neither: the write
  cursor stays at or below the read cursor, and the offsets are a
  caller-owned buffer. Unmeasured.

### 2.4 The aliasing fact stops at FuncToLLVM

- *measured* (22.1.8, `out/t1.ll`): the printed `%p: memref<?xi32>
  {llvm.noalias}` became `define i32 @_mlir_ciface_t_find(ptr noalias
  %0, ...)`. There `noalias` sits on the pointer to the descriptor. The
  function that does the work is `define i32 @t_find(ptr %0, ptr %1, i64
  %2, ...)`, with no `noalias` on the data pointer `%1`. The IR carries no
  `!tbaa` either (0 matches).
- *read* (pin 7208ba24,
  `mlir/lib/Conversion/FuncToLLVM/FuncToLLVM.cpp:406-418`): an argument
  that expands to several LLVM arguments, as a memref's descriptor does,
  gets empty attribute dictionaries ("TODO: Implement custom handling for
  types that expand to multiple function arguments"). The C wrapper copies
  the original attributes onto its own pointer arguments (`:83-99`).
- So no printer of `func.func` with memref arguments can give LLVM the
  "one owner" fact at the pin. Hand-written C++ gets some of it from TBAA,
  which the memref lowering does not emit (*recalled*: struct-path TBAA
  distinguishes `uint64_t` keys from `uint32_t` values).
- **Upstream patch** (*conjecture*, unwritten): in
  `propagateFunctionArgResAttrs`, map `llvm.noalias` on a memref argument
  to the aligned-pointer argument of its expansion. Test it in
  `mlir/test/Conversion/FuncToLLVM/`. That is the form AGENTS.md asks for,
  as `upstream/<bug>/mlir.patch`. This matters to anything of ours that
  lowers linear buffers through FuncToLLVM. Whether idris-mlir's own
  lowering does was not read.

### 2.5 A staged branch keeps its state's type

- *read* (my code, `idris/EG/Print.idr`, `cond` and `caseOpt`): the
  printer prints both branches, but it holds one linear state. It runs the
  first branch with it, then the second with the first branch's output.
  That is valid because, in the printer, a buffer is a name that no branch
  changes. Consequences:
  1. A branch's output state must have its input's type.
  2. The linear state may hold only buffers. A staged scalar in it would
     leak an SSA value from one region into the other. Only `mlir-opt`'s
     verifier would catch that, not the types.
- So a rule could not be written as "make a node; if the table is full,
  stop; otherwise union". The union moves the graph to a fresh epoch
  inside a branch. The fix was a representation: `node` returns a staged
  `Opt`, the rule chains its nodes with `bindOpt` inside one epoch, and
  `unite` takes the option after the join (`Kernel.idr:619-660`).
- Any staged Idris library over linear state meets the same constraint
  (*conjecture*).

## 3. Limits of the stock host

All *measured* with `idris2 0.8.0-1c630e67c --check`:

- **Elaboration time.**
  - `nodeNS`, written with four-level nested linear-pair patterns inside
    lambdas, made the module take 186.84 s user. Without it the rest took
    2.83 s.
  - Rewritten as small top-level functions over one linear record (`NS`),
    the module took 3.46 s.
  - The rebuild and index section, which still had nested constructor
    patterns inside lambdas (`recanonLeaves`, `Kernel.idr:873`), did not
    finish within `timeout 600`.
  - Part of the cost was ambiguity: `#` names the builtin `LPair`'s
    constructor and `Res`'s, so the result type got its own `:&` and
    `%hide Builtin.DPair.(#)`.
  - Linear code on this host has to be written flat: one record per state
    and top-level helpers. mlir-array and mlir-linear would pay the same
    (*conjecture*).
- **Higher-order buffer families need annotations.** `Can't solve
  constraint between: ?b 1 (Sc (Cnt ?k)) and b 1 (Sc (Cnt k))` appeared
  at every record constructor built in an argument position, and was
  fixed with `the (UF b g n) (MkUF ...)`.
- **A method must mention the determining parameter.** With `| m`,
  `canonT : ... -> v (Cls g n) -> v (Can g e n)` failed: `Can't find an
  implementation for Machine ?v ?b ?m`. Pure retags had to become
  monadic.
- **No friend modules.** A witness only the kernel may build must share a
  module with the interface whose methods take it, so the interface and
  the kernel are one module.
- **Small ones.** A doc comment cannot precede a fixity declaration
  (`Couldn't parse declaration`). An unrestricted bind cannot capture a
  linear name (`Trying to use linear name st in non-linear context`), so
  the printer's own text runs in an ordinary state monad joined by one
  linear `liftK`.
- None of this was checked under idris-mlir, which is not built here.

## 4. The bug table (D97): designed, not demonstrated

No misuse was compiled, so no error is quoted. These are the types meant
to refuse each bug, and the bug classes they cannot reach.

| bug | what refuses it | status |
| --- | --- | --- |
| a stale id after a union | `unite` returns `Fresh` (a fresh epoch); equality is only on `Can g e n` of one epoch | designed |
| a hash-cons out of step with the union-find | keys are built only from `Can`; `Clean` is reached only through `rebuild` | designed |
| matching on an unrebuilt graph | matching takes `EG ... Clean` (the matcher was not written) | designed |
| an id of one graph used in another | the erased brand `g` in `Cls g n` | designed |
| an access past capacity | every load and store takes `Ix n` for its buffer's `n`; no `Ix` from a raw word without a check | designed; the printed `find` has no check (§2.2) |

What the types cannot reach (*read*, the kernel's `Trusted` uses):

- the kernel's own algorithm: a find loop's exit is canonical, a
  compaction cursor stays at or below its read cursor, a counting sort's
  cursor stays inside its bucket, a hash table stays at most half full so
  probing ends;
- the phase and epoch the kernel assigns, which are claims, not proofs;
- the C++ caller's buffer sizes, checked at most once at entry;
- a scalar smuggled into linear state (§2.5).

## 5. Scaffolding, outside the repository

- `/tmp/eg-machine-proto/idris/EG/{Kernel,Print}.idr`: the library and
  the printer. `idris/T/T1.idr`: the `find` entry.
  `idris/probe/LinTest.idr`: the linearity probe.
- `/tmp/eg-machine-proto/scripts/lower.sh`: the 22.1.8 lowering.
- `/tmp/eg-machine-proto/out/{t1.mlir,t1.ll,t1main.c}`: the printed
  module, its LLVM IR and the C caller.
- `/tmp/eg-machine-proto/ref/eg.cpp`: speed.md's dense engine, sha256
  9a2e8744…, the same file speed.md measured; not run here.
