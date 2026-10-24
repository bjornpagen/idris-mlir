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
import IdrisMLIR.Frontend.Translate.Contraction
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
import IdrisMLIR.Spec.Families.Ops
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

-- A scope here is always a term's, the checker's: where a rule is decided
-- is no question this module asks.
%hide IdrisMLIR.Spec.Core.Rules.Scope

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
||| suspension's value, a value an implementation closes over, a settled
||| form's use), which a lambda there is the closure of; or none, for the
||| operand of a force, of a `Lazy` type no lambda has, whose type is read
||| off the term it becomes (`termType`).
public export
data Expected = ExpectedAt Ty | Synthesized

||| The Core type of a runtime variable; nothing for an entry of any other
||| kind, which binds no Core variable.
export
coreTyOf : VarInfo kc sp a -> Maybe Ty
coreTyOf (Runtime _ t) = Just (coreOf t)
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

||| What the last field of a snoc list's snoc is to the array ops, which
||| take and give naturals: a natural itself (`Extents`), or a numeral of
||| the type given, a family of numeral shape (`Index`'s `Fin`), which
||| `idr.numeral.of_nat` makes of its natural and `idr.numeral.to_nat`
||| reads back, with no range check: its bound is its type's.
data SnocField = IsNatural | IsNumeral Ty

||| A snoc list of naturals or numerals (`Extents`, `Index`) as its
||| declaration has it: the empty constructor, the snoc of the rest and the
||| element, and what the element is.
record Snocs where
  constructor MkSnocs
  lin : Con 0
  snoc : Con 2
  fieldForm : SnocField

||| A natural as a snoc list's element.
ofNatural : {0 m : Nat} -> Loc -> SnocField -> Term m -> Term m
ofNatural loc IsNatural n = n
ofNatural loc (IsNumeral t) n = PrimApp loc (Op numeralOfNatOp t made) Nothing [n]

||| A snoc list's element as a natural.
toNatural : {0 m : Nat} -> Loc -> SnocField -> Term m -> Term m
toNatural loc IsNatural n = n
toNatural loc (IsNumeral _) n = PrimApp loc (Op numeralToNatOp (NatT IOpaque) made) Nothing [n]

||| What fills each slot of an array made of copies of a cell: the cell
||| itself, where no axis of the array follows those it is repeated along;
||| else the cell's element at the slot's coordinates past them, the cell an
||| array (`array`) of those axes.
data Fill : Type where
  WholeCell : Fill
  ElementOfCell : {r : Nat} -> (array : ArrayType r) -> Fill

||| A snoc list built from its constructors and naturals, outermost first,
||| each natural made its element: an `Extents` or an `Index` value.
snocValue : {0 m : Nat} -> Loc -> Snocs -> List (Term m) -> Term m
snocValue loc s ns = foldl (\acc, n => ConApp loc s.snoc [] [acc, ofNatural loc s.fieldForm n]) (ConApp loc s.lin [] []) ns

||| A snoc list of naturals (extents or coordinates) taken apart into its
||| last `r` naturals, outermost first, by its snoc; the body is built over
||| them, with the renaming of the scope outside. A value of rank `r` holds
||| `r` snocs, as its type's index says, so the empty list is no possible
||| arm of a match.
apart : {0 m : Nat} -> Loc -> Snocs -> Nat -> Fin m ->
        ({0 p : Nat} -> (Fin m -> Fin p) -> List (Term p) -> Term p) -> Term m
apart loc s r x k = go r x (\ren, ns => k ren (map (toNatural loc s.fieldForm . Var loc) (ns <>> [])))
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
||| array and builds the cell again, so the cell is rebuilt in place by the
||| rule that rebuilds every cell of a type whose values are.
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

------------------------------------------------------------------------------
-- IO
------------------------------------------------------------------------------

%prefix_record_projections off

||| `IO` at a type, as Idris declares it (`MkIO : (1 fn : PrimIO a) -> IO
||| a`): its family, constructor and action (`Term.IOFamily`), which the
||| core term holds; and its field's Idris type, the `PrimIO`, which names
||| the `IORes` the action gives.
public export
record IOAt where
  constructor MkIOAt
  family : IOFamily
  primIO : ClosedTerm

%prefix_record_projections on

||| What an action takes the world at and what it gives, with its type the
||| function of the world to that.
partsOf : ActionType t -> (world : Uses ** gives : Ty ** t = FunT (MkBinder world WorldT) gives)
partsOf (OnWorld world gives) = (world ** gives ** Refl)

||| A type read at `IO` (`IOAt`) where `IO` is the type constructor it
||| applies, known by its identity, the address the boundary read `IO` at
||| (`Reading.ioType`), and never by its shape, so a family of the same
||| shape is not `IO`; nothing for a type of any other head. `IO`'s
||| declaration is Idris's: the family it names at the type, its one
||| constructor of one field (`Choices.onlyCon`), that field an action on
||| the world (`actionType`), each read where a hook, the program's root or
||| a local definition first reads `IO` at a type. A declaration of another
||| shape is the compiled module's error, refused there.
export
ioOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> String -> ClosedTerm -> Front (Maybe IOAt)
ioOf fc owner ty = do
  io <- (.ioType) <$> reading
  tm <- normaliseClosed ty
  case getFn tm of
    Ref _ (TyCon _) n => do
      (tc, _) <- lookupTyCon fc owner n
      if sameAddress (addressOf tc.placement) io then Just <$> declared tm else pure Nothing
    _ => pure Nothing
  where
    declared : ClosedTerm -> Front IOAt
    declared tm = do
      Just (df, _) <- dataFamilyOf fc owner tm
        | Nothing => reject fc owner CompiledModule "IO, which is no data type"
      only <- onlyCon 1 (reject fc owner CompiledModule) df
      let io = only.single
      let Just action = actionType (Data.Vect.head io.fields).type
        | Nothing => reject fc owner CompiledModule ("a value of " ++ keyText df.key ++ ", whose field holds no action on the world")
      let (world ** gives ** holds) = partsOf action
      pure (MkIOAt (MkIOFamily io world gives holds) (Data.Vect.head only.fieldTypes))

||| A type read at `IO` (`ioOf`) where a hook or the program's root takes
||| an `IO` value: one of any other type is refused there, by `refused`,
||| told what the type is.
export
ioAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
       FC -> String -> (refused : {0 r : Type} -> String -> Front r) -> ClosedTerm -> Front IOAt
ioAt fc owner refused ty = do
  Just a <- ioOf fc owner ty
    | Nothing => do
        written <- showTT ty
        refused ("a value of type " ++ written ++ ", which is no IO")
  pure a

------------------------------------------------------------------------------
-- A library function a hook calls
------------------------------------------------------------------------------

||| A library function's operands (`CheckedLibrary`), every binder its type
||| shows, read against the kinds of its case tree's parameters, which come
||| first and which its calls are translated at, `given` values among them:
||| its case tree takes every value its type shows, so a call gives them
||| all (`TreeTakesAll`); or its clauses take fewer (`compareInteger =
||| compare` takes none), so the call gives back a function, applied to the
||| values of the binders after them (`AppliedPast`, the operands of those
||| binders, at least one). The two are the problem's: Idris's clauses fix
||| how many parameters a case tree takes, which eta-reduction changes and
||| the type does not.
data TreeOperands : (count : Nat) -> (given : Nat) -> Type where
  TreeTakesAll : {0 count, given : Nat} -> (0 _ : given = count) -> TreeOperands count given
  AppliedPast : {0 count, given : Nat} -> {past : Nat} -> {0 applied : Nat} -> Operands (S past) applied ->
                (0 _ : given + applied = count) -> TreeOperands count given

||| The operands read against the kinds of the case tree's parameters: a
||| value at each operand among them, nothing at run time elsewhere, so the
||| kinds bind at run time as many values as those operands are; nothing
||| where a kind is a compile-time argument the hook cannot give (a type,
||| an implementation, a form, a choice), or where the kinds outrun the
||| binders, which no case tree Idris builds from its type's binders does.
||| The evidence is erased: reading the kinds builds no proof at run time.
treeOperands : {params : Nat} -> {0 count : Nat} -> Operands params count -> (ks : List PKind) ->
               Maybe (TreeOperands count (Runtimes ks))
treeOperands NoParameter [] = Just (TreeTakesAll Refl)
treeOperands {params = S n} ops@(Operand _) [] = Just (AppliedPast {past = n} ops Refl)
treeOperands {params = S n} ops@(NoOperand _) [] = Just (AppliedPast {past = n} ops Refl)
treeOperands {params = S n} (Operand ops) (ValueParam _ _ _ :: ks) = case treeOperands {params = n} ops ks of
  Just (TreeTakesAll same) => Just (TreeTakesAll (cong S same))
  Just (AppliedPast after same) => Just (AppliedPast after (cong S same))
  Nothing => Nothing
treeOperands {params = S n} (NoOperand ops) (ErasedParam :: ks) = treeOperands {params = n} ops ks
treeOperands {params = S n} (NoOperand ops) (IndexParam _ :: ks) = treeOperands {params = n} ops ks
treeOperands _ _ = Nothing

||| A call of a function whose case tree takes the first `g` of the values
||| given, its value a function of the `j` after them, which it is applied
||| to, each at its binder, to what gives `result`: every value bound
||| first, in order, so each is evaluated before the call, as an argument
||| is before the function it is given to.
calledThenApplied : {0 m, j, count : Nat} -> {g, arity : Nat} -> Loc -> Callee arity -> (indices : List ITerm) ->
                    (0 _ : g = arity) -> (given : Vect g Binder) -> (past : Vect j Binder) -> (0 _ : g + j = count) ->
                    (result : Ty) -> Vect count (Term m) -> Term m
calledThenApplied {g} loc callee is same given past adds result ts =
  bindArguments loc (given ++ past) (replace {p = \c => Vect c (Term m)} (sym adds) ts) body
  where
    -- The function applied to each value in turn, at the type of the
    -- function of the values after it.
    applyEach : {0 i, q : Nat} -> Term q -> Vect i Binder -> Vect i (Term q) -> Term q
    applyEach f [] [] = f
    applyEach f (b :: bs) (y :: ys) = applyEach (App loc b (foldr FunT result bs) f y) bs ys

    body : {0 q : Nat} -> (Fin m -> Fin q) -> Vect (g + j) (Fin q) -> Term q
    body _ vs =
      let (gv, pv) = Data.Vect.splitAt g vs in
      applyEach (Call loc callee Nothing is (replace {p = \c => Vect c (Term q)} same (map (Var loc) gv)))
                past (map (Var loc) pv)

||| The compile-time value a parameter's kind gives, where a projection
||| reads its arguments: a type, an implementation, or nothing known.
compileTimeArg : PKind -> ClosedTerm
compileTimeArg (TypeParam t _) = t
compileTimeArg (DictParam d _) = d.form
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

||| The Idris type of the value a `Force` of `tm` gives, as Idris checked
||| it, read off the types `tm` is built of: the type its `Lazy` type
||| holds, where `tm` is a runtime variable, or a variable or a definition
||| applied to arguments, each substituted where the rest of its type
||| mentions it (`instantiate`); a `Delay`'s, the type it holds, and so an
||| implementation's whose form is one (a delayed polymorphic function, a
||| branch of `if`); a `let`'s, its body's, the value it binds standing for
||| its variable. Nothing for a term of any other form: a metavariable, an
||| implementation applied or of another form, whose types no entry holds,
||| and a term of no `Lazy` type.
forcedOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           FC -> String -> StandsFor kc OfTerm vars (Fin nv) -> TT vars -> Front (Maybe ClosedTerm)
forcedOf fc owner env (TDelay _ _ ty _) = Just <$> closeNormalise fc env ty
forcedOf fc owner env (Bind _ _ (Let _ _ val _) sc) = forcedOf fc owner (TypeValue (closeWritten fc env val) :: env) sc
forcedOf fc owner env tm = case getFnArgs tm of
  (Local _ _ idx p, args) => case lookupVar idx p env of
    Runtime _ t => after (idrisOf t) args
    Shaped _ _ t _ => after t args
    e => case (implementationOf e, args) of
      (Just (TDelay _ _ ty _, _), []) => Just <$> normaliseClosed ty
      _ => pure Nothing
  (Ref rfc _ n, args) => do
    d <- lookupDef rfc owner n
    after d.type args
  _ => pure Nothing
  where
    -- A type as it is, where it shows what is read of it, else its normal
    -- form.
    showing : ClosedTerm -> Front ClosedTerm
    showing ty@(TDelayed {}) = pure ty
    showing ty@(Bind _ _ (Pi {}) _) = pure ty
    showing ty = normaliseClosed ty

    after : ClosedTerm -> List (TT vars) -> Front (Maybe ClosedTerm)
    after ty [] = do
      TDelayed _ _ t <- showing ty
        | _ => pure Nothing
      pure (Just t)
    after ty (a :: as) = do
      Bind _ _ (Pi {}) sc <- showing ty
        | _ => pure Nothing
      next <- instantiate fc env sc a
      after next as

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
||| (`Written`), whose implementations and polymorphic functions applied
||| may be settled once into the phase it holds; or settled (`Settled`):
||| the written form of one of those, walked where it is applied, closed
||| but for the variables bound around it. What a settled term settles
||| again (an implementation or a polymorphic function applied in it, a
||| value an implementation in it closes over) stays settled, on a path
||| that enters the definition at the head of what it settles, as a
||| metavariable's solution is entered.
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

