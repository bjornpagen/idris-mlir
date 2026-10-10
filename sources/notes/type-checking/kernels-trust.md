# Notes: small trusted kernels, fast proof checking, reflection (cluster kernels-trust)

Read 2026-10-09. Every path below is relative to the staged library root
`scratchpad/selfhost/tc/stage/sources/` unless it starts with `sources/` (the committed
library). `file:N` is a line number in the stored file; PDFs are cited by section, figure or
page. Entries marked *(sibling)* were staged by another cluster of this tc pass and are only
cross-linked here; entries marked *(link-only)* were not stored and nothing below rests on
their content.

The question: how small and how fast can a checker be, how does proof by reflection hand
checking over to compiled code, and what would an idris-mlir kernel, separate from its
elaborator, look like.

## 1. What "trusted" and "small" mean (Pollack, Barendregt–Wiedijk, Wiedijk)

**The de Bruijn criterion.** A proof assistant satisfies it when its output can be checked
independently "by a small program" that only checks that the small number of logical rules
are observed, however large the proof
(`papers/barendregt-2005-challenge-computer-mathematics/rspaper.tex:2221-2234`). Färber
quotes this definition as the motivation for small checkers
(`papers/farber-2022-kontroli/main.tex:204-207`).

**Two questions, not one.** Pollack splits belief in a formal proof into (a) is the object a
derivation in the stated formal system, answerable by machine through *independent checking*
with a simple checker that does no search, heuristics or decision procedures, and (b) is the
derived formula the claimed theorem, which no machine answers; for (b) you read only the
statement, the hereditary definitions and the outstanding assumptions, printed by the trusted
checker (`papers/pollack-1998-believe-machine-checked-proof/BRICS-RS-97-18.pdf`, §1.1,
pp. 2–4). Consequences he draws that bear directly on a kernel design:
- The checker's *parser and printer are trusted*, not just the kernel: "nothing the proof
  checker says can be believed" without an understood concrete-to-abstract mapping, so a
  system with extensible notation must also support an official parseable syntax (§3.1,
  pp. 6–7). LCF-style "small kernel" arguments routinely forget this.
- Checking cost is a property of the *presentation* of the logic: derivations can be shrunk
  by sharing (linear derivations naming earlier lines; definitions) and by *annotating
  conversions*: "I can annotate the proof with the conversion paths found by my proof
  checker … your checker need only follow the annotations … not discover a conversion path
  for itself", trading proof size against side-condition computation (§4.1, p. 13).
- On reflection: it "collapses the framework and the object logic" to get admissible rules
  without expansion, but "distorts the object logic … and is much harder to believe"
  (§3.2.1, p. 9). His preferred route is a three-level stack (programming language, logical
  framework, object logic), with admissible rules justified in the framework (§3.2.1, p. 9).
- The hardware/software stack cannot be believed by direct understanding; diverse platforms
  and independent checkers are the practical defence (§3.2, pp. 7–8; §3.2.2, p. 10).

**The Poincaré principle strains the criterion.** Systems that store proofs ("petrified")
usually let a class of equations `t = s` be checked by computation rather than by proof,
which "puts somewhat of a strain on the de Bruijn criterion requiring that the verifying
program be simple"; the authors accept it because a universal computational model's steps
are simple (`papers/barendregt-2005-challenge-computer-mathematics/rspaper.tex:2303-2309`).
They also describe proof by computation as proving once that `P_f(a,b) ↔ f(a)=b` and then
checking instances by evaluation (`rspaper.tex:2261-2309`).

