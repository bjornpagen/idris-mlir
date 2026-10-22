-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Function bodies: the algebra of the fold that writes a term, its
||| matches as a region per case, its lambdas and delays as functions of
||| their own (Emit.Closures) and its arrays as the array ops
||| (Emit.Tensors). Quantities are read off the binders, which the
||| translation made right; nothing here counts a use.
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
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Functions.Tail
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.Fin
import Data.List
import Data.List1
import Data.Maybe
import Data.SnocList
import Data.String
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Scopes
------------------------------------------------------------------------------

||| The scope a term is written in: what each of its variables stands for,
||| and the sorts of the erased binders its index terms' levels name, the
||| function's index parameters then each enclosing case's constructor
||| binders, in order.
public export
record Scope (nv : Nat) where
  constructor MkScope
  vars : Fin nv -> InScope
  telescope : List Sort

||| What the fold makes of a term in scope `nv`: given its scope and what
||| its context wants, it appends the term's operations and returns its
||| value, or `Nothing` when the term never returns (its region has then
||| ended in a terminator).
public export
Em : Nat -> Type
Em nv = Scope nv -> Wanted -> E (Maybe Val)

||| A scope under a binder of `k` variables, standing for `vs`.
bind : {k : Nat} -> Vect k InScope -> Scope nv -> Scope (Under k nv)
bind vs sc = { vars := \v => case splitUnder {k} v of
                              Left i => index i vs
                              Right x => sc.vars x } sc

||| The scope of a case region: its constructor's binders appended to the
||| telescope, at the next levels.
binding : List Sort -> Scope nv -> Scope nv
binding sorts sc = { telescope := sc.telescope ++ sorts } sc

||| The levels of a scope's telescope, each as the term naming it: what a
||| function lifted from the scope is given for its index parameters.
levels : List Sort -> List ITerm
levels ss = map IVar (take (length ss) [0 .. length ss])

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

||| The types of the module a result of type `t` is: none for the world.
export
resultTypes : Index -> Ty -> List MlirType
resultTypes ix WorldT = []
resultTypes ix t = [gradedType ix Many made t]

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
||| where it says nothing; bound to no variable.
operand1 : Index -> Loc -> Scope nv -> Maybe Binder -> Sub Em nv -> Operands Val
operand1 ix l sc slot a = MkOperands $ do
  Just v <- a.result sc (expecting (typeOf <$> slot))
    | Nothing => pure Nothing
  Just <$> coerce ix l (maybe Many (.quantity) slot) !(fit ix l (typeOf <$> slot) v)

||| A layer's operands, each in its slot, left to right; `Nothing` once one
||| never returns.
operands : Traversable t => Index -> Loc -> Scope nv -> t (Maybe Binder, Sub Em nv) -> E (Maybe (t Val))
operands ix l sc xs = (traverse (\(slot, a) => operand1 ix l sc slot a) xs).written

||| Operands that no slot types: each at its own type, used many times.
unslotted : Functor t => t (Sub Em nv) -> t (Maybe Binder, Sub Em nv)
unslotted = map (\a => (Nothing, a))

||| A constructor's fields, each in its slot (its type with the
||| constructor's binders given), left to right.
fields : Index -> Loc -> Scope nv -> Vect k Binder -> Vect k (Sub Em nv) -> Operands (Vect k Val)
fields ix l sc [] [] = pure []
fields ix l sc (b :: bs) (a :: as) = (::) <$> operand1 ix l sc (Just b) a <*> fields ix l sc bs as

||| A value as a region or a function gives it: used many times.
export
plain : Index -> Loc -> E (Maybe Val) -> E (Maybe Val)
plain ix l act = act >>= traverse (coerce ix l Many)

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

||| A field's position as `idr.data.field` holds it.
fieldIndex : Nat -> MlirAttr
fieldIndex i = IntegerAttr (natToInteger i) (IntegerType 64)

||| The yield that ends a region with its value; a region that never
||| returns has ended in a terminator already.
yielding : Index -> Loc -> Maybe Val -> List Statement
yielding ix l Nothing = []
yielding ix l (Just v) = [MkStatement Nothing (Idr.yieldOp (given ix (Just v))) (At l)]

