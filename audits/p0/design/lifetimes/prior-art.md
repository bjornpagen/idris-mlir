<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design, lifetimes: the prior art

Written 2026-10-21 at e96bb991 for the owner's open question on D39 and
D48. D39 says a lifetime parameter "is a handle at run time"
(`proposals/0000-mlir-native.md:677`). D48 makes lifetime variables
quantity-0 binders, "passed at calls at compile time only" (`:850`). Four
lanes propose splitting them: L05 §1 D39 item 5 and I2, L20 I5, L06 OQ1
and L02 Q1, with review claim 2 adding prerequisites. Two messages from
the owner arrived while this was being written, and they shape it:

- "the only thing up for debate is a better representation for lifetimes,
  but it has to be weighed against the costs of what mlir can do";
- **D63** (2026-10-21, relayed by the coordinator): a lifetime is an SSA
  value, a token yielded by `idr.lifetime` and passed as an argument or
  operand. It is the arena handle where allocation needs one, and erased
  everywhere else.

So §2 puts first the systems whose IR carries scopes as values or tokens,
and §4 asks what each teaches about checking a scope without following
def-use chains. §6 reads the evidence against options A, B and C and
against what D63 still leaves open. Nothing was built or run, and no file
of ours was changed except this one.

Marks: *read* means a source and a location (a paper's page, or a file and
line at the commit in §1). *measured* means a command and its output; the
only ones here are line counts. *recalled* means not checked against a
source in this session. *conjecture* and *decision* (Dn) are as elsewhere.
Each system is described by its mechanism: what exists at compile time,
what exists at run time, who passes what to whom, and what it costs.

## 1. Sources

Clones and downloads went to `/tmp/lifetimes-prior-art`, outside the
repository. Each source is cited by its upstream address, so it can be
fetched again.

| short name | source | revision or edition |
| --- | --- | --- |
| MLKit | https://github.com/melsman/mlkit | `d9c7f147d782` (2026-10-21) |
| manual | *Programming with Regions in the MLKit*, `doc/mlkit.pdf` in MLKit | revised for 4.7.22, 2026-04-28; pages are the book's |
| retro | Tofte, Birkedal, Elsman, Hallenberg, "A Retrospective on Region-Based Memory Management", HOSC 17 (2004) 245-265, https://melsman.github.io/mlkit/pdf/retro.pdf | journal pages |
| TT94 | Tofte, Talpin, POPL 1994, https://melsman.github.io/mlkit/pdf/popl94.pdf | proceedings pages |
| BTV96 | Birkedal, Tofte, Vejlstrup, "From region inference to von Neumann machines via region representation inference", POPL 1996, https://melsman.github.io/mlkit/pdf/popl96.pdf | |
| HET02 | Hallenberg, Elsman, Tofte, "Combining region inference and garbage collection", PLDI 2002, https://melsman.github.io/mlkit/pdf/pldi2002.pdf | |
| Els23 | Elsman, "Garbage-Collection Safety for Region-Based Type-Polymorphic Programs", PLDI 2023, https://elsman.com/mlkit/pdf/gcsafe-pldi23.pdf | |
| EH23 | Elsman, Henriksen, "Parallelism in a Region Inference Context", PLDI 2023, https://elsman.com/mlkit/pdf/parreg-pldi23.pdf | |
| Cyc02 | Grossman et al., "Region-based memory management in Cyclone", PLDI 2002, https://homes.cs.washington.edu/~djg/papers/cyclone_regions.pdf | |
| Cyc06 | Swamy, Hicks, Morrisett, Grossman, Jim, "Safe manual memory management in Cyclone", SCP 62 (2006), https://homes.cs.washington.edu/~djg/papers/cyclone_scp.pdf | |
| Cyclone src | https://github.com/FauxFaux/cyclone (git-svn mirror) | `a2d38846` (2009-05-15) |
| FMA06 | Fluet, Morrisett, Ahmed, "Linear Regions Are All You Need", ESOP 2006, https://www.cs.rit.edu/~mtf/research/substruct-regions/ESOP06/esop06.pdf | |
| Swift | `sources/docs/swift`, `sources/code/swift` | `swift-6.4.0-RELEASE` (`b8189d76`) |
| LLVM, MLIR | `.toolchain/llvm-project` | `7208ba24` (2026-10-08) |
| tok-RFC | "[RFC] Add a Builtin Token Type to MLIR", https://discourse.llvm.org/t/rfc-add-a-builtin-token-type-to-mlir/90706, and llvm/llvm-project PR #195640 | named by a web search; not opened (the landed text is read in the pinned tree) |
| IREE | https://github.com/iree-org/iree, `compiler/src/iree/compiler/Dialect/Stream/IR/StreamTypes.td` | `f1eb9ce7` |
| rustc guide | https://github.com/rust-lang/rustc-dev-guide | `e58d9a67` (2026-10-19) |
| bumpalo | https://github.com/fitzgen/bumpalo | `52816568` (2026-10-16) |
| typed-arena | https://github.com/thomcc/rust-typed-arena | `f1f26c39` (2023-04-04) |
| Mojo | `sources/docs/mojo` (`135c332f`); the manual page https://mojolang.org/docs/manual/values/lifetimes | the page read through a fetch summary |
| Ox24 | Lorenzen, White, Dolan, Eisenberg, Lindley, "Oxidizing OCaml with Modal Memory Management", PACMPL 8 ICFP art. 253 (2024), preprint https://antonlorenzen.de/oxidizing-ocaml-modal-memory-management.pdf | journal pages |
| OxCaml src | https://github.com/oxcaml/oxcaml | `32135cc2` (2026-10-21) |
| Verona | Arvidsson et al., "Reference Capabilities for Flexible Memory Management", OOPSLA 2023, extended https://arxiv.org/abs/2309.02983; https://github.com/microsoft/verona-rt | `5cb8e8cf` (2026-09-29) |
| Vale | Ovadia, "Zero-Cost Borrowing with Vale Regions, Part 1", https://verdagon.dev/blog/zero-cost-borrowing-regions-part-1-immutable-borrowing (2023-04-28) | read through a fetch summary |
| Pony | https://github.com/ponylang/ponyc (`9953464f`, 2026-10-21); `sources/papers/clebsch-2017-orca`, `clebsch-2015-deny-capabilities` | |
| GA01 | Gay, Aiken, "Language Support for Regions", PLDI 2001, https://theory.stanford.edu/~aiken/publications/papers/pldi01.pdf | |
| Gibbon | `sources/papers/vollmer-2019-local`, `sources/papers/koparkar-2024-mostly-serialized-gc` | |
| Lean | `src/include/lean/lean.h` of https://github.com/leanprover/lean4 | `a701b8ae` |
| CNF | `sources/papers/yang-2015-compact-normal-forms` | |

The OxCaml paper was out of reach for wave 1 (`audits/p0/wave1/5.10-rc.md:450-456`).
The preprint above is open, and it is read in full here.