||| What a `let` binds in Core, from the scope of `nv` variables to the one
||| its body is in: nothing (an erased value, a type, an implementation the
||| program fixes, which are compile-time values), or one variable.
data LetBinds : (nv : Nat) -> (m : Nat) -> Type where
  NoCoreBinder : LetBinds nv nv
  OneCoreBinder : LetBinds nv (S nv)

||| An argument under a `let`, as what it binds in Core says.
argUnderLet : LetBinds nv m -> Arg vars nv -> Arg (x :: vars) m
argUnderLet NoCoreBinder = overBinder
argUnderLet OneCoreBinder = underLet

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

||| What a marker of a settled term stands for.
data Stand : Nat -> Nat -> Type where
  ||| A variable in scope: the marker is bound as it is, with no `let`.
  AsVariable : VarInfo kc OfTerm (Fin nv) -> Stand kc nv
  ||| A runtime value of an Idris type, the one the implementation that
  ||| holds it gives it, bound once by a `let` before the term.
  AsValue : (idris : ClosedTerm) -> Lazy (Front (Term nv)) -> Stand kc nv

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
      BoundHere _ _ _ => AnImplementation
      _ => AValue
    offered _ = AValue

||| What a call gives each parameter of its callee that exists at run
||| time, among those its arguments reach, in order: the term the argument
||| at that position gives at that parameter's kind.
givenTo : {0 nv : Nat} -> (ks : List PKind) -> (args : List (PKind -> Front (Term nv))) ->
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
    -- none here: inside a settled term nothing computes it again. Its
    -- members are the ones that computation gives, which the program
    -- fixes; what is refused is computing it inside the settled form of
    -- the definition that gives it, at this site.
    formGiven : PKind -> Front (Term nv)
    formGiven _ = case value of
      Just v => pure v
      Nothing => do
        written <- showTT !(form.written)
        reject fc ctx.owner RuntimeClosure
               ("the value of " ++ written ++ ", which a definition Idris does not prove ends computes, at run " ++
                "time, inside the settled form of the definition that gives it")

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
-- entered once on its path (`Walk`); the written form of an
-- implementation or a polymorphic function a written term applies, which
-- is walked in the phase the written one held; and
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
  term ph w acc ctx env ex (Local fc r idx p) = applyVariable ph w acc ctx env ex fc fc r idx p []
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
      (suspensions, inner) <- letIn ph w acc ctx env fc x rig val ty (\_, env' => delayed ph w acc ctx env' ex sc)
      pure (foldr (\(l, t), body => Suspend l t body) inner suspensions)
    Nothing => (\((), t) => t) <$> letIn ph w acc ctx env fc x rig val ty (\_, env' => ((),) <$> term ph w acc ctx env' ex sc)

  -- A lambda's binder of quantity 0 is no parameter at runtime: the lambda
  -- is its body, which takes the runtime arguments after it, as its type
  -- does once the binder is left out, at what the lambda is expected at. A
  -- lambda is a closure, whose type is one for every extent its values are
  -- made at (`coreType`), so its binder is too: an array parameter's
  -- extents are its argument's, each dynamic, whatever the type at this
  -- lambda fixes. Its result is the one its position's function type gives
  -- (checked, as Idris's elaborator checked it there), its body translated
  -- at it. Every position a lambda stands at is translated at its type: a
  -- binder's, a `let`'s, a leaf's, a lambda's body's, a value an
  -- implementation closes over (`holed`), a settled form's use
  -- (`settle`). One whose Core type is no function's is a polymorphic
  -- function's choice, where a lambda stands only as the member of it the
  -- program fixes (`member`): one that is none is refused there, naming it.
  term ph w acc ctx env ex tm@(Bind fc x (Lam lfc rig _ ty) sc) =
    case use rig of
      Erased => term ph w acc ctx (TypeValue (Erased fc Placeholder) :: env) ex sc
      Used q => case ex of
        ExpectedAt (FunT _ r) => do
          loc <- toLoc (bestFC ctx fc)
          known <- closeNormalise fc env ty
          b <- closureBinder <$> coreBinder (bestFC ctx fc) ctx.owner ValueType q known
          Lam loc (binderName x) b r <$> term ph w acc ctx (under {k = 1} [Runtime FZ (BothTypes b.type known)] env) (ExpectedAt r) sc
        _ => do
          written <- showTT (closeWritten fc env tm)
          reject (bestFC ctx fc) ctx.owner RuntimeClosure
                 ("the function " ++ written ++ ", where a value of a choice the program fixes is expected, and which " ++
                  "is no member of it")
  term ph w acc ctx env ex (TDelay fc _ ty arg) = suspend ph w acc ctx env fc ty arg
  term ph w acc ctx env ex (TForce fc _ arg) = snd <$> forced ph w acc ctx env ex fc arg
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

  -- Kept: the value a force gives is of the type its operand's suspension
  -- holds, which the operand's variable's binder or its own term states;
  -- where neither does (an operand that never returns), the type the
  -- force's position expects. Idris checked the operand a `Lazy`, but the
  -- Core type read for it is a `Ty`, which does not say so.
  forcedType : FC -> Expected -> Maybe Ty -> Front Ty
  forcedType fc _ (Just (LazyT t)) = pure t
  forcedType fc (ExpectedAt t) Nothing = pure t
  forcedType fc _ suspension = internal fc ("a force of a value whose Core type " ++ show suspension ++ " is no suspension's")

  ||| A force of `arg`: the value its operand's suspension holds, of the type
  ||| its operand's own gives (`forcedType`), which it gives beside it.
  forced : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> FC -> TT vars -> Front (Ty, Term nv)
  forced ph w acc ctx env ex fc arg = do
    loc <- toLoc (bestFC ctx fc)
    operand <- term ph w acc ctx env Synthesized arg
    let suspension = case arg of
                       Local _ _ idx p => coreTyOf (lookupVar idx p env)
                       _ => termType ctx.depth (scopeOf env) operand
    value <- forcedType (bestFC ctx fc) ex suspension
    pure (value, Resume loc value operand)

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
    letIn ph w acc ctx env fc x rig val ty (\_, env' => delayed ph w acc ctx env' ex sc)
  delayed ph w acc ctx env ex tm = ([],) <$> term ph w acc ctx env ex tm

  ||| A `let`, its body translated by `body` in the scope it binds, told what
  ||| the `let` binds in Core (`LetBinds`). A `let` of a type or a type
  ||| family binds a type parameter whatever its quantity, as a lambda
  ||| applied to it binds it (`applyHead`), its value as written, never a
  ||| value at run time: the motive `rewrite` binds at quantity 0 is one,
  ||| which the program fixes and the types after it read. Any other `let`
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
          ({0 m : Nat} -> LetBinds nv m -> StandsFor kc OfTerm (x :: vars) (Fin m) -> Front (r, Term m)) -> Front (r, Term nv)
  letIn ph w acc ctx env fc x rig val ty body = do
    known <- closeNormalise fc env ty
    if isTypeLike known then body NoCoreBinder (TypeValue (closeWritten fc env val) :: env) else
      case use rig of
        Erased => body NoCoreBinder (TypeValue (Erased fc Placeholder) :: env)
        Used q => do
          loc <- toLoc (bestFC ctx fc)
          True <- polymorphicType known
            | False => runtimeLet q loc known
          impl <- solved (closeWritten fc env val)
          if not !(runtimeDependent impl)
            then do
              FixedNow _ <- fixing known impl
                | ChosenAtRunTime _ => runtimeLet q loc known
              body NoCoreBinder (BoundHere impl known Nothing :: env)
            else do
              Just (shape, values) <- holed ph w acc ctx env fc val
                | Nothing => runtimeLet q loc known
              FixedNow _ <- fixing known shape
                | ChosenAtRunTime _ => runtimeLet q loc known
              held <- coreType fc ctx.owner ValueType !(normaliseClosed !(packedType (map fst values)))
              v <- pack fc ctx.owner loc !(valuesOf values)
              (r', inner) <- body OneCoreBinder
                                  (under {k = 1} [BoundHere shape known (Just (FZ, MkHoles (map fst values) (MkBinder Many held)))] env)
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
        (r', inner) <- body OneCoreBinder (under {k = 1} [Runtime FZ (BothTypes b.type known)] env)
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
    Nothing => snd <$> letIn ph w acc ctx env fc x rig val vty (\_, env' => ((),) <$> atType ph w acc ctx env' ty sc)
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
  ||| takes the rest, so that no term is substituted; a `let`, whose body
  ||| takes them under what it binds; a solved metavariable, as its
  ||| solution; an `As` pattern, as its pattern; a force, as the value it
  ||| gives, of the type its operand's holds (`forcedOf`); anything, applied
  ||| to nothing, at what the application is expected at. So every value an
  ||| application applies is of a type it is read at: a variable's, a
  ||| definition's (`applyRef`), a force's.
  applyHead : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
              (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
              Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> FC -> TT vars -> List (Arg vars nv) -> Front (Term nv)
  applyHead ph w acc ctx env ex afc (Local fc r idx p) args = applyVariable ph w acc ctx env ex afc fc r idx p args
  -- The argument is bound as what it is: a compile-time value at an erased
  -- binder; another name for a variable; at a binder of a type or a type
  -- family, whatever its quantity, the type, as at an erased one (the
  -- binder is a type parameter, as `Instances.keyingOf` classifies a
  -- function's); at a binder of an implementation or a polymorphic
  -- function (`compileTimeBinder`), its form, with the values it closes
  -- over bound once; anything else, a runtime value bound by a `let`,
  -- which the application evaluates first, where the `let` translation
  -- would move it into a `Delay` the body builds (`delayedLets`).
  applyHead ph w acc ctx env ex afc (Bind bfc x (Lam _ rig _ ty) sc) (a :: rest) =
    case use rig of
      Erased => typeValue
      -- A variable given to a binder of quantity 1 stands for it, used at
      -- most once there as Idris proved; given to one of quantity many it
      -- is bound once, so a variable Idris lets be used once is never used
      -- twice.
      Used q => case (q, aliased a.written) of
        (Once, Just e) => spine ph w acc ctx (e :: env) ex afc sc (map overBinder rest)
        _ => do
          known <- closeNormalise bfc env ty
          if isTypeLike known then typeValue else do
            fixedHere <- compileTimeBinder rig ty
            loc <- toLoc (bestFC ctx bfc)
            if fixedHere then dictionary q loc known else asValue q loc known
    where
      typeValue : Front (Term nv)
      typeValue = spine ph w acc ctx (TypeValue (closeWritten bfc env a.written) :: env) ex afc sc (map overBinder rest)

      -- The argument as a runtime value, bound by a `let` at the binder's
      -- quantity, of its normalised type (`known`): a choice of an
      -- implementation among others (`Choices`).
      asValue : Uses -> Loc -> (known : ClosedTerm) -> Front (Term nv)
      asValue q loc known = do
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
      dictionary : Uses -> Loc -> (known : ClosedTerm) -> Front (Term nv)
      dictionary q loc known = do
        impl <- solved (closeWritten bfc env a.written)
        if not !(runtimeDependent impl)
          then do
            FixedNow _ <- fixing known impl
              | ChosenAtRunTime _ => asValue q loc known
            spine ph w acc ctx (BoundHere impl known Nothing :: env) ex afc sc (map overBinder rest)
          else do
            Just (shape, values) <- a.held
              | Nothing => asValue q loc known
            FixedNow _ <- fixing known shape
              | ChosenAtRunTime _ => asValue q loc known
            held <- coreType bfc ctx.owner ValueType !(normaliseClosed !(packedType (map fst values)))
            v <- pack bfc ctx.owner loc !(valuesOf values)
            body <- spine ph w acc ctx
                          (under {k = 1} [BoundHere shape known (Just (FZ, MkHoles (map fst values) (MkBinder Many held)))] env)
                          ex afc sc (map underLet rest)
            pure (Let loc (binderName x) (Checked (MkBinder Many held)) v body)
  applyHead ph w acc ctx env ex afc (Meta mfc n i margs) args = entered ph w acc ctx env ex afc mfc n i margs args
  applyHead ph w acc ctx env ex afc (As _ _ _ pat) args = spine ph w acc ctx env ex afc pat args
  applyHead ph w acc ctx env ex afc tm [] = term ph w acc ctx env ex tm
  -- A `let` applied: its body is applied, under the binding, which runs
  -- first, as the head of an application runs before its arguments.
  applyHead ph w acc ctx env ex afc (Bind bfc x (Let lfc rig val ty) sc) args@(_ :: _) =
    snd <$> letIn ph w acc ctx env bfc x rig val ty
                  (\binds, env' => ((),) <$> spine ph w acc ctx env' ex afc sc (map (argUnderLet binds) args))
  applyHead ph w acc ctx env ex afc tm@(TForce ffc _ e) args@(_ :: _) = do
    let fc = bestFC ctx afc
    loc <- toLoc fc
    -- A forced metavariable, or implementation of a form other than a
    -- `Delay`, applied is of a type no entry holds, so which of its
    -- arguments exist at run time is not read: refused, naming it.
    Just t <- forcedOf (bestFC ctx ffc) ctx.owner env e
      | Nothing => reject (bestFC ctx ffc) ctx.owner ValueType
                          ("an application of a force of " ++ !(showTT (closeWritten ffc env e)) ++
                           ", whose Lazy type is read off no variable, definition or Delay")
    (value, f) <- forced ph w acc ctx env Synthesized ffc e
    applyOver ph w acc ctx env fc loc (headName fc env tm) f value t args
  -- Idris applies only a function, a value of a function's type, which no
  -- other term is: a constant, a type or a suspension applied is the
  -- compiled module's, refused where the frontend first reads it.
  applyHead ph w acc ctx env ex afc tm (_ :: _) = do
    written <- showTT (closeWritten afc env tm)
    reject (bestFC ctx afc) ctx.owner CompiledModule ("an application of " ++ written ++ ", which is no function")

  ||| A variable applied to its arguments: a runtime value, applied; an
  ||| implementation, as `implementationAt` uses one.
  applyVariable : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                  (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                  Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> (afc : FC) -> (fc : FC) -> Maybe Bool ->
                  (idx : Nat) -> (0 p : IsVar n idx vars) -> List (Arg vars nv) -> Front (Term nv)
  applyVariable ph w acc ctx env ex afc fc r idx p args = case lookupVar idx p env of
    Runtime x t => applied x (coreOf t) (idrisOf t)
    Shaped x t ity _ => applied x t ity
    -- Idris's quantity check of a clause keeps a binder of quantity 0 out
    -- of every position that exists at runtime, a leaf reads each binder
    -- where its clause holds it at runtime (`Cases.heldAt`), and the
    -- translation leaves out every erased position. The check is Idris's,
    -- of the checked module, whose term the frontend first reads here, and
    -- TT's variable does not carry it: one that fails it is refused, as
    -- the compiled module it is.
    TypeValue _ => reject (bestFC ctx fc) ctx.owner CompiledModule "a compile-time variable in a runtime position"
    Static d held _ => implementationAt ph w acc ctx env ex fc d.form d.type held args
    BoundHere t ty held => implementationAt ph w acc ctx env ex fc t ty held args
    where
      -- The variable, of the Core and Idris types its entry gives.
      applied : Fin nv -> Ty -> ClosedTerm -> Front (Term nv)
      applied x core ity = do
        loc <- toLoc (bestFC ctx fc)
        let at = bestFC ctx afc
        aloc <- toLoc at
        applyOver ph w acc ctx env at aloc (headName at env (Local fc r idx p)) (Var loc x) core ity args

  ||| An implementation or a polymorphic function the environment binds,
  ||| used at runtime: its form, as written, is walked applied to its
  ||| arguments, each bound once (`settle`), each use at its own types. One
  ||| that closes over runtime values stands for them by the projections of
  ||| the variable that holds them, marker 0. Applied in a settled term (a
  ||| part of another implementation closes over it, or a `let` there binds
  ||| it), its form stays settled, on a path that enters the definition at
  ||| its head (`formHead`). One whose head is a
  ||| variable (a value it closes over, one of its own lambdas'), which no
  ||| path enters, and one whose definition the path has entered already,
  ||| which would be settled inside its own settled form, are the member at
  ||| this use's types (`applyAtUse`) at the type its entry holds it at
  ||| (`ty`), an instance the worklist translates on a path of its own and
  ||| bounds by the growth check: so the translation still ends, and a value
  ||| at the head is applied as its type's choice is, dispatched on.
  implementationAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                     Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                     Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> FC -> (t, ty : ClosedTerm) ->
                     Maybe (Fin nv, Holes) -> List (Arg vars nv) -> Front (Term nv)
  implementationAt ph@Settled w acc@(Access rec) ctx env ex fc t ty held args = do
    place <- formHead t
    case place >>= (\p => enter p w) of
      Just (Element w' less) => do
        (form, pre) <- standingFor t held
        settle ph w' (rec w' less) ctx env ex fc form pre args
      Nothing => do
        let at = bestFC ctx fc
        loc <- toLoc at
        let form = MkArgValue (pure t) (pure t) AnImplementation
                              (pure ((\(_, hs) => (t, hs.types)) <$> held)) (pure t)
        applyAtUse ctx env at loc ty form ((\(x, _) => Var loc x) <$> held) args
  implementationAt (Written next) w acc ctx env ex fc t _ held args = do
    (form, pre) <- standingFor t held
    settle next start (sizeAccessible start) ctx env ex fc form pre args

  ||| An implementation as `settle` takes it: its form, the markers of the
  ||| values it closes over the projections of the variable that holds
  ||| them, marker 0, which stands for that variable, of the type that holds
  ||| them, so that a value at the form's head is applied as its own type
  ||| says (a choice, dispatched on).
  standingFor : {auto s : Ref TState TS} -> ClosedTerm -> Maybe (Fin nv, Holes) -> Front (ClosedTerm, List (Stand kc nv))
  standingFor t Nothing = pure (t, [])
  standingFor t (Just (x, hs)) = do
    values <- unpacked hs.types (holeMarker 0)
    pure (fillHoles values t, [AsVariable (Runtime x (BothTypes hs.binder.type !(packedType hs.types)))])

  ||| A metavariable applied, as the solution the type checker gave it,
  ||| read once at the boundary by the entry its term gives it
  ||| (`State.solutionIn`), and entered once on the path, at that entry's
  ||| place. The term's name shows it in a message.
  entered : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> (afc : FC) -> (fc : FC) -> Name -> Int -> List (TT vars) ->
            List (Arg vars nv) -> Front (Term nv)
  entered ph w acc@(Access rec) ctx env ex afc fc n i margs args = do
    r <- reading
    -- A hole the source left is the escape hatch it is.
    SolvedAs tm place _ _ _ _ <- core (solutionIn r i)
      | Unsolved _ _ => reject (bestFC ctx fc) ctx.owner EscapeHatch ("the hole " ++ show n)
    -- Idris's occurs check keeps a solution from holding its own
    -- metavariable, which the walk is where the frontend first meets: a
    -- solution that holds it is refused, as the compiled module it is.
    let Just (Element w' less) = enter place w
      | Nothing => reject (bestFC ctx fc) ctx.owner CompiledModule "a metavariable met again on its own path"
    spine ph w' (rec w' less) ctx env ex afc (solvedApplied (bestFC ctx fc) tm margs) args

  ||| A value of the environment applied to arguments, walked as it is
  ||| written in phase `ph` on the path `w`, its arguments bound once where
  ||| its lambdas bind them, as any lambda applied in a term binds its
  ||| argument (`applyHead`): a closure is bound once by a `let` and called
  ||| where it is used, never put in at each use, which the pipeline's
  ||| inliner decides. `value` is closed but for the markers
  ||| `0 .. length pre - 1`, which `pre` says what they stand for. Nothing
  ||| is evaluated, so a value that refers to a definition Idris does not
  ||| prove ends is walked as any other. The whole is translated at what
  ||| the use that applies it expects (`ex`), as any term is, so a lambda the
  ||| form gives is the closure its use's position types.
  settle : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) -> Ctx kc -> StandsFor kc OfTerm vars (Fin nv) ->
           Expected -> FC -> (value : ClosedTerm) -> (pre : List (Stand kc nv)) -> List (Arg vars nv) -> Front (Term nv)
  settle ph w acc ctx env ex fc value pre args = do
    loc <- toLoc (bestFC ctx fc)
    bindStands ph w acc ctx env ex loc fc 0 id pre (embedClosed {vars} value) args

  ||| A settled term with its markers bound, the first first: a variable as
  ||| another name for it, with no Core binder; a value by a `let` before the
  ||| term, of the Idris type the implementation that holds it gives it.
  ||| Each value is in the scope outside the binders made so far, which
  ||| `ren` takes into the current one, and is renamed once, where it is
  ||| bound. The term is then applied to `args`, at `fc`, the arguments taken
  ||| under each binder made, at what the whole is expected at (`ex`).
  bindStands : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
               (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
               Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> Loc -> FC -> Nat -> (Fin m -> Fin nv) ->
               List (Stand kc m) -> TT vars -> List (Arg vars nv) -> Front (Term nv)
  bindStands ph w acc ctx env ex loc fc i ren [] body [] = term ph w acc ctx env ex body
  bindStands ph w acc ctx env ex loc fc i ren [] body args@(_ :: _) = spine ph w acc ctx env ex fc body args
  bindStands ph w acc ctx env ex loc fc i ren (AsVariable e :: stands) body args =
    bindStands ph w acc ctx (map ren e :: env) ex loc fc (S i) ren stands (refToLocal (markerName i) (markerName i) body)
               (map overBinder args)
  bindStands ph w acc ctx env ex loc fc i ren (AsValue ity v :: stands) body args = do
    value <- rename ren <$> v
    -- The value is of the type its own term states; one whose term states
    -- none (it never returns, or a primitive's op makes its type) is of its
    -- Idris type's.
    core <- case termType ctx.depth (scopeOf env) value of
              Just t => pure t
              Nothing => do
                normal <- normaliseClosed ity
                coreType (bestFC ctx fc) ctx.owner ValueType normal
    rest <- bindStands ph w acc ctx (under {k = 1} [Runtime FZ (BothTypes core ity)] env) ex loc fc (S i) (FS . ren) stands
                       (refToLocal (markerName i) (markerName i) body) (map underLet args)
    pure (Let loc (shown "held") (OfValue Many) value rest)

  ||| A value an implementation closes over, computed inside a settled term
  ||| (`holed`): translated in the settled phase, its markers the variables
  ||| they stand for, on a path that enters the definition that gives the
  ||| implementation, whose place `holed` found it under (`gives`). A value
  ||| of it computed inside another of its own values would translate
  ||| without end, and is the one case refused.
  settledPiece : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                 (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> Expected -> FC -> (giver : Placement) -> (impl : ClosedTerm) ->
                 (stands : List (VarInfo kc OfTerm (Fin nv))) -> TT vars -> Front (Term nv)
  settledPiece ph w acc@(Access rec) ctx env ex afc giver impl stands p = do
    let Just (Element w' less) = enter giver w
      | Nothing => reject (bestFC ctx afc) ctx.owner RuntimeClosure
                          ("a value an implementation closes over, computed inside another of its own: " ++
                           !(showTT impl))
    loc <- toLoc (bestFC ctx afc)
    bindStands ph w' (rec w' less) ctx env ex loc afc 0 id (map AsVariable stands) p []

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
      marking k (e@(BoundHere _ _ (Just _)) :: es) = let (es', ss) = marking (S k) es in (TypeValue (holeMarker k) :: es', e :: ss)
      marking k (e :: es) = let (es', ss) = marking k es in (e :: es', ss)

      marked : (StandsFor kc OfTerm vars (Fin nv), List (VarInfo kc OfTerm (Fin nv)))
      marked = marking 0 env

      stands : List (VarInfo kc OfTerm (Fin nv))
      stands = snd marked

      standAt : Name -> Maybe (VarInfo kc OfTerm (Fin nv))
      standAt n = markerOf n >>= \k => getAt k stands

      -- What the written form has for a variable (`closeWritten`), where a
      -- stand's marker is: a runtime value's unknown value, its shape with
      -- the runtime value where the shape says nothing (`shapeWritten`), an
      -- implementation's form.
      writtenAs : VarInfo kc OfTerm (Fin nv) -> ClosedTerm
      writtenAs (Shaped _ _ _ s) = shapeWritten s
      writtenAs (Static d _ _) = d.form
      writtenAs (BoundHere t _ _) = t
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
      -- Each translated at the Core type of its Idris type (`aty`,
      -- normalised), as any term at a position that states its type.
      piece : Phase -> Placement -> ClosedTerm -> (aty : ClosedTerm) -> ClosedTerm -> Front (Front (Term nv))
      piece ph'@Settled giver impl aty p =
        pure (do t <- coreType (bestFC ctx afc) ctx.owner ValueType aty
                 settledPiece ph' w acc ctx env (ExpectedAt t) afc giver (restore impl) stands (embedClosed {vars} p))
      piece (Written next) _ _ aty p = do
        loc <- toLoc (bestFC ctx afc)
        pure (do t <- coreType (bestFC ctx afc) ctx.owner ValueType aty
                 bindStands next start (sizeAccessible start) ctx env (ExpectedAt t) loc afc 0 id (map AsVariable stands)
                            (embedClosed {vars} p) [])

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
        Nothing => (\t => Just (foundMarker 0, [(Nothing, aty, t)])) <$> piece ph giver impl aty p

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
          FixedNow _ <- fixing aty' form
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
                               pure (Just v, held, pure {f = Front} (Var loc v))) used
          pure (Just (impl', found))
        where
          isMarker : Nat -> TT vs -> Bool
          isMarker k (Ref _ _ n) = n == markerName k
          isMarker _ _ = False

          holders : Nat -> List (VarInfo kc OfTerm (Fin nv)) -> List (Nat, (Fin nv, Holes, ClosedTerm))
          holders k (Static d (Just (v, hs)) _ :: rest) = (k, (v, hs, d.form)) :: holders (S k) rest
          holders k (BoundHere t _ (Just (v, hs)) :: rest) = (k, (v, hs, t)) :: holders (S k) rest
          holders k (_ :: rest) = holders (S k) rest
          holders _ [] = []

          -- Each holder's marker as its form, its own markers the
          -- projections of the value it is.
          fill : Nat -> List (Nat, (Fin nv, Holes, ClosedTerm)) -> ClosedTerm -> Front ClosedTerm
          fill j [] t = pure t
          fill j ((k, (_, hs, form)) :: rest) t = do
            projections <- unpacked hs.types (foundMarker j)
            fill (S j) rest (substName (markerName k) (fillHoles projections form) t)

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

      -- An implementation's spine, each argument with its own walk
      -- suspended where it is a subterm.
      walk : ClosedTerm -> ClosedTerm -> List (ClosedTerm, Lazy (Front (Maybe (ClosedTerm, Found nv)))) ->
             Front (Maybe (ClosedTerm, Found nv))
      walk impl (App _ f a) args = walk impl f ((a, walk a a []) :: args)
      walk impl h args = headed impl h args

  ||| An implementation or a polymorphic function the program fixes, written
  ||| in a runtime position, as the member of its type's choice it is
  ||| (`Choices`), the type as `holds` read it a choice's: its form, with
  ||| the runtime values it closes over as its field. One written as a
  ||| function that is, up to eta, a runtime value of the scope (`\x => f
  ||| x`, `f` a value of the choice a match took out of a field) is that
  ||| value: the member the running program chose, which the choice's
  ||| members already hold. Nothing for one the running program chooses
  ||| otherwise (stuck on a runtime value), or one a definition Idris does
  ||| not prove ends computes, which no compile-time reduction runs, as the
  ||| choice's registration decides (`Choices.memberBare`): it is translated
  ||| as the computation it is, whose value is the choice among the members
  ||| its own body fixes.
  member : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> Loc -> ChoiceType -> TT vars -> Front (Maybe (Term nv))
  member ph w acc ctx env fc loc ct written = case runtimeValue (contracted written).etaForm of
    Just x => pure (Just (Var loc x))
    Nothing => do
      impl <- solved (closeWritten fc env written)
      if not !(runtimeDependent impl)
        then do
          found <- memberBare fc ctx.owner ct !(implementationOf impl)
          pure (map (\con => ConApp loc con [] []) found)
        else do
          Just (shape, values) <- holed ph w acc ctx env fc written
            | Nothing => pure Nothing
          Just con <- memberHolding fc ctx.owner ct !(implementationOf shape) (map fst values)
            | Nothing => pure Nothing
          v <- pack fc ctx.owner loc !(valuesOf values)
          pure (Just (ConApp loc con [] [v]))
    where
      -- The runtime variable of the scope a term is, if it is one.
      runtimeValue : TT vars -> Maybe (Fin nv)
      runtimeValue (Local _ _ idx p) = case lookupVar idx p env of
        Runtime x _ => Just x
        Shaped x _ _ _ => Just x
        _ => Nothing
      runtimeValue _ = Nothing

  ||| A runtime argument given at a parameter of Core type `pty`, its Idris
  ||| type (normalised) with what a value given there holds of the type's
  ||| choice (`held`, computed only where it is read): a callee's member
  ||| table says (`givenAt`), and at a parameter no definition's table
  ||| speaks for, the type itself does (`typeHolding`). A lambda given where
  ||| a polymorphic function is held is the member of its type's choice it
  ||| is (`member`): its own binders do not say its type, which the
  ||| parameter's does; one given delayed where a delayed one is held (a
  ||| branch of `if`), the member delayed. Any other is translated at the
  ||| Core type.
  parameterGiven : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                   (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                   Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> Loc -> (held : Front (Holding, ClosedTerm)) ->
                   (pty : Ty) -> Arg vars nv -> Front (Term nv)
  parameterGiven ph w acc ctx env afc loc held pty x = case x.written of
    Bind _ _ (Lam {}) _ => do
      (holding, t) <- held
      Just m <- asMember holding t x.written
        | Nothing => x.translated (ExpectedAt pty)
      pure m
    -- The member's type is the choice the parameter's delayed type holds,
    -- which its Core type was made of already.
    TDelay dfc _ _ inner@(Bind _ _ (Lam {}) _) => do
      (holding, TDelayed _ _ t') <- held
        | _ => x.translated (ExpectedAt pty)
      Just m <- asMember holding t' inner
        | Nothing => x.translated (ExpectedAt pty)
      dloc <- toLoc (bestFC ctx dfc)
      delayedTy <- dynamicDims <$> coreType (bestFC ctx dfc) ctx.owner ValueType t'
      pure (Suspend dloc delayedTy m)
    _ => x.translated (ExpectedAt pty)
    where
      asMember : Holding -> ClosedTerm -> TT vars -> Front (Maybe (Term nv))
      asMember holding ty lam = do
        Just ct <- holds holding ty
          | Nothing => pure Nothing
        member ph w acc ctx env afc loc ct lam

  ||| A value applied to arguments, over its Idris type (`fty`), which every
  ||| value an application applies is read at (`applyHead`): an argument at
  ||| a binder of quantity 0 is not passed, since the value takes none there
  ||| at runtime, and any other is applied, given at its parameter as the
  ||| parameter's type says (`parameterGiven`), so a lambda given where the
  ||| type holds a polymorphic function is the member of its choice, as at a
  ||| definition's parameter. A polymorphic function held at run time is a
  ||| value of its type's choice, whose members each use calls at its own
  ||| types: applied here, where it is held, it is a use of it, the member at
  ||| the use's types (`applyAtUse`). Each application is at the function
  ||| type the value's Core type (`core`) is, the type the value is made at,
  ||| and gives a value of its result, which the next one applies. Idris
  ||| checked the application, so the type shows a binder for every
  ||| argument: one past every binder it shows is the compiled module's,
  ||| refused, naming the head (`what`).
  applyOver : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
              (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
              Ctx kc -> StandsFor kc OfTerm vars (Fin nv) -> FC -> Loc -> Front String ->
              Term nv -> (core : Ty) -> (fty : ClosedTerm) -> List (Arg vars nv) -> Front (Term nv)
  applyOver ph w acc ctx env fc loc what f core fty [] = pure f
  applyOver ph w acc ctx env fc loc what f core fty (x :: xs) = do
    ty <- case fty of
            Bind _ _ (Pi {}) _ => pure fty
            _ => normaliseClosed fty
    case ty of
      Bind _ _ (Pi _ rig _ a) sc => do
        False <- polymorphicType ty
          | True => applyAtUse ctx env fc loc ty (known ty AChoice) (Just f) (x :: xs)
        next <- instantiate fc env sc x.written
        case use rig of
          Erased => applyOver ph w acc ctx env fc loc what f core next xs
          Used _ => applied (parameterGiven ph w acc ctx env fc loc (heldBy a)) next
      _ => do
        arg <- showTT (closeWritten fc env x.written)
        reject fc ctx.owner CompiledModule
               (arg ++ ", an argument of " ++ !what ++ " past every binder its type " ++ !(showTT ty) ++ " shows")
    where
      -- What a closure's parameter of this Idris type holds, as its type
      -- alone says: no definition's member table speaks for it.
      heldBy : ClosedTerm -> Front (Holding, ClosedTerm)
      heldBy a = do
        a' <- normaliseClosed a
        pure (!(typeHolding a'), a')

      -- Kept: Idris checked the application, so the value is a function's
      -- wherever an argument is given, and a Core function type is what a
      -- runtime binder of its Idris type becomes; but the Core type is a
      -- `Ty`, read apart from the Idris type it comes from, which does not
      -- say so. The argument is given at the parameter's Core type
      -- (`give`).
      applied : (give : Ty -> Arg vars nv -> Front (Term nv)) -> ClosedTerm -> Front (Term nv)
      applied give next = case core of
        FunT a r => do
          v <- give a.type x
          applyOver ph w acc ctx env fc loc what (App loc a r f v) r next xs
        _ => do
          named <- what
          internal fc ("an application of " ++ named ++ ", whose Core type " ++ show core ++ " is no function's")

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

      -- A runtime argument, at position `j` of a callee whose member places
      -- are `places`, its parameter's binder `b` and Idris type `t`
      -- (normalised where the parameter was classified): given there as
      -- the member table says (`givenAt`), and where the instance decides,
      -- as its type there does (`parameterGiven`).
      valueAt : Loc -> MemberPlaces -> Nat -> Binder -> ClosedTerm -> Arg vars nv -> Front (Term nv)
      valueAt loc places j b t x = parameterGiven ph w acc ctx env afc loc (pure (givenAt j places, t)) b.type x

      -- The runtime arguments of a call of a callee whose member places
      -- are `places`, one term per parameter that exists at runtime among
      -- those the arguments given reach, as many as its type says:
      -- nothing for a type, an implementation or an argument of quantity
      -- 0. An implementation that closes over runtime values passes them,
      -- as one value (`packedType`); a choice of one is its value, given as
      -- a parameter that holds a member of the choice is (`parameterGiven`):
      -- a function written there that is, up to eta, a choice it closes
      -- over (`\x => f x`) is that choice (`member`).
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
          from j (ChoiceParam b ct :: ks) (x :: xs) =
            (::) <$> parameterGiven ph w acc ctx env afc loc (pure (AMember, ct.type)) b.type x <*> from (S j) ks xs
          from j (DictParam _ (Just _) :: ks) (x :: xs) = (::) <$> heldValue loc x <*> from (S j) ks xs
          from j (DictParam _ Nothing :: ks) (_ :: xs) = from (S j) ks xs
          from j (TypeParam _ _ :: ks) (_ :: xs) = from (S j) ks xs
          from j (ErasedParam :: ks) (_ :: xs) = from (S j) ks xs
          from j (IndexParam _ :: ks) (_ :: xs) = from (S j) ks xs
          from j (FormParam _ :: ks) (_ :: xs) = from (S j) ks xs

      argValues : List (Arg vars nv) -> ArgValues
      argValues = map (argValueIn env afc)

      -- The call's value: `mk` on the runtime arguments when the call gives
      -- every parameter, applied to the arguments past them over the
      -- callee's result type (`resTy`), at `valueTy`, the Core type `mk`
      -- makes the value at, which the call knew before it made the term;
      -- with fewer, one closure per missing runtime parameter, as the
      -- curried type of the result requires. The arguments given
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
           then applyOver ph w acc ctx env afc loc (show <$> fullName name) value valueTy resTy (drop arity xs)
           else pure value

      -- A method or a parent taken from an implementation the call fixes:
      -- the implementation's field, as the implementation writes it,
      -- applied in place to the arguments past the projection's, settled
      -- (`settle`). Idris writes a method's field as a lambda over every
      -- argument of the method, erased ones included, applying the
      -- method's own function, so once its lambdas have bound the
      -- arguments, that function is called at its own arity and no
      -- instance of the projection exists. No key is made of what it
      -- reads, so it reads its type and implementation arguments in this
      -- scope, its levels kept (`inScope`): the field it takes is called
      -- at the indices this scope names. A projection that does not
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
        statics <- traverse (uncurry inScope) (zip kinds xs)
        case getAt idx kinds of
          Just (DictParam _ Nothing) => do
            Just field <- projected n statics
              | Nothing => pure Nothing
            Just <$> settle next start (sizeAccessible start) ctx env ex fc field [] (drop parity xs)
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
            let pre = map (\(ity, v) => AsValue ity v) (forget held)
            Just <$> settle next start (sizeAccessible start) ctx env ex fc field pre (drop parity xs)
          _ => pure Nothing
        where
          replaceAt : Nat -> a -> List a -> List a
          replaceAt Z v (_ :: ys) = v :: ys
          replaceAt (S i) v (y :: ys) = y :: replaceAt i v ys
          replaceAt _ _ ys = ys

          -- The compile-time value an argument gives at its kind, read in
          -- this scope as the call's classification read it for its key
          -- (`Instances.offeredAt`), but with this scope's levels kept: a
          -- type normalised, an implementation as written (what it is,
          -- where it is written as a function of a runtime value), a form
          -- as its kind holds it; nothing known of any other.
          inScope : PKind -> Arg vars nv -> Front ClosedTerm
          inScope (TypeParam _ _) x = closeNormalise fc env x.written
          inScope (DictParam _ _) x = do
            written <- solved (closeWritten fc env x.written)
            if !(runtimeDependent written) then implementationOf written else pure written
          inScope k _ = pure (compileTimeArg k)

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

      -- The Idris type of an operand, as the call's classification reads
      -- its parameter in this scope: a value's, a choice's, or that of the
      -- values an implementation closes over, held as one (`packedType`).
      operandType : FC -> PKind -> Front ClosedTerm
      operandType fc (ValueParam _ _ t) = pure t
      operandType fc (ChoiceParam _ ct) = pure ct.type
      operandType fc (DictParam _ (Just hs)) = packedType hs.types
      operandType fc _ = compileTimeOperand fc

      -- The Idris types of a row's operands, in order, one per binder
      -- (`operandBinders`).
      operandTypes : FC -> Operands n k -> Vect n PKind -> Front (Vect k ClosedTerm)
      operandTypes fc NoParameter [] = pure []
      operandTypes fc (NoOperand ops) (_ :: ks) = operandTypes fc ops ks
      operandTypes fc (Operand ops) (kind :: ks) = (::) <$> operandType fc kind <*> operandTypes fc ops ks

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

      -- A lowered call's value: its hook's value on every operand, of the
      -- Core type `valueTy`, which the call knew before the hook made the
      -- term, the arguments past its arity applied to it at that type, over
      -- the result type read in this scope; or, where the call leaves
      -- operands out, a closure over each, as with a call of a function.
      -- An operand is left out only where the arguments end before the
      -- arity (`operandsGiven`), so none is past it.
      completed : Loc -> (arity : Nat) -> List (Arg vars nv) -> Supplied k nv -> Maker k -> (valueTy : Ty) -> ClosedTerm ->
                  Front (Term nv)
      completed loc arity xs (MkSupplied given [] together) mk valueTy resTy =
        applyOver ph w acc ctx env afc loc (show <$> fullName name) (etaExpand loc [] valueTy (recount together mk) given)
                  valueTy resTy (drop arity xs)
      completed loc arity xs (MkSupplied given missing@(_ :: _) together) mk valueTy resTy =
        pure (etaExpand loc missing valueTy (recount together mk) given)

      -- The identity on the last operand, wherever it stands among the
      -- proofs and types (a cell's form or a frame's extents before it
      -- are not read): given exactly its operands, that argument's value
      -- alone, at what the call is expected at; given more, that value, of its parameter's binder's type,
      -- the ones past its arity applied to it over the type the call gives
      -- (`completed`); below its arity a closure over its missing operands,
      -- whose body is the saturated identity, as every hook is below its
      -- arity.
      identity : FC -> Loc -> (arity : Nat) -> Operands arity (S k) -> Defined -> ClosedTerm -> List (Arg vars nv) ->
                 Front (Term nv)
      identity fc loc arity ops d ty xs = case saturation arity xs of
        Saturated now [] => (Data.Vect.index (lastOperand ops) now).translated ex
        _ => do
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
      -- world, after which nothing runs. The action is the last value the
      -- call passes, bound at the type this instance gives it, an action on
      -- the world, so the variable that applies it is of the type it is
      -- applied at; the boundary read only its shape (`ExitTypes`), since
      -- what it gives may name a type only the instance fixes. The exit's
      -- value is a lambda of the world, which never returns: its result is
      -- the one its position expects where that is an action on the world,
      -- as Idris's elaborator checked it there, and else the action's own,
      -- which a value that never returns may be given.
      exitAction : ExitTypes -> FC -> Loc -> Nat -> ClosedTerm -> List (Arg vars nv) -> Front (Term nv)
      exitAction exit fc loc arity ty xs = do
        (found, resTy) <- classifyCall fc ctx.owner (show name) arity ty (argValues (take arity xs))
        let kinds = toList found
        given <- arguments loc (memberPlaces d) kinds (take arity xs)
        let binders = runtimeBinders kinds
        (actionWorld, acted) <- actionOf binders
        let action = FunT actionWorld acted
            (valueWorld, result) = case (drop arity xs, ex) of
                                     ([], ExpectedAt (FunT b@(MkBinder _ WorldT) r)) => (b, r)
                                     _ => (MkBinder exit.valueWorld WorldT, acted)
        mk <- exits actionWorld acted action valueWorld result binders
        finish loc kinds arity xs given mk (FunT valueWorld result) resTy
        where
          -- What the action takes the world at and gives, off its binder at
          -- this instance. Essential: the boundary read the action's shape
          -- with the definition's variables as placeholders, which an
          -- instance's types may still contradict.
          actionOf : Vect r Binder -> Front (Binder, Ty)
          actionOf [] = unshaped fc "the registry names an exit whose action the definition does not take"
          actionOf bs@(_ :: _) = case (last bs).type of
            FunT w@(MkBinder _ WorldT) r => pure (w, r)
            _ => unshaped fc "the registry names an exit whose believe_me does not give an action on the world any result"

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
      -- the hook gives it and its type shows. Its calls are translated at
      -- its case tree's parameters, as every call of a definition is, and
      -- the values its clauses do not take are applied to what it gives.
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
        -- kinds, so it is read there, once, against the row's operands at
        -- its case tree's parameters, the first of them (`treeOperands`). A
        -- type, an implementation, a form or a choice among them is a
        -- compile-time argument the hook cannot give.
        let Just atTree = treeOperands checked.operands called.kinds
          | Nothing => reject fc (show lib.named) HookShape "the registry names a library function with compile-time arguments"
        -- Its runtime arguments are all a call gives it, so no index
        -- parameter of it is given a term it is linked to.
        is <- callIndices called.kinds vals
        case atTree of
          TreeTakesAll saturated => do
            let mk = recount (sym saturated) (recount called.sameCount (MkMaker (\ys => Call loc sig.callee Nothing is ys)))
            pure {f = Front} (\ns => mk.make ns)
          -- The binders its type shows past its case tree's parameters are
          -- its result's, read at the call as each runtime parameter is,
          -- against the row's operands there: the call's value is applied
          -- to the values they take.
          AppliedPast {past} after given => do
            (pastKinds, final) <- classifyCall fc ctx.owner (show lib.named) (S past) called.result
                                                 (the ArgValues (replicate (S past) Nothing))
            let Just (Element _ applied) = valuesAt after (toList pastKinds)
              | Nothing => reject fc (show lib.named) HookShape "the registry names a library function with compile-time arguments"
            result <- coreType fc ctx.owner ValueType final
            pure {f = Front} (\ns => calledThenApplied loc sig.callee is called.sameCount (runtimeBinders called.kinds)
                                       (runtimeBinders (toList pastKinds))
                                       (trans (cong (Runtimes called.kinds +) applied) given) result ns)
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

      -- How a field's value is read: as the classification read the value
      -- at its position, or as the layout's binder holds it.
      fieldRead : Binder -> ClosedTerm -> List PKind -> (Binder, Maybe ClosedTerm, ClosedTerm)
      fieldRead b t (ValueParam b' shape t' :: _) = (b', shape, t')
      fieldRead b t _ = (b, Nothing, t)

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

      -- A constructor application: a value of its family, of its fields,
      -- however few; how a family of one field is laid out is the
      -- dialect's.
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
          (_, Just (df, _)) => do
            -- Its tag is its place among its type's constructors, where
            -- the family holds its layout: Idris's numbering. The
            -- application is where the frontend first reads the
            -- constructor it builds with, so one its type does not list is
            -- refused here, as the compiled module it is.
            let Just (_, info) = constructorIn df d
              | Nothing => reject fc ctx.owner CompiledModule
                                  ("an application of " ++ show (fullname def) ++ ", which its type does not list as a constructor")
            -- Its fields are the call's runtime arguments, as many as its
            -- layout has, by construction (`asFields`): an implementation
            -- the constructor holds is a field like any other, the value of
            -- its choice the construction site gives.
            let (fields ** counted) = asFields info.args kinds
            given <- arguments loc (memberPlaces d) fields (take arity xs)
            let con = info.con
            links <- binderTerms con.binders (argValues (take arity xs))
            finish loc fields arity xs given (recount counted (MkMaker (\ys => ConApp loc con links ys))) (conType con links) resTy

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

      -- The type arguments of a call, in order.
      typeParams : List PKind -> List ClosedTerm
      typeParams (TypeParam t _ :: ks) = t :: typeParams ks
      typeParams (_ :: ks) = typeParams ks
      typeParams [] = []

      -- The Idris type of a runtime argument a call gives.
      runtimeType : PKind -> Maybe ClosedTerm
      runtimeType (ValueParam _ _ t) = Just t
      runtimeType _ = Nothing

      -- The data family a type the call reads names, as `coreType` reads
      -- it (`dataFamilyOf`): what the call's hook takes its values apart
      -- by, held, so no family is looked up by its identity.
      familyAt : FC -> ClosedTerm -> Front DataFamily
      familyAt fc ty = do
        Just (df, _) <- dataFamilyOf fc ctx.owner ty
          | Nothing => do
              written <- showTT ty
              unshaped fc ("the array language's function, given a value of type " ++ written ++ ", which is no data type")
        pure df

      -- The one constructor of the data family a type the call reads names
      -- (`Choices.onlyCon`), with its fields' Idris types.
      onlyAt : FC -> (k : Nat) -> ClosedTerm -> Front (Only k)
      onlyAt fc k ty = familyAt fc ty >>= onlyCon k (unshaped fc)

      -- What an IO primitive gives besides the next world, as many values
      -- as its action gives: for none, the unit its `IORes` holds, the one
      -- constructor of its value's type, read off the family the `IORes`
      -- field's Idris type names; for one, that value.
      gives : {0 count : Nat} -> FC -> IOAction i count -> Only 2 -> Front (IOGives count)
      gives fc a res = case actionGives a of
        GivesNone => GivesUnit . (.single) <$> onlyAt fc 0 (Data.Vect.index 0 res.fieldTypes)
        GivesOne => pure GivesValue

      -- What a function type takes at run time first and gives after it,
      -- as Idris types, every binder before it a placeholder: a binder of
      -- quantity 0 is no argument at run time, as `coreType` reads a
      -- function type.
      runtimeArrow : FC -> ClosedTerm -> Front (ClosedTerm, ClosedTerm)
      runtimeArrow fc ty = normaliseClosed ty >>= arrow
        where
          arrow : {vs : Scope} -> TT vs -> Front (ClosedTerm, ClosedTerm)
          arrow (Bind _ _ (Pi _ rig _ a) sc) = case use rig of
            Erased => arrow sc
            Used _ => pure (closedOver a, closedOver sc)
          arrow other = do
            written <- showTT (closedOver other)
            unshaped fc ("the array language's function, given a value of type " ++ written ++ " for a function")

      -- The constructors of a snoc list of naturals (`Extents`, `Index`),
      -- in tag order, the order the library declares them in: the empty
      -- one and the snoc of the rest and the natural, read off the family
      -- its Idris type names.
      snocCons : FC -> ClosedTerm -> Front Snocs
      snocCons fc ty = do
        df <- familyAt fc ty
        let [(0 ** lin), (2 ** snoc)] = (dataDeclared df).cons
          | _ => unshaped fc ("the array language's extents or coordinates of " ++ keyText df.key ++
                              ", which is not a snoc list of naturals")
        case (Data.Vect.index 1 snoc.fields).type of
          NatT _ => pure (MkSnocs lin snoc IsNatural)
          t@(DataT _ _) => pure (MkSnocs lin snoc (IsNumeral (substTy [] t)))
          t => unshaped fc ("the array language's extents or coordinates of " ++ keyText df.key ++
                            ", whose snoc holds a value of type " ++ show t ++ ", no natural or numeral")

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
      -- gives the variable it is bound to. The operands' Idris types (`ts`)
      -- and the result's (`resTy`) name the families the hook takes values
      -- of apart or builds.
      arrayTerm : {0 count : Nat} -> FC -> Loc -> ArrayPrim -> Ty -> (resTy : ClosedTerm) -> Vect count Binder ->
                  Vect count Ty -> (ts : Vect count ClosedTerm) -> List Ty -> List ClosedTerm -> Front (Maker count)
      arrayTerm fc loc g rt resTy bs vs ts typeArgs idrisTypes = case (g, map (.type) bs, vs, ts) of
        (AShape, [xTy], _, _) => do
          a <- theElement
          s <- snocCons fc resTy
          (rx ** xa) <- arrayOf xTy
          let r = minus rx (rank a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [x] =>
                  snocValue loc s (map (\j => Tensor loc (Extent xa j (Var loc x))) (take r (toList (Data.Vect.allFins rx))))))
        (ATabulate, [eTy, _], [_, FunT ib@(MkBinder _ idxTy) bTy], [eIdris, fIdris]) => do
          eSnoc <- snocCons fc eIdris
          iSnoc <- snocCons fc (fst !(runtimeArrow fc fIdris))
          let r = minus (rank rt) (rank bTy)
          cellsFixed fc rt r
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [e, f] =>
                  apart loc eSnoc r e (\ren', ds =>
                              Tabulate loc rt (fromList ds)
                                (App loc ib bTy (Var loc (Free {k = length ds} (ren' f)))
                                         (snocValue loc iSnoc (map (Var loc . Bound) (toList (Data.Vect.allFins (length ds)))))))))
        (AIndex, [xTy, iTy], _, [_, iIdris]) => do
          iSnoc <- snocCons fc iIdris
          (rx ** xa) <- arrayOf xTy
          let r = minus rx (rank rt)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [x, i] =>
                  apart loc iSnoc r i (\ren', cs => Tensor loc (Extract xa rt (Var loc (ren' x)) cs))))
        (AUpdate, [xTy, iTy, vTy], _, [_, iIdris, _]) => insert xTy iIdris vTy bs
        (AWrite, [lTy, iTy, vTy], _, [lIdris, iIdris, _]) => do
          (writing, ds, e) <- cellOf lIdris
          iSnoc <- snocCons fc iIdris
          let r = minus (length ds) (rank vTy)
              xa = MkArrayType (Data.Vect.fromList ds) e
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [l, i, v] =>
                  opened loc writing l (\ren', x =>
                    apart loc iSnoc r (ren' i) (\ren'', cs =>
                      ConApp loc writing []
                        [Tensor loc (Insert xa (TensorT ds e) (Var loc (ren'' x)) (Var loc (ren'' (ren' v))) cs)]))))
        (AFoldLast, [_, zTy, xTy], [FunT ab (FunT eb out), _, _], _) => reduce FoldLast ab eb out zTy xTy bs
        (AScanLast, [_, zTy, xTy], [FunT ab (FunT eb out), _, _], _) => reduce ScanLast ab eb out zTy xTy bs
        (AReshape, [eTy, xTy], _, [eIdris, _]) => do
          a <- theElement
          eSnoc <- snocCons fc eIdris
          (_ ** xa) <- arrayOf xTy
          let r = minus (rank rt) (rank a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [e, x] =>
                  apart loc eSnoc r e (\ren', es => Tensor loc (Reshape xa rt (Var loc (ren' x)) es))))
        -- The cells put back with the extents given, not the ones the
        -- cells hold: an empty frame has no cell to read them from, so the
        -- array is flattened and expanded to the frame's extents and then
        -- the given ones.
        (AMerge, [eTy, xTy], _, [eIdris, _]) => do
          a <- theElement
          eSnoc <- snocCons fc eIdris
          cellAxes <- cellRank
          (rx ** xa) <- arrayOf xTy
          let frame = minus (minus rx (rank a)) cellAxes
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [e, x] =>
                  apart loc eSnoc cellAxes e (\ren', es =>
                    Tensor loc (Reshape xa rt (Var loc (ren' x))
                                  (map (\j => Tensor loc (Extent xa j (Var loc (ren' x)))) (take frame (toList (Data.Vect.allFins rx)))
                                   ++ es)))))
        -- A transpose swaps its axis with the one after it, so its array
        -- has an axis past the one it names.
        (ATranspose, [xTy], _, _) => do
          a <- theElement
          (S rx ** xa) <- arrayOf xTy
            | (Z ** _) => unshaped fc "the array language's transpose, of an array of no axis"
          axis <- axisOf rx (minus (lastAxis xTy a) 1)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [x] => Tensor loc (Transpose xa rt axis (Var loc x))))
        (ATake, [_, xTy], _, _) => do
          a <- theElement
          (rx ** xa) <- arrayOf xTy
          ra <- ofRank rx rt
          axis <- axisOf rx (lastAxis xTy a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [k, x] => Tensor loc (Take xa ra axis (Var loc k) (Var loc x))))
        (ADrop, [_, xTy], _, _) => do
          a <- theElement
          (rx ** xa) <- arrayOf xTy
          ra <- ofRank rx rt
          axis <- axisOf rx (lastAxis xTy a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [k, x] => Tensor loc (Drop xa ra axis (Var loc k) (Var loc x))))
        (AConcat, [xTy, yTy], _, _) => do
          a <- theElement
          (rx ** xa) <- arrayOf xTy
          ya <- ofRank rx yTy
          ra <- ofRank rx rt
          axis <- axisOf rx (lastAxis xTy a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [x, y] => Tensor loc (Concat xa ya ra axis (Var loc x) (Var loc y))))
        (APad, [_, _, vTy, xTy], _, _) => do
          (rx ** xa) <- arrayOf xTy
          ra <- ofRank rx rt
          axis <- axisOf rx (lastAxis xTy vTy)
          fill <- fillOf (minus rx (S (finToNat axis))) vTy
          let front = alongAxis axis xa
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [lo, hi, v, x] =>
                  Tensor loc (Concat front front ra axis
                    (Tensor loc (Concat front xa front axis (copies xa axis fill (Var loc x) (Var loc lo) (Var loc v)) (Var loc x)))
                    (copies xa axis fill (Var loc x) (Var loc hi) (Var loc v)))))
        (AWithArray, [eTy, vTy, _], [_, _, FunT lb@(MkBinder _ lTy) kr], [eIdris, _, kIdris]) => do
          (writing, ds, e) <- cellOf (fst !(runtimeArrow fc kIdris))
          eSnoc <- snocCons fc eIdris
          let r = minus (length ds) (rank vTy)
          fill <- fillOf (minus (length ds) r) vTy
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [ex, v, k] =>
                  apart loc eSnoc r ex (\ren', ns =>
                    App loc lb kr (Var loc (ren' k))
                        (ConApp loc writing [] [filled ds e fill ns (Var loc (ren' v))]))))
        -- The element is read at the type of the held array's cells and
        -- given at the element's, which may fix extents the cells leave to
        -- their values.
        (ARead, [lTy, iTy], _, [lIdris, iIdris]) => do
          (writing, ds, e) <- cellOf lIdris
          a <- theElement
          iSnoc <- snocCons fc iIdris
          res <- (.single) <$> onlyAt fc 2 resTy
          let r = minus (length ds) (rank a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [l, i] =>
                  opened loc writing l (\ren', x =>
                    apart loc iSnoc r (ren' i) (\ren'', cs =>
                      ReadBack loc (cellAfter r ds e) (Var loc (ren'' x)) cs
                        (ConApp loc res [] [ Var loc (Bound {k = 2} FZ)
                                           , ConApp loc writing [] [Var loc (Bound {k = 2} (FS FZ))]])))))
        -- A thaw hands the continuation the array itself in a writable
        -- cell: whether writing it needs a copy first is bufferization's to
        -- decide, which sees whether anything reads the array after.
        (AThaw, [_, _], [_, FunT lb@(MkBinder _ lTy) kr], [_, kIdris]) => do
          (writing, _, _) <- cellOf (fst !(runtimeArrow fc kIdris))
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [x, k] =>
                  App loc lb kr (Var loc k) (ConApp loc writing [] [Var loc x])))
        (ALShape, [lTy], _, [lIdris]) => do
          (writing, ds, _) <- cellOf lIdris
          only <- onlyAt fc 2 resTy
          let res = only.single
          a <- theElement
          s <- snocCons fc (Data.Vect.index 0 only.fieldTypes)
          let r = minus (length ds) (rank a)
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [l] =>
                  opened loc writing l (\ren', x =>
                    ExtentsBack {k = r} loc (Var loc x)
                      (ConApp loc res []
                         [ snocValue loc s (toList (map (\j => Var loc (Bound (weaken j))) (Data.Vect.allFins r)))
                         , ConApp loc writing [] [Var loc (Bound (last {n = r}))]]))))
        -- The grown array fills a cell of the result's type, as long on the
        -- last axis as the result's shape says.
        (AGrow, [_, vTy, lTy], _, [_, _, lIdris]) => do
          (writing, ds, e) <- cellOf lIdris
          (grown, gds, _) <- cellOf resTy
          let xa = MkArrayType (Data.Vect.fromList ds) e
          ga <- ofRank (length ds) (TensorT gds e)
          axis <- axisOf (length ds) (lastAxis (TensorT ds e) vTy)
          fill <- fillOf (minus (length ds) (S (finToNat axis))) vTy
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [k, v, l] =>
                  opened loc writing l (\ren', x =>
                    ConApp loc grown []
                      [Tensor loc (Concat xa (alongAxis axis xa) ga axis
                         (Var loc x) (copies xa axis fill (Var loc x) (Var loc (ren' k)) (Var loc (ren' v))))])))
        -- The step at each index and the tabulation are `IO` values, each
        -- read at `IO` (`ioAt`): the tabulation is `IO`'s
        -- constructor applied to its action, which runs the step's action
        -- at each index on the world before it. The step's and the
        -- result's `IORes` are read off the Idris types of their actions.
        (ATabulateIO, [eTy, _], [_, FunT ib stepIO], [eIdris, actIdris]) => do
          (idxIdris, stepIdris) <- runtimeArrow fc actIdris
          stepAt <- ioAt fc ctx.owner (\why => unshaped fc ("the array language's world-ordered tabulation, given " ++ why))
                         stepIdris
          doneAt <- ioAt fc ctx.owner (\why => unshaped fc ("the array language's world-ordered tabulation, giving " ++ why))
                         resTy
          stepCon <- (.single) <$> onlyAt fc 2 (snd !(runtimeArrow fc stepAt.primIO))
          doneCon <- (.single) <$> onlyAt fc 2 (snd !(runtimeArrow fc doneAt.primIO))
          let arrTy = (Data.Vect.index 0 doneCon.fields).type
          a <- theElement
          eSnoc <- snocCons fc eIdris
          iSnoc <- snocCons fc idxIdris
          let r = minus (rank arrTy) (rank a)
          cellsFixed fc arrTy r
          pure $ MkMaker (\ys => bindArguments loc bs ys (\ren, [e, act] =>
                  apart loc eSnoc r e (\ren', ds =>
                    ConApp loc doneAt.family.io []
                      [Lam noLoc (shown "world") (MkBinder doneAt.family.world WorldT) doneAt.family.gives
                         (TabulateIO loc arrTy (map (rename FS) (fromList ds)) (Var loc FZ)
                            (runIO loc stepAt.family
                               (App loc ib stepIO (Var loc (Free {k = S (length ds)} (FS (ren' act))))
                                    (snocValue loc iSnoc
                                       (map (Var loc . Bound . weaken) (toList (Data.Vect.allFins (length ds))))))
                               (Bound (last {n = length ds})))
                            stepCon doneCon)])))
        _ => unshaped fc "the array language's function, at operand types it does not have"
        where
          -- The constructor of a linear array's cell, read off the family
          -- its Idris type names, and the dimensions and element of the
          -- array it holds.
          cellOf : ClosedTerm -> Front (Con 1, List Dim, Ty)
          cellOf t = do
            c <- (.single) <$> onlyAt fc 1 t
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

          insert : Ty -> ClosedTerm -> Ty -> Vect 3 Binder -> Front (Maker 3)
          insert xTy iIdris vTy three = do
            iSnoc <- snocCons fc iIdris
            (rx ** xa) <- arrayOf xTy
            let r = minus rx (rank vTy)
            pure $ MkMaker (\ys => bindArguments loc three ys (\ren, [x, i, v] =>
                    apart loc iSnoc r i (\ren', cs =>
                      Tensor loc (Insert xa rt (Var loc (ren' x)) (Var loc (ren' v)) cs))))

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
      -- classified; and the Idris types of the result (`resTy`) and of the
      -- operands (`ts`), which name the families a hook takes apart or
      -- builds.
      maker : {k : Nat} -> FC -> Loc -> Maybe Shown -> (bs : Vect k Binder) -> (vs : Vect k Ty) -> Vect n PKind -> (rt : Ty) ->
              (resTy : ClosedTerm) -> (ts : Vect k ClosedTerm) -> Lowering CheckedLibrary k -> Front (Maker k)
      maker fc loc lowered bs vs kinds rt resTy ts (NatPrimitive p) = pure (MkMaker (\ns => PrimApp loc p lowered ns))
      maker fc loc lowered bs vs kinds rt resTy ts (NatClamped p) =
        pure (MkMaker (\ns => PrimApp loc (Op natFromBig (NatT IOpaque) made) lowered
                                [PrimApp loc p lowered (map (\n => PrimApp loc (Op natToBig BigT made) lowered [n]) ns)]))
      maker fc loc lowered bs vs kinds rt resTy ts (NatTested test lib) = do
        toBool <- libraryCall fc loc lib
        pure (MkMaker (\ns => toBool [PrimApp loc test lowered ns]))
      maker fc loc lowered bs vs kinds rt resTy ts (NatOnIntegers lib) = do
        f <- libraryCall fc loc lib
        pure (MkMaker (\ns => f (map (\n => PrimApp loc (Op natToBig BigT made) lowered [n]) ns)))
      -- A string built once from the list the definition's type takes.
      maker fc loc lowered bs vs kinds rt resTy ts (Builder p fits) =
        pure (MkMaker (\ys => PrimApp loc (replace {p = Prim} fits (Op p.op rt made)) lowered ys))
      -- A function of the array language: the tensor operations of its
      -- sequential meaning, over its operands bound once each in order. A
      -- rank is read from the types of the operands and the result, never
      -- from the order of the implicits.
      maker fc loc lowered bs vs kinds rt resTy ts (ArrayOperation g) = do
        typeArgs <- traverse (\t => coreType fc ctx.owner ValueType !(normaliseClosed t)) (typeParams (toList kinds))
        arrayTerm fc loc g rt resTy bs vs ts typeArgs (mapMaybe runtimeType (toList kinds))
      maker fc loc lowered bs vs kinds rt resTy ts IdentityOnLast = pure (MkMaker (\ys => Data.Vect.last ys))
      -- A pure primitive on the operands and then the literals the call
      -- does not supply, of the call's result type, read in this scope: a
      -- result an erased argument indexes (the bound of a numeral a
      -- natural becomes) is typed at the term the call gives it.
      maker fc loc lowered bs vs kinds rt resTy ts (PureOperation p lits fits) =
        pure (MkMaker (\ys => PrimApp loc (replace {p = Prim} (sym fits) (Op p.op rt made)) lowered
                                (ys ++ map (Literal loc) (fromList lits))))
      maker fc loc lowered bs vs kinds rt resTy ts (IOOperation lits a) = do
        res <- onlyAt fc 2 resTy
        what <- gives fc a res
        pure (MkMaker (\ys => Effect loc a what (Data.Vect.init ys ++ map (Literal loc) (fromList lits)) (Data.Vect.last ys) res.single))
      -- An array access, IO in the world's order, giving the `IORes` of the
      -- call's result type, at the rank its row read off its operands.
      maker fc loc lowered bs vs kinds rt resTy ts (AccessOperation access rank) = do
        res <- onlyAt fc 2 resTy
        what <- gives fc (Accesses access rank) res
        pure (MkMaker (\ys => Effect loc (Accesses access rank) what (Data.Vect.init ys) (Data.Vect.last ys) res.single))
      -- A foreign definition's primitive on the operands and then the
      -- literals the call does not supply: a handle's test for null is a
      -- comparison with the null handle.
      maker fc loc lowered bs vs kinds rt resTy ts (PrimOperation lits p) =
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
      lowerCall fc loc lowered (MkLowered {arity} {count = S k} ops (IOOperation lits a)) d ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner (show (fullname d.def)) arity ty (argValues (take arity xs))
        rt <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
        MkSupplied values missing together <- operandsGiven fc loc (memberPlaces d) ops kinds 0 xs
        bs <- operandBinders fc ops kinds
        ts <- operandTypes fc ops kinds
        mk <- maker {k = S k} fc loc lowered bs (boundTypes values missing together bs) kinds rt resTy ts (IOOperation lits a)
        completed loc arity xs (MkSupplied values missing together) mk rt resTy
      lowerCall fc loc lowered (MkLowered {arity} {count} ops low) d ty xs = do
        (kinds, resTy) <- classifyCall fc ctx.owner (show (fullname d.def)) arity ty (argValues (take arity xs))
        MkSupplied values missing together <- operandsGiven fc loc (memberPlaces d) ops kinds 0 xs
        rt <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
        bs <- operandBinders fc ops kinds
        ts <- operandTypes fc ops kinds
        mk <- maker {k = count} fc loc lowered bs (boundTypes values missing together bs) kinds rt resTy ts low
        completed loc arity xs (MkSupplied values missing together) mk rt resTy

      -- A call of a definition the registry's hooks lower, whatever
      -- declares it, or `otherwise` when no hook does: a deprecated one is
      -- refused; one whose calls a hook lowers to an operation on its
      -- operands is that operation, by its row (`lowerCall`); a handle and
      -- a string of the compiler's are constants, each with the type it is
      -- made at; an alias is a call of the function it stands for.
      hooked : FC -> Loc -> Name -> Maybe Shown -> Defined -> ClosedTerm -> Hooks LibraryFunction -> Front (Term nv) ->
               Front (Term nv)
      hooked fc loc full lowered d ty hs otherwise =
        let constant = \v, t => applyOver ph w acc ctx env fc loc (pure (show full)) v t ty args in
        fromMaybe otherwise $
              map (reject fc ctx.owner Deprecated) hs.deprecated
          <|> map (\row => lowerCall fc loc lowered row d ty args) d.loweredBy
          <|> map (\h => constant (Literal loc h) (Term.literalType h)) hs.handle
          <|> map (\lib => aliasCall fc loc lowered lib args) hs.alias
          <|> map (uncurry constant . systemFact) hs.systemInfo
        where
          systemFact : SystemFact -> (Term nv, Ty)
          systemFact TargetOs = (PrimApp loc (Op platformOsOp StrT Hold.Static) Nothing [], StrT)
          systemFact BackendName = (Literal loc (LStr codegenName), StrT)

||| An implementation the environment binds (`Static`), computed at run
||| time where the translation reaches it, as the term `t` it is written as,
||| of Idris type `ty` (`implementationAt`, applied to nothing), at the Core
||| type its place holds it at (`ex`): a call of a definition Idris does not
||| prove ends runs there, eagerly, its divergence its call's.
export
computedAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             Ctx kc -> FC -> Expected -> (t, ty : ClosedTerm) -> Maybe (Fin nv, Holes) -> Front (Term nv)
computedAt ctx fc ex t ty held = implementationAt {vars = Scope.empty} asWritten start (sizeAccessible start) ctx [] ex fc t ty held []
