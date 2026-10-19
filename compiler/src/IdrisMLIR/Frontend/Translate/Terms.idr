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
import IdrisMLIR.Frontend.Translate.Dictionaries
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
import IdrisMLIR.Syntax.Idr
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

public export
record Ctx where
  constructor MkCtx
  owner : String
  fc : FC
  complete : Bool     -- Idris found no missing case

bestFC : Ctx -> FC -> FC
bestFC ctx fc = if isEmptyFC fc then ctx.fc else fc

||| The name of an Idris binder as Core keeps it, to name the value it
||| binds: a machine name (`{arg:12}`) by what it is, not by its counter.
export
binderName : Name -> Shown
binderName (NS _ n) = binderName n
binderName (MN s _) = shown s
binderName n = shown (show n)

||| The number of arguments a type takes, as its binders say.
binders : TT vars -> Nat
binders (Bind _ _ (Pi {}) sc) = S (binders sc)
binders _ = Z

||| The last of the arguments given at a type's binders that it takes at
||| runtime.
lastRuntime : TT vars -> List a -> Maybe a
lastRuntime (Bind _ _ (Pi _ rig _ _) sc) (x :: xs) = case lastRuntime sc xs of
  Just v => Just v
  Nothing => case use rig of
    Erased => Nothing
    Used _ => Just x
lastRuntime _ _ = Nothing

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
snocValue loc s ns = foldl (\acc, n => ConApp loc s.snoc [acc, n]) (ConApp loc s.lin []) ns

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

