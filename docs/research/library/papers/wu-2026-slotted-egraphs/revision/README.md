# Revision notes — September 9, 2026

The user requested synchronization with the latest GitHub experiments and a
more intuitive Preliminary section for readers unfamiliar with e-graphs and
Alloy. The paper retains its existing section title, Background and Scope.

## Experimental synchronization

The retrieval snapshot is [1e2667351532b0c632166fa21ae5fbc7308a8fe7](https://github.com/AlexandervonWu/ACGN/commit/1e2667351532b0c632166fa21ae5fbc7308a8fe7).
Release v2.17 retains the v2.15 full-corpus run and the v2.16 validation refresh.
The full run is db9f89bf-0965-4d74-8080-d9191d5f1aec; the validation run is
659e248c-d3d6-4a2b-8d99-67a0ebcf9eb4. Their separate producing commits, JARs,
configuration and manifest hashes appear in build-and-revision-verification.json.

The full corpus still has 61,598 eligible AST-different pairs: 19,212 CORRECT
and 42,386 incorrect, across 181 invariant groups and 17 variants. All seven
arms finish all eligible pairs. Correct zero-distance counts remain
820, 2,160, 820, 2,160, 2,159, 4,074 and 4,088; incorrect zeroes remain zero.
The 5,500-pair capability table, distance/size/truth-consolidation tables and
coverage curve also reproduce the earlier values.

The updated process measurements are:

| Arm | Wall (s) | Engine CPU (s) | Max RSS (MiB) |
| --- | ---: | ---: | ---: |
| Raw | 19.370 | 4.255 | 1,524.891 |
| Raw + De Bruijn | 19.380 | 5.015 | 1,575.672 |
| Java egglog | 19.270 | 4.176 | 1,475.656 |
| Java egglog + De Bruijn | 18.860 | 4.881 | 1,456.941 |
| Slotted | 19.670 | 15.565 | 1,614.004 |
| Fast Rewrite | 23.990 | 68.820 | 2,061.391 |
| Certificate-Integrated | 2,684.110 | 40,811.847 | 8,943.988 |

Certificate-Integrated peak heap is 7,137.811 MiB. Relative to Fast Rewrite,
the same-run process wall ratio is 111.885 and engine-CPU ratio is 593.026;
the separate targeted-suite wall ratio is 86.920. These remain single-run,
arm-specific observations, with no causal or cross-system performance claim.

The checker refresh follows temporal operators through predicate calls. All
29 family/subtype samples now finish without counterexamples, solver errors
or inconclusive results. Eight use temporal analysis at object scope 4 and
trace bounds 1–10, including the six previously inconclusive samples.
This is a sampled bounded validation, distinct from both the 5,500-pair
recognition suite and the 4,088 natural-corpus equality claim identities.

The coverage caption and appendix now correctly include oracle predicates in
the within-invariant nearest-reference pool. The current source SVG has the
same Git blob as the prior run, so the supplied chart image was retained.
The archived bridge matrix remains scoped to its old 6764808 snapshot; newer
bounded record replays are acknowledged without promoting its open rows.

## Readability and preservation

Background develops the existing arithmetic example into an explanation of
e-nodes, e-classes, sharing, congruence, rebuilding, saturation and extraction.
It distinguishes sequence/bag/set laws, explains alpha-equivalence and open
terms, and gives typed User/Photo slot intuition. An Alloy introduction
explains signatures, relations, predicates, joins, quantification,
multiplicities, run/check and the limits of bounded results, using the
existing social-media example. The evaluation refers back to these basics.

No formal claim, proof, equation, algorithm, bibliography entry, class/style
or graphic bytes changed. All 146 registered active formal source spans and
all 75 formal/ files are unchanged. Current whole-source identities are new:
the historical formal reports, including their earlier source/PDF snapshots,
remain archived records rather than new certifications of the whole paper.

## Verification and review records

- revision.diff and change-manifest.json identify all seven scientific-file
  deltas. U denotes the user's readability request; E denotes empirical
  synchronization and dependent coherence. Root README/manifest updates and
  these revision records are packaging changes (C).
- claim-evidence-ledger.json records each empirical or implementation claim,
  its values, repository path, frozen URL, hash and scope.
- retrieval-provenance.json records the retrieval commit and source/figure
  comparisons. baseline_evidence_verification.json checks 15 selected files
  against their publication-manifest hashes.
- final_emission_audit.md and .json provide the independent scientific and
  layout pass; final_notation_ledger.json records zero unresolved material rows.
- build-and-revision-verification.json binds the current 25-file input graph
  and 49-page PDF, documents full-page QA and states verification limits.

The locally rebuilt supplied source has 47 pages with main text 1–19.
The revised build has 49 pages with main text 1–20. The old README's separate
45-page/17-page-main rendering is historical, not the local baseline used here.

No experiments or Lean proofs were executed anew. Large LFS raw distances
and the augmented index were not independently downloaded or reaggregated.
The evidence checks use manifest-bound summaries and selected aggregates.
Neither these checks nor the reported bounded replays establish full Java or
parser refinement, universal semantic completeness, or whole-corpus trace replay.
