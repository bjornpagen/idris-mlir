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

-- Which of a definition's compile-time trees is built: the tree it is
-- evaluated by, which the frontend translates and Idris's checks read, or
-- the tree its coverage is checked by, which only proposes the cases its
-- clauses leave.
public export
data TreeFor = Evaluating | CheckingCoverage

-- The tree built is a compile-time tree of a definition of this
-- multiplicity. Upstream built another, for run time, with erasure and its
-- rewrites applied, for back ends this compiler does not have.
public export
data Phase = CompileTime RigCount TreeFor

-- The order a tree takes the columns in, among those `arrange` splits
-- first. The tree a definition is evaluated by takes them from the left,
-- and so does the tree a kept definition's coverage is checked by: a kept
-- definition matches an erased argument only where the patterns before it
-- force it (`getClauseType`), which only the order from the left tells. The
-- tree an erased definition's coverage is checked by splits an erased
-- argument wherever a clause matches it, and takes first the columns a run
-- would keep, from the left, then the erased ones from the right: a later
-- argument's type names the earlier ones, so the later determine the
-- earlier (an index is bound before the argument whose type it is in).
-- Split first, an index would end at each of its values no clause has with
-- the arguments that determine it unsplit, a case the coverage check cannot
-- refute without splitting them, and the walk of the missing cases would
-- repeat the rest of the tree for every constructor such a default stands
-- for.
data SplitOrder = FromLeft | KeptFirst

total
splitOrder : Phase -> SplitOrder
splitOrder (CompileTime r CheckingCoverage) = if isErased r then KeptFirst else FromLeft
splitOrder (CompileTime _ Evaluating) = FromLeft

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

-- The type of each column the tree has still to split, as the tree knows
-- it where it stands: the function's or the constructor's type the column
-- comes from, refined by the splits above, each by the value it gives the
-- column it splits (`refineColumns`) and by what the constructor's return
-- type fixes (`fixParts`), so it names the tree's own variables and
-- nothing else. A clause's copy of a column's type (`PatInfo.argType`) is
-- refined by that clause's own patterns too, which name the clause's
-- pattern variables, so that the tree can choose its splits by them; the
-- scrutinee type a case records is the column's.
namespace ColumnTypes
  public export
  data ColumnTypes : List Name -> Scoped where
       Nil : ColumnTypes [] vars
       (::) : ArgType vars -> ColumnTypes ns vars -> ColumnTypes (n :: ns) vars

  export
  (++) : ColumnTypes ms vars -> ColumnTypes ns vars -> ColumnTypes (ms ++ ns) vars
  (++) [] ys = ys
  (++) (x :: xs) ys = x :: xs ++ ys

-- The types of a clause's columns where no pattern has refined them yet:
-- where a column is made, every clause's copy of its type is the type it
-- comes from, so the columns' types are any clause's.
typesOf : NamedPats todo vars -> ColumnTypes todo vars
typesOf [] = []
typesOf (p :: ps) = argType p :: typesOf ps

-- A clause's patterns with these types.
withTypes : NamedPats todo vars -> ColumnTypes todo vars -> NamedPats todo vars
withTypes [] [] = []
withTypes (p :: ps) (t :: ts) = { argType := t } p :: withTypes ps ts

-- The columns after one whose type the function type `nf` has just given:
-- each that was waiting for it (`Unknown`) takes its type from `nf`'s
-- domain while `nf` is a function type, the next column from its codomain,
-- and the first `nf` is no function type for is stuck on it.
updateColumns : {vars, todo : _} ->
                {auto c : Ref Ctxt Defs} ->
                Env Term vars ->
                NF vars -> ColumnTypes todo vars -> Core (ColumnTypes todo vars)
updateColumns env nf [] = pure []
updateColumns {todo = pvar :: ns} env (NBind fc _ (Pi _ c _ farg) fsc) (Unknown :: ts)
    = do defs <- get Ctxt
         empty <- clearDefs defs
         pure (Known c !(quote empty env farg)
                 :: !(updateColumns env !(fsc defs (toClosure defaultOpts env (Ref fc Bound pvar))) ts))
updateColumns env nf (Unknown :: ts)
    = do defs <- get Ctxt
         empty <- clearDefs defs
         pure (Stuck !(quote empty env nf) :: ts)
updateColumns env nf ts = pure ts

updatePats : {vars, todo : _} ->
             {auto c : Ref Ctxt Defs} ->
             Env Term vars ->
             NF vars -> NamedPats todo vars -> Core (NamedPats todo vars)
updatePats env nf ps = withTypes ps <$> updateColumns env nf (typesOf ps)

-- The columns' types once the tree knows the value `tm` of the column `a`:
-- each names `a` no more, and one stuck on a function type that `tm` makes
-- a function type takes its type from it, as do the columns after it that
-- wait for it (`updateColumns`).
refineColumns : {vars, todo : _} ->
                {auto c : Ref Ctxt Defs} ->
                FC -> Name -> Term vars -> ColumnTypes todo vars ->
                Core (ColumnTypes todo vars)