## 2. IRs that carry scopes as values or tokens

### 2.1 MLKit: Tofte and Talpin's regions, compiled

**Compile time.**
- Every boxed value's type carries a region variable. Every function type
  carries an arrow effect of `put(ρ)` and `get(ρ)` atoms. A function's type
  scheme quantifies its region variables, and those variables are its
  formal region parameters (*read*: retro p. 247; manual p. 59-60).
- Recursion is polymorphic in regions: a recursive call may pass regions
  other than the function's own (*read*: retro p. 248; manual p. 65).
- Three later analyses work on the same variables:
  - *multiplicity* decides, per region, whether at most one value is ever
    written (finite) or more (infinite);
  - *physical size* sizes the finite regions;
  - *storage modes* turn each `at ρ` into `attop`, `atbot` (reset the
    region, then store) or `sat` (decide at run time) (*read*: manual p. 2,
    p. 101-104).
- *Drop regions* removes every formal region parameter whose region carries
  no `put` in the function's type. *Read*:
  `src/Compiler/Regions/DropRegions.sml:56-66`, whose comment reads "a rho
  is marked if it should NOT be dropped" and whose rule is
  `if Eff.is_put effect then visit(...)`. The manual gives the reason: "To
  avoid passing regions that are never used, the MLKit introduces only
  formal region variables for those bound region variables in the type
  scheme for which there appears at least one put effect ... This
  optimisation, which is called dropping of regions, is the key reason why
  the MLKit takes the trouble to distinguish between put and get effects"
  (p. 63-64).
- BTV96 also drops a parameter whose region holds only word-sized values:
  "This removes many region parameters in practice" (*read*: BTV96 §5).

**Run time.**
- A finite region is words in the activation record.
- An infinite region is a descriptor on the stack: the allocation pointer
  and first page of each generation, a link to the previous descriptor and
  a list of large objects. Its pages are 8 KiB, taken from a free list
  (*read*: `src/Runtime/Region.h:14-48, 83-104, 227-248`).
- A region passed to a function is one word: the descriptor's address, or
  the finite region's slot. "The least significant bit is 1 iff the region
  is infinite. The second least significant bit is 1 iff stores into the
  region should be preceded by emptying the region" (*read*:
  `Region.h:342-365`).
- Region arguments are their own class of the calling convention
  (`reg_args`, *read*: `src/Compiler/Backend/CALL_CONV.sml:10`), "passed on
  the runtime stack or in registers" (*read*: manual p. 138).

**Who passes what to whom.** The caller passes the actual region, with the
storage mode it chose at the call, for each formal parameter the callee
kept, which is each region the callee allocates into. A region the callee
only reads is never passed (*read*: the drop-regions rule above).

**Cost at run time.**
- The callee is compiled once, apart from its callers, so it tests the
  region word on every allocation into a formal region. *Read*:
  `src/Compiler/Backend/X64/CodeGenUtilX64.sml:468-525`.
  - `ATTOP_FF` (a formal region whose multiplicity in the callee is finite)
    tests the infinite bit and allocates only if it is set.
  - `SAT_FI` tests the atbot bit and resets the region if it is set.
  - `SAT_FF` tests both bits.
  - The kinds `FF`, `FI`, `LF` and `LI` are "formal and finite" through
    "letregion bound and infinite" (`CLOS_CONV_ENV.sml:36-40`).
- The manual says so itself: "Because the same region variable can be bound
  sometimes to a finite region and sometimes to an infinite region at
  runtime, resetting a region can involve a test at runtime" (p. 101). It
  also notes that when a parameter's multiplicity is infinite, "the runtime
  check on whether r has its infinity bit set is omitted" (p. 103, footnote
  3).
- An allocation into an infinite region loads the allocation pointer from
  the descriptor in memory, adds, compares with the page boundary, stores
  the pointer back, and branches out of line to a new page
  (`CodeGenUtilX64.sml:412-432`).

**Cost at compile time.** Polymorphic recursion is inferred by "iterative
region inference of the recursive function until a fixed-point type
scheme was obtained. Ad-hoc methods were used in order to ensure
termination" (*read*: retro p. 249). AnnoDomini, 58,000 lines, "took one
and a half hours to compile" with version 3 (*read*: retro p. 255).

**What went wrong.**
1. *Leaks without a fallback.* "Programs that had not been optimised for
   regions often contained space leaks that made memory usage linear in the
   running time" (*read*: retro p. 257-258). The first disappointment the
   authors list: "Unless combined with garbage collection, leaving region
   inference completely to the compiler is probably not a good idea"
   (p. 260). A tracing collector is on by default today (*read*: manual
   p. 157).
2. *Region-friendly code takes an expert.* "The process of making programs
   'region friendly' was time consuming and required intimate understanding
   of the analyses involved" (p. 252). The annotations were "vulnerable to
   program changes" (p. 260). Fixing AnnoDomini took rewriting about 10
   lines, but "it required a regions expert to locate and change the 10
   lines" (p. 255-256).
3. *Storage modes are fragile.* "The storage mode analysis is probably not
   the best way of handling tail recursion; it is complicated and
   vulnerable to program changes" (p. 260). Programmers write loops as
   "region endomorphisms" to make it work (manual p. 113-114).
4. *Infinite regions fragment.* Region waste reached 23% for programs not
   tuned for regions (p. 258), and "it is not clear that infinite regions
   are such a good idea" (p. 261).
5. *Regions break tail calls.* "A function call that looks like a tail call
   in the source program may end up as a non-tail call in the
   region-annotated program, because the function has to return to free
   memory" (manual p. 138). The option `-preserve_tail_calls` "ensures that
   no region binding is wrapped around a tail-call. This option is enabled
   by default when garbage collection is enabled" (p. 112, footnote 7).
6. *Dangling pointers.* Tofte and Talpin's system allows a pointer into a
   freed region if it is never dereferenced, and any manager that walks
   memory trips on such a pointer. The fix published in 2003 was itself
   unsound for polymorphic higher-order code, and the problem "has
   materialised as a practical soundness problem in a real implementation"
   (*read*: Els23 abstract; manual p. 157-159).
7. *Lambda-bound functions are not region-polymorphic.* Folding `+` over a
   list puts every partial sum into one region (*read*: TT94 p. 197; manual
   §13.4).

**What worked, measured by its authors.**
- The most common multiplicity bound was 1, the next infinity, and
  "only very rarely" anything else (*read*: retro p. 251).
- At least 85% of allocations went to finite (stack) regions in every
  benchmark but one, and more than 99% in the largest (*read*: BTV96
  Fig. 8).
- Multiplicity inference gave "speedups of more than 200%" (BTV96 §9.2).
- Regions alone were the fastest configuration, "mostly because tags were
  not necessary" (retro p. 257).
- "Finite regions typically account for the vast majority of allocations
  at runtime" (p. 260).

