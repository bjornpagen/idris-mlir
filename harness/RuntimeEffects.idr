-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Every op's declaration of its effects held to what its runtime function
||| does (tests/runtime-effects): the declared half is the specification's,
||| read here as it stands; the other half is LLVM's own reading of the
||| runtime's code, the module opt prints after inferring every function's
||| attributes from its body, so neither half is the other read back.
|||
|||     runtests --runtime-effects <module>
|||
||| prints whether every ending the specification names ends a process
||| through a function of the runtime, whether every op's declaration covers
||| what its function does (naming each op that breaks a relation), and
||| whether each relation names the op of a row made wrong (planting).
|||
||| Where a function reaches code outside the module (the C library, GMP),
||| LLVM knows nothing of what it does to memory, and the memory relations
||| do not judge it; its endings, its calls and its parameters are judged
||| all the same.
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
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.String
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
ruleChanged : {0 i, o : Nat} -> TypedRule i o -> List Changed
ruleChanged (ByType rule values) = oneRuleChanged values rule
ruleChanged (ByPair rule operandGroup resultGroup) =
  let pair = pairConsequence rule
  in concatMap (oneRuleChanged (Operands {o} operandGroup)) (operandRules pair)
     ++ concatMap (oneRuleChanged (Results {i} resultGroup)) (resultRules pair)
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
-- The declared half
------------------------------------------------------------------------------

||| One call of a runtime function by an op: the function's symbol, the
||| op's mnemonic, how many parameters the function takes (one per operand
||| group of the op), and what the op's declaration says.
record Row where
  constructor MkRow
  symbol : String
  mnemonic : String
  operands : Nat
  declared : Declared

callRow : Op i o a r -> String -> RuntimeCall i o -> Row
callRow op function call =
  MkRow function (opName op) (length (toList call.takes)) (declaredBy op.effects)

||| The rows of one op: one per runtime function it calls, one per case
||| where an op calls one per case, none for an op whose meaning is no
||| runtime function.
opRows : AnyOp -> List Row
opRows (SomeOp op) = case (callOf op, callsByCase op) of
  (Just call, _) => [callRow op (symbolText call.symbol) call]
  (Nothing, Just (call, functions)) => map (\function => callRow op function call) functions
  (Nothing, Nothing) => []

||| Every op's rows, in the specification's order.
declaredRows : List Row
declaredRows = concatMap opRows declarations.ops

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

||| Whether an ending of the run is a crash's or the exit's.
data EndingKind = CrashEnding | ExitEnding

Eq EndingKind where
  CrashEnding == CrashEnding = True
  ExitEnding == ExitEnding = True
  _ == _ = False

kindWord : EndingKind -> String
kindWord CrashEnding = "crash"
kindWord ExitEnding = "exit"

||| A type the runtime ends a process through: its kind, and its name in
||| the runtime.
record EndingType where
  constructor MkEndingType
  kind : EndingKind
  name : String

endingTypes : List EndingType
endingTypes = map (MkEndingType CrashEnding) crashNames ++ [MkEndingType ExitEnding "Exited"]

||| The function the runtime ends a process through for an ending type,
||| the template rt::end::end instantiated for it, whose name the type's
||| name fixes: `void rt::end::end<rt::end::NAME>(rt::end::NAME const&)`,
||| mangled.
endingSymbol : String -> String
endingSymbol name = "_ZN2rt3end3endINS0_" ++ show (length name) ++ name ++ "EEEvRKT_"

------------------------------------------------------------------------------
-- LLVM's half: the module opt prints
------------------------------------------------------------------------------

||| What LLVM proved a function does to memory: nothing, only reads, or
||| writes; or nothing it can prove, where the function reaches a call LLVM
||| knows nothing of (a function outside the module with no stated effects,
||| a call through a pointer), since then the absence of a stated effect
||| proves nothing.
data Memory = NoAccess | ReadsOnly | WritesSome | Unknown

||| Whether LLVM proved a function never returns.
data Returning = NeverReturns | MayReturn

||| What LLVM reads of one function: whether it returns; whether it reaches,
||| through the calls of the module's functions, the function the runtime
||| ends a process through for a crash, or for the exit; what it does to
||| memory; and the parameters, from 0, of pointer type, through which it
||| may write and which it never lets go of, so that what such a parameter
||| points to is written by the function's own code.
record Reading where
  constructor MkReading
  returning : Returning
  crashes : Occurs
  exits : Occurs
  memory : Memory
  written : List Nat

