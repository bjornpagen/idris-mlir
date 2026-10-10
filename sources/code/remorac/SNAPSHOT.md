# Snapshot: remorac (the 2015 Remora compiler front end)

- **Upstream:** `jrslepak/remorac` on GitHub (https://github.com/jrslepak/remorac), "Compiler
  for a rank-polymorphic array language" (OCaml, written while the author was at NVIDIA).
- **Revision:** `master` at `9bfe4ac37e87f2d314d02a3eb0236db8af903965` (last commit
  2015-08-20).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/jrslepak/remorac/9bfe4ac37e87f2d314d02a3eb0236db8af903965/<path>`.
- **Paths:** relative to the repository root (so `src/remora-internal/typechecker.ml`).
- **Files:** 13.
- **Licence:** BSD-3-Clause, © 2015 NVIDIA Corporation (`License.txt`; each source file
  carries the same header).
- **Threads:** typed-rank (Array languages and typed array programming); G.

**What is here and why.** The pass pipeline from the explicitly typed AST to a
`Map`/`Rep` IR, which is the compilation scheme that dissertation chapter 11 formalizes:
- `README.md`, `design.txt` (the author's design notes: annotation passes over a persistent
  AST; "Annotating with frames" explains the argument-expansion annotation that `Rep`
  needs), `License.txt`.
- `src/remora-internal/basic_ast.mli`, `annotation.mli` (the AST and its annotation
  machinery).
- `typechecker.{ml,mli}`: `idx_equal` (lines 181–193: a dimension is a constant plus a
  multiset of variables; shapes compare pointwise), `canonicalize_typ`, `frame_contribution`
  (284–302: peel the argument type until the cell type matches), `prefix_max` (323–343) and
  the `App` case (408–435) that assembles the principal frame.
- `frame_notes.{ml,mli}`: the app-frame and argument-expansion annotations.
- `erased_ast.{ml,mli}`: the type-erased AST.
- `map_replicate_ast.{ml,mli}`: the `Map`/`Rep` IR; `of_erased_idx` (lines 129–156) turns indices into term-level values (sorts become `int` and shape types; its comment:
  "We can determine how to split an array into mapping pieces given just
  the total number of pieces"); `defunctionalized_map` (195–231) handles an array of
  functions by mapping an `apply` lambda over function and argument cells; the `App` case
  (255–294) emits a `Rep` per argument and one `Map` over the principal frame.

**Not taken:** the tests (`test_*.ml`), `closures.ml`, `globals.ml`, `substitution.ml`, the
s-expression front end, `compiler.lyx`, the examples. Nothing was built or run.

**How to fetch more.** Same URL pattern; tree at
`https://api.github.com/repos/jrslepak/remorac/git/trees/9bfe4ac37e87f2d314d02a3eb0236db8af903965?recursive=1`.

## File manifest

Every stored file except this one: 13 files, 119,622 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
b1f88d94fd27cb8f3057696cc91c0b210bdeb24f95b98bbdb91cb8bd23ec10a8       1485  License.txt
262adad37951b68176ce7190b52cfe3c0a3fe4693127fbcb1f05644fd82bcf1e        281  README.md
5042b8c9f238ad97c519c925b8d0c8e8072bf990decbbfefeacb59bde2e3b227       3566  design.txt
6e157f2f68e655c307d9531874170b118785e5fc7d74abaebefee8446e95534a       2858  src/remora-internal/annotation.mli
6f93e0557c715bcd0de4fa595288a9e6eab223998dda646276251cef743f49ce       5445  src/remora-internal/basic_ast.mli
4d7ea717d2439957d727daaeaa3d5d6ed3ac2fae41a569c5ae540775c241e8ac      21545  src/remora-internal/erased_ast.ml
7e847f3271f2b616670ea4c5d5374f65de51fec5d058ea08c38e895c1918fc73       6725  src/remora-internal/erased_ast.mli
dafa144233035ed9502671db3119881381d09e86eeb7788c06e7dffa44e5d864      11898  src/remora-internal/frame_notes.ml
195c6edff222c14f4c4353514b926c270051eb64b20abdcc457fb73dacce541e       4010  src/remora-internal/frame_notes.mli
714ef1b605d659f035c69e4f485c4003ab8577c53622ba15dd8ecd33e2181513      21474  src/remora-internal/map_replicate_ast.ml
8cb9009ae61c3ea8b293f6563d624f5d45a58478f28f536a1b2b3bc2bc4a8491       5629  src/remora-internal/map_replicate_ast.mli
466a4a706455fccdae7e8a106b5996144a892f1fe9aa187d85ea13d1d9f0f5ac      30675  src/remora-internal/typechecker.ml
38c8ccdd07b14cf064b7116220a3f8246aa4977479ba6d09998c31396f41912a       4031  src/remora-internal/typechecker.mli
```
