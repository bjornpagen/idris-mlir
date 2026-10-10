# Snapshot: GHC's vectoriser (excerpts, before its removal)

- **Upstream:** `ghc/ghc` on GitHub (mirror of `gitlab.haskell.org/ghc/ghc`), `compiler/vectorise/`.
- **Revision:** `13a86606e51400bc2a81a0e04cfbb94ada5d2620`, the parent of
  `faee23bb69ca813296da484bc177f4480bcaee9f` ("vectorise: Put it out of its misery", Ben Gamari,
  2018-06-02, Phabricator D4761), the commit that deleted the vectoriser, the `ParallelArrays`
  extension and the `vector` and `primitive` submodules. Its message: "Poor DPH and its
  vectoriser have long been languishing; sadly it seems there is little chance that the effort
  will be rekindled." This is a different, older revision than any other GHC snapshot in the
  library, hence its own folder.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/ghc/ghc/13a86606e51400bc2a81a0e04cfbb94ada5d2620/<path>`; the
  removal commit's metadata from `https://api.github.com/repos/ghc/ghc/commits/faee23bb69ca813296da484bc177f4480bcaee9f`.
- **Paths:** relative to the GHC repository root (so `compiler/vectorise/Vectorise/Exp.hs`).
- **Files:** 11 (plus this file).
- **Licence:** The Glasgow Haskell Compiler License, BSD-3-Clause style (`LICENSE`, "Copyright
  2002, The University Court of the University of Glasgow").
- **Topic:** Flattened data: packed, columnar and nested layouts (cluster `flattening`).
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `LICENSE` | licence |
| `compiler/vectorise/Vectorise.hs` | the pass entry point over a module's bindings and type constructors |
| `compiler/vectorise/Vectorise/Exp.hs` | expression vectorisation: `vectAvoidInfo` (classifies subexpressions as simple, parallel or complex) and `encapsulateScalars` (vectorisation avoidance: lift maximal scalar subexpressions as one closure instead of vectorising them) |
| `compiler/vectorise/Vectorise/Generic/Description.hs` | the generic sum-of-products description of a user data type (`SumRepr`, `ConRepr`, `ProdRepr`), the shape `PData` is generated from |
| `compiler/vectorise/Vectorise/Generic/PData.hs`, `PAMethods.hs` | generation of the `PData`/`PDatas` instances and the `PA` conversion methods per data type |
| `compiler/vectorise/Vectorise/Type/Classify.hs`, `TyConDecl.hs`, `Type.hs` | which type constructors must be vectorised (a data type with vanilla constructors is vectorised only when a type in its definition is, so every type that involves `[::]` directly or indirectly is, and enumerations are not) and how their declarations are rewritten |
| `compiler/vectorise/Vectorise/Utils/Closure.hs` | building closures with scalar and lifted code and an environment |
| `compiler/vectorise/Vectorise/Builtins/Base.hs` | the names the vectoriser expects from the DPH libraries |

**Not taken.** The rest of `compiler/vectorise/` (monad, environment, naming, hoisting, other
utilities; 29 files in all at this revision) and the desugarer's parallel-array support. Fetch more
with the raw URL pattern above; the full list is
`https://api.github.com/repos/ghc/ghc/git/trees/13a86606e51400bc2a81a0e04cfbb94ada5d2620?recursive=1`.

## File manifest

Every stored file except this one: 11 files, 137,709 bytes in all. Computed 2026-10-09 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                                bytes  path
e06c13b8a117652621781c15d622bd4c62c568307954f7136955b4b656d14ec1       1611  LICENSE
b34b410dc7f9349d2a14b02033f0f5960535b4a235df86a6dc9eb9e9e7940716      14115  compiler/vectorise/Vectorise.hs
41e8c8b14e7836c7c1fe1ff4efa3de0d4834a8a9ee6f2e79fdb7c66a9bc7dbb3       8557  compiler/vectorise/Vectorise/Builtins/Base.hs
01a2bb28483c15ab002c310d8b16a36be5b0102c6072a6c05ac5543ba0363bf5      49710  compiler/vectorise/Vectorise/Exp.hs
36838721cce62642c35dc82a265522b7cb15a5933930386b8104faa4be046b85       9870  compiler/vectorise/Vectorise/Generic/Description.hs
65fa6db176c6547dd05368a41399c2f7006cdc92db63ac9b1bca207ea3105607      22306  compiler/vectorise/Vectorise/Generic/PAMethods.hs
8f9f393e4a7d80d55a03f45ee204a02844cd604cde04f0dbc0cb368eede9df99       6840  compiler/vectorise/Vectorise/Generic/PData.hs
ba51c7e88956971b71e531aaee23edf98f6fdbf57e7e3fb5c90ed364fba0b8c4       6138  compiler/vectorise/Vectorise/Type/Classify.hs
883fb88738b42c68c0367a3927a57c2ae6205c33e5d93c434208c3247a47bd96       9526  compiler/vectorise/Vectorise/Type/TyConDecl.hs
89b4d7804ea2a8a45d75f94d7b05728804804a5c2c47d2023de0541028fbbb60       2963  compiler/vectorise/Vectorise/Type/Type.hs
47424f263f509127baa15952a0bb07d10415bef647875109c67df15a7b8e4fd9       6073  compiler/vectorise/Vectorise/Utils/Closure.hs
```
