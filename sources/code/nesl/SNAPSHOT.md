# Snapshot: NESL 3.1 compiler and serial CVL (excerpts)

- **Upstream:** the NESL 3.1 distribution of the CMU SCAL project, browsable on the CMU AFS web
  gateway at `https://www.cs.cmu.edu/afs/cs.cmu.edu/project/scandal/public/code/nesl/nesl/`
  (the tarball `.../code/nesl/nesl.tar.gz` is linked from https://www.cs.cmu.edu/~scandal/nesl/nesl3.1.html).
  There is no version-control repository; GitHub searches for a mirror (`nesl vcode`, `nesl cvl`)
  returned nothing on 2026-10-09.
- **Revision:** release 3.1.0; `neslsrc/releasenum` reads `3.1.0 / Wed Dec 20 14:26:22 EST 1995`.
  The tree has no commit id, so each file is pinned by its SHA-256 below; the server's
  `Last-Modified` dates run from 1993-11-29 (`neslsrc/types.lnesl`) to 1995-12-20.
- **Fetched:** 2026-10-09, each file individually from
  `https://www.cs.cmu.edu/afs/cs.cmu.edu/project/scandal/public/code/nesl/nesl/<path>` (HTTP 200).
- **Paths:** relative to the distribution root `nesl/` (so `neslsrc/ptrans.lisp`).
- **Files:** 22 (plus this file).
- **Licence:** CMU SCAL project permissive licence (`COPYRIGHT`: "Permission to use, copy, modify
  and distribute this software and its documentation is hereby granted, provided that both the
  copyright notice and this permission notice appear in all copies"; "CARNEGIE MELLON ALLOWS FREE
  USE OF THIS SOFTWARE IN ITS 'AS IS' CONDITION"). Each source file repeats the notice.
- **Topic:** Flattened data: packed, columnar and nested layouts (cluster `flattening`).
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `COPYRIGHT`, `README`, `release.notes`, `neslsrc/releasenum` | licence, distribution layout, release identity |
| `neslsrc/types.lnesl` | the base types, `segdes` among them, and `(defrec (vector segdes a))`: a sequence is a record of a segment descriptor and its data, defined in NESL itself |
| `neslsrc/ptrans.lisp` | the flattening of nested parallelism: `conv-over` (apply-to-each: distribute every free variable with `prim-dist`, build the segment descriptor), `conv-if` (all-true and all-false fast paths, `vselect` for simple branches, otherwise pack the indices and free variables per branch and merge), `conv-func` (call the parallel version of a function) |
| `neslsrc/nest-ops.lnesl` | `partition` and `flatten`, "the only user accessible functions that deal with segments directly", and `split` |
| `neslsrc/vector-ops.lnesl` | the sequence library over the segmented representation |
| `neslsrc/type.lisp`, `neslsrc/type-check.lisp` | types and inference; `l-from-type` counts VCODE stack slots per type (a primitive is 1, a pair the sum, a sequence 1 for its `segdes` plus its element) |
| `neslsrc/trans.lisp` | translation to stack-based VCODE (`COPY`/`POP`/`CPOP` by type size and depth) |
| `neslsrc/strip-recs.lisp`, `neslsrc/free.lisp`, `neslsrc/funspec.lisp`, `neslsrc/defop.lisp` | the checks that serial-only functions are not called in parallel, free-variable analysis, function specialisation records, primitive definitions |
| `vcode/README` | the VCODE interpreter's notes |
| `cvl/serial/README`, `defins.h`, `facilt.c`, `vprims.c`, `vecops.c`, `elwise.c` | the serial C Vector Library: the segment descriptor is a vector of segment lengths (`facilt.c`, `mke_fov`), segmented scans and reductions loop over the lengths and fall back to the unsegmented kernel when there is one segment (`vprims.c`, `simpsegscan`) |

**Not taken.** `neslsrc/` parser, printer, REPL, I/O and plotting files; `neslseqsrc/`; the
VCODE interpreter sources besides its README; the CM-2, CM-5, Cray, MasPar and MPI CVL
back ends; `examples/`, `utils/`, `emacs/`, `bin/`, `lib/`, `include/`. The manuals in `doc/` are
snapshotted separately at [`docs/nesl/`](../../docs/nesl/SNAPSHOT.md). Fetch any other file with
the URL pattern above, or the whole tree with `curl -sL --fail -O https://www.cs.cmu.edu/afs/cs.cmu.edu/project/scandal/public/code/nesl/nesl.tar.gz`.

## File manifest

Every stored file except this one: 22 files, 174,899 bytes in all. Computed 2026-10-09 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                                bytes  path
4398338662f9063dc0f57db5731fe4072bc7c02fbdc4907cd7e7a8e055909da5       1032  COPYRIGHT
532866b19eb22cc08c910fb5d7170dc81290e6f93050f60a8b3fd3661903655b       3852  README
f59d89383b1da4d41acf2d757f310a5ca8c80803b1f1f2b0d06c8b375ea9ec79        667  cvl/serial/README
496e4df3f6cd236c6d336e3e189434feb33cb176bff0c055bc6adebdc1e24b70       6208  cvl/serial/defins.h
6244edf3d5f534301c202b8c0696cea4be72e941fcf7548482ec7930a79ba8b7      11077  cvl/serial/elwise.c
9cf468852cc32b52707274d11f9f9cb171222bd3a83d67814d2af01526da1a6e       6999  cvl/serial/facilt.c
b23954c27c67a4933f9305e43c024e6b6c547e5c6c45cf057f8ff53e614b3a27       8664  cvl/serial/vecops.c
6a5977c6e71b920d76d87ba7d9c3e2ced3cbfd175c201572c0b5a5c4a07b31a3      14351  cvl/serial/vprims.c
4af5bd2218adb3aed159d98551ce143711d7ae25dcc57622ac55e20bf90d1917       9464  neslsrc/defop.lisp
f6ce5c5cd6e546c420d08f847dea1e9e6a3c3af72959ae0e698f1c67e678000e       4256  neslsrc/free.lisp
94897d3fa21b8b71e80f4a49af094608dbc9841f338c7f90d4862fc66bf7c430       4708  neslsrc/funspec.lisp
c463e616c597cb22b4b9114f435944d6a9716554866cacce5c33f5c2d094deac       5570  neslsrc/nest-ops.lnesl
4d283200af7ca63f7f16ee5750c5520fdaa37e665bfa13f7a7411728be0bad90       9370  neslsrc/ptrans.lisp
874f495b18c37d134fcf5819f9f869c7ebea10c5dba982e7cef1b2499a3407bc         35  neslsrc/releasenum
ef0fad90c7afe34287693189769f9639122a3fd98c64e078f2ab392d1ba17907       5111  neslsrc/strip-recs.lisp
dfce33e8fd1475cc2e5b7d928463959bdf11c94fe664301226761eff92d639bc      13068  neslsrc/trans.lisp
1fcde838c841df1a5875fe5b5bbea0facfaf2666268434d9cf8eec9d7d855ec2      21040  neslsrc/type-check.lisp
89e261f8b0f980ae2cc63f9493694143ef19b9f48ac513e7a6e0e75ecd420f66       7624  neslsrc/type.lisp
22c4169d4c09958448c49f6fee484315a433c21ff0af680fb5beef1faa593045        409  neslsrc/types.lnesl
3c4ab4336c69015dbf7f4c909ae04a0790d12068f7e53f707a85fa55243d5d8e      40196  neslsrc/vector-ops.lnesl
ce74f7b5cb5f02ea9dd0bc8b4a81a20b0724a3794b4ece44b63389ee3b1335b8        301  release.notes
86e0fee724ca61461fa043ffa58ac46a34e197258dd995fb302f6cc4c5c95a6c        897  vcode/README
```
