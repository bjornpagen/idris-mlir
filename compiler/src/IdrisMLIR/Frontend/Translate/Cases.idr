-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Case trees: Idris's compile-time case trees (`treeCT`) as Core matches.
||| A match on a compile-time value selects its alternative now, and so does
||| a match on a value of a type with one runtime field, which is its
||| field's value.
module IdrisMLIR.Frontend.Translate.Cases

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Choices
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Given
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Terms
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.WellFounded
import Data.Fin
import Data.List
import Data.List1
import Data.String
import Decidable.Equality
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default total

-- A scope here is always a term's, the checker's: where a rule is decided
-- is no question this module asks.
%hide IdrisMLIR.Spec.Core.Rules.Scope

------------------------------------------------------------------------------
-- The clauses a leaf reads its variables by
------------------------------------------------------------------------------

mutual
  ||| A place of a clause's left-hand side as Idris's case builder read it,
  ||| which Idris keeps with the definition (`PMDef`'s clause patterns): the
  ||| clause's binders it names the whole by (a variable, and the names its
  ||| as-patterns give), each the name Idris closed the clause's binder
  ||| under, and what a match takes apart there.
  record Pattern where
    constructor MkPattern
    names : List Name
    parts : Parts

  ||| What a match takes apart at a place: a constructor's arguments (a
  ||| function type is the type constructor `->` of its domain and
  ||| codomain, as the tree names its alternative), or a suspension's type
  ||| and value; nothing at a variable, a constant, or a place the builder
  ||| cannot match (an erased place, a term the unifier computed from the
  ||| others).
  data Parts : Type where
    Whole : Parts
    Arguments : List Pattern -> Parts
    Suspension : Pattern -> Pattern -> Parts

mutual
  ||| A place as the case builder read it.
  patternOf : Pat -> Pattern
  patternOf (PAs _ n p) = { names $= (n ::) } (patternOf p)
  patternOf (PCon _ _ _ _ ps) = MkPattern [] (Arguments (patternsOf ps))
  patternOf (PTyCon _ _ _ ps) = MkPattern [] (Arguments (patternsOf ps))
  patternOf (PConst _ _) = MkPattern [] Whole
  patternOf (PArrow _ _ s t) = MkPattern [] (Arguments [patternOf s, patternOf t])
  patternOf (PDelay _ _ t p) = MkPattern [] (Suspension (patternOf t) (patternOf p))
  patternOf (PLoc _ n) = MkPattern [n] Whole
  patternOf (PUnmatchable _ _) = MkPattern [] Whole

  patternsOf : List Pat -> List Pattern
  patternsOf [] = []
  patternsOf (p :: ps) = patternOf p :: patternsOf ps

||| One step from a place to a part a match binds: argument `j` of a
||| constructor whose alternative binds `k`, or a suspension's type or
||| value.
data Step = Argument Nat Nat | DelayedType | DelayedValue

||| Where a variable of a case tree's scope stands in every clause of its
||| definition: one of the definition's parameters, then the step each
||| match that bound it took, outermost first. A tree's matches bind the
||| same parts for every clause, so a variable's place is the tree's, and
||| each leaf reads it in its own clause.
record Place where
  constructor MkPlace
  parameter : Nat
  steps : SnocList Step

||| A definition's clauses, each its places as the case builder read them,
||| read once with the definition, by the index a leaf of its tree names;
||| and where each variable of a tree's scope stands in them.
export
record Clauses (vars : Scope) where
  constructor MkClauses
  patterns : List (List Pattern)
  places : ByVar vars Place

||| The clauses at the root of a definition's tree, whose scope is its
||| parameters, the first first, each parameter its own place.
export
clauses : (args : Scope) -> List (List Pat) -> Clauses args
clauses args pats = MkClauses (map patternsOf pats) (rooted 0 args)
  where
    rooted : Nat -> (vs : Scope) -> ByVar vs Place
    rooted i [] = []
    rooted i (_ :: vs) = MkPlace i [<] :: rooted (S i) vs

-- Lists of equal successor lengths have tails of equal lengths.
0 tailsAgree : {0 m, n : Nat} -> S m = S n -> m = n
tailsAgree Refl = Refl

||| The clauses inside a match's alternative that binds `args` in front of
||| the scope, argument `j` at the place `part j` makes of the matched
||| variable's.
withArgs : (part : Nat -> Place -> Place) -> (args : List Name) -> Var vars -> Clauses vars ->
           Clauses (Scope.addInner vars args)
withArgs part args (MkVar {varIdx} prf) (MkClauses pats ps) =
  MkClauses pats (bound (lookupVar varIdx prf ps) 0 args ps)
  where
    -- Argument `j` and those after it, of the place `at`.
    bound : Place -> Nat -> (as : List Name) -> ByVar vs Place -> ByVar (Scope.addInner vs as) Place
    bound at j [] rest = rest
    bound at j (_ :: as) rest = part j at :: bound at (S j) as rest

||| The clauses inside a match's alternative of a constructor, whose
||| arguments it binds in front of the scope, each the next argument of
||| the matched variable's place.
afterCon : (args : List Name) -> Var vars -> Clauses vars -> Clauses (Scope.addInner vars args)
afterCon args = let k = length args in withArgs (\j, at => { steps $= (:< Argument j k) } at) args

||| The clauses inside a match on a suspension, which binds its type and
||| its value in front of the scope.
afterDelay : Var vars -> Clauses vars -> Clauses (Scope.addInner vars [ty, arg])
afterDelay (MkVar {varIdx} prf) (MkClauses pats ps) =
  let at = lookupVar varIdx prf ps in
  MkClauses pats ({ steps $= (:< DelayedType) } at :: { steps $= (:< DelayedValue) } at :: ps)

||| The binders a clause names the part at a place by; none where the
||| clause does not take the place apart as the tree did.
namesAt : List Pattern -> Place -> List Name
namesAt pats (MkPlace i steps) = maybe [] (.names) (getAt i pats >>= follow (steps <>> []))
  where
    follow : List Step -> Pattern -> Maybe Pattern
    follow [] p = Just p
    follow (Argument j k :: rest) p = case p.parts of
      Arguments ps => if length ps == k then getAt j ps >>= follow rest else Nothing
      _ => Nothing
    follow (DelayedType :: rest) p = case p.parts of
      Suspension t _ => follow rest t
      _ => Nothing
    follow (DelayedValue :: rest) p = case p.parts of
      Suspension _ v => follow rest v
      _ => Nothing

