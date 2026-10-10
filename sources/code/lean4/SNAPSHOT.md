# Snapshot: Lean 4 rewriting, abstraction and substitution

- **Upstream:** `leanprover/lean4` on GitHub (https://github.com/leanprover/lean4).
- **Revision:** default branch (`master`) at `7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f`, the
  HEAD resolved with `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/leanprover/lean4/7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f/<path>`.
- **Paths:** relative to the repository root (so `src/Lean/Meta/KAbstract.lean`).
- **Files:** 7 (6 sources and `LICENSE`).
- **Licence:** Apache-2.0 (`LICENSE`; each file's header says the same).
- **Threads:** dependent-equality (Array languages and typed array programming).

**What is here and why.** How Lean's `rw`, `generalize` and `subst` build motives, and the
"motive is not type correct" error:
- `src/Lean/Meta/KAbstract.lean` (69 lines: `kabstract` at 30–67, keyed matching: a subterm is a
  candidate only when its head symbol and argument count match the pattern's, then `isDefEq`;
  occurrence selection with metavariable-context rollback);
- `src/Lean/Meta/Tactic/Rewrite.lean` (`MVarId.rewrite`: abstract, `check motive`, the
  "motive is not type correct" message and its explanation at lines 58–73, the "Motive is
  dependent" check at 74–79, proof by `congrArg`);
- `src/Lean/Elab/Tactic/Rewrite.lean` (the tactic front end);
- `src/Lean/Meta/Tactic/Subst.lean` (`substCore`: revert the dependents, eliminate with
  `Eq.rec`/`Eq.ndrec`, and the `hAux.symm` trick at lines 97–108 that avoids an ill-typed
  motive when the goal depends on the equation itself);
- `src/Lean/Meta/Tactic/Generalize.lean` (`generalize`: `kabstract` then "result is not type
  correct"; the remark at lines 80–128 on why transparency is `implicit`: keyed `isDefEq`
  matching can blow up, Lean issue #3524);
- `src/Init/Tactics.lean` (the user-facing docstrings of `rw`/`rewrite` at 600–637, `subst`
  at 182–199, `simp` at 700–729, `generalize` at 1057–1064, `omega` at 1541–1572).

**Not taken:** the simplifier (`src/Lean/Meta/Tactic/Simp/`), `omega`'s implementation
(`src/Lean/Elab/Tactic/Omega/`), `grind`, the reference manual. To fetch more, use the same
raw URL pattern at this revision; the tree is listed by
`https://api.github.com/repos/leanprover/lean4/git/trees/7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f?recursive=1`.
Nothing was built or run.

## File manifest

Every stored file except this one: 7 files, 158,750 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
8b28515ffffc5c0fe2807d8ae3735b00b324d9b7ce807dd63ff6ac8922fbce7e       9160  LICENSE
982d2602ee1aee72783522e02387e5301f612b71e80234892d45994c0a041e16     114891  src/Init/Tactics.lean
ee24161d476a4379e07bee6b481bb24918677316afb2da2de1a06eb849ebc55e       5924  src/Lean/Elab/Tactic/Rewrite.lean
f9e8539020646b17761a0284f1774be2653e64d90a540a5d93aef784518ff67c       2756  src/Lean/Meta/KAbstract.lean
befa26929e3b94d01304228219b9aab7faae5eb215f2a3bd3bc088462a0249b8       7237  src/Lean/Meta/Tactic/Generalize.lean
9d3c22f93b20dca270ee73ac0e008968f4fa8c37bbb1a0604fc53d4f7bcd86af       5564  src/Lean/Meta/Tactic/Rewrite.lean
0fe317e03d0fe8aab9d6b210793f56b6de677b68364a6aa33093ec1f1b309f5f      13218  src/Lean/Meta/Tactic/Subst.lean
```
