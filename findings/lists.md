# Lists: deforestation (step 2b) and contiguous lists (step 3)

Research note, 2026-10-02, at bc6d454. A proposal, not a decision: it
answers the brief for the representation project the user approved
(precision in counting, then deforestation, then contiguous lists) with a
design for steps 2b and 3, the measurements that bound them, and the
lanes that would build them. Nothing here changes the compiler.

Status of every claim: **read** (a file and line of this tree at bc6d454,
a dump of a program compiled with main's tools at bc6d454, or a paper in
`sources/papers`); **measured** (a prototype in the design scratch
directory, the method in §5); **recalled** (from memory of a source not in
this tree); **conjecture**.

## Short answer

- **Where the time goes (measured, §5).** Minimum wall time over 41
  interleaved runs (5 for spectral-norm, 3 for k-nucleotide), on the
  shared 4-CPU container:

  | program | C | today | 2a alone | 2b by raising + 2a | 3 (contiguous) + 2a |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | fasta 250000 | 27.7 ms | 59.1 ms | 52.9 ms | 48.4 ms | 29.7 ms |
  | reverse-complement | 7.1 ms | 100.8 ms | 90.2 ms | 80.4 ms | 35.8–37.0 ms |
  | spectral-norm 5500 | 1433 ms | 1775 ms | n/a | ≈ today (conjecture) | 1478 ms |
  | k-nucleotide | 336 ms | 5955 ms | n/a | ≈ today (conjecture) | 4911 ms |

  fasta with its lines produced *in production order* and fused by hand
  takes 28.6 ms, the same as the contiguous form: what costs is building
  cells, not passing elements through a buffer. Most of the benchmarks'
  long lists are out of reach of fusion in production order: they are
  accumulated in reverse (fasta's `gen`, reverse-complement's `readAll`
  and `body`), read ahead from input before any output is written
  (`readAll`), or walked many times (spectral-norm's vectors,
  k-nucleotide's sequence); turning an accumulator around first would
  reach `gen` alone. Step 3 is where the benchmarks' gains are; 2b is
  cheap and general, and takes about 10% off fasta and
  reverse-complement after 2a.
- **Step 2b: the consumer driven by the producer, as raising (§3).**
  Today idr-specialize raises the one consumer of a call's result, an
  apply, into a clone of the callee, keyed by the pair, so that the clone's
  own recursive call with the same consumer becomes a self call
  (`foreign/idr/lib/Specialize/Raise.cc:1-24`). The proposal adds
  structural consumers: a call of a function at a parameter it recurses
  structurally on (binding time decreasing or bounded), and an op with a
  one-step fold on a constructor (2a's output op). Pushed to the
  producer's tails, the consumer meets `Nil` and `x :: rest`, call-pattern
  specialization unrolls one step of it, and the recursive producer call
  it then consumes is the same key: one loop, no list. This is candidate
  (a), and it is the terminating core of (d): driving is pushing plus
  one-step folds, folding is the clone table, generalization is key holes.
  Its legality is the raising and sinking rules that exist
  (`onlyAllocates`), which give exactly the conditions fusion needs on
  effects and early exit (§3.3). No type, no op, no pass: a second form of
  the one definition of a consumer that raising and sinking share, a key
  attribute, a profit and size test. Candidates (b) and (c) are rejected
  for 2b (§3.1).
- **Step 3: a list in a buffer, decided per value on the MLIR side,
  recorded in its type (§4).** A new type `!idr.seq<@T>` for a value of a
  list-shaped box type `@T` (a nil without fields, a cons of non-recursive
  fields and the tail) that lives in a buffer: an array cell (the runtime's
  `idris_rt_array`, its length the capacity) viewed from `start` for
  `length` elements, which is the array's memref descriptor with a dynamic
  offset. A new pass after idr-rc puts a web of list values in buffers when
  every cons in it has an exclusive tail (the `excl` grade), no value of it
  is stored in a box, a closure or an array, and its elements hold no
  references; anything else stays cells, with a named `missed` remark.
  Cons onto an exclusive seq is a push at its head end, amortized O(1);
  uncons is a view; a whole list is one counted cell. The verifier's rule
  that every cons onto a seq takes an exclusive tail turns a wrong decision
  into a compile error, never a write into a shared buffer. The frontend
  keeps deciding what a type is (box or unboxed sum, the cell layout);
  where a value of it lives, by proofs only the owned stage has, is a
  program decision, as `idr.stack` already is.
- **Plan (§6).** 2b-1 raising of structural consumers; 2b-2 output-op
  consumers (with 2a); 3a the seq type, runtime and lowering, unused; 3b
  the decision for accumulators and walks (reverse-complement, fasta);
  3c builders for `x :: f xs` producers (spectral-norm, k-nucleotide);
  3d bulk string and output ops on buffers; 3e in-place slots, slice
  views and a reversed direction. Each lands behind the verifier and an
  ablation switch.

## 1. What the benchmarks do with lists (read)

Read off the dumps after the simplify loop (`02-idr-simplify`) and after
idr-tail-loops (`08-idr-tail-loops`) of the four programs, compiled with
main's tools at bc6d454 (`tools/compile.sh --directive dump-mlir`).

| # | program | producer | consumer | order | must exist? |
| --- | --- | --- | --- | --- | --- |
| F1 | fasta `repeatFasta` | `take m` (non-tail recursion) of `drop k alu2` (a static list) | `pack`, `putStrLn` | production | no |
| F2 | fasta `randomFasta` | `gen`: a tail loop consing onto an accumulator, `reverse` at the end, returned in a `Pair` with the seed | `pack`, `putStrLn` | reversed, then read | no, but produced back to front |
| R1 | reverse-complement `readAll` | a tail loop over `getChar` consing onto an accumulator, `reverse` at the end | `process`/`body`, walks | reversed, then read | yes: input read ahead of output |
| R2 | reverse-complement `process` | `break (== '\n')` (non-tail, a pair) | `pack ('>' :: hdr)`, `putStrLn`; the rest to `body` | production | prefix no |
| R3 | reverse-complement `body` | consing `comp c` onto an accumulator | `putChunks`, which reads it from its head: the last consed first | against production | yes |
| R4 | reverse-complement `putChunks` | `splitAt 60` (non-tail, a pair) | `pack`, `putStrLn`; the rest looped | production | prefix no |
| S1 | spectral-norm | `replicate n 1.0` (non-tail) | every row's `dotRow` | — | yes: read n times |
| S2 | spectral-norm `mulAv` | `[0 .. n - 1]`: `takeUntil` over `countFrom`'s stream | `map (\i => dotRow ...)` | production | no |
| S3 | spectral-norm `mulAv` | that `map` | the next product, every row | — | yes |
| S4 | spectral-norm `dot` | `zipWith (*)` | `foldl (+)` | production | no |
| K1 | k-nucleotide | `readAll` as R1 | `splitLines` (`break`, `drop 1`) | reversed, then read | yes |
| K2 | k-nucleotide | `splitLines`: a list of lines | `three`, `collect` | production | no (the spine) |
| K3 | k-nucleotide `collect` | `map toUpper l` | `++ collect ls` | production | no |
| K4 | k-nucleotide | `collect`'s sequence | `count` seven times, `length` | — | yes |
| K5 | k-nucleotide `count` | `take k cs` at each position | `pack`, a map key | production | no |

The fixtures repeat these shapes: `map-deep` and `traverse-deep` sum and
traverse a list `build` accumulates in reverse; `prelude-lists` folds
small constant lists that compile-time evaluation folds away.

What the dumps say beyond the table (read):

- **The accumulators are exclusive today.** `gen$spec$1`'s accumulator is
  `!idr.excl<!idr.box<@List[Char]>>`, `reverseOnto[Char]` takes and
  returns exclusive lists and reuses every cell, `readAll$raise$1` returns
  an exclusive `IORes`, `body`'s accumulator is exclusive (08 dumps of
  fasta and reverse-complement). Step 3 needs exactly this fact (§4.1).
- **The list read from input is not.** `body`'s input is `own`, because
  `splitAt[Char]$excl` and `span` return their `MkPair(Nil, Nil)` static
  constant on one path, which is shared (08 dump of reverse-complement,
  `splitAt[Char]$excl`). Step 1 makes such a pair of atoms exclusive. Step
  3 needs no exclusivity for a list that is only walked (§4.1), so it does
  not wait for step 1; it gains from it on lists consed onto after such a
  join (`'>' :: hdr`).
- **TRMC misses `take` and `replicate`.** Their recursive call borrows the
  `Nat` counter, so the counter's `idr.drop` sits between the call and the
  constructor, and idr-trmc moves a call only past ops that neither touch
  memory nor fail (`foreign/idr/lib/Passes/Trmc.cc:121-124`): fasta's
  `take[Char]` and spectral-norm's `replicate[Double]` are non-tail
  recursions after idr-tail-loops (08 dumps), 5500 frames deep for
  spectral-norm's vector. Borrow inference's tail-call rule would have
  made the counter owned had it counted a call under a cons in tail
  position as a tail call (`foreign/idr/lib/Ownership/Borrow.cc:155-166,
  180-183`). A finding for the counting lane, independent of this note.
- **The range and the map share cells.** In spectral-norm the map's result
  is built in the range list's cells (`mapImpl[Double, Int]$spec$1$trmc`
  takes the exclusive range and reuses each cell, 08 dump): fusing S2
  saves a walk, not an allocation.