||| The one constructor of a data type (`Res`, `IORes`, a pair, the unit),
||| of `k` fields.
onlyCon : {auto s : Ref TState TS} -> FC -> (k : Nat) -> Ty -> Core (Con k)
onlyCon fc k (DataT inst) = do
  st <- get TState
  let Just decl = declared inst st
    | Nothing => internal fc ("a value of an undeclared type " ++ show inst)
  let [(k' ** con)] = consOf decl
    | _ => internal fc ("a value of " ++ show inst ++ ", which has not one constructor")
  let Yes Refl = decEq k' k
    | No _ => internal fc ("a value of " ++ show inst ++ ", whose constructor has " ++ show k' ++ " fields, not " ++ show k)
  pure con
onlyCon fc k t = internal fc ("a value of type " ++ show t)

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
      Let loc (shown "argument") b.quantity (rename ren t)
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
headName : {auto c : Ref Ctxt Defs} -> {vars : Scope} -> FC -> List (VarInfo a) -> TT vars -> Core String
headName fc env (Local _ _ idx p) = pure (show (nameAt {idx} p))
headName fc env tm = showTT (closeWritten fc env tm)

||| A type or an erased value where a value exists at runtime. Idris's
||| quantity check admits one only where the type of what takes it erases
||| it, which is where the translation leaves it out; here nothing does.
inRuntime : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            String -> FC -> List (VarInfo a) -> TT vars -> Core b
inRuntime owner fc env tm = do
  what <- showTT (closeWritten fc env tm)
  reject fc owner ValueType (what ++ " in a runtime position")

||| The scope of a closed function type at an argument: the argument's
||| closed normal form where the scope mentions it, nothing where it does
||| not.
instantiate : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
              FC -> List (VarInfo a) -> TT [x] -> TT vars -> Core ClosedTerm
instantiate fc env sc arg = case shrink sc (Drop Refl) of
  Just sc' => pure sc'
  Nothing => do
    value <- closeNormalise fc env arg
    pure (subst value sc)

||| The Idris type of a `let`'s value, which TTC does not keep: what tells
||| the erased arguments of a function-typed value from its runtime ones. A
||| lambda's is the telescope of its binders; an application of a
||| definition's, the definition's type after the arguments, each type
||| argument as written and each runtime one unknown; a variable's, its
||| own. Anything else's is not known here.
valueType : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
            FC -> List (VarInfo a) -> TT vars -> Core (Maybe ClosedTerm)
valueType fc env tm@(Bind _ _ (Lam {}) _) = Just <$> closeNormalise fc env (telescope tm)
  where
    telescope : TT vs -> TT vs
    telescope (Bind bfc x (Lam lfc rig info ty) sc) = Bind bfc x (Pi lfc rig info ty) (telescope sc)
    telescope _ = Erased fc Placeholder
valueType fc env tm@(Local {}) = pure (headType env tm)
valueType fc env tm = case getFnArgs tm of
  (Ref _ _ n, args) => do
    defs <- get Ctxt
    Just def <- lookupCtxtExact n (gamma defs)
      | Nothing => pure Nothing
    after (type def) args
  _ => pure Nothing
  where
    after : ClosedTerm -> List (TT vars) -> Core (Maybe ClosedTerm)
    after ty [] = pure (Just ty)
    after ty (a :: as) = do
      ty' <- case ty of
               Bind _ _ (Pi {}) _ => pure ty
               _ => normaliseClosed ty
      case ty' of
        Bind _ _ (Pi _ rig _ dom) sc =>
          after (subst (case use rig of
                          Erased => closeWritten fc env a
                          Used _ => if isTypeLike dom then closeWritten fc env a else Erased fc Placeholder) sc) as
        _ => pure Nothing

||| The runtime values an implementation closes over, as `holed` finds them:
||| the variable that holds each, when one does, its type, and its
||| translation.
Found : Nat -> Type
Found nv = List (Maybe (Fin nv), ClosedTerm, Core (Term nv))

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
||| evaluator, closed but for the variables bound around it, which
||| nothing evaluates again.
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
  translated : Lazy (Core (Term nv))
  held : Lazy (Core (Maybe (ClosedTerm, List1 (ClosedTerm, Core (Term nv)))))

||| An argument under a binder that binds nothing in Core: a compile-time
||| value, or another name for a variable.
overBinder : Arg vars nv -> Arg (x :: vars) nv
overBinder a = MkArg (weaken a.written) a.translated a.held

||| An argument under a binder that Core binds too, by a `let`.
underLet : Arg vars nv -> Arg (x :: vars) (S nv)
underLet a = MkArg (weaken a.written) (weakenUnder 1 <$> Force a.translated) (map weakened <$> Force a.held)
  where
    weakened : (ClosedTerm, List1 (ClosedTerm, Core (Term nv))) -> (ClosedTerm, List1 (ClosedTerm, Core (Term (S nv))))
    weakened (shape, values) = (shape, map (\(t, v) => (t, weakenUnder 1 <$> v)) values)

||| What a marker of a settled term stands for.
data Stand : Nat -> Type where
  ||| A variable in scope: the marker is bound as it is, with no `let`.
  AsVariable : VarInfo (Fin nv) -> Stand nv
  ||| A runtime value, bound once by a `let` before the term.
  AsValue : Lazy (Core (Term nv)) -> Stand nv

||| The values an implementation closes over, each translated.
valuesOf : {0 nv : Nat} -> List1 (ClosedTerm, Core (Term nv)) -> Core (List1 (ClosedTerm, Term nv))
valuesOf ((t, v) ::: rest) = (:::) <$> ((t,) <$> v) <*> later rest
  where
    later : List (ClosedTerm, Core (Term nv)) -> Core (List (ClosedTerm, Term nv))
    later [] = pure []
    later ((t', v') :: more) = (::) <$> ((t',) <$> v') <*> later more

||| The values an implementation closes over as the one value its parameter
||| holds (`packedType`): the value itself, or a pair of the first and the
||| rest.
pack : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {0 nv : Nat} ->
       FC -> String -> Loc -> List1 (ClosedTerm, Term nv) -> Core (Term nv)
pack fc owner loc (first ::: rest) = packed first rest
  where
    packed : (ClosedTerm, Term nv) -> List (ClosedTerm, Term nv) -> Core (Term nv)
    packed (_, v) [] = pure v
    packed (t, v) (p :: ps) = do
      DataT inst <- coreType fc owner ValueType !(normaliseClosed !(packedType (t ::: map fst (p :: ps))))
        | _ => internal fc "the values an implementation closes over, held in no pair"
      pair <- onlyCon fc 2 (DataT inst)
      pure (ConApp loc pair [v, !(packed p ps)])

||| A value applied to arguments, over the Idris type of the value where it
||| is known: an argument at a binder of quantity 0 is not passed, since
||| the value takes none there at runtime, and any other is applied. Past
||| the binders the type shows, an argument is a runtime value, and a type
||| or an erased value there is refused, naming the head (`what`).
applyOver : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            Ctx -> List (VarInfo (Fin nv)) -> FC -> Loc -> Core String ->
            Term nv -> Maybe ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
applyOver ctx env fc loc what f _ [] = pure f
applyOver ctx env fc loc what f known (x :: xs) = do
  ty <- the (Core (Maybe ClosedTerm)) $ case known of
          Just t@(Bind _ _ (Pi {}) _) => pure (Just t)
          Just t => Just <$> normaliseClosed t
          Nothing => pure Nothing
  case ty of
    Just (Bind _ _ (Pi _ rig _ _) sc) => do
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

-- The translation ends, lexicographically in the phase, the metavariables
-- entered on the path, and the term. Every step goes to a part of the term,
-- with two exceptions: a metavariable's solution, entered once on its path
-- (`Walk`), and a term Idris's evaluator settled, which is translated in
-- the phase the written one held and is never settled again. A part of
-- an application is made where it is a subterm (`argOf`), its translation
-- suspended there, so a use of it later is no step of the translation that
-- uses it.
mutual
  export
  term : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
         Ctx -> List (VarInfo (Fin nv)) -> TT vars -> Core (Term nv)
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
    -- The `let`s around a `Delay` move into it (`delayedLets`), into the
    -- innermost of a chain of them: the suspensions, outermost first, then
    -- the `let`s, then what the last `Delay` delays.
    Just _ => do
      (suspensions, inner) <- letIn ph w acc ctx env fc x rig val (\env' => delayed ph w acc ctx env' sc)
      pure (foldr Suspend inner suspensions)
    Nothing => (\((), t) => t) <$> letIn ph w acc ctx env fc x rig val (\env' => ((),) <$> term ph w acc ctx env' sc)

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
        body <- term ph w acc ctx (under {k = 1} [Runtime FZ (Just (typeOf b)) (Just known)] env) sc
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
            Ctx -> List (VarInfo (Fin nv)) -> TT vars -> Core (List Loc, Term nv)
  delayed ph w acc ctx env (TDelay dfc _ _ arg) = do
    loc <- toLoc (bestFC ctx dfc)
    (suspensions, inner) <- delayed ph w acc ctx env arg
    pure (loc :: suspensions, inner)
  delayed ph w acc ctx env (Bind fc x (Let lfc rig val ty) sc) =
    letIn ph w acc ctx env fc x rig val (\env' => delayed ph w acc ctx env' sc)
  delayed ph w acc ctx env tm = ([],) <$> term ph w acc ctx env tm

  ||| A `let`, its body translated by `body` in the scope it binds. A `let`
  ||| of quantity 0 binds a compile-time value, nothing at runtime. TTC does
  ||| not keep the types of lets (Core.TTC, `Let` binders): `Emit`
  ||| synthesizes the Core type, and the Idris type is the value's as far as
  ||| it shows.
  letIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Ctx -> List (VarInfo (Fin nv)) -> FC -> Name -> RigCount -> TT vars ->
          ({0 m : Nat} -> List (VarInfo (Fin m)) -> Core (r, Term m)) -> Core (r, Term nv)
  letIn ph w acc ctx env fc x rig val body =
    case use rig of
      Erased => body (TypeValue (Erased fc Placeholder) :: env)
      Used q => do
        loc <- toLoc (bestFC ctx fc)
        known <- valueType fc env val
        v <- term ph w acc ctx env val
        (r, inner) <- body (under {k = 1} [Runtime FZ Nothing known] env)
        pure (r, Let loc (binderName x) q v inner)

  suspend : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars -> Core (Term nv)
  suspend ph w acc ctx env fc arg = do
    loc <- toLoc (bestFC ctx fc)
    body <- term ph w acc ctx env arg
    pure (Suspend loc body)

  ||| An argument where it is a subterm of the application.
  argOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars -> Arg vars nv
  argOf ph w acc ctx env afc a = MkArg a (term ph w acc ctx env a) (holed ph ctx env afc a)

  ||| An application's spine, its arguments collected where each is a
  ||| subterm, down to its head.
  spine : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars -> List (Arg vars nv) -> Core (Term nv)
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
              Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars -> List (Arg vars nv) -> Core (Term nv)
  applyHead ph w acc ctx env afc (Local fc r idx p) args = applyVariable ph w acc ctx env afc fc r idx p args
  -- The argument is bound as what it is: a compile-time value at an erased
  -- binder; another name for a variable; at a dictionary binder, the
  -- implementation, with the values it closes over bound once; anything
  -- else, a runtime value bound by a `let`, which the application
  -- evaluates first, where the `let` translation would move it into a
  -- `Delay` the body builds (`delayedLets`).
  applyHead ph w acc ctx env afc (Bind bfc x (Lam _ rig _ ty) sc) (a :: rest) =
    case use rig of
      Erased => spine ph w acc ctx (TypeValue (closeWritten bfc env a.written) :: env) afc sc (map overBinder rest)
      Used q => case aliased a.written of
        Just e => spine ph w acc ctx (e :: env) afc sc (map overBinder rest)
        Nothing => do
          dict <- dictionaryBinder rig ty
          loc <- toLoc (bestFC ctx bfc)
          if dict then dictionary loc else do
            known <- closeNormalise bfc env ty
            v <- a.translated
            body <- spine ph w acc ctx (under {k = 1} [Runtime FZ Nothing (Just known)] env) afc sc (map underLet rest)
            pure (Let loc (binderName x) q v body)
    where
      aliased : TT vars -> Maybe (VarInfo (Fin nv))
      aliased (Local _ _ idx _) = getAt idx env
      aliased _ = Nothing

      dictionary : Loc -> Core (Term nv)
      dictionary loc = do
        impl <- solved (closeWritten bfc env a.written)
        if not !(runtimeDependent impl)
          then spine ph w acc ctx (Static impl Nothing :: env) afc sc (map overBinder rest)
          else do
            Just (shape, values) <- a.held
              | Nothing => reject (bestFC ctx bfc) ctx.owner RuntimeClosure
                                  ("an implementation chosen at runtime: " ++ !(showTT impl))
            held <- coreType bfc ctx.owner ValueType !(normaliseClosed !(packedType (map fst values)))
            v <- pack bfc ctx.owner loc !(valuesOf values)
            body <- spine ph w acc ctx
                          (under {k = 1} [Static shape (Just (FZ, MkHoles (map fst values) (MkBinder Many held)))] env)
                          afc sc (map underLet rest)
            pure (Let loc (binderName x) Many v body)
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
                  (idx : Nat) -> (0 p : IsVar n idx vars) -> List (Arg vars nv) -> Core (Term nv)
  applyVariable ph w acc ctx env afc fc r idx p args = case getAt idx env of
    Just (Runtime x _ _) => applied x
    Just (Shaped x _ _ _) => applied x
    -- Idris's quantity check of a clause keeps a binder of quantity 0 out
    -- of every position that exists at runtime, a leaf reads each binder
    -- where its clause holds it at runtime (`Forced.heldAt`), and the
    -- translation leaves out every erased position.
    Just (TypeValue _) => internal (bestFC ctx fc) "a compile-time variable in a runtime position"
    Just (Static t held) => implementationAt ph ctx env fc t held args
    Nothing => internal (bestFC ctx fc) "a variable out of scope"
    where
      applied : Fin nv -> Core (Term nv)
      applied x = do
        loc <- toLoc (bestFC ctx fc)
        let at = bestFC ctx afc
        aloc <- toLoc at
        let tm = Local fc r idx p
        applyOver ctx env at aloc (headName at env tm) (Var loc x) (headType env tm) args

  ||| An implementation the environment binds, used at runtime: as written,
  ||| applied to its arguments, it is settled by Idris's evaluator and its
  ||| normal form translated. Of a settled term, whose variables are all
  ||| runtime values but for what an implementation closes over (`holed`),
  ||| such a use is one chosen at runtime.
  implementationAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                     Phase -> Ctx -> List (VarInfo (Fin nv)) -> FC -> ClosedTerm -> Maybe (Fin nv, Holes) ->
                     List (Arg vars nv) -> Core (Term nv)
  implementationAt Settled ctx env fc t _ args =
    reject (bestFC ctx fc) ctx.owner RuntimeClosure ("an implementation chosen at runtime: " ++ !(showTT t))
  implementationAt (Written next) ctx env fc t Nothing args = settle next ctx env fc t [] args
  -- One that closes over runtime values stands for them by the projections
  -- of the variable that holds them, marker 0.
  implementationAt (Written next) ctx env fc t (Just (x, hs)) args = do
    values <- unpacked hs.types (holeMarker 0)
    settle next ctx env fc (fillHoles values t) [AsVariable (Runtime x (Just (typeOf hs.binder)) Nothing)] args

  ||| A metavariable applied, as the solution the type checker gave it,
  ||| entered once on the path.
  entered : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Ctx -> List (VarInfo (Fin nv)) -> (afc : FC) -> (fc : FC) -> Name -> Int -> List (TT vars) ->
            List (Arg vars nv) -> Core (Term nv)
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
  ||| runs at run time, and its normal form translated in phase `next`.
  ||| `value` is closed but for the markers `0 .. length pre - 1`, which
  ||| `pre` says what they stand for. Each argument is given in place when
  ||| the evaluator may see it whole, a compile-time value, and as a marker
  ||| when it is a runtime value. Since nothing is run, a value that refers
  ||| to a definition Idris does not prove ends is settled as any other.
  settle : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           (next : Phase) -> Ctx -> List (VarInfo (Fin nv)) -> FC ->
           (value : ClosedTerm) -> (pre : List (Stand nv)) -> List (Arg vars nv) -> Core (Term nv)
  settle next ctx env fc value pre args = do
    (terms, stands) <- given (length pre) args
    nf <- lambdasApplied (foldl (App EmptyFC) value terms)
    loc <- toLoc (bestFC ctx fc)
    bindStands next start (sizeAccessible start) ctx env loc 0 id (pre ++ stands) (embedClosed {vars} nf)
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
      anImplementation : TT vars -> Core Bool
      anImplementation tm = case getFnArgs tm of
        (Local _ _ idx _, _) => pure (case getAt idx env of
                                        Just (Static {}) => True
                                        _ => False)
        (Ref rfc _ n, _) => implementationType (type !(lookupDef rfc ctx.owner n))
        _ => pure False

      -- One argument for the evaluator, the new markers numbered from `k`,
      -- and what each stands for: a type in place; a runtime variable as a
      -- marker; a value that needs no runtime value where one exists, in
      -- place, as written, or once it needs none only as the implementation
      -- it reduces to (`implementationOf`), as that; an implementation that
      -- closes over runtime values by its form, its markers moved up to
      -- `k`; any other runtime value as a marker.
      argument : Nat -> Arg vars nv -> Core (ClosedTerm, List (Stand nv))
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

      given : Nat -> List (Arg vars nv) -> Core (List ClosedTerm, List (Stand nv))
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
               List (Stand m) -> TT vars -> Core (Term nv)
  bindStands ph w acc ctx env loc i ren [] body = term ph w acc ctx env body
  bindStands ph w acc ctx env loc i ren (AsVariable e :: stands) body =
    bindStands ph w acc ctx (map ren e :: env) loc (S i) ren stands (refToLocal (markerName i) (markerName i) body)
  bindStands ph w acc ctx env loc i ren (AsValue v :: stands) body = do
    value <- v
    rest <- bindStands ph w acc ctx (under {k = 1} [Runtime FZ Nothing Nothing] env) loc (S i) (FS . ren) stands
                       (refToLocal (markerName i) (markerName i) body)
    pure (Let loc (shown "held") Many (rename ren value) rest)

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
  ||| no such value.
  |||
  ||| It evaluates nothing itself: each runtime variable of the environment,
  ||| and each that holds an implementation closing over values, stands as a
  ||| marker in the written form, which Closed's reduction takes to the
  ||| implementation it stands for (`implementationOf`), and that is walked.
  holed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          Phase -> Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars ->
          Core (Maybe (ClosedTerm, List1 (ClosedTerm, Core (Term nv))))
  holed ph ctx env afc x = do
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
      writtenAs (Runtime {}) = Erased afc Impossible

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
      others : List (Nat, (Maybe (Fin nv), ClosedTerm, Core (Term nv))) ->
               List (Nat, (Maybe (Fin nv), ClosedTerm, Core (Term nv))) ->
               List (Nat, (Maybe (Fin nv), ClosedTerm, Core (Term nv)))
      others seen [] = []
      others seen (h@(_, (Just k, _, _)) :: hs) =
        if any (\(_, (k', _, _)) => k' == Just k) seen then others seen hs else h :: others (h :: seen) hs
      others seen (h :: hs) = h :: others (h :: seen) hs

      same : Nat -> Maybe (Fin nv) -> (Nat, (Maybe (Fin nv), ClosedTerm, Core (Term nv))) -> Bool
      same j (Just k) (_, (k', _, _)) = k' == Just k
      same j Nothing (j', _) = j == j'

      position : (a -> Bool) -> List a -> Nat
      position p [] = 0
      position p (y :: ys) = if p y then 0 else S (position p ys)

      -- A value of the implementation: a runtime variable as itself, any
      -- other computed from the variables in the next phase, or, in a
      -- settled term, chosen at runtime.
      piece : Phase -> ClosedTerm -> ClosedTerm -> Core (Core (Term nv))
      piece Settled impl _ =
        reject (bestFC ctx afc) ctx.owner RuntimeClosure ("an implementation chosen at runtime: " ++ !(showTT (restore impl)))
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

      value : ClosedTerm -> ClosedTerm -> ClosedTerm -> Core (Maybe (ClosedTerm, Found nv))
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
      gives : GlobalDef -> Core Bool
      gives def = case definition def of
        PMDef _ _ (STerm {}) _ _ => pure True
        DCon {} => resultIsImpl (type def)
        _ => pure False
        where
          -- The constructor's result, under its binders: an
          -- interface's own type, or a pair (whose components the
          -- binders name, so the pair is known by its type's name,
          -- not by what it pairs here).
          resultIsImpl : TT vs -> Core Bool
          resultIsImpl (Bind _ _ (Pi {}) sc) = resultIsImpl sc
          resultIsImpl tm = case getFnArgs tm of
            (Ref _ (TyCon _) tn, _) => if !(isPairType !(toFullNames tn))
                                          then pure True else implementationType tm
            _ => pure False

      -- The use and the type of the binder an argument is given at, and
      -- the rest of the type; nothing for an argument past the binders
      -- the type shows, a runtime value of a type not known here.
      binder : ClosedTerm -> (Maybe (Use, ClosedTerm), ClosedTerm -> ClosedTerm)
      binder (Bind _ _ (Pi _ rig _ aty) sc) = (Just (use rig, aty), \v => subst v sc)
      binder ty = (Nothing, const ty)

      -- An implementation is walked in turn; any other argument
      -- is a value.
      part : ClosedTerm -> ClosedTerm -> ClosedTerm -> Lazy (Core (Maybe (ClosedTerm, Found nv))) ->
             Core (Maybe (ClosedTerm, Found nv))
      part impl aty a walked = do
        aty' <- normaliseClosed aty
        if !(implementationType aty') then walked else value impl aty' a

      -- The arguments of a definition that gives `impl`, over its type,
      -- each found value numbered from 0 among the arguments' together.
      parts : ClosedTerm -> ClosedTerm -> List (ClosedTerm, Lazy (Core (Maybe (ClosedTerm, Found nv)))) ->
              Core (Maybe (List ClosedTerm, Found nv))
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
      closedOver : ClosedTerm -> Core (Maybe (ClosedTerm, Found nv))
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
          fill : Nat -> List (Nat, (Fin nv, Holes, ClosedTerm)) -> ClosedTerm -> Core ClosedTerm
          fill j [] t = pure t
          fill j ((k, (_, hs, form)) :: rest) t = do
            projections <- unpacked hs.types (foundMarker j)
            fill (S j) rest (substName (markerName k) (fillHoles projections form) t)

      -- What a definition that gives an implementation is applied to,
      -- and anything else.
      headed : ClosedTerm -> ClosedTerm -> List (ClosedTerm, Lazy (Core (Maybe (ClosedTerm, Found nv)))) ->
               Core (Maybe (ClosedTerm, Found nv))
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
        def <- lookupDef rfc ctx.owner n
        True <- gives def
          | False => closedOver impl
        Just (vs, found) <- parts impl (type def) args
          | Nothing => pure Nothing
        pure (Just (foldl (App rfc) (Ref rfc nt n) vs, found))
      headed impl _ _ = closedOver impl

      -- An implementation's spine, each argument with its own walk
      -- suspended where it is a subterm.
      walk : ClosedTerm -> ClosedTerm -> List (ClosedTerm, Lazy (Core (Maybe (ClosedTerm, Found nv)))) ->
             Core (Maybe (ClosedTerm, Found nv))
      walk impl (App _ f a) args = walk impl f ((a, walk a a []) :: args)
      walk impl h args = headed impl h args

  ||| A definition applied to its arguments.
  applyRef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
             (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             Ctx -> List (VarInfo (Fin nv)) -> (afc : FC) -> (rfc : FC) -> NameType -> Name ->
             List (Arg vars nv) -> Core (Term nv)
  applyRef ph w acc ctx env afc rfc nt name args = do
    let fc = bestFC ctx rfc
    loc <- toLoc fc
    def <- lookupDef fc ctx.owner name
    let full = fullname def
    -- What a hook lowers a call of this definition to stands for it, the
    -- registry's entry it applied.
    let lowered = Just (shown (show full))
    case definition def of
      DCon tag arity _ => constructor fc loc def arity args
      TCon {} => inRuntime ctx.owner fc env (foldl (App rfc) (Ref rfc nt name) (map (.written) args))
      Builtin {arity} op => primitive fc loc full arity op (type def) args
      PMDef _ params _ _ _ => hooked fc loc full lowered (length params) def (hooksOf full) $ do
        exiting <- exitCast def
        if exiting
           then exitAction fc loc (length params) (type def) args
           else call fc loc full Nothing (length params) (type def) args
      -- A `%foreign` definition is known by its spec, an `%extern` one by
      -- its name; one the registry gives no meaning is an escape hatch.
      ForeignDef arity specs => do
        site <- siteAt fc
        case foreignHookOf site ctx.owner "" full specs of
          Right hs => hooked fc loc full lowered arity def hs
                        (reject fc ctx.owner EscapeHatch ("foreign function " ++ show full))
          Left r => rejectWith r
      ExternDef arity => hooked fc loc full lowered arity def (hooksOf full)
                           (reject fc ctx.owner EscapeHatch ("extern function " ++ show full))
      Hole {} => reject fc ctx.owner EscapeHatch ("the hole " ++ show full)
      _ => internal fc ("a reference to " ++ show full)
    where
      -- A definition's type after arguments, each substituted where the
      -- rest mentions it; unknown once the type shows no more binders.
      typeAfter : ClosedTerm -> List (Arg vars nv) -> Core (Maybe ClosedTerm)
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
      -- them, as one value (`packedType`).
      arguments : Loc -> List PKind -> List (Arg vars nv) -> Core (List (Term nv))
      arguments loc (ValueParam {} :: ks) (x :: xs) = (::) <$> x.translated <*> arguments loc ks xs
      arguments loc (DictParam _ (Just _) :: ks) (x :: xs) = do
        Just (_, held) <- x.held
          | Nothing => internal afc "the values an implementation closes over are gone"
        v <- pack afc ctx.owner loc !(valuesOf held)
        (v ::) <$> arguments loc ks xs
      arguments loc (_ :: ks) (_ :: xs) = arguments loc ks xs
      arguments loc _ _ = pure []

      offered : TT vars -> Offer
      offered (Local _ _ idx _) = case getAt idx env of
        Just (Static _ _) => AnImplementation
        _ => AValue
      offered _ = AValue

      argValue : Arg vars nv -> Maybe ArgValue
      argValue x = Just (MkArgValue (closeNormalise afc env x.written) (solved (closeWritten afc env x.written))
                                    (offered x.written)
                                    (map (\(shape, held) => (shape, map fst held)) <$> Force x.held))

      argValues : List (Arg vars nv) -> ArgValues
      argValues = map argValue

      -- The call's value: `mk` on the runtime arguments when the call gives
      -- every parameter, applied to the arguments past them over the
      -- callee's result type (`resTy`); with fewer, one closure per missing
      -- runtime parameter, as the curried type of the result requires. The
      -- arguments given (`arguments`) and the closures' parameters are as
      -- many as the call has runtime parameters, which is what `mk` takes.
      finish : Loc -> (kinds : List PKind) -> Nat -> List (Term nv) ->
               Maker (Runtimes kinds) -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      finish loc kinds arity given mk resTy xs = do
        let missing = drop (length (take arity xs)) kinds
        let Yes counted = decEq (length given + Runtimes missing) (Runtimes kinds)
          | No _ => internal afc ("a call of " ++ show name ++ " given " ++ show (length given) ++
                                  " runtime arguments, missing " ++ show (Runtimes missing) ++ ", of its " ++
                                  show (Runtimes kinds))
        let made = etaExpand loc (runtimeBinders missing) (recount counted mk) (fromList given)
        if null missing
           then applyOver ctx env afc loc (show <$> toFullNames name) made (Just resTy) (drop arity xs)
           else do
             when (any isStatic missing) $
               reject afc ctx.owner StaticArgument "a partially applied type parameter or implementation"
             pure made
        where
          isStatic : PKind -> Bool
          isStatic (TypeParam _) = True
          isStatic (DictParam _ _) = True
          isStatic (FormParam _) = True
          isStatic _ = False

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
      resolveMethod : Phase -> FC -> Name -> List PKind -> List (Arg vars nv) -> Core (Maybe (Term nv))
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
            Just <$> settle next ctx env fc field [] (drop parity xs)
          -- The field's markers are the implementation's form's, which
          -- stand for the values it closes over.
          Just (DictParam _ (Just _)) => do
            let Just x = getAt idx xs
              | Nothing => pure Nothing
            Just (shape, held) <- x.held
              | Nothing => internal fc "the values an implementation closes over are gone"
            Just field <- projected n (replaceAt idx shape statics)
              | Nothing => pure Nothing
            Just <$> settle next ctx env fc field (map (\(_, v) => AsValue v) (forget held)) (drop parity xs)
          _ => pure Nothing
        where
          replaceAt : Nat -> a -> List a -> List a
          replaceAt Z v (_ :: ys) = v :: ys
          replaceAt (S i) v (y :: ys) = y :: replaceAt i v ys
          replaceAt _ _ ys = ys

      -- A call whose result is an array: its dimensions that an argument
      -- fixes (a natural, or a dimension of an array argument) stated equal
      -- to it, the arguments bound once.
      tiedCall : FC -> Loc -> FnId -> Maybe Shown -> Nat -> ClosedTerm -> (kinds : List PKind) -> ClosedTerm ->
                 Core (Maker (Runtimes kinds))
      tiedCall fc loc inst lowered arity ty kinds resTy = do
        Just _ <- arrayView resTy
          | Nothing => pure (listed (Call loc inst lowered))
        (tel, res) <- sizedTelescope arity ty kinds
        rt <- coreType fc ctx.owner ValueType resTy
        [] <- resultTies tel res rt
          | ties => pure (MkMaker (\ys => bindEach loc (runtimeBinders kinds) ys (\ren, vs =>
                      Tie loc (Call loc inst lowered (toList (map (Var loc) vs)))
                          (map (\(k, w) => (k, witnessTerm loc vs w)) ties))))
        pure (listed (Call loc inst lowered))

      call : FC -> Loc -> Name -> Maybe Shown -> Nat -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      call fc loc n lowered arity ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        Nothing <- resolveMethod ph fc n kinds xs
          | Just resolved => pure resolved
        inst <- request fc ctx.owner n kinds
        given <- arguments loc kinds (take arity xs)
        mk <- tiedCall fc loc inst lowered arity ty kinds resTy
        finish loc kinds arity given mk resTy xs

      -- The identity on the last runtime argument, wherever it stands among
      -- the proofs and types (a cell's form or a frame's extents before it
      -- are not read); below its arity a closure over its missing
      -- parameters, whose body is the saturated identity, as every hook is
      -- below its arity.
      identity : FC -> Loc -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      identity fc loc ty xs = do
        let arity = binders ty
        if length xs >= arity
           then do
             let (now, rest) = splitAt arity xs
             let Just value = lastRuntime ty now
               | Nothing => internal fc ("the identity " ++ show name ++ " without a runtime argument")
             v <- value.translated
             applyOver ctx env fc loc (pure (show name)) v !(typeAfter ty now) rest
           else do
             (kinds, resTy) <- classify fc ctx.owner arity ty (argValues xs)
             given <- arguments loc kinds xs
             mk <- lastOf (runtimeBinders kinds)
             finish loc kinds arity given mk resTy xs
        where
          -- Below its arity, the identity's value is its last runtime
          -- argument, which the closures take.
          lastOf : Vect r Binder -> Core (Maker r)
          lastOf [] = internal fc ("the identity " ++ show name ++ " without a runtime parameter")
          lastOf (_ :: _) = pure (MkMaker (\ys => Data.Vect.last ys))

      -- Is the definition being translated one whose calls end the program
      -- (`Hook.Exits`, `System.exitWith`)? Its `believe_me` gives the
      -- exit's `PrimIO ()` any result, which is sound only because that
      -- action does not return; anywhere else `believe_me` stays an escape
      -- hatch.
      exiting : Core Bool
      exiting = do
        st <- get TState
        let r :: _ = st.chain
          | [] => pure False
        owner <- lookupDef afc ctx.owner r.name
        pure (isJust (hooksOf (fullname owner)).exits)

      -- Is a definition `believe_me`, whose body is the `BelieveMe`
      -- primitive?
      believeMe : GlobalDef -> Core Bool
      believeMe def = do
        let PMDef _ _ (STerm _ tm) _ _ = definition def
          | _ => pure False
        let (Ref _ _ n, _) = getFnArgs tm
          | _ => pure False
        defs <- get Ctxt
        Just prim <- lookupCtxtExact n (gamma defs)
          | Nothing => pure False
        let Builtin BelieveMe = definition prim
          | _ => pure False
        pure True

      exitCast : GlobalDef -> Core Bool
      exitCast def = do
        wrapper <- believeMe def
        if wrapper then exiting else pure False

      -- The exit's `believe_me`, on the action: the action applied to the
      -- world, after which nothing runs.
      exitAction : FC -> Loc -> Nat -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      exitAction fc loc arity ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        mk <- exits (runtimeBinders kinds)
        finish loc kinds arity given mk resTy xs
        where
          -- The action, the last runtime argument, applied to the world;
          -- nothing runs after it.
          exits : Vect r Binder -> Core (Maker r)
          exits [] = internal fc ("the exit " ++ show name ++ " without its action")
          exits (_ :: _) = pure (MkMaker (\ns => Lam noLoc (shown "world") (MkBinder One WorldT)
                                                  (Let loc (shown "exited") Many
                                                       (App loc (weakenUnder 1 (Data.Vect.last ns)) (Var loc FZ))
                                                       (Unreachable loc))))

      -- A call of a monomorphic library function the registry names, on
      -- runtime arguments: saturated, and the ones past its arity applied.
      libraryCall : FC -> Loc -> QName -> Core ({0 m : Nat} -> List (Term m) -> Term m)
      libraryCall fc loc q = do
        def <- lookupDef fc ctx.owner (toName q)
        let PMDef _ params _ _ _ = definition def
          | _ => reject fc (show q) HookShape "the registry names a library function that is not a definition"
        let arity = length params
        (kinds, _) <- classify fc ctx.owner arity (type def) (replicate arity Nothing)
        let True = all valueOnly kinds
          | False => reject fc (show q) HookShape "the registry names a library function with compile-time arguments"
        inst <- request fc ctx.owner (fullname def) kinds
        let runtime = Runtimes kinds
        pure (\ns => let (now, rest) = splitAt runtime ns in
                     foldl (App loc) (Call loc inst Nothing now) rest)
        where
          valueOnly : PKind -> Bool
          valueOnly (ValueParam {}) = True
          valueOnly ErasedParam = True
          valueOnly _ = False

      -- A function on naturals, as the primitives it means (the registry's
      -- `NatOperation`); partially applied, it is eta-expanded like a call.
      natOperation : FC -> Loc -> Maybe Shown -> NatMeaning -> Nat -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      natOperation fc loc lowered m arity ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        case m of
          Primitive {k} p => do
            counted <- operands k kinds
            finish loc kinds arity given (recount counted (MkMaker (\ns => PrimApp loc p lowered ns))) resTy xs
          Clamped {k} p => do
            counted <- operands k kinds
            finish loc kinds arity given
                   (recount counted (MkMaker (\ns => PrimApp loc (Op NatFromBig NatT) lowered
                                                       [PrimApp loc p lowered (map (\n => PrimApp loc (Op NatToBig BigT) lowered [n]) ns)])))
                   resTy xs
          Tested c q => do
            toBool <- libraryCall fc loc q
            counted <- operands 2 kinds
            finish loc kinds arity given (recount counted (MkMaker (\ns => toBool [PrimApp loc (NatCompare c) lowered ns]))) resTy xs
          OnIntegers q => do
            f <- libraryCall fc loc q
            finish loc kinds arity given (listed (\ns => f (map (\n => PrimApp loc (Op NatToBig BigT) lowered [n]) ns))) resTy xs
        where
          -- The primitive takes the call's runtime arguments, as many as
          -- its operands.
          operands : (k : Nat) -> (kinds : List PKind) -> Core (Runtimes kinds = k)
          operands k kinds = case decEq (Runtimes kinds) k of
            Yes counted => pure counted
            No _ => internal fc ("the natural operation " ++ show name ++ " of " ++ show k ++ " operands, given " ++
                                 show (Runtimes kinds) ++ " runtime arguments")

      -- The value of a head that takes one runtime argument, made from it;
      -- a head of another number of them is not the one `wrong` names.
      single : FC -> String -> ({0 m : Nat} -> Term m -> Term m) -> Vect r Binder -> Core (Maker r)
      single fc wrong f [_] = pure (MkMaker (\[y] => f y))
      single fc wrong f _ = internal fc wrong

      -- A constructor of a `Nat`-like type is a natural: zero is 0, a
      -- successor adds 1 to its one runtime argument (the others are
      -- erased indices, as `FS`'s).
      natConstructor : FC -> Loc -> NatRole -> List PKind -> Nat -> List (Term nv) ->
                       ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      natConstructor fc loc Zero kinds arity given resTy xs =
        finish loc kinds arity given (MkMaker (\_ => Literal loc (LNat 0))) resTy xs
      natConstructor fc loc Succ kinds arity given resTy xs = do
        mk <- single fc "a successor without one runtime argument"
                     (\y => PrimApp loc (Op BigAdd NatT) Nothing [y, Literal loc (LNat 1)]) (runtimeBinders kinds)
        finish loc kinds arity given mk resTy xs

      -- Each argument of a constructor as its field holds it, with the
      -- argument given there if the call gives one: an implementation
      -- given to a dictionary field is the one the field holds, for the
      -- whole program.
      recorded : FC -> GlobalDef -> ConLayout -> List ArgKind -> List PKind -> List (Arg vars nv) -> Core ()
      recorded fc def info (arg :: args) (kind :: kinds) xs = do
        let (x, rest) = the (Maybe (Arg vars nv), List (Arg vars nv)) $ case xs of
                          [] => (Nothing, [])
                          (x :: rest) => (Just x, rest)
        case (arg, kind) of
          (DictArg key ty, DictParam t Nothing) => recordDictionary fc ctx.owner info key ty t
          -- A field holds one implementation for the whole program.
          -- The message names the implementation as written at the
          -- site, not its key, whose markers stand for the values.
          (DictArg _ _, DictParam t (Just _)) => do
            impl <- maybe (showTT t) (\x' => showTT (closeWritten fc env x'.written)) x
            reject fc ctx.owner RuntimeClosure ("an implementation chosen at runtime: " ++ impl)
          (DictArg _ _, _) => internal fc ("a runtime value for a dictionary field of " ++ show (fullname def))
          (_, DictParam _ _) => internal fc ("an implementation for a runtime field of " ++ show (fullname def))
          _ => pure ()
        recorded fc def info args kinds rest
      recorded _ _ _ _ _ _ = pure ()

      -- A constructor application: the fields, or for a type with one
      -- runtime field the field itself, since such a value is its field's.
      constructor : FC -> Loc -> GlobalDef -> Nat -> List (Arg vars nv) -> Core (Term nv)
      constructor fc loc def arity xs = do
        (kinds, resTy) <- classify fc ctx.owner arity (type def) (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        case natRole def of
          Just role => natConstructor fc loc role kinds arity given resTy xs
          Nothing => do
            Just (inst, _) <- dataOf fc ctx.owner !(normaliseClosed resTy)
              | Nothing => do
                  -- A value array is abstract: only the functions the
                  -- registry knows open it, and their bodies are not
                  -- translated.
                  Just _ <- arrayView !(normaliseClosed resTy)
                    | Nothing => internal fc "a constructor of a type that is not data"
                  reject fc (show (fullname def)) HookShape
                         ("the array type of " ++ show (fullname def) ++ " is opaque: its constructor is applied")
            st <- get TState
            Just cid <- conIdOf inst def
              | Nothing => internal fc ("the constructor " ++ show (fullname def) ++ " is not registered")
            let Just info = lookup cid st.cons
              | Nothing => internal fc ("the constructor " ++ show (fullname def) ++ " is not registered")
            -- An implementation given to a dictionary field is the one the
            -- field holds, for the whole program.
            recorded fc def info info.args kinds xs
            case newtypeOf inst st of
              Nothing => do
                -- Its fields are the call's runtime arguments.
                let (k ** con) = info.con
                let Yes counted = decEq (Runtimes kinds) k
                  | No _ => internal fc ("the constructor " ++ show (fullname def) ++ " of " ++ show k ++
                                         " fields, given " ++ show (Runtimes kinds) ++ " runtime arguments")
                finish loc kinds arity given (recount counted (MkMaker (\ys => ConApp loc con ys))) resTy xs
              Just _ => do
                mk <- single fc ("the constructor " ++ show (fullname def) ++ " of a type with one field takes another number")
                             id (runtimeBinders kinds)
                finish loc kinds arity given mk resTy xs

      primitive : FC -> Loc -> Name -> (arity : Nat) -> PrimFn arity -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
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
          supported : Core (Term nv)
          supported = do
            (kinds, resTy) <- classify fc ctx.owner arity ty []
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
      builderCall : FC -> Loc -> Maybe Shown -> Nat -> PurePrim -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      builderCall fc loc lowered arity p ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty []
        case kinds of
          [ValueParam (MkBinder _ (DataT _)) _ _] => pure ()
          _ => internal fc "a string built from something other than a list"
        let Yes counted = decEq (Runtimes kinds) (primArity p)
          | No _ => internal fc ("the string builder " ++ show name ++ " of another number of operands")
        given <- arguments loc kinds (take arity xs)
        result <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
        finish loc kinds arity given (recount counted (MkMaker (\ys => PrimApp loc (Op p result) lowered ys))) resTy xs

      -- A call of the library function a foreign definition stands for.
      aliasCall : FC -> Loc -> Maybe Shown -> QName -> List (Arg vars nv) -> Core (Term nv)
      aliasCall fc loc lowered q xs = do
        target <- lookupDef fc ctx.owner (toName q)
        let PMDef _ params _ _ _ = definition target
          | _ => internal fc (show q ++ " is not a function to stand for")
        call fc loc (fullname target) lowered (length params) (type target) xs

      -- What an IO primitive gives besides the next world, as its result
      -- kind says: for no value, the unit its `IORes` holds, the one
      -- constructor of its value's type; for a value, that value.
      gives : FC -> (r : IOResult) -> Con 2 -> Core (IOGives r)
      gives fc WorldOnly res = GivesUnit <$> onlyCon fc 0 (typeOf (Data.Vect.index 0 res.fields))
      gives fc ValueThenWorld res = pure GivesValue

      -- A pure primitive the registry lists, on the call's arguments and
      -- then the literals the call does not supply, as many as its
      -- operands, of the call's result type.
      pureCall : FC -> Loc -> Maybe Shown -> Nat -> PurePrim -> List Lit -> ClosedTerm -> List (Arg vars nv) ->
                 Core (Term nv)
      pureCall fc loc lowered arity p lits ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty []
        let Yes counted = decEq (Runtimes kinds + length lits) (primArity p)
          | No _ => internal fc ("the primitive of " ++ show name ++ " given " ++ show (Runtimes kinds) ++
                                 " runtime arguments and " ++ show (length lits) ++ " literals, of its " ++
                                 show (primArity p) ++ " operands")
        given <- arguments loc kinds (take arity xs)
        result <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
        finish loc kinds arity given
               (MkMaker (\ys => PrimApp loc (replace {p = Prim} (sym counted) (Op p result)) lowered
                                  (ys ++ map (Literal loc) (fromList lits))))
               resTy xs

      -- An IO primitive the registry lists, an effect on the call's
      -- arguments, whose world stays its last operand, and before it the
      -- literals the call does not supply (a new buffer's zero byte), giving
      -- the `IORes` of the call's result type.
      ioCall : FC -> Loc -> Nat -> IOPrim -> List Lit -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      ioCall fc loc arity p lits ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty []
        res <- onlyCon fc 2 !(coreType fc ctx.owner ValueType !(normaliseClosed resTy))
        what <- gives fc (ioResult p) res
        given <- arguments loc kinds (take arity xs)
        finish loc kinds arity given (listed (\ys => Effect loc p what (beforeWorld ys) res)) resTy xs
        where
          beforeWorld : {0 m : Nat} -> List (Term m) -> List (Term m)
          beforeWorld [] = map (Literal loc) lits
          beforeWorld [w] = map (Literal loc) lits ++ [w]
          beforeWorld (y :: ys) = y :: beforeWorld ys

      -- The type arguments of a call, in order.
      typeParams : List PKind -> List ClosedTerm
      typeParams (TypeParam t :: ks) = t :: typeParams ks
      typeParams (_ :: ks) = typeParams ks
      typeParams [] = []

      -- An array operation: IO, in the world's order, giving the `IORes`
      -- of the call's result type.
      arrayCall : FC -> Loc -> Nat -> IOPrim -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      arrayCall fc loc arity p ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        res <- onlyCon fc 2 !(coreType fc ctx.owner ValueType !(normaliseClosed resTy))
        what <- gives fc (ioResult p) res
        finish loc kinds arity given (listed (\ys => Effect loc p what ys res)) resTy xs

      -- A pure primitive on the call's runtime arguments, which its type
      -- fixes, as many as its operands: a buffer's length, an index
      -- checked against a bound.
      primCall : FC -> Loc -> Maybe Shown -> Nat -> (k ** Prim k) -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      primCall fc loc lowered arity (k ** p) ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty []
        let Yes counted = decEq (Runtimes kinds) k
          | No _ => internal fc ("the primitive of " ++ show name ++ " given " ++ show (Runtimes kinds) ++
                                 " runtime arguments, of its " ++ show k ++ " operands")
        given <- arguments loc kinds (take arity xs)
        finish loc kinds arity given (recount counted (MkMaker (\ys => PrimApp loc p lowered ys))) resTy xs

      -- The constructors of a snoc list of naturals (`Extents`, `Index`),
      -- in tag order, the order the library declares them in: the empty
      -- one and the snoc of the rest and the natural.
      snocCons : FC -> Ty -> Core Snocs
      snocCons fc (DataT inst) = do
        st <- get TState
        let Just decl = declared inst st
          | Nothing => internal fc ("extents or coordinates of an undeclared type " ++ show inst)
        let [(0 ** lin), (2 ** snoc)] = consOf decl
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
      cellsFixed : FC -> Ty -> Nat -> Core ()
      cellsFixed fc t r = when (dynamicCells r t) $
        reject fc ctx.owner ValueType ("an array of cells whose extents no type fixes: " ++ show t)

      arrayTerm : {0 count : Nat} -> FC -> Loc -> ArrayPrim -> Ty -> Vect count Binder -> List Ty -> Core (Maker count)
      arrayTerm fc loc g rt bs typeArgs = case (g, map typeOf bs) of
        (AShape, [xTy]) => do
          a <- theElement
          s <- snocCons fc rt
          let r = minus (rank xTy) (rank a)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [x] =>
                  snocValue loc s (map (\j => Tensor loc NatT (Extent j (Var loc x))) (axesOf r))))
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
        (AWrite, [xTy, iTy, vTy]) => insert xTy iTy vTy bs
        (AFoldLast, [FunT (MkBinder _ accTy) (FunT (MkBinder _ elTy) _), _, _]) => pure (reduce FoldLast accTy elTy bs)
        (AScanLast, [FunT (MkBinder _ accTy) (FunT (MkBinder _ elTy) _), _, _]) => pure (reduce ScanLast accTy elTy bs)
        (AReshape, [eTy, _]) => do
          a <- theElement
          eSnoc <- snocCons fc eTy
          let r = minus (rank rt) (rank a)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [e, x] =>
                  apart loc eSnoc r e (\ren', es => Tensor loc rt (Reshape (Var loc (ren' x)) (map (Var loc) es)))))
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
        (AWithArray, [eTy, vTy, FunT (MkBinder _ arrTy) _]) => do
          eSnoc <- snocCons fc eTy
          let r = minus (rank arrTy) (rank vTy)
          cellsFixed fc arrTy r
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [e, v, k] =>
                  apart loc eSnoc r e (\ren', ds =>
                                 App loc (Var loc (ren' k))
                                     (Tabulate loc arrTy (map (Var loc) (fromList ds))
                                               (Var loc (Free {k = length ds} (ren' v)))))))
        (ARead, [lTy, iTy]) => do
          a <- theElement
          iSnoc <- snocCons fc iTy
          res <- onlyCon fc 2 rt
          let r = minus (rank lTy) (rank a)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [l, i] =>
                  apart loc iSnoc r i (\ren', cs =>
                              ConApp loc res [ Tensor loc a (Extract (Var loc (ren' l)) (map (Var loc) cs))
                                             , Var loc (ren' l) ])))
        (AThaw, [_, _]) =>
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [x, k] =>
                  App loc (Var loc k) (Var loc x)))
        (ALShape, [lTy]) => do
          res <- onlyCon fc 2 rt
          a <- theElement
          s <- snocCons fc (typeOf (Data.Vect.index 0 res.fields))
          let r = minus (rank lTy) (rank a)
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [l] =>
                  ConApp loc res [ snocValue loc s (map (\j => Tensor loc NatT (Extent j (Var loc l))) (axesOf r))
                                 , Var loc l ]))
        (AGrow, [_, vTy, lTy]) => do
          let axis = lastAxis lTy vTy
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [k, v, l] =>
                  Tensor loc rt (Concat axis (Var loc l) (copies lTy axis (Var loc l) (Var loc k) (Var loc v)))))
        (ATabulateIO, [eTy, FunT (MkBinder _ idxTy) (FunT (MkBinder _ WorldT) (DataT step))]) => do
          FunT _ (DataT done) <- pure rt
            | _ => internal fc "a world-ordered tabulation whose result is no action"
          stepCon <- onlyCon fc 2 (DataT step)
          doneCon <- onlyCon fc 2 (DataT done)
          let arrTy = typeOf (Data.Vect.index 0 doneCon.fields)
          a <- theElement
          eSnoc <- snocCons fc eTy
          iSnoc <- snocCons fc idxTy
          let r = minus (rank arrTy) (rank a)
          cellsFixed fc arrTy r
          pure $ MkMaker (\ys => bindEach loc bs ys (\ren, [e, act] =>
                  apart loc eSnoc r e (\ren', ds =>
                                Lam noLoc (shown "world") (MkBinder One WorldT)
                                  (TabulateIO loc arrTy (map (Var loc . FS) (fromList ds)) (Var loc FZ)
                                     (App loc (App loc (Var loc (Free {k = S (length ds)} (FS (ren' act))))
                                                       (snocValue loc iSnoc
                                                          (map (Var loc . Bound . weaken) (toList (Data.Vect.allFins (length ds))))))
                                              (Var loc (Bound (last {n = length ds}))))
                                     stepCon doneCon))))
        _ => internal fc ("the array language's " ++ show name ++ " at operand types it does not have")
        where
          -- The one type argument of a call that has one: the element or
          -- the cell.
          theElement : Core Ty
          theElement = case typeArgs of
            [a] => pure a
            _ => internal fc ("the array language's " ++ show name ++ " without its one type argument")

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
            let es = map (\j => if j == a then n else Tensor loc NatT (Extent j x)) (axesOf (rank xTy))
                v' = weakenUnder (length es) v
                cell = map (Var loc . Bound) (drop (S a) (toList (Data.Vect.allFins (length es))))
                body = case (cell, xTy) of
                         ([], _) => v'
                         (_, TensorT _ e) => Tensor loc e (Extract v' cell)
                         _ => v'
            in Tabulate loc (alongAxis a xTy) (fromList es) body

          insert : Ty -> Ty -> Ty -> Vect 3 Binder -> Core (Maker 3)
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
      generating : FC -> Loc -> ArrayPrim -> Nat -> ClosedTerm -> List (Arg vars nv) -> Core (Term nv)
      generating fc loc g arity ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        rt <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
        typeArgs <- traverse (\t => coreType fc ctx.owner ValueType !(normaliseClosed t)) (typeParams kinds)
        mk <- arrayTerm fc loc g rt (runtimeBinders kinds) typeArgs
        finish loc kinds arity given mk resTy xs

      -- A call of a definition the registry's hooks lower, whatever
      -- declares it, or `otherwise` when no hook does. A hook for the
      -- identity on the one runtime argument, the last its type takes
      -- (`replace`, `rewrite__impl`, which `rewrite` elaborates to, the
      -- pointer casts, an array's `nest`); the rest are proofs and types.
      -- By the type, not the clause: `prim__castPtr = believe_me` binds
      -- only its erased type. A function of the array language is one by
      -- its type too: a bodiless declaration takes what its type says.
      hooked : FC -> Loc -> Name -> Maybe Shown -> Nat -> GlobalDef -> Hooks -> Core (Term nv) -> Core (Term nv)
      hooked fc loc full lowered arity def hs otherwise =
        let ty = type def
            constant = \v => applyOver ctx env fc loc (pure (show full)) v (Just ty) args in
        fromMaybe otherwise $
              map (reject fc ctx.owner Deprecated) hs.deprecated
          <|> map (\m => natOperation fc loc lowered m arity ty args) hs.natOperation
          <|> map (\p => builderCall fc loc lowered arity p ty args) hs.builds
          <|> map (\g => generating fc loc g (binders ty) ty args) hs.generating
          <|> (if hs.identityOnLast then Just (identity fc loc ty args) else Nothing)
          <|> map (\(p, lits) => pureCall fc loc lowered arity p lits ty args) hs.pureCall
          <|> map (\(p, lits) => ioCall fc loc arity p lits ty args) hs.ioCall
          <|> map (\p => arrayCall fc loc arity p ty args) hs.arrayCall
          <|> map (\p => primCall fc loc lowered arity p ty args) hs.primCall
          <|> map (constant . Literal loc) hs.handle
          <|> map (\q => aliasCall fc loc lowered q args) hs.alias
          <|> map (constant . systemFact) hs.systemInfo
        where
          systemFact : SystemFact -> Term nv
          systemFact TargetOs = PrimApp loc (Op Os StrT) Nothing []
          systemFact BackendName = Literal loc (LStr codegenName)
