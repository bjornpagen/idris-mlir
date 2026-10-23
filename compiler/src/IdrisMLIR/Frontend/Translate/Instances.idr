-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Function instances: requesting one, and classifying a callee's
||| parameters as compile-time values (types and implementations, which key
||| the instance), erased ones, and runtime ones, whose argument's shape
||| keys the instance too when the type must reduce on the value.
module IdrisMLIR.Frontend.Translate.Instances

import Core.Context
import Core.Core
import Core.Name.Scoped
import Core.TT
import Libraries.Data.List.Thin

import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Frontend.Translate.TypeConstructors
import IdrisMLIR.Ids
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Registry
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.List
import Data.List1
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default total

||| The type a member at a use is applied as by (`AtUse`): `{0 t : Type} ->
||| (f : t) -> t`, the form's type, then the form, giving a value of the
||| form's type, which the use's arguments are applied to as that type
||| takes them. So the type keys the instance as a type does, the form as
||| an implementation does, and each argument as the form's type says. It
||| is made once, with what the translation reads (`Read.application`).
export
applicationType : Front ClosedTerm
applicationType = (\r => r.application.type) <$> reading

||| The type an instance applies, as its parameters (`appliedArity`) are
||| classified over: a definition's; a member at a use's, as
||| `applicationType` applies it to the use's arguments.
appliedType : {auto s : Ref TState TS} ->
              FC -> String -> Instantiates -> Front ClosedTerm
appliedType fc owner (OfDefinition n _) = (.type) <$> lookupDef fc owner n
appliedType fc owner (AtUse uses) = applicationType

||| What a call knows of an argument it gives: an implementation known at
||| compile time, whatever binds it (Idris passes an enclosing function's
||| constraints to its case and with blocks as explicit arguments); a
||| choice of one, which a dispatch passes on (`Choices`); or a value,
||| whose parameter's type decides what it is.
public export
data Offer = AnImplementation | AChoice | AValue

||| A compile-time value of an argument, computed on demand: normalised for a
||| type, as written for an implementation, with what the call knows of it
||| (`Offer`). `holed` is the argument as an implementation that closes over
||| runtime values (`Terms.holed`): its form with a marker for each value
||| (`holeMarker`), and the values' types, by marker. These are what the
||| instance is keyed by, so none names a level of the caller's
||| (`unmarked`). `scoped` is the argument normalised in the caller's scope,
||| its levels kept: what an index parameter is given.
public export
record ArgValue where
  constructor MkArgValue
  normalised : Front ClosedTerm
  written : Front ClosedTerm
  offer : Offer
  holed : Front (Maybe (ClosedTerm, List1 ClosedTerm))
  scoped : Front ClosedTerm

||| A compile-time argument as the instance's call classified it: the
||| value, and what the call knows of it.
export
known : ClosedTerm -> Offer -> ArgValue
known t offer = MkArgValue (pure t) (pure t) offer (pure Nothing) (pure t)

||| The arguments of a call by position: `Nothing` for a runtime argument of
||| an instance.
public export
ArgValues : Type
ArgValues = List (Maybe ArgValue)

||| What a parameter is supplied with where a callee's type is classified:
||| what a call knows of the argument it gives there, whose binder decides
||| how it is read (`FromCall`, nothing for an argument the call leaves
||| out); or a requested instance's static argument, read once where it was
||| requested (`Template.staticReading`), which keys the instance and is put
||| in at its reading's form as it is, so nothing of it is read again: a
||| type, a form, a runtime value's shape at the quantity it was read with,
||| or an implementation with the values it closes over, fixed as its kind
||| holds it (`FixedDictionary`), which carries its reading.
public export
data Supply = FromCall (Maybe ArgValue)
            | FromType StaticReading
            | FromForm StaticReading
            | FromShape Uses StaticReading
            | FromDictionary (Maybe Holes) FixedDictionary

||| What a supplied argument keys its instance by: a requested static
||| argument's reading, at the kind it was read as; nothing for an argument
||| a call offers.
public export
keyOf : Supply -> Maybe (KeyedAs, StaticReading)
keyOf (FromCall _) = Nothing
keyOf (FromType r) = Just (AsType, r)
keyOf (FromForm r) = Just (AsForm, r)
keyOf (FromShape q r) = Just (AsShape q, r)
keyOf (FromDictionary holes d) = Just (AsDictionary holes, d.asStatic)

||| What each argument supplied keys its instance by, position by position.
public export
keysOf : List Supply -> List (Maybe (KeyedAs, StaticReading))
keysOf [] = []
keysOf (a :: as) = keyOf a :: keysOf as

||| What the next parameter is supplied with, and what those after it are:
||| past the arguments supplied, nothing a call offers.
public export
nextSupplied : List Supply -> (Supply, List Supply)
nextSupplied (a :: as) = (a, as)
nextSupplied [] = (FromCall Nothing, [])