||| The module's text, read once: each function it defines, with the
||| parameters it writes through; the attribute group of each function it
||| defines or declares; the functions it only declares; each attribute
||| group's text; the callees of each function it defines, intrinsics left
||| out, whose effects LLVM knows; and the functions that make a call LLVM
||| names no callee of.
record Module where
  constructor MkModule
  defined : SortedMap String (List Nat)
  groups : SortedMap String String
  outside : List String
  attributes : SortedMap String String
  edges : SortedMap String (List String)
  opaque : SortedSet String

emptyModule : Module
emptyModule = MkModule empty empty [] empty empty empty

stripPrefixL : List Char -> List Char -> Maybe (List Char)
stripPrefixL [] cs = Just cs
stripPrefixL (p :: ps) (c :: cs) = if p == c then stripPrefixL ps cs else Nothing
stripPrefixL (_ :: _) [] = Nothing

nameChar : Char -> Bool
nameChar c = isAlphaNum c || c == '-' || c == '_' || c == '.' || c == '$'

||| A name after its sigil, quoted or bare, without its quotes, and what
||| follows it.
nameAfter : List Char -> Maybe (List Char, List Char)
nameAfter ('"' :: rest) = case break (== '"') rest of
  (inside, '"' :: after) => Just (inside, after)
  _ => Nothing
nameAfter cs = case span nameChar cs of
  ([], _) => Nothing
  (name, after) => Just (name, after)

||| The first name of a line that one of the sigils starts and an opening
||| parenthesis follows (`@name(`, `@"name"(`, `%value(`): the sigil, the
||| name, and what follows the parenthesis.
firstCalled : (Char -> Bool) -> List Char -> Maybe (Char, String, List Char)
firstCalled sigil [] = Nothing
firstCalled sigil (c :: rest) =
  if sigil c
     then case nameAfter rest of
            Just (name, '(' :: after) => Just (c, pack name, after)
            _ => firstCalled sigil rest
     else firstCalled sigil rest

opens : Char -> Bool
opens c = c == '(' || c == '{' || c == '[' || c == '<'

closes : Char -> Bool
closes c = c == ')' || c == '}' || c == ']' || c == '>'

||| The parameters after a definition's opening parenthesis, split at the
||| commas outside brackets, and what follows the closing parenthesis.
paramsOf : List Char -> (List String, List Char)
paramsOf = go Z [<] [<]
  where
    kept : SnocList String -> SnocList Char -> SnocList String
    kept done cur = if any (/= ' ') (cur <>> []) then done :< pack (cur <>> []) else done

    go : Nat -> SnocList String -> SnocList Char -> List Char -> (List String, List Char)
    go _ done _ [] = (done <>> [], [])
    go depth done cur (c :: rest) =
      if opens c then go (S depth) done (cur :< c) rest
      else if closes c then
        case depth of
          Z => (kept done cur <>> [], rest)
          S d => go d done (cur :< c) rest
      else if c == ',' && depth == 0 then go depth (done :< pack (cur <>> [])) [<] rest
      else go depth done (cur :< c) rest

||| Whether a parameter is a pointer the function writes through and never
||| lets go of: of pointer type, neither readonly nor readnone, and not
||| captured.
writtenParam : String -> Bool
writtenParam p =
  let ws = words p in
  elem "ptr" ws && not (elem "readonly" ws || elem "readnone" ws)
    && (elem "nocapture" ws || isInfixOf "captures(none)" p)

indexed : Nat -> List a -> List (Nat, a)
indexed _ [] = []
indexed n (x :: xs) = (n, x) :: indexed (S n) xs

writtenPositions : List String -> List Nat
writtenPositions ps = map fst (filter (writtenParam . snd) (indexed 0 ps))

||| The attribute group a definition's line names after its parameters.
groupIn : List Char -> Maybe String
groupIn [] = Nothing
groupIn ('#' :: rest) = case span isDigit rest of
  ([], _) => groupIn rest
  (ds, _) => Just (pack ds)
groupIn (_ :: rest) = groupIn rest