||| A match from its arms, with the builder of its op over its cases, its
||| default region (none when the cases are exhaustive) and its results:
||| results when an arm yields, and none when no arm returns. The arms join
||| at the type the context expects, else the first arm's that returns; an
||| arm's value at other index terms, or an array of another static shape,
||| is cast to it.
match : Index -> Loc -> Wanted -> (List Case -> MLIR.Region -> List MlirType -> Op)
     -> List Case -> Maybe Arm -> E (Maybe Val)
match ix l w build cases fallback =
  let arms = map (.arm) cases ++ toList fallback in
  case w.type <|> map (.type) (head' (mapMaybe (.result) arms)) of
    Just t => if all (\a => isNothing a.result) arms then never else do
      cs <- traverse (\c => (\r => { arm.statements := r } c) <$> close t c.arm) cases
      d <- maybe (pure NoBlocks) (\a => MkRegion a.arguments <$> close t a) fallback
      Just <$> value {binder = w.binder} ix l t (\r => build cs d [r])
    Nothing => never
  where
    close : Ty -> Arm -> E (List Statement)
    close t a = do
      (v, cast) <- collect (traverse (fit ix l (Just t)) a.result)
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
  names : (from, k : Nat) -> Term n -> Bool
  names from k (Var _ x) = namesVar from k x
  names from k (Literal _ _) = False
  names from k (PrimApp _ _ _ as) = anyNames from k (toList as)
  names from k (Effect _ _ _ as world _) = anyNames from k (toList as) || names from k world
  names from k (Call _ _ _ _ as) = anyNames from k as
  names from k (ConApp _ _ _ as) = anyNames from k (toList as)
  names from k (Let _ _ _ v b) = names from k v || names (S from) k b
  names from k (Case _ _ x arms) = namesVar from k x || armsName from k arms
  names from k (CaseLit _ x arms) = namesVar from k x || litArmsName from k arms
  names from k (CaseNat _ x arms) = namesVar from k x || natArmsName from k arms
  names from k (Lam _ _ _ body) = names (S from) k body
  names from k (App _ f x) = names from k f || names from k x
  names from k (Suspend _ body) = names from k body
  names from k (Resume _ e) = names from k e
  names from k (Unreachable _) = False
  names from k (Assume _ _ _ body) = names from k body
  names from k (Crash _ _) = False
  names from k (CrashWith _ m) = names from k m
  names from k (NewWorld _) = False
  names from k (Tensor _ _ op) = anyNames from k (toList op)
  names from k (Tabulate {k = j} _ _ es body) = anyNames from k (toList es) || names (j + from) k body
  names from k (TabulateIO {k = j} _ _ es w body _ _) =
    anyNames from k (toList es) || names from k w || names (S j + from) k body
  names from k (Reduce _ _ _ _ _ z x body) = names from k z || names from k x || names (2 + from) k body
  names from k (Tie _ x ds) = names from k x || anyNames from k (map (stated . snd) ds)
    where
      stated : Stated (Term n) -> Term n
      stated (SameAs t) = t
      stated (Natural t) = t
  names from k (ReadBack _ _ x cs body) = names from k x || anyNames from k cs || names (2 + from) k body
  names from k (ExtentsBack {k = j} _ x body) = names from k x || names (S j + from) k body

  namesVar : (from, k : Nat) -> Fin n -> Bool
  namesVar from k x = from <= finToNat x && finToNat x < from + k

  anyNames : (from, k : Nat) -> List (Term n) -> Bool
  anyNames from k [] = False
  anyNames from k (t :: ts) = names from k t || anyNames from k ts

  altNames : (from, k : Nat) -> Alt n -> Bool
  altNames from k (MkAlt {k = j} _ _ body) = names (j + from) k body

  armsName : (from, k : Nat) -> CaseArms n -> Bool
  armsName from k (Defaulted alts d) = any (altNames from k) alts || names from k d
  armsName from k (Exhaustive alts) = any (altNames from k) (forget alts)

  keyedName : (from, k : Nat) -> LitArmsOf kt (Term n) -> Bool
  keyedName from k (LitDefault alts d) = any (names from k . snd) (forget alts) || names from k d
  keyedName from k (LitNoDefault alts) = any (names from k . snd) (forget alts)

  litArmsName : (from, k : Nat) -> LitArms n -> Bool
  litArmsName from k (OnlyDefault d) = names from k d
  litArmsName from k (OnInts _ arms) = keyedName from k arms
  litArmsName from k (OnChars arms) = keyedName from k arms
  litArmsName from k (OnStrings arms) = keyedName from k arms
  litArmsName from k (OnBigs arms) = keyedName from k arms

  natArmsName : (from, k : Nat) -> NatArms n -> Bool
  natArmsName from k (OnlyZero z) = names from k z
  natArmsName from k (OnlySucc _ s) = names (S from) k s
  natArmsName from k (Both z _ s) = names from k z || names (S from) k s

||| The scope inside a region of a match on the variable `x`: the variable
||| that named the scrutinee names the value the region binds, refined to
||| the region's constructors, so a field is a read of a value whose type
||| fixes its constructor, and a constructor is never rebuilt from fields.
refining : Fin nv -> Val -> Scope nv -> Scope nv
refining x r sc = { vars := \y => if y == x then Whole r else sc.vars y } sc

||| The fields of constructor `c` in a case at depth `d`: their types with
||| the constructor's binders at the levels `d ..`, each bound at the
||| scrutinee's uses times its own: a field of a value used many times is
||| used many times.
fieldBinders : Nat -> Uses -> Con k -> Vect k Binder
fieldBinders d u c =
  let bs = map IVar (take (length c.binders) [d .. d + length c.binders])
  in map (\b => MkBinder (times u b.quantity) (substTy bs b.type)) c.fields

||| A case's fields as the region holds them, from its refined value `r`:
||| each field the alternative names a read of `r` (`idr.data.field`), at
||| the value's uses times the field's, so a value used once is read once
||| per field; a field it never names is never read, and the world is no
||| value of the module. `named i` says whether the alternative names field
||| `i`.
caseFields : Index -> Loc -> Val -> (named : Nat -> Bool) -> Vect k Binder -> E (Vect k InScope)
caseFields ix l r named bs = traverse (\(i, b) => field (finToNat i) b) (zip range bs)
  where
    -- A field at a linear position of a value nothing else reaches is
    -- reached by nothing else either; any other field's sharing is unknown.
    fieldHold : Binder -> Hold
    fieldHold (MkBinder Once _) = case r.hold of
      Hold.Counted Deep => Hold.Counted Deep
      _ => made
    fieldHold (MkBinder Many _) = made
    read : Nat -> Binder -> E InScope
    read i (MkBinder _ WorldT) = pure World
    -- An array field is held as its buffer; its value is the tensor of it,
    -- restricted, so the buffer is no one else's while the tensor lives,
    -- and never written in place here: what may write it is decided once
    -- exclusivity is. The buffer enters the tensor at its bare grade, as
    -- upstream's op takes it, and the tensor is used as the field is.
    read i b@(MkBinder q t@(TensorT _ _)) = do
      let carrier = fieldType ix t
          graded = case (q, fieldHold b) of
                     (Many, Hold.Counted None) => carrier
                     (u, h) => Idr (GradedType u (Just h) carrier)
      buf <- mlirValue l graded (Idr.dataFieldOp (fieldIndex i) (operand ix r) [])
      bare <- case q of
                Many => pure buf
                Once => mlirValue l carrier (Idr.linCastOp buf [])
      v <- mlirValue l (mlirType ix t) (Bufferization.toTensorOp {restrict = True} bare)
      Whole <$> coerce ix l q (val v.name t Many made)
    read i b = do
      v <- mlirValue l (gradedType ix b.quantity (fieldHold b) b.type) (Idr.dataFieldOp (fieldIndex i) (operand ix r) [])
      pure (Whole (val v.name b.type b.quantity (fieldHold b)))
    -- A field no name of the alternative reads: never looked at.
    field : Nat -> Binder -> E InScope
    field i b = if named i then read i b else pure World

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

||| A call passes as many values as its callee takes. A count that differs
||| is a position the translator did not drop; nothing is written for it.
saturated : Loc -> String -> (given, taken : Nat) -> E ()
saturated l what given taken =
  unless (given == taken) $
    internal (fastConcat [show l, ": ", what, " passes ", show given, " values; it takes ", show taken])

||| The algebra: one layer of `Term` to its emitter. A layer whose value is
||| a subterm's (a `let`'s body, a match's arms) passes what its context
||| wants on to it; every other subterm is an operand or a region's, bound
||| to no variable.
export
alg : {0 nv : Nat} -> Index -> TermF (Sub Em) nv -> Em nv
alg ix (VarF l x) sc w = pure (Just (standing (sc.vars x)))
alg ix (LiteralF l x) sc w = Just <$> literal {binder = w.binder} ix l x
-- The op a primitive makes names the library definition the registry
-- lowered to it, where it lowered one, as a function's names its own.
alg ix (PrimAppF l p stands as) sc w = do
  Just vs <- operands ix l sc (zip (map (map (MkBinder Many)) (slots p)) as)
    | Nothing => pure Nothing
  Just <$> prim w.binder stands ix l p vs
-- An IO primitive takes its operands at their own types, then the world,
-- which is no value of the module.
alg ix (EffectF l p gives as world res) sc w = do
  Just vs <- operands ix l sc (unslotted as)
    | Nothing => pure Nothing
  Just _ <- world.result sc (expecting (Just WorldT))
    | Nothing => pure Nothing
  effect w.binder ix l p gives vs res
-- A call passes its callee's index parameters their terms here and its
-- arguments at the callee's binders with those terms substituted, so its
-- operand and result types are the callee's signature at the call. Where
-- it stands in its function is decided once, by the one definition of tail
-- position, when the program is first order: the frontend writes every
-- call `nontail`, which promises nothing, and the source states no other.
-- A call the registry lowered a library definition's call to names it.
alg ix (CallF l fn stands is as) sc w = do
  Just f <- pure (lookup fn ix.fns)
    | Nothing => internal ("a call of " ++ show fn ++ ", which is not in the program")
  saturated l ("a call of " ++ f.symbol) (length as) f.arity
  let slots = map (\(_, b) => Just (MkBinder b.quantity (substTy is b.type))) (toList f.params)
  Just vs <- operands ix l sc (zip slots as)
    | Nothing => pure Nothing
  let rt = substTy is f.result
      args = map (operand ix) (present vs)
      indexArgs = Just (IdrHand (ArgsOf (map (termNodes ix) is)))
      callee = SymbolRefAttr (MkSymbolRef f.symbol [])
  -- A call gives what its result type is: Idris's world, which is no value
  -- of the module, or one value.
  case rt of
    WorldT => do
      placed (madeAtPlace Nothing (placeOf stands l) Many) (Idr.callOp {index_args' = indexArgs} callee NonTail args [])
      pure (Just worldVal)
    _ => Just <$> fitted {binder = w.binder} {stands} ix l w.type rt (\t => Idr.callOp {index_args' = indexArgs} callee NonTail args [t])
-- A constructor's fields are checked at their types with its binders
-- given.
alg ix (ConAppF l c bs as) sc w = do
  Just vs <- (fields ix l sc (map (\b => { type $= substTy bs } b) c.fields) as).written
    | Nothing => pure Nothing
  Just <$> con {binder = w.binder} ix l c bs vs
-- A `let` binds an SSA value at its binder's type and quantity, as Idris
-- checked them; the op that makes it as the variable holds it stands at
-- the variable's name.
alg ix (LetF l name b v body) sc w = case b of
  Checked (MkBinder _ WorldT) => do
    Just _ <- v.result sc (expecting (Just WorldT))
      | Nothing => pure Nothing
    body.result (bind [World] sc) w
  Checked (MkBinder q t) => bound q (Just t)
  OfValue q => bound q Nothing
  where
    bound : Uses -> Maybe Ty -> E (Maybe Val)
    bound q t = do
      b <- binding name q
      Just x <- v.result sc (MkWanted t (Just b))
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
    alternative : Val -> AltF (Sub Em) nv -> E Case
    alternative scrut (MkAltF {k} c fs body) = do
      let d = length sc.telescope
      (r, arg) <- refinedArg scrut (c.tag ::: [])
      let bs = fieldBinders d scrut.uses c
          inner = refining x r (binding (map (.sort) c.binders) sc)
      (res, ops) <- collect $ do
        vals <- caseFields ix l r (\i => names i 1 body.term) bs
        plain ix l (body.result (bind vals inner) ({ binder := Nothing } w))
      pure (MkCase c.tag (MkArm [arg] res ops))
    -- The default binds the scrutinee refined to the constructors of its
    -- family `f` no case takes; none is left only when Idris proved the
    -- cases cover it, which is `Exhaustive`, so a default here has at
    -- least one.
    defaultArm : Val -> FamilyId -> List Nat -> Sub Em nv -> E Arm
    defaultArm scrut f taken d = do
      (back, arg) <- case untaken ix f taken of
        t :: ts => refinedArg scrut (t ::: ts)
        [] => do
          (v, a) <- freshVal ix scrut.type scrut.uses
          pure (v, MkArgument a (At l))
      (res, ops) <- collect (plain ix l (d.result (refining x back sc) ({ binder := Nothing } w)))
      pure (MkArm [arg] res ops)
-- A match on literals has no exhaustive form: when Idris proved the
-- default impossible, the last possible alternative stands for it, and a
-- match of one is that alternative. Each key is as `idr.lit.match` holds
-- it, by the match's one kind: an integer at its type's width, a `Char` as
-- its code point, a string, a big integer or a natural as itself. In a
-- case the scrutinee is its literal; the default binds it refined to the
-- complement of the keys, so what a case proved of it (a divisor matched
-- against `0`) stays known where the default reads it.
alg ix (CaseLitF l x arms) sc w = case arms of
  OnlyDefault d => d.result sc w
  OnInts t keyed => literalsOf (\n => litAttr (LInt t n)) keyed
  OnChars keyed => literalsOf (\c => litAttr (LChar c)) keyed
  OnStrings keyed => literalsOf (\s => litAttr (LStr s)) keyed
  OnBigs keyed => literalsOf (\n => litAttr (LBig n)) keyed
  where
    literals : (kt -> MlirAttr) -> List (kt, Sub Em nv) -> Sub Em nv -> E (Maybe Val)
    literals key [] d = d.result sc w
    literals key alts@(_ :: _) d = do
      scrut <- coerce ix l Many (standing (sc.vars x))
      let inner = refining x scrut sc
      arms <- traverse (\(_, c) => do
                          (res, ops) <- collect (plain ix l (c.result inner ({ binder := Nothing } w)))
                          pure (MkCase 0 (MkArm [] res ops))) alts
      (back, arg) <- freshVal ix scrut.type Many
      (res, ops) <- collect (plain ix l (d.result (refining x back sc) ({ binder := Nothing } w)))
      match ix l w (\cs, dr, ts => Idr.litMatchOp (ArrayAttr (map (key . fst) alts)) (operand ix scrut) [] dr (caseRegions cs) ts)
            arms (Just (MkArm [MkArgument arg (At l)] res ops))

    literalsOf : (kt -> MlirAttr) -> LitArmsOf kt (Sub Em nv) -> E (Maybe Val)
    literalsOf key (LitDefault alts d) = literals key (forget alts) d
    literalsOf key (LitNoDefault alts) = literals key (init alts) (snd (last alts))
-- The predecessor exists only where the value is not zero: the successor's
-- arm computes it from the value it binds, and only it binds it.
alg ix (CaseNatF l x arms) sc w = case arms of
  OnlyZero z => z.result sc w
  OnlySucc p s => successor p s sc w !(coerce ix l Many (standing (sc.vars x)))
  Both z p s => do
    n <- coerce ix l Many (standing (sc.vars x))
    (zr, zops) <- collect (plain ix l (z.result sc ({ binder := Nothing } w)))
    (back, arg) <- freshVal ix (NatT IOpaque) Many
    (sr, sops) <- collect (plain ix l (successor p s (refining x back sc) ({ binder := Nothing } w) back))
    match ix l w (\cs, dr, ts => Idr.litMatchOp (ArrayAttr [litAttr (LNat 0)]) (operand ix n) [] dr (caseRegions cs) ts)
          [MkCase 0 (MkArm [] zr zops)] (Just (MkArm [MkArgument arg (At l)] sr sops))
  where
    successor : Shown -> Sub Em (Under 1 nv) -> Scope nv -> Wanted -> Val -> E (Maybe Val)
    successor p s scope w' n = do
      b <- binding p Many
      pv <- value {binder = Just b} ix l (NatT IOpaque) (Idr.natPredOp (operand ix n))
      s.result (bind [Whole pv] scope) w'
-- A lambda is a closure of a function of its own, and a `Delay` a
-- suspension of one, each over the values its body uses from where it is
-- written and its scope's levels: the body is written first, as a region,
-- and the function made of it. A suspension of a value is that value
-- held, `idr.lazy.delay %v`. A lambda's parameter and result are at the types
-- the context expects of them: a closure's type holds the extents its
-- values are made at dynamic.
alg ix (LamF l name b body) sc w = do
  let (param, result) = case w.type of
                          Just (FunT a r) => (typeOf a, Just r)
                          _ => (typeOf b, Nothing)
  -- A lambda of the world, an action, binds no value for it.
  (args, r, ops) <- case param of
    WorldT => do
      (r, ops) <- collect $
        plain ix l (body.result (bind [World] sc) (expecting result))
          >>= traverse (fit ix l result)
      pure ([], r, ops)
    _ => do
      (p, arg) <- freshVal ix param b.quantity
      (r, ops) <- collect $ do
        inner <- coerce ix l b.quantity !(fit ix l (Just (typeOf b)) p)
        plain ix l (body.result (bind [Whole inner] sc) (expecting result))
          >>= traverse (fit ix l result)
      st <- get
      put ({ nextBinder $= S } st)
      pure ([MkArgument arg (Binder name (Spanned l) st.ownerSymbol st.nextBinder)], r, ops)
  Just t <- pure (result <|> map (.type) r)
    | Nothing => internal "the result type of a lambda whose body never returns"
  ops' <- epilogue ix l r ops
  (sym, captures) <- lift l LiftedLambda (map (sortOf ix) sc.telescope) args ops' (resultTypes ix t)
  Just <$> holding ix l w.binder (FunT (MkBinder b.quantity param) t) captures
                   (Idr.fnClosureOp {index_args' = Just (IdrHand (ArgsOf (map (termNodes ix) (levels sc.telescope))))} (SymbolRefAttr (MkSymbolRef sym [])) captures)
alg ix (AppF l f x) sc w = do
  Just fv <- plain ix l (f.result sc (expecting Nothing))
    | Nothing => pure Nothing
  FunT a r <- pure fv.type
    | t => internal ("an application of a value of type " ++ show t)
  Just v <- x.result sc (expecting (Just (typeOf a)))
    | Nothing => pure Nothing
  -- An action is applied to the world, which is no value: it takes none.
  xs <- case a.type of
    WorldT => pure []
    _ => (\xv => [operand ix xv]) <$> coerce ix l a.quantity !(fit ix l (Just (typeOf a)) v)
  case resultTypes ix r of
    [] => do
      statement l (Idr.fnApplyOp (operand ix fv) xs [])
      pure (Just worldVal)
    _ => Just <$> fitted {binder = w.binder} ix l w.type r (\t => Idr.fnApplyOp (operand ix fv) xs [t])
alg ix (SuspendF l body) sc w = do
  let result = case w.type of
                 Just (LazyT r) => Just r
                 _ => Nothing
  (r, ops) <- collect (plain ix l (body.result sc (expecting result))
                       >>= traverse (fit ix l result))
  Just t <- pure (result <|> map (.type) r)
    | Nothing => internal "the result type of a Delay whose body never returns"
  ops' <- epilogue ix l r ops
  (sym, captures) <- lift l LiftedDelay (map (sortOf ix) sc.telescope) [] ops' (resultTypes ix t)
  Just <$> holding ix l w.binder (LazyT t) captures
                   (Idr.lazySuspendOp {index_args' = Just (IdrHand (ArgsOf (map (termNodes ix) (levels sc.telescope))))} (SymbolRefAttr (MkSymbolRef sym [])) captures)
alg ix (ResumeF l e) sc w = do
  Just ev <- plain ix l (e.result sc (expecting Nothing))
    | Nothing => pure Nothing
  LazyT r <- pure ev.type
    | t => internal ("a force of a value of type " ++ show t)
  Just <$> fitted {binder = w.binder} ix l w.type r (Idr.lazyForceOp (operand ix ev))
-- The array language: each operand bound once, in order, by the frontend;
-- each body a region of the array op Emit.Tensors writes.
alg ix (TensorF l rt op) sc w = do
  Just vs <- operands ix l sc (unslotted op)
    | Nothing => pure Nothing
  Just <$> tensorOp ix l w.binder rt vs
alg ix (TabulateF {k} l rt es body) sc w = do
  Just extents <- operands ix l sc (unslotted es)
    | Nothing => pure Nothing
  tabulate ix l w.binder rt extents
           (\coords => plain ix l (body.result (bind (map Whole coords) sc) (expecting Nothing)))
alg ix (ReduceF l r acc el rt z x body) sc w = do
  Just zv <- (operand1 ix l sc Nothing z).written
    | Nothing => pure Nothing
  Just xv <- (operand1 ix l sc Nothing x).written
    | Nothing => pure Nothing
  reduce ix l w.binder r acc el rt zv xv
         (\a, e => plain ix l (body.result (bind [Whole a, Whole e] sc) (expecting (Just acc))))
alg ix (TieF l x ds) sc w = do
  Just xv <- plain ix l (x.result sc (expecting Nothing))
    | Nothing => pure Nothing
  Just dims <- statedAll ds
    | Nothing => pure Nothing
  Just <$> tie ix l w.binder xv dims
  where
    -- Each statement a natural.
    natural : Sub Em nv -> E (Maybe Val)
    natural d = plain ix l (d.result sc (expecting (Just (NatT IOpaque))))
    statedAll : List (Nat, Stated (Sub Em nv)) -> E (Maybe (List (Nat, Stated Val)))
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
  Just extents <- operands ix l sc (unslotted es)
    | Nothing => pure Nothing
  Just _ <- w.result sc (expecting (Just WorldT))
    | Nothing => pure Nothing
  Just arr <- tabulate ix l Nothing rt extents
                (\coords => do
                   Just res <- plain ix l (body.result (bind (snoc (map Whole coords) World) sc) (expecting Nothing))
                     | Nothing => pure Nothing
                   Just <$> resultOf res)
    | Nothing => pure Nothing
  Just <$> con {binder = wanted.binder} ix l done [] [arr, worldVal]
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
  (res, ops) <- collect (plain ix l (body.result sc ({ binder := Nothing } w)))
  let equation = IdrHand (EquationOf (termNodes ix lhs) (termNodes ix rhs))
  match ix l w (\_, d, ts => Idr.indexAssumeOp equation [] d ts) [] (Just (MkArm [] res ops))
-- A crash ends its region: its cause, its site and the definition it is
-- in are data the op holds; a trusted library's crash of a string reports
-- that string.
alg ix (CrashF l cause) sc _ = do
  statement l (Idr.crashCauseOp cause !(siteOf l))
  pure Nothing
alg ix (CrashWithF l m) sc _ = do
  Just s <- (operand1 ix l sc (Just (MkBinder Many StrT)) m).written
    | Nothing => pure Nothing
  statement l (Idr.crashMessageOp !(siteOf l) (operand ix s))
  pure Nothing
alg ix (NewWorldF l) sc w = pure (Just worldVal)
-- A read of the array a linear array's cell holds gives the array back as
-- a new value, so what writes the array next comes after the read by data
-- dependence; the body builds the cell again from it.
alg ix (ReadBackF l e x cs body) sc w = do
  Just xv <- (operand1 ix l sc Nothing x).written
    | Nothing => pure Nothing
  Just coords <- operands ix l sc (unslotted cs)
    | Nothing => pure Nothing
  ixs <- traverse (coordinate ix l) coords
  n <- numbered (At l) (Idr.arrayReadOp (operand ix xv) ixs)
  body.result (bind [Whole (val (Bound n 0) e Many made), Whole ({ name := Bound n 1 } xv)] sc) w
-- Each extent of the array a linear array's cell holds gives the array
-- back as a new value, threaded from one read to the next; the body binds
-- the extents and the last array given back.
alg ix (ExtentsBackF {k} l x body) sc w = do
  Just xv <- (operand1 ix l sc Nothing x).written
    | Nothing => pure Nothing
  (extents, final) <- readExtents k 0 xv
  body.result (bind (snoc extents (Whole final)) sc) w
  where
    readExtents : (j : Nat) -> Nat -> Val -> E (Vect j InScope, Val)
    readExtents Z a arr = pure ([], arr)
    readExtents (S j) a arr = do
      n <- numbered (At l) (Idr.arrayExtentOp (IntegerAttr (natToInteger a) (IntegerType 64)) (operand ix arr)
                              (gradedType ix Many made (NatT IOpaque)) (operand ix arr).type)
      (rest, final) <- readExtents j (S a) ({ name := Bound n 1 } arr)
      pure (Whole (val (Bound n 0) (NatT IOpaque) Many made) :: rest, final)
