<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the e-graph on real workloads

Status: written 2026-10-21 for D57 and D85 to D87
(`proposals/0000-mlir-native.md:973-986, 1232-1259`), on the owner's
request to check the e-graph design on real workflows rather than toy
terms ("let's try to answer the unknown unknowns, and try to run some real
workflows for the egraph checking", 2026-10-21), with parser combinators
as the headline workload ("it stress tests like every part of our
compiler", 2026-10-21, relayed by the coordinator). `speed.md` measured a
hand-written dense engine against egglog on one synthetic term. This file
runs both on the `idr` modules the frontend emits for every benchmark,
for three parser programs written for the purpose, and for the frontend
itself. It reverses nothing; where a finding bears on `egraph.md`,
`speed.md` or `one-engine.md` it says so in §5.

Grounds: *read* (path:line), *read (agent)* (read by this task's reading
agent at the place named, not re-read by me), *measured* (a command I
ran; the build, input and machine are those of §1), *recalled*,
*conjecture*. Ours at HEAD e96bb991 with the working tree. Machine: Apple
M2 Max (virtual), 8 cores, 32 GB, macOS, shared (load average 3.5 to 10
during the session); Apple clang 21.0.0 `-O2 -march=native`; the stock
Idris 0.8.0-1c630e67c on the pinned Chez in `.toolchain`; egglog 6b42f908,
the release build `speed.md` made. No C++ of ours, no LLVM and no MLIR
tool ran: the pinned toolchain's tools are not built here, and Homebrew's
LLVM 22.1.8 was not used. Every figure below is single-threaded.

## 0. In plain words

- **The frontend builds and emits on the stock host, the frontend
  included.** The fork in 1 min 51 s, the frontend in 11 min 53 s; the
  frontend then compiled itself to its module in 552 s at 6.7 GB
  (*measured*, §1.1). Every benchmark (30), three parser programs and the
  frontend were emitted; nothing was refused.
- **The workload is many tiny functions.** At emit, the 33 programs hold
  8,049 functions of 4.6 ops on average (median 3, p99 22, largest 736);
  the frontend holds 125,791 functions and 693,423 ops (median 3, p99 31,
  largest 4,287). Two thirds of the frontend's ops sit in functions of at
  most 10 ops. The largest match in the frontend has 77 cases, not tens of
  thousands. About 44-49% of ops float under the effect classification of
  `egraph.md` §2.1; at emit most of the skeleton is `idr.apply`
  (*measured*, §2).
- **Per function, at emit, the e-graph finds little, cheaply.** Case
  blocks are separate functions (`f.case0`), interface methods are
  zero-argument calls that return closures, and fields are case
  arguments, so one function's e-graph seldom sees a constructor meet its
  match. Today's patterns restated as rules (set A) resolve 1,864 applies
  to known closures over the 33 programs and 22,153 in the frontend, and
  decide no match the input did not already decide (*measured*, §3.1).
- **With callees inlined first (an approximation of idr-optimize), set A
  does real work**: 18% fewer nodes in what extraction keeps for the
  frontend, 44% fewer match results, 14,345 more matches decided, and
  155,586 case-of-case sites of which 22% (29% in the benchmarks) have
  arms that fold and arms that do not, which is where `egraph.md` §9 E9's
  per-arm choice matters (*measured*, §3.3).
- **The rule classes of `egraph.md` §9 that this IR can express (set B:
  E4 integer algebra, E5 string reassociation, E6 list theorems) found
  nothing extraction keeps**, on any program: 0 nodes over the 33
  programs, 86 of 3.4 million in the inlined frontend. They made every
  budget stop the input did not already make (42 after inlining, 31 in
  the frontend), and cost 64 times set A's time after inlining. Their worst real input is a Nat literal
  emitted as 64 chained `idr.big.add(_, 1)`: set A folds it, set B builds
  5,211 nodes in 67 ms for an answer that is a constant (*measured*, §3.2).
- **Parser combinators do not fuse inside a function.** A combinator is a
  closure passed as an argument; `<*>`, `<|>` and `>>=` apply parameters.
  In the fork's own parser library (7,132 specialized functions, 5.1% of
  the frontend's ops) the inlined e-graph made no apply's callee known
  (*measured*, §3.4). The laws (pure/`<*>`, map/map, `<|>` with `empty`)
  can fire only once a combinator is specialized on its closure
  arguments, across functions: the specializer's work, not saturation's
  (*conjecture*).
- **A soundness hole, found only on real code.** A case region binds its
  fields, not its refined scrutinee. Restated as an e-graph rule, today's
  in-arm eta (`con<C>(fields of x) = x`) put `C` into the scrutinee's
  class everywhere, and wrongly decided 1,347 matches in the frontend and
  17 in the benchmarks until each case was given a refined value. `egraph.md`
  §2.2 assumes the IR already binds one; at emit it does not (*measured*,
  §3.5).
- **Cost.** Set A on the whole frontend: 0.28 s at emit, 1.35 s after
  inlining, one thread; per function the median is 1.4 µs and p99.9 is
  60 µs; the largest e-graph has 2,534 nodes; 232-237 ns per node, build
  and extraction included. `speed.md` estimated 3-70 s of CPU and a
  single-function tail of 0.7-19 s; on this input the tail does not exist
  (*measured*, §4). egglog and the dense engine build identical e-graphs
  on ten real functions; the dense engine takes a sixth to a quarter of
  egglog's phase time on the structural rules, build and extraction
  included, and 2.3 times egglog's where associativity fires, since it
  lacks semi-naive matching. egglog on the whole frontend at once took
  500 s and 15.7 GB, nearly all of it loading the facts, for 1.4 s of
  saturation (*measured*, §4.3).

## 1. What was run

### 1.1 The frontend, built on the stock host

Copies under `/tmp/eg-workloads/src` of `compiler/`, `libs/`, `bench/` and
the Idris libraries the frontend's prefix needs (`third_party/Idris2/libs`);
every build directory there (*measured*, `scripts/build-*.sh`):

| step | command | time |
| --- | --- | --- |
| the fork, by the stock Idris | `idris2 --install idris-compiler.ipkg` (prefix `/tmp/eg-workloads/host`) | 1 min 51 s |
| the frontend, by the stock Idris | `idris2 --build idris-mlir.ipkg` | 11 min 53 s |
| its prefix, by the frontend | `idris-mlir-front --prefix … --install` prelude, base, mlir-linear, mlir-array | not timed |
| the fork, by the frontend (self) | `idris-mlir-front … --install idris-compiler.ipkg` | 133.7 s, 699 MB |
| the frontend's main, by itself | `idris-mlir-front … -p idris-compiler --core … -o … IdrisMLIR/Frontend/Driver.idr` | 551.6 s, 6.71 GB |

The self compile's phases (its `--timing`): checks 0.9 s, reachable
14.2 s, growth 95.7 s, translate 277.7 s, emit 105.2 s. The module is
70.8 MB of bytecode.

The frontend hands idris-mlir bytecode only (`compiler/src/IdrisMLIR/Emit.idr:5-7`,
*read*), whose `idr` entries only our C++ reads. One scaffold change, in
the `/tmp` copy only: `Emit.emit` also writes each top-level op's generic
form (`IdrisMLIR.MLIR.genericForm`, `compiler/src/IdrisMLIR/MLIR.idr:406-410`,
*read*) to a text file beside the module, and the program op with its
data table. The text is MLIR's generic form of exactly the ops the
bytecode holds (383 MB for the frontend).

### 1.2 Inputs

- **bench/**: all 30 programs with a `Main.idr`, their `packages` given.
- **Three parser programs** (`/tmp/eg-workloads/progs`, plain Idris in the
  subset both hosts compile, `%default partial` where base's `strIndex`
  is partial):
  - `json-comb`: a Parsec-style library (`Parser a` a record of
    `Input -> Int -> Res a`; Functor, Applicative, Monad, Alternative with
    a lazy right operand; `many`, `some`, `sepBy`, `between`, `chainl1`,
    `optional`, `eof`) and over it a JSON parser and an arithmetic
    expression parser. Built and run on Chez: its output agrees with
    `json-hand`'s on the test lines (*measured*).
  - `json-hand`: the same two parsers written by hand, recursive descent
    over the string and a position, no combinators.
  - `json-linear`: linear combinators after Krishnaswami and Yallop's
    typed algebraic parsing (*recalled*; PLDI 2019): the input is a
    quantity-1 `StringIterator` (`libs/mlir-linear`), read once; a parser
    carries its FIRST predicate and whether it accepts the empty input; a
    choice reads one character of lookahead held beside the iterator;
    numbers and strings are views (offsets) of the input. It type-checks
    on the stock host with its linearity; it cannot run there (its
    iterator's primitives are idris-mlir's, `libs/mlir-linear/Linear/String/Iterator.idr:38-41`,
    *read*).
- **The frontend itself**, as above: the stage-1 scale.

### 1.3 The model of the e-graph

`scripts/translate.py` reads the generic text and writes, per function,
the input of `egraph.md` §2's design:
- **Classification** by the op's declared effects, as the catalog of the
  dialect's declarations lists them (*read (agent)*, from
  `foreign/idr/include/idr/IR/*.td` and `foreign/idr/lib/IR/Func/Call.cpp:65-72`):
  *floating* (`arith`, `math`, `idr.constant`, `idr.con` of an unboxed
  type, `idr.closure`, `idr.suspend`, `idr.delay`, the pure scalar and
  string readers, and a call of a `total` callee, D13); the string and
  big-integer builders float too, as `egraph.md:304` proposes (L01 I2),
  though ODS declares an `Allocate` on their identity today; *unique*
  (`idr.lin.enter`, `idr.lin.use`: a node with its own identity);
  *ordered* (IO, guards, crashes, `idr.force`, `idr.apply`, which has no
  effect interface, a call of a partial callee); *region* (`idr.match`,
  `idr.match_lit`, the array ops); terminators.
- **The value graph.** Floating ops are hash-consed nodes; a leaf is an
  argument, a skeleton op's result, or a value from outside. A match's
  result `k` is a node `MATCHR(scrutinee, yield_k of each arm)`; a case's
  field `i` is `FIELD<C,i>(REFINE<C>(scrutinee))`, the projection of the
  scrutinee refined to the case (§3.5 says why the refinement is needed);
  the default region's argument is `DEFAULT<cases>(scrutinee)`; a literal
  case's argument is the literal.
- **The skeleton**: ordered ops, matches and terminators, their operands
  as roots, with the region tree.
- **Rule set A** (today's canonicalization patterns and folders restated,
  from the catalog of `foreign/idr/lib/IR/Canon/`, `Fold/` and `Ops*.cpp`,
  *read (agent)*): field of a known constructor (T1, R15); a match's result
  on a known constructor, a refined case, a default whose cases include
  the inner ones, or a literal, and on an enclosing match of the same
  class (R1); a match whose arms yield one value (R2); `arith` constant
  folds and identities (upstream's); big-integer folds within 64 bits
  and `big.add(x, 0)`, `big.to_int(big.from_sint x)` (T11, T12, F);
  `lin.use(lin.enter x)` (T5); constructor eta (T4, R16); `str.head` of
  `str.cons` (T9); a call of a total function whose body is one closure,
  constructor or call of its arguments is that op (leaf inlining, which
  idr-optimize's inliner does; it is what resolves an interface method's
  projection). The patterns that move ops into arms (SinkConsumer,
  SinkIntoRegions) are placement, which elaboration does: their sites are
  counted (§3.3), not rewritten. MoveOut (an array read and write fused
  across a world) and the effectful output rules are not modeled.
- **Rule set B**, the classes of `egraph.md:930-1004` this IR can state:
  E4 (commutativity and associativity of `addi`, `muli`, `big.add`,
  `big.mul`, commutativity of `andi`, `ori`, `xori`, `(x + y) - y = x` and
  `(x - y) + y = x` for words and Integer, `pred (x + 1) = x`); E5
  (associativity of `str.append` and of `Prelude.Types.String.(++)`, both
  ways); E6 (associativity of `Prelude.Types.List.(++)`,
  `reverse (reverse xs) = xs`). E1, E2, E3, E10 and E11 need what emit
  does not have (§3.6).
- **Saturation**: search every rule, apply, rebuild, until nothing changes
  or the node table reaches `16 × ops(f)` nodes (at least 64), `speed.md`'s
  lower budget. **Extraction**: greedy, a constructor or closure 10, a call
  20, a match result 5, a big or string op 8, others 1, constants and
  leaves 0; reported as the DAG reachable from the live skeleton's roots,
  a region being dead when its match is decided against it.
- **Inlining, approximated** (`scripts/inline.py`): the e-graph's points
  are after defunctionalization and inside idr-optimize
  (`foreign/idr/lib/Transforms/Pipeline.cpp:71, 93, 116`;
  `foreign/idr/lib/Transforms/Optimize/Optimize.cpp:51-74`, *read*), where callees are inlined and a
  known closure's apply is a call. The approximation inlines a call of a
  module function, or an apply of a closure built in the same function
  with all its arguments, when the callee has at most 64 ops, is not on
  the inlining stack, and the caller stays under 2,000 ops, eight levels
  deep. It does no specialization, redirect or SCCP. "-inl" below means
  this.

### 1.4 The engines

- **Dense** (`/tmp/eg-workloads/dense/{core.hpp,eg.cpp}`, 1,583 lines with
  the scripts): the engine `speed.md` §2 describes, generalized to the
  `idr` signature: kinds interned as (role, attribute, attribute), nodes in
  one array with children in CSR, an array union-find with the smaller
  id the representative, one open-addressing hash-cons, rules as C++
  over a per-iteration class-to-nodes index. It is naive (every rule
  re-matches every node each iteration), unlike `speed.md`'s semi-naive
  one.
- **egglog** (`scripts/to_egglog.py`): the same rules generated per arity
  (constructors `Con2`, `M5`, …; `TagOf` and relations for the arms),
  without the attribute folds and the context rule, whose egglog form
  would differ; the dense engine runs the same subset as sets `s` and
  `sb`.
- **Agreement** (*measured*): on ten real function and rule-set pairs
  (deriv's `Main.mul`, k-nucleotide's `Main.frequencies`, meteor's
  `Main.search.case0.case1.case0`, json-hand's `Main.line.case0`,
  json-comb's `Main.line`, each inlined, `s` and `sb`), the two engines
  hold the same number of nodes at saturation, and after iterations 1, 3
  and 6 on the one function checked iteration by iteration (922 and 922
  after 6).

## 2. The workload

*measured*, `scripts/agg.py` over `translate.py`'s per-function counts.

| input | functions | ops | ops per function: median, p90, p99, max | floating | unique | ordered | region | terminators |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 30 bench + 3 parsers, emit | 8,049 | 36,791 | 3, 8, 22, 736 | 43.6% | 5.4% | 14.3% | 5.1% | 31.6% |
| the frontend, emit | 125,791 | 693,423 | 3, 9, 31, 4,287 | 48.0% | 6.0% | 10.4% | 6.1% | 29.3% |
| the frontend, -inl | 125,791 | 5,254,168 | 6, –, 801, 4,287 | 48.6% | 9.8% | 3.2% | 12.0% | 26.4% |

- **The tail.** In the frontend at emit, functions above 10 ops hold
  34.1% of the ops, above 100 ops 9.6% (230 functions), above 1,000 ops
  2.2% (8 functions). The largest: `TTImp.WithClause.getMatch` (4,287 ops,
  968 constructions, 586 matches, region depth 16),
  `Core.Normalise.Convert.convGen_Convert_NF` (2,583),
  `TTImp.PartialEval.getSpecPats.case0.mkRHSargs0` (1,998),
  `Core.Unify.unifyBothApps` (1,957). The largest `idr.match` has 77
  cases, the largest `idr.match_lit` 34. Region depth: median 0, p99 3,
  maximum 28. Among the benchmarks one function is large: deriv's
  `Main.mul`, 736 ops, 151 matches, depth 14 (43% of its program).
- **Constructions and matches.** The frontend at emit: 74,450 `idr.con`,
  42,623 matches, 66,189 `idr.apply`, 160,251 `idr.call` (155,564 of a
  total callee), 58,036 closures (`closure`, `suspend`, `delay`), 1,192
  `force`. After inlining: 856,917 constructions and 631,074 matches.
- **What emit looks like** (*measured* in the text; the frontend's code,
  *read (agent)*):
  - each `case` block is a function of its own (`Main.nestAux.case0`), so
    a case-of-case is a call of a case function on a match result;
  - an interface method is a zero-argument call returning a closure, then
    an apply (`call @"Prelude.Interfaces.map[…]"()`, `idr.apply`);
  - IO is a function of `!idr.world`, so running an action is an apply;
  - `idr.field` and `idr.tag` are not emitted; a case's fields are its
    region's arguments;
  - a one-field record is erased to its field: json-comb's `Parser a` is
    the function `Input -> Int -> Res a` itself;
  - `Lazy` is `idr.delay` and `idr.force`; Prelude's `||` and `&&` take a
    lazy right operand, so hand-written code makes delays too.

## 3. What the e-graph found

Three runs per program: `none` (the input hash-consed: CSE), `A` and
`A+B`, budget 16 nodes per op. "Decided" counts matches whose arm the
classes or an enclosing match fix; "applies known" counts applies whose
callee class holds a closure; "keys" counts skeleton operands whose class
holds a constructor, closure or constant. *measured*, `scripts/run-all.sh`,
`run-inl.sh`, `agg2.py`.

### 3.1 At emit

| 33 programs, emit | none | A | A+B |
| --- | --- | --- | --- |
| nodes | 54,050 | 56,221 | 57,443 |
| decided / live matches | 40 / 1,668 | 40 / 1,668 | 40 / 1,668 |
| applies known | 3 | 1,864 | 1,864 |
| keys (E8) | 4,812 | 7,057 | 7,057 |
| kept: nodes / calls / closures / match results / constructions | 41,830 / 7,240 / 3,025 / 1,856 / 2,134 | 40,496 / 5,219 / 5,037 / 1,232 / 2,087 | the same as A |
| time, all functions; the largest | 13.4 ms; 101 µs | 16.8 ms; 126 µs | 19.0 ms; 570 µs |

The frontend at emit: nodes 1,141,543 / 1,184,229 / 1,418,978; applies
known 10 / 22,153 / 22,153; keys 63,047 / 100,285 / 100,284; decided 539
in all three; kept nodes 915,750 / 874,212 / 874,280 (B's 68 more are
greedy extraction's ties); calls kept 145,880 / 112,657; match results
41,878 / 24,891. Set A's work at emit is leaf inlining of method
projections (68,711 productive matches in the frontend) and match results
whose arms agree (15,701).

### 3.2 Set B: what the algebra found, and what it cost

| | 33 programs -inl, A | A+B | the frontend, A | A+B | the frontend -inl, A | A+B |
| --- | --- | --- | --- | --- | --- | --- |
| nodes | 209,590 | 575,444 | 1,184,229 | 1,418,978 | 5,825,101 | 6,100,570 |
| budget stops | 0 | 42 | 3 | 34 | 4 | 4 |
| engine time | 51 ms | 3,275 ms | 0.28 s | 1.37 s | 1.35 s | 1.65 s |
| largest function | 280 µs | 858 ms | 1.7 ms | 66.9 ms | 7.3 ms | 6.2 ms |
| kept nodes | 117,024 | 117,024 | 874,212 | 874,280 | 3,411,445 | 3,411,359 |

(The frontend's 3 and 4 stops under A, and 3 of its 34 under A+B, are
functions whose input already exceeds the budget: two ops and seventy
arguments.)

- **Nothing extraction keeps.** B's rules fired often (the inlined
  frontend: 104,954 commutations, 119,716 associations, 118,469 string
  reassociations, 432 list-append associations, 79 cancellations), and
  changed no decided match or known apply anywhere, the keys by one (a
  function stopped at the budget before a rule of A fired), and the kept
  nodes by at most 86 of 3.4 million. The algebra E4 to E6 describes is
  rare in these programs: the arithmetic that exists is positions,
  counters and masks with few constants, and no program calls
  `length (map f xs)` or `reverse (reverse xs)` in one function.
- **Where it explodes.** Every budget stop of A+B is associativity and
  commutativity meeting constant folding on a chain:
  - `IdrisMLIR.Ids.len17to128` (446 ops): a Nat literal emitted as 64
    chained `idr.big.add(_, #idr.big<1>)`. A folds it to one constant
    (one link per iteration: the frontend's longest set-A run is 97
    iterations); A+B builds 5,211 nodes (11.7 per op) in 67 ms.
  - meteor-contest's `Main.search.case0.case1.case0` (inlined, 1,066 ops:
    23 such `big.add` links, 21 `addi`, 10 `muli`, 122 constants): 17,056
    nodes at the budget in 8 iterations, 42 million associativity matches
    enumerated, 0.86 s, kept nodes unchanged. Without the constant folds
    (set `sb`) the same function saturates at 575 nodes.
  - json-hand's position arithmetic (`i + 1`, `i + k`), inlined: 22
    functions at the budget; the program takes 580 ms under A+B and
    5.5 ms under A.
- **A per-rule match cap is not a stop condition.** With 1,000 matches per
  rule per iteration and no rotation, the meteor function "saturated"
  falsely at 1,403 nodes: the same first 1,000 matches each iteration
  added nothing new. `speed.md` §4's back-off needs a scheduler that
  rotates, as egg's bans do.

### 3.3 After inlining: set A's work, case-of-case, sharing

| 33 programs -inl | none | A |
| --- | --- | --- |
| decided / live matches | 4,440 / 20,753 | 5,219 / 19,962 |
| applies / forces known | 317 / 1,283 | 1,269 / 1,283 |
| keys | 37,253 | 41,736 |
| kept nodes / constructions / calls / closures / match results | 136,572 / 14,309 / 5,113 / 10,208 / 24,055 | 117,024 / 13,835 / 4,094 / 10,640 / 15,200 |

The frontend -inl: decided 103,063 → 117,408; live matches 500,124 →
484,452; applies known 13,157 → 40,351; keys 709,411 → 841,693; kept
nodes 4,182,760 → 3,411,445 (−18%); constructions 440,492 → 405,103;
calls 300,075 → 255,152; match results 571,353 → 317,281 (−44%).
Productive matches per rule (the frontend -inl): match results whose arms
agree 160,446; `lin.use(lin.enter)` 140,039; known-case 76,949; big
folds 44,162; leaf inlining 36,456; eta 17,880; arith folds 2,122 and
identities 466; field of a known constructor 0 (every field is now read
through a refinement, §3.5).

- **E9, case-of-case per arm.** A live, undecided match whose scrutinee's
  class holds another match's result: 7,726 sites in the 33 inlined
  programs after A (4,881 where every inner arm yields a known
  constructor or literal, so a copy always folds; 2,240 mixed; 605 where
  none does), 155,586 in the inlined frontend (64,886 all fold, 34,877
  mixed, 55,823 none; 186,877 arms fold, 118,179 do not). Today's
  SinkConsumer copies the consumer into every arm when any feeds it
  (`foreign/idr/lib/IR/Canon/CaseOfCase.cpp:43-177`, *read (agent)*); the
  mixed sites (29% and 22%) are where `egraph.md` §9 E9's per-arm
  copy-or-join pays, and it is a skeleton decision with a local cost, not
  saturation.
- **E7, sharing.** Hash-consing merged 14% of constructions at emit (2,502
  to 2,156), 60% after inlining (36,081 to 14,408), 17% in the frontend
  and 47% in the inlined frontend. Most are copies in sibling arms (match
  compilation and inlining duplicate arm bodies), which elaboration
  places once per arm; how many are two constructions on one path, where
  counting can prefer two cells, was not measured.
- **E8, keys.** The keys counted above appear through leaf inlining (a
  fact of the call graph) more than through a class within one function.

### 3.4 Parser combinators

Counted over the parser functions only (`Combinators.*`, `LinearParser.*`
and the parsers of `Main`), *measured*:

| emit | functions | ops | applies | closures | matches | linear ops |
| --- | --- | --- | --- | --- | --- | --- |
| json-comb | 405 | 1,713 | 361 | 199 | 87 | 0 |
| json-hand | 68 | 599 | 74 | 9 | 59 | 0 |
| json-linear | 463 | 2,412 | 278 | 203 | 173 | 104 |

- At emit, set A made 79 of json-comb's 361 applies known (method
  projections: `pure`, `map`, `<*>` of the Parser instance), 16 of
  json-linear's 278, 39 of json-hand's 74.
- After inlining and A, json-comb's parser functions keep 418 skeleton
  ops, 240 live matches, 938 closures and 15 applies known; json-linear's
  keep 588 skeleton ops and 1,249 live matches (592 matches are decided
  before any rule, by literal cases whose argument is the literal; the
  likely cause is the lookahead character tested again inside the
  alternative it chose, *conjecture*; A carried 426 of those decisions
  into the match results); json-hand's,
  inlined most deeply, 1,725 skeleton ops, of which A resolved 279
  applies, and in the whole program 777 forces meet their delays (`||`
  and `&&`).
- **The laws do not fire within a function.** `pure f <*> p` becomes a
  known `Ok` only where the closure `pure f` builds is applied in the
  function that built it; here the composed parser is a top-level value
  (`member`, `value`), applied inside `<*>`'s lambda on a parameter. The
  same holds for map/map and for `<|>` with `empty`. In the fork's own
  library, `Libraries.Text.Parser` (7,132 functions after
  monomorphization, 35,598 ops at emit, 3,809 applies, 2,392 closures;
  its `Grammar` is `MkGrammar : (Input state tok -> ParseResult …) -> Grammar …`,
  `compiler/idris/src/Libraries/Text/Parser/Core.idr:62-65`, *read*), the
  inlined e-graph made 0 applies known; A still cut its kept nodes by
  21% (303,432 to 239,965) and its match results from 92,241 to 30,645,
  and left 33,071 case-of-case sites with arms that fold and arms that do
  not in equal number (26,001 and 25,834).
- **What would fuse them is specialization on closure arguments**
  (*conjecture*): defunctionalization makes every closure a constructor
  of a closed dispatch sum, idr-optimize's redirect specializes "a call
  whose arguments are known constructors"
  (`foreign/idr/lib/Transforms/Optimize/Optimize.cpp:68-70`, *read*), and
  in the specialized combinator the laws are known-case folds that set A
  already has. That is Parsley's staging (Willis, Wu, Pickering, ICFP
  2020) and flap's (Yallop, Xie, Krishnaswami, PLDI 2023) done by the
  compiler's specializer (*recalled*, neither re-read); it was not run
  here. Until then, against the hand-written parser, the combinator
  version keeps its closures and applies: 361 applies against 74
  (*measured*).
- **The linear variant** costs no more e-graph work than the others
  (json-linear-inl: 3.5 ms for 679 functions under A) and its linearity
  is untouched by A (its 104 linear ops are unique nodes; the round trip
  fired 7 times). Whether elaboration keeps it on one path was not
  tested (§5.3).

### 3.5 Three examples from real functions

1. **Eta needs a refined value** (json-comb,
   `Combinators.(<|>_Alternative_Parser).case0[Integer]`, *measured*):

   ```mlir
   %13 = "idr.match"(%4) <{cases = array<i32: 0, 1>}> ({}, {
     ...                       // Fail: run the lazy right parser
   }, {
   ^bb0(%10: !idr.big, %11: i64):
     %12 = "idr.con"(%10, %11) <{tag = 1 : i32}> : (!idr.big, i64) -> (...)
     "idr.yield"(%12)          // Ok x j, rebuilt
   })
   ```

   With fields read as `field<Ok,i>(%4)`, eta equates `%12` with `%4`,
   the class of `%4` then holds `Ok`, and the match on `%4` is "decided" to
   `Ok`: wrong, `%4` may be `Fail`. Over the frontend this rule decided
   1,347 matches it had no right to (539 before saturation, 1,886 after),
   17 in the benchmarks. Giving each case the scrutinee refined to it
   (`FIELD<C,i>(REFINE<C>(x))`) makes eta yield the refined value; the
   match stays live.
2. **`if` is case-of-case** (json-comb, `Combinators.eof`'s lambda,
   inlined): `arith.cmpi sge` and `extui`, an `idr.match_lit` whose arms
   build `True` and `False`, and an `idr.match` on that Bool whose arms
   build `Ok () i` and `Fail`. Both inner arms yield known constructors,
   so a copy of the outer match into each folds: no Bool, one
   `match_lit` on the comparison. 4,881 of the 7,726 sites are of this
   all-fold kind.
3. **A method projection resolved** (json-comb,
   `Combinators.optional[Char]`'s delayed `pure Nothing`): at emit
   `call @"Prelude.Interfaces.pure[…]"()`, `idr.con` (Nothing),
   `idr.apply`; the projection's body is one `idr.closure`, so the apply's
   callee is known and, inlined, the function is one
   `idr.closure @"Combinators.pure_Applicative_Parser[…].lam…"(%nothing)`:
   the dispatch is gone and the parser is still a closure.

### 3.6 What could not be measured at emit

- **E1, E2** need movement (two placements held, sinking per arm); the
  model holds values, and placement (elaboration) was not built.
- **E3** needs interval analysis seeded from `Fin n`, which the model
  does not have; 23 `check.in_bounds` exist across the benchmarks.
- **E10** needs region terms over the generating ops (9 `idr.tabulate`).
- **E11** needs a partial order per resource in the skeleton.

## 4. Cost

### 4.1 Distribution

Per function, dense engine, *measured*:

| input, set | total | median | p99 | p99.9 | max | ns per node | largest e-graph |
| --- | --- | --- | --- | --- | --- | --- | --- |
| frontend emit, none | 0.22 s | 1.2 µs | 7.5 µs | 24 µs | 1.1 ms | 189 | 2,531 |
| frontend emit, A | 0.28 s | 1.4 µs | 11.4 µs | 60 µs | 1.7 ms | 237 | 2,534 |
| frontend emit, A+B | 1.37 s | 1.5 µs | 17.5 µs | 1.36 ms | 66.9 ms | 962 | 5,231 |
| frontend -inl, A | 1.35 s | 2.1 µs | 181 µs | 382 µs | 7.3 ms | 232 | 2,534 |
| frontend -inl, A+B | 1.65 s | 2.2 µs | 235 µs | 536 µs | 6.2 ms | 271 | 2,569 |

Times include building the e-graph, the skeleton's reading and
extraction. The maxima under A are noise on a shared machine (a 15-node
function at 1 ms); the largest functions by nodes take 0.3-0.75 ms. The
five slowest functions hold 1-1.5% of set A's time, 20% of A+B's at emit
and 1% after inlining.
Memory: the largest per-function arena 112-237 KB; the engine process on
the inlined frontend 643 MB, almost all of it the parsed input.

### 4.2 Against the frontend

Set A over the whole frontend costs 0.28 s at emit and 1.35 s after
inlining, on one thread, against the frontend's own 551.6 s (*measured*);
across 8 threads it would be a fraction of a second (*conjecture*). Set A
made 0.06 new nodes per op at emit (42,686 over 693,423 ops) and 0.007
after inlining (35,826 over 5,254,168); under A no function stopped at
the budget but those whose input already exceeded it.

### 4.3 egglog against the dense engine

Whole programs, inlined, egglog's search, merge and rebuild times from
`--save-report`, against the dense engine's per-function total (which
includes the build and extraction egglog's figure leaves out), *measured*
(`scripts/egglog-cmp.sh`):

| program | set | egglog phases | of which rebuild | dense | egglog process, peak |
| --- | --- | --- | --- | --- | --- |
| json-comb-inl | s | 9.7 ms | 89% | 2.3 ms | 0.22 s, 168 MB |
| json-linear-inl | s | 18.4 ms | 93% | 3.0 ms | 0.38 s, 262 MB |
| json-hand-inl | s | 27.5 ms | 91% | 4.7 ms | 0.74 s, 416 MB |
| deriv-inl | s | 4.8 ms | 90% | 0.9 ms | 0.08 s, 77 MB |
| qsort-inl | s | 11.1 ms | 91% | 2.8 ms | 0.34 s, 253 MB |
| k-nucleotide-inl | s | 14.2 ms | 87% | 3.0 ms | 0.29 s, 225 MB |
| k-nucleotide-inl | sb | 23.2 ms | 84% | 52.7 ms | 0.30 s, 223 MB |
| meteor-contest-inl | sb | 19.0 ms | 86% | 3.2 ms | 0.29 s, 226 MB |

- On the structural rules the dense engine takes a sixth to a quarter of
  egglog's phase time, build and extraction included; egglog's time is
  rebuild, as `speed.md` §1.3 found on eggcc's small e-graphs.
- Where associativity fires (k-nucleotide, `sb`), the naive dense engine
  re-enumerates every associativity match each iteration (94,851 in one
  function) and loses 2.3 times; semi-naive matching is not optional once
  B runs.
- egglog's process time is dominated by reading the program (the facts),
  0.08-0.74 s.
- **The whole frontend at emit, set `s`, in one egglog e-graph**: 979,642
  rows (the dense engine's 1,175,857 per-function nodes, constants not
  shared across functions), 4 iterations, phases 1.42 s of which rebuild
  1.27 s, but 500 s of process time and a 15.7 GB peak footprint, nearly
  all of it reading and inserting the 1.2 million facts. The dense engine
  does the same work, build and extraction included, in 0.29 s.

## 5. What real workloads confirm, contradict, and leave open

### 5.1 Confirmed

- The effect classification of `egraph.md:304` leaves about half the ops
  floating (43.6-48.6%), and the region skeleton is small after inlining
  (ordered 3.2%).
- A dense, specialized engine on real per-function e-graphs costs what
  `speed.md` §2.2 measured in cache: 232-237 ns per node under A (its
  75-230 ns, without build and extraction).
- A node budget is the stop that matters, and one rule family can spend
  it: of the 76 budget stops under A+B, 73 are associativity with
  constant folding (the other 3 exceed the budget on input);
  `speed.md` §0's "one rule (associativity of `Mul`) produced 91% of all
  matches" holds on real code.
- Case-of-case per arm (`egraph.md` §9 E9) is real and frequent: 29% of
  sites mixed in the benchmarks, 22% in the frontend.
- The two engines build the same e-graph from the same rules on real
  functions, and egglog's phase time is 84-93% rebuild (`speed.md` §0:
  "it is mostly not the join").

### 5.2 Contradicted

- **`egraph.md` §2.2, "a case binds its refined value"** (`egraph.md:46,
  353-360`). At emit a case binds its fields only; a global e-graph over
  that form makes the in-arm eta (R16) unsound: 1,347 wrong decisions in
  the frontend. The refined value (G DP-37) is a prerequisite of the
  e-graph, as a node if not as an IR value.
- **`speed.md` §5's tail.** It assumed the largest function is a match of
  tens of thousands of cases, 1.6M-13M nodes, 0.7-19 s on one core
  (`speed.md:100-103, 562-567`). At HEAD the frontend's largest function
  has 4,287 ops and its largest match 77 cases; under A its largest
  e-graph has 2,534 nodes and no function takes more than a few
  milliseconds. Its 3-70 s of CPU is 0.28-1.35 s measured.
- **`speed.md` §5's budget arithmetic** (16-64 nodes made per op,
  `speed.md:555`): A makes 0.007-0.06 new nodes per op; only B reaches
  the budget, and gains nothing when it does.
- **`egraph.md` §9's Tier 2 algebra (E4, E5, E6) has no measured payoff
  on these workloads**: 0 decided matches, known applies or kept nodes
  gained over 33 programs and the frontend, at 64 times A's time after
  inlining and every budget stop.
- **The parser-combinator expectation**: combinator laws do not fuse in a
  per-function e-graph, inlined or not (*measured*); specialization on
  closure arguments would expose them to A (*conjecture*).

### 5.3 Still unknown

- **The real input.** The e-graph runs after defunctionalization,
  specialization and idr-optimize's inlining, which no tool here could
  run; the "-inl" form approximates inlining and known-closure applies,
  nothing else. After defunctionalization there are no applies or
  closures, so the floating share, E8 and the parser findings will move.
- **Today's patterns against A's fixpoint.** A saturated is an upper bound
  of what the greedy canonicalizer reaches; how much below it greedy
  rewriting stops was not measured.
- **Elaboration**: placement, its cost, and whether a linear value stays
  on one path (`egraph.md` §2.3 item 4) were not built.
- **E7's split** of merged constructions into same-path and sibling.
- **A semi-naive dense engine on B**, and a rotating per-rule cap.
- **The pinned toolchain**: no MLIR tool of the pin read these modules.

## 6. Scaffolding

Outside the repository, in `/tmp/eg-workloads`, not committed: `src/`
(the copies, with the text-writing patch in `compiler/src/IdrisMLIR/Emit.idr`
and `Frontend/Program.idr`), `scripts/` (`build-fork.sh`, `build-front.sh`,
`build-prefix.sh`, `emit.sh`, `self.sh`, `mlirparse.py`, `translate.py`,
`inline.py`, `to_egglog.py`, `run-all.sh`, `run-inl.sh`, `egglog-cmp.sh`,
`agg.py`, `agg2.py`, `eggreport.py`, `show.py`), `dense/` (the engine,
sha256 of `eg.cpp` da719ed2…, `core.hpp` 26e2435e…), `progs/` (the three
parser programs), `emit/<program>/` (bytecode, text, Core, timing),
`eg/` (the engine's inputs) and `out/` (every per-function table).