**Pollack-consistency.** A system is Pollack-inconsistent if from finitely many equations
`t1 = t2` with `print(t1) = print(t2)` a contradiction is derivable, and Pollack-super-
inconsistent if some provable formula prints exactly as `⊥`
(`papers/wiedijk-2012-pollack-inconsistency/rap.tex:283-376`). HOL Light and Isabelle are
shown strongly Pollack-inconsistent, Coq weakly super-inconsistent (via a coercion), Mizar
weakly inconsistent; Metamath is trivially consistent because its printer and parser are
the identity on token strings (`rap.tex:502-813`). The cure is cheap: print, re-parse, and
fall back to a fully explicit "failsafe" printer whenever the round trip fails
(`rap.tex:842-890`). Carneiro adopts Pollack-consistency as a design criterion for MM0
(`papers/carneiro-2022-metamath-zero-thesis/thesis.pdf`, §0.1, footnote 5).

## 2. The fastest small checkers, and what was actually measured

### Metamath

The whole proof rule is substitution of expressions for variables in token strings plus
disjoint-variable conditions; a proof is an RPN sequence of labels checked on a stack
(`docs/metamath/book/metamath.tex:9040-9130`, §4.1.4 "Proof Verification" and its
disjoint-variable rule, in the specification section that starts at line 8829). Trust comes from
multiplicity: set.mm "is currently verified by four different Metamath verifiers written by
four different people in four different languages" (`metamath.tex:1096-1100`; also
3002-3019), and over a dozen exist (`docs/metamath/other.html`).

Speed claims, separated by evidence:
- **Measured, with machine:** smm re-run single-threaded on an Intel i7 3.9 GHz on the then
  current set.mm: 927 ± 28 ms (`papers/carneiro-2020-metamath-zero/mm0-paper.tex:192`).
- **Self-reported, older machine:** smm3 0.7 s on a 2-core i5 1.6 GHz, multithreaded, June
  2016, on a smaller set.mm (`docs/metamath/other.html`, smm entry; repeated in
  `mm0-paper.tex:192`); metamath.exe "about 8 seconds" (`mm0-paper.tex:192`, no machine).
- **No benchmark:** metamath-knife "over 28,000 proofs can be proved in less than a second"
  with `--jobs 4`, no machine, no set.mm revision (`docs/metamath/knife/README.md:8,41`); the
  book's "re-verification of an entire database takes seconds" (`metamath.tex:3023`).

Weaknesses Carneiro identifies, each soundness-relevant: bundled variables give exponential
blow-up on translation out; string expressions make soundness depend on the
(undecidable-in-general) unambiguity of the grammar, and an ambiguous `→` would prove a
contradiction; definitions are just axioms, checked for conservativity by only one of the
17 verifiers (`mm0-paper.tex:194-220`; thesis Appendix A gives the contradiction).

### Metamath Zero (MM0)

**Architecture.** The trusted parts are the verifier and the human-readable `.mm0` file
(sorts, terms, axioms, theorem *statements*, no proofs); the `.mmb` proof file is untrusted
"in the strongest sense", e.g. from a malicious agent (`mm0-paper.tex:144-172`). The proof
file may introduce local definitions and theorems but not sorts, terms or axioms
(`mm0-paper.tex:376-379`). The `.mm0` file is maintained by hand next to the `.mm1` source
because a trusted artifact generated by an untrusted tool is hard to trust
(`mm0-paper.tex:562-567`). The kernel runs as its own process so that undefined behaviour
elsewhere cannot corrupt it (`mm0-paper.tex:132-142`).

