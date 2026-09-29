||| What the emitted module states about a function besides its type.
module IdrisMLIR.Emit.Attributes

import IdrisMLIR.Loc
import IdrisMLIR.Facts
import IdrisMLIR.Term

import Data.String

%default total

public export
data FnAttr
  = ||| Its code is from a library whose diagnostics are reported at the
    ||| user's code that reached it. Passes read this, never the location,
    ||| which is for messages only.
    Library
  | ||| Idris proved it terminating.
    Total
  | ||| A loop breaker: inlining it could unroll a cycle.
    NoInline

name : FnAttr -> String
name Library = "idr.library"
name Total = "idr.total"
name NoInline = "no_inline"

||| What a function states that the functions lifted from it state too:
||| their code is its code.
export
inherited : TFn -> List FnAttr
inherited f = [Library | inLibrary f.loc] ++ [Total | f.facts.terminating.holds]

||| The attribute dictionary of a function header, if it has any.
export
attributes : List FnAttr -> String
attributes [] = ""
attributes as = " attributes {" ++ joinBy ", " (map name as) ++ "}"
