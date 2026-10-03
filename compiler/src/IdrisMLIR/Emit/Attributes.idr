||| What the emitted module states about a function besides its type.
module IdrisMLIR.Emit.Attributes

import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Loc
import IdrisMLIR.Facts
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.MLIR
import IdrisMLIR.Term

%default total

public export
data FnAttr
  = ||| Its code is from a library a cycle of references breaks at only
    ||| when the cycle has no function from elsewhere (the registry's
    ||| *break last*). `idr-loop-breakers` reads this, never the location,
    ||| which is for messages only.
    BreaksLast
  | ||| Every loop of its own body is one Idris proved terminating.
    Total

||| The dialect's attribute that states it.
discardable : FnAttr -> NamedAttr
discardable BreaksLast = Idr.breakLastDiscardable
discardable Total = Idr.totalDiscardable

||| What a function states that the functions lifted from it state too:
||| their code is its code.
export
inherited : TFn -> List FnAttr
inherited f = [BreaksLast | covers BreakLast f.loc.origin]

||| What a function states of itself: Idris's proof of it.
export
own : TFn -> List FnAttr
own f = inherited f ++ [Total | f.facts.terminating.holds]

||| What a function lifted from a lambda or `Delay` states, besides what it
||| inherits. Its body has no loop of its own: a recursion goes through a
||| function of the program, whose own body carries Idris's proof or its
||| absence, and `idr-effects` finds whatever the lifted function reaches.
export
lifted : List FnAttr
lifted = [Total]

||| The attributes of a function that states `as`.
export
attributes : List FnAttr -> List NamedAttr
attributes = map discardable
