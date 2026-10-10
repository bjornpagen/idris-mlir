# Snapshot: GHC compact regions (Compact Normal Forms)

- **Upstream:** `ghc/ghc` (GitLab `gitlab.haskell.org/ghc/ghc`, mirrored at `github.com/ghc/ghc`).
- **Revision:** tag `ghc-9.14.1-release`, commit `902339d332fb4ce2b3c87dcac1ee6495d41ad886`
  (`git ls-remote` of both hosts, 2026-10-09; the same 9.14.1 series as `docs/ghc/`).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/ghc/ghc/902339d332fb4ce2b3c87dcac1ee6495d41ad886/<path>`.
- **Paths:** relative to the repository root (so `rts/sm/CNF.c`).
- **Files:** 7.
- **Licence:** The Glasgow Haskell Compiler License, BSD-3-Clause style (`LICENSE`); the
  `ghc-compact` library states `license: BSD3` with its own `libraries/ghc-compact/LICENSE`
  (portions by Giovanni Campagna under the same licence).
- **Threads:** flat (packed-trees), D.

**What is here.** The runtime and library implementing `yang-2015-compact-normal-forms`:

- `rts/sm/CNF.c`, `rts/sm/CNF.h`: Note [Compact Normal Forms] (structure of a CNF as a chain of
  blocks with `StgCompactNFDataBlock` headers, the invariants "self-contained" and "only
  immutable data: no thunks, functions or mutable objects", `BF_COMPACT` block flags for the
  constant-time membership test, the 252-block limit per compact block, appending by a
  Cheney-style scavenge, the sharing-preserving hash table, and pointer fixup on import).
- `libraries/ghc-compact/GHC/Compact.hs`: the user API (`compact`, `compactWithSharing`,
  `compactAdd`, `compactAddWithSharing`, `getCompact`, `inCompact`, `isCompact`, `compactSize`,
  `compactResize`) and its documented limits (no functions, no pinned byte arrays, no mutable
  pointer fields; `CompactionFailed`).
- `libraries/ghc-compact/GHC/Compact/Serialized.hs`: `SerializedCompact`,
  `withSerializedCompact`, `importCompact`.
- `libraries/ghc-compact/ghc-compact.cabal`, both `LICENSE` files.
