<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane accept-reject: what was done

Scope: `tests/accept`, `tests/reject`, `tests/compiler`, `tests/registry`,
`tests/two-levels`. Only files in that scope were edited; no compiler code
and no harness file (`tests/lib`, `tests/runner`, `tests/Main.idr`) was
touched. Every remaining test was run on this build (arm64 macOS) with
`make test only=<path> threads=2`; `make check` ran too (30/32: the two
failures, `spec/file-size` and `spec/licenses`, are outside this scope;
`spec/rules-covered` passes with the renamed and new reject fixtures).

After the change: accept 36 fixtures (26 pass), reject 43 fixtures and
`without-fixture` (42 pass), compiler 12 (8 pass), registry 6 (2 pass),
two-levels gone. No NEEDS-ACCEPTANCE mark is left in the scope. Every
failure left is a compiler bug or the harness's tree printer (listed below).

## Deleted

| path | reason |
| --- | --- |
| accept/action-run-at-once | prints 2; its closure claim is checked nowhere |
| accept/division | the partial-division boundary it stood on is gone |
| accept/fib, map-pair, pair-maybe, partial-application | generic programs at no boundary of the profile |
| accept/partial-integer | describes compile-time evaluation, which is not built |
| accept/runtime-data-first-of-two, runtime-data-list, runtime-data-prelude-list | boundary of a removed refusal of runtime data |
| accept/runtime-integer, runtime-integer-prelude | boundary of a removed refusal of runtime Integer |
| accept/runtime-string-compared | negative control of a claim nothing checked |
| accept/static-integers, static-list | compile-time evaluation; cites a fixture that does not exist |
| accept/default-pragma | shown by reject/pragma-default-with-inline, whose only error is the `%inline` |
| accept/runtime-partial-integer, runtime-partial-stream | describe a fuel budget; what they check (it compiles) is accept/nonterminating's |
| accept/equality-proofs | `sym` and `replace` are already run by registry/identity-hook; its comment cited a version |
| accept/action-after-effect | cannot fail as written (the division never crashes). Rewritten so the division crashes, the build crashes before printing "ready": whether `let action = report d` evaluates `report`'s strict `let` at the binding or when the action runs is not decided by any contract here (Idris's `let` is strict, its optimizer may inline a single-use let), so neither expectation is a specification. Left for the IO-trace model (below) |
| accept/partial-stream, accept/streams | replaced by accept/stream-take and stream-take-before (below) |
| reject/deprecated-buffer-data, deprecated-set-byte | same `deprecatedDef` entry kind as deprecated-get-byte, which stays as the rule's smoke fixture |
| reject/escape-hatch-phrase-in-comment | guarded a removed harness that counted phrases; otherwise escape-hatch-believe-me |
| reject/pragma-inline | the same refusal as pragma-default-with-inline |
| reject/polymorphism-growth-family-sum, polymorphism-growth-recursion | pinned the growth check's incompleteness: both programs have finitely many instances, so a better check that compiles them correctly would fail the test |
| compiler/module-location | pinned the printed module's last line |
| compiler/elaboration-error | moved to reject/elaboration-undefined-name (below) |
| compiler/main-visible | split into accept/main-private-in-import and reject/program-main-ambiguous (below) |
| two-levels/terms | its values are this compiler's output, frozen from a run Chez agreed with, with no level above them since 08a065e4; it times out and hits bug 5.12 today |
| reject/layout-256-counted-fields, layout-512-counted-fields, layout-768-counted-fields, primitive-shl, program-base; registry/base-surface, string-iterator | only an untracked `output` of a deleted test was left |

## Rewritten, merged, added

- **Imports added** (they never elaborated under the always-on
  `--no-prelude`): accept/bounded-family-{applied,head,higher,partial,scope},
  erased-elem-match, erased-elem-later-match, erased-index-forced-index,
  higher-order-dictionary, show-dependent-pair, reject/polymorphism-nested-data
  (header line moved 11 to 13). All pass, except higher-order-dictionary,
  which now shows a compiler bug.
- **accept/higher-order-dictionary**: it used `%search`, which the profile
  refuses as a pragma. The dictionary now comes from `found : Eq a => () ->
  Eq a`, applied to `()`, the same claim without the refused construct.
- **accept/stream-take, stream-take-before**: the two stream programs with
  the compile-time-evaluation premise and dead references removed. They stay
  separate because they fail differently (a wrong value, a hang), and one
  program would let the hang hide the wrong value.
