<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: rules found by offline synthesis, run on our primitives

Status: written 2026-10-21. Research for D57 ("nasty, ridiculous
unintuitive optimizations ... once we have the representation, the search
could be trivial", `proposals/0000-mlir-native.md:973-986`) and for
`design/egraph.md` §10.3, which names rule synthesis in the manner of Ruler
as research ("rules found offline from the runtime's semantics, checked by
§3.5's search, committed into the specification; a synthesizer kept in the
tree would be Idris (D15)", `egraph.md:1058-1061`). Framed by D106 and D107
(`proposals/0000-mlir-native.md:1557-1592`), which the owner ruled while
this ran: the e-graph is narrow and built in C++ from MLIR's own
mechanisms; its rules are today's local patterns with the choice per arm;
algebra rules are only one-way and narrowly triggered, because on real
code free-running algebra found nothing extraction kept and caused every
budget stop (`workloads.md` §3.2, `:301-330, 586-589`); rules and laws are
written once in the dialect's Idris specification and generated to each
side. So this file answers: which synthesized rules are one-way
improvements worth having as triggered rules or folds, how they would
enter the specification, and how they are checked. It reverses nothing.

Grounds: *measured* (a command I ran, with its input; machine and builds
below), *read* (a path:line or section I read), *recalled*, *conjecture*,
*decision* (a ruling Dn). Ours at HEAD e96bb991 with the working tree.

Machine: Apple M2 Max (virtual), 8 cores, 32 GB, macOS, shared with other
work. Ruler/Enumo at uwplse/ruler 7ed456de (2025-06-05; the
egraphs-good/ruler URL no longer resolves), built with rustc
1.101.0-nightly (2026-10-08), release; three small patches of mine, all in
`/tmp`: z3 removed from its manifest (my validators replace it), the two
merge assertions turned into counters (so an unsound merge is counted, not
fatal), and empty rounds allowed (a binary-only language has no
even-sized terms). Host Apple clang for C++. z3 5.3.1 from PyPI in a
`/tmp` virtualenv. Nothing was built or run in the repository; nothing of
LLVM was built (the checker links the pinned `libLLVMSupport.a` that
`.toolchain/build/typecheck-llvm/lib` already holds).

## 0. In plain words

- **It runs, and it finds hundreds of rules per domain in about a
  minute.** Ruler's Enumo, given our ops' meaning, finds 456 rules on Int8
  (exhaustively proven at 8 bits) in 56 s, 575 on Bits8 in 95 s, 556 on
  Integer in 63 s, 145 on the char conversion in 0.7 s, 25 on strings,
  2,256 on shifts at depth 7 in 353 s. Almost all are new against today's
  folders (410 of 456 on Int8), because our folders fold only constants
  and a handful of identities.
- **Few are worth keeping under D106.** About a quarter improve in one
  direction under a cost read off our lowering; up to 31% are degenerate
  (`(shr ?a ?a)`, `(mod ?a ?a)`; 20% on Int8) and no program writes them; and
  `workloads.md` measured that free-running algebra keeps nothing on real
  code. What survives is a short list of **constant-triggered strength
  reductions that exist only because of our semantics**: Euclidean
  division and modulus by a power of two become a shift and a mask
  (false for C's truncating `/` and `%`, so no upstream pattern has them),
  a total shift by a negative constant becomes the shift the other way, a
  scalar-value test on a value masked below 2^11 disappears. Each is a
  one-way rule triggered by one op with a constant operand: a fold or a
  narrow pattern, exactly D106's shape (§4).
- **Search by sampling is not sound, and the gap is large at 64 bits.**
  Of 508 Int64 rules that cvec matching plus 4,096 random samples
  accepted, z3 refutes 60 (12%) and cannot decide 22; one million more
  random samples through the folder's own C++ find none of the 60. The
  counterexamples sit at composite edge values no sampler draws (a shift
  amount of `MIN + 2`, small negative amounts), which at 8 bits are 1 in
  256 and get found. At 8 bits the same pipeline admitted 94 false rules
  of 567 with Ruler's corner-value samples alone, 35 of 483 with 64
  random rows, and none with 4,096 (§3).
- **Partiality modelled as an undefined value breaks the search.** With
  Euclidean `div`/`mod` at depth 7, Ruler's e-graph merged classes whose
  sampled values disagree 36.9 million times and learned nothing at that
  depth, even with equivalence-only validation; without the partial ops,
  zero. Our IR does not have that state: the guard returns the divisor
  refined (`idr.check.nonzero`, `IdrCheckOps.td:99-101`), so a division
  is a total function of an Int and a NonZero. Modelled that way, the
  same domain learned 513 rules to depth 6 (§3.4).
- **Entering the compiler**: as one-way rules in the specification's rule
  language, triggered by their root op and constant, each with its
  evidence: exhaustive at 8 bits plus SMT at every width through the D41
  template instantiated over SMT terms (so the encoding is not a second
  meaning); sampling against `runtime/` only as a regression check, and
  as the stated trust for runtime primitives no decision procedure
  covers. No synthesizer in the tree for P0 (§5).

## 1. What was run

### 1.1 The domains and their meaning

Each domain is a Ruler language whose interpreter is the op's one meaning,
taken from where it lives today:

- **Fixed-width integers** (Int8 and Bits8 as the 8-bit stand-ins, Int64;
  the dialect has one signless type and one op per signedness,
  `IdrScalarOps.td:14-17`). `+ - * & | ^` wrap (`arith`, emitted by
  `Emit/Operations.idr:211-219`). Division and modulus are Euclidean for
  signed and the naturals' for unsigned, guarded nonzero
  (`IdrScalarOps.td:20-52`); their meaning is `idrisDivMod`
  (`foreign/idr/lib/IR/Ops.cpp:205-223`). Shifts are total, a signed
  negative amount turns the direction, from the width up only the fill is
  left (`IdrScalarOps.td:54-91`; `idrisShift`, `Ops.cpp:252-274`). The
  char conversion is the scalar-value test (`foldToChar`,
  `OpsScalars.cpp:19-34`), widened back as Emit casts a Char. D41's one
  template does not exist yet; today the meaning is written in the folder
  and again in the lowering (`Conversion/Scalars.cpp:57-192`), and
  `runtime/` has no fixed-width division or shift (*read*). So the
  oracle for these ops is the folder's own C++.
- **Integer**: exact, `runtime/Big` on GMP; Euclidean `div`/`mod`
  (`runtime/Big/Arithmetic.cpp:114-139`), shifts as Scheme's `ash` with an
  Integer amount (`Bitwise.cpp:115-146`), two's-complement bitwise ops.
- **String**: `++`, `length` (scalar values), `reverse` (*read*
  `runtime/Strings/Concat.cpp:28-40`, `Scalars.cpp:75-78, 115-138`), with
  Int `+`.
- **Bool**: `i1` under `& | ^` (what comparisons and matches produce).
  Idris's `&&` and `||` are functions lazy in one argument, so their
  commutation is not a rule of the language where an operand can crash
  (*read* AGENTS.md:134-144 on eager meaning); only the `i1` ops were run.

The Rust port of the fixed-width meaning (`/tmp/eg-synthesis/idr-synth/src/sem.rs`)
was checked against the folder's functions themselves: `idrisDivMod` and
`idrisShift` included verbatim by line range from `Ops.cpp:207-223,
256-274` and the body of `foldToChar` from `OpsScalars.cpp:27-31`,
compiled on the pinned APInt, over specials and 20,000 random pairs at
widths 8, 16, 32 and 64: 808,192 cases, 0 mismatches (*measured*:
`folder_oracle | semcheck`).

### 1.2 The search

Ruler's `recursive_rules` (enumerate terms by size, merge by cvec, keep the
candidates the validator accepts, minimize against the rules so far):
three variables, the constants named per run, terms up to 5 atoms (two
binary ops) unless stated. The cvec samples are Ruler's practice, a cross
product of corner values (for a width w: 0, 1, 2, -1, -2, MIN, MAX, w,
w-1). The validator in the loop is mine, per run: *exhaustive* (every
assignment, a proof at that width; only for 8 bits and below), or
*sampled* (4,096 random rows, half corner values, half uniform). A rule is
valid when, wherever its left side is defined, its right side is defined
and equal; a guarded op is undefined where its guard would crash.

### 1.3 The checks after the search

- `rulecheck_fw`: each rule against the folder's verbatim functions on
  APInt, at a chosen width and signedness; exhaustive when the variables
  span at most 2^24 values, else 200,000 to 1,000,000 random and corner
  rows.
- `smtcheck.py`: each rule as a bit-vector query in z3 (10 s per rule),
  the ops encoded as the folder defines them; the encoding was first
  checked against the folder's printed outputs, 20,205 cases, 0
  mismatches (*measured*).
- `rulecheck_rt`: each Integer or String rule against `runtime/` itself,
  all of its units compiled by the host clang with the typecheck build's
  flags and linked with the sysroot's GMP; 20,000 rows per rule, Integer
  rows reaching past the 63-bit small range and up to 60 digits.
- `smtint.py`: Integer rules over `+ - * div mod` in z3's integer theory,
  whose `div` and `mod` are Euclidean as the runtime's are; rules with
  bitwise ops or shifts have no decision procedure there and are skipped.
- `derive`: Ruler's derivability (left and right in one e-graph, its
  `Limits::deriving`), from today's rules: our folders' identities
  (`Ops.cpp:237-254, 284-295`: `div x 1`, `mod x 1`, `shift x 0`), the
  big add's zero (`Fold/Bigs.cpp:32-43`), and upstream `arith`'s folders
  (`ArithOps.cpp` at the pin: `addi` :433, `subi` :606, `muli` :648,
  `andi` :1154, `ori` :1187, `xori` :1222) plus, generously,
  commutativity and associativity of the arith ops, so "new" is a lower
  bound. Constant folding is in the e-graph analysis.
- Cost: the ops our lowering emits, read off `Scalars.cpp`: a signed
  Euclidean `div`/`mod` 12 arith ops (`:62-108`), an unsigned one 1, a
  signed total shift by a variable 11 and an unsigned one 4 (`:116-161`),
  a shift by a constant in range 1 (the select chain folds), the char
  conversion 7 or 8 (`:166-192`), the rest 1; and a latency guess
  (*conjecture*: multiply 3, divide 8, Euclid 12, variable shift 3-5). "Improving" is
  strictly cheaper on one measure and no dearer on the other.

## 2. What it found

All *measured*; wall time of the synthesis alone, under the shared
machine's load.

| run | language | validation | rules | wall | new vs today | after-checks |
| --- | --- | --- | --- | --- | --- | --- |
| Int8 | `+ - * & \| ^ div mod shl shr`, consts 0 1 -1 2 | exhaustive | 456 | 55.9 s | 410 | folder, exhaustive at 8: 0 false; at 16/32/64 sampled: 1 false; z3 at 64: 435 proved, 1 refuted, 20 unknown |
| Bits8 | same, unsigned | exhaustive | 575 | 94.6 s | 529 | folder at 8: 0 false; at 64: 4 false |
| Int64 | same | sampled | 508 | 40.7 s | 462 | z3 at 64: 426 proved, **60 refuted**, 22 unknown; folder, 10^6 rows: 0 false |
| Int8 shifts, depth 7 | `+ - * shl shr`, consts 1 2, vars a b | exhaustive | 2,256 | 352.7 s | 2,038 | at 64 sampled: 93 false; of the 649 improving, z3 at 64: 586 proved, 55 refuted, 8 unknown |
| Int8 Euclid, depth 7 | `+ - * div mod`, consts 1 2, vars a b | exhaustive | 177 | 3.9 s | — | 36,871,269 value conflicts, 15 constant conflicts; nothing learned at depth 7 |
| Integer | ten ops | sampled | 556 | 63.3 s | 554 | runtime/Big: 0 false (9 at my 512-place growth cap, all pass with a cap of 100,000); z3 integer theory: 119 proved, 2 unknown, 435 outside it |
| Char | `chr`, `+ - & \|`, consts 0 1 -1 127, vars a b | sampled | 145 | 0.7 s | 104 | z3 at 64: 145 proved |
| String | `++ len rev +` | sampled | 25 | 0.1 s | 21 | runtime/Strings: 0 false |
| Bool | `& \| ^` on `i1` | exhaustive | 31 | 0.1 s | — | Boolean algebra; `andi`/`ori` are `Idempotent` and `Commutative` upstream |

Rules are counted per direction (Ruler's `<=>` is two).

- **Most new rules involve our ops**: 319 of Int8's 410 new rules and 437
  of Bits8's 529 contain `div`, `mod`, `shl`, `shr` or `chr`.
- **Improving in one direction** (§1.3's costs): 105 of Int8's 410 new,
  105 of Bits8's 529, 649 of the depth-7 shifts' 2,038. By op count alone:
  40, 32, 252; Integer 49 of 554, Char 13 of 104, String 13 of 25.
- **Degenerate**: a subterm applying a binary op to one variable twice
  (`(shr ?a ?a)`, `(mod ?b ?b)`): 83 of 410 (Int8), 88 of 529, 161 of 554
  (Integer), 630 of 2,038 (shifts), 7 of 104 (Char). Enumeration makes
  them; programs do not (`workloads.md` §3.2: "the arithmetic that exists
  is positions, counters and masks with few constants").

## 3. Soundness: what sampling accepts, and what each check proves

### 3.1 At 8 bits, where the truth is cheap

Int8, the same language and search, only the validator changed; every
output checked exhaustively against the folder's C++ (*measured*):

| validator in the loop | rules | false |
| --- | --- | --- |
| none (cvec of corner values only) | 567 | 94 (16.6%) |
| + 64 random rows | 483 | 35 (7.2%) |
| + 4,096 random rows | 456 | 0 |
| exhaustive | 456 | 0 (the identical set) |

At 8 bits a few thousand rows close the gap, because an edge value is 1 in
256 per variable.

### 3.2 At 64 bits, where sampling cannot see

The Int64 run's 60 refuted rules hold on every row 4,096 samples and
10^6 more drew, and fail at points of three kinds (*measured*, z3's
counterexamples):

- **A composite edge value**: `(shr ?b (- ?a 2)) ==> (shl ?b (- 2 ?a))`
  fails only at `?a = MIN + 2`, where `?a - 2` is the most negative amount
  and negating it gives itself, read as a huge count
  (`Ops.cpp:260-263`). The samplers draw `MIN`, never `MIN + 2`.
- **Small negative shift amounts**: `(shr ?a ?a) ==> (shr ?a (| ?a 2))`
  fails at `?a = -7`: the amount turns the shift around. Uniform 64-bit
  samples are almost never in `[-64, 0)`.
- **The wrap point of a product or sum**: `(div 1 (shl ?a 1)) ==> (div 2
  (shl ?a 2))` fails at `?a = 2^62`.

Synthesizing at 8 bits with a proof, then lifting, does far better: of the
456 exhaustively proven Int8 rules, z3 proves 435 at 64 bits, refutes 1
(`(shl 0 (shl ?a ?b)) ==> (shl ?a 8)`, whose literal 8 is the width), and
times out on 20, all with a variable divisor (*measured*). Bits8 has 4
such width-literal rules. A small-width proof is not a proof at another
width, but with constants among 0, 1, -1, 2 nearly every rule is generic
in the width.

### 3.3 Across domains

99 of the 556 Integer rules are false under Int64's wrapping (*measured*,
the folder's C++ at 64 bits): `(div (+ ?a ?b) ?a) ==> (+ (div ?b ?a) 1)`,
`(mod (* ?a ?b) ?a) ==> 0`, and `(div ?a -2) ==> (shr (- 1 ?a) 1)`, which
holds on Integer and fails on Int64 at `?a = MIN + 1`. A rule is per
domain; `egraph.md` §3.1's `Exact` condition is the fact that licenses
the Integer ones, and a rule synthesized on Integer is never applied to a
fixed-width op.

### 3.4 Partiality as an undefined value, against partiality as a sort

Ruler models a guarded op as undefined where the guard would crash, a
`None` that propagates through every term above it. With Euclidean
`div`/`mod` at depth 7 (Int8, exhaustive validation), applying the 177
proven rules to the depth-7 workload made Ruler's e-graph merge classes
whose sampled values disagree 36,871,269 times and merge two different
constants 15 times; the round learned nothing (*measured*). Control runs
at the same depth: `+ - *` alone, 0 conflicts (209 rules, 1.6 s); `+ - *
shl shr`, 0 conflicts (2,256 rules, 353 s). Accepting only equivalences
defined on exactly the same rows left the conflicts at 36,875,290
(*measured*), so the cause is not one-way rules but the model: a rule
validated over values meets, in the e-graph, a variable bound to a class
that is undefined on some rows (a partial subterm), and a rule that drops
or duplicates that variable changes where the term is defined
(*conjecture*, consistent with both runs).

Our IR does not have that state. The guard is an op that returns its
operand refined (`idr.check.nonzero`: "the value, which must not be zero,
else the program crashes", `IdrCheckOps.td:99-101`; AGENTS.md:485-489: a
total op stays below its guard by data dependence on the refined
result; D105 binds a case's scrutinee refined the same way). The crash
lives in the guard op, ordered with IO; the division is a total function
of an Int and a NonZero. Modelled that way (a second sort for the
divisor, sampled from nonzero values, no undefined value anywhere), the
same domain learned 15, 17, 262 and 219 rules at sizes 3 to 6 in 17.8 s,
for example `(div (int ?n) ?n) ==> 1` and `(mod ?a n2) <=> (mod (* ?a ?a)
n2)` (*measured*). Its depth-7 round ran past 10 minutes and 9.8 GB and was
stopped when the scope changed, so whether it stays free of conflicts at
depth is unmeasured.

### 3.5 What each check proves

- **Exhaustive at 8 bits**: a proof at 8 bits, of the meaning it ran. Cheap
  (the Int8 run's 7,135 validations in under a minute).
- **SMT at a width**: a proof at that width of the encoding. Bit-vector
  division is slow for it: 20 of 456 rules time out at 10 s at 64 bits.
  The encoding is a copy of the meaning; mine agreed with the folder on
  20,205 cases, which shows it was right, not that it stays right.
- **SMT's integer theory** for `+ - * div mod` on Integer: an independent
  oracle whose Euclidean semantics coincides with the runtime's, not the
  runtime's meaning.
- **Sampling against the folder or `runtime/`**: evidence of the meaning
  itself, a proof of nothing at 64 bits (§3.2), and the only check there
  is for Integer bitwise ops and shifts and for strings.

## 4. What is worth keeping under D106

D106 keeps the e-graph narrow: today's local patterns, the choice per arm,
and algebra only one-way and narrowly triggered. Read against that, the
synthesized rules fall into three groups.

**Kept: constant-triggered strength reductions our semantics creates.**
Each has one root op and a constant operand, so it is matched in O(1) by
root and attribute, and each removes a guarded or expanded op. The
instances named were *measured* proven by z3 at 8, 16, 32 and 64 bits
(`div` by 2 and 4, `mod` by 2, 4, 8, -2, -4, ±1, shifts by -3 and -5,
`(shl 2 (- 3 ?a))`) and exhaustively at 8 bits, unless marked; a family
over every `k` is a *conjecture* from those instances, which the
template's facts would state and the check would prove per width. The
cost is §1.3's.

| rule (one-way) | why it is ours | lowered ops |
| --- | --- | --- |
| `(mods ?a 2^k) ==> (andi ?a 2^k-1)` | Euclidean remainder is in `[0, 2^k)` even for negative `a`; false for truncating `%` | 12 → 1 |
| `(mods ?a -2^k) ==> (andi ?a 2^k-1)` | the remainder depends on `\|b\|` only (found as `(mod ?a -2) <=> (mod (\| ?a 2) 2)` and the mask rules) | 12 → 1 |
| `(divs ?a 2^k) ==> (shrs ?a k)` | Euclidean division by a positive divisor is floor division, which is the arithmetic shift; false for truncating `/` | 12 → 1 |
| `(divs ?a -1) ==> (subi 0 ?a)`, `(mods ?a ±1) ==> 0` | `MIN / -1` wraps to `MIN` in our meaning (`Ops.cpp:210-211`), as `0 - MIN` does | 12 → 1, 12 → 0 |
| `(shls ?a -k) ==> (shrs ?a k)`, `(shrs ?a -k) ==> (shls ?a k)` for constant `0 < k < w` | a negative amount turns the direction (`Ops.cpp:260-263`) | 11 → 1 |
| `(shl ?c (- k ?a)) ==> (shr (c·2^k) ?a)`, e.g. `(shl 2 (- 3 ?a)) ==> (shr 16 ?a)` | total shifts saturate and turn, so a shift by a difference is a shift the other way, for every `a` including `MIN` | 12 → 11 |
| `(chr (andi ?a m)) ==> (andi ?a m)` and `(chr (ori (chr ?a) m)) ==> (ori (chr ?a) m)` for `m < 2^11` | the surrogates are exactly one aligned 2^11 block, `[0xD800, 0xDFFF]`, so OR-ing a scalar value with any mask below 2^11 stays scalar; 2,047 is proved at 16, 32 and 64 bits, 2,048 and 4,095 refuted (at `0xD0C2` and `0xD000`) | 8 → 1 |
| `(chr (chr ?a)) ==> (chr ?a)` | the test is idempotent | two tests → one |
| Integer: `(mod ?a 2^k) ==> (and ?a 2^k-1)`, `(div ?a 2^k) ==> (shr ?a k)`, `(div ?a -2) ==> (shr (- 1 ?a) 1)` | the same, exact; *measured* on `runtime/Big` (20,000 rows), not provable in SMT's integer theory (bitwise) | a GMP call → inline |

The first five are what an LLVM-style compiler does for unsigned division
and for C's truncating division with a bias; for Euclidean division they
are simpler (no bias), and no upstream pattern applies because upstream
has no Euclidean op (`arith.floordivsi` is floor, not Euclid, for a
negative divisor). Whether LLVM recovers them from our 12-op expansion
after lowering is not measured (*conjecture*: partly, since the
expansion's selects on a constant divisor fold). At the `idr` level they
are certain and cost one match. They are D41's template's identities: the
template that is the op's meaning can state "a power-of-two divisor"
facts once, `static_assert`ed when the compiler is built, and the
specification prints the one-way rules from it (`egraph.md` §2.6, `:461-480`).

**Candidates, if a workload shows them**: one-way rules over two nested
ops with no constant, a root and a child op as the trigger:
`(mods (mods ?b ?a) ?a) ==> (mods ?b ?a)`, `(divs (mods ?b ?a) ?a) ==>
0`, `(mods (- ?a ?b) 2) <=> (mods (- ?b ?a) 2)`, `(mods (* ?a ?a) 2) ==>
(mods ?a 2)`. `payoffs.md`'s E4 row counts 15 `div`/`mod` pairs on the
same operands in the frontend (`payoffs.md:401`); those want the shared
`sdiv`/`srem` of the lowered pair, which CSE gives after lowering, not a
rule. None of this group is justified until `workloads.md`'s harness
shows a match on real IR.

**Dropped**: the degenerate rules (§2), the bidirectional algebra
(commutation, association, the Boolean algebra), and every rule whose
only use is to connect two equally costly forms. `workloads.md` measured
exactly this class: 104,954 commutations and 119,716 associations on the
inlined frontend changed no decided match and kept at most 86 of 3.4
million nodes, and caused every budget stop (`:315-330`).

So offline synthesis yields, for the narrow e-graph, about a dozen
one-way rule families on our ops, all constant-triggered, from several
thousand rules found.

## 5. How they enter the specification, and how they are checked

### 5.1 The form

A kept rule is a record of `egraph.md` §3.1's rule language
(`:535-588`) in the dialect's Idris specification, generated to the C++
side as the TableGen is (D16, D107): direction `Simplify` (one-way; the
language's own proof `safe` already forces `Simplify` on a rule that
drops a use, `:576-588`), its trigger the root op and the constant
condition (`Cond`'s `Constant` and `InRange`, with a
power-of-two and a below-2^11 condition added to that closed sum,
`:561`). Two
things the synthesis showed the language must hold:

- **A guarded operand has its refinement as its sort.** A rule binds a
  divisor at sort NonZero, the guard's result (§3.4); `(mods ?a ?a) ==> 0`
  is then a well-sorted rule and its reverse is ill-sorted, rejected when
  the specification builds, instead of a `None` the e-graph cannot keep
  consistent. This follows from D21 and D105 (a guard and a case return
  their operand refined) and is the coordinator's to record, not a new
  shape.
- **A rule is per domain.** Its signature fixes the op (`divs` on a
  fixed-width type, `big.div` on Integer); §3.3's 99 rules are why an
  Integer rule never meets a wrapping op.

### 5.2 Its evidence

Each rule carries the check that admitted it, as a closed sum in the
record, never prose:

- **Inline arithmetic** (division, shifts, the char conversion, D41):
  exhaustive at 8 bits, then SMT at every width the op admits (8, 16, 32,
  64). The SMT encoding is the D41 template instantiated over a domain of
  SMT terms, beside its instantiations over integers (the folder),
  intervals (the ranges) and an IR builder (the expansion)
  (`proposals/0000-mlir-native.md:729-748`): the query is then built
  from the one meaning, not from a hand copy like §1.3's (*conjecture*:
  the template's concept already abstracts the arithmetic it needs; an SMT
  term domain is one more model of it). A rule whose SMT query times out
  is not admitted at that width.
- **Runtime primitives** (Integer, strings): sampling against `runtime/`
  with samplers biased to the representation's edges (the 63-bit small
  range, multi-byte scalars), as `egraph.md` §3.5 has it; and for Integer
  `+ - * div mod`, SMT's integer theory as an independent check. Bitwise
  Integer ops, shifts and strings have no decision procedure, so such a
  rule's trust is a declared law of the primitive, the same trust
  `egraph.md` §3.2 states for hand-declared laws (`:589-602`), stated and
  never presented as proved.
- **Never sampling alone at 64 bits** (§3.2).

### 5.3 What `make check` runs

The rules are spec content, so D67's manifest already fingerprints them.
`make check` reruns the cheap evidence (exhaustive 8-bit through the
template's integer instantiation, and the runtime sampling, seconds per
hundred rules, *conjecture* from §2's validation counts), so a change to an op's
meaning fails the rule that no longer holds. The SMT proofs are slower
(*measured*: 6 min 44 s single-threaded for 456 rules at 64 bits, 10 s
limit) and are a fact known when nothing has changed: the manifest
records each proof's inputs (the rule, the template, the solver's
version) and the proof is rerun when one of them changes, never on every
check.

### 5.4 A synthesizer in the tree

Not in P0 (*conjecture* as a recommendation). D106's rules are few and
reviewed one by one; offline synthesis is an authoring aid, like a
reader, whose output a person admits with its evidence. If one is kept
later, AGENTS.md fixes its shape: its logic is Idris (D15), and it never
evaluates a primitive itself, because no primitive has an implementation
in Idris (AGENTS.md:253-261) and an Idris model of `divs` would be the
second copy 03 O-47 removed. It would enumerate and minimize in Idris and
hand terms to a C++ evaluator built on the D41 template and `runtime/`
through files, never a call: no C interop, both hosts build its Idris
part, one meaning. Ruler itself (Rust) stays an outside tool.

## 6. Verdict

- **A real source?** Yes, narrowly. It found, in minutes, the strength
  reductions that exist because our division is Euclidean, our shifts are
  total and our char test is a range test, which no upstream pattern has
  and today's folders lack; and the scalar-value mask fact (any mask below
  2^11) is the kind of unintuitive rule D57 asked for. It did not find a
  body of rules worth running free: thousands of rules collapse to about
  a dozen constant-triggered families once degenerate and
  cost-neutral ones go, which is what D106 and `workloads.md` predict.
- **Its soundness story**: sampling proposes, it never admits. At 64
  bits it admitted 12% false rules that a million more samples could not
  see; exhaustive proof at 8 bits plus SMT at each width (from the
  template's own instantiation) admits; for runtime primitives without a
  decision procedure, the rule is a declared law checked by sampling,
  stated as such. Partiality must be a sort, as the IR already has it,
  not an undefined value.
- **What it needs from the owner**, one decision at a time, the first
  first:
  1. Whether the constant-triggered strength reductions of §4's first
     table enter P0 as one-way rules in the specification (D106's
     narrowly triggered algebra), with the template stating their facts.
     Cost: a power-of-two and a below-2^11 condition in the rule
     language, one exhaustive and one SMT run per rule; buys 11-12
     lowered ops per Euclidean division or modulus by a power of two and
     per shift by a negative constant, and a removed range test on
     masked chars.
  2. The evidence policy of §5.2: SMT at every width through a fourth
     instantiation of the D41 template for inline arithmetic, sampling
     as the stated trust for runtime primitives. Cost: the template gains
     an SMT-term model, and a solver (z3 or cvc5) becomes a check-time
     dependency under `.toolchain`; buys proofs instead of samples.
  3. Whether any synthesizer is kept in the tree (§5.4); recommended
     none in P0.

## 7. Reproduction

All in `/tmp/eg-synthesis` (not committed; ephemeral):
`src/ruler` (the patched clone), `idr-synth/` (the domains: `src/sem.rs`,
`src/lib.rs`, `src/big.rs`, `src/strs.rs`, `src/nz.rs`; the `derive` and
`semcheck` tools), `check/` (`folder_oracle.cpp`, `rulecheck_fw.cpp`,
`rulecheck_rt.cpp`, `smtcheck.py`, `smtint.py`, `analyze.py`,
`opcount.py`, and the verbatim includes `divmod.inc`, `shift.inc`,
`tochar.inc`), `rt/` (the runtime objects and their build script),
`today/fw.rules` (today's rules for derivability), `runs/` (every rule
file, log and check output). A run is `idr-synth DOMAIN exact|sample ROWS
ATOMS VALS VARS UNOPS BINOPS OUT`, e.g. `idr-synth s8 exact 4096 5
"0,1,-1,2" "a,b,c" "" "+,-,*,&,|,^,div,mod,shl,shr" s8-exact.rules`.

## 8. Sources

- Ours: `AGENTS.md`; `.claude/skills/representation-first/SKILL.md`;
  `proposals/0000-mlir-native.md` (D15, D16, D41, D57, D67, D85-D87,
  D105-D108); `audits/p0/design/egraph.md` §2.6, §3, §10.3;
  `egraph-full/workloads.md` (§3.2, §5), `payoffs.md` (E4 row),
  `speed.md` (§4, Enumo's growth and compression), `one-engine.md` (§0, a
  route D107 retired). Code: `foreign/idr/include/idr/IR/IdrScalarOps.td`,
  `IdrBigOps.td`, `IdrCheckOps.td`, `IdrBase.td:295-309`;
  `foreign/idr/lib/IR/Ops.cpp:201-295`, `OpsScalars.cpp`,
  `Fold/Bigs.cpp`, `Fold/Strings.cpp`; `foreign/idr/lib/Conversion/Scalars.cpp`;
  `compiler/src/IdrisMLIR/Emit/Operations.idr:150-300`;
  `runtime/Big/{Arithmetic,Bitwise}.cpp`, `runtime/Strings/{Concat,Scalars}.cpp`,
  `runtime/idris_rt.h`; MLIR at the pin: `lib/Dialect/Arith/IR/{ArithOps.cpp,ArithCanonicalization.td}`,
  `include/mlir/Dialect/Arith/IR/ArithOps.td`.
- Outside: uwplse/ruler 7ed456de (`src/{language,lib,recipe_utils}.rs`,
  `src/enumo/{ruleset,rule,scheduler,workload}.rs`, `src/bv.rs`,
  `tests/{bv8,halide,nat}.rs`); Pal et al., "Equality Saturation Theory
  Exploration à la Carte", OOPSLA 2023 and its journal version
  (`sources/papers/pal-2023-ruler`: `01-introduction.tex:16-35` on one
  unsound rule compromising a system and "likely sound" candidates,
  `04-sliderule.tex:375-420` on candidates by evaluation and validators
  by SMT or fuzzing, `06-devexp.tex:32-35` on `(/ x x) → 1`,
  `06-extensibility.tex:10-16`); Nandi et al., OOPSLA 2021 (*recalled*,
  the cvec method).
