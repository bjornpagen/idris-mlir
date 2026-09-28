||| Source locations, kept independent of Idris's `FC` so that the middle end
||| does not import the Idris compiler (FE-IN-3).
module IdrisMLIR.Loc

import IdrisMLIR.Ids
import IdrisMLIR.Registry.Libraries

%default total

||| A source span, 0-based as in Idris.
public export
record Loc where
  constructor MkLoc
  ||| Where the code comes from, as the registry classified its module.
  origin : Origin
  ||| The module, as Idris names it: printed, and given back to Idris for
  ||| its error locations, but never compared (`origin` is what code tests).
  place : Shown
  file : String
  startLine : Int
  startCol : Int
  endLine : Int
  endCol : Int

export
noLoc : Loc
noLoc = MkLoc Generated (shown "") "" 0 0 0 0

||| `file:line:column`, 1-based, for messages; a library module whose
||| source is not installed is named by its module.
export
Show Loc where
  show l = (if l.file == "" then show l.place else l.file) ++ ":" ++
           show (l.startLine + 1) ++ ":" ++ show (l.startCol + 1)

||| Is a location in a library whose diagnostics are reported at the user's
||| code that reached it (DIAG-LOC-1)?
export
inLibrary : Loc -> Bool
inLibrary l = covers ReportAtCaller l.origin
