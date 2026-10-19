-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Templates: what a definition writes at a static argument, read as the
||| key of the request it makes holds it.
|||
||| A static argument (a type, a family, a dictionary, a form, a shape) is a
||| closed term over markers for the writer's own static parameters. Its
||| template is a tree of heads (constructors, implementations, binders)
||| whose leaves are the markers (`Var`), the closed parts (`Leaf`,
||| `Token`), a field of a dictionary that is no constructor yet (`Field`,
||| `Held`), and what a type computes from a marker: a definition's case
||| tree unfolded behind what it matched on (`Choice`), a recursion nothing
||| bounds (`Opaque`), or a family the writer was given, applied, which
||| every instance beta-reduces (`Applied`; `Computing` once the graph
||| finds a value that computes lands there). A family's value is read as
||| its meaning, what beta computes from its arguments (`Formal`), beside
||| the form its key holds, so that what lands at a family bounds what
||| every application of it writes. The growth check's arcs read one height
||| and one weight off it, and the bound check on every request reads the
||| request's argument by the function a site's argument is read by
||| (`rooted`), so the two cannot drift.
|||
||| There is one reading per kind, the key's (`Instances.classify`): a type,
||| a family or a form normalised, a dictionary as written or as the
||| implementation it stands for, a shape as its skeleton. The kind is an
||| argument, so no reading guesses what a term is.
|||
||| A marker is a bound name of the walk's own, a nested name around a user
||| name no Idris identifier spells. Idris's quotation rebinds a bound
||| machine name to the binder whose number it carries, so a marker is never
||| one: it passes through every normaliser, under every binder, as itself.
|||
||| Unfolding puts a definition on the walk's stack (`Walk.enter`), the
||| measure every reading here recurses on, so the readings end however the
||| definitions refer to one another. A definition met again on its own
||| unfolding is a recursion: one that takes its Nat-like argument's
||| predecessor, under at most one head a level, is bounded by its proof
||| (`structural`), and any other is `Opaque`. A weight of `Stuck` means
||| "met again", or a sum of two heights (an applied family whose argument
||| holds a marker), or a family whose value computes from its arguments
||| (`Beta`), never "did not reduce".
module IdrisMLIR.Frontend.Growth.Template

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.TT
import Libraries.Data.List.SizeOf
import Libraries.Data.List.Thin

import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List1
import Data.SortedMap
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The language
------------------------------------------------------------------------------

