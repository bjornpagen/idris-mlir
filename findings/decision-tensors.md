# Decision: pure array programs are tensors

The user decided this on 2026-10-09: "tensors should definitely be tensors,
pure array programs is one of the heavy hitting features of mlir and we
cannot lose this."

- **What.** An array that no world orders is a value, and in MLIR a value
  array is a `tensor`: built, read, sliced and combined by `tensor` and
  `linalg` ops on tensors, until One-Shot Bufferize turns it into memrefs.
  Arrays that the program mutates in the order its world gives (base's
  `IOArray`, the linear arrays of `libs/mlir-linear`) stay memrefs from
  birth, as every array is today (read: `substrate.md` S6, "our arrays are
  memrefs from birth, mutated in world order").
- **Why.** Upstream's array machinery works on tensors:
  - fusion and tiling of `linalg` on tensors;
  - bufferization in destination-passing style, "with aggressive in-place
    bufferization", which decides in-place updates over the whole function
    and copies "as little memory as possible" (read:
    `sources/docs/mlir/docs/Bufferization.md`);
  - SPMD partitioning across the core grid, whose sharding is a property of
    a tensor ("Define a sharding of a tensor"; read:
    `mlir/include/mlir/Dialect/Shard/IR/ShardOps.td` at the pin).

  These are single-thread wins first (fusion, in-place updates), and the
  multicore path second, which is the order
  `decision-single-thread-first.md` asks for.
- **What it settles.** Open question 5 of `README.md` ("should pure array
  programs exist as tensors before bufferization"): yes. `substrate.md` S6's
  SPMD step no longer waits on it. It waits on the work that makes array
  programs tensors.
- **What it does not settle.** Which Idris array operations are pure enough
  to be tensors, where bufferization runs in the pipeline, and how its
  in-place decisions meet `idr-rc`'s grades. A design note decides those,
  with the in-place promise (`substrate.md` §3) as its check.
