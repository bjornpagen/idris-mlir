# Snapshot: Dedukti kernel

- **Upstream:** `Deducteam/Dedukti` on GitHub (https://github.com/Deducteam/Dedukti).
- **Revision:** default branch at `f3c0eba869ddd46f2e75c123a59f2b612076dba0` (committed
  2026-07-01), the HEAD resolved with `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/Deducteam/Dedukti/f3c0eba869ddd46f2e75c123a59f2b612076dba0/<path>`.
- **Paths:** relative to the repository root (so `kernel/reduction.ml`).
- **Files:** 31 (the whole `kernel/` directory, 29 files, plus `README.md` and `LICENSE`).
- **Licence:** CeCILL-B (`LICENSE`).
- **Threads:** kernels-trust (Fast dependent type checking and elaboration).

**What is here and why.** The type checker of the λΠ-calculus modulo rewriting, the
reference checker that `papers/farber-2022-kontroli` measures against:
- `kernel/term.ml{,i}` (de Bruijn terms; `App` keeps the head and a spine),
  `kernel/reduction.ml{,i}` (the lazy abstract machine `state_whnf` with a context of lazy
  terms and a stack of shared mutable states, rewriting through decision trees, and
  `are_convertible`: physical equality, then syntactic equality, then whnf of both sides and
  structural comparison), `kernel/typing.ml{,i}` (bidirectional inference and checking of
  terms and of rewrite rules, using `srcheck.ml` to type a left-hand side by its most general
  typing substitution), `kernel/dtree.ml{,i}` and `kernel/matching.ml{,i}` (compiling the
  rules of a symbol into a decision tree; Miller-pattern matching), `kernel/rule.ml{,i}`,
  `kernel/signature.ml{,i}`, `kernel/subst.ml{,i}`, `kernel/exsubst.ml{,i}`,
  `kernel/ac.ml{,i}` (matching modulo AC), `kernel/confluence.ml{,i}` (export to an external
  confluence checker: Dedukti does not check confluence itself), `kernel/basic.ml{,i}`.

`kernel/*.ml{,i}` total 5,528 lines with comments and blank lines (`wc -l`); Färber counts
3,470 lines of code (Tokei, no comments or blanks) for `kernel/` at the older revision
`38e0c57`.

**Not taken:** `parsing/`, `api/`, the command-line tools, `tests/`, and Lambdapi
(`Deducteam/lambdapi`, the interactive successor, whose `src/core/` was listed at
`220752a204365c5d1591bcdf76079e1749268c0f` but not stored). Nothing was built or run.

## File manifest

Every stored file except this one: 31 files, 227962 bytes in all. Computed 2026-10-09 over
the stored copies; check with `shasum -a 256 <path>` from this folder.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `LICENSE` | 21392 | `733d2ce442237034fd3db55bc7d952303272531c5591d91db3ad8c5381423b93` |
| `README.md` | 15497 | `7aa3fb963af2678a04536aecbbca8e36330f431cf75170854ce49cf16c2aa0c6` |
| `kernel/ac.ml` | 1843 | `420c81118bb8e13077753b788799a2e31b83e9f2d8f3747940b337a4e4fc0866` |
| `kernel/ac.mli` | 794 | `7ff9428c0060672b66e725b1dbcda2de501509d561686b8fec0af01daf02bcd6` |
| `kernel/basic.ml` | 4347 | `3e6c7b608bdab85af21e8f47cc1c24aee80a25bda75220aa35ec8e4603c89a86` |
| `kernel/basic.mli` | 4782 | `3196894e3a957fba80208dec3a152b60ad90c9371c4d247ebe38319bc227690d` |
| `kernel/confluence.ml` | 7656 | `a8503c47abd49f330da381342e9f36c6daa07462e6aaec46314ba69aaad6d9f0` |
| `kernel/confluence.mli` | 482 | `4b31e46fd79ffad71546712d1982225719b34aa66918626e02106ea81b6c0964` |
| `kernel/dtree.ml` | 25577 | `1c1fc965ef5936b310639abbb34b76aa0d432843c7950dd64256b9eea1f4c458` |
| `kernel/dtree.mli` | 6937 | `3bc5733c255e671163db12cf224689e0b06efc61c0cedc434ab9523a47277f9c` |
| `kernel/dune` | 73 | `582735170dce6e32037c82b9ee11b5966e35f75ad3169bd2322156486460e329` |
| `kernel/exsubst.ml` | 5026 | `e395d645d859c7f9b5bba5a3c8d934c76ef9b00c1fd8d04b559c8024244bc353` |
| `kernel/exsubst.mli` | 1746 | `de4f1bf2bf369a43515e2cf103eb4179d6fd152a2e1819e3cbce713cf9af91da` |
| `kernel/matching.ml` | 21252 | `3e9a9d42af2d1773c3a0f3859944d8d1d68066234aa9f78a12b12c7f99fd855e` |
| `kernel/matching.mli` | 1371 | `df124eb5d5ae4abe2a3eb4bce35ef85c90a66c32cfbf8394789b58a91dd524e2` |
| `kernel/reduction.ml` | 25339 | `384f18b5e2e1a606e5720b6c30b3381c7d9442af6da356dba92329dfcc6ac218` |
| `kernel/reduction.mli` | 4010 | `9ce0a8aa282a7d2c42cec5ef64187adda8670b5d49936915e646decb99158845` |
| `kernel/rule.ml` | 10800 | `a2a4bd124258b22a4e8d0bfc7d8766e5725a3ac78ab21a0e31579bdfdb9c8351` |
| `kernel/rule.mli` | 4142 | `18d0ef3dce83f366d6f963e97c1c321cb152da4581dd3f66b85cc11e534a847c` |
| `kernel/signature.ml` | 12640 | `1eb630cfdd961cb22fa7fb7e5c7392a1e31e062a0e313cc7b1e90429420d881e` |
| `kernel/signature.mli` | 5330 | `b1a2bbede6774fe83ced78671773c45927c5a91d472d42ade6f3647d3fc7d692` |
| `kernel/srcheck.ml` | 14617 | `4e9676461a7179feeeb741b1e6e726c11686e2c2f10455742d52d45b8faa1ac9` |
| `kernel/srcheck.mli` | 1316 | `5e283642de7b3709b2e5aef3bfaeccf5e90297cf253e95a2cf8bad4c920dacff` |
| `kernel/subst.ml` | 2643 | `b2d586546c1ae9f0feb580d143b4adf76ce7eca95a2e55c26fb518ddc146cf15` |
| `kernel/subst.mli` | 1804 | `09193604156d366819956066d869b1ba676d5a49b7ca2665b745a331b2ac278f` |
| `kernel/term.ml` | 5605 | `d40ab476f502dfa614d58b281e111fd3a2fb158680c61d48ce272d3b8fe0b8bf` |
| `kernel/term.mli` | 3077 | `293d6b6588d1708257853b570d73f24445ac5b0d625ffe17e6ed2f06a6c1a9a8` |
| `kernel/typing.ml` | 15482 | `b2361ad478caa37055e9e39e021266994469368f639601fd62e66b7fae5c61be` |
| `kernel/typing.mli` | 2304 | `da4fc13b4d91a06ca53f8878b76c42851ecbf13fe15a140e74fb210050c8a99f` |
| `kernel/version.ml` | 22 | `6fbecc1c8c487adc91e598b486b7289e80ba0bfcd4330fbe03a43f33c49df168` |
| `kernel/version.mli` | 56 | `25123019c65f62e692e49f8316a2fad3c5820469ede100a820bfb9e4e40586ca` |