refineColumns fc a tm [] = pure []
refineColumns fc a tm (Known r ty :: ts)
    = (Known r (substName a tm ty) ::) <$> refineColumns fc a tm ts
refineColumns {todo = pvar :: _} fc a tm (Stuck fty :: ts)
    = do defs <- get Ctxt
         empty <- clearDefs defs
         let env = mkEnv fc vars
         let fty' = substName a tm fty
         case !(nf defs env fty') of
              NBind pfc _ (Pi _ r _ farg) fsc =>
                 do ts' <- updateColumns env !(fsc defs (toClosure defaultOpts env (Ref pfc Bound pvar))) ts
                    ty <- quote empty env farg
                    (Known r ty ::) <$> refineColumns fc a tm ts'
              _ => (Stuck fty' ::) <$> refineColumns fc a tm ts
refineColumns fc a tm (Unknown :: ts) = (Unknown ::) <$> refineColumns fc a tm ts

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

Weaken (ColumnTypes todo) where
  weakenNs s [] = []
  weakenNs s (t :: ts) = weakenNs s t :: weakenNs s ts

-- The columns with the one at `el` moved first, as `moveFirst` moves a
-- clause's patterns.
moveColumn : {idx : Nat} -> (0 el : IsVar nm idx ps) -> ColumnTypes ps vars ->
             ColumnTypes (nm :: dropIsVar ps el) vars
moveColumn el cols = typeAt el cols :: dropType el cols
  where
    typeAt : {idx' : Nat} -> (0 el' : IsVar nm idx' ps') -> ColumnTypes ps' vars -> ArgType vars
    typeAt First (x :: xs) = x
    typeAt (Later p) (x :: xs) = typeAt p xs

    dropType : {idx' : Nat} -> (0 el' : IsVar nm idx' ps') -> ColumnTypes ps' vars ->
               ColumnTypes (dropIsVar ps' el') vars
    dropType First (x :: xs) = xs
    dropType (Later p) (x :: xs) = x :: dropType p xs

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
    matchesErased (CompileTime cr _) Written = isErased cr
    matchesErased (CompileTime cr _) _ = False

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
    getClauseType (CompileTime cr _) (PCon _ _ _ a xs) (Known r t)
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

-- What a split of a column into parts tells the tree: the column's value,
-- made of the columns the split makes for its parts; the value of each
-- other column the constructor's return type fixes (`fixedBy`); and the
-- types of the parts, all as the tree knows them (`ColumnTypes`).
record Split (parts : List Name) (vars : Scope) where
  constructor MkSplit
  given : Term (parts ++ vars)
  fixed : List (Name, Term (parts ++ vars))
  partTypes : ColumnTypes parts (parts ++ vars)

data Group : List Name -> -- pattern variables still to process
             Scoped where
     ConGroup : {newargs : _} ->
                Name -> (tag : Int) -> Split newargs vars ->
                List01 True (PatClause (newargs ++ todo) (newargs ++ vars)) ->
                Group todo vars
     DelayGroup : {tyarg, valarg : _} ->
                  Split [tyarg, valarg] vars ->
                  List01 True (PatClause (tyarg :: valarg :: todo)
                                         (tyarg :: valarg :: vars)) ->
                  Group todo vars
     ConstGroup : Constant -> List01 True (PatClause todo vars) ->
                  Group todo vars

covering
{vars : _} -> {todo : _} -> Show (Group todo vars) where
  show (ConGroup c t _ cs) = "Con " ++ show c ++ ": " ++ show cs
  show (DelayGroup _ cs) = "Delay: " ++ show cs
  show (ConstGroup c cs) = "Const " ++ show c ++ ": " ++ show cs

-- The constructor a split takes a column apart by, as a clause's pattern
-- names it: a data constructor, a type constructor, or the arrow of a
-- function type, which has two parts, its domain and its codomain.
data SplitBy : List Pat -> Type where
     ByData : Name -> (tag : Int) -> (arity : Nat) -> SplitBy ps
     ByType : Name -> (arity : Nat) -> SplitBy ps
     ByArrow : (x : Name) -> SplitBy [s, t]

-- The name and the tag a split's alternative has; a type constructor's
-- tag is 0, as the arrow's is.
splitName : SplitBy ps -> Name
splitName (ByData n _ _) = n
splitName (ByType n _) = n
splitName (ByArrow _) = arrowConName

splitTag : SplitBy ps -> Int
splitTag (ByData _ tag _) = tag
splitTag _ = 0

-- The value a split gives the column it splits: its constructor applied to
-- the columns made for its parts, each by its name, which the tree binds.
splitValue : FC -> SplitBy ps -> (parts : List Name) -> LengthMatch ps parts -> Term vars
splitValue fc (ByData n tag arity) parts _
    = apply fc (Ref fc (DataCon tag arity) n) (map (Ref fc Bound) parts)
splitValue fc (ByType n arity) parts _
    = apply fc (Ref fc (TyCon arity) n) (map (Ref fc Bound) parts)
splitValue fc (ByArrow x) [dom, cod] (ConsMatch (ConsMatch NilMatch))
    = Bind fc x (Pi fc top Explicit (Ref fc Bound dom)) (Ref fc Bound cod)

-- The columns' types once the tree knows the values of these columns.
refineAll : {vars, todo : _} ->
            {auto c : Ref Ctxt Defs} ->
            FC -> List (Name, Term vars) -> ColumnTypes todo vars ->
            Core (ColumnTypes todo vars)
refineAll fc [] ts = pure ts
refineAll fc ((n, t) :: vs) ts = refineAll fc vs !(refineColumns fc n t ts)

-- What a constructor's return type `ret`, its parts named in it, fixes
-- where the scrutinee, of type `ty`, is that constructor applied, the two
-- types being one there: a part standing alone at a place of `ret` is the
-- term `ty` has there, and a column standing alone at a place of `ty` is
-- the term `ret` has there. Places are compared only under constructors,
-- which are injective; under anything else they fix nothing. This is how
-- the tree knows a parameter (`List a`'s `a`), which no value carries, and
-- an index the constructor fixes (`Vect`'s length, as `S k`).
mutual
  fixedBy : {vars : _} -> {auto c : Ref Ctxt Defs} ->
            Defs -> Env Term vars -> (parts : List Name) ->
            (ret : NF vars) -> (ty : NF vars) -> Core (List (Name, Term vars))
  fixedBy defs env parts (NApp _ (NRef Bound n) []) ty
      = if n `elem` parts
           then do empty <- clearDefs defs
                   pure [(n, !(quote empty env ty))]
           else pure []
  fixedBy defs env parts ret (NApp _ (NRef Bound n) [])
      = do empty <- clearDefs defs
           pure [(n, !(quote empty env ret))]
  fixedBy defs env parts (NTCon _ n _ rs) (NTCon _ n' _ ts)
      = if n == n' then fixedByArgs defs env parts rs ts else pure []
  fixedBy defs env parts (NDCon _ n _ _ rs) (NDCon _ n' _ _ ts)
      = if n == n' then fixedByArgs defs env parts rs ts else pure []
  fixedBy defs env parts (NDelayed _ _ r) (NDelayed _ _ t) = fixedBy defs env parts r t
  fixedBy defs env parts _ _ = pure []

  fixedByArgs : {vars : _} -> {auto c : Ref Ctxt Defs} ->
                Defs -> Env Term vars -> (parts : List Name) ->
                List (FC, Closure vars) -> List (FC, Closure vars) ->
                Core (List (Name, Term vars))
  fixedByArgs defs env parts ((_, r) :: rs) ((_, t) :: ts)
      = do here <- fixedBy defs env parts !(evalClosure defs r) !(evalClosure defs t)
           (here ++) <$> fixedByArgs defs env parts rs ts
  fixedByArgs defs env parts _ _ = pure []

-- The split of a column of type `ty` into these parts, by a constructor
-- whose type past its parts is `ret`, which gives the column the value
-- `given`: what `ret` fixes (`fixedBy`) put in place of the parts and the
-- columns it fixes, in the column's value, in the values it fixes and in
-- the parts' types.
fixParts : {parts, vars : _} -> {auto c : Ref Ctxt Defs} ->
           FC -> SizeOf parts -> (ty : Term vars) -> (ret : Maybe (NF vars)) ->
           (given : Term (parts ++ vars)) -> ColumnTypes parts (parts ++ vars) ->
           Core (Split parts vars)
fixParts fc l ty Nothing given pts = pure (MkSplit given [] pts)
fixParts fc l ty (Just ret) given pts
    = do defs <- get Ctxt
         let env = mkEnv fc vars
         found <- map (\(n, t) => (n, weakenNs l t)) <$> fixedBy defs env parts ret !(nf defs env ty)
         pts' <- refineAll fc found pts
         pure (MkSplit (refined found given) (map (\(n, t) => (n, refined found t)) found) pts')
  where
    refined : List (Name, Term (parts ++ vars)) -> Term (parts ++ vars) -> Term (parts ++ vars)
    refined vs t = foldl (\u, (n, v) => substName n v u) t vs

-- A match is found by comparing names, tags and constants as values; the
-- group it is found in keeps its own.
data GroupMatch : ConType -> List Pat -> Group todo vars -> Type where
     ConMatch : LengthMatch ps newargs ->
                GroupMatch (CName n tag) ps
                  (ConGroup {newargs} n' tag' sp (MkPatClause pvs pats pid rhs :: rest))
     DelayMatch : GroupMatch CDelay []
                    (DelayGroup {tyarg} {valarg} sp (MkPatClause pvs pats pid rhs :: rest))
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
checkGroupMatch (CName x tag) ps (ConGroup {newargs} x' tag' sp (MkPatClause pvs pats pid rhs :: rest))
    = case checkLengthMatch ps newargs of
           Nothing => NoMatch
           Just prf => if x == x' && tag == tag' then ConMatch prf else NoMatch
checkGroupMatch (CName x tag) ps _ = NoMatch
checkGroupMatch CDelay [] (DelayGroup sp (MkPatClause pvs pats pid rhs :: rest))
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
            (ps : List Pat) -> Maybe (NF vars) ->
            Core (args ** (SizeOf args, LengthMatch ps args, NamedPats args (args ++ vars), Maybe (NF vars)))
nextNames fc root unified src [] fty = pure ([] ** (zero, NilMatch, [], fty))
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
          (args ** (l, m, ps, ret)) <- nextNames fc root unified src pats (fst fa_tys)
          let argTy = case snd fa_tys of
                           Unknown => Unknown
                           Known rig t => Known rig (weakenNs (suc l) t)
                           Stuck t => Stuck (weakenNs (suc l) t)
          pure (n :: args ** (suc l, ConsMatch m, MkInfo p First argTy (sourceOf unified src p) :: weaken ps, ret))

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
            List Name -> (scrut : Term vars) ->
            (cs : List01 True (PatClause (a :: todo) vars)) ->
            (0 isCons : All IsConClause cs) =>
            Core (List01 True (Group todo vars))
groupCons fc fn pvars scrut (x :: xs) {isCons = p :: ps}
    = foldlC (uncurry . gc scrut) !(gc scrut [] x p) $ pushIn xs ps
  where
    -- The type of the constructor a split is by, whose arguments are the
    -- parts the split makes: the arrow's, of a domain and a codomain, is
    -- made here.
    conType : {vars' : _} -> SplitBy pargs -> Core (NF vars')
    conType (ByArrow _)
        = pure $ NBind fc (MN (known K_) 0) (Pi fc top Explicit (MkNFClosure defaultOpts (mkEnv fc vars') (NType fc (MN (known Ktop) 0)))) $
              (\d, a => pure $ NBind fc (MN (known K_) 1) (Pi fc top Explicit (MkNFClosure defaultOpts (mkEnv fc vars') (NErased fc Placeholder)))
                (\d, a => pure $ NType fc (MN (known Ktop) 0)))
    conType by
        = do defs <- get Ctxt
             Just t <- lookupTyExact (splitName by) (gamma defs)
                  | Nothing => pure (NErased fc Placeholder)
             nf defs (mkEnv fc vars') (embed t)

    addConG : {vars', todo' : _} ->
              Term vars' -> Source -> (pargs : List Pat) -> SplitBy pargs ->
              NamedPats todo' vars' ->
              Origin -> (rhs : Term vars') ->
              (acc : List01 ne (Group todo' vars')) ->
              Core (List01 True (Group todo' vars'))
    -- Group all the clauses that begin with the same constructor, and
    -- add new pattern arguments for each of that constructor's arguments.
    -- The type of 'ConGroup' ensures that we refer to the arguments by
    -- the same name in each of the clauses
    addConG sty src pargs by pats pid rhs []
        = do (patnames ** (l, m, newargs, ret)) <- nextNames fc (known Ke) (unified pid) src pargs (Just !(conType by))
             -- Update non-linear names in remaining patterns (to keep
             -- explicit dependencies in types accurate)
             let pats' = updatePatNames (updateNames (zip patnames pargs))
                                        (weakenNs l pats)
             let clause = MkPatClause pvars (newargs ++ pats') pid (weakenNs l rhs)
             sp <- fixParts fc l sty ret (splitValue fc by patnames m) (typesOf newargs)
             pure [ConGroup (splitName by) (splitTag by) sp [clause]]
    addConG sty src pargs by pats pid rhs (g :: gs) with (checkGroupMatch (CName (splitName by) (splitTag by)) pargs g)
      addConG sty src pargs by pats pid rhs
              (ConGroup n' tag' sp (MkPatClause pvars ps tid tm :: rest) :: gs) | ConMatch {newargs} lprf
        = do let newps = newPats (unified pid) src pargs lprf ps
             let l = mkSizeOf newargs
             let pats' = updatePatNames (updateNames (zip newargs pargs))
                                        (weakenNs l pats)
             let newclause = MkPatClause pvars (newps ++ pats') pid (weakenNs l rhs)
             -- put the new clause at the end of the group, since we
             -- match the clauses top to bottom.
             pure $ ConGroup n' tag' sp (MkPatClause pvars ps tid tm :: rest ++ [newclause]) :: gs
      addConG sty src pargs by pats pid rhs (g :: gs) | NoMatch
        = (g ::) <$> addConG sty src pargs by pats pid rhs gs

    -- This rather ugly special case is to deal with laziness, where Delay
    -- is like a constructor, but with a special meaning that it forces
    -- evaluation when case analysis reaches it (dealt with in the evaluator
    -- and compiler)
    addDelayG : {vars', todo' : _} ->
                Term vars' -> Source -> Delaying -> Pat -> Pat -> NamedPats todo' vars' ->
                Origin -> (rhs : Term vars') ->
                (acc : List01 ne (Group todo' vars')) ->
                Core (List01 True (Group todo' vars'))
    addDelayG sty src r pty parg pats pid rhs []
        = do let dty = NBind fc (MN (known Ka) 0) (Pi fc erased Explicit (MkNFClosure defaultOpts (mkEnv fc vars') (NType fc (MN (known Ktop) 0)))) $
                        (\d, a =>
                            do a' <- evalClosure d a
                               pure (NBind fc (MN (known Kx) 0) (Pi fc top Explicit a)
                                       (\dv, av => pure (NDelayed fc LUnknown a'))))
             ([tyname, argname] ** (l, ConsMatch (ConsMatch NilMatch), newargs, ret))
                 <- nextNames fc (known Ke) (unified pid) src [pty, parg] (Just dty)
             let pats' = updatePatNames (updateNames [(tyname, pty),
                                                      (argname, parg)])
                                        (weakenNs l pats)
             let clause = MkPatClause pvars (newargs ++ pats') pid (weakenNs l rhs)
             let given = TDelay fc r (Ref fc Bound tyname) (Ref fc Bound argname)
             sp <- fixParts fc l sty ret given (typesOf newargs)
             pure [DelayGroup sp [clause]]
    addDelayG sty src r pty parg pats pid rhs (g :: gs) with (checkGroupMatch CDelay [] g)
      addDelayG sty src r pty parg pats pid rhs
          (DelayGroup sp (MkPatClause pvars ps tid tm :: rest) :: gs) | DelayMatch {tyarg} {valarg}
        = do let l = mkSizeOf [tyarg, valarg]
             let newps = newPats (unified pid) src [pty, parg] (ConsMatch (ConsMatch NilMatch)) ps
             let pats' = updatePatNames (updateNames [(tyarg, pty),
                                                      (valarg, parg)])
                                        (weakenNs l pats)
             let newclause = MkPatClause pvars (newps ++ pats') pid (weakenNs l rhs)
             pure $ DelayGroup sp (MkPatClause pvars ps tid tm :: rest ++ [newclause]) :: gs
      addDelayG sty src r pty parg pats pid rhs (g :: gs) | NoMatch
        = (g ::) <$> addDelayG sty src r pty parg pats pid rhs gs

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
               Term vars -> Source -> (pat : Pat) -> (0 _ : IsConPat pat) =>
               (0 p : IsVar nm idx vars) ->
               NamedPats todo vars -> Origin -> Term vars ->
               List01 ne (Group todo vars) ->
               Core (List01 True (Group todo vars))
    -- In 'As' replace the name on the RHS with a reference to the
    -- variable we're doing the case split on
    addGroup sty src (PAs fc n p) pprf pats pid rhs acc
         = addGroup sty src p pprf pats pid (substName n (Local fc (Just True) idx pprf) rhs) acc
    addGroup sty src (PCon cfc n t a pargs) pprf pats pid rhs acc
         = if a == length pargs
              then addConG sty src pargs (ByData n t a) pats pid rhs acc
              else throw (CaseCompile cfc fn (NotFullyApplied n))
    addGroup sty src (PTyCon cfc n a pargs) pprf pats pid rhs acc
         = if a == length pargs
           then addConG sty src pargs (ByType n a) pats pid rhs acc
           else throw (CaseCompile cfc fn (NotFullyApplied n))
    addGroup sty src (PArrow _ x s t) pprf pats pid rhs acc
         = addConG sty src [s, t] (ByArrow x) pats pid rhs acc
    -- Go inside the delay; we'll flag the case as needing to force its
    -- scrutinee (need to check in 'caseGroups below)
    addGroup sty src (PDelay _ r pty parg) pprf pats pid rhs acc
         = addDelayG sty src r pty parg pats pid rhs acc
    addGroup sty src (PConst _ c) pprf pats pid rhs acc
         = addConstG c pats pid rhs acc

    gc : {a, vars, todo : _} ->
         Term vars ->
         List01 ne (Group todo vars) ->
         (p : PatClause (a :: todo) vars) ->
         (0 _ : IsConClause p) ->
         Core (List01 True (Group todo vars))
    gc sty acc (MkPatClause _ (MkInfo pat pprf _ src :: pats) pid rhs) isCon
        = addGroup sty src pat pprf pats pid rhs acc

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

-- What a clause does with its first column.
firstUse : NamedPats (p :: ps) vars -> Use
firstUse (p :: _) = use (source p) (pat p)

-- Where the clauses put each column: one they only bind, and some bind to
-- what unification found, goes after the others. Each row's first column
-- is read where it stands and the rest arranged from the rows' tails, as
-- the choice of the next column reads them.
arrangement : {todo : _} -> List01 True (NamedPats todo vars) ->
              (now ** after ** Arrangement now after todo)
arrangement {todo = []} rows = (_ ** _ ** NoColumns)
arrangement {todo = _ :: _} rows
    = let (_ ** _ ** placed) = arrangement (map CaseBuilder.tail rows) in
          case foldr (both . firstUse) Binds rows of
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

-- The columns' types in the order `arranged` puts the clauses' columns.
arrangeColumns : Arrangement now after todo -> ColumnTypes todo vars ->
                 ColumnTypes (now ++ after) vars
arrangeColumns placed ts = let (soon, late) = apart placed ts in soon ++ late
  where
    apart : Arrangement now' after' todo' -> ColumnTypes todo' vars ->
            (ColumnTypes now' vars, ColumnTypes after' vars)
    apart NoColumns [] = ([], [])
    apart (InPlace placed') (t :: ts')
        = let (soon, late) = apart placed' ts' in (t :: soon, late)
    apart (Postponed placed') (t :: ts')
        = let (soon, late) = apart placed' ts' in (soon, t :: late)

-- Whether every column's type is known. Where one is not, it is found as the
-- columns before it are split, so the columns keep their order.
typed : NamedPats todo vars -> Bool
typed [] = True
typed (p :: ps)
    = case argType p of
           Known {} => typed ps
           _ => False

-- The column a tree that takes the columns a run keeps first splits next,
-- of a group of columns: the first one a run keeps, or, where it keeps none
-- of them, the last.
total
keptOrLast : {p, ps : _} -> NamedPats (p :: ps) vars -> (n ** NVar n (p :: ps))
keptOrLast {ps = []} _ = (_ ** MkNVar First)
keptOrLast {ps = _ :: _} (pinf :: rest)
    = if kept (argType pinf)
         then (_ ** MkNVar First)
         else let (n ** MkNVar v) = keptOrLast rest in (n ** MkNVar (Later v))
  where
    kept : ArgType vs -> Bool
    kept (Known r _) = not (isErased r)
    kept _ = False

-- The column a tree that takes the columns a run keeps first splits next:
-- of those `arrangement` splits now, if there are any, else of those it
-- splits after them, so that a column postponed still comes after the
-- others.
total
keptFirstIn : {now, after : _} -> Arrangement now after (p :: ps) ->
              NamedPats now vars -> NamedPats after vars -> (n ** NVar n (now ++ after))
keptFirstIn _ soon@(_ :: _) _ = let (n ** v) = keptOrLast soon in (n ** embedNVar v)
keptFirstIn (Postponed _) [] late = keptOrLast late

-- The clauses, and the columns' types, with the column a tree of this
-- order splits next moved first, where pickNextViable takes it if it can.
-- From the left, the first column already is the next.
inOrder : {todo : _} -> SplitOrder -> Lazy (n ** NVar n todo) ->
          ColumnTypes todo vars -> List01 True (PatClause todo vars) ->
          (todo' ** (ColumnTypes todo' vars, List01 True (PatClause todo' vars)))
inOrder FromLeft _ ts cs = (_ ** (ts, cs))
inOrder KeptFirst next ts cs
    = let (nm ** MkNVar el) = Force next in (_ ** (moveColumn el ts, shuffleVars el <$> cs))

-- The clauses' own tests come before what unification fixed from them. A
-- column the clauses only bind, and some bind to what unification found
-- from the patterns they write (an implicit of the definition or of a
-- constructor in a pattern that a clause leaves out, a case block's
-- environment, a with block's argument), is split after the others, at
-- every step. Split before the patterns that fix it, it leaves branches
-- that only the emptiness of a later column's type rules out (`All IsF
-- (A :: xs)`, when `IsF A` has no constructor), which the coverage check
-- finds only by looking into that type, and only while what it looks into
-- gets smaller (`isEmpty`); split after them, those branches are impossible
-- by unification. It is still split: a leaf binds what its pattern names,
-- and a column whose type computes on it (`Lifted r xs y z`) waits for it
-- (pickNextViable). Of the columns split now (all of them, where the
-- columns keep their order), the one the tree's order takes next is moved
-- first (`SplitOrder`).
arrange : {todo : _} -> SplitOrder -> ColumnTypes todo vars ->
          List01 True (PatClause todo vars) ->
          (todo' ** (ColumnTypes todo' vars, List01 True (PatClause todo' vars)))
arrange {todo = []} _ ts cs = (_ ** (ts, cs))
arrange {todo = _ :: _} order ts cs@(c :: _)
    = if typed (getNPs c)
         then let (_ ** _ ** placed) = arrangement (getNPs <$> cs) in
                  inOrder order
                          (let (soon, late) = arrangePats placed (getNPs c) in
                               keptFirstIn placed soon late)
                          (arrangeColumns placed ts)
                          (arranged placed <$> cs)
         else inOrder order (keptOrLast (getNPs c)) ts cs

-- What a tree may assume of a variable a case further up has matched: the
-- alternative of this constructor was taken, or the default, past these
-- constructors.
data Matched = IsCon Name | NoneOf (List Name)

-- The alternatives of a case on the matched variable that can still be
-- taken: under a constructor's alternative, that constructor's, or else the
-- default; under the default, all but the matched constructors'. A data or
-- type constructor is told apart by its name, which is how the evaluator
-- matches a type constructor.
total
taken : Matched -> List (CaseAlt vars) -> List (CaseAlt vars)
taken (IsCon n) alts
    = case filter isThat alts of
           (a :: _) => [a]
           [] => filter isDefault alts
  where
    isThat : CaseAlt vars -> Bool
    isThat (ConCase n' _ _ _) = n == n'
    isThat _ = False
taken (NoneOf ns) alts = filter (not . matchedCon) alts
  where
    matchedCon : CaseAlt vars -> Bool
    matchedCon (ConCase n _ _ _) = n `elem` ns
    matchedCon _ = False

-- A case none of whose alternatives can be taken, which no evaluation
-- reaches, keeps its own: every case the builder makes has an alternative.
total
agreeing : Matched -> List (CaseAlt vars) -> List (CaseAlt vars)
agreeing m alts
    = case taken m alts of
           [] => alts
           kept@(_ :: _) => kept

-- A tree whose cases on a variable a case further up has matched keep only
-- the alternatives that can still be taken (`agreeing`). Evaluation takes
-- the same alternative of the tree as of the tree it prunes: a default is
-- taken only for a constructor none of the others is.
mutual
  pruneCase : Var vars -> Matched -> CaseTree vars -> CaseTree vars
  pruneCase v m (Case idx el ty alts)
      = let alts' = pruneAlts v m alts in
            Case idx el ty (if MkVar el == v then agreeing m alts' else alts')
  pruneCase v m t = t

  pruneAlts : Var vars -> Matched -> List (CaseAlt vars) -> List (CaseAlt vars)
  pruneAlts v m [] = []
  pruneAlts v m (alt :: alts) = pruneAlt v m alt :: pruneAlts v m alts

  pruneAlt : Var vars -> Matched -> CaseAlt vars -> CaseAlt vars
  pruneAlt v m (ConCase n t args sc)
      = ConCase n t args (pruneCase (weakenNs (mkSizeOf args) v) m sc)
  pruneAlt v m (DelayCase t a sc)
      = DelayCase t a (pruneCase (weakenNs (mkSizeOf [t, a]) v) m sc)
  pruneAlt v m (ConstCase c sc) = ConstCase c (pruneCase v m sc)
  pruneAlt v m (DefaultCase sc) = DefaultCase (pruneCase v m sc)

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
          ColumnTypes todo vars ->
          List01 True (PatClause todo vars) ->
          IMaybe ne (CaseTree vars) ->
          Core (CaseTree vars)
  match fc fn phase ts clauses err
      = let (_ ** (ts', clauses')) = arrange (splitOrder phase) ts clauses in
            step fc fn phase ts' clauses' err

  step : {vars, todo : _} ->
         {auto i : Ref PName Int} ->
         {auto c : Ref Ctxt Defs} ->
         FC -> Name -> Phase ->
         ColumnTypes todo vars ->
         List01 True (PatClause todo vars) ->
         IMaybe ne (CaseTree vars) ->
         Core (CaseTree vars)
  -- Before 'partition', reorder the arguments so that the one we
  -- inspect next has a concrete type that is the same in all cases, and
  -- has the most distinct constructors (via pickNextViable)
  step {todo = _ :: _} fc fn phase ts clauses err
      = do (n ** MkNVar next) <- pickNextViable fc phase fn (getNPs <$> clauses)
           log "compile.casetree.pick" 25 $ "Picked " ++ show n ++ " as the next split"
           let clauses' = shuffleVars next <$> clauses
           log "compile.casetree.clauses" 25 $
             unlines ("Using clauses:" :: map (("  " ++) . show) (forget clauses'))
           let ps = partition phase clauses'
           log "compile.casetree.partition" 25 $ "Got Partition:\n" ++ show ps
           Just mix <- mixture fc fn phase (moveColumn next ts) ps err
           log "compile.casetree.intermediate" 25 $ "match: new case tree " ++ show mix
           pure mix
  step {todo = []} fc fn phase ts (MkPatClause pvars [] pid (Erased _ Impossible) :: _) err
       = pure Impossible
  step {todo = []} fc fn phase ts (MkPatClause pvars [] pid rhs :: _) err
       = pure $ STerm (index pid) rhs

  -- A case on the column `pvar`, whose type `ty` names the tree's
  -- variables by name (`ColumnTypes`), each made its local here; the other
  -- columns' types are `ts`, which each alternative refines by the value it
  -- gives the column.
  caseGroups : {pvar, vars, todo : _} ->
               {auto i : Ref PName Int} ->
               {auto c : Ref Ctxt Defs} ->
               FC -> Name -> Phase ->
               {idx : Nat} -> (0 p : IsVar pvar idx vars) -> Term vars ->
               ColumnTypes todo vars ->
               List01 True (Group todo vars) -> IMaybe ne (CaseTree vars) ->
               Core (CaseTree vars)
  caseGroups fc fn phase el ty ts gs errorCase
      = Case idx el (resolveNames vars ty) <$> altGroups gs
    where
      -- The constructors this case matches.
      matched : forall ne. List01 ne (Group todo vars) -> List Name
      matched [] = []
      matched (ConGroup cn _ _ _ :: cs) = cn :: matched cs
      matched (_ :: cs) = matched cs

      -- The fallthrough tree is copied into every alternative. Each copy is
      -- reached only with 'el' known to be that alternative's constructor
      -- (or, for the default, none of the others), so its own cases on 'el'
      -- keep only the alternatives that can still be taken. Without this a
      -- function whose clauses alternate between a constructor and a
      -- wildcard in one argument gets a tree exponential in the number of
      -- clauses.
      altGroups : forall ne. List01 ne (Group todo vars) -> Core (List (CaseAlt vars))
      altGroups [] = pure $ toList $
          DefaultCase . pruneCase (MkVar el) (NoneOf (matched gs)) <$> errorCase
      altGroups (ConGroup {newargs} cn tag sp rest :: cs)
          = do let l = mkSizeOf newargs
               ts' <- refineAll fc ((pvar, sp.given) :: sp.fixed) (weakenNs l ts)
               crest <- match fc fn phase (sp.partTypes ++ ts') rest
                          (map (pruneCase (weakenNs l (MkVar el)) (IsCon cn) . weakenNs l)
                               errorCase)
               cs' <- altGroups cs
               pure (ConCase cn tag newargs crest :: cs')
      altGroups (DelayGroup {tyarg} {valarg} sp rest :: cs)
          = do let l = mkSizeOf [tyarg, valarg]
               ts' <- refineAll fc ((pvar, sp.given) :: sp.fixed) (weakenNs l ts)
               crest <- match fc fn phase (sp.partTypes ++ ts') rest (map (weakenNs l) errorCase)
               cs' <- altGroups cs
               pure (DelayCase tyarg valarg crest :: cs')
      altGroups (ConstGroup c rest :: cs)
          = do ts' <- refineColumns fc pvar (PrimVal fc c) ts
               crest <- match fc fn phase ts' rest errorCase
               cs' <- altGroups cs
               pure (ConstCase c crest :: cs')

  conRule : {a, vars, todo : _} ->
            {auto i : Ref PName Int} ->
            {auto c : Ref Ctxt Defs} ->
            FC -> Name -> Phase ->
            ColumnTypes (a :: todo) vars ->
            (cs : List01 True (PatClause (a :: todo) vars)) ->
            (0 isCons : All IsConClause cs) =>
            IMaybe ne (CaseTree vars) ->
            Core (CaseTree vars)
  -- ASSUMPTION, not expressed in the type, that the patterns all have
  -- the same variable (pprf) for the first argument. If not, the result
  -- will be a broken case tree... so we should find a way to express this
  -- in the type if we can.
  conRule {a} fc fn phase (aty :: ts) cs@(MkPatClause pvars (MkInfo pat pprf _ _ :: pats) pid rhs :: rest) err
      = do Element refinedcs _ <- pullOut <$> traverseList01 (substInClause fc) (pushIn cs isCons)
           -- The scrutinee's type is the column's, as the tree knows it
           -- here (`ColumnTypes`), never a clause's copy, which names that
           -- clause's pattern variables.
           ty <- case aty of
                      Known _ t => pure t
                      _ => throw (CaseCompile fc fn UnknownType)
           groups <- groupCons fc fn pvars ty refinedcs
           caseGroups fc fn phase pprf ty ts groups err

  varRule : {a, vars, todo : _} ->
            {auto i : Ref PName Int} ->
            {auto c : Ref Ctxt Defs} ->
            FC -> Name -> Phase ->
            ColumnTypes (a :: todo) vars ->
            List01 True (PatClause (a :: todo) vars) ->
            IMaybe ne (CaseTree vars) ->
            Core (CaseTree vars)
  varRule fc fn phase (_ :: ts) cs err
      = do alts' <- traverseList01 updateVar cs
           match fc fn phase ts alts' err
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
            ColumnTypes (a :: todo) vars ->
            Partitions ps ->
            IMaybe neErr (CaseTree vars) ->
            Core (IMaybe (ne || neErr) (CaseTree vars))
  mixture fc fn phase ts (ConClauses cs rest) err
      = do fallthrough <- mixture fc fn phase ts rest err
           Just <$> conRule fc fn phase ts cs fallthrough
  mixture fc fn phase ts (VarClauses vs rest) err
      = do fallthrough <- mixture fc fn phase ts rest err
           Just <$> varRule fc fn phase ts vs fallthrough
  mixture fc fn phase ts NoClauses err
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
         cases <- match fc fn phase (startColumns pats) pats Nothing
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

    -- Where the tree starts, every clause's types are the function type's
    -- (`typesOf`).
    startColumns : List01 True (PatClause todo vs) -> ColumnTypes todo vs
    startColumns (c :: _) = typesOf (getNPs c)

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