**Region profiling.** The profiler (Hallenberg 1996) "was a breakthrough
for our ability to program with regions in practice" (*read*: retro
p. 253). It still needs a *region flow graph* "to find the cascade of
region polymorphic applications that ends up instantiating r34 to r5"
(*read*: manual p. 166), because the run-time region a formal parameter
stands for is lost along the call chain. The `-warn_on_escaping_puts`
warning flags a function whose type scheme has a free `put` (p. 78).

**Parallel MLKit** puts a mutex on a region when inference cannot rule out
two tasks allocating into it (*read*: EH23 abstract, §4.4).

**What it teaches.**
- **Option A is where MLKit ended up.** The split between a run-time handle
  for regions that are put into and nothing for regions that are only read
  is MLKit's own "dropping of regions" (1996), and the reason given is the
  dead argument.
- **What MLKit tests at run time, we would decide when compiling.** The
  separately compiled callee tests multiplicity and storage mode on every
  allocation. A whole, monomorphic program fixes them at each call
  instead, so a callee gets one copy per mode (L05 WU-8) and pays no test
  (D10).
- **Finite regions are where the payoff is.** That is today's `cell.stack`
  slot.
- **A fallback is mandatory.** For us it is counting, per cell (D39).
- **Tail calls win over lexical scopes** whenever both exist.
- **Never allow a dangling pointer**, because a counted drop list walks
  owned fields at a scope's end.

### 2.2 Cyclone: region names in types, handles as values

**Compile time.**
- Every pointer type names its region: `τ*ρ`. Functions are polymorphic in
  region names (`<ρ, ρ2>`), and the names are erased.
- A type-and-effect system tracks the *capability*, the set of live region
  names at each point, and keeps the check intraprocedural through
  function prototypes. Regions are ordered by an outlives relation (*read*:
  Cyc02 §2.2, §3; Cyc06 §3.8).
- Each pointer also has an *aliasability* qualifier: `\U` unique, `\RC`
  reference-counted, `\A` aliasable, `\T` top. A flow analysis tracks
  consumption for `\U` and `\RC` (*read*: Cyc06 §3.1-3.3).

**Run time.**
- A *region handle* `region_t<ρ>` is a first-class value: a pointer to a
  `struct _RegionHandle` on the stack, holding the current page, the bump
  offset, the end, a table of allocation functions and statistics
  (*read*: Cyclone src `bin/cyc-lib/cyc_include.h:42-58`).
- Pages double in size. Handles and exception handlers sit on one LIFO
  list, and a throw frees regions while it unwinds (*read*: Cyc02 §5).
- `heap_region` is a handle too (Cyc02 §2.1).
- "There are no hidden fields or reference counts for maintaining region
  information at run-time" (Cyc02 §2.1), except for `\RC` objects, which
  carry a hidden count word (Cyc06 §3.3).

**Who passes what to whom.** The program passes a handle explicitly to a
function that allocates. A function that only reads takes none. In the
string library, `strcpy<ρ, ρ2>(char?ρ, const char?ρ2)` and
`strlen<ρ>(const char?ρ)` take no handle, while
`rstrdup<ρ, ρ2>(region_t<ρ>, const char?ρ2)` does (*read*: Cyc02 Fig. 1).
A web server stores the handle in a request structure and passes that
around (Cyc02 §6.1).

**Cost.**
- One body serves both the heap handle and region handles, so the inline
  allocator tests the handle on every allocation:
  `if (r > (struct _RegionHandle*)_CYC_MAX_REGION_CONST && r->curr != 0)`
  bumps; anything else calls `_region_malloc`, which dispatches through
  `r->fcns->_malloc` (*read*: `cyc_include.h:294-313`;
  `lib/runtime_memory.c:716-719`).
- Library functions "often come in two flavors: a heap allocating function
  ... and a version that takes an additional region handle" (*read*: Cyc02
  §6.2).
- Porting: about 13% of a web server's changes were region-related.
  Managing reference counts by hand changed 22% of an FTP server's code
  (*read*: Cyc02 §6.1; Cyc06 PDF p. 21).

**What went wrong.** cfrac: "for large inputs, it was difficult to keep
regions from growing large before deallocation. We conclude that garbage
collection is a better match for this code" (*read*: Cyc02 §6.1).

**Variants.**
- *Dynamic arenas* escape the LIFO order: `new_ukey()` returns a unique key
  `uregion_key_t<ρ>`, `open(k)` consumes the key for a lexical scope and
  gives back a handle, and `free_ukey` ends the arena. Keys may be
  reference-counted instead (*read*: Cyc06 §3.7).
- *Reaps* hold `\U` or `\RC` objects inside an arena. They need a different
  allocator, bget, with "two header words per object" (*read*: Cyc06
  §3.4).

**What it teaches.**
- **Option A is Cyclone's design**, written by hand: erased names, and a
  handle only where allocation happens.
- **A handle shared with the heap costs a test on every allocation.**
  Specialization removes the test.
- **A linear key is the known mechanism for a non-lexical arena**, and so
  for a lifetime that moves to another shard (L05 §2.6.5).
- **Counted cells inside an arena cost an allocator of their own** (L05 Q1).

### 2.3 Swift SIL: ownership SSA, borrow scopes as values

**IR representation.**
- Every SIL value has an ownership kind: `owned`, `guaranteed`, `none` or
  `unowned`. Every use is classified as lifetime-ending or not. "The
  lifetime ending use points jointly post-dominate all non-lifetime ending
  use points and ... a value must have exactly one lifetime ending use
  along all reachable program paths" (*read*: `sources/docs/swift/docs/SIL/Ownership.md:6-24`).
- A borrow scope is a value: `%2 = begin_borrow %1`, ended by
  `end_borrow %2` on every path. Other instructions also introduce scopes:
  `load_borrow`, `store_borrow`, `partial_apply [on_stack]` and
  `mark_dependence %v on %base` (*read*: `SIL.md:615-690`).
- Non-consuming forwarding uses of a guaranteed value "are also guaranteed
  and are recursively validated as being in the original values scope"
  (*read*: `Ownership.md:301-304`).
- Lifetimes are not in types. `~Escapable` dependencies are written on
  function signatures (`@_lifetime`, listed in
  `docs/swift/SNAPSHOT.sil-arc.md`).
- An object can live on the stack with its count word:
  `alloc_ref [stack]`, balanced by `dealloc_stack_ref`. `bare` marks an
  object whose header is never used (*read*: `Instructions.md`,
  `alloc_ref`).

**What the IR checks for free, and what Swift built.**
- SIL is a control-flow graph of blocks, so nothing structural bounds a
  scope. Swift built a *linear lifetime checker*, "a value that is
  guaranteed to be consuming exactly once along any path ... and has a
  guarantee that all non-consuming uses and the initial value are
  joint-postdominated by the set of consuming uses" (*read*:
  `sources/code/swift/lib/SIL/Verifier/LinearLifetimeChecker.cpp:13-19`).
  It runs per value, from `SILOwnershipVerifier.cpp`. The checker is 843
  lines and the verifier 1,074 (*measured*: `wc -l`).
