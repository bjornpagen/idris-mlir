-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Which places of a clause are one binder, as a case tree's matches take
||| the clause apart. Idris's compile-time tree names a binder of a clause
||| by the first place the clause binds it, leftmost first, and that can be
||| an erased place where another holds the same value at run time: in
||| `upTo (Step t p) Here` the erased index `z` is the field `t`, and the
||| leaf names `z`. The clause says which places are one binder, its
||| unifier having made them one, and each place's quantity says whether it
||| holds a value at run time, so a leaf reads an erased variable as the
||| variable that holds its binder, as Idris's run time tree does. Idris's
||| quantity check of the clause gives every binder its right side uses at
||| run time such a place. Idris keeps no clause number in a tree it reads
||| back, so the clauses a leaf reads are those whose left-hand side every
||| input that reaches it matches: an equation of such a clause holds there,
||| and the leaf's own clause is one. What a place tests is what Idris's
||| tree splits on there (`Pattern`): a term the unifier computed from the
||| other places (the index `cs ++ ps` of the value `ConClauses cs rest`)
||| tests nothing, so a clause that holds one at run time still matches.
module IdrisMLIR.Frontend.Translate.Forced

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Env
import Core.TT
import Idris.Host

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed

import Data.List
import Data.SortedMap
import Data.Vect

%default total

mutual
  ||| A place of a clause's left-hand side as Idris's case builder reads it
  ||| (`argToPat`), read once (`patternOf`): the clause's binders, by number,
  ||| that it names the whole by (a variable, and the names its as-patterns
  ||| give), and what tests the value there.
  record Pattern where
    constructor MkPattern
    names : List Nat
    test : Test

  ||| What a place tests, as Idris's tree splits on it: a data or type
  ||| constructor applied to its arguments (a function type is the type
  ||| constructor `->` applied to its domain and codomain, as the tree names
  ||| its alternative), a constant, or a suspension. Nothing is tested where
  ||| the place is a variable, or a term the builder cannot match: an erased
  ||| place, or a term the unifier computed from the clause's other places,
  ||| whose value those fix.
  data Test : Type where
    Untested : Test
    Con : Name -> List Pattern -> Test
    Lit : Constant -> Test
    Suspended : Pattern -> Pattern -> Test

||| A place that binds nothing and tests nothing.
wildcard : Pattern
wildcard = MkPattern [] Untested

||| What a clause's binders are called once it is closed (`Env.close`):
||| each by its number in the clause's scope, the innermost 0, as a case
||| tree's leaf names it.
placeName : String
placeName = "place"

||| The binder of the clause a place's name is, by its number.
binderOf : Name -> List Nat
binderOf (MN s i) = if s == placeName then [cast i] else []
binderOf _ = []

mutual
  ||| A place as the case builder read it.
  patternOf : Pat -> Pattern
  patternOf (PAs _ n p) = { names $= (binderOf n ++) } (patternOf p)
  patternOf (PCon _ n _ _ ps) = MkPattern [] (Con n (patternsOf ps))
  patternOf (PTyCon _ n _ ps) = MkPattern [] (Con n (patternsOf ps))
  patternOf (PConst _ c) = MkPattern [] (Lit c)
  patternOf (PArrow _ _ s t) = MkPattern [] (Con (UN (Basic "->")) [patternOf s, patternOf t])
  patternOf (PDelay _ _ t p) = MkPattern [] (Suspended (patternOf t) (patternOf p))
  patternOf (PLoc _ n) = MkPattern (binderOf n) Untested
  patternOf (PUnmatchable _ _) = wildcard

  patternsOf : List Pat -> List Pattern
  patternsOf [] = []
  patternsOf (p :: ps) = patternOf p :: patternsOf ps

||| A variable of a case tree's scope as one clause sees it: the quantity
||| of the place that holds it (the definition's parameter, or the
||| argument of the constructor a match took apart, times the quantity of
||| what it took apart), and the clause's place still to match there.
record Occurrence where
  constructor MkOccurrence
  quantity : RigCount
  matched : Pattern

||| One occurrence per variable of a scope, the innermost first.
export
data Occurrences : Scope -> Type where
  Nil : Occurrences []
  (::) : Occurrence -> Occurrences vars -> Occurrences (v :: vars)

||| The clauses whose left-hand sides the inputs that reach a point of a
||| case tree may match, each as occurrences of the tree's scope there.
public export
Clauses : Scope -> Type
Clauses vars = List (Occurrences vars)

||| The occurrence of the variable at a position of the scope.
occurrenceAt : (idx : Nat) -> (0 _ : IsVar n idx vars) -> Occurrences vars -> Occurrence
occurrenceAt Z _ (o :: _) = o
occurrenceAt (S i) p (_ :: os) = occurrenceAt i (dropLater p) os
occurrenceAt _ First [] impossible
occurrenceAt _ (Later _) [] impossible

