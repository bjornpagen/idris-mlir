-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Case.CaseTree

import Core.TT

import Data.DPair
import Data.List
import Data.So
import Data.String
import Idris.Pretty.Annotations

import Libraries.Data.NameMap
import Libraries.Text.PrettyPrint.Prettyprinter
import Libraries.Data.List.SizeOf

%default covering

-- A case tree's terms (each case's scrutinee type and each leaf's
-- right-hand side) are held as the definition holds them: `CaseTree` is a
-- tree of live terms, as the current module's definitions are; a stored
-- definition's tree holds the roots of its arena (`Core.TT.Stored`). The
-- tree's shape, its scopes and its proofs are the same for both.
mutual
  ||| Case trees in A-normal forms
  ||| i.e. we may only dispatch on variables, not expressions
  public export
  data CaseTree' : Scoped -> Scoped where
       ||| case x return scTy of { p1 => e1 ; ... }
       Case : {name : _} ->
              (idx : Nat) ->
              (0 p : IsVar name idx vars) ->
              (scTy : t vars) -> List (CaseAlt' t vars) ->
              CaseTree' t vars
       ||| RHS: no need for further inspection
       ||| The Int is a clause id that allows us to see which of the
       ||| initial clauses are reached in the tree
       STerm : Int -> t vars -> CaseTree' t vars
       ||| error from a partial match
       Unmatched : (msg : String) -> CaseTree' t vars
       ||| Absurd context
       Impossible : CaseTree' t vars

  ||| Case alternatives. Unlike arbitrary patterns, they can be at most
  ||| one constructor deep.
  public export
  data CaseAlt' : Scoped -> Scoped where
       ||| Constructor for a data type; bind the arguments and subterms.
       ConCase : Name -> (tag : Int) -> (args : List Name) ->
                 CaseTree' t (Scope.addInner vars args) -> CaseAlt' t vars
       ||| Lazy match for the Delay type use for codata types
       DelayCase : (ty : Name) -> (arg : Name) ->
                   CaseTree' t (Scope.addInner vars [ty, arg]) -> CaseAlt' t vars
                   -- TODO `arg` and `ty` should be swapped, as in Yaffle
       ||| Match against a literal
       ConstCase : Constant -> CaseTree' t vars -> CaseAlt' t vars
       ||| Catch-all case
       DefaultCase : CaseTree' t vars -> CaseAlt' t vars

||| A case tree of live terms.
public export
CaseTree : Scoped
CaseTree = CaseTree' Term

||| An alternative of a case tree of live terms.
public export
CaseAlt : Scoped
CaseAlt = CaseAlt' Term

mutual
  public export
  measure : CaseTree' t vars -> Nat
  measure (Case idx p scTy xs) = sum $ measureAlts <$> xs
  measure (STerm x y) = 0
  measure (Unmatched msg) = 0
  measure Impossible = 0

  measureAlts : CaseAlt' t vars -> Nat
  measureAlts (ConCase x tag args y) = 1 + (measure y)
  measureAlts (DelayCase ty arg x) = 1 + (measure x)
  measureAlts (ConstCase x y) = 1 + (measure y)
  measureAlts (DefaultCase x) = 1 + (measure x)

-- A case tree with `g` applied to each term it holds, given the size of
-- the scope the term is in, each alternative's subtree in the scope its
-- pattern extends; the alternatives in a list of their own, so that every
-- recursive call is on a part of its argument. The tree's shape is kept:
-- this is how a tree's terms change lifetime.
mutual
  export
  traverseTree : Applicative f => (forall vs . SizeOf vs -> t vs -> f (u vs)) ->
                 SizeOf vars -> CaseTree' t vars -> f (CaseTree' u vars)
  traverseTree g s (Case {name} idx p scTy alts)
      = Case {name} idx p <$> g s scTy <*> traverseAlts g s alts
  traverseTree g s (STerm i x) = STerm i <$> g s x
  traverseTree g s (Unmatched msg) = pure (Unmatched msg)
  traverseTree g s Impossible = pure Impossible

  traverseAlts : Applicative f => (forall vs . SizeOf vs -> t vs -> f (u vs)) ->
                 SizeOf vars -> List (CaseAlt' t vars) -> f (List (CaseAlt' u vars))
  traverseAlts g s [] = pure []
  traverseAlts g s (alt :: alts) = (::) <$> traverseAlt g s alt <*> traverseAlts g s alts

  traverseAlt : Applicative f => (forall vs . SizeOf vs -> t vs -> f (u vs)) ->
                SizeOf vars -> CaseAlt' t vars -> f (CaseAlt' u vars)
  traverseAlt g s (ConCase n tag args sc)
      = ConCase n tag args <$> traverseTree g (mkSizeOf args + s) sc
  traverseAlt g s (DelayCase ty arg sc)
      = DelayCase ty arg <$> traverseTree g (suc (suc s)) sc
  traverseAlt g s (ConstCase c sc) = ConstCase c <$> traverseTree g s sc
  traverseAlt g s (DefaultCase sc) = DefaultCase <$> traverseTree g s sc

