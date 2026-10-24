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
|||
||| The fact is declared once, here: the frontend holds a function's as
||| `Termination`, the C++ as the variant printed from the same cases
||| (Generated/Termination.h.inc), and the IR as `#idr.terminates`, which
||| holds the one case that carries something.
module IdrisMLIR.Spec.Functions.Termination

import IdrisMLIR.Spec.Core.Vocabulary

import Data.Fin
import Data.List.Elem
import Data.List1
import Data.Vect

%default total

||| What Idris proved of a function's own loops, over what a proof holds:
||| nothing (`Unproved`), or the component of its call graph it proved them
||| in (`InComponent`). Over the component's number it is a function's fact
||| (`Termination`); over nothing it is the case alone, the closed set the
||| C++ names its alternatives by, so the frontend's values and the C++
||| cases are one declaration.
public export
data TerminationOf component = Unproved | InComponent component

||| A function's termination: the component's number where Idris proved it.
public export
Termination : Type
Termination = TerminationOf Nat

||| The cases, the C++ `TerminationCase`, whose order `::idr::Termination`'s
||| alternatives keep.
export
terminationClosed : Closed (TerminationOf ())
terminationClosed = MkClosed
  { name = "TerminationCase"
  , shape = OneOf
  , every = Unproved ::: [InComponent ()]
  , complete = \case
      Unproved => Here
      InComponent () => There Here
  , describe = \case
      Unproved => MkCase "Unproved" ("unproved" ::: [])
        "Idris did not prove the function's loops end: a function without the attribute"
      InComponent () => MkCase "InComponent" ("in_component" ::: [])
        "Idris proved its loops end, in the component of its call graph with this number"
  , doc = brief "a termination's case, the alternative of `Termination` it is"
  }

||| What each case holds: a proof, its component, in 32 bits.
terminationMembers : TerminationOf () -> List WireField
terminationMembers Unproved = []
terminationMembers (InComponent ()) = [MkWireField "component" (WireLeaf LeafWord32)]

||| `::idr::Termination`, the variant of `::idr::Unproved` and
||| `::idr::InComponent`, with its cases' enum, printed under
||| Generated/Termination.h.inc, which Func.h includes.
export
terminationHeader : Header
terminationHeader = MkHeader "Termination"
  [ (DialectNamespace, [sumOf terminationClosed "Termination" terminationMembers
      "what is known of a function's own loops, the attribute read"]) ]
  (MkDoc "what Idris proved of a function's own loops"
     """
     One struct per case, holding what the case holds, and their variant,
     in the cases' order.
     """)

||| Idris's proof, as `#idr.terminates` holds it: the struct of the proved
||| case, laid out as its members. The attribute is written exactly when
||| there is one, so a function without it is unproved, and none can claim
||| an empty proof.
componentProofWire : Composite
componentProofWire = MkComposite "ComponentProof" "::idr::InComponent"
  (Fields (terminationMembers (InComponent ())))
  (brief "Idris proved the loops end in this component of its call graph")

||| The proof's text, `component 3`, and its bytecode, both the wire's.
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
  , stages = between Higher Owned
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