- A borrow scope crossing a block argument needs a *reborrow* phi.
  Recovering a phi's enclosing values meant walking predecessors, so Swift
  added an instruction that records them: `%3 = borrowed %2 from (%1, %0)`,
  "Declares the set of enclosing values for a reborrow or forwarded
  guaranteed phi argument" (*read*: `Instructions.md:972-995`).
- Stack allocation follows a *stack discipline* checked on the graph. "All
  stack deallocation instructions have an operand which identifies their
  paired stack allocation instruction. This operand must always be exactly
  the result of a stack allocation instruction, with no intervening
  conversions, basic block arguments, or other abstractions" (*read*:
  `SIL.md:1614-1660`). Nesting is then a rule about lists of active
  allocations at every edge.
- `OwnershipModelEliminator` lowers ownership SSA to plain SSA, with copies
  becoming retains and borrows erased (*read*: `code/swift/SNAPSHOT.sil-arc.md`).

**What it teaches.**
- **A scope token that may flow through block arguments and forwarding
  instructions needs walks**: forward liveness per value, and backward
  searches for the borrow introducer. Swift paid for them, then added
  `borrowed from` to stop one of the walks.
- **The cheap pairing is "this operand is exactly the producer's result"**,
  which is Swift's rule for stack deallocation and LLVM's rule for tokens
  (§2.4).
- **MLIR's regions give scope nesting by construction (D19)**, where SIL
  verifies it on edges.
- **Swift's counted object on the stack is today's counted stack cell**
  (L05 Q1(a)), and `bare` is Q1(b)'s uncounted cell.

### 2.4 LLVM and MLIR: tokens, scopes and ownership in upstream IR

**LLVM's `token` type.** "The token type is used when a value is associated
with an instruction but all uses of the value must not attempt to
introspect or obscure it. As such, it is not appropriate to have a phi or
select of type token" (*read*: `llvm/docs/LangRef.md:5010-5017`). The
verifier enforces it: "PHI nodes cannot have token type!", and only
intrinsics may return a token (*read*: `llvm/lib/IR/Verifier.cpp:3383,
4025, 4244-4247`).

The closest precedent to allocating through a token is
`llvm.call.preallocated.setup`.
- It "returns a token which is associated with at most one call".
  `llvm.call.preallocated.arg(token, i)` returns a pointer to that call's
  i-th argument area, and the call takes the token in a `"preallocated"`
  operand bundle. Nested setups "must be properly nested" (*read*:
  `LangRef.md:16239-16290`).
- The verifier checks each use in O(1), looking only at the operand's
  definition: `dyn_cast<CallBase>(Call.getArgOperand(0))` must be the
  setup intrinsic (*read*: `Verifier.cpp:6600-6631`).
- That check is possible only because a token cannot pass through a phi or
  a select.

**MLIR's builtin `!token`.** Proposed in May 2026 (tok-RFC) and present in
the pinned tree.
- "A use of a token SSA value is a pointer to an operation (in case of an
  OpResult) or a pointer to a region (in case of an entry block argument).
  A token carries no runtime data and cannot be forwarded" (*read*:
  `mlir/include/mlir/IR/BuiltinTypes.td:1265-1281`).
- LangRef: "Given a use of a token SSA value, its definition is guaranteed
  to be the semantic producer of the token. Generic transformations must
  preserve this invariant", and tokens leave CSE, DCE and hoisting
  unaffected (*read*: `mlir/docs/LangRef.md:750-776`).
- `Tokens.md` lists what a token may not be: "a forwarded result or operand
  of a `CallOpInterface` op; an argument or result type of a
  `FunctionOpInterface` op; a successor operand of a `BranchOpInterface`
  op; a block argument of a non-entry block; a forwarded operand to or from
  any region of a `RegionBranchOpInterface` op". It adds: "Because tokens
  are SSA values, they cannot cross `IsolatedFromAbove` region boundaries
  ... When a token-like dependency must cross such a boundary, another
  mechanism must be used (e.g. a symbolic reference using an attribute)"
  (*read*: `mlir/docs/Tokens.md`).
- The core verifier checks it per value. A token result or entry-block
  argument needs `TokenProducerTrait` on its op, and every user needs
  `TokenConsumerTrait`. `AnyType` excludes tokens, so `scf.yield`,
  `cf.br` and `func.return` reject them through their own ODS constraints
  (*read*: `mlir/lib/IR/Verifier.cpp:122-171`; `OpDefinition.h:782-794`;
  `Tokens.md`, "ODS-based Verification").

**MLIR's allocation scope.** `AutomaticAllocationScope` is a trait: a
`memref.alloca` "used within this scope [is] going to be cleaned up
automatically once the control-flow exits the nested region" (*read*:
`MemRefOps.td:424-452`; `OpBase.td:67`).
- Its effects name a resource, `AutomaticAllocationScopeResource`
  (`SideEffectInterfaces.h:196-201`).
- `memref.alloca_scope` declares no verifier (*read*: its ODS definition
  at `MemRefOps.td:424-470` has no `hasVerifier`), and memref types carry
  no scope. So nothing stops an alloca from being returned out of its
  scope; scope safety is the producer's job.

**MLIR's ownership-based buffer deallocation.** "Ownership materializes as
an `i1` SSA value". A `bufferization.dealloc` goes at the end of every
block, with run-time cost "`O(|memrefs|^2+|memref|*|retained|)`" unless
canonicalization and simplification fold the conditions away. The
convention at function boundaries is fixed: arguments are never owned,
results always are, and a function returning an alias of an argument must
copy (*read*: `mlir/docs/OwnershipBasedBufferDeallocation.md:1-80`).

**MLIR's transform dialect: consumption of handle values.** An op declares
that it consumes a handle as a `Free` effect on `TransformMappingResource`
(*read*: `TransformInterfaces.h:1276, 1297`). Use after consumption is
caught by "expensive opt-in checks" in a separate pass that computes block
reachability (*read*:
`mlir/lib/Dialect/Transform/Transforms/CheckUses.cpp:1-12, 27-60`). MLIR
has no built-in check of linearity.

**MLIR's async dialect.** `!async.token` is a run-time value, and the pass
`async-runtime-ref-counting` places `add_ref` and `drop_ref` from liveness
(*read*: `AsyncRuntimeRefCounting.cpp:1-12`; `Async/Passes.td:56-68`).

