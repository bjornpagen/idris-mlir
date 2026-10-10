# Snapshot: lean4lean (the Lean 4 kernel in Lean)

- **Upstream:** `digama0/lean4lean` on GitHub (https://github.com/digama0/lean4lean); the
  plan's `leanprover/lean4lean` does not exist ("Repository not found").
- **Revision:** default branch at `8223d223ed98661882e95d9d6a7126df7097cd76`, the HEAD resolved
  with `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/digama0/lean4lean/8223d223ed98661882e95d9d6a7126df7097cd76/<path>`.
- **Paths:** relative to the repository root.
- **Licence:** Apache-2.0 (`LICENSE`; file headers say the same).
- **Threads:** elaborators (Fast dependent type checking and elaboration).

**What is here and why.** The paper is `papers/carneiro-2024-lean4lean/`.
- `Lean4Lean/TypeChecker.lean` (979 lines): the kernel's `Methods` record and `RecM` monad,
  `inferType` with the `inferTypeI`/`inferTypeC` caches, `whnfCore`/`whnf` with their caches,
  lazy delta reduction, `isDefEq` with the union-find `EquivManager` and the failure set.
- `Lean4Lean/EquivManager.lean`: the union-find defeq cache (structural, with pointer and
  hash shortcuts). Note: the C++ kernel at the Lean pin of this pass replaced it with plain
  success/failure pair sets (see `code/lean4/src/kernel/type_checker.h`, lines 33–41).
- `Lean4Lean/Instantiate.lean` (`cheapBetaReduce`), `Lean4Lean/PtrEq.lean`,
  `Lean4Lean/Expr.lean`, `Main.lean` (the checker CLI, multithreaded per module),
  `README.md`, `bugs-found.md`, `LICENSE`.

**Not taken:** `Theory/`, `Verify/`, `Experimental/` (the metatheory and proofs, about 2 MB),
`Inductive/`, `Primitive.lean`, `Environment*.lean`, `Level.lean`. Nothing was built or run.

## File manifest

Every stored file except this one: 9 files, 73,332 bytes in all.

```
SHA-256                                                               bytes  path
c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4      11357  LICENSE
d99076acb5b384936133d8c6e28879953cacc31b749b6e6cd938809f00e40aa1       2142  Lean4Lean/EquivManager.lean
27777912eaabbe8daa2c7a7109eefd3ac03d10fb02fba8243f6629da10c00bc7       3659  Lean4Lean/Expr.lean
ae08b31657faf3b54de22688ae287d0bff362c573d6a2dd09f12f417b1975ec2       1036  Lean4Lean/Instantiate.lean
395e6b6907e548582d9e40e37f5344d6919e597500608c597048e621f27f0aa2        886  Lean4Lean/PtrEq.lean
32a426fb2cd092d2cc973866ac91adb44b3b91c463891b78c21d95c864fbf808      41774  Lean4Lean/TypeChecker.lean
3816b2088b5dfe3e036097e52015d7bf703b7c9671e171baadcd46583551c14d       6301  Main.lean
d824830a89fdac384c8090e954874ea9c131c0e521787bd866a73497ddeeec45       5872  README.md
825bbfbb2422975c17d22fc6bbf872c365582167ebfed3f1b1743a7a8cd9be7a        305  bugs-found.md
```
