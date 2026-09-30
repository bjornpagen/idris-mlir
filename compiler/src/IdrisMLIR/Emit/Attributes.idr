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
  | ||| It terminates: Idris proved it, or it is lifted from a function
    ||| and everything it reaches is proved.
    Total
  | ||| A loop breaker: inlining it could unroll a cycle.
    NoInline

name : FnAttr -> String
name Library = "idr.library"
name Total = "idr.total"
name NoInline = "no_inline"

||| What a function states that the functions lifted from it state too:
||| their code is its code. Whether each terminates is its own.
export
inherited : TFn -> List FnAttr
inherited f = [Library | inLibrary f.loc]

||| What a function states of itself.
export
own : TFn -> List FnAttr
own f = inherited f ++ [Total | f.facts.terminating.holds]

||| The attribute dictionary of a function header, if it has any.
export
attributes : List FnAttr -> String
attributes [] = ""
attributes as = " attributes {" ++ joinBy ", " (map name as) ++ "}"
