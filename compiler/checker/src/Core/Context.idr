-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Context

import        Core.Case.CaseTree
import public Core.Context.Context
import public Core.Core
import        Core.Env
import        Core.Hash
import public Core.Name
import        Core.Options
import public Core.Options.Log
import public Core.TT
import        Core.TT.Stored

import Libraries.Utils.Binary
import Libraries.Utils.Path
import Libraries.Text.PrettyPrint.Prettyprinter

import Idris.Syntax.Pragmas

import Control.Monad.Identity
import Data.DPair
import Data.Either
import Data.List1
import Data.String
import Data.Nat
import Libraries.Data.IntMap
import Libraries.Data.List.SizeOf
import Libraries.Data.NameMap
import Libraries.Data.NatSet
import Libraries.Data.StringMap
import Libraries.Data.Table
import Libraries.Data.UserNameMap
import Libraries.Data.VarSet
import Libraries.Data.WithDefault
import Libraries.Text.Distance.Levenshtein

import System.Clock
import System.Directory

%default covering

export
namesResolvedAs : Context -> NameMap Name
namesResolvedAs ctxt = map Resolved ctxt.resolvedAs

-- Implemented later, once we can convert to and from full names
-- Defined in Core.TTC
export total
decode : Context -> Int -> (update : Bool) -> ContextEntry -> Core GlobalDef

initSize : Int
initSize = 10000

export
initCtxtS : Ref Interned Idents -> Int -> Core Context
initCtxtS ids s
    = do aref <- coreLift (newTable s)
         pure $ MkContext
            { firstEntry = 0
            , nextEntry = 0
            , resolvedAs = empty
            , undefinedNames = empty
            , possibles = empty
            , content = aref
            , branchDepth = 0
            , staging = empty
            , visibleNS = []
            , allPublic = False
            , inlineOnly = False
            , hidden = empty
            , uconstraints = []
            , idents = ids
            }

export
initCtxt : Ref Interned Idents -> Core Context
initCtxt ids = initCtxtS ids initSize

addPossible : Name -> Int ->
              UserNameMap (List PossibleName) -> UserNameMap (List PossibleName)
addPossible n i ps
    = case userNameRoot n of
           Nothing => ps
           Just nr =>
              case lookup nr ps of
                   Nothing => insert nr [Direct n i] ps
                   Just nis => insert nr (Direct n i :: nis) ps

addAlias : Name -> Name -> Int ->
           UserNameMap (List PossibleName) -> UserNameMap (List PossibleName)
addAlias alias full i ps
    = case userNameRoot alias of
           Nothing => ps
           Just nr =>
              case lookup nr ps of
                   Nothing => insert nr [Alias alias full i] ps
                   Just nis => insert nr (Alias alias full i :: nis) ps

export
newEntry : Name -> Context -> Core (Int, Context)
newEntry n ctxt
    = do let idx = nextEntry ctxt
         -- An index a restored Defs hands out again keeps its slot; a
         -- fresh one is one past the last.
         coreLift (claimSlot idx (content ctxt))
         pure (idx, { nextEntry := idx + 1,
                      resolvedAs $= insert n idx,
                      undefinedNames $= insert idx n,
                      possibles $= addPossible n idx
                    } ctxt)

||| The entry at `idx`: none for an index the context never made, nor for
||| one made and not yet written.
export
entryAt : Context -> Int -> Core (Maybe ContextEntry)
entryAt ctxt idx = coreLift (lookupSlot idx (content ctxt))

||| `entry` at `idx`, an index the context has made.
export
setEntry : Context -> Int -> ContextEntry -> Core ()
setEntry ctxt idx entry
    = coreLift (setSlot idx entry (content ctxt))

-- Get the position of the next entry in the context array, growing the
-- array if it's out of bounds.
-- Updates the context with the mapping from name to index
export
getPosition : Name -> Context -> Core (Int, Context)
getPosition (Resolved idx) ctxt = pure (idx, ctxt)
getPosition n ctxt
    = case lookup n (resolvedAs ctxt) of
           Just idx =>
              do pure (idx, ctxt)
           Nothing => newEntry n ctxt

newAlias : Name -> Name -> Context -> Core Context
newAlias alias full ctxt
    = do (idx, ctxt) <- getPosition full ctxt
         pure $ { possibles $= addAlias alias full idx } ctxt

-- Public, so that a proof over the context reads off this definition that
-- a resolved name is its own entry.
public export
getNameID : Name -> Context -> Maybe Int
getNameID (Resolved idx) ctxt = Just idx
getNameID n ctxt = lookup n (resolvedAs ctxt)

-- Add the name to the context, or update the existing entry if it's already
-- there.
-- If we're not at the top level, add it to the staging area.
-- Either way the position is defined from here on: its name is its
-- definition's, no longer one of the undefined names.
export
addCtxt : Name -> GlobalDef -> Context -> Core (Int, Context)
addCtxt n val ctxt_in
    = if branchDepth ctxt_in == 0
         then do (idx, ctxt) <- getPosition n ctxt_in
                 setEntry ctxt idx (Decoded val)
                 pure (idx, { undefinedNames $= delete idx } ctxt)
         else do (idx, ctxt) <- getPosition n ctxt_in
                 pure (idx, { staging $= insert idx (Decoded val),
                              undefinedNames $= delete idx } ctxt)

export
addEntry : Name -> ContextEntry -> Context -> Core (Int, Context)
addEntry n entry ctxt_in
    = if branchDepth ctxt_in == 0
         then do (idx, ctxt) <- getPosition n ctxt_in
                 setEntry ctxt idx entry
                 pure (idx, { undefinedNames $= delete idx } ctxt)
         else do (idx, ctxt) <- getPosition n ctxt_in
                 pure (idx, { staging $= insert idx entry,
                              undefinedNames $= delete idx } ctxt)

returnDef : Bool -> Int -> GlobalDef -> Maybe (Int, GlobalDef)
returnDef False idx def = Just (idx, def)
returnDef True idx def
    = case definition def of
           PMDef pi _ _ =>
                 if alwaysReduce pi
                    then Just (idx, def)
                    else Nothing
           _ => Nothing

-- A name's entry: the name is turned into its index once (`getNameID`),
-- and the entry at the index is a staged one if there is one.
export
lookupContextEntry : Name -> Context -> Core (Maybe (Int, ContextEntry))
lookupContextEntry n ctxt
    = do let Just idx = getNameID n ctxt
               | Nothing => pure Nothing
         case lookup idx (staging ctxt) of
              Just entry => pure (Just (idx, entry))
              Nothing =>
                 do Just entry <- entryAt ctxt idx
                         | Nothing => pure Nothing
                    pure (Just (idx, entry))

export
lookupCtxtExactI : Name -> Context -> Core (Maybe (Int, GlobalDef))
lookupCtxtExactI n ctxt
    = do Just (idx, entry) <- lookupContextEntry n ctxt
              | Nothing => pure Nothing
         pure $ returnDef (inlineOnly ctxt) idx !(decode ctxt idx True entry)

export
lookupCtxtExact : Name -> Context -> Core (Maybe GlobalDef)
lookupCtxtExact n ctxt = map snd <$> lookupCtxtExactI n ctxt

||| Check if the given name has been hidden by the `%hide` directive.
export
isHidden : Name -> Context -> Bool
isHidden fulln ctxt = isJust $ lookup fulln (hidden ctxt)

||| Look up a possibly hidden name in the context. The first (boolean) argument
||| controls whether names hidden by `%hide` are returned too (True=yes, False=no).
export
lookupCtxtName' : Bool -> Name -> Context -> Core (List (Name, Int, GlobalDef))
lookupCtxtName' allowHidden n ctxt
    = case userNameRoot n of
           Nothing => do Just (i, res) <- lookupCtxtExactI n ctxt
                              | Nothing => pure []
                         pure [(n, i, res)]
           Just r =>
              do let Just ps = lookup r (possibles ctxt)
                      | Nothing => pure []
                 lookupPossibles [] ps
  where

    resn : (Name, Int, GlobalDef) -> Int
    resn (_, i, _) = i

    hlookup : Name -> NameMap () -> Maybe ()
    hlookup fulln hiddens = if allowHidden
      then Nothing
      else lookup fulln hiddens

    lookupPossibles : List (Name, Int, GlobalDef) -> -- accumulator
                      List PossibleName ->
                      Core (List (Name, Int, GlobalDef))
    lookupPossibles acc [] = pure (reverse acc)
    lookupPossibles acc (Direct fulln i :: ps)
       = case (hlookup fulln (hidden ctxt)) of
              Nothing =>
                do Just res <- lookupCtxtExact (Resolved i) ctxt
                        | Nothing => lookupPossibles acc ps
                   if matches n fulln && not (i `elem` map resn acc)
                      then lookupPossibles ((fulln, i, res) :: acc) ps
                      else lookupPossibles acc ps
              _ => lookupPossibles acc ps
    lookupPossibles acc (Alias asn fulln i :: ps)
       = case (hlookup fulln (hidden ctxt)) of
              Nothing =>
                do Just res <- lookupCtxtExact (Resolved i) ctxt
                        | Nothing => lookupPossibles acc ps
                   if (matches n asn) && not (i `elem` map resn acc)
                      then lookupPossibles ((fulln, i, res) :: acc) ps
                      else lookupPossibles acc ps
              _ => lookupPossibles acc ps

||| Look up a name in the context, ignoring names hidden by `%hide`.
export
lookupCtxtName : Name -> Context -> Core (List (Name, Int, GlobalDef))
lookupCtxtName = lookupCtxtName' False

||| Look up a (possible hidden) name in the context.
export
lookupHiddenCtxtName : Name -> Context -> Core (List (Name, Int, GlobalDef))
lookupHiddenCtxtName = lookupCtxtName' True

hideName : Name -> Context -> Context
hideName n ctxt = { hidden $= insert n () } ctxt

unhideName : Name -> Context -> Context
unhideName n ctxt = { hidden $= delete n } ctxt

branchCtxt : Context -> Core Context
branchCtxt ctxt = pure ({ branchDepth $= S } ctxt)

commitCtxt : Context -> Core Context
commitCtxt ctxt
    = case branchDepth ctxt of
           Z => pure ctxt
           S Z => -- add all the things from 'staging' to the real array,
                  -- which has every staged index: each was made in the
                  -- branch
                  do traverse_ (\(idx, val) => setEntry ctxt idx val)
                               (toList (staging ctxt))
                     pure ({ staging := empty,
                             branchDepth := Z } ctxt)
           S k => pure ({ branchDepth := k } ctxt)

||| Produce a new global definition with a lot of default values
||| @fc   definition site
||| @n    name
||| @rig  quantity annotation
||| @vars local variables
||| @ty   (closed) type
||| @vis  Visibility, defaulting to private
||| @def  actual definition
export
newDef : (fc : FC) -> (n : Name) -> (rig : RigCount) -> (vars : Scope) ->
         (ty : ClosedTerm) -> (vis : WithDefault Visibility Private) -> (def : Def) -> GlobalDef
newDef fc n rig vars ty vis def
    = MkGlobalDef
        { location = fc
        , fullname = n
        , type = LiveType ty
        , eraseArgs = NatSet.empty
        , safeErase = NatSet.empty
        , specArgs = NatSet.empty
        , inferrable = NatSet.empty
        , multiplicity = rig
        , localVars = vars
        , visibility = vis
        , totality = unchecked
        , isEscapeHatch = False
        , flags = []
        , refersToM = Nothing
        , invertible = False
        , noCycles = False
        , linearChecked = False
        , definition = def
        , sizeChange = []
        }

-- Rewrite rules, applied after type checking, for runtime code only
||| Types that are transformed into a faster representation
||| during codegen.
public export
data BuiltinType : Type where
    BuiltinNatural : BuiltinType
    NaturalToInteger : BuiltinType
    IntegerToNatural : BuiltinType

export
Show BuiltinType where
    show BuiltinNatural = "Natural"
    show NaturalToInteger = "NaturalToInteger"
    show IntegerToNatural = "IntegerToNatural"

-- TODO: refactor via a single function
-- onNames : (Context -> Name -> Core Name) ->
--           (Context -> a    -> Core a)
-- ?
public export
interface HasNames a where
  full : Context -> a -> Core a
  resolved : Context -> a -> Core a

-- Resolving a name is a lookup of its index, and looks up no definition.
-- Resolving a definition decoded from a TTC is the functions named
-- `resolve...` below, which the instances' `resolved` are: decoding
-- resolves through them, never through an instance, whose `full` looks up
-- definitions and so may decode another.
indexedName : Context -> Name -> Name
indexedName gam n = maybe n Resolved (getNameID n gam)

export
HasNames Name where
  -- A position's full name is the name it was given while nothing is
  -- defined there (a declaration whose type is being checked), and else its
  -- definition's. A position the context never gave, as metadata may hold,
  -- stays as it is.
  full gam (Resolved i)
      = case lookup i (undefinedNames gam) of
             Just n => pure n
             Nothing =>
               do Just gdef <- lookupCtxtExact (Resolved i) gam
                       | Nothing => pure (Resolved i)
                  pure (fullname gdef)
  full gam n = pure n

  resolved gam n = pure (indexedName gam n)

export
HasNames UConstraint where
  full gam (ULT x y)
      = do x' <- full gam x; y' <- full gam y
           pure (ULT x' y')
  full gam (ULE x y)
      = do x' <- full gam x; y' <- full gam y
           pure (ULE x' y')

  resolved gam (ULT x y)
      = do x' <- resolved gam x; y' <- resolved gam y
           pure (ULT x' y')
  resolved gam (ULE x y)
      = do x' <- resolved gam x; y' <- resolved gam y
           pure (ULE x' y')

-- Making a term's names full and resolving them are one traversal, given
-- what becomes of a name (`full` or `resolved` of the name) and of a
-- metavariable's name and index: making it full names it after its index,
-- resolving it indexes it by its name. Each kind of node that holds terms
-- is traversed by a function of its own, so that every recursive call is
-- on a part of its argument.
record OnNames where
  constructor MkOnNames
  onName : Name -> Core Name
  onMeta : Name -> Int -> Core (Name, Int)