- **`pack` walks its list twice**, once for the size and once to write
  (`foreign/idr/lib/Lower/Strings.cc:1-7`), so a fused `pack` would have to
  produce its list twice or build into a growable string: it is a
  materialization point, not a consumer to fuse (§3.2).

## 2. The facts each step relies on

| fact | Idris proves it? | the IR has it | used by |
| --- | --- | --- | --- |
| single use of the produced list | no (QTT 1 on a `List` binder says nothing of its tail: the Prelude's fields are unrestricted) | SSA: one use of the producer call's result | 2b |
| the producer or the consumer only computes (no IO, no crash, returns) | totality and effects, as facts | `onlyAllocates` on calls, from the callee's facts (`foreign/idr/include/idr/Idr.h:111-114`, `lib/Facts/CallEffects.cc`) | 2b |
| the consumer recurses structurally on its list | size change | binding times: decreasing or bounded (`lib/Specialize/BindingTimes.h:1-24`) | 2b |
| a tail consed onto is not shared | no (Marshall et al.: linearity restricts the future, uniqueness guarantees the past, p. 8) | the `excl` grade, by provenance on MLIR's dataflow solver (`lib/Ownership/Exclusive.cc:1-16`) | 3 |
| a list is not stored in a cell | n/a | types: a box field, a capture, an array element | 3 |
| the elements hold no references | the type | `Counting::counted` (`lib/Ownership/Counting.cc:9-38`) | 3 |
| the type is list-shaped | the declaration | `consOf` (`lib/Dialect/Ops.cc:1093-1112`) | 3 |

## 3. Step 2b: producer/consumer fusion

### 3.1 The candidates

| candidate | fuses | ours to write | upstream leverage | verdict |
| --- | --- | --- | --- | --- |
| (a) the consumer driven by the producer | in-order producers (map, filter, range, take, replicate, zipWith, splitAt's prefix) into folds, walks and output | a consumer kind in raising (§3.2) | the loops it makes are `scf.while`, uplift and LLVM's, as every loop's | **chosen** |
| (b) streams (`git show 903d127~1:findings/fusion.md`, §7) | the same, plus zip of two producers and `concatMap`, and accumulate-then-reverse by its F7 rule | a type, about ten ops, four verifier rules, a classifier of recursion schemes, nine rules, two lowerings | linalg for index spaces, once S3/S4 of that plan land | rejected: ten times the code, and recognition by shape of code that the simplify loop reshapes (gen's 15 copied leaves) |
| (c) known lengths raised to index spaces | `map`, `zipWith`, folds over ranges and `replicate`, as `idr.array.generate`/`fold` | a scheme recognizer, and contiguous data to raise to | the vectorizer; not linalg's fusion, which wants tensors (`ElementwiseOpFusion.cpp:154`, `hasPureTensorSemantics`) and our arrays are memrefs (`findings/decision-inhouse-linear.md`) | later, on contiguous lists (stage 3f) |
| (d) supercompilation in the simplify loop | everything (a) does, plus nested producers | unfolding of recursive functions, a whistle, generalization | none | rejected as such: (a) is its terminating core |

The literature agrees on what (a) gives up and why it is safe.
Deforestation folds "only calls that are identical up to renaming"
(Sørensen, Glück, Jones 1996, p. 2), which is what a clone key is; a
supercompiler removes `map g (map f zs)` "with no additional knowledge
about the map function or its fusion rules" (Mitchell 2010, §2.3, p. 4),
which is what pushing a consumer does after monomorphisation; GHC's rules
match names and "it is possible to get pessimized code via failed fusion"
(Kovács 2022, `paper.tex:613-617`), which a key never does: a failed
raise leaves the call as it was. Futhark fuses a producer "if it is the
source of only one dependency edge" (Henriksen 2017, §4, p. 7): our
single use.

### 3.2 The mechanism

Raising today (read: `Raise.cc:155-176`): the one use of a call's result
in its block is an elimination (an apply, through a field and linear
positions); the callee does not take the world; the call only computes, or
every op between it and the consumer does. The clone is keyed by the
callee and the consumer (`KeyApplyAttr`, `IdrOps.td:1447-1458`); its
parameters are the callee's, then the consumer's other operands; the
consumer is pushed to every tail of the body, through the matches whose
result is returned (`Raise.cc:106-151`).

The extension: a **structural consumer** is also an elimination.

- **A call `g(…, r, …)`** with the producer's result `r` at a parameter
  of `g` whose binding time is decreasing or bounded: `g` takes its list
  apart and recurses on a part of it. Key: the producer, its arity, `g`
  and the position. Pushed to a tail, `g` meets
  - `Nil` (a constant): call-pattern specialization makes `g`'s clone on
    it, and the inliner its body;
  - `x :: p(xs')`: specialization on `::(hole, hole)` unrolls one step of
    `g` (a decreasing or bounded parameter specializes on any shape that
    is not a hole, up to an unroll size of 32:
    `lib/Specialize/Specialize.cc:180-185`), small enough to inline,
    leaving `g(…, p(xs'), …)`, which raises to the same key: a self call;
  - `p(xs')` itself (filter's skip): the same key at once.
- **An op with a one-step fold**, in practice 2a's op that writes a list's
  characters: on `Nil` it is its world, on `c :: rest` it is itself on
  `rest` after `put_char c`. Two canonicalization patterns (DRR), and the
  op pushed as an apply is today.

For `foldl f z (map g xs)`, after the simplify loop: `foldl`'s loop clone
consumes `mapImpl`'s clone; raising gives `R(xs, acc)` = match `xs`:
`Nil` → `acc`; `x :: xs'` → `R(xs', f acc (g x))`, a tail call, so
idr-tail-loops makes the loop. Chains compose: `sum (map f [1 .. n])`
raises `sum` into `map`, then that clone (a structural consumer of `map`'s
input) into the range. `foldr` and `length` consumers fuse into non-tail
recursions with no list, as deep as the original.

New code (read: where it goes):

- **the consumer**, as a second form of `Elimination`
  (`include/idr/Idr.h:320-337`, `lib/Dialect/Dialect.cc:476-496`): a
  call that takes the value at a parameter its callee matches on.
  `Elimination` is the one definition of a consumer, read by raising
  (`consumerOf`) and by the meet that sinking and case-of-case test
  (`canon::feeds`, `lib/Dialect/Canonicalize/Meet.cc:14-17`), so sinking
  brings a producer to such a consumer with no rule of its own;
- **in raising** (`lib/Specialize/Raise.cc`): the binding-time test
  (decreasing or bounded), which only the specializer computes, and
  `push` for a call; a key attribute beside `KeyApply` (`IdrOps.td`);
- **profit:** the producer call only computes, or `g` does (its facts):
  otherwise the knot cannot tie (§3.3) and the clone would be waste;
- **size and budget:** the tails times the consumer's step stay under a
  bound, as sinking's does (`lib/Dialect/Canonicalize/Sink.cc:26, 80`),
  and a raise never spends the last clones of an owner: the clone table
  rejects the program past 1024 clones of one owner
  (`lib/Specialize/Clones.cc:87-91`, `Clones.h:22`), and a fusion that
  does not happen must cost nothing.

### 3.3 Correctness conditions

Fusion runs producer step k+1 after consumer step k, where the program as
written runs every producer step first. All three conditions the brief
names follow from rules that already guard code motion, so no new legality
code is written (conjecture until 2b-1's negative fixtures say so):

- **Order of effects and crashes.** The reordering happens at the knot:
  after one step of `g` is inlined, the block holds `ys = p(xs')`, then
  `g`'s step, then `g(…, ys)`. Raising `p(xs')` into `g` moves it past the
  step, which raising allows only if the call only computes or every op
  between does (`Raise.cc:169-174`). So a crashing or diverging producer
  fuses only with a consumer whose steps only compute (its crash happens
  at the same element; the consumer's work before it is unobservable), and
  a consumer with IO fuses only with a producer that only computes: IO
  stays in the consumer and the producer is pure (`fusion.md` §5.2's rule,
  derived instead of written). `traverse_ printLn (map (100 `div`) xs)`
  with a zero in `xs` prints nothing before the crash, fused or not.
- **Early exit.** A consumer that stops (`elem`, `any`, `take` as a
  consumer) leaves `ys = p(xs')` before a match whose stopping region does
  not use it. Raising needs the consumer in the call's block, so the call
  must first sink into the region that uses it, which sinking does only
  for an op that only computes (`Sink.cc:51-61`). A producer that may
  crash or diverge is therefore never skipped: the program crashes as
  written.
- **Exactly one use.** Raising takes a result with one use
  (`Raise.cc:156`). A shared list is not fused; it is step 3's.
- **Production order against consumption order.** Pushing follows
  production order. A producer that accumulates and reverses (fasta's
  `gen`, `readAll`, `listBindOnto` for comprehensions) reaches its consumer
  only at the end, through `reverse`: the consumer is pushed into
  `reverseOnto` and walks the reversed list, which is still built. Fusing
  it needs the producer turned around first (fusion.md's F7), which
  recognizes the reverse scheme by shape; contiguous lists make the
  accumulator a buffer instead (§4), at the same measured speed (§5), so
  2b does not take F7.
- **Termination.** One clone per key; keys pair existing functions with
  a position; the only unfolding is one step of a consumer on a known
  constructor, which the binding times already bound
  (`Specializer.h:15-18`, `kUnrollLimit`). Compile time grows with the
  tails a consumer is copied into, which the size guard bounds.

Not fused, by design: an IO producer (raising never raises a callee that
takes the world, `Raise.cc:23-24, 156`); zip of two producers (only one
side is pushed, as foldr/build cannot fuse `zip`, recalled); a consumer
whose list is used twice; `pack` (it would need a growable string, and a
string is a contiguous buffer: step 3's slice copy is the better form).

### 3.4 Where it sits, and what a test states

In idr-simplify's specializer, each round, beside today's raising: no new
pass, no new step in `idr::pipelineSteps` (`lib/Registration.cc:15-56`).

The property, defined once in `lib/Expect` and stated after
`idr-simplify`: **`builds-no-list=@f`**: nothing reachable from `@f`
builds a value of a list-shaped box type (`idr.con`, `idr.reuse`), checked
as `no-heap-allocation` checks allocation (`lib/Expect/Allocation.cc`),
over `@f` and its clones. Fixtures, each diffed against Chez:

- `sum (map f [1 .. n])`, `foldl (+) 0.0 (zipWith (*) xs ys)`,
  `traverse_ printLn (map f xs)` with pure `f`: `builds-no-list` and
  `constant-stack`;
- `elem 3 (map f xs)` with `f` crashing on an element after the first 3,
  and `traverse_ printLn (map (100 `div`) xs)` with a zero in `xs`: not
  fused, same output and crash as Chez (the negative cases of §3.3);
- fasta's `repeatFasta` shape over a static list with 2a's output op:
  `builds-no-list=@Main.repeatFasta`.

## 4. Step 3: contiguous lists

### 4.1 The facts, and what exclusivity gives today

A list may live in a buffer when pushing onto it never writes a slot
another value can see, and nothing needs it as a cell:

- **a cons onto it has an exclusive tail.** Today's `excl` grade proves
  it for every accumulator of §1 (read: the 08 dumps). It is provenance
  (`Exclusive.cc:1-16`): a constructor of exclusive fields, a field taken
  from an exclusive value, a result every return makes exclusive, a
  parameter every caller passes exclusive, with mixed callers split into
  `$excl` copies (`Exclusive.cc:373-470`). It is written into the types
  and checked locally after every pass: no dup of a view of an exclusive
  root that is then consumed as exclusive, no exclusive constructor of a
  shared field (`Verify.cc:203-224`). It does not hold through a join with
  a static constant other than an atom (step 1's), nor through IO that is
  not raised;
- **it is never stored** in a box field, a closure capture or an array
  element: read off the uses;
- **its elements hold no references**: read off the type;
- **it is read in order**: always, a list has no other read. Only the
  direction differs: an accumulator is read from its last cons.

A list that is only walked needs no exclusivity at all: uncons is a view.
"Built once, never shared" (the brief) is "exclusive wherever it grows".

### 4.2 Where the decision is made

Per value, on the MLIR side, recorded in the value's type.

- **Per data instance (the frontend) does not work.** The frontend sees
  types, not sharing: it would have to buffer every `List Char` of the
  program, and a cons onto a shared tail then copies it, O(n) where the
  program wrote O(1) (`git show 903d127~1:findings/representation.md`,
  "a representation must never make a program asymptotically slower").
  The way out, a hybrid of cells and buffer segments (CDR-coding, unrolled
  lists, recalled), needs interior pointers whose segment header is found
  by alignment or a tag (excluded: references stay raw addresses), and a
  test of the cell kind at every match.
- **Per value squares with AGENTS.md's split.** The frontend decides what
  a type is: an unboxed sum or a box when its containment is cyclic
  (`compiler/src/IdrisMLIR/Frontend/Translate/Programs.idr:98-110`,
  `compiler/src/IdrisMLIR/Term.idr:336-339`), and its cell layout. That stays its decision, and
  the list shape is read off the declaration it emits (`consOf`), so the
  frontend does not change. Where a value of the type lives is a fact
  about the program, proved only in the owned stage, the category of
  idr-stack's frame cells (`lib/Stack/Pass.cc:1-12`) and of the `excl`
  grade. Unlike `idr.stack`, which only moves a cell, a buffer changes how
  every op on the value lowers, so the decision is a type and not a
  discardable attribute: no pass can drop it, and the verifier checks it.

### 4.3 The type and the runtime form

- **`!idr.seq<@T>`**, for `@T` list-shaped: two constructors, one without
  fields, one whose last field is `@T` and whose others are not (`consOf`
  generalized from one element field to several). The ops of lists keep
  their names on it: `idr.constant`, `idr.con`, `idr.match`, `idr.take`,
  `idr.field`, `idr.tag`, and the owned stage's `dup`, `drop`, `borrow`,
  `share`; their verifiers accept a seq where the declaration says `@T`
  in the tail of a cons whose result is the seq. Graded as any counted
  value: `!idr.excl<!idr.seq<@T>>`.
- **The buffer** is an array cell (`runtime/idris_rt.h:147-157`): header,
  capacity (the array's length), elements laid out as the cons's fields
  without the tail (`Layouts::element`). An element is one word
  (`memref<?xi32>` for `Char`) or several slots, as for arrays
  (`lib/Lower/Arrays.cc:1-19`).
- **The value** is a view: the cell, `start`, `length`. That is the array's
  memref descriptor (`Arrays.cc:81-94`, `arrayView`) with a dynamic
  offset: `memref<?xE, strided<[1], offset: ?>>`, so loads, subviews and
  dimensions are upstream's (`expand-strided-metadata` is already in the
  pipeline). Three words in registers. An empty list has no cell.
- **Growth**: a push with no room at the end it pushes to calls the
  runtime (`idris_rt_seq_grow`): a new array cell of twice the length (16
  at least), the elements copied with `memcpy` to the end opposite the
  push, the old cell released. Amortized O(1) per push. Upstream's
  `memref.realloc` lowers only to alloc, copy and free
  (`git show 903d127~1:findings/mutable-buffers.md` §4), and our cells are
  the runtime's, so it is a runtime function.
- **Direction.** A cons pushes at the head end, a builder (§4.4) at the
  other, so the buffer has room at both ends and a view is read
  head-first. `reverse` stays O(n) (moves into a fresh buffer) until stage
  3e adds a reversed view, `!idr.seq<@T, reversed>`, whose storage runs
  last-to-first: memref strides must be positive (`BuiltinAttributes.td:1050`),
  so direction is static, in the type, and lowering indexes from the end.
  With 3e's in-place slots, `reverseOnto` writes each element back where
  it was read, a store of a loaded value to the same address, and its loop
  only moves two bounds, which LLVM deletes (conjecture): reverse O(1).

### 4.4 Every operation

| operation | on a seq | cost (cells: today) |
| --- | --- | --- |
| `[]` | the empty view, no cell | O(1) (O(1)) |
| `x :: xs`, `xs` exclusive | write at `start - 1`, or grow | amortized O(1) (O(1), one cell) |
| `x :: xs`, `xs` shared | not a seq web: cells (§4.5) | — |
| match, uncons | `length == 0`; head a load; tail the view from `start + 1` | O(1) (O(1)) |
| `idr.take` (the value dies) | the tail inherits the reference; no count changes, shared or not | O(1) (a count test unless exclusive) |
| `idr.reuse` of a taken token | stage 3b: the token dropped, a push; 3e: written into the vacated slot when it is next to the tail | O(1) |
| `length` | the Prelude's recursion, a walk | O(n) (O(n)) |
| `reverse` | `reverseOnto`'s loop: uncons and push into a fresh buffer; 3e: O(1) | O(n) |
| `drop k` | a loop of view advances, which LLVM closes once the counter is a word (conjecture) | O(k) |
| `take k`, `splitAt k` | 3c: the prefix copied by a builder, the rest a view; 3e: the prefix a view of an exclusive input | O(k) (O(k) cells) |
| `xs ++ ys` | 3c: a builder copies `xs`, then is copied before `ys` if `ys` is exclusive; a shared `ys` keeps the web in cells | O(\|xs\|) |
| `map`, `zipWith`, `replicate`, `[a .. b]` | 3c: builders (below) | O(n) |
| `foldl`, walks | a loop over memory | O(n) |
| `foldr` | the recursion, over a view | O(n) |
| `pack` | 3d: one call converting the slice (simdutf's UTF-32 to UTF-8, already linked) | O(n), vectorized |
| `unpack` | the Prelude's loop conses from the last character: a push per character | O(n) |
| 2a's write of a list | 3d: the slice converted into the output buffer at once | O(n) |
| `dup`, `drop` | one count, one release of one cell; no element walk | O(1) (O(1); the release walks the cells) |

**Builders.** `x :: f xs` in tail position is a loop today through
idr-trmc's destinations (`Trmc.cc:1-26`). A destination is the address of
a field in a cell that will never move; a buffer moves when it grows. So
for a seq result idr-trmc makes the accumulator form instead: the clone
takes a builder, an exclusive seq it appends to (`idr.seq.append`), and
finishes at a tail that is not a cons of a self call by putting the
builder before that tail's value (`idr.seq.prepend`: free when the value
is `[]`, a copy of the builder before an exclusive value, otherwise a web
the decision kept in cells). The two are the only new ops. The copy is
proportional to what the loop produced, so `++` stays O(|xs|).

### 4.5 The decision, fallbacks and boundaries

A pass, **idr-seq**, after idr-rc and before idr-trmc
(`lib/Registration.cc:28-31`): it needs the `excl` grades, and idr-trmc
needs to know which results are seqs. It joins list values into webs
(union-find): a cons and its tail; a take's or a match's tail and the
scrutinee; a value and its borrow, dup, share, change of quantity; the
results of a match and what its regions yield; arguments and parameters,
results and returns; the field of an unboxed sum and its reads, per
declaration. A web goes in buffers unless one of these, each a reason in
an `idr-seq` `missed` remark (`findings/mlir-survey.md` item 1):

- `shared-tail`: a cons in it takes a tail that is not exclusive;
- `stored`: a value of it is a box's field, a capture of a boxed closure
  sum, an array element, or an argument of an unknown or external
  function;
- `counted-elements`: its elements hold references;
- `stack-cell`: a cons in it is idr-stack's;
- `builder-base`: a tail value a builder would be put before is shared;
- `trmc-shape` (3b only, lifted by 3c): a cons around a self call in tail
  position, which idr-trmc makes a loop today, so that no web regresses
  to a deep recursion;
- `clone-budget`: splitting a function between webs would exceed the
  clone budget.

Then the commit: a function whose list parameters or results meet webs of
both kinds is cloned (`$seq`), as exclusivity clones its mixed callers;
an unboxed declaration with a field in a seq web is cloned with the field
a seq (`Pair[Int, List Char]` for `gen`, `IORes[List Char]` for
`readAll`), as idr-defunctionalize makes declarations; the types are
rewritten. Static lists in a seq web become static array cells (count 0),
written by lowering as other static data.

There are no conversions inside the program: a web is all buffers or all
cells. A conversion from a buffer to cells is O(n) at a point that may be
O(1) in the program (a `head`, a cons onto a shared tail) and may run in
a loop; placing it only where the program already walks the whole list is
a later refinement, if a remark census asks for it. Compile-time
evaluation is unaffected: idr-eval lowers its calls with idr-lower alone,
before idr-rc and idr-seq (`lib/Eval/Eval.cc:283-287`).

### 4.6 The verifier invariant

Checked with the owned stage's rule, after every pass:

1. `!idr.seq<@T>`: `@T` is list-shaped and its elements hold no
   references.
2. Every `idr.con` or `idr.reuse` of `@T`'s cons whose result is a seq
   takes as its tail an exclusive seq (`!idr.excl<!idr.seq<@T>>`) or the
   static empty one; `idr.seq.append` and `idr.seq.prepend` take
   exclusive operands. A push therefore writes only slots that no other
   value reaches, by the grade, which is itself checked by provenance
   (`Verify.cc:203-224`).
3. A seq is never where a box is declared: a field, a capture, an
   element, a parameter typed with the box. This is type equality in
   every existing verifier (`idr.con`'s fields, `func.call`'s operands),
   not new code.

A growth that releases the old cell while a view of it lives is excluded
by the owned stage's existing rule: a view is used only while its owner
holds its reference, and a push consumes the owner. So the decision may be
wrong only in ways the verifier rejects: a shared tail, a stored seq, a
counted element. Each is a compile error at the op, never a write into a
buffer another list reads.

### 4.7 Counting

One cell for the whole list. A seq holds one reference to its buffer: a
dup is one increment, a drop one decrement, and the release frees one cell
without walking any element. `idr.take` of a seq changes no count, whether
the value was exclusive or not: the tail takes over the reference the
value held. The placement of dups and drops is idr-rc's as for boxes
(`lib/Ownership/Counts.cc:1-28`); idr-seq only renames the types.

A buffer keeps the slots its views have walked past until the last view
dies, where cells free each one as it dies. A walk that keeps a short tail
alive holds the whole buffer. An exclusive take can shrink the buffer when
fewer than a quarter of its slots remain, a copy paid for by the uncons
before it (amortized O(1)); a view of a shared buffer keeps it until the
view dies, bounded by a buffer that existed anyway (conjecture: no
benchmark shows it, and a test should).

### 4.8 Lists of counted elements

Excluded at first (rule 1). A view does not own its elements one by one:
two views of one buffer, a dup's copies, hold the same elements, and a
dropped view cannot tell which of its elements another view still holds,
so element references would need a count per slot or a live range per
buffer. The benchmarks' long lists hold `Char`, `Int` and `Double`;
`List String` and `List (List Char)` stay cells. A later rule could admit
a web whose every drop is of an exclusive view, which then releases its
range.

### 4.9 Lowering

`lib/Lower/Seqs.cc`, beside Arrays.cc, on the same helpers: element
layouts, word views, the runtime's array cell. A push lowers to a compare
of `start` with 0 (or of the end with the capacity), a store, and the
grow call on the cold path; exclusivity is static, so there is no count
test. Seq values pass through `scf.while` and function boundaries as their
three components (`Layouts::components`, `Layout.cc:189-209`).

## 5. Prototypes (measured)

**Method.** Each program was compiled with main's tools at bc6d454
(`tools/compile.sh`), the C with the pinned clang as `bench/run.sh` builds
it (`-O2`, the target CPU, no contraction). Inputs: fasta 250000;
reverse-complement and k-nucleotide on fasta 250000's output (2.54 MB);
spectral-norm 5500. Every variant prints the C's bytes (reverse-complement,
fasta, k-nucleotide) or digits (spectral-norm). A Python driver runs every
variant once per round, interleaved, output to `/dev/null`, and reports
the minimum and median wall time and the minimum user time from `wait4`.
The container's 4 CPUs were shared with five other lanes (load 2.6 to 9
during these runs, higher during earlier ones whose numbers are not
reported), so minima are reported, and a ratio is read within its own run.
valgrind could not count instructions: snmalloc does not initialise under
it.

**The variants.** Each changes only what its name says.

- *2a alone*: the benchmark, each `putStrLn (pack l)` replaced by a walk
  writing `l`'s characters with `putChar`: what the output buffer as the
  string builder gives.
- *2b by raising + 2a*: as 2a, plus what §3 fuses by hand: fasta's
  `take m (drop k alu2)` written as it is walked; reverse-complement's
  `splitAt 60` and `break` prefixes written as walked (with the rest given
  back, an extension of raising to one field of a pair). `gen`, `readAll`
  and `body` stay lists: their consumers meet them reversed.
- *2b in production order + 2a* (fasta): every line written as produced,
  `gen` included: what F7 plus raising would give.
- *3 + 2a*: every list that must exist in a buffer: base's `ArrayData`
  through `Data.IOArray.Prims`, what `Linear.Array` is written over
  (`libs/mlir-linear/Linear/Array.idr:13-19`): a `memref<?xi32>` of
  `Char`s, as a seq of `Char` would be, grown by doubling, accumulators
  pushed at one end and read back from the other; `take`/`drop` of the
  static list a slice; output by `putChar`. reverse-complement also over
  base's `Buffer`, one byte per `Char`, and (separately) with each line
  written by one `writeBufferData`.
- spectral-norm: the bench's `spectral-norm-linear` (arrays through
  `Linear.Array`) is what the contiguous form compiles to, vectorized,
  and with `--directive without=idr-vectorize` scalar; and the list
  lane's C over 24-byte list cells.
- k-nucleotide: the sequence packed once into a `String`, each key
  `substr i k` of it: a slice copied, where the benchmark packs `take k`
  of the list.

| program | variant | min wall | median | min user | RSS |
| --- | --- | ---: | ---: | ---: | ---: |
| fasta | C | 27.7 ms | 34.8 | 27.0 | 7.4 MB |
| | today | 59.1 | 72.8 | 53.9 | 7.4 |
| | 2a alone | 52.9 | 68.0 | 50.2 | 7.4 |
| | 2b by raising + 2a | 48.4 | 59.5 | 42.7 | 7.4 |
| | 2b in production order + 2a | 28.6 | 35.5 | 25.1 | 7.4 |
| | 3 + 2a | 29.7 | 36.8 | 26.7 | 7.4 |
| reverse-complement | C | 7.1 | 8.9 | 0.0 | 7.5 |
| | today | 100.8 | 125.9 | 62.4 | 58.7 |
| | 2a alone | 90.2 | 119.4 | 61.9 | 58.7 |
| | 2b by raising + 2a | 80.4 | 106.7 | 44.8 | 58.5 |
| | 3 (`Char`) + 2a | 37.0 | 53.8 | 14.0 | 39.4 |
| | 3 (bytes) + 2a | 35.8 | 46.0 | 24.4 | 11.4 |
| spectral-norm | C over arrays | 1433 | 1511 | 1374 | 7.4 |
| | C over 24-byte list cells | 1819 | 1894 | 1802 | 7.4 |
| | today (lists) | 1775 | 2038 | 1752 | 7.4 |
| | arrays, scalar loops | 1478 | 1584 | 1439 | 7.4 |
| | arrays, vectorized | 1504 | 1538 | 1438 | 7.4 |
| k-nucleotide | C | 336 | 360 | 75 | 96.8 |
| | today | 5955 | 6683 | 5120 | 81.4 |
| | sequence as slices | 4911 | 5307 | 3943 | 63.0 |

In a second reverse-complement run (load 7.5): C 6.4, today 89.8, bytes
with `putChar` 32.6, bytes with one write per line 28.8 ms. User times
are in ticks and noisy; C's below one tick reads 0.

**What the table says.**

- fasta loses its gap to C (59 → 30 ms against 28) with lines that are not
  cells, whether in a buffer or not at all. Raising, which cannot reach
  `gen`, takes 8.5% off 2a (52.9 → 48.4 ms): 18% of what 2a leaves to C.
- reverse-complement: buffers take it from 101 to 36 ms (RSS 59 → 11–39
  MB); fusion gives 11% over 2a. The rest to C's 7 ms is the program's
  character at a time input and output and the prototypes' byte-by-byte
  growth copies (conjecture: the runtime's `memcpy` growth and 3d's slice
  conversions take a further few milliseconds, not 5×).
- spectral-norm: the representation is 17% of today's time (1775 → 1478,
  C 1433), as the C pair shows (1819 → 1433). Vectorizing the contiguous
  form gains nothing here, as `bench/README.md` explains (64-bit index
  arithmetic). 2b's fusions (range into map, zipWith into foldl) touch
  O(n) of O(n²) work.
- k-nucleotide: slices instead of `pack (take k cs)` save 18%; the other
  82%, 15 times C, is the persistent `SortedMap` of strings against C's
  hash table, not lists.

**A compiler limitation met on the way (read and measured).** The first
version of the contiguous reverse-complement pushed through a helper
`push : Chars -> Int -> Int -> Char -> IO (Chars, Int)` whose body is an
`if` over two actions, called as `push acc cap len (comp c)` from the
mutually recursive `process` and `body`. After idr-simplify,
`body$raise$1` exists, but `body` itself survives, returning an action,
and is called from the continuation of `push`'s bind. Each character
goes through `io_bind` closures (02 and 08 dumps). The program ends
with "stack exhausted" after about a million characters, where the
stock Chez backend runs it to the end.

The same program with `push acc cap len c`, or with the branch written
inline, compiles to the loop. A valid program that ends with "stack
exhausted" is worth its own fixture and its own fix.

## 6. Staged plan

Each lane lands with `make check`, `make build`, `make test`,
`make test-idr` (and `make test-mlir-tools` for 3a's use of memref), never
leaves main miscompiling (the new path is behind the verifier and an
ablation switch), and states properties, not op sequences.

1. **2b-1: raising structural consumers.** Files:
   `foreign/idr/include/idr/Idr.h` and `lib/Dialect/Dialect.cc`
   (`Elimination`'s second form), `lib/Specialize/Raise.cc` (the
   binding-time test, `push` for a call), `Specializer.h`, `IdrOps.td`
   (the key attribute), `lib/Expect` (`builds-no-list`). Tests: lit cases in
   `tests/idr/specialize/` stating `builds-no-list` after `--idr-simplify`
   on hand-written producers and consumers (map, filter, range, early exit,
   a crashing producer that must not fuse); fixtures in
   `tests/programs/prelude/` (§3.4), diffed against Chez. Gate: no
   fixture changes output; compile times (`tests/compile-times.sh`) within
   10%; spectral-norm and fasta not slower. Risk: compile time and clone
   budgets on programs with many producers (bounded by the size guard and
   a raise that declines near the budget); a wider meet: sinking and
   case-of-case also move toward call consumers, in programs 2b does not
   fuse too, which `kSinkBudget` bounds and the compile-time gate measures.
2. **2b-2: output-op consumers** (with 2a's op): the two one-step folds
   (DRR, `lib/Dialect/Canonicalize.td`) and the op as a raisable consumer.
   Test: `builds-no-list=@Main.repeatFasta` on a fasta-shaped fixture.
   Gate: fasta at or below the 2b-by-raising row. Risk: none beyond 2b-1.
3. **3a: the seq type, its runtime and lowering, unused.** Files:
   `IdrOps.td` (the type, the two builder ops, the verifier rules),
   `lib/Dialect/Ops.cc` (`consOf` generalized; the ops' verifiers accept a
   seq), `lib/Ownership/Counting.cc` and `Verify.cc` (a seq is counted;
   rule 2), `lib/Lower/Seqs.cc` (new), `lib/Lower/Layout.cc` (components),
   `runtime/arrays.cc` and `idris_rt.h` (`idris_rt_seq_grow`). Tests:
   `tests/idr/seq/` lit cases on hand-written owned-stage IR, each lowered
   and run (`idris-mlir-cc`), and verifier negatives (a cons onto a shared
   seq, a seq stored in a box, a seq of strings). Gate: test-idr,
   test-mlir-tools. Risk: none to programs, since nothing makes a seq yet.
4. **3b: the decision for accumulators and walks.** Files:
   `lib/Ownership/Seq.cc` (new pass `idr-seq`: webs, reasons, cloning of
   functions and unboxed declarations, commit), `Passes.td`,
   `lib/Registration.cc` (the step after idr-rc), `lib/Expect`
   (`lists-in-buffers=@f`: every list value `@f` builds is a seq).
   Excludes `trmc-shape`. Tests: fixtures for each remark reason (the
   program right, the remark named); reverse-complement's shapes as a
   fixture with `lists-in-buffers=@Main.readAll` and `@Main.body`;
   `IDRIS_RT_LIVE=1` leak checks; the `--without=idr-seq` ablation in
   `bench/README.md`. Gate: reverse-complement at least 2× faster with
   RSS under 15 MB; fasta at the 3 + 2a row once 2a lands; no fixture
   changes output. Risk: the web analysis splitting functions too often
   (clone budget), and the owned-stage verifier meeting a lowering of
   take and reuse it never saw: 3a's negatives come first.
5. **3c: builders.** Files: `lib/Passes/Trmc.cc` (the accumulator form
   for seq results), `lib/Ownership/Seq.cc` (lift `trmc-shape`). Tests:
   map, replicate, range, take, `++` fixtures with `lists-in-buffers` and
   `constant-stack`. Gate: spectral-norm (lists) within 5% of the scalar
   arrays row; k-nucleotide's sequence a seq. Risk: `++` onto a shared
   second list (kept in cells by `builder-base`, which a fixture states).
6. **3d: strings and output over buffers.** Files: `lib/Lower/Strings.cc`
   (`pack` and `concat` over a seq), the runtime (`idris_rt_str_from_utf32`
   over simdutf, and 2a's write of a slice). Gate: reverse-complement
   below 25 ms (conjecture), fasta unchanged.
7. **3e: in-place slots, slice views, the reversed direction.** A take's
   token as a vacated slot that a push next to it fills; `take`/`splitAt`
   prefixes as views of an exclusive input, which needs a refined grade
   (an exclusive view that owns no free slot next to it); `!idr.seq<@T,
   reversed>`. Gate: reverse-complement in one buffer after `readAll`; a
   reverse fixture with `counted-loop`-style evidence that the loop is
   gone. Risk: the refined grade is a change to exclusivity's lattice.
8. **3f (optional): index spaces.** Walks and builders over a seq whose
   length is known, raised to `idr.array.fold`/`generate`, so that
   spectral-norm's list version is the linear version's loop nest
   (`lib/Lower/Loops.cc:1-28`). Only if a benchmark shows the need.

## 7. What this needs from the other lanes

- **Step 1 (precision in counting):** nothing is required. 2b runs before
  counting. Step 3 needs exclusivity only where a list grows, which the
  accumulators have today (§1); step 1's exclusive static pairs widen it
  to prefixes consed onto after a join (`'>' :: hdr`).
- **2a:** for 2b-2, its consumer as an op with the two one-step folds, not
  only as a lowering of `put_str (str.pack xs)`; for 3d, the same op
  lowered over a seq as one conversion into the output buffer.

## 8. Open questions

1. Is the knot rule of §3.3 the whole legality? It is derived from
   raising's and sinking's conditions; 2b-1's negative fixtures are its
   test, and a counterexample would be a bug in those conditions too.
2. Should the decision convert at boundaries instead of keeping a web in
   cells? Only where the program already walks the whole list; the
   `missed seq(...)` census over `tests/programs` and `bench/` would say
   whether the boundaries cost anything.
3. A `Char` takes four bytes in a seq where reverse-complement's are
   bytes: the bytes variant halves RSS again (39 → 11 MB) at the same
   speed here. Narrowing an element type by the range of everything
   written into a web is idr-narrow's question for buffers.
4. Space: does any program keep a short tail of a long buffer alive long
   enough to matter (§4.7)? A fixture with `IDRIS_RT_LIVE` and a large
   input would say.
5. Can 3e's refined grade be had without a new lattice value, by making a
   slice view's free room the property of the value it was cut from?
