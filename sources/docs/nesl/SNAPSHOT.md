# Snapshot: NESL manuals (CVL and VCODE)

- **Upstream:** the `doc/` directory of the NESL 3.1 distribution, CMU SCAL project,
  `https://www.cs.cmu.edu/afs/cs.cmu.edu/project/scandal/public/code/nesl/nesl/doc/`.
- **Revision:** release 3.1.0 (see [`code/nesl/SNAPSHOT.md`](../../code/nesl/SNAPSHOT.md));
  `Last-Modified` 1995-07-07 for both files; pinned by SHA-256 below.
- **Fetched:** 2026-10-09, from `https://www.cs.cmu.edu/afs/cs.cmu.edu/project/scandal/public/code/nesl/nesl/doc/<file>` (HTTP 200).
- **Paths:** relative to the distribution root (so `doc/cvl.ps`).
- **Files:** 2.
- **Licence:** the distribution's CMU SCAL permissive licence (`code/nesl/COPYRIGHT`) covers "the
  software and its documentation" (verify).
- **Topic:** Flattened data: packed, columnar and nested layouts (cluster `flattening`).

| Path | What |
| --- | --- |
| `doc/cvl.ps` | "Cvl: A C Vector Library Manual", version 2.1, June 1995 (CMU-CS-93-114, revised; Blelloch, Chatterjee, Hardwick, Reid-Miller, Sipelstein, Zagha): vector memory reached only through `vec_p` handles, a length argument per vector and a segment descriptor per segmented operand; segment descriptors live in vector memory and carry two lengths, the number of segments and the number of elements; most operations have a segmented counterpart |
| `doc/vcode-ref.ps` | VCODE Reference Manual, version 2.0 (Blelloch, Chatterjee, Sipelstein, Zagha, May 15, 1994): six primitive types including `segdes`; "There are no scalar instructions; scalars are simply single-element vectors. Unsegmented vectors are represented as segmented vectors with but a single segment"; the machine representation of segment descriptors is implementation-dependent |

**Not taken.** `doc/manual.ps` (the language manual; the report `papers/blelloch-1995-nesl/` is
its updated form) and `doc/user.ps` (the user's guide, also online at
`https://www.cs.cmu.edu/~scandal/html-papers/nesl-user-manual/`).

## File manifest

```
SHA-256                                                                bytes  path
daf524c506ce0b6e57f43e17dfea9a741009caba22b580b2c3234e2a19869ab1     150406  doc/cvl.ps
aea1312d00d6881c7cc7a33c8c899af34656d5ab61a88a82542ea704cd3bf6dd      97512  doc/vcode-ref.ps
```
