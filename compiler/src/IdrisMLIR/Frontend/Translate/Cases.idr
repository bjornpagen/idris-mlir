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

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Terms
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
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

||| One place per variable of a scope, the innermost first.
data Places : Scope -> Type where
  NoPlaces : Places []
  Placed : Place -> Places vars -> Places (v :: vars)

||| The place of the variable at a position of the scope.
placeAt : (idx : Nat) -> (0 _ : IsVar n idx vars) -> Places vars -> Place
placeAt Z _ (Placed p _) = p
placeAt (S i) prf (Placed _ ps) = placeAt i (dropLater prf) ps
placeAt _ First NoPlaces impossible
placeAt _ (Later _) NoPlaces impossible

||| The places in scope order, the innermost first, as an environment
||| lists its variables.
placesOf : Places vars -> List Place
placesOf NoPlaces = []
placesOf (Placed p ps) = p :: placesOf ps

||| A definition's clauses, each its places as the case builder read them,
||| read once with the definition, by the index a leaf of its tree names;
||| and where each variable of a tree's scope stands in them.
export
record Clauses (vars : Scope) where
  constructor MkClauses
  patterns : List (List Pattern)
  places : Places vars

||| The clauses at the root of a definition's tree, whose scope is its
||| parameters, the first first, each parameter its own place.
export
clauses : (args : Scope) -> List (List Pat) -> Clauses args
clauses args pats = MkClauses (map patternsOf pats) (rooted 0 args)
  where
    rooted : Nat -> (vs : Scope) -> Places vs
    rooted i [] = NoPlaces
    rooted i (_ :: vs) = Placed (MkPlace i [<]) (rooted (S i) vs)

||| The clauses inside a match's alternative of a constructor, whose
||| arguments it binds in front of the scope, each the next argument of
||| the matched variable's place.
afterCon : (args : List Name) -> Var vars -> Clauses vars -> Clauses (Scope.addInner vars args)
afterCon args (MkVar {varIdx} prf) (MkClauses pats ps) =
  MkClauses pats (bound (placeAt varIdx prf ps) (length args) 0 args ps)
  where
    -- Argument `j` and those after it of `k`, of the place `at`.
    bound : Place -> (k : Nat) -> Nat -> (as : List Name) -> Places vs -> Places (Scope.addInner vs as)
    bound at k j [] rest = rest
    bound at k j (_ :: as) rest = Placed ({ steps $= (:< Argument j k) } at) (bound at k (S j) as rest)

||| The clauses inside a match on a suspension, which binds its type and
||| its value in front of the scope.
afterDelay : Var vars -> Clauses vars -> Clauses (Scope.addInner vars [ty, arg])
afterDelay (MkVar {varIdx} prf) (MkClauses pats ps) =
  let at = placeAt varIdx prf ps in
  MkClauses pats (Placed ({ steps $= (:< DelayedType) } at) (Placed ({ steps $= (:< DelayedValue) } at) ps))

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
heldAt : (clause : Nat) -> Clauses vars -> List (VarInfo a) -> List (VarInfo a)
heldAt clause cls env = case getAt clause cls.patterns of
  Just pats => let named = zip env (map (namesAt pats) (placesOf cls.places)) in
               map (read (reverse named)) named
  Nothing => env
  where
    -- A variable of no value: an erased place's.
    erased : VarInfo a -> Bool
    erased (TypeValue _) = True
    erased _ = False
    read : List (VarInfo a, List Name) -> (VarInfo a, List Name) -> VarInfo a
    read outermostFirst (v, ns) =
      if not (erased v) then v
        else maybe v fst (find (\(w, ms) => not (erased w) && any (\b => elem b ms) ns) outermostFirst)

||| What each argument of a constructor alternative binds, in argument
||| order, read with the shape of the matched value's argument there when
||| its shape is known: a parameter is the instance's value, an argument of
||| quantity 0 a compile-time one, and a runtime field (an implementation
||| the constructor holds among them, a choice) what `field` makes of it
||| and its shape.
argsBound : (field : Nat -> Binder -> ClosedTerm -> Maybe ClosedTerm -> VarInfo a) ->
            List ArgKind -> List ClosedTerm -> List (VarInfo a)
