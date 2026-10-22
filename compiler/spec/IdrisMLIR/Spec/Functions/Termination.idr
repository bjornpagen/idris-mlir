-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What is known of whether a function's own loops and recursion end: the
||| one input of a function's row that is no op. Idris's termination
||| checker decides it per component of Idris's own call graph, so the fact
||| names that component: specialization and defunctionalization make
||| cycles Idris's graph never had, and a cycle of ours ends only where
||| every function on it was proved in one and the same component of
||| Idris's. A function a pass makes takes its origin's fact, or, made with
||| no loop of its own (a dispatch, a force), ends wherever no cycle of
||| calls reaches it. Nothing clears the fact: code a body takes in brings
||| its own partiality with it, in its ops and in the rows of its calls.
module IdrisMLIR.Spec.Functions.Termination

import IdrisMLIR.Spec.Core.Vocabulary

import Data.Fin
import Data.List.Elem
import Data.List1
import Data.Vect

%default total

||| Idris did not prove the function's loops end (`Unproved`); it proved
||| them, in the component of its call graph with this number
||| (`InComponent`); or a pass made the function with no loop of its own,
||| so it ends where no cycle of calls reaches it (`Acyclic`).
public export
data Termination = Unproved | InComponent Nat | Acyclic

||| Which proof the attribute holds: Idris's, in a component of its call
||| graph, or a pass's, for a function it made with no loop of its own.
public export
data ProofKind = ProvedInComponent | MadeAcyclic

public export
proofKindClosed : Closed ProofKind
proofKindClosed = MkClosed
  { name = "ProofKind"
  , shape = OneOf
  , every = ProvedInComponent ::: [MadeAcyclic]
  , complete = \case
      ProvedInComponent => Here
      MadeAcyclic => There Here
  , describe = \case
      ProvedInComponent => MkCase "Component" ("component" ::: [])
                             "Idris proved the loops end in a component of its call graph"
      MadeAcyclic => MkCase "Acyclic" ("acyclic" ::: []) "a pass made the function with no loop of its own"
  , doc = brief "which proof a function's termination attribute holds"
  }

||| Idris's proof: the component of its call graph, in 32 bits.
public export
componentProofWire : Composite
componentProofWire = MkComposite "ComponentProof" "::idr::InComponent"
  (Fields [MkWireField "component" (WireLeaf LeafWord32)])
  (brief "Idris proved the loops end in this component of its call graph")

||| A made function's acyclicity, which holds nothing more.
public export
acyclicProofWire : Composite
acyclicProofWire = MkComposite "AcyclicProof" "::idr::Acyclic" (Fields [])
  (brief "a pass made the function with no loop of its own")

||| What the attribute holds: a proof, either case but `Unproved`, its kind
||| then what the kind holds. The attribute is written exactly when there is
||| one, so a function without it is unproved, and none can claim an empty
||| proof.
public export
proofWire : Composite
proofWire = MkComposite "TerminationProof" "::idr::TerminationProof"
  (variant proofKindClosed (\case
     ProvedInComponent => componentProofWire
     MadeAcyclic => acyclicProofWire))
  (brief "a termination proof: its kind, then what the kind holds")

||| The proof's text, `component 3` or `acyclic`; its bytecode is the
||| wire's.
export
proofDirective : Directive
proofDirective = MkDirective
  { name = "Proof"
  , args = []
  , doc = brief "a termination proof: `component <n>` or `acyclic`"
  }

||| `#idr.terminates<component 3>`, `#idr.terminates<acyclic>`, C++
||| `TerminatesAttr`, its parameter a `::idr::TerminationProof`.
export
terminatesAttr : AttrDef 1
terminatesAttr = MkAttrDef
  { mnemonic = "terminates"
  , params =
      [ MkParameter "proof" (WiredValue (WiredOf proofWire) proofDirective)
          AlwaysWritten "the component Idris proved it in, or a made function's acyclicity" ]
  , syntax = Declarative [Keyword "<", ParamAt FZ, Keyword ">"]
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , doc = MkDoc "how a function's own loops and recursion are known to end"
      """
      On idr.func exactly when Idris proved its loops end, or a pass made it
      with no loop of its own; its row holds divergence otherwise.
      """
  }
