-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Function bodies: the algebra of the fold that writes a term, its
||| matches as a region per case, its join points as `idr.join` and
||| `idr.loop`, its lambdas and delays as functions of their own
||| (Emit.Closures) and its arrays as the array ops (Emit.Tensors).
||| Quantities are read off the binders, which the translation made right;
||| nothing here counts a use.
module IdrisMLIR.Emit.Bodies

import IdrisMLIR.Dialect.Bufferization as Bufferization
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.UB as UB
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Closures
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Operations
import IdrisMLIR.Emit.Tensors
import IdrisMLIR.Emit.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Spec.Control.Joins
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Functions.Tail
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.Fin
import Data.List
import Data.List.Quantifiers
import Data.List1
import Data.Maybe
import Data.SnocList
import Data.String
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Scopes
------------------------------------------------------------------------------

%prefix_record_projections off

||| What a jump to a join point needs of it: the token that designates it,
||| its parameters, at the types its region binds them at, and the depth of
||| the telescope where its op stands, after which its region binds its
||| erased binders.
public export
record Reach (k : Nat) where
  constructor MkReach
  token : Value
  params : Vect k Binder
  depth : Nat

%prefix_record_projections on

||| The scope a term is written in: what each of its variables stands for;
||| the sorts of the erased binders its index terms' levels name, the
||| function's index parameters then each enclosing region's binders, in
||| order; and what each join point its tails may jump to is.
public export
record Scope (js : List Nat) (nv : Nat) where
  constructor MkScope
  vars : Fin nv -> InScope
  telescope : List Sort
  targets : All Reach js

||| What the fold makes of a term in scope `nv`: given its scope and what
||| its context wants, it appends the term's operations and returns its
||| value, or `Nothing` when the term never returns (its region has then
||| ended in a terminator).
public export
Em : List Nat -> Nat -> Type
Em js nv = Scope js nv -> Wanted -> E (Maybe Val)

||| A scope under a binder of `k` variables, standing for `vs`.
bind : {k : Nat} -> Vect k InScope -> Scope js nv -> Scope js (Under k nv)
bind vs sc = { vars := \v => case splitUnder {k} v of
                              Left i => index i vs
                              Right x => sc.vars x } sc

||| The scope of a position that is no tail of the term: the same values,
||| and no join point, since a jump from there would skip what its value is
||| for.
offTail : Scope js nv -> Scope [] nv
offTail sc = MkScope sc.vars sc.telescope []

||| The scope of a case region: its constructor's binders appended to the
||| telescope, at the next levels.
binding : List Sort -> Scope js nv -> Scope js nv
binding sorts sc = { telescope := sc.telescope ++ sorts } sc

||| The levels below `d`, each as the term naming it.
levelsBelow : Nat -> List ITerm
levelsBelow d = map IVar (take d [0 .. d])

||| The levels of a scope's telescope, each as the term naming it: what a
||| function lifted from the scope is given for its index parameters.
levels : List Sort -> List ITerm
levels ss = levelsBelow (length ss)

------------------------------------------------------------------------------
-- Operands
------------------------------------------------------------------------------

||| The value a variable stands for; the world for Idris's world.
standing : InScope -> Val
standing (Whole v) = v
standing World = worldVal

||| The values of the module among `vs`: every one but the world's.
present : List Val -> List Val
present = filter (\v => case v.type of
                          WorldT => False
                          _ => True)

||| What a layer's operands give, left to right: the next is written only
||| when the one before it returns, so that nothing follows a value that
||| never does (its region has ended in a terminator).
record Operands a where
  constructor MkOperands
  written : E (Maybe a)

Functor Operands where
  map f (MkOperands x) = MkOperands (map (map f) x)

Applicative Operands where
  pure x = MkOperands (pure (Just x))
  MkOperands f <*> MkOperands x = MkOperands $ do
    Just g <- f
      | Nothing => pure Nothing
    map g <$> x

||| A subterm's value where a slot takes it: checked against the type the
||| slot expects, if it says one, and used as the slot binds it, many times
||| where it says nothing; bound to no variable. An operand is no tail.
operand1 : Index -> Loc -> Scope [] nv -> Maybe Binder -> Sub Em [] nv -> Operands Val
operand1 ix l sc slot a = MkOperands $ do
  let uses = maybe Many (.quantity) slot
  Just v <- a.result sc (consumedAt (typeOf <$> slot) uses)
    | Nothing => pure Nothing
  Just <$> coerce ix l uses !(fit ix l (typeOf <$> slot) v)

||| A layer's operands, each in its slot, left to right; `Nothing` once one
||| never returns.
operands : Traversable t => Index -> Loc -> Scope [] nv -> t (Maybe Binder, Sub Em [] nv) -> E (Maybe (t Val))
operands ix l sc xs = (traverse (\(slot, a) => operand1 ix l sc slot a) xs).written

||| Operands that no slot types: each at its own type, used many times.
unslotted : Functor t => t (Sub Em [] nv) -> t (Maybe Binder, Sub Em [] nv)
unslotted = map (\a => (Nothing, a))

||| The slot of an array an operation takes: the type the operation holds
||| of it, used many times.
arraySlot : ArrayType r -> Maybe Binder
arraySlot a = Just (MkBinder Many (arrayTy a))

||| An array operation's operands, each in its slot: an array at the type
||| the operation holds of it, a natural or an element at its own.
arraySlots : TensorOp t -> TensorOp (Maybe Binder, t)
arraySlots (Extent a j x) = Extent a j (arraySlot a, x)
arraySlots (Extract a rt x cs) = Extract a rt (arraySlot a, x) (map (\c => (Nothing, c)) cs)
arraySlots (Insert a rt x v cs) = Insert a rt (arraySlot a, x) (Nothing, v) (map (\c => (Nothing, c)) cs)
arraySlots (Take a ra j k x) = Take a ra j (Nothing, k) (arraySlot a, x)
arraySlots (Drop a ra j k x) = Drop a ra j (Nothing, k) (arraySlot a, x)
arraySlots (Concat a b ra j x y) = Concat a b ra j (arraySlot a, x) (arraySlot b, y)
arraySlots (Transpose a rt j x) = Transpose a rt j (arraySlot a, x)
arraySlots (Reshape a rt x es) = Reshape a rt (arraySlot a, x) (map (\e => (Nothing, e)) es)

