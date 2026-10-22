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
import Data.Vect

%default total

||| Idris did not prove the function's loops end (`Unproved`); it proved
||| them, in the component of its call graph with this number
||| (`InComponent`); or a pass made the function with no loop of its own,
||| so it ends where no cycle of calls reaches it (`Acyclic`).
public export
data Termination = Unproved | InComponent Nat | Acyclic

||| What the attribute holds: a proof, either case but `Unproved`. The
||| attribute is written exactly when there is one, so a function without
||| it is unproved, and none can claim an empty proof.
public export
data Proof = ProvedIn Nat | MadeAcyclic

||| The attribute's one parameter, read and written by a hand directive:
||| `component 3`, `acyclic`.
export
proofDirective : Directive
proofDirective = MkDirective
  { name = "TerminationProof"
  , args = []
  , doc = brief "a termination proof: `component <n>` or `acyclic`"
  }

||| `#idr.terminates<component 3>`, `#idr.terminates<acyclic>`, C++
||| `TerminatesAttr`, its parameter the hand value `::idr::TerminationProof`.
export
terminatesAttr : AttrDef 1
terminatesAttr = MkAttrDef
  { mnemonic = "terminates"
  , params =
      [ MkParameter "proof" (HandValue "::idr::TerminationProof" proofDirective)
          AlwaysWritten "the component Idris proved it in, or a made function's acyclicity" ]
  , syntax = Declarative [Keyword "<", CustomParams proofDirective [FZ], Keyword ">"]
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
