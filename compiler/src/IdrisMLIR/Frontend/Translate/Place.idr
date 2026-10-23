-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Where a walk is in a writer's text: the step it took at each node on
||| the way down from the writer's root, one per constructor of the term or
||| of the case tree it went into, so that a place names one node of the
||| text the way the text's own constructors do. A walk that reads one
||| term more than one way (an argument as code and as a static value, a
||| leaf as code and as a member at a use) takes the step into it once per
||| way, each with its mode, so no two walks of one term meet at one place.
||| What a walk writes, each at its place, grows a tree in the text's shape
||| (`Grown`), a node per place it wrote at or below.
module IdrisMLIR.Frontend.Translate.Place

import Core.Name

import Data.Vect

%default total

||| How a walk reads a term it goes into: as code; as a static value; as a
||| member of its choice applied at a use; or as the computation a match
||| that finds a dictionary's field stuck computes where it reaches it.
public export
data WalkMode = CodeWalk | StaticWalk | UseWalk | ComputedWalk

||| One step down a writer's text, named by the constructor it goes into
||| a part of:
||| - an application's function, or its argument, read in a mode;
||| - a binder's type, a `let`'s value, read in a mode, or the scope a
|||   binder binds in;
||| - a `Delay`'s type or the value it suspends, what a `Force` forces, the
|||   type a lazy type holds, and the pattern an as pattern names;
||| - a metavariable's solution, entered where the metavariable stands;
||| - the normal form a dictionary or a polymorphic function applied
|||   settles to, which is walked where it is applied;
||| - a type constructor's constructor, by its name, whose type is the
|||   type's text about the values it builds;
||| - a definition's type or its case tree;
||| - the right-hand side of a match's alternative, by the alternative's
|||   position among the match's; a default's right-hand side read as one
|||   constructor it stands for, by that constructor; and a leaf's term,
|||   read in a mode.
public export
data PlaceStep
  = AppFunction
  | AppArgument WalkMode
  | BinderType
  | BinderValue WalkMode
  | BinderScope
  | DelayType
  | DelayValue
  | ForcedValue
  | LazyOf
  | PatternOfAs
  | MetaSolution
  | SettledForm
  | OfConstructor Name
  | DefinitionType
  | DefinitionTree
  | CaseAlternative Nat
  | Expansion Name
  | LeafTerm WalkMode

||| A place in a writer's text: the steps from the writer's root, the
||| outermost first, so a walk going down takes one more at the end.
public export
Place : Type
Place = SnocList PlaceStep

||| The place one step below another.
public export
into : PlaceStep -> Place -> Place
into s p = p :< s

-- The order the modes are declared in, which orders them.
modeRank : WalkMode -> Nat
modeRank CodeWalk = 0
modeRank StaticWalk = 1
modeRank UseWalk = 2
modeRank ComputedWalk = 3

export
Eq WalkMode where
  x == y = modeRank x == modeRank y

export
Ord WalkMode where
  compare x y = compare (modeRank x) (modeRank y)

-- The order the steps are declared in, which orders steps of different
-- constructors; two of one constructor are ordered by what they carry.
stepRank : PlaceStep -> Nat
stepRank AppFunction = 0
stepRank (AppArgument _) = 1
stepRank BinderType = 2
stepRank (BinderValue _) = 3
stepRank BinderScope = 4
stepRank DelayType = 5
stepRank DelayValue = 6
stepRank ForcedValue = 7
stepRank LazyOf = 8
stepRank PatternOfAs = 9
stepRank MetaSolution = 10
stepRank SettledForm = 11
stepRank (OfConstructor _) = 12
stepRank DefinitionType = 13
stepRank DefinitionTree = 14
stepRank (CaseAlternative _) = 15
stepRank (Expansion _) = 16
stepRank (LeafTerm _) = 17

export
Eq PlaceStep where
  AppArgument m == AppArgument m' = m == m'
  BinderValue m == BinderValue m' = m == m'
  OfConstructor n == OfConstructor n' = n == n'
  CaseAlternative k == CaseAlternative k' = k == k'
  Expansion n == Expansion n' = n == n'
  LeafTerm m == LeafTerm m' = m == m'
  x == y = stepRank x == stepRank y

