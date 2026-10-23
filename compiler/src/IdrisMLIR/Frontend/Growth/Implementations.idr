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
import IdrisMLIR.Frontend.Translate.Contraction
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Proof.Reading
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Data.List
import Data.List.Quantifiers
import Data.SortedMap
import Data.Vect

%default total

||| One field of a dictionary, over the parameters of the definition that
||| gives it (`Var i 0` is its parameter i), each template with the
||| definition of each recursion it holds, as its reading met it. A
||| method's field that Idris wrote also says where its method function M
||| takes each argument: M's parameters do not start with the
||| implementation's, since a method's own implicit type variables come
||| first (`map_Functor_(EitherT e m)` is `{b} {a} {e} {m} {Functor m} func
||| x`), so the placement is read off the field, never assumed.
public export
data Field : Type where
  -- an eta-wrapped method field: its method function m, as it was read, its template, and where each argument
  -- lands in m. own: for each of the method's own arguments (the field's lambdas, in order), its parameter index
  -- in m; leading: for each implementation parameter p, its index in m. Its root is m, by construction.
  Method : (m : Address) -> (function : GlobalDef) -> TemplateRead -> (own : List Nat) -> (leading : List (Nat, Nat)) -> Field
  -- a dictionary held as a field (a superclass, a constructor's dictionary argument), with its dictionaryRoot, the
  -- head of the choice its type is, and that type over the constructor's arguments (`Var c 0` its argument c): a
  -- match takes it apart, and finds a member of that choice where the running program chose it, holding it at that
  -- type until then.
  Dictionary : TemplateRead -> Root -> ChoiceHead -> (type : TemplateRead) -> Field
  -- any other field: a type, a hand-built dictionary's lambda, with its dictionaryRoot
  Plain : TemplateRead -> Root -> Field

||| What a definition that gives a dictionary holds, over its own
||| parameters: the definition itself, as it was read, which a message
||| about what its fields write names; the constructor the dictionary is
||| built with, its own for a constructor and the one an implementation's
||| body reduces to, which is what a reduction of the dictionary to its
||| head reaches, by its address and as it was read, which a message about
||| a rebuilt dictionary's fields names; and its fields, in that
||| constructor's order.
public export
record Fields where
  constructor MkFields
  givenBy : GlobalDef
  builtBy : Address
  builtAs : GlobalDef
  inOrder : List Field

||| Field k of a dictionary: nothing when it has fewer fields.
export
fieldIn : Fields -> Nat -> Maybe Field
fieldIn f k = head' (drop k f.inOrder)

||| Field k of the dictionary the definition at an address gives: nothing
||| when it gives none, or fewer fields.
export
fieldAt : SortedMap Address Fields -> Address -> Nat -> Maybe Field
fieldAt fs j k = lookup j fs >>= \f => fieldIn f k

||| What every field gives the flow, method or not: its template and its
||| root. A method field's root is its function.
export
fieldRead : Field -> (TemplateRead, Root)
fieldRead (Method m _ t _ _) = (t, Rooted m)
fieldRead (Dictionary t r _ _) = (t, r)
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

||| What stands for each variable of an implementation's body, one per
||| parameter, the first first, as the translation binds it: its marker
||| where the parameter is static (`staticsOver`, every parameter given as
||| its marker), so that a field holds it as the parameter it is;
||| otherwise, by its binder's quantity, an erased placeholder at 0 and an
||| unknown runtime value elsewhere, as `closeWritten` writes a runtime
||| variable, and past the binders the type shows over markers, an unknown
||| runtime value, as the walk reads every binder a type does not show.
marks : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
        (owner : String) -> Defined -> (args : Scope) -> Front (ByVar args ClosedTerm)
marks owner d args = do
  (kinds, _) <- staticsOver owner (length args) d.type (map (\i => Just (markerAt i [], AValue)) (iterateN (length args) S 0))
  pure (standing 0 args kinds)
  where
    standing : Nat -> (vs : Scope) -> Vect (length vs) ParamReading -> ByVar vs ClosedTerm
    standing i [] [] = []
    standing i (_ :: vs) (OffBinder (Just _) _ :: ks) = markerAt i [] :: standing (S i) vs ks
    standing i (_ :: vs) (OffBinder Nothing rig :: ks) =
      Erased EmptyFC (case use rig of Erased => Placeholder; Used _ => Impossible) :: standing (S i) vs ks
    standing i (_ :: vs) (PastBinders :: ks) = Erased EmptyFC Impossible :: standing (S i) vs ks

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
    passedAs t = case (contracted t).etaForm of
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
      Just (p, []) => Just (p, j)
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
    | Nothing => pure (Plain (MkTemplateRead (Leaf 1) [] []) Unrooted)
  ctx <- frozenContext
  -- The method function, read once: its address, what the boundary read
  -- of it, and that as the head of what the field writes.
  Just (am ** (md, methodHead)) <- definedHead ctx m
    | Nothing => pure (Plain (MkTemplateRead (Leaf 1) [] []) Unrooted)
  let xs = map value passed
  (kinds, _) <- staticsOver owner (length xs) md.type (map (\x => Just (x, AValue)) xs)
  ts <- traverse (\(k, x) => templateOf [] k x) (mapMaybe (\(k, x) => (, x) <$> k) (zip (toList (map staticOf kinds)) xs))
  pure (Method am md.def (MkTemplateRead (Head (Just am) (templatesOf ts)) (allRead ts) (methodHead :: allHeads ts)) own (leadingOf passed))
  where
    value : Passed -> ClosedTerm
    value (Own _) = Erased EmptyFC Placeholder
    value (Fixed t) = t

||| The type of a constructor's binder, under the binders before it, over
||| the constructor's arguments: each earlier binder its argument's marker
||| (`Var c 0`), so that a field read of the dictionary the constructor
||| builds reads each (`Heads.overPart`).
typeOverArguments : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> TT vs -> Front TemplateRead
typeOverArguments ty =
  templateOf [] AType (closeOver EmptyFC (markersOf vs) ty)
  where
    -- Each variable its own marker, numbered from the outermost, 0.
    markersOf : (ws : Scope) -> ByVar ws ClosedTerm
    markersOf [] = []
    markersOf (_ :: ws) = markerAt (length ws) [] :: markersOf ws

||| One field, by the binding of the binder that holds it, of type `ty`: a
||| static argument as its key holds it, with the root of the dictionary it
||| is, and a dictionary as a field read is given it: one the running
||| program chooses, a field computed at run time, is a member of the
||| choice of its type (`asGiven`); a method's field by the function it
||| applies.
fieldOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
          (owner : String) -> Binding -> (ty : TT vs) -> ClosedTerm -> Front Field
fieldOf owner (Reads ADictionary) ty a = do
  t <- templateOf [] ADictionary a
  r <- dictionaryRoot a
  (head ** member) <- choiceDefOf ty
  Dictionary (givenRead (Just head) member t r) r head <$> typeOverArguments ty
fieldOf owner (Reads k) ty a = do
  t <- templateOf [] k a
  r <- dictionaryRoot a
  pure (Plain t r)
fieldOf owner Wrapped ty a = methodField owner a

||| The fields of a constructor applied to its arguments, each argument
||| read by the binder of the constructor's type that binds it.
fieldsAlong : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
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
  stands <- marks owner d args
  Built con cargs <- whnf (closeOver EmptyFC stands body)
    | Stuck _ => pure Nothing
  Just cd <- defined con
    | Nothing => pure Nothing
  fs <- fieldsAlong owner !(normaliseClosed cd.type) cargs
  pure (Just (MkFields d.def (addressOf cd.placement) cd.def fs))

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
    (DCon _ arity _, _) => do
      ty <- normaliseClosed d.type
      Just . MkFields d.def (addressOf d.placement) d.def <$> arguments arity 0 ty
    (PMDef {}, Just m) => do
      True <- implementationType d.type
        | False => pure Nothing
      -- An implementation has one right-hand side.
      let Just rhs = leafOf m
        | Nothing => pure Nothing
      implementationFields d m.args rhs
    _ => pure Nothing
  where
    -- A constructor's arguments, each its parameter: a dictionary, by the
    -- head of the choice its binder's type is, and anything else as it is,
    -- as is each past the binders a type shows even normalised.
    arguments : {vs : Scope} -> Nat -> (j : Nat) -> TT vs -> Front (List Field)
    arguments Z j _ = pure []
    arguments (S n) j (Bind _ _ (Pi _ rig _ a) sc) = do
      here <- case !(bindingOf rig a) of
        Reads ADictionary => Dictionary (MkTemplateRead (Var j 0) [] []) (Parameter j 0) <$> choiceHeadOf a <*> typeOverArguments a
        _ => pure (Plain (MkTemplateRead (Var j 0) [] []) (Parameter j 0))
      (here ::) <$> arguments n (S j) sc
    arguments (S n) j _ = pure (map (\q => Plain (MkTemplateRead (Var q 0) [] []) (Parameter q 0)) (iterateN (S n) S j))
