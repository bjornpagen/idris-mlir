-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What is known of whether a function's own loops and recursion end, read
||| wherever a cycle runs through the function: whether a loop a pass makes
||| of its code may not end, and whether a cycle of calls through it does.
||| It is Idris's termination checker's verdict, which follows every call:
||| its proof that a function ends covers every run of it, through whatever
||| it calls, so a cycle that specialization and defunctionalization make of
||| proved functions still ends, and a cycle of ours ends exactly where
||| every function on it was proved. A function a pass makes takes its
||| origin's fact; one made with no origin (a dispatch, a force) has none,
||| since only a cycle through it asks and no proof covers that cycle.
||| Nothing clears the fact: code a body takes in brings its own partiality
||| with it, in its ops and in the rows of its calls.
|||
||| The fact is declared once, here: the frontend holds a function's as
||| `Termination`, the C++ as the enum printed from the same cases
||| (Generated/Termination.h.inc), and the IR as `#idr.terminates`, present
||| exactly on a function Idris proved.
module IdrisMLIR.Spec.Functions.Termination

import IdrisMLIR.Spec.Core.Vocabulary

import Data.List.Elem
import Data.List1
import Data.Vect

%default total

||| What Idris proved of a function's own loops: nothing (`Unproved`), or
||| that every call of it ends (`Proved`).
public export
data Termination = Unproved | Proved

||| The cases, the C++ `Termination`.
export
terminationClosed : Closed Termination
terminationClosed = MkClosed
  { name = "Termination"
  , shape = OneOf
  , every = Unproved ::: [Proved]
  , complete = \case
      Unproved => Here
      Proved => There Here
  , describe = \case
      Unproved => MkCase "Unproved" ("unproved" ::: [])
        "Idris did not prove the function ends: a function without the attribute"
      Proved => MkCase "Proved" ("proved" ::: [])
        "Idris proved every call of the function ends: a function with the attribute"
  , doc = brief "what Idris proved of a function's own loops, the attribute read"
  }

||| `::idr::Termination`, printed under Generated/Termination.h.inc, which
||| Func.h includes.
export
terminationHeader : Header
terminationHeader = MkHeader "Termination"
  [ (DialectNamespace, [EnumOf (enumDef terminationClosed)]) ]
  (brief "what Idris proved of a function's own loops")

||| `#idr.terminates`, C++ `TerminatesAttr`: Idris's proof, which holds
||| nothing beyond its presence.
export
terminatesAttr : AttrDef 0
terminatesAttr = MkAttrDef
  { mnemonic = "terminates"
  , stages = between Higher Owned
  , params = []
  , syntax = Declarative []
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , doc = MkDoc "how a function's own loops and recursion are known to end"
      """
      On idr.func exactly when Idris proved that every call of it ends. A
      cycle of calls through the function, or a loop a pass makes of its
      code, ends where every function on it holds it; it may run for ever
      otherwise.
      """
  }
