# Findings

Decisions the user took, each in one note (`decision-*.md`, including
`decision-threads-pointers.md`: threads, collector finalizers and raw
pointers are outside the language);
`decision-primitive-semantics.md` says where a primitive's meaning comes
from: Idris's own definition, then the standard it implements, then a
decision of ours written there, with Chez the oracle and not the
specification. Research notes for work not yet planned: `simd.md` (SIMD by
default); `mlir-survey.md` (what the pinned MLIR offers that the pipeline
does not use yet, with the effects census of every op); `competitors.md`
(what GHC, Lean 4, Koka, MLton, Idris 2's backends, Futhark and Dex do that
we should take, against the benchmark rows); `lists.md` (fusion by raising
structural consumers, and lists in buffers decided by exclusivity, with
measured bounds and a staged plan); `one-representation.md` (every concept
the compiler represents more than once, which copy should be the one and by
what mechanism, with a staged plan); `dictionary-fields-opaque-types.md`
(why two implementations of one dictionary field are rejected when a type
differs only through an opaque definition, and the runtime tag that would
accept them). Nothing here is a specification: the code is, and a note
becomes work only when a plan picks it up. The research streams behind the
2026-09 redesign were removed once their work landed; `git log -- findings`
has them.
