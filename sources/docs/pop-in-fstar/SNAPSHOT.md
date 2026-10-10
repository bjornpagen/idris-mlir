# Snapshot: Proof-Oriented Programming in F*, "Understanding how F* uses Z3"

- **Upstream:** `FStarLang/PoP-in-FStar` on GitHub (the book rendered at
  https://fstar-lang.org/tutorial/).
- **Revision:** `958d86f2eb158f349785e447228dbf016818c6be`, the HEAD resolved with
  `git ls-remote https://github.com/FStarLang/PoP-in-FStar HEAD` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/FStarLang/PoP-in-FStar/958d86f2eb158f349785e447228dbf016818c6be/<path>`;
  the tree was listed with the GitHub trees API at that revision.
- **Paths:** relative to the repository root.
- **Licence:** Apache-2.0 (`LICENSE`).
- **Threads:** decision-procedures (Fast dependent type checking and elaboration).

**What is here and why.** The F* developers' own account of running a dependent type checker
on top of Z3, with the operational detail no paper gives:
`book/under_the_hood/uth_smt.rst` (the SMT-LIB primer, the encoding of F* terms into a single
`Term` sort, fuel instrumentation of recursive definitions (lines 496–570), `--query_stats`,
the rlimit, a worked matching loop (lines 1188–1410), the remark on Z3's determinism and
`--quake` (lines 1409–1440), context filtering with `--using_facts_from`, and hints as recorded
unsat cores, including hints that fail to replay (lines 1831–1990)), and its parent
`book/under_the_hood/under_the_hood.rst`.

The elaborators cluster of this pass adds three more chapters in
`SNAPSHOT.elaborators.md` (same revision); merge both.

**Not taken:** the rest of the book and the `book/code/*.fst` files the chapter
`literalinclude`s (`ContextPollution.fst`, `HintReplay.fst`); same raw URL pattern. Nothing
was built or run.

## File manifest

The files of this snapshot (the elaborators addendum lists its own): 3 files, 98,064 bytes in all.

```
SHA-256                                                                bytes  path
c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4       11357  LICENSE
26968ebf140c952578768900a296646919d3fdf3e9560ed9f71147696b0d9ab1         414  book/under_the_hood/under_the_hood.rst
6d66e389d88bfa289b2d45b87b4d9eca52fb1f4edcb8de874ad86fa2126af2e3       86293  book/under_the_hood/uth_smt.rst
```