||| A request's parameter as its instance is supplied with it, by the kind
||| the call classified it as: each static argument read once, as an
||| instance's reading reads it (`Template.staticReading`), into the form
||| its link writes, which is the form a site's reading of the same kind
||| reads, so that one family is one key whatever stands for it; its height;
||| and the head that splits the request's node: the implementation at the
||| root of each static implementation the call gives, and the type
||| constructor at the head of each family it gives. A type argument has a
||| type constructor at its root only when it is applied to fewer arguments
||| than it takes, which only a family's value is, so the type arguments
||| that split the node are the families, those the graph splits a callee
||| by (`Sites`). An implementation that is a function (`() -> Eq a`) and a
||| family that is a lambda have no root and split nothing: cases the
||| problem has. A kind that keys nothing is offered as what the call knows
||| of it, and the instance's binder decides it. An implementation's kind
||| holds its reading already (`FixedDictionary`), read where it was fixed,
||| so nothing reads it again.
supplying : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> PKind -> Front Supply
supplying (TypeParam t) = FromType <$> staticReading AType t
supplying (DictParam d holes) = pure (FromDictionary holes d)
supplying (FormParam f) = FromForm <$> staticReading AForm f
supplying (ValueParam b (Just shape) _) = FromShape b.quantity <$> staticReading AShape shape
supplying (ValueParam _ Nothing _) = pure (FromCall Nothing)
-- A choice keys nothing: which implementation runs is the value's, and the
-- interface type it is a choice of follows from the static arguments
-- before it, which key the dispatch.
supplying (ChoiceParam _ t) = pure (FromCall (Just (known t.type AChoice)))
supplying ErasedParam = pure (FromCall Nothing)
supplying (IndexParam _) = pure (FromCall Nothing)

||| A request read: what it supplies each of the instance's parameters with
||| (`supplying`), each static argument read once, and the instance those
||| static arguments key, each written as its reading's form: its link,
||| which is its identity, its key and its symbol (`Keys.instanceKey`). The
||| key and the instance's classification read the one list, so an
||| instance is classified and translated at the forms that name it.
public export
record Requesting where
  constructor MkRequesting
  supplied : List Supply
  link : Link Form
  key : InstanceKey
  symbol : String

||| The instance of what is instantiated at the static arguments a call's
||| kinds give it (`Keys`), one kind per parameter it applies, each written
||| as its reading's form, with what it supplies each parameter with.
export
instanceFor : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              FC -> String -> (what : Instantiates) -> Vect (appliedArity what) PKind -> Front Requesting
instanceFor fc owner what kinds = do
  supplied <- traverse supplying (toList kinds)
  found <- keyed what (map (map snd . keyOf) supplied)
  pure (MkRequesting supplied found.link found.key found.symbol)
  where
    keyed : Instantiates -> List (Maybe StaticReading) -> Front (Instance StaticReading)
    keyed (OfDefinition n _) readings = snd <$> instanceKey fc owner n (.form) readings
    keyed (AtUse uses) readings = applicationKey fc uses (.form) readings

-- The heights and heads of the static arguments a request read, by
-- parameter index.
heightsOf : Nat -> List Supply -> List (Nat, StaticReading)
heightsOf i [] = []
heightsOf i (s :: rest) = case keyOf s of
  Just (_, r) => (i, r) :: heightsOf (S i) rest
  Nothing => heightsOf (S i) rest

||| Where the growth check bounds a new instance's static arguments, by
||| what its link heads: a definition's at its node, the definition split
||| by the heads of the implementations and families it is given, at each
||| parameter a static argument keys, with that argument's height; a
||| member at a use is no node of the graph, and the growth check bounds
||| its link alone.
boundedAt : Head -> List Supply -> List (Position, Nat)
boundedAt AnApplication _ = []
boundedAt (ADefinition address) supplied =
  let read = heightsOf 0 supplied
      node = MkNode address (mapMaybe (\(i, r) => (i,) <$> r.head) read) in
  map (\(i, r) => ((node, i), r.height)) read

||| The argument at the next parameter, and those after it: past the
||| arguments given, none.
nextStatic : List (Maybe a) -> (Maybe a, List (Maybe a))
nextStatic (v :: vs) = (v, vs)
nextStatic [] = (Nothing, [])

||| Does the rest of a callee's type reduce on a runtime parameter's value:
||| with what no shape says standing for the value, does the normalised
||| type mention it other than as an index of an inductive family, which is
||| compile-time information? Then the parameter is keyed by its
||| argument's shape. `(n : Nat) -> Vect n Int -> Int` only indexes a
||| vector by `n`, so one instance serves every argument.
needsShape : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             String -> (ClosedTerm -> ClosedTerm) -> Front Bool
needsShape owner rest = outsideIndices mentionsUnknown owner !(normaliseClosed (rest unknownPart))

||| What of a runtime argument's shape the rest of a callee's type needs to
||| reduce as it does at the call: nothing when it does not reduce on it
||| (`needsShape`); otherwise the shape cut at the least depth at which the
||| normalised type mentions what the cut leaves unknown only as an index,
||| or the whole shape when no depth is enough, the type stuck on what the
||| argument does not say.
neededShape : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              String -> (ClosedTerm -> ClosedTerm) -> ClosedTerm -> Front (Maybe ClosedTerm)
neededShape owner rest shape =
  if not !(needsShape owner rest) then pure Nothing else least (drop 1 [0 .. shapeDepth shape])
  where
    -- The depths a cut can have past the empty one, the least first.
    least : List Nat -> Front (Maybe ClosedTerm)
    least [] = pure (Just shape)
    least (d :: ds) = do
      ty <- normaliseClosed (rest (cutShape unknownPart d shape))
      if !(outsideIndices mentionsUnknown owner ty)
         then least ds
         else pure (Just (cutShape (Erased EmptyFC Impossible) d shape))

