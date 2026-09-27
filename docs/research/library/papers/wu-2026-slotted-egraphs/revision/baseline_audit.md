# Independent baseline audit

Auditor: `/root/paper_audit`. Scope: the two user-authorized changes (latest experimental synchronization and more intuitive Background), with unchanged formal content and unrelated prose preserved. No source/repository edit and no Lean build was performed.

## Decision

**Pre-edit audit passes for the bounded transformation.** No unresolved scientific choice or material notation defect was found that blocks these requested changes. The historical data are explicitly superseded by a new full-corpus run; the latest capability validation is a separately identified run. These are uniquely determined evidence updates already authorized by the user, not contradictory runs requiring an authorial choice. Final emission still requires the revised closure/diff/ledgers/build/render to pass.

## Package closure and structure

The structural inspector reports 21 reachable TeX files, one bibliography, one graphic, 86 labels, 34 reference keys and 21 citation keys. It reports zero missing input/bibliography/graphic files, duplicate labels, undefined references or undefined citations, and zero dynamic-include findings. The 101 supplied source/artifact files are SHA-256 recorded in `baseline_source_checksums.json`.

| File(s) | Purpose | Dependents / preservation condition |
|---|---|---|
| main_compressed.tex | LNCS v2.20 entry, macros, abstract and full closure; bibliography precedes appendices | abstract→intro→background→typed construction→metatheory→evaluation→conclusion→references→appendices |
| intro_compressed.tex | Problem, proof-carrying composition, checked-vs-proposed boundary, contributions | Consumes formal F03/F16/F17/F23–F27 and empirical seven-arm scope; no numeric change required |
| prelims_compressed.tex | Reviewer background: ordinary e-graph example, ACI and open interfaces, related work, scope, Alloy | Accessible explanation may expand/reorder within this explicitly authorized section; preserve definitions/citations/scope |
| foundations_compressed.tex | Typed carriers, contexts, embeddings, ports; graph-relative relations; finite quotient/extraction contracts; metatheory | F01–F27 with proof appendices; no formal changes authorized or needed by data synchronization |
| eval_compressed.tex | Alloy example, corpus/protocol, size/equality/distance/coverage, ablation/cost, independent-check scope | Consumes all empirical tables/chart; current full run performance/provenance and separate validation must propagate here |
| conclusion_compressed.tex | Formal and empirical implications, open bridges | No numeric update; preserve bounded claims and open Java/refinement/replay layers |
| appendix_formal.tex, formal/formal-statement-index.tex, appendix_closure_tables.tex | Named/atomic inventory, proof sketches, existing artifact/refinement layers | Retain 146-ID statement index and all proof text byte-for-byte; current bounded corpus update confers no new formal closure |
| appendix_eval.tex | Full run identities, seven arm boundaries, full empirical tables, checker limits | Update publication snapshot/full-run/source/JAR identifiers and separately reference latest validation |
| appendixC_vmcai_stage1.tex | Proposed canonicalizer, exact abstract contracts and rules, conditional implementation boundary | Only empirical publication-run reference near opening needs E update; formal source spans unchanged |
| figures/alloy-certificate-example.tex | Typed implication/alpha/ACI example for two equivalent policies | Readable quotient lacks independent semantic authority; preserve exact formal endpoints |
| figures/final_alg_vmcai_stage1.tex | Explicitly specification-only graph canonicalization producer | Appendix C explains distinction from checked typed/de Bruijn abstract contracts; preserve |
| figures/aci_canonicalization_distance.tex; figures/raw_edit_repair_coverage_relabel.png | Inclusive nearest-truth CDF and unit/repair-success caveats | Current raw/CI coverage headline values same; verify current bound SVG before retaining original PNG |
| tables/table1_rev4.tex; tables/table2_rev4.tex; tables/table3_vmcai_stage1.tex | Per-student view size, grouped truth consolidation, metric means | Same numerical summaries at new snapshot; denominator/unit qualifications must remain |
| tables/table6_ablation_vmcai_stage1.tex | Seven-arm zero/distance/performance/representation comparisons | Update remeasured wall, CPU, RSS; zeroes/distance/units unchanged |
| tables/table7_capability_rev4.tex | 77 targeted recognition cells plus seven totals | Current 11×500 in-vocabulary observations same; exclude separate 29-sample solver validation from these denominators |
| tables/model_overview.tex | Ten base-schema rows for 17 problem variants | Unchanged schema context; not a one-to-one variant mapping |
| ref.bib; llncs.cls; splncs04.bst; README.md; PACKAGE-MANIFEST.json | Citation inputs, template, build/provenance metadata | Preserve class/BST; README/build/package hashes must not remain stale after authorized changes |