||| A leaf's environment, read by the leaf's own clause (`clause`, the index
||| the leaf names): Idris's compile-time tree names a binder of a clause by
||| the first place the clause binds it, leftmost first, and that can be an
||| erased place where another holds the same value at run time (in `upTo
||| (Step t p) Here` the erased index `z` is the field `t`, and the leaf
||| names `z`). So an erased variable is read as the outermost variable,
||| the first the matches bound, that holds a value and whose place the
||| clause names by one of the erased one's binders, as Idris's run-time
||| tree reads it. Idris's quantity check gives every binder its right side
||| uses at run time such a place.
heldAt : (clause : Nat) -> Clauses vars -> StandsFor kc OfTree vars a -> StandsFor kc OfTerm vars a
heldAt clause cls env = case getAt clause cls.patterns of
  Just pats => let named = zipByVar (,) env (map (namesAt pats) cls.places) in
               map (asTermEntry . read (reverse (innermostFirst named))) named
  Nothing => map asTermEntry env
  where
    -- A variable of no value: an erased place's.
    erased : VarInfo kc OfTree a -> Bool
    erased (TypeValue _) = True
    erased _ = False
    read : List (VarInfo kc OfTree a, List Name) -> (VarInfo kc OfTree a, List Name) -> VarInfo kc OfTree a
    read outermostFirst (v, ns) =
      if not (erased v) then v
        else maybe v fst (find (\(w, ms) => not (erased w) && any (\b => elem b ms) ns) outermostFirst)

||| What each argument of a constructor alternative binds, in argument
||| order, read with the shape of the matched value's argument there when
||| its shape is known: a parameter is the instance's value, an argument of
||| quantity 0 a compile-time one, and a runtime field (an implementation
||| the constructor holds among them, a choice) what `field` makes of it
||| and its shape.
argsBound : (field : Nat -> Binder -> ClosedTerm -> Maybe ClosedTerm -> VarInfo kc sp a) ->
            (vs : Scope) -> (as : List ArgKind) -> (0 _ : length as = length vs) -> List ClosedTerm -> StandsFor kc sp vs a