||| The shape of a runtime argument, as far as it is known at compile time:
||| the constructors written in it (`skeleton`), or, for an argument that
||| mentions no runtime value and without which the rest of the type is
||| stuck, the constructors of what it reduces to. Base's `clockTime` passes
||| its with block `isClockMandatory clockType`, a closed pure call with no
||| constructor written, on which the block's type reduces.
argumentShape : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                String -> (ClosedTerm -> ClosedTerm) -> ArgValue -> Front (Maybe ClosedTerm)
argumentShape owner rest arg = do
  written <- arg.written
  case skeleton written of
    HasSkeleton shape _ => pure (Just shape)
    NoSkeleton _ =>
      if !(runtimeDependent written) then pure Nothing else do
        Just _ <- neededShape owner rest (Erased EmptyFC Impossible)
          | Nothing => pure Nothing
        -- Essential: a normal form a data constructor does not head (a
        -- function no compile-time reduction unfolds) says nothing of the
        -- value's shape, which then keys nothing.
        normalised <- arg.normalised
        pure (case skeleton normalised of
                HasSkeleton shape _ => Just shape
                NoSkeleton _ => Nothing)

||| How the rest of a callee's type depends on a runtime parameter: it does
||| not mention it (`Runs`), or it does (`Reduces`), and then the argument's
||| shape keys the instance as far as the rest reduces on it (`needsShape`).
data Dependence = Runs | Reduces

||| How a parameter keys an instance, decided from its binder (its quantity,
||| its normalised type and the rest of the type) and what the call knows
||| of its argument (`Offer`): a type or a type family (a type parameter
||| whose kind is a function into a universe), whatever its quantity, a
||| form, an implementation or a polymorphic function
||| (`compileTimeBinder`), at the quantity its binder has, an erased value
||| that keys nothing, or a runtime value, at the quantity its binder has,
||| by how the rest of the type depends on it. The one place `classify` and
||| `staticsOver` decide it.
data Keying = Typed | Family | Formed | Implemented Uses | Unkeyed | Runtime Uses Dependence

keyingOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           RigCount -> ClosedTerm -> TT [x] -> Offer -> Front Keying
-- A binder whose type is a universe, after any binders, takes a type or a
-- type family, whatever its quantity: the program fixes its values, as it
-- fixes every type's, so it keys the instance as a type does. Idris binds
-- an interface's parameter at quantity many unless it says 0
-- (`interface Walk (t : Type -> Type)`), and that `t` is the same type
-- parameter as an erased one: never a function chosen at run time, and
-- never a value at run time. A tree that matches on one taken at quantity
-- many matches on a type every instance knows (`Cases.typeHead`).
keyingOf rig a' sc offer =
  if isTypeLike a' then pure (case a' of
                                Bind _ _ (Pi {}) _ => Family
                                _ => Typed) else case use rig of
    Erased =>
      -- An erased shape of the array language that the rest of the type
      -- puts in a form is its form: a tensor's rank is its type, so it
      -- keys the instance, by the rule a data type's parameter is formed
      -- by. Any other erased argument keys nothing.
      pure (if !(formNeeded a' (\x => subst x sc)) then Formed else Unkeyed)
    Used q => case offer of
      AnImplementation => pure (Implemented q)
      AChoice => pure (Implemented q)
      AValue =>
        if !(compileTimeBinder rig a')
           then pure (Implemented q)
           else pure (Runtime q (if isJust (shrink sc (Drop Refl)) then Runs else Reduces))

||| What `staticsOver` reads of a parameter: off a binder the type shows
||| over the arguments given, the kind that keys it statically, if any, and
||| the binder's quantity; or, past every binder it shows, nothing a
||| reading over markers can say. Over markers, which stand for every
||| value, a type whose binders an argument's value decides shows none
||| past that argument, and which kind such a parameter has only an
||| instance decides, where its type is admitted with the arguments put in
||| (`admitted`). The walk reads it as it reads every binder a type does
||| not show: a runtime value.
public export
data ParamReading = OffBinder (Maybe Static) RigCount | PastBinders

||| The kind that keys a parameter statically, as `staticsOver` read it.
public export
staticOf : ParamReading -> Maybe Static
staticOf (OffBinder kind _) = kind
staticOf PastBinders = Nothing

||| `classify`'s decisions over arguments given as closed terms (over the
||| growth check's markers, `Growth.Sites`), each with what the call knows
||| of it (`Offer`), or `Nothing` for a runtime value: each parameter's
||| reading (`ParamReading`), and the rest of the type, or the type at the
||| first binder it does not show. It decides by `keyingOf` and
||| `needsShape`, as `classify` does, but computes no value, reads no Core
||| type, registers nothing and refuses nothing, so it runs over markers.
export
staticsOver : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              (owner : String) -> (arity : Nat) -> (callee : ClosedTerm) ->
              List (Maybe (ClosedTerm, Offer)) -> Front (Vect arity ParamReading, ClosedTerm)
staticsOver owner Z ty _ = pure ([], ty)
staticsOver owner (S k) ty vals = do
  -- Essential: the growth walk runs before any instance is requested, so
  -- over markers a binder only an instance's arguments show is shown by
  -- none of them.
  Bind _ _ (Pi _ rig _ a) sc <- showingBinder ty
    | shown => pure (replicate (S k) PastBinders, shown)
  a' <- normaliseClosed a
  let (given, vals') = nextStatic vals
  kind <- case !(keyingOf rig a' sc (maybe AValue snd given)) of
    Typed => pure (Just AType)
    Family => pure (Just AFamily)
    Formed => pure (Just AForm)
    Implemented _ => pure (Just ADictionary)
    Unkeyed => pure Nothing
    Runtime _ Runs => pure Nothing
    Runtime _ Reduces => pure (if !(needsShape owner (\x => subst x sc)) then Just AShape else Nothing)
  (kinds, res) <- staticsOver owner k !(normaliseClosed (subst (maybe (Erased EmptyFC Placeholder) fst given) sc)) vals'
  pure (OffBinder kind rig :: kinds, res)

||| A callee's parameters, one kind per argument it is classified at
||| (`classifyCall`), and the type after them.
public export
Classified : Nat -> Type
Classified arity = (Vect arity PKind, ClosedTerm)

||| The kinds in order, as many as the vector holds.
public export
vectList : Vect n a -> List a
vectList [] = []
vectList (k :: ks) = k :: vectList ks

0 vectListLength : (v : Vect n a) -> length (vectList v) = n
vectListLength [] = Refl
vectListLength (_ :: ks) = cong S (vectListLength ks)

-- A callee's parameters classified over what each is supplied with
-- (`Classified`), each put in as what it is supplied with keys it
-- (`AllAtKey`): a static argument its request read, at its reading's
-- form, so that an instance holds for each parameter its key names the
-- form its key writes there.
record ClassifiedFrom (arity : Nat) (supplied : List Supply) where
  constructor MkClassifiedFrom
  kinds : Vect arity PKind
  rest : ClosedTerm
  0 atKey : AllAtKey (keysOf supplied) (vectList kinds)

-- One parameter classified over what it is supplied with: its kind, the
-- level of the next index parameter, and the type after what stands for
-- the parameter, the kind put in as what it is supplied with keys it.
record Stepped (supplied : Supply) where
  constructor MkStepped
  kind : PKind
  nextLevel : Nat
  restType : ClosedTerm
  0 atKey : AtKey (keyOf supplied) kind

-- A parameter put in as what it is supplied with keys it, and each after
-- it as what it is supplied with keys it: every parameter from it on put
-- in as the arguments supplied key them, past their end at no key.
0 followed : (as : List Supply) -> AtKey (keyOf (fst (nextSupplied as))) k ->
             AllAtKey (keysOf (snd (nextSupplied as))) ks -> AllAtKey (keysOf as) (k :: ks)
followed [] here rest = here :: rest
followed (_ :: _) here rest = here :: rest

||| A callee's type as an instance admits it, `arity` parameters ahead: the
||| binder of its next parameter, which the type shows with every argument
||| before it put in, or, past them all, the type after them. Each step of
||| the walk that classifies an instance's parameters takes the binder its
||| type admits, and admits the rest once it has put in what stands for
||| the parameter (`admitted`).
public export
data Admitted : (arity : Nat) -> Type where
  AllAdmitted : (rest : ClosedTerm) -> Admitted Z
  Admits : (bfc : FC) -> (rig : RigCount) -> (binderType : ClosedTerm) -> (sc : TT [x]) -> Admitted (S k)

||| The request's name in a refusal: the definition an instance is of, or
||| the application of a form a member at a use is.
export
requestName : Instantiates -> String
requestName (OfDefinition n _) = show n
requestName (AtUse uses) = "a form applied to " ++ show uses ++ " arguments"

||| A callee's type admitted `arity` parameters ahead, with the arguments
||| before them put in, where its instance is first requested. Idris
||| checked the definition's clauses at its arity, over the arguments'
||| values; the type here is over what the request fixes of them, and a
||| type whose binders come from a value the request leaves to run time
||| (`(b : Bool) -> if b then .. else ..` at a runtime `b`) is stuck
||| before the binder: a function whose arity no compile-time reduction
||| fixes, which the program has. It is refused here, the one place an
||| instance's binder is read, naming the request.
admitted : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> (request : String) -> (arity : Nat) -> ClosedTerm -> Front (Admitted arity)
admitted fc owner request Z ty = pure (AllAdmitted ty)
admitted fc owner request (S k) ty = do
  Bind bfc _ (Pi _ rig _ a) sc <- showingBinder ty
    | _ => reject fc owner ValueType (request ++ " at a type whose binders depend on a value the call does not fix: " ++
                                      !(showTT ty))
  pure (Admits bfc rig a sc)

||| Walks a callee's type, as the instance admits it, over what each
||| parameter is supplied with: which are type parameters or
||| implementations, which are erased, which are index parameters, which
||| are runtime (and their types). A static argument a request read is put
||| in at its reading's form as the request classified it, and read no
||| further; only what a call offers is read here. Each index parameter
||| stands in the rest of the type as its own level (`marker`), the next
||| one `level`, so the types read in the callee's scope.
classifyAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> (request : String) -> (level : Nat) -> (arity : Nat) -> Admitted arity ->
             (supplied : List Supply) -> Front (ClassifiedFrom arity supplied)
classifyAt fc owner request level Z (AllAdmitted ty) _ = pure (MkClassifiedFrom [] ty [])
classifyAt fc owner request level (S k) (Admits bfc rig a sc) supplied = do
  step <- parameter (fst (nextSupplied supplied))
  admittedRest <- admitted fc owner request k step.restType
  more <- classifyAt fc owner request step.nextLevel k admittedRest (snd (nextSupplied supplied))
  pure (MkClassifiedFrom (step.kind :: more.kinds) more.rest (followed supplied step.atKey more.atKey))
  where
    -- A runtime parameter's Core type, read off its binder's normalised
    -- type, which may not depend on another argument.
    runtimeType : ClosedTerm -> Front Ty
    runtimeType a' = do
      when !(erasedOutsideIndices owner a') $ do
        reject fc owner ValueType ("a parameter type that depends on another argument: " ++ !(showTT a'))
      coreType fc owner ValueType a'

    -- A static argument put in at its value, as a request read it: the
    -- rest of the type has the value for the parameter, normalised, and
    -- the next index parameter the same level.
    keyedAt : {0 given : Supply} -> (kind : PKind) -> (0 _ : AtKey (keyOf given) kind) -> ClosedTerm ->
              Front (Stepped given)
    keyedAt kind atKey value = (\restType => MkStepped kind level restType atKey) <$> normaliseClosed (subst value sc)

    -- What a call offers is read by the parameter's binder, which decides
    -- how it keys the instance; nothing a request read keys it.
    offered : (given : Maybe ArgValue) -> Front (Stepped (FromCall given))
    offered given = do
      a' <- normaliseClosed a
      case !(keyingOf rig a' sc (maybe AValue (.offer) given)) of
        Typed => typed
        -- A family keys its instance as any type does; only the growth
        -- check reads what heads its value.
        Family => typed
        Formed => do
          let Just v = given
            | Nothing => leftOut "shape"
          form <- formOf <$> spineOf fc owner !(v.normalised)
          unkeyedAt (FormParam form) level !(normaliseClosed (subst form sc))
        -- An erased binder an index of a runtime parameter's type or of
        -- the result reads, and nothing a value is made of, is an index
        -- parameter, its level standing for it in the rest of the type;
        -- any other is absent.
        Unkeyed => do
          rest <- normaliseClosed (subst (marker level) sc)
          case !(occurrenceOf owner level rest) of
            IndexOnly => do
              sort <- sortOfType a'
              unkeyedAt (IndexParam sort) (S level) rest
            _ => unkeyedAt ErasedParam level (subst (Erased bfc Placeholder) sc)
        -- An implementation the call leaves out is given when the call's
        -- value, a closure, is applied: a run-time choice.
        Implemented q => do
          let Just v = given
            | Nothing => chosen q a'
          case v.offer of
            AChoice => chosen q a'
            _ => do
              written <- v.written
              implemented q a' v written
        Runtime q dependence => do
          t <- runtimeType a'
          -- The rest of the type may have to reduce on the parameter's value
          -- (`treeDelete : (n : Nat) -> ... -> Either (Tree n k v o) (delType n k v o)`
          -- in Data.SortedMap, where `delType` reduces on the constructors of
          -- `n`). Then the argument's shape, the constructors it is built
          -- with as written, everything else erased (`S _`), stands for the
          -- parameter in the type and keys the instance, so that the type
          -- reduces at each one as it does at each call; only as much of it
          -- as the type needs (`neededShape`), so that a recursion that
          -- builds its argument deeper below what the type looks at stays in
          -- one instance. The shape is read off the argument as written; it
          -- is computed only for a closed argument, one that mentions no
          -- runtime value, that the type is stuck without (`argumentShape`),
          -- by normalising it as the type itself is normalised. An argument
          -- that mentions a runtime value is any computation, which the
          -- compiler must not run. An argument with no constructor at its
          -- head, written or reduced to, has no shape, and a parameter the
          -- type does not mention, or mentions only as an index
          -- (`Vect n Int`), keys nothing, so a function on naturals has one
          -- instance.
          shape <- case (dependence, given) of
            (Reduces, Just arg) => do
              Just found <- argumentShape owner (\x => subst x sc) arg
                | Nothing => pure Nothing
              neededShape owner (\x => subst x sc) found
            _ => pure Nothing
          let value = fromMaybe (Erased bfc Placeholder) shape
          unkeyedAt (ValueParam (MkBinder q t) shape a') level !(normaliseClosed (subst value sc))
      where
        -- A kind the binder decides at what a call offers, which no static
        -- argument a request read keys. No step here reads what the call
        -- offered to key the instance, so each holds at whatever it offered
        -- (`call`), and the matches on `given` above meet each at the value
        -- they refine it to.
        unkeyedAt : {0 call : Maybe ArgValue} -> PKind -> (next : Nat) -> ClosedTerm -> Front (Stepped (FromCall call))
        unkeyedAt kind next restType = pure (MkStepped kind next restType NoKey)

        -- A type or a form the call leaves out: the call's value is a
        -- function that takes a type, held at run time. Where the program
        -- fixes such a function (an argument, a `let`, an applied lambda),
        -- its form is taken and never translated, and where it is held at
        -- run time it is a member of its type's choice (`Terms.member`), so
        -- no call of it is classified there; what reaches here is one no
        -- compile-time reduction fixes, which would be a closure whose type
        -- the next binder chooses where it is applied.
        leftOut : {0 call : Maybe ArgValue} -> String -> Front (Stepped (FromCall call))
        leftOut what =
          reject fc owner ValueType ("a function given no " ++ what ++ ", held at run time, at a parameter of type " ++
                                     !(showTT a))

        -- A type, normalised, keys the instance.
        typed : {0 call : Maybe ArgValue} -> Front (Stepped (FromCall call))
        typed = do
          let Just v = given
            | Nothing => leftOut "type"
          val <- v.normalised
          unkeyedAt (TypeParam val) level !(normaliseClosed (subst val sc))

        -- An implementation known now keys the instance, with the value it
        -- was fixed at, which its kind holds.
        static : {0 call : Maybe ArgValue} -> FixedDictionary -> Maybe Holes -> Front (Stepped (FromCall call))
        static d holes = unkeyedAt (DictParam d holes) level !(normaliseClosed (subst d.form sc))

        -- A choice of an implementation or a polymorphic function of the
        -- parameter's type (`choiceType`), a value at run time, which the
        -- call dispatches on. Which member it is no type after it can
        -- read. Essential: a function on values that the running program
        -- chooses, whose result is an implementation, is a value of a
        -- function type that takes no type: a closure, a runtime value
        -- like any other, whose uses apply it, each result a choice.
        chosen : {0 call : Maybe ArgValue} -> Uses -> ClosedTerm -> Front (Stepped (FromCall call))
        chosen q a' = do
          Just ct <- choiceType a'
            | Nothing => do
                b <- coreBinder fc owner ValueType q a'
                unkeyedAt (ValueParam b Nothing a') level !(normaliseClosed (subst (Erased bfc Placeholder) sc))
          choice <- choiceFamily fc owner ct
          unkeyedAt (ChoiceParam (MkBinder q (DataT choice.family [])) ct) level
                    !(normaliseClosed (subst (Erased bfc Placeholder) sc))

        -- An implementation given as written, at a parameter of an
        -- interface's type, or a polymorphic function, at a parameter of
        -- its type.
        implemented : {0 call : Maybe ArgValue} -> Uses -> ClosedTerm -> ArgValue -> ClosedTerm ->
                      Front (Stepped (FromCall call))
        implemented q a' v written = do
          -- An implementation can be a function of a runtime value
          -- (`{y : a} -> Show (p y)`, applied to the first component of a
          -- dependent pair), which Idris resolved at every value: constant
          -- in it, or using it only where it is erased (`Show (Tag y)`).
          -- What the function returns is then a compile-time value, seen
          -- once the projections and applications that lead to it are
          -- reduced.
          val <- if !(runtimeDependent written) then implementationOf written else pure written
          -- One that a definition gives without matching on a runtime value
          -- it closes over (`{vars : _} -> Show (Term vars)`) is chosen now
          -- all the same, and only the value is passed at runtime. What
          -- written holds only in an erased argument can still be needed
          -- at runtime once the implementation is expanded to its
          -- constructor, whose own blocks take that argument as an
          -- ordinary parameter (a case block of `Show (Term vars)` takes
          -- `vars` so), so dependence is judged on the expanded form too;
          -- an argument expansion keeps only in types (a grammar's
          -- consumption index) is no dependence. A form no compile-time
          -- reduction may expand, through a definition Idris does not prove
          -- ends, is taken as dependent: what it would show is not known.
          dependent <- if !(runtimeDependent val) then pure True
                         else if hasRuntimePart written
                                then maybe (pure True) runtimeDependent !(expandClosed written)
                                else pure False
          -- An implementation that needs no runtime value keys the
          -- instance when the program fixes it now, decided off what its
          -- reading's form reduces to, which the reading keeps
          -- (`Template.dictionaryReading`, `fixedAt`): one a definition
          -- Idris does not prove ends computes, or one stuck on a value no
          -- compile-time reduction passes, is computed at run time, a
          -- choice like any other.
          if not dependent
            then do
              d <- dictionaryReading val
              let FixedNow fixed = fixedAt a' d.reduct
                | ChosenAtRunTime _ => chosen q a'
              static (MkFixedDictionary val d.asStatic d.ofDictionary fixed) Nothing
            else do
              -- One that still needs a runtime value to say which it is is
              -- chosen at run time, among those the program fixes, unless
              -- its form says which it is whatever the values (`fixedAt`):
              -- then only the values are passed.
              Just (shape, tys) <- v.holed
                | Nothing => chosen q a'
              key <- implementationOf shape
              d <- dictionaryReading key
              let FixedNow fixed = fixedAt a' d.reduct
                | ChosenAtRunTime _ => chosen q a'
              held <- coreType fc owner ValueType !(normaliseClosed !(packedType tys))
              static (MkFixedDictionary key d.asStatic d.ofDictionary fixed) (Just (MkHoles tys (MkBinder Many held)))

    -- The parameter the binder binds, what stands for it in the rest of the
    -- type, and the rest of the type after it. A static argument a request
    -- read is put in at its reading's form, the form that keys the
    -- instance, as the request classified it: a type, a form, an
    -- implementation with the values it closes over, a runtime value's
    -- shape at the quantity it was read with, whose binder only the
    -- instance's own type gives. Nothing of the argument is read again: an
    -- implementation keeps the value it was fixed at.
    parameter : (given : Supply) -> Front (Stepped given)
    parameter (FromType r) = keyedAt (TypeParam r.form) TypeAtKey r.form
    parameter (FromDictionary holes d) = keyedAt (DictParam (atReading d) holes) DictionaryAtKey d.asStatic.form
    parameter (FromForm r) = keyedAt (FormParam r.form) FormAtKey r.form
    parameter (FromShape q r) = do
      a' <- normaliseClosed a
      t <- runtimeType a'
      keyedAt (ValueParam (MkBinder q t) (Just r.form) a') ShapeAtKey r.form
    parameter (FromCall given) = offered given

||| What a call gives each index parameter of its callee, in order: the
||| argument at its position, normalised in the caller's scope with the
||| caller's own levels kept; nothing where the call gives none.
indexForms : {auto c : Ref Ctxt Defs} -> List PKind -> ArgValues -> Front (List (Maybe ClosedTerm))
indexForms [] _ = pure []
indexForms (IndexParam _ :: ks) vals = do
  let (given, vals') = nextStatic vals
  here <- traverse (.scoped) given
  (here ::) <$> indexForms ks vals'
indexForms (_ :: ks) vals = indexForms ks (snd (nextStatic vals))

||| The index terms a call passes its callee, one per index parameter, in
||| the caller's scope: a number, a successor chain, a level of the
||| caller's own, or outside the language where no link exists (an
||| argument no index term reads, or none given).
export
callIndices : {auto c : Ref Ctxt Defs} -> List PKind -> ArgValues -> Front (List ITerm)
callIndices kinds vals = traverse (maybe (pure IOpaque) indexTerm) !(indexForms kinds vals)

||| The terms a construction site gives its constructor's erased binders,
||| in the site's scope: each the term of the argument at the binder's
||| position (a number, a level of the site's own plus a count), outside the
||| language where the site gives no argument there or no term reads it.
export
binderTerms : List ConBinder -> ArgValues -> Front (List ITerm)
binderTerms bs vals = traverse term bs
  where
    term : ConBinder -> Front ITerm
    term b = case join (getAt b.argument vals) of
      Just v => indexTerm !(v.scoped)
      Nothing => pure IOpaque

||| A callee's kinds and result as a call reads them, in the call's scope
||| (`inCaller`): every kind binds at run time where the callee's does, so
||| the call's runtime arguments are as many as the callee's parameters, by
||| type.
public export
record AtCall (signed : List PKind) where
  constructor MkAtCall
  kinds : List PKind
  0 sameCount : Runtimes kinds = Runtimes signed
  result : ClosedTerm

||| A runtime parameter's binder and Idris type read in the scope of a
||| call, each of the callee's levels given what the call passes it
||| (`forms`).
valueInCaller : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                FC -> String -> List (Maybe ClosedTerm) -> Binder -> ClosedTerm -> Front (Binder, ClosedTerm)
valueInCaller fc owner forms b idrisType = do
  here <- normaliseClosed (atLevels forms idrisType)
  t <- coreType fc owner ValueType here
  pure ({ type := t } b, here)

||| A callee's classified parameters and result read in the scope of a
||| call: each of its levels given the argument the call passes it, erased
||| where it passes none, in its runtime parameters' types and its result,
||| so that no level of the callee's reads as one of the caller's. Only a
||| runtime value's types change, so every kind binds at run time where it
||| did.
inCaller : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> ArgValues -> (kinds : List PKind) -> ClosedTerm -> Front (AtCall kinds)
inCaller fc owner vals kinds res = case telescopeOf kinds of
  [] => pure (MkAtCall kinds Refl res)
  _ => do
    forms <- indexForms kinds vals
    (kinds' ** same) <- retyped forms kinds
    res' <- normaliseClosed (atLevels forms res)
    pure (MkAtCall kinds' same res')
  where
    retyped : List (Maybe ClosedTerm) -> (ks : List PKind) -> Front (ks' : List PKind ** Runtimes ks' = Runtimes ks)
    retyped forms [] = pure ([] ** Refl)
    retyped forms (ValueParam b shape idrisType :: ks) = do
      (b', here) <- valueInCaller fc owner forms b idrisType
      (ks' ** same) <- retyped forms ks
      pure (ValueParam b' shape here :: ks' ** cong S same)
    retyped forms (k :: ks) = do
      (ks' ** same) <- retyped forms ks
      pure (k :: ks' ** cong (counted (boundAtRuntime k)) same)

||| A callee's parameters classified at a call (`classifyAt`), its type
||| admitted with the call's arguments put in, named `request` where it is
||| refused (`admitted`), read in the caller's scope as `inCaller` reads
||| them, one kind per parameter of the arity it is classified at: what
||| every use of a primitive's, a lowered definition's or a library
||| function's signature reads, which no instance is requested at.
export
classifyCall : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               FC -> String -> (request : String) -> (arity : Nat) -> ClosedTerm -> ArgValues ->
               Front (Classified arity)
classifyCall fc owner request arity ty vals = do
  classified <- classifyAt fc owner request 0 arity !(admitted fc owner request arity ty) (map FromCall vals)
  case telescopeOf (vectList classified.kinds) of
    [] => pure (classified.kinds, classified.rest)
    _ => do
      forms <- indexForms (vectList classified.kinds) vals
      kinds <- traverse (inScope forms) classified.kinds
      res' <- normaliseClosed (atLevels forms classified.rest)
      pure (kinds, res')
  where
    inScope : List (Maybe ClosedTerm) -> PKind -> Front PKind
    inScope forms (ValueParam b shape idrisType) = do
      (b', here) <- valueInCaller fc owner forms b idrisType
      pure (ValueParam b' shape here)
    inScope forms k = pure k

||| A callee's parameters classified at a call's arguments, in the
||| callee's scope, its type admitted where the call first instantiates it
||| with the call's arguments put in, named `request` where it is refused
||| (`admitted`): what keys the instance the call requests, whose
||| signature the call then reads (`atCall`).
export
classifyKeys : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               FC -> String -> (request : String) -> (arity : Nat) -> ClosedTerm -> ArgValues -> Front (Vect arity PKind)
classifyKeys fc owner request arity ty vals = do
  admittedType <- admitted fc owner request arity ty
  classified <- classifyAt fc owner request 0 arity admittedType (map FromCall vals)
  pure classified.kinds

||| A requested instance's signature as a call reads it, in the call's
||| scope (`inCaller`).
export
atCall : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         FC -> String -> ArgValues -> (sig : InstanceSig) -> Front (AtCall sig.kinds)
atCall fc owner vals sig = inCaller fc owner vals sig.kinds sig.result

||| An instance's signature (`InstanceSig`), read where it is first
||| requested, or where a dispatch is made (`Choices.dispatchOn`): what it
||| applies classified over what its request supplies (`Requesting`), each
||| static argument at the form its key writes, put in as it is, so that
||| the instance holds for each parameter its key names the form that names
||| it (`SignedAt`), and is translated at those forms; its index parameters
||| its own levels, which its body's scope binds first; its result
||| normalised and its Core type read; and what a call holds of it, its
||| identity, which its link is, and its symbol.
export
instanceSig : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              FC -> String -> (what : Instantiates) -> (requesting : Requesting) ->
              Front (sig : InstanceSig ** SignedAt what (keysOf requesting.supplied) sig)
instanceSig fc owner what requesting = do
  ty <- appliedType fc owner what
  let request = requestName what
  classified <- classifyAt fc owner request 0 (appliedArity what) !(admitted fc owner request (appliedArity what) ty)
                           requesting.supplied
  resTy' <- normaliseClosed classified.rest
  result <- coreType fc owner ValueType resTy'
  pure (MkInstanceSig (vectList classified.kinds) resTy'
                      (MkCallee (InstanceOf requesting.link) requesting.symbol (runtimeBinders (vectList classified.kinds)) result)
        ** MkSignedAt (vectListLength classified.kinds) classified.atKey)

||| A new instance recorded at its signature, read once (`instanceSig`):
||| in the instance table, in the order first requested, and as a request
||| the worklist takes, with what its request keyed each parameter by and
||| that each is put in at it, the site that requested it, the definition
||| whose translation did, and the positions at which the worklist checks
||| its static arguments against the growth check's bounds (`boundedAt`).
export
recordRequest : {auto s : Ref TState TS} ->
                FC -> (owner : String) -> (what : Instantiates) -> (requesting : Requesting) -> (sig : InstanceSig) ->
                SignedAt what (keysOf requesting.supplied) sig -> Front ()
recordRequest fc owner what requesting sig signed = do
  let inst = InstanceOf requesting.link
  updateState (derive { instances $= insert inst sig })
  updateState (derive { fnOrder $= (:< inst) })
  updateState { derived->requested $= (:< MkRequest what sig signed.classifiesAll (keysOf requesting.supplied) signed.atKey
                                                   requesting.key fc (shown owner) requesting.link
                                                   (boundedAt requesting.link.head requesting.supplied)) }

||| Requests a function instance, for parameters classified as the call
||| gives them, and returns its signature (`InstanceSig`), which holds its
||| identity. A new instance's signature is read here, once: what it
||| applies classified over what the request supplies (`instanceFor`), each
||| static argument at its reading's form, the form its key writes, its
||| result's Core type read, so that a result type the frontend refuses is
||| refused at the request that first meets it, which the refusal names;
||| its own step and every call of it read that one value. A new instance
||| is recorded with it (`recordRequest`), so that a method's projection is
||| checked at the implementation that runs, and a definition over a family
||| at the type constructor it is. The link stays its identity.
export
request : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> (owner : String) -> (what : Instantiates) -> Vect (appliedArity what) PKind -> Front InstanceSig
request fc owner what kinds = do
  requesting <- instanceFor fc owner what kinds
  let inst = InstanceOf requesting.link
  Nothing <- pure (requestedBefore inst !(getState))
    | Just sig => pure sig
  (sig ** signed) <- instanceSig fc owner what requesting
  recordRequest fc owner what requesting sig signed
  pure sig
