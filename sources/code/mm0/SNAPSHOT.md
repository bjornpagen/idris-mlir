# Snapshot: Metamath Zero verifier core (`mm0-c`) and the MM0 specification

- **Upstream:** `digama0/mm0` on GitHub (https://github.com/digama0/mm0).
- **Revision:** default branch (`master`) at `0d414c0bfdaaeb7fea571895127abc1fa5a3d956`
  (committed 2026-09-30), the HEAD resolved with `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/digama0/mm0/0d414c0bfdaaeb7fea571895127abc1fa5a3d956/<path>`.
- **Paths:** relative to the repository root (so `mm0-c/verifier.c`).
- **Files:** 12.
- **Licence:** CC0 1.0 Universal (`LICENSE.txt`).
- **Threads:** kernels-trust (Fast dependent type checking and elaboration).

**What is here and why.** The whole trusted verifier, as the paper presents it, and the two
formats it reads:
- `mm0-c/verifier.c` (the `.mmb` proof-stream and unify-stream interpreters `run_proof` and
  `run_unify`, and the declaration loop `verify`), `mm0-c/verifier_types.c` (the fixed-size
  stack, heap, store and unify arrays and their limits; the 32-bit stack words with a 2-bit
  tag), `mm0-c/types.c` (the `.mmb` header, term and theorem tables, the 64-bit binder type
  with a 55-bit dependency bitset), `mm0-c/parser.c` (the `.mm0` parser the verifier checks
  every statement against), `mm0-c/index.c` and `mm0-c/verifier_debug.c` (error reporting
  only; `-D BARE` removes it), `mm0-c/main.c` (mmap of the proof file, `.mm0` from stdin),
  `mm0-c/README.md` (build modes and limits);
- `mm0-c/mmb.md` (the binary proof format), `mm0.md` (the `.mm0` specification language),
  `README.md`, `LICENSE.txt`.

The `.c` files total 2,857 lines with comments and blank lines (`wc -l`), against the
README's "under 3,000 lines of C".

**Not taken:** `mm0-rs/` (the MM1 elaborator, compiler and language server, Rust),
`mm0-hs/`, `mm0-lean/`, `mm0-lean4/`, `examples/` (`peano.mm1`, `mm0.mm0`, `x86.mm0`,
`verifier.mm0`, the bootstrap specifications), `site/` (the thesis PDF is stored as
`papers/carneiro-2022-metamath-zero-thesis`), `mm0-rs/mmc.md` (the Metamath C compiler) and
`mm0-rs/mmb-lisp.md`. The tree is listed by
`https://api.github.com/repos/digama0/mm0/git/trees/0d414c0bfdaaeb7fea571895127abc1fa5a3d956?recursive=1`.
Nothing was built or run.

## File manifest

Every stored file except this one: 12 files, 185228 bytes in all. Computed 2026-10-09 over
the stored copies; check with `shasum -a 256 <path>` from this folder.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `LICENSE.txt` | 6555 | `36ffd9dc085d529a7e60e1276d73ae5a030b020313e6c5408593a6ae2af39673` |
| `README.md` | 10855 | `a62a362b425e74cdfa0881c74a5ca08adc7951876d770757b6a2f9f6d5994e46` |
| `mm0-c/README.md` | 4637 | `5ada16e00cd2f72e7f83d247768cde6ade34e56962b1858bc014fabedc900a70` |
| `mm0-c/index.c` | 3974 | `88214d057ad2c1e7569357022948c0cea1417b2b82a3fe5ce2f8c61bb176a1ac` |
| `mm0-c/main.c` | 2066 | `ecde31379241e38ca0b375df0f40b216e9108f6cfd45952ccb282658d883de17` |
| `mm0-c/mmb.md` | 39485 | `e93f3058650104b3f538fd8b2c583239c1e2fb076c7a75fa93b4fe93c16bc9a0` |
| `mm0-c/parser.c` | 29009 | `695bf56b4fe190e6ba369a8be854cd1031b2624929fc5fda995551e7bad00c39` |
| `mm0-c/types.c` | 13375 | `b3fc325b9269f50298b1d388c80b6544845a7185bc99df0dd9970ff306a215d1` |
| `mm0-c/verifier.c` | 31817 | `71428a117c96a37b81e183ce57ef34b71e99efecba019e65a47ce27dd4faa4b5` |
| `mm0-c/verifier_debug.c` | 9105 | `6db6e3dd5f4edf11a0a019bae785c5cde43dcc2601dcd7f11e90f9c7190b0ca1` |
| `mm0-c/verifier_types.c` | 6047 | `87a0b9470de5ae0beff5edfa565952520957a39b250591b0067ebc4786b5490e` |
| `mm0.md` | 28303 | `ccea6dcd3b19c4b83f1bebf735738cd8cb97517643fca3f0eb4e8ebfd61492f1` |