mutual
  onNamesPi : OnNames -> PiInfo (Term vars) -> Core (PiInfo (Term vars))
  onNamesPi f (DefImplicit t) = DefImplicit <$> onNamesTerm f t
  onNamesPi f p = pure p

  onNamesBinder : OnNames -> Binder (Term vars) -> Core (Binder (Term vars))
  onNamesBinder f (Lam fc c p ty) = pure (Lam fc c !(onNamesPi f p) !(onNamesTerm f ty))
  onNamesBinder f (Let fc c val ty) = pure (Let fc c !(onNamesTerm f val) !(onNamesTerm f ty))
  onNamesBinder f (Pi fc c p ty) = pure (Pi fc c !(onNamesPi f p) !(onNamesTerm f ty))
  onNamesBinder f (PVar fc c p ty) = pure (PVar fc c !(onNamesPi f p) !(onNamesTerm f ty))
  onNamesBinder f (PLet fc c val ty) = pure (PLet fc c !(onNamesTerm f val) !(onNamesTerm f ty))
  onNamesBinder f (PVTy fc c ty) = PVTy fc c <$> onNamesTerm f ty

  onNamesTerms : OnNames -> List (Term vars) -> Core (List (Term vars))
  onNamesTerms f [] = pure []
  onNamesTerms f (t :: ts) = pure (!(onNamesTerm f t) :: !(onNamesTerms f ts))

  onNamesTerm : OnNames -> Term vars -> Core (Term vars)
  onNamesTerm f (Ref fc x n) = Ref fc x <$> f.onName n
  onNamesTerm f (Meta fc x i xs)
      = do xs' <- onNamesTerms f xs
           (x', i') <- f.onMeta x i
           pure (Meta fc x' i' xs')
  onNamesTerm f (Bind fc x b scope)
      = pure (Bind fc x !(onNamesBinder f b) !(onNamesTerm f scope))
  onNamesTerm f (App fc fn arg)
      = pure (App fc !(onNamesTerm f fn) !(onNamesTerm f arg))
  onNamesTerm f (As fc s p tm)
      = pure (As fc s !(onNamesTerm f p) !(onNamesTerm f tm))
  onNamesTerm f (TDelayed fc x y)
      = pure (TDelayed fc x !(onNamesTerm f y))
  onNamesTerm f (TDelay fc x t y)
      = pure (TDelay fc x !(onNamesTerm f t) !(onNamesTerm f y))
  onNamesTerm f (TForce fc r y)
      = pure (TForce fc r !(onNamesTerm f y))
  onNamesTerm f (TType fc u) = TType fc <$> f.onName u
  onNamesTerm f (Erased fc (Dotted t))
      = pure (Erased fc (Dotted !(onNamesTerm f t)))
  onNamesTerm f tm = pure tm

-- A case tree's names: each case's scrutinee type and each leaf's term,
-- and each alternative's constructor; its alternatives are in a list of
-- their own.
mutual
  onNamesTree : OnNames -> CaseTree vars -> Core (CaseTree vars)
  onNamesTree f (Case i v ty alts)
      = pure $ Case i v !(onNamesTerm f ty) !(onNamesAlts f alts)
  onNamesTree f (STerm i tm) = STerm i <$> onNamesTerm f tm
  onNamesTree f t = pure t

  onNamesAlts : OnNames -> List (CaseAlt vars) -> Core (List (CaseAlt vars))
  onNamesAlts f [] = pure []
  onNamesAlts f (alt :: alts) = pure (!(onNamesAlt f alt) :: !(onNamesAlts f alts))

  onNamesAlt : OnNames -> CaseAlt vars -> Core (CaseAlt vars)
  onNamesAlt f (ConCase n t args sc)
      = do sc' <- onNamesTree f sc
           pure $ ConCase !(f.onName n) t args sc'
  onNamesAlt f (DelayCase ty arg sc) = DelayCase ty arg <$> onNamesTree f sc
  onNamesAlt f (ConstCase c sc) = ConstCase c <$> onNamesTree f sc
  onNamesAlt f (DefaultCase sc) = DefaultCase <$> onNamesTree f sc

fullNames : Context -> OnNames
fullNames gam = MkOnNames (full gam) fullMeta
  where
    fullMeta : Name -> Int -> Core (Name, Int)
    fullMeta x i = pure $ case !(lookupCtxtExact (Resolved i) gam) of
                               Nothing => (x, i)
                               Just gdef => (fullname gdef, i)

resolvedNames : Context -> OnNames
resolvedNames gam = MkOnNames (pure . indexedName gam) (\x, i => pure (x, fromMaybe i (getNameID x gam)))

export
HasNames (Term vars) where
  full gam = onNamesTerm (fullNames gam)
  resolved gam = onNamesTerm (resolvedNames gam)

export
HasNames (CaseTree vars) where
  full gam = onNamesTree (fullNames gam)
  resolved gam = onNamesTree (resolvedNames gam)

export
HasNames (CaseAlt vars) where
  full gam = onNamesAlt (fullNames gam)
  resolved gam = onNamesAlt (resolvedNames gam)

export
HasNames Pat where
  full gam (PAs fc n p)
     = [| PAs (pure fc) (full gam n) (full gam p) |]
  full gam (PCon fc n i ar ps)
     = [| PCon (pure fc) (full gam n) (pure i) (pure ar) (traverse (full gam) ps) |]
  full gam (PTyCon fc n ar ps)
     = [| PTyCon (pure fc) (full gam n) (pure ar) (traverse (full gam) ps) |]
  full gam p@(PConst {}) = pure p
  full gam (PArrow fc x p q)
     = [| PArrow (pure fc) (full gam x) (full gam p) (full gam q) |]
  full gam (PDelay fc laz p q)
     = [| PDelay (pure fc) (pure laz) (full gam p) (full gam q) |]
  full gam (PLoc fc n) = PLoc fc <$> full gam n
  full gam (PUnmatchable fc t) = PUnmatchable fc <$> full gam t

  resolved gam (PAs fc n p)
     = [| PAs (pure fc) (resolved gam n) (resolved gam p) |]
  resolved gam (PCon fc n i ar ps)
     = [| PCon (pure fc) (resolved gam n) (pure i) (pure ar) (traverse (resolved gam) ps) |]
  resolved gam (PTyCon fc n ar ps)
     = [| PTyCon (pure fc) (resolved gam n) (pure ar) (traverse (resolved gam) ps) |]
  resolved gam p@(PConst {}) = pure p
  resolved gam (PArrow fc x p q)
     = [| PArrow (pure fc) (resolved gam x) (resolved gam p) (resolved gam q) |]
  resolved gam (PDelay fc laz p q)
     = [| PDelay (pure fc) (pure laz) (resolved gam p) (resolved gam q) |]
  resolved gam (PLoc fc n) = PLoc fc <$> resolved gam n
  resolved gam (PUnmatchable fc t) = PUnmatchable fc <$> resolved gam t


------------------------------------------------------------------------------
-- A definition's terms, by their lifetime
------------------------------------------------------------------------------

-- Every reader of a definition's type, case tree, clause patterns or
-- clauses asks one of the functions below, and none tells a live term
-- from a stored one: a live term is read as it is, and a stored one is
-- decoded where the reader rebuilt or embedded the live one.

-- A stored case tree decoded, each term in the scope of the variables its
-- alternatives bind.
decodedTree : {args : Scope} -> CaseTree' Root args -> CaseTree args
decodedTree roots = runIdentity (traverseTree (\s, r => Id (Stored.decode s r)) (mkSizeOf args) roots)

||| A definition's type, as `readTypeOf` reads it: the live type it holds,
||| or the term its stored type decodes to.
export
data TypeOf : GlobalDef -> ClosedTerm -> Type where
  LiveTypeOf : (0 _ : type d = LiveType ty) -> TypeOf d ty
  StoredTypeOf : (0 _ : type d = StoredType r) -> TypeOf d (Stored.decode SizeOf.zero r)

||| A pattern-matching definition's case tree, as `readTreeOf` reads it
||| from the definition's body: the live tree it holds, or the tree its
||| stored one decodes to.
export
data TreeOf : Body args -> CaseTree args -> Type where
  LiveTreeOf : TreeOf (LiveBody tree pats clauses) tree
  StoredTreeOf : TreeOf (StoredBody roots pats clauses) (decodedTree roots)

0 liveOnce : LiveType t = LiveType t' -> t = t'
liveOnce Refl = Refl

0 storedOnce : StoredType r = StoredType r' -> r = r'
storedOnce Refl = Refl

0 liveNotStored : LiveType t = StoredType r -> Void
liveNotStored Refl impossible

||| A definition has one type: what it holds is one form, and decoding is a
||| function.
export
0 typeOnce : TypeOf d ty -> TypeOf d ty' -> ty = ty'
typeOnce (LiveTypeOf held) (LiveTypeOf held') = liveOnce (trans (sym held) held')
typeOnce (LiveTypeOf held) (StoredTypeOf held') = void (liveNotStored (trans (sym held) held'))
typeOnce (StoredTypeOf held) (LiveTypeOf held') = void (liveNotStored (trans (sym held') held))
typeOnce (StoredTypeOf held) (StoredTypeOf held')
    = cong (Stored.decode SizeOf.zero) (storedOnce (trans (sym held) held'))

||| A body has one case tree: what it holds is one form, and decoding is a
||| function.
export
0 treeOnce : TreeOf body tree -> TreeOf body tree' -> tree = tree'
treeOnce LiveTreeOf LiveTreeOf = Refl
treeOnce StoredTreeOf StoredTreeOf = Refl

||| A definition's type, with what it was read from: every reader of a
||| definition's type reads it here. Total, so that a total program reads
||| it directly.
export total
readTypeOf : (d : GlobalDef) -> Core (Subset ClosedTerm (TypeOf d))
readTypeOf d with (type d) proof held
  readTypeOf d | LiveType ty = pure (Element ty (LiveTypeOf held))
  readTypeOf d | StoredType r = pure (Element (Stored.decode zero r) (StoredTypeOf held))

||| A definition's type.
export
typeOf : GlobalDef -> Core ClosedTerm
typeOf gdef = (.fst) <$> readTypeOf gdef

||| What a definition's type computes once its arguments are given, read
||| off the type as it is held: a stored type is not decoded to say it.
export
typeHead : GlobalDef -> Core ResultHead
typeHead gdef
    = case type gdef of
           LiveType ty => pure (resultHead ty)
           StoredType r => pure (storedHead r)

||| A pattern-matching definition's case tree, with what it was read from:
||| every reader of a definition's case tree reads it here. Total, so that
||| a total program reads it directly.
export total
readTreeOf : {args : Scope} -> (body : Body args) -> Core (Subset (CaseTree args) (TreeOf body))
readTreeOf (LiveBody tree _ _) = pure (Element tree LiveTreeOf)
readTreeOf (StoredBody roots _ _) = pure (Element (decodedTree roots) StoredTreeOf)

||| A pattern-matching definition's case tree.
export
treeOf : {args : _} -> Body args -> Core (CaseTree args)
treeOf body = (.fst) <$> readTreeOf body

||| Each clause's arguments as the case builder read them, in the order of
||| the clauses.
export
clausePatsOf : Body args -> Core (List (List Pat))
clausePatsOf (LiveBody _ ps _) = pure ps
clausePatsOf (StoredBody _ ps _)
    = pure (map (\p => runIdentity (traversePats (Id . Stored.decode zero) p)) ps)

-- The size of a scope a variable is bound beyond.
tailSize : SizeOf (x :: vs) -> SizeOf vs
tailSize s = case sizedView s of
                  S s' => s'

-- An environment with `g` applied to each term of each binder, given the
-- size of the scope the binder is in.
traverseEnv : Applicative f => (forall vs . SizeOf vs -> t vs -> f (u vs)) ->
              SizeOf vars -> Env t vars -> f (Env u vars)
traverseEnv g s [] = pure []
traverseEnv g s (b :: env)
    = let s' = tailSize s in (::) <$> traverse (g s') b <*> traverseEnv g s' env

||| The clauses as checked: each left- and right-hand side, with the
||| environment that names their variables.
export
clausesOf : Body args -> Core (List (vs : Scope ** (Env Term vs, Term vs, Term vs)))
clausesOf (LiveBody _ _ cs) = pure cs
clausesOf (StoredBody _ _ cs) = pure (map decodeClause cs)
  where
    decodeClause : (vs : Scope ** (Env Root vs, Root vs, Root vs)) ->
                   (vs : Scope ** (Env Term vs, Term vs, Term vs))
    decodeClause (vs ** (env, lhs, rhs))
        = let s = mkSizeOf vs in
              (vs ** (runIdentity (traverseEnv (\s', r => Id (Stored.decode s' r)) s env),
                      Stored.decode s lhs, Stored.decode s rhs))

||| What a walk of a definition's case tree makes of a leaf it reaches: its
||| right-hand side as a term, in the scope of the tree's variables and of
||| the variables beyond them; and what that right-hand side computes once
||| its arguments are given.
public export
record Leaves (t : Scoped) where
  constructor MkLeaves
  leafTerm : {vs : Scope} -> {0 outer : Scope} -> t vs -> Core (Term (vs ++ outer))
  leafHead : {0 vs : Scope} -> t vs -> Core ResultHead

liveLeaf : {vs : Scope} -> {0 outer : Scope} -> Term vs -> Core (Term (vs ++ outer))
liveLeaf tm = pure (embed tm)

liveHead : {0 vs : Scope} -> Term vs -> Core ResultHead
liveHead tm = pure (resultHead tm)

storedLeaf : {vs : Scope} -> {0 outer : Scope} -> Root vs -> Core (Term (vs ++ outer))
storedLeaf r = pure (decodeWithin (mkSizeOf vs) r)

storedLeafHead : {0 vs : Scope} -> Root vs -> Core ResultHead
storedLeafHead r = pure (storedHead r)

||| A pattern-matching definition's case tree, given to a walk that reads
||| it: a live tree's leaf is its term, embedded in the walk's scope where
||| the walk reaches it; a stored tree's leaf is decoded into that scope
||| there, so only the leaf the walk reaches is decoded.
export
walkTree : Body args -> ({0 t : Scoped} -> Leaves t -> CaseTree' t args -> Core r) -> Core r
walkTree (LiveBody ct _ _) k = k (MkLeaves liveLeaf liveHead) ct
walkTree (StoredBody ct _ _) k = k (MkLeaves storedLeaf storedLeafHead) ct

-- What freezing a pattern-matching definition gives, each term a place in
-- its arena; and the same, each place made a root of the arena.
FrozenBody : (Scope -> Type) -> Scope -> Type
FrozenBody t args
    = (t [], CaseTree' t args, List (List (Pat' (t []))),
       List (vs : Scope ** (Env t vs, t vs, t vs)))

frozenBody : ClosedTerm -> (args : Scope) -> CaseTree args -> List (List Pat) ->
             List (vs : Scope ** (Env Term vs, Term vs, Term vs)) ->
             Freeze (FrozenBody Pos args)
