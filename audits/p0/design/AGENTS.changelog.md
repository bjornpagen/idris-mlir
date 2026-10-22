<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# AGENTS.md rewrite: what moved, what is new, and why

The changelog for `audits/p0/design/AGENTS.proposed.md`, the draft
replacement of AGENTS.md (2026-10-21, at e96bb991 with the working tree's
AGENTS.md, which already carries the static-fact bullet). Section 1 maps
every bullet of the current AGENTS.md to the draft; section 2 lists every
new rule with its source; section 3 lists what the draft deliberately does
not encode; section 4 is what the reviewer should look at first.

Citations: "D1" to "D13" are the owner's rulings in
`proposals/0000-mlir-native.md` §2, all dated 2026-10-21; "02 §3.7", "21
P-5" are `audits/p0/NN-*.md`; "A", "B", ... are `audits/p0/synthesis/`;
"PS" is `audits/p0/design/perf-sources.md`, "CT" is
`audits/p0/design/compile-time-cpp.md`, "EF" is
`audits/p0/design/effects.md`; "G DP-nn" is a coordinator decision still
under the owner's review (`synthesis/G-coordinator-decisions.md`).

The draft is 482 lines against the brief's 300–450: about 210 of them are
the current rules kept verbatim (the four targets, static linking, the
monomorphic language, acceptance and budgets, two hosts, the upstream-patch
procedure, the checks), which other files and checks rely on, and which
the brief asks to keep in substance.

## 1. Every bullet of the current AGENTS.md

