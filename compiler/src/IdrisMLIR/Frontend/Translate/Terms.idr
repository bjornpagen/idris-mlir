-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Terms: a TT term in scope, with an environment saying what each of its
||| variables stands for, as a Core term. A call requests the instance it
||| calls, or, for a method of an implementation the call fixes, calls the
||| implementation's method in place. Nothing of quantity 0 becomes Core: an
||| argument at an erased position is not translated, and an erased binder
||| binds a compile-time value.
module IdrisMLIR.Frontend.Translate.Terms

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Name.Scoped
import Core.TT
import Libraries.Data.List.SizeOf
import Libraries.Data.List.Thin

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Choices
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.Primitives
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Spec.Ops.Bigs
import IdrisMLIR.Spec.Ops.Values
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List1
import Data.SortedMap
import Data.Vect
import Decidable.Equality

%default total

||| What a function's translation reads beside each term: who owns it, for
||| a message; where it is; whether Idris found no missing case; and the
||| type every leaf of its tree gives (`result`), its expected type, which
||| a lambda there that a polymorphic function's choice holds needs, its
||| own binders not saying it (`atType`).
public export
record Ctx where
  constructor MkCtx
  owner : String
  fc : FC
  complete : Bool     -- Idris found no missing case
  result : ClosedTerm

bestFC : Ctx -> FC -> FC
bestFC ctx fc = if isEmptyFC fc then ctx.fc else fc

||| The name of an Idris binder as Core keeps it, to name the value it
||| binds: a machine name (`{arg:12}`) by what it is, not by its counter.
export
binderName : Name -> Shown
binderName (NS _ n) = binderName n
binderName (MN s _) = shown s.text
binderName n = shown (show n)

||| The number of arguments a type takes, as its binders say.
binders : TT vars -> Nat
binders (Bind _ _ (Pi {}) sc) = S (binders sc)
binders _ = Z

||| The axes of a rank, outermost first.
axesOf : Nat -> List Nat
axesOf = go 0
  where
    go : Nat -> Nat -> List Nat
    go i Z = []
    go i (S k) = i :: go (S i) k

||| Is a dimension one the value carries rather than its type?
dynamicDim : Dim -> Bool
dynamicDim Dynamic = True
dynamicDim (Static _) = False

||| The rank a type gives the tensor that holds it.
rank : Ty -> Nat
rank t = length (tensorDims t)

||| A snoc list of naturals (`Extents`, `Index`) as its declaration has
||| it: the empty constructor, and the snoc of the rest and the natural.
record Snocs where
  constructor MkSnocs
  lin : Con 0
  snoc : Con 2

||| A snoc list of naturals built from its constructors, outermost first:
||| an `Extents` or an `Index` value.
snocValue : {0 m : Nat} -> Loc -> Snocs -> List (Term m) -> Term m
snocValue loc s ns = foldl (\acc, n => ConApp loc s.snoc [] [acc, n]) (ConApp loc s.lin [] []) ns

||| A snoc list of naturals (extents or coordinates) taken apart into its
||| last `r` naturals, outermost first, by its snoc; the body is built over
||| them, with the renaming of the scope outside. A value of rank `r` holds
||| `r` snocs, as its type's index says, so the empty list is no possible
||| arm of a match.
apart : {0 m : Nat} -> Loc -> Snocs -> Nat -> Fin m ->
        ({0 p : Nat} -> (Fin m -> Fin p) -> List (Fin p) -> Term p) -> Term m