||| The occurrences with the one at a position replaced.
replaceAt : (idx : Nat) -> (0 _ : IsVar n idx vars) -> Occurrence -> Occurrences vars -> Occurrences vars
replaceAt Z _ o (_ :: os) = o :: os
replaceAt (S i) p o (o' :: os) = o' :: replaceAt i (dropLater p) o os
replaceAt _ First _ [] impossible
replaceAt _ (Later _) _ [] impossible

||| Each variable's position in the scope with its occurrence, the
||| innermost first.
positioned : Occurrences vars -> List (Nat, Occurrence)
positioned = go 0
  where
    go : Nat -> Occurrences vs -> List (Nat, Occurrence)
    go i [] = []
    go i (o :: os) = (i, o) :: go (S i) os

||| Occurrences of the arguments a match binds, in front of the scope's.
bindArgs : (args : List Name) -> Vect (length args) Occurrence -> Occurrences vars ->
           Occurrences (Scope.addInner vars args)
bindArgs [] [] os = os
bindArgs (_ :: as) (o :: rest) os = o :: bindArgs as rest os

||| A place once a match has taken it apart: the names it binds the whole
||| by, and nothing left to test.
takenApart : Pattern -> Pattern
takenApart = { test := Untested }

||| The quantities of a type's first `k` binders, in order; a binder the
||| type shows only once normalised is read there. Idris gives a
||| constructor as many binders as a match on it binds arguments, and a
||| definition at least as many as its clauses take, but its terms do not
||| say so: a binder past the type's would hold nothing at run time.
quantities : {auto c : Ref Ctxt Defs} -> (k : Nat) -> ClosedTerm -> Core (Vect k RigCount)
quantities Z _ = pure []
quantities (S k) (Bind _ _ (Pi _ rig _ _) sc) = (rig ::) <$> quantities k (subst (Erased EmptyFC Placeholder) sc)
quantities (S k) ty = case !(normaliseClosed ty) of
  Bind _ _ (Pi _ rig _ _) sc => (rig ::) <$> quantities k (subst (Erased EmptyFC Placeholder) sc)
  _ => pure (replicate (S k) erased)

||| A clause's left-hand side as occurrences of the definition's
||| parameters: its places, each at its parameter's quantity. Idris builds
||| the tree from clauses that take as many arguments as it has
||| parameters.
leftSide : (args : Scope) -> Vect (length args) RigCount -> List Pattern -> Occurrences args
leftSide [] [] _ = []
leftSide (_ :: as) (q :: qs) (p :: ps) = MkOccurrence q p :: leftSide as qs ps
leftSide (_ :: as) (q :: qs) [] = MkOccurrence q wildcard :: leftSide as qs []

||| A definition's clauses, at the root of its compile-time tree, whose
||| scope is the definition's parameters (`args`, of the type `ty`), each
||| argument of a clause read as the case builder reads it, from the clause
||| closed as Idris closes it to build the tree.
export
clauses : {auto c : Ref Ctxt Defs} -> (args : Scope) -> (ty : ClosedTerm) ->
          List (vs : Scope ** (Env TT vs, TT vs, TT vs)) -> Core (Clauses args)
clauses args ty pats = do
  qs <- quantities (length args) ty
  traverse (\(_ ** (env, lhs, _)) => do
              full <- toFullNames (close EmptyFC placeName env lhs)
              places <- traverse host.argToPat (snd (getFnArgs full))
              pure (leftSide args qs (map patternOf places)))
           pats

||| The arguments a match binds, each at the quantity of its binder times
||| the quantity of what the match took apart.
argsAt : RigCount -> Vect k RigCount -> Vect k Pattern -> Vect k Occurrence
argsAt q = zipWith (\b, part => MkOccurrence (q |*| b) part)

||| A clause after a match on constructor `cn` at a position: the place
||| there taken apart, its arguments in front; wildcards where the place
||| tests nothing. A place that tests anything else (another constructor,
||| one applied to other than its arguments, a constant, a suspension) is
||| not known to match the inputs that take this alternative, and the
||| clause is dropped.
split : {auto c : Ref Ctxt Defs} -> Name -> (idx : Nat) -> (0 _ : IsVar n idx vars) ->
        (bound : List Name) -> Vect (length bound) RigCount -> Occurrences vars ->
        Core (Maybe (Occurrences (Scope.addInner vars bound)))
split cn idx p bound qs os = do
  let o = occurrenceAt idx p os
  case o.matched.test of
    Untested => pure (Just (bindArgs bound (argsAt o.quantity qs (replicate (length bound) wildcard)) os))
    Con n ps => case toVect (length bound) ps of
      Just parts =>
        if !(sameName n cn)
          then pure (Just (bindArgs bound (argsAt o.quantity qs parts) (replaceAt idx p ({ matched $= takenApart } o) os)))
          else pure Nothing
      Nothing => pure Nothing
    Lit _ => pure Nothing
    Suspended _ _ => pure Nothing

||| The clauses that take a match's alternative for constructor `cn`, of
||| type `ty`, which binds `args`, at the variable it matches.
export
afterCon : {auto c : Ref Ctxt Defs} -> Name -> (ty : ClosedTerm) -> Var vars -> (args : List Name) ->
           Clauses vars -> Core (Clauses (Scope.addInner vars args))
afterCon cn ty (MkVar {varIdx} p) args cls = do
  qs <- quantities (length args) ty
  taken <- traverse (split cn varIdx p args qs) cls
  pure (mapMaybe id taken)

||| The clauses that take a match on a suspension at a variable: the
||| suspension's type, erased, and its value, in front.
export
afterDelay : Var vars -> Clauses vars -> Clauses (Scope.addInner vars [ty, arg])
afterDelay (MkVar {varIdx} p) = mapMaybe forced
  where
    forced : Occurrences vars -> Maybe (Occurrences (Scope.addInner vars [ty, arg]))
    forced os =
      let o = occurrenceAt varIdx p os in
      case o.matched.test of
        Untested => Just (MkOccurrence erased wildcard :: MkOccurrence o.quantity wildcard :: os)
        Suspended t v =>
          Just (MkOccurrence erased t :: MkOccurrence o.quantity v :: replaceAt varIdx p ({ matched $= takenApart } o) os)
        Con _ _ => Nothing
        Lit _ => Nothing

||| The clauses that take a match's alternative for a literal at a variable.
export
afterLit : Constant -> Var vars -> Clauses vars -> Clauses vars
afterLit c (MkVar {varIdx} p) = mapMaybe literal
  where
    literal : Occurrences vars -> Maybe (Occurrences vars)
    literal os =
      let o = occurrenceAt varIdx p os in
      case o.matched.test of
        Untested => Just os
        Lit c' => if c == c' then Just (replaceAt varIdx p ({ matched $= takenApart } o) os) else Nothing
        Con _ _ => Nothing
        Suspended _ _ => Nothing

||| Does every input that reaches a leaf match the clause: does no place
||| at a variable that holds a value at run time still test it? Idris's
||| tree matches every such place of a clause before the clause's leaf, and
||| an erased place is fixed by those its type depends on.
covers : Occurrences vars -> Bool
covers [] = True
covers (o :: os) = case (use o.quantity, o.matched.test) of
  (Erased, _) => covers os
  (Used _, Untested) => covers os
  (Used _, _) => False

||| The variables a leaf reads elsewhere by one clause, by position: each
||| one of quantity 0 whose binder a variable that holds a value at run
||| time also binds, with the outermost such variable, which the matches
||| bound first.
aliasesBy : List (Nat, Occurrence) -> List (Nat, Nat)
aliasesBy vs = mapMaybe alias vs
  where
    holds : List Nat -> (Nat, Occurrence) -> Bool
    holds bs (_, o) = case use o.quantity of
      Erased => False
      Used _ => any (\b => elem b o.matched.names) bs

    alias : (Nat, Occurrence) -> Maybe (Nat, Nat)
    alias (i, o) = case use o.quantity of
      Erased => map (\(j, _) => (i, j)) (find (holds o.matched.names) (reverse vs))
      Used _ => Nothing

||| The variables a leaf reads elsewhere, by every clause whose left-hand
||| side the inputs that reach it match, the first clause's reading first:
||| by position, the position read in its place.
aliases : Clauses vars -> SortedMap Nat Nat
aliases = foldl more empty
  where
    more : SortedMap Nat Nat -> Occurrences vars -> SortedMap Nat Nat
    more found os = if covers os then mergeLeft found (fromList (aliasesBy (positioned os))) else found

||| A leaf's environment, one entry per variable of its scope by position:
||| each erased variable read as the variable that holds its binder at run
||| time (`aliases`), which is never itself one read elsewhere.
export
heldAt : Clauses vars -> List a -> List a
heldAt cls env = foldl hold env (SortedMap.toList (aliases cls))
  where
    setAt : Nat -> a -> List a -> List a
    setAt Z v (_ :: xs) = v :: xs
    setAt (S i) v (x :: xs) = x :: setAt i v xs
    setAt _ _ [] = []

    hold : List a -> (Nat, Nat) -> List a
    hold e (i, j) = maybe e (\v => setAt i v e) (getAt j env)
