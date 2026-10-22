<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 verification swarm: the adversarial review

Reviewer: Sonnet 5.5 (a different model from the lanes). HEAD `e96bb991` at
start and at finish. Review and design only: no code, build, test or git
write; this is the one file written. Lanes returned when I read them: L01,
L02, L05, L06, L07, L08, L12, L13, L14, L15, L16, L18, L19 (L03, L04, L09,
L10, L11, L17, L20 had not). Where a returned lane found the same thing I
say so and cite it; those are convergences, not credit.

Grounds: *read* (path:line at HEAD or at the pinned toolchain
`.toolchain/llvm-project` at 7208ba24), *measured* (a `grep`/`wc` I ran on
the tree, named), *recalled* (not in `sources/`), *conjecture*, *decision*
(a ruling Dn or Cn). Nothing here was built or run.

## 0. Verdict

**Executable after named concrete prerequisites.** Two of the prerequisites
are design decisions the owner has not made, not work: D48's layout versus
its own erased index parameters (claim 1) and D44's staging (claim 8, §7 of
the proposal does not contain the absorbed proposals). Until those two are
ruled, the plan is materially under-specified in exactly those two places;
everything else survives with the corrections below.

Summary of the nine claims:

| # | claim | verdict |
| --- | --- | --- |
| 1 | D48 families in MLIR, readable from TT, refinement decidable | survives with named prerequisites (one is an owner decision) |
| 2 | D39, D40 lifetimes, borrowed results, O(1) free, inside D26 | survives with named prerequisites |
| 3 | D30, D31, D32, D34 tail calls, frame stacks, static stack | survives with named prerequisites; D30 conflicts with C1 and D39 as written |
| 4 | D25 carrying PR #166688 while fast-forwarding weekly | survives with named prerequisites; D25 contradicts itself and the design document |
| 5 | D16, D49, D52 generated TableGen, byte for byte on both hosts | survives with named prerequisites |
| 6 | D27 and C3 effect tree sound for upstream passes | survives with named prerequisites; the tree's payoff is narrower than §5.1 says |
| 7 | D26 covers every way memory is held | survives with named prerequisites |
| 8 | D44, D45, D53 to D55 | D44 as staged: broken (not in §7); D53 path rule: survives with a named correction (numerals); D54 survives; D55: design owed, one hole named |
| 9 | the packet | two scopes unowned (D53 to D55; two design files), validation check weak, duplicated owner questions |

## 1. The three most damaging findings

