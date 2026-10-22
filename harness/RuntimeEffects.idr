-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the specification says each op's runtime function does, as
||| tests/runtime-effects reads it: the declared half of a comparison whose
||| other half is LLVM's own reading of the runtime's code, so neither half
||| is the other read back. One line per function an op calls, in the
||| specification's order, one per case where an op calls one per case:
|||
|||     op <symbol> <op> <operands> <said>...
|||
||| `operands` is how many parameters the function takes, one per operand
||| group of the op. Each word of `said` names a sort of effect the
||| declaration has: `crash` (it may end the run by a crash), `exit` (it may
||| end it normally), `memory` (it changes a state the runtime keeps in
||| memory), `operands` (it changes the memory an operand reaches);
||| `nothing` when it has none of them. Then
||| one line per kind of ending a function may end the process through,
||| named as the runtime names its ending's type:
|||
|||     ending crash <name>
|||     ending exit <name>
module RuntimeEffects

import IdrisMLIR.Spec
import IdrisMLIR.Spec.Core.Declarations
import IdrisMLIR.Spec.Core.Ods
import IdrisMLIR.Spec.Core.Op
import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Generator.Cpp
import IdrisMLIR.Spec.Runtime.Endings

import Data.List
import Data.List.Elem
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- What a declaration changes
------------------------------------------------------------------------------

||| Whether an effect of the kind changes what it acts on: a read does not.
data Change = Changes | Keeps

change : Kind -> Change
change Read = Keeps
change Write = Changes
change Allocate = Changes
change Free = Changes

