# 13. Diagnostics

There are two kinds of error:
- **User errors.** The program is outside the profile. These are reported by
  the Idris side, at Idris source locations.
- **Internal errors.** The compiler broke its own contract. These are bugs.

## User errors

- **DIAG-CODE-1 (v0).** The error code is the violated rule's identifier
  (`PROF-*`, or `FE-ENTRY-3` for `-o`). There is no separate numbering.
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
- **DIAG-EXIT-1 (v0).** `idris-mlir --check` exits with status 1 on any user
  error and writes no artifact (`FE-ART-1`).
- **DIAG-ONE-1 (v0).** Compilation stops at the first user error. Reporting
  several errors at once is a later improvement.

## Internal errors

- **DIAG-ICE-1 (v0).** These are internal errors:
  - a `Core.Check` failure;
  - a contract violation found by `idr-check-input` or a verifier;
  - any pass failure in `idris-mlir-cc`;
  - any failure of the upstream tools on our output.

  They are reported as `idris-mlir: internal error: <stage>: <message>`, with
  the MLIR location, which is an Idris source location (`IDR-LOC-1`).
  - Each one is a bug. Its fix comes with a regression test.
  - An internal error MUST never be downgraded into a user error, or the
    reverse.
- **DIAG-ICE-2 (v0).** When the compiler cannot tell whether a construct is
  supported, it reports a user error with the most specific rule that applies
  (`GOAL-P3`). It never continues and hopes that a later stage copes.