||| The group an `attributes #<n> = {` line states.
attributeGroup : List Char -> Maybe String
attributeGroup cs = do
  rest <- stripPrefixL (unpack "attributes #") cs
  case span isDigit rest of
    (ds@(_ :: _), after) => map (const (pack ds)) (stripPrefixL (unpack " = {") after)
    _ => Nothing

||| What follows the keyword of a call or invoke instruction, when the line
||| holds one: `call ` or `invoke `, after `tail `, `musttail ` or
||| `notail ` if any, at the line's start or after a space or an `=`.
afterCall : List Char -> Maybe (List Char)
afterCall cs = keyword cs <|> after cs
  where
    instruction : List Char -> Maybe (List Char)
    instruction s = stripPrefixL (unpack "call ") s <|> stripPrefixL (unpack "invoke ") s

    keyword : List Char -> Maybe (List Char)
    keyword s = instruction s
            <|> (stripPrefixL (unpack "tail ") s >>= instruction)
            <|> (stripPrefixL (unpack "musttail ") s >>= instruction)
            <|> (stripPrefixL (unpack "notail ") s >>= instruction)

    after : List Char -> Maybe (List Char)
    after [] = Nothing
    after (c :: rest) = (if c == ' ' || c == '=' then keyword rest else Nothing) <|> after rest

||| What a line of a function's body calls: nothing; a function, by its
||| name; or something LLVM names no callee of (a call through a pointer,
||| inline assembly).
data Callee = NoCall | Calls String | Opaque

calleeOf : List Char -> Callee
calleeOf cs = case afterCall cs of
  Nothing => NoCall
  Just rest => case firstCalled (\c => c == '@' || c == '%') rest of
    Just ('@', name, _) => Calls name
    _ => Opaque

