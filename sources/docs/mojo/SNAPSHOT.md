# Snapshot: Mojo documentation on its MLIR-based design

- **Upstream:** `modular/modular` on GitHub (the Mojo standard library, MAX and the Mojo
  documentation sources; rendered at https://docs.modular.com/mojo/). The Mojo compiler
  itself is not in the repository.
- **Revision:** `main` at `135c332fec9b326cab8e2f3951a0b2f31d017a5d` (committed
  2026-10-09T07:29:04Z UTC; `git ls-remote https://github.com/modular/modular.git HEAD`).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/modular/modular/135c332fec9b326cab8e2f3951a0b2f31d017a5d/<path>`
  (HTTP 200 each). The files were located from the recursive tree listing
  (`https://api.github.com/repos/modular/modular/git/trees/<rev>?recursive=1`, 13,236
  entries, not truncated).
- **Paths:** relative to the repository root (so `Mojo/docs/site/...`).
- **Files:** 5.
- **Licence:** Apache-2.0 with LLVM Exceptions (the repository's `LICENSE`: "The Modular
  repository is licensed under the Apache License v2.0 with LLVM Exceptions"), which covers
  the documentation sources in the repository; not copied here.
- **Threads:** F, G (topic: Array languages and typed array programming / lowering target).

**What is here and why.** The openly licensed documentation of how Mojo is built on MLIR:

- `Mojo/docs/site/reference/inline-mlir.mdx` — the user-facing reference for
  `__mlir_type`, `__mlir_attr`, `__mlir_op` and `__mlir_region`: how a language exposes
  MLIR types, attributes and operations (with properties and regions) from source.
- `Mojo/docs/stdlib/internal/pop_dialect.md` — the internal `pop` ("parametric
  operations") dialect: parametric SIMD and array types (`!kgen.simd<size, dtype>`,
  `!pop.array<size, type>`), elaboration of parameters, and `pop.cast_to_builtin` /
  `cast_from_builtin` bridging to MLIR builtin types and `vector`.
- `Mojo/docs/stdlib/internal/mlir.md` — internal note on `always_inline("builtin")`: how
  dependent parameter expressions such as `T[a+b]` stay symbolic and fold at elaboration.
- `Mojo/docs/site/manual/parameters/index.mdx` — the parameter (compile-time value)
  system: the `SIMD[dtype, length]` case study and `rebind`, which defers a type equality
  to elaboration.
- `Mojo/docs/site/faq.md` — the FAQ's statement on hardware lowering through LLVM-level
  dialects and other MLIR-based backends.

Internal documents are marked by upstream as private APIs subject to change; they describe
the design at this revision only.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `Mojo/docs/site/reference/inline-mlir.mdx` | 26,357 | `944c10bb8c8e3f8928d9e988bee8ff83fc0b0dbd3015852f0c8e6be75b18c997` |
| `Mojo/docs/stdlib/internal/pop_dialect.md` | 7,539 | `31f3def01524a637fd65b9046ef55df86a61e32dd14d78e2041decbdc65bcb4c` |
| `Mojo/docs/stdlib/internal/mlir.md` | 3,077 | `3ed2df469ea5fad1804f08bbcb87ae71ba049a40e5e0b1db33fc22a3759653c3` |
| `Mojo/docs/site/manual/parameters/index.mdx` | 45,988 | `da6bb8a6a7becee4317dce7d892c819ce870379aabc3b921599f5f049f826087` |
| `Mojo/docs/site/faq.md` | 12,696 | `3f9111f1b4aeb7a572570221d3d09afc94d08850551c7ee6f46eed5af68cf618` |

**How to fetch more.** `curl -L --fail -o <file> https://raw.githubusercontent.com/modular/modular/135c332fec9b326cab8e2f3951a0b2f31d017a5d/<path>`.
The standard library's MLIR use (`Mojo/stdlib/std/builtin/simd.mojo` and the like) is in
the same tree.