**Logic.** Multi-sorted first-order schematic metatheory: names (bound variables) versus
metavariables with explicit dependency lists `φ : s x̄`; definitions are conservative and
unfold by a convertibility judgment; theorem application checks admissibility with V(e) (all
variables) rather than FV(e) because it is faster and as expressive given alpha-renaming in
the logic (`mm0-paper.tex:222-338`, Fig. 1–2 at 224-296; V vs FV at 312, "Theorem
application is the hottest loop" at 333).

**Proof format: "avoid search" and "don't repeat yourself"** (`mm0-paper.tex:398`).
- The `.mmb` file is laid out to be used in place: header, term table, theorem table,
  declaration list; names are indexes, strings live in a strippable index used only for
  errors (`mm0-paper.tex:400-405`; `code/mm0/mm0-c/types.c` header and tables;
  `code/mm0/mm0-c/main.c:63` mmaps it read-only).
- A proof is a postfix stream of opcodes for a stack machine with a heap of saved results
  (`Ref`, `Term`, `Save`, `Dummy`, `Thm`, `Hyp`, `Conv`, `Refl`, `Symm`, `Cong`, `Unfold`,
  `ConvCut`, `ConvRef`, `ConvSave`); a theorem's statement is a prefix *unify stream*
  (`UTerm`, `URef`, `USave`, `UDummy`, `UHyp`) that *deconstructs* the supplied conclusion
  rather than building a substitution instance (`mm0-paper.tex:409-468`, Fig. 3;
  `code/mm0/mm0-c/verifier.c:213-331` `run_unify`, `:341-663` `run_proof`).
- **Allocation is controlled by the proof.** Terms are only allocated by `Term` and `Dummy`;
  since every repeated subterm is reached by backreference, the verifier *requires* that
  anything compared was constructed once, so every equality test is a pointer comparison,
  O(1), with no hash-consing in the checker (`mm0-paper.tex:476-478`;
  `verifier.c:245` `URef`, `:550` `Refl`). The producer does the hash-consing
  (`mm0-paper.tex:494-519`).
- **Conversion is co-inductive on the stack:** `Conv` leaves an obligation `e1 =?= e2` that
  `Refl`/`Cong`/`Unfold` discharge by deconstructing terms already built
  (`mm0-paper.tex:470-474`; `verifier.c:532-607`). This is Pollack's annotated conversion
  path made concrete: the checker never searches for a conversion.
- Free-variable/disjointness data is a 64-bit word per expression: 55 dependency bits,
  sort, bound flag; at most 55 bound variables per declaration
  (`code/mm0/mm0-c/types.c:69-80`; `code/mm0/mm0-c/README.md:44`). All limits are fixed
  arrays, failure rather than growth (`code/mm0/mm0-c/verifier_types.c:19-77`;
  `README.md:28-37`).
- Complexity is O(mn) (proof length × longest statement), linear on realistic libraries;
  the paper gives the contrived quadratic case (`mm0-paper.tex:482`). Memory high-water is
  under 1 MB on set.mm, and with heap/stack encoded in the stream O(1) writable memory is
  possible (`mm0-paper.tex:480`).

**Size.** `mm0-c` is "under 3,000 lines of C" (`code/mm0/README.md`); the stored `.c`
files are 2,857 lines including comments and the debug printer (`wc -l`, see
`code/mm0/SNAPSHOT.md`).

**Measurements.**
- set.mm translated to MM0: 195 ± 5 ms, Intel i7 3.9 GHz, single-threaded
  (`mm0-paper.tex:130,398`), against 927 ± 28 ms for smm on the same machine
  (`mm0-paper.tex:192`). set.mm is 34 MB / 590 kLOC, over 34,000 proofs
  (`mm0-paper.tex:130,398`). The author's own caveat: "This is not a fair comparison … we
  are adding a bunch of information and rearranging it to be faster to check … in a sense
  that's the point" (`mm0-paper.tex:398`). The `.mmb` size is not reported.
- peano.mm1 (about 1,000 theorems): verification 2 ± 0.05 ms with mm0-c; compilation by the
  untrusted mm0-rs 306 ± 4 ms (`mm0-paper.tex:554`).
- **Not measurements:** the "4–5 orders of magnitude" over Isabelle/Coq/Lean libraries is
  explicitly "(unfairly) compared" (`mm0-paper.tex:130`); beating CakeML's 14-hour bootstrap
  by "3–5 orders of magnitude" is a projection (`mm0-paper.tex:657`).

**Bootstrap status.** The goal theorem says the verifier's x86-64 ELF terminates and accepts
only valid input (`mm0-paper.tex:595-628`); the proof-producing compiler (Metamath C) that
would discharge it is described in the thesis, with the assembler and compiler theorems
marked work in progress (`thesis.pdf`, table of contents §2.2.8–2.2.9, Chapter 4). MMC
compiles to an SSA/MIR with ghost analysis and proves the output correct per program
rather than proving the compiler (`thesis.pdf`, Chapter 4 introduction, pp. 99–102).

### Dedukti (λΠ-calculus modulo rewriting) and Kontroli

**Logic.** LF plus user rewrite rules in the global context; conversion is βΓ; type checking
is decidable when βΓ is confluent and terminating on typed terms, and subject reduction
needs well-typed rules and product compatibility
(`papers/assaf-2016-dedukti/expressing.tex:315-661`). Left-hand sides are Miller patterns
(higher-order rewriting) (`:497-563`); a rule whose lhs is not itself well typed is accepted
when its *most general typing substitution* makes both sides agree, which needs injectivity
of "static" symbols (no rules on them) (`:565-661`, `:782-817`); "guards" `{n}` are checked
at *every use* of the rule, at run time (`:832-855`).

**Trust gaps.** "Checking confluence is out of the scope of Dedukti itself, and is a separate
concern", delegated to external tools via TPDB export (`expressing.tex:742-747`;
`code/dedukti/kernel/confluence.ml`); termination likewise is assumed. So the small kernel
is sound only relative to a side condition the kernel does not check.

