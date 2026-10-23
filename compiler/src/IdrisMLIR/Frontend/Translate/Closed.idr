-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Terms as closed values: types and implementations are compile-time
||| values, closed TT terms, which the translation substitutes, normalises
||| and reduces to their constructors.
module IdrisMLIR.Frontend.Translate.Closed

import Core.Case.CaseTree
import Core.CompileExpr
import Core.Context
import Core.Core
import Core.Env
import Core.Options
import Core.TT
import Idris.Host
import Libraries.Data.List.SizeOf
import Libraries.Data.NatSet

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Contraction
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Proof.Reading
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List1
import Data.Nat
import Data.SnocList
import Data.SortedSet
import Data.Vect

-- A rule's scope (where a refusal is made) is named as the checker's
-- scope of variables is; here every `Scope` is the checker's.
%hide IdrisMLIR.Spec.Core.Rules.Scope

%default total

||| Idris's terms and binders; `Term` and `Binder` are Core's own.
public export
TT : Scope -> Type
TT = Core.TT.Term.Term

public export
TTBinder : Type -> Type
TTBinder = Core.TT.Binder.Binder

||| What is known of a runtime variable's type: its Core type and its
||| closed Idris type, which says which arguments a function-typed value
||| takes at runtime; its Core type alone (a suspension's value, whose
||| Idris type the match on it does not show); or neither (a value a
||| settled term computes, which no type of the scope gives).
public export
data KnownTypes = BothTypes Ty ClosedTerm | CoreTypeOnly Ty | Untyped

||| The Core type of a runtime variable, where it is known (`KnownTypes`).
export
coreOf : KnownTypes -> Maybe Ty
coreOf (BothTypes t _) = Just t
coreOf (CoreTypeOnly t) = Just t
coreOf Untyped = Nothing

||| The closed Idris type of a runtime variable, where it is known
||| (`KnownTypes`).
export
idrisOf : KnownTypes -> Maybe ClosedTerm
idrisOf (BothTypes _ i) = Just i
idrisOf _ = Nothing

||| Where a variable's entry stands: in a case tree's scope, every
||| implementation of which is a parameter's or a part a compile-time match
||| took out of one; or in a term's, which also binds implementations of
||| its own. Essential: the tree takes a parameter's implementation apart,
||| and a term only uses implementations.
public export
data Scoping = OfTree | OfTerm

%prefix_record_projections off

||| The parameter an implementation the instance is given is of: its
||| position among the instance's `kc` parameters, and the values that
||| parameter holds, with the variable that holds them, where it holds any.
public export
record GivenParameter (kc : Nat) (a : Type) where
  constructor MkGivenParameter
  position : Fin kc
  holding : Maybe (a, Holes)

||| A constructor a compile-time match found an implementation built with:
||| the constructor, its arguments as the reduction gave them, the one a
||| part the match bound is, and that part's type, its binder's in the
||| constructor's type closed over the arguments before it.
public export
record Opened where
  constructor MkOpened
  con : Name
  args : List ClosedTerm
  at : Nat
  partType : ClosedTerm

%prefix_record_projections on

export
Functor (GivenParameter kc) where
  map f p = MkGivenParameter p.position (map (\(x, hs) => (f x, hs)) p.holding)

||| What a TT variable stands for: a Core variable (with what is known of
||| its type, `KnownTypes`, and the shape of its value when that is known),
||| a compile-time value, or an implementation's value. Types and
||| implementations are compile-time values, closed TT terms, and so is a
||| variable of quantity 0, which is `TypeValue` of `Erased`: none is a
||| Core variable. An implementation is used by translating it where it is
||| needed. An implementation that closes over runtime values holds
||| markers for them (`holeMarker`), with the variable that holds them and
||| what it holds (`Holes`). The instance has `kc` parameters, and the
||| entry stands in a scope of the kind `sp` says (`Scoping`).
public export
data VarInfo : (kc : Nat) -> Scoping -> Type -> Type where
  Runtime : a -> KnownTypes -> VarInfo kc sp a
  ||| A runtime value whose shape is known: the constructors every call of
  ||| the instance built its argument with (`Instances.classify`), or a
  ||| constructor's field of such a value. The shape stands for the value
  ||| in types, and a match on the value takes only the alternatives a
  ||| value of that shape can. Its Idris type is the one before the shape.
  Shaped : a -> Ty -> ClosedTerm -> ClosedTerm -> VarInfo kc sp a
  TypeValue : ClosedTerm -> VarInfo kc sp a
  ||| An implementation the instance is given, whole, as its parameter's
  ||| kind holds it, fixed (`FixedDictionary`), with the parameter it is
  ||| of (`GivenParameter`), built where the parameters are bound
  ||| (`Programs.runtimeParams`). A part a match took out of one is a
  ||| `Part` in a case tree's scope, and in a term's an implementation
  ||| known as a term (`BoundHere`), which a term only uses.
  Static : FixedDictionary -> Maybe (a, Holes) -> GivenParameter kc a -> VarInfo kc sp a
  ||| A part a compile-time match took out of an implementation the
  ||| instance is given (`Cases.staticCase`), with the parameter it is of
  ||| and the constructor each match on the way found it built with
  ||| (`Opened`), the innermost first, so that a part no reduction reaches
  ||| is put back into the implementation with nothing reduced again
  ||| (`Cases.heldHere`). Only a case tree takes an implementation apart.
  Part : ClosedTerm -> Maybe (a, Holes) -> GivenParameter kc a -> List1 Opened -> VarInfo kc OfTree a
  ||| An implementation a term's scope knows as a term: one a `let` binds or
  ||| a lambda applied there takes, or a part a compile-time match took out
  ||| of a given one (`asTermEntry`), which a term only uses. No case tree's
  ||| scope holds one.
  BoundHere : ClosedTerm -> Maybe (a, Holes) -> VarInfo kc OfTerm a

export
Functor (VarInfo kc sp) where
  map f (Runtime x t) = Runtime (f x) t
  map f (Shaped x t i sh) = Shaped (f x) t i sh
  map f (TypeValue t) = TypeValue t
  map f (Static t h p) = Static t (map (\(x, hs) => (f x, hs)) h) (map f p)
  map f (Part t h p o) = Part t (map (\(x, hs) => (f x, hs)) h) (map f p) o
  map f (BoundHere t h) = BoundHere t (map (\(x, hs) => (f x, hs)) h)

-- An entry's implementation and a term's (`implementationOf` below) are
-- read by one name, told apart by what they read.
namespace VarInfo
  ||| An implementation's entry, given or bound by a term, as a term uses
  ||| either: its form, and the values it closes over where it closes over
  ||| any; nothing for an entry of any other kind.
  export
  implementationOf : VarInfo kc sp a -> Maybe (ClosedTerm, Maybe (a, Holes))
  implementationOf (Static d h _) = Just (d.form, h)
  implementationOf (Part t h _ _) = Just (t, h)
  implementationOf (BoundHere t h) = Just (t, h)
  implementationOf _ = Nothing

||| A case tree's entry as a term's scope holds it, at a leaf: a part of an
||| implementation the instance is given, which no term takes apart, as an
||| implementation known as a term, with the values it closes over.
export
asTermEntry : VarInfo kc OfTree a -> VarInfo kc OfTerm a
asTermEntry (Runtime x t) = Runtime x t
asTermEntry (Shaped x t i sh) = Shaped x t i sh
asTermEntry (TypeValue t) = TypeValue t
asTermEntry (Static d h p) = Static d h p
asTermEntry (Part t h _ _) = BoundHere t h

||| The role Idris gives a constructor of a `Nat`-like type
||| (`TTImp.ProcessData.calcNaty`): the type is `NatT`, zero is `0`, and the
||| successor adds one, as Idris's own backends represent every such type.
||| Idris counts only runtime arguments, so `Fin` is one too.
public export
data NatRole = Zero | Succ

export
natRole : GlobalDef -> Maybe NatRole
natRole def = case mapMaybe role (flags def) of
  (r :: _) => Just r
  [] => Nothing
  where
    role : DefFlag -> Maybe NatRole
    role (ConType ZERO) = Just Zero
    role (ConType SUCC) = Just Succ
    role _ = Nothing

||| One entry per variable of a scope, the innermost first, so that every
||| variable the scope holds has its entry and no other has one.
public export
data ByVar : Scope -> Type -> Type where
  Nil : ByVar [] a
  (::) : a -> ByVar vs a -> ByVar (v :: vs) a

export
Functor (ByVar vs) where
  map f [] = []
  map f (x :: xs) = f x :: map f xs

||| The entries, the innermost first.
export
innermostFirst : ByVar vs a -> List a
innermostFirst [] = []
innermostFirst (x :: xs) = x :: innermostFirst xs

||| The entry of a variable, which its scope says is there.
export
lookupVar : (idx : Nat) -> (0 _ : IsVar n idx vs) -> ByVar vs a -> a
lookupVar Z _ (x :: _) = x
lookupVar (S i) p (_ :: xs) = lookupVar i (dropLater p) xs
lookupVar _ First [] impossible
lookupVar _ (Later _) [] impossible

||| Each entry made by an effect, in scope order.
export
traverseByVar : Applicative f => (a -> f b) -> ByVar vs a -> f (ByVar vs b)
traverseByVar g [] = pure []
traverseByVar g (x :: xs) = (::) <$> g x <*> traverseByVar g xs

||| Two entries of each variable, made one.
export
zipByVar : (a -> b -> c) -> ByVar vs a -> ByVar vs b -> ByVar vs c
zipByVar f [] [] = []
zipByVar f (x :: xs) (y :: ys) = f x y :: zipByVar f xs ys

||| The entries of inner variables put in front of a scope's.
export
prepend : ByVar as a -> ByVar vs a -> ByVar (as ++ vs) a
prepend [] xs = xs
prepend (y :: ys) xs = y :: prepend ys xs

||| One entry per name, each made from the element of a list as long.
export
byVarFrom : (vs : Scope) -> (f : a -> b) -> (xs : List a) -> (0 _ : length xs = length vs) -> ByVar vs b
byVarFrom [] f [] _ = []
byVarFrom (_ :: vs) f (x :: xs) same = f x :: byVarFrom vs f xs (predecessors same)
  where
    predecessors : {0 m, n : Nat} -> S m = S n -> m = n
    predecessors Refl = Refl
byVarFrom [] f (_ :: _) Refl impossible
byVarFrom (_ :: _) f [] Refl impossible

||| The same entry for every name.
export
everyVar : (vs : Scope) -> a -> ByVar vs a
everyVar [] x = []
everyVar (_ :: vs) x = x :: everyVar vs x

||| What each variable of a scope stands for, in an instance of `kc`
||| parameters, in a scope of the kind `sp` says.
public export
StandsFor : (kc : Nat) -> Scoping -> Scope -> Type -> Type
StandsFor kc sp vs a = ByVar vs (VarInfo kc sp a)

