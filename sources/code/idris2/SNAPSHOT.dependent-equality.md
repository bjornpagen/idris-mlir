# Addendum to code/idris2/SNAPSHOT.md: rewriting and with-abstraction

To be merged into `code/idris2/SNAPSHOT.md` (same upstream, same revision, same path rule).

- **Revision:** `1c630e67c386629a0fbbc6b78a59176fde7f0a76` (the `third_party/Idris2` pin).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/idris-lang/Idris2/1c630e67c386629a0fbbc6b78a59176fde7f0a76/<path>`;
  each file was compared with `cmp` against the pinned checkout and is byte-identical.
  (`compiler/idris/src/TTImp/Elab/Rewrite.idr`, this repository's fork, differs only in
  threading the delayed-elaboration reference `dl`.)
- **Files added:** 8.
- **Licence:** BSD-3-Clause (verify), as for the rest of the snapshot.

**What is added and why.** How Idris 2 elaborates `rewrite` and `with`:
- `src/TTImp/Elab/Rewrite.idr` (`elabRewrite`: normalise the expected type, replace every
  subterm convertible to the rule's left-hand side by a fresh variable, wrap it as the
  predicate `\v => ...`, and fail with `RewriteNoChange` if nothing changed; `checkRewrite`
  applies the `%rewrite` lemma; the predicate is not type-checked on its own);
- `src/Core/GetType.idr` (line 10: `getType` gets "the type of an already typechecked thing";
  `elabRewrite` applies it to the unchecked predicate);
- `src/Core/Normalise.idr` (`replace'`, lines 243–312: the abstraction, a conversion check at
  every subterm of the normal form);
- `libs/prelude/Builtin.idr` (`Equal`, `rewrite__impl` with an erased predicate and rule and a
  linear value, `%rewrite Equal rewrite__impl`, `replace`, `sym`, `trans`: lines 118–180);
- `src/TTImp/ProcessDef.idr` (the `WithClause` case of `checkClause`, lines 441–640: the
  "magic with" abstraction through the same `replace`, the auxiliary with-function, the
  `Syntactic` flag that abstracts without normalising);
- `src/TTImp/Elab/Utils.idr` (`bindNotReq`/`bindReq`: the split of the context into the part
  the with-value needs and the part generalised over it);
- `src/TTImp/WithClause.idr` (matching each with-clause's left-hand side against its parent's);
- `libs/base/Data/Nat.idr` (the arithmetic lemmas users rewrite with: `plusZeroRightNeutral`,
  `plusCommutative`, `multCommutative`, ...).

**Fetching more.** Any other file at the same pin, read-only: read
`third_party/Idris2/<path>` in place (the checkout is at this pin), or
`curl -sL --fail -o <path> https://raw.githubusercontent.com/idris-lang/Idris2/1c630e67c386629a0fbbc6b78a59176fde7f0a76/<path>`.

## File manifest

Every stored file except this one: 8 files, 127,628 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
8f1b8949799e2d75243765b0569b223ee07538253a1eddc095288e10e3ece1ad      27056  libs/base/Data/Nat.idr
15f4ef41dc3294bd418eebf0c18efe503b4e60854011ee0554906ba1d808621a       7535  libs/prelude/Builtin.idr
a3dde5306de03ccc7043e16ef03a8d9b7cd1fe224c78b44033c69739276f4625       4876  src/Core/GetType.idr
cf50bf53ac9afa23bd6faa6a9abf6aa1273d258011bec04b342a6045b35922e3      12475  src/Core/Normalise.idr
da0484a8d8655c136cb94d64661b747279526bbf87ec32ac73bc6205a7b7f26e       5904  src/TTImp/Elab/Rewrite.idr
682a1c075603838bf5f0621345d7d1a4312d75bb6dd69d24365719d58ae91eda      10458  src/TTImp/Elab/Utils.idr
adb540925af31bd113af1c9a0223901e437718997fd6dc81315876341cfdb799      48053  src/TTImp/ProcessDef.idr
7847cb8e55014514df2132492368daebd6d29652c8f7d0f84091bef7297a3d19      11271  src/TTImp/WithClause.idr
```