export
Ord PlaceStep where
  compare (AppArgument m) (AppArgument m') = compare m m'
  compare (BinderValue m) (BinderValue m') = compare m m'
  compare (OfConstructor n) (OfConstructor n') = compare n n'
  compare (CaseAlternative k) (CaseAlternative k') = compare k k'
  compare (Expansion n) (Expansion n') = compare n n'
  compare (LeafTerm m) (LeafTerm m') = compare m m'
  compare x y = compare (stepRank x) (stepRank y)

||| Where in its writer's text a dictionary that closes over values is
||| bound: the place of the `let`, of the lambda applied to it, or of the
||| argument a match that finds it stuck computes, which binds it. No two
||| binders of a writer's text are at one place, so each such dictionary
||| has a place of its own, which holds what it closes over as one value
||| (`Heads.ByBinding`).
public export
record BoundPlace where
  constructor MkBoundPlace
  place : Place

export
Eq BoundPlace where
  x == y = x.place == y.place

export
Ord BoundPlace where
  compare x y = compare x.place y.place

||| What a walk wrote over a writer's text, in the text's shape: at a place,
||| what it wrote there, in the order it wrote it, and below the place each
||| step the walk took into a part of the text, in the steps' order, each
||| once, with what it wrote in that part. A part the walk wrote nothing in
||| takes no step, so the tree is as large as what was written.
public export
data Grown : Type -> Type where
  MkGrown : (here : List e) -> (below : List (PlaceStep, Grown e)) -> Grown e

||| Nothing written anywhere.
bare : Grown e
bare = MkGrown [] []

||| A tree with one more entry, written at the place the steps reach from
||| its root, the outermost step first, after what was written there.
grownAt : List PlaceStep -> e -> Grown e -> Grown e
grownAt [] x (MkGrown here below) = MkGrown (here ++ [x]) below
grownAt (s :: ss) x (MkGrown here below) = MkGrown here (into below)
  where
    into : List (PlaceStep, Grown e) -> List (PlaceStep, Grown e)
    into [] = [(s, grownAt ss x bare)]
    into all@((s', t) :: rest) = case compare s s' of
      LT => (s, grownAt ss x bare) :: all
      EQ => (s', grownAt ss x t) :: rest
      GT => (s', t) :: into rest

||| Entries, each written at its place, in the order given.
export
grownFrom : List (Place, e) -> Grown e
grownFrom = foldl (\t, (p, x) => grownAt (p <>> []) x t) bare

mutual
  -- What a tree holds, in the text's order (at each place what was
  -- written there, then below it, step by step), before `rest`.
  entriesOnto : Grown e -> List e -> List e
  entriesOnto (MkGrown here below) rest = here ++ belowOnto below rest

  belowOnto : List (PlaceStep, Grown e) -> List e -> List e
  belowOnto [] rest = rest
  belowOnto ((_, t) :: more) rest = entriesOnto t (belowOnto more rest)

||| What a tree holds, in the text's order: at each place what was written
||| there, then below it, step by step.
export
entriesOf : Grown e -> List e
entriesOf t = entriesOnto t []

mutual
  ||| How many entries a tree holds.
  public export
  entryCount : Grown e -> Nat
  entryCount (MkGrown here below) = length here + sizeBelow below

  public export
  sizeBelow : List (PlaceStep, Grown e) -> Nat
  sizeBelow [] = 0
  sizeBelow ((_, t) :: more) = entryCount t + sizeBelow more

mutual
  ||| What a tree holds, in the text's order, as many as it holds.
  export
  entryVect : (t : Grown e) -> Vect (entryCount t) e
  entryVect (MkGrown here below) = Vect.fromList here ++ belowVect below

  belowVect : (bs : List (PlaceStep, Grown e)) -> Vect (sizeBelow bs) e
  belowVect [] = []
  belowVect ((_, t) :: more) = entryVect t ++ belowVect more

-- A list's entries replaced, in order, by as many.
relabelled : (xs : List a) -> Vect (length xs) b -> List b
relabelled [] [] = []
relabelled (_ :: xs) (y :: ys) = y :: relabelled xs ys

mutual
  ||| A tree with its entries replaced, in the text's order, by as many: the
  ||| same places, written alike.
  export
  relabel : (t : Grown a) -> Vect (entryCount t) b -> Grown b
  relabel (MkGrown here below) ys =
    let (hs, bs) = splitAt (length here) ys in MkGrown (relabelled here hs) (relabelBelow below bs)

  relabelBelow : (bs : List (PlaceStep, Grown a)) -> Vect (sizeBelow bs) b -> List (PlaceStep, Grown b)
  relabelBelow [] [] = []
  relabelBelow ((s, t) :: more) ys = let (ts, ms) = splitAt (entryCount t) ys in (s, relabel t ts) :: relabelBelow more ms
