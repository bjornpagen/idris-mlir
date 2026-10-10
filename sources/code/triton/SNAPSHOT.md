# Snapshot: Triton MLIR dialects (selected ODS)

- **Upstream:** `triton-lang/triton` on GitHub.
- **Revision:** `main` at `11523f38065f52a8117dc3c4d74a2ac59936c19e` (committed
  2026-10-09T23:32:37Z UTC; `git ls-remote https://github.com/triton-lang/triton.git refs/heads/main`).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/triton-lang/triton/11523f38065f52a8117dc3c4d74a2ac59936c19e/<path>`
  (HTTP 200 each).
- **Paths:** relative to the repository root (so `include/triton/Dialect/...`).
- **Files:** 3.
- **Licence:** MIT (the repository's `LICENSE`: "Copyright 2018-2020 Philippe Tillet,
  Copyright 2020-2022 OpenAI", MIT terms); not copied here.
- **Threads:** G (topic: Array languages and typed array programming / lowering target).

**What is here and why.** Today's Triton is an MLIR compiler; the LLVM-based Triton-IR of
`papers/tillet-2019-triton` was replaced by these dialects:

- `include/triton/Dialect/Triton/IR/TritonOps.td` — the `tt` dialect: block-level tensor
  ops (`tt.load`/`tt.store` on tensors of pointers with masks, `tt.splat`, `tt.broadcast`,
  `tt.trans`, `tt.dot`, `tt.make_range`, `tt.get_program_id`) and, notably, `tt.reduce`
  and `tt.scan` with a combiner region over an axis.
- `include/triton/Dialect/Triton/IR/TritonTypes.td` — its tensor and pointer types.
- `include/triton/Dialect/TritonGPU/IR/TritonGPUAttrDefs.td` — the `ttg` layout
  encodings attached to `tensor` types (blocked, slice, dot-operand, MMA and linear
  layouts), which say which thread, warp and CTA owns which element.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `include/triton/Dialect/Triton/IR/TritonOps.td` | 51,228 | `b7b5154993687a5e1cb7f6f88878d3af206626f1fe7c87c0d62734b32a05b9a2` |
| `include/triton/Dialect/Triton/IR/TritonTypes.td` | 5,758 | `976748bbb03e51a6a241db0c08117207c195209d2c9db9beb80eda2bd0b5e446` |
| `include/triton/Dialect/TritonGPU/IR/TritonGPUAttrDefs.td` | 62,416 | `91b94dfc582b8955e84db9162fb597ae94beb8f54a38f0f7f639dc04f08073e7` |

**How to fetch more.** `curl -L --fail -o <file> https://raw.githubusercontent.com/triton-lang/triton/11523f38065f52a8117dc3c4d74a2ac59936c19e/<path>`.
The linear-layout definition is `include/triton/Tools/LinearLayout.h`; the passes are
under `include/triton/Dialect/TritonGPU/Transforms/Passes.td`.