**IREE's stream dialect: a lifetime in a type.** `!stream.resource<L>`
takes a lifetime from a closed enum: `*` ("a value whose lifetime is not
yet analyzed"), `external`, `staging`, `transient`, `variable` and
`constant`. A pass refines `*` (*read*: IREE `StreamTypes.td:74-93,
128-170`). Ordering is a separate SSA value, `!stream.timepoint`
(`StreamTypes.td:19-35`).

**What it teaches.**
- **MLIR now gives D63's scope relation for free, inside a function.** A
  token that is an entry-block argument of `idr.lifetime` points at its
  region from every use, in O(1). The core verifier stops it from passing
  through yields, branches, selects or join arguments.
- **The builtin token cannot carry a lifetime across a call.** Its
  contract excludes function arguments and call operands, and functions are
  `IsolatedFromAbove`. MLIR's own advice for such a boundary is "a symbolic
  reference using an attribute", which is D48's binder.
- **The builtin token carries no run-time data.** So an arena handle, which
  does carry data, cannot be a builtin token.
- **What upstream does for ownership is weaker than D24 and C1.**
  Bufferization decides ownership at run time unless folded, and fixes
  the function convention. The transform dialect checks consumption only
  in an opt-in dataflow pass.
- **IREE is the upstream precedent for lifetime constants in a type**,
  refined by a pass. It has no variables.

### 2.5 The calculus behind the split: name, handle, capability

FMA06's λrgnUL keeps three things apart for each region.
- The *name* ϱ is type-level only.
- The *handle* `hnd ϱ` is unrestricted. Of the source calculus's handle,
  which λrgnUL's mirrors: "we require a handle to allocate a reference in a
  region, but do not require a handle to read or write a reference"
  (*read*: FMA06 §2, p. 3; §3).
- The *capability* `cap ϱ` is linear and "is represented as a dummy token,
  which has no run-time significance". `newrgn` returns the capability and
  the handle packed together, and `freergn` consumes both (*read*: FMA06
  §3, p. 5-7).

The same paper encodes Tofte-Talpin regions and Cyclone's dynamic regions
and unique pointers in this calculus (abstract).

**What it teaches.**
- **Being linear and being run-time data are separate facts.** The handle
  is the run-time part, needed only to allocate. The capability is the
  linear part, and it costs nothing.
- **In D63's terms:** the token is the capability (erased), and the arena
  is the handle (data). They are one SSA value only if its lowering decides
  from its uses whether it carries data, which MLKit's drop-regions does on
  `put` effects.

### 2.6 Gibbon (LoCal): region variables erased, output locations as cursors

**Compile time.** Functions take region and location parameters,
`sum [l r] t`, where `l` is a location in region `r` (*read*: Vollmer 2019
§2).

**Run time.** "Location arguments and return values turn into first-class
cursor values (pointers into memory buffers representing regions)". Region
variables have no cursor, and a function returns an "end-witness" cursor
(*read*: §4.3-4.4).
- Regions are chunk lists that double in size, with region-level reference
  counts: "Exiting a letregion decrements the region's count, and it is
  freed when no other regions point into it" (*read*: §4.5).
- Koparkar 2024 stores a pointer's "offset from there to the target chunk's
  footer" in "the 16 high-order bits" of the pointer, so as to reach the
  region's count (*read*: PDF p. 9). It cites MLKit's leaks as the reason
  for its backup collector (PDF p. 1-2).

**What it teaches.**
- **A fifth system has option A's shape**: only what a function writes
  through becomes a run-time value.
- **Threading the cursor as a returned value keeps the bump pointer in
  SSA**, and so in registers.
- **Region-level counting needs the region from any pointer.** Gibbon gets
  it from high bits, which AGENTS.md forbids ("Heap references stay raw,
  untagged addresses").

## 3. Lifetimes erased, or regions without a handle

### 3.1 Rust

**IR representation.**
- MIR types carry region variables. Borrow checking solves *non-lexical*
  regions over the MIR graph: "The value of a region can be thought of as a
  set. This set contains all points in the MIR where the region is valid"
  plus `end('a)` elements. Liveness and outlives constraints are solved per
  function (*read*: rustc guide `src/borrow-check/region-inference.md:73-112`).
- Storage is marked by `StorageLive` and `StorageDead` statements (*read*:
  `src/mir/index.md:128-142`).
- Then lifetimes are erased: regions are "all erased during codegen", and
  "we treat all erased regions as equal" (*read*:
  `src/type-inference.md:226-229`; `src/solve/invariants.md:166`).
  Monomorphization never splits by lifetime.

**Arenas are ordinary values.**
- `bumpalo::Bump` holds `current_chunk_footer: Cell<NonNull<ChunkFooter>>`
  and a limit (*read*: `src/lib.rs:332-336`).
  `alloc<T>(&self, val: T) -> &mut T` (`:2163`).
- Its collections store the arena: `Vec<'bump, T>` holds
  `bump: &'bump Bump` (*read*: `src/collections/vec.rs:521, 545`).
- Values are not dropped: "allocated objects' `Drop` implementations are
  not invoked" (*read*: `README.md:28-34`). A `dealloc` reclaims memory
  only for the last allocation (`src/lib.rs:1809-1824`).
- `typed_arena::Arena<T>` is a `RefCell` of chunk vectors, so it drops its
  values at the end and allows cycles (*read*: `src/lib.rs:1-12, 28-49,
  103-110`).

**Who passes what to whom.** User code passes `&'a Bump` to whatever
allocates, and functions that only read take `&'a T`, with no handle. The
borrow checker sees `'a` on both and proves nothing outlives the arena;
`reset` needs `&mut self` (*read*: bumpalo `src/lib.rs:1036-1039`).

**Cost.**
- The handle is shared (`&Bump`), so the bump pointer lives in the chunk
  footer in memory. Every allocation loads the footer pointer, loads the
  bump pointer and the chunk start, compares, and stores (*read*:
  `src/lib.rs:1458-1500`).
- `typed_arena` takes a `RefCell` borrow on each allocation (*read*:
  `src/lib.rs:186-205`).

**What it teaches.**
- **Option A, at industrial scale**, written by users: erased lifetimes and
  an arena passed by reference where allocation happens.
- **Rust can erase because lifetimes only check.** Nothing after borrow
  checking reads them. Ours decide layout and allocation, and must survive
  inlining and specialization, so the comparison stops at codegen.
- **A shared handle forces the allocation pointer into memory** (§7.2).

### 3.2 Mojo: origins

- An origin is "a special value called an origin to track the lifetime of
  variables and the validity of references". "Since origins are
  parameters, the compiler can infer an origin value". "Origin tracking
  and lifetime checking is done at compile time", and origins "track
  variables symbolically" (*read*, through a fetch summary: the Mojo
  manual's Lifetimes page).
- Signatures name them: `-> ref[self] String` and `ref[a, b]`, the latter
  a union that "extends both lifetimes". The checker is "a compiler pass
  that analyzes dataflow through your program", which also places
  destructors (same page).
- In the MLIR that Mojo emits, the origin is gone from the pointer type:
  for `Pointer[Int, MutAnyOrigin]` the lowered type is
  `!kgen.pointer<Int>` (*read*: `sources/docs/mojo/Mojo/docs/site/reference/inline-mlir.mdx:299-300`).
- Origins are parameter expressions that the compile-time interpreter
  folds, at the price of a "layering problem" (*read*:
  `Mojo/docs/stdlib/internal/mlir.md:25-40`).

**What it teaches.** In the one MLIR-based language with lifetimes, origins
are compile-time parameters, D48's quantity-0 binder. They are checked by a
dataflow pass and erased from the MLIR types it emits.

### 3.3 OxCaml: the local mode, a region stack with no handle

**Compile time.**
- Locality is a *mode*, `global < local`. A local value "cannot leave a
  region", and regions are lexical: function bodies, loop bodies and
  module bindings (*read*: Ox24 §2.4, §6.2).
- An implementation-only `regional` mode lets a value escape the current
  region but no further (§6.3).
- Modes are fully inferred (abstract). Since "Regions nest ... at runtime
  one can allocate only in the current stack frame", a local value lives in
  the innermost region (*read*: OxCaml src
  `jane/doc/extensions/_02-stack-allocation/reference.md:162-168`).

**Run time.**
- Stack allocations "do not take place on the function call stack, but on
  a separately-allocated stack that follows the same layout as the OCaml
  minor heap" (*read*: `reference.md:60-69`). It grows by ×4, up to a
  fixed count of arenas (`runtime/memory.c:644-687`).
- Domain state holds `local_sp`, `local_top` and `local_limit`
  (`runtime/caml/domain_state.tbl:49-54`).
- Opening a region is one load of `local_sp` into a register; closing it is
  one store back (*read*: `backend/arm64/emit.ml:1724-1727`;
  `runtime/memory.c:730-738`).
- A local allocation loads `local_limit` and `local_sp`, subtracts, stores
  `local_sp`, compares, branches, loads `local_top` and adds
  (`emit.ml:1094-1116`). A heap allocation bumps a pinned register and
  loads only the limit (`emit.ml:1124-1145`).
- The collector must recognise local blocks: `caml_modify_local` tests the
  header's colour at run time (`runtime/memory.c:584-597`).

**Who passes what to whom.** Nobody. The current region is the domain's
stack pointer. `exclave_` "terminates the current region and executes the
subsequent code in the outer region", so a callee allocates into its
caller's region (*read*: `reference.md:492-560`; Ox24 §6.2).
- It is "only supported in tail position of an existing region" (Ox24
  §6.2), and "`Lexclave` nesting is currently unsupported" (*read*:
  `lambda/lambda.mli:1060-1063`).
- To keep temporaries while building a result in the caller's region, a
  function delays `exclave_` until after the temporaries are dead
  (`reference.md`, "Delaying exclaves").

**Cost.**
- A tail call ends the function's region before the call, so "local
  values may not be passed to tail calls" (*read*: `reference.md:412-490`).
  In the ocamldep case study, programmers "marked various calls occurring
  at the end of a function as not requiring tail-call optimization" (Ox24
  §7.1).
- *Measured by the authors* (Ox24 Table 1): heap allocation per iteration
  went from 247 kB to 18 kB with no speedup in isolation (485 to 490 µs).
  With other work running it was about 9% faster (1,131 to 1,038 µs).
- Adoption: 2,648 of 187,765 `.mli` files use `local` or `global`
  (February 2024, §7).

**What it teaches.**
- **Option C can still put into a caller's lifetime**, by allocating into
  whatever region is current. But only the innermost region, only in a
  tail, and only after the callee has given up its own region.
- **No handle means global state**: the allocation pointer lives in memory,
  per domain or per shard. OxCaml's own local allocation does more memory
  traffic than its heap allocation.
- **Tail calls end regions**, as our rule 8 and A6 do (L05 §2.5, §2.6.3).
- **`regional` is `borrow ρ'` passed to a tail call** (L05 §2.4.2).

### 3.4 Verona: per-region memory management, an implicit current region

- Objects form a forest of regions, each reached by a unique `iso`
  reference to its bridge object. "The open regions form a LIFO stack. The
  top region is active ... An active region permits allocation,
  deallocation and mutation of its objects" (*read*: Verona §3.2.3,
  Table 1).
