# Formal Closure Report

Status: **formal layers closed; bounded nontrivial trace-witness synchronization passed**.

## Exact formal result

- Audit rows: 158
- Active formal units: 146
- Named environments: 27
- Distinct exact compiled declarations: 146
- Exact proofs / definitions / constructors: 83 / 44 / 19
- Source-tag parity: 146/146
- Uncovered active rows: 0
- Unproved proof-bearing rows: 0

Two fresh independent round-2 correspondence reviewers passed the frozen
mapping, and two isolated Lean 4.33.0 clean builds passed.  The empirical
refresh changed no formal span, statement, hypothesis, dependency, Lean
declaration, proof, normalization rule, or formal source/config file.  Two
fresh Lean 4.33 metadata dumps reproduce the frozen compiler projection
byte-for-byte.

## Frozen identities

- Current author-source graph: `6e386c342c9866479a31186ec31968a2f007d780fba3715a28a6172626dc1411`
- Pre-witness-sync author-source graph: `29348d88fbad07dfeddca2abf880b0718a8ca2ba26d41ee82a08e8f60d94d7d1`
- Pre-repaired-Fast-IR refresh author-source graph: `1e8c1cebd6f35f8747524a971f3999a2424f698eb7957bff6aad684b903e1964`
- Pre-layout-repair author-source graph: `285527fc185771fdc43be9b618669deef64bda55418d4654a3310042ab2b10b4`
- Pre-refresh author-source graph: `17a1ed53bafabdfbe9fdfda4c28ced12d6fc2de38e5cd663f8d55b05fb7ad183`
- Correspondence-reviewed graph: `e5ed4bb73d6b1ca664b5428ad22a5d36b460ef67bca180f261d894c2c647203c`
- Formal source/config graph: `1ee980165520906477f21d527631463639833c3bd9f601854a8c74c5982d6299`
- Formal registry: `687f18cf2bc1c361441a4e6b0a99b0e9706904685835d91137403756f672219b`
- Normalization contract: `9b4a84e6b492a65bed6c9446b1c3c9e255e21277caba9cc9d8c31d713c873bc6`
- PaperIndex: `dc10d182fd5e4249b8c67f92cb69b5057ca9a90f8dc82aa8e9ecd299c891fdcb`
- Empirical refresh report: `formal/experimental-data-refresh-report.json`
- Provenance-layout repair report: `formal/provenance-layout-repair-report.json`
- Trace-envelope witness sync report: `formal/trace-envelope-witness-sync-report.json`

## Empirical binding

- Audited ACGN branch head: `f5dbc1a04e10b61e39e6fe1b0fe8d5b236728625`
- Experiment publication commit: `63f3b8c2931202e9b3582a8802c558725a67ac26`
- Immutable publication run: `df4d8d4c-6265-4fe7-88d5-3aceee60398b`
- Clean experiment source: `fbd9b1497a9036c55780da777f56581bc1c6bcec`
- Dataset SHA-256: `d6741fbf4c4a9b3714d012d068f84cc918052f1f55211bf4d0443b990736a689`
- JAR SHA-256: `361b33ef56f6ccb1089a7a6fdda2a92bf621e501166c5a1c73330a0cc1686807`
- Chart SHA-256: `c618301c1447ef10a463851500ef1785cf1eb890d614fb823f31d167704c7dc5`
- Abstract trace-witness commit: `f5dbc1a04e10b61e39e6fe1b0fe8d5b236728625`
- Trace-witness source SHA-256: `d4571f177607c4073f35466ab7d8bd2bf642bd1190a4ba38508c5a5ddfa93b7f`

The active prose and empirical tables use the repaired-run manifest-bound
values.  The chart remains byte-identical because its raw-AST and
Certificate-Integrated series did not change.  Java, experimental results,
Lean sources, formal claims, Table 7 capability counts, and the bibliography
were not changed.

The external witness focus-builds under exact Lean 4.33.0.  It supplies one
fixed abstract trace with AC reassociation, a bijective two-slot binder
remapping, union insertion, rebuild, and congruence restoration after operand
reordering.  Indexed construction checks adjacency and replay under the
module's finite-set interpreter checks endpoint-denotation equality.  This is
not a Java-produced or verifier-replayed trace and does not close artifact
refinement or experimental replay.

## Current layer status

| Layer | Status |
|---|---|
| Paper formal closure | `CLOSED` |
| Paper--Lean correspondence closure | `CLOSED` |
| Abstract-kernel closure | `CLOSED` |
| Artifact-refinement closure | `PARTIAL` |
| Experimental-replay closure | `PARTIAL` |
| Lean GitHub publication | `OUT_OF_SCOPE_CURRENT_TASK` |
| Permitted public label | `NO_FORMAL_CLOSURE_CLAIM` |

The artifact layer remains partial because theorem-critical Java paths lack a
complete Lean refinement proof or independently Lean-replayed producer trace.
The experiment layer remains partial because raw-source normalization and
theorem-relevant experiment traces were not replayed in Lean.

## LaTeX integration status

One clean in-place LaTeX build after `latexmk -C` succeeded.  The generated
PDF has 45 pages: the main text occupies pages 1--17, references begin on page
18, and appendices begin on page 20.  The 20-page main-text limit therefore
passes with three pages of margin.  Citations, references, and labels resolve.

The four long provenance identifiers now break within the text block without
changing any source literal or value.  The clean build records zero overfull
boxes, all four exact identifiers survive whitespace-only PDF-text
normalization, and the affected pages 30--31 pass a bounded render check.

The post-witness-sync render review covered changed pages 16, 17, and 35 and
found no clipping, overlap, overflow, or section-boundary defect.  The earlier
45-page all-page QA report is preserved as pre-sync history and was not
rewritten or represented as a fresh all-page pass.  The chart, bibliography,
floats, and layout commands were unchanged.  Publication was not executed.