public export
data Template
  = Var Nat Nat                         -- the writer's parameter i, bound by its pattern at depth d (0: unmatched)
  | Head (Maybe Address) (List Template) -- a head: a type or data constructor, an implementation, an interface's
                                        -- constructor (Just), a binder or primitive type former (Nothing)
  | Leaf Nat                            -- a closed part of that height: a Nat literal's run (n: n + 1), a primitive type,
                                        -- a bound variable, an Erased placeholder (1)
  | Token Nat                           -- any other literal, or a hole marker: height 1, carrying its key token's weight
                                        -- for Bounds.heaviest
  | Choice Template (List Template)     -- one of its leaves at every instance, behind what it matched on: a stuck
                                        -- non-recursive definition, unfolded; a definition given fewer arguments than
                                        -- its parameters, as written and walked over the arguments it lacks; one stuck
                                        -- on an argument of a family's value, as written and as what beta computes; a
                                        -- projection of a record no constructor yet, as written and as its field; a
                                        -- structural recursion, its other leaves and its argument raised by them
  | Opaque Address (List Template)      -- a recursive definition, stuck on what its arguments hold
  | Applied Nat Nat (List Template)     -- the writer's family Var i d applied, which every instance beta-reduces
  | Computing Nat Nat (List Template)   -- the writer's family Var i d applied where its value, or an argument, computes
                                        -- from what it is given: what beta makes there nothing bounds
  | Formal Nat Nat                      -- argument j of a family's value, taking a arguments of its own: what beta
                                        -- substitutes, a leaf of height 1 until it does; nothing matches one, so it
                                        -- has no depth
  | Field Nat Template                  -- field k (a method or a superclass) of a dictionary not yet a constructor
  | Held Address Nat                    -- the dictionary data constructor C holds at field p, matched out of a value
                                        -- (SortedDMap's Ord)

||| What a dictionary or a family is at its root: the definition there (an
||| implementation or an interface constructor a dictionary is, the type
||| constructor a family's value applies), the writer's own parameter there
||| (a marker `Var i d`), or neither (a lambda's result, `\_ =>
||| __Impl_Eq_Int`; a family that is a lambda).
public export
data Root = Rooted Address
          | Parameter Nat Nat
          | Unrooted

------------------------------------------------------------------------------
-- The markers
------------------------------------------------------------------------------

-- The walk's own markers are probes (`Walk`): bound names that no binder
-- binds and no context holds, each passing through every normaliser as
-- itself (a bound reference stays applied, Eval.idr). None is a hole
-- marker, since a request's key holds those for runtime values.

||| The marker `Var i d` reads back from: the writer's parameter i, matched
||| d constructors deep.
export
markerAt : (i, d : Nat) -> ClosedTerm
markerAt i d = probeTerm (ProbeVar i d)

||| The parameter and depth of `markerAt`'s name, and of no other.
export
markerOf : Name -> Maybe (Nat, Nat)
markerOf n = case probeOf n of
  Just (ProbeVar i d) => Just (i, d)
  _ => Nothing

||| The marker `Formal j a` reads back from: argument j of a family's
||| value, which takes a arguments of its own. A lambda's variable is one,
||| and so is each argument a definition given fewer than its parameters
||| lacks, so that what the value computes from its arguments is read where
||| beta puts them. Nothing matches it deeper: a match on it leaves the
||| value as written (`walk`).
formalAt : (j, a : Nat) -> Term vs
formalAt j a = probeTerm (ProbeFormal j a)

||| What a site binds a match on a field of the dictionary marker `Var i d`
||| to, by its path: the dictionary's field first, then a field of that
||| field. A dictionary with no path is the marker itself, one name per
||| value.
export
fieldAt : (i, d : Nat) -> (path : List Nat) -> ClosedTerm
fieldAt i d [] = markerAt i d
fieldAt i d (k :: ks) = probeTerm (ProbeFieldPath i d (k ::: ks))

||| What a site binds the dictionary a data constructor holds at field p
||| to, when a match takes it out of a value: the constructor's address, its
||| own eight bytes, and the field.
export
heldAt : Address -> Nat -> ClosedTerm
heldAt a p = probeTerm (ProbeHeld a p)

||| The marker `Var i d` a term is, when it is one, unapplied.
bareMarker : ClosedTerm -> Maybe (Nat, Nat)
bareMarker (Ref _ Bound n) = Template.markerOf n
bareMarker _ = Nothing

------------------------------------------------------------------------------
-- Scopes
------------------------------------------------------------------------------

||| What each variable of a scope stands for, the first first: a
||| definition's parameters and the arguments its matches bind.
data Values : Type -> Scope -> Type where
  Nil : Values a []
  (::) : a -> Values a vs -> Values a (v :: vs)

||| What a variable stands for, which its scope says is there.
valueAt : Values a vs -> (idx : Nat) -> (0 _ : IsVar n idx vs) -> a
valueAt (x :: _) Z _ = x
valueAt (_ :: xs) (S i) v = valueAt xs i (dropLater v)
valueAt [] _ First impossible
valueAt [] _ (Later _) impossible

||| An alternative's arguments, which come first, before the scope it
||| extends.
extend : Values a xs -> Values a ys -> Values a (xs ++ ys)
extend [] ys = ys
extend (x :: xs) ys = x :: extend xs ys

||| The parameters of a definition, the first argument first, and the
||| arguments past them; nothing when it is applied to fewer.
bindParams : (vs : Scope) -> List a -> Maybe (Values a vs, List a)
bindParams [] as = Just ([], as)
bindParams (_ :: vs) (a :: as) = map (\(env, rest) => (a :: env, rest)) (bindParams vs as)
bindParams (_ :: _) [] = Nothing

||| A constructor's arguments bound to what it was applied to; nothing when
||| they are not as many.
bindEach : (ns : List Name) -> List a -> Maybe (Values a ns)
bindEach [] [] = Just []
bindEach (_ :: ns) (x :: xs) = (x ::) <$> bindEach ns xs
bindEach _ _ = Nothing

||| Every argument of an alternative bound to one value.
bindAll : (ns : List Name) -> a -> Values a ns
bindAll [] _ = []
bindAll (_ :: ns) x = x :: bindAll ns x

sizeOfValues : Values a vs -> SizeOf vs
sizeOfValues [] = zero
sizeOfValues (_ :: xs) = suc (sizeOfValues xs)

substEnv : (a -> ClosedTerm) -> Values a vs -> SubstEnv vs []
substEnv f [] = []
substEnv f (x :: xs) = f x :: substEnv f xs

||| A term with each of its variables replaced by the term `f` makes of
||| what stands for it.
closeBy : (a -> ClosedTerm) -> Values a vs -> TT vs -> ClosedTerm
closeBy {vs} f env tm = substs (sizeOfValues env) (substEnv f env) (rewrite appendNilRightNeutral vs in tm)

||| A term with what each of its variables stands for.
close : Values ClosedTerm vs -> TT vs -> ClosedTerm
close = closeBy id

placeholders : (vs : Scope) -> Values ClosedTerm vs
placeholders [] = []
placeholders (_ :: vs) = Erased EmptyFC Placeholder :: placeholders vs

||| A term under binders, each binder's variable a placeholder, which no
||| reading looks into: what a part under a binder is when it is
||| substituted into a definition.
closedOver : {vs : Scope} -> TT vs -> ClosedTerm
closedOver tm = close (placeholders vs) tm

applyTo : ClosedTerm -> List ClosedTerm -> ClosedTerm
applyTo = foldl (App EmptyFC)

------------------------------------------------------------------------------
-- What every reading and every match sees
------------------------------------------------------------------------------

||| A reference as every reading and every match takes it. In order: a hole
||| marker (a runtime value an implementation closes over, which the key
||| writes as its number), an argument of a family's value, one of the
||| walk's markers, a bound name that is none of these (a runtime part), a
||| data or type constructor, a definition with a place, and a definition
||| with none, which stands for what is not known of a runtime value
||| (`unknownPart`, as `Closed.normalHead` reads it).
data Reference = HoleMarker Nat
               | FormalMarker Nat Nat
               | WalkMarker Template
               | RuntimePart
               | DataConstructor (Maybe Address)
               | TypeConstructor (Maybe Address)
               | Defined Address

referenceOf : Context -> NameType -> Name -> Reference
referenceOf ctx nt n = case probeOf n of
  Just (ProbeHole i) => HoleMarker i
  Just (ProbeFormal j a) => FormalMarker j a
  Just (ProbeVar i d) => WalkMarker (Var i d)
  Just (ProbeFieldPath i d path) => WalkMarker (foldl (\t, k => Field k t) (Var i d) path)
  Just (ProbeHeld a p) => WalkMarker (Held a p)
  -- Any other name, a probe of another family's included, is what its
  -- reference says it is.
  _ => case nt of
    Bound => RuntimePart
    DataCon _ _ => DataConstructor (definitionAddress ctx n)
    TyCon _ => TypeConstructor (definitionAddress ctx n)
    Func => maybe RuntimePart Defined (definitionAddress ctx n)

||| The role a constructor has in a Nat-like type, if any.
roleOf : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe NatRole)
roleOf n = do
  defs <- get Ctxt
  pure (natRole =<< !(lookupCtxtExact n (gamma defs)))

||| A closed run, as `Keys.successorRun` reads one: n >= 1 applications of
||| one successor, the same definition at each step, ending in a zero. Its
||| count n; the run's template is `Leaf (S n)`, the model's height of
||| `S^n Z`, so that a template's explicit successors over a marker are
||| never shorter than the run they close to. A run that ends in anything
||| else is read node by node.
export
closedRun : {auto c : Ref Ctxt Defs} -> TT vs -> Core (Maybe Nat)
closedRun t@(App _ (Ref _ (DataCon _ _) _) _) = do
  w <- writerOf (heads t)
  pure ((\(k, _, _) => k) <$> successorRun w t)
  where
    -- The constructors down a run's spine: the only names its reading asks
    -- the roles of.
    heads : TT vs -> List (TT vs)
    heads (App _ f@(Ref _ (DataCon _ _) _) a) = f :: heads a
    heads z@(Ref _ (DataCon _ _) _) = [z]
    heads _ = []
closedRun _ = pure Nothing

||| A constant, read off the tokens `Keys.writeConstant` writes for it, so
||| that its template and its key are one spelling: an integer's one token
||| carries its magnitude's weight, a string and a double are a node per
||| character after their shape's, anything else is one node. A literal's
||| height is its node's, never its magnitude.
constant : Constant -> Template
constant k = case writeConstant k of
  [Number _ m] => Token (S m)
  (Node (Shaped Text) _ _ :: chars) => Head Nothing (map (const (Leaf 1)) chars)
  (Node (Shaped Floating) _ _ :: chars) => Head Nothing (map (const (Leaf 1)) chars)
  _ => Leaf 1

||| What a match meets, parsed once: a data or type constructor applied, a
||| literal, a delay, one of the walk's markers, an argument of a family's
||| value, a runtime value (a part every reading takes as one node, or a
||| hole marker), or anything else: an application stuck in turn, a
||| projection of what is no constructor, an applied marker.
data Scrutinee = Constructed Name (List ClosedTerm)
               | Literal Constant
               | Suspended ClosedTerm ClosedTerm
               | Matched Nat Nat
               | OnFormal Nat Nat
               | AtRuntime
               | StuckInTurn

undotted : TT vs -> TT vs
undotted (Erased _ (Dotted u)) = undotted u
undotted t = t

scrutineeOf : Context -> ClosedTerm -> Scrutinee
scrutineeOf ctx s = case getFnArgs (undotted s) of
  (Ref _ nt n, args) => case (referenceOf ctx nt n, args) of
    (DataConstructor _, _) => Constructed n args
    (TypeConstructor _, _) => Constructed n args
    (WalkMarker (Var i d), []) => Matched i d
    (FormalMarker j a, []) => OnFormal j a
    (RuntimePart, _) => AtRuntime
    (HoleMarker _, _) => AtRuntime
    _ => StuckInTurn
  (PrimVal _ k, []) => Literal k
  (TDelay _ _ ty a, []) => Suspended ty a
  (Erased _ Placeholder, _) => AtRuntime
  (Erased _ Impossible, _) => AtRuntime
  (Meta {}, _) => AtRuntime
  _ => StuckInTurn

------------------------------------------------------------------------------
-- Structural recursions
------------------------------------------------------------------------------

||| An alternative of a recursion on a Nat-like argument, one level deep:
||| the successor's leaf, which may recur, or another's (the zero's, the
||| default's), which must be closed.
data Arm = Step ClosedTerm | Base ClosedTerm

||| The alternatives of a match one level deep on a Nat-like argument, each
||| leaf with the parameters substituted and every argument the match binds
||| the marker one level deeper; nothing for any other match.
natArms : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Values ClosedTerm vs -> List (CaseAlt vs) ->
          Core (Maybe (List Arm))
natArms m env [] = pure (Just [])
natArms m env (ConCase con _ cargs (STerm _ rhs) :: alts) = do
  let body = close (extend (bindAll cargs m) env) rhs
  Just role <- roleOf con
    | Nothing => pure Nothing
  let arm = case role of
              Succ => Step body
              Zero => Base body
  map (arm ::) <$> natArms m env alts
natArms m env (DefaultCase (STerm _ rhs) :: alts) = map (Base (close env rhs) ::) <$> natArms m env alts
natArms m env (_ :: _) = pure Nothing

||| The other leaves of a structural recursion, and the closed children of
||| its successor's leaf, when it is one. The successor's leaf is a
||| recursive call, or a data or type constructor applied to children each
||| of which is a recursive call or closed; every recursive call takes the
||| predecessor marker at the matched position and every other argument as
||| it came; every other leaf is closed; and at least one call recurs.
||| Closed means: no marker of the walk's, no mention of the definition.
recursion : Context -> (self : Address) -> (predecessor : (Nat, Nat)) -> (args : List ClosedTerm) ->
            (idx : Nat) -> List Arm -> Maybe (List ClosedTerm, List ClosedTerm)
recursion ctx self predecessor args idx arms = case go arms of
  Just (bases, kids, S _) => Just (bases, kids)
  _ => Nothing
  where
    refersOut : {0 vs : Scope} -> TT vs -> Bool
    refersOut (Ref _ nt n) = case referenceOf ctx nt n of
      WalkMarker _ => True
      FormalMarker _ _ => True
      Defined a => a == self
      HoleMarker _ => False
      RuntimePart => False
      DataConstructor _ => False
      TypeConstructor _ => False
    refersOut _ = False

    isClosed : ClosedTerm -> Bool
    isClosed t = not (mentions refersOut t)

    -- The predecessor at the matched position, the arguments as they came
    -- at every other.
    stepped : Nat -> List ClosedTerm -> List ClosedTerm -> Bool
    stepped _ [] [] = True
    stepped Z (x :: xs) (_ :: ys) = bareMarker x == Just predecessor && xs == ys
    stepped (S k) (x :: xs) (y :: ys) = x == y && stepped k xs ys
    stepped _ _ _ = False

    isCall : ClosedTerm -> Bool
    isCall t = case getFnArgs t of
      (Ref _ Func f, as) => definitionAddress ctx f == Just self && stepped idx as args
      _ => False

    -- The closed children and the number of recursive calls among them.
    children : List ClosedTerm -> Maybe (List ClosedTerm, Nat)
    children [] = Just ([], 0)
    children (k :: ks) = do
      (closed, calls) <- children ks
      if isCall k then Just (closed, S calls)
        else if isClosed k then Just (k :: closed, calls)
        else Nothing

    step : ClosedTerm -> Maybe (List ClosedTerm, Nat)
    step leaf = if isCall leaf then Just ([], 1) else case getFnArgs leaf of
      (Ref _ (DataCon _ _) _, ks) => children ks
      (Ref _ (TyCon _) _, ks) => children ks
      _ => Nothing

    go : List Arm -> Maybe (List ClosedTerm, List ClosedTerm, Nat)
    go [] = Just ([], [], 0)
    go (Step leaf :: rest) = do
      (closed, calls) <- step leaf
      (bases, kids, more) <- go rest
      Just (bases, closed ++ kids, calls + more)
    go (Base leaf :: rest) =
      if isClosed leaf
         then do (bases, kids, calls) <- go rest
                 Just (leaf :: bases, kids, calls)
         else Nothing

mutual
  ||| The tallest of some templates; 0 for none.
  tallest : List Template -> Nat
  tallest [] = 0
  tallest (t :: ts) = max (height t) (tallest ts)

  ||| The model's height of a template: a marker, a field and a held
  ||| dictionary are 0 (what they stand for is weighed by their arcs), a
  ||| leaf its own, a token and an argument of a family's value 1 (the
  ||| key's bound variable), a head and an applied family one above their
  ||| tallest child, a choice its tallest leaf.
  export
  height : Template -> Nat
  height (Var _ _) = 0
  height (Field _ _) = 0
  height (Held _ _) = 0
  height (Leaf h) = h
  height (Token _) = 1
  height (Formal _ _) = 1
  height (Head _ ts) = S (tallest ts)
  height (Opaque _ ts) = S (tallest ts)
  height (Applied _ _ ts) = S (tallest ts)
  height (Computing _ _ ts) = S (tallest ts)
  height (Choice _ ts) = tallest ts

||| `c` levels of a head above a template.
raise : Nat -> Template -> Template
raise Z t = t
raise (S c) t = Head Nothing [raise c t]

------------------------------------------------------------------------------
-- The readings
------------------------------------------------------------------------------

||| What a reading keeps of a part: a type's (or a dictionary's) every node,
||| or a value's skeleton, in which every part that is no data constructor
||| is one hole (`skeleton` makes it `Erased`). These are two cases of the
||| problem, and the one distinction an unfolding carries.
data Reading = AsType | AsShape

||| What a reading does with a definition left applied: unfold its case
||| tree, as a normal form's stuck call is read, or keep it as written, as a
||| written key (a dictionary, a shape's constructors) holds it.
data Calls = Unfolded | Kept

record Mode where
  constructor MkMode
  reading : Reading
  calls : Calls

||| A part that is no data constructor: a node of a type's form, a hole of
||| a value's skeleton.
node : Reading -> Lazy (Core Template) -> Core Template
node AsType t = t
node AsShape _ = pure (Leaf 1)

||| An argument met on a spine, as a closed term, for what substitutes it,
||| and as read; each computed when it is needed.
record Arg where
  constructor MkArg
  value : Lazy ClosedTerm
  template : Lazy (Core Template)

readings : List Arg -> Core (List Template)
readings = traverse (\a => Force a.template)

||| A template applied: a head above it and its arguments' readings.
above : Template -> List Arg -> Core Template
above t args = (\ts => Head Nothing (t :: ts)) <$> readings args

||| One of the walk's markers applied: its reading, then its arguments'. A
||| family the writer was given, applied, is whatever every instance's
||| beta-reduction makes of its value's body around the arguments, which is
||| no head above them (`Applied`); a dictionary's field applied is a head
||| above it and them.
marked : Template -> List Arg -> Core Template
marked t [] = pure t
marked (Var i d) args = Applied i d <$> readings args
marked t args = above t args

||| A part that is no head of its own, applied: a node above it and its
||| arguments in a type's form, a hole in a skeleton.
part : Mode -> Template -> List Arg -> Core Template
part m t [] = pure t
part m t args@(_ :: _) = node m.reading (above t args)

||| A definition kept as it is written: its head and its arguments'
||| readings in a type's form, a hole in a skeleton.
kept : Reading -> Address -> List Arg -> Core Template
kept r a args = node r (Head (Just a) <$> readings args)

||| A projection applied to its parameters whose record is no data
||| constructor application: its field, the record, and the arguments past
||| the projection's own. A normal form has projected every constructor
||| record, and a dictionary's key writes a projection of one as the
||| application it is.
projectedRecord : {auto c : Ref Ctxt Defs} -> Name -> List Arg -> Core (Maybe (Nat, Arg, List Arg))
projectedRecord n args = do
  Just pr <- projection n
    | Nothing => pure Nothing
  pure $ do
    (env, extras) <- bindParams pr.params args
    let projected = valueAt env pr.matched pr.isParam
    case getFnArgs (Force projected.value) of
      (Ref _ (DataCon _ _) _, _) => Nothing
      _ => Just (pr.field, projected, extras)

||| How many arguments a value of a type takes: its Pi binders, read off
||| its normal form when the type as written is no Pi down to a universe or
||| a type constructor applied, the forms no normaliser adds a binder to.
arityOf : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> TT vs -> Core Nat
arityOf ty = case written ty of
    Just k => pure k
    Nothing => pure (pis !(normaliseClosed (closedOver ty)))
  where
    pis : TT ws -> Nat
    pis (Bind _ _ (Pi {}) sc) = S (pis sc)
    pis _ = 0

    written : TT ws -> Maybe Nat
    written (Bind _ _ (Pi {}) sc) = S <$> written sc
    written (TType {}) = Just 0
    written t = case getFn t of
      Ref _ (TyCon _) _ => Just 0
      PrimVal {} => Just 0
      _ => Nothing

||| How many arguments each parameter of a type takes, in order.
binderArities : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> TT vs -> Core (List Nat)
binderArities (Bind _ _ (Pi _ _ _ ty) sc) = (::) <$> arityOf ty <*> binderArities sc
binderArities _ = pure []

||| What a variable bound inside the term being read is substituted by: a
||| lambda's, an argument of a family's value, which beta substitutes (its
||| position, and how many arguments it takes); any other binder's, a
||| placeholder no reading looks into.
data Substitute = FormalArgument Nat Nat | Placeholding

||| A substitute as a closed term, which a part is closed with.
substituted : Substitute -> ClosedTerm
substituted (FormalArgument j k) = formalAt j k
substituted Placeholding = Erased EmptyFC Placeholder

||| A substitute as read: an argument of a family's value, or a leaf of the
||| placeholder's height, so that every part it is substituted into stays
||| closed.
substituteTemplate : Substitute -> Template
substituteTemplate (FormalArgument j k) = Formal j k
substituteTemplate Placeholding = Leaf 1

||| Arguments j, j + 1, ... of a family's value, as many as asked, each
||| taking as many arguments as its type does (none past the list).
formalsFrom : Nat -> List Nat -> Nat -> List Substitute
formalsFrom j ks Z = []
formalsFrom j [] (S n) = FormalArgument j 0 :: formalsFrom (S j) [] n
formalsFrom j (k :: ks) (S n) = FormalArgument j k :: formalsFrom (S j) ks n

mutual
  ||| A term read as its key writes it, each variable by its substitute
  ||| (a placeholder, or a lambda's argument). A dotted term is what it
  ||| dots; a closed run of a Nat-like type is its run's height
  ||| (`closedRun`).
  read : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> Mode -> (w : Walked) -> (0 acc : SizeAccessible w) ->
         Values Substitute vs -> TT vs -> Core Template
  read m w acc stand (Erased _ (Dotted u)) = read m w acc stand u
  read m w acc stand t = do
    Just k <- closedRun t
      | Nothing => spine m w acc stand t []
    pure (Leaf (S k))

  ||| A part met on a spine.
  argOf : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> Mode -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Values Substitute vs -> TT vs -> Arg
  argOf m w acc stand a = MkArg (closeBy substituted stand a) (read m w acc stand a)

  ||| A term applied to arguments, read by its head.
  spine : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> Mode -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Values Substitute vs -> TT vs -> List Arg -> Core Template
  spine m w acc stand (App _ f a) args = spine m w acc stand f (argOf m w acc stand a :: args)
  spine m w acc stand (Erased _ (Dotted u)) args = spine m w acc stand u args
  -- A runtime part is one key node, in every reading. An `Erased` part is an
  -- unbound binder's placeholder, or a part cut or holed at runtime; a
  -- binder's variable is its substitute; a metavariable left after
  -- `solved` and every normaliser has no solution.
  spine m w acc stand (Erased _ _) args = part m (Leaf 1) args
  spine m w acc stand (Local _ _ idx p) args = part m (substituteTemplate (valueAt stand idx p)) args
  spine m w acc stand (Meta {}) args = part m (Leaf 1) args
  spine m w acc stand (Ref _ nt n) args = reference m w acc nt n args
  spine m w acc stand (TType {}) args = part m (Leaf 1) args
  spine m w acc stand (PrimVal _ k) args = node m.reading (part m (constant k) args)
  -- A lambda is a family's value (or a function's), whose variable is
  -- what beta substitutes: an argument (`Formal`), so that a definition
  -- stuck on it is read for what it computes from each argument as well
  -- as as written. Any other binder is a head above its parts and its
  -- scope, in which its variable is a placeholder. A term is read
  -- contracted (`contracted`), so no lambda here only applies something
  -- to its own variables.
  spine {vs} m w acc stand (Bind _ x (Lam _ _ _ ty) sc) args = node m.reading $ do
    t <- read m w acc stand ty
    k <- arityOf (closeBy substituted stand ty)
    s <- read m w acc (FormalArgument (length vs) k :: stand) sc
    part m (Head Nothing [t, s]) args
  spine m w acc stand tm@(Bind _ x b sc) args = node m.reading $ do
    ps <- binder m w acc stand b
    s <- read m w acc (Placeholding :: stand) sc
    part m (Head Nothing (ps ++ [s])) args
  spine m w acc stand (TDelayed _ _ u) args = node m.reading $ do
    t <- read m w acc stand u
    part m (Head Nothing [t]) args
  spine m w acc stand (TDelay _ _ ty a) args = node m.reading $ do
    t <- read m w acc stand ty
    v <- read m w acc stand a
    part m (Head Nothing [t, v]) args
  spine m w acc stand (TForce _ _ u) args = node m.reading $ do
    t <- read m w acc stand u
    part m (Head Nothing [t]) args
  spine m w acc stand (As _ _ a p) args = node m.reading $ do
    t <- read m w acc stand a
    v <- read m w acc stand p
    part m (Head Nothing [t, v]) args

  ||| A binder's parts: its type, and a `let`'s value before it.
  binder : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> Mode -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Values Substitute vs -> TTBinder (TT vs) -> Core (List Template)
  binder m w acc stand (Lam _ _ _ ty) = pure [!(read m w acc stand ty)]
  binder m w acc stand (Let _ _ v ty) = pure [!(read m w acc stand v), !(read m w acc stand ty)]
  binder m w acc stand (Pi _ _ _ ty) = pure [!(read m w acc stand ty)]
  binder m w acc stand (PVar _ _ _ ty) = pure [!(read m w acc stand ty)]
  binder m w acc stand (PLet _ _ v ty) = pure [!(read m w acc stand v), !(read m w acc stand ty)]
  binder m w acc stand (PVTy _ _ ty) = pure [!(read m w acc stand ty)]

  ||| A reference applied, in every reading: a runtime part is one node,
  ||| a hole marker its token, one of the walk's markers its family's
  ||| reading (applied, a head above it and its arguments). A data
  ||| constructor is a head in every reading, a type constructor in a type's.
  reference : {auto c : Ref Ctxt Defs} -> Mode -> (w : Walked) -> (0 acc : SizeAccessible w) ->
              NameType -> Name -> List Arg -> Core Template
  reference m w acc nt n args = do
    defs <- get Ctxt
    case referenceOf (gamma defs) nt n of
      HoleMarker i => part m (Token (S i)) args
      FormalMarker j k => part m (Formal j k) args
      WalkMarker t => marked t args
      RuntimePart => part m (Leaf 1) args
      DataConstructor a => Head a <$> readings args
      TypeConstructor a => node m.reading (Head a <$> readings args)
      Defined a => ofDefinition m w acc n a args

  ||| A definition with a place, applied. In a type's form, a projection of a
  ||| record that is no constructor is, at an instance, one of two things: the
  ||| application as written, which a dictionary's key keeps (`classify`
  ||| takes a dictionary as written), and a normal form keeps while the
  ||| record stays no constructor; or the record's field (`Field`), once the
  ||| record is one. So it is the choice of both, behind the record it
  ||| matches. In a skeleton, a projection of a value is a match on it like
  ||| any other.
  ofDefinition : {auto c : Ref Ctxt Defs} -> Mode -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 Name -> Address -> List Arg -> Core Template
  ofDefinition m@(MkMode AsType _) w acc n a args = do
    Just (k, projected, extras) <- projectedRecord n args
      | Nothing => call m w acc n a args
    matched <- Force projected.template
    written <- kept AsType a args
    field <- part m (Template.Field k matched) extras
    pure (Choice matched [written, field])
  ofDefinition m@(MkMode AsShape _) w acc n a args = call m w acc n a args

  call : {auto c : Ref Ctxt Defs} -> Mode -> (w : Walked) -> (0 acc : SizeAccessible w) ->
         Name -> Address -> List Arg -> Core Template
  call (MkMode r Unfolded) w acc n a args = applied r w acc n a args
  call (MkMode r Kept) w acc n a args = kept r a args

  ||| A definition left applied in a type's normal form or a shape's. The
  ||| normaliser leaves applied, whatever its arguments, one that does not
  ||| match (its visibility, an implementation under `normaliseTypes`, a
  ||| builtin) and one applied to fewer arguments than its parameters, so it
  ||| is applied at every instance too: it stays as written. One already
  ||| being unfolded on this path is a recursion (`Opaque`), unless the
  ||| first unfolding found it structural. Any other is unfolded: its case
  ||| tree walked over its arguments.
  applied : {auto c : Ref Ctxt Defs} -> Reading -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Name -> Address -> List Arg -> Core Template
  applied r w acc@(Access rec) n a args = do
    let folded = kept r a args
    Just (placement, def) <- resolve n
      | Nothing => folded
    case definition def of
      PMDef _ pargs tree _ _ =>
        let terms = map (\x => Force x.value) args in
        case (bindParams pargs terms, tree) of
          (Nothing, _) => given r w acc placement a terms (type def) pargs tree folded
          (Just _, STerm {}) => folded
          (Just (env, extras), _) => case enter placement w of
            Nothing => Opaque a <$> readings args
            Just (Element w' less) => do
              Nothing <- structural r w' (rec w' less) a terms env tree extras
                | Just t => pure t
              Just t <- walk r w' (rec w' less) a folded env tree extras
                | Nothing => folded
              pure t
      _ => folded

  ||| A definition given fewer arguments than its parameters: a family's
  ||| value (or a function's). Its key holds it as written, and beta gives
  ||| it the rest, so in a type's form it is the choice of both: as
  ||| written, and its case tree walked over an argument (`Formal`) for
  ||| each parameter it lacks. A skeleton keeps it as written: no value's
  ||| skeleton is applied.
  given : {auto c : Ref Ctxt Defs} -> Reading -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Placement -> Address -> List ClosedTerm -> (type : ClosedTerm) -> (pargs : Scope) -> CaseTree pargs ->
          Core Template -> Core Template
  given AsShape w acc placement a terms ty pargs tree folded = folded
  given AsType w acc@(Access rec) placement a terms ty pargs tree folded = do
    arities <- binderArities ty
    let lacking = formalsFrom 0 (drop (length terms) arities) (minus (length pargs) (length terms))
    case bindParams pargs (terms ++ map substituted lacking) of
      Nothing => folded
      -- Met again on its own unfolding: as written, or a recursion through
      -- the arguments it lacks, which nothing bounds.
      Just (env, extras) => case enter placement w of
        Nothing => do
          written <- folded
          pure (Choice (Leaf 1) [written, Opaque a (map substituteTemplate lacking)])
        Just (Element w' less) => do
          Just t <- walk AsType w' (rec w' less) a folded env tree extras
            | Nothing => folded
          written <- folded
          pure (Choice (Leaf 1) [written, t])

  ||| A recursion structural on one Nat-like argument, read as the
  ||| argument raised by its leaves' height: `Choice (Var j e)` of the other
  ||| leaves and of `Var j e` under c heads, with c = max B S' - 1, B the
  ||| tallest other leaf and S' the tallest closed child of the successor's.
  |||
  ||| Proof, by induction on the argument v, with h(v) = k + 1 for k
  ||| successors: h(n Z) <= B <= 1 + c; h(n (S k)) <= 1 + max(S', h(n k))
  ||| <= 1 + h(k) + c = h(S k) + c, since h(k) >= 1 and c >= S' - 1. So
  ||| h(n v) <= h(v) + c, which is the reading's weight from `Var j e`. A
  ||| default's leaf is a base like the zero's. A leaf that holds another
  ||| marker grows by a sum of heights (`F a Z = a`), which no template
  ||| states, so it is no structural recursion; nor is a deeper step, a
  ||| recursion on a non-Nat value, a nested case tree, or two heads a
  ||| level.
  structural : {auto c : Ref Ctxt Defs} -> Reading -> (w : Walked) -> (0 acc : SizeAccessible w) ->
               (self : Address) -> List ClosedTerm -> Values ClosedTerm vs -> CaseTree vs -> List ClosedTerm ->
               Core (Maybe Template)
  structural r w acc self args env (Case idx p _ alts) extras = do
    let Just (j, e) = bareMarker (valueAt env idx p)
      | Nothing => pure Nothing
    Just arms <- natArms (markerAt j (S e)) env alts
      | Nothing => pure Nothing
    arms' <- traverse normalisedArm arms
    defs <- get Ctxt
    let Just (bases, kids) = recursion (gamma defs) self (j, S e) args idx arms'
      | Nothing => pure Nothing
    leaves <- traverse (read (MkMode r Unfolded) w acc []) bases
    children <- traverse (read (MkMode r Unfolded) w acc []) kids
    let c = minus (max (tallest leaves) (tallest children)) 1
    pure (Just (Choice (Var j e) (leaves ++ [raise c (Var j e)])))
    where
      normalisedArm : Arm -> Core Arm
      normalisedArm (Step t) = Step . contracted <$> normaliseClosed (applyTo t extras)
      normalisedArm (Base t) = Base . contracted <$> normaliseClosed (applyTo t extras)
  structural _ _ _ _ _ _ _ _ = pure Nothing

  ||| A case tree walked over what its variables stand for, the leaves it
  ||| can reach read under the walk that entered it; nothing for an absurd
  ||| tree. A match on a constructor, a literal or a delay takes its
  ||| alternative, as the normaliser would at every instance; one on a
  ||| runtime value is stuck at every instance, so the definition stays as
  ||| written (`folded`); one on a marker, or on what is stuck in turn, is a
  ||| `Choice` of every alternative's leaves behind what it matched on; one
  ||| on an argument of a family's value is the choice of the definition as
  ||| written and of a recursion of `self` stuck on that argument, since
  ||| what it computes depends on what beta substitutes there.
  walk : {auto c : Ref Ctxt Defs} -> Reading -> (w : Walked) -> (0 acc : SizeAccessible w) ->
         Address -> Core Template -> Values ClosedTerm vs -> CaseTree vs -> List ClosedTerm -> Core (Maybe Template)
  walk r w acc self folded env (STerm _ rhs) extras =
    Just <$> read (MkMode r Unfolded) w acc [] (contracted !(normaliseClosed (applyTo (close env rhs) extras)))
  -- A partial definition stops where it does not match, at every instance.
  walk r w acc self folded env (Unmatched _) extras = Just <$> folded
  walk r w acc self folded env Impossible extras = pure Nothing
  walk r w acc self folded env (Case idx p _ alts) extras = do
    defs <- get Ctxt
    let s = valueAt env idx p
    case scrutineeOf (gamma defs) s of
      Constructed c sargs => chosen r w acc self folded env !(toFullNames c) sargs alts extras
      Literal k => literal r w acc self folded env k alts extras
      Suspended ty a => delayed r w acc self folded env ty a alts extras
      -- A constructor's argument is a part of the matched value, one level
      -- deeper.
      Matched i d => Just . Choice (Var i d) <$> everyAlt r w acc self folded env (markerAt i (S d)) alts extras
      -- An argument of a family's value: as written, which every key of
      -- the value holds and an argument at run time leaves stuck; or, once
      -- beta substitutes the argument, what the match computes from it,
      -- which nothing bounds (`beta` says the value computes).
      OnFormal j k => do
        written <- folded
        pure (Just (Choice (Formal j k) [written, Opaque self [Formal j k]]))
      AtRuntime => Just <$> folded
      -- A constructor's argument is a part of the value, so the value
      -- bounds it.
      StuckInTurn => do
        t <- read (MkMode r Unfolded) w acc [] s
        Just . Choice t <$> everyAlt r w acc self folded env s alts extras

  ||| The alternative a constructor takes, by its full name, as the
  ||| translation's own static match takes it (`Cases.staticCase`).
  chosen : {auto c : Ref Ctxt Defs} -> Reading -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Address -> Core Template -> Values ClosedTerm vs -> Name -> List ClosedTerm -> List (CaseAlt vs) ->
           List ClosedTerm -> Core (Maybe Template)
  chosen r w acc self folded env c sargs (ConCase con _ cargs t :: alts) extras = do
    full <- toFullNames con
    if full /= c then chosen r w acc self folded env c sargs alts extras else
      case bindEach cargs sargs of
        Just bound => walk r w acc self folded (extend bound env) t extras
        Nothing => internal EmptyFC ("constructor " ++ show c ++ " binds an unexpected number of arguments")
  chosen r w acc self folded env c sargs (DefaultCase t :: _) extras = walk r w acc self folded env t extras
  chosen r w acc self folded env c sargs (_ :: alts) extras = chosen r w acc self folded env c sargs alts extras
  chosen r w acc self folded env c sargs [] extras = Just <$> folded

  literal : {auto c : Ref Ctxt Defs} -> Reading -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Address -> Core Template -> Values ClosedTerm vs -> Constant -> List (CaseAlt vs) -> List ClosedTerm ->
            Core (Maybe Template)
  literal r w acc self folded env k (ConstCase k' t :: alts) extras =
    if k' == k then walk r w acc self folded env t extras else literal r w acc self folded env k alts extras
  literal r w acc self folded env k (DefaultCase t :: _) extras = walk r w acc self folded env t extras
  literal r w acc self folded env k (_ :: alts) extras = literal r w acc self folded env k alts extras
  literal r w acc self folded env k [] extras = Just <$> folded

  delayed : {auto c : Ref Ctxt Defs} -> Reading -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Address -> Core Template -> Values ClosedTerm vs -> ClosedTerm -> ClosedTerm -> List (CaseAlt vs) ->
            List ClosedTerm -> Core (Maybe Template)
  delayed r w acc self folded env ty a (DelayCase _ _ t :: _) extras = walk r w acc self folded (ty :: a :: env) t extras
  delayed r w acc self folded env ty a (DefaultCase t :: _) extras = walk r w acc self folded env t extras
  delayed r w acc self folded env ty a (_ :: alts) extras = delayed r w acc self folded env ty a alts extras
  delayed r w acc self folded env ty a [] extras = Just <$> folded

  ||| Every alternative's leaves, each argument a constructor or a delay
  ||| binds standing for `x`; an absurd one gives none.
  everyAlt : {auto c : Ref Ctxt Defs} -> Reading -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             Address -> Core Template -> Values ClosedTerm vs -> ClosedTerm -> List (CaseAlt vs) ->
             List ClosedTerm -> Core (List Template)
  everyAlt r w acc self folded env x [] extras = pure []
  everyAlt r w acc self folded env x (alt :: alts) extras = do
    here <- alternative r w acc self folded env x alt extras
    rest <- everyAlt r w acc self folded env x alts extras
    pure (maybe rest (:: rest) here)

  alternative : {auto c : Ref Ctxt Defs} -> Reading -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                Address -> Core Template -> Values ClosedTerm vs -> ClosedTerm -> CaseAlt vs ->
                List ClosedTerm -> Core (Maybe Template)
  alternative r w acc self folded env x (ConCase _ _ cargs t) extras = walk r w acc self folded (extend (bindAll cargs x) env) t extras
  alternative r w acc self folded env x (DelayCase _ _ t) extras = walk r w acc self folded (x :: x :: env) t extras
  alternative r w acc self folded env x (ConstCase _ t) extras = walk r w acc self folded env t extras
  alternative r w acc self folded env x (DefaultCase t) extras = walk r w acc self folded env t extras

||| A closed term read on a walk that has entered nothing yet.
readFromStart : {auto c : Ref Ctxt Defs} -> Mode -> ClosedTerm -> Core Template
readFromStart m t = read m start (sizeAccessible start) [] t

||| A type, a family or a form as its template and its root read it: its
||| normal form, as classify normalises it, a lambda that only applies a
||| family to its variable contracted to that family.
typeForm : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
typeForm t = contracted <$> normaliseClosed t

||| The template of a normal form (`typeForm`), stuck definitions unfolded.
formTemplate : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Template
formTemplate form = readFromStart (MkMode AsType Unfolded) form

mutual
  ||| A shape's template as a key holds its form (`Shapes.formOf`): each
  ||| `:<` of its spine, the constructor of tag 1 as `Shapes.shapeView`
  ||| reads it, with its extent the leaf an erased extent is; any other
  ||| part (`Lin`, the writer's marker, a computation) as it is, and each
  ||| leaf of a choice so. A form's height is then the key's, whatever
  ||| extents are written, so that a key and the bound on it are read alike.
  export
  formedTemplate : {auto c : Ref Ctxt Defs} -> Template -> Core Template
  formedTemplate t@(Head (Just a) [e, rest, _]) = do
    Just def <- definitionAt a
      | Nothing => pure t
    case definition def of
      DCon 1 _ _ => pure (Head (Just a) [e, !(formedTemplate rest), Leaf 1])
      _ => pure t
  formedTemplate (Choice t ls) = Choice t <$> formedTemplates ls
  formedTemplate t = pure t

  formedTemplates : {auto c : Ref Ctxt Defs} -> List Template -> Core (List Template)
  formedTemplates [] = pure []
  formedTemplates (t :: ts) = (::) <$> formedTemplate t <*> formedTemplates ts

||| What a site, a field or a cap writes at a static argument of kind k,
||| read as its key writes it there (`Instances.classify`). A type, a
||| family and a form are normalised as classify normalises them, stuck
||| definitions unfolded, and a form is read as its key holds it
||| (`formedTemplate`). A dictionary is the form classify
||| keys: as written, or the implementation it stands for when it depends
||| on a runtime value, nothing normalised or unfolded. A shape is a
||| skeleton: of the argument as written when a data constructor heads it,
||| else of its normal form (`Instances.argumentShape`).
export
templateOf : {auto c : Ref Ctxt Defs} -> State.Static -> ClosedTerm -> Core Template
templateOf AType t = formTemplate !(typeForm t)
templateOf AFamily t = formTemplate !(typeForm t)
templateOf AForm t = formedTemplate !(formTemplate !(typeForm t))
templateOf ADictionary t = do
  written <- solved t
  form <- if !(runtimeDependent written) then implementationOf written else pure written
  readFromStart (MkMode AsType Kept) (contracted form)
templateOf AShape t = do
  written <- solved t
  case getFnArgs written of
    (Ref _ (DataCon _ _) _, _) => readFromStart (MkMode AsShape Kept) (contracted written)
    _ => readFromStart (MkMode AsShape Unfolded) (contracted !(normaliseClosed t))

------------------------------------------------------------------------------
-- The measures
------------------------------------------------------------------------------

mutual
  widest : List Template -> Nat
  widest [] = 0
  widest (t :: ts) = max (arity t) (widest ts)

  ||| The most children of any node, a choice's leaves' own.
  export
  arity : Template -> Nat
  arity (Head _ ts) = max (length ts) (widest ts)
  arity (Opaque _ ts) = max (length ts) (widest ts)
  arity (Applied _ _ ts) = max (S (length ts)) (widest ts)
  arity (Computing _ _ ts) = max (S (length ts)) (widest ts)
  arity (Choice _ ts) = widest ts
  arity (Field _ s) = arity s
  arity (Var _ _) = 0
  arity (Leaf _) = 0
  arity (Token _) = 0
  arity (Held _ _) = 0
  arity (Formal _ _) = 0

||| What beta makes of the family values a template holds, each read as
||| its meaning (lambdas' variables and the parameters a definition lacks
||| as arguments, `Formal`): no higher than the value above the tallest
||| argument (`Inert`), or what nothing bounds (`Computes`). A value
||| computes when its meaning holds a definition stuck on one of its
||| arguments (`Opaque`: beta lets its match go on), or applies an argument
||| to what holds another argument, or to other than as many arguments as
||| it takes: a sum of two heights. Each of these is a case of the problem:
||| an argument that beta substitutes into a computation, rather than
||| places.
public export
data Beta = Inert | Computes

both : Beta -> Beta -> Beta
both Inert b = b
both Computes _ = Computes

mutual
  -- Does any of these templates hold an argument of a family's value?
  holdsFormal : List Template -> Bool
  holdsFormal [] = False
  holdsFormal (t :: ts) = formalIn t || holdsFormal ts

  formalIn : Template -> Bool
  formalIn (Formal _ _) = True
  formalIn (Head _ ts) = holdsFormal ts
  formalIn (Opaque _ ts) = holdsFormal ts
  formalIn (Applied _ _ ts) = holdsFormal ts
  formalIn (Computing _ _ ts) = holdsFormal ts
  formalIn (Choice s ts) = formalIn s || holdsFormal ts
  formalIn (Field _ t) = formalIn t
  formalIn _ = False

mutual
  ||| What beta makes of the family values a template holds (`Beta`). An
  ||| argument that takes arguments of its own reads as a head above them
  ||| when it is applied (`marked`); one that takes none at the head of a
  ||| node is a binder's type, which is no application.
  export
  beta : Template -> Beta
  beta (Opaque _ ts) = if holdsFormal ts then Computes else betaAll ts
  beta (Head Nothing (Formal _ k@(S _) :: args)) =
    if length args /= k || holdsFormal args then Computes else betaAll args
  beta (Formal _ (S _)) = Computes
  beta (Head _ ts) = betaAll ts
  beta (Choice _ ts) = betaAll ts
  beta (Applied _ _ ts) = betaAll ts
  beta (Computing _ _ _) = Computes
  beta (Field _ t) = beta t
  beta (Var _ _) = Inert
  beta (Leaf _) = Inert
  beta (Token _) = Inert
  beta (Held _ _) = Inert
  beta (Formal _ Z) = Inert

  betaAll : List Template -> Beta
  betaAll [] = Inert
  betaAll (t :: ts) = both (beta t) (betaAll ts)

||| What lands at the position of a family the writer was given, over the
||| growth graph's walk: only closed values no higher than k, each inert; or
||| inert values not all closed, whose height an arc carries; or a value
||| that computes, carried there from where one lands or written there not
||| closed; or closed values only, some computing, which are these terms:
||| a family applied there is evaluated at each (`Graph.evaluated`).
public export
data Landing = Closed Nat | Open | Computed | Evaluable (List ClosedTerm)

mutual
  -- The writer's families a template carries on as families: the whole
  -- template when it is one of them (a family passed on), and every one
  -- applied in it (inside a family's value, what beta makes of the value
  -- is what the family makes). Anywhere else a marker is a type's part,
  -- which beta never applies.
  export
  familiesIn : Template -> List Nat
  familiesIn (Var i _) = [i]
  familiesIn t = appliedIn t

  appliedIn : Template -> List Nat
  appliedIn (Applied i _ ts) = i :: appliedAll ts
  appliedIn (Computing i _ ts) = i :: appliedAll ts
  appliedIn (Head _ ts) = appliedAll ts
  appliedIn (Opaque _ ts) = appliedAll ts
  appliedIn (Choice s ts) = appliedIn s ++ appliedAll ts
  appliedIn (Field _ t) = appliedIn t
  appliedIn _ = []

  appliedAll : List Template -> List Nat
  appliedAll [] = []
  appliedAll (t :: ts) = appliedIn t ++ appliedAll ts

mutual
  -- The writer's families whose landing an applied family in a template
  -- reads: each family applied, and each one its arguments carry on
  -- (`withClosedFamilies`).
  export
  applyingIn : Template -> List Nat
  applyingIn (Applied i _ ts) = i :: (ts >>= familiesIn) ++ applyingAll ts
  applyingIn (Computing i _ ts) = i :: (ts >>= familiesIn) ++ applyingAll ts
  applyingIn (Head _ ts) = applyingAll ts
  applyingIn (Opaque _ ts) = applyingAll ts
  applyingIn (Choice s ts) = applyingIn s ++ applyingAll ts
  applyingIn (Field _ t) = applyingIn t
  applyingIn _ = []

  applyingAll : List Template -> List Nat
  applyingAll [] = []
  applyingAll (t :: ts) = applyingIn t ++ applyingAll ts

-- Whether arguments applied to a family give beta what computes: one of
-- them computes, or carries on a family where a computing value lands. A
-- family's value may apply an argument it is given, and what that
-- argument computes from its own arguments is then in the result.
argumentsBeta : (Nat -> Landing) -> List Template -> Beta
argumentsBeta c ts = both (betaAll ts) (if any computing (ts >>= familiesIn) then Computes else Inert)
  where
    computing : Nat -> Bool
    computing i = case c i of
      Computed => True
      Evaluable _ => True
      _ => False

mutual
  ||| A template read at a node, each applied family of the writer's by what
  ||| lands at its position (`Graph`). Beta of an inert family no higher
  ||| than k, applied to arguments no higher than h, is no higher than k + h
  ||| (`Proof.Bound.betaHeight`'s statement): the value's meaning is no
  ||| higher than the value and holds each argument no deeper than the value
  ||| is high. So where only closed values no higher than k land, an
  ||| applied family reads as k heads above its arguments; where values not
  ||| all closed land, it stays applied, the family's own height carried by
  ||| an arc when its arguments are closed (`appliedWeight`), and a sum of
  ||| two heights otherwise; and where a value may compute, or an argument
  ||| does, it reads as computing (`Computing`), a value nothing bounds.
  export
  withClosedFamilies : (landing : Nat -> Landing) -> Template -> Template
  withClosedFamilies c (Applied i d ts) =
    let ts' = allWithClosed c ts in
    case (c i, argumentsBeta c ts') of
      (Computed, _) => Computing i d ts'
      (Evaluable _, _) => Computing i d ts'
      (_, Computes) => Computing i d ts'
      (Closed k, Inert) => raise k (Head Nothing ts')
      (Open, Inert) => Applied i d ts'
  withClosedFamilies c (Computing i d ts) = Computing i d (allWithClosed c ts)
  withClosedFamilies c (Head a ts) = Head a (allWithClosed c ts)
  withClosedFamilies c (Opaque a ts) = Opaque a (allWithClosed c ts)
  withClosedFamilies c (Choice t ts) = Choice (withClosedFamilies c t) (allWithClosed c ts)
  withClosedFamilies c (Field k t) = Field k (withClosedFamilies c t)
  withClosedFamilies c t@(Var _ _) = t
  withClosedFamilies c t@(Leaf _) = t
  withClosedFamilies c t@(Token _) = t
  withClosedFamilies c t@(Held _ _) = t
  withClosedFamilies c t@(Formal _ _) = t

  allWithClosed : (landing : Nat -> Landing) -> List Template -> List Template
  allWithClosed c [] = []
  allWithClosed c (t :: ts) = withClosedFamilies c t :: allWithClosed c ts

mutual
  ||| Is what every instance writes at a template no higher than the
  ||| template: it holds no marker, field or held dictionary, whose values
  ||| are their arcs', and no family applied? A choice's value is one of its
  ||| leaves, and an argument of a family's value is the writer's to no
  ||| instance: what beta makes of it, `beta` says.
  export
  selfBounded : Template -> Bool
  selfBounded (Head _ ts) = allSelfBounded ts
  selfBounded (Opaque _ ts) = allSelfBounded ts
  selfBounded (Choice _ ts) = allSelfBounded ts
  selfBounded (Leaf _) = True
  selfBounded (Token _) = True
  selfBounded (Var _ _) = False
  selfBounded (Applied _ _ _) = False
  selfBounded (Computing _ _ _) = False
  selfBounded (Field _ _) = False
  selfBounded (Held _ _) = False
  selfBounded (Formal _ _) = True

  allSelfBounded : List Template -> Bool
  allSelfBounded [] = True
  allSelfBounded (t :: ts) = selfBounded t && allSelfBounded ts

-- How much an applied family grows its own marker, at e heads deep. Beta
-- of a family no higher than k, applied to arguments no higher than h, is
-- no higher than k + h, when the family is inert (`withClosedFamilies`
-- says which are). With closed arguments, h is their height: the marker's
-- own value raised by a constant. With an argument that holds a marker it
-- is a sum of two heights, which no weight states (`Stuck`).
appliedWeight : (e, d : Nat) -> List Template -> Weight
appliedWeight e d ts = if allSelfBounded ts then Finite (e + tallest ts) d else Growth.Stuck

-- One side 0.
settled : Weight -> Weight
settled (Finite g l) = Finite (minus g l) (minus l g)
settled w = w

mutual
  -- `Var i d` at e heads deep weighs e - d. A field's record is weighed by
  -- the arcs its value carries (`Graph`'s `fieldValue`), and a choice's
  -- scrutinee by its caps, so neither is a part the template's height
  -- carries. An applied family's arguments are a sum with its value's
  -- height, unbounded.
  weightsAt : (e : Nat) -> Template -> SortedMap Nat Weight -> SortedMap Nat Weight
  weightsAt e (Var j d) m = insertWith join j (Finite e d) m
  weightsAt e (Head _ ts) m = weightsAll (S e) ts m
  weightsAt e (Opaque _ ts) m = stuckAll ts m
  weightsAt e (Applied j d ts) m = insertWith join j (appliedWeight e d ts) (stuckAll ts m)
  weightsAt e (Computing j _ ts) m = stuckAll ts (insert j Growth.Stuck m)
  weightsAt e (Choice _ ts) m = weightsAll e ts m
  weightsAt e (Field _ _) m = m
  weightsAt e (Leaf _) m = m
  weightsAt e (Token _) m = m
  weightsAt e (Held _ _) m = m
  weightsAt e (Formal _ _) m = m

  weightsAll : (e : Nat) -> List Template -> SortedMap Nat Weight -> SortedMap Nat Weight
  weightsAll e [] m = m
  weightsAll e (t :: ts) m = weightsAll e ts (weightsAt e t m)

  -- Every `Var i` below, as `Stuck`: under an `Opaque`, what a recursion
  -- computes from a marker, inside a field or not, has no depth bound.
  stuckAt : Template -> SortedMap Nat Weight -> SortedMap Nat Weight
  stuckAt (Var j _) m = insert j Growth.Stuck m
  stuckAt (Field _ s) m = stuckAt s m
  stuckAt (Head _ ts) m = stuckAll ts m
  stuckAt (Opaque _ ts) m = stuckAll ts m
  stuckAt (Applied j _ ts) m = stuckAll ts (insert j Growth.Stuck m)
  stuckAt (Computing j _ ts) m = stuckAll ts (insert j Growth.Stuck m)
  stuckAt (Choice _ ts) m = stuckAll ts m
  stuckAt (Leaf _) m = m
  stuckAt (Token _) m = m
  stuckAt (Held _ _) m = m
  stuckAt (Formal _ _) m = m

  stuckAll : List Template -> SortedMap Nat Weight -> SortedMap Nat Weight
  stuckAll [] m = m
  stuckAll (t :: ts) m = stuckAll ts (stuckAt t m)

||| Every parameter a template grows, each once, with how much: the most of
||| e - d over its occurrences `Var i d` at e heads deep outside every
||| field, written with one side 0; `Stuck` under an `Opaque` or an
||| argument of an applied family. A parameter that does not occur is not
||| listed.
export
weights : Template -> List (Nat, Weight)
weights t = map (\(i, w) => (i, settled w)) (SortedMap.toList (weightsAt 0 t empty))

mutual
  heaviestOf : List Template -> Nat
  heaviestOf [] = 0
  heaviestOf (t :: ts) = max (heaviest t) (heaviestOf ts)

  ||| The heaviest literal or hole token a template holds, a choice's
  ||| leaves' included and its scrutinee skipped; 0 for none.
  export
  heaviest : Template -> Nat
  heaviest (Token k) = k
  heaviest (Head _ ts) = heaviestOf ts
  heaviest (Opaque _ ts) = heaviestOf ts
  heaviest (Applied _ _ ts) = heaviestOf ts
  heaviest (Computing _ _ ts) = heaviestOf ts
  heaviest (Choice _ ts) = heaviestOf ts
  heaviest (Field _ s) = heaviest s
  heaviest (Var _ _) = 0
  heaviest (Leaf _) = 0
  heaviest (Held _ _) = 0
  heaviest (Formal _ _) = 0

------------------------------------------------------------------------------
-- Roots and requests
------------------------------------------------------------------------------

||| A part of a dictionary met on the way to its root: as written, the
||| constructor it is built with and that constructor's arguments, and the
||| implementation at its root, each found when needed, on the walk where
||| the part was met.
record Piece where
  constructor MkPiece
  written : Lazy ClosedTerm
  built : Lazy (Core (Maybe (Name, List Piece)))
  root : Lazy (Core Root)

-- A dictionary is taken apart the way the growth graph reads one
-- (`Implementations.fieldsOf`, `Heads`) and the translation projects one
-- (`Closed`'s projections take the field this way first): a projection
-- takes its field from the constructor its record is built with, and a
-- record is built with one as written, or once a definition with one
-- right-hand side (an implementation) is unfolded over its arguments. A
-- projection whose record is built with none (a marker, a runtime part)
-- has no root of its own: the template's field says what it is. Nothing
-- goes to Idris's normaliser, whose normal form of a record unfolds the
-- implementations inside the field too.
mutual
  ||| A part met as an argument of a spine.
  pieceOf : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) -> ClosedTerm -> Piece
  pieceOf w acc t = MkPiece t (builtOf w acc t []) (rootOf w acc t [])

  ||| The constructor a dictionary is built with, and its arguments; nothing
  ||| for a marker, a runtime part, a definition that matches, or one met
  ||| again on its own unfolding.
  builtOf : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            ClosedTerm -> List Piece -> Core (Maybe (Name, List Piece))
  builtOf w acc (App _ f a) args = builtOf w acc f (pieceOf w acc a :: args)
  builtOf w acc (Ref _ (DataCon _ _) n) args = pure (Just (n, args))
  builtOf w acc (Ref _ Func n) args = do
    Just pr <- projection n
      | Nothing => unfoldedBuilt w acc n args
    Just (field, extras) <- projectedPiece pr args
      | Nothing => pure Nothing
    map (\(con, fields) => (con, fields ++ extras)) <$> Force field.built
  builtOf w acc _ _ = pure Nothing

  ||| A definition with one right-hand side, applied to its parameters,
  ||| unfolded: the constructor its body is built with.
  unfoldedBuilt : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                  Name -> List Piece -> Core (Maybe (Name, List Piece))
  unfoldedBuilt w acc@(Access rec) n args = do
    Just (placement, def) <- resolve n
      | Nothing => pure Nothing
    case definition def of
      PMDef _ pargs (STerm _ body) _ _ => case bindParams pargs args of
        Nothing => pure Nothing
        -- Entered already: met again on its own unfolding.
        Just (env, extras) => case enter placement w of
          Nothing => pure Nothing
          Just (Element w' less) =>
            let written : Piece -> ClosedTerm
                written p = Force p.written in
            builtOf w' (rec w' less) (applyTo (closeBy written env body) (map written extras)) []
      _ => pure Nothing

  ||| A projection applied to its parameters: the field it takes from the
  ||| constructor its record is built with, and the arguments past the
  ||| projection's own.
  projectedPiece : {auto c : Ref Ctxt Defs} -> Projection -> List Piece -> Core (Maybe (Piece, List Piece))
  projectedPiece pr args = do
    let Just (env, extras) = bindParams pr.params args
      | Nothing => pure Nothing
    Just (con, fields) <- Force (valueAt env pr.matched pr.isParam).built
      | Nothing => pure Nothing
    if !(toFullNames con) /= !(toFullNames pr.con)
       then pure Nothing
       else pure ((, extras) <$> getAt pr.field fields)

  ||| The implementation, or the constructor, at a dictionary's root: one of
  ||| the walk's markers is the writer's own dictionary; a constructor
  ||| applied, or a definition applied that is no projection (an
  ||| implementation), is itself; a projection is its field's root when its
  ||| record is built with a constructor, and has none when it is not (its
  ||| record a marker, a runtime part, a definition that matches): what it
  ||| is then, the template's field says (`Heads`). A field applied to
  ||| further arguments is a function, and roots nothing.
  rootOf : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           ClosedTerm -> List Piece -> Core Root
  rootOf w acc (App _ f a) args = rootOf w acc f (pieceOf w acc a :: args)
  rootOf w acc (Ref _ nt n) args = do
    defs <- get Ctxt
    case referenceOf (gamma defs) nt n of
      WalkMarker (Var i d) => pure (Parameter i d)
      DataConstructor a => pure (maybe Unrooted Rooted a)
      Defined a => do
        Just pr <- projection n
          | Nothing => pure (Rooted a)
        Just (field, []) <- projectedPiece pr args
          | _ => pure Unrooted
        Force field.root
      -- A field of a dictionary, which the template's field says, and
      -- what is no dictionary.
      WalkMarker _ => pure Unrooted
      HoleMarker _ => pure Unrooted
      FormalMarker _ _ => pure Unrooted
      RuntimePart => pure Unrooted
      TypeConstructor _ => pure Unrooted
  rootOf w acc _ _ = pure Unrooted

||| What a dictionary is at its root (`rootOf`), never its written head:
||| `snd (MkPair x d)` is d's root. A lambda applied at its head is applied
||| first. The one root function of a dictionary: a request's, a site's and
||| a field's roots are its result.
export
dictionaryRoot : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Root
dictionaryRoot t = do
  written <- solved t
  form <- case getFn written of
            Bind {} => lambdasApplied written
            _ => pure written
  rootOf start (sizeAccessible start) form []

||| What a type is at its root, as its normal form (`typeForm`) shows it:
||| the type constructor at its head when it takes more arguments than it
||| is applied to, which is a family's value (`Term`, `Either e`), and only
||| a family's, since a type of kind `Type` is a type constructor applied
||| in full; the writer's family there, applied or not, a marker that no
||| head was given for; or nothing (a lambda, a type, a stuck computation).
formRoot : Context -> ClosedTerm -> Root
formRoot ctx form = case getFnArgs form of
  (Ref _ (TyCon arity) n, args) =>
    if length args < arity then maybe Unrooted Rooted (definitionAddress ctx n) else Unrooted
  (Ref _ Bound n, _) => maybe Unrooted (uncurry Parameter) (Template.markerOf n)
  _ => Unrooted

-- A type read once: its template, as `templateOf` reads it, and its root,
-- off the same normal form.
typeReading : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (Template, Root)
typeReading t = do
  defs <- get Ctxt
  form <- typeForm t
  pure (!(formTemplate form), formRoot (gamma defs) form)

||| A static argument read once at its kind: its template (`templateOf`),
||| and its root, the definition that splits the node it is given to. A
||| dictionary's is the implementation that runs (`dictionaryRoot`). A
||| type's is the type constructor at its head, which only a family's value
||| has (`formRoot`), off the normal form its template reads; a request's
||| type parameter is a type or a family alike, so every type is read for
||| one. A form and a shape split nothing. The one reading of a site's
||| argument and of a request's, so the graph and the requests split a
||| definition by the same heads.
export
rooted : {auto c : Ref Ctxt Defs} -> State.Static -> ClosedTerm -> Core (Template, Root)
rooted AType t = typeReading t
rooted AFamily t = typeReading t
rooted AForm t = (, Unrooted) <$> templateOf AForm t
rooted AShape t = (, Unrooted) <$> templateOf AShape t
rooted ADictionary t = (,) <$> templateOf ADictionary t <*> dictionaryRoot t

||| A request's argument read as its key (`rooted`): its height and its
||| root.
export
closedHeight : {auto c : Ref Ctxt Defs} -> State.Static -> ClosedTerm -> Core (Nat, Root)
closedHeight k t = mapFst height <$> rooted k t