||| An environment under a binder of `k` variables, which come first.
export
under : {k : Nat} -> StandsFor kc sp new (Fin (Under k n)) -> StandsFor kc sp vs (Fin n) ->
        StandsFor kc sp (new ++ vs) (Fin (Under k n))
under bound env = prepend bound (map (map (Free {k})) env)

||| Does the term mention `Erased` (a placeholder for an unknown value)?
export
anyErased : TT vars -> Bool
anyErased = mentions erasedTerm
  where
    erasedTerm : TT vs -> Bool
    erasedTerm (Erased _ _) = True
    erasedTerm _ = False

||| An Idris constant as the middle end's literal, one to one: the one place
||| the translation reads Idris's constants. A primitive type or the world
||| is no literal.
export
constantLit : Constant -> Maybe Lit
constantLit (I x) = Just (LInt IdrisInt (cast x))
constantLit (I8 x) = Just (LInt SInt8 (cast x))
constantLit (I16 x) = Just (LInt SInt16 (cast x))
constantLit (I32 x) = Just (LInt SInt32 (cast x))
constantLit (I64 x) = Just (LInt SInt64 (cast x))
constantLit (B8 x) = Just (LInt UInt8 (cast x))
constantLit (B16 x) = Just (LInt UInt16 (cast x))
constantLit (B32 x) = Just (LInt UInt32 (cast x))
constantLit (B64 x) = Just (LInt UInt64 (cast x))
constantLit (Ch x) = Just (LChar (cast (ord x)))
constantLit (Str x) = Just (LStr x)
constantLit (Db x) = Just (LDouble x)
constantLit (BI x) = Just (LBig x)
constantLit _ = Nothing

||| Abstracts every variable in scope with a lambda, giving a closed term whose
||| outermost lambda binds the last variable of `vars`.
wrapLams : {vars : Scope} -> FC -> TT vars -> ClosedTerm
wrapLams {vars = []} fc tm = tm
wrapLams {vars = x :: rest} fc tm =
  wrapLams {vars = rest} fc (Bind fc x (Lam fc top Explicit (Erased fc Placeholder)) tm)

||| A closed term in any scope.
export
embedClosed : {0 vars : Scope} -> ClosedTerm -> TT vars
embedClosed t = embed {outer = vars} t

||| Beta-reduces a closed lambda with its arguments, by substitution.
betaAll : ClosedTerm -> List ClosedTerm -> ClosedTerm
betaAll (Bind _ _ (Lam _ _ _ _) sc) (v :: vs) = betaAll (subst v sc) vs
betaAll tm vs = foldl (App EmptyFC) tm vs

||| Substitutes the outer `let`s of a term. Idris elaborates a record update
||| to a `let` of the record around its fields, so an implementation
||| resolved inside it is written under a `let` it does not use. The `let`s
||| of the body come off first; a body that is then the variable a `let`
||| binds is that `let`'s value, with its own outer `let`s substituted.
zeta : TT vars -> TT vars
zeta (Bind _ _ (Let _ _ v _) sc) = case zeta sc of
  Local _ _ Z _ => zeta v
  body => subst v body
zeta tm = tm

||| `let`s around a `Delay` the elaborator inserted for a `Lazy` expected
||| type, moved into it: the location of the `Delay` and the `let`s around
||| its argument. Idris elaborates `a; let x = v; b` in a `do` block to
||| `a >> (let x = v in Delay b)`, the `Delay` its own, so `v` belongs to
||| the suspended `b` and runs after `a`'s effects; every use of `x` is
||| inside the `Delay`. A `Delay` the source writes is the language's:
||| `f (let x = loop 0 in Delay 3)` evaluates the `let` first, eagerly, and
||| no `let` moves into it.
export
delayedLets : TT vars -> Maybe (FC, TT vars)
delayedLets (TDelay fc (MkDelaying _ ByElaborator) _ arg) = Just (fc, arg)
delayedLets (Bind fc x b@(Let {}) sc) = map (Bind fc x b) <$> delayedLets sc
delayedLets _ = Nothing

||| Is a name the stand-in for a runtime value (`ProbeRuntime`): a part of
||| a written or closed term no compile-time value fills? Idris keeps its
||| own reasons for erasure, `Impossible` among them, so the frontend's
||| stand-in is a probe of its own, never one of Idris's terms.
export
runtimePart : Name -> Bool
runtimePart n = case probeOf n of
  Just ProbeRuntime => True
  _ => False

||| A term in scope as a closed term, each variable the closed term its
||| entry gives, substituted and not normalised.
export
closeOver : {vars : Scope} -> FC -> ByVar vars ClosedTerm -> TT vars -> ClosedTerm
closeOver fc values tm = zeta (betaAll (wrapLams fc tm) (reverse (innermostFirst values)))

||| A term in scope as a closed term, with compile-time values substituted
||| and not normalised, so that an implementation keeps its written form. A
||| runtime variable becomes the stand-in for a runtime value
||| (`runtimePart`), which `runtimeDependent` detects.
export
closeWritten : {vars : Scope} -> FC -> StandsFor kc sp vars a -> TT vars -> ClosedTerm
closeWritten fc env tm = closeOver fc (map value env) tm
  where
    value : VarInfo kc spc a -> ClosedTerm
    value (TypeValue t) = t
    value (Static d _ _) = d.form
    value (Part t _ _ _) = t
    value (BoundHere t _) = t
    -- A shape is what is known of the value at compile time; its holes
    -- are the runtime parts (`skeleton`).
    value (Shaped _ _ _ s) = s
    value (Runtime {}) = probeTerm ProbeRuntime

