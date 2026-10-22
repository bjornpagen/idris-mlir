-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a specialized copy is to the recursion of the function it was made
||| from, decided when the specializer grants the copy's key and held on the
||| copy, so the inliner reads it from the function alone. A copy whose
||| origin is on no cycle, a raise and a signature copy are none of these:
||| the inliner weighs them as any function, and the function holds no
||| kind.
module IdrisMLIR.Spec.Functions.Copy

import IdrisMLIR.Spec.Core.Vocabulary

import Data.List.Elem
import Data.List1

%default total

||| A step of a recursion on static data, whose next step is another copy:
||| inlined, it would unroll the recursion into its callers, so it is kept
||| (`step`). Or a step that fixes closures alone, of labels outside its
||| origin's component and none of them shared: inlined, it consumes the
||| constructors its caller built and calls the recursion, never itself,
||| so it is weighed even on its caller's cycle (`beta`). A later request
||| that shares a closure makes a beta copy a step, and nothing makes a
||| step anything else.
public export
data CopyKind = Step | Beta

public export
copyKindClosed : Closed CopyKind
copyKindClosed = MkClosed
  { name = "CopyKind"
  , shape = OneOf
  , every = Step ::: [Beta]
  , complete = \case
      Step => Here
      Beta => There Here
  , describe = \case
      Step => MkCase "Step" ("step" ::: []) "a step of a recursion on static data, kept from inlining"
      Beta => MkCase "Beta" ("beta" ::: []) "a step on closures alone, weighed even on its caller's cycle"
  , doc = MkDoc "what a specialized copy is to its origin's recursion"
      """
      Decided when the copy's key is granted and written on the copy once the
      run that made it ends; absent from a function that is none of these.
      """
  }
