-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a program's functions may hold, the stage the pipeline has brought
||| it to, said once on the program so no pass finds it by walking the
||| functions and no verifier guesses it from a grade: `higher`, closures
||| and suspensions, the frontend's; `first`, the first-order program
||| defunctionalization makes; `graded`, every hold strengthened as far as
||| lifetimes and borrows show, before counting places a reference; `owned`,
||| every reference counted; `lowered`, the functions upstream's
||| `llvm.func`, before the program is taken apart. The frontend and the
||| harness import it.
module IdrisMLIR.Spec.Pipeline.Stage

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Enums

import Data.List.Elem
import Data.List1
-- `between`'s automatic `LTE` proof is searched where the call is written.
import public Data.Nat

%default total

public export
data Stage = Higher | First | Graded | Owned | Lowered

||| The stage's place in the chain.
public export
rank : Stage -> Nat
rank Higher = 0
rank First = 1
rank Graded = 2
rank Owned = 3
rank Lowered = 4

public export
stageClosed : Closed Stage
stageClosed = MkClosed
  { name = ident "Stage"
  , shape = OneOf
  , every = Higher ::: [First, Graded, Owned, Lowered]
  , complete = \case
      Higher => Here
      First => There Here
      Graded => There (There Here)
      Owned => There (There (There Here))
      Lowered => There (There (There (There Here)))
  , describe = \case
      Higher => MkCase (ident "Higher") (word "higher" ::: []) (line "closures and suspensions, as the frontend writes them")
      First => MkCase (ident "First") (word "first" ::: []) (line "first-order: every closure a sum, every force a call")
      Graded => MkCase (ident "Graded") (word "graded" ::: []) (line "every hold strengthened before counting places a reference")
      Owned => MkCase (ident "Owned") (word "owned" ::: []) (line "every reference counted")
      Lowered => MkCase (ident "Lowered") (word "lowered" ::: []) (line "upstream's functions, before the program is taken apart")
  , doc = brief (line "what the functions of a program may hold")
  }

||| The stages an op is legal at: every one, or an interval of the chain,
||| its first no later than its last.
public export
data Legal : Type where
  Always : Legal
  Between : (first, last : Stage) -> (0 ordered : LTE (rank first) (rank last)) -> Legal

public export
between : (first, last : Stage) -> {auto 0 ordered : LTE (rank first) (rank last)} -> Legal
between f l = Between f l ordered

||| Whether an op legal at `legal` may stand in a program at `s`.
public export
legalAt : Legal -> Stage -> Bool
legalAt Always _ = True
legalAt (Between f l _) s = rank f <= rank s && rank s <= rank l

------------------------------------------------------------------------------
-- What a stage implies
------------------------------------------------------------------------------

||| Whether closures and suspensions may remain, which defunctionalization
||| makes sums.
public export
data StageClosures = ClosuresRemain | FirstOrder

||| Whether references are counted exactly, which placement makes.
public export
data StageCounting = ReferencesUncounted | ReferencesCounted

||| Whether the program's functions are ours, or upstream's lowered ones.
public export
data StageFunctions = OurFunctions | LoweredFunctions

||| Whether a call's tail fact is a promise, which the frontend makes and a
||| call keeps, or the one decider's answer on every call, which the pass
||| that makes the program first order writes and every pass after keeps.
public export
data StageTails = TailsPromised | TailsDecided

public export
closuresClosed : Closed StageClosures
closuresClosed = MkClosed
  { name = ident "StageClosures", shape = OneOf, every = ClosuresRemain ::: [FirstOrder]
  , complete = \case
      ClosuresRemain => Here
      FirstOrder => There Here
  , describe = \case
      ClosuresRemain => MkCase (ident "Remain") (word "remain" ::: []) (line "closures and suspensions may remain")
      FirstOrder => MkCase (ident "FirstOrder") (word "first_order" ::: []) (line "every closure is a constructor of a sum")
  , doc = brief (line "whether closures may remain") }

public export
countingClosed : Closed StageCounting
countingClosed = MkClosed
  { name = ident "StageCounting", shape = OneOf, every = ReferencesUncounted ::: [ReferencesCounted]
  , complete = \case
      ReferencesUncounted => Here
      ReferencesCounted => There Here
  , describe = \case
      ReferencesUncounted => MkCase (ident "Uncounted") (word "uncounted" ::: []) (line "references are not yet counted")
      ReferencesCounted => MkCase (ident "Counted") (word "counted" ::: []) (line "every reference is counted exactly")
  , doc = brief (line "whether references are counted") }

public export
functionsClosed : Closed StageFunctions
functionsClosed = MkClosed
  { name = ident "StageFunctions", shape = OneOf, every = OurFunctions ::: [LoweredFunctions]
  , complete = \case
      OurFunctions => Here
      LoweredFunctions => There Here
  , describe = \case
      OurFunctions => MkCase (ident "Ours") (word "ours" ::: []) (line "the program's functions are idr.func")
      LoweredFunctions => MkCase (ident "Lowered") (word "lowered" ::: []) (line "the program's functions are upstream's")
  , doc = brief (line "whose functions the program holds") }

public export
tailsClosed : Closed StageTails
tailsClosed = MkClosed
  { name = ident "StageTails", shape = OneOf, every = TailsPromised ::: [TailsDecided]
  , complete = \case
      TailsPromised => Here
      TailsDecided => There Here
  , describe = \case
      TailsPromised => MkCase (ident "Promised") (word "promised" ::: []) (line "a tail or modulo_context call is a promise, and a nontail one makes none")
      TailsDecided => MkCase (ident "Decided") (word "decided" ::: []) (line "every call's tail fact is the decider's answer")
  , doc = brief (line "whether every call's tail fact is decided") }

public export
closuresAt : Stage -> StageClosures
closuresAt Higher = ClosuresRemain
closuresAt _ = FirstOrder

public export
countingAt : Stage -> StageCounting
countingAt Owned = ReferencesCounted
countingAt Lowered = ReferencesCounted
countingAt _ = ReferencesUncounted

public export
functionsAt : Stage -> StageFunctions
functionsAt Lowered = LoweredFunctions
functionsAt _ = OurFunctions

public export
tailsAt : Stage -> StageTails
tailsAt Higher = TailsPromised
tailsAt _ = TailsDecided

||| What each stage implies, one row per stage: only the five stages have a
||| row, so no combination of facts a stage cannot have is written.
public export
stageFacts : Table
stageFacts = table stageClosed
  [ MkColumn (ident "closuresAt") (EnumColumn (enumDef closuresClosed)) (\s => CaseCell (caseRef closuresClosed (closuresAt s))) (line "whether closures may remain")
  , MkColumn (ident "countingAt") (EnumColumn (enumDef countingClosed)) (\s => CaseCell (caseRef countingClosed (countingAt s))) (line "whether references are counted")
  , MkColumn (ident "functionsAt") (EnumColumn (enumDef functionsClosed)) (\s => CaseCell (caseRef functionsClosed (functionsAt s))) (line "whose functions the program holds")
  , MkColumn (ident "tailsAt") (EnumColumn (enumDef tailsClosed)) (\s => CaseCell (caseRef tailsClosed (tailsAt s))) (line "whether every call's tail fact is decided")
  ]