||| One line of the module read into it, inside the function the lines
||| before it left open, if any.
step : (Maybe String, Module) -> String -> (Maybe String, Module)
step (current, m) line =
  if isPrefixOf "define " line then define
  else if isPrefixOf "declare " line then declare
  else case attributeGroup chars of
    Just g => (current, { attributes $= insert g line } m)
    Nothing => case current of
      Nothing => (Nothing, m)
      Just f => if isPrefixOf "}" line then (Nothing, m) else body f
  where
    chars : List Char
    chars = unpack line

    grouped : String -> List Char -> Module -> Module
    grouped name rest m' = maybe m' (\g => { groups $= insert name g } m') (groupIn rest)

    define : (Maybe String, Module)
    define = case firstCalled (== '@') chars of
      Nothing => (Nothing, m)
      Just (_, name, after) =>
        let (ps, rest) = paramsOf after in
        (Just name, grouped name rest ({ defined $= insert name (writtenPositions ps) } m))

    declare : (Maybe String, Module)
    declare = case firstCalled (== '@') chars of
      Nothing => (current, m)
      Just (_, name, after) =>
        (current, grouped name (snd (paramsOf after)) ({ outside $= (name ::) } m))

    -- An intrinsic's effects are LLVM's own, known to it.
    body : String -> (Maybe String, Module)
    body f = case calleeOf chars of
      NoCall => (Just f, m)
      Opaque => (Just f, { opaque $= insert f } m)
      Calls callee =>
        if isPrefixOf "llvm." callee then (Just f, m)
        else (Just f, { edges $= insert f (callee :: fromMaybe [] (lookup f m.edges)) } m)

readModule : String -> Module
readModule text = snd (foldl step (Nothing, emptyModule) (lines text))

||| The text of the first `memory(...)` attribute of a group's text.
memoryIn : List Char -> Maybe (List Char)
memoryIn [] = Nothing
memoryIn cs@(_ :: rest) = case stripPrefixL (unpack "memory(") cs of
  Just after => case break (== ')') after of
    (inside, ')' :: _) => Just inside
    _ => memoryIn rest
  Nothing => memoryIn rest

||| What a memory attribute's text says: writes when any location may be
||| written, else reads when any may be read, else nothing.
memoryOf : List Char -> Memory
memoryOf spec =
  let accesses = map access (forget (split (== ',') spec)) in
  if any (isInfixOf (unpack "write")) accesses then WritesSome
  else if any (isInfixOf (unpack "read")) accesses then ReadsOnly
  else NoAccess
  where
    access : List Char -> List Char
    access part =
      let trimmed = dropWhile (== ' ') part in
      case break (== ':') trimmed of
        (_, ':' :: after) => dropWhile (== ' ') after
        _ => trimmed

||| How an attribute group's text spells `noreturn`, between its neighbours.
noreturnSpellings : List String
noreturnSpellings = [" noreturn ", " noreturn}", "{noreturn ", "{noreturn}"]

noreturnIn : String -> Returning
noreturnIn text =
  if any (`isInfixOf` text) noreturnSpellings
     then NeverReturns else MayReturn

attributesOf : Module -> String -> String
attributesOf m name = fromMaybe "" (lookup name m.groups >>= \g => lookup g m.attributes)

||| The functions LLVM knows nothing of: those that make a call it names no
||| callee of, and those outside the module whose effects nothing states.
opaqueOf : Module -> SortedSet String
opaqueOf m = foldl unstated m.opaque m.outside
  where
    unstated : SortedSet String -> String -> SortedSet String
    unstated s name = case memoryIn (unpack (attributesOf m name)) of
      Nothing => insert name s
      Just _ => s

||| Every function a function reaches by calls, itself included. A name is
||| queued only when first seen, and a module names finitely many, so the
||| walk ends.
covering
reached : Module -> String -> SortedSet String
reached m start = go [start] (SortedSet.singleton start)
  where
    covering
    go : List String -> SortedSet String -> SortedSet String
    go [] seen = seen
    go (u :: queue) seen =
      let fresh = nub (filter (\v => not (contains v seen)) (fromMaybe [] (lookup u m.edges))) in
      go (queue ++ fresh) (foldl (flip insert) seen fresh)

||| Whether a call among `called` ends a process as an ending of the kind.
endsAs : EndingKind -> List String -> Occurs
endsAs kind called =
  let symbols = map (\t => endingSymbol t.name) (filter (\t => t.kind == kind) endingTypes) in
  if any (`elem` symbols) called then Somewhere else Nowhere

||| What LLVM reads of the function `symbol`, if the module defines it.
covering
readingOf : Module -> SortedSet String -> String -> Maybe Reading
readingOf m opaque symbol = do
  written <- lookup symbol m.defined
  let seen = Prelude.toList (reached m symbol)
  let called = concatMap (\u => fromMaybe [] (lookup u m.edges)) seen
  let text = attributesOf m symbol
  let memory = case memoryIn (unpack text) of
                 Just spec => memoryOf spec
                 Nothing => if any (`contains` opaque) seen then Unknown else WritesSome
  pure (MkReading (noreturnIn text) (endsAs CrashEnding called) (endsAs ExitEnding called) memory written)

||| LLVM's reading of every function a row names, by its symbol; a function
||| the module does not define has none.
covering
readingsOf : Module -> SortedMap String Reading
readingsOf m =
  let opaque = opaqueOf m in
  fromList (mapMaybe (\s => map (\r => (s, r)) (readingOf m opaque s)) (nub (map (.symbol) declaredRows)))

------------------------------------------------------------------------------
-- The relations
------------------------------------------------------------------------------

||| A relation an op's declaration must keep with what its function does:
|||
|||   missing   the function is in the runtime;
|||   stops     a function that never returns is an op's that may crash or exit;
|||   crash     one that reaches a crash's ending is an op's that may crash;
|||   exit      one that reaches the exit's ending is an op's that may exit;
|||   inert     one LLVM proves writes no memory is an op's that changes none,
|||             and neither crashes nor exits, each of which writes its message;
|||   operand   one that writes through an operand it never lets go of is an
|||             op's that changes an operand's memory;
|||   writes    one LLVM proves writes memory is an op's that changes some.
data Relation
  = NotInRuntime | NeverReturning | ReachesCrash | ReachesExit
  | WritesNothing | WritesOperand | WritesMemory

relationWord : Relation -> String
relationWord NotInRuntime = "missing"
relationWord NeverReturning = "stops"
relationWord ReachesCrash = "crash"
relationWord ReachesExit = "exit"
relationWord WritesNothing = "inert"
relationWord WritesOperand = "operand"
relationWord WritesMemory = "writes"

||| The relations a planted row is shown to: every one but `missing`, which
||| a function present cannot break.
plantedRelations : List Relation
plantedRelations = [NeverReturning, ReachesCrash, ReachesExit, WritesNothing, WritesOperand, WritesMemory]

somewhere : Occurs -> Bool
somewhere Somewhere = True
somewhere Nowhere = False

endsRun : Declared -> Bool
endsRun d = somewhere d.crash || somewhere d.exit

saysNothing : Declared -> Bool
saysNothing d = not (endsRun d || somewhere d.memory || somewhere d.operands)

neverReturns : Returning -> Bool
neverReturns NeverReturns = True
neverReturns MayReturn = False

writesNone : Memory -> Bool
writesNone NoAccess = True
writesNone ReadsOnly = True
writesNone _ = False

writesSome : Memory -> Bool
writesSome WritesSome = True
writesSome _ = False

onlyIf : Bool -> a -> List a
onlyIf True x = [x]
onlyIf False _ = []

||| A relation an op breaks: the row, the relation, and what is wrong.
record Finding where
  constructor MkFinding
  row : Row
  relation : Relation
  what : String

findingLine : Finding -> String
findingLine f = f.row.mnemonic ++ " (" ++ f.row.symbol ++ "): " ++ relationWord f.relation ++ ": " ++ f.what

||| The relations one row breaks, against LLVM's readings. Where LLVM knows
||| nothing of what the function does to memory, the memory relations do
||| not judge it; the endings, the calls and the parameters still do.
findingsOf : SortedMap String Reading -> Row -> List Finding
findingsOf readings row = case lookup row.symbol readings of
  Nothing => [MkFinding row NotInRuntime "its function is not in the runtime"]
  Just r =>
    let d = row.declared in
    onlyIf (neverReturns r.returning && not (endsRun d))
      (MkFinding row NeverReturning "its function never returns, and it declares neither a crash nor an exit")
    ++ onlyIf (somewhere r.crashes && not (somewhere d.crash))
      (MkFinding row ReachesCrash "its function may crash, and it declares no crash")
    ++ onlyIf (somewhere r.exits && not (somewhere d.exit))
      (MkFinding row ReachesExit "its function may end the run normally, and it declares no exit")
    ++ onlyIf (writesNone r.memory && (somewhere d.memory || endsRun d))
      (MkFinding row WritesNothing ("its function writes no memory, and it declares" ++ concatMap (" " ++) (declaredWords d)))
    ++ (if somewhere d.operands then [] else
          map (\k => MkFinding row WritesOperand
                       ("its function writes through operand " ++ show k ++ ", and it declares no change to an operand's memory"))
              (filter (< row.operands) r.written))
    ++ onlyIf (writesSome r.memory && saysNothing d)
      (MkFinding row WritesMemory "its function writes memory, and it declares no change to any")

findingLines : List Row -> SortedMap String Reading -> List String
findingLines rs readings = map findingLine (concatMap (findingsOf readings) rs)

------------------------------------------------------------------------------
-- A row made wrong
------------------------------------------------------------------------------

||| The rows and readings with one row made wrong, and that row, whose op
||| the relation must name.
record Planted where
  constructor MkPlanted
  rows : List Row
  readings : SortedMap String Reading
  row : Row

||| The declaration made wrong where the row's function makes the relation
||| bite: its crash, exit, change or silence dropped or added, so that what
||| is planted is a wrong declaration of a real function.
wrongDeclaration : Relation -> Reading -> Row -> Maybe Declared
wrongDeclaration NotInRuntime _ _ = Nothing
wrongDeclaration NeverReturning r row =
  if neverReturns r.returning && endsRun row.declared
     then Just ({ crash := Nowhere, exit := Nowhere } row.declared) else Nothing
wrongDeclaration ReachesCrash r row =
  if somewhere r.crashes && somewhere row.declared.crash then Just ({ crash := Nowhere } row.declared) else Nothing
wrongDeclaration ReachesExit r row =
  if somewhere r.exits && somewhere row.declared.exit then Just ({ exit := Nowhere } row.declared) else Nothing
wrongDeclaration WritesNothing r row =
  if writesNone r.memory && saysNothing row.declared
     then Just (MkDeclared Nowhere Nowhere Somewhere Nowhere) else Nothing
wrongDeclaration WritesOperand r row =
  if any (< row.operands) r.written && somewhere row.declared.operands
     then Just ({ operands := Nowhere } row.declared) else Nothing
wrongDeclaration WritesMemory r row =
  if writesSome r.memory && not (saysNothing row.declared)
     then Just (MkDeclared Nowhere Nowhere Nowhere Nowhere) else Nothing

||| The function read wrong instead, where no function of this runtime
||| makes the relation bite, so that every relation is shown to catch what
||| it forbids on every target.
wrongReading : Relation -> Reading -> Row -> Maybe Reading
wrongReading NotInRuntime _ _ = Nothing
wrongReading NeverReturning r row =
  if endsRun row.declared then Nothing else Just ({ returning := NeverReturns } r)
wrongReading ReachesCrash r row =
  if somewhere row.declared.crash then Nothing else Just ({ crashes := Somewhere } r)
wrongReading ReachesExit r row =
  if somewhere row.declared.exit then Nothing else Just ({ exits := Somewhere } r)
wrongReading WritesNothing r row =
  if somewhere row.declared.memory then Just ({ memory := NoAccess } r) else Nothing
wrongReading WritesOperand r row =
  if row.operands > 0 && not (somewhere row.declared.operands) then Just ({ written := [0] } r) else Nothing
wrongReading WritesMemory r row =
  if saysNothing row.declared then Just ({ memory := WritesSome } r) else Nothing

||| The first row, in the specification's order, whose declaration can be
||| made wrong for the relation; else the first whose function can be read
||| wrong; else none.
plant : SortedMap String Reading -> Relation -> Maybe Planted
plant readings relation = declaredSide [<] declaredRows <|> readingSide declaredRows
  where
    declaredSide : SnocList Row -> List Row -> Maybe Planted
    declaredSide _ [] = Nothing
    declaredSide before (row :: after) =
      case lookup row.symbol readings >>= \r => wrongDeclaration relation r row of
        Just d =>
          let wrong = { declared := d } row in
          Just (MkPlanted (before <>> (wrong :: after)) readings wrong)
        Nothing => declaredSide (before :< row) after

    readingSide : List Row -> Maybe Planted
    readingSide [] = Nothing
    readingSide (row :: after) =
      case lookup row.symbol readings >>= \r => wrongReading relation r row of
        Just r' => Just (MkPlanted declaredRows (insert row.symbol r' readings) row)
        Nothing => readingSide after

