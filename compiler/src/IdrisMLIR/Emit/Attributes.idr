||| What the emitted module states about a function besides its type.
module IdrisMLIR.Emit.Attributes

import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Loc
import IdrisMLIR.Facts
import IdrisMLIR.MLIR
import IdrisMLIR.Term

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

||| The dialect's attribute that states it.
discardable : FnAttr -> NamedAttr
discardable Library = Idr.libraryDiscardable
discardable Total = Idr.totalDiscardable

||| What a function states that the functions lifted from it state too:
||| their code is its code. Whether each terminates is its own.
export
inherited : TFn -> List FnAttr
inherited f = [Library | inLibrary f.loc]

||| What a function states of itself.
export
own : TFn -> List FnAttr
own f = inherited f ++ [Total | f.facts.terminating.holds]

||| The attributes of a function that states `as`.
export
attributes : List FnAttr -> List NamedAttr
attributes = map discardable
