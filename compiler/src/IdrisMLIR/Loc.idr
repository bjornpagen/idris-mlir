||| Source locations, kept independent of Idris's `FC` so that the middle end
||| does not import the Idris compiler (FE-IN-3).
module IdrisMLIR.Loc

%default total

||| Where a source file came from, so the frontend can rebuild Idris's `FC`.
public export
data Origin = FromModule (List String) | FromPackage String | Nowhere

||| A source span, 0-based as in Idris.
public export
record Loc where
  constructor MkLoc
  origin : Origin
  file : String
  startLine : Int
  startCol : Int
  endLine : Int
  endCol : Int

export
noLoc : Loc
noLoc = MkLoc Nowhere "" 0 0 0 0

||| `file:line:column`, 1-based, for messages.
export
Show Loc where
  show l = l.file ++ ":" ++ show (l.startLine + 1) ++ ":" ++ show (l.startCol + 1)
