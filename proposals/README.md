# Proposals

Designs that have not been decided yet, one file each, numbered in the
order they were written: `NNNN-short-name.md`. A proposal states what it
would change, which rules of AGENTS.md and `findings/` it keeps, the
staged plan, the alternatives it rejects and the questions it leaves for
the user. Claims are marked as in `findings/` (read, measured, recalled,
conjecture, decision).

When the user decides, the decision moves to `findings/decision-*.md` and
the plan becomes work; the proposal stays as the record of the reasoning,
with its status line updated (accepted, accepted in part, rejected,
superseded by NNNN). Nothing here is a specification: the code is.

- [0001](0001-rust-interop.md): Rust as the one foreign world: bindings
  generated from rustdoc's JSON, shims linked as bitcode, Rust values in
  counted cells, ownership as the compiler's grades.
