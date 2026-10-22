-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Case.CaseBuilder

import Core.Case.CaseTree
import Core.Case.Util
import Core.Context.Log
import Core.Env
import Core.Normalise
import Core.Options
import Core.Value

import Idris.Pretty.Annotations

import Data.DPair
import Data.List.Quantifiers
import Data.SortedSet
import Data.String
import Data.Vect
import Libraries.Data.IMaybe
import Libraries.Data.List.SizeOf
import Libraries.Data.List.LengthMatch
import Libraries.Data.List01
import Libraries.Data.List01.Quantifiers
import Libraries.Data.VarSet

import Decidable.Equality

import Libraries.Text.PrettyPrint.Prettyprinter

%default covering

%hide Symbols.equals

||| The name a case tree gives the alternative of a function type: the
||| type constructor `->`, applied to its domain and codomain.
export
arrowConName : Name
arrowConName = knownUN KArrow

-- The tree built is the compile-time tree of a definition of this
-- multiplicity: the one the frontend translates, and Idris's checks read.
-- Upstream built a second, for run time, with erasure and its rewrites
-- applied, for back ends this compiler does not have.
public export
data Phase = CompileTime RigCount

Eq Phase where
  CompileTime r == CompileTime r' = r == r'

data ArgType : Scoped where
     Known : RigCount -> (ty : Term vars) -> ArgType vars -- arg has type 'ty'
     Stuck : (fty : Term vars) -> ArgType vars
         -- ^ arg will have argument type of 'fty' when we know enough to
         -- calculate it
     Unknown : ArgType vars
         -- arg's type is not yet known due to a previously stuck argument

HasNames (ArgType vars) where
  full gam (Known c ty) = Known c <$> full gam ty
  full gam (Stuck ty) = Stuck <$> full gam ty
  full gam Unknown = pure Unknown

  resolved gam (Known c ty) = Known c <$> resolved gam ty
  resolved gam (Stuck ty) = Stuck <$> resolved gam ty
  resolved gam Unknown = pure Unknown

covering
{ns : _} -> Show (ArgType ns) where
  show (Known c t) = "Known " ++ show c ++ " " ++ show t
  show (Stuck t) = "Stuck " ++ show t
  show Unknown = "Unknown"

-- Where a clause's pattern on a column comes from: the clause wrote it, or
-- unification found it from the patterns the clause wrote. The latter is
-- the elaborator's as-pattern for an argument the clause leaves to
-- unification (an implicit of the definition or of a constructor in a
-- pattern that it leaves out, a case block's environment, a with block's
-- argument), and every part of such a pattern once the tree splits it.
data Source = Written | Unified

-- The source of a pattern on a column made from a pattern of source `s`:
-- what unification found stays found, and an as-pattern whose name
-- `unified` holds is found. A column's source is read once, when the column
-- is made, so it holds as the tree takes the column's as-patterns off.
sourceOf : (unified : List Name) -> Source -> Pat -> Source
sourceOf unified s (PAs _ n p)
    = if n `elem` unified then Unified else sourceOf unified s p
sourceOf unified s _ = s

record PatInfo (pvar : Name) (vars : Scope) where
  constructor MkInfo
  {idx : Nat}
  {name : Name}
  pat : Pat
  0 loc : IsVar name idx vars
  argType : ArgType vars -- Type of the argument being inspected (i.e.
                         -- *not* refined by this particular pattern)
  source : Source

covering
{vars : _} -> Show (PatInfo n vars) where
  show pi = show (pat pi) ++ " : " ++ show (argType pi)

HasNames (PatInfo n vars) where
  full gam (MkInfo pat loc argType source)
     = do pat <- full gam pat
          argType <- full gam argType
          pure $ MkInfo pat loc argType source

  resolved gam (MkInfo pat loc argType source)
     = do pat <- resolved gam pat
          argType <- resolved gam argType
          pure $ MkInfo pat loc argType source

{-
NamedPats is a list of patterns on the LHS of a clause. Each entry in
the list gives a pattern, and a proof that there is a variable we can
inspect to see if it matches the pattern.

A definition consists of a list of clauses, which are a 'NamedPats' and
a term on the RHS. There is an assumption that corresponding positions in
NamedPats always have the same 'Elem' proof, though this isn't expressed in
a type anywhere.
-}

data NamedPats : List Name -> -- the pattern variables still to process, in order
                 Scoped where
     Nil : NamedPats [] vars
     (::) : PatInfo pvar vars ->
            -- ^ a pattern, where its variable appears in the vars list,
            -- and its type. The type has no variable names; any names it
            -- refers to are explicit
            NamedPats ns vars -> NamedPats (pvar :: ns) vars

getPatInfo : NamedPats todo vars -> List Pat
getPatInfo [] = []
getPatInfo (x :: xs) = pat x :: getPatInfo xs

updatePats : {vars, todo : _} ->
             {auto c : Ref Ctxt Defs} ->
             Env Term vars ->
             NF vars -> NamedPats todo vars -> Core (NamedPats todo vars)
updatePats env nf [] = pure []
updatePats {todo = pvar :: ns} env (NBind fc _ (Pi _ c _ farg) fsc) (p :: ps)
  = case argType p of
         Unknown =>
            do defs <- get Ctxt
               empty <- clearDefs defs
               pure ({ argType := Known c !(quote empty env farg) } p
                          :: !(updatePats env !(fsc defs (toClosure defaultOpts env (Ref fc Bound pvar))) ps))
         _ => pure (p :: ps)
updatePats env nf (p :: ps)
  = case argType p of
         Unknown =>
            do defs <- get Ctxt
               empty <- clearDefs defs
               pure ({ argType := Stuck !(quote empty env nf) } p :: ps)
         _ => pure (p :: ps)

substInPatInfo : {pvar, vars, todo : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 FC -> Name -> Term vars -> PatInfo pvar vars ->
                 NamedPats todo vars ->
                 Core (PatInfo pvar vars, NamedPats todo vars)
substInPatInfo fc n tm p ps
    = case argType p of
           Known c ty =>
                do defs <- get Ctxt
                   tynf <- nf defs (mkEnv fc vars) ty
                   case tynf of
                        NApp {} =>
                           pure ({ argType := Known c (substName n tm ty) } p, ps)
                        -- Got a concrete type, and that's all we need, so stop
                        _ => pure (p, ps)
           Stuck fty =>
             do defs <- get Ctxt
                empty <- clearDefs defs
                let env = mkEnv fc vars
                case !(nf defs env (substName n tm fty)) of
                     NBind pfc _ (Pi _ c _ farg) fsc =>
                       pure ({ argType := Known c !(quote empty env farg) } p,
                                 !(updatePats env
                                       !(fsc defs (toClosure defaultOpts env
                                             (Ref pfc Bound pvar))) ps))
                     _ => pure (p, ps)
           Unknown => pure (p, ps)

-- Substitute the name with a term in the pattern types, and reduce further
-- (this aims to resolve any 'Stuck' pattern types)
substInPats : {vars, todo : _} ->
              {auto c : Ref Ctxt Defs} ->
              FC -> Name -> Term vars -> NamedPats todo vars ->
              Core (NamedPats todo vars)
substInPats fc n tm [] = pure []
substInPats fc n tm (p :: ps)
    = do (p', ps') <- substInPatInfo fc n tm p ps
         pure (p' :: !(substInPats fc n tm ps'))

getPat : {idx : Nat} ->
         (0 el : IsVar nm idx ps) -> NamedPats ps ns -> PatInfo nm ns
getPat First (x :: xs) = x
getPat (Later p) (x :: xs) = getPat p xs

dropPat : {idx : Nat} ->
          (0 el : IsVar nm idx ps) ->
          NamedPats ps ns -> NamedPats (dropIsVar ps el) ns
dropPat First (x :: xs) = xs
dropPat (Later p) (x :: xs) = x :: dropPat p xs

HasNames (NamedPats todo vars) where
  full gam [] = pure []
  full gam (x::xs) = [| (::) (full gam x) (full gam xs) |]

  resolved gam [] = pure []
  resolved gam (x::xs) = [| (::) (resolved gam x) (resolved gam xs) |]

