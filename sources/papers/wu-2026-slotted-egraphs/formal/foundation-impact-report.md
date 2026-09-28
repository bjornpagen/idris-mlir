# Foundation Impact Report

Status: **declaration-level axiom audit complete; current-workflow review round 2 and gated builds pending**.

The `STANDARD_LEAN_EXPLICIT_TCB` profile permits exactly `propext`, `Quot.sound`, and `Classical.choice`. Direct Lean 4.33.0 `#print axioms` output was captured for all 146 active mapped declarations, and every set is a subset of the whitelist. Every one of the 83 proof-bearing active rows also has its own exact direct sentinel in `PaperIndex.lean`.

| Observed dependency | Principal use |
|---|---|
| `Classical.choice` | Finite coding/context selection and well-founded rebuild existence |
| `propext` | Extensional support/closure and finite quotient-normalization reasoning |
| `Quot.sound` | Quotient/extensional encodings and structural alpha/support results |

The round-1 repairs are reflected in the regenerated exact types and metadata: independently quantified conjunction clauses; pointwise collision ownership; supplied-record kernel replay; generic finite-presentation and natural-measure rebuilding; and transition constructors restricted to addition, rekeying, composition, or removal evidence.

Forbidden project axioms, proof placeholders, `native_decide`, unsafe/partial proof dependencies, compiler/FFI proof oracles, and unverified external-solver results were not observed in the mapped Lean sources. Java code, the non-Lean verifier, bounded tests, and experiments are not proof dependencies.

Exact axiom lists are recorded in `axiom-report.json`; the repaired formal source/config aggregate is `1ee980165520906477f21d527631463639833c3bd9f601854a8c74c5982d6299`. This declaration-level result is outcome-neutral and does not pre-empt the second and final current-workflow correspondence review.
