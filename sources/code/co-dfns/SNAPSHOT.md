# Snapshot: Co-dfns compiler passes

- **Upstream:** `Co-dfns/Co-dfns` on GitHub (Aaron W. Hsu).
- **Revision:** `master` at `073634096d0aa030addddc7cf9d2adebe5200ce2` (`git ls-remote https://github.com/Co-dfns/Co-dfns.git HEAD`, 2026-10-09); `cmp/global.apl` declares `VERSION←5 7 1`.
- **Fetched:** 2026-10-09, from `https://raw.githubusercontent.com/Co-dfns/Co-dfns/073634096d0aa030addddc7cf9d2adebe5200ce2/<path>` (paths with `∆` or spaces URL-encoded).
- **Paths:** relative to the repository root (so `cmp/TT.apl`).
- **Files:** 17.
- **Licence:** GNU AGPL-3.0-or-later (`LICENSE.txt`, `COPYING.txt`: © 2011-2025 Aaron W. Hsu; "available under other licensing options" on request). AGPL is copyleft: these excerpts are for study and must not be copied into this repository's code.
- **Threads:** Array languages and typed array programming (cluster apl-lineage).

**What is here and why.**
- `README.md`, `LICENSE.txt`, `COPYING.txt`.
- `cmp/`, the whole compiler: `PS.apl` (tokenizer and parser; builds the depth vector `d` from
  brace/bracket nesting with `+⍀` and converts it with `p←D2P d`), `TT.apl` (the tree
  transformations over the parent-vector inverted table `p t k n lx vb pos end`: node
  deletion with pointer recomputation, ancestor walks `I@{…}⍣≡`, lifting dfns to the top
  level, wrapping and flattening expressions, a graph-colouring frame allocator), `GC.apl`
  (generates C against the `libcodfns` runtime), `CC.apl` (invokes the C compiler), `NS.apl`,
  `MK∆RTM.apl`, `INSTALL∆RTM.apl`, `global.apl` (node-type enumeration and error table;
  `D2P` and `P2D`, the depth-vector/parent-vector conversions), `main.apl`, `util.apl`.
- `docs/`: `FAQ.md`, `MANUAL.md`, `PERFORMANCE.md` (the primitives' GPU cost classes and the
  critical-path model), and `Beautiful Code is Good Code.pdf` (143,690 bytes; Hsu, 2025-10-24,
  the developers' guide: "the code is the specification").

The 17-line core compiler measured in Hsu's dissertation is an earlier form of `cmp/TT.apl`;
the dissertation's version is in `papers/hsu-2019-data-parallel-compiler/hsu-dissertation.pdf.txt`
(lines 2228–2245). The current `TT.apl` (251 lines) does more, and the BQN author notes
(`docs/bqn/implementation/codfns.md`, lines 11 and 19) that recent Co-dfns relaxes the strict
flat-array style.

**Not taken, and how to get more.** `rtm/` (the C runtime), `tests/`, `tests_old/`, `attic/`
(including two test inputs of 14.7 MB and 5.0 MB) and `ime/` (keyboard layouts). Fetch single
files from the raw URL pattern above at the same revision; list paths with
`https://api.github.com/repos/Co-dfns/Co-dfns/git/trees/073634096d0aa030addddc7cf9d2adebe5200ce2?recursive=1`.

## File manifest

Every stored file except this one: 17 files, 310,030 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
c770c13901bb7863d27b321f3d2aafc269f2a18cc2af7a48d1355bbdacf6b95d        882  COPYING.txt
432d251a78dbc966e6add13f9f3b40a53daca222208e50cb514cfc77e7d85af6      34521  LICENSE.txt
a4fd00e91e92f26fcf88f115a12a2702d8ba150a49f50e7eef476db72f213f8e       7239  README.md
c93f78d790c4d1c797037081f8a10800c7d97d1429bd764a46b15a3aade06eee       3874  cmp/CC.apl
3137b4067ae11afe37998be492234bac1d3f43d03b0f23add17d529dc45b2a09      28821  cmp/GC.apl
bd4b9dbf41b501a67e0dcaa06d5c6bfe71424f8de653d8691dd4ec07bbf6f7e4        579  cmp/INSTALL∆RTM.apl
7618b61d76e6cf373d9905fcd444fa13e49de10a2ff5cc47f8fa0a83d70700e1       3188  cmp/MK∆RTM.apl
169806037d1f1b691e21694fb68c1c8afc5de5c5ab70c80043fb825d388f2c5d       2376  cmp/NS.apl
a850d88103dab26e1f8e756188ed2f7cf701323c637c34b53b4077a88b2871af      32986  cmp/PS.apl
eb5d9ca81dd0e3dadf3983f3d415ca4fcdf9363de38c616a5724881eb2af3c41      15264  cmp/TT.apl
3d1707627b2cba75c34d033babf2632d0fdb3896c4aacbe431ca618e66a25299       3291  cmp/global.apl
f6da4c31d5032aa0da9c5096f59371be1e7677629cfd1da40df1a4ac189f43fa       1231  cmp/main.apl
98cedae333abcf15778a77cf918fdd37269f66fcda551644238775c0c17ad649       2995  cmp/util.apl
86e471c161d3d907a0f328c4409822a05d634e44fd751be9ad8e2fb3f23e0f7b     143690  docs/Beautiful Code is Good Code.pdf
301e6c00e30dede4ca273aa51c9463d7d7cc52fcecb67925ec2b67aa3d2483d7       8535  docs/FAQ.md
8395e6ee10af7c4a79bb114789a7abbdb227e911c50686dfe5df576177d7561e      10591  docs/MANUAL.md
4c079b47eb7b590ce56b72fc8012b07bf02bc865c0f69657255a4429b55be26f       9967  docs/PERFORMANCE.md
```