covering
{vars : _} -> {todo : _} -> Show (NamedPats todo vars) where
  show xs = "[" ++ showAll xs ++ "]"
    where
      showAll : {vs, ts : _} -> NamedPats ts vs -> String
      showAll [] = ""
      showAll {ts = t :: _} [x]
          = show t ++ " " ++ show (pat x) ++ " [" ++ show (argType x) ++ "]"
      showAll {ts = t :: _} (x :: xs)
          = show t ++ " " ++ show (pat x) ++ " [" ++ show (argType x) ++ "]"
                     ++ ", " ++ showAll xs

{vars : _} -> {todo : _} -> Pretty IdrisSyntax (NamedPats todo vars) where
  pretty xs = hsep $ prettyAll xs
    where
      prettyAll : {vs, ts : _} -> NamedPats ts vs -> List (Doc IdrisSyntax)
      prettyAll [] = []
      prettyAll {ts = t :: _} (x :: xs)
          = parens (pretty0 t <++> equals <++> pretty (pat x))
          :: prettyAll xs

Weaken ArgType where
  weaken (Known c ty) = Known c (weaken ty)
  weaken (Stuck fty) = Stuck (weaken fty)
  weaken Unknown = Unknown

  weakenNs s (Known c ty) = Known c (weakenNs s ty)
  weakenNs s (Stuck fty) = Stuck (weakenNs s fty)
  weakenNs s Unknown = Unknown

Weaken (PatInfo p) where
  weakenNs s (MkInfo p el fty src) = MkInfo p (weakenIsVar s el) (weakenNs s fty) src

Weaken (NamedPats todo) where
  weaken [] = []
  weaken (p :: ps) = weaken p :: weaken ps

  weakenNs ns [] = []
  weakenNs ns (p :: ps) = weakenNs ns p :: weakenNs ns ps

(++) : NamedPats ms vars -> NamedPats ns vars -> NamedPats (ms ++ ns) vars
(++) [] ys = ys
(++) (x :: xs) ys = x :: xs ++ ys

tail : NamedPats (p :: ps) vars -> NamedPats ps vars
tail (x :: xs) = xs

