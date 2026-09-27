||| The facts about a function (docs/plan.md, section 8.3), as far as that
||| record exists today. Each fact records what it rests on: an analysis or
||| flag of Idris's own, or the registry. Rules consume facts whatever their
||| source; the source says why one holds.
module IdrisMLIR.Facts

%default total

||| What a fact rests on.
public export
data Source
  = ||| Idris itself: its totality checker, its flags, the structure of its
    ||| names.
    FromIdris
  | ||| The registry (docs/architecture/17-registry.md): a hook, or a cell of
    ||| its library table.
    FromRegistry

export
Show Source where
  show FromIdris = "Idris"
  show FromRegistry = "the registry"

public export
record Fact where
  constructor MkFact
  holds : Bool
  source : Source

||| The facts about one function.
public export
record Facts where
  constructor MkFacts
  ||| It terminates: Idris's checker reports it total, or the compiler wrote
  ||| it (ELIM-G-5, PROF-HEAP-5).
  terminating : Fact
  ||| It is an Idris case or with block, part of its parent (ELIM-G-19).
  block : Fact
  ||| It is unfolded as its author's hint: `%inline` in a library whose
  ||| hints the registry's library table honours (ELIM-G-19).
  inline : Fact
