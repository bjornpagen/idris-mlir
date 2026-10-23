-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The host's reduction (`Idris.Host.Reduces`) and the frontend's eta
||| contraction (`Proof.Reading.EtaContracts`) inverted where a reading of
||| an instance's term meets a node whose head no step rewrites.
|||
||| A site's reading and an instance's reading of one static argument are
||| related node by node, the instance's term being the site's with a value
||| put in for each marker, normalised and contracted. At a node headed by
||| a bound name (a marker, a hole, a runtime part), a data constructor, a
||| type constructor that takes arguments, or a function the context
||| defines as nothing, no step of the evaluator applies at the root
||| (`noRootStep`), so every reduction of it, however its steps are
||| chained, keeps the head and reduces each argument
||| (`inertReduces`); an argument of a normal form is normal
||| (`argumentIrreducible`); and contraction, which rewrites only a
||| lambda, keeps the head and contracts each argument (`refContracts`).
||| So the instance's form at such a node is the same head over the forms
||| of its arguments, which the reading lemma's induction descends into.
||| Alone, or applied to one argument, such a head reduces to itself over
||| what the argument reduces to (`inertAlone`, `inertOne`); and an erased
||| part no dot holds, which no step rewrites either, reduces only to
||| itself (`erasedReduces`).
|||
||| A site's term and an instance's are related by putting the instance's
||| values in for the site's markers (`Idris.Host.putIn`), which rebuilds an
||| application from its parts put in (`putInApp`) and keeps every head no
||| value is put in for (`putInHead`): so at a node of the site's term an
||| inert head heads, whatever the instance's values, the instance's term
||| reduces under the same head, its arguments put in (`inertPutIn`), and
||| each argument of a normal form it reaches is normal
||| (`argumentsIrreducible`).
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Inversion

import Core.Context
import Core.TT
import Idris.Host
import Libraries.Data.List.SizeOf

import IdrisMLIR.Proof.Reading

import Data.List
import Data.List.Elem
import Data.List.Quantifiers

%default total

------------------------------------------------------------------------------
-- Spines headed by a reference
------------------------------------------------------------------------------

