# Typed Flexible-Arity Slotted E-Graphs — arXiv Source Bundle

This archive intentionally contains source files only. It is the LaTeX source
graph used for the newest verified rendering of the paper; the rendered PDF is
not included. The archive also contains the unchanged buildable Lean proof
package and its bounded correspondence evidence.

Four reader-facing, nonformal source corrections distinguish this package from
the preceding source candidate: two small prose refinements in the introduction
and background, the exact packaged path of `TraceEnvelopeWitness.lean`, and the
replacement of one leaked internal theorem handle by its prose description.
No theorem statement, proof, experimental value, citation key, figure, or
layout command changed.

## Build the paper

From the archive root:

    latexmk -C main_compressed.tex
    latexmk -pdf -bibtex -interaction=nonstopmode -halt-on-error -file-line-error main_compressed.tex

The authoritative entrypoint is `main_compressed.tex`. The verified external
rendering corresponding to these source bytes has:

- PDF SHA-256: `486d3d72fe40cf54c271358cd931c5b608487849c361f4e1f56656838629d347`
- Total length: 45 pages
- Main text: pages 1–17
- References: pages 18–19
- Appendices: pages 20–45

The 20-file author-source graph has SHA-256
`91015d8292a8bffb9e75429e4e4a3f1800a79201c90250db85098d58d627b656`.
The 24-file self-contained LaTeX-input graph has SHA-256
`fcef028185ebbed53d340857089fb123d1be69e50028b12a4c60f83c28254086`;
it additionally covers the generated formal-statement index, active chart,
`llncs.cls`, and `splncs04.bst`.

The clean LaTeX build and basic PDF review are bound by verification-report
SHA-256
`da6feebf24cc9a5a33cdb7e8057471284c4e036a40bdf30aa19c6485bc0aea47`.
That report records the page boundary, citation and cross-reference checks,
chart identity, and basic visual review of all 45 pages. It does not claim a
new adversarial PDF-review round.

## Build the Lean package

Lean is pinned exactly to 4.33.0. From the archive root:

    cd formal
    lake clean
    lake build
    lake env lean PaperIndex.lean

The canonical `lean-toolchain` contains exactly
`leanprover/lean4:v4.33.0` followed by one newline. The package has no external
Lake dependencies. The 23-file Lean source/configuration graph has SHA-256
`1ea8b2d58e1f4c3c007f8da46f77c7818d716b21bf418929ea9f9ecb8bef5afa`.
Two isolated clean builds of that exact graph are bound by build-report
SHA-256
`06250e17f59a5b8c7c695a4be050e371c0d27693ba3cec4a0e5ee9c7e4ce8078`.

## Formal correspondence and boundary

The frozen paper–Lean correspondence snapshot is
`8f7729dfd0f97230f30039b1a66553c65a2df0c9e7643bac47e084c2de3be203`;
its normalization contract is
`9b4a84e6b492a65bed6c9446b1c3c9e255e21277caba9cc9d8c31d713c873bc6`.
It covers 146 active formal units: 83 proof-bearing declarations, 44
definitions, and 19 constructors. The four corrections above touch neither
file containing the 146 mapped source spans (`foundations_compressed.tex` and
`appendixC_vmcai_stage1.tex`) and touch no Lean source. Frozen correspondence
inputs therefore retain their original source-snapshot hashes; the package
manifest records the exact nonformal delta and current author-source graph.

The supplemental witness is
`formal/TypedSlottedEGraphsPaper/TraceEnvelopeWitness.lean`, SHA-256
`d4571f177607c4073f35466ab7d8bd2bf642bd1190a4ba38508c5a5ddfa93b7f`.
It supplies one nontrivial abstract trace witness. It does not establish Java
producer–verifier refinement, parser refinement, whole-artifact correctness,
or experimental replay.

Artifact refinement and experimental replay remain partial. Java sources,
experimental manifests, and result files are intentionally absent and were
not modified by this packaging stage.

## Package manifest

`PACKAGE-MANIFEST.json` lists every archived file and its SHA-256 hash. It
excludes itself from the hashed inventory to avoid self-reference. The
rendered PDF, LaTeX auxiliary files, build caches, compiled Lean objects,
temporary renders, Java sources, and experimental result files are excluded.