- Each region picks its memory management when it is created: tracing,
  arena or counted (`src/rt/region/region_base.h:22-27`).
- The runtime keeps a `static thread_local RegionContext` stack of
  (entry point, region) frames (*read*: `src/rt/region/region_api.h:12-57`).
- `create_object` allocates into the top region, switching on its kind at
  run time (`region_api.h:194-211`).
- A counted region keeps a bag of (object, count) pairs
  (`region_rc.h:15-23`). An arena region is a list of arenas that merges in
  O(1) (`region_arena.h:13-35`).
- A result destined for another region is built as `new iso` (a fresh
  region) and merged into the receiver's region (*read*: Verona §6, the
  key-value store example).

**What it teaches.**
- **The unique reference to the region is the handle.**
- **"Build in a fresh region, then merge" is a fourth way to put into a
  caller's region without passing anything down.** It costs a region per
  call.
- **A whole-program compiler would specialise the run-time switch on the
  region's kind.**

### 3.5 Vale: region borrowing that skips checks

- Regions exist only when compiling; references into an immutable region
  are raw. "Adding `pure` to a function" makes all data that existed before
  the call immutable for its duration, so generation checks on that data
  are skipped (*read*, through a fetch summary: Vale Part 1).
- A function over a "read-only" region "is then monomorphized into both
  variants", mutable and immutable, with no run-time flag. Only part 1 was
  prototyped (same post).

**What it teaches.** Specialization, not a run-time mode bit, for code
that is polymorphic in a region's mode. Our views skip count operations
the way Vale's skip generation checks.

### 3.6 Pony: reference capabilities, per-actor heaps

- The capabilities `iso`, `trn`, `ref`, `val`, `box` and `tag` are deny
  properties on local and global aliases (*read*:
  `clebsch-2015-deny-capabilities`, §2).
- Each actor collects its own heap by mark and sweep, with no barriers.
  Objects shared between actors are counted, coarsely and deferred, by
  messages (*read*: `clebsch-2017-orca`, §4, p. 7-8).
- Allocation goes into the current actor's heap: `pony_alloc(ctx, size)`
  uses `ctx->current->heap` (*read*: ponyc `src/libponyrt/actor/actor.c:1138-1144`).
  Generated code fetches `ctx` once per function with `pony_ctx()` and
  passes it to each allocation (`src/libponyc/codegen/codegen.c:1684-1705`).

**What it teaches.** The implicit handle is a context read once per
function. Types remove barriers, and counting is kept for the boundary.
That layout is the inverse of ours (counting everywhere, arenas inside),
and it matches 0007's shards.

### 3.7 Others that pair regions with counting

- **Gay and Aiken's RC** gives each region "a reference count of the number
  of external pointers to objects in r ... Calls to deleteregion fail if
  this count is not zero". Annotations (`sameregion`, `traditional`,
  `parentptr`) skip the count updates, and "reduce the overhead of
  reference counting from a maximum of 27% to a maximum of 11%" (*read*:
  GA01 abstract and §1). `sameregion` is L05's `plain ℓ` field rule:
  pointers within a lifetime are never counted.