frozenBody ty args ct ps cs
    = do tyAt <- freeze zero ty
         ctAt <- traverseTree freeze (mkSizeOf args) ct
         psAt <- traverse (traversePats (freeze zero)) ps
         csAt <- traverse frozenClause cs
         pure (tyAt, ctAt, psAt, csAt)
  where
    frozenClause : (vs : Scope ** (Env Term vs, Term vs, Term vs)) ->
                   Freeze (vs : Scope ** (Env Pos vs, Pos vs, Pos vs))
    frozenClause (vs ** (env, lhs, rhs))
        = do let s = mkSizeOf vs
             env' <- traverseEnv freeze s env
             lhs' <- freeze s lhs
             rhs' <- freeze s rhs
             pure (vs ** (env', lhs', rhs'))

rootedBody : (a : Arena) -> (args : Scope) -> FrozenBody Pos args -> Maybe (FrozenBody Root args)
rootedBody a args (tyAt, ctAt, psAt, csAt)
    = do ty <- rootAt a tyAt
         ct <- traverseTree (\_ => rootAt a) (mkSizeOf args) ctAt
         ps <- traverse (traversePats (rootAt a)) psAt
         cs <- traverse rootedClause csAt
         pure (ty, ct, ps, cs)
  where
    rootedClause : (vs : Scope ** (Env Pos vs, Pos vs, Pos vs)) ->
                   Maybe (vs : Scope ** (Env Root vs, Root vs, Root vs))
    rootedClause (vs ** (env, lhs, rhs))
        = do env' <- traverseEnv (\_ => rootAt a) (mkSizeOf vs) env
             lhs' <- rootAt a lhs
             rhs' <- rootAt a rhs
             pure (vs ** (env', lhs', rhs'))

-- A definition's terms frozen, sealed into their arena and made its roots:
-- the one place what a read of a stored term relies on is decided
-- (`seal`, `rootAt`). Freezing lays all of it, so only a fault in this
-- compiler fails here; it is decided rather than proved because the
-- arena's columns are `mlir-array`'s arrays, of which a type knows nothing
-- element by element.
sealedRoots : Freeze x -> (Arena -> x -> Maybe y) -> Core y
sealedRoots job root
    = case seal job >>= (\(a, x) => root a x) of
           Just r => pure r
           Nothing => throw (InternalError "A frozen definition's terms are not laid as its arena holds them")

-- A definition with its terms stored: its type, and a pattern-matching
-- definition's case tree, clause patterns and clauses with their
-- environments, all frozen into one arena, each subterm shared within it.
-- Every other kind of definition holds no term but its type, or holds a
-- guess, which stays live.
freezeDef : GlobalDef -> Core GlobalDef
freezeDef gdef
    = do ty <- typeOf gdef
         case definition gdef of
              PMDef pi args body =>
                do ct <- treeOf body
                   ps <- clausePatsOf body
                   cs <- clausesOf body
                   (ty', ct', ps', cs') <- sealedRoots (frozenBody ty args ct ps cs) (\a => rootedBody a args)
                   pure ({ type := StoredType ty',
                           definition := PMDef pi args (StoredBody ct' ps' cs') } gdef)
              _ => do ty' <- sealedRoots (freeze zero ty) rootAt
                      pure ({ type := StoredType ty' } gdef)


-- Resolving each part of a definition decoded from a TTC.
resolveEnv : Context -> Env Term vars -> Core (Env Term vars)
resolveEnv gam [] = pure Env.empty
resolveEnv gam (b :: bs)
    = pure $ !(onNamesBinder (resolvedNames gam) b) :: !(resolveEnv gam bs)

-- The names in each clause's patterns, and the terms a pattern cannot
-- match, given what becomes of each: one traversal, structural, for making
-- them full and for resolving them.
mutual
  onPatNames : (Name -> Core Name) -> (ClosedTerm -> Core ClosedTerm) -> Pat -> Core Pat
  onPatNames f g (PAs fc n p) = PAs fc <$> f n <*> onPatNames f g p
  onPatNames f g (PCon fc n t a ps) = PCon fc <$> f n <*> pure t <*> pure a <*> onPatsNames f g ps
  onPatNames f g (PTyCon fc n a ps) = PTyCon fc <$> f n <*> pure a <*> onPatsNames f g ps
  onPatNames f g (PConst fc c) = pure (PConst fc c)
  onPatNames f g (PArrow fc x s t) = PArrow fc x <$> onPatNames f g s <*> onPatNames f g t
  onPatNames f g (PDelay fc r t p) = PDelay fc r <$> onPatNames f g t <*> onPatNames f g p
  onPatNames f g (PLoc fc n) = pure (PLoc fc n)
  onPatNames f g (PUnmatchable fc tm) = PUnmatchable fc <$> g tm

  onPatsNames : (Name -> Core Name) -> (ClosedTerm -> Core ClosedTerm) -> List Pat -> Core (List Pat)
  onPatsNames f g [] = pure []
  onPatsNames f g (p :: ps) = [| onPatNames f g p :: onPatsNames f g ps |]

onClausePatNames : (Name -> Core Name) -> (ClosedTerm -> Core ClosedTerm) ->
                   List (List Pat) -> Core (List (List Pat))
onClausePatNames f g [] = pure []
onClausePatNames f g (c :: cs) = [| onPatsNames f g c :: onClausePatNames f g cs |]

-- Later keys overwrite earlier ones that resolve to the same name, as
-- inserting them in order does.
resolveNameMap : Context -> NameMap a -> NameMap a
resolveNameMap gam nmap
    = foldl (\m, (k, v) => insert (indexedName gam k) v m) empty (NameMap.toList nmap)

resolvePartial : Context -> PartialReason -> PartialReason
resolvePartial gam NotStrictlyPositive = NotStrictlyPositive
resolvePartial gam (BadCall ns) = BadCall (map (indexedName gam) ns)
resolvePartial gam (BadPath init n)
    = BadPath (map (\(fc, x) => (fc, indexedName gam x)) init) (indexedName gam n)
resolvePartial gam (RecPath loop)
    = RecPath (map (\(fc, x) => (fc, indexedName gam x)) loop)

resolveTerminating : Context -> Terminating -> Terminating
resolveTerminating gam (NotTerminating p) = NotTerminating (resolvePartial gam p)
resolveTerminating gam t = t

resolveCovering : Context -> Covering -> Core Covering
resolveCovering gam IsCovering = pure IsCovering
resolveCovering gam (MissingCases ts)
    = MissingCases <$> traverse (onNamesTerm (resolvedNames gam)) ts
resolveCovering gam (NonCoveringCall ns)
    = pure $ NonCoveringCall (map (indexedName gam) ns)

resolveTotality : Context -> Totality -> Core Totality
resolveTotality gam (MkTotality t c)
    = MkTotality (resolveTerminating gam t) <$> resolveCovering gam c

resolveSCCall : Context -> SCCall -> SCCall
resolveSCCall gam sc = { fnCall := indexedName gam (fnCall sc) } sc

||| The definition a TTC held, as the context stores it: the namespace the
||| TTC trimmed from its case tree's and clauses' references restored, its
||| names resolved, and its terms frozen. Resolving looks up no definition,
||| so nothing else is decoded meanwhile.
export
storeDecoded : Context -> Namespace -> GlobalDef -> Core GlobalDef
storeDecoded gam ns def
    = do ty <- typeOf def
         d <- resolveDef (definition def)
         tot <- resolveTotality gam (totality def)
         freezeDef ({ type := LiveType !(onNamesTerm (resolvedNames gam) ty),
                      definition := d,
                      totality := tot,
                      refersToM := map (resolveNameMap gam) (refersToM def),
                      sizeChange := map (resolveSCCall gam) (sizeChange def)
                    } def)
  where
    resolveClause : (vs : Scope ** (Env Term vs, Term vs, Term vs)) ->
                    Core (vs : Scope ** (Env Term vs, Term vs, Term vs))
    resolveClause (_ ** (env, lhs, rhs))
        = pure (_ ** (!(resolveEnv gam env),
                      !(onNamesTerm (resolvedNames gam) (restoreNS ns lhs)),
                      !(onNamesTerm (resolvedNames gam) (restoreNS ns rhs))))

    resolveDef : Def -> Core Def
    resolveDef (PMDef r args body)
        = do ct <- treeOf body
             ps <- clausePatsOf body
             cs <- clausesOf body
             ct' <- onNamesTree (resolvedNames gam) (restoreNS ns ct)
             ps' <- onClausePatNames (pure . indexedName gam) (onNamesTerm (resolvedNames gam)) ps
             cs' <- traverse resolveClause cs
             pure (PMDef r args (LiveBody ct' ps' cs'))
    -- A type's constructors are kept by their full names, which is how a
    -- TTC holds them: resolving leaves them as they are.
    resolveDef (TCon a ps ds u ms mcs det)
        = pure $ TCon a ps ds u (map (indexedName gam) ms) mcs det
    resolveDef (BySearch c n) = pure $ BySearch c (indexedName gam n)
    resolveDef (Guess tm b cs)
        = pure $ Guess !(onNamesTerm (resolvedNames gam) tm) b cs
    resolveDef t = pure t

export
HasNames (Env Term vars) where
  full gam [] = pure Env.empty
  full gam (b :: bs)
      = pure $ !(traverse (full gam) b) :: !(full gam bs)

  resolved = resolveEnv

export
HasNames Clause where
  full gam (MkClause env lhs rhs unified)
     = pure $ MkClause !(full gam env) !(full gam lhs) !(full gam rhs) unified

  resolved gam (MkClause env lhs rhs unified)
    = [| MkClause (resolved gam env) (resolved gam lhs) (resolved gam rhs) (pure unified) |]


HasNames (NameMap a) where
  full gam nmap
      = insertAll empty (toList nmap)
    where
      insertAll : NameMap a -> List (Name, a) -> Core (NameMap a)
      insertAll ms [] = pure ms
      insertAll ms ((k, v) :: ns)
          = insertAll (insert !(full gam k) v ms) ns

  resolved gam nmap = pure (resolveNameMap gam nmap)

export
HasNames PartialReason where
  full gam NotStrictlyPositive = pure NotStrictlyPositive
  full gam (BadCall ns) = pure $ BadCall !(traverse (full gam) ns)
  full gam (BadPath init n) = pure $ BadPath !(traverse (traversePair (full gam)) init) !(full gam n)
  full gam (RecPath loop) = pure $ RecPath !(traverse (traversePair (full gam)) loop)

  resolved gam p = pure (resolvePartial gam p)

export
HasNames Terminating where
  full gam (NotTerminating p) = pure $ NotTerminating !(full gam p)
  full gam t = pure t

  resolved gam t = pure (resolveTerminating gam t)

export
HasNames Covering where
  full gam IsCovering = pure IsCovering
  full gam (MissingCases ts)
      = pure $ MissingCases !(traverse (full gam) ts)
  full gam (NonCoveringCall ns)
      = pure $ NonCoveringCall !(traverse (full gam) ns)

  resolved = resolveCovering

export
HasNames CaseError where
  full gam DifferingArgNumbers = pure DifferingArgNumbers
  full gam DifferingTypes = pure DifferingTypes
  full gam (MatchErased (vs ** (rho, t))) = do
    rho <- full gam rho
    t <- full gam t
    pure (MatchErased (vs ** (rho, t)))
  full gam (NotFullyApplied n) = NotFullyApplied <$> full gam n
  full gam UnknownType = pure UnknownType

  resolved gam DifferingArgNumbers = pure DifferingArgNumbers
  resolved gam DifferingTypes = pure DifferingTypes
  resolved gam (MatchErased (vs ** (rho, t))) = do
    rho <- resolved gam rho
    t <- resolved gam t
    pure (MatchErased (vs ** (rho, t)))
  resolved gam (NotFullyApplied n) = NotFullyApplied <$> resolved gam n
  resolved gam UnknownType = pure UnknownType


export
HasNames Warning where
  full gam (ParserWarning fc x) = pure (ParserWarning fc x)
  full gam (UnreachableClause fc rho s) = UnreachableClause fc <$> full gam rho <*> full gam s
  full gam (ShadowingGlobalDefs fc xs)
    = ShadowingGlobalDefs fc <$> traverseList1 (traversePair (traverseList1 (full gam))) xs
  full gam (IncompatibleVisibility fc x y n) = IncompatibleVisibility fc x y <$> full gam n
  full gam w@(ShadowingLocalBindings {}) = pure w
  full gam (Deprecated fc x y) = Deprecated fc x <$> traverseOpt (traversePair (full gam)) y
  full gam (GenericWarn fc x) = pure (GenericWarn fc x)

  resolved gam (ParserWarning fc x) = pure (ParserWarning fc x)
  resolved gam (UnreachableClause fc rho s) = UnreachableClause fc <$> resolved gam rho <*> resolved gam s
  resolved gam (ShadowingGlobalDefs fc xs)
    = ShadowingGlobalDefs fc <$> traverseList1 (traversePair (traverseList1 (resolved gam))) xs
  resolved gam (IncompatibleVisibility fc x y n) = IncompatibleVisibility fc x y <$> resolved gam n
  resolved gam w@(ShadowingLocalBindings {}) = pure w
  resolved gam (Deprecated fc x y) = Deprecated fc x <$> traverseOpt (traversePair (resolved gam)) y
  resolved gam (GenericWarn fc x) = pure (GenericWarn fc x)

export
HasNames Error where
  full gam (Fatal err) = Fatal <$> full gam err
  full _ (CantConvert fc gam rho s t)
    = CantConvert fc gam <$> full gam rho <*> full gam s <*> full gam t
  full _ (CantSolveEq fc gam rho s t)
    = CantSolveEq fc gam <$> full gam rho <*> full gam s <*> full gam t
  full gam (PatternVariableUnifies fc fct rho n s)
    = PatternVariableUnifies fc fct <$> full gam rho <*> full gam n <*> full gam s
  full gam (CyclicMeta fc rho n s)
    = CyclicMeta fc <$> full gam rho <*> full gam n <*> full gam s
  full _ (WhenUnifying fc gam rho s t err)
    = WhenUnifying fc gam <$> full gam rho <*> full gam s <*> full gam t <*> full gam err
  full gam (ValidCase fc rho x)
    = ValidCase fc <$> full gam rho <*> either (map Left . full gam) (map Right . full gam) x
  full gam (UndefinedName fc n) = UndefinedName fc <$> full gam n
  full gam (InvisibleName fc n mns) = InvisibleName fc <$> full gam n <*> pure mns
  full gam (BadTypeConType fc n) = BadTypeConType fc <$> full gam n
  full gam (BadDataConType fc n n') = BadDataConType fc <$> full gam n <*> full gam n'
  full gam (NotCovering fc n cov) = NotCovering fc <$> full gam n <*> full gam cov
  full gam (NotTotal fc n pr) = NotTotal fc <$> full gam n <*> full gam pr
  full gam ImpossibleCase = pure ImpossibleCase
  full gam (LinearUsed fc k n) = LinearUsed fc k <$> full gam n
  full gam (LinearMisuse fc n x y) = LinearMisuse fc <$> full gam n <*> pure x <*> pure y
  full gam (BorrowPartial fc rho s t) = BorrowPartial fc <$> full gam rho <*> full gam s <*> full gam t
  full gam (BorrowPartialType fc rho s) = BorrowPartialType fc <$> full gam rho <*> full gam s
  full gam (AmbiguousName fc xs) = AmbiguousName fc <$> traverse (full gam) xs
  full gam (AmbiguousElab fc rho xs)
    = AmbiguousElab fc <$> full gam rho <*> traverse (\ (gam, t) => (gam,) <$> full gam t) xs
  full gam (AmbiguousSearch fc rho s xs)
    = AmbiguousSearch fc <$> full gam rho <*> full gam s <*> traverse (full gam) xs
  full gam (AllFailed xs)
     = map AllFailed $ for xs $ \ (mn, err) =>
         (,) <$> traverseOpt (full gam) mn <*> full gam err
  full gam (RecordTypeNeeded fc rho) = RecordTypeNeeded fc <$> full gam rho
  full gam (DuplicatedRecordUpdatePath fc xs) = pure (DuplicatedRecordUpdatePath fc xs)
  full gam (NotRecordField fc x mn) = NotRecordField fc x <$> traverseOpt (full gam) mn
  full gam (NotRecordType fc n) = NotRecordType fc <$> full gam n
  full gam (IncompatibleFieldUpdate fc xs) = pure (IncompatibleFieldUpdate fc xs)
  full gam (InvalidArgs fc rho xs s) = InvalidArgs fc <$> full gam rho <*> traverse (full gam) xs <*> full gam s
  full gam (TryWithImplicits fc rho xs)
    = TryWithImplicits fc <$> full gam rho
       <*> for xs (\ (n, t) => (,) <$> full gam n <*> full gam t)
  full gam (BadUnboundImplicit fc rho n s) = BadUnboundImplicit fc <$> full gam rho <*> full gam n <*> full gam s
  full _ (CantSolveGoal fc gam rho s merr)
    = CantSolveGoal fc gam <$> full gam rho <*> full gam s <*> traverseOpt (full gam) merr
  full gam (DeterminingArg fc n x rho s)
    = DeterminingArg fc <$> full gam n <*> pure x <*> full gam rho <*> full gam s
  full _ (GrowingSearch fc gam e l hs)
    = GrowingSearch fc gam <$> full gam e <*> full gam l <*> traverse (full gam) hs
  full gam (UnsolvedHoles xs) = UnsolvedHoles <$> traverse (traversePair (full gam)) xs
  full gam (CantInferArgType fc rho n n1 s)
    = CantInferArgType fc <$> full gam rho <*> full gam n <*> full gam n1 <*> full gam s
  full gam (SolvedNamedHole fc rho n s) = SolvedNamedHole fc <$> full gam rho <*> full gam n <*> full gam s
  full gam (VisibilityError fc x n y n1) = VisibilityError fc x <$> full gam n <*> pure y <*> full gam n1
  full gam (NonLinearPattern fc n) = NonLinearPattern fc <$> full gam  n
  full gam (BadPattern fc n) = BadPattern fc <$> full gam n
  full gam (NoDeclaration fc n) = NoDeclaration fc <$> full gam n
  full gam (AlreadyDefined fc n) = AlreadyDefined fc <$> full gam n
  full gam (NotFunctionType fc rho s) = NotFunctionType fc <$> full gam rho <*> full gam s
  full gam (RewriteNoChange fc rho s t) = RewriteNoChange fc <$> full gam rho <*> full gam s <*> full gam t
  full gam (NotRewriteRule fc rho s) = NotRewriteRule fc <$> full gam rho <*> full gam s
  full gam (CaseCompile fc n x) = CaseCompile fc <$> full gam n <*> full gam x
  full gam (MatchTooSpecific fc rho s) = MatchTooSpecific fc <$> full gam rho <*> full gam s
  full gam (BadDotPattern fc rho x s t)
    = BadDotPattern fc <$> full gam rho <*> pure x <*> full gam s <*> full gam t
  full gam (BadImplicit fc x) = pure (BadImplicit fc x)
  full gam (BadRunElab fc rho s desc) = BadRunElab fc <$> full gam rho <*> full gam s <*> pure desc
  full gam (RunElabFail e) = RunElabFail <$> full gam e
  full gam (GenericMsg fc x) = pure (GenericMsg fc x)
  full gam (GenericMsgSol fc x y z) = pure (GenericMsgSol fc x y z)
  full gam (TTCError x) = pure (TTCError x)
  full gam (FileErr x y) = pure (FileErr x y)
  full gam (CantFindPackage x) = pure (CantFindPackage x)
  full gam (LazyImplicitFunction fc) = pure (LazyImplicitFunction fc)
  full gam (LazyPatternVar fc) = pure (LazyPatternVar fc)
  full gam (LitFail fc) = pure (LitFail fc)
  full gam (LexFail fc x) = pure (LexFail fc x)
  full gam (ParseFail xs) = pure (ParseFail xs)
  full gam (ModuleNotFound fc x) = pure (ModuleNotFound fc x)
  full gam (CyclicImports xs) = pure (CyclicImports xs)
  full gam ForceNeeded = pure ForceNeeded
  full gam (InternalError x) = pure (InternalError x)
  full gam (UserError x) = pure (UserError x)
  full gam (NoForeignCC fc xs) = pure (NoForeignCC fc xs)
  full gam (BadMultiline fc x) = pure (BadMultiline fc x)
  full gam (FailingDidNotFail fc) = pure (FailingDidNotFail fc)
  full gam (FailingWrongError fc x err) = FailingWrongError fc x <$> traverseList1 (full gam) err
  full gam (InType fc n err) = InType fc <$> full gam n <*> full gam err
  full gam (InCon n err) = InCon <$> traverse (full gam) n <*> full gam err
  full gam (InLHS fc n err) = InLHS fc <$> full gam n <*> full gam err
  full gam (InRHS fc n err) = InRHS fc <$> full gam n <*> full gam err
  full gam (MaybeMisspelling err xs) = MaybeMisspelling <$> full gam err <*> pure xs
  full gam (WarningAsError wrn) = WarningAsError <$> full gam wrn
  full gam (OperatorBindingMismatch fc expected actual (Left opName) rhs candidates)
      = OperatorBindingMismatch fc expected actual
          <$> (Left <$> full gam opName) <*> pure rhs <*> pure candidates
  full gam (OperatorBindingMismatch fc expected actual (Right opName) rhs candidates)
      = OperatorBindingMismatch fc expected actual
          <$> (Right <$> full gam opName) <*> pure rhs <*> pure candidates

  resolved gam (Fatal err) = Fatal <$> resolved gam err
  resolved _ (CantConvert fc gam rho s t)
    = CantConvert fc gam <$> resolved gam rho <*> resolved gam s <*> resolved gam t
  resolved _ (CantSolveEq fc gam rho s t)
    = CantSolveEq fc gam <$> resolved gam rho <*> resolved gam s <*> resolved gam t
  resolved gam (PatternVariableUnifies fc fct rho n s)
    = PatternVariableUnifies fc fct <$> resolved gam rho <*> resolved gam n <*> resolved gam s
  resolved gam (CyclicMeta fc rho n s)
    = CyclicMeta fc <$> resolved gam rho <*> resolved gam n <*> resolved gam s
  resolved _ (WhenUnifying fc gam rho s t err)
    = WhenUnifying fc gam <$> resolved gam rho <*> resolved gam s <*> resolved gam t <*> resolved gam err
  resolved gam (ValidCase fc rho x)
    = ValidCase fc <$> resolved gam rho <*> either (map Left . resolved gam) (map Right . resolved gam) x
  resolved gam (UndefinedName fc n) = UndefinedName fc <$> resolved gam n
  resolved gam (InvisibleName fc n mns) = InvisibleName fc <$> resolved gam n <*> pure mns
  resolved gam (BadTypeConType fc n) = BadTypeConType fc <$> resolved gam n
  resolved gam (BadDataConType fc n n') = BadDataConType fc <$> resolved gam n <*> resolved gam n'
  resolved gam (NotCovering fc n cov) = NotCovering fc <$> resolved gam n <*> resolved gam cov
  resolved gam (NotTotal fc n pr) = NotTotal fc <$> resolved gam n <*> resolved gam pr
  resolved gam ImpossibleCase = pure ImpossibleCase
  resolved gam (LinearUsed fc k n) = LinearUsed fc k <$> resolved gam n
  resolved gam (LinearMisuse fc n x y) = LinearMisuse fc <$> resolved gam n <*> pure x <*> pure y
  resolved gam (BorrowPartial fc rho s t) = BorrowPartial fc <$> resolved gam rho <*> resolved gam s <*> resolved gam t
  resolved gam (BorrowPartialType fc rho s) = BorrowPartialType fc <$> resolved gam rho <*> resolved gam s
  resolved gam (AmbiguousName fc xs) = AmbiguousName fc <$> traverse (resolved gam) xs
  resolved gam (AmbiguousElab fc rho xs)
    = AmbiguousElab fc <$> resolved gam rho <*> traverse (\ (gam, t) => (gam,) <$> resolved gam t) xs
  resolved gam (AmbiguousSearch fc rho s xs)
    = AmbiguousSearch fc <$> resolved gam rho <*> resolved gam s <*> traverse (resolved gam) xs
  resolved gam (AllFailed xs)
     = map AllFailed $ for xs $ \ (mn, err) =>
         (,) <$> traverseOpt (resolved gam) mn <*> resolved gam err
  resolved gam (RecordTypeNeeded fc rho) = RecordTypeNeeded fc <$> resolved gam rho
  resolved gam (DuplicatedRecordUpdatePath fc xs) = pure (DuplicatedRecordUpdatePath fc xs)
  resolved gam (NotRecordField fc x mn) = NotRecordField fc x <$> traverseOpt (resolved gam) mn
  resolved gam (NotRecordType fc n) = NotRecordType fc <$> resolved gam n
  resolved gam (IncompatibleFieldUpdate fc xs) = pure (IncompatibleFieldUpdate fc xs)
  resolved gam (InvalidArgs fc rho xs s) = InvalidArgs fc <$> resolved gam rho <*> traverse (resolved gam) xs <*> resolved gam s
  resolved gam (TryWithImplicits fc rho xs)
    = TryWithImplicits fc <$> resolved gam rho
       <*> for xs (\ (n, t) => (,) <$> resolved gam n <*> resolved gam t)
  resolved gam (BadUnboundImplicit fc rho n s) = BadUnboundImplicit fc <$> resolved gam rho <*> resolved gam n <*> resolved gam s
  resolved _ (CantSolveGoal fc gam rho s merr)
    = CantSolveGoal fc gam <$> resolved gam rho <*> resolved gam s <*> traverseOpt (resolved gam) merr
  resolved gam (DeterminingArg fc n x rho s)
    = DeterminingArg fc <$> resolved gam n <*> pure x <*> resolved gam rho <*> resolved gam s
  resolved _ (GrowingSearch fc gam e l hs)
    = GrowingSearch fc gam <$> resolved gam e <*> resolved gam l <*> traverse (resolved gam) hs
  resolved gam (UnsolvedHoles xs) = UnsolvedHoles <$> traverse (traversePair (resolved gam)) xs
  resolved gam (CantInferArgType fc rho n n1 s)
    = CantInferArgType fc <$> resolved gam rho <*> resolved gam n <*> resolved gam n1 <*> resolved gam s
  resolved gam (SolvedNamedHole fc rho n s) = SolvedNamedHole fc <$> resolved gam rho <*> resolved gam n <*> resolved gam s
  resolved gam (VisibilityError fc x n y n1) = VisibilityError fc x <$> resolved gam n <*> pure y <*> resolved gam n1
  resolved gam (NonLinearPattern fc n) = NonLinearPattern fc <$> resolved gam  n
  resolved gam (BadPattern fc n) = BadPattern fc <$> resolved gam n
  resolved gam (NoDeclaration fc n) = NoDeclaration fc <$> resolved gam n
  resolved gam (AlreadyDefined fc n) = AlreadyDefined fc <$> resolved gam n
  resolved gam (NotFunctionType fc rho s) = NotFunctionType fc <$> resolved gam rho <*> resolved gam s
  resolved gam (RewriteNoChange fc rho s t) = RewriteNoChange fc <$> resolved gam rho <*> resolved gam s <*> resolved gam t
  resolved gam (NotRewriteRule fc rho s) = NotRewriteRule fc <$> resolved gam rho <*> resolved gam s
  resolved gam (CaseCompile fc n x) = CaseCompile fc <$> resolved gam n <*> resolved gam x
  resolved gam (MatchTooSpecific fc rho s) = MatchTooSpecific fc <$> resolved gam rho <*> resolved gam s
  resolved gam (BadDotPattern fc rho x s t)
    = BadDotPattern fc <$> resolved gam rho <*> pure x <*> resolved gam s <*> resolved gam t
  resolved gam (BadImplicit fc x) = pure (BadImplicit fc x)
  resolved gam (BadRunElab fc rho s desc) = BadRunElab fc <$> resolved gam rho <*> resolved gam s <*> pure desc
  resolved gam (RunElabFail e) = RunElabFail <$> resolved gam e
  resolved gam (GenericMsg fc x) = pure (GenericMsg fc x)
  resolved gam (GenericMsgSol fc x y z) = pure (GenericMsgSol fc x y z)
  resolved gam (TTCError x) = pure (TTCError x)
  resolved gam (FileErr x y) = pure (FileErr x y)
  resolved gam (CantFindPackage x) = pure (CantFindPackage x)
  resolved gam (LazyImplicitFunction fc) = pure (LazyImplicitFunction fc)
  resolved gam (LazyPatternVar fc) = pure (LazyPatternVar fc)
  resolved gam (LitFail fc) = pure (LitFail fc)
  resolved gam (LexFail fc x) = pure (LexFail fc x)
  resolved gam (ParseFail xs) = pure (ParseFail xs)
  resolved gam (ModuleNotFound fc x) = pure (ModuleNotFound fc x)
  resolved gam (CyclicImports xs) = pure (CyclicImports xs)
  resolved gam ForceNeeded = pure ForceNeeded
  resolved gam (InternalError x) = pure (InternalError x)
  resolved gam (UserError x) = pure (UserError x)
  resolved gam (NoForeignCC fc xs) = pure (NoForeignCC fc xs)
  resolved gam (BadMultiline fc x) = pure (BadMultiline fc x)
  resolved gam (FailingDidNotFail fc) = pure (FailingDidNotFail fc)
  resolved gam (FailingWrongError fc x err) = FailingWrongError fc x <$> traverseList1 (resolved gam) err
  resolved gam (InType fc n err) = InType fc <$> resolved gam n <*> resolved gam err
  resolved gam (InCon n err) = InCon <$> traverse (resolved gam) n <*> resolved gam err
  resolved gam (InLHS fc n err) = InLHS fc <$> resolved gam n <*> resolved gam err
  resolved gam (InRHS fc n err) = InRHS fc <$> resolved gam n <*> resolved gam err
  resolved gam (MaybeMisspelling err xs) = MaybeMisspelling <$> resolved gam err <*> pure xs
  resolved gam (WarningAsError wrn) = WarningAsError <$> resolved gam wrn
  resolved gam (OperatorBindingMismatch fc expected actual (Left opName) rhs candidates)
      = OperatorBindingMismatch fc expected actual
          <$> (Left <$> resolved gam opName) <*> pure rhs <*> pure candidates
  resolved gam (OperatorBindingMismatch fc expected actual (Right opName) rhs candidates)
      = OperatorBindingMismatch fc expected actual
          <$> (Right <$> resolved gam opName) <*> pure rhs <*> pure candidates

export
HasNames Totality where
  full gam (MkTotality t c) = pure $ MkTotality !(full gam t) !(full gam c)
  resolved = resolveTotality

export
HasNames SCCall where
  full gam sc = pure $ { fnCall := !(full gam (fnCall sc)) } sc
  resolved gam sc = pure (resolveSCCall gam sc)

export
HasNames a => HasNames (Maybe a) where
  full gam Nothing = pure Nothing
  full gam (Just x) = pure $ Just !(full gam x)
  resolved gam Nothing = pure Nothing
  resolved gam (Just x) = pure $ Just !(resolved gam x)

||| A definition as a TTC holds it: every term live (a stored one decoded),
||| every name full, and the module's namespace trimmed from its case
||| tree's and clauses' references.
export
writtenDef : Context -> Namespace -> GlobalDef -> Core GlobalDef
writtenDef gam ns def
    = do ty <- typeOf def
         d <- fullDef (definition def)
         pure $ { type := LiveType !(full gam ty),
                  definition := d,
                  totality := !(full gam (totality def)),
                  refersToM := !(full gam (refersToM def)),
                  sizeChange := !(traverse (full gam) (sizeChange def))
                } def
  where
    fullClause : (vs : Scope ** (Env Term vs, Term vs, Term vs)) ->
                 Core (vs : Scope ** (Env Term vs, Term vs, Term vs))
    fullClause (_ ** (env, lhs, rhs))
        = pure (_ ** (!(full gam env),
                      trimNS ns !(full gam lhs), trimNS ns !(full gam rhs)))

    fullDef : Def -> Core Def
    fullDef (PMDef r args body)
        = do ct <- treeOf body
             ps <- clausePatsOf body
             cs <- clausesOf body
             ct' <- full gam ct
             ps' <- onClausePatNames (full gam) (full gam) ps
             cs' <- traverse fullClause cs
             pure (PMDef r args (LiveBody (trimNS ns ct') ps' cs'))
    fullDef (TCon a ps ds u ms mcs det)
        = pure $ TCon a ps ds u !(traverse (full gam) ms)
                                  !(traverseOpt (traverse (full gam)) mcs) det
    fullDef (BySearch c n) = pure $ BySearch c !(full gam n)
    fullDef (Guess tm b cs) = pure $ Guess !(full gam tm) b cs
    fullDef t = pure t

-- Return all the currently defined names
export
allNames : Context -> Core (List Name)
allNames ctxt = traverse (full ctxt) $ map Resolved [1..nextEntry ctxt - 1]

||| The modules a context's imports reach without importing them, and the
||| definitions read from them, which the termination check reads and the
||| elaborator never sees. A definition an import holds may call into any
||| module that import reaches, but a module is checked with only what its
||| imports make visible; a check that follows calls out of that finds the
||| callees here. A module is named here when a module the context imports
||| imports it and no import of this context reads it, and read the first
||| time the check needs a definition the context does not hold.
public export
record Unimported where
  constructor MkUnimported
  ||| The modules named and not read yet.
  unread : List ModuleIdent
  ||| The definitions of the modules read, and of every module they
  ||| import, by full name.
  unimportedDefs : NameMap ContextEntry

%prefix_record_projections off

||| A TTC the session read: its file and where the search found it, the
||| module it holds, named as the locations of its terms name it (the main
||| module too, under the module its path names), whether it was read
||| re-exported, and the namespace it was read as.
public export
record Loaded where
  constructor MkLoaded
  file : String
  foundIn : Found
  ident : ModuleIdent
  reexported : Bool
  readAs : Namespace

%prefix_record_projections on

||| An `import` of a module: where it is written, whether it re-exports,
||| the module, and the namespace it is imported as. The parser makes it and
||| the TTC keeps it, so a reader of a module's imports reads this fact.
public export
record Import where
  constructor MkImport
  loc : FC
  reexport : Bool
  path : ModuleIdent
  nameAs : Namespace

%prefix_record_projections off

||| An import the session read: the module whose TTC writes it, the import
||| as written there, and the module read for it. The loader makes one
||| where it resolves the import, so a reader of what a module imports
||| reads which module each import is, never resolving its name again.
public export
record ImportRead where
  constructor MkImportRead
  importer : Loaded
  written : Import
  importee : Loaded

%prefix_record_projections on

public export
record Defs where
  constructor MkDefs
  gamma : Context
  mutData : List Name -- Currently declared but undefined data types
  currentNS : Namespace -- namespace for current definitions
  nestedNS : List Namespace -- other nested namespaces we can look in
  options : Options
  toSave : NameMap ()
  typeHints : NameMap (List (Name, Bool))
     -- ^ a mapping from type names to hints (and a flag setting whether it's
     -- a "direct" hint). Direct hints are searched first (as part of a group)
     -- the indirect hints. Indirect hints, in practice, are used to find
     -- instances of parent interfaces, and we don't search these until we've
     -- tried to find a direct result via a constructor or a top level hint.
  autoHints : NameMap Bool
     -- ^ global search hints. A mapping from the hint name, to whether it is
     -- a "default hint". A default hint is used only if all other attempts
     -- to search fail (this flag is really only intended as a mechanism
     -- for defaulting of literals)
  openHints : NameMap ()
     -- ^ currently open global hints; just for the rest of this module (not exported)
     -- and prioritised
  localHints : NameMap ()
     -- ^ Hints defined in the current environment
  saveTypeHints : List (Name, Name, Bool)
     -- We don't look up anything in here, it's merely for saving out to TTC.
     -- We save the hints in the 'GlobalDef' itself for faster lookup.
  saveAutoHints : List (Name, Bool)
  namedirectives : NameMap (List String)
  ifaceHash : Int
  importHashes : List (Namespace, Int)
     -- ^ interface hashes of imported modules
  imported : List Import
     -- ^ the modules this module imports, each where its `import` is
  pragmaUses : List PragmaUse
     -- ^ the pragmas this module writes, each where it is written
  allImported : List Loaded
     -- ^ every TTC the session read, so that none is read twice (a record
     -- of all the things we've called 'readFromTTC' with, in practice)
  importsRead : List ImportRead
     -- ^ every import of a TTC the session read that it read in turn, the
     -- last first, each with the module it was read as
  cgdirectives : List (CG, String)
     -- ^ Code generator directives, which are free form text and thus to
     -- be interpreted however the specific code generator requires
  userHoles : NameMap Bool
     -- ^ Metavariables the user still has to fill in. In practice, that's
     -- everything with a user accessible name and a definition of Hole.
     -- The Bool says whether it was introduced in another module.
  timings : StringMap (Bool, Integer)
     -- ^ record of timings from logTimeRecord
  warnings : List Warning
     -- ^ as yet unreported warnings
  schemeEvalLoaded : Bool
  foreignExports : NameMap (List (String, String))
       -- ^ For functions which are callable from a foreign language. This
       -- maps names to a pair of the back end and the exported function name
  defsStack : SnocList Name -- stack of the definition names being processed
  unimported : Unimported

-- Label for context references
export
data Ctxt : Type where


export
clearDefs : Defs -> Core Defs
clearDefs defs
    = pure ({ gamma->inlineOnly := True } defs)

||| A context holding nothing, over the session's table of identifiers.
export
initDefsWith : Ref Interned Idents -> Core Defs
initDefsWith ids
    = do gam <- initCtxt ids
         opts <- defaults
         pure $ MkDefs
           { gamma = gam
           , mutData = []
           , currentNS = mainNS
           , nestedNS = []
           , options = opts
           , toSave = empty
           , typeHints = empty
           , autoHints = empty
           , openHints = empty
           , localHints = empty
           , saveTypeHints = []
           , saveAutoHints = []
           , namedirectives = empty
           , ifaceHash = 5381
           , importHashes = []
           , imported = []
           , pragmaUses = []
           , allImported = []
           , importsRead = []
           , cgdirectives = []
           , userHoles = empty
           , timings = empty
           , warnings = []
           , schemeEvalLoaded = False
           , foreignExports = empty
           , defsStack = [<]
           , unimported = MkUnimported [] empty
           }

||| The first context of a process, with the process's table of identifiers.
export
initDefs : Core Defs
initDefs
    = do ids <- newRef Interned seeded
         initDefsWith ids

||| The identifier spelled so, from the session's table: the one met before,
||| or a new one. Text becomes an identifier only here, where it enters the
||| compiler (a source's tokens, a TTC's names, a name the elaborator makes
||| from text); everything after compares identifiers by id.
export
internWith : (ids : Ref Interned Idents) -> String -> Core Ident
internWith ids s
    = do t <- get Interned @{ids}
         let (i, t') = internIn s t
         put Interned @{ids} t'
         pure i

export
intern : {auto c : Ref Ctxt Defs} -> String -> Core Ident
intern s = internWith (!(get Ctxt)).gamma.idents s

||| A user name spelled as text: `_` is no name, `.x` the field `x`.
export
internUserName : {auto c : Ref Ctxt Defs} -> String -> Core UserName
internUserName "_" = pure Underscore
internUserName str
    = case strUncons str of
           Just ('.', n) => Field <$> intern n
           _ => Basic <$> intern str

||| A namespace spelled as text, its parts separated by dots.
export
internNamespace : {auto c : Ref Ctxt Defs} -> String -> Core Namespace
internNamespace "" = pure emptyNS
internNamespace str = nsOf <$> traverse intern (forget (split (== '.') str))

||| A module's identifier spelled as text, its parts separated by dots.
export
internModuleIdent : {auto c : Ref Ctxt Defs} -> String -> Core ModuleIdent
internModuleIdent str = nsAsModuleIdent <$> internNamespace str

||| The identifier a name's root (`nameRoot`) is spelled by: the name's own,
||| reused, and interned only for the text a block's or a resolved name's
||| root is printed as, which no identifier holds.
export
rootIdent : {auto c : Ref Ctxt Defs} -> Name -> Core Ident
rootIdent (NS _ n) = rootIdent n
rootIdent (UN (Basic i)) = pure i
rootIdent (UN (Field i)) = pure i
rootIdent (UN Underscore) = pure (known K_)
rootIdent (MN i _) = pure i
rootIdent (PV n _) = rootIdent n
rootIdent (DN _ n) = rootIdent n
rootIdent (Nested _ n) = rootIdent n
rootIdent n = intern (nameRoot n)

-- Reset the context, except for the options
export
clearCtxt : {auto c : Ref Ctxt Defs} ->
            Core ()
clearCtxt
    = do defs <- get Ctxt
         put Ctxt ({ options := resetElab (options defs),
                     timings := timings defs } !(initDefsWith defs.gamma.idents))
  where
    resetElab : Options -> Options
    resetElab opts =
      let tot = totalReq (session opts) in
      { elabDirectives := { totality := tot } defaultElab } opts

export
getFieldNames : Context -> Namespace -> List Name
getFieldNames ctxt recNS
  = let nms = resolvedAs ctxt in
    keys $ flip filterBy nms $ \ n =>
      case isRF n of
        Nothing => False
        Just (ns, field) => ns == recNS

-- Find similar looking names in the context
export
getSimilarNames : {auto c : Ref Ctxt Defs} ->
                  -- Predicate run to customise the behavior of looking for similar names
                  -- Sometime we might want to hide names that we know make no sense.
                  {default Nothing keepPredicate : Maybe ((Name, GlobalDef) -> Core Bool)} ->
                  Name -> Core (Maybe (String, List (Name, Visibility, Nat)))
getSimilarNames nm = case show <$> userNameRoot nm of
  Nothing => pure Nothing
  Just str => if length str <= 1 then pure (Just (str, [])) else
    do defs <- get Ctxt
       let threshold : Nat := max 1 (divNatNZ (length str) 3 ItIsSucc)
       let test : Name -> Core (Maybe (Visibility, Nat)) := \ nm => do
               let (Just str') = show <$> userNameRoot nm
                   | _ => pure Nothing
               dist <- coreLift $ Levenshtein.compute str str'
               let True = dist <= threshold
                   | False => pure Nothing
               Just def <- lookupCtxtExact nm (gamma defs)
                   | Nothing => pure Nothing -- should be impossible
               let predicate = fromMaybe (\_ => pure True) keepPredicate
               True <- predicate (nm, def)
                   | False => pure Nothing
               pure (Just (collapseDefault $ visibility def, dist))
       kept <- NameMap.mapMaybeM @{CORE} test (resolvedAs (gamma defs))
       pure $ Just (str, toList kept)

export
showSimilarNames : Namespace -> Name -> String ->
                   List (Name, Visibility, Nat) -> List String
showSimilarNames ns nm str kept
  = let (loc, priv) := partitionEithers $ kept <&> \ (nm', vis, n) =>
                         let False = fst (splitNS nm') `isParentOf` ns
                               | _ => Left (nm', n)
                             Private = vis
                               | _ => Left (nm', n)
                         in Right (nm', n)
        sorted      := sortBy (compare `on` snd)
        roots1      := mapMaybe (showNames nm str False . fst) (sorted loc)
        roots2      := mapMaybe (showNames nm str True  . fst) (sorted priv)
    in nub roots1 ++ nub roots2

  where

  showNames : Name -> String -> Bool -> Name -> Maybe String
  showNames target str priv nm = do
    let adj  = if priv then " (not exported)" else ""
    let root = nameRoot nm
    let True = str == root
      | _ => pure (root ++ adj)
    let full = show (pretty nm)
    let True = (str == full || show target == full) && not priv
      | _ => pure (full ++ adj)
    Nothing


getVisibility : {auto c : Ref Ctxt Defs} ->
                FC -> Name -> Core (WithDefault Visibility Private)
getVisibility fc n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => throw (UndefinedName fc n)
         pure $ visibility def

maybeMisspelling : {auto c : Ref Ctxt Defs} ->
                   Error -> Name -> Core a
maybeMisspelling err nm = do
  ns <- currentNS <$> get Ctxt
  Just (str, kept) <- getSimilarNames nm
    | Nothing => throw err
  let candidates = showSimilarNames ns nm str kept
  case candidates of
    [] => throw err
    (x::xs) => throw (MaybeMisspelling err (x ::: xs))

-- Throw an UndefinedName exception. But try to find similar names first.
export
undefinedName : {auto c : Ref Ctxt Defs} ->
                FC -> Name -> Core a
undefinedName loc nm = maybeMisspelling (UndefinedName loc nm) nm

-- Throw a NoDeclaration exception. But try to find similar names first.
export
noDeclaration : {auto c : Ref Ctxt Defs} ->
                FC -> Name -> Core a
noDeclaration loc nm = maybeMisspelling (NoDeclaration loc nm) nm

export
ambiguousName : {auto c : Ref Ctxt Defs} -> FC
             -> Name -> List Name
             -> Core a
ambiguousName fc n ns = do
  ns <- filterM (\x => pure $ !(collapseDefault <$> getVisibility fc x) /= Private) ns
  case ns of
    [] =>         undefinedName fc n
    ns => throw $ AmbiguousName fc ns

-- Get the canonical name of something that might have been aliased via
-- import as
export
canonicalName : {auto c : Ref Ctxt Defs} ->
                FC -> Name -> Core Name
canonicalName fc n
    = do defs <- get Ctxt
         case !(lookupCtxtName n (gamma defs)) of
              [(n, _, _)] => pure n
              ns => ambiguousName fc n (map fst ns)

-- If the name is aliased, get the alias
export
aliasName : {auto c : Ref Ctxt Defs} ->
            Name -> Core Name
aliasName fulln
    = do defs <- get Ctxt
         let Just r = userNameRoot fulln
                | Nothing => pure fulln
         let Just ps = lookup r (possibles (gamma defs))
                | Nothing => pure fulln
         findAlias ps
  where
    findAlias : List PossibleName -> Core Name
    findAlias [] = pure fulln
    findAlias (Alias as full i :: ps)
        = if full == fulln
             then pure as
             else findAlias ps
    findAlias (_ :: ps) = findAlias ps

-- Beware: if your hashable thing contains (potentially resolved) names,
-- it'll be better to use addHashWithNames to make the hash independent
-- of the internal numbering of names.
export
addHash : {auto c : Ref Ctxt Defs} -> Hashable a => a -> Core ()
addHash x = update Ctxt { ifaceHash $= flip hashWithSalt x }

export
initHash : {auto c : Ref Ctxt Defs} -> Core ()
initHash = update Ctxt { ifaceHash := 5381 }

export
addUserHole : {auto c : Ref Ctxt Defs} ->
              Bool -> -- defined in another module?
              Name -> -- hole name
              Core ()
addUserHole ext n = update Ctxt { userHoles $= insert n ext }

export
clearUserHole : {auto c : Ref Ctxt Defs} -> Name -> Core ()
clearUserHole n = update Ctxt { userHoles $= delete n }

export
getUserHoles : {auto c : Ref Ctxt Defs} ->
               Core (List Name)
getUserHoles
    = do defs <- get Ctxt
         let hs = sort (keys (userHoles defs))
         filterM (isHole defs) hs
  where
    -- If a hole is declared in one file and defined in another, its
    -- name won't have been cleared unless we've already looked up its
    -- definition (as addDef needs to be called to clear it). So here
    -- check that it's really a hole
    isHole : Defs -> Name -> Core Bool
    isHole defs n
        = do Just def <- lookupCtxtExact n (gamma defs)
                  | Nothing => pure True
             pure $ case definition def of
                  None => True
                  Hole {} => True
                  _ => False

export
addDef : {auto c : Ref Ctxt Defs} ->
         Name -> GlobalDef -> Core Int
addDef n def
    = do defs <- get Ctxt
         (idx, gam') <- addCtxt n def (gamma defs)
         put Ctxt ({ gamma := gam' } defs)
         case definition def of
              None => pure ()
              Hole {} => pure ()
              _ => clearUserHole (fullname def)
         pure idx

export
addContextEntry : {auto c : Ref Ctxt Defs} ->
                  Namespace -> Name -> Binary -> Core Int
addContextEntry ns n def
    = do defs <- get Ctxt
         (idx, gam') <- addEntry n (Coded ns def) (gamma defs)
         put Ctxt ({ gamma := gam' } defs)
         pure idx

export
addContextAlias : {auto c : Ref Ctxt Defs} ->
                  Name -> Name -> Core ()
addContextAlias alias full
    = do defs <- get Ctxt
         Nothing <- lookupCtxtExact alias (gamma defs)
             | _ => pure () -- Don't add the alias if the name exists already
         gam' <- newAlias alias full (gamma defs)
         put Ctxt ({ gamma := gam' } defs)

export
addBuiltin : {arity : _} ->
             {auto x : Ref Ctxt Defs} ->
             Name -> ClosedTerm -> Totality ->
             PrimFn arity -> Core ()
addBuiltin n ty tot op
   = do ignore $
       addDef n $ MkGlobalDef
         { location = emptyFC
         , fullname = n
         , type = LiveType ty
         , eraseArgs = NatSet.empty
         , safeErase = NatSet.empty
         , specArgs = NatSet.empty
         , inferrable = NatSet.empty
         , multiplicity = top
         , localVars = Scope.empty
         , visibility = specified Public
         , totality = tot
         , isEscapeHatch = False
         , flags = [Inline]
         , refersToM = Nothing
          , invertible = False
         , noCycles = False
         , linearChecked = True
         , definition = Builtin op
         , sizeChange = []
         }

export
updateDef : {auto c : Ref Ctxt Defs} ->
            Name -> (Def -> Maybe Def) -> Core ()
updateDef n fdef
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
             | Nothing => pure ()
         case fdef (definition gdef) of
              Nothing => pure ()
              Just def' => ignore $ addDef n ({ definition := def' } gdef)

export
updateTy : {auto c : Ref Ctxt Defs} ->
           Int -> ClosedTerm -> Core ()
updateTy i ty
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact (Resolved i) (gamma defs)
              | Nothing => pure ()
         ignore $ addDef (Resolved i) ({ type := LiveType ty } gdef)

-- Record that the name has been linearity checked so we don't need to do
-- it again
export
setLinearCheck : {auto c : Ref Ctxt Defs} ->
                 Int -> Bool -> Core ()
setLinearCheck i chk
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact (Resolved i) (gamma defs)
              | Nothing => pure ()
         ignore $ addDef (Resolved i) ({ linearChecked := chk } gdef)

export
setCtxt : {auto c : Ref Ctxt Defs} -> Context -> Core ()
setCtxt gam = update Ctxt { gamma := gam }

export
resolveName : {auto c : Ref Ctxt Defs} ->
            Name -> Core Int
resolveName (Resolved idx) = pure idx
resolveName n
  = do defs <- get Ctxt
       (i, gam') <- getPosition n (gamma defs)
       setCtxt gam'
       pure i

export
addName : {auto c : Ref Ctxt Defs} ->
          Name -> Core Int
addName (Resolved idx) = pure idx
addName n
  = do defs <- get Ctxt
       (i, gam') <- newEntry n (gamma defs)
       setCtxt gam'
       pure i

-- Call this before trying alternative elaborations, so that updates to the
-- context are put in the staging area rather than writing over the mutable
-- array of definitions.
-- Returns the old context (the one we'll go back to if the branch fails)
export
branch : {auto c : Ref Ctxt Defs} ->
       Core Defs
branch
  = do ctxt <- get Ctxt
       gam' <- branchCtxt (gamma ctxt)
       setCtxt gam'
       pure ctxt

-- Call this after trying an elaboration to commit any changes to the mutable
-- array of definitions once we know they're correct. Only actually commits
-- when we're right back at the top level
export
commit : {auto c : Ref Ctxt Defs} ->
       Core ()
commit
  = do defs <- get Ctxt
       gam' <- commitCtxt (gamma defs)
       setCtxt gam'

export
depth : {auto c : Ref Ctxt Defs} ->
      Core Nat
depth
  = do defs <- get Ctxt
       pure (branchDepth (gamma defs))

export
dumpStaging : {auto c : Ref Ctxt Defs} ->
              Core ()
dumpStaging
    = do defs <- get Ctxt
         coreLift $ putStrLn $ "Staging area: " ++ show (keys (staging (gamma defs)))

-- Explicitly note that the name should be saved when writing out a .ttc
export
addToSave : {auto c : Ref Ctxt Defs} ->
          Name -> Core ()
addToSave n_in
  = do defs <- get Ctxt
       n <- full (gamma defs) n_in
       put Ctxt ({ toSave $= insert n () } defs)

-- Specific lookup functions
export
lookupExactBy : (GlobalDef -> a) -> Name -> Context ->
              Core (Maybe a)
lookupExactBy fn n gam
  = do Just gdef <- lookupCtxtExact n gam
            | Nothing => pure Nothing
       pure (Just (fn gdef))

export
lookupNameBy : (GlobalDef -> a) -> Name -> Context ->
             Core (List (Name, Int, a))
lookupNameBy fn n gam
  = do gdef <- lookupCtxtName n gam
       pure (map (\ (n, i, gd) => (n, i, fn gd)) gdef)

export
lookupDefExact : Name -> Context -> Core (Maybe Def)
lookupDefExact = lookupExactBy definition

export
lookupDefName : Name -> Context -> Core (List (Name, Int, Def))
lookupDefName = lookupNameBy definition

export
lookupTyExact : Name -> Context -> Core (Maybe ClosedTerm)
lookupTyExact n gam
  = do Just gdef <- lookupCtxtExact n gam
            | Nothing => pure Nothing
       Just <$> typeOf gdef

export
lookupTyName : Name -> Context -> Core (List (Name, Int, ClosedTerm))
lookupTyName n gam
  = do gdefs <- lookupCtxtName n gam
       traverse (\ (n, i, gd) => do ty <- typeOf gd
                                    pure (n, i, ty)) gdefs

export
lookupDefTyExact : Name -> Context -> Core (Maybe (Def, ClosedTerm))
lookupDefTyExact n gam
  = do Just gdef <- lookupCtxtExact n gam
            | Nothing => pure Nothing
       pure (Just (definition gdef, !(typeOf gdef)))

-- private names are only visible in this namespace if their namespace
-- is the current namespace (or an outer one)
-- that is: the namespace of 'n' is a parent of nspace
export
visibleIn : Namespace -> Name -> Visibility -> Bool
visibleIn nspace (NS ns n) Private = isParentOf ns nspace
-- Public and Export names are always visible
visibleIn nspace n _ = True

export
visibleInAny : List Namespace -> Name -> Visibility -> Bool
visibleInAny nss n vis = any (\ns => visibleIn ns n vis) nss

reducibleIn : Namespace -> Name -> Visibility -> Bool
reducibleIn nspace (NS ns (UN n)) Export = isParentOf ns nspace
reducibleIn nspace (NS ns (UN n)) Private = isParentOf ns nspace
reducibleIn nspace n _ = True

export
reducibleInAny : List Namespace -> Name -> Visibility -> Bool
reducibleInAny nss n vis = any (\ns => reducibleIn ns n vis) nss

export
toFullNames : {auto c : Ref Ctxt Defs} ->
              HasNames a => a -> Core a
toFullNames t
    = do defs <- get Ctxt
         full (gamma defs) t

export
toResolvedNames : {auto c : Ref Ctxt Defs} ->
                  HasNames a => a -> Core a
toResolvedNames t
    = do defs <- get Ctxt
         resolved (gamma defs) t

-- Make the name look nicer for user display
export
prettyName : {auto c : Ref Ctxt Defs} ->
             Name -> Core String
prettyName (Nested (i, _) n)
    = do i' <- toFullNames (Resolved i)
         pure (!(prettyName i') ++ "," ++
               !(prettyName n))
prettyName (CaseBlock outer idx)
    = pure ("case block in " ++ !(prettyName outer))
prettyName (WithBlock outer idx)
    = pure ("with block in " ++ !(prettyName outer))
prettyName (NS ns n) = prettyName n
prettyName n = pure (show n)

-- Add a hash of a thing that contains names,
-- but convert the internal numbers to full names first.
-- This makes the hash not depend on the internal numbering,
-- which is unstable.
export
addHashWithNames : {auto c : Ref Ctxt Defs} ->
  Hashable a => HasNames a => a -> Core ()
addHashWithNames x = toFullNames x >>= addHash

export
setIsEscapeHatch : {auto c : Ref Ctxt Defs} ->
  FC -> Name -> Core ()
setIsEscapeHatch fc n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName fc n
         ignore $ addDef n ({ isEscapeHatch := True } def)

export
setFlag : {auto c : Ref Ctxt Defs} ->
        FC -> Name -> DefFlag -> Core ()
setFlag fc n fl
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName fc n
         let flags' = fl :: filter (/= fl) (flags def)
         ignore $ addDef n ({ flags := flags' } def)

export
setNameFlag : {auto c : Ref Ctxt Defs} ->
              FC -> Name -> DefFlag -> Core ()
setNameFlag fc n fl
    = do defs <- get Ctxt
         [(n', i, def)] <- lookupCtxtName n (gamma defs)
              | res => ambiguousName fc n (map fst res)
         let flags' = fl :: filter (/= fl) (flags def)
         ignore $ addDef (Resolved i) ({ flags := flags' } def)

export
unsetFlag : {auto c : Ref Ctxt Defs} ->
            FC -> Name -> DefFlag -> Core ()
unsetFlag fc n fl
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName fc n
         let flags' = filter (/= fl) (flags def)
         ignore $ addDef n ({ flags := flags' } def)

export
hasFlag : {auto c : Ref Ctxt Defs} ->
          FC -> Name -> DefFlag -> Core Bool
hasFlag fc n fl
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName fc n
         pure (fl `elem` flags def)

export
hasSetTotal : {auto c : Ref Ctxt Defs} -> FC -> Name -> Core Bool
hasSetTotal fc n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
             | Nothing => undefinedName fc n
         pure $ isJust $ findSetTotal def.flags

export
setSizeChange : {auto c : Ref Ctxt Defs} ->
                FC -> Name -> List SCCall -> Core ()
setSizeChange loc n sc
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName loc n
         ignore $ addDef n ({ sizeChange := sc } def)

export
setTotality : {auto c : Ref Ctxt Defs} ->
              FC -> Name -> Totality -> Core ()
setTotality loc n tot
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName loc n
         ignore $ addDef n ({ totality := tot } def)

export
setCovering : {auto c : Ref Ctxt Defs} ->
              FC -> Name -> Covering -> Core ()
setCovering loc n tot
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName loc n
         ignore $ addDef n ({ totality->isCovering := tot } def)

export
setTerminating : {auto c : Ref Ctxt Defs} ->
                 FC -> Name -> Terminating -> Core ()
setTerminating loc n tot
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName loc n
         ignore $ addDef n ({ totality->isTerminating := tot } def)

export
getTotality : {auto c : Ref Ctxt Defs} ->
              FC -> Name -> Core Totality
getTotality loc n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName loc n
         pure $ totality def

export
getSizeChange : {auto c : Ref Ctxt Defs} ->
                FC -> Name -> Core (List SCCall)
getSizeChange loc n
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName loc n
         pure $ sizeChange def

export
setVisibility : {auto c : Ref Ctxt Defs} ->
                FC -> Name -> Visibility -> Core ()
setVisibility fc n vis
    = do defs <- get Ctxt
         Just def <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName fc n
         ignore $ addDef n ({ visibility := specified vis } def)

export
withDefStacked : {auto c : Ref Ctxt Defs} ->
                 Name -> Core a -> Core a
withDefStacked n act
    = do defs <- get Ctxt
         let ds = defs.defsStack
         put Ctxt $ {defsStack $= (:< n)} defs
         act <* update Ctxt {defsStack := ds}

public export
record SearchData where
  constructor MkSearchData
  ||| determining argument positions
  detArgs : NatSet
  ||| Name of functions to use as hints, and whether ambiguity is allowed
  |||
  ||| In proof search, for every group of names
  |||  * If exactly one succeeds, use it
  |||  * If more than one succeeds, report an ambiguity error
  |||  * If none succeed, move on to the next group
  |||
  ||| This allows us to prioritise some names (e.g. to declare 'open' hints,
  ||| which we might us to open an implementation working as a module, or to
  ||| declare a named implementation to be used globally), and to have names
  ||| which are only used if all else fails (e.g. as a defaulting mechanism),
  ||| while the proof search mechanism doesn't need to know about any of the
  ||| details.
  hintGroups : List (Bool, List Name)

||| Get the auto search data for a name.
export
getSearchData : {auto c : Ref Ctxt Defs} ->
                FC -> (defaults : Bool) -> Name ->
                Core SearchData
getSearchData fc defaults target
    = do defs <- get Ctxt
         Just (TCon _ _ dets u _ _ _) <- lookupDefExact target (gamma defs)
              | _ => undefinedName fc target
         hs <- case lookup !(toFullNames target) (typeHints defs) of
                       Just hs => filterM (\x => notHidden x (gamma defs)) hs
                       Nothing => pure []
         if defaults
            then let defns = map fst !(filterM (\x => pure $ isDefault x
                                                 && !(notHidden x (gamma defs)))
                                             (toList (autoHints defs))) in
                     pure (MkSearchData NatSet.empty [(False, defns)])
            else let opens = map fst !(filterM (\x => notHidden x (gamma defs))
                                             (toList (openHints defs)))
                     autos = map fst !(filterM (\x => pure $ not (isDefault x)
                                                 && !(notHidden x (gamma defs)))
                                             (toList (autoHints defs)))
                     tyhs = map fst (filter direct hs)
                     chasers = map fst (filter (not . direct) hs) in
                     pure (MkSearchData dets (filter (isCons . snd)
                               [(False, opens),
                                (False, autos),
                                (not (uniqueAuto u), tyhs),
                                (True, chasers)]))
  where
    ||| We don't want hidden (by `%hide`) names to appear in the search.
    ||| Lookup has to be done by a full qualified name, not a resolved ID.
    notHidden : forall a. (Name, a) -> Context -> Core Bool
    notHidden (n, _) ctxt = do
      fulln <- toFullNames n
      pure $ not (isHidden fulln ctxt)

    isDefault : (Name, Bool) -> Bool
    isDefault = snd

    direct : (Name, Bool) -> Bool
    direct = snd

export
setMutWith : {auto c : Ref Ctxt Defs} ->
             FC -> Name -> List Name -> Core ()
setMutWith fc tn tns
    = do defs <- get Ctxt
         Just g <- lookupCtxtExact tn (gamma defs)
              | _ => undefinedName fc tn
         let TCon a ps dets u _ cons det = definition g
              | _ => throw (GenericMsg fc (show (fullname g) ++ " is not a type constructor [setMutWith]"))
         updateDef tn (const (Just (TCon a ps dets u tns cons det)))

export
addMutData : {auto c : Ref Ctxt Defs} ->
             Name -> Core ()
addMutData n = update Ctxt { mutData $= (n ::) }

export
dropMutData : {auto c : Ref Ctxt Defs} ->
              Name -> Core ()
dropMutData n = update Ctxt { mutData $= filter (/= n) }

export
setDetermining : {auto c : Ref Ctxt Defs} ->
                 FC -> Name -> List1 Name -> Core ()
setDetermining fc tyn args
    = do defs <- get Ctxt
         Just g <- lookupCtxtExact tyn (gamma defs)
              | _ => undefinedName fc tyn
         let TCon a ps _ u cons ms det = definition g
              | _ => throw (GenericMsg fc (show (fullname g) ++ " is not a type constructor [setDetermining]"))
         apos <- getPos 0 (forget args) !(typeOf g)
         updateDef tyn (const (Just (TCon a ps apos u cons ms det)))
  where
    -- Type isn't normalised, but the argument names refer to those given
    -- explicitly in the type, so there's no need.
    getPos : Nat -> List Name -> Term vs -> Core NatSet
    getPos i ns (Bind _ x (Pi {}) sc)
        = if x `elem` ns
             then do rest <- getPos (1 + i) (filter (/=x) ns) sc
                     pure $ insert i rest
             else getPos (1 + i) ns sc
    getPos _ [] _ = pure NatSet.empty
    getPos _ ns ty = throw (GenericMsg fc ("Unknown determining arguments: "
                           ++ showSep ", " (map show ns)))

export
setDetags : {auto c : Ref Ctxt Defs} ->
            FC -> Name -> Maybe NatSet -> Core ()
setDetags fc tyn args
    = do defs <- get Ctxt
         Just g <- lookupCtxtExact tyn (gamma defs)
              | _ => undefinedName fc tyn
         let TCon a ps det u cons ms _ = definition g
              | _ => throw (GenericMsg fc (show (fullname g) ++ " is not a type constructor [setDetermining]"))
         updateDef tyn (const (Just (TCon a ps det u cons ms args)))

export
setUniqueSearch : {auto c : Ref Ctxt Defs} ->
                  FC -> Name -> Bool -> Core ()
setUniqueSearch fc tyn u
    = do defs <- get Ctxt
         Just g <- lookupCtxtExact tyn (gamma defs)
              | _ => undefinedName fc tyn
         let TCon a ps ds fl cons ms det = definition g
              | _ => throw (GenericMsg fc (show (fullname g) ++ " is not a type constructor [setDetermining]"))
         let fl' = { uniqueAuto := u } fl
         updateDef tyn (const (Just (TCon a ps ds fl' cons ms det)))

export
setExternal : {auto c : Ref Ctxt Defs} ->
              FC -> Name -> Bool -> Core ()
setExternal fc tyn u
    = do defs <- get Ctxt
         Just g <- lookupCtxtExact tyn (gamma defs)
              | _ => undefinedName fc tyn
         let TCon a ps ds fl cons ms det = definition g
              | _ => throw (GenericMsg fc (show (fullname g) ++ " is not a type constructor [setDetermining]"))
         let fl' = { external := u } fl
         updateDef tyn (const (Just (TCon a ps ds fl' cons ms det)))

export
addHintFor : {auto c : Ref Ctxt Defs} ->
             FC -> Name -> Name -> Bool -> Bool -> Core ()
addHintFor fc tyn_in hintn_in direct loading
    = do defs <- get Ctxt
         tyn <- toFullNames tyn_in
          -- ^ We have to index by full name because of the order we load -
          -- the name may not be resolved yet when we load the hints.
          -- Revisit if this turns out to be a bottleneck (it seems unlikely)
         hintn <- toResolvedNames hintn_in

         let hs = case lookup tyn (typeHints defs) of
                       Just hs => hs
                       Nothing => []
         if loading
            then put Ctxt
                     ({ typeHints $= insert tyn ((hintn, direct) :: hs)
                      } defs)
            else put Ctxt
                     ({ typeHints $= insert tyn ((hintn, direct) :: hs),
                        saveTypeHints $= ((tyn, hintn, direct) :: )
                      } defs)

export
addGlobalHint : {auto c : Ref Ctxt Defs} ->
                Name -> Bool -> Core ()
addGlobalHint hintn_in isdef
    = do hintn <- toResolvedNames hintn_in
         update Ctxt { autoHints $= insert hintn isdef,
                       saveAutoHints $= ((hintn, isdef) ::) }

export
addLocalHint : {auto c : Ref Ctxt Defs} ->
               Name -> Core ()
addLocalHint hintn_in
    = do hintn <- toResolvedNames hintn_in
         update Ctxt { localHints $= insert hintn () }

export
addOpenHint : {auto c : Ref Ctxt Defs} -> Name -> Core ()
addOpenHint hintn_in
    = do hintn <- toResolvedNames hintn_in
         update Ctxt { openHints $= insert hintn () }

export
dropOpenHint : {auto c : Ref Ctxt Defs} -> Name -> Core ()
dropOpenHint hintn_in
    = do hintn <- toResolvedNames hintn_in
         update Ctxt { openHints $= delete hintn }

export
setOpenHints : {auto c : Ref Ctxt Defs} -> NameMap () -> Core ()
setOpenHints hs = update Ctxt { openHints := hs }

export
clearSavedHints : {auto c : Ref Ctxt Defs} -> Core ()
clearSavedHints = update Ctxt { saveTypeHints := [], saveAutoHints := [] }

-- Set the default namespace for new definitions
export
setNS : {auto c : Ref Ctxt Defs} -> Namespace -> Core ()
setNS ns = update Ctxt { currentNS := ns }

-- Set the nested namespaces we're allowed to look inside
export
setNestedNS : {auto c : Ref Ctxt Defs} ->
              List Namespace -> Core ()
setNestedNS ns = update Ctxt { nestedNS := ns }

-- Get the default namespace for new definitions
export
getNS : {auto c : Ref Ctxt Defs} ->
        Core Namespace
getNS
    = do defs <- get Ctxt
         pure (currentNS defs)

-- Get the nested namespaces we're allowed to look inside
export
getNestedNS : {auto c : Ref Ctxt Defs} ->
              Core (List Namespace)
getNestedNS
    = do defs <- get Ctxt
         pure (nestedNS defs)

-- Add an import of this module: the module, whether it is re-exported,
-- the namespace it is imported as ("import X as Y" is X as Y; "import
-- public X" is, when re-exported, the same as "import X as [current
-- namespace]"), and where it is written.
export
addImported : {auto c : Ref Ctxt Defs} ->
              Import -> Core ()
addImported imp = update Ctxt { imported $= (imp ::) }

||| An import of a TTC the session read, with the module read for it,
||| recorded where the loader resolves it.
export
addImportRead : {auto c : Ref Ctxt Defs} ->
                ImportRead -> Core ()
addImportRead r = update Ctxt { importsRead $= (r ::) }

||| The pragmas this module writes, as its parse kept them.
export
setPragmaUses : {auto c : Ref Ctxt Defs} ->
                List PragmaUse -> Core ()
setPragmaUses uses = update Ctxt { pragmaUses := uses }

||| Names a module that a module the context imports imports, and that no
||| import of this context reads, so that the termination check can read it.
export
addUnimported : {auto c : Ref Ctxt Defs} -> ModuleIdent -> Core ()
addUnimported m = update Ctxt { unimported->unread $= (m ::) }

export
addDirective : {auto c : Ref Ctxt Defs} ->
               String -> String -> Core ()
addDirective c str
    = do defs <- get Ctxt
         case getCG (options defs) c of
              Nothing => -- warn, rather than fail, because the CG may exist
                         -- but be unknown to this particular instance
                         coreLift $ putStrLn $ "Unknown code generator " ++ c
              Just cg => put Ctxt ({ cgdirectives $= ((cg, str) ::) } defs)

export
getDirectives : {auto c : Ref Ctxt Defs} ->
                CG -> Core (List String)
getDirectives cg
    = do defs <- get Ctxt
         pure $ defs.options.session.directives ++
                 mapMaybe getDir (cgdirectives defs)
  where
    getDir : (CG, String) -> Maybe String
    getDir (x', str) = if cg == x' then Just str else Nothing

-- Add a new nested namespace to the current namespace for new definitions
-- e.g. extendNS ["Data"] when namespace is "Prelude.List" leads to
-- current namespace of "Prelude.List.Data"
-- Inner namespaces go first, for ease of name lookup
export
extendNS : {auto c : Ref Ctxt Defs} -> Namespace -> Core ()
extendNS ns = update Ctxt { currentNS $= (<.> ns) }

export
withExtendedNS : {auto c : Ref Ctxt Defs} ->
                 Namespace -> Core a -> Core a
withExtendedNS ns act
    = do defs <- get Ctxt
         let cns = currentNS defs
         put Ctxt ({ currentNS := cns <.> ns } defs)
         ma <- catch (Right <$> act) (pure . Left)
         defs <- get Ctxt
         put Ctxt ({ currentNS := cns } defs)
         case ma of
           Left err => throw err
           Right a  => pure a

-- Get the name as it would be defined in the current namespace
-- i.e. if it doesn't have an explicit namespace already, add it,
-- otherwise leave it alone
export
inCurrentNS : {auto c : Ref Ctxt Defs} ->
              Name -> Core Name
inCurrentNS (UN n)
    = do defs <- get Ctxt
         pure (NS (currentNS defs) (UN n))
inCurrentNS n@(CaseBlock {})
    = do defs <- get Ctxt
         pure (NS (currentNS defs) n)
inCurrentNS n@(WithBlock {})
    = do defs <- get Ctxt
         pure (NS (currentNS defs) n)
inCurrentNS n@(Nested {})
    = do defs <- get Ctxt
         pure (NS (currentNS defs) n)
inCurrentNS n@(MN {})
    = do defs <- get Ctxt
         pure (NS (currentNS defs) n)
inCurrentNS n@(DN {})
    = do defs <- get Ctxt
         pure (NS (currentNS defs) n)
inCurrentNS n = pure n

export
setVisible : {auto c : Ref Ctxt Defs} ->
             Namespace -> Core ()
setVisible nspace = update Ctxt { gamma->visibleNS $= (nspace ::) }

export
getVisible : {auto c : Ref Ctxt Defs} ->
             Core (List Namespace)
getVisible
    = do defs <- get Ctxt
         pure (visibleNS (gamma defs))

-- set whether all names should be viewed as public. Be careful with this,
-- it's not intended for when checking user code! It's meant for allowing
-- easy checking of partially evaluated definitions.
export
setAllPublic : {auto c : Ref Ctxt Defs} ->
               (pub : Bool) -> Core ()
setAllPublic pub = update Ctxt { gamma->allPublic := pub }

export
isAllPublic : {auto c : Ref Ctxt Defs} ->
              Core Bool
isAllPublic
    = do defs <- get Ctxt
         pure (allPublic (gamma defs))

-- Return True if the given namespace is visible in the context (meaning
-- the namespace itself, and any namespace it's nested inside)
export
isVisible : {auto c : Ref Ctxt Defs} ->
            Namespace -> Core Bool
isVisible nspace
    = do defs <- get Ctxt
         pure (any visible (allParents (currentNS defs) ++
                            nestedNS defs ++
                            visibleNS (gamma defs)))

  where
    -- Visible if any visible namespace is a parent of the namespace we're
    -- asking about
    visible : Namespace -> Bool
    visible visns = isParentOf visns nspace

-- Get the next entry id in the context (this is for recording where to go
-- back to when backtracking in the elaborator)
export
getNextEntry : {auto c : Ref Ctxt Defs} ->
               Core Int
getNextEntry
    = do defs <- get Ctxt
         pure (nextEntry (gamma defs))

-- Set the 'first entry' index (i.e. the first entry in the current file)
-- to the place we currently are in the context
export
resetFirstEntry : {auto c : Ref Ctxt Defs} ->
                  Core ()
resetFirstEntry
    = do defs <- get Ctxt
         put Ctxt ({ gamma->firstEntry := nextEntry (gamma defs) } defs)

export
getFullName : {auto c : Ref Ctxt Defs} ->
              Name -> Core Name
getFullName (Resolved i)
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact (Resolved i) (gamma defs)
              | Nothing => pure (Resolved i)
         pure (fullname gdef)
getFullName n = pure n

-- Getting and setting various options

export
getPPrint : {auto c : Ref Ctxt Defs} ->
            Core PPrinter
getPPrint
    = do defs <- get Ctxt
         pure (printing (options defs))

export
setPPrint : {auto c : Ref Ctxt Defs} -> PPrinter -> Core ()
setPPrint ppopts = update Ctxt { options->printing := ppopts }

export
updatePPrint : {auto c : Ref Ctxt Defs} -> (PPrinter -> PPrinter) -> Core ()
updatePPrint f = update Ctxt { options->printing $= f }

export
getDirs : {auto c : Ref Ctxt Defs} -> Core Dirs
getDirs
    = do defs <- get Ctxt
         pure (dirs (options defs))

export
addExtraDir : {auto c : Ref Ctxt Defs} -> String -> Core ()
addExtraDir dir = update Ctxt { options->dirs->extra_dirs $= ((::) dir) . filter (/= dir) }

export
addPackageDir: {auto c : Ref Ctxt Defs} -> PackageDir -> Core ()
addPackageDir pkg
    = update Ctxt { options->dirs->package_dirs $= ((::) pkg) . filter (\p => p.dir /= pkg.dir) }

export
addPackageSearchPath: {auto c : Ref Ctxt Defs} -> String -> Core ()
addPackageSearchPath dir =
  let newPath = parse dir
   in update Ctxt { options->dirs->package_search_paths $= ((::) newPath) . filter (/= newPath) }

export
addDataDir : {auto c : Ref Ctxt Defs} -> String -> Core ()
addDataDir dir = update Ctxt { options->dirs->data_dirs $= (++ [dir]) }

export
addLibDir : {auto c : Ref Ctxt Defs} -> String -> Core ()
addLibDir dir = update Ctxt { options->dirs->lib_dirs $= (++ [dir]) }

export
setBuildDir : {auto c : Ref Ctxt Defs} -> String -> Core ()
setBuildDir dir = update Ctxt { options->dirs->build_dir := dir }

export
setDependsDir : {auto c : Ref Ctxt Defs} -> String -> Core ()
setDependsDir dir = update Ctxt { options->dirs->depends_dir := dir }

export
setOutputDir : {auto c : Ref Ctxt Defs} -> Maybe String -> Core ()
setOutputDir dir = update Ctxt { options->dirs->output_dir := dir }

export
setSourceDir : {auto c : Ref Ctxt Defs} -> Maybe String -> Core ()
setSourceDir mdir = update Ctxt { options->dirs->source_dir := mdir }

export
setWorkingDir : {auto c : Ref Ctxt Defs} -> String -> Core ()
setWorkingDir dir
    = do coreLift_ $ changeDir dir
         Just cdir <- coreLift $ currentDir
              | Nothing => throw (InternalError "Can't get current directory")
         update Ctxt { options->dirs->working_dir := cdir }

export
getWorkingDir : Core String
getWorkingDir
    = do Just d <- coreLift $ currentDir
              | Nothing => throw (InternalError "Can't get current directory")
         pure d

export
setExtraDirs : {auto c : Ref Ctxt Defs} -> List String -> Core ()
setExtraDirs dirs = update Ctxt { options->dirs->extra_dirs := dirs }

export
withCtxt : {auto c : Ref Ctxt Defs} -> Core a -> Core a
withCtxt = wrapRef Ctxt resetCtxt
  where
    resetCtxt : Defs -> Core ()
    resetCtxt defs = do let dir = defs.options.dirs.working_dir
                        coreLift_ $ changeDir dir

export
setPrefix : {auto c : Ref Ctxt Defs} -> String -> Core ()
setPrefix dir = update Ctxt { options->dirs->prefix_dir := dir }

export
setExtension : {auto c : Ref Ctxt Defs} -> LangExt -> Core ()
setExtension e = update Ctxt { options $= setExtension e }

export
isExtension : LangExt -> Defs -> Bool
isExtension e defs = isExtension e (options defs)

export
checkUnambig : {auto c : Ref Ctxt Defs} ->
               FC -> Name -> Core Name
checkUnambig fc n
    = do defs <- get Ctxt
         case !(lookupDefName n (gamma defs)) of
              [(fulln, i, _)] => pure (Resolved i)
              ns => ambiguousName fc n (map fst ns)

export
lazyActive : {auto c : Ref Ctxt Defs} -> Bool -> Core ()
lazyActive a = update Ctxt { options->elabDirectives->lazyActive := a }

export
setUnboundImplicits : {auto c : Ref Ctxt Defs} -> Bool -> Core ()
setUnboundImplicits a = update Ctxt { options->elabDirectives->unboundImplicits := a }

export
setPrefixRecordProjections : {auto c : Ref Ctxt Defs} -> Bool -> Core ()
setPrefixRecordProjections b = update Ctxt { options->elabDirectives->prefixRecordProjections := b }

export
setDefaultTotalityOption : {auto c : Ref Ctxt Defs} ->
                           TotalReq -> Core ()
setDefaultTotalityOption tot = update Ctxt { options->elabDirectives->totality := tot }

export
setNFThreshold : {auto c : Ref Ctxt Defs} ->
                 Nat -> Core ()
setNFThreshold max = update Ctxt { options->elabDirectives->nfThreshold := max }

export
isLazyActive : {auto c : Ref Ctxt Defs} ->
               Core Bool
isLazyActive
    = do defs <- get Ctxt
         pure (lazyActive (elabDirectives (options defs)))

export
isUnboundImplicits : {auto c : Ref Ctxt Defs} ->
                  Core Bool
isUnboundImplicits
    = do defs <- get Ctxt
         pure (unboundImplicits (elabDirectives (options defs)))

export
isPrefixRecordProjections : {auto c : Ref Ctxt Defs} -> Core Bool
isPrefixRecordProjections =
  prefixRecordProjections . elabDirectives . options <$> get Ctxt

export
getDefaultTotalityOption : {auto c : Ref Ctxt Defs} ->
                           Core TotalReq
getDefaultTotalityOption
    = do defs <- get Ctxt
         pure (totality (elabDirectives (options defs)))

export
setPair : {auto c : Ref Ctxt Defs} ->
          FC -> (pairType : Name) -> (fstn : Name) -> (sndn : Name) ->
          Core ()
setPair fc ty f s
    = do ty' <- checkUnambig fc ty
         f' <- checkUnambig fc f
         s' <- checkUnambig fc s
         update Ctxt { options $= setPair ty' f' s' }

export
setRewrite : {auto c : Ref Ctxt Defs} ->
             FC -> (eq : Name) -> (rwlemma : Name) -> Core ()
setRewrite fc eq rw
    = do rw' <- checkUnambig fc rw
         eq' <- checkUnambig fc eq
         update Ctxt { options $= setRewrite eq' rw' }

-- Don't check for ambiguity here; they're all meant to be overloadable
export
setFromInteger : {auto c : Ref Ctxt Defs} ->
                 Name -> Core ()
setFromInteger n = update Ctxt { options $= setFromInteger n }

export
setFromString : {auto c : Ref Ctxt Defs} ->
                Name -> Core ()
setFromString n = update Ctxt { options $= setFromString n }

export
setFromChar : {auto c : Ref Ctxt Defs} ->
              Name -> Core ()
setFromChar n = update Ctxt { options $= setFromChar n }

export
setFromDouble : {auto c : Ref Ctxt Defs} ->
              Name -> Core ()
setFromDouble n = update Ctxt { options $= setFromDouble n }

export
setFromTTImp : {auto c : Ref Ctxt Defs} ->
               Name -> Core ()
setFromTTImp n = update Ctxt { options $= setFromTTImp n }

export
setFromName : {auto c : Ref Ctxt Defs} ->
              Name -> Core ()
setFromName n = update Ctxt { options $= setFromName n }

export
setFromDecls : {auto c : Ref Ctxt Defs} ->
               Name -> Core ()
setFromDecls n = update Ctxt { options $= setFromDecls n }

export
addNameDirective : {auto c : Ref Ctxt Defs} ->
                   FC -> Name -> List String -> Core ()
addNameDirective fc n ns
    = do n' <- checkUnambig fc n
         update Ctxt { namedirectives $= insert n' ns  }

-- Checking special names from Options

export
isPairType : {auto c : Ref Ctxt Defs} ->
             Name -> Core Bool
isPairType n
    = do defs <- get Ctxt
         case pairnames (options defs) of
              Nothing => pure False
              Just l => pure $ !(getFullName n) == !(getFullName (pairType l))

export
fstName : {auto c : Ref Ctxt Defs} ->
          Core (Maybe Name)
fstName
    = do defs <- get Ctxt
         pure $ maybe Nothing (Just . fstName) (pairnames (options defs))

export
sndName : {auto c : Ref Ctxt Defs} ->
          Core (Maybe Name)
sndName
    = do defs <- get Ctxt
         pure $ maybe Nothing (Just . sndName) (pairnames (options defs))

export
getRewrite :{auto c : Ref Ctxt Defs} ->
            Core (Maybe Name)
getRewrite
    = do defs <- get Ctxt
         pure $ maybe Nothing (Just . rewriteName) (rewritenames (options defs))

export
isEqualTy : {auto c : Ref Ctxt Defs} ->
            Name -> Core Bool
isEqualTy n
    = do defs <- get Ctxt
         case rewritenames (options defs) of
              Nothing => pure False
              Just r => pure $ !(getFullName n) == !(getFullName (equalType r))

export
fromIntegerName : {auto c : Ref Ctxt Defs} ->
                  Core (Maybe Name)
fromIntegerName
    = do defs <- get Ctxt
         pure $ fromIntegerName (primnames (options defs))

export
fromStringName : {auto c : Ref Ctxt Defs} ->
                 Core (Maybe Name)
fromStringName
    = do defs <- get Ctxt
         pure $ fromStringName (primnames (options defs))

export
fromCharName : {auto c : Ref Ctxt Defs} ->
               Core (Maybe Name)
fromCharName
    = do defs <- get Ctxt
         pure $ fromCharName (primnames (options defs))

export
fromDoubleName : {auto c : Ref Ctxt Defs} ->
               Core (Maybe Name)
fromDoubleName
    = do defs <- get Ctxt
         pure $ fromDoubleName (primnames (options defs))

export
fromTTImpName : {auto c : Ref Ctxt Defs} ->
                Core (Maybe Name)
fromTTImpName
    = do defs <- get Ctxt
         pure $ fromTTImpName (primnames (options defs))

export
fromNameName : {auto c : Ref Ctxt Defs} ->
               Core (Maybe Name)
fromNameName
    = do defs <- get Ctxt
         pure $ fromNameName (primnames (options defs))

export
fromDeclsName : {auto c : Ref Ctxt Defs} ->
                Core (Maybe Name)
fromDeclsName
    = do defs <- get Ctxt
         pure $ fromDeclsName (primnames (options defs))

export
getPrimNames : {auto c : Ref Ctxt Defs} -> Core PrimNames
getPrimNames = [| MkPrimNs fromIntegerName
                           fromStringName
                           fromCharName
                           fromDoubleName
                           fromTTImpName
                           fromNameName
                           fromDeclsName |]

export
getPrimitiveNames : {auto c : Ref Ctxt Defs} -> Core (List Name)
getPrimitiveNames = primNamesToList <$> getPrimNames

export
isPrimName : List Name -> Name -> Bool
isPrimName prims given = let (ns, nm) = splitNS given in go ns nm prims where

  go : Namespace -> Name -> List Name -> Bool
  go ns nm [] = False
  go ns nm (p :: ps)
    = let (ns', nm') = splitNS p in
      (nm' == nm && (ns' `isApproximationOf` ns))
      || go ns nm ps

export
addLogLevel : {auto c : Ref Ctxt Defs} ->
              Maybe LogLevel -> Core ()
addLogLevel Nothing  = update Ctxt { options->session->logEnabled := False, options->session->logLevel := defaultLogLevel }
addLogLevel (Just l) = update Ctxt { options->session->logEnabled := True, options->session->logLevel $= insertLogLevel l }

export
setLogLevel : {auto c : Ref Ctxt Defs} ->
              LogLevel -> Core ()
setLogLevel = addLogLevel . Just

export
stopLogging : {auto c : Ref Ctxt Defs} -> Core ()
stopLogging = addLogLevel Nothing

export
withLogLevel : {auto c : Ref Ctxt Defs} ->
               LogLevel -> Core a -> Core a
withLogLevel l comp = do
  defs <- get Ctxt
  let logs = logLevel (session (options defs))
  put Ctxt ({ options->session->logLevel := insertLogLevel l logs } defs)
  r <- comp
  defs <- get Ctxt
  put Ctxt ({ options->session->logLevel := logs } defs)
  pure r

export
setLogTimings : {auto c : Ref Ctxt Defs} -> Nat -> Core ()
setLogTimings n = update Ctxt { options->session->logTimings := Just n }

export
getSession : {auto c : Ref Ctxt Defs} ->
             Core Session
getSession
    = do defs <- get Ctxt
         pure (session (options defs))

export
setSession : {auto c : Ref Ctxt Defs} -> Session -> Core ()
setSession sopts = update Ctxt { options->session := sopts }

%inline
export
updateSession : {auto c : Ref Ctxt Defs} ->
                (Session -> Session) -> Core ()
updateSession f = setSession (f !getSession)

export
recordWarning : {auto c : Ref Ctxt Defs} -> Warning -> Core ()
recordWarning w = update Ctxt { warnings $= (w ::) }

export
getTime : Core Integer
getTime
    = do clock <- coreLift (clockTime Monotonic)
         pure (seconds clock * nano + nanoseconds clock)
  where
    nano : Integer
    nano = 1000000000

-- Set a name as Private that was previously visible (and, if 'everywhere' is
-- set, hide in any modules imported by this one)
export
hide : {auto c : Ref Ctxt Defs} ->
       FC -> Name -> Core ()
hide fc n
    = do defs <- get Ctxt
         [(nsn, _)] <- lookupCtxtName n (gamma defs)
              | res => ambiguousName fc n (map fst res)
         put Ctxt ({ gamma $= hideName nsn } defs)

-- Set a name as Public that was previously hidden
-- Note: this is here at the bottom only becuase `recordWarning` is defined just above.
export
unhide : {auto c : Ref Ctxt Defs} ->
       FC -> Name -> Core ()
unhide fc n
    = do defs <- get Ctxt
         [(nsn, _)] <- lookupHiddenCtxtName n (gamma defs)
              | res => ambiguousName fc n (map fst res)
         put Ctxt ({ gamma $= unhideName nsn } defs)
         unless (isHidden nsn (gamma defs)) $ do
           recordWarning $ GenericWarn fc $
             "Trying to %unhide `" ++ show nsn ++ "`, which was not hidden in the first place"