-- The clause a row of the match comes from, which every copy of the row
-- carries through the splits: its place among the clauses, which its leaf
-- names, and the names of the arguments it leaves to unification
-- (`Clause`'s `unified`), which the tree splits after the others
-- (`arrange`).
record Origin where
  constructor MkOrigin
  index : Int
  unified : List Name

data PatClause : (todo : List Name) -> Scoped where
     MkPatClause : List Name -> -- names matched so far (from original lhs)
                   NamedPats todo vars ->
                   Origin -> (rhs : Term vars) -> PatClause todo vars

getNPs : PatClause todo vars -> NamedPats todo vars
getNPs (MkPatClause _ lhs pid rhs) = lhs

covering
{vars : _} -> {todo : _} -> Show (PatClause todo vars) where
  show (MkPatClause _ ps pid rhs)
     = show ps ++ " => " ++ show rhs

{vars : _} -> {todo : _} -> Pretty IdrisSyntax (PatClause todo vars) where
  pretty (MkPatClause _ ps _ rhs)
     = pretty ps <++> fatArrow <++> byShow rhs

HasNames (PatClause todo vars) where
  full gam (MkPatClause ns nps i rhs)
     = [| MkPatClause (traverse (full gam) ns) (full gam nps) (pure i) (full gam rhs) |]

  resolved gam (MkPatClause ns nps i rhs)
     = [| MkPatClause (traverse (resolved gam) ns) (resolved gam nps) (pure i) (resolved gam rhs) |]

0 IsConClause : PatClause (a :: todo) vars -> Type
IsConClause (MkPatClause _ (MkInfo pat _ _ _ :: _) _ _) = IsConPat pat

substInClause : {a, vars, todo : _} ->
                {auto c : Ref Ctxt Defs} ->
                FC -> Subset (PatClause (a :: todo) vars) IsConClause ->
                Core (Subset (PatClause (a :: todo) vars) IsConClause)
substInClause fc (Element (MkPatClause pvars (MkInfo pat pprf fty src :: pats) pid rhs) isCons)
    = do pats' <- substInPats fc a (mkTerm vars pat) pats
         pure $ Element (MkPatClause pvars (MkInfo pat pprf fty src :: pats') pid rhs) isCons

data Partitions : List01 ne (PatClause (a :: todo) vars) -> Type where
     ConClauses : {a, todo, vars : _} ->
                  {ps : List01 ne   (PatClause (a :: todo) vars)} ->
                  (cs : List01 True (PatClause (a :: todo) vars )) ->
                  (0 isCons : All IsConClause cs) =>
                  Partitions ps -> Partitions (cs ++ ps)
     VarClauses : {a, todo, vars : _} ->
                  {ps : List01 ne   (PatClause (a :: todo) vars)} ->
                  (vs : List01 True (PatClause (a :: todo) vars)) ->
                  Partitions ps -> Partitions (vs ++ ps)
     NoClauses : Partitions []

covering
{ps : _} -> Show (Partitions ps) where
  show (ConClauses cs rest)
    = unlines ("CON" :: map (("  " ++) . show) (forget cs))
    ++ "\n, " ++ show rest
  show (VarClauses vs rest)
    = unlines ("VAR" :: map (("  " ++) . show) (forget vs))
    ++ "\n, " ++ show rest
  show NoClauses = "NONE"

-- What a clause does with a column, least first: binds it to a variable;
-- binds it to what unification found from the patterns the clause writes
-- (`Unified`); or tests it.
data Use = Binds | Fixed | Tests

-- What two clauses together do with an argument: the more of the two.
both : Use -> Use -> Use
both Tests _ = Tests
both _ Tests = Tests
both Fixed _ = Fixed
both _ Fixed = Fixed
both Binds Binds = Binds

-- What a clause does with a column, by its pattern there and where the
-- pattern comes from. A pattern the tree cannot split binds.
use : Source -> Pat -> Use
use src (PAs _ _ p) = use src p
use src (PLoc {}) = Binds
use src (PUnmatchable {}) = Binds
use Written _ = Tests
use Unified _ = Fixed

data ClauseType : PatClause (a :: todo) vars -> Type where
     ConClause : (0 isCon : IsConClause p) => ClauseType p
     VarClause : ClauseType p

namesIn : List Name -> Pat -> Bool
namesIn pvars (PAs _ n p) = (n `elem` pvars) && namesIn pvars p
namesIn pvars (PCon _ _ _ _ ps) = all (namesIn pvars) ps
namesIn pvars (PTyCon _ _ _ ps) = all (namesIn pvars) ps
namesIn pvars (PArrow _ _ s t) = namesIn pvars s && namesIn pvars t
namesIn pvars (PDelay _ _ t p) = namesIn pvars t && namesIn pvars p
namesIn pvars (PLoc _ n) = n `elem` pvars
namesIn pvars _ = True

namesFrom : Pat -> List Name
namesFrom (PAs _ n p) = n :: namesFrom p
namesFrom (PCon _ _ _ _ ps) = concatMap namesFrom ps
namesFrom (PTyCon _ _ _ ps) = concatMap namesFrom ps
namesFrom (PArrow _ _ s t) = namesFrom s ++ namesFrom t
namesFrom (PDelay _ _ t p) = namesFrom t ++ namesFrom p
namesFrom (PLoc _ n) = [n]
namesFrom _ = []

clauseType : Phase -> (p : PatClause (a :: as) vars) -> ClauseType p
-- If it's irrelevant, a constructor, and there's no names we haven't seen yet
-- and don't see later, treat it as a variable
-- Or, if it's an under-applied constructor then do NOT attempt to split on it!
clauseType phase (MkPatClause pvars (MkInfo arg _ ty src :: rest) pid rhs)
    = maybe VarClause (\isCon => ConClause @{isCon}) $ getClauseType phase arg ty
  where
    -- At quantity 0 a pattern a clause writes on an erased argument is a
    -- match, a constant or a type as much as a constructor (below): nothing
    -- there was made must-unify. What unification fixed there stays a
    -- variable, unless it is a constructor: a type it solved (the `a` of
    -- `[] {a}`) is the only one the argument's type allows.
    matchesErased : Phase -> Source -> Bool
    matchesErased (CompileTime cr) Written = isErased cr
    matchesErased (CompileTime cr) _ = False

    -- used when we are tempted to split on a constructor: is
    -- this actually a fully applied one?
    splitCon : Nat -> List Pat -> Maybe (So True)
    splitCon arity xs = toMaybe (arity == length xs) Oh

    -- used to get the remaining clause types
    clauseType' : (p : Pat) -> Maybe (IsConPat p)
    clauseType' (PCon _ _ _ a xs) = splitCon a xs
    clauseType' (PTyCon _ _ a xs) = splitCon a xs
    clauseType' (PConst _ x)      = Just Oh
    clauseType' (PArrow _ _ s t)  = Just Oh
    clauseType' (PDelay {})       = Just Oh
    clauseType' _                 = Nothing

    getClauseType : Phase -> (p : Pat) -> ArgType vars -> Maybe (IsConPat p)
    getClauseType (CompileTime cr) (PCon _ _ _ a xs) (Known r t)
        = if (isErased r && not (isErased cr) &&
             all (namesIn (pvars ++ concatMap namesFrom (getPatInfo rest))) xs)
             then Nothing
             else splitCon a xs
    getClauseType phase (PAs _ _ p) t = getClauseType phase p t
    getClauseType phase l (Known r t) = if isErased r && not (matchesErased phase src)
      then Nothing
      else clauseType' l
    getClauseType phase l _ = clauseType' l

partition : {a, as, vars : _} ->
            Phase -> (ps : List01 ne (PatClause (a :: as) vars)) -> Partitions ps
partition phase [] = NoClauses
partition phase (x :: xs) with (partition phase xs)
  partition phase (x :: .(cs ++ ps)) | (ConClauses cs rest)
        = case clauseType phase x of
               ConClause => ConClauses (x :: cs) rest
               VarClause => VarClauses [x] (ConClauses cs rest)
  partition phase (x :: .(vs ++ ps)) | (VarClauses vs rest)
        = case clauseType phase x of
               ConClause => ConClauses [x] (VarClauses vs rest)
               VarClause => VarClauses (x :: vs) rest
  partition phase [x] | NoClauses
        = case clauseType phase x of
               ConClause => ConClauses [x] NoClauses
               VarClause => VarClauses [x] NoClauses

data ConType : Type where
     CName : Name -> (tag : Int) -> ConType
     CDelay : ConType
     CConst : Constant -> ConType

data Group : List Name -> -- pattern variables still to process
             Scoped where
     ConGroup : {newargs : _} ->
                Name -> (tag : Int) ->
                List01 True (PatClause (newargs ++ todo) (newargs ++ vars)) ->
                Group todo vars
     DelayGroup : {tyarg, valarg : _} ->
                  List01 True (PatClause (tyarg :: valarg :: todo)
                                         (tyarg :: valarg :: vars)) ->
                  Group todo vars
     ConstGroup : Constant -> List01 True (PatClause todo vars) ->
                  Group todo vars

covering
{vars : _} -> {todo : _} -> Show (Group todo vars) where
  show (ConGroup c t cs) = "Con " ++ show c ++ ": " ++ show cs
  show (DelayGroup cs) = "Delay: " ++ show cs
  show (ConstGroup c cs) = "Const " ++ show c ++ ": " ++ show cs

-- A match is found by comparing names, tags and constants as values; the
-- group it is found in keeps its own.
data GroupMatch : ConType -> List Pat -> Group todo vars -> Type where
     ConMatch : LengthMatch ps newargs ->
                GroupMatch (CName n tag) ps
                  (ConGroup {newargs} n' tag' (MkPatClause pvs pats pid rhs :: rest))
     DelayMatch : GroupMatch CDelay []
                    (DelayGroup {tyarg} {valarg} (MkPatClause pvs pats pid rhs :: rest))
     ConstMatch : GroupMatch (CConst c) []
                    (ConstGroup c' (MkPatClause pvs pats pid rhs :: rest))
     NoMatch : GroupMatch ct ps g

-- Two constants' clauses are one group when the constants are equal, but
-- doubles never are, and of the primitive types only those `primTypeEq`
-- relates.
sameConstant : Constant -> Constant -> Bool
sameConstant (Db _) (Db _) = False
sameConstant (PrT x) (PrT y) = isJust (primTypeEq x y)
sameConstant c c' = c == c'

checkGroupMatch : (c : ConType) -> (ps : List Pat) -> (g : Group todo vars) ->
                  GroupMatch c ps g
checkGroupMatch (CName x tag) ps (ConGroup {newargs} x' tag' (MkPatClause pvs pats pid rhs :: rest))
    = case checkLengthMatch ps newargs of
           Nothing => NoMatch
           Just prf => if x == x' && tag == tag' then ConMatch prf else NoMatch
checkGroupMatch (CName x tag) ps _ = NoMatch
checkGroupMatch CDelay [] (DelayGroup (MkPatClause pvs pats pid rhs :: rest))
    = DelayMatch
checkGroupMatch (CConst c) [] (ConstGroup c' (MkPatClause pvs pats pid rhs :: rest))
    = if sameConstant c c' then ConstMatch else NoMatch
checkGroupMatch _ _ _ = NoMatch

data PName : Type where

nextName : {auto i : Ref PName Int} ->
           Ident -> Core Name
nextName root
    = do x <- get PName
         put PName (x + 1)
         pure (MN root x)

nextNames : {vars : _} ->
            {auto i : Ref PName Int} ->
            {auto c : Ref Ctxt Defs} ->
            FC -> Ident -> (unified : List Name) -> Source ->
            List Pat -> Maybe (NF vars) ->
            Core (args ** (SizeOf args, NamedPats args (args ++ vars)))
nextNames fc root unified src [] fty = pure ([] ** (zero, []))
nextNames fc root unified src (p :: pats) fty
     = do defs <- get Ctxt
          empty <- clearDefs defs
          n <- nextName root
          let env = mkEnv fc vars
          fa_tys <- the (Core (Maybe (NF vars), ArgType vars)) $
              case fty of
                   Nothing => pure (Nothing, Unknown)
                   Just (NBind pfc _ (Pi _ c _ fargc) fsc) =>
                      do farg <- evalClosure defs fargc
                         case farg of
                              NErased {} =>
                                pure (Just !(fsc defs (toClosure defaultOpts env (Ref pfc Bound n))),
                                      Unknown)
                              _ => pure (Just !(fsc defs (toClosure defaultOpts env (Ref pfc Bound n))),
                                         Known c !(quote empty env farg))
                   Just t =>
                      pure (Nothing, Stuck !(quote empty env t))
          (args ** (l, ps)) <- nextNames fc root unified src pats (fst fa_tys)
          let argTy = case snd fa_tys of
                           Unknown => Unknown
                           Known rig t => Known rig (weakenNs (suc l) t)
                           Stuck t => Stuck (weakenNs (suc l) t)
          pure (n :: args ** (suc l, MkInfo p First argTy (sourceOf unified src p) :: weaken ps))

-- replace the prefix of patterns with 'pargs'
newPats : (unified : List Name) -> Source ->
          (pargs : List Pat) -> LengthMatch pargs ns ->
          NamedPats (ns ++ todo) vars ->
          NamedPats ns vars
newPats unified src [] NilMatch rest = []
newPats unified src (newpat :: xs) (ConsMatch w) (pi :: rest)
  = { pat := newpat, source := sourceOf unified src newpat } pi
      :: newPats unified src xs w rest

updateNames : List (Name, Pat) -> List (Name, Name)
updateNames = mapMaybe update
  where
    update : (Name, Pat) -> Maybe (Name, Name)
    update (n, PLoc fc p) = Just (p, n)
    update _ = Nothing

updatePatNames : List (Name, Name) -> NamedPats todo vars -> NamedPats todo vars
updatePatNames _ [] = []
updatePatNames ns (pi :: ps)
    = { pat $= update } pi :: updatePatNames ns ps
  where
    update : Pat -> Pat
    update (PAs fc n p)
        = case lookup n ns of
               Nothing => PAs fc n (update p)
               Just n' => PAs fc n' (update p)
    update (PCon fc n i a ps) = PCon fc n i a (map update ps)
    update (PTyCon fc n a ps) = PTyCon fc n a (map update ps)
    update (PArrow fc x s t) = PArrow fc x (update s) (update t)
    update (PDelay fc r t p) = PDelay fc r (update t) (update p)
    update (PLoc fc n)
        = case lookup n ns of
               Nothing => PLoc fc n
               Just n' => PLoc fc n'
    update p = p

groupCons : {a, vars, todo : _} ->
            {auto i : Ref PName Int} ->
            {auto ct : Ref Ctxt Defs} ->
            FC -> Name ->
            List Name ->
            (cs : List01 True (PatClause (a :: todo) vars)) ->
            (0 isCons : All IsConClause cs) =>
            Core (List01 True (Group todo vars))
groupCons fc fn pvars (x :: xs) {isCons = p :: ps}
    = foldlC (uncurry . gc) !(gc [] x p) $ pushIn xs ps
  where
    addConG : {vars', todo' : _} ->
              Name -> (tag : Int) -> Source ->
              List Pat -> NamedPats todo' vars' ->
              Origin -> (rhs : Term vars') ->
              (acc : List01 ne (Group todo' vars')) ->
              Core (List01 True (Group todo' vars'))
    -- Group all the clauses that begin with the same constructor, and
    -- add new pattern arguments for each of that constructor's arguments.
    -- The type of 'ConGroup' ensures that we refer to the arguments by
    -- the same name in each of the clauses
    addConG n tag src pargs pats pid rhs []
        = do cty <- if n == arrowConName
                      then pure $ NBind fc (MN (known K_) 0) (Pi fc top Explicit (MkNFClosure defaultOpts (mkEnv fc vars') (NType fc (MN (known Ktop) 0)))) $
                              (\d, a => pure $ NBind fc (MN (known K_) 1) (Pi fc top Explicit (MkNFClosure defaultOpts (mkEnv fc vars') (NErased fc Placeholder)))
                                (\d, a => pure $ NType fc (MN (known Ktop) 0)))
                      else do defs <- get Ctxt
                              Just t <- lookupTyExact n (gamma defs)
                                   | Nothing => pure (NErased fc Placeholder)
                              nf defs (mkEnv fc vars') (embed t)
             (patnames ** (l, newargs)) <- nextNames fc (known Ke) (unified pid) src pargs (Just cty)
             -- Update non-linear names in remaining patterns (to keep
             -- explicit dependencies in types accurate)
             let pats' = updatePatNames (updateNames (zip patnames pargs))
                                        (weakenNs l pats)
             let clause = MkPatClause pvars (newargs ++ pats') pid (weakenNs l rhs)
             pure [ConGroup n tag [clause]]
    addConG n tag src pargs pats pid rhs (g :: gs) with (checkGroupMatch (CName n tag) pargs g)
      addConG n tag src pargs pats pid rhs
              (ConGroup n' tag' (MkPatClause pvars ps tid tm :: rest) :: gs) | ConMatch {newargs} lprf
        = do let newps = newPats (unified pid) src pargs lprf ps
             let l = mkSizeOf newargs
             let pats' = updatePatNames (updateNames (zip newargs pargs))
                                        (weakenNs l pats)
             let newclause = MkPatClause pvars (newps ++ pats') pid (weakenNs l rhs)
             -- put the new clause at the end of the group, since we
             -- match the clauses top to bottom.
             pure $ ConGroup n' tag' (MkPatClause pvars ps tid tm :: rest ++ [newclause]) :: gs
      addConG n tag src pargs pats pid rhs (g :: gs) | NoMatch
        = (g ::) <$> addConG n tag src pargs pats pid rhs gs

    -- This rather ugly special case is to deal with laziness, where Delay
    -- is like a constructor, but with a special meaning that it forces
    -- evaluation when case analysis reaches it (dealt with in the evaluator
    -- and compiler)
    addDelayG : {vars', todo' : _} ->
                Source -> Pat -> Pat -> NamedPats todo' vars' ->
                Origin -> (rhs : Term vars') ->
                (acc : List01 ne (Group todo' vars')) ->
                Core (List01 True (Group todo' vars'))
    addDelayG src pty parg pats pid rhs []
        = do let dty = NBind fc (MN (known Ka) 0) (Pi fc erased Explicit (MkNFClosure defaultOpts (mkEnv fc vars') (NType fc (MN (known Ktop) 0)))) $
                        (\d, a =>
                            do a' <- evalClosure d a
                               pure (NBind fc (MN (known Kx) 0) (Pi fc top Explicit a)
                                       (\dv, av => pure (NDelayed fc LUnknown a'))))
             ([tyname, argname] ** (l, newargs)) <- nextNames fc (known Ke) (unified pid) src [pty, parg]
                                                  (Just dty)
                | _ => throw (InternalError "Error compiling Delay pattern match")
             let pats' = updatePatNames (updateNames [(tyname, pty),
                                                      (argname, parg)])
                                        (weakenNs l pats)
             let clause = MkPatClause pvars (newargs ++ pats') pid (weakenNs l rhs)
             pure [DelayGroup [clause]]
    addDelayG src pty parg pats pid rhs (g :: gs) with (checkGroupMatch CDelay [] g)
      addDelayG src pty parg pats pid rhs
          (DelayGroup (MkPatClause pvars ps tid tm :: rest) :: gs) | DelayMatch {tyarg} {valarg}
        = do let l = mkSizeOf [tyarg, valarg]
             let newps = newPats (unified pid) src [pty, parg] (ConsMatch (ConsMatch NilMatch)) ps
             let pats' = updatePatNames (updateNames [(tyarg, pty),
                                                      (valarg, parg)])
                                        (weakenNs l pats)
             let newclause = MkPatClause pvars (newps ++ pats') pid (weakenNs l rhs)
             pure $ DelayGroup (MkPatClause pvars ps tid tm :: rest ++ [newclause]) :: gs
      addDelayG src pty parg pats pid rhs (g :: gs) | NoMatch
        = (g ::) <$> addDelayG src pty parg pats pid rhs gs

    addConstG : {vars', todo' : _} ->
                Constant -> NamedPats todo' vars' ->
                Origin -> (rhs : Term vars') ->
                (acc : List01 ne (Group todo' vars')) ->
                Core (List01 True (Group todo' vars'))
    addConstG c pats pid rhs []
          = pure [ConstGroup c [MkPatClause pvars pats pid rhs]]
    addConstG c pats pid rhs (g :: gs) with (checkGroupMatch (CConst c) [] g)
      addConstG c pats pid rhs
              (ConstGroup c' (MkPatClause pvars ps tid tm :: rest) :: gs) | ConstMatch
        = do let newclause = MkPatClause pvars pats pid rhs
             pure $ ConstGroup c' (MkPatClause pvars ps tid tm :: rest ++ [newclause]) :: gs
      addConstG c pats pid rhs (g :: gs) | NoMatch
        = (g ::) <$> addConstG c pats pid rhs gs

    addGroup : {vars, todo, idx : _} ->
               Source -> (pat : Pat) -> (0 _ : IsConPat pat) =>
               (0 p : IsVar nm idx vars) ->
               NamedPats todo vars -> Origin -> Term vars ->
               List01 ne (Group todo vars) ->
               Core (List01 True (Group todo vars))
    -- In 'As' replace the name on the RHS with a reference to the
    -- variable we're doing the case split on
    addGroup src (PAs fc n p) pprf pats pid rhs acc
         = addGroup src p pprf pats pid (substName n (Local fc (Just True) idx pprf) rhs) acc
    addGroup src (PCon cfc n t a pargs) pprf pats pid rhs acc
         = if a == length pargs
              then addConG n t src pargs pats pid rhs acc
              else throw (CaseCompile cfc fn (NotFullyApplied n))
    addGroup src (PTyCon cfc n a pargs) pprf pats pid rhs acc
         = if a == length pargs
           then addConG n 0 src pargs pats pid rhs acc
           else throw (CaseCompile cfc fn (NotFullyApplied n))
    addGroup src (PArrow _ _ s t) pprf pats pid rhs acc
         = addConG arrowConName 0 src [s, t] pats pid rhs acc
    -- Go inside the delay; we'll flag the case as needing to force its
    -- scrutinee (need to check in 'caseGroups below)
    addGroup src (PDelay _ _ pty parg) pprf pats pid rhs acc
         = addDelayG src pty parg pats pid rhs acc
    addGroup src (PConst _ c) pprf pats pid rhs acc
         = addConstG c pats pid rhs acc

    gc : {a, vars, todo : _} ->
         List01 ne (Group todo vars) ->
         (p : PatClause (a :: todo) vars) ->
         (0 _ : IsConClause p) ->
         Core (List01 True (Group todo vars))
    gc acc (MkPatClause _ (MkInfo pat pprf _ src :: pats) pid rhs) isCon
        = addGroup src pat pprf pats pid rhs acc

getFirstPat : NamedPats (p :: ps) ns -> Pat
getFirstPat (p :: _) = pat p

getFirstArgType : NamedPats (p :: ps) ns -> ArgType ns
getFirstArgType (p :: _) = argType p

-- Check whether all the initial patterns have the same concrete, known
-- and matchable type, which is multiplicity > 0.
-- If so, it's okay to match on it
sameType : {ns : _} ->
           {auto c : Ref Ctxt Defs} ->
           FC -> Phase -> Name ->
           Env Term ns -> List01 ne (NamedPats (p :: ps) ns) ->
           Core ()
sameType fc phase fn env [] = pure ()
sameType {ns} fc phase fn env (p :: xs)
    = do defs <- get Ctxt
         case getFirstArgType p of
              Known _ t => sameTypeAs phase
                                      !(nf defs env t)
                                      (map getFirstArgType xs)
              ty => throw (CaseCompile fc fn DifferingTypes)
  where
    firstPat : NamedPats (np :: nps) ns -> Pat
    firstPat (pinf :: _) = pat pinf

    headEq : NF ns -> NF ns -> Phase -> Bool
    headEq (NBind _ _ (Pi {}) _) (NBind _ _ (Pi {}) _) _ = True
    headEq (NTCon _ n _ _) (NTCon _ n' _ _) _ = n == n'
    headEq (NPrimVal _ c) (NPrimVal _ c') _ = c == c'
    headEq (NType {}) (NType {}) _ = True
    headEq (NErased _ (Dotted x)) y ph = headEq x y ph
    headEq x (NErased _ (Dotted y)) ph = headEq x y ph
    headEq _ _ _ = False

    sameTypeAs : forall ne. Phase -> NF ns -> List01 ne (ArgType ns) -> Core ()
    sameTypeAs _ ty [] = pure ()
    sameTypeAs ph ty (Known r t :: xs) =
         do defs <- get Ctxt
            if headEq ty !(nf defs env t) phase
               then sameTypeAs ph ty xs
               else throw (CaseCompile fc fn DifferingTypes)
    sameTypeAs p ty _ = throw (CaseCompile fc fn DifferingTypes)

-- Check whether all the initial patterns are the same, or are all a variable.
-- If so, we'll match it to refine later types and move on
samePat : List01 True (NamedPats (p :: ps) ns) -> Bool
samePat (pi :: xs)
    = samePatAs (dropAs (getFirstPat pi))
                (map (dropAs . getFirstPat) xs)
  where
    dropAs : Pat -> Pat
    dropAs (PAs _ _ p) = p
    dropAs p = p

    samePatAs : Pat -> List01 ne Pat -> Bool
    samePatAs p [] = True
    samePatAs (PTyCon fc n a args) (PTyCon _ n' _ _ :: ps)
        = n == n' && samePatAs (PTyCon fc n a args) ps
    samePatAs (PCon fc n t a args) (PCon _ n' t' _ _ :: ps)
        = n == n' && t == t' && samePatAs (PCon fc n t a args) ps
    samePatAs (PConst fc c) (PConst _ c' :: ps)
        = c == c' && samePatAs (PConst fc c) ps
    samePatAs (PArrow fc x s t) (PArrow _ _ s' t' :: ps)
        = samePatAs (PArrow fc x s t) ps
    samePatAs (PDelay fc r t p) (PDelay _ _ _ _ :: ps)
        = samePatAs (PDelay fc r t p) ps
    samePatAs (PLoc fc n) (PLoc _ _ :: ps) = samePatAs (PLoc fc n) ps
    samePatAs x y = False

getScore : {ns : _} ->
           {auto c : Ref Ctxt Defs} ->
           FC -> Phase -> Name ->
           List01 True (NamedPats (p :: ps) ns) ->
           Core (Either CaseError ())
getScore fc phase name npss
    = catch (Right () <$ sameType fc phase name (mkEnv fc ns) npss)
            $ \case
              CaseCompile _ _ err => pure $ Left err
              err => throw err

||| Pick the leftmost matchable thing with all constructors in the
||| same family, or all variables, or all the same type constructor.
pickNextViable : {p, ns, ps : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 FC -> Phase -> Name -> List01 True (NamedPats (p :: ps) ns) ->
                 Core (n ** NVar n (p :: ps))
-- last possible variable
pickNextViable {ps = []} fc phase fn npss
    = if samePat npss
         then pure (_ ** MkNVar First)
         else do Right () <- getScore fc phase fn npss
                       | Left err => throw (CaseCompile fc fn err)
                 pure (_ ** MkNVar First)
pickNextViable {ps = q :: qs} fc phase fn npss
    = if samePat npss
         then pure (_ ** MkNVar First)
         else case !(getScore fc phase fn npss) of
                   Right () => pure (_ ** MkNVar First)
                   _ => do (_ ** MkNVar var) <- pickNextViable fc phase fn (map tail npss)
                           pure (_ ** MkNVar (Later var))

moveFirst : {idx : Nat} -> (0 el : IsVar nm idx ps) -> NamedPats ps ns ->
            NamedPats (nm :: dropIsVar ps el) ns
moveFirst el nps = getPat el nps :: dropPat el nps

shuffleVars : {idx : Nat} -> (0 el : IsVar nm idx todo) -> PatClause todo vars ->
              PatClause (nm :: dropIsVar todo el) vars
shuffleVars First orig@(MkPatClause pvars lhs pid rhs) = orig -- no-op
shuffleVars el (MkPatClause pvars lhs pid rhs)
    = MkPatClause pvars (moveFirst el lhs) pid rhs

-- The columns `todo` taken apart, each part in order, into those the tree
-- splits where they stand (`now`) and those it splits after all of them
-- (`after`).
data Arrangement : (now, after, todo : List Name) -> Type where
     NoColumns : Arrangement [] [] []
     InPlace : Arrangement now after todo -> Arrangement (n :: now) after (n :: todo)
     Postponed : Arrangement now after todo -> Arrangement now (n :: after) (n :: todo)

-- Where the clauses put each column: one they only bind, and some bind to
-- what unification found, goes after the others.
arrangement : {todo : _} -> List01 True (NamedPats todo vars) ->
              (now ** after ** Arrangement now after todo)
arrangement {todo = []} rows = (_ ** _ ** NoColumns)
arrangement {todo = _ :: _} rows
    = let (column, rest) = splitColumn rows
          (_ ** _ ** placed) = arrangement rest in
          case foldr (\p, u => both (use (source p) (pat p)) u) Binds column of
               Fixed => (_ ** _ ** Postponed placed)
               _ => (_ ** _ ** InPlace placed)

arrangePats : Arrangement now after todo -> NamedPats todo vars ->
              (NamedPats now vars, NamedPats after vars)
arrangePats NoColumns [] = ([], [])
arrangePats (InPlace placed) (p :: ps)
    = let (soon, late) = arrangePats placed ps in (p :: soon, late)
arrangePats (Postponed placed) (p :: ps)
    = let (soon, late) = arrangePats placed ps in (soon, p :: late)

arranged : Arrangement now after todo -> PatClause todo vars ->
           PatClause (now ++ after) vars
arranged placed (MkPatClause pvars ps pid rhs)
    = let (soon, late) = arrangePats placed ps in
          MkPatClause pvars (soon ++ late) pid rhs

-- Whether every column's type is known. Where one is not, it is found as the
-- columns before it are split, so the columns keep their order.
typed : NamedPats todo vars -> Bool
typed [] = True
typed (p :: ps)
    = case argType p of
           Known {} => typed ps
           _ => False

-- The clauses' own tests come before what unification fixed from them. A
-- column the clauses only bind, and some bind to what unification found
-- from the patterns they write (an implicit of the definition or of a
-- constructor in a pattern that a clause leaves out, a case block's
-- environment, a with block's argument), is split after the others, at
-- every step. Split before the patterns that fix it, it leaves branches
-- that only the emptiness of a later column's type rules out (`All IsF
-- (A :: xs)`, when `IsF A` has no constructor), which the coverage check
-- does not look into; split after them, those branches are impossible by
-- unification. It is still split: a leaf binds what its pattern names, and
-- a column whose type computes on it (`Lifted r xs y z`) waits for it
-- (pickNextViable).
arrange : {todo : _} -> List01 True (PatClause todo vars) ->
          (todo' ** List01 True (PatClause todo' vars))
arrange cs@(c :: _)
    = if typed (getNPs c)
         then let (_ ** _ ** placed) = arrangement (getNPs <$> cs) in
                  (_ ** arranged placed <$> cs)
         else (_ ** cs)

mutual
  {- 'PatClause' contains a list of patterns still to process (that's the
     "todo") and a right hand side with the variables we know about "vars".
     So "match" builds the remainder of the case tree for
     the unprocessed patterns. "err" is the tree for when the patterns don't
     cover the input (i.e. the "fallthrough" pattern, which at the top
     level will be an error). -}
  match : {vars, todo : _} ->
          {auto i : Ref PName Int} ->
          {auto c : Ref Ctxt Defs} ->
          FC -> Name -> Phase ->
          List01 True (PatClause todo vars) ->
          IMaybe ne (CaseTree vars) ->
          Core (CaseTree vars)
  match fc fn phase clauses err
      = let (_ ** clauses') = arrange clauses in
            step fc fn phase clauses' err

  step : {vars, todo : _} ->
         {auto i : Ref PName Int} ->
         {auto c : Ref Ctxt Defs} ->
         FC -> Name -> Phase ->
         List01 True (PatClause todo vars) ->
         IMaybe ne (CaseTree vars) ->
         Core (CaseTree vars)
  -- Before 'partition', reorder the arguments so that the one we
  -- inspect next has a concrete type that is the same in all cases, and
  -- has the most distinct constructors (via pickNextViable)
  step {todo = _ :: _} fc fn phase clauses err
      = do (n ** MkNVar next) <- pickNextViable fc phase fn (getNPs <$> clauses)
           log "compile.casetree.pick" 25 $ "Picked " ++ show n ++ " as the next split"
           let clauses' = shuffleVars next <$> clauses
           log "compile.casetree.clauses" 25 $
             unlines ("Using clauses:" :: map (("  " ++) . show) (forget clauses'))
           let ps = partition phase clauses'
           log "compile.casetree.partition" 25 $ "Got Partition:\n" ++ show ps
           Just mix <- mixture fc fn phase ps err
           log "compile.casetree.intermediate" 25 $ "match: new case tree " ++ show mix
           pure mix
  step {todo = []} fc fn phase (MkPatClause pvars [] pid (Erased _ Impossible) :: _) err
       = pure Impossible
  step {todo = []} fc fn phase (MkPatClause pvars [] pid rhs :: _) err
       = pure $ STerm (index pid) rhs

  caseGroups : {pvar, vars, todo : _} ->
               {auto i : Ref PName Int} ->
               {auto c : Ref Ctxt Defs} ->
               FC -> Name -> Phase ->
               {idx : Nat} -> (0 p : IsVar pvar idx vars) -> Term vars ->
               List01 True (Group todo vars) -> IMaybe ne (CaseTree vars) ->
               Core (CaseTree vars)
  caseGroups fc fn phase el ty gs errorCase
      = Case idx el (resolveNames vars ty) <$> altGroups gs
    where
      altGroups : forall ne. List01 ne (Group todo vars) -> Core (List (CaseAlt vars))
      altGroups [] = pure $ toList $ DefaultCase <$> errorCase
      altGroups (ConGroup {newargs} cn tag rest :: cs)
          = do crest <- match fc fn phase rest (map (weakenNs (mkSizeOf newargs)) errorCase)
               cs' <- altGroups cs
               pure (ConCase cn tag newargs crest :: cs')
      altGroups (DelayGroup {tyarg} {valarg} rest :: cs)
          = do crest <- match fc fn phase rest (map (weakenNs (mkSizeOf [tyarg, valarg])) errorCase)
               cs' <- altGroups cs
               pure (DelayCase tyarg valarg crest :: cs')
      altGroups (ConstGroup c rest :: cs)
          = do crest <- match fc fn phase rest errorCase
               cs' <- altGroups cs
               pure (ConstCase c crest :: cs')

  conRule : {a, vars, todo : _} ->
            {auto i : Ref PName Int} ->
            {auto c : Ref Ctxt Defs} ->
            FC -> Name -> Phase ->
            (cs : List01 True (PatClause (a :: todo) vars)) ->
            (0 isCons : All IsConClause cs) =>
            IMaybe ne (CaseTree vars) ->
            Core (CaseTree vars)
  -- ASSUMPTION, not expressed in the type, that the patterns all have
  -- the same variable (pprf) for the first argument. If not, the result
  -- will be a broken case tree... so we should find a way to express this
  -- in the type if we can.
  conRule {a} fc fn phase cs@(MkPatClause pvars (MkInfo pat pprf fty _ :: pats) pid rhs :: rest) err
      = do Element refinedcs _ <- pullOut <$> traverseList01 (substInClause fc) (pushIn cs isCons)
           groups <- groupCons fc fn pvars refinedcs
           ty <- case fty of
                      Known _ t => pure t
                      _ => throw (CaseCompile fc fn UnknownType)
           caseGroups fc fn phase pprf ty groups err

  varRule : {a, vars, todo : _} ->
            {auto i : Ref PName Int} ->
            {auto c : Ref Ctxt Defs} ->
            FC -> Name -> Phase ->
            List01 True (PatClause (a :: todo) vars) ->
            IMaybe ne (CaseTree vars) ->
            Core (CaseTree vars)
  varRule fc fn phase cs err
      = do alts' <- traverseList01 updateVar cs
           match fc fn phase alts' err
    where
      updateVar : PatClause (a :: todo) vars -> Core (PatClause todo vars)
      -- replace the name with the relevant variable on the rhs
      updateVar (MkPatClause pvars (MkInfo (PLoc pfc n) prf fty _ :: pats) pid rhs)
          = pure $ MkPatClause (n :: pvars)
                        !(substInPats fc a (Local pfc (Just False) _ prf) pats)
                        pid (substName n (Local pfc (Just False) _ prf) rhs)
      -- If it's an as pattern, replace the name with the relevant variable on
      -- the rhs then continue with the inner pattern
      updateVar (MkPatClause pvars (MkInfo (PAs pfc n pat) prf fty src :: pats) pid rhs)
          = do pats' <- substInPats fc a (mkTerm _ pat) pats
               let rhs' = substName n (Local pfc (Just True) _ prf) rhs
               updateVar (MkPatClause pvars (MkInfo pat prf fty src :: pats') pid rhs')
      -- match anything, name won't appear in rhs but need to update
      -- LHS pattern types based on what we've learned
      updateVar (MkPatClause pvars (MkInfo pat prf fty _ :: pats) pid rhs)
          = pure $ MkPatClause pvars
                        !(substInPats fc a (mkTerm vars pat) pats) pid rhs

  mixture : {a, vars, todo : _} ->
            {auto i : Ref PName Int} ->
            {auto c : Ref Ctxt Defs} ->
            {ps : List01 ne (PatClause (a :: todo) vars)} ->
            FC -> Name -> Phase ->
            Partitions ps ->
            IMaybe neErr (CaseTree vars) ->
            Core (IMaybe (ne || neErr) (CaseTree vars))
  mixture fc fn phase (ConClauses cs rest) err
      = do fallthrough <- mixture fc fn phase rest err
           Just <$> conRule fc fn phase cs fallthrough
  mixture fc fn phase (VarClauses vs rest) err
      = do fallthrough <- mixture fc fn phase rest err
           Just <$> varRule fc fn phase vs fallthrough
  mixture fc fn phase NoClauses err
      = pure err

export
mkPat : {auto c : Ref Ctxt Defs} ->
        (matchable : Bool) -> List Pat -> ClosedTerm -> ClosedTerm -> Core Pat
mkPat _ [] orig (Ref fc Bound n) = pure $ PLoc fc n
mkPat True args orig (Ref fc (DataCon t a) n) = pure $ PCon fc n t a args
mkPat True args orig (Ref fc (TyCon a) n) = pure $ PTyCon fc n a args
mkPat True args orig (Ref fc Func n)
  = do prims <- getPrimitiveNames
       mtm <- normalisePrims (const True) isPConst True prims n args orig Env.empty
       case mtm of
         Just tm => if tm /= orig -- check we made progress; if there's an
                                  -- unresolved interface, we might be stuck
                                  -- and we'd loop forever
                       then mkPat True [] tm tm
                       else -- Possibly this should be an error instead?
                            pure $ PUnmatchable (getLoc orig) orig
         Nothing =>
           do log "compile.casetree" 10 $
                "Unmatchable function: " ++ show n
              pure $ PUnmatchable (getLoc orig) orig
mkPat True args orig (Bind fc x (Pi _ _ _ s) t)
    -- For (b:Nat) -> b, the codomain looks like b [__], but we want `b` as the pattern
    = case subst (Erased fc Placeholder) t of
        App _ t'@(Ref fc Bound n) (Erased {}) => pure $ PArrow fc x !(mkPat True [] s s) !(mkPat False [] t' t')
        t' => pure $ PArrow fc x !(mkPat True [] s s) !(mkPat False [] t' t')
mkPat True args orig (App fc fn arg)
    = do parg <- mkPat True [] arg arg
         mkPat True (parg :: args) orig fn
mkPat True args orig (As fc _ (Ref _ Bound n) ptm)
    = pure $ PAs fc n !(mkPat True [] ptm ptm)
mkPat True args orig (As fc _ _ ptm)
    = mkPat True [] orig ptm
mkPat True args orig (TDelay fc r ty p)
    = pure $ PDelay fc r !(mkPat True [] orig ty) !(mkPat True [] orig p)
mkPat True args orig (PrimVal fc $ PrT c) -- Primitive type constant
    = pure $ PTyCon fc (knownUN (primTypeKnown c)) 0 []
mkPat True args orig (PrimVal fc c) = pure $ PConst fc c -- Non-type constant
mkPat True args orig (TType fc _) = pure $ PTyCon fc (knownUN KType) 0 []
mkPat _ args orig tm
   = do log "compile.casetree" 10 $
          "Catchall: marking " ++ show tm ++ " as unmatchable"
        pure $ PUnmatchable (getLoc orig) orig

export
argToPat : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Pat
argToPat tm = mkPat True [] tm tm

mkPatClause : {auto c : Ref Ctxt Defs} ->
              FC -> Name ->
              (args : Scope) -> ClosedTerm ->
              Origin -> (List Pat, ClosedTerm) ->
              Core (PatClause args args)
mkPatClause fc fn args ty pid (ps, rhs)
    = maybe (throw (CaseCompile fc fn DifferingArgNumbers))
            (\eq =>
               do defs <- get Ctxt
                  nty <- nf defs Env.empty ty
                  ns <- mkNames args ps eq (Just nty)
                  log "compile.casetree" 20 $
                    "Make pat clause for names " ++ show ns
                     ++ " in LHS " ++ show ps
                  pure (MkPatClause [] ns pid
                          (rewrite sym (appendNilRightNeutral args) in
                                   (weakenNs (mkSizeOf args) rhs))))
            (checkLengthMatch args ps)
  where
    mkNames : (vars : Scope) -> (ps : List Pat) ->
              LengthMatch vars ps -> Maybe (NF []) ->
              Core (NamedPats vars vars)
    mkNames [] [] NilMatch fty = pure []
    mkNames (arg :: args) (p :: ps) (ConsMatch eq) fty
        = do defs <- get Ctxt
             empty <- clearDefs defs
             fa_tys <- the (Core (Maybe _, ArgType _)) $
                case fty of
                     Nothing => pure (Nothing, CaseBuilder.Unknown)
                     Just (NBind pfc _ (Pi _ c _ farg) fsc) =>
                        pure (Just !(fsc defs (toClosure defaultOpts [] (Ref pfc Bound arg))),
                              Known c (embed !(quote empty [] farg)))
                     Just t =>
                        pure (Nothing, Stuck (embed !(quote empty [] t)))
             pure (MkInfo p First (Builtin.snd fa_tys) (sourceOf (unified pid) Written p)
                      :: weaken !(mkNames args ps eq (Builtin.fst fa_tys)))

-- Each clause comes with the names of the arguments it leaves to
-- unification (`Origin`).
export
patCompile : {auto c : Ref Ctxt Defs} ->
             FC -> Name -> Phase ->
             ClosedTerm -> List01 True (List Name, List Pat, ClosedTerm) ->
             Core (args ** CaseTree args)
patCompile fc fn phase ty (p :: ps)
    = do let (ns ** n) = getNames 0 (fst (snd p))
         pats <- mkPatClausesFrom 0 ns (p :: ps)
         -- low verbosity level: pretty print fully resolved names
         logC "compile.casetree" 5 $ do
           pats <- traverse toFullNames $ forget pats
           pure $ "Pattern clauses:\n"
                ++ show (indent 2 $ vcat $ pretty <$> pats)
         -- higher verbosity: dump the raw data structure
         log "compile.casetree" 10 $ show pats
         i <- newRef PName (the Int 0)
         cases <- match fc fn phase pats Nothing
         pure (_ ** cases)
  where
    mkPatClausesFrom : Int -> (args : Scope) ->
                       List01 ne (List Name, List Pat, ClosedTerm) ->
                       Core (List01 ne (PatClause args args))
    mkPatClausesFrom i ns [] = pure []
    mkPatClausesFrom i ns ((unified, p) :: ps)
        = do p' <- mkPatClause fc fn ns ty (MkOrigin i unified) p
             ps' <- mkPatClausesFrom (i + 1) ns ps
             pure (p' :: ps')

    getNames : Int -> List Pat -> (ns : Scope ** SizeOf ns)
    getNames i [] = ([] ** zero)
    getNames i (x :: xs) =
      let (ns ** n) = getNames (i + 1) xs
      in (MN (known Karg) i :: ns ** suc n)

toPatClause : {auto c : Ref Ctxt Defs} ->
              FC -> Name -> (List Name, ClosedTerm, ClosedTerm) ->
              Core (List Name, List Pat, ClosedTerm)
toPatClause fc n (unified, lhs, rhs)
    = case getFnArgs lhs of
           (Ref ffc Func fn, args)
              => do defs <- get Ctxt
                    (np, _) <- getPosition n (gamma defs)
                    (fnp, _) <- getPosition fn (gamma defs)
                    if np == fnp
                       then pure (unified, !(traverse argToPat args), rhs)
                       else throw (GenericMsg ffc ("Wrong function name in pattern LHS " ++ show (n, fn)))
           (f, args) => throw (GenericMsg fc "Not a function name in pattern LHS")

-- Assumption (given 'ClosedTerm') is that the pattern variables are
-- explicitly named. We'll assign de Bruijn indices when we're done, and
-- the names of the top level variables we created are returned in 'args'.
-- Each clause comes with the names of the arguments it leaves to
-- unification, which the tree splits after the others (patCompile).
export
simpleCase : {auto c : Ref Ctxt Defs} ->
             FC -> Phase -> Name -> ClosedTerm ->
             (clauses : List01 True (List Name, ClosedTerm, ClosedTerm)) ->
             Core (args ** (CaseTree args, List (List Pat)))
simpleCase fc phase fn ty clauses
    = do logC "compile.casetree" 5 $
                do cs <- traverse (\ (_,c,d) => [| MkPair (toFullNames c) (toFullNames d) |]) (forget clauses)
                   pure $ "simpleCase: Clauses:\n" ++ show (
                     indent 2 $ vcat $ flip map cs $ \ lrhs =>
                       byShow (fst lrhs) <++> pretty "=" <++> byShow (snd lrhs))
         ps <- traverseList01 (toPatClause fc fn) clauses
         (_ ** t) <- patCompile fc fn phase ty ps
         pure (_ ** (t, map clausePats (forget ps)))
  where
    clausePats : (List Name, List Pat, ClosedTerm) -> List Pat
    clausePats (_, ps, _) = ps

mutual
  findReachedAlts : CaseAlt ns' -> List Int
  findReachedAlts (ConCase _ _ _ t) = findReached t
  findReachedAlts (DelayCase _ _ t) = findReached t
  findReachedAlts (ConstCase _ t) = findReached t
  findReachedAlts (DefaultCase t) = findReached t

  findReached : CaseTree ns -> List Int
  findReached (Case _ _ _ alts) = concatMap findReachedAlts alts
  findReached (STerm i _) = [i]
  findReached _ = []

-- Replace a default case with explicit branches for the constructors.
-- This is easier than checking whether a default is needed when traversing
-- the tree (just one constructor lookup up front).
-- Unreachable defaults are those that when replaced by all possible constructors
-- followed by a removal of duplicate cases there is one _fewer_ total case alts.
identifyUnreachableDefaults : {auto c : Ref Ctxt Defs} ->
                              {vars : _} ->
                              FC -> Defs -> NF vars -> List (CaseAlt vars) ->
                              Core (SortedSet Int)
-- Leave it alone if it's a primitive type though, since we need the catch
-- all case there
identifyUnreachableDefaults fc defs (NPrimVal {}) cs = pure empty
identifyUnreachableDefaults fc defs (NType {}) cs = pure empty
identifyUnreachableDefaults fc defs nfty cs
    = do cs' <- traverse rep cs
         let (cs'', extraClauseIdxs) = dropRep (concat cs') empty
         let extraClauseIdxs' =
           if (length cs == (length cs'' + 1))
              then extraClauseIdxs
              else empty
         -- if a clause is unreachable under all the branches it can be found under
         -- then it is entirely unreachable.
         when (not $ null extraClauseIdxs') $
           log "compile.casetree.clauses" 25 $
             "Marking the following clause indices as unreachable under the current branch of the tree: " ++ (show extraClauseIdxs')
         pure extraClauseIdxs'
  where
    rep : CaseAlt vars -> Core (List (CaseAlt vars))
    rep (DefaultCase sc)
        = do allCons <- getCons defs nfty
             pure (map (mkAlt fc sc) allCons)
    rep c = pure [c]

    dropRep : List (CaseAlt vars) -> SortedSet Int -> (List (CaseAlt vars), SortedSet Int)
    dropRep [] extra = ([], extra)
    dropRep (c@(ConCase n t args sc) :: rest) extra
          -- assumption is that there's no defaultcase in 'rest' because
          -- we've just removed it
        = let (filteredClauses, extraCases) = partition (not . tagIs t) rest
              extraClauses = extraCases >>= findReachedAlts
              (rest', extra') = dropRep filteredClauses $ fromList extraClauses
          in  (c :: rest', extra `union` extra')
    dropRep (c :: rest) extra
        = let (rest', extra') = dropRep rest extra
          in  (c :: rest', extra')

||| Find unreachable default paths through the tree for each clause.
||| This is accomplished by expanding default clases into all concrete constructions
||| and then listing the clauses reached.
||| This list of clauses can be substracted from the list of "reachable" clauses
||| and if it turns out that the number of unreachable ways to use a clause is equal
||| to the number of ways to reach a RHS for that clause then the clause is totally
||| superfluous (it will never be reached).
findExtraDefaults : {auto c : Ref Ctxt Defs} ->
                    {vars : _} ->
                    FC -> Defs -> CaseTree vars ->
                    Core (List Int)
findExtraDefaults fc defs (Case idx el ty altsIn)
  = do let fenv = mkEnv fc vars
       nfty <- nf defs fenv ty
       extraCases <- identifyUnreachableDefaults fc defs nfty altsIn
       extraCases' <- concat <$> traverse findExtraAlts altsIn
       pure (Prelude.toList extraCases ++ extraCases')
  where
    findExtraAlts : CaseAlt vars -> Core (List Int)
    findExtraAlts (ConCase x tag args ctree) = findExtraDefaults fc defs ctree
    findExtraAlts (DelayCase x arg ctree) = findExtraDefaults fc defs ctree
    findExtraAlts (ConstCase x ctree) = findExtraDefaults fc defs ctree
    -- already handled defaults by elaborating them to all possible cons
    findExtraAlts (DefaultCase ctree) = pure []

findExtraDefaults fc defs ctree = pure []

-- Returns the case tree, and a list of the clauses that aren't reachable
export
getPMDef : {auto c : Ref Ctxt Defs} ->
           FC -> Phase -> Name -> ClosedTerm -> List Clause ->
           Core (args ** (CaseTree args, List (List Pat), List Clause))
-- If there's no clauses, make a definition with the right number of arguments
-- for the type, which we can use in coverage checking to ensure that one of
-- the arguments has an empty type
getPMDef fc phase fn ty []
    = do log "compile.casetree.getpmdef" 20 "getPMDef: No clauses!"
         defs <- get Ctxt
         pure (!(getArgs 0 !(nf defs Env.empty ty)) ** (Unmatched "No clauses in \{show fn}", [], []))
  where
    getArgs : Int -> ClosedNF -> Core (List Name)
    getArgs i (NBind fc x (Pi {}) sc)
        = do defs <- get Ctxt
             sc' <- sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder))
             pure (MN (known Karg) i :: !(getArgs i sc'))
    getArgs i _ = pure []
getPMDef fc phase fn ty clauses@(_ :: _)
    = do defs <- get Ctxt
         labelled <- labelPat 0 (fromList clauses)
         let cs = map (toClosed defs) labelled
         (_ ** (t, pats)) <- simpleCase fc phase fn ty cs
         logC "compile.casetree.getpmdef" 20 $
           pure $ "Compiled to: " ++ show !(toFullNames t)
         let reached = findReached t
         log "compile.casetree.clauses" 25 $
           "Reached clauses: " ++ (show reached)
         extraDefaults <- findExtraDefaults fc defs t
         let unreachable = getUnreachable 0 (reached \\ extraDefaults) clauses
         pure (_ ** (t, pats, unreachable))
  where
    getUnreachable : Int -> List Int -> List Clause -> List Clause
    getUnreachable i is [] = []
    getUnreachable i is (c :: cs)
        = if i `elem` is
             then getUnreachable (i + 1) is cs
             else c :: getUnreachable (i + 1) is cs

    -- Each clause's label is the stem of its variables' names, so that the
    -- variables of two clauses are never the same name.
    labelPat : Int -> List01 ne a -> Core (List01 ne (Ident, a))
    labelPat i [] = pure []
    labelPat i (x :: xs)
        = do l <- intern ("pat" ++ show i ++ ":")
             pure ((l, x) :: !(labelPat (i + 1) xs))

    -- The names `close` gives the variables a clause leaves to
    -- unification, which the tree splits after the others (patCompile).
    unifiedNames : {vars : _} -> Ident -> VarSet vars -> List Name
    unifiedNames pname unified
        = map (\v => MN pname (cast (varIdx v))) (VarSet.toList unified)

    toClosed : Defs -> (Ident, Clause) -> (List Name, ClosedTerm, ClosedTerm)
    toClosed defs (pname, MkClause env lhs rhs unified)
          = (unifiedNames pname unified, close fc pname env lhs, close fc pname env rhs)