| # | current bullet | in the draft | disposition and reason |
| --- | --- | --- | --- |
| P | Preamble: the code is the specification; read MLIR and `sources/`; comments explain why and cite no documents or rule numbers | Preamble, first paragraph | Kept verbatim. Two paragraphs follow it: the lens (new, §2 N1) and how "never" lines cite evidence. |
| 1 | Four first-class targets; nothing per-target outside the target's entry | The targets and the build | Kept verbatim (`tools/bootstrap.sh` and `tests/static-linking` enforce it). Never line added: a fold falling back to the build machine's triple (03 O-81), the host's `sizeof` in the lowering (11 I-CV10). |
| 2 | Static linking; only the OS's C library shared | The targets and the build | Kept verbatim, including PINS.md `idris-support-host-cc`. |
| 3 | Idris does types; MLIR does programs | The Idris side | Kept verbatim. |
| 4 | The Idris side compiles under two hosts | The Idris side | Kept verbatim. Never line added: hosts agreeing by coincidence of two float printers (14 X01). D8 follows it as its own bullet (§2 N22). |
| 5 | One thing, one representation | One fact, held once | Kept. One clause added: "a copy kept in step by a verifier is still a copy" (21 P-5: `Idr_Decides` and its `verifyTrait`; the skill's "one fact, one place"). Never lines added: Euclidean division in folder, lowering and runtime (03 O-47); `Idr_Decides` (101edbc5; 21 P-5); a guard filtering a state the representation still allows (9db9813d; 21 P-15). |
| 6 | NO FACT KNOWN STATICALLY ... PAID FOR AT RUNTIME, with eight negative examples | One fact, held once | Kept and sharpened (D10). Changes: (a) "run time" spelled out as both the compiler's and the compiled program's; (b) the knowers gain "a pass's construction" (MLIR's `Pass::initialize`, CT §1.1 T2) and the forbidden acts gain "string-compared, hashed" (D7's own list); (c) new sentence: what the compiler knows about a program goes into the program as a constant (CT §1.1: "T3 is T4's build"); (d) the allowed run-time cost names its cases: the input, the machine, which registered op an `Operation *` is (CT §1.4). Negatives split into "when the compiler runs" and "when a compiled program runs". Corrected for accuracy: the 70% figure is defunctionalization's whole per-function step by total; the pattern set's populate, freeze and destroy are about 11% self of it (PS §1 M9). "The TableGen backend compared C++ names as strings in about twenty places" became "reading records by C++ spelling and name strings (14 T06, T34)": lane 14's "about twenty places" counts bypasses of upstream's typed wrappers, not string compares (D §2.6). The 4,472 example now says what it is: fields counted one by one where the runs are known (18 R-RC-4). The pointer to `audits/flamegraph-2026-10-21.md` became its commit, 51a4771b (the file is on origin/main only). Moved out: "rebuilding what nothing changed" (call graph, `givesBack`) to Analyses and solvers; "throwing away what Idris computed" (FB-01, FB-15) to The Idris side and to the acceptance bullet. |
| 7 | The compiler consumes checked Idris TT; no CExp or run-time case trees; no erasure before use | The Idris side | Kept verbatim, extended: the TTC keeps every fact a reader would rebuild, read once at the boundary into a typed table (§2 N23). |
| 8 | No primitive has an implementation in Idris; its one meaning is the runtime's | What the compiler accepts | Kept verbatim. DP-17 may amend it; the draft keeps it as written. |
| 9 | The monomorphic language; megamorphic refused; contrib etc. no commitment; `libs/`; trusted `unsafePerformIO` | What the compiler accepts | Kept; compressed without change of substance ("the other packages shipped with Idris ... upstream itself plans to disband contrib for external packages. What they covered comes from the packages this compiler ships in `libs/`" became "Idris's other packages (...) are no commitment (upstream plans to disband contrib); what they covered comes from `libs/` (...)"). |
| 10 | There is no oracle | What the compiler accepts | Kept verbatim, placed beside D12 and D13 as the owner's clarification of 2026-10-21 asks (testing-by-search's skill cites it). |
| 11 | `%foreign` and the C ABI are outside the language | What the compiler accepts | Kept verbatim. |
| 12 | Only `IdrisMLIR.Frontend.*` imports the fork | The Idris side | Kept verbatim. |
| 13 | third_party/Idris2 unmodified, pinned | Upstream and pins | Kept verbatim. |
| 14 | Dependencies under .toolchain/ by `make bootstrap`; pin policy | The targets and the build | Kept verbatim. |
| 15 | Reject with `unsupported`; never miscompile silently | What the compiler accepts | Kept verbatim. Never lines added: no stack probes, so a large frame lands in the signal stack (read, 18 R-STK-1, R-STK-2); a solve's answer dropped in release (10 R-2). |
| 16 | Acceptance is the program's; budgets never refuse | What the compiler accepts | Kept verbatim. Never lines added: the `max-rounds` refusal until c7aa7b62 and 19fe1332; valid programs refused by the TTC's dropped `let` type (17 FB-01); a refusal an optimization can add or remove (read, 08 NQ1). The last is stated as the rule's violation only; how the in-place promise is to be defined is DP-12, open. |
| 17 | No pass may drop what Idris proved; quantity 1 a type; no discardable attribute | One fact, held once | Kept verbatim. Never lines added: `idr.refusals` (14 T38); Emit demoting a quantity-1 binder (17 FB-28). |
| 18 | Erased does not mean constant ... | One fact, held once | Kept verbatim. |
| 19 | An upstream bug is fixed upstream; the patch procedure; the fork's bugs; nothing sent to Idris | Upstream and pins | Kept verbatim (`tools/lanes/README.md` and `upstream/README.md` cite it). One sentence follows it: PINS.md and `upstream/` change in the commit that changes what they describe (§2 N27). Never lines added. |
| 20 | Tests check behaviour | Tests and checks | Kept verbatim. Never line added: a test that names a pass (28274bd3; 19 T1-T3). |
| 21 | Checks: the `make` targets | Tests and checks | Kept verbatim. Every `make <target>` the draft names is documented in the Makefile's header (bootstrap, check, build, test, test-idr, test-unit, test-mlir-tools), as `tests/commands` checks. |

No current rule is dropped. The changes in substance are only those of row
6 (accuracy and the sharpening D10 asked for) and the added sentences of
rows 5, 7 and 19.

## 2. New rules, and where each comes from

