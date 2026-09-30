# Decision: the representation of Nat

Nat is the most common number in Idris code: lengths, indices, `Fin`,
counters, fuel. It has to cost what a machine word costs wherever the
program lets it, and stay arbitrary-precision where it does not. There are
two tiers.

## Tier 1: proved range, a plain word

- **The representation:** a Nat whose values are proved to fit is a plain
  `i64`, with no tag, no GMP path and no call. Its ops are `arith` with
  `nuw`/`nsw`, so SCEV, vectorization and `int-range-optimizations` see
  ordinary integers.
- **How we prove it:** the ops that compute on naturals and bigs implement
  `InferIntRangeInterface`. Their ranges are 64-bit, and "may not fit a
  small" is top.
- **Where it lives:** the proved range lives in no attribute. A narrowing
  pass reads `IntegerRangeAnalysis` and rewrites every web of `!idr.nat`
  values it proves fits into `i64` arithmetic. The consumer rewrites the IR;
  nothing is stored.
- **What a Nat can be bounded by:**
  - constants;
  - bounded ops on bounded operands;
  - a value that only decreases from a bounded one (a predecessor chain,
    and a loop that counts down to `Z`);
  - `Fin n`, which is below `n`;
  - a count of heap cells, which the address space bounds.
- **Loop versioning:** a loop whose counter only decreases (the size-change
  fact) tests once, on entry, that the counter is small, then runs as an
  untagged `i64` loop. The unproved entry value costs one test, not one per
  iteration.

## Tier 2: unproved range, the tagged big

- **The runtime form stays `Integer`'s:**
  - small: low bit 1 and a signed 63-bit value;
  - big: low bit 0, a pointer to a cell holding the GMP integer.

  So `natToInteger` stays the identity. The sign bit Nat never uses costs
  only the values in [2^62, 2^63), which go to GMP. That is worth less
  than a free conversion.
- **The fast path is in the IR, not in a runtime call.** `idr-lower` emits
  the small case inline, with branch weights, for `!idr.nat` and `!idr.big`
  alike. Only the cold path calls the runtime.
  - **add:** both small (`a & b & 1`), then `llvm.sadd.with.overflow(a, b - 1)`.
    Overflow is exactly leaving the small range.
  - **sub:** `ssub.with.overflow(a, b - 1)`.
  - **mul:** `smul.with.overflow(a >> 1, b - 1) + 1`.
  - **pred:** of a natural proved nonzero, it is `a - 2`, which cannot
    overflow.
  - **compare:** of two smalls, it compares the tagged words themselves.
  - **clamp** (`nat.from_big`): a small negative becomes the small 0.
- The runtime's functions stay the one meaning (AGENTS.md). Folders call
  them, and the inline path is only their small case, restated.

## Why not the alternatives

- **An unsigned small form for Nat:** it buys one bit and makes
  `natToInteger` a branch.
- **Unary Nat, or Nat compiled as written:** that is O(n). It is the bug
  this replaces (`tri 500` overflowed the stack).
- **A runtime call per op, left for LTO to inline:** MLIR then never sees
  the arithmetic, so range analysis cannot remove the tag test.
- **i64 for every Nat:** it would silently wrap. Idris's Nat has no bound,
  and a miscompile is never acceptable.

## Proved by

- `tri 500` and `acc+2` match Chez, and are timed against a C `uint64_t`
  loop.
- The ir property holds: a counted-down loop has no tag test inside.
- A Nat past 2^62 still prints right, through GMP.