argsBound field [] [] _ _ = []
argsBound field (_ :: vs) (arg :: as) same ss =
  let (s, ss') = next ss in
  bound arg s :: argsBound field vs as (tailsAgree same) ss'
  where
    -- The shape of an argument and those of the arguments after it; none
    -- once the shape gives no more.
    next : List ClosedTerm -> (Maybe ClosedTerm, List ClosedTerm)
    next [] = (Nothing, [])
    next (s :: ss) = (Just s, ss)

    bound : ArgKind -> Maybe ClosedTerm -> VarInfo kc sp a
    bound (Param v) _ = TypeValue v
    bound ErasedArg _ = TypeValue (Erased EmptyFC Placeholder)
    bound (Field i b ity) s = field i b ity s
argsBound field [] (_ :: _) Refl _ impossible
argsBound field (_ :: _) [] Refl _ impossible

||| The names a match gives a constructor's runtime fields, one per field
||| of its layout's arguments, each its argument's name in the tree.
fieldNames : (vs : Scope) -> (as : List ArgKind) -> (0 _ : length as = length vs) -> Vect (fieldCount as) Shown
fieldNames [] [] _ = []
fieldNames (_ :: vs) (Param _ :: as) same = fieldNames vs as (tailsAgree same)
fieldNames (_ :: vs) (ErasedArg :: as) same = fieldNames vs as (tailsAgree same)
fieldNames (v :: vs) (Field _ _ _ :: as) same = binderName v :: fieldNames vs as (tailsAgree same)
fieldNames [] (_ :: _) Refl impossible
fieldNames (_ :: _) [] Refl impossible

||| What a runtime variable's binder says of it, beside its Core type
||| (`Terms.coreTyOf`): its Idris type, the shape of its value, and the
||| variable.
idrisTypeOf : VarInfo kc sp a -> Maybe ClosedTerm
idrisTypeOf (Runtime _ t) = idrisOf t
idrisTypeOf (Shaped _ _ t _) = Just t
idrisTypeOf _ = Nothing

shapeOf : VarInfo kc sp a -> Maybe ClosedTerm
shapeOf (Shaped _ _ _ s) = Just s
shapeOf _ = Nothing

variableOf : VarInfo kc sp a -> Maybe a
variableOf (Runtime x _) = Just x
variableOf (Shaped x _ _ _) = Just x
variableOf _ = Nothing

||| A leaf no input reaches: `Unreachable` in a covering definition
||| (Idris proved no input reaches it), a crash otherwise.
missingCase : {0 nv : Nat} -> Ctx kc -> Loc -> IdrisMLIR.Term.Term nv
missingCase ctx loc =
  if ctx.complete then Unreachable loc else Crash loc NoClauseMatched

||| An arm of a match as its tree gives it: none, one no value takes (Idris
||| proved it impossible, or the value's shape rules it out), or one that
||| runs. An arm no value takes is left out of the match.
data Arm t = Absent | Dead | Present t

Functor Arm where
  map f Absent = Absent
  map f Dead = Dead
  map f (Present t) = Present (f t)

||| An arm, or, where the tree gives none, another.
orElse : Arm t -> Arm t -> Arm t
orElse Absent other = other
orElse arm _ = arm

||| What runs where the tree has no arm: nothing in a covering definition,
||| a crash otherwise.
missingArm : {0 nv : Nat} -> Ctx kc -> Loc -> Arm (IdrisMLIR.Term.Term nv)
missingArm ctx loc = if ctx.complete then Dead else Present (Crash loc NoClauseMatched)

||| A match on a value of the family `inst`, by its possible arms: its
||| alternatives and its default when one runs, its alternatives when none
||| does; with no possible arm, the match is unreachable.
armsOf : Loc -> FamilyId -> Fin n -> List (Alt n) -> Arm (IdrisMLIR.Term.Term n) -> IdrisMLIR.Term.Term n
armsOf loc inst i alts (Present d) = Case loc inst i (Defaulted alts d)
armsOf loc inst i (a :: as) _ = Case loc inst i (Exhaustive (a ::: as))
armsOf loc inst i [] _ = Unreachable loc

||| A literal as a match keys it: a fixed-width integer at its type, a
||| character by its code point, a string, or a number held as a big
||| integer (an `Integer` or a natural). A double is no key: no match on
||| one is translated.
data CaseKey = IntKey IntTy Integer | CharKey Integer | StrKey String | BigKey Integer

||| A match's literal alternatives after the first, each keyed as `key`
||| reads it, the first's kind. A constant does not carry the type of the
||| place it is matched at, and the checked module's tree is where the
||| frontend first reads its constants: one whose tree matches constants of
||| two types at one place is refused here, as the compiled module it is.
keysAs : {auto s : Ref TState TS} -> FC -> (owner : String) -> (CaseKey -> Maybe k) -> List (CaseKey, t) ->
         Front (List (k, t))
keysAs fc owner key [] = pure []
keysAs fc owner key ((c, b) :: rest) = case key c of
  Just kv => ((kv, b) ::) <$> keysAs fc owner key rest
  Nothing => reject fc owner CompiledModule "a match whose alternatives are constants of more than one type"

||| The arms of a match on literals of one kind: the first alternative, the
||| others keyed as `key` reads them, and the default when one runs.
keyedArms : {auto s : Ref TState TS} -> FC -> (owner : String) -> (CaseKey -> Maybe k) -> (k, t) ->
            List (CaseKey, t) -> Maybe t -> Front (LitArmsOf k t)
keyedArms fc owner key first rest (Just d) = (\ks => LitDefault (first ::: ks) d) <$> keysAs fc owner key rest
keyedArms fc owner key first rest Nothing = (\ks => LitNoDefault (first ::: ks)) <$> keysAs fc owner key rest

||| A match on literals keyed by the kind of its first alternative's.
litMatch : {auto s : Ref TState TS} -> FC -> (owner : String) -> (CaseKey, t) -> List (CaseKey, t) -> Maybe t ->
           Front (LitMatch t)
litMatch fc owner (IntKey it n, b) rest d = OnInts it <$> keyedArms fc owner intKey (n, b) rest d
  where
    intKey : CaseKey -> Maybe Integer
    intKey (IntKey it' m) = if it' == it then Just m else Nothing
    intKey _ = Nothing
litMatch fc owner (CharKey n, b) rest d = OnChars <$> keyedArms fc owner charKey (n, b) rest d
  where
    charKey : CaseKey -> Maybe Integer
    charKey (CharKey m) = Just m
    charKey _ = Nothing
litMatch fc owner (StrKey str, b) rest d = OnStrings <$> keyedArms fc owner strKey (str, b) rest d
  where
    strKey : CaseKey -> Maybe String
    strKey (StrKey s') = Just s'
    strKey _ = Nothing
litMatch fc owner (BigKey n, b) rest d = OnBigs <$> keyedArms fc owner bigKey (n, b) rest d
  where
    bigKey : CaseKey -> Maybe Integer
    bigKey (BigKey m) = Just m
    bigKey _ = Nothing

||| A match on a natural's possible arms; with no possible arm, the match is
||| unreachable.
natArms : Loc -> Fin n -> Arm (IdrisMLIR.Term.Term n) -> Arm (Shown, IdrisMLIR.Term.Term (Under 1 n)) ->
          IdrisMLIR.Term.Term n
natArms loc x (Present z) (Present (p, s)) = CaseNat loc x (Both z p s)
natArms loc x (Present z) _ = CaseNat loc x (OnlyZero z)
natArms loc x _ (Present (p, s)) = CaseNat loc x (OnlySucc p s)
natArms loc x _ _ = Unreachable loc

||| Does the shape of the matched value, if known, rule out the alternative
||| for this constructor? A value built with another constructor never
||| takes it, and the alternative's code, typed at the other constructor,
||| need not fit the instance.
excludedBy : Maybe ClosedTerm -> Name -> Front Bool
excludedBy shape cn = case maybe Nothing shapeHead shape of
  Just (built, _) => (/=) <$> fullName built <*> fullName cn
  Nothing => pure False

||| The shapes of a constructor's arguments, from the shape of the value.
shapeArgs : Maybe ClosedTerm -> List ClosedTerm
shapeArgs shape = maybe [] snd (maybe Nothing shapeHead shape)

conName : CaseAlt vars -> Maybe Name
conName (ConCase cn _ _ _) = Just cn
conName _ = Nothing

||| Every constructor of the type a match's constructors build.
export
siblings : List (CaseAlt vars) -> Front (List Name)
siblings alts = case mapMaybe conName alts of
  [] => pure []
  (cn :: _) => do
    Just d <- defined cn
      | Nothing => pure []
    let Just tn = built d.type
      | Nothing => pure []
    Just td <- defined tn
      | Nothing => pure []
    case definition td.def of
      TCon _ _ _ _ _ (Just cons) _ => pure cons
      _ => pure []
  where
    built : TT vs -> Maybe Name
    built (Bind _ _ (Pi {}) sc) = built sc
    built tm = case getFnArgs tm of
      (Ref _ (TyCon _) tn, _) => Just tn
      _ => Nothing

||| Does a match name every constructor of the type? Then its default, which
||| Idris's tree keeps for the clauses after a complete split, stands for
||| no value: it is not translated, and the match has none.
export
coversAll : List (CaseAlt vars) -> Front Bool
coversAll alts = do
  named <- SortedSet.fromList <$> traverse fullName (mapMaybe conName alts)
  every <- traverse fullName !(siblings alts)
  pure (not (null every) && all (\c => contains c named) every)

||| Does a match name the constructor the value's shape, if known, says it
||| was built with? Then its default stands for no value the match sees, and
||| its code, which may call for instances no value needs (one a constructor
||| deeper, where a shape keys the instance), is not translated.
builtNamed : Maybe ClosedTerm -> List (CaseAlt vars) -> Front Bool
builtNamed shape alts = case the (Maybe (Name, List ClosedTerm)) (shape >>= shapeHead) of
  Just (cn, _) => do
    named <- traverse fullName (mapMaybe conName alts)
    pure (elem !(fullName cn) named)
  Nothing => pure False

||| What a reading of a match's alternatives takes apart: constructors, or
||| constants.
data AltKind = ConAlts | ConstAlts

||| A place's alternatives as a reading of a kind (`AltKind`) meets them, up
||| to the default that the clauses after the split keep, which ends what a
||| match reads: a constructor's alternative only where constructors are
||| read; a constant's in either reading, where constructors are read one
||| no value takes; never a suspension's, which the match is when it has
||| one (`DelayIn`).
data OfKind : AltKind -> List (CaseAlt vars) -> Type where
  Exhausted : OfKind {vars} k []
  AtDefault : OfKind {vars} k (DefaultCase rhs :: rest)
  OnCon : OfKind {vars} ConAlts rest -> OfKind {vars} ConAlts (ConCase cn tag args rhs :: rest)
  OnConst : OfKind {vars} k rest -> OfKind {vars} k (ConstCase c rhs :: rest)

-- The alternatives after a constructor's, of the same reading.
0 nextCon : OfKind {vars} ConAlts (ConCase cn tag args rhs :: rest) -> OfKind {vars} ConAlts rest
nextCon (OnCon more) = more

-- The alternatives after a constant's, of the same reading.
0 nextConst : OfKind {vars} k (ConstCase c rhs :: rest) -> OfKind {vars} k rest
nextConst (OnConst more) = more

-- Constants alone, read where constructors are.
0 amongCons : OfKind {vars} ConstAlts alts -> OfKind {vars} ConAlts alts
amongCons Exhausted = Exhausted
amongCons AtDefault = AtDefault
amongCons (OnConst more) = OnConst (amongCons more)

||| Where a place's first suspension alternative is, anywhere among them.
data DelayIn : List (CaseAlt vars) -> Type where
  AtDelay : DelayIn {vars} (DelayCase ty arg rhs :: rest)
  AfterCon : DelayIn {vars} rest -> DelayIn {vars} (ConCase cn tag args rhs :: rest)
  AfterConst : DelayIn {vars} rest -> DelayIn {vars} (ConstCase c rhs :: rest)
  AfterDefault : DelayIn {vars} rest -> DelayIn {vars} (DefaultCase rhs :: rest)

0 pastCon : DelayIn {vars} (ConCase cn tag args rhs :: rest) -> DelayIn {vars} rest
pastCon (AfterCon d) = d

0 pastConst : DelayIn {vars} (ConstCase c rhs :: rest) -> DelayIn {vars} rest
pastConst (AfterConst d) = d

0 pastDefault : DelayIn {vars} (DefaultCase rhs :: rest) -> DelayIn {vars} rest
pastDefault (AfterDefault d) = d

||| A runtime value's match by what its alternatives take apart, read once
||| where the frontend reads the match, every place a reading: one with a
||| suspension's alternative anywhere is the force (`DelayIn`); else one
||| with a constructor's anywhere a match on constructors, the first named,
||| read up to the default; else a match on constants.
data Route : List (CaseAlt vars) -> Type where
  OnSuspension : (0 _ : DelayIn {vars} alts) -> Route {vars} alts
  OnConstructors : (cn : Name) -> (0 _ : OfKind {vars} ConAlts alts) -> Route {vars} alts
  OnConstants : (0 _ : OfKind {vars} ConstAlts alts) -> Route {vars} alts

||| How a place's alternatives are read (`Route`).
route : (alts : List (CaseAlt vars)) -> Route alts
route [] = OnConstants Exhausted
route (DelayCase _ _ _ :: _) = OnSuspension AtDelay
route (ConCase cn _ _ _ :: rest) = case route rest of
  OnSuspension d => OnSuspension (AfterCon d)
  OnConstructors _ more => OnConstructors cn (OnCon more)
  OnConstants more => OnConstructors cn (OnCon (amongCons more))
route (ConstCase _ _ :: rest) = case route rest of
  OnSuspension d => OnSuspension (AfterConst d)
  OnConstructors cn more => OnConstructors cn (OnConst more)
  OnConstants more => OnConstants (OnConst more)
route (DefaultCase _ :: rest) = case route rest of
  OnSuspension d => OnSuspension (AfterDefault d)
  OnConstructors cn _ => OnConstructors cn AtDefault
  OnConstants _ => OnConstants AtDefault

||| Where an implementation a compile-time match takes apart stands, with
||| what the match reads of it there: the whole implementation a parameter
||| of the instance is given, at the value its kind holds it fixed at
||| (`FixedDictionary`), which nothing reduces again; or a part earlier
||| matches took out of one, as a term no reduction has reached into, with
||| the constructors they found it inside (`Opened`, the innermost first).
||| Essential: a part is put back into its parameter's implementation where
||| no reduction reaches it (`heldHere`), and the whole has nothing to be
||| put back into.
data Taken = WholeParameter FixedValue | TakenOut ClosedTerm (List1 Opened)

||| The constructors a match found the implementation inside, the
||| innermost first: none around a parameter's whole implementation.
openedOf : Taken -> List Opened
openedOf (WholeParameter _) = []
openedOf (TakenOut _ opened) = forget opened

mutual
  ||| A case tree over its scope's variables, and where they stand in the
  ||| definition's clauses (`Clauses`). Each leaf's term starts a path of its
  ||| own, at the type the definition gives (`Terms.atType`), and reads each
  ||| variable where its clause holds it.
  export
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         Ctx kc -> StandsFor kc OfTree vars (Fin nv) -> Clauses vars -> CaseTree vars -> Front (Term nv)
  tree ctx env cls (STerm clause tm) =
    atType asWritten start (sizeAccessible start) ctx (heldAt (cast clause) cls env) ctx.result tm
  -- Idris proved it cannot be reached. An `Unmatched` leaf of a covering
  -- definition is one too: a definition whose clauses are all impossible
  -- has only that leaf. In a definition with missing cases it is one of
  -- them, and crashes.
  tree ctx env cls (Unmatched msg) = missingCase ctx <$> toLoc ctx.fc
  tree ctx env cls Impossible = Unreachable <$> toLoc ctx.fc
  tree ctx env cls (Case {name} idx p scTy alts) = do
    loc <- toLoc ctx.fc
    case lookupVar idx p env of
      -- Every compile-time variable of a tree's scope is a quantity-0
      -- binder's (a proof, an index, a type, a form, a constructor's
      -- parameter), whatever the instance knows of its value, and Idris's
      -- erasure check lets the compile-time tree match one only where its
      -- type forces the alternative; its fields are erased too.
      TypeValue _ => forced alts
      -- A match on an implementation selects its alternative now: a
      -- parameter's whole, or a part an earlier match took out of one.
      Static d hole given => staticCase ctx env cls scrutinee hole given (WholeParameter d.reducesTo) alts
      OpenedPart t hole given opened => staticCase ctx env cls scrutinee hole given (TakenOut t opened) alts
      v@(Runtime i t) => case coreOf t of
        Just WorldT => world alts
        _ => runtime loc v i
      v@(Shaped i _ _ _) => runtime loc v i
    where
      scrutinee : Var vars
      scrutinee = MkVar p

      -- The world has one value, which the alternative that names it takes,
      -- or else the default: what the match is, chosen now. With neither,
      -- no alternative takes the value: the missing case.
      world : List (CaseAlt vars) -> Front (Term nv)
      world (ConstCase WorldVal rhs :: _) = tree ctx env cls rhs
      world (DefaultCase rhs :: _) = tree ctx env cls rhs
      world (_ :: rest) = world rest
      world [] = missingCase ctx <$> toLoc ctx.fc

      -- A literal match Idris proved complete has no default: its last
      -- alternative stands in for one (LitNoDefault), and with no
      -- alternative at all no value reaches it. An incomplete one's
      -- default is the missing case's crash.
      literals : Loc -> Fin nv -> (lits : List (CaseAlt vars)) -> (0 _ : OfKind ConstAlts lits) -> Front (Term nv)
      literals loc i lits consts = do
        (litAlts, def) <- litAlternatives ctx env cls scrutinee lits consts
        let d = def <|> (if ctx.complete then Nothing else Just (missingCase ctx loc))
        case litAlts of
          a :: as => CaseLit loc i <$> litMatch ctx.fc ctx.owner a as d
          [] => pure (maybe (Unreachable loc) (CaseLit loc i . OnlyDefault) d)

      -- The Idris type of the value matched: its binder's, or, where its
      -- binder gives none (a suspension's value, a value a settled term
      -- computes), the type Idris's tree gives the value it matches, which
      -- every match carries.
      valueType : VarInfo kc OfTree (Fin nv) -> Front ClosedTerm
      valueType v = maybe (normaliseClosed (closeWritten ctx.fc env scTy)) pure (idrisTypeOf v)

      -- The data instance a match's constructors are of, at the value's
      -- type. The Core type names it when it is a declaration the
      -- constructor belongs to; a value of a type with one runtime field
      -- has its field's type, so the Idris type names it then: the
      -- value's own, or, where its binder gives none (a suspension's
      -- value, a value a settled term computes), the type Idris's tree
      -- gives the value it matches, which every match carries.
      instanceOf : VarInfo kc OfTree (Fin nv) -> Defined -> Front DataFamily
      instanceOf v con = do
        st <- getState
        let cn = fullname con.def
        -- The Core type may name a choice, or the family of the one field
        -- a value of a type with one runtime field has, neither of which
        -- has this constructor: the Idris type names its family then.
        let fromCore = case coreTyOf v of
                         Just (DataT d _) => lookupFact (.dataFamilies) d st >>= \df => df <$ constructorIn df con
                         _ => Nothing
        case fromCore of
          Just df => pure df
          Nothing => do
            ity' <- normaliseClosed (maybe (closeWritten ctx.fc env scTy) id (idrisTypeOf v))
            -- A constructor's type that names no family is one the
            -- registry gives a representation of its own: a value array,
            -- abstract, which only the functions the registry knows open,
            -- their bodies not translated; an ordered array or a machine
            -- word likewise.
            Just (df, _) <- dataOf ctx.fc ctx.owner ity'
              | Nothing => do
                  Just _ <- arrayView ity'
                    | Nothing => reject ctx.fc ctx.owner HookShape
                                   ("the type of " ++ show cn ++ " has the representation the registry gives it: " ++
                                    "its constructor is matched")
                  reject ctx.fc ctx.owner HookShape
                         ("the array type of " ++ show cn ++ " is opaque: its constructor is matched")
            pure df

      -- A match on a runtime value's constructors, the first `cn`.
      constructors : Loc -> VarInfo kc OfTree (Fin nv) -> Fin nv -> (cn : Name) -> (as : List (CaseAlt vars)) ->
                     (0 _ : OfKind ConAlts as) -> Front (Term nv)
      constructors loc v i cn as cons = do
        con <- lookupDef ctx.fc ctx.owner cn
        let shape = shapeOf v
        case (natRole con.def, coreTyOf v) of
          -- A value of Idris's `Nat` is a natural: a match on its
          -- constructors is a match on zero. A family of the same shape
          -- (`Fin`, `Elem`) is a family like any other, laid out as a
          -- number by the dialect.
          (Just _, Just (NatT _)) => do
            ity <- valueType v
            natCase ctx env cls scrutinee shape loc i ity as cons
          _ => do
            df <- instanceOf v con
            every <- coversAll as
            built <- builtNamed shape as
            (named, conAlts, fallback) <- conAlternatives ctx env cls scrutinee shape every built df as cons
            -- The constructors a tree with no default leaves out are one
            -- default: impossible when the definition is covering, a
            -- crash otherwise.
            let crashing = case (fallback, ctx.complete) of
                             (Absent, False) => if all (\l => contains l.con.tag named) df.layouts
                                                  then Absent else Present (missingCase ctx loc)
                             _ => fallback
            pure (armsOf loc df.id i conAlts crashing)

      -- A match on a runtime value, by what its alternatives match
      -- (`route`): a suspension's form, constructors (a natural's, one
      -- runtime field's, a declaration's), or literals. A suspension has
      -- one form, `Delay x`, so its match chooses nothing: it is the
      -- force, whose value `x` binds, then the alternative's tree, whose
      -- first variable is the value's type, erased.
      runtime : Loc -> VarInfo kc OfTree (Fin nv) -> Fin nv -> Front (Term nv)
      runtime loc v i = routed alts (route alts)
        where
          -- The value a suspension holds: of the Idris type its `Lazy` type
          -- holds, and of the Core type its suspension's holds, which its
          -- binder states, or else that Idris type's, every extent dynamic
          -- as a suspension's value has it. Idris's tree matches a
          -- suspension's form on a value of a suspension's type only: one
          -- of another is refused, as the compiled module it is.
          forcedTypes : Front (Ty, ClosedTerm)
          forcedTypes = do
            TDelayed _ _ ity <- valueType v
              | _ => reject ctx.fc ctx.owner CompiledModule "a match on a suspension's form of a value of no suspension type"
            t <- case coreTyOf v of
                   Just (LazyT t) => pure t
                   _ => dynamicDims <$> coreType ctx.fc ctx.owner ValueType ity
            pure (t, ity)

          -- The first alternative that matches a suspension.
          firstDelay : (as : List (CaseAlt vars)) -> (0 _ : DelayIn as) -> Front (Term nv)
          firstDelay (DelayCase ty arg rhs :: _) _ = do
            (t, ity) <- forcedTypes
            body <- tree ctx (under {k = 1} {new = [ty, arg]} [TypeValue (Erased ctx.fc Placeholder), Runtime FZ (BothTypes t ity)] env)
                         (afterDelay scrutinee cls) rhs
            pure (Let loc (binderName arg) (OfValue Many) (Resume loc t (Var loc i)) body)
          firstDelay (ConCase _ _ _ _ :: rest) d = firstDelay rest (pastCon d)
          firstDelay (ConstCase _ _ :: rest) d = firstDelay rest (pastConst d)
          firstDelay (DefaultCase _ :: rest) d = firstDelay rest (pastDefault d)
          firstDelay [] _ impossible

          routed : (as : List (CaseAlt vars)) -> Route as -> Front (Term nv)
          routed as (OnSuspension d) = firstDelay as d
          routed as (OnConstructors cn cons) = constructors loc v i cn as cons
          routed as (OnConstants consts) = literals loc i as consts

      -- The alternative of a match on an erased proof of an equality
      -- (`Refl`: `replace` and `rewrite` are such matches) holds where the
      -- proof's two sides are equal, on Idris's word alone: its body is the
      -- region that assumes it. A side outside the language refines
      -- nothing, and neither does a region assuming it.
      assumed : Term nv -> Front (Term nv)
      assumed body = do
        ty <- normaliseClosed (closeWritten ctx.fc env scTy)
        let (Ref _ (TyCon _) tn, [_, _, l, r]) = getFnArgs ty
          | _ => pure body
        Just tc <- defined tn
          | Nothing => pure body
        let Just IsEquality = (namedHooks tc.registered).sumShape
          | _ => pure body
        case (!(indexTerm l), !(indexTerm r)) of
          (IOpaque, _) => pure body
          (_, IOpaque) => pure body
          (lhs, rhs) => do
            loc <- toLoc ctx.fc
            pure (Assume loc lhs rhs body)

      forced : List (CaseAlt vars) -> Front (Term nv)
      forced [ConCase cn _ args rhs] = do
        body <- tree ctx (prepend (everyVar args (TypeValue (Erased ctx.fc Placeholder))) env)
                     (afterCon args scrutinee cls) rhs
        assumed body
      forced [DefaultCase rhs] = tree ctx env cls rhs
      forced _ = do
        cons <- traverse altName alts
        reject ctx.fc ctx.owner Match
               ("a match on `" ++ show name ++ "`, which is erased (quantity 0, or an index or proof " ++
                "with no runtime value), between " ++ joinBy ", " cons ++ ": only a runtime value can " ++
                "choose an alternative; match on the runtime value that determines it instead")
        where
          altName : CaseAlt vars -> Front String
          altName (ConCase cn _ _ _) = show <$> fullName cn
          altName (ConstCase c _) = pure (show c)
          altName (DelayCase {}) = pure "Delay"
          altName (DefaultCase _) = pure "the default"

  ||| A match on a `Nat`-like value: zero, or a successor binding the
  ||| predecessor. The default stands for whichever the tree leaves out.
  natCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            Ctx kc -> StandsFor kc OfTree vars (Fin nv) -> Clauses vars -> Var vars ->
            Maybe ClosedTerm -> Loc -> Fin nv -> ClosedTerm ->
            (alts : List (CaseAlt vars)) -> (0 _ : OfKind ConAlts alts) -> Front (Term nv)
  natCase ctx env cls scrutinee shape loc x ity alts cons = do
    every <- coversAll alts
    built <- builtNamed shape alts
    (z, s, d) <- natAlternatives ctx env cls scrutinee shape ity (every || built) loc x alts cons
    -- Where the tree has no arm for zero or a successor, the default runs,
    -- or, with none, what runs where the tree has no arm.
    let otherwise = orElse d (missingArm ctx loc)
    pure $ case (z, s) of
      (Absent, Absent) => case otherwise of
        Present t => t
        _ => Unreachable loc
      _ => natArms loc x (orElse z otherwise) (orElse s (map (\t => (shown "_", weakenUnder 1 t)) otherwise))

  ||| The alternatives of a match on a `Nat`-like value: zero's, the
  ||| successor's (over the predecessor, named, its erased arguments
  ||| compile-time values), and the default, unless no value takes it
  ||| (`deadDefault`). The value's shape, if known, rules one of the two out,
  ||| and gives the predecessor its own; the predecessor is of the value's
  ||| type (`ity`).
  natAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx kc -> StandsFor kc OfTree vars (Fin nv) -> Clauses vars -> Var vars ->
                    Maybe ClosedTerm -> ClosedTerm -> Bool -> Loc -> Fin nv ->
                    (alts : List (CaseAlt vars)) -> (0 _ : OfKind ConAlts alts) ->
                    Front (Arm (Term nv), Arm (Shown, Term (Under 1 nv)), Arm (Term nv))
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x [] _ = pure (Absent, Absent, Absent)
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x (ConCase cn _ args rhs :: rest) cons = do
    con <- lookupDef ctx.fc ctx.owner cn
    let taken = con.taken
    dead <- excludedBy shape (fullname con.def)
    let cls' = afterCon args scrutinee cls
    case natRole con.def of
      Just Zero => do
        z <- if dead then pure Dead
             else Present <$> tree ctx (prepend (everyVar args (TypeValue (Erased ctx.fc Placeholder))) env) cls' rhs
        (_, s, d) <- natAlternatives ctx env cls scrutinee shape ity deadDefault loc x rest (nextCon cons)
        pure (z, s, d)
      Just Succ => do
        -- The constructor's type shows a binder for each argument its
        -- alternative binds, which Idris's tree takes from it, in the
        -- module the compiler reads when it runs.
        let Yes counted = decEq (length taken) (length args)
          | No _ => reject ctx.fc ctx.owner CompiledModule
                           ("the successor " ++ show cn ++ " binds another number of arguments than it takes")
        let predInfo : VarInfo kc OfTree (Fin (Under 1 nv))
            predInfo = case predecessor (shapeArgs shape) taken of
                         Just p => shaped FZ (NatT IOpaque) ity p
                         Nothing => Runtime FZ (BothTypes (NatT IOpaque) ity)
        let infos = byVarFrom args (\a => case a of
                                         RuntimeValue _ => predInfo
                                         _ => TypeValue (Erased ctx.fc Placeholder)) taken counted
        let pred = maybe (shown "_") (binderName . fst) (find (isValue . snd) (zip args taken))
        body <- if dead then pure Dead
                else (\b => Present (pred, b)) <$> tree ctx (under {k = 1} infos env) cls' rhs
        (z, _, d) <- natAlternatives ctx env cls scrutinee shape ity deadDefault loc x rest (nextCon cons)
        pure (z, body, d)
      -- A constructor no natural is built with: no value takes its
      -- alternative.
      Nothing => natAlternatives ctx env cls scrutinee shape ity deadDefault loc x rest (nextCon cons)
    where
      -- Does a constructor take a value at the argument?
      isValue : ArgumentAt -> Bool
      isValue (RuntimeValue _) = True
      isValue _ = False

      -- The successor's one runtime argument, among the shape's.
      predecessor : List ClosedTerm -> List ArgumentAt -> Maybe ClosedTerm
      predecessor (a :: as) (RuntimeValue _ :: _) = Just a
      predecessor (a :: as) (_ :: ps) = predecessor as ps
      predecessor _ _ = Nothing
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x (DefaultCase rhs :: _) _ =
    pure (Absent, Absent, !(if deadDefault then pure Dead else Present <$> tree ctx env cls rhs))
  -- A constant: no natural, a constructor's value, takes its alternative.
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x (ConstCase _ _ :: rest) cons =
    natAlternatives ctx env cls scrutinee shape ity deadDefault loc x rest (nextConst cons)
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x (DelayCase {} :: _) _ impossible

  ||| A match on a compile-time value: the implementation at its
  ||| constructor, and the alternative's variables stand for its arguments,
  ||| each a part taken out of it (`Taken`). An argument that mentions the
  ||| runtime value the implementation closes over closes over it too, and
  ||| every argument is of the parameter the implementation is (`given`). A
  ||| part no compile-time reduction reaches is computed where the match
  ||| reaches it (`heldHere`).
  staticCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
               Ctx kc -> StandsFor kc OfTree vars (Fin nv) -> Clauses vars -> Var vars ->
               Maybe (Fin nv, Holes) -> (given : GivenParameter kc (Fin nv)) -> Taken ->
               List (CaseAlt vars) -> Front (Term nv)
  staticCase ctx env cls scrutinee hole given taken alts = case taken of
    -- A parameter's whole implementation is one the program fixes now:
    -- its kind holds the value it reduces to (`FixedDictionary`), read
    -- where it was classified, registered as a member, or built beside a
    -- form built around one, so it is taken apart as it is.
    WholeParameter (FixedConstructor cn cargs) => built cn cargs
    -- Essential: the checked tree matches only a value of a data type,
    -- and a function value is none, though a parameter of a function type
    -- is fixed at one. A tree that matches one is the compiled module's,
    -- refused where the frontend first reads the match.
    WholeParameter (FixedFunction v) => do
      written <- showTT v
      reject ctx.fc ctx.owner CompiledModule ("a match on an implementation that is a function value: " ++ written)
    -- A part is reduced here first. A field of a fixed implementation that
    -- the running program chooses is a value the parameter holds, and an
    -- instance given one is split by the members of its choice
    -- (`Choices.heldDispatch`), so its tree takes apart the member. What
    -- reaches here stuck is a part of a fixed implementation that no
    -- compile-time reduction reaches: one a definition Idris does not prove
    -- ends computes, or one computed from the values the implementation
    -- closes over.
    TakenOut t opened => do
      Built cn cargs <- whnf t
        | Stuck on => heldHere t opened on
      built cn cargs
    where
      -- What a constructor's argument stands for: a runtime value of it, a
      -- part taken out of the implementation, with the constructor it was
      -- found built with (`o`) inside those the matches before found.
      info : Opened -> ArgumentAt -> ClosedTerm -> VarInfo kc OfTree (Fin nv)
      info o (RuntimeValue _) v = OpenedPart v (if mentionsHole v then hole else Nothing) given (o ::: openedOf taken)
      info _ _ v = TypeValue v

      -- Each argument of the constructor `cn`, applied to `cargs`, as many
      -- as its type shows binders and the reduction gave arguments, the
      -- next at position `j`: what its variable stands for, and its type,
      -- its binder's closed over the arguments before it.
      typedParts : Name -> List ClosedTerm -> (j : Nat) -> Given ws -> Binders ArgumentAt ws -> List ClosedTerm ->
                   List (VarInfo kc OfTree (Fin nv), ClosedTerm)
      typedParts cn cargs j g (ShowsBinder at ty rest) (v :: vs) =
        let partType = close g ty in
        (info (MkOpened cn cargs j partType) at v, partType) :: typedParts cn cargs (S j) (give v g) rest vs
      typedParts _ _ _ _ _ _ = []

      -- The alternative of the constructor `cn` the implementation was
      -- found built with, applied to `cargs`, whose parts each place it
      -- binds stands for (`typed`); else the default. With neither, no
      -- alternative takes the value: the missing case, as any match's.
      pick : Name -> List ClosedTerm -> List (VarInfo kc OfTree (Fin nv), ClosedTerm) -> List (CaseAlt vars) -> Front (Term nv)
      pick cn cargs typed (ConCase con _ args rhs :: rest) = do
        full <- fullName con
        if full /= cn then pick cn cargs typed rest else do
          let Yes same = decEq (length typed) (length args)
            | No _ => reject ctx.fc ctx.owner CompiledModule ("constructor " ++ show cn ++ " binds an unexpected number of arguments")
          tree ctx (prepend (byVarFrom args fst typed same) env) (afterCon args scrutinee cls) rhs
      pick cn cargs typed (DefaultCase rhs :: _) = tree ctx env cls rhs
      pick cn cargs typed (_ :: rest) = pick cn cargs typed rest
      pick cn cargs typed [] = missingCase ctx <$> toLoc ctx.fc

      -- An implementation built with its constructor applied, an argument
      -- replaced, and the value it is at its head, which is that
      -- constructor applied, by construction.
      rebuilt : Name -> Nat -> ClosedTerm -> List ClosedTerm -> Front (ClosedTerm, FixedValue)
      rebuilt cn j v args = do
        f <- refTo EmptyFC cn
        let args' = replaceAt j v args
        pure (foldl (App EmptyFC) f args', FixedConstructor cn args')
        where
          replaceAt : Nat -> a -> List a -> List a
          replaceAt Z x (_ :: ys) = x :: ys
          replaceAt (S i) x (y :: ys) = y :: replaceAt i x ys
          replaceAt _ _ [] = []

      -- A parameter's implementation with the part a match took out of it
      -- a value it holds, marker `m`: rebuilt around the part from the
      -- constructors the compile-time matches on the way found, the
      -- innermost first (the one the part is an argument of, then those
      -- outer to it), with nothing reduced again; the value it is at its
      -- head, its outermost constructor applied; and the part's type.
      holding : (m : Nat) -> List1 Opened -> Front (ClosedTerm, FixedValue, ClosedTerm)
      holding m (inner ::: outer) = do
        ty <- normaliseClosed inner.partType
        (form, value) <- around !(rebuilt inner.con inner.at (holeMarker m) inner.args) outer
        pure (form, value, ty)
        where
          around : (ClosedTerm, FixedValue) -> List Opened -> Front (ClosedTerm, FixedValue)
          around done [] = pure done
          around (part, _) (f :: fs) = rebuilt f.con f.at part f.args >>= \b => around b fs

      -- The variable that holds the value of parameter `i` at run time, as
      -- the tree's scope binds it: the parameter itself, at its own place,
      -- which every scope of the tree keeps outermost; none for a
      -- parameter that binds nothing at run time.
      parameterValue : Nat -> Maybe (Fin nv)
      parameterValue i = go (innermostFirst (zipByVar (,) cls.places env))
        where
          valueOf : VarInfo kc OfTree (Fin nv) -> Maybe (Fin nv)
          valueOf (Static _ (Just (x, _)) _) = Just x
          valueOf v = variableOf v

          go : List (Place, VarInfo kc OfTree (Fin nv)) -> Maybe (Fin nv)
          go [] = Nothing
          go ((MkPlace j [<], v) :: rest) = if i == j then valueOf v else go rest
          go (_ :: rest) = go rest

      -- An instance's runtime arguments, one per parameter of its kinds
      -- that exists at run time, in order, each this instance's parameter
      -- at that position but at parameter `p`, which is `here`; `ren`
      -- takes the scope's variables into the one they are read in.
      passedOn : {0 q : Nat} -> Loc -> (Fin nv -> Fin q) -> (p : Nat) -> Term q -> (ks : List PKind) ->
                 Front (Vect (Runtimes ks) (Term q))
      passedOn loc ren p here = eachRuntime value
        where
          value : Nat -> PKind -> Front (Term q)
          value i _ =
            -- The instance called takes the signature it was first
            -- requested with, classified apart from this instance's, so
            -- the types do not say that a parameter it takes at run time
            -- is one this instance binds at run time too.
            if i == p then pure here else case parameterValue i of
              Just x => pure (Var loc (ren x))
              Nothing => internal ctx.fc ("parameter " ++ show i ++ " binds nothing at run time here")

      -- A field no compile-time reduction reaches is computed here, where
      -- the tree reaches it, eagerly, its divergence its computation's:
      -- the rest is the instance's definition again, at the
      -- implementation with that field a value it holds, its last
      -- (`holding`), so that instance is a dispatch on the field's choice
      -- (`Choices.heldDispatch`), each of whose arms takes apart a member
      -- the program fixes. What the tree matched before this match only
      -- tested values, which that instance tests again. A field that is no
      -- implementation is never taken apart, and is refused as it is. The
      -- parameter the implementation is of, its position among the
      -- instance's and the values it holds, is the entry's (`given`), and
      -- so are the constructors the matches on the way found (`opened`).
      -- The implementation rebuilt is fixed by construction, at its
      -- outermost constructor (`holding`), so nothing reduces it.
      heldHere : ClosedTerm -> List1 Opened -> StuckOn -> Front (Term nv)
      heldHere t opened on = do
        let r = ctx.request
        let own = replace {p = \n => Vect n PKind} ctx.counts (Data.Vect.fromList ctx.request.signature.kinds)
        let position = given.position
        let parameter = finToNat position
        let held = map snd given.holding
        let count = maybe 0 (length . forget . (.types)) held
        (form', value', fieldType) <- holding count opened
        Just _ <- choiceType fieldType
          | Nothing => reject ctx.fc ctx.owner RuntimeClosure
                            ("an implementation's field no compile-time reduction reaches, matched where the " ++
                             "implementation was taken apart: " ++ !(showTT t) ++ ", stuck on " ++ !(stuckText on))
        let types = maybe (fieldType ::: []) (\hs => appendl hs.types [fieldType]) held
        packed <- coreType ctx.fc ctx.owner ValueType !(normaliseClosed !(packedType types))
        fixed <- builtDictionary form' value'
        let kinds = replaceAt position (DictParam fixed (Just (MkHoles types (MkBinder Many packed)))) own
        sig <- request ctx.fc ctx.owner ctx.request.instantiates
                       (replace {p = \n => Vect n PKind} (trans (sym ctx.counts) ctx.request.classifiesAll) kinds)
        loc <- toLoc ctx.fc
        value <- computedAt ctx ctx.fc t hole
        let levels = ownLevels (length (telescopeOf r.signature.kinds))
        body <- case given.holding of
          Nothing => Call loc sig.callee Nothing levels <$> passedOn loc FS parameter (Var loc FZ) sig.kinds
          Just (x, hs) =>
            takenApart ctx.fc ctx.owner loc hs.types (FS x) $ \ren, vs => do
              values <- pack ctx.fc ctx.owner loc
                          (ending (zip (forget hs.types) (map (Var loc) (toList vs))) (fieldType, Var loc (ren FZ)))
              Call loc sig.callee Nothing levels <$> passedOn loc (ren . FS) parameter values sig.kinds
        pure (Let loc (shown "field") (OfValue Many) value body)
        where
          -- The values held, the field last.
          ending : List a -> a -> List1 a
          ending [] x = x ::: []
          ending (y :: ys) x = y ::: (ys ++ [x])

      -- The alternative of the constructor the implementation is at,
      -- applied to `cargs` (`pick`).
      built : Name -> List ClosedTerm -> Front (Term nv)
      built cn cargs = do
        full <- fullName cn
        con <- lookupDef ctx.fc ctx.owner full
        pick full cargs (typedParts full cargs 0 none con.binders cargs) alts

  ||| The constructors a match's alternatives name, its possible
  ||| alternatives, each over its fields, named as the alternative names
  ||| them, and the default: none when the alternatives name every
  ||| constructor (`every`), one no value takes when they name the one the
  ||| value's shape says it was built with (`built`). The shape, if known,
  ||| rules out every other constructor and gives the fields their shapes;
  ||| an alternative it rules out, or of a constructor with no value yet,
  ||| is no possible one.
  conAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx kc -> StandsFor kc OfTree vars (Fin nv) -> Clauses vars -> Var vars ->
                    Maybe ClosedTerm -> Bool -> Bool -> DataFamily ->
                    (alts : List (CaseAlt vars)) -> (0 _ : OfKind ConAlts alts) ->
                    Front (SortedSet Nat, List (Alt nv), Arm (Term nv))
  conAlternatives ctx env cls scrutinee shape every built df [] _ = pure (empty, [], Absent)
  conAlternatives ctx env cls scrutinee shape every built df (ConCase cn _ args rhs :: rest) cons = do
    found <- lookupDef ctx.fc ctx.owner cn
    let def = found.def
    -- Its tag is its place among its type's constructors, where the family
    -- holds its layout: Idris's numbering. The checked module's tree is
    -- where the frontend first reads the constructor a match names, so one
    -- its type does not list is refused here, as the compiled module it is.
    let Just (cid, info) = constructorIn df found
      | Nothing => reject ctx.fc ctx.owner CompiledModule
                          ("a match names " ++ show (fullname def) ++ ", which its type does not list as a constructor")
    let Yes bound = decEq (length info.args) (length args)
      | No _ => reject ctx.fc ctx.owner CompiledModule
                       ("constructor " ++ show (fullname def) ++ " binds an unexpected number of arguments")
    dead <- excludedBy shape (fullname def)
    -- Each field is of its type in scope (`fieldsAt`), the constructor's
    -- binders at the levels its region binds them at, as `Emit` reads it,
    -- and the region's terms stand that many levels deeper.
    let infos = argsBound (fieldAt (fieldsAt ctx.depth info.con)) args info.args bound (shapeArgs shape)
    alt <- if dead then pure Nothing else do
      -- The alternative binds the constructor's fields, as many as the
      -- layout's arguments hold, each named as the tree names its argument.
      body <- tree ({ depth $= (+ length info.con.binders) } ctx) (under {k = fieldCount info.args} infos env)
                   (afterCon args scrutinee cls) rhs
      pure (Just (MkAlt info.con (fieldNames args info.args bound) body))
    (others, alts, fallback) <- conAlternatives ctx env cls scrutinee shape every built df rest (nextCon cons)
    pure (insert (finToNat cid.index) others, maybe alts (:: alts) alt, fallback)
    where
      -- Runtime field `i` is the alternative's `Bound i`, of its type in
      -- scope, with what the value's shape says of it.
      fieldAt : {k : Nat} -> Vect k Binder -> Nat -> Binder -> ClosedTerm -> Maybe ClosedTerm -> VarInfo kc OfTree (Fin (Under k nv))
      fieldAt {k} inScope i _ ity s = case natToFin i k of
        Just f => let t = (index f inScope).type in case s of
          Just s' => shaped (Bound {n = nv} f) t ity s'
          Nothing => Runtime (Bound {n = nv} f) (BothTypes t ity)
        Nothing => TypeValue (Erased EmptyFC Placeholder)
  conAlternatives ctx env cls scrutinee shape every built df (DefaultCase rhs :: _) _ =
    if every then pure (empty, [], Absent)
      else if built then pure (empty, [], Dead)
      else (\d => (empty, [], Present d)) <$> tree ctx env cls rhs
  -- A constant: no constructor's value takes its alternative.
  conAlternatives ctx env cls scrutinee shape every built df (ConstCase _ _ :: rest) cons =
    conAlternatives ctx env cls scrutinee shape every built df rest (nextConst cons)
  conAlternatives ctx env cls scrutinee shape every built df (DelayCase {} :: _) _ impossible

  ||| The alternatives of a match on literals, each keyed by its constant,
  ||| and the default when one runs.
  litAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx kc -> StandsFor kc OfTree vars (Fin nv) -> Clauses vars -> Var vars ->
                    (alts : List (CaseAlt vars)) -> (0 _ : OfKind ConstAlts alts) ->
                    Front (List (CaseKey, Term nv), Maybe (Term nv))
  litAlternatives ctx env cls scrutinee [] _ = pure ([], Nothing)
  litAlternatives ctx env cls scrutinee (ConstCase c rhs :: rest) consts = do
    Just lit <- pure (constantLit c)
      | Nothing => reject ctx.fc ctx.owner StringPrimitive ("a match on " ++ show c)
    key <- the (Front CaseKey) $ case lit of
      LInt t n => pure (IntKey t n)
      LChar n => pure (CharKey n)
      LStr str => pure (StrKey str)
      LBig n => pure (BigKey n)
      LNat n => pure (BigKey n)
      LDouble _ => reject ctx.fc ctx.owner Primitive "a match on a Double literal"
    body <- tree ctx env cls rhs
    (alts, def) <- litAlternatives ctx env cls scrutinee rest (nextConst consts)
    pure ((key, body) :: alts, def)
  litAlternatives ctx env cls scrutinee (DefaultCase rhs :: _) _ =
    pure ([], Just !(tree ctx env cls rhs))
  litAlternatives ctx env cls scrutinee (ConCase {} :: _) _ impossible
  litAlternatives ctx env cls scrutinee (DelayCase {} :: _) _ impossible
