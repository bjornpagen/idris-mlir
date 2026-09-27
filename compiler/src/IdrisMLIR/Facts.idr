||| The facts about a function (docs/plan.md, section 8.3), as far as that
||| record exists today. Each fact records its provenance: an analysis or
||| flag of Idris's own, or the registry. Rules consume facts whatever their
||| provenance; the provenance says why one holds.
module IdrisMLIR.Facts

%default total

||| What a fact rests on.
public export
data Provenance
  = ||| Idris itself: its totality checker, its flags, the structure of its
    ||| names.
    FromIdris
  | ||| The registry (docs/architecture/17-registry.md): a hook, or a cell of
    ||| its library table.
    FromRegistry

export
Show Provenance where
  show FromIdris = "Idris"
  show FromRegistry = "the registry"

public export
record Fact where
  constructor MkFact
  holds : Bool
  provenance : Provenance

||| The facts about one function.
public export
record Facts where
  constructor MkFacts
  ||| It terminates: Idris's checker reports it terminating
  ||| (`Core.Termination.checkTotal`).
  terminating : Fact