argsBound field [] _ = []
argsBound field (a :: as) ss =
  let (s, ss') = next ss in
  bound a s :: argsBound field as ss'
  where
    -- The shape of an argument and those of the arguments after it; none
    -- once the shape gives no more.
    next : List ClosedTerm -> (Maybe ClosedTerm, List ClosedTerm)
    next [] = (Nothing, [])
    next (s :: ss) = (Just s, ss)

    bound : ArgKind -> Maybe ClosedTerm -> VarInfo a
    bound (Param v) _ = TypeValue v
    bound ErasedArg _ = TypeValue (Erased EmptyFC Placeholder)
    bound (Field i b ity) s = field i b ity s

||| What a runtime variable's binder says of it: its Core type, its Idris
||| type, the shape of its value, and the variable.
coreTyOf : VarInfo a -> Maybe Ty
coreTyOf (Runtime _ t _) = t
coreTyOf (Shaped _ t _ _) = Just t
coreTyOf _ = Nothing

idrisTypeOf : VarInfo a -> Maybe ClosedTerm
idrisTypeOf (Runtime _ _ t) = t
idrisTypeOf (Shaped _ _ t _) = Just t
idrisTypeOf _ = Nothing

shapeOf : VarInfo a -> Maybe ClosedTerm
shapeOf (Shaped _ _ _ s) = Just s
shapeOf _ = Nothing

variableOf : VarInfo a -> Maybe a
variableOf (Runtime x _ _) = Just x
variableOf (Shaped x _ _ _) = Just x
variableOf _ = Nothing

||| A leaf no input reaches: `Unreachable` in a covering definition
||| (Idris proved no input reaches it), a crash otherwise.
missingCase : {0 nv : Nat} -> Ctx -> Loc -> IdrisMLIR.Term.Term nv
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
missingArm : {0 nv : Nat} -> Ctx -> Loc -> Arm (IdrisMLIR.Term.Term nv)
missingArm ctx loc = if ctx.complete then Dead else Present (Crash loc NoClauseMatched)

||| A match's possible arms: its alternatives and its default when one runs,
||| its alternatives when none does; with no possible arm, the match is
||| unreachable.
armsOf : Loc -> Fin n -> List (Alt n) -> Arm (IdrisMLIR.Term.Term n) -> IdrisMLIR.Term.Term n
armsOf loc i alts (Present d) = Case loc i (Defaulted alts d)
armsOf loc i (a :: as) _ = Case loc i (Exhaustive (a ::: as))
armsOf loc i [] _ = Unreachable loc

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
excludedBy : {auto c : Ref Ctxt Defs} -> Maybe ClosedTerm -> Name -> Front Bool
excludedBy shape cn = case maybe Nothing shapeHead shape of
  Just (built, _) => (/=) <$> fullNames built <*> fullNames cn
  Nothing => pure False

||| The shapes of a constructor's arguments, from the shape of the value.
shapeArgs : Maybe ClosedTerm -> List ClosedTerm
shapeArgs shape = maybe [] snd (maybe Nothing shapeHead shape)

conName : CaseAlt vars -> Maybe Name
conName (ConCase cn _ _ _) = Just cn
conName _ = Nothing

||| Every constructor of the type a match's constructors build.
export
siblings : {auto c : Ref Ctxt Defs} -> List (CaseAlt vars) -> Front (List Name)
siblings alts = case mapMaybe conName alts of
  [] => pure []
  (cn :: _) => do
    defs <- getDefs
    Just def <- lookupExact cn (gamma defs)
      | Nothing => pure []
    let Just tn = built (type def)
      | Nothing => pure []
    Just tdef <- lookupExact tn (gamma defs)
      | Nothing => pure []
    case definition tdef of
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
coversAll : {auto c : Ref Ctxt Defs} -> List (CaseAlt vars) -> Front Bool
coversAll alts = do
  named <- SortedSet.fromList <$> traverse fullNames (mapMaybe conName alts)
  every <- traverse fullNames !(siblings alts)
  pure (not (null every) && all (\c => contains c named) every)

||| Does a match name the constructor the value's shape, if known, says it
||| was built with? Then its default stands for no value the match sees, and
||| its code, which may call for instances no value needs (one a constructor
||| deeper, where a shape keys the instance), is not translated.
builtNamed : {auto c : Ref Ctxt Defs} -> Maybe ClosedTerm -> List (CaseAlt vars) -> Front Bool
builtNamed shape alts = case the (Maybe (Name, List ClosedTerm)) (shape >>= shapeHead) of
  Just (cn, _) => do
    named <- traverse fullNames (mapMaybe conName alts)
    pure (elem !(fullNames cn) named)
  Nothing => pure False

mutual
  ||| A case tree over its scope's variables, and where they stand in the
  ||| definition's clauses (`Clauses`). Each leaf's term starts a path of its
  ||| own (`Terms.term`), and reads each variable where its clause holds it.
  export
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> CaseTree vars -> Front (Term nv)
  tree ctx env cls (STerm clause tm) = term asWritten start (sizeAccessible start) ctx (heldAt (cast clause) cls env) tm
  -- Idris proved it cannot be reached. An `Unmatched` leaf of a covering
  -- definition is one too: a definition whose clauses are all impossible
  -- has only that leaf. In a definition with missing cases it is one of
  -- them, and crashes.
  tree ctx env cls (Unmatched msg) = missingCase ctx <$> toLoc ctx.fc
  tree ctx env cls Impossible = Unreachable <$> toLoc ctx.fc
  tree ctx env cls (Case {name} idx p _ alts) = do
    loc <- toLoc ctx.fc
    case getAt idx env of
      Just (Runtime i (Just WorldT) _) => case alts of
        [ConstCase WorldVal rhs] => tree ctx env cls rhs
        _ => internal ctx.fc "an unexpected match on the world"
      -- A match on a quantity-0 value (a proof, an index) is in the
      -- compile-time tree only when its type forces the alternative, as
      -- Idris's erasure check guarantees; its fields are erased too.
      Just (TypeValue (Erased _ _)) => forced alts
      -- A match on an implementation selects its alternative now.
      Just (Static t hole) => staticCase ctx env cls scrutinee t hole alts
      Just v@(Runtime i _ _) => runtime loc v i
      Just v@(Shaped i _ _ _) => runtime loc v i
      _ => internal ctx.fc "a match on a compile-time value"
    where
      scrutinee : Var vars
      scrutinee = MkVar p

      -- A literal match Idris proved complete has no default: its last
      -- alternative stands in for one (LitNoDefault), and with no
      -- alternative at all no value reaches it. An incomplete one's
      -- default is the missing case's crash.
      literals : Loc -> Fin nv -> Front (Term nv)
      literals loc i = do
        (litAlts, def) <- litAlternatives ctx env cls scrutinee alts
        pure $ case def <|> (if ctx.complete then Nothing else Just (missingCase ctx loc)) of
          Just d => CaseLit loc i (LitDefault litAlts d)
          Nothing => case litAlts of
            a :: as => CaseLit loc i (LitNoDefault (a ::: as))
            [] => Unreachable loc

      -- The data instance a match's constructors are of, at the value's
      -- type. The Core type names it when it is a declaration the
      -- constructor belongs to; a value of a type with one runtime field
      -- has its field's type, so the Idris type names it then.
      instanceOf : VarInfo (Fin nv) -> GlobalDef -> Front FamilyId
      instanceOf v def = do
        st <- getState
        let cn = fullname def
        fromCore <- case coreTyOf v of
                      Just (DataT d _) => do
                        Just cid <- conIdOf d def
                          | Nothing => pure Nothing
                        pure (case lookup cid st.cons of
                                Just layout => if layout.name == cn then Just d else Nothing
                                Nothing => Nothing)
                      _ => pure Nothing
        case (fromCore, idrisTypeOf v) of
          (Just d, _) => pure d
          (Nothing, Just ity) => do
            ity' <- normaliseClosed ity
            Just (inst, _) <- dataOf ctx.fc ctx.owner ity'
              | Nothing => do
                  -- A value array is abstract: only the functions the
                  -- registry knows open it, and their bodies are not
                  -- translated.
                  Just _ <- arrayView ity'
                    | Nothing => internal ctx.fc ("a match on " ++ show cn ++ " at a type that is not data")
                  reject ctx.fc ctx.owner HookShape
                         ("the array type of " ++ show cn ++ " is opaque: its constructor is matched")
            pure inst
          (Nothing, Nothing) =>
            internal ctx.fc ("a match on " ++ show cn ++ " of a value whose type is not known")

      -- A match on a runtime value's constructors or literals.
      matched : Loc -> VarInfo (Fin nv) -> Fin nv -> Front (Term nv)
      matched loc v i =
        case mapMaybe conName alts of
          [] => literals loc i
          (cn :: _) => do
            def <- lookupDef ctx.fc ctx.owner cn
            let shape = shapeOf v
            case (natRole def, coreTyOf v) of
              -- A value of Idris's `Nat` is a natural: a match on its
              -- constructors is a match on zero. A family of the same shape
              -- (`Fin`, `Elem`) is a family like any other, laid out as a
              -- number by the dialect.
              (Just _, Just (NatT _)) => natCase ctx env cls scrutinee shape loc i (idrisTypeOf v) alts
              _ => do
                inst <- instanceOf v def
                every <- coversAll alts
                built <- builtNamed shape alts
                (named, conAlts, fallback) <- conAlternatives ctx env cls scrutinee shape every built inst alts
                -- The constructors a tree with no default leaves out are one
                -- default: impossible when the definition is covering, a
                -- crash otherwise.
                let crashing = case (fallback, ctx.complete) of
                                 (Absent, False) => case familyOf inst !(getState) of
                                   Just f => if all (\(_ ** c) => contains c.id named) f.cons
                                               then Absent else Present (missingCase ctx loc)
                                   Nothing => Absent
                                 _ => fallback
                pure (armsOf loc i conAlts crashing)

      -- A match on a runtime value, by what its alternatives match: a
      -- suspension's form, a natural's constructors, one runtime field's
      -- constructor, a declaration's constructors, or literals. A
      -- suspension has one form, `Delay x`, so its match chooses nothing:
      -- it is the force, whose value `x` binds, then the alternative's
      -- tree, whose first variable is the value's type, erased.
      runtime : Loc -> VarInfo (Fin nv) -> Fin nv -> Front (Term nv)
      runtime loc v i = delayed alts
        where
          -- The first alternative that matches a suspension, or a match on
          -- the value's constructors or literals.
          delayed : List (CaseAlt vars) -> Front (Term nv)
          delayed (DelayCase _ arg rhs :: _) = do
            let value = case (coreTyOf v, idrisTypeOf v) of
                          (Just (LazyT t), Just (TDelayed _ _ ity)) => Runtime FZ (Just t) (Just ity)
                          (Just (LazyT t), _) => Runtime FZ (Just t) Nothing
                          _ => Runtime FZ Nothing Nothing
            body <- tree ctx (under {k = 1} [TypeValue (Erased ctx.fc Placeholder), value] env)
                         (afterDelay scrutinee cls) rhs
            pure (Let loc (binderName arg) (OfValue Many) (Resume loc (Var loc i)) body)
          delayed (_ :: rest) = delayed rest
          delayed [] = matched loc v i

      forced : List (CaseAlt vars) -> Front (Term nv)
      forced [ConCase cn _ args rhs] =
        tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env)
             (afterCon args scrutinee cls) rhs
      forced [DefaultCase rhs] = tree ctx env cls rhs
      forced _ = do
        cons <- traverse altName alts
        reject ctx.fc ctx.owner Match
               ("a match on `" ++ show name ++ "`, which is erased (quantity 0, or an index or proof " ++
                "with no runtime value), between " ++ joinBy ", " cons ++ ": only a runtime value can " ++
                "choose an alternative; match on the runtime value that determines it instead")
        where
          altName : CaseAlt vars -> Front String
          altName (ConCase cn _ _ _) = show <$> fullNames cn
          altName (ConstCase c _) = pure (show c)
          altName (DelayCase {}) = pure "Delay"
          altName (DefaultCase _) = pure "the default"

  ||| A match on a `Nat`-like value: zero, or a successor binding the
  ||| predecessor. The default stands for whichever the tree leaves out.
  natCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
            Maybe ClosedTerm -> Loc -> Fin nv -> Maybe ClosedTerm ->
            List (CaseAlt vars) -> Front (Term nv)
  natCase ctx env cls scrutinee shape loc x ity alts = do
    every <- coversAll alts
    built <- builtNamed shape alts
    (z, s, d) <- natAlternatives ctx env cls scrutinee shape ity (every || built) loc x alts
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
                    Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
                    Maybe ClosedTerm -> Maybe ClosedTerm -> Bool -> Loc -> Fin nv ->
                    List (CaseAlt vars) ->
                    Front (Arm (Term nv), Arm (Shown, Term (Under 1 nv)), Arm (Term nv))
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x [] = pure (Absent, Absent, Absent)
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    taken <- argumentsOf def
    dead <- excludedBy shape (fullname def)
    let cls' = afterCon args scrutinee cls
    case natRole def of
      Just Zero => do
        z <- if dead then pure Dead
             else Present <$> tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env) cls' rhs
        (_, s, d) <- natAlternatives ctx env cls scrutinee shape ity deadDefault loc x rest
        pure (z, s, d)
      Just Succ => do
        -- The constructor's type shows a binder for each argument its
        -- alternative binds, which Idris's tree takes from it.
        let Yes _ = decEq (length taken) (length args)
          | No _ => internal ctx.fc ("the successor " ++ show cn ++ " binds another number of arguments than it takes")
        let predInfo : VarInfo (Fin (Under 1 nv))
            predInfo = case (predecessor (shapeArgs shape) taken, ity) of
                         (Just p, Just t) => shaped FZ NatT t p
                         _ => Runtime FZ (Just (NatT IOpaque)) ity
        let infos = map (\a => case a of
                                  RuntimeValue _ => predInfo
                                  _ => TypeValue (Erased ctx.fc Placeholder)) taken
        let pred = maybe (shown "_") (binderName . fst) (find (isValue . snd) (zip args taken))
        body <- if dead then pure Dead
                else (\b => Present (pred, b)) <$> tree ctx (under {k = 1} infos env) cls' rhs
        (z, _, d) <- natAlternatives ctx env cls scrutinee shape ity deadDefault loc x rest
        pure (z, body, d)
      Nothing => internal ctx.fc ("a constructor of another type in a match on a Nat-like value")
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
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x (DefaultCase rhs :: _) =
    pure (Absent, Absent, !(if deadDefault then pure Dead else Present <$> tree ctx env cls rhs))
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x (_ :: _) =
    internal ctx.fc "an unexpected alternative"

  ||| A match on a compile-time value: the implementation is reduced to its
  ||| constructor, and the alternative's variables stand for its arguments.
  ||| An argument that mentions the runtime value the implementation closes
  ||| over closes over it too.
  staticCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
               Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
               ClosedTerm -> Maybe (Fin nv, Holes) ->
               List (CaseAlt vars) -> Front (Term nv)
  staticCase ctx env cls scrutinee t hole alts = do
    Built cn cargs <- whnf t
      | Stuck on => do
          -- No parameter is such a form: an implementation a runtime value
          -- chooses, or one a definition Idris does not prove ends
          -- computes, is passed as a choice (`Instances.classify`) and
          -- translated as the computation it is (`Terms.memberHere`), so
          -- each member a dispatch fixes reduces. What reaches here is a
          -- field of a reduced implementation matched again in the same
          -- tree, whose match would dispatch the rest of the tree over the
          -- members of its choice.
          let rule = case on of
                       OnRuntime _ => RuntimeClosure
                       _ => StaticArgument
          reject ctx.fc ctx.owner rule
                 ("an implementation that does not reduce to its constructor: " ++ !(showTT t) ++
                  ", stuck on " ++ !(stuckText on))
    cn <- fullNames cn
    taken <- argumentsOf !(lookupDef ctx.fc ctx.owner cn)
    pick cn (zipWith info taken cargs) alts
    where
      info : ArgumentAt -> ClosedTerm -> VarInfo (Fin nv)
      info (RuntimeValue _) v = Static v (if mentionsHole v then hole else Nothing)
      info _ v = TypeValue v
      pick : Name -> List (VarInfo (Fin nv)) -> List (CaseAlt vars) -> Front (Term nv)
      pick cn infos (ConCase con _ args rhs :: rest) = do
        full <- fullNames con
        if full /= cn then pick cn infos rest else do
          when (length args /= length infos) $
            internal ctx.fc ("constructor " ++ show cn ++ " binds an unexpected number of arguments")
          tree ctx (infos ++ env) (afterCon args scrutinee cls) rhs
      pick cn infos (DefaultCase rhs :: _) = tree ctx env cls rhs
      pick cn infos (_ :: rest) = pick cn infos rest
      pick cn infos [] = internal ctx.fc ("no alternative for " ++ show cn)

  ||| The constructors a match's alternatives name, its possible
  ||| alternatives, each over its fields, named as the alternative names
  ||| them, and the default: none when the alternatives name every
  ||| constructor (`every`), one no value takes when they name the one the
  ||| value's shape says it was built with (`built`). The shape, if known,
  ||| rules out every other constructor and gives the fields their shapes;
  ||| an alternative it rules out, or of a constructor with no value yet,
  ||| is no possible one.
  conAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
                    Maybe ClosedTerm -> Bool -> Bool -> FamilyId ->
                    List (CaseAlt vars) -> Front (SortedSet ConId, List (Alt nv), Arm (Term nv))
  conAlternatives ctx env cls scrutinee shape every built inst [] = pure (empty, [], Absent)
  conAlternatives ctx env cls scrutinee shape every built inst (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    Just cid <- conIdOf inst def
      | Nothing => internal ctx.fc ("the constructor " ++ show (fullname def) ++ " is not registered")
    st <- getState
    let Just info = lookup cid st.cons
      | Nothing => internal ctx.fc ("the constructor " ++ show (fullname def) ++ " is not registered")
    when (length info.args /= length args) $
      reject ctx.fc ctx.owner CompiledModule
             ("constructor " ++ show (fullname def) ++ " binds an unexpected number of arguments")
    let named = mapMaybe fieldNamed (zip args info.args)
    -- The alternative binds the constructor's fields, as many as its tree
    -- names.
    let (k ** con) = info.con
    let Yes counted = decEq (length named) k
      | No _ => internal ctx.fc ("the constructor " ++ show (fullname def) ++ " of " ++ show k ++
                                 " fields, which its alternative binds " ++ show (length named) ++ " of")
    dead <- excludedBy shape (fullname def)
    let infos = argsBound (fieldAt k) info.args (shapeArgs shape)
    alt <- if dead then pure Nothing else do
      body <- tree ctx (under {k} infos env) (afterCon args scrutinee cls) rhs
      pure (Just (MkAlt con (replace {p = \c => Vect c Shown} counted (fromList named)) body))
    (others, alts, fallback) <- conAlternatives ctx env cls scrutinee shape every built inst rest
    pure (insert cid others, maybe alts (:: alts) alt, fallback)
    where
      fieldNamed : (Name, ArgKind) -> Maybe Shown
      fieldNamed (n, Field _ _ _) = Just (binderName n)
      fieldNamed _ = Nothing

      -- Runtime field `i` is the alternative's `Bound i`, with what the
      -- value's shape says of it.
      fieldAt : (k : Nat) -> Nat -> Binder -> ClosedTerm -> Maybe ClosedTerm -> VarInfo (Fin (Under k nv))
      fieldAt k i b ity s = case natToFin i k of
        Just f => case s of
          Just s' => shaped (Bound {n = nv} f) (typeOf b) ity s'
          Nothing => Runtime (Bound {n = nv} f) (Just (typeOf b)) (Just ity)
        Nothing => TypeValue (Erased EmptyFC Placeholder)
  conAlternatives ctx env cls scrutinee shape every built inst (DefaultCase rhs :: _) =
    if every then pure (empty, [], Absent)
      else if built then pure (empty, [], Dead)
      else (\d => (empty, [], Present d)) <$> tree ctx env cls rhs
  conAlternatives ctx env cls scrutinee shape every built inst (DelayCase {} :: _) =
    internal ctx.fc "a suspension's alternative in a constructor match"
  conAlternatives ctx env cls scrutinee shape every built inst (ConstCase {} :: _) =
    internal ctx.fc "a constant alternative in a constructor match"

  litAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
                    List (CaseAlt vars) ->
                    Front (List (Lit, Term nv), Maybe (Term nv))
  litAlternatives ctx env cls scrutinee [] = pure ([], Nothing)
  litAlternatives ctx env cls scrutinee (ConstCase c rhs :: rest) = do
    Just lit <- pure (constantLit c)
      | Nothing => reject ctx.fc ctx.owner StringPrimitive ("a match on " ++ show c)
    case lit of
      LDouble _ => reject ctx.fc ctx.owner Primitive "a match on a Double literal"
      _ => pure ()
    body <- tree ctx env cls rhs
    (alts, def) <- litAlternatives ctx env cls scrutinee rest
    pure ((lit, body) :: alts, def)
  litAlternatives ctx env cls scrutinee (DefaultCase rhs :: _) =
    pure ([], Just !(tree ctx env cls rhs))
  litAlternatives ctx env cls scrutinee _ = internal ctx.fc "an unexpected alternative"