**Kernel algorithm** (`code/dedukti/kernel/reduction.ml`): a lazy Krivine-style machine whose
state is (context of lazy terms, term, stack of shared mutable states), so an argument
reduced while matching is reduced once for all copies (`:55-82`, `:402-452` `state_whnf`);
rewriting goes through per-symbol *decision trees* (`:290-385` `gamma_rw`;
`kernel/dtree.mli`); conversion is a work list: physical equality, then syntactic equality,
else whnf of both sides and compare heads (`:467-518`). No unfolding heuristics: every
definition is a rewrite rule.

**Performance claims.** The paper reports library *sizes* only (595 MB gzipped Zenon, 21.5 MB
HOL Light, …) and concludes the tool "scales up well" (`expressing.tex:2620-2631`) without
checking times; a timing sentence survives only as a LaTeX comment
(`expressing.tex:1446-1448`). Treat "scales" as unmeasured in that paper.

**Kontroli, the measured comparison** (`papers/farber-2022-kontroli/`; machine: 32
Broadwell CPUs at 2.2 GHz, 32 GB, OCaml 4.08.1, Rust 1.54, ten runs, `main.tex:1209-1212`):

| Dataset (size) | Dedukti seq. | Kontroli seq. | DK parse only | KO parse only | KO 8 check threads | source |
| --- | --- | --- | --- | --- | --- | --- |
| HOL Light stdlib (2.0 GB, 1.78 M commands) | 344.5 s | 219.9 s | 77.1 s | 21.3 s | 146.5 s | `eval/itp/time/hol_stdlib_u.dat` |
| Isabelle/HOL to `HOL.List` (2.5 GB, 117 k commands) | 415.1 s | 305.7 s | 195.3 s | 43.2 s | 119.9 s | `eval/itp/time/isabelle_hol.dat` |
| Matita, Fermat's little theorem (2.0 MB) | 0.567 s | 0.311 s | 0.179 s | 0.093 s | 0.235 s | `eval/itp/time/matita_sttfa.dat` |
| Zenon B-method (15.4 GB), 24 theory-parallel | 425.3 s | 263.9 s | – | – | – | `eval/atp/zenon.dat` |
| iProver TPTP (431 MB), 24 theory-parallel | 15.3 s | 11.9 s | – | – | – | `eval/atp/iprover.dat` |