||| Does a term mention a part that stands for a runtime value, wherever
||| it stands (`runtimeDependent`'s two markers)?
export
hasRuntimePart : TT vars -> Bool
hasRuntimePart = mentions part
  where
    part : TT vs -> Bool
    part (Ref _ _ n) = isJust (markerOf n) || runtimePart n
    part _ = False

||| A closed term with its lambdas applied and the solutions of its
||| metavariables filled in, by the normaliser of Idris's that evaluates
||| nothing else: it unfolds no definition, so it runs none. Its markers
||| come back as themselves (`markerName`).
export
lambdasApplied : ClosedTerm -> Front ClosedTerm
lambdasApplied tm = (.value) <$> core (host.normaliseHoles !frozenContext tm)

||| A term with its unknowns' solutions put in, in a frozen context, with
||| how (`Readings.Solved`): the one solving every reader of a written form
||| takes.
export
solving : (ctx : Frozen) -> (t : ClosedTerm) -> Front (Subset ClosedTerm (Solved ctx t))
solving ctx t with (hasMeta t) proof unknown
  _ | True = (\r => Element r.value (SolvedBy unknown r)) <$> core (host.normaliseHoles ctx t)
  _ | False = pure (Element t (NoUnknown unknown))

||| A written form with the solutions of its metavariables filled in, and
||| nothing else evaluated when it has none (`solving`, in the frozen
||| context).
export
solved : ClosedTerm -> Front ClosedTerm
solved tm = do
  ctx <- frozenContext
  (.fst) <$> solving ctx tm

||| A metavariable applied to its arguments, as the solution the type checker
||| gave it, which Idris's evaluator and its compilers follow too. Idris
||| leaves a solved one in a checked term when it solved it after the term
||| was elaborated (a lambda postponed until its type was known). The
||| solution is a closed term: lambdas over the scope the metavariable was
||| made in, the arguments, and `let`s for that scope's `let`s; both are
||| substituted. `Nothing` for a metavariable without a solution, a hole.
export
solution : {vars : Scope} -> FC -> Name -> List (TT vars) -> Front (Maybe (TT vars))
solution fc n args = do
  Just d <- defined n
    | Nothing => internal fc ("the metavariable " ++ show n ++ " is not in the context")
  case d.matched of
    Just (MkMatched [] (STerm _ tm) _ _) => pure (Just (apply (embedClosed tm) args zero Subst.empty))
    Just _ => internal fc ("the solution of " ++ show n ++ " is not a term")
    Nothing => pure Nothing
  where
    apply : {drop, vs : Scope} -> TT (drop ++ vs) -> List (TT vs) -> SizeOf drop -> SubstEnv drop vs -> TT vs
    apply (Bind _ _ (Lam {}) sc) (a :: as) drop env = apply sc as (suc drop) (a :: env)
    apply (Bind _ _ (Let _ _ val _) sc) as drop env = apply sc as (suc drop) (substs drop env val :: env)
    apply tm as drop env = foldl (App fc) (substs drop env tm) as

||| The normal form of a closed term, its definitions unfolded as in
||| `closeNormalise`.
export
normaliseClosed : ClosedTerm -> Front ClosedTerm
normaliseClosed tm = (.value) <$> core (host.normaliseTypes !frozenContext tm)

||| What a binder of quantity `rig` takes, where no definition's decision
||| is there to read: a computed type's binder.
byQuantity : RigCount -> ArgumentAt
byQuantity rig = case use rig of
  Erased => NoValue
  Used u => RuntimeValue u

||| Does a definition take no value at position `j`? Idris decided it once
||| the definition's clauses were checked against its whole type, and kept
||| it with the definition (`eraseArgs`): the one source of a definition's
||| erasure, read as a bit, with nothing normalised.
erasedPosition : GlobalDef -> (j : Nat) -> Bool
erasedPosition def j = NatSet.elem j (eraseArgs def)

||| What a definition takes at its binder `j`, of quantity `rig`: no value
||| where Idris decided the position erased (`erasedPosition`), the value
||| the quantity says otherwise.
export
argumentAt : GlobalDef -> (j : Nat) -> (rig : RigCount) -> ArgumentAt
argumentAt def j rig = if erasedPosition def j then NoValue else byQuantity rig

||| What a type no definition has takes at each binder its normal form
||| shows (a method's type past its record, computed at a call): its
||| binders' own quantities, since no clause of it was checked.
export
argumentsIn : ClosedTerm -> Front (List ArgumentAt)
argumentsIn ty = shown <$> normaliseClosed ty
  where
    shown : TT vs -> List ArgumentAt
    shown (Bind _ _ (Pi _ rig _ _) sc) = byQuantity rig :: shown sc
    shown _ = []

||| What `runtimeDependent` has read of an application, its head and
||| arguments from the left: a type, whose arguments are types; a part that
||| stands for a runtime value where one exists, after which nothing else
||| matters; the head's definition, at the position of the next argument;
||| or a head that is no definition, which says nothing of its arguments,
||| each of which may then be a value.
data Applied = OfType | Depends | Taking GlobalDef Nat | Unsaid

||| Does a written implementation depend on a runtime value: does a part
||| that stands for one (`runtimePart`: a runtime variable, or a part of a
||| runtime value its shape does not say; or
||| `holeMarker`, the value an implementation closes over) stand
||| where a value exists at runtime? A type does not (a binder's type, a
||| type constructor's arguments), nor does an argument a definition or a
||| constructor takes with quantity 0, which Idris has checked is never
||| used at runtime: `Foldable (Vect n)` does not depend on the length
||| `n`, while `MkBox {v = n}` holds `n` itself. An argument the head's
||| type says nothing of may be a value.
export
runtimeDependent : ClosedTerm -> Front Bool
runtimeDependent = go
  where
    mutual
      go : TT vs -> Front Bool
      go (Ref _ _ n) = pure (isJust (markerOf n) || runtimePart n)
      go (Erased _ (Dotted t)) = go t
      go (Bind _ _ (Pi {}) _) = pure False
      go (Bind _ _ (Let _ _ v _) sc) = if !(go v) then pure True else go sc
      go (Bind _ _ (PLet _ _ v _) sc) = if !(go v) then pure True else go sc
      go (Bind _ _ _ sc) = go sc
      go (TDelay _ _ _ arg) = go arg
      go (TForce _ _ t) = go t
      go (As _ _ _ p) = go p
      go (Meta _ _ _ args) = anyOf args
      go (App _ f a) = do
        Depends <- appliedTo f a
          | _ => pure False
        pure True
      go _ = pure False

      anyOf : List (TT vs) -> Front Bool
      anyOf [] = pure False
      anyOf (t :: ts) = if !(go t) then pure True else anyOf ts

      -- An application's function applied to one more argument.
      appliedTo : TT vs -> TT vs -> Front Applied
      appliedTo f a = case !(applied f) of
        OfType => pure OfType
        Depends => pure Depends
        -- Past every binder the definition's type shows, the type is
        -- computed and Idris erased nothing there: the argument may be a
        -- value, as `erasedPosition` says.
        Taking def j =>
          if erasedPosition def j then pure (Taking def (S j)) else do
            dependent <- go a
            pure (if dependent then Depends else Taking def (S j))
        Unsaid => pure (if !(go a) then Depends else Unsaid)

      applied : TT vs -> Front Applied
      applied (App _ f a) = appliedTo f a
      applied (Ref _ (TyCon _) _) = pure OfType
      applied (Ref _ _ n) = do
        Just d <- defined n
          | Nothing => pure Unsaid
        pure (Taking d.def 0)
      applied f = pure (if !(go f) then Depends else Unsaid)

||| A type with its first binder showing: itself when it shows one, and its
||| normal form (`normaliseClosed`) when a name for a function type hides
||| it (`a -@ b`). The one place a type's next binder is read.
export
showingBinder : ClosedTerm -> Front ClosedTerm
showingBinder ty@(Bind _ _ (Pi {}) _) = pure ty
showingBinder ty = normaliseClosed ty

||| A runtime value an implementation closes over, where its compile-time
||| form stands, by its number among the values (`holeMarker`, below with
||| the values it stands among).
export
holeMarker : Nat -> ClosedTerm

||| One of Idris's normalisers: a closed term's normal form of its kind in
||| the frozen context, with the steps that reach it.
Normaliser : NormalForm -> Type
Normaliser form = (ctx : Frozen) -> (t : ClosedTerm) -> Core (Reduct form ctx t)

||| A projection: a definition that matches one of its parameters against
||| one constructor and returns one of that constructor's arguments, as
||| `fst` and an interface's parents and methods do. Its parameters, the
||| first first, the one it matches, which its case tree says is one of
||| them, the constructor, and the position of the argument it returns.
public export
record Projection where
  constructor MkProjection
  params : Scope
  matched : Nat
  0 param : Name
  0 isParam : IsVar param matched params
  con : Name
  field : Nat

||| The projection a definition is, if it is one: its case tree's root,
||| one alternative whose leaf is one of the constructor's arguments.
projectionOf : Defined -> Maybe Projection
projectionOf d = case d.matched of
  Just m => projected m.args m.tree
  Nothing => Nothing
  where
    projected : (pargs : Scope) -> CaseTree pargs -> Maybe Projection
    projected pargs (Case idx v _ [ConCase cn _ cargs (STerm _ (Local _ _ k _))]) =
      if k < length cargs then Just (MkProjection pargs idx _ v cn k) else Nothing
    projected _ _ = Nothing

||| The projection a definition is, if it is one.
export
projection : Name -> Front (Maybe Projection)
projection n = (>>= projectionOf) <$> defined n

||| The parameters and right-hand side of a definition whose case tree is
||| one leaf; nothing for one that matches, or that has no case tree.
oneLeaf : Defined -> Maybe (vs : Scope ** TT vs)
oneLeaf d = case d.matched of
  Just m => (\rhs => (m.args ** rhs)) <$> leafOf m
  Nothing => Nothing

||| The definition a case, with or nested block belongs to, through every
||| block between: a case or with block's parent is its full name, which
||| Idris keeps; a nested function's parent is its place in the context.
||| Idris's numbers in a nested name are those of the session that
||| elaborated it, so the parents of a loaded one can lead anywhere, even
||| back to a name passed already: the walk enters each parent once
||| (`Walk`), and stops at a name whose parent it has entered.
export
rootOf : Name -> Front Name
rootOf n = climb start (sizeAccessible start) n
  where
    mutual
      -- The accessibility proof is erased, and every clause matches its one
      -- constructor: no alternative is chosen by it.
      climb : (w : Walked) -> (0 _ : SizeAccessible w) -> Name -> Front Name
      climb w (Access rec) m@(NS _ (CaseBlock outer _)) = parent w rec m outer
      climb w (Access rec) m@(NS _ (WithBlock outer _)) = parent w rec m outer
      climb w (Access rec) m@(NS _ (Nested (outer, _) _)) = do
        -- A negative parent is no place, which Idris's bare `Int` allows.
        let Just placement = placementOf outer
          | Nothing => pure m
        -- Entered already: the parents led back to it.
        case enter placement w of
          Nothing => pure m
          Just (Element w' less) => climb w' (rec w' less) !(fullName (Resolved outer))
      climb w (Access _) m = pure m

      -- A block's parent, entered once, as a nested function's is.
      parent : (w : Walked) -> (0 rec : (w' : Walked) -> Smaller w' w -> SizeAccessible w') -> Name -> Name -> Front Name
      parent w rec m outer = do
        Just d <- defined outer
          | Nothing => pure m
        case enter d.placement w of
          Nothing => pure m
          Just (Element w' less) => climb w' (rec w' less) outer

||| Did Idris prove that every call of a definition ends? Its termination
||| check's verdict, read once at the boundary (`Defined.ends`), which
||| follows everything the definition calls, so a reduction through such a
||| definition ends by Idris's proof. Idris checks a block as part of the
||| definition it belongs to, whose calls the block's are, so a block ends
||| when that definition does too.
endsOf : Defined -> Front Ends
endsOf d = do
  owner <- defined !(rootOf (fullname d.def))
  pure (case (d.ends, map (.ends) owner) of
          (ProvedToEnd, Just NotProvedToEnd) => NotProvedToEnd
          (own, _) => own)

||| The definitions a term refers to, each once, in the order first met.
functionsIn : TT vars -> List Name
functionsIn tm = fst (go tm ([<], empty)) <>> []
  where
    Met : Type
    Met = (SnocList Name, SortedSet Name)

    met : Name -> Met -> Met
    met n m@(order, seen) = if contains n seen then m else (order :< n, insert n seen)

    mutual
      go : TT vs -> Met -> Met
      go (Ref _ Func n) m = met n m
      go (Bind _ _ b sc) m = go sc (binder b m)
      go (App _ f a) m = go a (go f m)
      go (As _ _ _ p) m = go p m
      go (TDelayed _ _ t) m = go t m
      go (TDelay _ _ t a) m = go a (go t m)
      go (TForce _ _ t) m = go t m
      go (Meta _ _ _ args) m = each args m
      go (Erased _ (Dotted t)) m = go t m
      go _ m = m

      each : List (TT vs) -> Met -> Met
      each [] m = m
      each (t :: ts) m = each ts (go t m)

      -- A binder's type, then the value of a `let`.
      binder : TTBinder (TT vs) -> Met -> Met
      binder (Lam _ _ _ ty) m = go ty m
      binder (Let _ _ v ty) m = go v (go ty m)
      binder (Pi _ _ _ ty) m = go ty m
      binder (PVar _ _ _ ty) m = go ty m
      binder (PLet _ _ v ty) m = go v (go ty m)
      binder (PVTy _ _ ty) m = go ty m

||| The first definition a term refers to that Idris does not prove ends,
||| if any. Idris's normaliser runs a term only when there is none: it
||| normalises the whole term, so a definition anywhere in it is run.
partialIn : ClosedTerm -> Front (Maybe Name)
partialIn tm = firstOf (functionsIn tm)
  where
    firstOf : List Name -> Front (Maybe Name)
    firstOf [] = pure Nothing
    firstOf (n :: ns) = do
      Just d <- defined n
        | Nothing => firstOf ns
      ProvedToEnd <- endsOf d
        | NotProvedToEnd => pure (Just (fullname d.def))
      firstOf ns

||| A closed term as written, its metavariables filled in, normalised by
||| one of Idris's normalisers: when the term refers to a definition Idris
||| does not prove ends, which the normaliser would run, that definition
||| instead. Every call of a normaliser that unfolds definitions on a term
||| the translation reduces goes through here, so none runs what Idris does
||| not prove ends; the one that applies lambdas (`lambdasApplied`) runs
||| none.
normalisedBy : Normaliser form -> ClosedTerm -> Front (Either Name ClosedTerm)
normalisedBy normaliser tm = do
  filled <- solved tm
  Nothing <- partialIn filled
    | Just n => pure (Left n)
  (Right . (.value)) <$> core (normaliser !frozenContext filled)

||| A closed term expanded by Idris's normaliser, implementations unfolded
||| to their constructors: the form a projection's field is taken from,
||| in which an argument an implementation took erased can stand where its
||| own blocks take it at runtime. Nothing when the term refers to a
||| definition Idris does not prove ends.
export
expandClosed : ClosedTerm -> Front (Maybe ClosedTerm)
expandClosed tm = either (const Nothing) Just <$> normalisedBy host.normalise tm

------------------------------------------------------------------------------
-- Reduction to a head
------------------------------------------------------------------------------

||| What a compile-time value is at its head: a constructor applied to its
||| arguments, or the part its reduction is stuck on.
public export
data Head : Type -> Type where
  Built : Name -> List a -> Head a
  Stuck : StuckOn -> Head a

export
Functor Head where
  map f (Built n args) = Built n (map f args)
  map f (Stuck on) = Stuck on

||| Which of Idris's normalisers a term on the way to the next unfolding
||| is a normal form of, so that none is asked of it again: a term as
||| written, of none; what the normaliser that evaluates only lambdas
||| applied and metavariables gives (`lambdasApplied`), of that one; what
||| the normaliser that keeps to the program's visibility gives, of both.
||| What is left in a normal form of that one is kept from it by its
||| visibility, and goes to the one that unfolds every definition, whose
||| normal form is the head (`again`). A phase holds the phases after it,
||| so that asking a normaliser is a step to a part of the phase.
data Phase : Type
data IsNormal : Phase -> Type
data IsBeta : Phase -> Type

data Phase : Type where
  Normal : Phase
  Beta : (normalised : Phase) -> (0 _ : IsNormal normalised) -> Phase
  Written : (beta : Phase) -> (0 _ : IsBeta beta) -> Phase

data IsNormal : Phase -> Type where
  ItIs : IsNormal Normal

data IsBeta : Phase -> Type where
  ItIsBeta : IsBeta (Beta Normal ItIs)

asWritten : Phase
asWritten = Written (Beta Normal ItIs) ItIsBeta

||| A part of a term a reduction meets (an argument, or the value a lambda
||| or a `let` binds), from where it meets it: as written, to its head
||| (`value`), and to the implementation it stands for (`implemented`),
||| each computed when it is needed, on the head path where the part was
||| met. A projection's field continues the path its record was reduced on.
record Part where
  constructor MkPart
  written : Lazy ClosedTerm
  value : Lazy (Front (Head Part))
  implemented : Lazy (Front ClosedTerm)

-- What each variable of a scope stands for is one part per variable, the
-- innermost first (`ByVar vs Part`), read at a variable by `lookupVar`.

-- A scope's size, one entry per variable.
scopeSize : ByVar vs a -> SizeOf vs
scopeSize [] = zero
scopeSize (_ :: ps) = suc (scopeSize ps)

substEnv : ByVar vs Part -> SubstEnv vs []
substEnv [] = []
substEnv (p :: ps) = p.written :: substEnv ps

||| A term with what each of its variables stands for, as written.
close : ByVar vs Part -> TT vs -> ClosedTerm
close {vs} env tm = substs (scopeSize env) (substEnv env) (rewrite appendNilRightNeutral vs in tm)

||| A term applied to parts, as written.
whole : ByVar vs Part -> TT vs -> List Part -> ClosedTerm
whole env tm args = applyAll (close env tm) args
  where
    applyAll : ClosedTerm -> List Part -> ClosedTerm
    applyAll f [] = f
    applyAll f (a :: as) = applyAll (App EmptyFC f a.written) as

||| The parameters of a definition, the first argument first, from the
||| parts it is applied to, and the parts past them: nothing when it is
||| applied to fewer.
params : (vs : Scope) -> List Part -> Maybe (ByVar vs Part, List Part)
params [] args = Just ([], args)
params (_ :: vs) (a :: args) = map (\(env, rest) => (a :: env, rest)) (params vs args)
params (_ :: _) [] = Nothing

||| A projection applied to parts, when it applies to all of them: the
||| field it takes from the constructor its record reduces to, and the
||| parts past the projection's own.
project : Projection -> List Part -> Front (Maybe (Part, List Part))
project pr args = case params pr.params args of
  Nothing => pure Nothing
  Just (env, extras) => do
    Built built fields <- (lookupVar pr.matched pr.isParam env).value
      | Stuck _ => pure Nothing
    let Just field = getAt pr.field fields
      | Nothing => pure Nothing
    if !(fullName built) /= !(fullName pr.con)
       then pure Nothing
       else pure (Just (field, extras))

||| The head of a normal form, every part of it a normal form too, which
||| nothing is left to reduce. A reference to a name the context does not
||| have stands for what is not known of a runtime value, as it does where
||| a reduction unfolds it (`unfolded`).
normalHead : Context -> ClosedTerm -> Head Part
normalHead ctxt tm = spine tm []
  where
    normalPart : ClosedTerm -> Part
    normalPart t = MkPart t (pure (normalHead ctxt t)) (pure t)

    spine : ClosedTerm -> List Part -> Head Part
    spine (App _ f a) args = spine f (normalPart a :: args)
    spine (Ref _ (DataCon _ _) n) args = Built n args
    spine (Ref _ Bound _) _ = Stuck (OnRuntime tm)
    spine (Ref _ Func n) _ = Stuck (maybe (OnRuntime tm) (const (OnValue tm)) (getNameID n ctxt))
    spine _ _ = Stuck (OnValue tm)

||| A definition the reduction meets again on its head path: unfolding it
||| came back to it, so what ends its recursion is a match on the way,
||| which is Idris's to evaluate. The term goes to Idris's normaliser with
||| every definition unfolded whatever its visibility, when every
||| definition it refers to ends, and its normal form is the head. A
||| definition does not come back to itself through unfoldings and
||| projections alone unless it does not end, so the normaliser is asked
||| only where a match recurses.
again : ClosedTerm -> Front (Head Part)
again tm = do
  fz <- frozenContext
  either (Stuck . OnPartial) (normalHead (gamma (defsOf fz))) <$> normalisedBy host.normaliseAll tm

mutual
  ||| A term, with what each of its variables stands for, applied to parts,
  ||| reduced to its head on a head path. An implementation is a definition
  ||| with one right-hand side, so it is unfolded by binding its parameters
  ||| to its arguments, keeping the rest as written, whatever its
  ||| visibility: one its module exports without its definition is a module
  ||| boundary, not a value. Anything else goes to Idris's normaliser, when
  ||| every definition the term refers to ends, which stops at such an
  ||| implementation: a projection it leaves takes its field from the
  ||| constructor the record reduces to here. A lambda applied to parts and
  ||| a `let` bind their variable to the part, so no term is substituted on
  ||| the way.
  |||
  ||| It ends, lexicographically in the definitions not yet unfolded on the
  ||| path, the phase, and the term: an unfolding puts a definition on the
  ||| path, which it unfolds only while it is not there (`enter`), and one
  ||| met again goes to the normaliser (`again`); asking a normaliser
  ||| moves to the phase of its normal form, of which neither it nor one
  ||| before it is asked again; every other step goes to a part of the
  ||| term. A part's own reductions are suspended where the part is met, a
  ||| part of the term there or of a body on a longer path, so forcing one
  ||| later is no step of the reduction that forces it. What is not bounded
  ||| so, a recursion through a match, the evaluation of a definition that
  ||| matches, and a lambda that reaches the head as a value applied to
  ||| parts, is Idris's normaliser's, the one reduction the frontend takes
  ||| on trust (`Host`): Idris's theory is not strongly normalising, so no
  ||| measure of the term bounds it.
  reduce : Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           ByVar vs Part -> TT vs -> List Part -> Front (Head Part)
  reduce ph w acc env (App _ f a) args = reduce ph w acc env f (partOf ph w acc env a :: args)
  reduce ph w acc env (Bind _ _ (Lam {}) sc) (a :: args) = reduce ph w acc (a :: env) sc args
  reduce ph w acc env tm@(Bind _ _ (Lam {}) _) [] = pure (Stuck (OnValue (close env tm)))
  reduce ph w acc env (Bind _ _ (Let _ _ v _) sc) args = reduce ph w acc (partOf ph w acc env v :: env) sc args
  reduce ph w acc env (Local _ _ idx v) args = applied ph w acc (lookupVar idx v env) args
  reduce ph w acc env (Ref _ (DataCon _ _) n) args = pure (Built n args)
  reduce ph w acc env tm@(Ref _ (TyCon _) _) args = pure (Stuck (OnValue (whole env tm args)))
  reduce ph w acc env tm@(Ref _ Bound _) args = pure (Stuck (OnRuntime (whole env tm args)))
  reduce ph w acc env tm@(Ref _ Func n) args =
    if runtimePart n then pure (Stuck (OnRuntime (whole env tm args)))
      else unfolded ph w acc n (whole env tm args) args
  reduce ph w acc env tm@(Meta _ _ i _) args = filledIn ph w acc i (whole env tm args)
  reduce ph w acc env tm args = normalised ph w acc (whole env tm args)

  ||| A part met on the path.
  partOf : Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           ByVar vs Part -> TT vs -> Part
  partOf ph w acc env a = MkPart (close env a) (reduce ph w acc env a []) (implementing ph w acc env a [])

  ||| A definition applied to parts. A reference to a definition that does
  ||| not exist stands for what is not known of a runtime value
  ||| (`unknownPart`).
  unfolded : Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             Name -> Lazy ClosedTerm -> List Part -> Front (Head Part)
  unfolded ph w acc@(Access rec) n tm args = do
    Just d <- defined n
      | Nothing => pure (Stuck (OnRuntime tm))
    -- A definition of one right-hand side.
    case oneLeaf d of
      Just (pargs ** body) => case params pargs args of
        Nothing => pure (Stuck (OnValue tm))
        Just (env, rest) => case enter d.placement w of
          Nothing => again tm
          Just (Element w' less) => reduce asWritten w' (rec w' less) env body rest
      Nothing => case projectionOf d of
        Nothing => normalised ph w acc tm
        -- A projection: the field it takes from the constructor its record
        -- reduces to here, its arguments as written, so that an
        -- implementation in it stays the implementation it names. A
        -- normal form of the record unfolds every implementation inside
        -- its fields too, so taken first it would give one implementation
        -- a second written form. A record that reduces to no constructor
        -- here is stuck in the normal form of the normaliser that unfolds
        -- every definition, which no other normaliser goes past, so the
        -- projection is what that normaliser makes of it.
        Just pr => do
          Just (field, extras) <- project pr args
            | Nothing => again tm
          applied ph w acc field extras

  ||| A metavariable applied, as the solution Idris gave it: unfolded as a
  ||| definition is, once on a path.
  filledIn : Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             Int -> Lazy ClosedTerm -> Front (Head Part)
  filledIn ph w acc@(Access rec) i tm = do
    -- A negative index is no place, which Idris's bare `Int` allows.
    let Just placement = placementOf i
      | Nothing => again tm
    -- Entered already: met before on this path.
    case enter placement w of
      Nothing => again tm
      Just (Element w' less) => do
        filled <- solved tm
        if hasMeta filled then pure (Stuck (OnValue tm)) else reduce asWritten w' (rec w' less) [] filled []

  ||| A part applied to parts. A constructor takes them as its arguments; a
  ||| runtime value applied is one. Anything else, a lambda or a function
  ||| applied to fewer arguments than it takes, is applied as written
  ||| (`betaReduced`).
  applied : Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Part -> List Part -> Front (Head Part)
  applied ph w acc part [] = part.value
  applied ph w acc part args@(_ :: _) = do
    Built n fields <- part.value
      | Stuck (OnRuntime _) => pure (Stuck (OnRuntime (whole [] part.written args)))
      | Stuck _ => betaReduced ph w acc (whole [] part.written args)
    pure (Built n (fields ++ args))

  ||| A term as written that applies what is no constructor, its lambdas
  ||| applied by the normaliser that unfolds no definition
  ||| (`lambdasApplied`), and reduced on in that normaliser's phase, so
  ||| that a definition the lambdas lead to is unfolded as any other is.
  ||| Applying a lambda is bounded by no measure of the term, since Idris's
  ||| theory is not strongly normalising, so it is Idris's normaliser's. In
  ||| a term that normaliser gave, what applies a function is a projection
  ||| or a `let`, and goes to the normaliser of the phase (`normalised`).
  betaReduced : Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                Lazy ClosedTerm -> Front (Head Part)
  betaReduced (Written beta _) w acc tm = reduce beta w acc [] !(lambdasApplied tm) []
  betaReduced ph w acc tm = normalised ph w acc tm

  ||| A term given to Idris's normaliser that keeps to the program's
  ||| visibility, when every definition it refers to ends, and its normal
  ||| form reduced on the same path. In the normal form, what is still not
  ||| reduced is kept from the normaliser by its visibility, and goes to it
  ||| again with every definition unfolded (`again`).
  normalised : Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
               Lazy ClosedTerm -> Front (Head Part)
  normalised Normal w acc tm = again tm
  normalised (Beta next _) w acc tm = normalisedTo next w acc tm
  normalised (Written (Beta next _) _) w acc tm = normalisedTo next w acc tm
  normalised (Written Normal ItIsBeta) _ _ _ impossible
  normalised (Written (Written _ _) ItIsBeta) _ _ _ impossible

  normalisedTo : Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 Lazy ClosedTerm -> Front (Head Part)
  normalisedTo next w acc tm = case !(normalisedBy host.normalise tm) of
    Left n => pure (Stuck (OnPartial n))
    Right nf => reduce next w acc [] nf []

  ||| The implementation a term stands for (`implementationOf`), with what
  ||| each of its variables stands for, applied to parts.
  implementing : Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 ByVar vs Part -> TT vs -> List Part -> Front ClosedTerm
  implementing ph w acc env (App _ f a) args = implementing ph w acc env f (partOf ph w acc env a :: args)
  implementing ph w acc env (Bind _ _ (Lam {}) sc) (a :: args) = implementing ph w acc (a :: env) sc args
  implementing ph w acc env (Bind _ _ (Let _ _ v _) sc) args =
    implementing ph w acc (partOf ph w acc env v :: env) sc args
  implementing ph w acc env (Local _ _ idx v) args = implementationApplied ph w acc (lookupVar idx v env) args
  implementing ph w acc env tm@(Ref fc _ n) args = do
    Just (field, extras) <- projectedPart n args
      | Nothing => foldl (App fc) (close env tm) <$> implementations args
    implementationApplied ph w acc field extras
  implementing ph w acc env tm args = pure (whole env tm args)

  ||| A projection's field, when the name is a projection that applies.
  projectedPart : Name -> List Part -> Front (Maybe (Part, List Part))
  projectedPart n args = do
    Just pr <- projection n
      | Nothing => pure Nothing
    project pr args

  ||| The implementation a part applied to parts stands for: of the part as
  ||| written applied to them, its lambdas applied as `betaReduced` applies
  ||| them, so that a field a projection takes past its own arguments, or a
  ||| function an implementation is given, is applied to its arguments. In
  ||| a term that normaliser gave, a part is applied by a projection or a
  ||| `let`, and its implementation stays applied to theirs.
  implementationApplied : Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                          Part -> List Part -> Front ClosedTerm
  implementationApplied ph w acc part [] = part.implemented
  implementationApplied (Written beta _) w acc part args@(_ :: _) =
    implementing beta w acc [] !(lambdasApplied (whole [] part.written args)) []
  implementationApplied ph w acc part args@(_ :: _) = do
    f <- part.implemented
    foldl (App EmptyFC) f <$> implementations args

  implementations : List Part -> Front (List ClosedTerm)
  implementations [] = pure []
  implementations (a :: as) = do
    t <- a.implemented
    (t ::) <$> implementations as

||| What a compile-time value reduces to at its head (`reduce`), from a
||| head path that has unfolded nothing.
export
whnf : ClosedTerm -> Front (Head ClosedTerm)
whnf tm = map (\a => Force a.written) <$> reduce asWritten start (sizeAccessible start) [] tm []

||| Whether an implementation the program writes is one implementation now,
||| with the value it reduced to (`FixedNow`), so that a reader of the value
||| does not reduce it again, or one the running program chooses, with what
||| its reduction is stuck on (`ChosenAtRunTime`).
public export
data Fixing = FixedNow FixedValue | ChosenAtRunTime StuckOn

||| What an implementation's form reduces to at its head, whatever type it
||| is given at: an interface's constructor applied to its fields; a value,
||| a lambda or a definition applied to fewer arguments than it takes, which
||| evaluating does nothing to; or what the reduction is stuck on: a
||| runtime value, even deep inside, where the reduction reports the
||| definition it could not unfold (`ifThenElse` on a comparison of one), a
||| value no compile-time reduction passes, or a definition Idris does not
||| prove ends. A dictionary's reading reads it once (`DictionaryReading`).
export
reducedOf : ClosedTerm -> Front HeadReduct
reducedOf form = do
  reduced <- whnf form
  case reduced of
    Built n fields => pure (ReducesTo (FixedConstructor n fields))
    Stuck (OnValue v) => do
      True <- aValue v
        | False => pure (StuckAt (OnValue v))
      pure (ReducesTo (FixedFunction v))
    Stuck on => pure (StuckAt on)
  where
    aValue : ClosedTerm -> Front Bool
    aValue (Bind _ _ (Lam {}) _) = pure True
    aValue v = case getFnArgs v of
      (Ref _ Func n, args) => do
        Just d <- defined n
          | Nothing => pure False
        pure (case d.matched of
                Just m => length args < length m.args
                Nothing => False)
      _ => pure False

||| Whether an implementation of a type (normalised) is one the program
||| fixes now, decided off what its form reduces to (`reducedOf`). Of an
||| interface's own type, it is when its head reduces to the interface's
||| constructor, so a tree that matches on it takes the constructor apart.
||| Of a function type (a constraint over a value, a polymorphic function),
||| it is when it reduces to a value, which each use may apply in place; a
||| value at a type that is no function's says nothing of which
||| implementation it is. One stuck is computed when the program runs, its
||| value chosen among the members its computation fixes.
export
fixedAt : (type : ClosedTerm) -> HeadReduct -> Fixing
fixedAt _ (ReducesTo v@(FixedConstructor _ _)) = FixedNow v
fixedAt (Bind _ _ (Pi {}) _) (ReducesTo v@(FixedFunction _)) = FixedNow v
fixedAt _ (ReducesTo (FixedFunction v)) = ChosenAtRunTime (OnValue v)
fixedAt _ (StuckAt on) = ChosenAtRunTime on

||| Whether an implementation of a type (normalised) is one the program
||| fixes now (`fixedAt`), its form reduced here (`reducedOf`), where no
||| reading of it keeps what it reduces to.
export
fixing : (type, form : ClosedTerm) -> Front Fixing
fixing type form = fixedAt type <$> reducedOf form

||| A projection applied to arguments, when it applies to all of them: the
||| field it takes from the constructor its record reduces to, applied to
||| the arguments past the projection's own.
export
projected : Name -> List ClosedTerm -> Front (Maybe ClosedTerm)
projected n args = do
  Just (field, extras) <- projectedPart n (map (partOf asWritten start (sizeAccessible start) []) args)
    | Nothing => pure Nothing
  pure (Just (whole [] field.written extras))

||| The implementation a written one stands for, so that two are compared
||| by what they are: the name of an implementation applied to its
||| arguments, each of them an implementation reduced in turn, once what
||| leads to it is reduced: a projection of a constructor's argument (an
||| implementation's constraints, which Idris passes as one tuple, taken
||| apart with `fst` and `snd`; a parent taken from an implementation), a
||| `let`, an applied lambda. The implementation itself is not unfolded. A
||| projection's field continues the head path its record was reduced on,
||| so a field that leads back to a definition already unfolded there is
||| the one Idris's normaliser reduces (`again`).
export
implementationOf : ClosedTerm -> Front ClosedTerm
implementationOf tm = implementing asWritten start (sizeAccessible start) [] tm []

||| A term as a message shows it, every name full: a name Idris has
||| resolved to its place in the context prints as `$resolved359`, which
||| says nothing to the reader.
export
showTT : ClosedTerm -> Front String
showTT tm = show <$> fullTerm tm

||| What a message says a reduction is stuck on: the value or the
||| definition it names.
export
stuckText : StuckOn -> Front String
stuckText (OnRuntime tm) = ("the runtime value " ++) <$> showTT tm
stuckText (OnPartial n) = pure (show !(fullName n) ++ ", which Idris does not prove ends")
stuckText (OnValue tm) = ("the value " ++) <$> showTT tm

||| What a shape says a value was built with: a constructor, with the
||| shapes of its arguments. A shape that is no constructor application (an
||| erased part) says nothing of the value.
export
shapeHead : ClosedTerm -> Maybe (Name, List ClosedTerm)
shapeHead tm = case getFnArgs tm of
  (Ref _ (DataCon _ _) n, args) => Just (n, args)
  _ => Nothing

||| A term's skeleton, decided: the skeleton, with the evidence that it is
||| the term's (`Readings.SkeletonOf`), or the evidence that the term has
||| none, no data constructor heading it (`Readings.Unshaped`). A proof of
||| what a request holds of a shape reads the evidence, and an argument cut
||| to a hole carries the second (`Readings.ArgumentCutAt`).
public export
data Skeletal : ClosedTerm -> Type where
  HasSkeleton : (shape : ClosedTerm) -> (0 _ : SkeletonOf t shape) -> Skeletal t
  NoSkeleton : (0 _ : Unshaped t) -> Skeletal t

||| The shape of a term as written: the constructors it is built with,
||| everything else erased, and nothing when its head is no constructor
||| (`Skeletal`). Nothing is evaluated: a constant, a variable or a call
||| says nothing. What the shape does not say is a part of a runtime value,
||| so a hole is the stand-in for one, as a runtime variable is in the
||| written form: `runtimeDependent` refuses it wherever a value is needed.
export
skeleton : (t : ClosedTerm) -> Skeletal t
skeleton (Ref fc (DataCon tag arity) n) = HasSkeleton (Ref fc (DataCon tag arity) n) SkeletonHead
skeleton (App fc f a) = case skeleton f of
  HasSkeleton f' sf => case skeleton a of
    HasSkeleton a' sa => HasSkeleton (App fc f' a') (SkeletonApplied sf (ArgumentKept sa))
    NoSkeleton none => HasSkeleton (App fc f' (probeTerm ProbeRuntime)) (SkeletonApplied sf (ArgumentCutAt none))
  NoSkeleton none => NoSkeleton (UnshapedApplied none)
skeleton (Local fc l i p) = NoSkeleton UnshapedLocal
skeleton (Ref fc Bound n) = NoSkeleton UnshapedBound
skeleton (Ref fc Func n) = NoSkeleton UnshapedFunction
skeleton (Ref fc (TyCon arity) n) = NoSkeleton UnshapedFamily
skeleton (Meta fc n i args) = NoSkeleton UnshapedMeta
skeleton (Bind fc x b sc) = NoSkeleton UnshapedBinder
skeleton (As fc side a p) = NoSkeleton UnshapedAs
skeleton (TDelayed fc r t) = NoSkeleton UnshapedDelayed
skeleton (TDelay fc r ty a) = NoSkeleton UnshapedDelay
skeleton (TForce fc r t) = NoSkeleton UnshapedForce
skeleton (PrimVal fc c) = NoSkeleton UnshapedConstant
skeleton (Erased fc why) = NoSkeleton UnshapedErased
skeleton (TType fc u) = NoSkeleton UnshapedUniverse

||| A runtime value of a type with what its shape says, if anything.
export
shaped : a -> Ty -> ClosedTerm -> ClosedTerm -> VarInfo kc sp a
shaped x t ity s = if isJust (shapeHead s) then Shaped x t ity s else Runtime x (BothTypes t ity)

||| How many constructors deep a shape says what the value was built with.
export
shapeDepth : ClosedTerm -> Nat
shapeDepth tm = maybe Z S (deepest tm)
  where
    -- The depth of the deepest argument of a constructor application.
    deepest : ClosedTerm -> Maybe Nat
    deepest (Ref _ (DataCon _ _) _) = Just Z
    deepest (App _ f a) = (\d => max d (shapeDepth a)) <$> deepest f
    deepest _ = Nothing

mutual
  ||| A shape cut at a depth: every part below it, and every part the shape
  ||| does not say, is `hole`. Its body is public, and the spine is read
  ||| with its evidence (`Proof.Reading.spineOf`, which gathers the
  ||| arguments as `getFnArgs` does), so a proof sees what a cut keeps
  ||| (`cutShapeNeeded`).
  public export
  cutShape : ClosedTerm -> Nat -> ClosedTerm -> ClosedTerm
  cutShape hole Z _ = hole
  cutShape hole (S d) tm = cutSpine hole d (spineOf tm)

  ||| A term's spine cut below its head: a data constructor applied to its
  ||| arguments each cut one level shallower, rebuilt at the constructor's
  ||| location; any other head, the hole.
  public export
  cutSpine : ClosedTerm -> Nat -> {0 tm : ClosedTerm} -> SpineOf tm -> ClosedTerm
  cutSpine hole d (MkSpineOf con@(Ref fc (DataCon _ _) _) args _) = foldl (App fc) con (map (cutShape hole d) args)
  cutSpine hole d (MkSpineOf _ _ _) = hole

-- Rebuilding over a spine one argument longer is the spine before it,
-- rebuilt, applied to the last argument's image.
0 rebuiltSnoc : (fc : FC) -> (g : ClosedTerm -> ClosedTerm) -> (h : ClosedTerm) -> (pre : List ClosedTerm) -> (a : ClosedTerm) ->
                foldl (App fc) h (map g (pre ++ [a])) = App fc (foldl (App fc) h (map g pre)) (g a)
rebuiltSnoc fc g h pre a = rewrite mapAppend g pre [a] in foldlAppend (App fc) h (map g pre) [g a]

mutual
  ||| The cut `Instances.neededShape` keeps (`cutShape`, with an erased
  ||| hole) is a cut of the shape (`Readings.NeededCut`): at no depth left,
  ||| the hole; else the spine's head, a data constructor rebuilt over its
  ||| arguments each cut one level shallower, or any other head, the hole.
  export
  0 cutShapeNeeded : (d : Nat) -> (tm : ClosedTerm) -> NeededCut tm (cutShape (Erased EmptyFC Impossible) d tm)
  cutShapeNeeded Z tm = NeedsNone
  cutShapeNeeded (S d) tm = cutSpineNeeded d (spineOf tm)

  0 cutSpineNeeded : (d : Nat) -> {0 tm : ClosedTerm} -> (sp : SpineOf tm) ->
                     NeededCut tm (cutSpine (Erased EmptyFC Impossible) d sp)
  cutSpineNeeded d (MkSpineOf (Ref fc (DataCon tag arity) n) args sp) = rebuiltNeeded d sp
  cutSpineNeeded d (MkSpineOf (Local _ _ _ _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (Ref _ Bound _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (Ref _ Func _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (Ref _ (TyCon _) _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (Meta _ _ _ _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (Bind _ _ _ _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (App _ _ _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (As _ _ _ _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (TDelayed _ _ _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (TDelay _ _ _ _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (TForce _ _ _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (PrimVal _ _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (Erased _ _) _ _) = NeedsNone
  cutSpineNeeded d (MkSpineOf (TType _ _) _ _) = NeedsNone

  -- A spine whose arguments are each cut, rebuilt over its head at one
  -- location: the last argument applied last, so the rebuilt term is the
  -- spine before it rebuilt, applied to its cut.
  0 rebuiltNeeded : (d : Nat) -> {0 fc : FC} -> {0 h : ClosedTerm} -> Spine t h args ->
                    NeededCut t (foldl (App fc) h (map (cutShape (Erased EmptyFC Impossible) d) args))
  rebuiltNeeded d Host.Head = NeedsWhole
  rebuiltNeeded d {fc} {h} (Host.Applied {a} {args = pre} sp) =
    rewrite rebuiltSnoc fc (cutShape (Erased EmptyFC Impossible) d) h pre a in
    NeedsBelow (rebuiltNeeded d sp) (cutShapeNeeded d a)

||| What a shape leaves unknown of a runtime value, where a type is asked
||| whether it needs it: a reference to a definition that does not exist,
||| at which reduction stops exactly where it would need the value. Idris's
||| quotation gives such a function back as it was, where it would take a
||| bound machine name for one of the binders it makes, by its number.
export
unknownPart : ClosedTerm
unknownPart = probeTerm ProbeUnknown

-- The marker itself (declared above): a bound name that no binder binds,
-- which a translation of the implementation replaces with the value
-- (`Terms.term`, by `refToLocal`, which takes bound names).
holeMarker i = probeTerm (ProbeHole i)

||| Replaces each marker of the values an implementation closes over with
||| the term for its value, by number.
export
fillHoles : List ClosedTerm -> ClosedTerm -> ClosedTerm
fillHoles values tm = foldl fill tm (zip [0 .. length values] values)
  where
    fill : ClosedTerm -> (Nat, ClosedTerm) -> ClosedTerm
    fill t (i, v) = substName (markerName i) v t

||| A reference to a definition, as Idris writes one: with its kind.
export
refTo : FC -> Name -> Front ClosedTerm
refTo fc n = do
  Just d <- defined n
    | Nothing => throw (InternalError ("no definition of " ++ show n))
  pure (Ref fc (kind (definition d.def)) (fullname d.def))
  where
    kind : Def -> NameType
    kind (DCon tag arity _) = DataCon tag arity
    kind (TCon arity _ _ _ _ _ _) = TyCon arity
    kind _ = Func

||| The pair Idris's `%pair` names: its type, its projections.
export
pairNames : Front (Name, Name, Name)
pairNames = do
  fz <- frozenContext
  let Just ns = pairnames (options (defsOf fz))
    | Nothing => throw (InternalError "no pair type")
  pure (pairType ns, fstName ns, sndName ns)

||| The type of the one value that holds the values an implementation closes
||| over: the one type, or a pair of the first and the rest.
export
packedType : List1 ClosedTerm -> Front ClosedTerm
packedType (t ::: ts) = packed t ts
  where
    packed : ClosedTerm -> List ClosedTerm -> Front ClosedTerm
    packed t [] = pure t
    packed t (u :: us) = do
      (pair, _, _) <- pairNames
      p <- refTo EmptyFC pair
      pure (App EmptyFC (App EmptyFC p t) !(packed u us))

||| The values the one value holds (`packedType`), as projections of it.
export
unpacked : List1 ClosedTerm -> ClosedTerm -> Front (List ClosedTerm)
unpacked (t ::: ts) v = projections t ts v
  where
    projections : ClosedTerm -> List ClosedTerm -> ClosedTerm -> Front (List ClosedTerm)
    projections _ [] v = pure [v]
    projections t (u :: us) v = do
      (_, first, second) <- pairNames
      f <- refTo EmptyFC first
      s <- refTo EmptyFC second
      rest <- packedType (u ::: us)
      let proj = \p => App EmptyFC (App EmptyFC (App EmptyFC p t) rest) v
      (proj f ::) <$> projections u us (proj s)

||| Does a term mention `holeMarker`?
export
mentionsHole : TT vars -> Bool
mentionsHole = mentions hole
  where
    hole : TT vs -> Bool
    hole (Ref _ _ n) = isJust (markerOf n)
    hole _ = False

||| Does a term mention `unknownPart`?
export
mentionsUnknown : TT vars -> Bool
mentionsUnknown = mentions unknownRef
  where
    unknownRef : TT vs -> Bool
    unknownRef (Ref _ _ n) = case probeOf n of
      Just ProbeUnknown => True
      _ => False
    unknownRef _ = False

||| A type-level parameter: its type is a universe, possibly after Pi binders.
export
isTypeLike : TT vars -> Bool
isTypeLike (TType _ _) = True
isTypeLike (Bind _ _ (Pi _ _ _ _) sc) = typeLikeScope sc
  where
    typeLikeScope : TT vs -> Bool
    typeLikeScope (TType _ _) = True
    typeLikeScope (Bind _ _ (Pi _ _ _ _) s) = typeLikeScope s
    typeLikeScope _ = False
isTypeLike _ = False

||| The definition a name names, as it was read (`Errors.defined`): a name
||| no definition has is a module compiled without it, and refused.
export
lookupDef : {auto s : Ref TState TS} -> FC -> String -> Name -> Front Defined
lookupDef fc owner n = do
  Just d <- defined n
    | Nothing => reject fc owner CompiledModule ("missing definition " ++ show n)
  pure d

||| Does a definition compute a type: is its type, normalised, a universe
||| after its arguments? Normalised, since a type may be written with a
||| name for one: `VarSet : Scoped` is `Scope -> Type`.
export
computesType : Defined -> Front Bool
computesType d = isTypeLike <$> normaliseClosed d.type

||| A closed term as a reading of the growth check takes it: the host's
||| normal form of it (`normaliseClosed`'s) in the frozen context the
||| reading reads, eta-contracted as the reading contracts (`Contracting`:
||| every redex for an instance, all but those around calls for a site's
||| type), so that a family is read as itself whatever stands for it; with
||| the host's steps and the contraction it was read by
||| (`Proof.Reading.NormalReading`), and the contraction's evidence that it
||| left no redex it contracts, all at quantity 0, which is what the growth
||| proof covers. The reading passes its context, so every normal form it
||| states is over that one context.
export
readNormal : (how : Contracting) -> (ctx : Frozen) -> (t : ClosedTerm) -> Front (MaximalReading how ctx t)
readNormal how ctx t = do
  r <- core (host.normaliseTypes ctx t)
  let c = contractedBy how r.value
  pure (MkMaximalReading (MkNormalReading c.etaForm r c.etaSteps) c.etaNormal)

||| A type argument as data instances compare them: up to eta, and with
||| a type-level function and the lambda of its one clause as one
||| argument. Elaboration writes a family as `f` in one type and as `\x =>
||| f x` in another, at any depth (`(c ** as ** Positive g c as)` holds
||| `\as => Positive g c as` under the lambda over `c`), so the argument
||| is contracted (`contracted`) before anything else reads it: the
||| contracted form is the one each of them has without knowing a
||| family's arity, which expanding would need, and it is taken before
||| the indices are erased (`Types.eraseIndices`), which would leave
||| `\as => Positive _ _ _`, no longer a redex. A lambda's domain is no
||| part of the comparison (`Keys.write`). Elaboration also leaves a
||| type-level function's name in one type and its clause in another
||| (`Printed`, and `\n => (Fin n -> Nat) -> Nat -> String`), including
||| where the name is an argument of another type (`List (AltF Printed
||| _)`): the clause is inlined where the name stands, when that clause is
||| a function type, and is contracted too. An applied name is left to
||| normalisation, and so is an alias of a data type: normalisation has
||| already made those one type.
export
canonicalTypeArg : ClosedTerm -> Front ClosedTerm
canonicalTypeArg tm = (\t => (contracted t).etaForm) <$> walk False (contracted tm).etaForm
  where
    -- Reduced to a name, rather than staying a lambda over its clause.
    etaContracted : TT vars -> Bool
    etaContracted (Bind _ _ (Lam {}) sc) = etaContracted sc
    etaContracted (Ref _ Func _) = True
    etaContracted _ = False

    -- A function type, under the lambdas of the clause. `Printed n` is
    -- `(Fin n -> Nat) -> Nat -> String`. An alias of a data type
    -- (`Scopeable a = List a`) is already that data type once normalised.
    hasPi : TT vars -> Bool
    hasPi (Bind _ _ (Pi {}) _) = True
    hasPi (Bind _ _ (Lam {}) sc) = hasPi sc
    hasPi (App _ f a) = hasPi f || hasPi a
    hasPi _ = False

    normaliseClause : {vs : _} -> FC -> TT vs -> Front (Maybe ClosedTerm)
    normaliseClause fc body = do
      let written = wrapLams fc body
      -- A name with no argument (`Scope = List Name`) is already reduced
      -- by ordinary normalisation wherever it is applied. Inlining it
      -- here turns a parameter into a value at one site only.
      case written of
        Bind _ _ (Lam {}) _ => do
          nf <- normaliseClosed written
          -- Quoting can put the name back; the clause is kept as written.
          let chosen = if etaContracted nf then written else nf
          pure (if hasPi chosen then Just chosen else Nothing)
        _ => pure Nothing

    -- The lambda of a type-level function's one clause, or nothing when
    -- the name is not such a function.
    clause : FC -> Name -> Front (Maybe ClosedTerm)
    clause fc n = do
      Just d <- defined n
        | Nothing => pure Nothing
      -- The type as written is enough for `Nat -> Type`. A name for one
      -- (`VarSet : Scoped`) needs the normalised type, and that lookup is
      -- the uncommon case.
      yes <- if isTypeLike d.type then pure True else computesType d
      if yes then case d.matched of
             Just m => case m.onlyClause of
               Just (_ ** rhs) => normaliseClause fc rhs
               Nothing => case leafOf m of
                 Just rhs => normaliseClause fc rhs
                 Nothing => pure Nothing
             Nothing => pure Nothing
        else pure Nothing

    -- `head` is the function of an application: that name is left to
    -- normalisation, and only its arguments are inlined. Replacing an
    -- applied name with its clause and not reducing the application is
    -- a different type than the reduced one. The clause inlined is not
    -- walked: it is already the form elaboration uses, and walking it
    -- would inline the names it mentions into types that were left as
    -- names, so that a call would no longer match its function.
    walk : Bool -> TT vars -> Front (TT vars)
    walk head (Ref fc Func n) =
      if head then pure (Ref fc Func n) else do
        Nothing <- clause fc n
          | Just lam => pure (embedClosed lam)
        pure (Ref fc Func n)
    walk _ (App fc f a) = App fc <$> walk True f <*> walk False a
    walk _ (Meta fc n i args) = Meta fc n i <$> each args
      where
        each : List (TT vars) -> Front (List (TT vars))
        each [] = pure []
        each (t :: ts) = (::) <$> walk False t <*> each ts
    walk _ (TDelayed fc r t) = TDelayed fc r <$> walk False t
    walk _ (TDelay fc r ty a) = TDelay fc r <$> walk False ty <*> walk False a
    walk _ (TForce fc r t) = TForce fc r <$> walk False t
    walk _ (As fc s p q) = As fc s <$> walk False p <*> walk False q
    walk _ tm = pure tm

------------------------------------------------------------------------------
-- Computations on runtime values, cut
------------------------------------------------------------------------------

||| A runtime variable in a term closed for normalisation: a reference to a
||| definition that does not exist, which no reduction looks into.
runtimeVariable : ClosedTerm
runtimeVariable = probeTerm ProbeRuntime

isRuntimeVariable : TT vs -> Bool
isRuntimeVariable (Ref _ _ n) = case probeOf n of
  Just ProbeRuntime => True
  _ => False
isRuntimeVariable _ = False

||| An argument a lambda applied to it binds, in the scope of the cut term:
||| as written, whether it mentions a runtime variable, and as cut where it
||| is written.
record Arg (ws : Scope) where
  constructor MkArg
  written : TT ws
  runtime : Bool
  cutForm : Lazy (Front (TT ws))

weakenArg : Arg ws -> Arg (x :: ws)
weakenArg a = MkArg (weaken a.written) a.runtime (weaken <$> a.cutForm)

||| What each variable of a term being cut (`vs`) stands for in the cut
||| term (`ws`): a variable of a binder the cut keeps, or of the scope it
||| started in; or the argument a lambda applied to it binds.
data CutEnv : Scope -> Scope -> Type where
  ||| A closed term's, in any scope.
  Closed : CutEnv [] ws
  ||| Every variable stands for itself.
  Same : CutEnv vs vs
  ||| A binder kept.
  Keep : CutEnv vs ws -> CutEnv (x :: vs) (x :: ws)
  ||| A lambda applied, its variable bound to the argument.
  Apply : Arg ws -> CutEnv vs ws -> CutEnv (x :: vs) ws

||| A binder kept: where every variable stands for itself, it does too.
keep : CutEnv vs ws -> CutEnv (x :: vs) (x :: ws)
keep Same = Same
keep env = Keep env

||| What a variable stands for in the cut term.
data Bound : Scope -> Type where
  AVar : TT ws -> Bound ws
  AnArg : Arg ws -> Bound ws

weakenBound : Bound ws -> Bound (x :: ws)
weakenBound (AVar t) = AVar (weaken t)
weakenBound (AnArg a) = AnArg (weakenArg a)

boundAt : CutEnv vs ws -> FC -> (idx : Nat) -> (0 _ : IsVar n idx vs) -> Bound ws
boundAt Same fc idx v = AVar (Local fc Nothing idx v)
boundAt Closed _ _ First impossible
boundAt Closed _ _ (Later _) impossible
boundAt (Keep env) fc Z _ = AVar (Local fc Nothing Z First)
boundAt (Keep env) fc (S i) v = weakenBound (boundAt env fc i (dropLater v))
boundAt (Apply a env) fc Z _ = AnArg a
boundAt (Apply a env) fc (S i) v = boundAt env fc i (dropLater v)

mutual
  ||| A term in the scope of the cut term, as written.
  rename : CutEnv vs ws -> TT vs -> TT ws
  rename Same tm = tm
  rename Closed tm = embed tm
  rename env (Local fc _ idx v) = case boundAt env fc idx v of
    AVar t => t
    AnArg a => a.written
  rename env (Ref fc nt n) = Ref fc nt n
  rename env (Meta fc n i args) = Meta fc n i (renameAll env args)
  rename env (Bind fc x b sc) = Bind fc x (renameBinder env b) (rename (keep env) sc)
  rename env (App fc f a) = App fc (rename env f) (rename env a)
  rename env (As fc s a p) = As fc s (rename env a) (rename env p)
  rename env (TDelayed fc r t) = TDelayed fc r (rename env t)
  rename env (TDelay fc r t a) = TDelay fc r (rename env t) (rename env a)
  rename env (TForce fc r t) = TForce fc r (rename env t)
  rename env (PrimVal fc c) = PrimVal fc c
  rename env (Erased fc Placeholder) = Erased fc Placeholder
  rename env (Erased fc Impossible) = Erased fc Impossible
  rename env (Erased fc (Dotted t)) = Erased fc (Dotted (rename env t))
  rename env (TType fc u) = TType fc u

  renameAll : CutEnv vs ws -> List (TT vs) -> List (TT ws)
  renameAll env [] = []
  renameAll env (t :: ts) = rename env t :: renameAll env ts

  renamePi : CutEnv vs ws -> PiInfo (TT vs) -> PiInfo (TT ws)
  renamePi env Implicit = Implicit
  renamePi env Explicit = Explicit
  renamePi env AutoImplicit = AutoImplicit
  renamePi env (DefImplicit t) = DefImplicit (rename env t)

  renameBinder : CutEnv vs ws -> TTBinder (TT vs) -> TTBinder (TT ws)
  renameBinder env (Lam fc r i ty) = Lam fc r (renamePi env i) (rename env ty)
  renameBinder env (Let fc r v ty) = Let fc r (rename env v) (rename env ty)
  renameBinder env (Pi fc r i ty) = Pi fc r (renamePi env i) (rename env ty)
  renameBinder env (PVar fc r i ty) = PVar fc r (renamePi env i) (rename env ty)
  renameBinder env (PLet fc r v ty) = PLet fc r (rename env v) (rename env ty)
  renameBinder env (PVTy fc r ty) = PVTy fc r (rename env ty)

mutual
  ||| Does a term mention a runtime variable, itself or through an argument
  ||| a lambda binds?
  dependsOn : CutEnv vs ws -> TT vs -> Bool
  dependsOn Same tm = mentions isRuntimeVariable tm
  dependsOn env (Local fc _ idx v) = case boundAt env fc idx v of
    AVar _ => False
    AnArg a => a.runtime
  dependsOn env tm@(Ref _ _ _) = isRuntimeVariable tm
  dependsOn env (Meta _ _ _ args) = dependsOnAny env args
  dependsOn env (Bind _ _ b sc) = binderDependsOn env b || dependsOn (keep env) sc
  dependsOn env (App _ f a) = dependsOn env f || dependsOn env a
  dependsOn env (As _ _ _ p) = dependsOn env p
  dependsOn env (TDelayed _ _ t) = dependsOn env t
  dependsOn env (TDelay _ _ t a) = dependsOn env t || dependsOn env a
  dependsOn env (TForce _ _ t) = dependsOn env t
  dependsOn env _ = False

  dependsOnAny : CutEnv vs ws -> List (TT vs) -> Bool
  dependsOnAny env [] = False
  dependsOnAny env (t :: ts) = dependsOn env t || dependsOnAny env ts

  binderDependsOn : CutEnv vs ws -> TTBinder (TT vs) -> Bool
  binderDependsOn env (Lam _ _ _ ty) = dependsOn env ty
  binderDependsOn env (Let _ _ v ty) = dependsOn env ty || dependsOn env v
  binderDependsOn env (Pi _ _ _ ty) = dependsOn env ty
  binderDependsOn env (PVar _ _ _ ty) = dependsOn env ty
  binderDependsOn env (PLet _ _ v ty) = dependsOn env ty || dependsOn env v
  binderDependsOn env (PVTy _ _ ty) = dependsOn env ty

||| A function that does not match on its arguments: its parameters, the
||| first first, its body, and its placement in the context.
plain : Name -> Front (Maybe (vs ** (TT vs, Placement)))
plain n = do
  Just d <- defined n
    | Nothing => pure Nothing
  pure (case oneLeaf d of
          Just (pargs ** rhs) => Just (pargs ** (rhs, d.placement))
          Nothing => Nothing)

||| Does a definition compute a type?
typeFunction : Name -> Front Bool
typeFunction n = do
  Just d <- defined n
    | Nothing => pure False
  computesType d

||| Whether a term with this head is cut by cutting its arguments, keeping
||| the head, so that it is cut applied to more arguments as its cut
||| applied to theirs: a constructor, a type constructor, a function that
||| computes a type.
keepsHead : TT ws -> Front Bool
keepsHead (Ref _ (DataCon _ _) _) = pure True
keepsHead (Ref _ (TyCon _) _) = pure True
keepsHead (Ref _ Func n) = typeFunction n
keepsHead _ = pure False

||| The parameters of a plain function, bound to the arguments it is
||| applied to, cut where they are written, and the arguments past them.
boundParams : (w : Walked) -> (0 acc : SizeAccessible w) -> (vs : Scope) ->
              List (TT ws) -> Maybe (CutEnv vs ws, List (Arg ws))

mutual
  ||| A computation on a runtime variable in a term, cut (`cutRuntime`),
  ||| with what each of its variables stands for, on the path of plain
  ||| functions unfolded on the way to the term. It ends, lexicographically
  ||| in the functions not yet unfolded on the path and the term: an
  ||| unfolding puts a function on the path, and every other step goes to a
  ||| part of the term, an argument's cut suspended where it is written.
  cut : (w : Walked) -> (0 acc : SizeAccessible w) ->
        CutEnv vs ws -> TT vs -> Front (TT ws)
  cut w acc env tm = cutApplied w acc env tm []

  ||| A term applied to arguments, cut: as written, unless it or an
  ||| argument mentions a runtime variable.
  cutApplied : (w : Walked) -> (0 acc : SizeAccessible w) ->
               CutEnv vs ws -> TT vs -> List (Arg ws) -> Front (TT ws)
  cutApplied w acc env tm args =
    if dependsOn env tm || any (.runtime) args
       then spine w acc env tm args
       else pure (foldl (App EmptyFC) (rename env tm) (map (.written) args))

  argOf : (w : Walked) -> (0 acc : SizeAccessible w) ->
          CutEnv vs ws -> TT vs -> Arg ws
  argOf w acc env a = MkArg (rename env a) (dependsOn env a) (cut w acc env a)

  ||| The head of an application, with its arguments, cut. The
  ||| accessibility proof is erased, and every clause matches its one
  ||| constructor: no alternative is chosen by it.
  spine : (w : Walked) -> (0 acc : SizeAccessible w) ->
          CutEnv vs ws -> TT vs -> List (Arg ws) -> Front (TT ws)
  spine w acc@(Access _) env (App _ f a) args = spine w acc env f (argOf w acc env a :: args)
  spine w acc@(Access _) env (Bind _ _ (Lam {}) sc) (a :: args) = cutApplied w acc (Apply a env) sc args
  spine w acc@(Access _) env (Bind fc x b sc) [] = Bind fc x <$> binder w acc env b <*> cut w acc (keep env) sc
  spine w acc@(Access _) env (TDelayed fc r t) [] = TDelayed fc r <$> cut w acc env t
  spine w (Access _) env (Local fc _ idx v) [] = case boundAt env fc idx v of
    AVar t => pure t
    AnArg a => a.cutForm
  spine w (Access _) env (Local fc _ idx v) args@(_ :: _) = case boundAt env fc idx v of
    AVar _ => pure (Erased fc Placeholder)
    AnArg a => appliedArg a args
  spine w (Access _) env tm@(Ref fc (DataCon _ _) _) args = foldl (App fc) (rename env tm) <$> cutArgs args
  spine w (Access _) env tm@(Ref fc (TyCon _) _) args = foldl (App fc) (rename env tm) <$> cutArgs args
  spine w acc@(Access rec) env tm@(Ref fc Func n) args =
    if !(typeFunction n)
       then foldl (App fc) (rename env tm) <$> cutArgs args
       -- A function that does not match on its arguments runs nothing on
       -- the value (`(.)` in `(PiInfo . Term) vars`): it is unfolded, and
       -- what it calls is cut in turn.
       else do
         Just (pargs ** (body, placement)) <- plain n
           | Nothing => pure (Erased fc Placeholder)
         -- Entered already: met again on its own path.
         let Just (Element w' less) = enter placement w
           | Nothing => pure (Erased fc Placeholder)
         given <- cutArgs args
         let Just (env', rest) = boundParams w' (rec w' less) pargs given
           | Nothing => pure (Erased fc Placeholder)
         cutApplied w' (rec w' less) env' body rest
  spine w (Access _) env _ _ = pure (Erased EmptyFC Placeholder)

  ||| An argument a lambda or a plain function binds, applied in turn: the
  ||| argument's cut applied to theirs, when it keeps its head
  ||| (`keepsHead`); otherwise a computation through a value, and cut.
  appliedArg : Arg ws -> List (Arg ws) -> Front (TT ws)
  appliedArg a args = do
    True <- keepsHead (getFn a.written)
      | False => pure (Erased EmptyFC Placeholder)
    f <- a.cutForm
    foldl (App EmptyFC) f <$> cutArgs args

  cutArgs : List (Arg ws) -> Front (List (TT ws))
  cutArgs [] = pure []
  cutArgs (a :: as) = do
    t <- a.cutForm
    (t ::) <$> cutArgs as

  binder : (w : Walked) -> (0 acc : SizeAccessible w) ->
           CutEnv vs ws -> TTBinder (TT vs) -> Front (TTBinder (TT ws))
  binder w acc env (Lam fc r i ty) = Lam fc r (renamePi env i) <$> cut w acc env ty
  binder w acc env (Let fc r val ty) = Let fc r <$> cut w acc env val <*> cut w acc env ty
  binder w acc env (Pi fc r i ty) = Pi fc r (renamePi env i) <$> cut w acc env ty
  binder w acc env (PVar fc r i ty) = PVar fc r (renamePi env i) <$> cut w acc env ty
  binder w acc env (PLet fc r val ty) = PLet fc r <$> cut w acc env val <*> cut w acc env ty
  binder w acc env (PVTy fc r ty) = PVTy fc r <$> cut w acc env ty

-- Each parameter is the argument as cut, which the body cuts again where
-- it stands, on the path that has unfolded the function.
boundParams w acc [] given = Just (Closed, map (\t => MkArg t (mentions isRuntimeVariable t) (cut w acc Same t)) given)
boundParams w acc (_ :: vs) (t :: given) =
  map (\(env, rest) => (Apply (MkArg t (mentions isRuntimeVariable t) (cut w acc Same t)) env, rest))
      (boundParams w acc vs given)
boundParams w acc (_ :: _) [] = Nothing

||| A type in which no computation is run on a runtime variable: what is
||| known of one is its constructors, as written, so a constructor or a type
||| constructor applied to one stays, and any other call to one, a
||| computation of a value, is unknown (`Erased`), as a runtime argument's
||| shape is read (`skeleton`). A computation on a value nothing is known of
||| can only be stuck, or never end: a parser's, built of closures that call
||| one another, unfolds without end once normalised under them. A function
||| that does not match on its arguments runs nothing on the value
||| (`(PiInfo . Term) vars`): it is unfolded, and what it calls is cut in
||| turn, except a function already unfolded on the way to it, whose
||| unfolding again would be a recursion that matches on nothing: that is
||| cut, so that the functions left to unfold are fewer at each unfolding.
||| The arguments are cut where they are written, before they are
||| substituted, so a function they apply is not counted as the unfolded
||| one's own. A function whose result is a type (`IsNothing m = m =
||| Nothing`) is no such computation: the type it gives is needed whatever
||| the value, and is cut inside instead. Nor is a lambda applied to one, a
||| type family at a value (`(\m => Vect m Int) n`), which binds its
||| variable to the value. A variable bound so that is applied in turn is
||| cut as what it is bound to is: a constructor's, a type's or a type
||| function's applied to more arguments, as those; a lambda's or a
||| function's that does not match, a computation through a value. A value
||| whose constructors are known (`Shaped`) is no runtime variable, and a
||| type still reduces on it.
cutRuntime : TT vars -> Front (TT vars)
cutRuntime tm = cut start (sizeAccessible start) Same tm

||| The closed normal form of a term in scope, with type variables replaced by
||| their known values and every runtime variable by `Erased`, once every
||| computation on one is cut (`cutRuntime`). A solved metavariable is
||| filled in first: it stands applied to every variable in scope where it
||| was made, runtime ones too, which its solution need not use. A
||| definition that computes a type unfolds whatever its visibility
||| (`normaliseTypes`): Idris's plain `normalise` keeps a `private` function
||| of another module as it is (a type-level function such as
||| Data.SortedMap's `delType`), which is a module boundary, not a value.
||| Any other unfolds as Idris's own normalisation unfolds it: a value whose
||| definition its module keeps to itself stays as it is (a parser's, whose
||| closures, normalised, would unfold without end).
export
closeNormalise : {vars : Scope} ->
                 FC -> StandsFor kc sp vars a -> TT vars -> Front ClosedTerm
closeNormalise fc env tm = do
  closed <- solved (betaAll (wrapLams fc tm) (reverse (innermostFirst (map value env))))
  normaliseClosed !(cutRuntime closed)
  where
    value : VarInfo kc spc a -> ClosedTerm
    value (TypeValue t) = t
    value (Static d _ _) = d.form
    value (Part t _ _ _) = t
    value (BoundHere t _) = t
    value (Shaped _ _ _ s) = s
    value (Runtime {}) = runtimeVariable