- **Lean 4** gives persistent objects and objects in compact regions a
  count of 0: "We don't use reference counting for objects stored in
  compact regions". Every increment and decrement tests the count (*read*:
  `lean.h:146-148, 640-643`). This is today's `static` count 0, and L05's
  arena header.
- **GHC compact regions**: "if a single object in a compact region is live,
  all objects in a compact region are live" (*read*: CNF p. 5). A region
  moves as one object, which is the shape of a lifetime moving whole
  between shards.

## 4. Checking a scope without following def-use chains

What each system does to find, from a use, the scope it belongs to:

| mechanism | who | cost per check | condition |
| --- | --- | --- | --- |
| the name in every type, the name bound by a binder | MLKit, Cyclone, Rust (before erasure), Mojo | a type well-formedness check per value; a substitution per call | types may mention the binder |
| the scope is the operand's definition | LLVM `token`, LLVM `preallocated`, Swift's stack discipline, MLIR builtin `!token` | O(1) per use | the token never passes through a merge (phi, select, block argument, yield) |
| the scope is the enclosing region | MLIR regions (`AutomaticAllocationScope`, D19's region ops) | free: dominance and region visibility; results and terminator operands checked by type | values may leave only through the op's results |
| liveness of the value, walked | Swift (linear lifetime checker, borrow introducers), Rust NLL, Mojo's dataflow, transform `CheckUses` | per value, over uses and blocks | none; the general case |

1. **Swift is the counterexample.** Scope tokens are ordinary values that
   may flow through forwarding instructions and block arguments, and lifetimes
   are not in types. So every check walks (*read*: §2.3), and Swift
   added `borrowed from` to stop one walk.
2. **LLVM and MLIR tokens are the positive case.** Forbidding merges makes
   "which scope?" one pointer dereference, enforced by the verifier per use
   (*read*: §2.4).
3. **Types make a value's scope local without any operand.** The hold of
   L05 §2.1, `borrow ℓ` or `plain ℓ` with `ℓ` a binder's position, is this
   (Cyclone, MLKit). Without a lifetime in the type, a value derived from a
   view (a field read, a case binding) finds its scope only by walking back
   to the op that took the token, which is Swift's borrow-introducer search.
4. **A dependence across a call is a signature fact**: Rust's `'a`,
   Mojo's `ref[self]`, Swift's `@_lifetime`, Cyclone's prototypes,
   MLKit's type schemes. Each call substitutes, and the check is local
   (L05 §2.5 rule 4).

## 5. The table

| system | compile-time artifact | run-time artifact | who passes the handle | cost | failure mode |
| --- | --- | --- | --- | --- | --- |
| MLKit | region variables in types; put/get effects; multiplicity; storage modes; dropped regions | descriptor on the stack, 8 KiB pages; finite region in the frame; a tagged word per kept region parameter | caller, for each region the callee puts into; get-only regions dropped | bit tests per allocation into a formal region; descriptor in memory; slow fixed-point inference | leaks without GC; expert tuning; fragile storage modes; tail calls lost; GC-safety bug for 20 years |
| Cyclone | region names in types; effects; outlives; aliasability qualifiers | `region_t<ρ>` struct on the stack; pages doubling; unique or counted keys | the program, explicitly, to allocating functions only | handle-kind test per allocation; two library flavours; 13-22% of code changed when porting | regions grew before deallocation (cfrac); manual counting |
| Swift SIL | ownership kinds; borrow scopes as values; `@_lifetime` | none for borrows (erased); counted objects, some on the stack | n/a (no arenas) | linear lifetime checker per value; reborrow and `borrowed from` | the walks themselves |
| LLVM/MLIR tokens | token values; producer and consumer traits | none (builtin `!token`); preallocated argument area | n/a; the token names the scope | O(1) per use | the builtin token cannot cross calls |
| λrgnUL | name ϱ; linear `cap ϱ` | unrestricted `hnd ϱ` | whoever allocates holds `hnd` | none beyond the handle | (a calculus) |
| Gibbon | region and location variables | cursors; chunk lists with region counts | caller passes output cursors; callee returns end-witnesses | region count updates; high pointer bits | a backup GC needed |
| Rust | lifetimes in MIR, NLL, then erased | `Bump` struct; chunk footer | user code passes `&'a Bump` | memory traffic per allocation through a shared handle | no `Drop` in bumpalo; lifetime parameters spread through structs |
| Mojo | origins as compile-time parameters; dataflow checker | none (erased from `!kgen.pointer`) | n/a | dataflow per function | (not documented) |
| OxCaml | locality mode; lexical regions; `exclave_`; `regional` | separate local stack; `local_sp` in domain state | nobody; the current region is global state | load and store per region; memory traffic per allocation | no locals into tail calls; `[@nontail]`; exclave only in a tail |
| Verona | capabilities; region forest; one active region | region metadata from the `iso`; thread-local region stack | nobody; `enter` makes a region current | TLS read and a kind switch per allocation | navigation; one window of mutability |
| Vale | regions; `pure` | raw references | n/a | none; specialised per mode | (prototype) |
| Pony | reference capabilities | per-actor heap; counts held by actors | `ctx` fetched per function | TLS read per function | (outside regions) |
| RC (Gay-Aiken) | `sameregion` and kin | count per region | the program | 11% at most | deletion fails at run time |

## 6. What the evidence says about the three options

**A: an erased lifetime, plus a linear run-time arena handle passed only to
functions that allocate into a caller's lifetime.**
- Five independent systems reached this shape: MLKit (drop regions,
  BTV96), Cyclone (handles only for allocating functions), Rust (erased
  lifetimes, `&Bump`), λrgnUL (handle needed only to allocate) and Gibbon
  (only output locations become cursors) (*read*: §2.1, §2.2, §2.5, §2.6,
  §3.1).
- MLKit reached it from experience. Tofte and Talpin's semantics passes
  every region parameter at run time (*read*: TT94 p. 190-191, region
  closures). By 1996 MLKit dropped every parameter without a `put`.
- What none of them has is *linearity* of the handle. Their handles are
  unrestricted, and linear things appear only as keys of non-lexical
  arenas (Cyclone's `uregion_key_t`, Verona's `iso`) and as erased
  capabilities (λrgnUL).
- For a lexical lifetime, the region op bounds the handle already, so it
  needs no linearity for safety (L05 §2.5 rule 3). Linearity is earned in
  two places: a lifetime moving between shards (L05 §2.6.5), and the
  threaded cursor of §7.2.
- *Costs*: one register per allocating call; one more inference over the
  SCCs (L02 Q1); a counted copy of a callee whose callers sometimes have no
  arena, keyed by allocation mode under a budget (L05 WU-8). Each
  precedent pays instead a test on every allocation (MLKit, Cyclone).

**B: every lifetime parameter a run-time value.**
- No system in this survey keeps a get-only lifetime at run time.
- The one that started there, Tofte and Talpin's semantics, gave it up in
  MLKit with the stated reason: regions that are never used should not be
  passed (*read*: manual p. 63-64).
- B buys a uniform calling convention and costs a dead register on every
  call that only views (D10).

**C: lifetimes only, no handle.**
- C as L06 OQ1(c) writes it (no allocation into a caller's lifetime) is
  what OxCaml found too narrow. It added `exclave_` because a constructor
  such as `Counter.make` otherwise forces its result to the heap (*read*:
  `reference.md:492-545`).
- C with an implicit current lifetime (OxCaml, Verona, Pony) does put into
  a caller's lifetime with nothing passed, at three costs:
  - the allocation pointer becomes per-shard state in memory;
  - only the innermost lifetime can be the target;
  - the callee must end its own lifetime first.
- *Conjecture*: those restrictions fit most of the puts D26's *spine*
  proof admits (each put cell is taken into the result). But they rule out
  a callee that puts into two caller lifetimes, and a pinned register for
  the pointer would be a whole-program calling convention under D30's
  `tailcc`.

**D63 against the evidence.**
- D63 makes the lifetime one SSA value that is the arena handle where
  allocation needs one, and nothing elsewhere. That is A's run-time
  behaviour, with MLKit's mechanism: a region parameter that is both the
  variable in types and the run-time argument, dropped when no `put` uses
  it.
- MLIR shapes how it can be built (*read*: §2.4):
  1. Inside a function, the builtin `!token` gives the relation from each
     use to its `idr.lifetime` in O(1), and stops forwarding through
     yields, branches, selects and join arguments, all for free.
  2. Across a call it cannot: the builtin token may be neither a function
     argument nor a call operand, and functions are `IsolatedFromAbove`.
     MLIR's own advice is an attribute, D48's binder.
  3. The builtin token carries no data. So "the arena handle where
     allocation needs it" is either a value of our own type, with the
     token discipline restated by our verifier and shielded from upstream
     ops that accept `AnyType`, or a second value beside a builtin token.
  4. Without a lifetime in the type, a derived view finds its scope only by
     walking (Swift). The prior art keeps the name in the type (§4 item 3).
- Each is a representation choice inside D63 for the owner, one at a time.
  This document records the facts and decides none of them.

**Review claim 2's prerequisites, against the prior art.**
- *Tail calls and recursion get no lifetime.* MLKit with GC and OxCaml
  chose the same.
- *A termination argument for the inference by SCCs.* MLKit's ad hoc
  fixed points are the warning (retro p. 249). L05's put inference is a
  two-point marking that only rises, so it ends by construction.
- *Two versions or a run-time test.* MLKit and Cyclone chose the test;
  Vale chose versions, which D10 requires.

**Polymorphic recursion in lifetimes is forgone.** Tofte and Talpin found
polymorphic recursion in regions "vital" against values piling up in one
region (*read*: retro p. 248; manual p. 65). L05 recurses monomorphically
and lets D26's *spine* proof send what would pile up back to counting
(L05 §2.4.2, §2.6.3). That is sound under D26, but nobody has measured it
(§8).

## 7. What in the prior art beats all three here

These refine A, or D63's lowering. None replaces it, and each is the
owner's to rule.

1. **A finite put is a destination, not an arena.** MLKit found that a
   region's multiplicity is almost always 1 (retro p. 251), and passed a
   finite actual region as a slot in the caller's frame. Its callee tested
   a bit to learn so (`ATTOP_FF`, §2.1). In a whole program the bound is
   known at each call. So a callee that puts a statically bounded number
   of fixed-size cells into the caller's lifetime takes a destination
   (D34's `!idr.dest`, Gibbon's output location) into the caller's slot
   (`cell.stack`). No arena is opened and no handle passed, and the case
   joins D34's mechanism instead of adding one. *Conjecture* on how many
   puts it covers: count them on the suite and stage 1 (§8).
2. **The linear handle is the bump cursor, threaded.** MLKit, Cyclone,
   bumpalo and OxCaml all keep the allocation pointer in memory, because
   their handle is shared or global (*read*: §2.1, §2.2, §3.1, §3.3).
   Gibbon threads its cursor through SSA and returns end-witnesses (§2.6).
   If the arena value is linear, consumed by each allocation and returned
   by each put function, then the pointer and its limit are two SSA words.
   LLVM keeps them in registers, a chunk refill is an out-of-line call,
   and the chunk list's head stays in the lifetime's frame slot for
   freeing. This is the concrete gain linearity buys (L06 OQ1(a) against
   L05 §2.3's quantity many). *Conjecture*: memory operations per
   allocation drop from about four to none, at one extra result per put
   function. Measure it (§8).
3. **Proved reuse replaces storage modes.** MLKit's storage-mode analysis
   (atbot: reset the region, then store) existed to make tail-recursive
   loops run in constant space, and its authors call it the wrong tool
   (retro p. 260). In this compiler that job belongs to in-place reuse
   (D24, C1) and to D31 and D34, which a region system did not have. So
   nothing in the lifetime design should reset an arena inside a loop.
4. **No dangling pointer, by type.** Keep L05's holding rule, under which
   no counted cell refers into an arena and no view outlives its region,
   as Cyclone, Rust and OxCaml do. Tofte and Talpin's dangling-but-unused
   pointers cost MLKit two GC-safety repairs (*read*: Els23), and a drop
   list that walks owned fields at a lifetime's end would fail in the
   same way.
5. **Defunctionalization removes Tofte and Talpin's higher-order weak
   spot.** A lambda-bound function cannot be region-polymorphic (§2.1
   item 7). After defunctionalization, `apply` is a first-order function
   whose puts are inferred like any other.

Rejected:
- region-level counts (Gay and Aiken, Gibbon), which need the region from
  any pointer, so tagged pointers or a table, and add up to 11%;
- an implicit current region (OxCaml, Verona, Pony): global state, and
  LIFO only;
- "build in a fresh region, then merge" (Verona): a region per call.

## 8. Measurements owed (none taken)

1. Puts with a static bound: on the suite and stage 1, the number of put
   results whose cells are bounded in count and size (item 1 of §7),
   against all put results.
2. Cursor threading: memory operations per arena allocation, and wall time,
   in a `bench/` loop building a tree into a caller's lifetime, with the
   handle in memory and threaded (item 2 of §7).
3. What monomorphic recursion costs: cells sent back to counting by the
   *spine* proof at a recursive call, against what polymorphic recursion
   in lifetimes would have kept (the end of §6).
4. Copies by allocation mode: the number of counted copies made under L05
   WU-8, and the budget spent, on stage 1.
5. Lifetimes cut by tail calls: allocation sites that A6 and rule 8 keep
   counted because their scope would span a tail call or a call on a
   cycle (review claim 2).
