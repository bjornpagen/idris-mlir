-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What is known of whether a function's own loops and recursion end, read
||| wherever a cycle runs through the function: whether a loop a pass makes
||| of its code may not end, and whether a cycle of calls through it does.
||| Idris's termination checker decides it per component of Idris's own
||| call graph, so the fact names that component: specialization and
||| defunctionalization make cycles Idris's graph never had, and a cycle of
||| ours ends only where every function on it was proved in one and the
||| same component of Idris's. A function a pass makes takes its origin's
||| fact; one made with no origin (a dispatch, a force) has none, since only
||| a cycle through it asks and no proof covers that cycle. Nothing clears
||| the fact: code a body takes in brings its own partiality with it, in its
||| ops and in the rows of its calls.
module IdrisMLIR.Spec.Functions.Termination

import IdrisMLIR.Spec.Core.Vocabulary

import Data.Fin
import Data.List1
import Data.Vect

%default total

||| Idris did not prove the function's loops end (`Unproved`), or it proved
||| them, in the component of its call graph with this number
||| (`InComponent`).
public export
data Termination = Unproved | InComponent Nat

||| Idris's proof: the component of its call graph, in 32 bits. The
||| attribute is written exactly when there is one, so a function without
||| it is unproved, and none can claim an empty proof.
public export
componentProofWire : Composite
componentProofWire = MkComposite "ComponentProof" "::idr::InComponent"
  (Fields [MkWireField "component" (WireLeaf LeafWord32)])
  (brief "Idris proved the loops end in this component of its call graph")

||| The proof's text, `component 3`; its bytecode is the wire's.
export
proofDirective : Directive
proofDirective = MkDirective
  { name = "Proof"
  , args = []
  , doc = brief "a termination proof: `component <n>`"
  }

||| `#idr.terminates<component 3>`, C++ `TerminatesAttr`, its parameter a
||| `::idr::InComponent`.
export
terminatesAttr : AttrDef 1
terminatesAttr = MkAttrDef
  { mnemonic = "terminates"
  , params =
      [ MkParameter "proof" (WiredValue (WiredOf componentProofWire) proofDirective)
          AlwaysWritten "the component Idris proved it in" ]
  , syntax = Declarative [Keyword "<", ParamAt FZ, Keyword ">"]
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , doc = MkDoc "how a function's own loops and recursion are known to end"
      """
      On idr.func exactly when Idris proved its loops end, in the component
      of its call graph named. A cycle of calls through the function, or a
      loop a pass makes of its code, ends only where every function on it
      holds the same component; it may run for ever otherwise.
      """
  }
