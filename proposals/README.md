# Proposals

Designs that have not been decided yet, numbered in the order they were
written: one file, `NNNN-short-name.md`, or, for a design compiled into
work for a swarm of agents, one directory, `NNNN-short-name/`, whose
`README.md` is the proposal and whose other files are the contracts,
lanes and dispatches it is executed from. A proposal states what it
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
- [0002](0002-representation-cutover/README.md): the representation
  cutover (W1 to W10 of `findings/README.md`) as a swarm packet of 23
  lanes. Ownership is declared on ops and grades, partial ops become
  guards, closure conversion moves to MLIR's region isolation, thunks
  become memo sums, compile-time evaluation runs the program's own
  lowering, constants are flat, base's surface becomes runtime
  primitives, and the acyclic-heap and in-place promises become checks.
- [0003](0003-llvm-trunk.md): the LLVM pin moves from `llvmorg-23.1.2` to
  a commit of llvm main, so that each patch we carry is its pull request,
  and the toolchain is one recipe for both targets.