Dataset sizes from `main.tex:1133-1155`. Lessons the paper draws, each with a number:
- **Parsing is a first-order cost:** up to half of checking time; Dedukti's parser takes
  77 of 344 s on HOL Light and 195 of 415 s on Isabelle; Kontroli's lexer-generated,
  allocation-free parser with constants as slices of the input is 4.5× faster on Isabelle
  (`main.tex:925-942,1224-1225`; data above).
- **Term representation:** moving atoms out of boxes (fewer pointers) cut total checking time
  by 20% with `Rc` and 29% with `Arc` on one dataset (`main.tex:727-731`).
- **Parallel reduction loses:** thread-safe abstract machines (Arc, Mutex) cost more than
  parallel substitution/matching gains (`main.tex:812-838`). Parallel parsing through a
  channel also loses (`main.tex:960-968`).
- **What parallelises:** split each command into sequential inference (adds to the global
  context) and deferred checking `Γ,Δ ⊢ r : A` run in a pool, with an O(1)-copy persistent
  map for Γ: type-checking time drops 6.6× with 8 threads on Isabelle/HOL, only 1.4–1.5×
  on HOL Light and Matita whose commands are small (`main.tex:847-920,1061-1071,1235-1244`).
  Atomic refcounts alone cost 28.2% on HOL Light (`main.tex:1228-1231`).
- **Memory:** Kontroli keeps the whole 2.5 GB input in memory: 6.1 GB peak RSS sequential,
  12.7 GB at 8 threads, versus 3.65 GB for Dedukti (`eval/itp/ram/isabelle_hol.dat`, KB;
  `main.tex:1252-1276`).
- **Size:** Kontroli kernel 663 LOC versus Dedukti's 3,470 (Tokei, older revisions), by
  omitting higher-order rewriting, AC matching, rule-variable inference and decision trees
  (`main.tex:1077-1103`); the stored kernels are 913 and 5,528 raw lines
  (`code/kontroli/SNAPSHOT.md`, `code/dedukti/SNAPSHOT.md`). The kernel is `no_std`, pure,
  no I/O (`main.tex:995-998`). Coq data could not be evaluated because its encoding needs
  higher-order rewriting (`main.tex:1129-1131`).
- Other checker sizes it reports: Appel et al.'s LF checker 803 LOC of C (kernel 278);
  LFSC-generated SAT checker 600 LOC C++; Checkers (λProlog) 98 LOC; mmverify.py 308 LOC;
  Wiedijk's Automath checker 3,048 LOC of C; HOL Light kernel 396 LOC of OCaml but 2,753 LOC
  of syntax extension (`main.tex:1301-1371`).

### The Lean reference point *(sibling)*

`papers/carneiro-2024-lean4lean/main.tex:764-778` *(sibling)*: the C++ Lean kernel
(`lean4checker`) checks Mathlib + Batteries + Lean in 44.54 min single-threaded on an Intel
i7-1255U at 2.1 GHz, Lean4Lean (a reimplementation in Lean) in 58.79 min (1.32×). That
paper also calls kernel native evaluation through `reduceBool` "unsound by design", because
compiled code can call C through `implemented_by`, and notes Mathlib avoids it
(`main.tex:535`), and that proofs by reflection are "comparatively rare, in part because the
kernel algorithm for this is not very efficient" (`main.tex:482`, footnote). Its
`code/lean4lean/bugs-found.md` *(sibling)* lists kernel soundness bugs found by
formalisation. This is the bar a "faster than Lean" claim must clear, on the same library
and machine class.

## 3. Proof by reflection: computing instead of proving

**The technique.** Prove once that a decision function is correct, `∀x. f x = true → P x`,
then prove each instance by `refl : f a = true`, which the kernel discharges by conversion;
the proof term's size no longer depends on the work (`papers/gregoire-2002-strong-reduction/strong-reduction.pdf`,
§1; `papers/boespflug-2011-full-throttle/cpp11.pdf` *(sibling)*, Introduction, which
attributes the method to Boutin 1997 *(link-only)*).