||| A constructor's fields, each in its slot (its type with the
||| constructor's binders given), left to right.
fields : Index -> Loc -> Scope [] nv -> Vect k Binder -> Vect k (Sub Em [] nv) -> Operands (Vect k Val)
fields ix l sc [] [] = pure []
fields ix l sc (b :: bs) (a :: as) = (::) <$> operand1 ix l sc (Just b) a <*> fields ix l sc bs as

||| A term's value where an operand takes it as `w` asks: the term is
||| written for `w`, and a value it gives at other uses (a variable's, a
||| call's result) is cast to the uses `w` takes it at, so the uses asked
||| are the uses given.
consumed : Index -> Loc -> Wanted -> (Wanted -> E (Maybe Val)) -> E (Maybe Val)
consumed ix l w term = term w >>= traverse (coerce ix l w.uses)

||| A function's body, its value of type `t` as the function returns it
||| (`returned`), used once: the return is its one use, handing the caller
||| the one reference it gives. The body is written for that type and those
||| uses, so a call at its tail gives what its slot takes and nothing stands
||| between the call and the return; a value of a more static type is cast
||| before the return, and one used many times cast into its one use.
export
returning : Index -> Loc -> Ty -> (Wanted -> E (Maybe Val)) -> E (Maybe Val)
returning ix l t body =
  let r = returned t in
  body (consumedAt (Just r) Once) >>= traverse (\v => fit ix l (Just r) v >>= coerce ix l Once)

||| The values a region or a function gives: none for the world.
given : Index -> Maybe Val -> List Value
given ix Nothing = []
given ix (Just v) = map (operand ix) (present [v])

------------------------------------------------------------------------------
-- Matches
------------------------------------------------------------------------------

||| An arm of a match: the arguments of its region, its operations, and its
||| value, which it yields.
record Arm where
  constructor MkArm
  arguments : List Argument
  result : Maybe Val
  statements : List Statement

||| A case of a match: its constructor's tag, or its literal's place among
||| the keys, and its arm. The sorts a data case binds are its
||| constructor's, which the op reads off the family; nothing writes them.
record Case where
  constructor MkCase
  tag : Nat
  arm : Arm

||| The regions of a match's cases, in order: each arm's arguments and its
||| statements.
caseRegions : List Case -> List MLIR.Region
caseRegions = map (\c => MkRegion c.arm.arguments c.arm.statements)

||| What a region of a literal match binds, and its argument: the scrutinee
||| at its own type, grade and hold, as the match moves it into every
||| region. What a region knows of it, its key or none of the keys, is the
||| match's to say, not the type's.
rebound : Index -> Loc -> Val -> E (Val, Argument)
rebound ix l scrut = do
  n <- fresh
  let r = { name := Bound n 0 } scrut
  pure (r, MkArgument (operand ix r) (At l))

||| A field's position as `idr.data.field` holds it.
fieldIndex : Nat -> MlirAttr
fieldIndex i = IntegerAttr (natToInteger i) (OfWidth 64)

||| The yield that ends a region with its value; a region that never
||| returns has ended in a terminator already.
yielding : Index -> Loc -> Maybe Val -> List Statement
yielding ix l Nothing = []
yielding ix l (Just v) = [MkStatement Nothing (Idr.yieldOp (given ix (Just v))) (At l)]

||| A match from its arms, with the builder of its op over its cases, its
||| default region (none when the cases are exhaustive) and its results:
||| results when an arm yields, and none when no arm returns. The arms join
||| at the type the context expects, else the first arm's that returns, and
||| at the uses it takes the match's value at, which each arm was written
||| for: an arm's value at other index terms, or an array of another static
||| shape, is cast to the type, and one at other uses to those uses.
match : Index -> Loc -> Wanted -> (List Case -> MLIR.Region -> List MlirType -> Op)
     -> List Case -> Maybe Arm -> E (Maybe Val)
match ix l w build cases fallback =
  let arms = map (.arm) cases ++ toList fallback in
  case w.type <|> map (.type) (head' (mapMaybe (.result) arms)) of
    Just t => if all (\a => isNothing a.result) arms then never else do
      cs <- traverse (\c => (\r => { arm.statements := r } c) <$> close t c.arm) cases
      d <- maybe (pure NoBlocks) (\a => MkRegion a.arguments <$> close t a) fallback
      Just <$> valueAt {binder = w.binder} ix l w.uses t (\r => build cs d [r])
    Nothing => never
  where
    close : Ty -> Arm -> E (List Statement)
    close t a = do
      (v, cast) <- collect (traverse (\r => fit ix l (Just t) r >>= coerce ix l w.uses) a.result)
      pure (a.statements ++ cast ++ yielding ix l v)
    -- A match whose every arm ends in a terminator has no results, and
    -- nothing after it runs: its region ends in `ub.unreachable`.
    never : E (Maybe Val)
    never = do
      placed (At l) (build cases (maybe NoBlocks (\a => MkRegion a.arguments a.statements) fallback) [])
      statement l UB.unreachableOp
      pure Nothing

mutual
  ||| Whether a term names one of the `k` variables from `from` of its
  ||| scope, the fields an alternative binds (from 0, and further out under
  ||| each binder inside): a field the alternative names is read, one it
  ||| never names is not, so a field of a value used once is read at most
  ||| once. The problem has both cases (`xs@(_ :: _)` names the value and
  ||| no field); the quantities stay the binders'.
  names : (from, k : Nat) -> TermAt js n -> Bool
  names from k (Var _ x) = namesVar from k x
  names from k (Literal _ _) = False
  names from k (PrimApp _ _ _ as) = vectNames from k as
  names from k (Effect _ _ _ as world _) = vectNames from k as || names from k world
  names from k (Call _ _ _ _ as) = vectNames from k as
  names from k (ConApp _ _ _ as) = vectNames from k as
  names from k (Let _ _ _ v b) = names from k v || names (S from) k b
  names from k (Case _ _ x arms) = namesVar from k x || armsName from k arms
  names from k (CaseLit _ x arms) = namesVar from k x || litArmsName from k arms
  names from k (CaseNat _ x arms) = namesVar from k x || natArmsName from k arms
  names from k (Lam _ _ _ _ body) = names (S from) k body
  names from k (App _ _ _ f x) = names from k f || names from k x
  names from k (Suspend _ _ body) = names from k body
  names from k (Resume _ _ e) = names from k e
  names from k (Unreachable _) = False
  names from k (Assume _ _ _ body) = names from k body
  names from k (Crash _ _) = False
  names from k (CrashWith _ m) = names from k m
  names from k (NewWorld _) = False
  names from k (Tensor _ op) = opNames from k op
  names from k (Tabulate {k = j} _ _ es body) = vectNames from k es || names (j + from) k body
  names from k (TabulateIO {k = j} _ _ es w body _ _) =
    vectNames from k es || names from k w || names (S j + from) k body
  names from k (Reduce _ _ _ _ _ _ _ z x body) = names from k z || names from k x || names (2 + from) k body
  names from k (Tie _ _ x ds) = names from k x || statedNames from k ds
  names from k (ReadBack _ _ x cs body) = names from k x || anyNames from k cs || names (2 + from) k body
  names from k (ExtentsBack {k = j} _ x body) = names from k x || names (S j + from) k body
  names from k (Join _ _ targets body) = targetsName from k targets || names from k body
  names from k (Jump _ _ _ as) = vectNames from k as

  namesVar : (from, k : Nat) -> Fin n -> Bool
  namesVar from k x = from <= finToNat x && finToNat x < from + k

  -- Each container of subterms is walked by its own clauses, every one
  -- taken apart where it is matched, so each term the walk reaches is a
  -- part of the one it started from.
  anyNames : (from, k : Nat) -> List (TermAt js n) -> Bool
  anyNames from k [] = False
  anyNames from k (t :: ts) = names from k t || anyNames from k ts

  vectNames : (from, k : Nat) -> Vect j (TermAt js n) -> Bool
  vectNames from k [] = False
  vectNames from k (t :: ts) = names from k t || vectNames from k ts

  opNames : (from, k : Nat) -> TensorOp (TermAt js n) -> Bool
  opNames from k (Extent _ _ x) = names from k x
  opNames from k (Extract _ _ x cs) = names from k x || anyNames from k cs
  opNames from k (Insert _ _ x v cs) = names from k x || names from k v || anyNames from k cs
  opNames from k (Take _ _ _ c x) = names from k c || names from k x
  opNames from k (Drop _ _ _ c x) = names from k c || names from k x
  opNames from k (Concat _ _ _ _ x y) = names from k x || names from k y
  opNames from k (Transpose _ _ _ x) = names from k x
  opNames from k (Reshape _ _ x es) = names from k x || anyNames from k es

  statedNames : (from, k : Nat) -> List (Nat, Stated (TermAt js n)) -> Bool
  statedNames from k [] = False
  statedNames from k ((_, SameAs t) :: ds) = names from k t || statedNames from k ds
  statedNames from k ((_, Natural t) :: ds) = names from k t || statedNames from k ds

  altNames : (from, k : Nat) -> AltAt js n -> Bool
  altNames from k (MkAlt {k = j} _ _ body) = names (j + from) k body

  altsNames : (from, k : Nat) -> List (AltAt js n) -> Bool
  altsNames from k [] = False
  altsNames from k (alt :: alts) = altNames from k alt || altsNames from k alts

  armsName : (from, k : Nat) -> CaseArmsOf (AltAt js n) (TermAt js n) -> Bool
  armsName from k (Defaulted alts d) = altsNames from k alts || names from k d
  armsName from k (Exhaustive (alt ::: alts)) = altNames from k alt || altsNames from k alts

  litsName : (from, k : Nat) -> List (kt, TermAt js n) -> Bool
  litsName from k [] = False
  litsName from k ((_, t) :: rest) = names from k t || litsName from k rest

  keyedName : (from, k : Nat) -> LitArmsOf kt (TermAt js n) -> Bool
  keyedName from k (LitDefault ((_, t) ::: alts) d) = names from k t || litsName from k alts || names from k d
  keyedName from k (LitNoDefault ((_, t) ::: alts)) = names from k t || litsName from k alts

  litArmsName : (from, k : Nat) -> LitMatch (TermAt js n) -> Bool
  litArmsName from k (OnlyDefault d) = names from k d
  litArmsName from k (OnInts _ arms) = keyedName from k arms
  litArmsName from k (OnChars arms) = keyedName from k arms
  litArmsName from k (OnStrings arms) = keyedName from k arms
  litArmsName from k (OnBigs arms) = keyedName from k arms

  natArmsName : (from, k : Nat) -> NatArmsOf (TermAt js n) (TermAt js (Under 1 n)) -> Bool
  natArmsName from k (OnlyZero z) = names from k z
  natArmsName from k (OnlySucc _ s) = names (S from) k s
  natArmsName from k (Both z _ s) = names from k z || names (S from) k s

  targetsName : (from, k : Nat) -> All (Target s n) ts -> Bool
  targetsName from k [] = False
  targetsName from k (MkTarget {k = j} _ _ _ _ _ body :: rest) = names (j + from) k body || targetsName from k rest

||| The scope inside a region of a match on the variable `x`: the variable
||| that named the scrutinee names the value the region binds, refined to
||| the region's constructors, so a field is a read of a value whose type
||| fixes its constructor, and a constructor is never rebuilt from fields.
refining : Fin nv -> Val -> Scope js nv -> Scope js nv
refining x r sc = { vars := \y => if y == x then Whole r else sc.vars y } sc

||| The fields of constructor `c` in a case at depth `d`: their types in
||| scope (`fieldsAt`, the reading the translation types a field's variable
||| by), each bound at the scrutinee's uses times its own: a field of a
||| value used many times is used many times.
fieldBinders : Nat -> Uses -> Con k -> Vect k Binder
fieldBinders d u c = map (\b => MkBinder (times u b.quantity) b.type) (fieldsAt d c)

||| A case's fields as the region holds them, from its refined value `r`:
||| each field the alternative names a read of `r` (`idr.data.field`), at
||| the value's uses times the field's, so a value used once is read once
||| per field; a field it never names is never read, and the world is no
||| value of the module. `named i` says whether the alternative names field
||| `i`; `reaches` how far `r`'s claim reaches into each (`fieldReaches`).
caseFields : Index -> Loc -> Val -> (named : Nat -> Bool) -> Vect k Binder -> Vect k FieldReach -> E (Vect k InScope)
caseFields ix l r named bs reaches = fieldsFrom 0 bs reaches
  where
    -- A field holds what the value it is read from holds, claiming what
    -- the value's claim reaches into it at the uses the read gives it: the
    -- grade's read, which the read's own inference gives.
    fieldHold : Binder -> FieldReach -> Hold
    fieldHold b reach = readHold reach b.quantity r.hold
    read : Nat -> Binder -> FieldReach -> E InScope
    read i (MkBinder _ WorldT) _ = pure World
    -- An array field is held as its buffer; its value is the tensor of it,
    -- restricted, so the buffer is no one else's while the tensor lives,
    -- and never written in place here: what may write it is decided once
    -- exclusivity is. The buffer enters the tensor at its bare grade, as
    -- upstream's op takes it, and the tensor is used as the field is.
    read i b@(MkBinder q t@(TensorT _ _)) reach = do
      let carrier = fieldType ix t
          graded = case (q, fieldHold b reach) of
                     (Many, Hold.Counted None) => carrier
                     (u, h) => Idr (GradedType u (Just h) carrier)
      buf <- mlirValue l graded (Idr.dataFieldOp (fieldIndex i) (operand ix r) [])
      bare <- case q of
                Many => pure buf
                Once => mlirValue l carrier (Idr.linCastOp buf [])
      v <- mlirValue l (mlirType ix t) (Bufferization.toTensorOp {restrict = True} bare)
      Whole <$> coerce ix l q (val v.name t Many made)
    read i b reach = do
      v <- mlirValue l (gradedType ix b.quantity (fieldHold b reach) b.type) (Idr.dataFieldOp (fieldIndex i) (operand ix r) [])
      pure (Whole (val v.name b.type b.quantity (fieldHold b reach)))
    -- A field no name of the alternative reads: never looked at.
    field : Nat -> Binder -> FieldReach -> E InScope
    field i b reach = if named i then read i b reach else pure World
    -- The fields from position `i` on, each numbered as it is reached, so
    -- the count of them is never needed at run time.
    fieldsFrom : Nat -> Vect j Binder -> Vect j FieldReach -> E (Vect j InScope)
    fieldsFrom i [] [] = pure []
    fieldsFrom i (b :: rest) (reach :: further) = (::) <$> field i b reach <*> fieldsFrom (S i) rest further

||| Starts a function: its own SSA numbers and operations.
export
inFunction : E a -> E (a, List Statement)
inFunction act = do
  st <- get
  put ({ next := 0, ops := [<] } st)
  x <- act
  inner <- gets (.ops)
  modify { next := st.next, ops := st.ops }
  pure (x, inner <>> [])

||| The end of a function's body: its value, returned; a body that never
||| returns has ended in a terminator already.
export
epilogue : Index -> Loc -> Maybe Val -> List Statement -> E (List Statement)
epilogue ix l (Just v) ops = pure (ops ++ [MkStatement Nothing (Idr.returnOp (given ix (Just v))) (At l)])
epilogue ix l Nothing ops = pure ops

||| A closure or a suspension of a function, made by `build` at type `t`
||| over `captures`, the variable `binder` bound to it. One that holds a
||| linear value is used once: the dialect gives a closure's type the
||| quantity of its captures, which its op's result type states.
holding : Index -> Loc -> Maybe Binding -> Ty -> List Value -> (MlirType -> Op) -> E Val
holding ix l binder t captures build =
  if any linearType captures
    then do
      r <- mlirValueAt (madeAt binder l Once) (gradedType ix Once made t) build
      pure (val r.name t Once made)
    else value {binder} ix l t build
  where
    linearType : Value -> Bool
    linearType v = case v.type of
      Idr (GradedType Once _ _) => True
      _ => False

------------------------------------------------------------------------------
-- Join points
------------------------------------------------------------------------------

||| The tokens of a join op, one per join point, each a region's argument,
||| and what a jump to each needs, its op's telescope `depth` deep.
reaching : Loc -> Nat -> All (TargetF f s nv) ts -> E (All Reach ts, List Argument)
reaching l depth [] = pure ([], [])
reaching l depth (MkTargetF _ _ _ _ params _ :: rest) = do
  n <- fresh
  let token = MkValue (Bound n 0) MlirType.TokenType
  (reaches, args) <- reaching l depth rest
  pure (MkReach token params depth :: reaches, MkArgument token (At l) :: args)

||| A join region's parameters as its arguments, each named as the program
||| names it; the world binds no value.
parametersOf : Index -> Loc -> Vect k Shown -> Vect k Binder -> E (Vect k InScope, List Argument)
parametersOf ix l [] [] = pure ([], [])
parametersOf ix l (_ :: rest) (MkBinder _ WorldT :: bs) = do
  (vs, args) <- parametersOf ix l rest bs
  pure (World :: vs, args)
parametersOf ix l (name :: rest) (b :: bs) = do
  (v, o) <- freshVal ix b.type b.quantity
  st <- get
  put ({ nextBinder $= S } st)
  (vs, args) <- parametersOf ix l rest bs
  pure (Whole v :: vs, MkArgument o (Binder name (Spanned l) st.ownerSymbol st.nextBinder) :: args)

||| What `act` writes as code of a local definition: a crash in it names
||| that definition as the one it is in, as it would in its own function.
inCodeOf : CodeOf -> E a -> E a
inCodeOf Surrounding act = act
inCodeOf (LocalCode d) act = do
  saved <- gets (.definition)
  modify { definition := d }
  x <- act
  modify { definition := saved }
  pure x

||| The sorts a join region binds.
sortsOf : TargetF f s nv k -> List Sort
sortsOf (MkTargetF _ _ sorts _ _ _) = sorts

||| What begins each join region of an `idr.loop`, a region that may run
||| again: `idr.may_loop`, the divergence of a region repeated for ever,
||| unless Idris proved that every loop through the function stays in the
||| one component it names, whose calls decrease.
repeats : Loc -> E ()
repeats l = do
  t <- gets (.termination)
  case t of
    Terminates _ => pure ()
    MayDiverge => statement l Idr.mayLoopOp

||| A join op, by its member's builder: its body, a region entered once,
||| which begins with one token per join point and sees them after those
||| around the op; and a region per join point, which gets its tokens (a
||| loop's every region begins with them; a join's begin with none) and
||| sees the join points its member lets it see (`regionTokens`), begins
||| with what its member says of a region that runs again (`begins`: a
||| join's none, a loop's `repeats`), binds its erased binders at the next
||| levels and its parameters as its arguments, and is code of the
||| definition it is. They rejoin at the op's results as a match's cases
||| do.
joined : {0 js, s, ts : List Nat} -> {0 nv : Nat} ->
         Index -> Loc -> Scope js nv -> Wanted -> (MlirAttr -> MLIR.Region -> List MLIR.Region -> List MlirType -> Op)
      -> (regionTokens : E (All Reach s, List Argument)) -> (begins : Loc -> E ())
      -> All (TargetF (Sub Em) s nv) ts -> Sub Em (js ++ ts) nv -> E (Maybe Val)
joined ix l sc w member regionTokens begins targets body = do
  (own, tokens) <- reaching l (length sc.telescope) targets
  (res, ops) <- collect (body.result (MkScope sc.vars sc.telescope (sc.targets ++ own))
                                     ({ binder := Nothing } w))
  regions <- regionsOf targets
  let binders = ArrayAttr (forget (mapProperty {q = const MlirAttr} (\t => Idr (IndexBindersAttr (map (sortOf ix) (sortsOf t))))
                                               targets))
  match ix l w (\cs, d, rs => member binders d (caseRegions cs) rs) regions (Just (MkArm tokens res ops))
  where
    region : TargetF (Sub Em) s nv k -> E Case
    region (MkTargetF {k} tl code sorts given params rbody) = do
      (reach, tokens) <- regionTokens
      (vals, args) <- parametersOf ix tl given params
      (res, ops) <- collect $ do
        begins tl
        inCodeOf code $
          rbody.result (bind vals (MkScope sc.vars (sc.telescope ++ sorts) reach)) ({ binder := Nothing } w)
      pure (MkCase 0 (MkArm (tokens ++ args) res ops))

    regionsOf : All (TargetF (Sub Em) s nv) ts' -> E (List Case)
    regionsOf [] = pure []
    regionsOf (t :: rest) = (::) <$> region t <*> regionsOf rest

------------------------------------------------------------------------------
-- The algebra
------------------------------------------------------------------------------

||| The algebra: one layer of `TermAt` to its emitter. A layer whose value
||| is a subterm's (a `let`'s body, a match's arms, a join op's regions)
||| passes what its context wants on to it; every other subterm is an
||| operand or a region's, bound to no variable, in a scope that sees no
||| join point.
export
alg : {0 js : List Nat} -> {0 nv : Nat} -> Index -> TermF (Sub Em) js nv -> Em js nv
alg ix (VarF l x) sc w = pure (Just (standing (sc.vars x)))
alg ix (LiteralF l x) sc w = Just <$> literal {binder = w.binder} ix l x
-- The op a primitive makes names the library definition the registry
-- lowered to it, where it lowered one, as a function's names its own.
alg ix (PrimAppF l p stands as) sc w = do
  Just vs <- operands ix l (offTail sc) (zip (map (map (MkBinder Many)) (slots p)) as)
    | Nothing => pure Nothing
  Just <$> prim w.binder stands ix l p vs
-- An IO primitive takes its operands at their own types, then the world,
-- which is no value of the module.
alg ix (EffectF l p gives as world res) sc w = do
  Just vs <- operands ix l (offTail sc) (unslotted as)
    | Nothing => pure Nothing
  Just _ <- world.result (offTail sc) (expecting (Just WorldT))
    | Nothing => pure Nothing
  effect w.binder ix l p gives vs res
-- A call holds its callee's signature, one argument per binder: it passes
-- its callee's index parameters their terms here and its arguments at the
-- callee's binders with those terms substituted, so its operand and result
-- types are the callee's signature at the call, its result as the callee
-- returns it (`returned`) and used once, the type and uses every tail of
-- its caller is written for, so a call at a tail is never cast. A slot
-- that is no tail and that Idris's type gives a static axis (a `let`'s
-- binder, a static input of another call) takes the result cast to it, and
-- one that uses it many times takes it cast out of its one use, after the
-- call and never between the call and a return. Where it stands in its
-- function is decided once, by the one definition of tail position, when
-- the program is first order: the frontend writes every call `nontail`,
-- which promises nothing, and the source states no other. A call the
-- registry lowered a library definition's call to names it.
alg ix (CallF l f stands is as) sc w = do
  let slots = map (\b => Just (MkBinder b.quantity (substTy is b.type))) f.params
  Just vs <- operands ix l (offTail sc) (zip slots as)
    | Nothing => pure Nothing
  let rt = returned (substTy is f.result)
      args = map (operand ix) (present (toList vs))
      indexArgs = Just (indexArgsOf ix is)
      callee = SymbolRefAttr (MkSymbolRef f.symbol [])
  -- A call gives what its result type is: Idris's world, which is no value
  -- of the module, or one value.
  case rt of
    WorldT => do
      placed (madeAtPlace Nothing (placeOf stands l) Many) (Idr.callOp {index_args' = indexArgs} callee NonTail args [])
      pure (Just worldVal)
    _ => Just <$> fitted {binder = w.binder} {stands} ix l Once w.type rt (\t => Idr.callOp {index_args' = indexArgs} callee NonTail args [t])
-- A constructor's fields are checked at their types with its binders
-- given.
alg ix (ConAppF l c bs as) sc w = do
  Just vs <- (fields ix l (offTail sc) (map (\b => { type $= substTy bs } b) c.fields) as).written
    | Nothing => pure Nothing
  Just <$> con {binder = w.binder} ix l w.uses c bs vs
-- A `let` binds an SSA value at its binder's type and quantity, as Idris
-- checked them; the op that makes it as the variable holds it stands at
-- the variable's name.
alg ix (LetF l name b v body) sc w = case b of
  Checked (MkBinder _ WorldT) => do
    Just _ <- v.result (offTail sc) (expecting (Just WorldT))
      | Nothing => pure Nothing
    body.result (bind [World] sc) w
  Checked (MkBinder q t) => bound q (Just t)
  OfValue q => bound q Nothing
  where
    bound : Uses -> Maybe Ty -> E (Maybe Val)
    bound q t = do
      b <- binding name q
      Just x <- v.result (offTail sc) (MkWanted t (Just b) q)
        | Nothing => pure Nothing
      case x.type of
        WorldT => body.result (bind [World] sc) w
        _ => do
          x' <- coerce {binder = Just b} ix l q !(fit ix l t x)
          body.result (bind [Whole x'] sc) w
-- A match takes its scrutinee as it is held. Each case binds the scrutinee
-- refined to its constructor, and its constructor's binders at the next
-- levels; its fields are reads of the refined value, or, for a scrutinee
-- used once whose alternative names a field, the value taken apart. The
-- default binds the scrutinee refined to the constructors no case takes.
-- Inside every region the variable that named the scrutinee names the
-- value the region binds.
alg ix (CaseF l f x arms) sc w = do
  let scrut = standing (sc.vars x)
  (cases, fallback) <- the (E (List Case, Maybe Arm)) $ case arms of
    Defaulted alts d => do
      cs <- traverse (alternative scrut) alts
      pure (cs, Just !(defaultArm scrut f (map (.tag) cs) d))
    Exhaustive alts => do
      cs <- traverse (alternative scrut) (forget alts)
      pure (cs, Nothing)
  -- The frontend forwards no value and states no lifetime: the scoped
  -- values a match makes are decided once lifetimes are, which sets its
  -- `outers`.
  match ix l w (\cs, d, ts => Idr.dataMatchOp (DenseI32ArrayAttr (map (.tag) cs)) (operand ix scrut) [] [] d (caseRegions cs) ts)
        cases fallback
  where
    -- The value a region binds: the scrutinee refined to the constructors
    -- given, its argument at the region's start.
    refinedArg : Val -> List1 Nat -> E (Val, Argument)
    refinedArg scrut tags = do
      n <- fresh
      let r = MkVal (Bound n 0) scrut.type scrut.uses scrut.hold (OneOf tags)
      pure (r, MkArgument (operand ix r) (At l))
    alternative : Val -> AltF (Sub Em) js nv -> E Case
    alternative scrut (MkAltF {k} c fs body) = do
      let d = length sc.telescope
      (r, arg) <- refinedArg scrut (c.tag ::: [])
      let bs = fieldBinders d scrut.uses c
          inner = refining x r (binding (map (.sort) c.binders) sc)
      (res, ops) <- collect $ do
        vals <- caseFields ix l r (\i => names i 1 body.term) bs (fieldReaches ix c)
        body.result (bind vals inner) ({ binder := Nothing } w)
      pure (MkCase c.tag (MkArm [arg] res ops))
    -- The default binds the scrutinee refined to the constructors of its
    -- family `f` no case takes; none is left only when Idris proved the
    -- cases cover it, which is `Exhaustive`, so a default here has at
    -- least one.
    defaultArm : Val -> FamilyId -> List Nat -> Sub Em js nv -> E Arm
    defaultArm scrut f taken d = do
      (back, arg) <- case untaken ix f taken of
        t :: ts => refinedArg scrut (t ::: ts)
        [] => do
          (v, a) <- freshVal ix scrut.type scrut.uses
          pure (v, MkArgument a (At l))
      (res, ops) <- collect (d.result (refining x back sc) ({ binder := Nothing } w))
      pure (MkArm [arg] res ops)
-- A match on literals has no exhaustive form: when Idris proved the
-- default impossible, the last possible alternative stands for it, and a
-- match of one is that alternative. Each key is as `idr.lit.match` holds
-- it, by the match's one kind: an integer at its type's width, a `Char` as
-- its code point, a string, a big integer or a natural as itself. Every
-- region binds the scrutinee, and the variable that named it names the
-- binding there, as in a data match: in a case the binding is its
-- literal, and the default's is refined to the complement of the keys, so
-- what a case proved of it (a divisor matched against `0`) stays known
-- where the default reads it.
alg ix (CaseLitF l x arms) sc w = case arms of
  OnlyDefault d => d.result sc w
  OnInts t keyed => literalsOf (\n => litAttr (LInt t n)) keyed
  OnChars keyed => literalsOf (\c => litAttr (LChar c)) keyed
  OnStrings keyed => literalsOf (\s => litAttr (LStr s)) keyed
  OnBigs keyed => literalsOf (\n => litAttr (LBig n)) keyed
  where
    literals : (kt -> MlirAttr) -> List (kt, Sub Em js nv) -> Sub Em js nv -> E (Maybe Val)
    literals key [] d = d.result sc w
    literals key alts@(_ :: _) d = do
      let scrut = standing (sc.vars x)
      arms <- traverse (\(_, c) => do
                          (inCase, arg) <- rebound ix l scrut
                          (res, ops) <- collect (c.result (refining x inCase sc) ({ binder := Nothing } w))
                          pure (MkCase 0 (MkArm [arg] res ops))) alts
      (back, arg) <- rebound ix l scrut
      (res, ops) <- collect (d.result (refining x back sc) ({ binder := Nothing } w))
      match ix l w (\cs, dr, ts => Idr.litMatchOp (ArrayAttr (map (key . fst) alts)) (operand ix scrut) [] dr (caseRegions cs) ts)
            arms (Just (MkArm [arg] res ops))

    literalsOf : (kt -> MlirAttr) -> LitArmsOf kt (Sub Em js nv) -> E (Maybe Val)
    literalsOf key (LitDefault alts d) = literals key (forget alts) d
    literalsOf key (LitNoDefault alts) = literals key (init alts) (snd (last alts))
-- The predecessor exists only where the value is not zero: the successor's
-- arm computes it from the value it binds, which is not zero there. The
-- zero arm binds the scrutinee too, which is zero there, as every region
-- of a literal match binds it.
alg ix (CaseNatF l x arms) sc w = case arms of
  OnlyZero z => z.result sc w
  OnlySucc p s => successor p s sc w (standing (sc.vars x))
  Both z p s => do
    let n = standing (sc.vars x)
    (atZero, zarg) <- rebound ix l n
    (zr, zops) <- collect (z.result (refining x atZero sc) ({ binder := Nothing } w))
    (back, arg) <- rebound ix l n
    (sr, sops) <- collect (successor p s (refining x back sc) ({ binder := Nothing } w) back)
    match ix l w (\cs, dr, ts => Idr.litMatchOp (ArrayAttr [litAttr (LNat 0)]) (operand ix n) [] dr (caseRegions cs) ts)
          [MkCase 0 (MkArm [zarg] zr zops)] (Just (MkArm [arg] sr sops))
  where
    successor : Shown -> Sub Em js (Under 1 nv) -> Scope js nv -> Wanted -> Val -> E (Maybe Val)
    successor p s scope w' n = do
      b <- binding p Many
      pv <- value {binder = Just b} ix l (NatT IOpaque) (Idr.natPredOp (operand ix !(coerce ix l Many n)))
      s.result (bind [Whole pv] scope) w'
-- A lambda is a closure of a function of its own, and a `Delay` a
-- suspension of one, each over the values its body uses from where it is
-- written and its scope's levels: the body is written first, as a region,
-- and the function made of it. A lambda's parameter and result are at the
-- types the context expects of them, and a suspension's value at the type
-- the context expects of it, else the ones the term holds: a closure's
-- type holds the extents its values are made at dynamic.
alg ix (LamF l name b held body) sc w = do
  let (param, result) = case w.type of
                          Just (FunT a r) => (typeOf a, r)
                          _ => (typeOf b, held)
  -- A lambda of the world, an action, binds no value for it.
  (args, r, ops) <- case param of
    WorldT => do
      (r, ops) <- collect $ returning ix l result (body.result (bind [World] (offTail sc)))
      pure (Prelude.Nil, r, ops)
    _ => do
      (p, arg) <- freshVal ix param b.quantity
      (r, ops) <- collect $ do
        inner <- coerce ix l b.quantity !(fit ix l (Just (typeOf b)) p)
        returning ix l result (body.result (bind [Whole inner] (offTail sc)))
      st <- get
      put ({ nextBinder $= S } st)
      pure ([MkArgument arg (Binder name (Spanned l) st.ownerSymbol st.nextBinder)], r, ops)
  ops' <- epilogue ix l r ops
  (sym, captures) <- lift l LiftedLambda (map (sortOf ix) sc.telescope) args ops' (resultTypes ix result)
  Just <$> holding ix l w.binder (FunT (MkBinder b.quantity param) result) captures
                   (Idr.fnClosureOp {index_args' = Just (indexArgsOf ix (levels sc.telescope))} (SymbolRefAttr (MkSymbolRef sym [])) captures)
-- An application applies its head at the function type it holds, the one
-- the head's own type gives, and gives the value as the closure's
-- function returns it (`returned`), used once.
alg ix (AppF l a r f x) sc w = do
  Just fv <- consumed ix l (expecting Nothing) (f.result (offTail sc))
    | Nothing => pure Nothing
  Just v <- x.result (offTail sc) (consumedAt (Just (typeOf a)) a.quantity)
    | Nothing => pure Nothing
  -- An action is applied to the world, which is no value: it takes none.
  xs <- case a.type of
    WorldT => pure []
    _ => (\xv => [operand ix xv]) <$> coerce ix l a.quantity !(fit ix l (Just (typeOf a)) v)
  case resultTypes ix r of
    [] => do
      statement l (Idr.fnApplyOp (operand ix fv) xs [])
      pure (Just worldVal)
    _ => Just <$> fitted {binder = w.binder} ix l Once w.type (returned r) (\t => Idr.fnApplyOp (operand ix fv) xs [t])
alg ix (SuspendF l delayed body) sc w = do
  let t = case w.type of
            Just (LazyT r) => r
            _ => delayed
  (r, ops) <- collect (returning ix l t (body.result (offTail sc)))
  ops' <- epilogue ix l r ops
  (sym, captures) <- lift l LiftedDelay (map (sortOf ix) sc.telescope) [] ops' (resultTypes ix t)
  Just <$> holding ix l w.binder (LazyT t) captures
                   (Idr.lazySuspendOp {index_args' = Just (indexArgsOf ix (levels sc.telescope))} (SymbolRefAttr (MkSymbolRef sym [])) captures)
-- A force gives the value its suspension holds, of the type the force
-- holds, the one its operand's own type gives, as the suspension's
-- function returns it (`returned`), used many times: the suspension keeps
-- it for every force.
alg ix (ResumeF l r e) sc w = do
  Just ev <- consumed ix l (expecting Nothing) (e.result (offTail sc))
    | Nothing => pure Nothing
  Just <$> fitted {binder = w.binder} ix l Many w.type (returned r) (Idr.lazyForceOp (operand ix ev))
-- The array language: each operand bound once, in order, by the frontend,
-- an array at the type the operation holds of it; each body a region of
-- the array op Emit.Tensors writes.
alg ix (TensorF l op) sc w = do
  Just vs <- operands ix l (offTail sc) (arraySlots op)
    | Nothing => pure Nothing
  Just <$> tensorOp ix l w.binder vs
alg ix (TabulateF {k} l rt es body) sc w = do
  Just extents <- operands ix l (offTail sc) (unslotted es)
    | Nothing => pure Nothing
  tabulate ix l w.binder rt extents
           (\coords => consumed ix l (expecting Nothing) (body.result (bind (map Whole coords) (offTail sc))))
alg ix (ReduceF l r acc el rt xa axis z x body) sc w = do
  Just zv <- (operand1 ix l (offTail sc) Nothing z).written
    | Nothing => pure Nothing
  Just xv <- (operand1 ix l (offTail sc) (arraySlot xa) x).written
    | Nothing => pure Nothing
  reduce ix l w.binder r acc el rt xa axis zv xv
         (\a, e => consumed ix l (expecting (Just acc)) (body.result (bind [Whole a, Whole e] (offTail sc))))
-- A tie takes its array as it is made, which a call's result is at the
-- tail of a function or of a join point's region, and keeps its type
-- (`tie`). What it states reads the arguments of the call it ties, which
-- are bound before the call, so it is made before the array is, and
-- nothing but the tie stands between a call and its tail.
alg ix (TieF l t x ds) sc w = do
  Just dims <- statedAll ds
    | Nothing => pure Nothing
  (res, ops) <- collect (operand1 ix l (offTail sc) Nothing x).written
  case res of
    Just xv => Just <$> tie ix l w.binder t xv ops dims
    -- An array never made has ended its region in a terminator.
    Nothing => do
      traverse_ append ops
      pure Nothing
  where
    -- Each statement a natural.
    natural : Sub Em [] nv -> E (Maybe Val)
    natural d = consumed ix l (expecting (Just (NatT IOpaque))) (d.result (offTail sc))
    statedAll : List (Nat, Stated (Sub Em [] nv)) -> E (Maybe (List (Nat, Stated Val)))
    statedAll [] = pure (Just [])
    statedAll ((a, SameAs d) :: rest) = do
      Just v <- natural d
        | Nothing => pure Nothing
      map ((a, SameAs v) ::) <$> statedAll rest
    statedAll ((a, Natural d) :: rest) = do
      Just v <- natural d
        | Nothing => pure Nothing
      map ((a, Natural v) ::) <$> statedAll rest
-- An array made in the order of IO is a tabulation whose body's effects
-- its ops declare: no world threads it, so the body's `IORes` gives the
-- element and the array's `IORes` is built of the array alone.
alg ix (TabulateIOF {k} l rt es w body step done) sc wanted = do
  Just extents <- operands ix l (offTail sc) (unslotted es)
    | Nothing => pure Nothing
  Just _ <- w.result (offTail sc) (expecting (Just WorldT))
    | Nothing => pure Nothing
  Just arr <- tabulate ix l Nothing rt extents
                (\coords => do
                   Just res <- consumed ix l (expecting Nothing) (body.result (bind (snoc (map Whole coords) World) (offTail sc)))
                     | Nothing => pure Nothing
                   Just <$> resultOf res)
    | Nothing => pure Nothing
  Just <$> con {binder = wanted.binder} ix l wanted.uses done [] [arr, worldVal]
  where
    -- The element an `IORes` holds: its first field, read.
    resultOf : Val -> E Val
    resultOf res = do
      let e = typeOf (head step.fields)
      v <- mlirValue l (gradedType ix Many made e) (Idr.dataFieldOp (fieldIndex 0) (operand ix res) [])
      pure (val v.name e Many made)
alg ix (UnreachableF l) sc _ = do
  statement l UB.unreachableOp
  pure Nothing
-- An erased equality Idris proved holds in a region, its sides index terms
-- of the scope, and nothing forwarded into it: the region gives the body's
-- value at the type the context expects, cast to it inside, where the
-- equation makes the two types one.
alg ix (AssumeF l lhs rhs body) sc w = do
  (res, ops) <- collect (body.result sc ({ binder := Nothing } w))
  let equation = Idr (EquationAttr (termNodes ix lhs) (termNodes ix rhs))
  match ix l w (\_, d, ts => Idr.indexAssumeOp equation [] d ts) [] (Just (MkArm [] res ops))
-- A crash ends its region: its cause, its site and the definition it is
-- in are data the op holds; a trusted library's crash of a string reports
-- that string.
alg ix (CrashF l cause) sc _ = do
  statement l (Idr.crashCauseOp cause !(siteOf l))
  pure Nothing
alg ix (CrashWithF l m) sc _ = do
  Just s <- (operand1 ix l (offTail sc) (Just (MkBinder Many StrT)) m).written
    | Nothing => pure Nothing
  statement l (Idr.crashMessageOp !(siteOf l) (operand ix s))
  pure Nothing
alg ix (NewWorldF l) sc w = pure (Just worldVal)
-- A read of the array a linear array's cell holds gives the array back as
-- a new value, so what writes the array next comes after the read by data
-- dependence; the body builds the cell again from it.
alg ix (ReadBackF l e x cs body) sc w = do
  Just xv <- (operand1 ix l (offTail sc) Nothing x).written
    | Nothing => pure Nothing
  Just coords <- operands ix l (offTail sc) (unslotted cs)
    | Nothing => pure Nothing
  ixs <- traverse (coordinate ix l) coords
  n <- numbered (At l) (Idr.arrayReadOp (operand ix xv) ixs)
  body.result (bind [Whole (val (Bound n 0) e Many made), Whole ({ name := Bound n 1 } xv)] sc) w
-- Each extent of the array a linear array's cell holds gives the array
-- back as a new value, threaded from one read to the next; the body binds
-- the extents and the last array given back.
alg ix (ExtentsBackF {k} l x body) sc w = do
  Just xv <- (operand1 ix l (offTail sc) Nothing x).written
    | Nothing => pure Nothing
  (extents, final) <- readExtents k 0 xv
  body.result (bind (snoc extents (Whole final)) sc) w
  where
    readExtents : (j : Nat) -> Nat -> Val -> E (Vect j InScope, Val)
    readExtents Z a arr = pure ([], arr)
    readExtents (S j) a arr = do
      n <- numbered (At l) (Idr.arrayExtentOp (IntegerAttr (natToInteger a) (OfWidth 64)) (operand ix arr)
                              (gradedType ix Many made (NatT IOpaque)) (operand ix arr).type)
      (rest, final) <- readExtents j (S a) ({ name := Bound n 1 } arr)
      pure (Whole (val (Bound n 0) (NatT IOpaque) Many made) :: rest, final)
-- The join points the program as written makes: an `idr.join`, whose
-- regions see only the join points around it, so each runs at most once;
-- or an `idr.loop`, whose every region begins with its tokens, so its
-- regions may jump among themselves, each one saying whether it may
-- repeat for ever (`repeats`).
alg ix (JoinF l InBody targets body) sc w =
  joined ix l sc w (\bs, d, rs, results => Idr.joinOp bs [] d rs results) (pure (sc.targets, [])) (\_ => pure ())
         targets body
alg ix (JoinF l InEveryRegion targets body) sc w =
  joined ix l sc w (\bs, d, rs, results => Idr.loopOp bs [] d rs results)
         (mapFst (\own => sc.targets ++ own) <$> reaching l (length sc.telescope) targets) repeats targets body
-- A jump passes its join point's parameters their arguments, at the types
-- its region binds them at with its erased binders given the jump's
-- terms, and ends its region: control goes on in the region its token
-- designates.
alg ix (JumpF l e terms as) sc w = do
  let reach = indexAll e sc.targets
      instantiated = levelsBelow reach.depth ++ terms
      slots = map (\b => Just (MkBinder b.quantity (substTy instantiated b.type))) reach.params
  Just vs <- operands ix l (offTail sc) (zip slots as)
    | Nothing => pure Nothing
  statement l (Idr.jumpOp {terms' = Just (indexArgsOf ix terms)} reach.token (map (operand ix) (present (toList vs))))
  pure Nothing
