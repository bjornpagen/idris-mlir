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
import IdrisMLIR.Frontend.Translate.Readings
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
||| a message; where it is; whether Idris found no missing case; the type
||| every leaf of its tree gives (`result`), its expected type, which a
||| lambda there that a polymorphic function's choice holds needs, its own
||| binders not saying it (`atType`), and its Core type, the function's
||| result as every call of it holds it (`resultType`), which a leaf is
||| translated at (`Expected`); the depth of the telescope where the term
||| stands (`depth`): the function's index parameters, then the erased
||| binders of each constructor whose alternative encloses it, as `Emit`
||| binds them, at which a field's type is read (`fieldsAt`) and a term's
||| value is typed (`termType`); what a value of that type is to the
||| choices, as the member table says of the definition applied to its
||| parameters (`givesAfter`), or the instance's to decide where no
||| definition is translated; and the request of the instance being
||| translated, the step's own: what it is an instance of, which an exit
||| reads (`exiting`), and its signature, the kinds it was classified at,
||| which a field taken apart where it is held reads (`Cases.heldHere`).
public export
record Ctx (kc : Nat) where
  constructor MkCtx
  owner : String
  fc : FC
  complete : Bool     -- Idris found no missing case
  result : ClosedTerm
  resultType : Ty
  depth : Nat
  resultHolding : Holding
  request : Request
  0 counts : length request.signature.kinds = kc

bestFC : Ctx kc -> FC -> FC
bestFC ctx fc = if isEmptyFC fc then ctx.fc else fc