export
isDefault : CaseAlt' t vars -> Bool
isDefault (DefaultCase _) = True
isDefault _ = False

-- A case tree with `f` applied to each term it holds (each case's
-- scrutinee type and each leaf's term), its alternatives in a list of
-- their own, so that every recursive call is on a part of its argument.
mutual
  onTreeTerms : (forall vs . Term vs -> Term vs) -> CaseTree vars -> CaseTree vars
  onTreeTerms f (Case idx p scTy xs) = Case idx p (f scTy) (onAltsTerms f xs)
  onTreeTerms f (STerm x t) = STerm x (f t)
  onTreeTerms f c = c

  onAltsTerms : (forall vs . Term vs -> Term vs) -> List (CaseAlt vars) -> List (CaseAlt vars)
  onAltsTerms f [] = []
  onAltsTerms f (alt :: alts) = onAltTerms f alt :: onAltsTerms f alts

  onAltTerms : (forall vs . Term vs -> Term vs) -> CaseAlt vars -> CaseAlt vars
  onAltTerms f (ConCase x tag args t) = ConCase x tag args (onTreeTerms f t)
  onAltTerms f (DelayCase ty arg t) = DelayCase ty arg (onTreeTerms f t)
  onAltTerms f (ConstCase x t) = ConstCase x (onTreeTerms f t)
  onAltTerms f (DefaultCase t) = DefaultCase (onTreeTerms f t)

export
StripNamespace (CaseTree vars) where
  trimNS ns = onTreeTerms (trimNS ns)
  restoreNS ns = onTreeTerms (restoreNS ns)

export
StripNamespace (CaseAlt vars) where
  trimNS ns = onAltTerms (trimNS ns)
  restoreNS ns = onAltTerms (restoreNS ns)


-- A clause's argument as the case builder read it. A term it holds (one a
-- pattern cannot match) is held as the definition holds its terms: `Pat`
-- holds a live term, a stored definition's a root of its arena.
public export
data Pat' : Type -> Type where
     PAs : FC -> Name -> Pat' tm -> Pat' tm
     PCon : FC -> Name -> (tag : Int) -> (arity : Nat) ->
            List (Pat' tm) -> Pat' tm
     PTyCon : FC -> Name -> (arity : Nat) -> List (Pat' tm) -> Pat' tm
     PConst : FC -> (c : Constant) -> Pat' tm
     PArrow : FC -> (x : Name) -> Pat' tm -> Pat' tm -> Pat' tm
     PDelay : FC -> Delaying -> Pat' tm -> Pat' tm -> Pat' tm
     -- TODO: Matching on lazy types
     PLoc : FC -> Name -> Pat' tm
     PUnmatchable : FC -> tm -> Pat' tm

||| A clause's argument holding live terms.
public export
Pat : Type
Pat = Pat' ClosedTerm

-- A pattern with `g` applied to each term it holds; the patterns a pattern
-- holds are in a list of their own, so that every recursive call is on a
-- part of its argument. This is how a pattern's terms change lifetime.
mutual
  export
  traversePat : Applicative f => (a -> f b) -> Pat' a -> f (Pat' b)
  traversePat g (PAs fc n p) = PAs fc n <$> traversePat g p
  traversePat g (PCon fc n tag ar ps) = PCon fc n tag ar <$> traversePats g ps
  traversePat g (PTyCon fc n ar ps) = PTyCon fc n ar <$> traversePats g ps
  traversePat g (PConst fc c) = pure (PConst fc c)
  traversePat g (PArrow fc x s t) = PArrow fc x <$> traversePat g s <*> traversePat g t
  traversePat g (PDelay fc r t p) = PDelay fc r <$> traversePat g t <*> traversePat g p
  traversePat g (PLoc fc n) = pure (PLoc fc n)
  traversePat g (PUnmatchable fc x) = PUnmatchable fc <$> g x

  export
  traversePats : Applicative f => (a -> f b) -> List (Pat' a) -> f (List (Pat' b))
  traversePats g [] = pure []
  traversePats g (p :: ps) = (::) <$> traversePat g p <*> traversePats g ps

export
isPConst : Pat -> Maybe Constant
isPConst (PConst _ c) = Just c
isPConst _ = Nothing