||| Whether the runtime's code changes memory when an op changes the state:
||| a fresh identity is no memory, divergence writes nothing, and a frame is
||| the function's own, which LLVM does not count as memory it touches; the
||| heap, a cell's contents, its count, a memo cell, the runtime's tables
||| and the outside (written through the runtime's buffers), and the ends of
||| the run (each writes its message), are memory.
data Held = InMemory | NoMemory

held : Resource.Resource -> Held
held Root = InMemory
held Frame = NoMemory
held Heap = InMemory
held Contents = InMemory
held Count = InMemory
held MemoState = InMemory
held Identity = NoMemory
held IO = InMemory
held RuntimeState = InMemory
held Exit = InMemory
held Crash = InMemory
held Divergence = NoMemory

||| What one part of a declaration changes: the memory an operand reaches,
||| other memory, or none.
data Changed = OperandMemory | OtherMemory | NoChange

||| An effect of the kind on the state, landing on an operand or elsewhere.
changeOf : Kind -> Resource.Resource -> Changed -> Changed
changeOf k r landing = case (change k, held r) of
  (Changes, InMemory) => landing
  _ => NoChange

effectChanged : Effect i o -> Changed
effectChanged (OnState k r) = changeOf k r OtherMemory
effectChanged (OnValues k r (Operands _)) = changeOf k r OperandMemory
effectChanged (OnValues k r (Results _)) = changeOf k r OtherMemory

anyChanges : List Kind -> Change
anyChanges [] = Keeps
anyChanges (k :: ks) = case change k of
  Changes => Changes
  Keeps => anyChanges ks

||| What a rule gives where its condition holds, or fails: a change of the
||| values it reads when it lands on them and they are operands, of other
||| memory when it lands on the results or on the state.
givenChanged : {0 s : Side} -> Values i o -> Given s -> Changed
givenChanged _ NothingGiven = NoChange
givenChanged values (GivenOn kinds state landing) = case (anyChanges (forget kinds), held state) of
  (Changes, InMemory) => case (landing, values) of
    (OnTheValues, Operands _) => OperandMemory
    _ => OtherMemory
  _ => NoChange

||| What one rule applied to a group may give, either way its condition
||| goes.
oneRuleChanged : Values i o -> RuleName -> List Changed
oneRuleChanged values rule =
  let outcome = consequence rule
  in [givenChanged values outcome.holds, givenChanged values outcome.fails]

||| What a typed rule may give: a rule of one group, as it goes; a pair
||| rule, the rules it applies to its operand and to its result where its
||| relation holds, each landing on the value it reads, and nothing where
||| the relation fails; a call's row, anything.
ruleChanged : TypedRule i o -> List Changed
ruleChanged (ByType rule values) = oneRuleChanged values rule
ruleChanged (ByPair rule operandGroup resultGroup) =
  let pair = pairConsequence rule
  in concatMap (oneRuleChanged (Operands operandGroup)) (operandRules pair)
     ++ concatMap (oneRuleChanged (Results resultGroup)) (resultRules pair)
ruleChanged Summarized = [OperandMemory, OtherMemory]

||| Memory the runtime's function holds that no value names changes when
||| it acquires or frees some.
memoryChanged : RuntimeMemory -> List Changed
memoryChanged Untouched = []
memoryChanged Touched = [OtherMemory]

------------------------------------------------------------------------------
-- What a declaration says, as words
------------------------------------------------------------------------------

anyIn : (a -> Occurs) -> List a -> Occurs
anyIn found [] = Nowhere
anyIn found (x :: xs) = case found x of
  Somewhere => Somewhere
  Nowhere => anyIn found xs

touchesMemory : Changed -> Occurs
touchesMemory NoChange = Nowhere
touchesMemory _ = Somewhere

touchesOperands : Changed -> Occurs
touchesOperands OperandMemory = Somewhere
touchesOperands _ = Nowhere

||| The sorts of effect a declaration has.
record Declared where
  constructor MkDeclared
  crash : Occurs
  exit : Occurs
  memory : Occurs
  operands : Occurs

||| What the declaration of an op says. A definition is never a runtime
||| call; read as MLIR reads it, it may do anything.
declaredBy : Declaration i o -> Declared
declaredBy Definition = MkDeclared Somewhere Somewhere Somewhere Somewhere
declaredBy (Executes effects rules _ memory) =
  let changes = map effectChanged effects ++ concatMap ruleChanged rules
                  ++ memoryChanged memory
  in MkDeclared (anyOf crashes effects) (anyOf endsNormally effects)
                (anyIn touchesMemory changes) (anyIn touchesOperands changes)

declaredWords : Declared -> List String
declaredWords d =
  case wordIf "crash" d.crash ++ wordIf "exit" d.exit ++ wordIf "memory" d.memory ++ wordIf "operands" d.operands of
    [] => ["nothing"]
    ws => ws
  where
    wordIf : String -> Occurs -> List String
    wordIf w Somewhere = [w]
    wordIf _ Nowhere = []

------------------------------------------------------------------------------
-- The lines
------------------------------------------------------------------------------

callLine : Op i o a r -> String -> RuntimeCall i o -> String
callLine op function call =
  unwords (["op", function, opName op, show (length (toList call.takes))]
           ++ declaredWords (declaredBy op.effects))

||| The lines of one op: one per runtime function it calls, none for an op
||| whose meaning is no runtime function.
opLines : AnyOp -> List String
opLines (SomeOp op) = case (callOf op, callsByCase op) of
  (Just call, _) => [callLine op (symbolText call.symbol) call]
  (Nothing, Just (call, functions)) => map (\function => callLine op function call) functions
  (Nothing, Nothing) => []

||| A crash's kind, by the name of its ending's type in the runtime, which
||| is the specification's name for it: the runtime ends a process through
||| one function per ending type.
crashName : Endings.Crash -> String
crashName (Failed _) = "Failed"
crashName Said = "Said"
crashName Unreportable = "Unreportable"

crashNames : List String
crashNames = ["Failed", "Said", "Unreportable"]

||| Every crash's kind is listed, so a kind the specification adds is a
||| hole here, which the totality check refuses.
0 listed : (c : Endings.Crash) -> Elem (crashName c) RuntimeEffects.crashNames
listed (Failed _) = Here
listed Said = There Here
listed Unreportable = There (There Here)

||| Every line, the ops' in the specification's order, then the endings'.
export
effectLines : List String
effectLines = concatMap opLines declarations.ops
        ++ map ("ending crash " ++) crashNames
        ++ ["ending exit Exited"]
