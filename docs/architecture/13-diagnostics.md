# 13. Diagnostics

There are two kinds of error:
- **User errors.** The program is outside the profile. These are reported by
  the Idris side, at Idris source locations, including those that
  `idris-mlir-cc` finds (`DRV-CC-2`, *since the cutover*).
- **Internal errors.** The compiler broke its own contract. These are bugs.

## User errors

- **DIAG-CODE-1 (v0).** The error code is the violated rule's identifier
  (`PROF-*`, or `FE-ENTRY-3` for `-o`; also `HOOK-SHAPE-1`, and from the
  cutover `SEM-HOST-1` and `EVAL-1`). There is no separate numbering.
- **DIAG-FMT-1 (v0).** A user error is an Idris `GenericMsg` with the message:

  ```text
  mlir backend: <Idris full name>: unsupported (<RULE-ID>): <what, in source terms>
  ```

  For example: `mlir backend: Prog.total: unsupported (PROF-TYPE-2): Integer
  in a runtime position`. The name is the definition being compiled. The
  text names the offending construct in source terms, not TT terms.
- **DIAG-LOC-1 (v0).** Every user error carries a non-empty `FC`, the most
  specific one available:
  1. the offending term's `FC`;
  2. otherwise its binder's;
  3. otherwise the definition's `location`;
  4. otherwise the start of the module.

  *Rationale:* `idris2 --check` exits non-zero only for errors that carry a
  source location. This was verified: an error with `EmptyFC` exits 0.

  TTC keeps no term locations, only each definition's `location`. So for IO
  programs, which Idris loads from TTC under `-o`, errors point at the
  enclosing definition or case block, not at the term itself.

  From v3, an error found inside library code (the Prelude, `Builtin`,
  `PrimIO`: the *Report at caller* column of the library table,
  [17-registry](17-registry.md)) is reported at the innermost user
  definition that reached it, and names the library location in
  parentheses: `Main:11:1: ... (in Prelude.Cast:83:1)`.

  *Revised at the cutover:* an error that `idris-mlir-cc` finds carries the
  op's MLIR location chain: inlining and specialization nest the locations
  of the code they copy inside those of the call, and `Emit` wraps the
  location of library code in `loc(fused<"library">[...])` (`IDR-LOC-1`).
  The frontend reports the innermost location in the chain that is not
  library code, and names the library location in parentheses as above.
  - Test: `tests/profile/v3/reject/PROF-TYPE-4-prelude-integer.idr`
- **DIAG-EXIT-1 (v0).** `idris-mlir --check` exits with status 1 on any user
  error and writes no artifact (`FE-ART-1`).
- **DIAG-HEAP-1 (v1).** A rejection of dynamic allocation (`PROF-HEAP-*`,
  `PROF-TYPE-4` for bigs, `PROF-DATA-3`, `PROF-PRIM-4`) explains why the
  value survived. *Revised at the cutover:* `idr-check-profile` reports it,
  and it gives:
  1. the op that allocates (a closure, a box's constructor, a string
     builder, a big op), with its location chain (`DIAG-LOC-1`);
  2. why it survived: for a closure, the functions that may reach it are
     not a finite set, or its captures contain it; for a string, the use
     that is not output; for a box or a big, the operand that is not a
     constant;
  3. where the value is used, as a secondary location.

  With `--remarks=idr-eval` and the other passes' remarks, `idris-mlir-cc`
  also reports the specialization or the evaluation that stopped: a
  `Missed` remark for a call the growth check or the clone limit stopped
  (`ELIM-SPEC-2`), naming which, or an evaluation that crashed
  (`ELIM-EVAL-1`).

  For example:

  ```text
  mlir backend: Main.label: unsupported (PROF-HEAP-3): string built at runtime
    by `strCons` at Main.idr:9:9, from a value known only at runtime, is
    returned by Main.label instead of being written by putStr
    (used at Main.idr:14:3)
  ```

  An `EVAL-1` error names the call and what ran out, at the call's
  location:

  ```text
  mlir backend: Main.main: unsupported (EVAL-1): the compile-time evaluation
    of Main.ackermann at Main.idr:12:10 ran out of stack
  ```
- **DIAG-ONE-1 (v0).** Compilation stops at the first user error. Reporting
  several errors at once is a later improvement. *Revised at the cutover:*
  "first" means the frontend's errors, in its stage order (`04-frontend`),
  then `idr-check-profile`'s, in the order of the ops in the module after
  the pipeline. (Before, it was evaluation order within `Simplify`, and
  `PROF-HEAP-5` came last.)
  - Test: the reject fixtures whose programs break two rules, of which the
    expected one comes first (`TEST-REJ-1`)

## Internal errors

- **DIAG-ICE-1 (v0).** These are internal errors:
  - a module that does not parse, or that fails the MLIR verifier, when
    `idris-mlir-cc` reads it or after any pass (*revised at the cutover*:
    this replaces the checks of `Core`, `CORE-CHECK-1`, and
    `idr-check-input`);
  - any pass failure in `idris-mlir-cc` other than a profile rejection
    (exit status 3) or `EVAL-1` (exit status 4), and any signal in
    `idr-eval`'s child but those of `EVAL-1`;
  - any failure of the upstream tools on our output.

  They are reported as `idris-mlir: internal error: <stage>: <message>`, with
  the MLIR location, which is an Idris source location (`IDR-LOC-1`).
  - Each one is a bug. Its fix comes with a regression test.
  - An internal error MUST never be downgraded into a user error, or the
    reverse.
- **DIAG-ICE-2 (v0).** When the compiler cannot tell whether a construct is
  supported, it reports a user error with the most specific rule that applies
  (`GOAL-P3`). It never continues and hopes that a later stage copes.
  - Check: review (a design rule for every check)