- **accept/fused-stored-string, recursive-string, indexed-tags**: their
  comments' claims ("no string is built at runtime", "a value is only its
  tag") are now checked by the `heap-free` mark, run through `e2e_io`.
- **accept/unreachable**: its unreached `Integer` is no longer outside the
  profile. The unreached definition is now `system "true"`, which the
  profile refuses where it is reached.
- **accept/growing-specialization-function**: "its closures are built on
  the heap" was an implementation claim; the comment now states what is
  checked (accepted, and every closure freed).
- **accept/main-private-in-import** (new, from main-visible): a private
  `main` in an imported module is not seen; the program prints "main".
- **reject/program-main-ambiguous** (new, from main-visible): `-- expect:
  program, line 1` and `-- message: Helper.main`. The rule and site are
  checked, not the words.
- **reject/elaboration-interface-body, elaboration-totality-depth-pragma**
  (renamed from idris-*): the header names the rule `elaboration`, the
  one user-error rule, not `idris`. In interface-body, the use of the
  dropped type is removed. Its two follow-on Idris errors made the rule
  appear three times, and the claim "refused, not dropped" still fails if
  the declaration is dropped (the program would then compile).
- **reject/elaboration-undefined-name** (new, from compiler/elaboration-error).
- **reject/cycle-ioref-knot**: the mark was removed and the header kept at
  line 18 (SUMMARY §8). It fails on bug 5.29.
- **reject/without-fixture**: the `elaboration` line is gone, since three
  fixtures now state the rule. Its reasons cite files and definitions, not
  line numbers (every cited line had drifted). The `hook` line no longer
  cites the deleted base-surface.
- **compiler/content-hash**: the run script copies Ids.idr with the Prelude
  import that stock Idris adds implicitly. It now compiles, and the program
  then fails on a new bug (below).
- **compiler/handoff-readable**: four checks removed:
  - `instance` on every idr.func: it is optional in ODS (SUMMARY §8);
  - "old forms": those ops no longer parse, so the check could not fail;
  - "nothing erased": no `erased` mnemonic exists, so it could not fail;
  - "every op located": `Loc.Unlocated` is generated code's documented
    location, and the synthesized entry and the module carry it.

  It keeps the symbol, program and stage, and no-func-dialect checks.
- **compiler/handoff-round-trip**: no longer compiles
  tests/programs/data/shapes, which the programs lane deletes.
- **compiler/frontend-command-line**: the "undefined" case no longer expects
  the frontend to print Idris's error. It checks that the module was written
  and that `idris-mlir --report` on it reports `elaboration Main.idr:6`.
- **compiler/probe-names**: it now enumerates every one-name probe at
  small arguments, axes through their term, and eight non-probe names. A
  probe is compared with what is read back by constructor and arguments,
  not by name, so a non-injective `probeName` fails. It prints three
  lines, not 24 spellings.
- **registry/broken-entry**: case 2's Main imports `Builtin` and `PrimIO`,
  which `Prelude.IO` imports privately, so it reaches the validation and
  passes. The "unbroken" case and its Main.idr are gone: every other test
  compiles that program.
- **registry/registry-only**: the test programs are excluded by category,
  and their exclusion is written in the run script: the dialect samples
  (SyntaxSamples.idr) and the googletest boxes. The 7 hits left are the
  compiler's own (below).
- Marks removed where the test passes or fails on a listed bug:
  accept/bounded-synonym, bounded-field, bounded-method-own,
  polymorphic-recursion-swapped, compiler/dialect-syntax,
  handoff-round-trip, handoff-readable, registry/scalar-bytes.

## Left failing, each on a compiler bug (SUMMARY §5 numbers)