||| What a term is translated at, as Idris's elaborator checked it: the
||| Core type its position expects of it (a parameter's binder, a `let`'s,
||| a definition's result at a leaf, a lambda's result in its body, a
||| suspension's value), which a lambda there is the closure of; or none,
||| at the head of an application and wherever no binder says one, where
||| the type is read off the term it becomes (`termType`).
public export
data Expected = ExpectedAt Ty | Synthesized

||| The Core type of a runtime variable, where its entry gives it.
export
coreTyOf : VarInfo kc sp a -> Maybe Ty
coreTyOf (Runtime _ t) = coreOf t
coreTyOf (Shaped _ t _ _) = Just t
coreTyOf _ = Nothing

||| What the environment knows of the types of the Core variables in scope:
||| each runtime variable's, as its entry gives it. It reads the entries
||| one by one, so a variable whose entry is at hand is typed by it instead.
scopeOf : StandsFor kc OfTerm vars (Fin nv) -> ScopeTypes nv
scopeOf env x = go (innermostFirst env)
  where
    go : List (VarInfo kc OfTerm (Fin nv)) -> Maybe Ty
    go [] = Nothing
    go (e@(Runtime y _) :: es) = if y == x then coreTyOf e else go es
    go (e@(Shaped y _ _ _) :: es) = if y == x then coreTyOf e else go es
    go (_ :: es) = go es

||| What a position that takes a parameter of this kind expects of the
||| term given there: its binder's type, where the parameter exists at run
||| time.
expectedBy : PKind -> Expected
expectedBy k = maybe Synthesized (\b => ExpectedAt b.type) (boundAtRuntime k)

||| The name of an Idris binder as Core keeps it, to name the value it
||| binds: a machine name (`{arg:12}`) by what it is, not by its counter.
export
binderName : Name -> Shown
binderName (NS _ n) = binderName n
binderName (MN s _) = shown s.text
binderName n = shown (show n)

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

||| What fills each slot of an array made of copies of a cell: the cell
||| itself, where no axis of the array follows those it is repeated along;
||| else the cell's element at the slot's coordinates past them, the cell an
||| array (`array`) of those axes.
data Fill : Type where
  WholeCell : Fill
  ElementOfCell : {r : Nat} -> (array : ArrayType r) -> Fill

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
      Case loc s.snoc.id.family x (Exhaustive (MkAlt s.snoc [shown "rest", shown "n"]
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
  Case loc writing.id.family x (Exhaustive (MkAlt writing [shown "elements"] (k (Free {k = 1}) (Bound {k = 1} FZ)) ::: []))

||| Each term bound by a `let` at the quantity of the parameter it is given
||| for, left to right, and the body built over the variables that hold
||| them, as many and in the same order, with the renaming of the scope
||| outside. A value used more than once, or in an order of its own, is
||| evaluated once, where the call put it; one Idris lets the callee use
||| once stays used once.
bindArguments : {0 m : Nat} -> Loc -> Vect r Binder -> Vect r (Term m) ->
           ({0 p : Nat} -> (Fin m -> Fin p) -> Vect r (Fin p) -> Term p) -> Term m
bindArguments loc bs ts k = go id bs ts k
  where
    -- Under the binders already made: `ren` takes the outer scope into the
    -- current one, and each term is renamed once, where it is bound.
    go : {0 p : Nat} -> (Fin m -> Fin p) -> Vect s Binder -> Vect s (Term m) ->
         ({0 q : Nat} -> (Fin p -> Fin q) -> Vect s (Fin q) -> Term q) -> Term p
    go ren [] [] k' = k' id []
    go ren (b :: bs') (t :: ts') k' =
      Let loc (shown "argument") (OfValue b.quantity) (rename ren t)
          (go (FS . ren) bs' ts' (\ren', vs => k' (ren' . FS) (ren' FZ :: vs)))

||| The compile-time value a parameter's kind gives, where a projection
||| reads its arguments: a type, an implementation, or nothing known.
compileTimeArg : PKind -> ClosedTerm
compileTimeArg (TypeParam t) = t
compileTimeArg (DictParam t _) = t
compileTimeArg (FormParam f) = f
compileTimeArg _ = Erased EmptyFC Placeholder

||| Is an argument a type or a compile-time value, which exists only where
||| what takes it erases it?
compileTime : StandsFor kc sp vars a -> TT vars -> Bool
compileTime env (Local _ _ idx p) = case lookupVar idx p env of
  TypeValue _ => True
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
headType : StandsFor kc sp vars a -> TT vars -> Maybe ClosedTerm
headType env (Local _ _ idx p) = case lookupVar idx p env of
  Runtime _ t => idrisOf t
  Shaped _ _ t _ => Just t
  _ => Nothing
headType env (TForce _ _ e) = case headType env e of
  Just (TDelayed _ _ t) => Just t
  _ => Nothing
headType _ _ = Nothing

||| A head as a message names it: a variable by its name.
headName : {vars : Scope} -> FC -> StandsFor kc sp vars a -> TT vars -> Front String
headName fc env (Local _ _ idx p) = pure (show (nameAt {idx} p))
headName fc env tm = showTT (closeWritten fc env tm)

||| A type or an erased value where a value exists at runtime. Idris's
||| quantity check admits one only where the type of what takes it erases
||| it, which is where the translation leaves it out; here nothing does.
inRuntime : {auto s : Ref TState TS} -> {vars : Scope} ->
            String -> FC -> StandsFor kc sp vars a -> TT vars -> Front b
inRuntime owner fc env tm = do
  what <- showTT (closeWritten fc env tm)
  reject fc owner ValueType (what ++ " in a runtime position")

||| The scope of a closed function type at an argument: the argument's
||| closed normal form where the scope mentions it, nothing where it does
||| not.
instantiate : {vars : Scope} ->
              FC -> StandsFor kc sp vars a -> TT [x] -> TT vars -> Front ClosedTerm
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
||| its translation at what its position expects, which the use that gives
||| it knows (`Expected`), and what it closes over as an implementation
||| (`holed`), each suspended there, so that no use translates a list
||| element.
record Arg (vars : Scope) (nv : Nat) where
  constructor MkArg
  written : TT vars
  translated : Expected -> Front (Term nv)
  held : Lazy (Front (Maybe (ClosedTerm, List1 (ClosedTerm, Front (Term nv)))))

||| An argument under a binder that binds nothing in Core: a compile-time
||| value, or another name for a variable.
overBinder : Arg vars nv -> Arg (x :: vars) nv
overBinder a = MkArg (weaken a.written) a.translated a.held

||| An argument under a binder that Core binds too, by a `let`.
underLet : Arg vars nv -> Arg (x :: vars) (S nv)
underLet a = MkArg (weaken a.written) (\ex => weakenUnder 1 <$> a.translated ex) (map weakened <$> Force a.held)
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
              StandsFor 0 OfTerm vs Nat -> TT vs -> Front (Maybe ClosedTerm)
    lambdas k ls env (Bind _ x (Lam _ rig p ty) sc) =
      lambdas (S k) (ls ++ [(x, rig, map (closeWritten EmptyFC env) p, closeWritten EmptyFC env ty)])
              (TypeValue (formal k) :: env) sc
    lambdas k ls env body = map (bound 0 ls) <$> bodyType ls (closeWritten EmptyFC env body)

||| What a marker of a settled term stands for.
data Stand : Nat -> Nat -> Type where
  ||| A variable in scope: the marker is bound as it is, with no `let`.
  AsVariable : VarInfo kc OfTerm (Fin nv) -> Stand kc nv
  ||| A runtime value, bound once by a `let` before the term.
  AsValue : Lazy (Front (Term nv)) -> Stand kc nv

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
argValueIn : {vars : Scope} ->
             StandsFor kc OfTerm vars (Fin nv) -> FC -> Arg vars nv -> Maybe ArgValue
argValueIn env fc x = Just (MkArgValue (unmarked <$> closeNormalise fc env x.written)
                                       (unmarked <$> solved (closeWritten fc env x.written))
                                       (offered x.written)
                                       (map (\(shape, held) => (unmarked shape, map fst held)) <$> Force x.held)
                                       (closeNormalise fc env x.written))
  where
    offered : TT vars -> Offer
    offered (Local _ _ idx p) = case lookupVar idx p env of
      Static _ _ _ => AnImplementation
      BoundHere _ _ => AnImplementation
      _ => AValue
    offered _ = AValue

||| What a call gives each parameter of its callee that exists at run
||| time, among those its arguments reach, in order: the term the argument
||| at that position gives at that parameter's kind.
givenTo : (ks : List PKind) -> (args : List (PKind -> Front (Term nv))) ->
          Front (Vect (Runtimes (take (length args) ks)) (Term nv))
givenTo [] [] = pure []
givenTo [] (_ :: _) = pure []
givenTo (_ :: _) [] = pure []
givenTo (k :: ks) (a :: as) = consAt (boundAtRuntime k) (a k) (givenTo ks as)

||| A compile-time form of type `t` applied where no definition of the
||| program applies it, as the member at this use's types it is (`AtUse`):
||| the instance that applies the form at the use's own types, keyed by the
||| form's type and the form (`form`, what the call knows of it), and each
||| argument as the form's type takes it, its signature read in this scope
||| (`atCall`), so the call gives as many arguments as it takes, by type.
||| The use takes every argument the application gives, all of which the
||| type takes, as Idris checked the application, so no instance takes more
||| than the type does. The form's value at run time (`value`) is a choice,
||| which the call dispatches on, each arm the member at the use's types
||| (`Choices.calleeAt`), or the values a fixed form closes over.
applyAtUse : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
             Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> Loc -> (t : ClosedTerm) -> (form : ArgValue) ->
             (value : Maybe (Term nv)) -> List (Arg vars nv) -> Front (Term nv)
applyAtUse ctx env fc loc t form value args = do
  ty <- applicationType
  let vals = Just (known t AValue) :: Just form :: map (argValueIn env fc) args
  kinds <- classifyKeys fc ctx.owner (requestName (AtUse (length args))) (2 + length args) ty vals
  sig <- calleeAt (choicesIn kinds) fc ctx.owner (AtUse (length args)) kinds
  called <- atCall fc ctx.owner vals sig
  let sources = typeGiven :: formGiven :: map useGiven args
  given <- givenTo called.kinds sources
  is <- callIndices called.kinds vals
  let mk = recount called.sameCount (MkMaker (\ys => Call loc sig.callee Nothing is ys))
  pure (etaExpand loc (runtimeBinders (drop (length sources) called.kinds)) (substTy is sig.callee.result)
                  (recount (runtimesSplit (length sources) called.kinds) mk) given)
  where
    -- The form's type is a type: where a parameter takes it at run time it
    -- is translated as any type there is.
    typeGiven : PKind -> Front (Term nv)
    typeGiven _ = inRuntime ctx.owner fc env (embedClosed {vars} t)

    -- The form's value, where its parameter exists at run time. A form
    -- bound as a compile-time value that its type reads as a run-time
    -- one (a field a definition Idris does not prove ends computes) has
    -- none here: inside a settled term nothing computes it again.
    formGiven : PKind -> Front (Term nv)
    formGiven _ = case value of
      Just v => pure v
      Nothing => do
        written <- showTT !(form.written)
        reject fc ctx.owner RuntimeClosure
               ("a function computed at run time, applied inside a settled term that settles it again: " ++ written)

    -- An argument as its kind takes it: a value or a choice as itself, an
    -- implementation that closes over runtime values as the values, held
    -- as one.
    useGiven : Arg vars nv -> PKind -> Front (Term nv)
    useGiven x (DictParam _ (Just _)) = do
      -- The classification read these values to give the argument this
      -- kind, which keeps their types, not them: read again here.
      Just (_, held) <- x.held
        | Nothing => internal fc "the values an implementation closes over are gone"
      pack fc ctx.owner loc !(valuesOf held)
    useGiven x k = x.translated (expectedBy k)

||| A value applied to arguments, over the Idris type of the value where it
||| is known: an argument at a binder of quantity 0 is not passed, since
||| the value takes none there at runtime, and any other is applied. A
||| polymorphic function held at run time is a value of its type's choice,
||| whose members each use calls at its own types: applied here, where it
||| is held, it is a use of it, the member at the use's types
||| (`applyAtUse`). Past the binders the type shows, an argument is a
||| runtime value, and a type or an erased value there is refused, naming
||| the head (`what`). Each application is at the function type the value's
||| Core type (`core`) is, the type the value is made at, and gives a value
||| of its result, which the next one applies; its argument is translated
||| at the parameter's type.
applyOver : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> Loc -> Front String ->
            Term nv -> (core : Maybe Ty) -> Maybe ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
applyOver ctx env fc loc what f core _ [] = pure f
applyOver ctx env fc loc what f core fty (x :: xs) = do
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
        Erased => applyOver ctx env fc loc what f core (Just next) xs
        Used _ => applied (Just next)
    _ => do
      when (compileTime env x.written) $ do
        arg <- showTT (closeWritten fc env x.written)
        reject fc ctx.owner ValueType
               (arg ++ " in a runtime position: an argument of " ++ !what ++ ", whose type is not known here")
      applied Nothing
  where
    -- Kept: Idris checked the application, so the value is a function's
    -- wherever an argument is given, and a Core function type is what a
    -- runtime binder of its Idris type becomes; but the Core type is a
    -- `Ty`, which does not say so, read apart from the Idris type it
    -- comes from, and a value a settled term computes whose term states
    -- no type (`KnownTypes.Untyped`) has none.
    applied : Maybe ClosedTerm -> Front (Term nv)
    applied next = case core of
      Just (FunT a r) => do
        v <- x.translated (ExpectedAt a.type)
        applyOver ctx env fc loc what (App loc a r f v) (Just r) next xs
      _ => do
        named <- what
        internal fc ("an application of " ++ named ++ ", whose Core type " ++ show core ++ " is no function's")

||| The type of the value a `Delay` suspends, as Idris checked it (`TDelay`
||| holds it), at the extents a suspension's type holds: every one dynamic,
||| as `coreType` makes a `Lazy` type's.
delayedType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
              Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> TT vars -> Front Ty
delayedType ctx env fc ty = do
  known <- closeNormalise fc env ty
  dynamicDims <$> coreType (bestFC ctx fc) ctx.owner ValueType known

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
  ||| A term in scope, translated at what its position expects (`ex`).
  export
  term : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
         Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> (ex : Expected) -> TT vars -> Front (Term nv)
  term ph w acc ctx env ex (Local fc r idx p) = applyVariable ph w acc ctx env fc fc r idx p []
  term ph w acc ctx env ex tm@(PrimVal fc c) = do
    loc <- toLoc (bestFC ctx fc)
    case constantLit c of
      Just l => pure (Literal loc l)
      Nothing => case c of
        -- A trusted library forges a world (`unsafePerformIO`); the
        -- profile has rejected the user's (Profile.checkReachable).
        WorldVal => pure (NewWorld loc)
        PrT _ => inRuntime ctx.owner (bestFC ctx fc) env tm
        _ => reject (bestFC ctx fc) ctx.owner ValueType ("constant " ++ show c)
  term ph w acc ctx env ex tm@(TType fc _) = inRuntime ctx.owner (bestFC ctx fc) env tm
  term ph w acc ctx env ex tm@(Erased fc _) = inRuntime ctx.owner (bestFC ctx fc) env tm
  term ph w acc ctx env ex tm@(Bind fc _ (Pi {}) _) = inRuntime ctx.owner (bestFC ctx fc) env tm
  term ph w acc ctx env ex tm@(Bind fc x (Let lfc rig val ty) sc) = case delayedLets tm of
    -- The `let`s around a `Delay` the elaborator inserted for a `Lazy`
    -- expected type move into it (`delayedLets`), into the innermost of a
    -- chain of them: the suspensions, outermost first, then the `let`s,
    -- then what the last `Delay` delays. A `Delay` the source wrote keeps
    -- its `let`s outside, which eager evaluation runs first.
    Just _ => do
      (suspensions, inner) <- letIn ph w acc ctx env fc x rig val ty (\env' => delayed ph w acc ctx env' ex sc)
      pure (foldr (\(l, t), body => Suspend l t body) inner suspensions)
    Nothing => (\((), t) => t) <$> letIn ph w acc ctx env fc x rig val ty (\env' => ((),) <$> term ph w acc ctx env' ex sc)

  -- A lambda's binder of quantity 0 is no parameter at runtime: the lambda
  -- is its body, which takes the runtime arguments after it, as its type
  -- does once the binder is left out, at what the lambda is expected at. A
  -- lambda is a closure, whose type is one for every extent its values are
  -- made at (`coreType`), so its binder is too: an array parameter's
  -- extents are its argument's, each dynamic, whatever the type at this
  -- lambda fixes. Its result is the one its position's function type gives
  -- (checked, as Idris's elaborator checked it there), its body translated
  -- at it; where its position states no function type, the one its body's
  -- term states (`lambdaResult`).
  term ph w acc ctx env ex (Bind fc x (Lam lfc rig _ ty) sc) =
    case use rig of
      Erased => term ph w acc ctx (TypeValue (Erased fc Placeholder) :: env) ex sc
      Used q => do
        loc <- toLoc (bestFC ctx fc)
        known <- closeNormalise fc env ty
        b <- closureBinder <$> coreBinder (bestFC ctx fc) ctx.owner ValueType q known
        let inner = under {k = 1} [Runtime FZ (BothTypes b.type known)] env
        case ex of
          ExpectedAt (FunT _ r) => Lam loc (binderName x) b r <$> term ph w acc ctx inner (ExpectedAt r) sc
          _ => do
            body <- term ph w acc ctx inner Synthesized sc
            r <- lambdaResult (bestFC ctx fc) (termType ctx.depth (scopeOf inner) body)
            pure (Lam loc (binderName x) b r body)
  term ph w acc ctx env ex (TDelay fc _ ty arg) = suspend ph w acc ctx env fc ty arg
  -- A force gives the value its operand's suspension holds, of the type its
  -- operand's own gives (`forcedType`).
  term ph w acc ctx env ex (TForce fc _ arg) = do
    loc <- toLoc (bestFC ctx fc)
    operand <- term ph w acc ctx env Synthesized arg
    let suspension = case arg of
                       Local _ _ idx p => coreTyOf (lookupVar idx p env)
                       _ => termType ctx.depth (scopeOf env) operand
    value <- forcedType (bestFC ctx fc) ex suspension
    pure (Resume loc value operand)
  term ph w acc ctx env ex tm@(TDelayed fc _ _) = inRuntime ctx.owner (bestFC ctx fc) env tm
  term ph w acc ctx env ex (Meta fc n i margs) = entered ph w acc ctx env ex fc fc n i margs []
  term ph w acc ctx env ex (As fc _ _ pat) = term ph w acc ctx env ex pat
  term ph w acc ctx env ex (App fc f a) = spine ph w acc ctx env ex fc f [argOf ph w acc ctx env fc a]
  term ph w acc ctx env ex (Ref fc nt n) = applyRef {vars} ph w acc ctx env ex fc fc nt n []
  -- A pattern binder: TT admits one in any term, and Idris's elaborator
  -- keeps them to left-hand sides. The checked module's right-hand side
  -- is where the frontend first reads a term, so one there is refused, as
  -- the compiled module it is.
  term ph w acc ctx env ex (Bind fc _ _ _) =
    reject (bestFC ctx fc) ctx.owner CompiledModule "a pattern binder in a right-hand side"

  -- Kept: the result of a lambda whose position states no function type
  -- (an argument of a value whose type the scope does not give, a value a
  -- settled term computes) is the one its body's term states, a closure's
  -- with its extents dynamic; a body that never returns states none, and
  -- the type its position would have given is the one the translation
  -- does not hold there.
  lambdaResult : FC -> Maybe Ty -> Front Ty
  lambdaResult fc (Just t) = pure (dynamicDims t)
  lambdaResult fc Nothing = internal fc "the result type of a lambda whose body never returns, where nothing expects a function"

  -- Kept: the value a force gives is of the type its operand's suspension
  -- holds, which the operand's variable's binder or its own term states;
  -- where neither does (an operand that never returns), the type the
  -- force's position expects. Idris checked the operand a `Lazy`, but the
  -- Core type read for it is a `Ty`, which does not say so.
  forcedType : FC -> Expected -> Maybe Ty -> Front Ty
  forcedType fc _ (Just (LazyT t)) = pure t
  forcedType fc (ExpectedAt t) Nothing = pure t
  forcedType fc _ suspension = internal fc ("a force of a value whose Core type " ++ show suspension ++ " is no suspension's")

  ||| A chain of `let`s and `Delay`s, read as `delayedLets` moves the `let`s:
  ||| the location and the value's type (`delayedType`) of each `Delay`
  ||| met, outermost first, and the `let`s around what the last one delays,
  ||| each bound where it is met, so that every part translated is a part
  ||| of the chain.
  delayed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> TT vars -> Front (List (Loc, Ty), Term nv)
  delayed ph w acc ctx env ex (TDelay dfc _ ty arg) = do
    loc <- toLoc (bestFC ctx dfc)
    t <- delayedType ctx env dfc ty
    (suspensions, inner) <- delayed ph w acc ctx env (ExpectedAt t) arg
    pure ((loc, t) :: suspensions, inner)
  delayed ph w acc ctx env ex (Bind fc x (Let lfc rig val ty) sc) =
    letIn ph w acc ctx env fc x rig val ty (\env' => delayed ph w acc ctx env' ex sc)
  delayed ph w acc ctx env ex tm = ([],) <$> term ph w acc ctx env ex tm

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
          Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> (x : Name) -> RigCount -> TT vars -> TT vars ->
          ({0 m : Nat} -> StandsFor kc OfTerm (x :: vars) (Fin m) -> Front (r, Term m)) -> Front (r, Term nv)
  letIn ph w acc ctx env fc x rig val ty body =
    case use rig of
      Erased => body (TypeValue (Erased fc Placeholder) :: env)
      Used q => do
        loc <- toLoc (bestFC ctx fc)
        known <- closeNormalise fc env ty
        True <- polymorphicType known
          | False => runtimeLet q loc known
        impl <- solved (closeWritten fc env val)
        if not !(runtimeDependent impl)
          then do
            FixedNow <- fixing known impl
              | ChosenAtRunTime _ => runtimeLet q loc known
            body (BoundHere impl Nothing :: env)
          else do
            Just (shape, values) <- holed ph w acc ctx env fc val
              | Nothing => runtimeLet q loc known
            FixedNow <- fixing known shape
              | ChosenAtRunTime _ => runtimeLet q loc known
            held <- coreType fc ctx.owner ValueType !(normaliseClosed !(packedType (map fst values)))
            v <- pack fc ctx.owner loc !(valuesOf values)
            (r', inner) <- body (under {k = 1} [BoundHere shape (Just (FZ, MkHoles (map fst values) (MkBinder Many held)))] env)
            pure (r', Let loc (binderName x) (Checked (MkBinder Many held)) v inner)
    where
      -- The value computed and bound by a `let`, a runtime value used as
      -- the `let`'s quantity says; or, for a lambda its body uses only as
      -- a continuation, the join point the program as written makes
      -- (`letOf`).
      runtimeLet : Uses -> Loc -> ClosedTerm -> Front (r, Term nv)
      runtimeLet q loc known = do
        b <- coreBinder (bestFC ctx fc) ctx.owner ValueType q known
        v <- term ph w acc ctx env (ExpectedAt b.type) val
        (r', inner) <- body (under {k = 1} [Runtime FZ (BothTypes b.type known)] env)
        pure (r', letOf loc (binderName x) b v inner)

  ||| A term at the type it is expected to have (`ty`), the type a
  ||| definition's leaf gives, translated at its Core type
  ||| (`Ctx.resultType`): a lambda there, where that type is a polymorphic
  ||| function's (`Ctx.resultHolding`), is the member of the type's choice
  ||| it is (`member`), as one given at a parameter of the type is, its own
  ||| binders not saying the type; a `let` gives its body the type it
  ||| expects. Any other term is translated as it is.
  export
  atType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> (ty : ClosedTerm) -> TT vars -> Front (Term nv)
  atType ph w acc ctx env ty tm@(Bind fc _ (Lam {}) _) = do
    Just ct <- holds ctx.resultHolding ty
      | Nothing => term ph w acc ctx env (ExpectedAt ctx.resultType) tm
    loc <- toLoc (bestFC ctx fc)
    Just m <- member ph w acc ctx env fc loc ct tm
      | Nothing => term ph w acc ctx env (ExpectedAt ctx.resultType) tm
    pure m
  atType ph w acc ctx env ty tm@(Bind fc x (Let lfc rig val vty) sc) = case delayedLets tm of
    Just _ => term ph w acc ctx env (ExpectedAt ctx.resultType) tm
    Nothing => snd <$> letIn ph w acc ctx env fc x rig val vty (\env' => ((),) <$> atType ph w acc ctx env' ty sc)
  atType ph w acc ctx env ty tm = term ph w acc ctx env (ExpectedAt ctx.resultType) tm

  ||| A `Delay` of `arg`, of the type `ty` Idris checked it at, which its
  ||| body is translated at.
  suspend : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> (ty, arg : TT vars) -> Front (Term nv)
  suspend ph w acc ctx env fc ty arg = do
    loc <- toLoc (bestFC ctx fc)
    t <- delayedType ctx env fc ty
    body <- term ph w acc ctx env (ExpectedAt t) arg
    pure (Suspend loc t body)

  ||| An argument where it is a subterm of the application, translated at
  ||| what the use that gives it expects.
  argOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> TT vars -> Arg vars nv
  argOf ph w acc ctx env afc a = MkArg a (\ex => term ph w acc ctx env ex a) (holed ph w acc ctx env afc a)

  ||| An application's spine, its arguments collected where each is a
  ||| subterm, down to its head; `ex` is what the whole application is
  ||| expected at.
  spine : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> FC -> TT vars -> List (Arg vars nv) -> Front (Term nv)
  spine ph w acc ctx env ex afc (App _ f a) args = spine ph w acc ctx env ex afc f (argOf ph w acc ctx env afc a :: args)
  spine ph w acc ctx env ex afc (Ref rfc nt n) args = applyRef ph w acc ctx env ex afc rfc nt n args
  spine ph w acc ctx env ex afc tm args = applyHead ph w acc ctx env ex afc tm args

  ||| A head that is no definition, applied to its arguments: a variable; a
  ||| lambda, whose argument is bound in the environment and whose body
  ||| takes the rest, so that no term is substituted; a solved metavariable,
  ||| as its solution; an `As` pattern, as its pattern; anything else, as its
  ||| value applied, its type read off the term it becomes, or, applied to
  ||| nothing, at what the application is expected at.
  applyHead : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
              (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
              Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> FC -> TT vars -> List (Arg vars nv) -> Front (Term nv)
  applyHead ph w acc ctx env ex afc (Local fc r idx p) args = applyVariable ph w acc ctx env afc fc r idx p args
  -- The argument is bound as what it is: a compile-time value at an erased
  -- binder; another name for a variable; at a binder of an implementation
  -- or a polymorphic function (`compileTimeBinder`), its form, with the
  -- values it closes over bound once; anything else, a runtime value
  -- bound by a `let`, which the application evaluates first, where the
  -- `let` translation would move it into a `Delay` the body builds
  -- (`delayedLets`).
  applyHead ph w acc ctx env ex afc (Bind bfc x (Lam _ rig _ ty) sc) (a :: rest) =
    case use rig of
      Erased => spine ph w acc ctx (TypeValue (closeWritten bfc env a.written) :: env) ex afc sc (map overBinder rest)
      -- A variable given to a binder of quantity 1 stands for it, used at
      -- most once there as Idris proved; given to one of quantity many it
      -- is bound once, so a variable Idris lets be used once is never used
      -- twice.
      Used q => case (q, aliased a.written) of
        (Once, Just e) => spine ph w acc ctx (e :: env) ex afc sc (map overBinder rest)
        _ => do
          fixedHere <- compileTimeBinder rig ty
          loc <- toLoc (bestFC ctx bfc)
          if fixedHere then dictionary q loc else asValue q loc
    where
      -- The argument as a runtime value, bound by a `let` at the binder's
      -- quantity: a choice of an implementation among others (`Choices`).
      asValue : Uses -> Loc -> Front (Term nv)
      asValue q loc = do
        known <- closeNormalise bfc env ty
        b <- coreBinder (bestFC ctx bfc) ctx.owner ValueType q known
        v <- a.translated (ExpectedAt b.type)
        body <- spine ph w acc ctx (under {k = 1} [Runtime FZ (BothTypes b.type known)] env) ex afc sc (map underLet rest)
        pure (Let loc (binderName x) (Checked b) v body)

      aliased : TT vars -> Maybe (VarInfo kc OfTerm (Fin nv))
      aliased (Local _ _ idx p) = Just (lookupVar idx p env)
      aliased _ = Nothing

      -- One the program fixes now (`fixing`) is its form; one the running
      -- program chooses, or a definition Idris does not prove ends
      -- computes, is computed when the program runs: a choice, bound as a
      -- value.
      dictionary : Uses -> Loc -> Front (Term nv)
      dictionary q loc = do
        known <- closeNormalise bfc env ty
        impl <- solved (closeWritten bfc env a.written)
        if not !(runtimeDependent impl)
          then do
            FixedNow <- fixing known impl
              | ChosenAtRunTime _ => asValue q loc
            spine ph w acc ctx (BoundHere impl Nothing :: env) ex afc sc (map overBinder rest)
          else do
            Just (shape, values) <- a.held
              | Nothing => asValue q loc
            FixedNow <- fixing known shape
              | ChosenAtRunTime _ => asValue q loc
            held <- coreType bfc ctx.owner ValueType !(normaliseClosed !(packedType (map fst values)))
            v <- pack bfc ctx.owner loc !(valuesOf values)
            body <- spine ph w acc ctx
                          (under {k = 1} [BoundHere shape (Just (FZ, MkHoles (map fst values) (MkBinder Many held)))] env)
                          ex afc sc (map underLet rest)
            pure (Let loc (binderName x) (Checked (MkBinder Many held)) v body)
  applyHead ph w acc ctx env ex afc (Meta mfc n i margs) args = entered ph w acc ctx env ex afc mfc n i margs args
  applyHead ph w acc ctx env ex afc (As _ _ _ pat) args = spine ph w acc ctx env ex afc pat args
  applyHead ph w acc ctx env ex afc tm [] = term ph w acc ctx env ex tm
  applyHead ph w acc ctx env ex afc tm args@(_ :: _) = do
    let fc = bestFC ctx afc
    loc <- toLoc fc
    f <- term ph w acc ctx env Synthesized tm
    applyOver ctx env fc loc (headName fc env tm) f (termType ctx.depth (scopeOf env) f) (headType env tm) args

  ||| A variable applied to its arguments: a runtime value, applied; an
  ||| implementation, as `implementationAt` uses one.
  applyVariable : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                  (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                  Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> (afc : FC) -> (fc : FC) -> Maybe Bool ->
                  (idx : Nat) -> (0 p : IsVar n idx vars) -> List (Arg vars nv) -> Front (Term nv)
  applyVariable ph w acc ctx env afc fc r idx p args = case lookupVar idx p env of
    e@(Runtime x _) => applied x e
    e@(Shaped x _ _ _) => applied x e
    -- Idris's quantity check of a clause keeps a binder of quantity 0 out
    -- of every position that exists at runtime, a leaf reads each binder
    -- where its clause holds it at runtime (`Cases.heldAt`), and the
    -- translation leaves out every erased position. The check is Idris's,
    -- of the checked module, whose term the frontend first reads here, and
    -- TT's variable does not carry it: one that fails it is refused, as
    -- the compiled module it is.
    TypeValue _ => reject (bestFC ctx fc) ctx.owner CompiledModule "a compile-time variable in a runtime position"
    Static t held _ => implementationAt ph w acc ctx env fc t held args
    BoundHere t held => implementationAt ph w acc ctx env fc t held args
    where
      -- The variable, of the Core type its entry gives.
      applied : Fin nv -> VarInfo kc OfTerm (Fin nv) -> Front (Term nv)
      applied x e = do
        loc <- toLoc (bestFC ctx fc)
        let at = bestFC ctx afc
        aloc <- toLoc at
        let tm = Local fc r idx p
        applyOver ctx env at aloc (headName at env tm) (Var loc x) (coreTyOf e) (headType env tm) args

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
                     Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> ClosedTerm -> Maybe (Fin nv, Holes) ->
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
  standingFor : ClosedTerm -> Maybe (Fin nv, Holes) -> Front (ClosedTerm, List (Stand kc nv))
  standingFor t Nothing = pure (t, [])
  standingFor t (Just (x, hs)) = do
    values <- unpacked hs.types (holeMarker 0)
    pure (fillHoles values t, [AsVariable (Runtime x (BothTypes hs.binder.type !(packedType hs.types)))])

  ||| A metavariable applied, as the solution the type checker gave it,
  ||| entered once on the path.
  entered : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> (afc : FC) -> (fc : FC) -> Name -> Int -> List (TT vars) ->
            List (Arg vars nv) -> Front (Term nv)
  entered ph w acc@(Access rec) ctx env ex afc fc n i margs args = do
    -- The metavariable's entry is Idris's bare `Int`, which a resolved
    -- name of the checked module never makes negative; the term is where
    -- the frontend first reads it, so a negative one is refused, as the
    -- compiled module it is.
    let Just place = placementOf i
      | Nothing => reject (bestFC ctx fc) ctx.owner CompiledModule "a metavariable at a negative place"
    -- Idris's occurs check keeps a solution from holding its own
    -- metavariable, which the walk is where the frontend first meets: a
    -- solution that holds it is refused, as the compiled module it is.
    let Just (Element w' less) = enter place w
      | Nothing => reject (bestFC ctx fc) ctx.owner CompiledModule "a metavariable met again on its own path"
    Just tm <- solution (bestFC ctx fc) n margs
      | Nothing => reject (bestFC ctx fc) ctx.owner EscapeHatch ("the hole " ++ show n)
    spine ph w' (rec w' less) ctx env ex afc tm args

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
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) -> Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC ->
           (value : ClosedTerm) -> (pre : List (Stand kc nv)) -> List (Arg vars nv) -> Front (Term nv)
  settle ph w acc ctx env fc value pre args = do
    (terms, stands) <- given (length pre) args
    nf <- lambdasApplied (foldl (App EmptyFC) value terms)
    loc <- toLoc (bestFC ctx fc)
    bindStands ph w acc ctx env loc 0 id (pre ++ stands) (embedClosed {vars} nf)
    where
      -- A runtime value as a marker: a variable as itself, anything else
      -- by its translation.
      stand : Arg vars nv -> Stand kc nv
      stand a = case a.written of
        Local _ _ idx p => case lookupVar idx p env of
          e@(Runtime {}) => AsVariable e
          e@(Shaped {}) => AsVariable e
          _ => AsValue (a.translated Synthesized)
        _ => AsValue (a.translated Synthesized)

      -- Is an argument an implementation: a variable that holds one, or a
      -- definition whose type gives one, applied?
      anImplementation : TT vars -> Front Bool
      anImplementation tm = case getFnArgs tm of
        (Local _ _ idx p, _) => pure (case lookupVar idx p env of
                                        Static {} => True
                                        BoundHere {} => True
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
      argument : Nat -> Arg vars nv -> Front (ClosedTerm, List (Stand kc nv))
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

      given : Nat -> List (Arg vars nv) -> Front (List ClosedTerm, List (Stand kc nv))
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
               Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Loc -> Nat -> (Fin m -> Fin nv) ->
               List (Stand kc m) -> TT vars -> Front (Term nv)
  bindStands ph w acc ctx env loc i ren [] body = term ph w acc ctx env Synthesized body
  bindStands ph w acc ctx env loc i ren (AsVariable e :: stands) body =
    bindStands ph w acc ctx (map ren e :: env) loc (S i) ren stands (refToLocal (markerName i) (markerName i) body)
  bindStands ph w acc ctx env loc i ren (AsValue v :: stands) body = do
    value <- rename ren <$> v
    -- The value is of the type its own term states, where it states one.
    let held = maybe Untyped CoreTypeOnly (termType ctx.depth (scopeOf env) value)
    rest <- bindStands ph w acc ctx (under {k = 1} [Runtime FZ held] env) loc (S i) (FS . ren) stands
                       (refToLocal (markerName i) (markerName i) body)
    pure (Let loc (shown "held") (OfValue Many) value rest)

  ||| A value an implementation closes over, computed inside a settled term
  ||| (`holed`): translated in the settled phase, its markers the variables
  ||| they stand for, on a path that enters the definition that gives the
  ||| implementation, whose place `holed` found it under (`gives`). A value
  ||| of it computed inside another of its own values would translate
  ||| without end, and is the one case refused.
  settledPiece : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                 (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> (giver : Placement) -> (impl : ClosedTerm) ->
                 (stands : List (VarInfo kc OfTerm (Fin nv))) -> TT vars -> Front (Term nv)
  settledPiece ph w acc@(Access rec) ctx env afc giver impl stands p = do
    let Just (Element w' less) = enter giver w
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
          Phase -> (w : Walked) -> (0 acc : SizeAccessible w) -> Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> TT vars ->
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
      marking : Nat -> StandsFor kc OfTerm vs (Fin nv) -> (StandsFor kc OfTerm vs (Fin nv), List (VarInfo kc OfTerm (Fin nv)))
      marking k [] = ([], [])
      marking k (e@(Runtime {}) :: es) = let (es', ss) = marking (S k) es in (TypeValue (holeMarker k) :: es', e :: ss)
      marking k (e@(Shaped {}) :: es) = let (es', ss) = marking (S k) es in (TypeValue (holeMarker k) :: es', e :: ss)
      marking k (e@(Static _ (Just _) _) :: es) = let (es', ss) = marking (S k) es in (TypeValue (holeMarker k) :: es', e :: ss)
      marking k (e@(BoundHere _ (Just _)) :: es) = let (es', ss) = marking (S k) es in (TypeValue (holeMarker k) :: es', e :: ss)
      marking k (e :: es) = let (es', ss) = marking k es in (e :: es', ss)

      marked : (StandsFor kc OfTerm vars (Fin nv), List (VarInfo kc OfTerm (Fin nv)))
      marked = marking 0 env

      stands : List (VarInfo kc OfTerm (Fin nv))
      stands = snd marked

      standAt : Name -> Maybe (VarInfo kc OfTerm (Fin nv))
      standAt n = markerOf n >>= \k => getAt k stands

      -- What the written form has for a variable (`closeWritten`), where a
      -- stand's marker is: a runtime value's unknown value, its shape, an
      -- implementation's form.
      writtenAs : VarInfo kc OfTerm (Fin nv) -> ClosedTerm
      writtenAs (Shaped _ _ _ s) = s
      writtenAs (Static t _ _) = t
      writtenAs (BoundHere t _) = t
      writtenAs (TypeValue t) = t
      writtenAs (Runtime {}) = probeTerm ProbeRuntime

      restoring : Nat -> List (VarInfo kc OfTerm (Fin nv)) -> (ns : List Name ** (Bounds ns, SubstEnv ns Scope.empty))
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
      -- definition that gives the implementation (`settledPiece`), at the
      -- place it was found under.
      piece : Phase -> Placement -> ClosedTerm -> ClosedTerm -> Front (Front (Term nv))
      piece ph'@Settled giver impl p =
        pure (settledPiece ph' w acc ctx env afc giver (restore impl) stands (embedClosed {vars} p))
      piece (Written next) _ _ p = do
        loc <- toLoc (bestFC ctx afc)
        pure (bindStands next start (sizeAccessible start) ctx env loc 0 id (map AsVariable stands) (embedClosed {vars} p))

      -- The runtime variable a part of the implementation is, if it is one.
      variableOf : ClosedTerm -> Maybe (Fin nv)
      variableOf (Ref _ Bound n) = case standAt n of
        Just (Runtime v _) => Just v
        Just (Shaped v _ _ _) => Just v
        _ => Nothing
      variableOf _ = Nothing

      value : Placement -> ClosedTerm -> ClosedTerm -> ClosedTerm -> Front (Maybe (ClosedTerm, Found nv))
      value giver impl aty p = case variableOf p of
        Just v => do
          loc <- toLoc (bestFC ctx afc)
          pure (Just (foundMarker 0, [(Just v, aty, pure (Var loc v))]))
        Nothing => (\t => Just (foundMarker 0, [(Nothing, aty, t)])) <$> piece ph giver impl p

      -- Does a definition give an implementation without matching on
      -- its arguments: one with one right-hand side, or a constructor
      -- of an implementation (the pair that holds a tuple of
      -- constraints, or an interface's own constructor, which an
      -- expanded implementation is already built with: its fields
      -- that are functions are the closures it closes over values
      -- with)?
      gives : Defined -> Front Bool
      gives d = case d.matched of
        Just m => pure (isJust (leafOf m))
        Nothing => case definition d.def of
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
      part : Placement -> ClosedTerm -> ClosedTerm -> ClosedTerm -> Lazy (Front (Maybe (ClosedTerm, Found nv))) ->
             Front (Maybe (ClosedTerm, Found nv))
      part giver impl aty a walked = do
        aty' <- normaliseClosed aty
        if not !(implementationType aty') || isJust (variableOf a) then value giver impl aty' a else do
          Just (form, found) <- walked
            | Nothing => value giver impl aty' a
          FixedNow <- fixing aty' form
            | ChosenAtRunTime _ => value giver impl aty' a
          pure (Just (form, found))

      -- The arguments of a definition that gives `impl`, at the place
      -- `giver`, over its type, each found value numbered from 0 among the
      -- arguments' together.
      parts : Placement -> ClosedTerm -> ClosedTerm -> List (ClosedTerm, Lazy (Front (Maybe (ClosedTerm, Found nv)))) ->
              Front (Maybe (List ClosedTerm, Found nv))
      parts giver impl _ [] = pure (Just ([], []))
      parts giver impl ty ((a, walked) :: as) = do
        let written = restore a
        dependent <- runtimeDependent written
        ty' <- normaliseClosed ty
        let (at, rest) = binder ty'
        here <- case (at, dependent) of
                  (Just (Erased, _), _) => pure (Just (written, the (Found nv) []))
                  (_, False) => pure (Just (written, the (Found nv) []))
                  (Just (Used _, aty), True) => part giver impl aty a walked
                  (Nothing, True) => pure Nothing
        let Just (v, found) = here
          | Nothing => pure Nothing
        Just (vs, after) <- parts giver impl (rest v) as
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

          holders : Nat -> List (VarInfo kc OfTerm (Fin nv)) -> List (Nat, (Fin nv, Holes, ClosedTerm))
          holders k (Static t (Just (v, hs)) _ :: rest) = (k, (v, hs, t)) :: holders (S k) rest
          holders k (BoundHere t (Just (v, hs)) :: rest) = (k, (v, hs, t)) :: holders (S k) rest
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
      headed impl (Ref _ Bound n) [] = case standAt n >>= implementationOf of
        Just (t, Just (v, hs)) => do
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
        Just (vs, found) <- parts d.placement impl d.type args
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
          capture : Loc -> Nat -> List (Nat, VarInfo kc OfTerm (Fin nv)) -> ClosedTerm -> Front (Maybe (ClosedTerm, Found nv))
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
              standing : VarInfo kc OfTerm (Fin nv) -> Front (Maybe (Fin nv, ClosedTerm, ClosedTerm))
              standing (Runtime v (BothTypes _ ity)) = pure (Just (v, ity, foundMarker j))
              standing (Shaped v _ ity _) = pure (Just (v, ity, foundMarker j))
              standing e = case implementationOf e of
                Just (form, Just (v, hs)) => do
                  projections <- unpacked hs.types (foundMarker j)
                  held <- packedType hs.types
                  pure (Just (v, held, fillHoles projections form))
                _ => pure Nothing

      -- An implementation's spine, each argument with its own walk
      -- suspended where it is a subterm.
      walk : ClosedTerm -> ClosedTerm -> List (ClosedTerm, Lazy (Front (Maybe (ClosedTerm, Found nv)))) ->
             Front (Maybe (ClosedTerm, Found nv))
      walk impl (App _ f a) args = walk impl f ((a, walk a a []) :: args)
      walk impl h args = headed impl h args

  ||| An implementation or a polymorphic function the program fixes, written
  ||| in a runtime position, as the member of its type's choice it is
  ||| (`Choices`), the type as `holds` read it a choice's: its form, with
  ||| the runtime values it closes over as its field. Nothing for one the
  ||| running program chooses (stuck on a runtime value), or one a
  ||| definition Idris does not prove ends computes, which no compile-time
  ||| reduction runs: it is translated as the computation it is, whose
  ||| value is the choice among the members its own body fixes.
  member : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> Loc -> ChoiceType -> TT vars -> Front (Maybe (Term nv))
  member ph w acc ctx env fc loc ct written = do
    impl <- solved (closeWritten fc env written)
    if not !(runtimeDependent impl)
      then do
        FixedNow <- fixing ct.type impl
          | ChosenAtRunTime _ => pure Nothing
        con <- memberBare fc ctx.owner ct !(implementationOf impl)
        pure (Just (ConApp loc con [] []))
      else do
        Just (shape, values) <- holed ph w acc ctx env fc written
          | Nothing => pure Nothing
        form <- implementationOf shape
        FixedNow <- fixing ct.type form
          | ChosenAtRunTime _ => pure Nothing
        held <- coreType fc ctx.owner ValueType !(normaliseClosed !(packedType (map fst values)))
        con <- memberHolding fc ctx.owner ct form (MkHoles (map fst values) (MkBinder Many held))
        v <- pack fc ctx.owner loc !(valuesOf values)
        pure (Just (ConApp loc con [] [v]))

  ||| A definition applied to its arguments.
  applyRef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
             (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> (afc : FC) -> (rfc : FC) -> NameType -> Name ->
             List (Arg vars nv) -> Front (Term nv)
  applyRef ph w acc ctx env ex afc rfc nt name args = do
    d <- lookupDef (bestFC ctx rfc) ctx.owner name
    applyDefined ph w acc ctx env ex afc rfc nt name d args

  ||| A definition, as it was read (`d`), applied to its arguments; `ex`
  ||| is what the whole application is expected at.
  applyDefined : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                 (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> (afc : FC) -> (rfc : FC) -> NameType -> Name ->
                 Defined -> List (Arg vars nv) -> Front (Term nv)
  applyDefined ph w acc ctx env ex afc rfc nt name d args = do
    let fc = bestFC ctx rfc
    loc <- toLoc fc
    let def = d.def
    let ty = d.type
    let full = fullname def
    -- What a hook lowers a call of this definition to stands for it, the
    -- registry's entry it applied.
    let lowered = Just (shown (show full))
    -- An implementation in a runtime position that the program fixes here
    -- is a member of its type's choice.
    Nothing <- memberHere fc loc
      | Just member => pure member
    case callHooks d.registered of
      -- A `%foreign` definition is known by its spec, an `%extern` one by
      -- its name; one the registry gives no meaning is refused where it
      -- is called.
      Left miss => do
        site <- siteAt fc
        rejectWith (foreignRefusal site ctx.owner "" full miss)
      -- A definition that matches is called at the arity of its case
      -- tree's parameters, as the boundary read its body, which its own
      -- translation reads too.
      Right hs => case d.matched of
        Just m => hooked fc loc full lowered d ty hs $ do
          Just exit <- exitCast d
            | Nothing => call fc loc d Nothing m args
          exitAction exit fc loc (length m.args) ty args
        Nothing => case definition def of
          DCon tag arity _ => constructor fc loc d ty arity args
          TCon {} => inRuntime ctx.owner fc env (foldl (App rfc) (Ref rfc nt name) (map (.written) args))
          Builtin {arity} op => primitive fc loc full arity op ty args
          ForeignDef {} => hooked fc loc full lowered d ty hs
                             (reject fc ctx.owner EscapeHatch ("foreign function " ++ show full))
          ExternDef {} => hooked fc loc full lowered d ty hs
                            (reject fc ctx.owner EscapeHatch ("extern function " ++ show full))
          Hole {} => reject fc ctx.owner EscapeHatch ("the hole " ++ show full)
          -- A definition Idris left unfinished (no body, a guess, a pending
          -- search or default): its checker finishes every definition a
          -- checked program reaches, and the context's type of a definition
          -- does not say so. The reference is where the frontend first
          -- meets it, so it is refused here, as the compiled module it is.
          _ => reject fc ctx.owner CompiledModule ("a reference to the unfinished definition " ++ show full)
    where
      -- The member of its type's choice an implementation or a
      -- polymorphic function fixed here is (`member`), where the
      -- definition applied to the arguments gives one in a runtime
      -- position: as the member table says (`givesAfter`), and where the
      -- instance decides, as its type after the arguments does. A
      -- function to implementations is a closure.
      memberHere : FC -> Loc -> Front (Maybe (Term nv))
      memberHere fc loc = case givesAfter (length args) (memberPlaces d) of
        NoMember => pure Nothing
        holding => do
          Just ty <- typeAfter d.type args
            | Nothing => pure Nothing
          ty' <- normaliseClosed ty
          Just ct <- holds holding ty'
            | Nothing => pure Nothing
          member ph w acc ctx env afc loc ct (foldl (App rfc) (Ref rfc nt name) (map (.written) args))

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

      -- The values an implementation given as an argument closes over, as
      -- one value (`packedType`).
      heldValue : Loc -> Arg vars nv -> Front (Term nv)
      heldValue loc x = do
        -- The classification read this argument's held values to give
        -- it its kind, and the kind keeps their types, not them: this
        -- reads them again, the same computation over the same state.
        Just (_, held) <- x.held
          | Nothing => internal afc "the values an implementation closes over are gone"
        pack afc ctx.owner loc !(valuesOf held)

      -- The runtime arguments of a call of a callee whose member places
      -- are `places`, one term per parameter that exists at runtime among
      -- those the arguments given reach, as many as its type says:
      -- nothing for a type, an implementation or an argument of quantity
      -- 0. An implementation that closes over runtime values passes them,
      -- as one value (`packedType`); a choice of one is its value.
      arguments : Loc -> MemberPlaces -> (ks : List PKind) -> (ys : List (Arg vars nv)) ->
                  Front (Vect (Runtimes (take (length ys) ks)) (Term nv))
      arguments loc places = from 0
        where
          -- From the parameter at position `j`.
          from : Nat -> (ks : List PKind) -> (ys : List (Arg vars nv)) ->
                 Front (Vect (Runtimes (take (length ys) ks)) (Term nv))
          from j [] [] = pure []
          from j [] (_ :: _) = pure []
          from j (_ :: _) [] = pure []
          from j (ValueParam b _ t :: ks) (x :: xs) = (::) <$> valueAt loc places j b t x <*> from (S j) ks xs
          from j (k@(ChoiceParam {}) :: ks) (x :: xs) = (::) <$> x.translated (expectedBy k) <*> from (S j) ks xs
          from j (DictParam _ (Just _) :: ks) (x :: xs) = (::) <$> heldValue loc x <*> from (S j) ks xs
          from j (DictParam _ Nothing :: ks) (_ :: xs) = from (S j) ks xs
          from j (TypeParam _ :: ks) (_ :: xs) = from (S j) ks xs
          from j (ErasedParam :: ks) (_ :: xs) = from (S j) ks xs
          from j (IndexParam _ :: ks) (_ :: xs) = from (S j) ks xs
          from j (FormParam _ :: ks) (_ :: xs) = from (S j) ks xs

      -- A runtime argument, at position `j` of a callee whose member places
      -- are `places`, its parameter's binder `b` and Idris type `t`. A
      -- lambda given where a polymorphic function is held is the member of
      -- its type's choice it is (`member`): its own binders do not say its
      -- type, which the position does, as the member table says
      -- (`givenAt`), and where the instance decides, as its type there
      -- does; one given delayed where a delayed one is held (a branch of
      -- `if`), the member delayed. Any other is translated at the binder's
      -- type.
      valueAt : Loc -> MemberPlaces -> Nat -> Binder -> ClosedTerm -> Arg vars nv -> Front (Term nv)
      valueAt loc places j b t x = case (x.written, t) of
        (Bind _ _ (Lam {}) _, _) => do
          Just m <- asMember t x.written
            | Nothing => x.translated (ExpectedAt b.type)
          pure m
        -- The member's type is the choice the parameter's type holds,
        -- which its binder was made of already.
        (TDelay dfc _ _ inner@(Bind _ _ (Lam {}) _), TDelayed _ _ t') => do
          Just m <- asMember t' inner
            | Nothing => x.translated (ExpectedAt b.type)
          dloc <- toLoc (bestFC ctx dfc)
          held <- dynamicDims <$> coreType (bestFC ctx dfc) ctx.owner ValueType t'
          pure (Suspend dloc held m)
        _ => x.translated (ExpectedAt b.type)
        where
          asMember : ClosedTerm -> TT vars -> Front (Maybe (Term nv))
          asMember ty lam = do
            Just ct <- holds (givenAt j places) ty
              | Nothing => pure Nothing
            member ph w acc ctx env afc loc ct lam

      argValues : List (Arg vars nv) -> ArgValues
      argValues = map (argValueIn env afc)

      -- The call's value: `mk` on the runtime arguments when the call gives
      -- every parameter, applied to the arguments past them over the
      -- callee's result type (`resTy`), at the type the value's term states;
      -- with fewer, one closure per missing runtime parameter, as
      -- the curried type of the result requires. The arguments given
      -- (`arguments`, over the first `arity` of `xs`) and the closures'
      -- parameters are as many as the call has runtime parameters, which is
      -- what `mk` takes (`runtimesSplit`).
      finish : Loc -> (kinds : List PKind) -> (arity : Nat) -> (xs : List (Arg vars nv)) ->
               Vect (Runtimes (take (length (take arity xs)) kinds)) (Term nv) ->
               Maker (Runtimes kinds) -> (valueTy : Ty) -> ClosedTerm -> Front (Term nv)
      finish loc kinds arity xs given mk valueTy resTy = do
        let missing = drop (length (take arity xs)) kinds
        let value = etaExpand loc (runtimeBinders (drop (length (take arity xs)) kinds)) valueTy
                              (recount (runtimesSplit (length (take arity xs)) kinds) mk) given
        -- A type or a form the call leaves out was refused where the
        -- call's arguments were classified, and an implementation it
        -- leaves out is a choice, so the missing ones are runtime
        -- parameters, each a closure's.
        if null missing
           then applyOver ctx env afc loc (show <$> fullName name) value (termType ctx.depth (scopeOf env) value) (Just resTy)
                          (drop arity xs)
           else pure value

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
            -- Read again, as the classification read them to give this
            -- kind, which keeps their types, not them.
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

      -- A call of the instance whose signature is `sig`, read in this scope
      -- (`called`), on its runtime arguments; where its result is an array,
      -- its dimensions that an argument fixes (a natural, or a dimension of
      -- an array argument) stated equal to it, the arguments bound once.
      -- `is` are the terms the call gives its callee's index parameters,
      -- and the call's value is of its callee's result type with them
      -- given, which the tie states its dimensions of.
      tiedCall : FC -> Loc -> (sig : InstanceSig) -> Maybe Shown -> List ITerm -> ClosedTerm ->
                 (called : AtCall sig.kinds) -> Front (Maker (Runtimes called.kinds))
      tiedCall fc loc sig lowered is ty called = do
        let calls = recount called.sameCount (MkMaker (\ys => Call loc sig.callee lowered is ys))
        Just _ <- arrayView called.result
          | Nothing => pure calls
        (tel, res) <- sizedTelescope ty called.kinds
        rt <- coreType fc ctx.owner ValueType called.result
        [] <- resultTies tel res rt
          | ties => pure (MkMaker (\ys => bindArguments loc (runtimeBinders called.kinds) ys (\ren, vs =>
                      Tie loc (substTy is sig.callee.result) (calls.make (map (Var loc) vs))
                          (map (\(k, w) => (k, witnessTerm loc vs w)) ties))))
        pure calls

      -- A call of a function: its instance at the static arguments the
      -- call gives, whose signature, read where it was requested, the call
      -- reads in this scope (`atCall`), its index parameters given the
      -- terms of the arguments at their positions, so the call gives as
      -- many arguments as the instance takes, by type.
      call : FC -> Loc -> Defined -> Maybe Shown -> Matched -> List (Arg vars nv) -> Front (Term nv)
      call fc loc callee lowered m xs = do
        let n = fullname callee.def
        let ty = callee.type
        let arity = length m.args
        let vals = argValues (take arity xs)
        kinds <- classifyKeys fc ctx.owner (show n) (length m.args) ty vals
        Nothing <- resolveMethod ph fc n (toList kinds) xs
          | Just resolved => pure resolved
        sig <- calleeAt (choicesIn kinds) fc ctx.owner (OfDefinition n m) kinds
        called <- atCall fc ctx.owner vals sig
        given <- arguments loc (memberPlaces callee) called.kinds (take arity xs)
        is <- callIndices called.kinds vals
        mk <- tiedCall fc loc sig lowered is ty called
        finish loc called.kinds arity xs given mk (substTy is sig.callee.result) called.result

      -- A type a hook reads in this scope (an operand of the array
      -- language's, the exit's action) at an instance whose types are not
      -- the ones the hook takes: what the definition's type gives, the
      -- instance's types read again, here, where the call is classified.
      unshaped : {0 result : Type} -> FC -> String -> Front result
      unshaped fc what = reject fc (show name) HookShape what

      -- An operand of a lowered call the call gives as an implementation
      -- the program fixes. Essential: a hook's operand whose type an
      -- instance makes an implementation's is a compile-time value there,
      -- which the classification keys nothing by and no runtime parameter
      -- holds, where the hook takes a value at run time.
      compileTimeOperand : {0 result : Type} -> FC -> Front result
      compileTimeOperand fc =
        reject fc (show name) HookShape "the call fixes an implementation where the registry's hook takes a value at run time"

      -- The binder of an operand, as the call's classification reads its
      -- parameter in this scope.
      operandBinder : FC -> PKind -> Front Binder
      operandBinder fc kind = maybe (compileTimeOperand fc) pure (boundAtRuntime kind)

      -- The binders of a row's operands, in order.
      operandBinders : FC -> Operands n k -> Vect n PKind -> Front (Vect k Binder)
      operandBinders fc NoParameter [] = pure []
      operandBinders fc (NoOperand ops) (_ :: ks) = operandBinders fc ops ks
      operandBinders fc (Operand ops) (kind :: ks) = (::) <$> operandBinder fc kind <*> operandBinders fc ops ks

      -- The value a call gives at an operand, at position `j` of a callee
      -- whose member places are `places`, as its classification reads the
      -- parameter (`arguments`).
      operandTerm : FC -> Loc -> MemberPlaces -> Nat -> PKind -> Arg vars nv -> Front (Term nv)
      operandTerm fc loc places j (ValueParam b _ t) x = valueAt loc places j b t x
      operandTerm fc loc places j k@(ChoiceParam {}) x = x.translated (expectedBy k)
      operandTerm fc loc places j (DictParam _ (Just _)) x = heldValue loc x
      operandTerm fc loc places j _ x = compileTimeOperand fc

      -- What a lowered call gives its hook, by the row's positions, from
      -- the parameter at position `j`: the arguments it gives at operands,
      -- each as the call's classification reads its parameter, and the
      -- binders of the operands past them, which closures take. The row
      -- says which parameters are operands, so the hook is given as many
      -- as it takes.
      operandsGiven : FC -> Loc -> MemberPlaces -> Operands n k -> Vect n PKind -> (j : Nat) -> List (Arg vars nv) ->
                      Front (Supplied k nv)
      operandsGiven fc loc places NoParameter [] j xs = pure (MkSupplied [] [] Refl)
      operandsGiven fc loc places (NoOperand ops) (_ :: ks) j xs = operandsGiven fc loc places ops ks (S j) (drop 1 xs)
      operandsGiven fc loc places (Operand ops) (kind :: ks) j [] = do
        b <- operandBinder fc kind
        bs <- operandBinders fc ops ks
        pure (MkSupplied [] (b :: bs) Refl)
      operandsGiven fc loc places (Operand ops) (kind :: ks) j (x :: xs) = do
        t <- operandTerm fc loc places j kind x
        MkSupplied ts bs same <- operandsGiven fc loc places ops ks (S j) xs
        pure (MkSupplied (t :: ts) bs (cong S same))

      -- The type each runtime operand a call gives its maker is bound at, in
      -- order: one the call gives, the type its own term states
      -- (`termType`), the one `Emit` gives its value; one it leaves to the
      -- closures that complete the call, the closure's parameter's
      -- (`closureBinder`). An operand whose term states none never returns,
      -- or is no function (an IO primitive's result), so no application is
      -- made at its type and nothing reads it: its parameter's binder's
      -- stands there.
      boundTypes : Vect g (Term nv) -> Vect m Binder -> (0 _ : g + m = k) -> Vect k Binder -> Vect k Ty
      boundTypes given missing together bs =
        zipWith (\b, t => fromMaybe b.type t) bs
                (replace {p = \j => Vect j (Maybe Ty)} together
                         (map (termType ctx.depth (scopeOf env)) given ++ map (\b => Just (closureBinder b).type) missing))

      -- A lowered call's value: its hook's value on the operands it gives,
      -- of the Core type `valueTy`, a closure over each it leaves out, and
      -- the arguments past its arity applied to it, at the type its term
      -- states, over the result type read in this scope.
      completed : Loc -> (arity : Nat) -> List (Arg vars nv) -> Supplied k nv -> Maker k -> (valueTy : Ty) -> ClosedTerm ->
                  Front (Term nv)
      completed loc arity xs (MkSupplied given missing together) mk valueTy resTy = do
        let value = etaExpand loc missing valueTy (recount together mk) given
        applyOver ctx env afc loc (show <$> fullName name) value (termType ctx.depth (scopeOf env) value) (Just resTy)
                  (drop arity xs)

      -- The identity on the last operand, wherever it stands among the
      -- proofs and types (a cell's form or a frame's extents before it
      -- are not read): saturated, that argument's value alone, the ones
      -- past its arity applied to it; below its arity a closure over its
      -- missing operands, whose body is the saturated identity, as every
      -- hook is below its arity.
      identity : FC -> Loc -> (arity : Nat) -> Operands arity (S k) -> Defined -> ClosedTerm -> List (Arg vars nv) ->
                 Front (Term nv)
      identity fc loc arity ops d ty xs = case saturation arity xs of
        Saturated now rest => do
          v <- (Data.Vect.index (lastOperand ops) now).translated Synthesized
          applyOver ctx env fc loc (pure (show name)) v (termType ctx.depth (scopeOf env) v) !(typeAfter ty (toList now)) rest
        -- Its value is the last operand, of its parameter's binder's type.
        Short => do
          (kinds, resTy) <- classifyCall fc ctx.owner (show name) arity ty (argValues xs)
          given <- operandsGiven fc loc (memberPlaces d) ops kinds 0 xs
          lastBinder <- operandBinder fc (Data.Vect.index (lastOperand ops) kinds)
          completed loc arity xs given (MkMaker (\ys => Data.Vect.last ys)) lastBinder.type resTy

      -- Is the definition being translated one whose calls end the program
      -- (`Hook.Exits`, `System.exitWith`)? Its `believe_me` gives the
      -- exit's `PrimIO ()` any result, which is sound only because that
      -- action does not return; anywhere else `believe_me` stays an escape
      -- hatch.
      exiting : Front (Maybe ExitTypes)
      exiting = do
        -- A member at a use is no definition, and so no exit's.
        let OfDefinition n _ = ctx.request.instantiates
          | AtUse _ => pure Nothing
        owner <- lookupDef afc ctx.owner n
        pure owner.exitTypes

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

      exitCast : Defined -> Front (Maybe ExitTypes)
      exitCast d = do
        wrapper <- believeMe d
        if wrapper then exiting else pure Nothing

      -- The exit's `believe_me`, on the action: the action applied to the
      -- world, after which nothing runs, each at the type the boundary read
      -- off Idris's types (`ExitTypes`). The action is bound at its type,
      -- an action on the world giving an `IORes` of `actionGives`, so the
      -- variable that applies it is of the type it is applied at. The
      -- exit's value is a lambda of the world, which never returns: its
      -- result is the one its position expects where that is an action on
      -- the world, as Idris's elaborator checked it there, and else the
      -- action's own, which a value that never returns may be given.
      exitAction : ExitTypes -> FC -> Loc -> Nat -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      exitAction exit fc loc arity ty xs = do
        (found, resTy) <- classifyCall fc ctx.owner (show name) arity ty (argValues (take arity xs))
        let kinds = toList found
        given <- arguments loc (memberPlaces d) kinds (take arity xs)
        acted <- coreType fc ctx.owner ValueType exit.actionGives
        let actionWorld = MkBinder exit.actionWorld WorldT
            action = FunT actionWorld acted
            (valueWorld, result) = case (drop arity xs, ex) of
                                     ([], ExpectedAt (FunT b@(MkBinder _ WorldT) r)) => (b, r)
                                     _ => (MkBinder exit.valueWorld WorldT, acted)
        mk <- exits actionWorld acted action valueWorld result (runtimeBinders kinds)
        finish loc kinds arity xs given mk (FunT valueWorld result) resTy
        where
          exits : (actionWorld : Binder) -> (acted, action : Ty) -> (valueWorld : Binder) -> (result : Ty) ->
                  Vect r Binder -> Front (Maker r)
          exits actionWorld acted action valueWorld result [] =
            unshaped fc "the registry names an exit whose action the definition does not take"
          exits actionWorld acted action valueWorld result (_ :: _) =
            pure (MkMaker (\ns => Lam noLoc (shown "world") valueWorld result
                                     (Let loc (shown "action") (Checked (MkBinder Many action)) (weakenUnder 1 (Data.Vect.last ns))
                                          (Let loc (shown "exited") (OfValue Many)
                                               (App loc actionWorld acted (Var loc FZ) (Var loc (FS FZ)))
                                               (Unreachable loc)))))

      -- A call of a monomorphic library function a hook of the callee
      -- names, which the boundary read against its definition
      -- (`CheckedLibrary`): it takes `count` values at run time, as many as
      -- the hook gives it, so the call is saturated.
      libraryCall : {count : Nat} -> FC -> Loc -> CheckedLibrary count -> Front ({0 m : Nat} -> Vect count (Term m) -> Term m)
      libraryCall {count} fc loc checked = do
        let lib = checked.library
        target <- lookupDef fc ctx.owner lib.name
        let def = target.def
        let Just m = target.matched
          | Nothing => reject fc (show lib.named) HookShape "the registry names a library function that is not a definition"
        let arity = length m.args
        let vals = the ArgValues (replicate arity Nothing)
        kinds <- classifyKeys fc ctx.owner (show lib.named) (length m.args) target.type vals
        sig <- request fc ctx.owner (OfDefinition (fullname def) m) kinds
        called <- atCall fc ctx.owner vals sig
        -- Which of its parameters exist at run time is its own signature's,
        -- keyed by no static argument and classified apart from the call's
        -- kinds, so it is read there, once, against the row's operands: a
        -- value at each, nothing at run time elsewhere, which is the
        -- `count` values the hook gives it, by type. A type, an
        -- implementation, a form or a choice among them is a compile-time
        -- argument the hook cannot give.
        let Just (Element _ saturated) = valuesAt checked.operands called.kinds
          | Nothing => reject fc (show lib.named) HookShape "the registry names a library function with compile-time arguments"
        -- Its runtime arguments are all a call gives it, so no index
        -- parameter of it is given a term it is linked to.
        is <- callIndices called.kinds vals
        let mk = recount (sym saturated) (recount called.sameCount (MkMaker (\ys => Call loc sig.callee Nothing is ys)))
        pure (\ns => mk.make ns)
        where
          -- The kinds as the row's operands read them: a runtime value at
          -- each operand, an erased or index parameter at each binder of
          -- quantity 0, so the kinds bind at run time as many values as the
          -- operands are. The evidence is erased: reading the kinds builds
          -- no proof at run time.
          valuesAt : {0 p, k : Nat} -> Operands p k -> (ks : List PKind) -> Maybe (Subset () (\_ => Runtimes ks = k))
          valuesAt NoParameter [] = Just (Element () Refl)
          valuesAt (Operand ops) (ValueParam _ _ _ :: ks) = map oneMore (valuesAt ops ks)
            where
              oneMore : Subset () (\_ => Runtimes ks = j) -> Subset () (\_ => S (Runtimes ks) = S j)
              oneMore (Element u same) = Element u (cong S same)
          valuesAt (NoOperand ops) (ErasedParam :: ks) = valuesAt ops ks
          valuesAt (NoOperand ops) (IndexParam _ :: ks) = valuesAt ops ks
          valuesAt _ _ = Nothing

      -- The value of a head that takes one runtime argument, made from it;
      -- a head of another number of them is not the one `wrong` names.
      -- Idris flags a constructor a successor only where it takes one
      -- runtime argument, and the flag does not carry the count: the call
      -- is where the frontend first reads both, so a successor of another
      -- count is refused, as the compiled module it is.
      single : FC -> String -> ({0 m : Nat} -> Term m -> Term m) -> Vect r Binder -> Front (Maker r)
      single fc wrong f [_] = pure (MkMaker (\[y] => f y))
      single fc wrong f _ = reject fc ctx.owner CompiledModule wrong

      -- A constructor of a `Nat`-like type is a natural: zero is 0, a
      -- successor adds 1 to its one runtime argument (the others are
      -- erased indices, as `FS`'s). A successor of a literal is one
      -- literal, so a closed chain of them, a numeral Idris wrote, is one
      -- constant however large, never a chain of additions.
      natConstructor : FC -> Loc -> NatRole -> (kinds : List PKind) -> (arity : Nat) -> (xs : List (Arg vars nv)) ->
                       Vect (Runtimes (take (length (take arity xs)) kinds)) (Term nv) -> ClosedTerm -> Front (Term nv)
      natConstructor fc loc Zero kinds arity xs given resTy =
        finish loc kinds arity xs given (MkMaker (\_ => Literal loc (LNat 0))) (NatT IOpaque) resTy
      natConstructor fc loc Succ kinds arity xs given resTy = do
        mk <- single fc "a successor without one runtime argument" successor (runtimeBinders kinds)
        finish loc kinds arity xs given mk (NatT IOpaque) resTy
        where
          successor : {0 m : Nat} -> Term m -> Term m
          successor (Literal _ (LNat k)) = Literal loc (LNat (k + 1))
          successor y = PrimApp loc (Op bigAdd (NatT IOpaque) made) Nothing [y, Literal loc (LNat 1)]

      -- A constructor application: the fields, or for a type with one
      -- runtime field the field itself, since such a value is its field's.
      constructor : FC -> Loc -> Defined -> ClosedTerm -> Nat -> List (Arg vars nv) -> Front (Term nv)
      constructor fc loc d ty arity xs = do
        let def = d.def
        (found, resTy) <- classifyCall fc ctx.owner (show (fullname def)) arity ty (argValues (take arity xs))
        let kinds = toList found
        -- A constructor of Idris's `Nat` is a natural; one of any family,
        -- a numeral family (`Fin`) among them, is the family's.
        family <- dataOf fc ctx.owner !(normaliseClosed resTy)
        case (natRole def, family) of
          (Just role, Nothing) => do
            given <- arguments loc (memberPlaces d) kinds (take arity xs)
            natConstructor fc loc role kinds arity xs given resTy
          -- A constructor's type ends in its type constructor, and one that
          -- names no family and no natural is a type the registry gives a
          -- representation of its own: a value array, abstract, which only
          -- the functions the registry knows open, their bodies not
          -- translated; an ordered array or a machine word likewise.
          (_, Nothing) => do
            Just _ <- arrayView !(normaliseClosed resTy)
              | Nothing => reject fc (show (fullname def)) HookShape
                             ("the type of " ++ show (fullname def) ++ " has the representation the registry " ++
                              "gives it: its constructor is applied")
            reject fc (show (fullname def)) HookShape
                   ("the array type of " ++ show (fullname def) ++ " is opaque: its constructor is applied")
          (_, Just (inst, _)) => do
            -- Its tag is its place among its type's constructors, which
            -- the family was registered with: Idris's numbering. The
            -- application is where the frontend first reads the
            -- constructor it builds with, so one its type does not list is
            -- refused here, as the compiled module it is.
            Just cid <- conIdOf inst d
              | Nothing => reject fc ctx.owner CompiledModule
                                  ("an application of " ++ show (fullname def) ++ ", which its type does not list as a constructor")
            -- The family's registration wrote a layout for each of its
            -- constructors, in a table its identities key, whose type does
            -- not say every identity it mints has one.
            let Just info = lookupFact (.cons) cid !(getState)
              | Nothing => internal fc ("the constructor " ++ show (fullname def) ++ " is not registered")
            -- Its fields are the call's runtime arguments, as many as its
            -- layout has, by construction (`asFields`): an implementation
            -- the constructor holds is a field like any other, the value of
            -- its choice the construction site gives.
            let (fields ** counted) = asFields info.args kinds
            given <- arguments loc (memberPlaces d) fields (take arity xs)
            let con = info.con
            links <- binderTerms con.binders (argValues (take arity xs))
            finish loc fields arity xs given (recount counted (MkMaker (\ys => ConApp loc con links ys))) (conType con links) resTy

      -- A constructor's kinds, one per argument its layout lists, the
      -- layout's fields the values at run time and nothing else: the
      -- registration read the constructor's fields once, so the call gives
      -- as many runtime arguments as it has fields, by type, and the
      -- classification says only how each field's value is read. A field
      -- it read as a value is that value, in the call's scope; an
      -- implementation the constructor holds is its field's binder, its
      -- value the argument translated, a member of its choice where the
      -- site fixes the implementation. An argument that is no field exists
      -- only at compile time.
      asFields : (as : List ArgKind) -> List PKind -> (fs : List PKind ** Runtimes fs = fieldCount as)
      asFields [] _ = ([] ** Refl)
      asFields (Field _ b t :: as) ks =
        let (b', shape, t') = fieldRead b t ks
            (fs ** same) = asFields as (drop 1 ks) in
        (ValueParam b' shape t' :: fs ** cong S same)
      asFields (Param _ :: as) ks = let (fs ** same) = asFields as (drop 1 ks) in (ErasedParam :: fs ** same)
      asFields (ErasedArg :: as) ks = let (fs ** same) = asFields as (drop 1 ks) in (ErasedParam :: fs ** same)

      -- How a field's value is read: as the classification read the value
      -- at its position, or as the layout's binder holds it.
      fieldRead : Binder -> ClosedTerm -> List PKind -> (Binder, Maybe ClosedTerm, ClosedTerm)
      fieldRead b t (ValueParam b' shape t' :: _) = (b', shape, t')
      fieldRead b t _ = (b, Nothing, t)

      primitive : FC -> Loc -> Name -> (arity : Nat) -> PrimFn arity -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      primitive fc loc n arity op ty xs = case op of
        BelieveMe => do
          Just exit <- exiting
            | Nothing => reject fc ctx.owner EscapeHatch "believe_me"
          exitAction exit fc loc arity ty xs
        -- A user's crash is rejected. A trusted library's is the string it
        -- is given: the program ends with that string and does not return.
        Crash => do
          here <- toLoc ctx.fc
          if covers Trusted here.origin
            then case last' (take arity xs) of
              Just m => do
                s <- m.translated (ExpectedAt StrT)
                pure (CrashWith loc s)
              Nothing => reject fc ctx.owner EscapeHatch "idris_crash"
            else reject fc ctx.owner EscapeHatch "idris_crash"
        _ => supported
        where
          -- The primitive on the arguments its type takes, one per operand
          -- of its translation.
          supported : Front (Term nv)
          supported = do
            (found, resTy) <- classifyCall fc ctx.owner (show n) arity ty []
            let kinds = toList found
            result <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
            let Just mk = primTerm loc result op
              | Nothing => reject fc ctx.owner Primitive ("primitive " ++ show n)
            -- A builtin's arity and its type are both Idris's own, and the
            -- arity its definition carries is not tied to its type's
            -- binders: the call is where the frontend first reads both, so
            -- a builtin whose two disagree is refused, as the compiled
            -- module it is.
            let Yes counted = decEq (Runtimes kinds) arity
              | No _ => reject fc ctx.owner CompiledModule
                               ("the primitive " ++ show n ++ " given " ++ show (Runtimes kinds) ++
                                " runtime arguments, of its " ++ show arity)
            given <- arguments loc (memberPlaces d) kinds (take arity xs)
            finish loc kinds arity xs given (recount counted (MkMaker mk)) result resTy

      -- A call of the library function a foreign definition stands for, as
      -- it was read with the definition (`LibraryFunction`).
      aliasCall : FC -> Loc -> Maybe Shown -> LibraryFunction -> List (Arg vars nv) -> Front (Term nv)
      aliasCall fc loc lowered lib xs = do
        target <- lookupDef fc ctx.owner lib.name
        let Just m = target.matched
          | Nothing => reject fc (show lib.named) HookShape "the registry names a library function that is not a definition"
        call fc loc target lowered m xs

      -- What an IO primitive gives besides the next world, as many values
      -- as its action gives: for none, the unit its `IORes` holds, the one
      -- constructor of its value's type; for one, that value.
      gives : {0 count : Nat} -> FC -> IOAction i count -> Con 2 -> Front (IOGives count)
      gives fc a res = case actionGives a of
        GivesNone => GivesUnit <$> onlyCon fc 0 (unshaped fc) (Data.Vect.index 0 res.fields).type
        GivesOne => pure GivesValue

      -- The type arguments of a call, in order.
      typeParams : List PKind -> List ClosedTerm
      typeParams (TypeParam t :: ks) = t :: typeParams ks
      typeParams (_ :: ks) = typeParams ks
      typeParams [] = []

      -- The Idris type of a runtime argument a call gives.
      runtimeType : PKind -> Maybe ClosedTerm
      runtimeType (ValueParam _ _ t) = Just t
      runtimeType _ = Nothing

      -- The constructors of a snoc list of naturals (`Extents`, `Index`),
      -- in tag order, the order the library declares them in: the empty
      -- one and the snoc of the rest and the natural.
      snocCons : FC -> Ty -> Front Snocs
      snocCons fc (DataT inst _) = do
        st <- getState
        -- A family's identity is minted by its registration, which writes
        -- it in the table this reads, whose type does not say so.
        let Just decl = familyOf inst st
          | Nothing => internal fc ("extents or coordinates of an undeclared type " ++ show inst)
        let [(0 ** lin), (2 ** snoc)] = decl.cons
          | _ => unshaped fc ("the array language's extents or coordinates of " ++ show inst ++
                              ", which is not a snoc list of naturals")
        pure (MkSnocs lin snoc)
      snocCons fc t = unshaped fc ("the array language's extents or coordinates of type " ++ show t)

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

      -- An operation of the array language on its operands, whose binders
      -- (`bs`) are as the call's classification reads its parameters and
      -- whose values are of the types `vs` (`boundTypes`): a function an
      -- operand gives is applied at its value's own type, the one `Emit`
      -- gives the variable it is bound to.
      arrayTerm : {0 count : Nat} -> FC -> Loc -> ArrayPrim -> Ty -> Vect count Binder -> Vect count Ty -> List Ty ->
                  List ClosedTerm -> Front (Maker count)
      arrayTerm fc loc g rt bs vs typeArgs idrisTypes = case (g, map (.type) bs, vs) of
        (AShape, [xTy], _) => do
          a <- theElement
          s <- snocCons fc rt
          (rx ** xa) <- arrayOf xTy
          let r = minus rx (rank a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [x] =>
                  snocValue loc s (map (\j => Tensor loc (Extent xa j (Var loc x))) (take r (toList (Data.Vect.allFins rx))))))
        (ATabulate, [eTy, _], [_, FunT ib@(MkBinder _ idxTy) bTy]) => do
          eSnoc <- snocCons fc eTy
          iSnoc <- snocCons fc idxTy
          let r = minus (rank rt) (rank bTy)
          cellsFixed fc rt r
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [e, f] =>
                  apart loc eSnoc r e (\ren', ds =>
                              Tabulate loc rt (map (Var loc) (fromList ds))
                                (App loc ib bTy (Var loc (Free {k = length ds} (ren' f)))
                                         (snocValue loc iSnoc (map (Var loc . Bound) (toList (Data.Vect.allFins (length ds)))))))))
        (AIndex, [xTy, iTy], _) => do
          iSnoc <- snocCons fc iTy
          (rx ** xa) <- arrayOf xTy
          let r = minus rx (rank rt)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [x, i] =>
                  apart loc iSnoc r i (\ren', cs => Tensor loc (Extract xa rt (Var loc (ren' x)) (map (Var loc) cs)))))
        (AUpdate, [xTy, iTy, vTy], _) => insert xTy iTy vTy bs
        (AWrite, [lTy, iTy, vTy], _) => do
          (writing, ds, e) <- cellOf lTy
          iSnoc <- snocCons fc iTy
          let r = minus (length ds) (rank vTy)
              xa = MkArrayType (Data.Vect.fromList ds) e
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [l, i, v] =>
                  opened loc writing l (\ren', x =>
                    apart loc iSnoc r (ren' i) (\ren'', cs =>
                      ConApp loc writing []
                        [Tensor loc (Insert xa (TensorT ds e) (Var loc (ren'' x)) (Var loc (ren'' (ren' v))) (map (Var loc) cs))]))))
        (AFoldLast, [_, zTy, xTy], [FunT ab (FunT eb out), _, _]) => reduce FoldLast ab eb out zTy xTy bs
        (AScanLast, [_, zTy, xTy], [FunT ab (FunT eb out), _, _]) => reduce ScanLast ab eb out zTy xTy bs
        (AReshape, [eTy, xTy], _) => do
          a <- theElement
          eSnoc <- snocCons fc eTy
          (_ ** xa) <- arrayOf xTy
          let r = minus (rank rt) (rank a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [e, x] =>
                  apart loc eSnoc r e (\ren', es => Tensor loc (Reshape xa rt (Var loc (ren' x)) (map (Var loc) es)))))
        -- The cells put back with the extents given, not the ones the
        -- cells hold: an empty frame has no cell to read them from, so the
        -- array is flattened and expanded to the frame's extents and then
        -- the given ones.
        (AMerge, [eTy, xTy], _) => do
          a <- theElement
          eSnoc <- snocCons fc eTy
          cellAxes <- cellRank
          (rx ** xa) <- arrayOf xTy
          let frame = minus (minus rx (rank a)) cellAxes
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [e, x] =>
                  apart loc eSnoc cellAxes e (\ren', es =>
                    Tensor loc (Reshape xa rt (Var loc (ren' x))
                                  (map (\j => Tensor loc (Extent xa j (Var loc (ren' x)))) (take frame (toList (Data.Vect.allFins rx)))
                                   ++ map (Var loc) es)))))
        -- A transpose swaps its axis with the one after it, so its array
        -- has an axis past the one it names.
        (ATranspose, [xTy], _) => do
          a <- theElement
          (S rx ** xa) <- arrayOf xTy
            | (Z ** _) => unshaped fc "the array language's transpose, of an array of no axis"
          axis <- axisOf rx (minus (lastAxis xTy a) 1)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [x] => Tensor loc (Transpose xa rt axis (Var loc x))))
        (ATake, [_, xTy], _) => do
          a <- theElement
          (rx ** xa) <- arrayOf xTy
          ra <- ofRank rx rt
          axis <- axisOf rx (lastAxis xTy a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [k, x] => Tensor loc (Take xa ra axis (Var loc k) (Var loc x))))
        (ADrop, [_, xTy], _) => do
          a <- theElement
          (rx ** xa) <- arrayOf xTy
          ra <- ofRank rx rt
          axis <- axisOf rx (lastAxis xTy a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [k, x] => Tensor loc (Drop xa ra axis (Var loc k) (Var loc x))))
        (AConcat, [xTy, yTy], _) => do
          a <- theElement
          (rx ** xa) <- arrayOf xTy
          ya <- ofRank rx yTy
          ra <- ofRank rx rt
          axis <- axisOf rx (lastAxis xTy a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [x, y] => Tensor loc (Concat xa ya ra axis (Var loc x) (Var loc y))))
        (APad, [_, _, vTy, xTy], _) => do
          (rx ** xa) <- arrayOf xTy
          ra <- ofRank rx rt
          axis <- axisOf rx (lastAxis xTy vTy)
          fill <- fillOf (minus rx (S (finToNat axis))) vTy
          let front = alongAxis axis xa
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [lo, hi, v, x] =>
                  Tensor loc (Concat front front ra axis
                    (Tensor loc (Concat front xa front axis (copies xa axis fill (Var loc x) (Var loc lo) (Var loc v)) (Var loc x)))
                    (copies xa axis fill (Var loc x) (Var loc hi) (Var loc v)))))
        (AWithArray, [eTy, vTy, _], [_, _, FunT lb@(MkBinder _ lTy) kr]) => do
          (writing, ds, e) <- cellOf lTy
          eSnoc <- snocCons fc eTy
          let r = minus (length ds) (rank vTy)
          fill <- fillOf (minus (length ds) r) vTy
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [ex, v, k] =>
                  apart loc eSnoc r ex (\ren', ns =>
                    App loc lb kr (Var loc (ren' k))
                        (ConApp loc writing [] [filled ds e fill (map (Var loc) ns) (Var loc (ren' v))]))))
        -- The element is read at the type of the held array's cells and
        -- given at the element's, which may fix extents the cells leave to
        -- their values.
        (ARead, [lTy, iTy], _) => do
          (writing, ds, e) <- cellOf lTy
          a <- theElement
          iSnoc <- snocCons fc iTy
          res <- onlyCon fc 2 (unshaped fc) rt
          let r = minus (length ds) (rank a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [l, i] =>
                  opened loc writing l (\ren', x =>
                    apart loc iSnoc r (ren' i) (\ren'', cs =>
                      ReadBack loc (cellAfter r ds e) (Var loc (ren'' x)) (map (Var loc) cs)
                        (ConApp loc res [] [ Var loc (Bound {k = 2} FZ)
                                           , ConApp loc writing [] [Var loc (Bound {k = 2} (FS FZ))]])))))
        -- A thaw hands the continuation the array itself in a writable
        -- cell: whether writing it needs a copy first is bufferization's to
        -- decide, which sees whether anything reads the array after.
        (AThaw, [_, _], [_, FunT lb@(MkBinder _ lTy) kr]) => do
          (writing, _, _) <- cellOf lTy
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [x, k] =>
                  App loc lb kr (Var loc k) (ConApp loc writing [] [Var loc x])))
        (ALShape, [lTy], _) => do
          (writing, ds, _) <- cellOf lTy
          res <- onlyCon fc 2 (unshaped fc) rt
          a <- theElement
          s <- snocCons fc (Data.Vect.index 0 res.fields).type
          let r = minus (length ds) (rank a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [l] =>
                  opened loc writing l (\ren', x =>
                    ExtentsBack {k = r} loc (Var loc x)
                      (ConApp loc res []
                         [ snocValue loc s (toList (map (\j => Var loc (Bound (weaken j))) (allFins r)))
                         , ConApp loc writing [] [Var loc (Bound (last {n = r}))]]))))
        -- The grown array fills a cell of the result's type, as long on the
        -- last axis as the result's shape says.
        (AGrow, [_, vTy, lTy], _) => do
          (writing, ds, e) <- cellOf lTy
          (grown, gds, _) <- cellOf rt
          let xa = MkArrayType (Data.Vect.fromList ds) e
          ga <- ofRank (length ds) (TensorT gds e)
          axis <- axisOf (length ds) (lastAxis (TensorT ds e) vTy)
          fill <- fillOf (minus (length ds) (S (finToNat axis))) vTy
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [k, v, l] =>
                  opened loc writing l (\ren', x =>
                    ConApp loc grown []
                      [Tensor loc (Concat xa (alongAxis axis xa) ga axis
                         (Var loc x) (copies xa axis fill (Var loc x) (Var loc (ren' k)) (Var loc (ren' v))))])))
        (ATabulateIO, [eTy, _], [_, FunT ib@(MkBinder _ idxTy) stepAction@(FunT wb@(MkBinder _ WorldT) step@(DataT _ _))]) => do
          FunT rb@(MkBinder _ WorldT) done@(DataT _ _) <- pure rt
            | _ => unshaped fc "the array language's world-ordered tabulation, whose result is no action"
          stepCon <- onlyCon fc 2 (unshaped fc) step
          doneCon <- onlyCon fc 2 (unshaped fc) done
          let arrTy = (Data.Vect.index 0 doneCon.fields).type
          a <- theElement
          eSnoc <- snocCons fc eTy
          iSnoc <- snocCons fc idxTy
          let r = minus (rank arrTy) (rank a)
          cellsFixed fc arrTy r
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [e, act] =>
                  apart loc eSnoc r e (\ren', ds =>
                                Lam noLoc (shown "world") rb done
                                  (TabulateIO loc arrTy (map (Var loc . FS) (fromList ds)) (Var loc FZ)
                                     (App loc wb step
                                          (App loc ib stepAction (Var loc (Free {k = S (length ds)} (FS (ren' act))))
                                                   (snocValue loc iSnoc
                                                      (map (Var loc . Bound . weaken) (toList (Data.Vect.allFins (length ds))))))
                                          (Var loc (Bound (last {n = length ds}))))
                                     stepCon doneCon))))
        _ => unshaped fc "the array language's function, at operand types it does not have"
        where
          -- The constructor of a linear array's cell, and the dimensions
          -- and element of the array it holds.
          cellOf : Ty -> Front (Con 1, List Dim, Ty)
          cellOf t = do
            c <- onlyCon fc 1 (unshaped fc) t
            case (Data.Vect.head c.fields).type of
              TensorT ds e => pure (c, ds, e)
              held => unshaped fc ("the array language's linear array, whose cell holds a value of type " ++ show held)

          -- The type of the cells after the first `r` axes of an array of
          -- `ds` of `e`: its element when they are all its axes.
          cellAfter : Nat -> List Dim -> Ty -> Ty
          cellAfter r ds e = case drop r ds of
            [] => e
            cds => TensorT cds e

          -- An operand's type as an array of its rank, which the hook takes
          -- there: a value of another type is no operand of it.
          arrayOf : Ty -> Front (r : Nat ** ArrayType r)
          arrayOf (TensorT ds e) = pure (length ds ** MkArrayType (Data.Vect.fromList ds) e)
          arrayOf t = unshaped fc ("the array language's function, given a value of type " ++ show t ++ " for an array")

          -- An operand's type as an array of the rank another one has, as
          -- the hook takes its arrays.
          ofRank : (r : Nat) -> Ty -> Front (ArrayType r)
          ofRank r t = do
            (q ** a) <- arrayOf t
            case decEq q r of
              Yes Refl => pure a
              No _ => unshaped fc ("the array language's function, given an array of rank " ++ show q ++
                                   " where one of rank " ++ show r ++ " goes")

          -- An axis of an array of rank `r`, as the hook's types place it.
          axisOf : (r : Nat) -> Nat -> Front (Fin r)
          axisOf r a = case natToFin a r of
            Just axis => pure axis
            Nothing => unshaped fc ("the array language's function, along axis " ++ show a ++
                                    " of an array of rank " ++ show r)

          -- What fills each slot of an array made of a cell of type `vTy`,
          -- where `after` of the array's axes follow the ones the cell is
          -- repeated along: the cell itself where none does, else the
          -- cell's element at the slot's coordinates past them, the cell an
          -- array of those axes.
          fillOf : (after : Nat) -> (vTy : Ty) -> Front Fill
          fillOf Z vTy = pure WholeCell
          fillOf (S _) vTy = do
            (rv ** va) <- arrayOf vTy
            pure (ElementOfCell {r = rv} va)

          -- The extents of a cell, each read off it: none for an element.
          cellExtents : {0 m : Nat} -> Fill -> Term m -> List (Term m)
          cellExtents WholeCell v = []
          cellExtents (ElementOfCell {r} va) v = map (\j => Tensor loc (Extent va j v)) (toList (Data.Vect.allFins r))

          -- A new array of `ds` of `e` whose leading extents are given and
          -- whose every cell is `v`, each slot filled as `fill` says: the
          -- cells' extents are `v`'s, read off it, so no type need fix
          -- them, and every slot is written once.
          filled : {0 m : Nat} -> List Dim -> Ty -> Fill -> List (Term m) -> Term m -> Term m
          filled ds e fill ns v =
            let es = ns ++ cellExtents fill v
                v' = weakenUnder (length es) v
                body = case fill of
                         WholeCell => v'
                         ElementOfCell va =>
                           Tensor loc (Extract va e v' (map (Var loc . Bound) (drop (length ns) (toList (Data.Vect.allFins (length es))))))
            in Tabulate loc (TensorT ds e) (Data.Vect.fromList es) body

          -- The one type argument of a call that has one: the element or
          -- the cell.
          theElement : Front Ty
          theElement = case typeArgs of
            [a] => pure a
            _ => unshaped fc "the array language's function, without its one type argument"

          -- How many axes the cells of an array of arrays take, read from
          -- the Idris type of the array, the last runtime argument: a
          -- tensor's type holds the frame's axes and the cells' as one run,
          -- so where one ends is read where Idris still tells them apart.
          cellRank : Front Nat
          cellRank = do
            Just outer <- pure (last' idrisTypes)
              | Nothing => unshaped fc "the array language's function, without its array"
            Just (_, cellTy) <- arrayView outer
              | Nothing => unshaped fc "the array language's function, given no array of arrays"
            Just (c, _) <- arrayView cellTy
              | Nothing => unshaped fc "the array language's function, given no array of arrays"
            sp <- spineOf fc ctx.owner c
            pure (length sp.axes)

          -- The shape's last axis of an array whose cell has the type given.
          lastAxis : Ty -> Ty -> Nat
          lastAxis xTy cellTy = minus (minus (rank xTy) 1) (rank cellTy)

          -- An array like one of type `xa` with the length of its axis `a`
          -- left to its value.
          alongAxis : Fin r -> ArrayType r -> ArrayType r
          alongAxis a xa = { dims := Data.Vect.replaceAt a Dynamic xa.dims } xa

          -- `n` copies of the cell `v` along axis `a` of an array like `x`,
          -- of type `xa`, its other axes `x`'s, the cell's among them, each
          -- slot filled as `fill` says: a new array of every element, each
          -- copy its own, whatever the element holds. A pad, and a growth,
          -- is the array joined to such copies, so that every slot of the
          -- result is written once.
          copies : {0 m : Nat} -> {rx : Nat} -> ArrayType rx -> Fin rx -> Fill -> (x, n, v : Term m) -> Term m
          copies xa a fill x n v =
            let es = map (\j => if j == a then n else Tensor loc (Extent xa j x)) (toList (Data.Vect.allFins rx))
                v' = weakenUnder (length es) v
                body = case fill of
                         WholeCell => v'
                         ElementOfCell va =>
                           Tensor loc (Extract va xa.element v'
                                         (map (Var loc . Bound) (drop (S (finToNat a)) (toList (Data.Vect.allFins (length es))))))
            in Tabulate loc (arrayTy (alongAxis a xa)) (Data.Vect.fromList es) body

          insert : Ty -> Ty -> Ty -> Vect 3 Binder -> Front (Maker 3)
          insert xTy iTy vTy three = do
            iSnoc <- snocCons fc iTy
            (rx ** xa) <- arrayOf xTy
            let r = minus rx (rank vTy)
            pure $ MkMaker (\ys => bindArguments loc three ys (\ren, [x, i, v] =>
                    apart loc iSnoc r i (\ren', cs =>
                      Tensor loc (Insert xa rt (Var loc (ren' x)) (Var loc (ren' v)) (map (Var loc) cs)))))

          -- A reduction of the array along the axis after the frame of its
          -- accumulators, the axes the accumulators' array has beyond one
          -- accumulator's, by the function the first operand is, of the
          -- accumulator (`ab`) and then the element (`eb`) to the next
          -- accumulator (`out`).
          reduce : Reduction -> (ab, eb : Binder) -> (out, z, x : Ty) -> Vect 3 Binder -> Front (Maker 3)
          reduce red ab eb out zTy xTy three = do
            (rx ** xa) <- arrayOf xTy
            axis <- axisOf rx (minus (rank zTy) (rank ab.type))
            pure $ MkMaker (\ys => bindArguments loc three ys (\ren, [g, z, x] =>
              Reduce loc red ab.type eb.type rt xa axis (Var loc z) (Var loc x)
                (App loc eb out (App loc ab (FunT eb out) (Var loc (Free {k = 2} g)) (Var loc (Bound {k = 2} FZ)))
                         (Var loc (Bound {k = 2} (FS FZ))))))

      -- What a lowering makes of its `k` operands (`Resolve.Lowering`), read
      -- in this scope: the operands' binders (`bs`) and the types their
      -- values are bound at (`vs`, `boundTypes`), the call's kinds and the
      -- Core type of its result (`rt`), read once, where the call is
      -- classified.
      maker : {k : Nat} -> FC -> Loc -> Maybe Shown -> (bs : Vect k Binder) -> (vs : Vect k Ty) -> Vect n PKind -> (rt : Ty) ->
              Lowering CheckedLibrary k -> Front (Maker k)
      maker fc loc lowered bs vs kinds rt (NatPrimitive p) = pure (MkMaker (\ns => PrimApp loc p lowered ns))
      maker fc loc lowered bs vs kinds rt (NatClamped p) =
        pure (MkMaker (\ns => PrimApp loc (Op natFromBig (NatT IOpaque) made) lowered
                                [PrimApp loc p lowered (map (\n => PrimApp loc (Op natToBig BigT made) lowered [n]) ns)]))
      maker fc loc lowered bs vs kinds rt (NatTested test lib) = do
        toBool <- libraryCall fc loc lib
        pure (MkMaker (\ns => toBool [PrimApp loc test lowered ns]))
      maker fc loc lowered bs vs kinds rt (NatOnIntegers lib) = do
        f <- libraryCall fc loc lib
        pure (MkMaker (\ns => f (map (\n => PrimApp loc (Op natToBig BigT made) lowered [n]) ns)))
      -- A string built once from the list the definition's type takes.
      maker fc loc lowered bs vs kinds rt (Builder p fits) =
        pure (MkMaker (\ys => PrimApp loc (replace {p = Prim} fits (Op p.op rt made)) lowered ys))
      -- A function of the array language: the tensor operations of its
      -- sequential meaning, over its operands bound once each in order. A
      -- rank is read from the types of the operands and the result, never
      -- from the order of the implicits.
      maker fc loc lowered bs vs kinds rt (ArrayOperation g) = do
        typeArgs <- traverse (\t => coreType fc ctx.owner ValueType !(normaliseClosed t)) (typeParams (toList kinds))
        arrayTerm fc loc g rt bs vs typeArgs (mapMaybe runtimeType (toList kinds))
      maker fc loc lowered bs vs kinds rt IdentityOnLast = pure (MkMaker (\ys => Data.Vect.last ys))
      -- A pure primitive on the operands and then the literals the call
      -- does not supply, of the call's result type, read in this scope: a
      -- result an erased argument indexes (the bound of a numeral a
      -- natural becomes) is typed at the term the call gives it.
      maker fc loc lowered bs vs kinds rt (PureOperation p lits fits) =
        pure (MkMaker (\ys => PrimApp loc (replace {p = Prim} (sym fits) (Op p.op rt made)) lowered
                                (ys ++ map (Literal loc) (fromList lits))))
      maker fc loc lowered bs vs kinds rt (IOOperation lits a) = do
        res <- onlyCon fc 2 (unshaped fc) rt
        what <- gives fc a res
        pure (MkMaker (\ys => Effect loc a what (Data.Vect.init ys ++ map (Literal loc) (fromList lits)) (Data.Vect.last ys) res))
      -- An array access, IO in the world's order, giving the `IORes` of the
      -- call's result type, at the rank its row read off its operands.
      maker fc loc lowered bs vs kinds rt (AccessOperation access rank) = do
        res <- onlyCon fc 2 (unshaped fc) rt
        what <- gives fc (Accesses access rank) res
        pure (MkMaker (\ys => Effect loc (Accesses access rank) what (Data.Vect.init ys) (Data.Vect.last ys) res))
      -- A foreign definition's primitive on the operands and then the
      -- literals the call does not supply: a handle's test for null is a
      -- comparison with the null handle.
      maker fc loc lowered bs vs kinds rt (PrimOperation lits p) =
        pure (MkMaker (\ys => PrimApp loc p lowered (ys ++ map (Literal loc) (fromList lits))))

      -- A call of a definition a hook lowers, by its row (`Resolve.Lowered`):
      -- the hook's operands are the call's arguments at the row's
      -- positions, each read by the call's classification of its
      -- parameter, which reads their types and the result's in this scope.
      -- An IO primitive's result is read before its operands, as its
      -- families are registered before theirs.
      lowerCall : FC -> Loc -> Maybe Shown -> Lowered CheckedLibrary -> Defined -> ClosedTerm -> List (Arg vars nv) ->
                  Front (Term nv)
      lowerCall fc loc lowered (MkLowered {arity} ops IdentityOnLast) d ty xs = identity fc loc arity ops d ty xs
      lowerCall fc loc lowered (MkLowered {arity} {count} ops (IOOperation lits a)) d ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner (show (fullname d.def)) arity ty (argValues (take arity xs))
        rt <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
        MkSupplied values missing together <- operandsGiven fc loc (memberPlaces d) ops kinds 0 xs
        bs <- operandBinders fc ops kinds
        mk <- maker {k = count} fc loc lowered bs (boundTypes values missing together bs) kinds rt (IOOperation lits a)
        completed loc arity xs (MkSupplied values missing together) mk rt resTy
      lowerCall fc loc lowered (MkLowered {arity} {count} ops low) d ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner (show (fullname d.def)) arity ty (argValues (take arity xs))
        MkSupplied values missing together <- operandsGiven fc loc (memberPlaces d) ops kinds 0 xs
        rt <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
        bs <- operandBinders fc ops kinds
        mk <- maker {k = count} fc loc lowered bs (boundTypes values missing together bs) kinds rt low
        completed loc arity xs (MkSupplied values missing together) mk rt resTy

      -- A call of a definition the registry's hooks lower, whatever
      -- declares it, or `otherwise` when no hook does: a deprecated one is
      -- refused; one whose calls a hook lowers to an operation on its
      -- operands is that operation, by its row (`lowerCall`); a handle and
      -- a string of the compiler's are constants; an alias is a call of
      -- the function it stands for.
      hooked : FC -> Loc -> Name -> Maybe Shown -> Defined -> ClosedTerm -> Hooks LibraryFunction -> Front (Term nv) ->
               Front (Term nv)
      hooked fc loc full lowered d ty hs otherwise =
        let constant = \v => applyOver ctx env fc loc (pure (show full)) v (termType ctx.depth (scopeOf env) v) (Just ty) args in
        fromMaybe otherwise $
              map (reject fc ctx.owner Deprecated) hs.deprecated
          <|> map (\row => lowerCall fc loc lowered row d ty args) d.loweredBy
          <|> map (constant . Literal loc) hs.handle
          <|> map (\lib => aliasCall fc loc lowered lib args) hs.alias
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
             Ctx kc -> FC -> ClosedTerm -> Maybe (Fin nv, Holes) -> Front (Term nv)
computedAt ctx fc t held = implementationAt {vars = Scope.empty} asWritten start (sizeAccessible start) ctx [] fc t held []