**Small-scale reflection** generalises it from big decision procedures to everyday proof:
decidable predicates are defined as `bool` functions and related to `Prop` by the
`reflect P b` inductive, so case analysis and truth-table evaluation do the routine steps;
"if a predicate is decidable, it should be defined through a boolean predicate, possibly
accompanied with logical specifications"; the methodology comes from the Four Colour proof
(`papers/gonthier-2010-small-scale-reflection/paper.pdf`, §1 pp. 96–97, §4.1 pp. 114–115,
§4.1.4 p. 117). Boolean equality also yields uniqueness of equality proofs on `eqType`s
(§4.3, p. 124). Effect on a checker: proof terms shrink, conversion work grows, so the
evaluator becomes the hot path.

**Compiled conversion (vm_compute).** Grégoire and Leroy compile terms to a modified OCaml
ZAM bytecode that performs *weak symbolic reduction* on open terms, representing stuck
computations as *accumulators* (a free variable applied to values, or a match/fix blocked on
one), and recover strong normal forms by a type-free *readback* that applies function values
to fresh accumulators; equivalence testing compares head forms and returns early on a
mismatch (`strong-reduction.pdf`, §2–4). Function application and case need no "is this
symbolic?" test at run time (§7). The machine and compilation scheme were proved correct in
Coq (about 5,000 lines) by simulation (§5).
Measured on a Pentium III 1 GHz, 256 MB (Fig. 5–6):
- Four Colour reducibility, perimeter 13: 14.8 s versus 680 s for Coq's interpreter;
  perimeter 14: 69.6 s versus out of memory; OCaml native on extracted code: 4.11 s and
  19.8 s (Fig. 6).
- Coq's standard library (little computation): 135 s versus 131 s, a 3% slowdown from
  compiling terms that are already normal (Fig. 6, §6).
- Synthetic tests: 10–100× faster than the lazy interpreter (§6, Fig. 5).
- Caveat stated by the authors: conversion is tested on *type-erased* terms; consistency
  follows from Miquel's model for the core CC but "remains to be extended to inductive types"
  (§8).

**Native compilation (native_compute)** *(sibling)*: compile CIC terms to OCaml source and
let the stock optimising compiler produce native code; accumulators as tagged closures;
"untyped normalization by evaluation" (`cpp11.pdf`, Abstract, §1–3). Table 1 (64-bit, 4 GB;
CPU not named): Four Colour 3 h 7 min bytecode → 34 min 47 s native (18.6%); BDD 21.98 s →
11.36 s; Lucas–Lehmer 29.80 s → 8.47 s; typically 2–5×, up to 7–14× when there is little
allocation (§4). The price: "the correctness of our approach is in part contingent upon the
correctness of the compiler, whose entire code enters the trusted base" (Conclusion).

## 4. Unification is elaborator business, and it is subtle

Dynamic pattern unification (solve Miller-pattern equations eagerly, postpone the rest) for
λΠΣ: η-contraction, projection elimination, Σ-flattening and lowering turn more equations
into patterns; pruning removes dependencies a metavariable cannot have; intersection solves
`u[ρ] = u[ξ]`; termination by an ordinal measure
(`papers/abel-2011-dynamic-pattern-unification/unif-sigma.pdf`, §3, Fig. 3–5, Theorem 1).
Gundry and McBride do it for a full-spectrum theory with heterogeneous equations and *twin*
variables so that every solution produced is well typed even when problems remain blocked
(Reed's "typing modulo" lets solved metavariables be ill typed if constraints stay unsolved,
which is wrong for an elaborator that interleaves checking and unification)
(`papers/gundry-2012-dynamic-pattern-unification/pattern-unification-2012-07-10.pdf`, §1.2,
§1.4; code `code/pattern-unify/Unify.lhs`).

