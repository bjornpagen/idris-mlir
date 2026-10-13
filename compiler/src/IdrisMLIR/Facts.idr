||| The facts about a function that Idris proved and the passes read, which
||| Emit writes as the function's own attributes.
module IdrisMLIR.Facts

%default total

||| The facts about one function.
public export
record Facts where
  constructor MkFacts
  ||| Every loop through it terminates: the size-change graphs Idris keeps
  ||| of the calls in its component of the call graph decrease some
  ||| argument each time round (`Translate.Recursion`). A loop never leaves
  ||| its component; what it calls outside carries its own fact, and the
  ||| passes find through the calls whether a call may diverge.
  terminating : Bool
