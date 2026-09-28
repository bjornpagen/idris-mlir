# Current Formal Status Report

Status: **`CORRESPONDENCE_CLOSED`; current build and PDF gates pending**.

## Correspondence result

- Active formal units: 146
- Exact distinct Lean mappings: 146
- Named environments: 27
- Proofs / definitions / constructors: 83 / 44 / 19
- Source-tag parity: 146/146
- Uncovered active rows: 0
- Review rounds executed: 1 of 1
- Fresh independent passes in that round: 2
- Blocking correspondence findings: 0
- Source mutations during review: 0

Both reviewers used snapshot
`8f7729dfd0f97230f30039b1a66553c65a2df0c9e7643bac47e084c2de3be203`
and the single normalization contract
`9b4a84e6b492a65bed6c9446b1c3c9e255e21277caba9cc9d8c31d713c873bc6`.
They independently checked every active mapping and all 27 named environments.
Two separate reader-facing identifier-leak passes found no accidental Lean or
ledger handle. Exact names retained in the formal appendix and metadata are
intentional evidence references.

## Supplemental witness

`TypedSlottedEGraphsPaper/TraceEnvelopeWitness.lean` is bound exactly to ACGN
commit `f5dbc1a04e10b61e39e6fe1b0fe8d5b236728625`, Git blob
`48528272445b6fa81ebd6c1f30680cd285751b5f`, and source SHA-256
`d4571f177607c4073f35466ab7d8bd2bf642bd1190a4ba38508c5a5ddfa93b7f`.
It supplies one nontrivial five-stage abstract trace with indexed adjacency and
endpoint-denotation equality. It is supplemental evidence, so the active claim
count changes by zero. It does not establish Java refinement, parser
refinement, whole-artifact correctness, or experimental replay.

## Frozen identities

- Author-source graph:
  `712e1c6849da7dcae46a910cf53a59a85c799d482f9635229eb51cf5a6a42f9b`
- Self-contained LaTeX graph:
  `73bf16fb9cc0cc92f00a2f2fe47791c084ac01780b784ef1dd3db33ee00d4e9e`
- Formal source/config graph:
  `1ea8b2d58e1f4c3c007f8da46f77c7818d716b21bf418929ea9f9ecb8bef5afa`
- Formal registry:
  `ad9499ca333900f7bf815ff3a133c65382c5b265dd912351ce722fd7a8d43e3a`
- PaperIndex:
  `dc10d182fd5e4249b8c67f92cb69b5057ca9a90f8dc82aa8e9ecd299c891fdcb`

## Layer status

| Layer | Status |
|---|---|
| Paper--Lean correspondence | `CLOSED` |
| Paper formal closure | `PENDING_CURRENT_CLEAN_LEAN_BUILDS` |
| Abstract-kernel closure | `PENDING_CURRENT_CLEAN_LEAN_BUILDS` |
| Artifact refinement | `PARTIAL` |
| Experimental replay | `PARTIAL` |
| Current LaTeX build and PDF QA | `NOT_EXECUTED` |
| GitHub publication | `NOT_EXECUTED` |
| Permitted public label | `NO_FORMAL_CLOSURE_CLAIM` |

Historical build and PDF records are preserved but do not bind the current
formal or author-source graph. The stale input PDF is excluded from the source
candidate. No Lean, LaTeX, PDF, Java, parser, experimental, packaging-publication,
or whole-artifact verification step was executed in this gate.
