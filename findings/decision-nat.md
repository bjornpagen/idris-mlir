# Decision: the representation of Nat and Integer

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

## Integer gets the same treatment

Integer is Nat without the lower bound, so both types go through one
machinery with equal sophistication: the same range interface, the same
narrowing pass, the same inline fast path and the same loop versioning.

- Integer's ranges come from:
  - constants;
  - bounded ops on bounded operands;
  - casts from `Int` or `Bits*`, which are exactly their width's range;
  - `natToInteger` of a bounded Nat;
  - loop counters that are only ever incremented or decremented within
    bounds.
- An Integer proved to fit is a plain `i64` with `nsw`.
- Nat only adds the lower bound 0, seeded from its type.

## One hop to the digits

- **Today a big outside the small range costs two dependent loads:** the
  word, then the cell, then GMP's separately allocated limbs (`limbs` in
  `idris_rt_bignum`).
- **Bigs are immutable, so the limbs belong inline:**
  - the cell is the header, the size, then the limbs;
  - reads are a zero-cost `mpz_roinit_n` view of the cell;
  - results are computed into a stack `mpz`, or with `mpn_` directly into
    a cell of the exact size, and allocated once.
- **The chain gets shorter:** word → cell holding the digits, one hop,
  contiguous, so the adjacent-line prefetcher covers the digits.
- **References stay raw, canonical, untagged addresses:**
  - an even word is exactly the cell's address;
  - no high-bit tags, no compression, no NaN-boxing;
  - that is the form a hardware pointer prefetcher recognizes. Apple's
    data-memory-dependent prefetcher (M1–M3) and Intel's (Raptor Lake)
    both prefetch values that look like pointers into the heap.
  - Our tag lives only in bit 0 of small values, which are never mistaken
    for pointers.
  - It's an invariant of the layout, with a `static_assert` next to the
    packing.
- **Scope:** arm64 macOS is the next first-class target, and it runs on
  Apple silicon, where the DMP follows these references. The layout is
  written for it now.

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

- `tri 500` and `acc+2` print their expected output, which matched Chez's
  when it was committed, and are timed against a C `uint64_t` loop.
- The ir property holds: a counted-down loop has no tag test inside.
- A Nat past 2^62 still prints right, through GMP.
- Integer's proofs match Nat's: an Integer loop from `cast` of an `Int` bound runs
  untagged.
- A large big's digits are one load from its word (no `limbs` pointer
  in the cell).
