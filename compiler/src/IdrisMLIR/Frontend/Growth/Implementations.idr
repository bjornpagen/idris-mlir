-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a dictionary holds, over the parameters of the definition that
||| gives it: an implementation's fields, each read as the static argument it
||| is, with the root of the dictionary there, and a constructor's own
||| parameters, which are its fields.
module IdrisMLIR.Frontend.Growth.Implementations

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.TT

import Libraries.Data.List.Thin

import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Data.List
import Data.SortedMap

%default total

||| One field of a dictionary, over the parameters of the definition that
||| gives it (`Var i 0` is its parameter i). A method's field that Idris
||| wrote also says where its method function M takes each argument: M's
||| parameters do not start with the implementation's, since a method's
||| own implicit type variables come first (`map_Functor_(EitherT e m)` is
||| `{b} {a} {e} {m} {Functor m} func x`), so the placement is read off the
||| field, never assumed.
public export
data Field : Type where
  -- an eta-wrapped method field: its method function m, its template, and where each argument lands in m.
  -- own: for each of the method's own arguments (the field's lambdas, in order), its parameter index in m;
  -- leading: for each implementation parameter p, its index in m. Its root is m, by construction.
  Method : (m : Address) -> Template -> (own : List Nat) -> (leading : List (Nat, Nat)) -> Field
  -- any other field: a hand-built dictionary's lambda, a superclass dictionary, with its dictionaryRoot
  Plain : Template -> Root -> Field

||| The fields of a definition that gives a dictionary, over its own
||| parameters, in the interface constructor's order.
public export
Fields : Type
Fields = List Field

||| Field k of the dictionary the definition at an address gives: nothing
||| when it gives none, or fewer fields.
export
fieldAt : SortedMap Address Fields -> Address -> Nat -> Maybe Field
fieldAt fs j k = lookup j fs >>= head' . drop k

||| What every field gives the flow, method or not: its template and its
||| root. A method field's root is its function.
export
fieldRead : Field -> (Template, Root)
fieldRead (Method m t _ _) = (t, Rooted m)
fieldRead (Plain t r) = (t, r)

||| What a constructor's argument is to the dictionary it builds, by its
||| binder: a static argument of a kind (at quantity 0, the interface's own
||| type arguments; at a dictionary binder, a parent), or a method's field,
||| which Idris writes as a lambda wrapping the method's own function.
data Binding = Reads Static | Wrapped

||| A binder's binding, by its quantity, then, for a used binder, by whether
||| its type is an implementation's (`implementationType`), which decides
||| in any scope, as it does for a function's parameters and a
||| constructor's fields, so the binders before it need no stand-ins.
bindingOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> RigCount -> TT vs -> Front Binding
bindingOf rig a = case use rig of
  Erased => pure (Reads AType)
  Used _ => (\dict => if dict then Reads ADictionary else Wrapped) <$> implementationType a

||| What stands for each parameter of an implementation in its body, the
||| first first, as the translation binds it: its marker where the
||| parameter is static (`staticsOver`, every parameter given as its
||| marker), so that a field holds it as the parameter it is; otherwise,
||| by its binder's quantity, an erased placeholder at 0 and an unknown
||| runtime value elsewhere, as `closeWritten` writes a runtime variable. A
||| type `implementationType` accepts shows a binder for each parameter.
marks : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
        (owner : String) -> Defined -> (arity : Nat) -> Front (List (VarInfo ()))
marks owner d arity = do
  (kinds, _) <- staticsOver owner arity d.type (map (\i => Just (markerAt i 0, AValue)) (iterateN arity S 0))
  pure (standing 0 (toList kinds) d.type)
  where
    standing : Nat -> List (Maybe Static) -> TT vs -> List (VarInfo ())
    standing i (Just _ :: ks) (Bind _ _ (Pi {}) sc) = TypeValue (markerAt i 0) :: standing (S i) ks sc
    standing i (Nothing :: ks) (Bind _ _ (Pi _ rig _ _) sc) =
      TypeValue (Erased EmptyFC (case use rig of Erased => Placeholder; Used _ => Impossible)) :: standing (S i) ks sc
    standing _ _ _ = []

||| What a method's field passes the function it applies, at one argument:
||| one of the field's own arguments (a variable of its lambda, by its
||| index there, the innermost 0), or a closed term over the
||| implementation's parameters.
data Passed = Own Nat | Fixed ClosedTerm

||| The function a method's field applies, what it passes it at each of its
||| parameters, and the parameter at which it takes each of the field's own
||| arguments, the outermost first, when the field is an eta wrapper. Idris
||| writes a method's field as a lambda over every argument of the method,
||| erased ones included, whose body applies the method's own function to
||| each of those arguments and to the implementation's parameters
||| (`\{b}, {a}, func, x => map_Functor_(EitherT e m) b a e m d func x`). A
||| lambda whose arguments go anywhere else computes: it is a field written
||| by hand (`\x, y => rank x == rank y`), and the function it applies is no
||| method's. The arguments other than the lambda's are closed, which
||| shrinking them past its variables shows.
etaWrapper : Thin [] ks -> (bound : Nat) -> TT ks -> Maybe (Name, List Passed, List Nat)
etaWrapper th k (Bind _ _ (Lam {}) sc) = etaWrapper (Drop th) (S k) sc
etaWrapper th k body = case getFnArgs body of
  (Ref _ Func m, xs) => do
    passed <- traverse passedAs xs
    let indexed = zip (iterateN (length passed) S 0) passed
    -- Where M takes each own argument, the outermost (whose index is the
    -- highest) first: an eta wrapper passes each of its variables at one
    -- place.
    own <- traverse (\i => onePlace (mapMaybe (at i) indexed)) (reverse (iterateN k S 0))
    pure (m, passed, own)
  _ => Nothing
  where
    passedAs : TT ks -> Maybe Passed
    passedAs t = case contracted t of
      Local _ _ i _ => Just (Own i)
      _ => Fixed <$> shrink t th

    at : Nat -> (Nat, Passed) -> Maybe Nat
    at i (j, Own v) = if v == i then Just j else Nothing
    at _ (_, Fixed _) = Nothing

    onePlace : List Nat -> Maybe Nat
    onePlace [j] = Just j
    onePlace _ = Nothing