||| Why a relation does not name the op of the row made wrong, if it does
||| not: no row could be made wrong, or the finding the row must bring is
||| not among the planted tables' findings, or is among the true ones'.
missedBy : SortedMap String Reading -> (true : List String) -> Relation -> Maybe String
missedBy readings true relation = case plant readings relation of
  Nothing => Just (relationWord relation ++ " (no row to plant)")
  Just p =>
    let expected = p.row.mnemonic ++ " (" ++ p.row.symbol ++ "): " ++ relationWord relation ++ ":"
        planted = findingLines p.rows p.readings
    in if any (isInfixOf expected) planted && not (any (isInfixOf expected) true)
          then Nothing else Just (relationWord relation)

------------------------------------------------------------------------------
-- The lines
------------------------------------------------------------------------------

||| `--runtime-effects <module>`: the endings, the relations and the planted
||| rows, held against the module's text, a line each, with what fails
||| under it.
export covering
heldLines : (moduleText : String) -> List String
heldLines text = case declaredRows of
  [] => ["declared: no op calls the runtime"]
  _ =>
    let m = readModule text
        readings = readingsOf m
        absent = filter (\t => isNothing (lookup (endingSymbol t.name) m.defined)) endingTypes
        true = findingLines declaredRows readings
        missed = mapMaybe (missedBy readings true) plantedRelations
    in (case absent of
          [] => ["endings: each the specification names ends a process through a function of the runtime"]
          _ => "endings: no function of the runtime ends a process as:"
               :: map (\t => "  " ++ kindWord t.kind ++ " " ++ t.name) absent)
       ++ (case true of
             [] => ["relations: every op's declaration covers what its runtime function does"]
             _ => "relations: declarations that do not cover what their runtime function does:"
                  :: map ("  " ++) true)
       ++ [case missed of
             [] => "planted: each relation names the op of the row made wrong"
             _ => "planted: relations that do not name the row made wrong:" ++ concatMap (" " ++) missed]