Both published pruning rules are wrong (they lose solutions when a "bad" variable sits in
an eliminable position), as are the TLCA paper's non-linear extension and, reported in
2025, its strongly-rigid occurs check (`papers/abel-2011-dynamic-pattern-unification/errata-tlca11.txt`
items 1–4; `papers/gundry-2012-dynamic-pattern-unification/thesis-errata.txt`). Agda shipped
the pruning bug (issue 458, cited in both errata). Moral for the design: unifiers lose
completeness easily and may lose soundness; keep them outside the trusted base, and have a
kernel re-check whatever they produce.

## 5. What idris-mlir's type checker should take

1. **A kernel separate from the elaborator, checking a certificate.** The elaborator
   (unification, implicit search, totality heuristics, tactics, elaborator reflection) stays
   untrusted, as MM1 is untrusted for MM0 (`mm0-paper.tex:144-172`) and as unifiers have
   proven buggy (§4). The kernel checks a fully explicit core term in which every
   conversion that is not syntactic carries its path (Pollack §4.1; MM0's `Conv/Refl/Cong/
   Unfold`, `verifier.c:532-607`). Pollack's warning that the printer and parser are part of
   the trusted base applies to us: the statement of what was proved must be readable in an
   official syntax (§1).
2. **Make equality a pointer comparison by construction.** Let the certificate, produced by
   an elaborator that hash-conses, dictate sharing (MM0, `mm0-paper.tex:476-478`), so the
   kernel needs no hash table and conversion fast paths are O(1). Dedukti and Kontroli get
   part of this from physical equality checks (`reduction.ml:504-518`;
   `convertible.rs:58-72`), but without sharing guaranteed by the producer.
3. **A flat, in-place, index-addressed format and fixed arenas** (`mm0-paper.tex:400-405`,
   `verifier_types.c`), which fit the flat array representations of the proposal this
   cluster serves: tables of terms, theorems and binder types; strings stripped to a side
   index; mmap read-only; a write-once store reset per declaration.
4. **Budget the front end.** Parsing was up to half of Dedukti's checking time and a
   lexer-generated, zero-copy parser cut it 4.5× (Kontroli, above). A binary certificate
   removes parsing from the kernel altogether (MM0).
5. **Parallelise at declaration granularity, not inside reduction.** Kontroli's split
   (sequential inference that extends the context, parallel deferred checking of bodies with
   a persistent context) gave 6.6× at 8 threads where bodies are large and little where they
   are small; parallel reduction was a net loss (`main.tex:812-920,1235-1244`). MM0's
   declaration list carries next-pointers "for fast scanning and parallelization"
   (`mm0-paper.tex:455`).
6. **Reflection as the bridge to our backend.** Our MLIR pipeline already compiles Idris to
   native code, and AGENTS.md makes the runtime the one meaning of every primitive, which
   compile-time evaluation also calls. That is the native_compute architecture
   (`cpp11.pdf` *(sibling)*): kernel conversion on closed, first-order data (Bool, Nat, Bits,
   arrays) evaluated by compiled code through the same runtime, with accumulators/readback
   (`strong-reduction.pdf` §2–4) for open terms. Measured upside: 10–100× over interpreters
   (2002) and a further 2–5× from native code (2011); measured downside: about 3% when
   proofs do little computation (Fig. 6), so it must be opt-in per conversion or chosen by
   cost.
7. **Keep the computation trust explicit.** Compiling a reflected decision procedure puts our
   compiler, MLIR and LLVM in the trusted base (`cpp11.pdf`, Conclusion; Lean's `reduceBool`
   is "unsound by design" for the same reason *(sibling)*). Options, cheapest first: (a)
   report every theorem whose check used compiled evaluation, as `#print axioms`-style
   provenance; (b) re-check such conversions with the kernel's own interpreter in an
   independent, slower pass (Pollack's independent checking); (c) per-program translation
   validation of the compiled decision procedure, which is what MMC does for machine code
   (`thesis.pdf`, Chapter 4); (d) a proved compiler for the evaluator, as Grégoire did for
   the ZAM in Coq (`strong-reduction.pdf` §5).
8. **Erasure needs an argument before it is used in conversion.** Comparing type-erased terms
   is consistent for core CC but was open for inductive types in 2002
   (`strong-reduction.pdf` §8). Our `!idr.erased` (quantity 0) is exactly the information that
   would let a kernel skip erased arguments in conversion; doing so needs a stated theorem
   for QTT, not an optimisation flag.
9. **Pollack-consistent printing.** Print, re-parse, fall back to an explicit printer when
   the round trip fails (`rap.tex:842-890`); Idris's implicit arguments, quantities,
   `auto`-found instances and erased indices are exactly what a default printer hides.
10. **More than one checker.** Metamath's trust story is four independent verifiers on one
    library (`metamath.tex:1096-1100`); Lean4Lean is a second Lean kernel *(sibling)*. A
    second checker for idris-mlir certificates, small and slow, written from the
    specification, is cheap once the certificate format exists. (It is not an "oracle" in
    the sense of `findings/decision-no-oracle.md`: it checks the same certificate against
    the same specification, not program outputs against another implementation.)

## 6. What to avoid

- **Kernel soundness resting on unchecked side conditions.** Dedukti's confluence and
  termination are external (`expressing.tex:742-747`); guards are checked at run time
  (`:849-855`). If our kernel admits user rewrite rules or `%transform`-like equations into
  conversion, their conditions must be checked by the kernel or the rules kept out of it.
- **A "small kernel" with a large trusted periphery.** HOL Light's 396-line kernel sits on
  2,753 lines of syntax extension (`main.tex:1360-1365`, Kontroli); the trusted `.mm0`
  parser is part of MM0's base (`mm0-paper.tex:170`; `code/mm0/mm0-c/parser.c`).
- **Undefined behaviour sharing an address space with the kernel** (`mm0-paper.tex:136-138`):
  our kernel and elaborator are in one static binary; the kernel's memory must not be
  writable by elaborator code paths, or the kernel runs as its own process on a certificate
  file, as MM0's does.
- **Treating unifier output as trusted** (§4 errata).
- **Fixed limits that encode a format restriction silently** (MM0's 55 bound variables,
  `README.md:44`): acceptable in a bootstrap verifier, not for a language whose programs are
  machine-generated (`code/mm0/mm0-c/README.md:46`: "Computer-generated proofs may exceed this limit").

## 7. Limits of this evidence

- No source here checks a dependent type theory with *quantities*, linearity or erasure in a
  kernel; QTT kernel design is an open gap for this cluster (see
  `sources/papers/brady-2021-idris2-qtt` and `sources/code/idris2/src/Core/LinearCheck.idr`,
  where Idris 2 checks usage on elaborated terms inside the elaborator).
- The headline speeds are on unlike workloads: MM0's 195 ms is set.mm in a first-order
  schematic logic with no computation in conversion, on an input pre-arranged for checking
  (`mm0-paper.tex:398`); Dedukti/Kontroli times are for HOL-family exports; the Lean figure
  is a full dependent type theory with computation. None is a like-for-like comparison, and
  the MM0-versus-Lean ratio is called unfair by its author (`mm0-paper.tex:130`).
- Hardware is old for several numbers (Pentium III 2002; 2016 i5 self-report); the
  native_compute paper does not name its CPU (`cpp11.pdf` Table 1) *(sibling)*.
- Kontroli supports a fragment of Dedukti (no higher-order rewriting), so its speed-ups are
  on the datasets that fragment can check (`main.tex:1087-1103`).
- Metamath verifier speeds other than the MM0 paper's re-run are self-reported.
- Not stored, so not relied on: Boutin 1997 (the original reflection paper), Gonthier 2008
  (Notices AMS, Four Colour), the SSReflect manual RR-6455 (catalogue, link-only rows).