apart loc s r x k = go r x (\ren, ns => k ren (ns <>> []))
  where
    -- The naturals taken apart so far, the outermost first, as the snocs
    -- inside give them.
    go : {0 m' : Nat} -> Nat -> Fin m' ->
         ({0 p : Nat} -> (Fin m' -> Fin p) -> SnocList (Fin p) -> Term p) -> Term m'
    go Z x k' = k' id [<]
    go (S r') x k' =
      Case loc x (Exhaustive (MkAlt s.snoc [shown "rest", shown "n"]
                                (go r' (Bound {k = 2} FZ)
                                    (\ren, ns => k' (ren . Free {k = 2}) (ns :< ren (Bound {k = 2} (FS FZ)))))
                              ::: []))

||| A linear array's cell taken apart, by its one constructor, into the
||| array it holds; the body is built over the array, with the renaming of
||| the scope outside. Every operation of a linear array runs on that
||| array and builds the cell again, so the cell is rebuilt in place by
||| the rule that rebuilds every cell of a type whose values are.
opened : {0 m : Nat} -> Loc -> Con 1 -> Fin m -> ({0 p : Nat} -> (Fin m -> Fin p) -> Fin p -> Term p) -> Term m
opened loc writing x k =
  Case loc x (Exhaustive (MkAlt writing [shown "elements"] (k (Free {k = 1}) (Bound {k = 1} FZ)) ::: []))

||| The binder of a closure's parameter: one closure type serves every
||| extent its values are made at, so every tensor dimension in it is
||| dynamic, as the closure's own type has it (`coreType`).
closureBinder : Binder -> Binder
closureBinder b = { type $= dynamicDims } b

||| A call's value made from its runtime arguments, as many as it has
||| parameters that exist at runtime.
record Maker (r : Nat) where
  constructor MkMaker
  make : {0 m : Nat} -> Vect r (Term m) -> Term m

||| A value made from its runtime arguments in order, whatever their number.
listed : ({0 m : Nat} -> List (Term m) -> Term m) -> Maker r
listed f = MkMaker (\ys => f (toList ys))

||| A maker over a count shown equal to its own.
recount : (0 _ : a = b) -> Maker b -> Maker a
recount Refl mk = mk

||| Each term bound by a `let` at the quantity of the parameter it is given
||| for, left to right, and the body built over the variables that hold
||| them, as many and in the same order, with the renaming of the scope
||| outside. A value used more than once, or in an order of its own, is
||| evaluated once, where the call put it; one Idris lets the callee use
||| once stays used once.
bindEach : {0 m : Nat} -> Loc -> Vect r Binder -> Vect r (Term m) ->
           ({0 p : Nat} -> (Fin m -> Fin p) -> Vect r (Fin p) -> Term p) -> Term m
bindEach loc bs ts k = go id bs ts k
  where
    -- Under the binders already made: `ren` takes the outer scope into the
    -- current one, and each term is renamed once, where it is bound.
    go : {0 p : Nat} -> (Fin m -> Fin p) -> Vect s Binder -> Vect s (Term m) ->
         ({0 q : Nat} -> (Fin p -> Fin q) -> Vect s (Fin q) -> Term q) -> Term p
    go ren [] [] k' = k' id []
    go ren (b :: bs') (t :: ts') k' =
      Let loc (shown "argument") (OfValue b.quantity) (rename ren t)
          (go (FS . ren) bs' ts' (\ren', vs => k' (ren' . FS) (ren' FZ :: vs)))

||| Eta-expands a known head applied to too few arguments over its missing
||| runtime parameters, one closure each, as the curried type of the
||| result requires: `\x => .. => head(args ++ xs)`.
etaExpand : {0 nv : Nat} -> {0 g : Nat} -> Loc -> Vect k Binder -> Maker (g + k) -> Vect g (Term nv) -> Term nv
etaExpand loc [] mk given = (recount (sym (plusZeroRightNeutral g)) mk).make given
etaExpand loc {k = S k'} (b :: rest) mk given =
  Lam loc (shown "x") (closureBinder b)
      (etaExpand loc rest (recount (plusSuccRightSucc g k') mk)
                 (snoc (map (weakenUnder 1) given) (Var loc FZ)))

||| The compile-time value a parameter's kind gives, where a projection
||| reads its arguments: a type, an implementation, or nothing known.
compileTimeArg : PKind -> ClosedTerm
compileTimeArg (TypeParam t) = t
compileTimeArg (DictParam t _) = t
compileTimeArg (FormParam f) = f
compileTimeArg _ = Erased EmptyFC Placeholder

||| Is an argument a type or a compile-time value, which exists only where
||| what takes it erases it?
compileTime : List (VarInfo a) -> TT vars -> Bool
compileTime env (Local _ _ idx _) = case getAt idx env of
  Just (TypeValue _) => True
  _ => False
compileTime env (TType _ _) = True
compileTime env (Erased _ _) = True
compileTime env (Bind _ _ (Pi {}) _) = True
compileTime env (TDelayed _ _ _) = True
compileTime env (PrimVal _ (PrT _)) = True
compileTime env tm = case getFnArgs tm of
  (Ref _ (TyCon _) _, _) => True
  _ => False

||| The Idris type of a variable at the head of an application, through a
||| `Force` of a lazy one.
headType : List (VarInfo a) -> TT vars -> Maybe ClosedTerm
headType env (Local _ _ idx _) = case getAt idx env of
  Just (Runtime _ _ t) => t
  Just (Shaped _ _ t _) => Just t
  _ => Nothing
headType env (TForce _ _ e) = case headType env e of
  Just (TDelayed _ _ t) => Just t
  _ => Nothing
headType _ _ = Nothing

||| A head as a message names it: a variable by its name.
headName : {auto c : Ref Ctxt Defs} -> {vars : Scope} -> FC -> List (VarInfo a) -> TT vars -> Front String
headName fc env (Local _ _ idx p) = pure (show (nameAt {idx} p))
headName fc env tm = showTT (closeWritten fc env tm)

||| A type or an erased value where a value exists at runtime. Idris's
||| quantity check admits one only where the type of what takes it erases
||| it, which is where the translation leaves it out; here nothing does.
inRuntime : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            String -> FC -> List (VarInfo a) -> TT vars -> Front b
inRuntime owner fc env tm = do
  what <- showTT (closeWritten fc env tm)
  reject fc owner ValueType (what ++ " in a runtime position")

||| The scope of a closed function type at an argument: the argument's
||| closed normal form where the scope mentions it, nothing where it does
||| not.
instantiate : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
              FC -> List (VarInfo a) -> TT [x] -> TT vars -> Front ClosedTerm
instantiate fc env sc arg = case shrink sc (Drop Refl) of
  Just sc' => pure sc'
  Nothing => do
    value <- closeNormalise fc env arg
    pure (subst value sc)

||| The runtime values an implementation closes over, as `holed` finds them:
||| the variable that holds each, when one does, its type, and its
||| translation.
Found : Nat -> Type
Found nv = List (Maybe (Fin nv), ClosedTerm, Front (Term nv))

||| A value `holed` found, by the order it found them in, before the values
||| one variable holds are made one; and its marker, a name no normaliser
||| takes for a binder, as `markerName` is.
foundName : Nat -> Name
foundName i = probeName (ProbeHoleFound i)

foundMarker : Nat -> ClosedTerm
foundMarker i = Ref EmptyFC Bound (foundName i)

||| A term with the markers `0 .. count - 1` of one family moved up by
||| `by`, the highest first, so that no marker is moved twice.
shifted : (family : Nat -> Name) -> (by : Nat) -> (count : Nat) -> ClosedTerm -> ClosedTerm
shifted family by Z t = t
shifted family by (S k) t = shifted family by k (substName (family k) (Ref EmptyFC Bound (family (k + by))) t)

||| Where a term being translated comes from: written in the definition
||| (`Written`), which may still hold redexes, solved metavariables and
||| values the environment binds, and which may be settled once into the
||| phase it holds; or settled (`Settled`): a normal form of Idris's
||| evaluator, closed but for the variables bound around it. What a
||| settled term settles again (an implementation or a polymorphic
||| function applied in it, a value an implementation in it closes over)
||| stays settled, on a path that enters the definition at the head of
||| what it settles, as a metavariable's solution is entered.
export
data Phase = Settled | Written Phase

||| The phase of a term as a definition writes it.
export
asWritten : Phase
asWritten = Written Settled

||| An argument of an application, made where it is a subterm: as written,
||| its translation, and what it closes over as an implementation
||| (`holed`), each suspended there, so that no use translates a list
||| element.
record Arg (vars : Scope) (nv : Nat) where
  constructor MkArg
  written : TT vars
  translated : Lazy (Front (Term nv))
  held : Lazy (Front (Maybe (ClosedTerm, List1 (ClosedTerm, Front (Term nv)))))

||| An argument under a binder that binds nothing in Core: a compile-time
||| value, or another name for a variable.
overBinder : Arg vars nv -> Arg (x :: vars) nv
overBinder a = MkArg (weaken a.written) a.translated a.held

||| An argument under a binder that Core binds too, by a `let`.
underLet : Arg vars nv -> Arg (x :: vars) (S nv)
underLet a = MkArg (weaken a.written) (weakenUnder 1 <$> Force a.translated) (map weakened <$> Force a.held)
  where
    weakened : (ClosedTerm, List1 (ClosedTerm, Front (Term nv))) -> (ClosedTerm, List1 (ClosedTerm, Front (Term (S nv))))
    weakened (shape, values) = (shape, map (\(t, v) => (t, weakenUnder 1 <$> v)) values)

||| The place of the definition at the head of a compile-time form, under
||| the lambdas it starts with: an implementation's definition, the
||| definition or constructor a polymorphic function applies. A settled
||| term that settles the form again enters it on its path. Nothing for a
||| form whose head is a variable.
formHead : ClosedTerm -> Front (Maybe Placement)
formHead t = case headName t of
  Just n => map (.placement) <$> defined n
  Nothing => pure Nothing
  where
    headName : TT vs -> Maybe Name
    headName (Bind _ _ (Lam {}) sc) = headName sc
    headName tm = case getFn tm of
      Ref _ _ n => Just n
      _ => Nothing

||| The type of a compile-time form (`Static`), closed but for the markers
||| of the values it closes over, whose types `held` gives, by marker: each
||| lambda the form starts with a binder of a function type, around the
||| type of what its body applies (a definition, a constructor, a value the
||| form closes over, one of its own lambdas' variables) applied to the
||| body's arguments, its `let`s put in. Each lambda's variable stands in
||| what follows as the probe of a lambda's argument, and is bound again
||| around the result. Nothing for a body that applies nothing whose type
||| a binder or a definition gives.
formType : {auto c : Ref Ctxt Defs} -> List ClosedTerm -> ClosedTerm -> Front (Maybe ClosedTerm)
formType held t = lambdas 0 [] [] !(lambdasApplied t)
  where
    formal : Nat -> ClosedTerm
    formal k = probeTerm (ProbeFormal k 0)

    -- The type of what a body applies, given its arguments.
    applied : Maybe ClosedTerm -> List ClosedTerm -> Front (Maybe ClosedTerm)
    applied Nothing _ = pure Nothing
    applied (Just ty) [] = pure (Just ty)
    applied (Just ty) (a :: as) = do
      Bind _ _ (Pi {}) sc <- showingBinder ty
        | _ => pure Nothing
      applied (Just (subst a sc)) as

    -- The type of a closed body under the lambdas met, the outermost
    -- first.
    bodyType : List (Name, RigCount, PiInfo ClosedTerm, ClosedTerm) -> ClosedTerm -> Front (Maybe ClosedTerm)
    bodyType ls body = case getFnArgs body of
      (Ref _ Bound n, args) => case probeOf n of
        Just (ProbeFormal k _) => applied ((\(_, _, _, ty) => ty) <$> getAt k ls) args
        Just (ProbeHole k) => applied (getAt k held) args
        _ => pure Nothing
      (Ref _ _ n, args) => do
        Just d <- defined n
          | Nothing => pure Nothing
        applied (Just d.type) args
      _ => pure Nothing

    -- The lambdas, the outermost first, bound around a type as a function
    -- type's binders, each variable's probe made that binder's variable.
    bound : Nat -> List (Name, RigCount, PiInfo ClosedTerm, ClosedTerm) -> ClosedTerm -> ClosedTerm
    bound k [] r = r
    bound k ((x, rig, p, ty) :: ls) r =
      Bind EmptyFC x (Pi EmptyFC rig p ty) (refToLocal (probeName (ProbeFormal k 0)) x (bound (S k) ls r))

    -- Down the lambdas, each variable standing for its probe (`env`, the
    -- innermost first), then the body, closed with its `let`s put in.
    lambdas : {vs : Scope} -> Nat -> List (Name, RigCount, PiInfo ClosedTerm, ClosedTerm) ->
              List (VarInfo Nat) -> TT vs -> Front (Maybe ClosedTerm)
    lambdas k ls env (Bind _ x (Lam _ rig p ty) sc) =
      lambdas (S k) (ls ++ [(x, rig, map (closeWritten EmptyFC env) p, closeWritten EmptyFC env ty)])
              (TypeValue (formal k) :: env) sc
    lambdas k ls env body = map (bound 0 ls) <$> bodyType ls (closeWritten EmptyFC env body)

||| What a marker of a settled term stands for.
data Stand : Nat -> Type where
  ||| A variable in scope: the marker is bound as it is, with no `let`.
  AsVariable : VarInfo (Fin nv) -> Stand nv
  ||| A runtime value, bound once by a `let` before the term.
  AsValue : Lazy (Front (Term nv)) -> Stand nv

||| The values an implementation closes over, each translated.
valuesOf : {0 nv : Nat} -> List1 (ClosedTerm, Front (Term nv)) -> Front (List1 (ClosedTerm, Term nv))
valuesOf ((t, v) ::: rest) = (:::) <$> ((t,) <$> v) <*> later rest
  where
    later : List (ClosedTerm, Front (Term nv)) -> Front (List (ClosedTerm, Term nv))
    later [] = pure []
    later ((t', v') :: more) = (::) <$> ((t',) <$> v') <*> later more

||| What a call knows of an argument it gives (`Instances.ArgValue`), read
||| in its scope: what keys an instance names no level of the scope
||| (`unmarked`); what an index parameter is given keeps them (`scoped`).
argValueIn : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
             List (VarInfo (Fin nv)) -> FC -> Arg vars nv -> Maybe ArgValue
argValueIn env fc x = Just (MkArgValue (unmarked <$> closeNormalise fc env x.written)
                                       (unmarked <$> solved (closeWritten fc env x.written))
                                       (offered x.written)
                                       (map (\(shape, held) => (unmarked shape, map fst held)) <$> Force x.held)
                                       (closeNormalise fc env x.written))
  where
    offered : TT vars -> Offer
    offered (Local _ _ idx _) = case getAt idx env of
      Just (Static _ _) => AnImplementation
      _ => AValue
    offered _ = AValue

||| A compile-time form of type `t` applied where no definition of the
||| program applies it, as the member at this use's types it is (`AtUse`):
||| the instance that applies the form at the use's own types, keyed by the
||| form's type and the form (`form`, what the call knows of it), and each
||| argument as the form's type takes it. The use takes every argument the
||| application gives, all of which the type takes, as Idris checked the
||| application, so no instance takes more than the type does. The form's
||| value at run time (`value`) is a choice, which the call dispatches on,
||| each arm the member at the use's types (`Choices.calleeAt`), or the
||| values a fixed form closes over.
applyAtUse : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
             Ctx -> List (VarInfo (Fin nv)) -> FC -> Loc -> (t : ClosedTerm) -> (form : ArgValue) ->
             (value : Maybe (Term nv)) -> List (Arg vars nv) -> Front (Term nv)
applyAtUse ctx env fc loc t form value args = do
  ty <- applicationType
  let vals = Just (known t AValue) :: Just form :: map (argValueIn env fc) args
  (kinds, _) <- classifyCall fc ctx.owner (2 + length args) ty vals
  let (_ :: formKind :: useKinds) = kinds
    | _ => internal fc "a member at a use classified without its form"
  inst <- calleeAt (choicesIn kinds) fc ctx.owner (AtUse (length args)) kinds
  formGiven <- formValue (boundAtRuntime formKind)
  given <- uses useKinds args
  is <- callIndices kinds vals
  pure (Call loc inst Nothing is (formGiven ++ given))
  where
    -- The form's value, where its parameter exists at run time. A form
    -- bound as a compile-time value that its type reads as a run-time
    -- one (a field a definition Idris does not prove ends computes) has
    -- none here: inside a settled term nothing computes it again.
    formValue : Maybe Binder -> Front (List (Term nv))
    formValue Nothing = pure []
    formValue (Just _) = case value of
      Just v => pure [v]
      Nothing => reject fc ctx.owner RuntimeClosure
                        ("a function computed at run time, applied inside a settled term that settles it again: " ++
                         !(showTT !(form.written)))

    -- Each argument as its kind takes it: a value or a choice as itself,
    -- an implementation that closes over runtime values as the values,
    -- held as one, and a compile-time value as nothing.
    uses : List PKind -> List (Arg vars nv) -> Front (List (Term nv))
    uses (ValueParam {} :: ks) (x :: xs) = (::) <$> x.translated <*> uses ks xs
    uses (ChoiceParam {} :: ks) (x :: xs) = (::) <$> x.translated <*> uses ks xs
    uses (DictParam _ (Just _) :: ks) (x :: xs) = do
      Just (_, held) <- x.held
        | Nothing => internal fc "the values an implementation closes over are gone"
      v <- pack fc ctx.owner loc !(valuesOf held)
      (v ::) <$> uses ks xs
    uses (_ :: ks) (_ :: xs) = uses ks xs
    uses _ _ = pure []

||| A value applied to arguments, over the Idris type of the value where it
||| is known: an argument at a binder of quantity 0 is not passed, since
||| the value takes none there at runtime, and any other is applied. A
||| polymorphic function held at run time is a value of its type's choice,
||| whose members each use calls at its own types: applied here, where it
||| is held, it is a use of it, the member at the use's types
||| (`applyAtUse`). Past the binders the type shows, an argument is a
||| runtime value, and a type or an erased value there is refused, naming
||| the head (`what`).
applyOver : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            Ctx -> List (VarInfo (Fin nv)) -> FC -> Loc -> Front String ->
            Term nv -> Maybe ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
applyOver ctx env fc loc what f _ [] = pure f
applyOver ctx env fc loc what f fty (x :: xs) = do
  ty <- the (Front (Maybe ClosedTerm)) $ case fty of
          Just t@(Bind _ _ (Pi {}) _) => pure (Just t)
          Just t => Just <$> normaliseClosed t
          Nothing => pure Nothing
  case ty of
    Just t@(Bind _ _ (Pi _ rig _ _) sc) => do
      False <- polymorphicType t
        | True => applyAtUse ctx env fc loc t (known t AChoice) (Just f) (x :: xs)
      next <- instantiate fc env sc x.written
      case use rig of
        Erased => applyOver ctx env fc loc what f (Just next) xs
        Used _ => do
          v <- x.translated
          applyOver ctx env fc loc what (App loc f v) (Just next) xs
    _ => do
      when (compileTime env x.written) $ do
        arg <- showTT (closeWritten fc env x.written)
        reject fc ctx.owner ValueType
               (arg ++ " in a runtime position: an argument of " ++ !what ++ ", whose type is not known here")
      v <- x.translated
      applyOver ctx env fc loc what (App loc f v) Nothing xs

-- The translation ends, lexicographically in the phase, the definitions
-- and metavariables entered on the path, and the term. Every step goes to
-- a part of the term, with three exceptions: a metavariable's solution,
-- entered once on its path (`Walk`); a written term Idris's evaluator
-- settled, which is translated in the phase the written one held; and
-- what a settled term settles again, which enters the definition at its
-- head on the path, once, or, where it cannot, is an instance of its own
-- (`applyAtUse`), which the worklist translates on a path of its own. A
-- part of an application is made where it is a subterm (`argOf`), its
-- translation suspended there, so a use of it later is no step of the
-- translation that uses it.
mutual
  export
  term : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
         Ctx -> List (VarInfo (Fin nv)) -> TT vars -> Front (Term nv)
  term ph w acc ctx env (Local fc r idx p) = applyVariable ph w acc ctx env fc fc r idx p []
  term ph w acc ctx env tm@(PrimVal fc c) = do
    loc <- toLoc (bestFC ctx fc)
    case constantLit c of
      Just l => pure (Literal loc l)
      Nothing => case c of
        -- A trusted library forges a world (`unsafePerformIO`); the
        -- profile has rejected the user's (Profile.checkReachable).
        WorldVal => pure (NewWorld loc)
        PrT _ => inRuntime ctx.owner (bestFC ctx fc) env tm
        _ => reject (bestFC ctx fc) ctx.owner ValueType ("constant " ++ show c)
  term ph w acc ctx env tm@(TType fc _) = inRuntime ctx.owner (bestFC ctx fc) env tm
  term ph w acc ctx env tm@(Erased fc _) = inRuntime ctx.owner (bestFC ctx fc) env tm
  term ph w acc ctx env tm@(Bind fc _ (Pi {}) _) = inRuntime ctx.owner (bestFC ctx fc) env tm
  term ph w acc ctx env tm@(Bind fc x (Let lfc rig val ty) sc) = case delayedLets tm of
    -- The `let`s around a `Delay` the elaborator inserted for a `Lazy`
    -- expected type move into it (`delayedLets`), into the innermost of a
    -- chain of them: the suspensions, outermost first, then the `let`s,
    -- then what the last `Delay` delays. A `Delay` the source wrote keeps
    -- its `let`s outside, which eager evaluation runs first.
    Just _ => do
      (suspensions, inner) <- letIn ph w acc ctx env fc x rig val ty (\env' => delayed ph w acc ctx env' sc)
      pure (foldr Suspend inner suspensions)
    Nothing => (\((), t) => t) <$> letIn ph w acc ctx env fc x rig val ty (\env' => ((),) <$> term ph w acc ctx env' sc)

  -- A lambda's binder of quantity 0 is no parameter at runtime: the lambda
  -- is its body, which takes the runtime arguments after it, as its type
  -- does once the binder is left out. A lambda is a closure, whose type is
  -- one for every extent its values are made at (`coreType`), so its
  -- binder is too: an array parameter's extents are its argument's, each
  -- dynamic, whatever the type at this lambda fixes.
  term ph w acc ctx env (Bind fc x (Lam lfc rig _ ty) sc) =
    case use rig of
      Erased => term ph w acc ctx (TypeValue (Erased fc Placeholder) :: env) sc
      Used _ => do
        loc <- toLoc (bestFC ctx fc)
        known <- closeNormalise fc env ty
        b <- closureBinder <$> coreBinder (bestFC ctx fc) ctx.owner ValueType rig known
        body <- term ph w acc ctx (under {k = 1} [Runtime FZ (Just b.type) (Just known)] env) sc
        pure (Lam loc (binderName x) b body)
  term ph w acc ctx env (TDelay fc _ _ arg) = suspend ph w acc ctx env fc arg
  term ph w acc ctx env (TForce fc _ arg) = Resume <$> toLoc (bestFC ctx fc) <*> term ph w acc ctx env arg
  term ph w acc ctx env tm@(TDelayed fc _ _) = inRuntime ctx.owner (bestFC ctx fc) env tm
  term ph w acc ctx env (Meta fc n i margs) = entered ph w acc ctx env fc fc n i margs []
  term ph w acc ctx env (As fc _ _ pat) = term ph w acc ctx env pat
  term ph w acc ctx env (App fc f a) = spine ph w acc ctx env fc f [argOf ph w acc ctx env fc a]
  term ph w acc ctx env (Ref fc nt n) = applyRef {vars} ph w acc ctx env fc fc nt n []
  term ph w acc ctx env (Bind fc _ _ _) = internal (bestFC ctx fc) "a binder in a runtime position"

  ||| A chain of `let`s and `Delay`s, read as `delayedLets` moves the `let`s:
  ||| the location of each `Delay` met, outermost first, and the `let`s
  ||| around what the last one delays, each bound where it is met, so that
  ||| every part translated is a part of the chain.
  delayed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Ctx -> List (VarInfo (Fin nv)) -> TT vars -> Front (List Loc, Term nv)
  delayed ph w acc ctx env (TDelay dfc _ _ arg) = do
    loc <- toLoc (bestFC ctx dfc)
    (suspensions, inner) <- delayed ph w acc ctx env arg
    pure (loc :: suspensions, inner)
  delayed ph w acc ctx env (Bind fc x (Let lfc rig val ty) sc) =
    letIn ph w acc ctx env fc x rig val ty (\env' => delayed ph w acc ctx env' sc)
  delayed ph w acc ctx env tm = ([],) <$> term ph w acc ctx env tm

  ||| A `let`, its body translated by `body` in the scope it binds. A `let`
  ||| of quantity 0 binds a compile-time value, nothing at runtime. Its type
  ||| is the one Idris checked, which the TTC keeps: read once, here, into
  ||| its binder, at the quantity Idris gave it. A polymorphic function
  ||| (`polymorphicType`) the program fixes now (`fixing`) is a compile-time
  ||| value, as one passed as an argument is: its form, each use applying
  ||| it at the use's own types, with the runtime values it closes over
  ||| bound once, here, where eager evaluation computes them.
  letIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Ctx -> List (VarInfo (Fin nv)) -> FC -> Name -> RigCount -> TT vars -> TT vars ->
          ({0 m : Nat} -> List (VarInfo (Fin m)) -> Front (r, Term m)) -> Front (r, Term nv)
  letIn ph w acc ctx env fc x rig val ty body =
    case use rig of
      Erased => body (TypeValue (Erased fc Placeholder) :: env)
      Used q => do
        loc <- toLoc (bestFC ctx fc)
        known <- closeNormalise fc env ty
        True <- polymorphicType known
          | False => runtimeLet loc known
        impl <- solved (closeWritten fc env val)
        if not !(runtimeDependent impl)
          then do
            FixedNow <- fixing known impl
              | ChosenAtRunTime _ => runtimeLet loc known
            body (Static impl Nothing :: env)
          else do
            Just (shape, values) <- holed ph w acc ctx env fc val
              | Nothing => runtimeLet loc known
            FixedNow <- fixing known shape
              | ChosenAtRunTime _ => runtimeLet loc known
            held <- coreType fc ctx.owner ValueType !(normaliseClosed !(packedType (map fst values)))
            v <- pack fc ctx.owner loc !(valuesOf values)
            (r', inner) <- body (under {k = 1} [Static shape (Just (FZ, MkHoles (map fst values) (MkBinder Many held)))] env)
            pure (r', Let loc (binderName x) (Checked (MkBinder Many held)) v inner)
    where
      -- The value computed and bound by a `let`, a runtime value.
      runtimeLet : Loc -> ClosedTerm -> Front (r, Term nv)
      runtimeLet loc known = do
        b <- coreBinder (bestFC ctx fc) ctx.owner ValueType rig known
        v <- term ph w acc ctx env val
        (r', inner) <- body (under {k = 1} [Runtime FZ (Just b.type) (Just known)] env)
        pure (r', Let loc (binderName x) (Checked b) v inner)

  ||| A term at the type it is expected to have (`ty`), the type a
  ||| definition's leaf gives: a lambda there, where that type is a
  ||| polymorphic function's, is the member of the type's choice it is
  ||| (`member`), as one given at a parameter of the type is, its own
  ||| binders not saying the type; a `let` gives its body the type it
  ||| expects. Any other term is translated as it is.
  export
  atType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Ctx -> List (VarInfo (Fin nv)) -> (ty : ClosedTerm) -> TT vars -> Front (Term nv)
  atType ph w acc ctx env ty tm@(Bind fc _ (Lam {}) _) = do
    True <- choiceType ty
      | False => term ph w acc ctx env tm
    loc <- toLoc (bestFC ctx fc)
    Just m <- member ph w acc ctx env fc loc ty tm
      | Nothing => term ph w acc ctx env tm
    pure m
  atType ph w acc ctx env ty tm@(Bind fc x (Let lfc rig val vty) sc) = case delayedLets tm of
    Just _ => term ph w acc ctx env tm
    Nothing => snd <$> letIn ph w acc ctx env fc x rig val vty (\env' => ((),) <$> atType ph w acc ctx env' ty sc)
  atType ph w acc ctx env ty tm = term ph w acc ctx env tm

  suspend : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars -> Front (Term nv)
  suspend ph w acc ctx env fc arg = do
    loc <- toLoc (bestFC ctx fc)
    body <- term ph w acc ctx env arg
    pure (Suspend loc body)

  ||| An argument where it is a subterm of the application.
  argOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars -> Arg vars nv
  argOf ph w acc ctx env afc a = MkArg a (term ph w acc ctx env a) (holed ph w acc ctx env afc a)

  ||| An application's spine, its arguments collected where each is a
  ||| subterm, down to its head.
  spine : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars -> List (Arg vars nv) -> Front (Term nv)
  spine ph w acc ctx env afc (App _ f a) args = spine ph w acc ctx env afc f (argOf ph w acc ctx env afc a :: args)
  spine ph w acc ctx env afc (Ref rfc nt n) args = applyRef ph w acc ctx env afc rfc nt n args
  spine ph w acc ctx env afc tm args = applyHead ph w acc ctx env afc tm args

  ||| A head that is no definition, applied to its arguments: a variable; a
  ||| lambda, whose argument is bound in the environment and whose body
  ||| takes the rest, so that no term is substituted; a solved metavariable,
  ||| as its solution; an `As` pattern, as its pattern; anything else, as its
  ||| value applied.
  applyHead : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
              (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
              Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars -> List (Arg vars nv) -> Front (Term nv)
  applyHead ph w acc ctx env afc (Local fc r idx p) args = applyVariable ph w acc ctx env afc fc r idx p args
  -- The argument is bound as what it is: a compile-time value at an erased
  -- binder; another name for a variable; at a binder of an implementation
  -- or a polymorphic function (`compileTimeBinder`), its form, with the
  -- values it closes over bound once; anything else, a runtime value
  -- bound by a `let`, which the application evaluates first, where the
  -- `let` translation would move it into a `Delay` the body builds
  -- (`delayedLets`).
  applyHead ph w acc ctx env afc (Bind bfc x (Lam _ rig _ ty) sc) (a :: rest) =
    case use rig of
      Erased => spine ph w acc ctx (TypeValue (closeWritten bfc env a.written) :: env) afc sc (map overBinder rest)
      -- A variable given to a binder of quantity 1 stands for it, used at
      -- most once there as Idris proved; given to one of quantity many it
      -- is bound once, so a variable Idris lets be used once is never used
      -- twice.
      Used q => case (q, aliased a.written) of
        (Once, Just e) => spine ph w acc ctx (e :: env) afc sc (map overBinder rest)
        _ => do
          fixedHere <- compileTimeBinder rig ty
          loc <- toLoc (bestFC ctx bfc)
          if fixedHere then dictionary loc else asValue loc
    where
      -- The argument as a runtime value, bound by a `let`: a choice of an
      -- implementation among others (`Choices`).
      asValue : Loc -> Front (Term nv)
      asValue loc = do
        known <- closeNormalise bfc env ty
        b <- coreBinder (bestFC ctx bfc) ctx.owner ValueType rig known
        v <- a.translated
        body <- spine ph w acc ctx (under {k = 1} [Runtime FZ (Just b.type) (Just known)] env) afc sc (map underLet rest)
        pure (Let loc (binderName x) (Checked b) v body)

      aliased : TT vars -> Maybe (VarInfo (Fin nv))
      aliased (Local _ _ idx _) = getAt idx env
      aliased _ = Nothing

      -- One the program fixes now (`fixing`) is its form; one the running
      -- program chooses, or a definition Idris does not prove ends
      -- computes, is computed when the program runs: a choice, bound as a
      -- value.
      dictionary : Loc -> Front (Term nv)
      dictionary loc = do
        known <- closeNormalise bfc env ty
        impl <- solved (closeWritten bfc env a.written)
        if not !(runtimeDependent impl)
          then do
            FixedNow <- fixing known impl
              | ChosenAtRunTime _ => asValue loc
            spine ph w acc ctx (Static impl Nothing :: env) afc sc (map overBinder rest)
          else do
            Just (shape, values) <- a.held
              | Nothing => asValue loc
            FixedNow <- fixing known shape
              | ChosenAtRunTime _ => asValue loc
            held <- coreType bfc ctx.owner ValueType !(normaliseClosed !(packedType (map fst values)))
            v <- pack bfc ctx.owner loc !(valuesOf values)
            body <- spine ph w acc ctx
                          (under {k = 1} [Static shape (Just (FZ, MkHoles (map fst values) (MkBinder Many held)))] env)
                          afc sc (map underLet rest)
            pure (Let loc (binderName x) (Checked (MkBinder Many held)) v body)
  applyHead ph w acc ctx env afc (Meta mfc n i margs) args = entered ph w acc ctx env afc mfc n i margs args
  applyHead ph w acc ctx env afc (As _ _ _ pat) args = spine ph w acc ctx env afc pat args
  applyHead ph w acc ctx env afc tm args = do
    let fc = bestFC ctx afc
    loc <- toLoc fc
    f <- term ph w acc ctx env tm
    applyOver ctx env fc loc (headName fc env tm) f (headType env tm) args

  ||| A variable applied to its arguments: a runtime value, applied; an
  ||| implementation, as `implementationAt` uses one.
  applyVariable : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                  (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                  Ctx -> List (VarInfo (Fin nv)) -> (afc : FC) -> (fc : FC) -> Maybe Bool ->
                  (idx : Nat) -> (0 p : IsVar n idx vars) -> List (Arg vars nv) -> Front (Term nv)
  applyVariable ph w acc ctx env afc fc r idx p args = case getAt idx env of
    Just (Runtime x _ _) => applied x
    Just (Shaped x _ _ _) => applied x
    -- Idris's quantity check of a clause keeps a binder of quantity 0 out
    -- of every position that exists at runtime, a leaf reads each binder
    -- where its clause holds it at runtime (`Cases.heldAt`), and the
    -- translation leaves out every erased position.
    Just (TypeValue _) => internal (bestFC ctx fc) "a compile-time variable in a runtime position"
    Just (Static t held) => implementationAt ph w acc ctx env fc t held args
    Nothing => internal (bestFC ctx fc) "a variable out of scope"
    where
      applied : Fin nv -> Front (Term nv)
      applied x = do
        loc <- toLoc (bestFC ctx fc)
        let at = bestFC ctx afc
        aloc <- toLoc at
        let tm = Local fc r idx p
        applyOver ctx env at aloc (headName at env tm) (Var loc x) (headType env tm) args

  ||| An implementation or a polymorphic function the environment binds,
  ||| used at runtime: as written, applied to its arguments, it is settled
  ||| by Idris's evaluator and its normal form translated, each use at its
  ||| own types. One that closes over runtime values stands for them by the
  ||| projections of the variable that holds them, marker 0. Applied in a
  ||| settled term (a part of another implementation closes over it, or a
  ||| `let` there binds it), its normal form stays settled, on a path that
  ||| enters the definition at its head (`formHead`). One whose head is a
  ||| variable (a value it closes over, one of its own lambdas'), which no
  ||| path enters, and one whose definition the path has entered already,
  ||| which would be settled inside its own settled form, are the member at
  ||| this use's types (`applyAtUse`), an instance the worklist translates
  ||| on a path of its own and bounds by the growth check: so the
  ||| translation still ends, and a value at the head is applied as its
  ||| type's choice is, dispatched on.
  implementationAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                     Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                     Ctx -> List (VarInfo (Fin nv)) -> FC -> ClosedTerm -> Maybe (Fin nv, Holes) ->
                     List (Arg vars nv) -> Front (Term nv)
  implementationAt ph@Settled w acc@(Access rec) ctx env fc t held args = do
    place <- formHead t
    case place >>= (\p => enter p w) of
      Just (Element w' less) => do
        (form, pre) <- standingFor t held
        settle ph w' (rec w' less) ctx env fc form pre args
      Nothing => do
        let at = bestFC ctx fc
        loc <- toLoc at
        Just ty <- formType (maybe [] (\(_, hs) => forget hs.types) held) t
          | Nothing => reject at ctx.owner RuntimeClosure
                              ("a form whose type its body does not give, applied inside a settled term: " ++
                               !(showTT t))
        let form = MkArgValue (pure t) (pure t) AnImplementation
                              (pure ((\(_, hs) => (t, hs.types)) <$> held)) (pure t)
        applyAtUse ctx env at loc ty form ((\(x, _) => Var loc x) <$> held) args
  implementationAt (Written next) w acc ctx env fc t held args = do
    (form, pre) <- standingFor t held
    settle next start (sizeAccessible start) ctx env fc form pre args

  ||| An implementation as `settle` takes it: its form, the markers of the
  ||| values it closes over the projections of the variable that holds
  ||| them, marker 0, which stands for that variable, of the type that holds
  ||| them, so that a value at the form's head is applied as its own type
  ||| says (a choice, dispatched on).
  standingFor : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Maybe (Fin nv, Holes) -> Front (ClosedTerm, List (Stand nv))
  standingFor t Nothing = pure (t, [])
  standingFor t (Just (x, hs)) = do
    values <- unpacked hs.types (holeMarker 0)
    pure (fillHoles values t, [AsVariable (Runtime x (Just hs.binder.type) (Just !(packedType hs.types)))])

  ||| A metavariable applied, as the solution the type checker gave it,
  ||| entered once on the path.
  entered : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Ctx -> List (VarInfo (Fin nv)) -> (afc : FC) -> (fc : FC) -> Name -> Int -> List (TT vars) ->
            List (Arg vars nv) -> Front (Term nv)
  entered ph w acc@(Access rec) ctx env afc fc n i margs args = do
    let Just place = placementOf i
      | Nothing => internal (bestFC ctx fc) "a metavariable at a negative place"
    let Just (Element w' less) = enter place w
      | Nothing => internal (bestFC ctx fc) "a metavariable met again on its own path"
    Just tm <- solution (bestFC ctx fc) n margs
      | Nothing => reject (bestFC ctx fc) ctx.owner EscapeHatch ("the hole " ++ show n)
    spine ph w' (rec w' less) ctx env afc tm args

  ||| A value of the environment applied to arguments, its lambdas applied
  ||| and its solved metavariables filled in by Idris's evaluator that runs
  ||| no definition (`lambdasApplied`), so that a closed call in it still
  ||| runs at run time, and its normal form translated in phase `ph` on the
  ||| path `w`. `value` is closed but for the markers `0 .. length pre - 1`,
  ||| which `pre` says what they stand for. Each argument is given in place
  ||| when the evaluator may see it whole, a compile-time value, and as a
  ||| marker when it is a runtime value. Since nothing is run, a value that
  ||| refers to a definition Idris does not prove ends is settled as any
  ||| other.
  settle : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) -> Ctx -> List (VarInfo (Fin nv)) -> FC ->
           (value : ClosedTerm) -> (pre : List (Stand nv)) -> List (Arg vars nv) -> Front (Term nv)
  settle ph w acc ctx env fc value pre args = do
    (terms, stands) <- given (length pre) args
    nf <- lambdasApplied (foldl (App EmptyFC) value terms)
    loc <- toLoc (bestFC ctx fc)
    bindStands ph w acc ctx env loc 0 id (pre ++ stands) (embedClosed {vars} nf)
    where
      -- A runtime value as a marker: a variable as itself, anything else
      -- by its translation.
      stand : Arg vars nv -> Stand nv
      stand a = case a.written of
        Local _ _ idx _ => case getAt idx env of
          Just e@(Runtime {}) => AsVariable e
          Just e@(Shaped {}) => AsVariable e
          _ => AsValue a.translated
        _ => AsValue a.translated

      -- Is an argument an implementation: a variable that holds one, or a
      -- definition whose type gives one, applied?
      anImplementation : TT vars -> Front Bool
      anImplementation tm = case getFnArgs tm of
        (Local _ _ idx _, _) => pure (case getAt idx env of
                                        Just (Static {}) => True
                                        _ => False)
        (Ref rfc _ n, _) => implementationType (!(lookupDef rfc ctx.owner n)).type
        _ => pure False

      -- One argument for the evaluator, the new markers numbered from `k`,
      -- and what each stands for: a type in place; a runtime variable as a
      -- marker; a value that needs no runtime value where one exists, in
      -- place, as written, or once it needs none only as the implementation
      -- it reduces to (`implementationOf`), as that; an implementation that
      -- closes over runtime values by its form, its markers moved up to
      -- `k`; any other runtime value as a marker.
      argument : Nat -> Arg vars nv -> Front (ClosedTerm, List (Stand nv))
      argument k a = do
        written <- solved (closeWritten fc env a.written)
        if compileTime env a.written then pure (written, []) else case stand a of
          s@(AsVariable _) => pure (holeMarker k, [s])
          s@(AsValue _) => do
            dependent <- runtimeDependent written
            if not dependent then pure (written, []) else do
              impl <- implementationOf written
              if not !(runtimeDependent impl) then pure (impl, []) else do
                True <- anImplementation a.written
                  | False => pure (holeMarker k, [s])
                Just (shape, values) <- a.held
                  | Nothing => pure (holeMarker k, [s])
                pure (shifted markerName k (length values) shape, map (\(_, v) => AsValue v) (forget values))

      given : Nat -> List (Arg vars nv) -> Front (List ClosedTerm, List (Stand nv))
      given k [] = pure ([], [])
      given k (a :: as) = do
        (t, ss) <- argument k a
        (ts, sss) <- given (k + length ss) as
        pure (t :: ts, ss ++ sss)

  ||| A settled term with its markers bound, the first first: a variable as
  ||| another name for it, with no Core binder; a value by a `let` before the
  ||| term. Each value is in the scope outside the binders made so far,
  ||| which `ren` takes into the current one, and is renamed once, where it
  ||| is bound.
  bindStands : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
               (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
               Ctx -> List (VarInfo (Fin nv)) -> Loc -> Nat -> (Fin m -> Fin nv) ->
               List (Stand m) -> TT vars -> Front (Term nv)
  bindStands ph w acc ctx env loc i ren [] body = term ph w acc ctx env body
  bindStands ph w acc ctx env loc i ren (AsVariable e :: stands) body =
    bindStands ph w acc ctx (map ren e :: env) loc (S i) ren stands (refToLocal (markerName i) (markerName i) body)
  bindStands ph w acc ctx env loc i ren (AsValue v :: stands) body = do
    value <- v
    rest <- bindStands ph w acc ctx (under {k = 1} [Runtime FZ Nothing Nothing] env) loc (S i) (FS . ren) stands
                       (refToLocal (markerName i) (markerName i) body)
    pure (Let loc (shown "held") (OfValue Many) (rename ren value) rest)

  ||| A value an implementation closes over, computed inside a settled term
  ||| (`holed`): translated in the settled phase, its markers the variables
  ||| they stand for, on a path that enters the definition that gives the
  ||| implementation. A value of it computed inside another of its own
  ||| values would translate without end, and is the one case refused.
  settledPiece : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                 (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 Ctx -> List (VarInfo (Fin nv)) -> FC -> (impl : ClosedTerm) ->
                 (stands : List (VarInfo (Fin nv))) -> TT vars -> Front (Term nv)
  settledPiece ph w acc@(Access rec) ctx env afc impl stands p = do
    -- `holed` takes a value apart only under a definition that gives an
    -- implementation (`gives`), which is the head of `impl`.
    Just place <- formHead impl
      | Nothing => internal (bestFC ctx afc) ("a value closed over by an implementation no definition gives: " ++
                                              !(showTT impl))
    let Just (Element w' less) = enter place w
      | Nothing => reject (bestFC ctx afc) ctx.owner RuntimeClosure
                          ("a value an implementation closes over, computed inside another of its own: " ++
                           !(showTT impl))
    loc <- toLoc (bestFC ctx afc)
    bindStands ph w' (rec w' less) ctx env loc 0 id (map AsVariable stands) p

  ||| An implementation that closes over runtime values: a definition that
  ||| gives an implementation without matching on its arguments, applied to
  ||| the values, or to implementations that close over them (`TTC (List
  ||| (Term vars))` is the implementation for lists given `TTC (Term
  ||| vars)`), or a variable that holds one. Which implementation it is is
  ||| known now: its form with a marker for each value (`holeMarker`), which
  ||| keys the callee's instance, with the values' types. The values
  ||| themselves are what the callee's parameter holds at runtime. Two
  ||| places that one variable holds are one value. A value of an
  ||| implementation's own type is an implementation chosen at runtime, and
  ||| no such value. A lambda (a polymorphic function, a constraint over a
  ||| value) closes over the runtime values of the scope it mentions.
  |||
  ||| It evaluates nothing itself: each runtime variable of the environment,
  ||| and each that holds an implementation closing over values, stands as a
  ||| marker in the written form, which Closed's reduction takes to the
  ||| implementation it stands for (`implementationOf`), and that is walked.
  holed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          Phase -> (w : Walked) -> (0 acc : SizeAccessible w) -> Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars ->
          Front (Maybe (ClosedTerm, List1 (ClosedTerm, Front (Term nv))))
  holed ph w acc ctx env afc x = do
    r <- implementationOf !(solved (closeWritten afc (fst marked) x))
    Just (shape, f :: fs) <- walk r r []
      | _ => pure Nothing
    let numbered = zip [0 .. length fs] (f :: fs)
    let first = (0, f)
    let distinct = first ::: others [first] (zip [1 .. length fs] fs)
    let finals = map (\(j, (key, _, _)) => position (same j key) (forget distinct)) numbered
    let shape' = foldl (\t, (j, f) => substName (foundName j) (holeMarker f) t)
                       shape (zip [0 .. length finals] finals)
    pure (Just (shape', map (\(_, (_, ty, v)) => (ty, v)) distinct))
    where
      -- The environment with each runtime variable, and each that holds an
      -- implementation closing over values, replaced by its marker, and
      -- those variables, the stands, by marker.
      marking : Nat -> List (VarInfo (Fin nv)) -> (List (VarInfo (Fin nv)), List (VarInfo (Fin nv)))
      marking k [] = ([], [])
      marking k (e@(Runtime {}) :: es) = let (es', ss) = marking (S k) es in (TypeValue (holeMarker k) :: es', e :: ss)
      marking k (e@(Shaped {}) :: es) = let (es', ss) = marking (S k) es in (TypeValue (holeMarker k) :: es', e :: ss)
      marking k (e@(Static _ (Just _)) :: es) = let (es', ss) = marking (S k) es in (TypeValue (holeMarker k) :: es', e :: ss)
      marking k (e :: es) = let (es', ss) = marking k es in (e :: es', ss)

      marked : (List (VarInfo (Fin nv)), List (VarInfo (Fin nv)))
      marked = marking 0 env

      stands : List (VarInfo (Fin nv))
      stands = snd marked

      standAt : Name -> Maybe (VarInfo (Fin nv))
      standAt n = markerOf n >>= \k => getAt k stands

      -- What the written form has for a variable (`closeWritten`), where a
      -- stand's marker is: a runtime value's unknown value, its shape, an
      -- implementation's form.
      writtenAs : VarInfo (Fin nv) -> ClosedTerm
      writtenAs (Shaped _ _ _ s) = s
      writtenAs (Static t _) = t
      writtenAs (TypeValue t) = t
      writtenAs (Runtime {}) = probeTerm ProbeRuntime

      restoring : Nat -> List (VarInfo (Fin nv)) -> (ns : List Name ** (Bounds ns, SubstEnv ns Scope.empty))
      restoring k [] = ([] ** (None, []))
      restoring k (e :: es) =
        let (ns ** (bs, vs)) = restoring (S k) es in
        (markerName k :: ns ** (Add (markerName k) (markerName k) bs, writtenAs e :: vs))

      -- A part of the implementation with the stands' markers back as the
      -- written form has them, all at once.
      restore : ClosedTerm -> ClosedTerm
      restore t = let (ns ** (bs, vs)) = restoring 0 stands in substs (mkSizeOf ns) vs (refsToLocals bs t)

      -- The values after the first, the first place each variable
      -- holds: `seen` are the values kept so far.
      others : List (Nat, (Maybe (Fin nv), ClosedTerm, Front (Term nv))) ->
               List (Nat, (Maybe (Fin nv), ClosedTerm, Front (Term nv))) ->
               List (Nat, (Maybe (Fin nv), ClosedTerm, Front (Term nv)))
      others seen [] = []
      others seen (h@(_, (Just k, _, _)) :: hs) =
        if any (\(_, (k', _, _)) => k' == Just k) seen then others seen hs else h :: others (h :: seen) hs
      others seen (h :: hs) = h :: others (h :: seen) hs

      same : Nat -> Maybe (Fin nv) -> (Nat, (Maybe (Fin nv), ClosedTerm, Front (Term nv))) -> Bool
      same j (Just k) (_, (k', _, _)) = k' == Just k
      same j Nothing (j', _) = j == j'

      position : (a -> Bool) -> List a -> Nat
      position p [] = 0
      position p (y :: ys) = if p y then 0 else S (position p ys)

      -- A value of the implementation: a runtime variable as itself, any
      -- other computed from the variables in the next phase, or, in a
      -- settled term, in the settled phase on a path that enters the
      -- definition that gives the implementation (`settledPiece`).
      piece : Phase -> ClosedTerm -> ClosedTerm -> Front (Front (Term nv))
      piece ph'@Settled impl p =
        pure (settledPiece ph' w acc ctx env afc (restore impl) stands (embedClosed {vars} p))
      piece (Written next) _ p = do
        loc <- toLoc (bestFC ctx afc)
        pure (bindStands next start (sizeAccessible start) ctx env loc 0 id (map AsVariable stands) (embedClosed {vars} p))

      -- The runtime variable a part of the implementation is, if it is one.
      variableOf : ClosedTerm -> Maybe (Fin nv)
      variableOf (Ref _ Bound n) = case standAt n of
        Just (Runtime v _ _) => Just v
        Just (Shaped v _ _ _) => Just v
        _ => Nothing
      variableOf _ = Nothing

      value : ClosedTerm -> ClosedTerm -> ClosedTerm -> Front (Maybe (ClosedTerm, Found nv))
      value impl aty p = case variableOf p of
        Just v => do
          loc <- toLoc (bestFC ctx afc)
          pure (Just (foundMarker 0, [(Just v, aty, pure (Var loc v))]))
        Nothing => (\t => Just (foundMarker 0, [(Nothing, aty, t)])) <$> piece ph impl p

      -- Does a definition give an implementation without matching on
      -- its arguments: one with one right-hand side, or a constructor
      -- of an implementation (the pair that holds a tuple of
      -- constraints, or an interface's own constructor, which an
      -- expanded implementation is already built with: its fields
      -- that are functions are the closures it closes over values
      -- with)?
      gives : Defined -> Front Bool
      gives d = case definition d.def of
        PMDef {} => pure (case d.matched of
                            Just m => isJust (leafOf m)
                            Nothing => False)
        DCon {} => resultIsImpl d.type
        _ => pure False
        where
          -- The constructor's result, under its binders: an
          -- interface's own type, or a pair (whose components the
          -- binders name, so the pair is known by its type's name,
          -- not by what it pairs here).
          resultIsImpl : TT vs -> Front Bool
          resultIsImpl (Bind _ _ (Pi {}) sc) = resultIsImpl sc
          resultIsImpl tm = case getFnArgs tm of
            (Ref _ (TyCon _) tn, _) => if !(pairTyped tn)
                                          then pure True else implementationType tm
            _ => pure False

      -- The use and the type of the binder an argument is given at, and
      -- the rest of the type; nothing for an argument past the binders
      -- the type shows, a runtime value of a type not known here.
      binder : ClosedTerm -> (Maybe (Use, ClosedTerm), ClosedTerm -> ClosedTerm)
      binder (Bind _ _ (Pi _ rig _ aty) sc) = (Just (use rig, aty), \v => subst v sc)
      binder ty = (Nothing, const ty)

      -- An implementation is walked in turn, holding the values it closes
      -- over, where the program fixes it now (`fixing`); any other
      -- argument is a value. A runtime variable there holds a choice, and
      -- an implementation the running program chooses computes one: a
      -- value like any other, the implementation holding the choice its
      -- constraint made.
      part : ClosedTerm -> ClosedTerm -> ClosedTerm -> Lazy (Front (Maybe (ClosedTerm, Found nv))) ->
             Front (Maybe (ClosedTerm, Found nv))
      part impl aty a walked = do
        aty' <- normaliseClosed aty
        if not !(implementationType aty') || isJust (variableOf a) then value impl aty' a else do
          Just (form, found) <- walked
            | Nothing => value impl aty' a
          FixedNow <- fixing aty' form
            | ChosenAtRunTime _ => value impl aty' a
          pure (Just (form, found))

      -- The arguments of a definition that gives `impl`, over its type,
      -- each found value numbered from 0 among the arguments' together.
      parts : ClosedTerm -> ClosedTerm -> List (ClosedTerm, Lazy (Front (Maybe (ClosedTerm, Found nv)))) ->
              Front (Maybe (List ClosedTerm, Found nv))
      parts impl _ [] = pure (Just ([], []))
      parts impl ty ((a, walked) :: as) = do
        let written = restore a
        dependent <- runtimeDependent written
        ty' <- normaliseClosed ty
        let (at, rest) = binder ty'
        here <- case (at, dependent) of
                  (Just (Erased, _), _) => pure (Just (written, the (Found nv) []))
                  (_, False) => pure (Just (written, the (Found nv) []))
                  (Just (Used _, aty), True) => part impl aty a walked
                  (Nothing, True) => pure Nothing
        let Just (v, found) = here
          | Nothing => pure Nothing
        Just (vs, after) <- parts impl (rest v) as
          | Nothing => pure Nothing
        pure (Just (v :: map (shifted foundName (length found) (length after)) vs, found ++ after))

      -- Anything else written of implementations that close over
      -- values and of compile-time values (a projection of a tuple
      -- of constraints, `fst c`): each variable that holds one is one
      -- value, its markers that value's projections, and nothing
      -- else may be a runtime value.
      closedOver : ClosedTerm -> Front (Maybe (ClosedTerm, Found nv))
      closedOver impl = do
        let used = filter (\(k, _) => mentions (isMarker k) impl) (holders 0 stands)
        filled <- fill 0 used impl
        let impl' = restore filled
        if !(runtimeDependent impl') then pure Nothing else do
          loc <- toLoc afc
          found <- traverse (\(_, (v, hs, _)) => do
                               held <- packedType hs.types
                               pure (Just v, held, pure (Var loc v))) used
          pure (Just (impl', found))
        where
          isMarker : Nat -> TT vs -> Bool
          isMarker k (Ref _ _ n) = n == markerName k
          isMarker _ _ = False

          holders : Nat -> List (VarInfo (Fin nv)) -> List (Nat, (Fin nv, Holes, ClosedTerm))
          holders k (Static t (Just (v, hs)) :: rest) = (k, (v, hs, t)) :: holders (S k) rest
          holders k (_ :: rest) = holders (S k) rest
          holders _ [] = []

          -- Each holder's marker as its form, its own markers the
          -- projections of the value it is.
          fill : Nat -> List (Nat, (Fin nv, Holes, ClosedTerm)) -> ClosedTerm -> Front ClosedTerm
          fill j [] t = pure t
          fill j ((k, (_, hs, form)) :: rest) t = do
            projections <- unpacked hs.types (foundMarker j)
            fill (S j) rest (substName (markerName k) (fillHoles projections form) t)

      -- What a definition that gives an implementation is applied to,
      -- and anything else.
      headed : ClosedTerm -> ClosedTerm -> List (ClosedTerm, Lazy (Front (Maybe (ClosedTerm, Found nv)))) ->
               Front (Maybe (ClosedTerm, Found nv))
      -- A variable that holds an implementation that closes over values
      -- holds them as one value: its markers become that value's
      -- projections.
      headed impl (Ref _ Bound n) [] = case standAt n of
        Just (Static t (Just (v, hs))) => do
          loc <- toLoc (bestFC ctx afc)
          projections <- unpacked hs.types (foundMarker 0)
          held <- packedType hs.types
          pure (Just (fillHoles projections t, [(Just v, held, pure (Var loc v))]))
        _ => closedOver impl
      headed impl (Ref _ Bound _) _ = closedOver impl
      headed impl (Ref rfc nt n) args = do
        d <- lookupDef rfc ctx.owner n
        True <- gives d
          | False => closedOver impl
        Just (vs, found) <- parts impl d.type args
          | Nothing => pure Nothing
        pure (Just (foldl (App rfc) (Ref rfc nt n) vs, found))
      headed impl lam@(Bind _ _ (Lam {}) _) [] = captured lam
      headed impl _ _ = closedOver impl

      -- A lambda: a function it gives (a polymorphic one, a constraint over
      -- a value), which closes over the runtime values of the scope it
      -- mentions, as a closure holds its captures: a runtime variable as
      -- itself, a variable that holds an implementation closing over
      -- values as those values. Its form keys the instance of what it is
      -- given to, the values its parameter holds. A runtime variable whose
      -- Idris type is not known here is no value of a known type, so the
      -- lambda is computed as the closure it is.
      captured : ClosedTerm -> Front (Maybe (ClosedTerm, Found nv))
      captured lam = do
        loc <- toLoc (bestFC ctx afc)
        let used = filter (\(k, _) => mentions (isMarker k) lam) (zip [0 .. length stands] stands)
        Just (filled, found) <- capture loc 0 used lam
          | Nothing => pure Nothing
        let lam' = restore filled
        if !(runtimeDependent lam') then pure Nothing else pure (Just (lam', found))
        where
          isMarker : Nat -> TT vs -> Bool
          isMarker k (Ref _ _ n) = n == markerName k
          isMarker _ _ = False

          -- Each stand the lambda mentions, from found value `j` on.
          capture : Loc -> Nat -> List (Nat, VarInfo (Fin nv)) -> ClosedTerm -> Front (Maybe (ClosedTerm, Found nv))
          capture loc j [] t = pure (Just (t, []))
          capture loc j ((k, e) :: rest) t = do
            Just (v, ty, here) <- standing e
              | Nothing => pure Nothing
            Just (t', more) <- capture loc (S j) rest (substName (markerName k) here t)
              | Nothing => pure Nothing
            pure (Just (t', (Just v, ty, pure (Var loc v)) :: more))
            where
              -- The variable a stand is, the type of the value it holds, and
              -- what the lambda has where its marker was.
              standing : VarInfo (Fin nv) -> Front (Maybe (Fin nv, ClosedTerm, ClosedTerm))
              standing (Runtime v _ (Just ity)) = pure (Just (v, ity, foundMarker j))
              standing (Shaped v _ ity _) = pure (Just (v, ity, foundMarker j))
              standing (Static form (Just (v, hs))) = do
                projections <- unpacked hs.types (foundMarker j)
                held <- packedType hs.types
                pure (Just (v, held, fillHoles projections form))
              standing _ = pure Nothing

      -- An implementation's spine, each argument with its own walk
      -- suspended where it is a subterm.
      walk : ClosedTerm -> ClosedTerm -> List (ClosedTerm, Lazy (Front (Maybe (ClosedTerm, Found nv)))) ->
             Front (Maybe (ClosedTerm, Found nv))
      walk impl (App _ f a) args = walk impl f ((a, walk a a []) :: args)
      walk impl h args = headed impl h args

  ||| An implementation or a polymorphic function the program fixes, written
  ||| in a runtime position, as the member of its type's choice it is
  ||| (`Choices`): its form, with the runtime values it closes over as its
  ||| field. Nothing for one the running program chooses (stuck on a
  ||| runtime value), or one a definition Idris does not prove ends
  ||| computes, which no compile-time reduction runs: it is translated as
  ||| the computation it is, whose value is the choice among the members
  ||| its own body fixes.
  member : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Ctx -> List (VarInfo (Fin nv)) -> FC -> Loc -> (type : ClosedTerm) -> TT vars -> Front (Maybe (Term nv))
  member ph w acc ctx env fc loc ty written = do
    impl <- solved (closeWritten fc env written)
    if not !(runtimeDependent impl)
      then do
        FixedNow <- fixing ty impl
          | ChosenAtRunTime _ => pure Nothing
        con <- memberBare fc ctx.owner ty !(implementationOf impl)
        pure (Just (ConApp loc con [] []))
      else do
        Just (shape, values) <- holed ph w acc ctx env fc written
          | Nothing => pure Nothing
        form <- implementationOf shape
        FixedNow <- fixing ty form
          | ChosenAtRunTime _ => pure Nothing
        held <- coreType fc ctx.owner ValueType !(normaliseClosed !(packedType (map fst values)))
        con <- memberHolding fc ctx.owner ty form (MkHoles (map fst values) (MkBinder Many held))
        v <- pack fc ctx.owner loc !(valuesOf values)
        pure (Just (ConApp loc con [] [v]))

  ||| A definition applied to its arguments.
  applyRef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
             (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             Ctx -> List (VarInfo (Fin nv)) -> (afc : FC) -> (rfc : FC) -> NameType -> Name ->
             List (Arg vars nv) -> Front (Term nv)
  applyRef ph w acc ctx env afc rfc nt name args = do
    let fc = bestFC ctx rfc
    loc <- toLoc fc
    d <- lookupDef fc ctx.owner name
    let def = d.def
    let ty = d.type
    let full = fullname def
    -- What a hook lowers a call of this definition to stands for it, the
    -- registry's entry it applied.
    let lowered = Just (shown (show full))
    -- An implementation in a runtime position that the program fixes here
    -- is a member of its type's choice.
    Nothing <- memberHere fc loc ty
      | Just member => pure member
    case definition def of
      DCon tag arity _ => constructor fc loc d ty arity args
      TCon {} => inRuntime ctx.owner fc env (foldl (App rfc) (Ref rfc nt name) (map (.written) args))
      Builtin {arity} op => primitive fc loc full arity op ty args
      PMDef _ params _ => hooked fc loc full lowered (length params) d ty (hooksOf full) $ do
        exiting <- exitCast d
        if exiting
           then exitAction fc loc (length params) ty args
           else call fc loc full Nothing (length params) ty args
      -- A `%foreign` definition is known by its spec, an `%extern` one by
      -- its name; one the registry gives no meaning is an escape hatch.
      ForeignDef arity specs => do
        site <- siteAt fc
        case foreignHookOf site ctx.owner "" full specs of
          Right hs => hooked fc loc full lowered arity d ty hs
                        (reject fc ctx.owner EscapeHatch ("foreign function " ++ show full))
          Left r => rejectWith r
      ExternDef arity => hooked fc loc full lowered arity d ty (hooksOf full)
                           (reject fc ctx.owner EscapeHatch ("extern function " ++ show full))
      Hole {} => reject fc ctx.owner EscapeHatch ("the hole " ++ show full)
      _ => internal fc ("a reference to " ++ show full)
    where
      -- The member of its type's choice an implementation or a
      -- polymorphic function fixed here is (`member`), where the
      -- definition applied to the arguments gives one in a runtime
      -- position. A function to implementations is a closure.
      memberHere : FC -> Loc -> ClosedTerm -> Front (Maybe (Term nv))
      memberHere fc loc defTy = do
        Just ty <- typeAfter defTy args
          | Nothing => pure Nothing
        ty' <- normaliseClosed ty
        True <- choiceType ty'
          | False => pure Nothing
        member ph w acc ctx env afc loc ty' (foldl (App rfc) (Ref rfc nt name) (map (.written) args))

      -- A definition's type after arguments, each substituted where the
      -- rest mentions it; unknown once the type shows no more binders.
      typeAfter : ClosedTerm -> List (Arg vars nv) -> Front (Maybe ClosedTerm)
      typeAfter ty [] = pure (Just ty)
      typeAfter ty (x :: xs) = do
        ty' <- case ty of
                 Bind _ _ (Pi {}) _ => pure ty
                 _ => normaliseClosed ty
        case ty' of
          Bind _ _ (Pi {}) sc => do
            next <- instantiate afc env sc x.written
            typeAfter next xs
          _ => pure Nothing

      -- The runtime arguments of a call, one term per parameter that exists
      -- at runtime: nothing for a type, an implementation or an argument of
      -- quantity 0. An implementation that closes over runtime values passes
      -- them, as one value (`packedType`); a choice of one is its value.
      arguments : Loc -> List PKind -> List (Arg vars nv) -> Front (List (Term nv))
      arguments loc (ValueParam _ _ t :: ks) (x :: xs) = (::) <$> valueAt loc t x <*> arguments loc ks xs
      arguments loc (ChoiceParam {} :: ks) (x :: xs) = (::) <$> x.translated <*> arguments loc ks xs
      arguments loc (DictParam _ (Just _) :: ks) (x :: xs) = do
        Just (_, held) <- x.held
          | Nothing => internal afc "the values an implementation closes over are gone"
        v <- pack afc ctx.owner loc !(valuesOf held)
        (v ::) <$> arguments loc ks xs
      arguments loc (_ :: ks) (_ :: xs) = arguments loc ks xs
      arguments loc _ _ = pure []

      -- A runtime argument. A lambda given where a polymorphic function is
      -- held is the member of its type's choice it is (`member`): its own
      -- binders do not say its type, which the position does; one given
      -- delayed where a delayed one is held (a branch of `if`), the member
      -- delayed.
      valueAt : Loc -> ClosedTerm -> Arg vars nv -> Front (Term nv)
      valueAt loc t x = case (x.written, t) of
        (Bind _ _ (Lam {}) _, _) => do
          Just m <- asMember t x.written
            | Nothing => x.translated
          pure m
        (TDelay dfc _ _ inner@(Bind _ _ (Lam {}) _), TDelayed _ _ t') => do
          Just m <- asMember t' inner
            | Nothing => x.translated
          (\dloc => Suspend dloc m) <$> toLoc (bestFC ctx dfc)
        _ => x.translated
        where
          asMember : ClosedTerm -> TT vars -> Front (Maybe (Term nv))
          asMember ty lam = do
            True <- choiceType ty
              | False => pure Nothing
            member ph w acc ctx env afc loc ty lam

      argValues : List (Arg vars nv) -> ArgValues
      argValues = map (argValueIn env afc)

      -- The call's value: `mk` on the runtime arguments when the call gives
      -- every parameter, applied to the arguments past them over the
      -- callee's result type (`resTy`); with fewer, one closure per missing
      -- runtime parameter, as the curried type of the result requires. The
      -- arguments given (`arguments`) and the closures' parameters are as
      -- many as the call has runtime parameters, which is what `mk` takes.
      finish : Loc -> (kinds : List PKind) -> Nat -> List (Term nv) ->
               Maker (Runtimes kinds) -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      finish loc kinds arity given mk resTy xs = do
        let missing = drop (length (take arity xs)) kinds
        let Yes counted = decEq (length given + Runtimes missing) (Runtimes kinds)
          | No _ => internal afc ("a call of " ++ show name ++ " given " ++ show (length given) ++
                                  " runtime arguments, missing " ++ show (Runtimes missing) ++ ", of its " ++
                                  show (Runtimes kinds))
        let made = etaExpand loc (runtimeBinders missing) (recount counted mk) (fromList given)
        -- A type or a form the call leaves out was refused where the
        -- call's arguments were classified, and an implementation it
        -- leaves out is a choice, so the missing ones are runtime
        -- parameters, each a closure's.
        if null missing
           then applyOver ctx env afc loc (show <$> fullName name) made (Just resTy) (drop arity xs)
           else pure made

      -- A method or a parent taken from an implementation the call fixes:
      -- the implementation's field, applied in place to the arguments past
      -- the projection's, settled. Idris writes a method's field as a
      -- lambda over every argument of the method, erased ones included,
      -- applying the method's own function, so once the evaluator has
      -- applied it, that function is called at its own arity and no
      -- instance of the projection exists. A projection that does not
      -- reduce, or whose record is a runtime value (`fst` of a pair), is
      -- called as any definition is, and so is every projection of a
      -- settled term: the same value, one call further.
      resolveMethod : Phase -> FC -> Name -> List PKind -> List (Arg vars nv) -> Front (Maybe (Term nv))
      resolveMethod Settled fc n kinds xs = pure Nothing
      resolveMethod (Written next) fc n kinds xs = do
        Just pr <- projection n
          | Nothing => pure Nothing
        let parity = length pr.params
        let idx = pr.matched
        let True = length xs >= parity
          | False => pure Nothing
        let statics = map compileTimeArg kinds
        case getAt idx kinds of
          Just (DictParam _ Nothing) => do
            Just field <- projected n statics
              | Nothing => pure Nothing
            Just <$> settle next start (sizeAccessible start) ctx env fc field [] (drop parity xs)
          -- The field's markers are the implementation's form's, which
          -- stand for the values it closes over.
          Just (DictParam _ (Just _)) => do
            let Just x = getAt idx xs
              | Nothing => pure Nothing
            Just (shape, held) <- x.held
              | Nothing => internal fc "the values an implementation closes over are gone"
            Just field <- projected n (replaceAt idx shape statics)
              | Nothing => pure Nothing
            let pre = map (\(_, v) => AsValue v) (forget held)
            Just <$> settle next start (sizeAccessible start) ctx env fc field pre (drop parity xs)
          _ => pure Nothing
        where
          replaceAt : Nat -> a -> List a -> List a
          replaceAt Z v (_ :: ys) = v :: ys
          replaceAt (S i) v (y :: ys) = y :: replaceAt i v ys
          replaceAt _ _ ys = ys

      -- A call whose result is an array: its dimensions that an argument
      -- fixes (a natural, or a dimension of an array argument) stated equal
      -- to it, the arguments bound once. `is` are the terms the call gives
      -- its callee's index parameters.
      tiedCall : FC -> Loc -> FnId -> Maybe Shown -> List ITerm -> Nat -> ClosedTerm -> (kinds : List PKind) ->
                 ClosedTerm -> Front (Maker (Runtimes kinds))
      tiedCall fc loc inst lowered is arity ty kinds resTy = do
        Just _ <- arrayView resTy
          | Nothing => pure (listed (Call loc inst lowered is))
        (tel, res) <- sizedTelescope arity ty kinds
        rt <- coreType fc ctx.owner ValueType resTy
        [] <- resultTies tel res rt
          | ties => pure (MkMaker (\ys => bindEach loc (runtimeBinders kinds) ys (\ren, vs =>
                      Tie loc (Call loc inst lowered is (toList (map (Var loc) vs)))
                          (map (\(k, w) => (k, witnessTerm loc vs w)) ties))))
        pure (listed (Call loc inst lowered is))

      -- A call of a function: its instance at the static arguments the
      -- call gives, its index parameters given the terms of the arguments
      -- at their positions, read in this scope.
      call : FC -> Loc -> Name -> Maybe Shown -> Nat -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      call fc loc n lowered arity ty xs = do
        let vals = argValues (take arity xs)
        (kinds, resTy) <- classifyCall fc ctx.owner arity ty vals
        Nothing <- resolveMethod ph fc n kinds xs
          | Just resolved => pure resolved
        inst <- calleeAt (choicesIn kinds) fc ctx.owner (OfDefinition n) kinds
        given <- arguments loc kinds (take arity xs)
        is <- callIndices kinds vals
        mk <- tiedCall fc loc inst lowered is arity ty kinds resTy
        finish loc kinds arity given mk resTy xs

      -- The identity on the last runtime argument, wherever it stands among
      -- the proofs and types (a cell's form or a frame's extents before it
      -- are not read); below its arity a closure over its missing
      -- parameters, whose body is the saturated identity, as every hook is
      -- below its arity.
      identity : FC -> Loc -> Defined -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      identity fc loc d ty xs = do
        let arity = binders ty
        if length xs >= arity
           then do
             let (now, rest) = splitAt arity xs
             let Just value = lastValue !(argumentsOf d) now
               | Nothing => internal fc ("the identity " ++ show name ++ " without a runtime argument")
             v <- value.translated
             applyOver ctx env fc loc (pure (show name)) v !(typeAfter ty now) rest
           else do
             (kinds, resTy) <- classifyCall fc ctx.owner arity ty (argValues xs)
             given <- arguments loc kinds xs
             mk <- lastOf (runtimeBinders kinds)
             finish loc kinds arity given mk resTy xs
        where
          -- Below its arity, the identity's value is its last runtime
          -- argument, which the closures take.
          lastOf : Vect r Binder -> Front (Maker r)
          lastOf [] = internal fc ("the identity " ++ show name ++ " without a runtime parameter")
          lastOf (_ :: _) = pure (MkMaker (\ys => Data.Vect.last ys))

      -- Is the definition being translated one whose calls end the program
      -- (`Hook.Exits`, `System.exitWith`)? Its `believe_me` gives the
      -- exit's `PrimIO ()` any result, which is sound only because that
      -- action does not return; anywhere else `believe_me` stays an escape
      -- hatch.
      exiting : Front Bool
      exiting = do
        st <- getState
        -- A member at a use is no definition, and so no exit's.
        let OfDefinition n :: _ = map (.instantiates) st.chain
          | _ => pure False
        owner <- lookupDef afc ctx.owner n
        pure (hooksOf (fullname owner.def)).exits

      -- Is a definition `believe_me`, whose body is the `BelieveMe`
      -- primitive?
      believeMe : Defined -> Front Bool
      believeMe d = do
        let Just m = d.matched
          | Nothing => pure False
        let Just tm = leafOf m
          | Nothing => pure False
        let (Ref _ _ n, _) = getFnArgs tm
          | _ => pure False
        Just prim <- defined n
          | Nothing => pure False
        let Builtin BelieveMe = definition prim.def
          | _ => pure False
        pure True

      exitCast : Defined -> Front Bool
      exitCast d = do
        wrapper <- believeMe d
        if wrapper then exiting else pure False

      -- The exit's `believe_me`, on the action: the action applied to the
      -- world, after which nothing runs.
      exitAction : FC -> Loc -> Nat -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      exitAction fc loc arity ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        mk <- exits (runtimeBinders kinds)
        finish loc kinds arity given mk resTy xs
        where
          -- The action, the last runtime argument, applied to the world;
          -- nothing runs after it.
          exits : Vect r Binder -> Front (Maker r)
          exits [] = internal fc ("the exit " ++ show name ++ " without its action")
          exits (_ :: _) = pure (MkMaker (\ns => Lam noLoc (shown "world") (MkBinder Once WorldT)
                                                  (Let loc (shown "exited") (OfValue Many)
                                                       (App loc (weakenUnder 1 (Data.Vect.last ns)) (Var loc FZ))
                                                       (Unreachable loc))))

      -- The library function a hook of the callee names (`q`, as the
      -- registry writes it, for a message), as it was read with the
      -- callee (`Defined.library`): the name was interned once, where the
      -- callee's definitions were read, for every hook that names one.
      libraryNamed : FC -> QName -> Maybe Name -> Front Name
      libraryNamed fc q (Just n) = pure n
      libraryNamed fc q Nothing = internal fc ("the library function " ++ show q ++ " a hook of " ++ show name ++ " names was not read")

      -- A call of a monomorphic library function the registry names, on
      -- runtime arguments: saturated, and the ones past its arity applied.
      libraryCall : FC -> Loc -> QName -> Maybe Name -> Front ({0 m : Nat} -> List (Term m) -> Term m)
      libraryCall fc loc q library = do
        target <- lookupDef fc ctx.owner !(libraryNamed fc q library)
        let def = target.def
        let PMDef _ params _ = definition def
          | _ => reject fc (show q) HookShape "the registry names a library function that is not a definition"
        let arity = length params
        (kinds, _) <- classifyCall fc ctx.owner arity target.type (replicate arity Nothing)
        let True = all valueOnly kinds
          | False => reject fc (show q) HookShape "the registry names a library function with compile-time arguments"
        inst <- request fc ctx.owner (OfDefinition (fullname def)) kinds
        -- Its runtime arguments are all a call gives it, so no index
        -- parameter of it is given a term it is linked to.
        is <- callIndices kinds (replicate arity Nothing)
        let runtime = Runtimes kinds
        pure (\ns => let (now, rest) = splitAt runtime ns in
                     foldl (App loc) (Call loc inst Nothing is now) rest)
        where
          valueOnly : PKind -> Bool
          valueOnly (ValueParam {}) = True
          valueOnly ErasedParam = True
          valueOnly (IndexParam _) = True
          valueOnly _ = False

      -- A function on naturals, as the primitives it means (the registry's
      -- `NatOperation`); partially applied, it is eta-expanded like a call.
      natOperation : FC -> Loc -> Maybe Shown -> Maybe Name -> NatMeaning -> Nat -> ClosedTerm -> List (Arg vars nv) ->
                     Front (Term nv)
      natOperation fc loc lowered library m arity ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        case m of
          Primitive {k} p => do
            counted <- operands k kinds
            finish loc kinds arity given (recount counted (MkMaker (\ns => PrimApp loc p lowered ns))) resTy xs
          Clamped {k} p => do
            counted <- operands k kinds
            finish loc kinds arity given
                   (recount counted (MkMaker (\ns => PrimApp loc (Op natFromBig (NatT IOpaque) made) lowered
                                                       [PrimApp loc p lowered (map (\n => PrimApp loc (Op natToBig BigT made) lowered [n]) ns)])))
                   resTy xs
          Tested c q => do
            toBool <- libraryCall fc loc q library
            counted <- operands 2 kinds
            finish loc kinds arity given (recount counted (MkMaker (\ns => toBool [PrimApp loc (NatCompare c) lowered ns]))) resTy xs
          OnIntegers q => do
            f <- libraryCall fc loc q library
            finish loc kinds arity given (listed (\ns => f (map (\n => PrimApp loc (Op natToBig BigT made) lowered [n]) ns))) resTy xs
        where
          -- The primitive takes the call's runtime arguments, as many as
          -- its operands.
          operands : (k : Nat) -> (kinds : List PKind) -> Front (Runtimes kinds = k)
          operands k kinds = case decEq (Runtimes kinds) k of
            Yes counted => pure counted
            No _ => internal fc ("the natural operation " ++ show name ++ " of " ++ show k ++ " operands, given " ++
                                 show (Runtimes kinds) ++ " runtime arguments")

      -- The value of a head that takes one runtime argument, made from it;
      -- a head of another number of them is not the one `wrong` names.
      single : FC -> String -> ({0 m : Nat} -> Term m -> Term m) -> Vect r Binder -> Front (Maker r)
      single fc wrong f [_] = pure (MkMaker (\[y] => f y))
      single fc wrong f _ = internal fc wrong

      -- A constructor of a `Nat`-like type is a natural: zero is 0, a
      -- successor adds 1 to its one runtime argument (the others are
      -- erased indices, as `FS`'s). A successor of a literal is one
      -- literal, so a closed chain of them, a numeral Idris wrote, is one
      -- constant however large, never a chain of additions.
      natConstructor : FC -> Loc -> NatRole -> List PKind -> Nat -> List (Term nv) ->
                       ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      natConstructor fc loc Zero kinds arity given resTy xs =
        finish loc kinds arity given (MkMaker (\_ => Literal loc (LNat 0))) resTy xs
      natConstructor fc loc Succ kinds arity given resTy xs = do
        mk <- single fc "a successor without one runtime argument" successor (runtimeBinders kinds)
        finish loc kinds arity given mk resTy xs
        where
          successor : {0 m : Nat} -> Term m -> Term m
          successor (Literal _ (LNat k)) = Literal loc (LNat (k + 1))
          successor y = PrimApp loc (Op bigAdd (NatT IOpaque) made) Nothing [y, Literal loc (LNat 1)]

      -- A constructor application: the fields, or for a type with one
      -- runtime field the field itself, since such a value is its field's.
      constructor : FC -> Loc -> Defined -> ClosedTerm -> Nat -> List (Arg vars nv) -> Front (Term nv)
      constructor fc loc d ty arity xs = do
        let def = d.def
        (kinds, resTy) <- classifyCall fc ctx.owner arity ty (argValues (take arity xs))
        -- A constructor of Idris's `Nat` is a natural; one of any family,
        -- a numeral family (`Fin`) among them, is the family's.
        family <- dataOf fc ctx.owner !(normaliseClosed resTy)
        case (natRole def, family) of
          (Just role, Nothing) => do
            given <- arguments loc kinds (take arity xs)
            natConstructor fc loc role kinds arity given resTy xs
          (_, Nothing) => do
            -- A value array is abstract: only the functions the registry
            -- knows open it, and their bodies are not translated.
            Just _ <- arrayView !(normaliseClosed resTy)
              | Nothing => internal fc "a constructor of a type that is not data"
            reject fc (show (fullname def)) HookShape
                   ("the array type of " ++ show (fullname def) ++ " is opaque: its constructor is applied")
          (_, Just (inst, _)) => do
            st <- getState
            Just cid <- conIdOf inst d
              | Nothing => internal fc ("the constructor " ++ show (fullname def) ++ " is not registered")
            let Just info = lookup cid st.cons
              | Nothing => internal fc ("the constructor " ++ show (fullname def) ++ " is not registered")
            -- Its fields are the call's runtime arguments: an implementation
            -- the constructor holds is a field like any other, the value of
            -- its choice the construction site gives.
            let fields = asFields info.args kinds
            given <- arguments loc fields (take arity xs)
            let (k ** con) = info.con
            let Yes counted = decEq (Runtimes fields) k
              | No _ => internal fc ("the constructor " ++ show (fullname def) ++ " of " ++ show k ++
                                     " fields, given " ++ show (Runtimes fields) ++ " runtime arguments")
            links <- binderTerms con.binders (argValues (take arity xs))
            finish loc fields arity given (recount counted (MkMaker (\ys => ConApp loc con links ys))) resTy xs

      -- A constructor's kinds with each implementation it holds a field:
      -- the field's binder, its value the argument translated, a member of
      -- its choice where the site fixes the implementation.
      asFields : List ArgKind -> List PKind -> List PKind
      asFields (Field _ b t :: as) (DictParam _ _ :: ks) = ValueParam b Nothing t :: asFields as ks
      asFields (Field _ b t :: as) (ChoiceParam _ _ :: ks) = ValueParam b Nothing t :: asFields as ks
      asFields (_ :: as) (k :: ks) = k :: asFields as ks
      asFields _ ks = ks

      primitive : FC -> Loc -> Name -> (arity : Nat) -> PrimFn arity -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      primitive fc loc n arity op ty xs = case op of
        BelieveMe => do
          exit <- exiting
          if exit then exitAction fc loc arity ty xs
                  else reject fc ctx.owner EscapeHatch "believe_me"
        -- A user's crash is rejected. A trusted library's is the string it
        -- is given: the program ends with that string and does not return.
        Crash => do
          here <- toLoc ctx.fc
          if covers Trusted here.origin
            then case last' (take arity xs) of
              Just m => do
                s <- m.translated
                pure (CrashWith loc s)
              Nothing => reject fc ctx.owner EscapeHatch "idris_crash"
            else reject fc ctx.owner EscapeHatch "idris_crash"
        _ => supported
        where
          -- The primitive on the arguments its type takes, one per operand
          -- of its translation.
          supported : Front (Term nv)
          supported = do
            (kinds, resTy) <- classifyCall fc ctx.owner arity ty []
            result <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
            let Just mk = primTerm loc result op
              | Nothing => reject fc ctx.owner Primitive ("primitive " ++ show n)
            let Yes counted = decEq (Runtimes kinds) arity
              | No _ => internal fc ("the primitive " ++ show n ++ " given " ++ show (Runtimes kinds) ++
                                     " runtime arguments, of its " ++ show arity)
            given <- arguments loc kinds (take arity xs)
            finish loc kinds arity given (recount counted (MkMaker mk)) resTy xs

      -- A string built once from a list: the primitive of the one
      -- parameter, a list, which it takes at the list's own instance.
      builderCall : FC -> Loc -> Maybe Shown -> Nat -> PureOp -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      builderCall fc loc lowered arity p ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner arity ty []
        case kinds of
          [ValueParam (MkBinder _ (DataT _ _)) _ _] => pure ()
          _ => internal fc "a string built from something other than a list"
        let Yes counted = decEq (Runtimes kinds) p.arity
          | No _ => internal fc ("the string builder " ++ show name ++ " of another number of operands")
        given <- arguments loc kinds (take arity xs)
        result <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
        finish loc kinds arity given (recount counted (MkMaker (\ys => PrimApp loc (Op p.op result made) lowered ys))) resTy xs

      -- A call of the library function a foreign definition stands for.
      aliasCall : FC -> Loc -> Maybe Shown -> QName -> Maybe Name -> List (Arg vars nv) -> Front (Term nv)
      aliasCall fc loc lowered q library xs = do
        target <- lookupDef fc ctx.owner !(libraryNamed fc q library)
        let PMDef _ params _ = definition target.def
          | _ => internal fc (show q ++ " is not a function to stand for")
        call fc loc (fullname target.def) lowered (length params) target.type xs

      -- What an IO primitive gives besides the next world, as many values
      -- as its action gives: for none, the unit its `IORes` holds, the one
      -- constructor of its value's type; for one, that value.
      gives : {0 count : Nat} -> FC -> IOAction i count -> Con 2 -> Front (IOGives count)
      gives fc a res = case actionGives a of
        GivesNone => GivesUnit <$> onlyCon fc 0 (Data.Vect.index 0 res.fields).type
        GivesOne => pure GivesValue

      -- A pure primitive the registry lists, on the call's arguments and
      -- then the literals the call does not supply, as many as its
      -- operands, of the call's result type, read in this scope: a result
      -- an erased argument indexes (the bound of a numeral a natural
      -- becomes) is typed at the term the call gives it.
      pureCall : FC -> Loc -> Maybe Shown -> Nat -> PureOp -> List Lit -> ClosedTerm -> List (Arg vars nv) ->
                 Front (Term nv)
      pureCall fc loc lowered arity p lits ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner arity ty (argValues (take arity xs))
        let Yes counted = decEq (Runtimes kinds + length lits) p.arity
          | No _ => internal fc ("the primitive of " ++ show name ++ " given " ++ show (Runtimes kinds) ++
                                 " runtime arguments and " ++ show (length lits) ++ " literals, of its " ++
                                 show p.arity ++ " operands")
        given <- arguments loc kinds (take arity xs)
        result <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
        finish loc kinds arity given
               (MkMaker (\ys => PrimApp loc (replace {p = Prim} (sym counted) (Op p.op result made)) lowered
                                  (ys ++ map (Literal loc) (fromList lits))))
               resTy xs

      -- An action's operands and its world, from a call's runtime
      -- arguments, the world last, and the literals the call does not
      -- supply (a new buffer's zero byte), which follow the others: as many
      -- as the action takes, which the registry's row and the definition's
      -- type agree on here, once, or nothing where they do not.
      effectOperands : Loc -> (r, operands : Nat) -> List Lit ->
                       Maybe ({0 m : Nat} -> Vect r (Term m) -> (Vect operands (Term m), Term m))
      effectOperands loc (S k) operands lits = case decEq (k + length lits) operands of
        Yes counted => Just (\ys => rewrite sym counted in (init ys ++ map (Literal loc) (fromList lits), last ys))
        No _ => Nothing
      effectOperands loc Z _ _ = Nothing

      -- An IO primitive the registry lists, an effect on the call's
      -- arguments and the literals it does not supply, ordered by its
      -- world, giving the `IORes` of the call's result type.
      ioCall : FC -> Loc -> Nat -> SomeAction -> List Lit -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      ioCall fc loc arity (MkSomeAction {operands} a) lits ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner arity ty (argValues (take arity xs))
        res <- onlyCon fc 2 !(coreType fc ctx.owner ValueType !(normaliseClosed resTy))
        what <- gives fc a res
        given <- arguments loc kinds (take arity xs)
        let Just split = effectOperands loc (Runtimes kinds) operands lits
          | Nothing => internal fc ("the IO primitive of " ++ show name ++ " given " ++ show (Runtimes kinds) ++
                                    " runtime arguments and " ++ show (length lits) ++ " literals, of its " ++
                                    show operands ++ " operands and the world")
        finish loc kinds arity given (MkMaker (\ys => (\(os, w) => Effect loc a what os w res) (split ys))) resTy xs

      -- The type arguments of a call, in order.
      typeParams : List PKind -> List ClosedTerm
      typeParams (TypeParam t :: ks) = t :: typeParams ks
      typeParams (_ :: ks) = typeParams ks
      typeParams [] = []

      -- The Idris type of a runtime argument a call gives.
      runtimeType : PKind -> Maybe ClosedTerm
      runtimeType (ValueParam _ _ t) = Just t
      runtimeType _ = Nothing

      -- An array operation: IO, in the world's order, giving the `IORes`
      -- of the call's result type, at the rank of the array its type
      -- takes, one size or index per dimension.
      arrayCall : FC -> Loc -> Nat -> ArrayAccess -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      arrayCall fc loc arity access ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        res <- onlyCon fc 2 !(coreType fc ctx.owner ValueType !(normaliseClosed resTy))
        let Just rank = accessRank access (pred (Runtimes kinds))
          | Nothing => internal fc ("the array access " ++ show name ++ " given " ++ show (Runtimes kinds) ++
                                    " runtime arguments, which no rank of an array takes")
        what <- gives fc (Accesses access rank) res
        let Just split = effectOperands loc (Runtimes kinds) (accessOperands access rank) []
          | Nothing => internal fc ("the array access " ++ show name ++ " given " ++ show (Runtimes kinds) ++
                                    " runtime arguments, of its operands and the world")
        finish loc kinds arity given
               (MkMaker (\ys => (\(os, w) => Effect loc (Accesses access rank) what os w res) (split ys))) resTy xs

      -- A primitive the registry lists for a foreign definition, on the
      -- call's arguments and then the literals the call does not supply:
      -- a handle's test for null is a comparison with the null handle.
      primCall : FC -> Loc -> Maybe Shown -> Nat -> ((k ** Prim k), List Lit) -> ClosedTerm -> List (Arg vars nv) ->
                 Front (Term nv)
      primCall fc loc lowered arity ((k ** p), lits) ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner arity ty (argValues (take arity xs))
        let Yes counted = decEq (Runtimes kinds + length lits) k
          | No _ => internal fc ("the primitive of " ++ show name ++ " given " ++ show (Runtimes kinds) ++
                                 " runtime arguments and " ++ show (length lits) ++ " literals, of its " ++
                                 show k ++ " operands")
        given <- arguments loc kinds (take arity xs)
        finish loc kinds arity given
               (MkMaker (\ys => PrimApp loc (replace {p = Prim} (sym counted) p) lowered
                                  (ys ++ map (Literal loc) (fromList lits))))
               resTy xs

      -- The constructors of a snoc list of naturals (`Extents`, `Index`),
      -- in tag order, the order the library declares them in: the empty
      -- one and the snoc of the rest and the natural.
      snocCons : FC -> Ty -> Front Snocs
      snocCons fc (DataT inst _) = do
        st <- getState
        let Just decl = familyOf inst st
          | Nothing => internal fc ("extents or coordinates of an undeclared type " ++ show inst)
        let [(0 ** lin), (2 ** snoc)] = decl.cons
          | _ => internal fc ("extents or coordinates of " ++ show inst ++ ", which is not a snoc list of naturals")
        pure (MkSnocs lin snoc)
      snocCons fc t = internal fc ("extents or coordinates of type " ++ show t)

      -- Does a new array of this type hold a dynamic dimension past its
      -- first `r` axes, in its cells? A tabulation is given the extents of
      -- the axes it tabulates, and the extents of its cells only by their
      -- types: nothing else holds them before the first cell is made, nor
      -- when the array is empty. A record element holds its own fields,
      -- whatever their extents.
      dynamicCells : Nat -> Ty -> Bool
      dynamicCells r (TensorT ds _) = any dynamicDim (drop r ds)
      dynamicCells _ _ = False

      -- A tabulation of cells whose extents no type fixes is refused by
      -- name: the cells' extents would have to come from a cell.
      cellsFixed : FC -> Ty -> Nat -> Front ()
      cellsFixed fc t r = when (dynamicCells r t) $
        reject fc ctx.owner ValueType ("an array of cells whose extents no type fixes: " ++ show t)

      arrayTerm : {0 count : Nat} -> FC -> Loc -> ArrayPrim -> Ty -> Vect count Binder -> List Ty -> List ClosedTerm ->
                  Front (Maker count)
      arrayTerm fc loc g rt bs typeArgs idrisTypes = case (g, map (.type) bs) of
        (AShape, [xTy]) => do
          a <- theElement
          s <- snocCons fc rt
          let r = minus (rank xTy) (rank a)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [x] =>
                  snocValue loc s (map (\j => Tensor loc (NatT IOpaque) (Extent j (Var loc x))) (axesOf r))))
        (ATabulate, [eTy, FunT (MkBinder _ idxTy) bTy]) => do
          eSnoc <- snocCons fc eTy
          iSnoc <- snocCons fc idxTy
          let r = minus (rank rt) (rank bTy)
          cellsFixed fc rt r
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [e, f] =>
                  apart loc eSnoc r e (\ren', ds =>
                              Tabulate loc rt (map (Var loc) (fromList ds))
                                (App loc (Var loc (Free {k = length ds} (ren' f)))
                                         (snocValue loc iSnoc (map (Var loc . Bound) (toList (Data.Vect.allFins (length ds)))))))))
        (AIndex, [xTy, iTy]) => do
          iSnoc <- snocCons fc iTy
          let r = minus (rank xTy) (rank rt)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [x, i] =>
                  apart loc iSnoc r i (\ren', cs => Tensor loc rt (Extract (Var loc (ren' x)) (map (Var loc) cs)))))
        (AUpdate, [xTy, iTy, vTy]) => insert xTy iTy vTy bs
        (AWrite, [lTy, iTy, vTy]) => do
          (writing, ds, e) <- cellOf lTy
          iSnoc <- snocCons fc iTy
          let r = minus (length ds) (rank vTy)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [l, i, v] =>
                  opened loc writing l (\ren', x =>
                    apart loc iSnoc r (ren' i) (\ren'', cs =>
                      ConApp loc writing []
                        [Tensor loc (TensorT ds e) (Insert (Var loc (ren'' x)) (Var loc (ren'' (ren' v))) (map (Var loc) cs))]))))
        (AFoldLast, [FunT (MkBinder _ accTy) (FunT (MkBinder _ elTy) _), _, _]) => pure (reduce FoldLast accTy elTy bs)
        (AScanLast, [FunT (MkBinder _ accTy) (FunT (MkBinder _ elTy) _), _, _]) => pure (reduce ScanLast accTy elTy bs)
        (AReshape, [eTy, _]) => do
          a <- theElement
          eSnoc <- snocCons fc eTy
          let r = minus (rank rt) (rank a)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [e, x] =>
                  apart loc eSnoc r e (\ren', es => Tensor loc rt (Reshape (Var loc (ren' x)) (map (Var loc) es)))))
        -- The cells put back with the extents given, not the ones the
        -- cells hold: an empty frame has no cell to read them from, so the
        -- array is flattened and expanded to the frame's extents and then
        -- the given ones.
        (AMerge, [eTy, xTy]) => do
          a <- theElement
          eSnoc <- snocCons fc eTy
          cellAxes <- cellRank
          let frame = minus (minus (rank xTy) (rank a)) cellAxes
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [e, x] =>
                  apart loc eSnoc cellAxes e (\ren', es =>
                    Tensor loc rt (Reshape (Var loc (ren' x))
                                    (map (\j => Tensor loc (NatT IOpaque) (Extent j (Var loc (ren' x)))) (axesOf frame)
                                     ++ map (Var loc) es)))))
        (ATranspose, [xTy]) => do
          a <- theElement
          let axis = minus (lastAxis xTy a) 1
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [x] => Tensor loc rt (Transpose axis (Var loc x))))
        (ATake, [_, xTy]) => do
          a <- theElement
          let axis = lastAxis xTy a
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [k, x] => Tensor loc rt (Take axis (Var loc k) (Var loc x))))
        (ADrop, [_, xTy]) => do
          a <- theElement
          let axis = lastAxis xTy a
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [k, x] => Tensor loc rt (Drop axis (Var loc k) (Var loc x))))
        (AConcat, [xTy, _]) => do
          a <- theElement
          let axis = lastAxis xTy a
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [x, y] => Tensor loc rt (Concat axis (Var loc x) (Var loc y))))
        (APad, [_, _, vTy, xTy]) => do
          let axis = lastAxis xTy vTy
              front = alongAxis axis xTy
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [lo, hi, v, x] =>
                  Tensor loc rt (Concat axis
                    (Tensor loc front (Concat axis (copies xTy axis (Var loc x) (Var loc lo) (Var loc v)) (Var loc x)))
                    (copies xTy axis (Var loc x) (Var loc hi) (Var loc v)))))
        (AWithArray, [eTy, vTy, FunT (MkBinder _ lTy) _]) => do
          (writing, ds, e) <- cellOf lTy
          eSnoc <- snocCons fc eTy
          let r = minus (length ds) (rank vTy)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [ex, v, k] =>
                  apart loc eSnoc r ex (\ren', ns =>
                    App loc (Var loc (ren' k))
                        (ConApp loc writing [] [filled ds e (map (Var loc) ns) (Var loc (ren' v))]))))
        -- The element is read at the type of the held array's cells and
        -- given at the element's, which may fix extents the cells leave to
        -- their values.
        (ARead, [lTy, iTy]) => do
          (writing, ds, e) <- cellOf lTy
          a <- theElement
          iSnoc <- snocCons fc iTy
          res <- onlyCon fc 2 rt
          let r = minus (length ds) (rank a)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [l, i] =>
                  opened loc writing l (\ren', x =>
                    apart loc iSnoc r (ren' i) (\ren'', cs =>
                      ReadBack loc (cellAfter r ds e) (Var loc (ren'' x)) (map (Var loc) cs)
                        (ConApp loc res [] [ Var loc (Bound {k = 2} FZ)
                                           , ConApp loc writing [] [Var loc (Bound {k = 2} (FS FZ))]])))))
        (AThaw, [_, FunT (MkBinder _ lTy) _]) => do
          (writing, ds, e) <- cellOf lTy
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [x, k] =>
                  App loc (Var loc k) (ConApp loc writing [] [fresh ds e (Var loc x)])))
        (ALShape, [lTy]) => do
          (writing, ds, _) <- cellOf lTy
          res <- onlyCon fc 2 rt
          a <- theElement
          s <- snocCons fc (Data.Vect.index 0 res.fields).type
          let r = minus (length ds) (rank a)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [l] =>
                  opened loc writing l (\ren', x =>
                    ExtentsBack {k = r} loc (Var loc x)
                      (ConApp loc res []
                         [ snocValue loc s (toList (map (\j => Var loc (Bound (weaken j))) (allFins r)))
                         , ConApp loc writing [] [Var loc (Bound (last {n = r}))]]))))
        -- The grown array fills a cell of the result's type, as long on the
        -- last axis as the result's shape says.
        (AGrow, [_, vTy, lTy]) => do
          (writing, ds, e) <- cellOf lTy
          (grown, gds, _) <- cellOf rt
          let arrTy = TensorT ds e
              axis = lastAxis arrTy vTy
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [k, v, l] =>
                  opened loc writing l (\ren', x =>
                    ConApp loc grown []
                      [Tensor loc (TensorT gds e)
                         (Concat axis (Var loc x) (copies arrTy axis (Var loc x) (Var loc (ren' k)) (Var loc (ren' v))))])))
        (ATabulateIO, [eTy, FunT (MkBinder _ idxTy) (FunT (MkBinder _ WorldT) step@(DataT _ _))]) => do
          FunT _ done@(DataT _ _) <- pure rt
            | _ => internal fc "a world-ordered tabulation whose result is no action"
          stepCon <- onlyCon fc 2 step
          doneCon <- onlyCon fc 2 done
          let arrTy = (Data.Vect.index 0 doneCon.fields).type
          a <- theElement
          eSnoc <- snocCons fc eTy
          iSnoc <- snocCons fc idxTy
          let r = minus (rank arrTy) (rank a)
          cellsFixed fc arrTy r
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [e, act] =>
                  apart loc eSnoc r e (\ren', ds =>
                                Lam noLoc (shown "world") (MkBinder Once WorldT)
                                  (TabulateIO loc arrTy (map (Var loc . FS) (fromList ds)) (Var loc FZ)
                                     (App loc (App loc (Var loc (Free {k = S (length ds)} (FS (ren' act))))
                                                       (snocValue loc iSnoc
                                                          (map (Var loc . Bound . weaken) (toList (Data.Vect.allFins (length ds))))))
                                              (Var loc (Bound (last {n = length ds}))))
                                     stepCon doneCon))))
        _ => internal fc ("the array language's " ++ show name ++ " at operand types it does not have")
        where
          -- The constructor of a linear array's cell, and the dimensions
          -- and element of the array it holds.
          cellOf : Ty -> Front (Con 1, List Dim, Ty)
          cellOf t = do
            c <- onlyCon fc 1 t
            case (Data.Vect.head c.fields).type of
              TensorT ds e => pure (c, ds, e)
              held => internal fc ("a linear array whose cell holds a value of type " ++ show held)

          -- The type of the cells after the first `r` axes of an array of
          -- `ds` of `e`: its element when they are all its axes.
          cellAfter : Nat -> List Dim -> Ty -> Ty
          cellAfter r ds e = case drop r ds of
            [] => e
            cds => TensorT cds e

          -- A new array of `ds` of `e` whose leading extents are given and
          -- whose every cell is `v`: the cells' extents are `v`'s, read off
          -- it, so no type need fix them, and every slot is written once.
          filled : {0 m : Nat} -> List Dim -> Ty -> List (Term m) -> Term m -> Term m
          filled ds e ns v =
            let es = ns ++ map (\j => Tensor loc (NatT IOpaque) (Extent j v)) (axesOf (minus (length ds) (length ns)))
                v' = weakenUnder (length es) v
                cell = map (Var loc . Bound) (drop (length ns) (toList (Data.Vect.allFins (length es))))
                body = case cell of
                         [] => v'
                         _ => Tensor loc e (Extract v' cell)
            in Tabulate loc (TensorT ds e) (fromList es) body

          -- A new array of `ds` of `e` holding every element of `x`, in
          -- slots of its own: what a linear array made of an array holds,
          -- so that no other value reaches them while it writes them.
          fresh : {0 m : Nat} -> List Dim -> Ty -> Term m -> Term m
          fresh ds e x =
            let es = map (\j => Tensor loc (NatT IOpaque) (Extent j x)) (axesOf (length ds))
            in Tabulate loc (TensorT ds e) (fromList es)
                 (Tensor loc e (Extract (weakenUnder (length es) x)
                                        (map (Var loc . Bound) (toList (Data.Vect.allFins (length es))))))

          -- The one type argument of a call that has one: the element or
          -- the cell.
          theElement : Front Ty
          theElement = case typeArgs of
            [a] => pure a
            _ => internal fc ("the array language's " ++ show name ++ " without its one type argument")

          -- How many axes the cells of an array of arrays take, read from
          -- the Idris type of the array, the last runtime argument: a
          -- tensor's type holds the frame's axes and the cells' as one run,
          -- so where one ends is read where Idris still tells them apart.
          cellRank : Front Nat
          cellRank = do
            Just outer <- pure (last' idrisTypes)
              | Nothing => internal fc ("the array language's " ++ show name ++ " without its array")
            Just (_, cellTy) <- arrayView outer
              | Nothing => internal fc ("the array language's " ++ show name ++ " given no array of arrays")
            Just (c, _) <- arrayView cellTy
              | Nothing => internal fc ("the array language's " ++ show name ++ " given no array of arrays")
            sp <- spineOf fc ctx.owner c
            pure (length sp.axes)

          -- The shape's last axis of an array whose cell has the type given.
          lastAxis : Ty -> Ty -> Nat
          lastAxis xTy cellTy = minus (minus (rank xTy) 1) (rank cellTy)

          -- An array like one of type `xTy` with the length of its axis
          -- `a` left to its value.
          alongAxis : Nat -> Ty -> Ty
          alongAxis a (TensorT ds e) = TensorT (zipWith (\j, d => if j == a then Dynamic else d) (axesOf (length ds)) ds) e
          alongAxis a t = t

          -- `n` copies of the cell `v` along axis `a` of an array like `x`,
          -- of type `xTy`, its other axes `x`'s, the cell's among them: a
          -- new array of every element, each copy its own, whatever the
          -- element holds. A pad, and a growth, is the array joined to
          -- such copies, so that every slot of the result is written once.
          copies : {0 m : Nat} -> Ty -> Nat -> (x, n, v : Term m) -> Term m
          copies xTy a x n v =
            let es = map (\j => if j == a then n else Tensor loc (NatT IOpaque) (Extent j x)) (axesOf (rank xTy))
                v' = weakenUnder (length es) v
                cell = map (Var loc . Bound) (drop (S a) (toList (Data.Vect.allFins (length es))))
                body = case (cell, xTy) of
                         ([], _) => v'
                         (_, TensorT _ e) => Tensor loc e (Extract v' cell)
                         _ => v'
            in Tabulate loc (alongAxis a xTy) (fromList es) body

          insert : Ty -> Ty -> Ty -> Vect 3 Binder -> Front (Maker 3)
          insert xTy iTy vTy three = do
            iSnoc <- snocCons fc iTy
            let r = minus (rank xTy) (rank vTy)
            pure $ MkMaker (\ys => bindEach loc three ys (\ren, [x, i, v] =>
                    apart loc iSnoc r i (\ren', cs =>
                      Tensor loc rt (Insert (Var loc (ren' x)) (Var loc (ren' v)) (map (Var loc) cs)))))

          reduce : Reduction -> Ty -> Ty -> Vect 3 Binder -> Maker 3
          reduce red accTy elTy three = MkMaker (\ys => bindEach loc three ys (\ren, [g, z, x] =>
            Reduce loc red accTy elTy rt (Var loc z) (Var loc x)
              (App loc (App loc (Var loc (Free {k = 2} g)) (Var loc (Bound {k = 2} FZ)))
                       (Var loc (Bound {k = 2} (FS FZ))))))
      -- A function of the array language: the tensor operations of its
      -- sequential meaning, over its runtime arguments bound once each in
      -- order; below its arity, a closure over the missing ones. A rank is
      -- read from the types of the operands and the result, never from the
      -- order of the implicits.
      generating : FC -> Loc -> ArrayPrim -> Nat -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      generating fc loc g arity ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        rt <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
        typeArgs <- traverse (\t => coreType fc ctx.owner ValueType !(normaliseClosed t)) (typeParams kinds)
        mk <- arrayTerm fc loc g rt (runtimeBinders kinds) typeArgs (mapMaybe runtimeType kinds)
        finish loc kinds arity given mk resTy xs

      -- A call of a definition the registry's hooks lower, whatever
      -- declares it, or `otherwise` when no hook does. A hook for the
      -- identity on the one runtime argument, the last its type takes
      -- (the pointer casts, an array's `nest`); the rest are proofs and
      -- types. By the type, not the clause: `prim__castPtr = believe_me`
      -- binds only its erased type. A function of the array language is one by
      -- its type too: a bodiless declaration takes what its type says.
      hooked : FC -> Loc -> Name -> Maybe Shown -> Nat -> Defined -> ClosedTerm -> Hooks -> Front (Term nv) ->
               Front (Term nv)
      hooked fc loc full lowered arity d ty hs otherwise =
        let constant = \v => applyOver ctx env fc loc (pure (show full)) v (Just ty) args in
        fromMaybe otherwise $
              map (reject fc ctx.owner Deprecated) hs.deprecated
          <|> map (\m => natOperation fc loc lowered d.library m arity ty args) hs.natOperation
          <|> map (\p => builderCall fc loc lowered arity p ty args) hs.builds
          <|> map (\g => generating fc loc g (binders ty) ty args) hs.generating
          <|> (if hs.identityOnLast then Just (identity fc loc d ty args) else Nothing)
          <|> map (\(p, lits) => pureCall fc loc lowered arity p lits ty args) hs.pureCall
          <|> map (\(p, lits) => ioCall fc loc arity p lits ty args) hs.ioCall
          <|> map (\p => arrayCall fc loc arity p ty args) hs.arrayCall
          <|> map (\p => primCall fc loc lowered arity p ty args) hs.primCall
          <|> map (constant . Literal loc) hs.handle
          <|> map (\q => aliasCall fc loc lowered q d.library args) hs.alias
          <|> map (constant . systemFact) hs.systemInfo
        where
          systemFact : SystemFact -> Term nv
          systemFact TargetOs = PrimApp loc (Op platformOsOp StrT Hold.Static) Nothing []
          systemFact BackendName = Literal loc (LStr codegenName)

||| An implementation the environment binds (`Static`), computed at run
||| time where the translation reaches it, as the term it is written as
||| (`implementationAt`, applied to nothing): a call of a definition Idris
||| does not prove ends runs there, eagerly, its divergence its call's.
export
computedAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             Ctx -> List (VarInfo (Fin nv)) -> FC -> ClosedTerm -> Maybe (Fin nv, Holes) -> Front (Term nv)
computedAt ctx env fc t held = implementationAt {vars = Scope.empty} asWritten start (sizeAccessible start) ctx env fc t held []