| # | rule (short) | section | source |
| --- | --- | --- | --- |
| N1 | Representation first is the lens; read both skills; the handoff names the state made unrepresentable, the check moved or the branch deleted | Preamble | D5 ("This document outlines the philosophy and it's extremely important"); the skill's handoff rule; `tools/lanes/README.md` (the owner's binding rules: read AGENTS.md and both skills). |
| N2 | "Never" lines cite a commit or an audit finding | Preamble | The brief. |
| N3 | Architectural choices go to the owner before they are recorded; an agent's choice is never written as settled; a recorded design is reversed only by a dated ruling named in its commit | The owner | The brief (the owner's working rules, relayed 2026-10-21); the owner's ruling of 2026-10-17 reversing a design taken inside a wave without him (recorded by the coordinator as "Loop the owner in"); lane 20 §4.1 and L8 (the reversals that held were rulings written down that day: 19fe1332, 57bf8e1d, 7203ef2e; agent reversals recurred). Never line: 595ed341 → ffa91113; 467fa2f5 → c4d38e9b. Lane 20 NQ5 had asked the question; the brief states the answer as settled. |
| N4 | Decisions one at a time, with full context; say plainly what each option costs and buys | The owner | D11 (quoted). "Plainly" is the owner's 2026-10-15 objection to tradeoffs hidden behind jargon (coordinator's record), consistent with D11's "full context". |
| N5 | The coordinator's delegation; what stays the owner's | The owner | D6; F §4. |
| N6 | Research before code; P0 first; no code of P0 before the whole plan is approved | The owner | D3, D1, D4. Stated for P0 only: whether D4 binds the parallel agent is DP-05, open, and the draft does not say. |
| N7 | Hard cutover, hard culling; no option selecting an implementation | The owner | D6 (quoted); the skill's ruling of 2026-10-17 (quoted). Never line: the owner's call of 2026-10-14 in 57bf8e1d (quoted), striking 552d682a. New to AGENTS.md as a bullet; it was the skill's and the lanes README's. |
| N8 | Done means built, run and passing on the four targets; type-checked is not built, built is not run | The owner | Current rows 1 and 21, made explicit by the history: lane 20 §2.3, L2 (waves landed type-checked, 10-14 to 10-18; not green since); 21 P-16 (101edbc5 landed with "the program suite has not been rerun": 403/480, repaired by 0be4e660). Not encoded: the per-step gate's further parts (stage-1 record, frozen invariant set, a receding frontier failing a step), which are G DP-22 and DP-07 (§3). |
| N9 | A claim carries its ground, and a number its measure, build and input | The owner | `proposals/README.md`'s grounds (read, measured, recalled, conjecture, decision); 21 P-18 (four measures in one table of walls), 21 P-9 (16005000's unmeasured claim). Not encoded: who measures, on which build, and whether every run leaves a record (DP-07). |
| N10 | A strict subset, never a contradiction; flags, pragmas and defaults mean what they mean upstream; upstream is the philosophy, not the oracle; we keep the language where upstream's compiler departs from it | What the compiler accepts | D12 with its refinement of the same day (the owner's clarification relayed by the coordinator, now in the proposal's D12). Never line: upstream's inliner deleting an unused pure `let` (`src/Compiler/Inline.idr:200-206`, D13's citation). |
| N11 | Eager evaluation is the meaning; only totality licenses deletion; `total` carries no divergence effect and lowers with `mustprogress`; a certain crash is compiled with no run-time test; totality not mandatory | What the compiler accepts | D13 (DP-01's first part). DP-01's second part (`exit`) is not encoded. |
| N12 | A copy kept in step by a verifier is still a copy | One fact, held once | The skill ("one fact, one place"); 21 P-5. |
| N13 | What the compiler knows about a program is compiled into it as a constant | One fact, held once | D10 ("at the compiler's run time or a compiled program's"); CT §1.1. |
| N14 | One op per semantics; families from lists; a flag that changes meaning splits the op; `idr` holds only what upstream's dialects do not mean | One fact, held once | D9's second half (quoted); the skill's "Map onto MLIR's grain" (one op per semantics; upstream dialects before ours). No op merge or split is encoded (each is the coordinator's or the owner's: DP-15, G DP-41 to DP-47). |
| N15 | A name is text for a human; every string that names a thing is a missing type | One fact, held once | The skill ("Every string that names a thing is a missing type"). Never lines: b9d4d592 (types digested by printing), 2ab5adf9 (a fixpoint by printed modules). |
| N16 | Our own C++ is concept-constrained templates; callbacks as template parameters; ladders as concept-constrained overloads or one fold over a closed sum; monomorphized, one explicit instantiation where compile time calls for it; template cost measured | The C++ | D7 (quoted three times), settling Q1, Q-M3, Q-llvm-1 and cxx-Q1 (DP-08). "A type-erased callback stays only where an upstream API takes one or the owner accepted it": synthesis A §2.7 (the lanes' cold `function_ref`s become exceptions the owner accepts case by case). "Measured, never assumed": synthesis E §2.10, the consequence the ruling's own relay drew. |
| N17 | Over ops, MLIR's dispatch where the op set is open; below it typed code; a concept reads ODS, never lists ops; no `isa` ladder | The C++ | D7. The skill's current wording ("never an `isa<A, B>` ladder or a C++ concept") contradicts D7; the proposal records the owner's approval of "never a ladder, and never a concept that lists ops" as pending (DP-08). The draft follows D7. |
| N18 | Every static fact a compile-time constant generated from TableGen and checked at build; runtime dispatch, tables, string compares and hash lookups of static facts only where the open op set forces them, each listed and justified | The C++ | D7 (its second half, near verbatim). |
| N19 | A choice is a type or an enum case, never a `bool`; nothing static per function; no attribute or type made on a worker's hot path; no pointer-keyed map holding per-node state; no per-query recomputation of a fact numbered once | The C++ | The skill ("a sum, never a flag"); the proposal's §5.2 "At run time", which it lists under D7 as settled; PS R2, R3, R5, R6. Never lines: 08 C-51, 21 P-19, d06ed15c (lane 20 L6), 02 T7, 7987388b (21 P-6), 98c6315c (PS M14), 1b2e31da (PS C13). See §4 item 3. |
| N20 | One effect system: one TableGen source for every effect fact; every reader generated or monomorphized; one query API; nothing else restates an effect | Effects | D9 (quoted), settling the structure (DP-04); the proposal's §5.1 "The structure is settled"; EF §2.8. |
| N21 | A function's effects derived from its ops by one derivation and verified per function; a call carries its callee's; effects reach LLVM; the tree's shape (crash, `exit`, the world) is the owner's | Effects | D9; proposal §5.1 (one verifier rule; the LLVM attributes generated). Worded "held to it" rather than "equals": EF §4.1 refines equality to containment after every pass and equality at each write, a choice it returns to the owner (EF §6.8). Never lines: 02 §3.1, 02 §3.7, 04 C26, 12 CV-05; the landing trap (02 §8; proposal §5.1 "Landing"). |
| N22 | Upstream first, then upstream patched, then our own solver named as what it is, in one solver layer whose composition and threading are explicit; upstream not dropped with the middle step skipped | Analyses and solvers | D2 (quoted); the order is the proposal's goal ("upstream first"). Never lines: 595ed341, ffa91113, wave1/5.1 A4, 0451b1b8, 16005000 (lane 20 §3.1, §4.2 item 1); 06 L-17. Not encoded: the scale-measurement gate for adopting or removing upstream (G DP-24, whose AGENTS.md wording is returned to the owner). |
| N23 | A fact is computed once and kept (analysis manager, preserved; across passes in a type or verified property); a mechanism found by one fix is written once and shared; what an analysis admits changes only in a commit that says so | Analyses and solvers | D10 applied to analyses; the skill ("use the infrastructure: the `AnalysisManager`"); lane 20 L4 (one mechanism written three times). Never lines: 05 §2.2, R5; synthesis C §1; 21 P-14; 21 P-3. |
| N24 | A solve's state is sized by the problem | Analyses and solvers | The proposal's §1 finding ("whole-program state per value is the shape of every memory wall"). Never lines: ffa91113 (PS C7), b8301ebe (PS C8), e96bb991 (PS C10), 16005000 (PS C9), PS §3. The representation that replaces it (dense ids, CSR, the shared types) is G DP-52 and DP-53, not encoded. |
| N25 | The Idris side is refactored where the representation calls for it, type-driven, within the subset both hosts compile | The Idris side | D8 (quoted); the skill's type-driven half. |
| N26 | The TTC keeps every fact a reader would rebuild; the frontend reads each once, at the boundary, into a typed table | The Idris side | D10 ("a fact an earlier stage knew or could have kept counts as known"); proposal §5.6; synthesis D §2.1. Never lines: 17 FB-01, FB-15, FB-10; 16 FC-79; 14 R06, 15 RS-1. |
| N27 | A fact both sides hold is generated to both from ODS; a `.td` change the Idris side names lands with the Idris side it regenerates | The Idris side | Current rows 4 and 5 with hard cutover (N7): the frontend would not build otherwise, and a shim is a second copy (synthesis D §5 D1: "settled in substance"). G DP-23 records the same as a coordinator decision; the draft states only the consequence of settled rules. Never lines: 14 E14, 16 FC-78, 19 G6. |
| N28 | PINS.md and `upstream/` change in the commit that changes what they describe | Upstream and pins | Current row 19 (PINS.md records every pinned workaround; the PINS.md entry lands with its patch; a patch goes when nothing reaches its bug) and lane 20 L5. Never lines: synthesis A B9 (`NeverRuns`), 17 FB-18 (`paramPos`), lane 20 H2, H3 (patches 06, 28, 63; PINS.md; the table missing 62, 63). |
| N29 | Never: a test that names a pass | Tests and checks | Current row 20 applied (a pass rename is an unrelated change); 28274bd3; 19 T1-T3. The generated pass table that would replace the names (19 C2, 13 T2) is not encoded. |

## 3. Deliberately not encoded

Open decisions (proposal §4) and the coordinator's drafts under review (G),
which the draft leaves alone or states only as the settled principle:
- DP-01's second part (`exit`), DP-02 (the world), DP-03 (what is ordered
  with what): the draft says the tree's shape is the owner's to rule.
- DP-05 (the fence on the parallel agent): N6 names P0 only.
- DP-06 (`Positions`): 101edbc5 appears only as evidence (order recomputed
  per query; a landing without the program suite; `decides` narrowed
  silently), never as a design for or against the numbering.
- DP-07 (the stage-1 record) and G DP-22 (the step gate): N8 and N9 keep
  to the current checks and honest reporting.
- DP-09, DP-10 (scope with 0003, 0011, 0009); DP-11 (out of memory);
  DP-12 (the in-place promise; only the current rule's violation is
  cited); DP-13, DP-14 (space and stack promises); DP-15 (the match's
  form); DP-16 (borrows); DP-17 (the scalar primitives' meaning; row 8
  kept as written); DP-18 (crash statuses; the crash-as-text example is
  the current AGENTS.md's); DP-19 to DP-21.
- G DP-24 (measure before adopting, patch before dropping, at stage-1
  scale): only D2's order and the history are stated.
- G DP-53 (dense ids, CSR, the solver layer's types), DP-60
  (verification's cost), DP-73 (`match` against `std::visit`), DP-74
  (precompiled headers), DP-75 (hardening), DP-80 (stack probes; only the
  current violation is cited), DP-81 (test hooks; the live-cell example is
  the current AGENTS.md's): none is a rule in the draft.
- The decide / apply / restructure shape of the pipeline (13 T1), actions
  per solve unit, determinism across thread counts (G DP-34), no WIP on
  main (lane 20 H7; the lanes README allows WIP that builds): not encoded.

## 4. For the reviewer, first

1. **D1 and D4 in AGENTS.md.** They are rulings about the current queue,
   not lasting rules; the draft states them in one bullet (N6) so the
   ruling binds while it holds. They could live in `proposals/README.md`
   instead.
2. **The skill's wording.** D7 is followed (N17); the skill still reads
   "never an `isa<A, B>` ladder or a C++ concept" until the owner approves
   the new wording (DP-08). Installing the draft without the skill's
   change leaves the two contradicting.
3. **N19's run-time rules.** The proposal's §5.2 lists them under D7 as
   settled; PS calls its rules (R2, R3, R5, R6) design inputs, not
   settled. The draft states the four §5.2 lines and none of PS's
   mechanisms (`Materializer`, chunking, CSR).
4. **Lane evidence marked "read".** Three never lines rest on code read,
   not reproduced, and say so: the stack guard (18 R-STK-1, R-STK-2), the
   in-place promise (08 NQ1), and the summary ignoring its ops (02 §3.7;
   synthesis A B1-B3 mark B1 and B3 as conjecture of reach). The last is
   written as what the code does (the summary's derivation ignores the
   ops), which is read; whether a miscompile follows is not claimed.
5. **Citations that will move.** `audits/p0/` may be folded into proposals
   and deleted, as the 10-19 audits were (91615083); commit hashes stay.
   If the audit goes, its IDs in the draft should become the commits or
   the proposal sections that hold them.