||| A term headed by a reference has one such head and one list of
||| arguments: a spine reaches its head through applications alone.
export
0 refSpines : Spine t (Ref fc nt n) args -> Spine t (Ref fc' nt' n') args' ->
              (Ref fc nt n = Ref fc' nt' n', args = args')
refSpines Head Head = (Refl, Refl)
refSpines Head (Applied _) impossible
refSpines (Applied _) Head impossible
refSpines (Applied s) (Applied s') = case refSpines s s' of
  (Refl, Refl) => (Refl, Refl)

-- A spine headed by a reference never passes through any node but an
-- application: each of these is a head of its own.

0 notBind : Spine (Bind fc x b sc) (Ref rfc nt n) args -> Void
notBind Head impossible
notBind (Applied _) impossible

0 notAs : Spine (As fc side a p) (Ref rfc nt n) args -> Void
notAs Head impossible
notAs (Applied _) impossible

0 notDelayed : Spine (TDelayed fc r t) (Ref rfc nt n) args -> Void
notDelayed Head impossible
notDelayed (Applied _) impossible

0 notDelay : Spine (TDelay fc r ty a) (Ref rfc nt n) args -> Void
notDelay Head impossible
notDelay (Applied _) impossible

0 notForce : Spine (TForce fc r t) (Ref rfc nt n) args -> Void
notForce Head impossible
notForce (Applied _) impossible

export
0 notErased : Spine (Erased fc why) (Ref rfc nt n) args -> Void
notErased Head impossible
notErased (Applied _) impossible

0 notConstant : Spine (PrimVal fc c) (Ref rfc nt n) args -> Void
notConstant Head impossible
notConstant (Applied _) impossible

0 notUniverse : Spine (TType fc u) (Ref rfc nt n) args -> Void
notUniverse Head impossible
notUniverse (Applied _) impossible

0 notLocal : Spine (Local fc l idx p) (Ref rfc nt n) args -> Void
notLocal Head impossible
notLocal (Applied _) impossible

0 notMeta : Spine (Meta fc m i scope) (Ref rfc nt n) args -> Void
notMeta Head impossible
notMeta (Applied _) impossible

||| A term headed by a reference is headed by no unknown.
export
0 refNotMeta : Spine t (Ref fc nt n) args -> Spine t (Meta mfc m i scope) more -> Void
refNotMeta Head Head impossible
refNotMeta Head (Applied _) impossible
refNotMeta (Applied _) Head impossible
refNotMeta (Applied s) (Applied s') = refNotMeta s s'

-- A head that drops what it is applied to is no reference.
0 droppedHead : DropsArguments f -> Spine f (Ref rfc nt n) args -> Void
droppedHead DropsAtPlaceholder s = notErased s
droppedHead DropsAtImpossible s = notErased s
droppedHead DropsAtConstant s = notConstant s
droppedHead DropsAtUniverse s = notUniverse s
droppedHead DropsAtDelay s = notDelay s

------------------------------------------------------------------------------
-- Inert heads
------------------------------------------------------------------------------

||| A head no step of the evaluator rewrites in a context, whatever it is
||| applied to: a bound name, which no step reads (a step reads a function,
||| a constructor or a family through its kind and its entry); a data
||| constructor; a type constructor that takes arguments; or a function the
||| context defines as nothing, which no step can unfold, since a step that
||| unfolds a name or computes a primitive reads the definition the context
||| gives it. A type constructor of none is the universe or a primitive type
||| by its name, which a step rewrites, and a function the context defines
||| is what steps unfold: neither is one.
public export
data Inert : Frozen -> NameType -> Name -> Type where
  InertBound : Inert ctx Bound n
  InertData : Inert ctx (DataCon tag arity) n
  InertFamily : Inert ctx (TyCon (S arity)) n
  InertUndefined : (0 _ : (d : GlobalDef) -> Not (Defines ctx n d)) -> Inert ctx Func n

export
Uninhabited (Inert ctx (TyCon Z) n) where
  uninhabited InertBound impossible
  uninhabited InertData impossible
  uninhabited InertFamily impossible
  uninhabited (InertUndefined _) impossible

-- An inert function defines nothing.
0 inertUndefined : Inert ctx Func n -> Defines ctx n d -> Void
inertUndefined (InertUndefined none) defines = none _ defines

-- A step that unfolds a function, by the definition the context gives it,
-- is no step at an inert head.
0 funcHead : Inert ctx nt n -> Spine t (Ref fc nt n) args -> Spine t (Ref fc' Func n') args' -> Defines ctx n' d -> Void
funcHead inert s s' defines = case refSpines s s' of
  (Refl, _) => inertUndefined inert defines

||| No step of the evaluator applies at the root of a term an inert head
||| heads: each step's left side is a lambda or a `let` applied or alone,
||| an as pattern, a force, a binder, a lazy type, a dot or a head that
||| drops its arguments applied, a function or an unknown applied, or a
||| type constructor of no arguments alone.
export
0 noRootStep : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
               Inert ctx nt n -> Spine t (Ref fc nt n) args -> Contracts ev ctx t u -> Void
noRootStep inert Head Beta impossible
noRootStep inert (Applied s) Beta = notBind s
noRootStep inert s (Zeta _) = notBind s
noRootStep inert s (Unfold s' defines _ _ _ _ _ _) = funcHead inert s s' defines
noRootStep inert s (Solve s' _ _ _ _ _ _ _ _) = refNotMeta s s'
noRootStep inert s (Primitive s' defines _ _ _ _) = funcHead inert s s' defines
noRootStep inert s ForceDelay = notForce s
noRootStep inert s (RemoveAs _) = notAs s
noRootStep inert Head (FloatAs _) impossible
noRootStep inert (Applied s) (FloatAs _) = notAs s
noRootStep inert Head (FloatBinder _) impossible
noRootStep inert (Applied s) (FloatBinder _) = notBind s
noRootStep inert Head FloatDelayed impossible
noRootStep inert (Applied s) FloatDelayed = notDelayed s
noRootStep inert Head FloatDot impossible
noRootStep inert (Applied s) FloatDot = notErased s
noRootStep inert Head (DropApplied _) impossible
noRootStep inert (Applied s) (DropApplied dropped) = droppedHead dropped s
noRootStep inert Head (TypeName _) = absurd inert
noRootStep inert (Applied _) (TypeName _) impossible
noRootStep inert Head (ConstantTypeName _) = absurd inert
noRootStep inert (Applied _) (ConstantTypeName _) impossible

------------------------------------------------------------------------------
-- Reduction under an inert head
------------------------------------------------------------------------------

||| Two lists of terms, each reducing to the other's term in turn, chained.
export
0 allThen : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
            AllReduce ev ctx as bs -> AllReduce ev ctx bs cs -> AllReduce ev ctx as cs
allThen NoneLeft NoneLeft = NoneLeft
allThen NoneLeft (Each _ _) impossible
allThen (Each _ _) NoneLeft impossible
allThen (Each r rs) (Each r' rs') = Each (Then r r') (allThen rs rs')

||| One more argument, reduced, after arguments reduced.
export
0 allSnoc : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
            AllReduce ev ctx as bs -> Reduces ev ctx a b -> AllReduce ev ctx (as ++ [a]) (bs ++ [b])
allSnoc NoneLeft r = Each r NoneLeft
allSnoc (Each r' rs) r = Each r' (allSnoc rs r)

||| What a reduction makes of a term an inert head heads: the same head,
||| at some location, applied to what each argument reduces to.
public export
data InertReduct : {0 vs : Scope} -> Evaluation -> Frozen -> NameType -> Name -> List (Term vs) -> Term vs -> Type where
  ReducedUnder : {0 ev : Evaluation} -> {0 ctx : Frozen} -> {0 args, args' : List (Term vs)} ->
                 Spine u (Ref fc' nt n) args' -> AllReduce ev ctx args args' -> InertReduct ev ctx nt n args u

||| A term an inert head heads reduces only under its arguments: no step
||| applies at its root (`noRootStep`), an application's congruence keeps
||| the head of its function and reduces its argument, a reference's keeps
||| the reference, and a chain of reductions chains what each makes of the
||| arguments.
export
0 inertReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Inert ctx nt n ->
                 Spine t (Ref fc nt n) args -> Reduces ev ctx t u -> InertReduct ev ctx nt n args u
inertReduces inert s (Then r r') = case inertReduces inert s r of
  ReducedUnder s' rs => case inertReduces inert s' r' of
    ReducedUnder s'' rs' => ReducedUnder s'' (allThen rs rs')
inertReduces inert s (Contract c) = void (noRootStep inert s c)
inertReduces inert Head ARef = ReducedUnder Head NoneLeft
inertReduces inert (Applied s) ARef impossible
inertReduces inert (Applied s) (AnApp rf ra) = case inertReduces inert s rf of
  ReducedUnder s' rs => ReducedUnder (Applied s') (allSnoc rs ra)
inertReduces inert Head (AnApp _ _) impossible
inertReduces inert s ALocal = void (notLocal s)
inertReduces inert s (AMeta _) = void (notMeta s)
inertReduces inert s (ABind _ _) = void (notBind s)
inertReduces inert s (AnAs _ _) = void (notAs s)
inertReduces inert s (ADelayed _) = void (notDelayed s)
inertReduces inert s (ADelay _ _) = void (notDelay s)
inertReduces inert s (AForce _) = void (notForce s)
inertReduces inert s APrimVal = void (notConstant s)
inertReduces inert s (AnErased _) = void (notErased s)
inertReduces inert s AType = void (notUniverse s)

------------------------------------------------------------------------------
-- Spines of no argument and of one
------------------------------------------------------------------------------

-- A list one element longer at its end is never empty.
0 snocNotNil : (xs : List a) -> xs ++ [x] = [] -> Void
snocNotNil [] Refl impossible
snocNotNil (_ :: _) Refl impossible

0 nilNotCons : the (List a) [] = x :: xs -> Void
nilNotCons Refl impossible

-- A list one element longer at its end is one element only where it was
-- empty, and that element is the one added.
0 snocOne : (xs : List a) -> xs ++ [x] = [y] -> (xs = [], x = y)
snocOne [] Refl = (Refl, Refl)
snocOne (_ :: zs) eq = void (snocNotNil zs (snd (consInjective eq)))

||| A spine of no argument is its head.
export
0 headOnly : Spine t h args -> args = [] -> t = h
headOnly Head _ = Refl
headOnly (Applied {args = xs} _) eq = void (snocNotNil xs eq)

||| A spine of one argument is its head applied to it.
export
0 oneApplied : Spine t h args -> args = [x] -> (fc : FC ** t = App fc h x)
oneApplied Head eq = void (nilNotCons eq)
oneApplied (Applied {fc} {a} {args = xs} s) eq = case snocOne xs eq of
  (Refl, Refl) => (fc ** cong (\g => App fc g a) (headOnly s Refl))

||| What an inert head alone reduces to: itself, at some location.
export
0 inertAlone : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Inert ctx nt n ->
               Reduces ev ctx (Ref fc nt n) v -> (fc' : FC ** v = Ref fc' nt n)
inertAlone inert r = case inertReduces inert Head r of
  ReducedUnder s NoneLeft => (_ ** headOnly s Refl)

||| What an inert head applied to one argument reduces to: the head, at
||| some location, applied to what the argument reduces to.
export
0 inertOne : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Inert ctx nt n ->
             Reduces ev ctx (App fc (Ref rfc nt n) a) v ->
             (fc' : FC ** rfc' : FC ** a' : Term vs ** (v = App fc' (Ref rfc' nt n) a', Reduces ev ctx a a'))
inertOne inert r = case inertReduces inert (Applied Head) r of
  ReducedUnder s (Each ra NoneLeft) => case oneApplied s Refl of
    (fc' ** same) => (fc' ** _ ** _ ** (same, ra))

------------------------------------------------------------------------------
-- Heads that reduce only to themselves
------------------------------------------------------------------------------

||| An erased part no dot holds: a placeholder, or what is impossible.
public export
data Undotted : WhyErased (Term vs) -> Type where
  IsPlaceholder : Undotted Placeholder
  IsImpossible : Undotted Impossible

-- A term an erased part heads is headed by no unknown.
0 erasedNotMeta : Spine (Erased fc why) (Meta mfc m i scope) more -> Void
erasedNotMeta Head impossible
erasedNotMeta (Applied _) impossible

-- No step of the evaluator applies at the root of an erased part: each
-- step's left side is a node of another form, or a function, an unknown
-- or a type constructor at the head of its spine.
0 erasedNoStep : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Contracts ev ctx (Erased fc why) u -> Void
erasedNoStep (Unfold s _ _ _ _ _ _ _) = notErased s
erasedNoStep (Solve s _ _ _ _ _ _ _ _) = erasedNotMeta s
erasedNoStep (Primitive s _ _ _ _ _) = notErased s

||| What an erased part no dot holds reduces to: itself, at some location.
export
0 erasedReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Undotted why ->
                  Reduces ev ctx (Erased fc why) v -> (fc' : FC ** v = Erased fc' why)
erasedReduces u (Then r r') = case erasedReduces u r of
  (_ ** Refl) => erasedReduces u r'
erasedReduces u (Contract c) = void (erasedNoStep c)
erasedReduces IsPlaceholder (AnErased APlaceholder) = (_ ** Refl)
erasedReduces IsImpossible (AnErased AnImpossible) = (_ ** Refl)

------------------------------------------------------------------------------
-- A normal form's arguments
------------------------------------------------------------------------------

0 splitElem : (xs : List a) -> Elem x (xs ++ ys) -> Either (Elem x xs) (Elem x ys)
splitElem [] e = Right e
splitElem (_ :: xs) Here = Left Here
splitElem (_ :: xs) (There e) = case splitElem xs e of
  Left l => Left (There l)
  Right r => Right r

-- A step in an argument of a spine is a step of the term, under the
-- applications that apply the head to the arguments.
0 liftedRedex : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
                Spine u h args -> Elem a args -> Redex ev ctx a -> Redex ev ctx u
liftedRedex Head el r = absurd el
liftedRedex (Applied {args = xs} s) el r = case splitElem xs el of
  Left inFunction => InFunction (liftedRedex s inFunction r)
  Right Here => InArgument r
  Right (There e) => absurd e

||| An argument of a normal form is normal.
export
0 argumentIrreducible : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
                        Spine u h args -> Elem a args -> Irreducible ev ctx u -> Irreducible ev ctx a
argumentIrreducible s el normal redex = normal (liftedRedex s el redex)

------------------------------------------------------------------------------
-- Contraction under a reference
------------------------------------------------------------------------------

||| Terms each contracted to the other's term in turn.
public export
data AllContract : List (Term vs) -> List (Term vs) -> Type where
  NoneContracted : AllContract [] []
  EachContracted : EtaContracts t u -> AllContract ts us -> AllContract (t :: ts) (u :: us)

-- Every list of terms is itself contracted.
0 noneChanged : (ts : List (Term vs)) -> AllContract ts ts
noneChanged [] = NoneContracted
noneChanged (t :: ts) = EachContracted EtaSame (noneChanged ts)

-- One more argument, contracted, after arguments contracted.
0 contractedSnoc : AllContract xs ys -> EtaContracts a b -> AllContract (xs ++ [a]) (ys ++ [b])
contractedSnoc NoneContracted c = EachContracted c NoneContracted
contractedSnoc (EachContracted c' cs) c = EachContracted c' (contractedSnoc cs c)

||| What contraction makes of a term a reference heads: the same head, at
||| the same location, applied to each argument contracted.
public export
data RefContracted : {0 vs : Scope} -> FC -> NameType -> Name -> List (Term vs) -> Term vs -> Type where
  ContractedUnder : {0 args, args' : List (Term vs)} ->
                    Spine u (Ref fc nt n) args' -> AllContract args args' -> RefContracted fc nt n args u

||| Contraction keeps the head of a term a reference heads and contracts
||| each argument: a redex is a lambda, which no such term is, and every
||| other node it rewrites is a head of its own.
export
0 refContracts : Spine v (Ref fc nt n) args -> EtaContracts v u -> RefContracted fc nt n args u
refContracts {args} s EtaSame = ContractedUnder s (noneChanged args)
refContracts (Applied s) (EtaApp cf ca) = case refContracts s cf of
  ContractedUnder s' cs => ContractedUnder (Applied s') (contractedSnoc cs ca)
refContracts Head (EtaApp _ _) impossible
refContracts s (EtaRedex _ _) = void (notBind s)
refContracts s (EtaBind _ _) = void (notBind s)
refContracts s (EtaAs _ _) = void (notAs s)
refContracts s (EtaDelayed _) = void (notDelayed s)
refContracts s (EtaDelay _ _) = void (notDelay s)
refContracts s (EtaForce _) = void (notForce s)
refContracts s (EtaDotted _) = void (notErased s)

------------------------------------------------------------------------------
-- Values put in under a head no value is put in for
------------------------------------------------------------------------------

||| A head putting values in keeps: a data constructor, a type constructor,
||| a function, or a bound name the bounds do not replace (a runtime part,
||| a hole, an argument of a family's value).
public export
data KeptHead : Bounds ns -> NameType -> Name -> Type where
  KeptData : KeptHead bs (DataCon tag arity) n
  KeptFamily : KeptHead bs (TyCon arity) n
  KeptFunc : KeptHead bs Func n
  KeptBound : (0 _ : replaces bs n = False) -> KeptHead bs Bound n

||| Putting values in rebuilds an application from its parts put in:
||| `substTerm` and `mkLocals` are public, and each rebuilds one so.
export
0 putInApp : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
             (f, a : Term (outer ++ vars)) ->
             putIn o sz bs vs (App fc f a) = App fc (putIn o sz bs vs f) (putIn o sz bs vs a)
putInApp o sz None vs f a = Refl
putInApp o sz (Add new old rest) vs f a = Refl

||| Putting values in keeps a head no value is put in for.
export
0 putInHead : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
              KeptHead bs nt n -> putIn o sz bs vs (Ref fc nt n) = Ref fc nt n
putInHead o sz None vs KeptData = Refl
putInHead o sz (Add new old rest) vs KeptData = Refl
putInHead o sz None vs KeptFamily = Refl
putInHead o sz (Add new old rest) vs KeptFamily = Refl
putInHead o sz None vs KeptFunc = Refl
putInHead o sz (Add new old rest) vs KeptFunc = Refl
putInHead o sz bs vs (KeptBound none) = putInUnreplaced o sz bs vs none

-- One more element at the end, mapped.
0 mapSnoc : (g : a -> b) -> (xs : List a) -> (x : a) -> map g (xs ++ [x]) = map g xs ++ [g x]
mapSnoc g [] x = Refl
mapSnoc g (y :: ys) x = cong (g y ::) (mapSnoc g ys x)

-- A spine read with its head written another way.
0 headAs : Spine t h args -> h = h' -> Spine t h' args
headAs s Refl = s

||| A spine with values put in is the head put in over its arguments put in.
export
0 putInSpine : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
               Spine t h args -> Spine (putIn o sz bs vs t) (putIn o sz bs vs h) (map (putIn o sz bs vs) args)
putInSpine o sz bs vs Head = Head
putInSpine o sz bs vs (Applied {fc} {f} {a} {args} s) =
  rewrite putInApp {fc} o sz bs vs f a in
  rewrite mapSnoc (putIn o sz bs vs) args a in
  Applied (putInSpine o sz bs vs s)

||| What an instance's reduction makes of a node of the site's term that a
||| head no value is put in for and no step rewrites heads: the same head,
||| at some location, over what each argument, put in, reduces to.
export
0 inertPutIn : {0 ev : Evaluation} -> {0 ctx : Frozen} ->
               (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
               Inert ctx nt n -> KeptHead bs nt n -> Spine u (Ref fc nt n) args ->
               Reduces ev ctx (putIn o sz bs vs u) w -> InertReduct ev ctx nt n (map (putIn o sz bs vs) args) w
inertPutIn o sz bs vs inert kept s r = inertReduces inert (headAs (putInSpine o sz bs vs s) (putInHead o sz bs vs kept)) r

-- A property of every member of a list, from one of each member.
0 everyElem : {0 p : a -> Type} -> (xs : List a) -> ((x : a) -> Elem x xs -> p x) -> All p xs
everyElem [] f = []
everyElem (x :: xs) f = f x Here :: everyElem xs (\y, el => f y (There el))

||| Every argument of a normal form is normal (`argumentIrreducible`).
export
0 argumentsIrreducible : {0 ev : Evaluation} -> {0 ctx : Frozen} -> Spine u h args -> Irreducible ev ctx u ->
                         All (Irreducible ev ctx) args
argumentsIrreducible {args} s normal = everyElem args (\a, el => argumentIrreducible s el normal)
