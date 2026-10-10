||| The facts about a function, as far as the compiler records them today.
||| Each fact records its provenance: an analysis or flag of Idris's own, or
||| the registry. Rules consume facts whatever their provenance; the
||| provenance says why one holds.
module IdrisMLIR.Facts

%default total

||| What a fact rests on.
public export
data Provenance
  = ||| Idris itself: its totality checker, its flags, the structure of its
    ||| names.
    FromIdris
  | ||| The registry: a hook, or a cell of
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
  ||| Every loop through it terminates: the size-change graphs Idris keeps
  ||| of the calls in its component of the call graph decrease some
  ||| argument each time round (`Translate.Recursion`). A loop never leaves
  ||| its component; what it calls outside carries its own fact, and the
  ||| passes find through the calls whether a call may diverge.
  terminating : Fact
