-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Coverage

import Core.Case.CaseTree
import Core.Case.Util
import Core.Context.Log
import Core.Env
import Core.Normalise
import Core.Value

import Control.WellFounded
import Data.Maybe
import Data.Nat
import Data.So
import Data.String

import Libraries.Data.NameMap
import Libraries.Data.NatSet
import Libraries.Data.String.Extra
import Libraries.Data.List.SizeOf
import Libraries.Text.PrettyPrint.Prettyprinter

%default covering

-- Return whether any of the name matches conflict
conflictMatch : List (Name, Term vars) -> Bool
conflictMatch [] = False
conflictMatch ((x, tm) :: ms) = conflictArgs x tm ms || conflictMatch ms
  where
    data ClashResult = Distinct | Same | Incomparable

    clash : Term vars -> Term vars -> ClashResult
    clash (Ref _ (DataCon t _) _) (Ref _ (DataCon t' _) _)
        = if t /= t' then Distinct else Same
    clash (Ref _ (TyCon _) n) (Ref _ (TyCon _) n')
        = if n /= n' then Distinct else Same
    clash (PrimVal _ c) (PrimVal _ c') = if c /= c' then Distinct else Same
    clash (Ref _ t _) (PrimVal {}) = if isJust (isCon t) then Distinct else Incomparable
    clash (PrimVal {}) (Ref _ t _) = if isJust (isCon t) then Distinct else Incomparable
    clash (Ref _ t _) (TType {})   = if isJust (isCon t) then Distinct else Incomparable
    clash (TType {}) (Ref _ t _)   = if isJust (isCon t) then Distinct else Incomparable
    clash (TType {}) (PrimVal {})  = Distinct
    clash (PrimVal {}) (TType {})  = Distinct
    clash _ _ = Incomparable

    findN : Nat -> Term vars -> Bool
    findN i (Local _ _ i' _) = i == i'
    findN i tm
        = let (Ref _ (DataCon {}) _, args) = getFnArgs tm
                   | _ => False in
              any (findN i) args

    -- Assuming in normal form. Look for: mismatched constructors, or
    -- a name appearing strong rigid in the other term
    conflictTm : Term vars -> Term vars -> Bool
    conflictTm (Local _ _ i _) tm
        = let (Ref _ (DataCon {}) _, args) = getFnArgs tm
                   | _ => False in
              any (findN i) args
    conflictTm tm (Local _ _ i _)
        = let (Ref _ (DataCon {}) _, args) = getFnArgs tm
                   | _ => False in
              any (findN i) args
    conflictTm tm tm'
        = let (f, args) = getFnArgs tm
              (f', args') = getFnArgs tm' in
          case clash f f' of
            Distinct => True
            Incomparable => False
            Same => (any (uncurry conflictTm) (zip args args'))

    conflictArgs : Name -> Term vars -> List (Name, Term vars) -> Bool
    conflictArgs n tm [] = False
    conflictArgs n tm ((x, tm') :: ms)
        = (n == x && conflictTm tm tm') || conflictArgs n tm ms

-- The nodes of a term, which bound how far 'isEmpty' looks into a type.
-- Each kind of node that holds terms is counted by a function of its own,
-- so that every recursive call is on a part of its argument.
mutual
  total
  sizePi : PiInfo (Term vars) -> Nat
  sizePi (DefImplicit t) = termSize t
  sizePi _ = 0

  total
  sizeBinder : Binder (Term vars) -> Nat
  sizeBinder (Lam _ _ p ty) = sizePi p + termSize ty
  sizeBinder (Let _ _ val ty) = termSize val + termSize ty
  sizeBinder (Pi _ _ p ty) = sizePi p + termSize ty
  sizeBinder (PVar _ _ p ty) = sizePi p + termSize ty
  sizeBinder (PLet _ _ val ty) = termSize val + termSize ty
  sizeBinder (PVTy _ _ ty) = termSize ty

  total
  sizeTerms : List (Term vars) -> Nat
  sizeTerms [] = 0
  sizeTerms (t :: ts) = termSize t + sizeTerms ts

  total
  termSize : Term vars -> Nat
  termSize (Meta _ _ _ args) = S (sizeTerms args)
  termSize (Bind _ _ b sc) = S (sizeBinder b + termSize sc)
  termSize (App _ f a) = S (termSize f + termSize a)
  termSize (As _ _ a p) = S (termSize a + termSize p)
  termSize (TDelayed _ _ t) = S (termSize t)
  termSize (TDelay _ _ ty a) = S (termSize ty + termSize a)
  termSize (TForce _ _ t) = S (termSize t)
  termSize _ = 1

-- A fresh name for a binder of a constructor's type, numbered `i`, in case
-- a user has bound the same name twice somehow: both references could
-- appear in one result. A user name's printed form is its identifier's
-- text, so only another name's is interned.
freshName : {auto c : Ref Ctxt Defs} -> Name -> Int -> Core Name
freshName (UN (Basic j)) i = pure (MN j i)
freshName x i = pure (MN !(intern (show x)) i)

-- A constructor's type with each of its `arity` arguments a fresh name,
-- numbered from `i`: the arguments' types, the type it returns, and the
-- next number. The arity is the count of the binders of the type's normal
-- form, which the constructor was declared with, so the walk descends it.
instantiate : {auto c : Ref Ctxt Defs} ->
              Defs -> (arity : Nat) -> Int -> ClosedNF ->
              Core (List ClosedTerm, ClosedNF, Int)
instantiate defs (S k) i (NBind fc x b sc)
    = do x' <- freshName x i
         ty <- quote defs Env.empty (binderType b)
         (tys, ret, next) <- instantiate defs k (i + 1)
                               !(sc defs (toClosure defaultOpts Env.empty (Ref fc Bound x')))
         pure (ty :: tys, ret, next)
instantiate defs _ i ret = pure ([], ret, i)

-- Two parts of a type that every value of it holds equal.
data Equation : Scoped where
     MkEquation : (lhs : Term vars) -> (rhs : Term vars) -> Equation vars

-- A term with each fresh name the first part of a pair names replaced by
-- the second. The fresh names of a search are numbered past those of every
-- type it is inside, so what one is replaced by mentions no other of them.
total
substAll : List (Name, Term vars) -> Term vars -> Term vars
substAll [] tm = tm
substAll ((x, v) :: ms) tm = substAll ms (substName x v tm)

-- The parts of a type a constructor's return type puts at one of its
-- arguments, two by two: each two are equal, since the argument is one
-- value (`Refl`'s two sides, both at its `x`).
total
sameArgument : List (Name, Term vars) -> List (Equation vars)
sameArgument [] = []
sameArgument ((x, tm) :: ms)
    = map (MkEquation tm . snd) (filter ((== x) . fst) ms) ++ sameArgument ms

-- What a constructor's type says of building a value of a given type: it
-- cannot, its return type conflicting with the type, or it may, and then
-- takes arguments of these types, each argument its return type
-- determines replaced by what the type has there (an argument it does not
-- determine stays a fresh name, which conflicts with nothing). A fit also
-- holds the equations its return type holds of the type, two parts of the
-- type it puts at one of its arguments being equal (`Refl`'s, at
-- `MkHead Nothing (y :: z) = MkHead Nothing ts`, that the two sides are),
-- and the next number for a fresh name.
data Fit : Scoped where
     Conflicts : Fit vars
     Fits : (argTypes : List (Term vars)) -> (holds : List (Equation vars)) ->
            (next : Int) -> Fit vars

-- How a constructor builds a value of the type, if it can: whether any
-- part of the type conflicts with the constructor's return type in such a
-- way that they can't possibly be equal (i.e. mismatched constructor), and
-- otherwise the types of its arguments, their fresh names numbered from
-- `base`. A name that is no data constructor tells nothing, so it fits,
-- with nothing to look into.
fitting : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          Defs -> Env Term vars -> (base : Int) -> NF vars -> Name -> Core (Fit vars)
fitting defs env base nfty n
    = do Just gdef <- lookupCtxtExact n (gamma defs)
              | Nothing => pure (Fits [] [] base)
         case definition gdef of
              DCon _ arity _
                  => do (argtys, ret, next) <- instantiate defs arity base
                                                 !(nf defs Env.empty !(typeOf gdef))
                        Just ms <- conflictNF next nfty ret
                            | Nothing => pure Conflicts
                        pure $ if conflictMatch ms
                                  then Conflicts
                                  else Fits (map (argTypeIn ms) argtys) (sameArgument ms) next
              _ => pure (Fits [] [] base)
  where
    -- An argument's type in the scope of the type built, each argument the
    -- constructor's return type determines replaced by what the type has.
    argTypeIn : List (Name, Term vars) -> ClosedTerm -> Term vars
    argTypeIn ms ty = substAll ms (embed ty)

    mutual
      conflictArgs : Int -> List (Closure vars) -> List ClosedClosure ->
                     Core (Maybe (List (Name, Term vars)))
      conflictArgs _ [] [] = pure (Just [])
      conflictArgs i (c :: cs) (c' :: cs')
          = do cnf <- evalClosure defs c
               cnf' <- evalClosure defs c'
               Just ms <- conflictNF i cnf cnf'
                    | Nothing => pure Nothing
               Just ms' <- conflictArgs i cs cs'
                    | Nothing => pure Nothing
               pure (Just (ms ++ ms'))
      conflictArgs _ _ _ = pure (Just [])

      -- If the constructor type (the ClosedNF) matches the variable type,
      -- then there may be a way to construct it, so return the matches in
      -- the indices.
      -- If any of those matches clash, the constructor is not valid
      -- e.g, Eq x x matches Eq Z (S Z), with x = Z and x = S Z
      -- conflictNF returns the list of matches, for checking
      conflictNF : Int -> NF vars -> ClosedNF ->
                   Core (Maybe (List (Name, Term vars)))
      conflictNF i t (NBind fc x b sc)
          = do x' <- freshName x i
               conflictNF (i + 1) t
                      !(sc defs (toClosure defaultOpts Env.empty (Ref fc Bound x')))
      conflictNF i nf (NApp _ (NRef Bound n) [])
          = pure (Just [(n, !(quote defs env nf))])
      conflictNF i (NDCon _ n t a args) (NDCon _ n' t' a' args')
          = if t == t'
               then conflictArgs i (map snd args) (map snd args')
               else pure Nothing
      conflictNF i (NTCon _ n a args) (NTCon _ n' a' args')
          = if n == n'
               then conflictArgs i (map snd args) (map snd args')
               else pure Nothing
      conflictNF i (NPrimVal _ c) (NPrimVal _ c')
          = if c == c'
               then pure (Just [])
               else pure Nothing
      conflictNF _ _ _ = pure (Just [])

-- A type that is a family applied to its indices: the only kind 'isEmpty'
-- takes apart, since only a family has constructors to try.
data OfFamily : NF vars -> Type where
     FamilyApplied : OfFamily (NTCon fc n a args)

-- Whether a name occurs in a term.
total
occurs : Name -> Term vars -> Bool
occurs x tm = isJust (lookup x (getRefs (UN Underscore) tm))

-- What equations between parts of a type say of its fresh names, the
-- arguments a search for a value has not determined: a fresh name equal to
-- a term it does not occur in is that term, and two applications of one
-- constructor are equal only where their arguments are. Any other equation
-- says nothing here, which loses facts and never invents one.
mutual
  total
  solveEquation : Term vars -> Term vars -> List (Name, Term vars)
  solveEquation (Ref _ Bound x) tm = if occurs x tm then [] else [(x, tm)]
  solveEquation tm (Ref _ Bound x) = if occurs x tm then [] else [(x, tm)]
  solveEquation tm tm' = fromMaybe [] (sameSpine tm tm')

  -- Two applications of one constructor to as many arguments, argument by
  -- argument, peeled together so that each call is on a part of its
  -- arguments; Nothing for two terms of any other shape.
  total
  sameSpine : Term vars -> Term vars -> Maybe (List (Name, Term vars))
  sameSpine (App _ f a) (App _ f' a') = map (++ solveEquation a a') (sameSpine f f')
  sameSpine (Ref _ (DataCon {}) n) (Ref _ (DataCon {}) n')
      = if n == n' then Just [] else Nothing
  sameSpine (Ref _ (TyCon {}) n) (Ref _ (TyCon {}) n')
      = if n == n' then Just [] else Nothing
  sameSpine _ _ = Nothing

-- The fresh names a type's equations solve, each with what it stands for.
total
forcedBy : List (Equation vars) -> List (Name, Term vars)
forcedBy [] = []
forcedBy (MkEquation lhs rhs :: eqs) = solveEquation lhs rhs ++ forcedBy eqs

-- Whether a term names one of the fresh names solved.
total
mentionsSolved : List (Name, Term vars) -> Term vars -> Bool
mentionsSolved solved ty = any (\s => occurs (fst s) ty) solved

-- What the search knows of the values of a type, or of a constructor's
-- arguments taken together: there are none, or every one holds these
-- equations of the type's parts. A type with one constructor holds those
-- its constructor's return type holds (`Refl`'s) and those its arguments'
-- types hold (a pair's parts'); one with more holds none here.
data Inhabitants : Scoped where
     NoValue : Inhabitants vars
     Holding : (equations : List (Equation vars)) -> Inhabitants vars

-- What the values hold, and these equations besides.
total
holdingAlso : List (Equation vars) -> Inhabitants vars -> Inhabitants vars
holdingAlso _ NoValue = NoValue
holdingAlso eqs (Holding held) = Holding (eqs ++ held)

-- Whether a type of a family, of `nodes` nodes, has a value, and what every
-- value of it holds: the search for a constructor that can build one. Its
-- arguments' types are looked into only while they have fewer nodes, so the
-- search descends the nodes, whose accessibility it carries. Each search
-- takes the number of its first fresh name, `next`, and gives the number
-- past every fresh name it made, so no two fresh names of the whole search
-- are the same, and putting into a type what one stands for captures no
-- other.
mutual
  inhabitantsOf : {vars : _} ->
                  {auto c : Ref Ctxt Defs} ->
                  Defs -> Env Term vars -> (next : Int) ->
                  (nfty : NF vars) -> (0 _ : OfFamily nfty) ->
                  (nodes : Nat) -> (0 _ : Accessible LT nodes) ->
                  Core (Inhabitants vars, Int)
  inhabitantsOf defs env next nfty@(NTCon _ n _ _) _ nodes acc
      = do Just nty <- lookupDefExact n (gamma defs)
             | _ => pure (Holding [], next)
           case nty of
                TCon _ _ _ flags _ (Just cons) _
                     => if not (external flags)
                           then byConstructors defs env next nfty nodes acc cons
                           else pure (Holding [], next)
                _ => pure (Holding [], next)

  -- A type with one constructor holds what that constructor holds of it
  -- when it builds a value; with more, a value is built by any one of them,
  -- and what one holds another need not, so the type holds nothing here.
  byConstructors : {vars : _} ->
                   {auto c : Ref Ctxt Defs} ->
                   Defs -> Env Term vars -> (next : Int) -> NF vars ->
                   (nodes : Nat) -> (0 _ : Accessible LT nodes) ->
                   List Name -> Core (Inhabitants vars, Int)
  byConstructors defs env next nfty nodes acc [con]
      = built defs env next nfty nodes acc con
  byConstructors defs env next nfty nodes acc cons
      = someBuilds defs env next nfty nodes acc cons

  -- Whether one of the constructors builds a value of the type.
  someBuilds : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               Defs -> Env Term vars -> (next : Int) -> NF vars ->
               (nodes : Nat) -> (0 _ : Accessible LT nodes) ->
               List Name -> Core (Inhabitants vars, Int)
  someBuilds defs env next nfty nodes acc [] = pure (NoValue, next)
  someBuilds defs env next nfty nodes acc (con :: cons)
      = do (NoValue, next) <- built defs env next nfty nodes acc con
             | (Holding _, next) => pure (Holding [], next)
           someBuilds defs env next nfty nodes acc cons

  -- What every value the constructor builds of the type holds, or that it
  -- builds none: its return type conflicts with the type, or one of its
  -- arguments' types is empty, as it is or read under what the others hold
  -- of the fresh names, each of which stands for one value of an argument.
  -- Only the arguments whose types name a fresh name so solved are read
  -- again, each still only while it has fewer nodes than the type.
  built : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          Defs -> Env Term vars -> (next : Int) -> NF vars ->
          (nodes : Nat) -> (0 _ : Accessible LT nodes) ->
          Name -> Core (Inhabitants vars, Int)
  built defs env next nfty nodes acc con
      = case !(fitting defs env next nfty con) of
             Conflicts => pure (NoValue, next)
             Fits argtys eqs next
                 => do (Holding held, next) <- argsHold defs env next nodes acc argtys
                         | (NoValue, next) => pure (NoValue, next)
                       let holds = eqs ++ held
                       let solved = forcedBy holds
                       (Holding _, next) <- argsHold defs env next nodes acc
                                              (map (substAll solved)
                                                   (filter (mentionsSolved solved) argtys))
                         | (NoValue, next) => pure (NoValue, next)
                       pure (Holding holds, next)

  -- What the values of the arguments hold together, or that they have none,
  -- one of their types being empty.
  argsHold : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             Defs -> Env Term vars -> (next : Int) ->
             (nodes : Nat) -> (0 _ : Accessible LT nodes) ->
             List (Term vars) -> Core (Inhabitants vars, Int)
  argsHold defs env next nodes acc [] = pure (Holding [], next)
  argsHold defs env next nodes acc (ty :: tys)
      = do (Holding eqs, next) <- argHolds defs env next nodes acc ty
             | (NoValue, next) => pure (NoValue, next)
           (held, next) <- argsHold defs env next nodes acc tys
           pure (holdingAlso eqs held, next)

  -- What the values of an argument's type hold, looked into only when the
  -- type has fewer nodes than the type it is an argument of: the search's
  -- bound, so that a family whose arguments do not get smaller is not taken
  -- apart again. The family is written out where it is used, not named by
  -- an as-pattern, since the case below is a function of its own that sees
  -- the name apart from what it matched.
  argHolds : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             Defs -> Env Term vars -> (next : Int) ->
             (nodes : Nat) -> (0 _ : Accessible LT nodes) ->
             Term vars -> Core (Inhabitants vars, Int)
  argHolds defs env next nodes (Access rec) ty
      = do NTCon nfc nn na nargs <- nf defs env ty
             | _ => pure (Holding [], next)
           argNodes <- termSize <$> quote defs env (NTCon nfc nn na nargs)
           case choose (argNodes < nodes) of
                Left lt => inhabitantsOf defs env next (NTCon nfc nn na nargs) FamilyApplied
                                         argNodes (rec argNodes (ltOpReflectsLT argNodes nodes lt))
                Right _ => pure (Holding [], next)

-- Return whether the given type is definitely empty: no constructor can
-- build a value of it, since its return type conflicts with the type, or
-- one of its arguments has a type which is itself empty there (a pair
-- whose second part is `0 = 1`; `LTE (S (S k)) (S Z)`, whose `LTESucc`
-- takes an `LTE (S k) Z`), or empty once read under what the others hold
-- of the arguments the type does not determine (a dependent pair `(ts **
-- (MkHead Nothing (y :: z) = MkHead Nothing ts, AllR [] ts))`, whose
-- equation holds `ts = y :: z`, under which its second part is empty). A
-- pattern variable of such a type is the evidence a missing case is
-- impossible, wherever in the variable's type the conflict is. An
-- argument's type is looked into only while it is smaller than the type it
-- is an argument of, so the search ends: a family whose arguments do not
-- get smaller, a stream with no end, is not taken apart again. A type that
-- is no family's has no constructor to try.
export
isEmpty : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          Defs -> Env Term vars -> NF vars -> Core Bool
isEmpty defs env nfty@(NTCon {})
    = do nodes <- termSize <$> quote defs env nfty
         (NoValue, _) <- inhabitantsOf defs env 0 nfty FamilyApplied nodes (wellFounded nodes)
           | (Holding _, _) => pure False
         pure True
isEmpty defs env _ = pure False

altMatch : CaseAlt vars -> CaseAlt vars -> Bool
altMatch _ (DefaultCase _) = True
altMatch (DelayCase _ _ t) (DelayCase _ _ t') = True
altMatch (ConCase n t _ _) (ConCase n' t' _ _) = t == t'
altMatch (ConstCase c _) (ConstCase c' _) = c == c'
altMatch _ _ = False

-- Given a type and a list of case alternatives, return the
-- well-typed alternatives which were *not* in the list
getMissingAlts : {auto c : Ref Ctxt Defs} ->
                 {vars : _} ->
                 FC -> Defs -> NF vars -> List (CaseAlt vars) ->
                 Core (List (CaseAlt vars))
-- If it's a primitive other than WorldVal, there's too many to reasonably
-- check, so require a catch all
getMissingAlts fc defs (NPrimVal _ $ PrT WorldType) alts
    = if isNil alts
         then pure [DefaultCase (Unmatched "Coverage check")]
         else pure []
getMissingAlts fc defs (NPrimVal _ c) alts
  = do log "coverage.missing" 50 $ "Looking for missing alts at type " ++ show c
       if any isDefault alts
         then do log "coverage.missing" 20 "Found default"
                 pure []
         else pure [DefaultCase (Unmatched "Coverage check")]
-- Similarly for types
getMissingAlts fc defs (NType {}) alts
    = do log "coverage.missing" 50 "Looking for missing alts at type Type"
         if any isDefault alts
           then do log "coverage.missing" 20 "Found default"
                   pure []
           else pure [DefaultCase (Unmatched "Coverage check")]
getMissingAlts fc defs nfty alts
    = do log "coverage.missing" 50 $ "Getting constructors for: " ++ show nfty
         logNF "coverage.missing" 20 "Getting constructors for" (mkEnv fc _) nfty
         allCons <- getCons defs nfty
         pure (filter (noneOf alts)
                 (map (mkAlt fc (Unmatched "Coverage check")) allCons))
  where
    -- Return whether the alternative c matches none of the given cases in alts
    noneOf : List (CaseAlt vars) -> CaseAlt vars -> Bool
    noneOf alts c = not $ any (altMatch c) alts

-- Mapping of variable to constructor tag already matched for it
KnownVars : Scope -> Type -> Type
KnownVars vars a = List (Var vars, a)

-- TODO re-use `Thinnable`
weakenNs : SizeOf args -> KnownVars vars a -> KnownVars (args ++ vars) a
weakenNs args [] = []
weakenNs args ((v, t) :: xs)
  = (weakenNs args v, t) :: weakenNs args xs

findTag : {idx, vars : _} ->
          (0 p : IsVar n idx vars) -> KnownVars vars a -> Maybe a
findTag v [] = Nothing
findTag v ((v', t) :: xs)
    = if MkVar v == v'
         then Just t
         else findTag v xs

addNot : {idx, vars : _} ->
         (0 p : IsVar n idx vars) -> Int -> KnownVars vars (List Int) ->
         KnownVars vars (List Int)
addNot v t [] = [(MkVar v, [t])]
addNot v t ((v', ts) :: xs)
    = if MkVar v == v'
         then ((v', t :: ts) :: xs)
         else ((v', ts) :: addNot v t xs)

tagIsNot : List Int -> CaseAlt vars -> Bool
tagIsNot ts (ConCase _ t' _ _) = not (t' `elem` ts)
tagIsNot ts (ConstCase {}) = True
tagIsNot ts (DelayCase {}) = True
tagIsNot ts (DefaultCase _) = False

-- Replace a default case with explicit branches for the constructors.
-- This is easier than checking whether a default is needed when traversing
-- the tree (just one constructor lookup up front).
replaceDefaults : {auto c : Ref Ctxt Defs} ->
                  {vars : _} ->
                  FC -> Defs -> NF vars -> List (CaseAlt vars) ->
                  Core (List (CaseAlt vars))
-- Leave it alone if it's a primitive type though, since we need the catch
-- all case there
replaceDefaults fc defs (NPrimVal {}) cs = pure cs
replaceDefaults fc defs (NType {}) cs = pure cs
replaceDefaults fc defs nfty cs
    = do cs' <- traverse rep cs
         pure (dropRep (concat cs'))
  where
    rep : CaseAlt vars -> Core (List (CaseAlt vars))
    rep (DefaultCase sc)
        = do allCons <- getCons defs nfty
             pure (map (mkAlt fc sc) allCons)
    rep c = pure [c]

    dropRep : List (CaseAlt vars) -> List (CaseAlt vars)
    dropRep [] = []
    dropRep (c@(ConCase n t args sc) :: rest)
          -- assumption is that there's no defaultcase in 'rest' because
          -- we've just removed it
        = c :: dropRep (filter (not . tagIs t) rest)
    dropRep (c :: rest) = c :: dropRep rest

-- What the walk of a case tree has built of the function's arguments: a
-- pattern variable, which a split refines; a constructor applied to its
-- parts; a delay of its type and its value; a constant. A split builds only
-- these, so the walk holds no other term.
data Built : Type where
     Unsplit : Name -> Built
     ConApplied : (con : Name) -> (tag : Int) -> (parts : List Built) -> Built
     DelayBuilt : (ty : Built) -> (arg : Built) -> Built
     ConstBuilt : Constant -> Built

-- A pattern with the pattern variable `x` replaced by what a split refined
-- it to.
mutual
  total
  refineBuilt : (x : Name) -> Built -> Built -> Built
  refineBuilt x pat (Unsplit y) = if x == y then pat else Unsplit y
  refineBuilt x pat (ConApplied n t parts) = ConApplied n t (refineParts x pat parts)
  refineBuilt x pat (DelayBuilt ty arg)
      = DelayBuilt (refineBuilt x pat ty) (refineBuilt x pat arg)
  refineBuilt x pat (ConstBuilt c) = ConstBuilt c

  total
  refineParts : (x : Name) -> Built -> List Built -> List Built
  refineParts x pat [] = []
  refineParts x pat (b :: bs) = refineBuilt x pat b :: refineParts x pat bs

-- The pattern a clause would write for what the walk built: a pattern
-- variable is a bound name, and a delay is a written `Delay`, whatever the
-- clauses that made the tree wrote, which the tree does not keep and
-- matching does not compare.
mutual
  total
  builtTerm : FC -> Built -> ClosedTerm
  builtTerm fc (Unsplit x) = Ref fc Bound x
  builtTerm fc (ConApplied n t parts)
      = apply fc (Ref fc (DataCon t (length parts)) n) (builtTerms fc parts)
  builtTerm fc (DelayBuilt ty arg)
      = TDelay fc (MkDelaying LUnknown InSource) (builtTerm fc ty) (builtTerm fc arg)
  builtTerm fc (ConstBuilt c) = PrimVal fc c

  total
  builtTerms : FC -> List Built -> List ClosedTerm
  builtTerms fc [] = []
  builtTerms fc (b :: bs) = builtTerm fc b :: builtTerms fc bs

-- What the walk has built of each of the function's arguments.
data Patterns : Scope -> Type where
     Nil : Patterns []
     (::) : Built -> Patterns vs -> Patterns (v :: vs)

-- What each variable of a case tree's scope stands for in what the walk has
-- built of the function's arguments, `outer`: an argument's own pattern, or,
-- for a variable a split binds inside them, the part of a pattern it binds.
-- A tree splits a variable again below a split of it (the tree of a default
-- repeats the split), binding its arguments under new names, and a split of
-- one of those refines what the first split found; what each variable
-- stands for is what joins the two.
data Standing : (outer : Scope) -> (vars : Scope) -> Type where
     Arguments : Patterns outer -> Standing outer outer
     Inside : Built -> Standing outer vars -> Standing outer (v :: vars)

-- Each argument stands for itself until a split refines it.
total
unsplit : (vs : Scope) -> Patterns vs
unsplit [] = []
unsplit (v :: vs) = Unsplit v :: unsplit vs

total
patternAt : {idx : Nat} -> (0 _ : IsVar n idx vs) -> Patterns vs -> Built
patternAt First (b :: _) = b
patternAt (Later el) (_ :: bs) = patternAt el bs

total
standsFor : {idx : Nat} -> (0 _ : IsVar n idx vars) -> Standing outer vars -> Built
standsFor el (Arguments bs) = patternAt el bs
standsFor First (Inside b _) = b
standsFor (Later el) (Inside _ s) = standsFor el s

total
patternList : Patterns vs -> List Built
patternList [] = []
patternList (b :: bs) = b :: patternList bs

total
argumentsOf : Standing outer vars -> List Built
argumentsOf (Arguments bs) = patternList bs
argumentsOf (Inside _ s) = argumentsOf s

-- Everything the walk has built with the pattern variable `x` refined: what
-- each variable stands for, the arguments' patterns among it.
total
refinePatterns : (x : Name) -> Built -> Patterns vs -> Patterns vs
refinePatterns x pat [] = []
refinePatterns x pat (b :: bs) = refineBuilt x pat b :: refinePatterns x pat bs

total
refineStanding : (x : Name) -> Built -> Standing outer vars -> Standing outer vars
refineStanding x pat (Arguments bs) = Arguments (refinePatterns x pat bs)
refineStanding x pat (Inside b s) = Inside (refineBuilt x pat b) (refineStanding x pat s)

-- A split's arguments, each standing for the part given for it, in order:
-- a repeated split gives the parts of the pattern the first split built,
-- one per argument of the same constructor. An argument no part is given
-- for stands for itself, as every variable does until a split refines it.
total
bindParts : (as : List Name) -> List Built -> Standing outer vars -> Standing outer (as ++ vars)
bindParts [] _ s = s
bindParts (a :: as) (p :: ps) s = Inside p (bindParts as ps s)
bindParts (a :: as) [] s = Inside (Unsplit a) (bindParts as [] s)

-- The pattern variable of a split's argument, numbered `i`. The patterns
-- give each split's arguments names of their own, since the alternatives
-- that stand for a default all name theirs alike, and print them `m`, as
-- those are printed.
total
freshPart : Int -> Built
freshPart i = Unsplit (MN (known Km) i)

-- A split's arguments as fresh pattern variables numbered from `next`, and
-- the next number.
total
freshParts : (as : List Name) -> (next : Int) -> (List Built, Int)
freshParts [] next = ([], next)
freshParts (_ :: as) next
    = let (parts, next') = freshParts as (next + 1) in
          (freshPart next :: parts, next')

-- Whether a pattern's constructor is an alternative's: a tag tells data
-- constructors apart; type constructors, which all have tag 0, by their
-- names, resolved or not.
sameCon : {auto c : Ref Ctxt Defs} -> (Name, Int) -> (Name, Int) -> Core Bool
sameCon (n, t) (n', t')
    = if t /= t'
         then pure False
         else if n == n'
                 then pure True
                 else do full <- getFullName n
                         full' <- getFullName n'
                         pure (full == full')

-- Traverse a case tree and refine the arguments while matching, so that
-- when we reach a leaf we know what patterns were used to get there,
-- and return those patterns.
-- The returned patterns are those arising from the *missing* cases.
-- A split of a variable that stands for a pattern variable refines it,
-- throughout what the walk has built; a split of one that stands for what a
-- split further up built is taken only by the alternative of that
-- constructor, delay or constant, and binds its arguments to the parts the
-- first split built.
buildArgs : {auto c : Ref Ctxt Defs} ->
            {vars : _} ->
            FC -> Defs ->
            KnownVars vars Int -> -- Things which have definitely match
            KnownVars vars (List Int) -> -- Things an argument *can't* be
                                    -- (because a previous case matches)
            (next : Int) -> -- the number of the next pattern variable a
                            -- split names
            Standing outer vars -> CaseTree vars -> Core (List (List ClosedTerm))
buildArgs fc defs known not next standing cs@(Case idx el ty altsIn)
  -- If we've already matched on 'el' in this branch, restrict the alternatives
  -- to the tag we already know. Otherwise, add missing cases and filter out
  -- the ones it can't possibly be (the 'not') because a previous case
  -- has matched.
    = do let fenv = mkEnv fc _
         nfty <- nf defs fenv ty
         alts <- replaceDefaults fc defs nfty altsIn
         let alts' = alts ++ !(getMissingAlts fc defs nfty alts)
         let altsK = maybe alts' (\t => filter (tagIs t) alts')
                              (findTag el known)
         let altsN = maybe altsK (\ts => filter (tagIsNot ts) altsK)
                              (findTag el not)
         buildArgsAlt not altsN
  where
    buildArgAlt : KnownVars vars (List Int) ->
                  CaseAlt vars -> Core (List (List ClosedTerm))
    buildArgAlt not' (ConCase n t args sc)
        = do let l = mkSizeOf args
             case standsFor el standing of
                  Unsplit x =>
                     do let (parts, next') = freshParts args next
                        buildArgs fc defs (weakenNs l ((MkVar el, t) :: known))
                                  (weakenNs l not') next'
                                  (refineStanding x (ConApplied n t parts)
                                                  (bindParts args parts standing))
                                  sc
                  ConApplied n' t' parts =>
                     do same <- sameCon (n, t) (n', t')
                        if same
                           then buildArgs fc defs (weakenNs l ((MkVar el, t) :: known))
                                          (weakenNs l not') next
                                          (bindParts args parts standing) sc
                           else pure []
                  -- A delay or a constant, which no constructor's
                  -- alternative matches.
                  DelayBuilt {} => pure []
                  ConstBuilt {} => pure []
    buildArgAlt not' (DelayCase t a sc)
        = let l = mkSizeOf [t, a] in
              case standsFor el standing of
                   Unsplit x =>
                      let tyPart = freshPart next
                          argPart = freshPart (next + 1) in
                          buildArgs fc defs (weakenNs l known) (weakenNs l not')
                                    (next + 2)
                                    (refineStanding x (DelayBuilt tyPart argPart)
                                                    (bindParts [t, a] [tyPart, argPart] standing))
                                    sc
                   DelayBuilt tyPart argPart =>
                      buildArgs fc defs (weakenNs l known) (weakenNs l not') next
                                (bindParts [t, a] [tyPart, argPart] standing) sc
                   -- A constructor or a constant, which no delay is.
                   ConApplied {} => pure []
                   ConstBuilt {} => pure []
    buildArgAlt not' (ConstCase c sc)
        = case standsFor el standing of
               Unsplit x =>
                  buildArgs fc defs known not' next
                            (refineStanding x (ConstBuilt c) standing) sc
               ConstBuilt c' =>
                  if c == c'
                     then buildArgs fc defs known not' next standing sc
                     else pure []
               -- A constructor or a delay, which no constant is.
               ConApplied {} => pure []
               DelayBuilt {} => pure []
    buildArgAlt not' (DefaultCase sc)
        = buildArgs fc defs known not' next standing sc

    buildArgsAlt : KnownVars vars (List Int) -> List (CaseAlt vars) ->
                   Core (List (List ClosedTerm))
    buildArgsAlt not' [] = pure []
    buildArgsAlt not' (c@(ConCase _ t _ _) :: cs)
        = pure $ !(buildArgAlt not' c) ++
                 !(buildArgsAlt (addNot el t not') cs)
    buildArgsAlt not' (c :: cs)
        = pure $ !(buildArgAlt not' c) ++ !(buildArgsAlt not' cs)

buildArgs fc defs known not next standing (STerm _ vs)
    = pure [] -- matched, so return nothing
buildArgs fc defs known not next standing (Unmatched msg)
    = pure [builtTerms fc (argumentsOf standing)] -- unmatched, so return it
buildArgs fc defs known not next standing Impossible
    = pure [] -- not a possible match, so return nothing

-- Traverse a case tree and return pattern clauses which are not
-- matched. These might still be invalid patterns, or patterns which are covered
-- elsewhere (turning up due to overlapping clauses) so the results should be
-- checked
export
getMissing : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             FC -> Name -> ClosedTerm ->
             CaseTree vars ->
             Core (List ClosedTerm)
getMissing fc n ty ctree
   = do defs <- get Ctxt
        pats <- buildArgs fc defs [] [] 0 (Arguments (unsplit vars)) ctree
        pats <- for pats $ trimArgs defs [<] !(nf defs Env.empty ty)
        unless (null pats) $
          logC "coverage.missing" 20 $ map unlines $
            for pats $ map show . traverse toFullNames
        pure (map (apply fc (Ref fc Func n)) pats)
  where
    trimArgs : Defs ->
               SnocList ClosedTerm -> ClosedNF ->
               List ClosedTerm -> Core (List ClosedTerm)
    trimArgs defs acc (NBind _ n (Pi {}) sc) (x :: xs)
        = trimArgs defs (acc :< x) !(sc defs $ toClosure defaultOpts Env.empty x) xs
    trimArgs _ acc _ _ = pure $ toList acc

-- For the given name, get the names it refers to which are not themselves
-- covering.
-- Also need to go recursively into case blocks, since we only calculate
-- references for them at the top level clause
export
getNonCoveringRefs : {auto c : Ref Ctxt Defs} ->
                     FC -> Name -> Core (List Name)
getNonCoveringRefs fc n
   = do defs <- get Ctxt
        Just d <- lookupCtxtExact n (gamma defs)
           | Nothing => undefinedName fc n
        let ds = mapMaybe noAssert (toList (refersTo d))
        let cases = filter isCase !(traverse toFullNames ds)

        -- Case blocks aren't recursive, so we're safe!
        cbad <- traverse (getNonCoveringRefs fc) cases
        topbad <- filterM (notCovering defs) ds
        pure (topbad ++ concat cbad)
  where
    isCase : Name -> Bool
    isCase (NS _ n) = isCase n
    isCase (CaseBlock {}) = True
    isCase _ = False

    noAssert : (Name, Bool) -> Maybe Name
    noAssert (n, True) = Nothing
    noAssert (n, False) = Just n

    notCovering : Defs -> Name -> Core Bool
    notCovering defs n
        = case !(lookupCtxtExact n (gamma defs)) of
               Just def => case isCovering (totality def) of
                                IsCovering => pure False
                                _ => pure True
               _ => pure False

-- Does the second term match against the first?
-- 'Erased' matches against anything, we assume that's a Rig0 argument that
-- we don't care about
match : Term vs -> Term vs -> Bool
match (Local _ _ i _) _ = True
match (Ref _ Bound n) _ = True
match (Ref _ _ n) (Ref _ _ n') = n == n'
match (App _ f a) (App _ f' a') = match f f' && match a a'
match (As _ _ _ p) (As _ _ _ p') = match p p'
match (As _ _ _ p) p' = match p p'
match (TDelayed _ _ t) (TDelayed _ _ t') = match t t'
match (TDelay _ _ _ t) (TDelay _ _ _ t') = match t t'
match (TForce _ _ t) (TForce _ _ t') = match t t'
match (PrimVal _ c) (PrimVal _ c') = c == c'
match (Erased _ (Dotted t)) u = match t u
match t (Erased _ (Dotted u)) = match t u
match (Erased {}) _ = True
match _ (Erased {}) = True
match (TType {}) (TType {}) = True
match _ _ = False

-- Erase according to argument position
eraseApps : {auto c : Ref Ctxt Defs} ->
            Term vs -> Core (Term vs)
eraseApps {vs} tm
    = case getFnArgs tm of
           (Ref fc Bound n, args) =>
                do args' <- traverse eraseApps args
                   pure (apply fc (Ref fc Bound n) args')
           (Ref fc nt n, args) =>
                do defs <- get Ctxt
                   mgdef <- lookupCtxtExact n (gamma defs)
                   let eargs = maybe NatSet.empty eraseArgs mgdef
                   args' <- traverse eraseApps (NatSet.overwrite (Erased fc Placeholder) eargs args)
                   pure (apply fc (Ref fc nt n) args')
           (tm, args) =>
                do args' <- traverse eraseApps args
                   pure (apply (getLoc tm) tm args')

-- if tm would be matched by trylhs, then it's not an impossible case
-- because we've already got it. Ignore anything in erased position.
clauseMatches : {vars : _} ->
                {auto c : Ref Ctxt Defs} ->
                (erase : Bool) -> Env Term vars -> Term vars ->
                ClosedTerm -> Core Bool
clauseMatches erase env tm trylhs
    = do let lhs = close (getLoc tm) (known Kcov) env tm
         lhs <- if erase
                   then eraseApps lhs
                   else pure lhs
         pure $ match !(toResolvedNames lhs) !(toResolvedNames trylhs)

export
checkMatched : {auto c : Ref Ctxt Defs} ->
               (erase : Bool) -> List Clause -> ClosedTerm -> Core (Maybe ClosedTerm)
checkMatched erase cs ulhs
    = do logTerm "coverage" 5 "Checking coverage for" ulhs
         logC "coverage" 10 $ pure $ "(raw term: " ++ show !(toFullNames ulhs) ++ ")"
         ulhs <- if erase
                    then do ulhs <- eraseApps ulhs
                            logTerm "coverage" 5 "Erased to" ulhs
                            pure ulhs
                    else pure ulhs
         logC "coverage" 5 $ do
            cs <- traverse toFullNames cs
            pure $ "Against clauses:\n" ++
                   (show $ indent 2 $ vcat $ map (pretty . show) cs)
         tryClauses cs ulhs
  where
    tryClauses : List Clause -> ClosedTerm -> Core (Maybe ClosedTerm)
    tryClauses [] ulhs
        = do logTermNF "coverage" 10 "Nothing matches" Env.empty ulhs
             pure $ Just ulhs
    tryClauses (MkClause env lhs _ _ :: cs) ulhs
        = if !(clauseMatches erase env lhs ulhs)
             then do logTermNF "coverage" 10 "Yes" env lhs
                     pure Nothing -- something matches, discared it
             else do logTermNF "coverage" 10 "No match" env lhs
                     tryClauses cs ulhs