||| Where M takes each implementation parameter the field passes it as
||| itself: its marker, which stands for the parameter in the field.
leadingOf : List Passed -> List (Nat, Nat)
leadingOf passed = mapMaybe at (zip (iterateN (length passed) S 0) passed)
  where
    at : (Nat, Passed) -> Maybe (Nat, Nat)
    at (j, Fixed (Ref _ Bound n)) = case Template.markerOf n of
      Just (p, Z) => Just (p, j)
      _ => Nothing
    at _ = Nothing

||| A method's field, when it is an eta wrapper: its function `M`, the
||| function a dispatch through the field calls, `M`'s head over the static
||| arguments the field passes it (`staticsOver` over `M`'s type, each own
||| argument an erased placeholder), and where `M` takes the dispatch's
||| arguments and the implementation's parameters. Any other field, a
||| lambda written by hand, or one whose function the context does not
||| hold, is plain, and names no method function.
methodField : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              (owner : String) -> ClosedTerm -> Front Field
methodField owner field = do
  let Just (m, passed, own) = etaWrapper Refl 0 field
    | Nothing => pure (Plain (Leaf 1) Unrooted)
  Just md <- defined m
    | Nothing => pure (Plain (Leaf 1) Unrooted)
  let am = addressOf md.placement
  let xs = map value passed
  (kinds, _) <- staticsOver owner (length xs) md.type (map (\x => Just (x, AValue)) xs)
  ts <- traverse (\(k, x) => templateOf [] k x) (mapMaybe (\(k, x) => (, x) <$> k) (zip (toList kinds) xs))
  pure (Method am (Head (Just am) ts) own (leadingOf passed))
  where
    value : Passed -> ClosedTerm
    value (Own _) = Erased EmptyFC Placeholder
    value (Fixed t) = t

||| One field, by the binding of the binder that holds it, of type `ty`: a
||| static argument as its key holds it, with the root of the dictionary it
||| is, and a dictionary as a field read is given it: one the running
||| program chooses, a field computed at run time, is a member of the
||| choice of its type (`asGiven`); a method's field by the function it
||| applies.
fieldOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          (owner : String) -> Binding -> (ty : TT vs) -> ClosedTerm -> Front Field
fieldOf owner (Reads ADictionary) ty a = do
  t <- templateOf [] ADictionary a
  r <- dictionaryRoot a
  head <- choiceHeadOf ty
  pure (Plain (asGiven (Just head) (t, r)) r)
fieldOf owner (Reads k) ty a = do
  t <- templateOf [] k a
  r <- dictionaryRoot a
  pure (Plain t r)
fieldOf owner Wrapped ty a = methodField owner a

||| The fields of a constructor applied to its arguments, each argument
||| read by the binder of the constructor's type that binds it.
fieldsAlong : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              (owner : String) -> TT vs -> List ClosedTerm -> Front (List Field)
fieldsAlong owner (Bind _ _ (Pi _ rig _ a) sc) (x :: xs) = do
  field <- fieldOf owner !(bindingOf rig a) a x
  (field ::) <$> fieldsAlong owner sc xs
fieldsAlong _ _ _ = pure []

||| An implementation's fields: its body, with its parameters standing as
||| `marks` gives them, reduced to the constructor it builds, whose
||| arguments are the fields. A body whose reduction is stuck builds no
||| dictionary to read, and nor does a constructor the context does not
||| hold.
implementationFields : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                       Defined -> (args : Scope) -> TT args -> Front (Maybe Fields)
implementationFields d args body = do
  let owner = show (fullname d.def)
  stands <- marks owner d (length args)
  Built con cargs <- whnf (closeWritten EmptyFC stands body)
    | Stuck _ => pure Nothing
  Just cd <- defined con
    | Nothing => pure Nothing
  fs <- fieldsAlong owner !(normaliseClosed cd.type) cargs
  pure (Just fs)

||| The fields of a definition, over its parameters. An
||| implementation, a definition with one right-hand side whose type is an
||| implementation's, gives the fields of the constructor it builds. A
||| constructor, of data or of an interface, gives its own parameters: so a
||| field of a constraint tuple, of a record holding a dictionary, or of a
||| dictionary built by hand is one of the constructor's variables, as a
||| field of an implementation over its parameters is. Anything else (a
||| function that matches, a primitive, a type constructor) holds no
||| dictionary's fields.
export
fieldsOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Defined -> Front (Maybe Fields)
fieldsOf d = case (definition d.def, d.matched) of
    (DCon _ arity _, _) =>
      pure (Just (map (\j => Plain (Var j 0) (Parameter j 0)) (iterateN arity S 0)))
    (PMDef {}, Just m) => do
      True <- implementationType d.type
        | False => pure Nothing
      -- An implementation has one right-hand side.
      let Just rhs = leafOf m
        | Nothing => pure Nothing
      implementationFields d m.args rhs
    _ => pure Nothing