## Notation baseline

`baseline_notation_ledger.json` has 41 grouped interface rows covering the complete mathematical vocabulary, examples, algorithms, empirical distances and permitted local overloads. Each row records kind/type/arity/binding/properties/equality notion/definition/consumers/overload. No unresolved material row remains. Important preserved distinctions are:

- Invocation `m*a` is a constructor; embedding action is `e·q`. A proper embedding is not invertible or evidence of independence.
- Checked ports store occurrence vectors, while extensional Seq/Bag/Set carriers and their structural quotient rules are separately defined.
- Typed free-slot renaming, descriptor-certified bound permutation, recorded leader symmetry, structural quotient, EqCert derivation and model equality remain distinct.
- Checked finite-presentation/extraction/trace contracts and named-slot proposed producer pseudocode have explicit boundaries; no concrete Java theorem is inferred.
- Generic 0/1 canonicalDistance is distinct from empirical repair/TED coordinates; zero distance is bounded implementation evidence.

## Evidence and required propagation

Frozen retrieval identity: `AlexandervonWu/ACGN`, branch `aislop`, commit `1e2667351532b0c632166fa21ae5fbc7308a8fe7`. Full run `db9f89bf-0965-4d74-8080-d9191d5f1aec` has clean result source `8ad5fead39b687d2cadc79b01ac27743c1ece990`, original JAR SHA-256 `a053e40e64faa2ecffb0f4999b57aa661eae51933d6daf93a95d973144a71abf`, and dataset SHA-256 `d6741fbf4c4a9b3714d012d068f84cc918052f1f55211bf4d0443b990736a689`. Release-v2.16/v2.17 explicitly preserve these measurements while superseding capability validation separately.

| Required E update | Exact original source location | Verified current value / minimum repair |
|---|---|---|
| Historical publication identity | eval_compressed.tex:32–36; appendix_eval.tex:13–27; appendixC_vmcai_stage1.tex:14–17 | Bind empirical results to db9f89bf…/8ad5fead… and the correct original JAR; frozen retrieval HEAD is not result-producing source |
| Natural process timing, CPU, RSS | eval_compressed.tex:118–122 and 146–155; tables/table6_ablation_vmcai_stage1.tex:30–36 | Use comparison.json run fields for each arm; do not substitute summed worker latency for process wall |
| Ratios and CI memory | eval_compressed.tex:147–153 | Natural wall 111.885; engine CPU 593.026; targeted wall 86.920; peak heap 7,137.811 MiB; max RSS 8,943.988 MiB |
| Old inconclusive temporal analysis | eval_compressed.tex:167–173; appendix_eval.tex:119–128 | Cite separate validation run 659e248c… from clean 8feab00f…, 29 sampled checks, zero counterexamples/errors/inconclusive, eight temporal commands; retain finite scope and trace bounds |
| Truth-pool composition | appendix_eval.tex:68–71 | Clarify one oracle per invariant plus CORRECT student predicates (19,212+181=19,393), per alloy4fun-augmented/summary.md:50; same-group restriction remains |
| Package/build metadata | README.md and PACKAGE-MANIFEST.json | Refresh current output/source hashes and change manifest; retain historical formal closure evidence without claiming it was rerun |

Current unchanged headline data match the original paper: 61,598 eligible pairs after 4,482 identical-AST exclusions; 19,212 correct/42,386 incorrect; all seven zero counts; distance means; representation units; 17 problem truth rows totaling 19,393/4,496/2,101/11,382; raw/CI coverage at 1/2/5/10; all 77 targeted cells. The full-run checks still cover 4,088 natural claimed-equal identities and reject four invalid probes. The 29-case validation sample is not a rerun of all 5,500 capabilities and not an expansion of the natural semantic-check denominator.

`baseline_evidence_verification.json` records 15 locally available exact artifact/manifest hash checks and independent arithmetic. All checked hashes match; no repository-output disagreement was detected in this fetched subset. Not all 5,808 full-run files were independently downloaded or recomputed by this auditor.

## Build and audit limits

Baseline pdfLaTeX/BibTeX output builds. Static closure has no unresolved refs/citations. The baseline has no Overfull warning, numerous inherited Underfull warnings (especially the formal-index table), and an inherited font substitution warning. Layout and page boundaries must be checked on the revised PDF. The supplied class identifies LLNCS v2.20 (10-Mar-2018); no new target-venue transformation is in the user request.

This audit does not rerun experiments, verify the Java producer universally, recheck Lean proofs, or expand the existing formal closure claim. It checks scientific consistency and preservation relevant to the bounded edit. No source file was edited; source checksums are the conservation baseline.