1. **D48's layout contradicts D48's erased index parameters** (claim 1,
   C1-a). A function body is generic in an erased index (`@map<n>`, one
   body, "passed at calls at compile time only"), yet a value of a known
   index is inline and one of an unknown index is a cell. A call that
   passes `#Vect[3]` to a body compiled for `#Vect[n]` crosses two
   layouts. The only consistent readings are: specialize on every known
   index (quadratic code on a recursive consumer of `Vect 100000`), or
   convert at the call (an allocation and a copy, which also loses the
   identity a linear vector's in-place promise needs), or make layout
   independent of the index (then "three words inline" is false). The
   ruling is the owner's.
2. **D44 absorbs four proposals into P0 and §7 is unchanged.** The
   execution section lists S0 to S7 and names none of 0003 (62 items per
   L16, not 21), 0011, 0010's A0 or 0015's R1 and R2, whose bars are
   ratios to a native run at `make self` and two of which wait on outside
   engines (L16). "Their stages keep their order" has no place to keep it
   in.
3. **D53's path rule collapses numerals.** Goals `LTE 4 10` and `LTE 3 9`
   have the same abstraction under "every primitive constant by its type",
   so the earlier one embeds in the later one, is not convertible, holds
   no unknown, and the program is refused (case 3 of the rule). Upstream
   `base` does this search: `natToFinLT` takes `{auto 0 prf : x `LT` n}`
   (`third_party/Idris2/libs/base/Data/Fin.idr:186-187`). The design
   document never mentions numeric goals (grep for `LTE`, `InBounds`,
   `IsSucc` in `design/elaborator-counts.md`: none).

Honourable mentions, each with its claim below: D25's patch is not the PR
it names (claim 4); the D30 guarantee is broken by C1's "type bounds
everything it reaches" at a tail call and by D39 regions around a tail call
(claim 3); the effect tree's disjointness is read by one upstream
transform, CSE (claim 6).

---

## 2. Claim 1. D48: families as MLIR attributes, read from TT, decidable refinement

**Verdict: survives with named prerequisites.** The representation is
buildable and the refinement is decidable on the language given; the
layout rule is not consistent with the erased-parameter rule.

### 2.1 Buildable in MLIR: yes

- *Self back-references carrying indices*: `self[m]` is a position, not a
  pointer, so the declaration is a finite tree. No attribute needs
  `mutate` (MLIR's mutable storage, the thing `MutableType` used). Equal
  declarations uniquing to one attribute is the ordinary `StorageUniquer`
  contract. [read: the D48 text, proposals:801-818; recalled: StorageUniquer]
- *Mutual groups*: by position, a finite tree again. One hole: a **nested**
  occurrence is not an Idris mutual block. `data Rose a = Node a (List
  (Rose a))` instantiates `List` at a type that contains `Rose`, so the
  instance `List (Rose a)` must be a member of Rose's group. The group is
  the strongly connected component of the monomorphic instance graph, not
  `mutwith`. The frontend already builds an instance graph (Growth); the
  design says "a mutually recursive group as `#idr.families<...>`" and
  should say the group is the instance graph's component. [conjecture on
  the implementation, read on the Idris data type]
- *Bytecode*: native entries are possible (08647d2e, read in `git log`),
  and a position-based self reference adds no cycle. The recursive
  attribute parser is already a known weak spot
  (`upstream/10-recursive-attribute-parser`, a report, L15). Deeply nested
  index terms are numbers ("`Nat` as a number"), so depth does not come from
  `S (S (S ...))`. [read]

### 2.2 Readable from the fork's TT: yes, through the fork's erasure, not the Pi quantities

A constructor's Pi binder carries the quantity as written. In upstream
`Data.Vect` the length of `(::)` is an implicit written without quantity
0, and it is Idris's own erasure analysis (the `eraseArgs` of the fork,
which nothing reads today: 17 FB-15; D §2.2) that makes it absent at run
time. D48's "per constructor its fields, each with its quantity (one or
many: an erased field does not exist)" holds only if "quantity" means the
fork's computed erasure, with the Pi quantity as input. L16 reaches the
same end (D48 corrected: today the frontend drops every index, and the
one-field collapse goes). [read: Forced.idr:1-24 reads the compile-time
tree; recalled: the prelude's declaration]

### 2.3 Decidable refinement: yes on the stated language, and weaker than Idris's coverage

Matching constructor-headed terms with variables is first-order
unification: decidable, with an occurs check (`n = S n` is false). Every
opaque term refines nothing, which is sound. So "a case whose equation is
false does not exist" is decidable. [recalled: Robinson]

Two consequences the ruling does not state:

- **The verifier's impossible is smaller than Idris's.** Idris proves an
  arm impossible by conversion, with function reduction, `Uninhabited`
  instances and `impossible` clauses. The frontend already reads that
  verdict: an `Impossible` leaf of the compile-time tree becomes an
  `Unreachable` arm (`Translate/Cases.idr:205-210`, read). So two classes
  of impossible arm survive: ours (the arm is absent) and Idris's, with
  the arm present and unreachable. The verifier can then require neither
  "every arm whose equation is not provably false" (rejects Idris's) nor
  its converse. This is an essential branch (Brooks), not a coordinate
  error; the ruling should name it, and the arm's justification belongs in
  its op (an `unreachable` that carries "Idris, not unification").
  [read for the leaf; conjecture for the verifier rule]
- **Existential indices held twice.** `(n ** Vect n a)` stores `n` as a
  runtime word and uses `n` in the next field's type. MLIR types cannot
  name an SSA value, so the match binds an erased index variable `n` and a
  runtime `%n`. They are one Idris value held in two places with no
  equation between them: constant folding `%n` to 3 leaves the index `n`
  symbolic, so "a known index fixes the shape" does not fire. A cost, not
  unsoundness, and a fact held twice against the owner's rule. [conjecture]

### 2.4 Counterexamples to the layout rule (the ruling's text at proposals:822-832)

**C1-a. Layout versus erased index parameters.**

```idris
map : (a -> b) -> Vect n a -> Vect n b
map f []        = []
map f (x :: xs) = f x :: map f xs

main = printLn (sum (map (+1) (replicate 3 0)))      -- Vect 3
     >> printLn (sum (map (+1) (replicate 100000 0))) -- Vect 100000
```

D48 says an erased parameter is "passed at calls at compile time only"
(`idr.call @map<k, frame>`), so there is one `idr.func @map<n>`. It also
says "a recursive field at an unknown index is a cell, a value of a known
index has a fixed size" (proposals:829-832) and `#Vect[3]` "is three words
inline, no tag, no cell, no count". Inside `@map<n>` the type is
`#Vect[n]`: a cell. At the call the argument is `#Vect[3]`: three words.
The call is ill-typed in layout though well-typed in the family. Each way
out costs:

| reading | cost |
| --- | --- |
| specialize on every known index (L06:366, 981: "keys gain known index terms and lifetimes, so a call at a known index gets the copy whose shape the index fixes") | `map` at 100000 makes 100000 clones (`@map<99999>` is a distinct key), and clone *k* holds *k* words inline: Θ(n²) code. The optimizer's budget stops it ("a spent budget leaves the program less optimized", AGENTS.md), which leaves the generic body, which is the next row |
| the generic body keeps a cell layout, the call converts | an allocation and a copy per call at every budget boundary; a hidden cost in no type; and for a linear vector the copy is a new identity, which D24's in-place promise forbids (the promise is "read off the program before counting", the conversion is not in the program) |
| layout independent of the index | `#Vect[3]` is a cell like `#Vect[n]`; the three-words claim and L07's "a token type cannot name a cell of unknown size" (L07:107) are false for indexed families |

[read: D48 and L06; the clone count is derived from D48 and L06:366,
conjecture on the optimizer's actual keying]

**C1-b. A fixed size has no ceiling.** `the (Vect 100000 Int) (replicate _
0)` is an inline value of 800,000 bytes. D32 requires "no frame larger
than the guard, checked when built" (proposals:575-576), and AGENTS.md
says "no representation limit refuses a program: a limit is lifted by a
representation". A size cutoff above which a known index stays a cell is
the lifting representation, but it is a round constant (C5: "every size is
the program's or the host's, never a round constant"), and then `Vect 4` is
inline and `Vect 5000` is a cell for the same family, which is C1-a again
at the cutoff. [read, derived]

**C1-c. Layout is not invariant under Idris's conversion.** `Vect (fib
10)` and `Vect 55` are convertible in Idris. With no normalizer in the
specializer ("static normalization (0010) is not built", AGENTS.md) `fib
10` is an opaque term, so the first is a cell and the second is inline: a
conversion (`rewrite`, `replace`, an index equality) between them is an
erased cast in the types and a data conversion in the layout. The frontend
sits in Idris and can normalize closed index terms with the fork's
evaluator at the boundary, which closes the closed case; the open case
(`plus n Z` against `n`) is a cell on both sides and is safe. Prerequisite:
state that the frontend normalizes closed index terms, and that casts
between index terms are erased only where layouts agree. [conjecture;
narrow]

**What the owner must rule** (a core shape, AGENTS.md "contested core
shapes"): which of the three readings of C1-a. My evidence favours "layout
is a function of the *family and its parameters*, and an index fixes a
shape only where the function is specialized on it for a stated reason
(a closed small literal, or an index the call chain proves constant)",
which makes the inline case an optimization with a conversion-free
boundary (the callee clone exists or the call is generic on both sides).
That is a recommendation, not a ruling.

**Survives**: representation, TT reading, decidability. **Prerequisites**:
the owner's layout ruling; group = instance-graph component; the
arm-justification class; the erasure source named as the fork's.

---

## 3. Claim 2. D39 and D40: lifetimes, borrowed results, O(1) free, inside D26

**Verdict: survives with named prerequisites.** L05 is the deep verification
(refuted: "three constants"; the element-view rule unsound for IORefs; a
scope parameter as a run-time handle contradicting D48; C1's `length`) and I
do not repeat it. What I add:

- **No scope may hold a tail call or a call on its function's cycle
  (L05 rule 8, A6), so lifetimes exist where recursion does not.** The
  region system's old conflict: the extent ends after the call returns, so
  the call is not a tail call. A function

  ```idris
  go : Nat -> Acc -> Acc
  go (S n) a = let t = Pair n a in go n (step t)
  ```

  with `t` in a lifetime bound by a region op around the body frees `t`
  after `go n ...` returns: D30 is violated, or `t` is not in a scope.
  L05's rule is the right repair. Its cost, which the ruling does not
  state: the code that most wants allocation into a lifetime (a parser, an
  evaluator, a tree builder, all on call cycles) gets none unless the
  recursive call is outside the region. The benefit is unmeasured.
  [recalled: Tofte and Talpin's tail-call and space discussion, Birkedal
  et al.; conjecture on the benefit]
- **"Freed in O(1)" holds only for a view-only region** (D39 says so:
  "one holding only views of older data and of each other"). A region with
  one owned counted reference is O(cells) at its end, and a loop body's
  region that holds one is the usual case. [read, D39]
- **Inference by SCCs needs a termination argument by construction.**
  Region-polymorphic recursion is inferred by iterating an effect and
  region fixpoint inside the SCC; the lattice is finite (a function's
  lifetime parameters and their order constraints), so it ends, but
  AGENTS.md allows a fixpoint "that has to be reached" only when it
  terminates by construction, and D39 does not give the argument.
  [recalled: Tofte and Birkedal; conjecture that it applies]
- **Counting as the fallback needs two code versions or a run-time
  test for a callee that allocates into a lifetime parameter** (L05 I2,
  L06 OQ1): a cell in a counted lifetime has a count word, a cell in an
  arena has none. One body cannot have both layouts; D10 forbids the test.
  This is the same shape as C1-a, over lifetimes.

**Survives**: lexical lifetimes as an optimization over counting, borrowed
results, checking local and linear given signatures. **Prerequisites**:
L05's corrections; the tail and cycle rule; a termination argument; the
two-version rule.

---

## 4. Claim 3. D30, D31, D32, D34

**Verdict: survives with named prerequisites.**

### 4.1 D30: every tail call a jump, `musttail` and `tailcc`, four targets

- The LLVM side is real but not free: `tailcc` on AArch64 already needed
  a patch carried here (`upstream/30-aarch64-sibcall-callee-pop`: a
  `tailcc` function with stack arguments sibling-called a C function and
  returned with its argument area still on the stack; six programs
  crashed after `main` returned; arm64 Darwin and Linux) [read:
  `upstream/30-aarch64-sibcall-callee-pop/README.md`]. D30 puts `tailcc`
  on every function only the module's calls reach, so the surface for the
  next such bug is the whole program, on four targets, re-verified at
  every weekly fast-forward (D25). Prerequisite: a fixture per target for
  `musttail` of every shape the lowering emits (stack-passed arguments
  both more and fewer than the caller's, a memory-returned result
  forwarding the caller's slot, a call to a runtime function in tail
  position, which D30 excludes by calling it a primitive). [conjecture on
  the open bugs; read on patch 30]
- **D30 conflicts with C1 as written.** C1: a parameter is borrowed when
  "at every call the caller uses the argument afterwards **or its type
  bounds everything it reaches**". At a call in tail position whose
  argument the caller owns and does not use afterwards, the second
  disjunct borrows it and counting must place a `drop` after the call: the
  call is then not a jump. L07 C1.7(b) finds the same ("too weak at a call
  in tail position"; today only within a cycle, `Borrows.cpp:236-237`).
  The repair is a rule on the one tail fact: a parameter passed at a tail
  call at its last use is owned, whatever its type bounds. [read]
- **D30 conflicts with D39 regions** as in claim 2 (L05 rule 8).

### 4.2 D31: typed linear frame stacks

I tried to break the "one stack per result type" discipline on interleaved
nesting and could not. Frames awaiting a result of type R form a
sub-sequence of the global call stack, and when a function returning R
returns, every frame pushed after its caller's frame and awaiting R belongs
to a call nested inside it, already popped. The top of the R stack is the
right frame. [reasoned]

What the ruling leaves open: the cost on every non-tail recursion on a cycle
(`fib`, tree folds, non-accumulating `length`, `foldr`) is a frame push, a
tag, and an **indirect dispatch on return**, which defeats the return-address
predictor that a native `ret` uses. D32 says "Costs, measured as it is
built". I would add the measurement to take before approval: `fib 35` and a
tree fold, native recursion against frame stack, on arm64 and x86_64.
[conjecture]

Interaction with D19's regions: the continuation of a call inside a nested
case region includes the rest of every enclosing region and their joins, so
the cut for D31 is across region boundaries and needs the join-point form
(D19) to avoid copying; L05 A6 removes lifetimes from this by rule. The
design says "it transforms the call's continuation"; the continuation of a
call nested in `idr.match` regions is not a suffix of a block. [conjecture;
the mechanism is match-and-counting.md's join point, unread by me for this
case]

### 4.3 D32: the static native stack

- *Codegen reports frame sizes*: the object-format-independent route is
  `-fstack-usage` (`AsmPrinter.cpp:1740-1767`, a text file of `getStackSize()`
  per function, with `dynamic` for functions with variable-sized objects).
  The `.stack_sizes` section is ELF only (`MCObjectFileInfo.cpp:566` makes
  it in the ELF initialization and `:1274-1277` returns the null section
  otherwise), so macOS cannot read it from the object. [read, pinned
  toolchain] So "as code generation reports it" is realizable on all four
  targets only through the text route, as a second output of codegen
  consumed by a later build step: the runner's reservation is then a
  link-time constant fed from a codegen result. The ruling says nothing of
  that step.
- *What the report omits*: `getStackSize()` is the frame the function
  allocates; the x86-64 red zone (up to 128 bytes below the stack pointer
  a leaf may use without allocating it), the incoming argument area of a
  `tailcc` function (counted in the caller, adjusted on each tail call to a
  callee with a different area) and any `dynamic` function are not in it.
  [recalled for the red zone and for X86's tail-call return-address delta;
  read for `dynamic`] The margin must cover them and the runtime and the
  C library, and a margin is a constant. C5 says "never a round constant";
  the margin is a measurement per target (GMP's temporaries on `alloca`
  are the largest known consumer, C5), which is a stated value, not a
  round one, if it is measured and checked at build.
- *The guard check*: "no frame larger than the guard, checked when built"
  needs C1-b's answer for inline values.

### 4.4 D34: tail recursion modulo context as a promise

A promise "read off the program as the frontend wrote it" must state the
evaluation order. `f x :: map f xs` evaluates `f x` and then the call under
left-to-right eager evaluation (D13), and the context cell can be built
first. `Node (go l) (g x)` evaluates `go l` and then `g x`; building the
cell first evaluates `g x` before the call and moves a crash of `g x`
across a divergence of `go l`, which D13 forbids. The promise's source
condition needs "the call is the last evaluated component of every context
cell on the path". [read: D13, D34; the order is Idris's evaluation order,
recalled]

**Survives**: all four. **Prerequisites**: per-target `musttail` fixtures;
the tail-fact rule against C1 and D39; the codegen-report step and the
omissions list; D34's order condition; the frame-stack cost measurement.

---

## 5. Claim 4. D25: carrying PR #166688 while fast-forwarding weekly

**Verdict: survives with named prerequisites; D25 is internally
inconsistent.**

- **The carried patch is not the PR.** D25 says "carry the PR as a patch"
  and also "The encoding: the PR's is ours, a token defined by the target
  op". `match-and-counting.md:235-243` says the PR's encoding is still
  argued upstream (a count of regions, labels, or an SSA token) and records
  that the pin has none of it (my grep for `HasBreakingControlFlow` and
  `PropagateControlFlowBreak` in the pinned `mlir/include` and `mlir/lib`
  finds nothing: *measured*). A token encoding in `Dominance.cpp`,
  `Verifier.cpp`, the control-flow interfaces, the dataflow analyses, the
  inliner and `scf` is a rewrite of a 3,965-line PR, and AGENTS.md's rule is
  "prefer upstream's own fix, backported". D25 also says "If upstream merges
  another form, ours moves to it", which D19 forbids unless an owner ruling
  names a strictly better form: the move is forced by a third party and
  reverses `idr.join` and `idr.jump`'s encoding. [read]
- **D25 and the design document disagree about a second tier.** D25:
  "the conservative modelling of §5.4 and idr-lower's own lowering of
  nested jumps are never built." `match-and-counting.md:395-402` (§5.4, "At
  the pin, until option 3"): "our own passes read the jump edges off one
  generated interface method of `idr.join`. That is a second tier ... the
  lowering of nested jumps is ours until then." Either the patch lands
  before the first pass that reads a nested jump (the whole of S5 and S6
  waits on it) or the second tier is built and deleted. [read]
- **Scale against the tree's experience.** The tree carries 18 `llvm*.patch`
  files totalling 5,133 lines (*measured*: `ls upstream/*/llvm*.patch`,
  `cat | wc -l`), and several were "tested on a private build ... not yet
  in the toolchain" (`git log`: 930d6a5b, f7f14407, 4dde6b7f). The PR alone
  adds 77% of that again, in the files every MLIR change touches. Whether it
  rebases weekly cannot be measured here (the pinned checkout is shallow:
  `git log` shows one commit). The measurement to take: on a full clone,
  `git log --since=<8 weeks> -- mlir/lib/IR/Dominance.cpp mlir/lib/IR/Verifier.cpp
  mlir/lib/Interfaces/ControlFlowInterfaces.cpp
  mlir/lib/Analysis/DataFlow/DeadCodeAnalysis.cpp
  mlir/lib/Transforms/Inliner.cpp mlir/lib/Dialect/SCF/IR/SCF.cpp`, and
  for each commit whether it conflicts with the PR's hunks. [conjecture on
  the rate; measurement owed]
- **Weekly fast-forward of all dependencies, four targets, is a build the
  agents do not run** (memory: no LLVM builds by agents) and a bump gates on
  `make test` on four targets (AGENTS.md). With S0 doing the first bump
  *before* the cutover on a tree whose suite has stood at 470 of 480 since
  0be4e660 (proposals:142-144), a regression from the bump is not
  separable from the tree's own. Prerequisite: the suite green on the
  pre-bump pin before S0's bump, or the bump's baseline recorded as a
  ratio (L19's S1, S2).

**Prerequisites**: choose which of the two (the PR's own form, a token
variant) the patch is, and say which the design document's second tier
does; the full-clone churn measurement; a green baseline before the first
bump.

---

## 6. Claim 5. D16, D49, D52

**Verdict: survives with named prerequisites.**

- *100% generated TableGen* is achievable for what ODS declares. It is not
  100% of the semantics: one-source §8.2 counts 183 `[{ }]` C++ blocks
  (about 1,590 lines), 36 `CPred`s, 37 `extraClassDeclaration`s that become
  "a trait or a free function the spec names" (`one-source.md:655-657`,
  read). The generated `.td` and the generated header name hand C++; "a
  missing one a link error" is a good check. What Idris's types prove is
  the specification's internal laws (the effect tree, the grade algebra,
  the family index arity), never the hand bodies. State that boundary in
  D16 so "invariants proven by Idris's types" is not read as covering the
  hooks.
- *Upstream vocabulary drift*: the specification names upstream's ODS
  classes (`DeclareOpInterfaceMethods`, `OpBuilder`, trait names) as text
  it prints. D51's `IdrAdmitted.td` makes a wrong upstream op name
  TableGen's error, but a renamed ODS class or a changed `OpBase.td` default
  is found only at the C++ build, weekly under D25. Not a defect: a named
  detection point. [conjecture]
- *Byte for byte, D52*: the output must be a function of the specification
  alone, and the generator is compiled by two hosts with different string
  runtimes. The specification's prose (`Doc`) can contain non-ASCII text.
  Idris's `String` is code points; idris-mlir's runtime strings are UTF-8
  bytes with simdutf pinned, and `length`, `substr`, `strIndex`, padding
  and `unpack` differ over non-ASCII if either is byte based. Prerequisite:
  the generator uses no code-point-sensitive operation, or the specification
  and every `Doc` is checked to be ASCII. The test to take: generate on both
  hosts and `cmp`, with a non-ASCII character in a `Doc` in the fixture.
  [unverified, conjecture]
- *The subset*: the specification's types (`Vect s`, `Fin s`, a field whose
  type is a computed index) must compile under the *current* idris-mlir,
  which refuses a type stored in a run-time field (`tests/dependent-field-type-field`,
  read) and accepts `(n ** Vect n Int)` of one representation. one-source
  §4.4 states this and calls it *conjecture until gate A*; agreed. After
  D48 lands, `Vect s` with a stored `s` has an unknown index and is a cell,
  so the answer under the new compiler is the same, and the prerequisite is
  only for the first stage.
- *D49 and D52 at the seam*: L19 finds "the stamp has no reader; the
  generator in the fingerprint". A fingerprint of the specification's
  source text changes with a comment; D52 wants the output "a pure function
  of the specification". The stamp should hash the specification's printed
  value, not its files. [read: L19; conjecture on the fix]

---

## 7. Claim 6. D27 and C3: the effect tree for every upstream pass that reads effects

**Verdict: survives with named prerequisites; the tree buys less than §5.1
says.**

- **Only one upstream transform reads resource disjointness.** In the
  pinned tree `isDisjointFrom` has one caller outside the alias analysis and
  bufferization: `Transforms/Utils/CSE.cpp:222` (*measured*: `grep -rn
  isDisjointFrom mlir/lib mlir/include`). Loop-invariant code motion moves
  only `isPure` operations (`LoopInvariantCodeMotionUtils.cpp:117`, read),
  so it never moves a read across anything. D21's "heap reads and writes may
  move across a crash or a guard" and §5.1's "CSE, dead code, hoisting,
  sinking and the inliner read the declared effects" are true for the
  effect *kinds* and, for the tree, only for CSE. To cash the tree's
  disjointness in hoisting and sinking the pin needs a patch (a
  resource-aware LICM), which AGENTS.md puts before our own pass.
  [measured, read]
- **What the tree cannot make unsound in the pinned CSE.** Writes are the
  only conflict CSE sees (`isa<Write>`, `CSE.cpp:213-232`): a `Free` between
  two reads of one pointer is not a conflict, correct only because a read
  after a free of the same value is already ill-formed. And an op whose
  only effects are `Allocate` on its own result is trivially dead
  (`SideEffectInterfaces.cpp:75-90`): the effect must name the result value
  (a resource-only `Allocate` makes the op undeletable). The specification's
  law "an acquisition names its result" is exactly that, and it is the right
  one. [read]
- **C3 turns the in-place promise's acceptance into the optimizer's.**
  L01 §1.8 (I1) and L08 B7 find this independently; the minimal case:

  ```idris
  -- LList: kind in_place, rebuild takes (1 xs : LList a)
  main = do
    let a = LCons 1 LNil
        b = LCons 1 LNil          -- ω binders: C3 makes both `con`s pure
    printLn (toList (rebuild a))
    printLn (toList (rebuild b))
  ```

  CSE merges `a` and `b` (C3: "two equal ones merge"), the merged value has
  two uses, exclusivity cannot prove either call exclusive, and D24 refuses
  `unsupported (uniqueness)`. Without CSE both are fresh and exclusive and
  the program is accepted. AGENTS.md: "a refusal an optimization can add or
  remove" is what D24 was written to end. Repair (L01 I1's direction): an
  unrestricted `con` whose result flows to an `in_place` parameter at
  quantity 1 takes a fresh identity, or exclusivity is decided before any
  value-merging pass. [read]
- C3's other readers (L01's table): `no-heap-allocation` flips before
  counting, `BuildsValue` is void, runtime builders' `alloc` is omitted.
  Convergent; no new finding.

**Survives**: the tree as a set of facts, CSE's use of it, Allocate-only
deletion. **Prerequisites**: the D24 repair; a patch or a stated absence for
LICM and sink; L01 and L02's corrections.

---

## 8. Claim 7. D26's statement covers every way memory is held

**Verdict: survives with named prerequisites.** L07 §2.9 accounts 28
holdings against D26 and L05 I5 adds the per-lifetime proof; I checked
those rather than redo them. What D26 as written does not cover:

| way of holding | in D26's statement | gap |
| --- | --- | --- |
| reuse tokens, stack-cell shells, borrows, frame stacks | yes ("a call may hold") | frame-stack chunk retention (L07 row 28): at most one chunk, to be stated by L10 |
| lifetimes (D39) | no: D26 predates D39 and has no clause for a region's cells | a dead cell in a region is neither "reachable from what the program will use" nor "held by an active call"; L05 I5's count and spine proof, per lifetime, is the clause; without it a loop that builds a temporary per element into the enclosing lifetime holds a million dead cells with correct output |
| memo cells | after force (L07 row 22) | holds: forces move captures out; `Captures.cpp:3-5` read by L07 |
| 0007's suspended tasks | no | a parked task's frames are "heap continuation frames of `idr-frames`" only if 0007's task stack is that stack; C2 marks 0007's task frames stale. A task never resumed holds cells it "will use" in a sense nothing decides. [conjecture] |
| memory the kernel or another process observes | no | D21: "after a crash nothing observes the heap". C2 R2 makes `heap` include a kernel buffer ring and foreign allocations; a write into a shared mapping or a submission ring before a crash or `exit` is observed. Not a P0 construct today, a hole D21 opens for 0007 and 0020. [conjecture] |
| "reachable from what the program will use" | the central term | a semantic liveness, not a property of any representation; L19 Q1 asks whether to check D26 at run time by a typed record from the checked runtime. The statement is only checkable per kind of holding (a frame's bytes, a token's size); the owner's promise "a fixed number of bytes ... computed by the compiler from its types" is the checkable half and should be the statement |

**Prerequisites**: a per-lifetime rule; L10's chunk statement; the typed
record of L19 Q1 (or a static form) so the promise is checked, not stated;
a sentence for foreign and kernel-visible memory under D21.

---

## 9. Claim 8. D44, D45, D53 to D55

### 9.1 D44: absorbing 0003, 0011, 0010's A0, 0015's R1 and R2

**Verdict: broken as staged.** D44: "Their stages keep their order and their
measured bars; each comes into P0's execution (§7) with its proposal
amended in the same change." §7 (proposals:1313-1344) lists S0 to S7 and
names none of them; its gate is "passes the five suites and the invariant set
unchanged", while those proposals' bars are ratios to a native run at `make
self` (L16). L16 also finds: 0003 has 62 items, not 21; O6 and O7 depend on
unabsorbed work (0009's plain-Idris layer, 0015's R4); R1 and R2 are gated
on outside engines. So "whole" is a program the plan has no stage for and
three of whose dependencies it excludes. [read: proposals §7, L16]
Prerequisite: a rewritten §7 that places each absorbed stage, with its
dependency on P0's S-stages, before the owner approves the plan (D4).

### 9.2 D45 and D53: the path rule

*Termination.* The abstraction ⌊·⌋ has a finite label set (the context's
names, the root environment's locals, `?`, `x`, one symbol per primitive
type, binder kinds), so Kruskal's theorem applies to the sequence of goals
on a path; each node has finitely many children, so König's lemma gives a
finite tree. I could not break that. [recalled; the doc's argument is
elaborator-counts.md:499-511]

*Counterexample: numerals.* ⌊·⌋ replaces "every primitive constant by its
type" (:483-485). The goal chain of an auto proof of `x `LT` n`:

```
LTE 4 10  ->  LTE 3 9  ->  LTE 2 8  ->  LTE 1 7  ->  LTE 0 6   (LTESucc each step)
```

Under ⌊·⌋ every goal is `LTE(Nat, Nat)`: `LTE 4 10` ⊴ `LTE 3 9`; not
convertible; no unknown; case 3: the program is refused, naming both
goals. Upstream does this search: `natToFinLT`'s
`{auto 0 prf : x `LT` n}` (`libs/base/Data/Fin.idr:186-187`, read), and
`contrib`'s `index` takes `{auto ok : LT i n}` (`contrib/Data/Seq/Sized.idr:122`).
Whether a `Nat` literal in a goal is a `PrimVal` or a chain of `S` is
*recalled* (Idris 2 keeps literals as `PrimVal` and matches them against `S`
in the evaluator); if it is a chain the abstraction does not collapse, and
the length of the chain is the measure. Either way the document does not say.
Repair (selected): numerals of a unary type enter ⌊·⌋ as the unary tree
(`S (S ... Z)`), with the label set `{S, Z}` finite; the embedding of two
chains is `≤`, so a shrinking numeric chain never embeds. Other primitive
constants (strings, `Integer`, `Bits`) enter by type, which is safe because
no search recurses on them. Discriminated by a fixture: `natToFinLT 3 {n =
10}` elaborates and `Cons2.idr` is refused. [read for the callers; the
refusal is derived from the document's own rule]

Also check, because D53 states "every program the stock Idris elaborates
with a large enough depth is elaborated the same, except where upstream's
answer was its depth running out": the document's own §2.6 list (a growing
hint tried before a succeeding sibling; `{auto t : Rose Nat}`) are programs
upstream accepts at depth 50 and the fork refuses, not only programs whose
answer "was the depth". D53's sentence is narrower than §2.6's list.
[read]

### 9.3 D54: postponing a growing search that holds an unknown

Survives. Retry only after a round makes progress, progress solves a hole
for good (`Unify.idr:1428-1447` as cited), so postponement ends; cost is a
restart of the search per retry, polynomial in the rounds. The one thing I
would pin: "the last chance" is the end of the elaboration of the
declaration, and a program refused there names goals that contain
unknowns, which the message should say. [read the document; conjecture on
the cost]

### 9.4 D55: the ambiguity count deleted, tuples settled by sort

The deletion survives: the count bounds nothing that would not end, and the
measurements are the document's (`printLn` of a 22-tuple: 433 s). The
replacement does not yet exist ("Its design in the fork is owed"), and the
ruling's sentence "(a, b) is settled by the sort of its expected type when
that is known, and by its components when not" has a hole:

- `(a, b)` is `UniqueDefault (MkPair a b)` over `[Pair a b, MkPair a b]`
  (`Desugar.idr:529-534`, per the document): when both readings elaborate,
  the **value** is the default. `let t = (Nat, Nat)` with an unknown expected
  type has components that are both of sort `Type`, so "by its components"
  allows either; upstream's answer is `MkPair Nat Nat : (Type, Type)`. A
  settlement that picks the type reading when both components are types
  changes the meaning of a program upstream accepts, against D12. The rule
  must say "components of sort `Type` with an unknown expected type: the
  value, as upstream's default".
- "Known expected type" is elaboration state, not syntax: it can be a
  metavariable solved a few steps later. The settlement is therefore
  postponement again (as D54), not a function of the syntax tree, so D55's
  "settled by representation" needs the delayed form to be complete.
  [read; conjecture on the design]

### 9.5 AGENTS.md's acceptance rule and D45

Every count D45 replaces is a refusal; the replacement's refusals are
"search grows" and "last chance", both properties of the program and its
search, not of the optimizer: consistent with AGENTS.md. Nothing to add.

---

## 10. Claim 9. The packet

- **D53, D54 and D55 are in no lane.** The README's table and
  `common.md` say "D1 to D52"; the proposal is D1 to D55 (proposals:880-918).
  L17's body names D45 and says to read `elaborator-counts.md` "if it exists
  when you reach it ... and do not redo its design". So the three rulings
  that settled the elaborator's mechanisms are checked by this review alone,
  and I could not run the stock Idris (no run rule), so §9 is read and
  derived. Relay to the coordinator: tell L17 (not yet returned) that D53 to
  D55 and the document exist and are in scope, and that numerals and the
  tuple default are open.
- **Two design files are read by no lane**: `design/AGENTS.proposed.md` and
  `design/AGENTS.changelog.md` (*measured*: grep of `parts/lanes/*.md`).
  `validate.sh`'s design list (`effects effect-vocabulary typed-effects
  one-source compile-time-cpp perf-sources match-and-counting`) omits them
  and `elaborator-counts.md`. Its coverage check is a numeric grep
  (`(^|[^0-9.§])NN([^0-9]|$)` on the concatenated reread blocks), which a
  stray "10" in an unrelated sentence satisfies for lane 10: it checks that
  a number appears, not that a document is named. The README's "every audit
  document is in some lane's reread list" is not what the script proves.
- **Overlapping reads (writes are disjoint, so the validator is satisfied)**:
  D44 in four lanes (L14, L16, L17, L18), D48 in five (L04, L05, L16, L18,
  L20), D39 in four (L05, L08, L12, L14), D41 in three (L12, L13, L15), D33
  in two (L10, L15), C5 in two (L10, L11). Same finding written several
  times is the expected result; `status.md` already shows one owner
  question raised by three lanes (the lifetime parameter at run time: L02
  Q1, L05 Q1, L06 OQ1). D11 allows one question at a time, so the coordinator
  must merge them.
- **Dependencies hidden in the "none waiting" frontier.** L06 (every
  question, DP and G decision against the rulings) and L20 (QTT end to end)
  state claims about the other eighteen areas while those run. Their
  cross-area findings cannot be checked against files still moving; re-read
  both against the other lanes after the last return.
- **Scope that cannot be completed by review**: every "measured as built"
  (D31, D32, the C5 sizes, the effect-tree reorderings, the weekly rebase)
  needs a build or a full clone. The packet accepts "the exact measurement to
  take"; I list the ones I owe in §12. Not an impossible scope, but nothing
  in the swarm can discharge them, so the verdicts above are *read* or
  *conjecture* for cost and *read* for correctness.
- **A tree the lanes read is the coordinator's uncommitted one.** L19 finds
  `tests/spec/` and `tests/build` stop the test runner starting. That is the
  coordinator's own dirty tree; relay.

---

## 11. Disagreements with the rulings

Not verdicts. Each row is where the evidence I read stands against a
ruling's text, with both sides, and what would settle it. The owner or the
coordinator (per D6) decides.

| ruling | the ruling's side | the other side | what would settle it |
| --- | --- | --- | --- |
| D48, layout (proposals:822-832) | a known index fixes a shape; one `idr.func @map<n>` per function; erased parameters "compile time only"; deleted `!idr.box`; L07:107 "holds, gives D26's statically sized by construction" | C1-a: the body's `#Vect[n]` is a cell and the call's `#Vect[3]` is inline; specializing makes Θ(n²) code on a recursive consumer; converting allocates; C1-b: an inline `Vect 100000` is 800 KB against D32's guard | the owner's choice among the three readings in §2.4; a fixture `map` over `Vect 3` and `Vect 100000` on the built compiler, with code size |
| D30 against C1 (proposals:511-536 and 927-952) | "a call in tail position MUST NEVER grow the stack"; C1's second disjunct bounds borrowing by type | a bounded borrow at a tail call needs a `drop` after it: no jump (L07 C1.7(b); `Borrows.cpp:236-237`, `Placement.cpp:226-233`) | a rule on the one tail fact: owned at a tail call's last use (L07's I1 direction) |
| D30 against D39 (proposals:511-536 and 643-692) | lifetimes are lexical regions, frees at the region's end | a region around a tail call frees after the call: no jump (L05 rule 8) | L05's rule 8 and A6 (no scope holds a tail call or a cycle call), with its cost stated: lifetimes absent from recursive code |
| D25 (proposals:400-430) | "obviously carry the PR as a patch"; "always carry the patch"; the token encoding is ours | the PR's encoding is argued upstream (match-and-counting.md:235-243); the carried patch is a variant; "ours moves to it" if upstream differs reverses D19; the design document keeps a second tier D25 says is never built (:395-402) | the owner's word on which form the patch is, and on whether "moves to it" is a standing authority or needs D19's strictly-better ruling |
| D32, "frame sizes as code generation reports it" (proposals:559-579) | static, computed when the program is built, small; C5 expects tens to hundreds of KiB | `.stack_sizes` is ELF only (`MCObjectFileInfo.cpp:566, 1274-1277`); the `-fstack-usage` text route is portable; the frame report omits red zone, `tailcc` incoming-argument area and `dynamic` functions (`AsmPrinter.cpp:1740-1767`) | a second codegen output consumed at link time, and a measured per-target margin; C5's "never a round constant" read as "a measured, checked value" |
| D53, the abstraction ⌊·⌋ (elaborator-counts.md:483-485) | finite labels, Kruskal, every search ends; "every program stock Idris elaborates with enough depth is elaborated the same" | numerals collapse: `LTE 4 10` and `LTE 3 9` are one tree, so `natToFinLT 3 {n = 10}`'s proof is refused (Data/Fin.idr:186-187); §2.6's own list refuses programs stock accepts after a growing detour | unary numerals in ⌊·⌋ (§9.2), and the first experiment the document lists (§8: log firings over prelude, base, fork, frontend, libs) extended to numeric goals |
| D55 (proposals:903-918) | "B": the tuple's meaning settled by representation; design owed | `UniqueDefault (MkPair a b)`: upstream's default is the value when both elaborate; "expected type known" is elaboration state | the design the ruling owes, stating the default and the delayed case |
| D44 (proposals:739-755) | "no more postponing ... we should do the big one"; absorbed stages keep order and bars | §7 has no stage for them; bars are ratios at `make self`; L16: 62 items, O6 and O7 depend on unabsorbed work, R1 and R2 on outside engines | a §7 that places each, before D4's approval |
| §5.1 and D21 on upstream reading the tree | "CSE, dead code, hoisting, sinking and the inliner read the declared effects"; heap moves across a crash | disjointness has one transform reader, CSE (`CSE.cpp:222`); LICM moves only `isPure` ops (`LoopInvariantCodeMotionUtils.cpp:117`) | a resource-aware LICM patch (AGENTS.md: patch upstream first), or the claim narrowed to CSE |
| C3, revised (proposals:979-992) | pure before counting is an optimization "where no reader needs" an exact count | the in-place promise's acceptance depends on CSE merging (`rebuild a`, `rebuild b`): L01 §1.8 I1, L08 B7; AGENTS.md's acceptance rule | a fresh identity for an unrestricted `con` that reaches an `in_place` parameter, or exclusivity before value merging |
| D34 and D13 (proposals:589-599, 223-237) | a self call modulo a context is a loop building each cell first, "read off the program as written" | building a cell before the call moves the evaluation of the cell's other components across it, against eager order | the source condition "the call is the last evaluated component" |
| D26 (proposals:431-464) | frame-limited, stated for every compiled program, "reachable from what the program will use" | semantic liveness, uncheckable; lifetimes, a parked task and kernel-visible memory are outside its holder list | L05 I5, L07 §2.9, L19 Q1's typed record; owner's call on kernel-visible memory under 0007 |
| D16, "invariants proven by Idris's types" (proposals:257-265) | the dialect's one source is typed Idris, TableGen 100% generated | 183 hand `[{ }]` blocks (about 1,590 lines) become named hooks in C++ (`one-source.md:655-657`); the types do not cover them | a sentence in D16 stating the boundary |

---

## 12. Measurements owed (exact; none taken, per the no-run rule)

1. Layout (claim 1): on the built compiler, `map` over `Vect 3` and `Vect
   100000`, with and without specialization on known indices: instance
   count, code size, a conversion's allocations.
2. Tail calls (claim 3): the `musttail` fixture matrix per target at each
   LLVM bump; `fib 35` and a tree fold, native against frame stack, arm64
   and x86_64, wall and returns mispredicted.
3. Stack bound (claim 3): `-fstack-usage` for the stage-1 module on all four
   targets, the largest frame, the runtime's deepest chain into the C
   library and GMP; the red zone's use in a leaf.
4. Patch churn (claim 4): the `git log --since` over the files named in §5,
   on a full clone of the pinned project.
5. Generator on both hosts (claim 5): `cmp` of the generated tree under
   stock Idris and under idris-mlir, with a non-ASCII `Doc`.
6. Effects (claim 6): the LICM and sink behaviour on a loop with a heap read
   and a crash arm, at the pin.
7. Elaborator (claim 8): `natToFinLT 3 {n = 10}` and a numeric `LTE` auto
   proof with the path rule logging, and `let t = (Nat, Nat)` with an
   unknown expected type on the stock Idris (which reading it takes).

## 13. What I did not attack

D1 to D24 except D24's seam with C3; D35 to D38 (L11, L19 cover them: L19
corrected D35 to Linux only and D37 and D38); D41 to D43 (L12, L13, L15
verified; L15's finding that `mlir::Value` converts to `bool` is the one I
would have looked for); the verification of the fork's two counts beyond
what the document measured (I did not run Idris).

HEAD at finish: `e96bb991`.