public export
0 isConPat : Pat -> Bool
isConPat (PAs _ _ p) = isConPat p
isConPat (PCon {}) = True
isConPat (PTyCon {}) = True
isConPat (PConst {}) = True
isConPat (PArrow {}) = True
isConPat (PDelay {}) = True
isConPat _ = False

public export
0 IsConPat : Pat -> Type
IsConPat = So . isConPat

-- A case tree shown with each term it holds shown by `sh`, in the scope
-- the term is in.
total
showCT : ({vs : Scope} -> t vs -> String) ->
         {vars : _} -> (indent : String) -> CaseTree' t vars -> String
total
showCA : ({vs : Scope} -> t vs -> String) ->
         {vars : _} -> (indent : String) -> CaseAlt' t vars  -> String
total
showCAs : ({vs : Scope} -> t vs -> String) ->
          {vars : _} -> (indent : String) -> List (CaseAlt' t vars) -> List String

showCT sh indent (Case {name} idx prf ty alts)
  = "case " ++ show name ++ "[" ++ show idx ++ "] : " ++ sh ty ++ " of"
  ++ "\n" ++ indent ++ " { "
  ++ showSep ("\n" ++ indent ++ " | ") (showCAs sh ("  " ++ indent) alts)
  ++ "\n" ++ indent ++ " }"
showCT sh indent (STerm i tm) = "[" ++ show i ++ "] " ++ sh tm
showCT sh indent (Unmatched msg) = "Error: " ++ show msg
showCT sh indent Impossible = "Impossible"

showCA sh indent (ConCase n tag args sc)
        = showSep " " (map show (n :: args)) ++ " => " ++
          showCT sh indent sc
showCA sh indent (DelayCase _ arg sc)
        = "Delay " ++ show arg ++ " => " ++ showCT sh indent sc
showCA sh indent (ConstCase c sc)
        = "Constant " ++ show c ++ " => " ++ showCT sh indent sc
showCA sh indent (DefaultCase sc)
        = "_ => " ++ showCT sh indent sc

showCAs sh indent [] = []
showCAs sh indent (alt :: alts) = showCA sh indent alt :: showCAs sh indent alts

||| A case tree shown with each term it holds shown by `sh`.
export
showTree : ({vs : Scope} -> t vs -> String) ->
           {vars : _} -> CaseTree' t vars -> String
showTree sh = showCT sh ""

export
{vars : _} -> Show (CaseTree vars) where
  show = showCT showTerm ""

export
{vars : _} -> Show (CaseAlt vars) where
  show = showCA showTerm ""

mutual
  export
  eqTree : CaseTree vs -> CaseTree vs' -> Bool
  eqTree (Case i _ _ alts) (Case i' _ _ alts')
      = i == i'
       && length alts == length alts'
       && all (uncurry eqAlt) (zip alts alts')
  eqTree (STerm _ t) (STerm _ t') = eqTerm t t'
  eqTree (Unmatched _) (Unmatched _) = True
  eqTree Impossible Impossible = True
  eqTree _ _ = False

  eqAlt : CaseAlt vs -> CaseAlt vs' -> Bool
  eqAlt (ConCase n t args tree) (ConCase n' t' args' tree')
      = n == n' && eqTree tree tree' -- assume arities match, since name does
  eqAlt (DelayCase _ _ tree) (DelayCase _ _ tree')
      = eqTree tree tree'
  eqAlt (ConstCase c tree) (ConstCase c' tree')
      = c == c' && eqTree tree tree'
  eqAlt (DefaultCase tree) (DefaultCase tree')
      = eqTree tree tree'
  eqAlt _ _ = False

export
covering
Show Pat where
  show (PAs _ n p) = show n ++ "@(" ++ show p ++ ")"
  show (PCon _ n i _ args) = show n ++ " " ++ show i ++ " " ++ assert_total (show args)
  show (PTyCon _ n _ args) = "<TyCon>" ++ show n ++ " " ++ assert_total (show args)
  show (PConst _ c) = show c
  show (PArrow _ x s t) = "(" ++ show s ++ " -> " ++ show t ++ ")"
  show (PDelay _ _ _ p) = "(Delay " ++ show p ++ ")"
  show (PLoc _ n) = show n
  show (PUnmatchable _ tm) = ".(" ++ show tm ++ ")"

export
Pretty IdrisSyntax Pat where
  prettyPrec d (PAs _ n p) = pretty0 n <++> keyword "@" <+> parens (pretty p)
  prettyPrec d (PCon _ n _ _ args) =
    parenthesise (d > Open) $ hsep (pretty0 n :: map (prettyPrec App) args)
  prettyPrec d (PTyCon _ n _ args) =
    parenthesise (d > Open) $ hsep (pretty0 n :: map (prettyPrec App) args)
  prettyPrec d (PConst _ c) = pretty c
  prettyPrec d (PArrow _ _ p q) =
    parenthesise (d > Open) $ pretty p <++> arrow <++> pretty q
  prettyPrec d (PDelay _ _ _ p) = parens ("Delay" <++> pretty p)
  prettyPrec d (PLoc _ n) = pretty0 n
  prettyPrec d (PUnmatchable _ tm) = keyword "." <+> parens (byShow tm)

mutual
  insertCaseNames : SizeOf outer ->
                    SizeOf ns ->
                    CaseTree (outer ++ inner) ->
                    CaseTree (outer ++ (ns ++ inner))
  insertCaseNames outer ns (Case idx prf scTy alts)
      = let MkNVar prf' = insertNVarNames outer ns (MkNVar prf) in
            Case _ prf' (insertNames outer ns scTy)
                (map (insertCaseAltNames outer ns) alts)
  insertCaseNames outer ns (STerm i x) = STerm i (insertNames outer ns x)
  insertCaseNames _ _ (Unmatched msg) = Unmatched msg
  insertCaseNames _ _ Impossible = Impossible

  insertCaseAltNames : SizeOf outer ->
                       SizeOf ns ->
                       CaseAlt (outer ++ inner) ->
                       CaseAlt (outer ++ (ns ++ inner))
  insertCaseAltNames p q (ConCase x tag args ct)
      = ConCase x tag args
           (rewrite appendAssociative args outer (ns ++ inner) in
                    insertCaseNames (mkSizeOf args + p) q {inner}
                        (rewrite sym (appendAssociative args outer inner) in
                                 ct))
  insertCaseAltNames outer ns (DelayCase tyn valn ct)
      = DelayCase tyn valn
                  (insertCaseNames (suc (suc outer)) ns ct)
  insertCaseAltNames outer ns (ConstCase x ct)
      = ConstCase x (insertCaseNames outer ns ct)
  insertCaseAltNames outer ns (DefaultCase ct)
      = DefaultCase (insertCaseNames outer ns ct)

export
Weaken CaseTree where
  weakenNs ns t = insertCaseNames zero ns t

total
getNames : (forall vs . NameMap Bool -> Term vs -> NameMap Bool) ->
           NameMap Bool -> CaseTree vars -> NameMap Bool
getNames add ns sc = getSet ns sc
  where
    mutual
      getAltSet : NameMap Bool -> CaseAlt vs -> NameMap Bool
      getAltSet ns (ConCase n t args sc) = getSet ns sc
      getAltSet ns (DelayCase t a sc) = getSet ns sc
      getAltSet ns (ConstCase i sc) = getSet ns sc
      getAltSet ns (DefaultCase sc) = getSet ns sc

      getAltSets : NameMap Bool -> List (CaseAlt vs) -> NameMap Bool
      getAltSets ns [] = ns
      getAltSets ns (a :: as) = getAltSets (getAltSet ns a) as

      getSet : NameMap Bool -> CaseTree vs -> NameMap Bool
      getSet ns (Case _ x ty xs) = getAltSets ns xs
      getSet ns (STerm i tm) = add ns tm
      getSet ns (Unmatched msg) = ns
      getSet ns Impossible = ns

export total
getRefs : (aTotal : Name) -> CaseTree vars -> NameMap Bool
getRefs at = getNames (addRefs False at) empty

export total
addRefs : (aTotal : Name) -> NameMap Bool -> CaseTree vars -> NameMap Bool
addRefs at ns = getNames (addRefs False at) ns

export total
getMetas : CaseTree vars -> NameMap Bool
getMetas = getNames (addMetas False) empty

export
mkTerm : (vars : Scope) -> Pat -> Term vars
mkTerm vars (PAs fc x y) = mkTerm vars y
mkTerm vars (PCon fc x tag arity xs)
    = apply fc (Ref fc (DataCon tag arity) x)
               (map (mkTerm vars) xs)
mkTerm vars (PTyCon fc x arity xs)
    = apply fc (Ref fc (TyCon arity) x)
               (map (mkTerm vars) xs)
mkTerm vars (PConst fc c) = PrimVal fc c
mkTerm vars (PArrow fc x s t)
    = Bind fc x (Pi fc top Explicit (mkTerm vars s)) (mkTerm (x :: vars) t)
mkTerm vars (PDelay fc r ty p)
    = TDelay fc r (mkTerm vars ty) (mkTerm vars p)
mkTerm vars (PLoc fc n)
    = case isVar n vars of
           Just (MkVar prf) => Local fc Nothing _ prf
           _ => Ref fc Bound n
mkTerm vars (PUnmatchable fc tm) = embed tm