| test | bug | evidence |
| --- | --- | --- |
| accept/stream-take | 5.20 | prints 34, expected 55 |
| accept/stream-take-before | 5.20 | run times out at 60 s, expected 63 |
| accept/string-primitive-runtime-match, polymorphic-recursion-swapped, bounded-synonym | 5.12 | `'llvm.call' op operand type mismatch: expected 'i64', provided '!llvm.ptr'` (in the last two as an internal error) |
| accept/runtime-lazy-value-growing-choice | 5.10 | `idris-rt: live cells 48` |
| registry/nat-operations | 5.10 | `idris-rt: live cells 1` |
| accept/recursive-string | 5.13 (heap-free broken) | `idr.str.show_sint` and `idr.str.append` allocate in `@Main.digits`: the output-fusion clone its comment describes is not made |
| accept/higher-order-dictionary | **new** | `unsupported (static argument): Prelude.EqOrd.(==): an implementation that does not reduce to its constructor: (Main.HasEq.eqOf Int ...hole)`: one implementation, which the whole program fixes, read from a record field, is refused (against AGENTS: a set the whole program fixes compiles) |
| accept/bounded-field, bounded-method-own, registry/pointer-handles, registry/scalar-bytes | 5.38 | compile exit 1, 40 lines of `File name too long` from the harness's `--mlir-print-ir-tree-dir` |
| reject/cycle-ioref-knot | 5.29 | refusal at line 16, the header (Passes.td's placement) says 18 |
| compiler/artifacts | 5.32 | `stale artifacts after the failure: build/exec/Main.<hash>.o` |
| compiler/dialect-syntax | 5.33 | the samples' root `@sample` breaks the root type rule (SyntaxSamples.idr) |
| compiler/handoff-round-trip | 5.8 | linarray-combinators: `'linalg.generic' op consumes a view, which holds no reference` |
| compiler/content-hash | **new** | compiles in 12 s, then the program (XXH3-128 of the frontend's own Ids.idr) prints nothing and runs past 300 s (measured: killed at 300 s, 242 s user). A hang or catastrophic slowness of compiled code, not of the harness |
| registry/registry-only | code rule ("every string that names a thing is a missing type") | `Walk.probeName` builds 6 names from literals (`idris-mlir-hole`, `-hole-found`, `-var`, `-formal`, `-field`, `-held`) and `Forced.patternOf` builds `UN (Basic "->")`: compiler-made names need one typed home |

## For the orchestrator: outside this scope, now stale

- **tests/Main.idr**: the `two-levels` pool, `--two-levels-program`, and
  `--two-levels-check` now have no test. `tests/lib/two-levels.sh` and its
  line in `testutils.sh` are dead too, and so is the `two-levels/` mention
  in tests/README.md and the Makefile comment. `tests/TwoLevels.idr` is
  still read by Fuzz.idr's self-checks (`TwoLevels.checks`) and by
  `tests/fuzz/two-hosts/expected-stdout`, so it goes with the search lane's
  plan for two-hosts.
- **tests/lib/profile.sh**: the `idris` header branch of `profile_reject`
  is now unused. No fixture names `idris`; three name `elaboration`.
  rules-covered's comment about `idris` is stale too.
- **tests/programs/prelude/prelude-math/Main.idr:9** cites the deleted
  accept/partial-integer, and its compile-time-evaluation premise with it.
- **tests/ACCEPTANCE.md** lists many of the deleted tests (machinery deletes it).

## What a future generator or harness must cover

- **Growth generator** (§4.4): take the two deleted shapes as seeds.
  - The family-sum shape: `W m n = T (m g x) n` with `m = \g, x => g (List x)`.
  - The stuck type-level recursion: `Two (S (S k)) = (Int, Two k)` behind
    `wrap : (n : Nat) -> Two n -> ...`, called once at a constant.

  The oracle is "refused at the cycle, or compiled with the stdout the
  graph computes". Both programs are finite, so the improvement must be
  allowed to compile them.
- **Registry pool** (AR-14): one program per Forbidden or Deprecated entry,
  including `bufferData` and `setByte` (deleted here) and every
  `deprecatedForeign` entry, which no fixture ever reached.
- **IO-trace and laziness model** (G9): it must first decide when a
  let-bound action's strict `let` runs (at the binding, or when the action
  runs). Then it should generate the deleted action-after-effect shape with
  a faulting division, and action-run-at-once's shape.
- **Refused-or-correct header** (AR-6): a reject header that also accepts
  a correct compile, so a known limit is data, not a passing test.
- **Header with a file** (AR-4): `-- expect: <rule>, <file>:<line>`. The two
  `Data/Evil.idr` fixtures still cannot check their file.
- **Universal emitted-module properties** (AR-8, AR-9): on every
  compilation, in place of handoff-readable's greps and
  handoff-round-trip's two programs:
  - the round trip;
  - no func dialect before lowering;
  - block symbol names;
  - every op whose origin is not Generated carries a location. That needs
    the origin in the module; today it cannot be told from the print.
- **Two-levels' replacement** (AR-16): Sem-style tables for String, Char,
  Double and Integer from the runtime's documented meaning, and Prelude
  laws over Gen-generated values. Nothing comes from a compiler's printed
  values.
