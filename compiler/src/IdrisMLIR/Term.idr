-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Full Core: the higher-order language
||| that `Frontend.Translate` produces from checked TT and `Emit` writes as
||| MLIR.
|||
||| `TermAt js n` is a term in a scope of `n` variables, each a de Bruijn
||| index (`Fin n`, `0` the innermost): a binder of `k` variables holds a
||| term in `Under k n`, its own variables first, then the scope's outside
||| it. A closed term is in scope `0`; a function's body is in scope
||| `arity`, parameter `i` being `i`, as in Idris's case trees. An unbound
||| variable is a type error. The scope is counted by a number, not named by
||| a type of variables, so that a traversal under a binder recurses at the
||| same types, only at another number. `js` are the join points its tail
||| positions may jump to (`Join`, `Jump`); `Term n` is a term no join point
||| is in scope of, which is every term the translation makes before it
||| finds the join points the program as written makes.
|||
||| A visit (`visitTerm`) reads or rewrites each variable, call and level of a
||| term; renaming is one (`rename`). Every other traversal is a fold over
||| the base functor `TermF`: `cata`, or `para` where the algebra needs a
||| part as it was.
|||
||| A lambda's or a `Delay`'s body stays in the scope it is written in, as a
||| `let`'s does: renaming enters it, and the variables of that scope it
||| uses are its captures. `Emit` writes it as a function of its own, which
||| the closure or the suspension names with its captures.
module IdrisMLIR.Term

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Spec.Control.Joins
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Families.Group
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Types

import Control.Monad.Identity
import Data.Fin
import Data.Fin.Split
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.List1
import Data.Maybe
import Data.Nat
import Data.SnocList
import Data.String
import Data.Vect
import Decidable.Equality

%default total

------------------------------------------------------------------------------
-- Scopes
------------------------------------------------------------------------------

||| The scope under a binder of `k` variables, in a scope of `n`.
public export
Under : Nat -> Nat -> Nat
Under k n = k + n

||| One of a binder's own variables.
public export
Bound : {0 n : Nat} -> Fin k -> Fin (Under k n)
Bound i = weakenN n i

||| One of the variables of the scope outside a binder of `k`.
public export
Free : {k : Nat} -> Fin n -> Fin (Under k n)
Free x = shift k x

||| A variable under a binder of `k` variables: one of the binder's, or one
||| of the scope's outside it.
public export
splitUnder : {k : Nat} -> Fin (Under k n) -> Either (Fin k) (Fin n)
splitUnder v = splitSum v

------------------------------------------------------------------------------
-- Families
------------------------------------------------------------------------------

||| An erased binder of a constructor: its sort, and the argument of the
||| constructor's application that gives it, counting every argument, so
||| that a construction site links the binder to the term that argument is.
public export
record ConBinder where
  constructor MkConBinder
  sort : Sort
  argument : Nat

||| A constructor of a family instance, of `k` fields: its identity (the
||| family and its position, Idris's tag), its name within its type, as the
||| module labels it (`Types.shortName`); its erased binders, the levels
||| `0 .. j-1` of its own scope (Idris's quantity-0 arguments that an index
||| of its result or a field's type refers to; a proof no index reads is no
||| binder); the term each index of its family equals, one per index, in
||| that scope; and its fields (its runtime arguments, not its parameters),
||| each as it binds, its type in that scope. A field of quantity 0 does not
||| exist. Every reference to a constructor holds it.
public export
record Con (k : Nat) where
  constructor MkCon
  id : ConId
  name : String
  binders : List ConBinder
  equation : List ITerm
  fields : Vect k Binder
  loc : Loc

||| What a call holds of its callee, read once where the callee was
||| requested (`Instances.request`), the same value the callee's own
||| function is made with: its identity, its symbol (its key printed,
||| `keyText`, once), its runtime parameters' binders and its result, in
||| the callee's scope, whose levels are its index parameters. A call's
||| runtime arguments are as many as the binders, by type.
public export
record Callee (arity : Nat) where
  constructor MkCallee
  fn : FnId
  symbol : String
  params : Vect arity Binder
  result : Ty

||| A constructor's tag: Idris's, its identity's position (`id.index`).
public export
(.tag) : Con k -> Nat
(.tag) c = finToNat c.id.index

||| A family instance: the inductive family Idris checked, at the
||| parameters its key holds (keyed parameters substituted, dictionary
||| fields fixed for the program), carried whole: the sorts of its erased
||| indices, its constructors in tag order, and what its library promises
||| of its values (`Promise`: rebuilt in place, the registry's
||| `InPlaceType`). Its key is what it is an instance of, and its Idris
||| name is the key's origin. How its values are laid out, inline or in a
||| cell, is the dialect's, from the type.
public export
record Family where
  constructor MkFamily
  id : FamilyId
  key : InstanceKey
  promise : Promise
  indices : List Sort
  cons : List (k ** Con k)
  loc : Loc

------------------------------------------------------------------------------
-- The array language
------------------------------------------------------------------------------

%prefix_record_projections off

||| An array type of rank `r`: its dimensions, outermost first, and its
||| element. An operation of the array language holds the types of the
||| arrays it takes so, so that an axis is a position among an array's
||| dimensions and no axis past its rank can be written; a size witness
||| names its axis the same way (`Shapes.AxisAt`).
public export
record ArrayType (r : Nat) where
  constructor MkArrayType
  dims : Vect r Dim
  element : Ty

%prefix_record_projections on

||| An array type as a type.
public export
arrayTy : ArrayType r -> Ty
arrayTy a = TensorT (toList a.dims) a.element

||| An operation of the array language on its operands `t`, in the order the
||| dump writes them, holding the type of each array it takes and of what
||| it gives. An axis is a position among its array's dimensions, outermost
||| first: the axis of `Take`, `Drop` and `Concat` is the shape's last,
||| before the cell's, and `Transpose`'s the shape's last but one, which it
||| swaps with the one after it, so the array it transposes has an axis
||| past the one it names.
public export
data TensorOp : Type -> Type where
  ||| The extent of the array's axis, a natural.
  Extent : {0 r : Nat} -> (array : ArrayType r) -> Fin r -> t -> TensorOp t
  ||| The element of the array at the coordinates (naturals, one per
  ||| leading axis), or the cell there when `result` is an array.
  Extract : {0 r : Nat} -> (array : ArrayType r) -> (result : Ty) -> t -> List t -> TensorOp t
  ||| The array with the element or cell at the coordinates, giving a value
  ||| of `result`.
  Insert : {0 r : Nat} -> (array : ArrayType r) -> (result : Ty) -> t -> t -> List t -> TensorOp t
  ||| The first k along the axis of the array.
  Take : {0 r : Nat} -> (array, result : ArrayType r) -> Fin r -> t -> t -> TensorOp t
  ||| All but the first k along the axis of the array.
  Drop : {0 r : Nat} -> (array, result : ArrayType r) -> Fin r -> t -> t -> TensorOp t
  ||| One array then the other along the axis.
  Concat : {0 r : Nat} -> (first, second, result : ArrayType r) -> Fin r -> t -> t -> TensorOp t
  ||| The array with the axis and the one after it swapped.
  Transpose : {0 r : Nat} -> (array : ArrayType (S r)) -> (result : Ty) -> Fin r -> t -> TensorOp t
  ||| The array's elements in row-major order at the result's shape, its
  ||| extents given outermost first; the result's dimensions after them are
  ||| the cell's.
  Reshape : {0 r : Nat} -> (array : ArrayType r) -> (result : Ty) -> t -> List t -> TensorOp t

export
Functor TensorOp where
  map f (Extent a j x) = Extent a j (f x)
  map f (Extract a rt x cs) = Extract a rt (f x) (map f cs)
  map f (Insert a rt x v cs) = Insert a rt (f x) (f v) (map f cs)
  map f (Take a ra j k x) = Take a ra j (f k) (f x)
  map f (Drop a ra j k x) = Drop a ra j (f k) (f x)
  map f (Concat a b ra j x y) = Concat a b ra j (f x) (f y)
  map f (Transpose a rt j x) = Transpose a rt j (f x)
  map f (Reshape a rt x es) = Reshape a rt (f x) (map f es)

export
Foldable TensorOp where
  foldr f z (Extent _ _ x) = f x z
  foldr f z (Extract _ _ x cs) = f x (foldr f z cs)
  foldr f z (Insert _ _ x v cs) = f x (f v (foldr f z cs))
  foldr f z (Take _ _ _ k x) = f k (f x z)
  foldr f z (Drop _ _ _ k x) = f k (f x z)
  foldr f z (Concat _ _ _ _ x y) = f x (f y z)
  foldr f z (Transpose _ _ _ x) = f x z
  foldr f z (Reshape _ _ x es) = f x (foldr f z es)

export
Traversable TensorOp where
  traverse f (Extent a j x) = Extent a j <$> f x
  traverse f (Extract a rt x cs) = Extract a rt <$> f x <*> traverse f cs
  traverse f (Insert a rt x v cs) = Insert a rt <$> f x <*> f v <*> traverse f cs
  traverse f (Take a ra j k x) = Take a ra j <$> f k <*> f x
  traverse f (Drop a ra j k x) = Drop a ra j <$> f k <*> f x
  traverse f (Concat a b ra j x y) = Concat a b ra j <$> f x <*> f y
  traverse f (Transpose a rt j x) = Transpose a rt j <$> f x
  traverse f (Reshape a rt x es) = Reshape a rt <$> f x <*> traverse f es

------------------------------------------------------------------------------
-- Terms
------------------------------------------------------------------------------

||| What an IO primitive gives besides the next world, by how many values
||| its action gives: none, whose `IORes` holds the unit constructor named;
||| or one, the action's result.
public export
data IOGives : Nat -> Type where
  GivesUnit : Con 0 -> IOGives 0
  GivesValue : IOGives 1

||| What a `let` binds: an Idris `let`'s binder, its type the one Idris
||| checked, which the TTC keeps; or a value the translation binds once
||| (an argument evaluated where the call puts it, a held value), at the
||| quantity it makes it at, its type the value's own.
public export
data LetBinder = Checked Binder | OfValue Uses

||| A match's possible alternatives and its default, or alternatives that
||| cover every constructor, at least one: a match with no possible arm is
||| `Unreachable`.
public export
data CaseArmsOf alt t = Defaulted (List alt) t | Exhaustive (List1 alt)

||| A match on literals' possible alternatives, each keyed by a `k`, at
||| least one, and its default, or, when Idris proved the default
||| impossible, none.
public export
data LitArmsOf k t = LitDefault (List1 (k, t)) t | LitNoDefault (List1 (k, t))

||| A match on literals, keyed by the one kind of literal Idris's tree
||| matches at a place: a fixed-width integer of its type, a character by
||| its code point, a string, or a number held as a big integer (an
||| `Integer`, or a natural, which `idr.lit.match` keys alike). A match
||| whose every literal is impossible has its default alone, and no kind.
public export
data LitMatch t
  = OnlyDefault t
  | OnInts IntTy (LitArmsOf Integer t)
  | OnChars (LitArmsOf Integer t)
  | OnStrings (LitArmsOf String t)
  | OnBigs (LitArmsOf Integer t)

||| A match on a natural's possible arms: zero, a successor binding its
||| predecessor (named), or both.
public export
data NatArmsOf z s = OnlyZero z | OnlySucc Shown s | Both z Shown s

||| The join points a join op's regions may jump to, by where its member
||| puts its tokens: an `idr.join`'s see only those around the op, so none
||| repeats; an `idr.loop`'s see the op's own too, after those around it,
||| which is what lets them repeat.
public export
regionsSee : TokenScope -> List Nat -> List Nat -> List Nat
regionsSee InBody js ts = js
regionsSee InEveryRegion js ts = js ++ ts

||| Whose code a join region is, which a crash in it names as the
||| definition it is in: the code around it (a `let`'s lambda), or the code
||| of the local definition Idris named so and lifted out of the function.
public export
data CodeOf = Surrounding | LocalCode Shown

mutual
  ||| A term in scope `n` whose tail positions may jump to the join points
  ||| `js`, each by its arity, the outermost first. Only a tail position
  ||| sees them: an operand, a `let`'s value, a lambda's, a delay's or an
  ||| array op's body sees none, since a jump from there would skip what
  ||| that value is for, or leave the function the body becomes. So every
  ||| jump is a tail of each op around it up to its join op, and no other
  ||| jump can be written.
  public export
  data TermAt : (js : List Nat) -> (n : Nat) -> Type where
    Var : Loc -> Fin n -> TermAt js n
    Literal : Loc -> Lit -> TermAt js n
    ||| A primitive, and the library definition it stands for when the
    ||| registry lowered that definition's call to it, for a message to
    ||| name; nothing computes with it.
    PrimApp : {k : Nat} -> Loc -> Prim k -> (standsFor : Maybe Shown) -> Vect k (TermAt [] n) -> TermAt js n
    ||| An IO primitive on its operands, as many as its action takes, and the
    ||| world, giving the `IORes` (`res`) of what it gives and the next
    ||| world.
    Effect : {i, o : Nat} -> Loc -> IOAction i o -> IOGives o -> Vect i (TermAt [] n) -> (world : TermAt [] n) ->
             (res : Con 2) -> TermAt js n
    ||| A saturated call of the callee it holds, one argument per runtime
    ||| parameter, and the library definition it stands for when the
    ||| registry lowered that definition's call to it, as for a primitive.
    ||| `indices` are the terms its callee's erased index parameters are
    ||| given, in the caller's scope, one per parameter of the callee's
    ||| telescope (`TFn.telescope`).
    Call : {arity : Nat} -> Loc -> Callee arity -> (standsFor : Maybe Shown) -> (indices : List ITerm) ->
           Vect arity (TermAt [] n) -> TermAt js n
    ||| A saturated constructor application; parameters are not fields.
    ||| `binders` are the terms the constructor's first erased binders are
    ||| given, in the scope it is written in, each the term of the argument
    ||| that gives it (`ConBinder.argument`); a binder past them, as in a
    ||| value the translation builds with no argument written, is outside
    ||| the language. The indices of its value are its equation with them
    ||| substituted.
    ConApp : {k : Nat} -> Loc -> Con k -> (binders : List ITerm) -> Vect k (TermAt [] n) -> TermAt js n
    ||| `let`, with its variable's name and what it binds.
    Let : Loc -> (name : Shown) -> LetBinder -> TermAt [] n -> TermAt js (Under 1 n) -> TermAt js n
    ||| A match on a value of the family named, by its constructors.
    Case : Loc -> FamilyId -> Fin n -> CaseArmsOf (AltAt js n) (TermAt js n) -> TermAt js n
    CaseLit : Loc -> Fin n -> LitMatch (TermAt js n) -> TermAt js n
    ||| A match on a `Nat`-like value: zero, or a successor, whose
    ||| predecessor the successor's arm binds. The predecessor exists only
    ||| there, where the value is not zero.
    CaseNat : Loc -> Fin n -> NatArmsOf (TermAt js n) (TermAt js (Under 1 n)) -> TermAt js n
    ||| A lambda; its body binds the parameter (`Bound 0`), named as Idris
    ||| named it.
    Lam : Loc -> (name : Shown) -> Binder -> TermAt [] (Under 1 n) -> TermAt js n
    App : Loc -> TermAt [] n -> TermAt [] n -> TermAt js n
    ||| A suspended computation, of the type `value` Idris checked it at
    ||| (`TDelay` holds it), at the extents a suspension's type holds.
    Suspend : Loc -> (value : Ty) -> TermAt [] n -> TermAt js n
    Resume : Loc -> TermAt [] n -> TermAt js n
    ||| A term Idris proved never runs: a match with no possible arm.
    Unreachable : Loc -> TermAt js n
    ||| A region in which an erased equality Idris proved holds, its two
    ||| sides index terms of the scope: a match on an erased `Refl`, which
    ||| `replace` and `rewrite` are. The body's value leaves it at the type
    ||| its context expects, cast to it inside the region, where the
    ||| equation makes the two types one.
    Assume : Loc -> (lhs, rhs : ITerm) -> TermAt js n -> TermAt js n
    ||| A crash of a partial definition, its cause one of the
    ||| specification's (`NoClauseMatched` for a case it does not cover);
    ||| Emit gives it its site and the definition it is in, as data.
    Crash : Loc -> Cause -> TermAt js n
    ||| A trusted library's crash with a message computed at run time.
    CrashWith : Loc -> TermAt [] n -> TermAt js n
    ||| A world forged where a trusted library runs an IO action for a pure
    ||| value (`unsafePerformIO`): the first world of a chain of its own.
    ||| Like every world it is no value of the module: the action's effects
    ||| are ordered by the effects its ops declare.
    NewWorld : Loc -> TermAt js n
    ||| An operation of the array language on its operands, which holds the
    ||| types of the arrays it takes and of what it gives.
    Tensor : Loc -> TensorOp (TermAt [] n) -> TermAt js n
    ||| A new array of `result` (a `TensorT`) of the extents given
    ||| (naturals, one per axis of the shape tabulated, outermost first),
    ||| each element or cell the body's value; the body binds the
    ||| coordinates, coordinate j (outermost first) being `Bound j`, a
    ||| natural.
    Tabulate : {k : Nat} -> Loc -> (result : Ty) -> Vect k (TermAt [] n) -> TermAt [] (Under k n) -> TermAt js n
    ||| A new array of `result` (a `TensorT`) of the extents given, made in
    ||| the world's order: the body binds the coordinates (`Bound 0` to
    ||| `Bound (k - 1)`, outermost first) and the world before it (`Bound
    ||| k`), and gives the `IORes` (`step`) of the element and the world
    ||| after it, once per index in row-major order, never when the array is
    ||| empty. Its value is the `IORes` (`done`) of the array and the last
    ||| world; `world` is the first.
    TabulateIO : {k : Nat} -> Loc -> (result : Ty) -> Vect k (TermAt [] n) -> (world : TermAt [] n)
              -> TermAt [] (Under (S k) n) -> (step, done : Con 2) -> TermAt js n
    ||| A reduction of `x`, of type `array`, along `axis`, the one after
    ||| the frame of `z`, from `z`'s accumulators, left to right in index
    ||| order; the body binds the accumulator (`Bound 0`) and the element or
    ||| cell (`Bound 1`). `FoldLast` gives the last accumulators (`z`'s
    ||| type), `ScanLast` every one, along that axis.
    Reduce : {0 r : Nat} -> Loc -> Reduction -> (acc, elem, result : Ty) -> (array : ArrayType r) -> (axis : Fin r) ->
             (z, x : TermAt [] n) -> TermAt [] (Under 2 n) -> TermAt js n
    ||| The array, of type `array`, the dynamic dimensions that type gives
    ||| it stated equal to what each statement gives, axis by axis (an axis
    ||| counted from 0, outermost first).
    Tie : Loc -> (array : Ty) -> TermAt [] n -> List (Nat, Stated (TermAt [] n)) -> TermAt js n
    ||| A read of the array a linear array's cell holds: the element or
    ||| cell at the coordinates (naturals, one per leading axis), and the
    ||| array given back as a new value, so that what writes the array next
    ||| comes after the read by data dependence. The body binds the element
    ||| (`Bound 0`) and the array given back (`Bound 1`).
    ReadBack : Loc -> (elem : Ty) -> (array : TermAt [] n) -> List (TermAt [] n) -> TermAt js (Under 2 n) ->
               TermAt js n
    ||| The extents of the array a linear array's cell holds, each read
    ||| giving the array back as a new value: the body binds extent j
    ||| (outermost first) as `Bound j`, a natural, and the array given back
    ||| last as `Bound k`.
    ExtentsBack : {k : Nat} -> Loc -> (array : TermAt [] n) -> TermAt js (Under (S k) n) -> TermAt js n
    ||| Join points the program as written makes, at least one: the op of
    ||| `scope`'s member (`idr.join`, or `idr.loop` for one whose regions
    ||| jump among themselves), its join regions, each seeing the join
    ||| points its member lets it see, and its body, entered once, whose
    ||| tails may jump to the op's own after those around it. Its value is
    ||| the value of whichever region returns.
    Join : {0 ts : List Nat} -> {auto 0 nonEmpty : NonEmpty ts} -> Loc -> (scope : TokenScope) ->
           All (Target (regionsSee scope js ts) n) ts -> TermAt (js ++ ts) n -> TermAt js n
    ||| A jump to a join point in scope, which ends the region: the terms
    ||| its region's erased binders are given, in this scope, and an
    ||| argument per parameter of its region, as many as its arity.
    Jump : {k : Nat} -> Loc -> Elem k js -> (terms : List ITerm) -> Vect k (TermAt [] n) -> TermAt js n

  ||| A constructor alternative binds the constructor's fields (not its
  ||| parameters), each named as its pattern variable: field `i` is
  ||| `Bound i`, bound as the constructor holds it. Its region also binds
  ||| the constructor's erased binders, at the next levels of the scope's
  ||| telescope, and inside it the scrutinee is the value refined to the
  ||| constructor.
  public export
  data AltAt : List Nat -> Nat -> Type where
    MkAlt : {k : Nat} -> Con k -> Vect k Shown -> TermAt js (Under k n) -> AltAt js n

  ||| A join point of `k` parameters: where it is written; whose code it
  ||| is; the sorts of the erased index variables its region binds at the
  ||| next levels, which a jump gives its terms for; its parameters, each
  ||| named, in the order a jump passes its arguments; and its body,
  ||| parameter `i` being `Bound i`, seeing the join points `scope`.
  public export
  data Target : (scope : List Nat) -> (n : Nat) -> (k : Nat) -> Type where
    MkTarget : {k : Nat} -> Loc -> CodeOf -> (sorts : List Sort) -> Vect k Shown -> Vect k Binder ->
               TermAt scope (Under k n) -> Target scope n k

||| A term no join point is in scope of.
public export
Term : Nat -> Type
Term = TermAt []

||| An alternative no join point is in scope of.
public export
Alt : Nat -> Type
Alt = AltAt []

||| A match's arms.
public export
CaseArms : Nat -> Type
CaseArms n = CaseArmsOf (Alt n) (Term n)

||| A match on literals' arms.
public export
LitArms : Nat -> Type
LitArms n = LitMatch (Term n)

||| A match on a natural's arms.
public export
NatArms : Nat -> Type
NatArms n = NatArmsOf (Term n) (Term (Under 1 n))

------------------------------------------------------------------------------
-- Visits: each variable, call and level of a term
------------------------------------------------------------------------------

||| How a visit moves the levels of the scope's telescope that a term's
||| index terms and types name: not at all, or each past `q` more, as when
||| a function's body becomes a region of another function whose own
||| telescope is `q` deep.
public export
data Levels = Unmoved | MovedBy Nat

mutual
  ||| An index term with each level moved past `q` more. A level stays a
  ||| level, so the normal form (`succ`) is kept.
  moveTerm : Nat -> ITerm -> ITerm
  moveTerm q (IVar k) = IVar (k + q)
  moveTerm q (ISucc t k) = ISucc (moveTerm q t) k
  moveTerm q (ICon f c as) = ICon f c (moveTerms q as)
  moveTerm q (IType t) = IType (moveTy q t)
  moveTerm q t = t

  moveTerms : Nat -> List ITerm -> List ITerm
  moveTerms q [] = []
  moveTerms q (t :: ts) = moveTerm q t :: moveTerms q ts

  moveTy : Nat -> Ty -> Ty
  moveTy q (NatT t) = NatT (moveTerm q t)
  moveTy q (DataT f ts) = DataT f (moveTerms q ts)
  moveTy q (FunT (MkBinder u a) r) = FunT (MkBinder u (moveTy q a)) (moveTy q r)
  moveTy q (LazyT a) = LazyT (moveTy q a)
  moveTy q (TensorT ds a) = TensorT ds (moveTy q a)
  moveTy q (MemRefT o a) = MemRefT o (moveTy q a)
  moveTy q t = t

mutual
  ||| An index term with the terms `bs` substituted for the levels `0 ..`
  ||| of the scope it is written in: a constructor's equation or field in
  ||| the scope its value is made or read in, a callee's signature at a
  ||| call.
  export
  substitute : List ITerm -> ITerm -> ITerm
  substitute bs (IVar k) = fromMaybe IOpaque (getAt k bs)
  substitute bs (ISucc t k) = succ (substitute bs t) k
  substitute bs (ICon f c as) = ICon f c (substituteAll bs as)
  substitute bs (IType t) = IType (substTy bs t)
  substitute bs t = t

  export
  substituteAll : List ITerm -> List ITerm -> List ITerm
  substituteAll bs [] = []
  substituteAll bs (t :: ts) = substitute bs t :: substituteAll bs ts

  ||| A type with the terms `bs` substituted for the levels of its scope:
  ||| a callee's result at a call, which the call's value is of.
  export
  substTy : List ITerm -> Ty -> Ty
  substTy bs (DataT f ts) = DataT f (substituteAll bs ts)
  substTy bs (NatT t) = NatT (substitute bs t)
  substTy bs (FunT (MkBinder q a) r) = FunT (MkBinder q (substTy bs a)) (substTy bs r)
  substTy bs (LazyT a) = LazyT (substTy bs a)
  substTy bs (TensorT ds a) = TensorT ds (substTy bs a)
  substTy bs (MemRefT o a) = MemRefT o (substTy bs a)
  substTy bs t = t

moved : Levels -> ITerm -> ITerm
moved Unmoved t = t
moved (MovedBy q) t = moveTerm q t

movedTerms : Levels -> List ITerm -> List ITerm
movedTerms Unmoved ts = ts
movedTerms (MovedBy q) ts = moveTerms q ts

movedTy : Levels -> Ty -> Ty
movedTy Unmoved t = t
movedTy (MovedBy q) t = moveTy q t

movedBinder : Levels -> Binder -> Binder
movedBinder ls (MkBinder u t) = MkBinder u (movedTy ls t)

movedLet : Levels -> LetBinder -> LetBinder
movedLet ls (Checked b) = Checked (movedBinder ls b)
movedLet ls (OfValue u) = OfValue u

movedSort : Levels -> Sort -> Sort
movedSort ls (SScalar t) = SScalar (movedTy ls t)
movedSort ls s = s

-- A primitive names a type of the scope only as an array's element or an
-- op's result.
movedPrim : Levels -> Prim k -> Prim k
movedPrim ls (ArrayLength t) = ArrayLength (movedTy ls t)
movedPrim ls (Op {i} op r h) = Op {i} op (movedTy ls r) h
movedPrim ls p = p

-- An array type names a type of the scope only as its element.
movedArray : Levels -> ArrayType r -> ArrayType r
movedArray ls a = { element $= movedTy ls } a

%prefix_record_projections off

||| A visit of a term in scope `n`, which it makes one of scope `m`: what
||| each variable becomes; what each call's callee lets through (a visit
||| that looks for a callee fails at it); and how the levels move.
public export
record Visit (g : Type -> Type) (n, m : Nat) where
  constructor MkVisit
  var : Fin n -> g (Fin m)
  call : FnId -> g ()
  levels : Levels

%prefix_record_projections on

||| The visit under a binder of `k` variables: the binder's own stay.
underVisit : Applicative g => {k : Nat} -> Visit g n m -> Visit g (Under k n) (Under k m)
underVisit v = MkVisit (\x => case splitUnder {k} x of
                                Left i => pure (Bound {n = m} i)
                                Right y => Free {k} <$> v.var y)
                       v.call v.levels

mutual
  ||| A term visited: each variable as the visit makes it, each callee
  ||| shown to it, each level moved as it says, left to right.
  export
  visitTerm : Applicative g => Visit g n m -> TermAt js n -> g (TermAt js m)
  visitTerm v (Var l x) = Var l <$> v.var x
  visitTerm v (Literal l x) = pure (Literal l x)
  visitTerm v (PrimApp l p stands as) = PrimApp l (movedPrim v.levels p) stands <$> visitVect v as
  visitTerm v (Effect l p gives as w res) = (\as', w' => Effect l p gives as' w' res) <$> visitVect v as <*> visitTerm v w
  visitTerm v (Call l c stands is as) = v.call c.fn *> (Call l c stands (movedTerms v.levels is) <$> visitVect v as)
  visitTerm v (ConApp l c bs as) = ConApp l c (movedTerms v.levels bs) <$> visitVect v as
  visitTerm v (Let l x b val body) = Let l x (movedLet v.levels b) <$> visitTerm v val <*> visitTerm (underVisit {k = 1} v) body
  visitTerm v (Case l fam x arms) = Case l fam <$> v.var x <*> visitArms v arms
  visitTerm v (CaseLit l x arms) = CaseLit l <$> v.var x <*> visitLitArms v arms
  visitTerm v (CaseNat l x arms) = CaseNat l <$> v.var x <*> visitNatArms v arms
  visitTerm v (Lam l x b body) = Lam l x (movedBinder v.levels b) <$> visitTerm (underVisit {k = 1} v) body
  visitTerm v (App l f x) = App l <$> visitTerm v f <*> visitTerm v x
  visitTerm v (Suspend l t body) = Suspend l (movedTy v.levels t) <$> visitTerm v body
  visitTerm v (Resume l e) = Resume l <$> visitTerm v e
  visitTerm v (Unreachable l) = pure (Unreachable l)
  visitTerm v (Assume l a b body) = Assume l (moved v.levels a) (moved v.levels b) <$> visitTerm v body
  visitTerm v (Crash l m) = pure (Crash l m)
  visitTerm v (CrashWith l m) = CrashWith l <$> visitTerm v m
  visitTerm v (NewWorld l) = pure (NewWorld l)
  visitTerm v (Tensor l op) = Tensor l <$> visitOp v op
  visitTerm v (Tabulate {k} l ty es body) =
    Tabulate l (movedTy v.levels ty) <$> visitVect v es <*> visitTerm (underVisit {k} v) body
  visitTerm v (TabulateIO {k} l ty es w body step done) =
    (\es', w', body' => TabulateIO l (movedTy v.levels ty) es' w' body' step done)
      <$> visitVect v es <*> visitTerm v w <*> visitTerm (underVisit {k = S k} v) body
  visitTerm v (Reduce l red acc el ty a j z x body) =
    Reduce l red (movedTy v.levels acc) (movedTy v.levels el) (movedTy v.levels ty) (movedArray v.levels a) j
      <$> visitTerm v z <*> visitTerm v x <*> visitTerm (underVisit {k = 2} v) body
  visitTerm v (Tie l t x ds) = Tie l (movedTy v.levels t) <$> visitTerm v x <*> visitStated v ds
  visitTerm v (ReadBack l e x cs body) =
    ReadBack l (movedTy v.levels e) <$> visitTerm v x <*> visitAll v cs <*> visitTerm (underVisit {k = 2} v) body
  visitTerm v (ExtentsBack {k} l x body) = ExtentsBack l <$> visitTerm v x <*> visitTerm (underVisit {k = S k} v) body
  visitTerm v (Join {nonEmpty} l scope targets body) =
    (\targets', body' => Join {nonEmpty} l scope targets' body') <$> visitTargets v targets <*> visitTerm v body
  visitTerm v (Jump l e terms as) = Jump l e (movedTerms v.levels terms) <$> visitVect v as

  visitAll : Applicative g => Visit g n m -> List (TermAt js n) -> g (List (TermAt js m))
  visitAll v [] = pure []
  visitAll v (t :: ts) = (::) <$> visitTerm v t <*> visitAll v ts

  visitVect : Applicative g => Visit g n m -> Vect k (TermAt js n) -> g (Vect k (TermAt js m))
  visitVect v [] = pure []
  visitVect v (t :: ts) = (::) <$> visitTerm v t <*> visitVect v ts

  visitOp : Applicative g => Visit g n m -> TensorOp (TermAt js n) -> g (TensorOp (TermAt js m))
  visitOp v (Extent a j x) = Extent (movedArray v.levels a) j <$> visitTerm v x
  visitOp v (Extract a rt x cs) =
    Extract (movedArray v.levels a) (movedTy v.levels rt) <$> visitTerm v x <*> visitAll v cs
  visitOp v (Insert a rt x y cs) =
    Insert (movedArray v.levels a) (movedTy v.levels rt) <$> visitTerm v x <*> visitTerm v y <*> visitAll v cs
  visitOp v (Take a ra j c x) = Take (movedArray v.levels a) (movedArray v.levels ra) j <$> visitTerm v c <*> visitTerm v x
  visitOp v (Drop a ra j c x) = Drop (movedArray v.levels a) (movedArray v.levels ra) j <$> visitTerm v c <*> visitTerm v x
  visitOp v (Concat a b ra j x y) =
    Concat (movedArray v.levels a) (movedArray v.levels b) (movedArray v.levels ra) j <$> visitTerm v x <*> visitTerm v y
  visitOp v (Transpose a rt j x) = Transpose (movedArray v.levels a) (movedTy v.levels rt) j <$> visitTerm v x
  visitOp v (Reshape a rt x es) = Reshape (movedArray v.levels a) (movedTy v.levels rt) <$> visitTerm v x <*> visitAll v es

  visitStated : Applicative g => Visit g n m -> List (Nat, Stated (TermAt js n)) -> g (List (Nat, Stated (TermAt js m)))
  visitStated v [] = pure []
  visitStated v ((a, SameAs t) :: ds) = (\t', ds' => (a, SameAs t') :: ds') <$> visitTerm v t <*> visitStated v ds
  visitStated v ((a, Natural t) :: ds) = (\t', ds' => (a, Natural t') :: ds') <$> visitTerm v t <*> visitStated v ds

  visitLits : Applicative g => Visit g n m -> List (kt, TermAt js n) -> g (List (kt, TermAt js m))
  visitLits v [] = pure []
  visitLits v ((kv, t) :: rest) = (\t', rest' => (kv, t') :: rest') <$> visitTerm v t <*> visitLits v rest

  visitKeyed : Applicative g => Visit g n m -> LitArmsOf kt (TermAt js n) -> g (LitArmsOf kt (TermAt js m))
  visitKeyed v (LitDefault ((kv, t) ::: alts) d) =
    (\t', alts', d' => LitDefault ((kv, t') ::: alts') d') <$> visitTerm v t <*> visitLits v alts <*> visitTerm v d
  visitKeyed v (LitNoDefault ((kv, t) ::: alts)) =
    (\t', alts' => LitNoDefault ((kv, t') ::: alts')) <$> visitTerm v t <*> visitLits v alts

  visitLitArms : Applicative g => Visit g n m -> LitMatch (TermAt js n) -> g (LitMatch (TermAt js m))
  visitLitArms v (OnlyDefault d) = OnlyDefault <$> visitTerm v d
  visitLitArms v (OnInts t arms) = OnInts t <$> visitKeyed v arms
  visitLitArms v (OnChars arms) = OnChars <$> visitKeyed v arms
  visitLitArms v (OnStrings arms) = OnStrings <$> visitKeyed v arms
  visitLitArms v (OnBigs arms) = OnBigs <$> visitKeyed v arms

  visitNatArms : Applicative g => Visit g n m -> NatArmsOf (TermAt js n) (TermAt js (Under 1 n)) ->
                 g (NatArmsOf (TermAt js m) (TermAt js (Under 1 m)))
  visitNatArms v (OnlyZero z) = OnlyZero <$> visitTerm v z
  visitNatArms v (OnlySucc p s) = OnlySucc p <$> visitTerm (underVisit {k = 1} v) s
  visitNatArms v (Both z p s) = (\z', s' => Both z' p s') <$> visitTerm v z <*> visitTerm (underVisit {k = 1} v) s

  visitAlt : Applicative g => Visit g n m -> AltAt js n -> g (AltAt js m)
  visitAlt v (MkAlt {k} c fs body) = MkAlt c fs <$> visitTerm (underVisit {k} v) body

  visitAlts : Applicative g => Visit g n m -> List (AltAt js n) -> g (List (AltAt js m))
  visitAlts v [] = pure []
  visitAlts v (alt :: alts) = (::) <$> visitAlt v alt <*> visitAlts v alts

  visitArms : Applicative g => Visit g n m -> CaseArmsOf (AltAt js n) (TermAt js n) ->
              g (CaseArmsOf (AltAt js m) (TermAt js m))
  visitArms v (Defaulted alts d) = Defaulted <$> visitAlts v alts <*> visitTerm v d
  visitArms v (Exhaustive (alt ::: alts)) = (\a, as => Exhaustive (a ::: as)) <$> visitAlt v alt <*> visitAlts v alts

  visitTargets : Applicative g => Visit g n m -> All (Target s n) ts -> g (All (Target s m) ts)
  visitTargets v [] = pure []
  visitTargets v (t :: rest) = (::) <$> visitTarget v t <*> visitTargets v rest

  visitTarget : Applicative g => Visit g n m -> Target s n k -> g (Target s m k)
  visitTarget v (MkTarget {k} l code sorts names params body) =
    MkTarget {k} l code (map (movedSort v.levels) sorts) names (map (movedBinder v.levels) params)
      <$> visitTerm (underVisit {k} v) body

||| The term with each variable renamed.
export
rename : (Fin n -> Fin m) -> TermAt js n -> TermAt js m
rename f t = runIdentity (visitTerm (MkVisit (\x => Id (f x)) (\_ => Id ()) Unmoved) t)

||| The term under a binder of `k` variables it does not use.
export
weakenUnder : (k : Nat) -> TermAt js n -> TermAt js (Under k n)
weakenUnder k = rename (Free {k})

||| What a visit that only reads collects: the callees it met, in order.
record Collected (a : Type) where
  constructor Collect
  callees : SnocList FnId

Functor Collected where
  map f (Collect cs) = Collect cs

Applicative Collected where
  pure _ = Collect [<]
  Collect a <*> Collect b = Collect (a ++ b)

||| Every callee a term calls, in the order its calls are written, each as
||| often as it is called.
export
calleesOf : TermAt js n -> List FnId
calleesOf t = (visitTerm (the (Visit Collected n n) (MkVisit (\_ => Collect [<]) (\fn => Collect [< fn]) Unmoved)) t).callees <>> []

------------------------------------------------------------------------------
-- The base functor and its folds
------------------------------------------------------------------------------

mutual
  ||| One layer of `TermAt`, its subterms replaced by `f` at the join
  ||| points they see and at their scopes: a higher-order base functor,
  ||| since a subterm under a binder is in a larger scope than the term
  ||| itself, and one in no tail position sees no join point.
  public export
  data TermF : (List Nat -> Nat -> Type) -> List Nat -> Nat -> Type where
    VarF : Loc -> Fin n -> TermF f js n
    LiteralF : Loc -> Lit -> TermF f js n
    PrimAppF : {k : Nat} -> Loc -> Prim k -> Maybe Shown -> Vect k (f [] n) -> TermF f js n
    EffectF : {i, o : Nat} -> Loc -> IOAction i o -> IOGives o -> Vect i (f [] n) -> f [] n -> Con 2 -> TermF f js n
    CallF : {arity : Nat} -> Loc -> Callee arity -> Maybe Shown -> List ITerm -> Vect arity (f [] n) -> TermF f js n
    ConAppF : {k : Nat} -> Loc -> Con k -> List ITerm -> Vect k (f [] n) -> TermF f js n
    LetF : Loc -> Shown -> LetBinder -> f [] n -> f js (Under 1 n) -> TermF f js n
    CaseF : Loc -> FamilyId -> Fin n -> CaseArmsOf (AltF f js n) (f js n) -> TermF f js n
    CaseLitF : Loc -> Fin n -> LitMatch (f js n) -> TermF f js n
    CaseNatF : Loc -> Fin n -> NatArmsOf (f js n) (f js (Under 1 n)) -> TermF f js n
    LamF : Loc -> Shown -> Binder -> f [] (Under 1 n) -> TermF f js n
    AppF : Loc -> f [] n -> f [] n -> TermF f js n
    SuspendF : Loc -> Ty -> f [] n -> TermF f js n
    ResumeF : Loc -> f [] n -> TermF f js n
    UnreachableF : Loc -> TermF f js n
    AssumeF : Loc -> ITerm -> ITerm -> f js n -> TermF f js n
    CrashF : Loc -> Cause -> TermF f js n
    CrashWithF : Loc -> f [] n -> TermF f js n
    NewWorldF : Loc -> TermF f js n
    TensorF : Loc -> TensorOp (f [] n) -> TermF f js n
    TabulateF : {k : Nat} -> Loc -> Ty -> Vect k (f [] n) -> f [] (Under k n) -> TermF f js n
    TabulateIOF : {k : Nat} -> Loc -> Ty -> Vect k (f [] n) -> f [] n -> f [] (Under (S k) n) -> Con 2 -> Con 2 ->
                  TermF f js n
    ReduceF : {0 r : Nat} -> Loc -> Reduction -> Ty -> Ty -> Ty -> ArrayType r -> Fin r -> f [] n -> f [] n ->
              f [] (Under 2 n) -> TermF f js n
    TieF : Loc -> Ty -> f [] n -> List (Nat, Stated (f [] n)) -> TermF f js n
    ReadBackF : Loc -> Ty -> f [] n -> List (f [] n) -> f js (Under 2 n) -> TermF f js n
    ExtentsBackF : {k : Nat} -> Loc -> f [] n -> f js (Under (S k) n) -> TermF f js n
    JoinF : {0 ts : List Nat} -> Loc -> (scope : TokenScope) -> All (TargetF f (regionsSee scope js ts) n) ts ->
            f (js ++ ts) n -> TermF f js n
    JumpF : {k : Nat} -> Loc -> Elem k js -> List ITerm -> Vect k (f [] n) -> TermF f js n

  public export
  data AltF : (List Nat -> Nat -> Type) -> List Nat -> Nat -> Type where
    MkAltF : {k : Nat} -> Con k -> Vect k Shown -> f js (Under k n) -> AltF f js n

  public export
  data TargetF : (List Nat -> Nat -> Type) -> List Nat -> Nat -> Nat -> Type where
    MkTargetF : {k : Nat} -> Loc -> CodeOf -> List Sort -> Vect k Shown -> Vect k Binder -> f s (Under k n) ->
                TargetF f s n k

||| A subterm as it was, with what the fold made of it (for `para`).
public export
record Sub (f : List Nat -> Nat -> Type) (js : List Nat) (n : Nat) where
  constructor MkSub
  term : TermAt js n
  result : f js n

||| The action of `TermF` on a natural transformation.
export
hmap : ({0 js' : List Nat} -> {0 m : Nat} -> f js' m -> g js' m) -> TermF f js n -> TermF g js n
hmap h (VarF l x) = VarF l x
hmap h (LiteralF l x) = LiteralF l x
hmap h (PrimAppF l p stands as) = PrimAppF l p stands (map h as)
hmap h (EffectF l p gives as w res) = EffectF l p gives (map h as) (h w) res
hmap h (CallF l c stands is as) = CallF l c stands is (map h as)
hmap h (ConAppF l c bs as) = ConAppF l c bs (map h as)
hmap h (LetF l x b v body) = LetF l x b (h v) (h body)
hmap h (CaseF l fam x arms) = CaseF l fam x (armsMap arms)
  where
    alt : AltF f js n -> AltF g js n
    alt (MkAltF c fs b) = MkAltF c fs (h b)
    armsMap : CaseArmsOf (AltF f js n) (f js n) -> CaseArmsOf (AltF g js n) (g js n)
    armsMap (Defaulted alts d) = Defaulted (map alt alts) (h d)
    armsMap (Exhaustive alts) = Exhaustive (map alt alts)
hmap h (CaseLitF l x arms) = CaseLitF l x (matchMap arms)
  where
    keyed : LitArmsOf kt (f js n) -> LitArmsOf kt (g js n)
    keyed (LitDefault alts d) = LitDefault (map (\(kv, e) => (kv, h e)) alts) (h d)
    keyed (LitNoDefault alts) = LitNoDefault (map (\(kv, e) => (kv, h e)) alts)
    matchMap : LitMatch (f js n) -> LitMatch (g js n)
    matchMap (OnlyDefault d) = OnlyDefault (h d)
    matchMap (OnInts t a) = OnInts t (keyed a)
    matchMap (OnChars a) = OnChars (keyed a)
    matchMap (OnStrings a) = OnStrings (keyed a)
    matchMap (OnBigs a) = OnBigs (keyed a)
hmap h (CaseNatF l x arms) = CaseNatF l x (armsMap arms)
  where
    armsMap : NatArmsOf (f js n) (f js (Under 1 n)) -> NatArmsOf (g js n) (g js (Under 1 n))
    armsMap (OnlyZero z) = OnlyZero (h z)
    armsMap (OnlySucc p s) = OnlySucc p (h s)
    armsMap (Both z p s) = Both (h z) p (h s)
hmap h (LamF l x b body) = LamF l x b (h body)
hmap h (AppF l f x) = AppF l (h f) (h x)
hmap h (SuspendF l t body) = SuspendF l t (h body)
hmap h (ResumeF l e) = ResumeF l (h e)
hmap h (UnreachableF l) = UnreachableF l
hmap h (AssumeF l a b body) = AssumeF l a b (h body)
hmap h (CrashF l m) = CrashF l m
hmap h (CrashWithF l m) = CrashWithF l (h m)
hmap h (NewWorldF l) = NewWorldF l
hmap h (TensorF l op) = TensorF l (map h op)
hmap h (TabulateF l ty es body) = TabulateF l ty (map h es) (h body)
hmap h (TabulateIOF l ty es w body step done) = TabulateIOF l ty (map h es) (h w) (h body) step done
hmap h (ReduceF l red acc el ty a j z x body) = ReduceF l red acc el ty a j (h z) (h x) (h body)
hmap h (TieF l t x ds) = TieF l t (h x) (map (\(a, s) => (a, map h s)) ds)
hmap h (ReadBackF l e x cs body) = ReadBackF l e (h x) (map h cs) (h body)
hmap h (ExtentsBackF l x body) = ExtentsBackF l (h x) (h body)
hmap h (JoinF l scope targets body) = JoinF l scope (targetsMap targets) (h body)
  where
    targetsMap : All (TargetF f s n) ts' -> All (TargetF g s n) ts'
    targetsMap [] = []
    targetsMap (MkTargetF {k} tl code sorts names params b :: rest) =
      MkTargetF {k} tl code sorts names params (h b) :: targetsMap rest
hmap h (JumpF l e terms as) = JumpF l e terms (map h as)

mutual
  ||| The paramorphism: each layer with its subterms as they were and as the
  ||| algebra made them.
  export
  para : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
         TermAt js n -> f js n
  para alg (Var l x) = alg (VarF l x)
  para alg (Literal l x) = alg (LiteralF l x)
  para alg (PrimApp l p stands as) = alg (PrimAppF l p stands (paraVect alg as))
  para alg (Effect l p gives as w res) = alg (EffectF l p gives (paraVect alg as) (sub alg w) res)
  para alg (Call l c stands is as) = alg (CallF l c stands is (paraVect alg as))
  para alg (ConApp l c bs as) = alg (ConAppF l c bs (paraVect alg as))
  para alg (Let l x b v body) = alg (LetF l x b (sub alg v) (sub alg body))
  para alg (Case l fam x arms) = alg (CaseF l fam x (paraArms alg arms))
  para alg (CaseLit l x arms) = alg (CaseLitF l x (paraLitArms alg arms))
  para alg (CaseNat l x arms) = alg (CaseNatF l x (paraNatArms alg arms))
  para alg (Lam l x b body) = alg (LamF l x b (sub alg body))
  para alg (App l f x) = alg (AppF l (sub alg f) (sub alg x))
  para alg (Suspend l t body) = alg (SuspendF l t (sub alg body))
  para alg (Resume l e) = alg (ResumeF l (sub alg e))
  para alg (Unreachable l) = alg (UnreachableF l)
  para alg (Assume l a b body) = alg (AssumeF l a b (sub alg body))
  para alg (Crash l m) = alg (CrashF l m)
  para alg (CrashWith l m) = alg (CrashWithF l (sub alg m))
  para alg (NewWorld l) = alg (NewWorldF l)
  para alg (Tensor l op) = alg (TensorF l (paraOp alg op))
  para alg (Tabulate l ty es body) = alg (TabulateF l ty (paraVect alg es) (sub alg body))
  para alg (TabulateIO l ty es w body step done) =
    alg (TabulateIOF l ty (paraVect alg es) (sub alg w) (sub alg body) step done)
  para alg (Reduce l red acc el ty a j z x body) = alg (ReduceF l red acc el ty a j (sub alg z) (sub alg x) (sub alg body))
  para alg (Tie l t x ds) = alg (TieF l t (sub alg x) (paraStated alg ds))
  para alg (ReadBack l e x cs body) = alg (ReadBackF l e (sub alg x) (paraAll alg cs) (sub alg body))
  para alg (ExtentsBack l x body) = alg (ExtentsBackF l (sub alg x) (sub alg body))
  para alg (Join l scope targets body) = alg (JoinF l scope (paraTargets alg targets) (sub alg body))
  para alg (Jump l e terms as) = alg (JumpF l e terms (paraVect alg as))

  sub : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
        TermAt js n -> Sub f js n
  sub alg t = MkSub t (para alg t)

  paraAll : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
            List (TermAt js n) -> List (Sub f js n)
  paraAll alg [] = []
  paraAll alg (t :: ts) = sub alg t :: paraAll alg ts

  paraVect : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
             Vect k (TermAt js n) -> Vect k (Sub f js n)
  paraVect alg [] = []
  paraVect alg (t :: ts) = sub alg t :: paraVect alg ts

  paraOp : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
           TensorOp (TermAt js n) -> TensorOp (Sub f js n)
  paraOp alg (Extent a j x) = Extent a j (sub alg x)
  paraOp alg (Extract a rt x cs) = Extract a rt (sub alg x) (paraAll alg cs)
  paraOp alg (Insert a rt x v cs) = Insert a rt (sub alg x) (sub alg v) (paraAll alg cs)
  paraOp alg (Take a ra j k x) = Take a ra j (sub alg k) (sub alg x)
  paraOp alg (Drop a ra j k x) = Drop a ra j (sub alg k) (sub alg x)
  paraOp alg (Concat a b ra j x y) = Concat a b ra j (sub alg x) (sub alg y)
  paraOp alg (Transpose a rt j x) = Transpose a rt j (sub alg x)
  paraOp alg (Reshape a rt x es) = Reshape a rt (sub alg x) (paraAll alg es)

  paraStated : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
               List (Nat, Stated (TermAt js n)) -> List (Nat, Stated (Sub f js n))
  paraStated alg [] = []
  paraStated alg ((a, SameAs t) :: ds) = (a, SameAs (sub alg t)) :: paraStated alg ds
  paraStated alg ((a, Natural t) :: ds) = (a, Natural (sub alg t)) :: paraStated alg ds

  paraLits : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
             List (kt, TermAt js n) -> List (kt, Sub f js n)
  paraLits alg [] = []
  paraLits alg ((kv, t) :: rest) = (kv, sub alg t) :: paraLits alg rest

  paraKeyed : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
              LitArmsOf kt (TermAt js n) -> LitArmsOf kt (Sub f js n)
  paraKeyed alg (LitDefault ((kv, t) ::: alts) d) = LitDefault ((kv, sub alg t) ::: paraLits alg alts) (sub alg d)
  paraKeyed alg (LitNoDefault ((kv, t) ::: alts)) = LitNoDefault ((kv, sub alg t) ::: paraLits alg alts)

  paraLitArms : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
                LitMatch (TermAt js n) -> LitMatch (Sub f js n)
  paraLitArms alg (OnlyDefault d) = OnlyDefault (sub alg d)
  paraLitArms alg (OnInts t arms) = OnInts t (paraKeyed alg arms)
  paraLitArms alg (OnChars arms) = OnChars (paraKeyed alg arms)
  paraLitArms alg (OnStrings arms) = OnStrings (paraKeyed alg arms)
  paraLitArms alg (OnBigs arms) = OnBigs (paraKeyed alg arms)

  paraNatArms : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
                NatArmsOf (TermAt js n) (TermAt js (Under 1 n)) -> NatArmsOf (Sub f js n) (Sub f js (Under 1 n))
  paraNatArms alg (OnlyZero z) = OnlyZero (sub alg z)
  paraNatArms alg (OnlySucc p s) = OnlySucc p (sub alg s)
  paraNatArms alg (Both z p s) = Both (sub alg z) p (sub alg s)

  paraAlt : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
            AltAt js n -> AltF (Sub f) js n
  paraAlt alg (MkAlt c fs body) = MkAltF c fs (sub alg body)

  paraAlts : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
             List (AltAt js n) -> List (AltF (Sub f) js n)
  paraAlts alg [] = []
  paraAlts alg (alt :: rest) = paraAlt alg alt :: paraAlts alg rest

  paraArms : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
             CaseArmsOf (AltAt js n) (TermAt js n) -> CaseArmsOf (AltF (Sub f) js n) (Sub f js n)
  paraArms alg (Defaulted alts d) = Defaulted (paraAlts alg alts) (sub alg d)
  paraArms alg (Exhaustive (alt ::: alts)) = Exhaustive (paraAlt alg alt ::: paraAlts alg alts)

  paraTargets : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
                All (Target s n) ts -> All (TargetF (Sub f) s n) ts
  paraTargets alg [] = []
  paraTargets alg (t :: rest) = paraTarget alg t :: paraTargets alg rest

  paraTarget : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF (Sub f) js' m -> f js' m) ->
               Target s n k -> TargetF (Sub f) s n k
  paraTarget alg (MkTarget {k} l code sorts names params body) = MkTargetF {k} l code sorts names params (sub alg body)

||| The catamorphism: each layer with what the algebra made of its subterms.
export
cata : {0 f : List Nat -> Nat -> Type} -> ({0 js' : List Nat} -> {0 m : Nat} -> TermF f js' m -> f js' m) ->
       TermAt js n -> f js n
cata alg = para (\layer => alg (hmap (.result) layer))

------------------------------------------------------------------------------
-- Join points the program as written makes
------------------------------------------------------------------------------

||| A type that is an action: a function of the world, which it takes at
||| the quantity its binder gives, to what the action gives.
public export
data ActionType : Ty -> Type where
  OnWorld : (world : Uses) -> (gives : Ty) -> ActionType (FunT (MkBinder world WorldT) gives)

||| The evidence that a type is an action, where it is one.
export
actionType : (t : Ty) -> Maybe (ActionType t)
actionType (FunT (MkBinder q WorldT) r) = Just (OnWorld q r)
actionType _ = Nothing

||| A continuation the program as written makes, as its uses are written in
||| a term of scope `n`, which becomes one of scope `m` without it: a
||| variable applied to `k` arguments (a `let` of a lambda of `k`
||| parameters), the one variable `without` takes out; a call of a local
||| definition of `k` parameters, by the callee every call of it holds; or
||| such a call whose result is an action, applied to the world, which is
||| the action's call saturated with the world, its `k` arguments and the
||| world the join point's.
public export
data Continuation : (n, m, k : Nat) -> Type where
  Applying : (without : Fin n -> Maybe (Fin m)) -> Continuation n m k
  Calling : Callee k -> Continuation n n k
  Running : (c : Callee k) -> (0 _ : ActionType c.result) -> Continuation n n (S k)

||| The continuation under a binder of `j` variables: the binder's own are
||| none of it.
underCont : {j : Nat} -> Continuation n m k -> Continuation (Under j n) (Under j m) k
underCont (Applying without) = Applying (\x => case splitUnder {k = j} x of
                                               Left i => Just (Bound {n = m} i)
                                               Right y => Free {k = j} <$> without y)
underCont (Calling c) = Calling c
underCont (Running c a) = Running c a

||| A position no tail of the term reaches, visited for a use of the
||| continuation, which such a position may not hold: it would be the
||| continuation as a value, or a call that returns.
awayFrom : Continuation n m k -> Visit Maybe n m
awayFrom (Applying without) = MkVisit without (\_ => Just ()) Unmoved
awayFrom (Calling c) = MkVisit Just (\fn => if fn == c.fn then Nothing else Just ()) Unmoved
awayFrom (Running c _) = MkVisit Just (\fn => if fn == c.fn then Nothing else Just ()) Unmoved

||| The head of an application and its arguments, the first first.
headOf : TermAt [] n -> List (TermAt [] n) -> (TermAt [] n, List (TermAt [] n))
headOf (App _ f x) args = headOf f (x :: args)
headOf h args = (h, args)

||| A tie's operand inside every tie around it, and what each of those ties
||| states, the innermost's first.
throughTies : TermAt [] n -> List (Nat, Stated (TermAt [] n)) -> (TermAt [] n, List (Nat, Stated (TermAt [] n)))
throughTies (Tie _ _ x ds) stated = throughTies x (ds ++ stated)
throughTies x stated = (x, stated)

||| What the head of a tail is to a continuation: a use of it, which is a
||| jump where it is saturated and its arguments hold no use (nothing
||| otherwise); or no use, and the tail is visited as any other term.
data HeadOf : (k : Nat) -> (js : List Nat) -> (m : Nat) -> Type where
  UseOf : Maybe (TermAt (k :: js) m) -> HeadOf k js m
  NoUse : HeadOf k js m

||| A call at a tail, to a continuation: a use where it calls the local
||| definition with all its parameters.
callHead : {k, arity : Nat} -> Continuation n m k -> Loc -> Callee arity -> List ITerm -> Vect arity (TermAt [] n) ->
           HeadOf k js m
callHead c@(Calling target) l callee is as =
  if callee.fn == target.fn
     -- Every call of a callee holds the one signature its function is made
     -- with, so its arity is the continuation's: the check says to the
     -- types what the identity says already.
     then UseOf (case decEq arity k of
                   Yes Refl => Jump l Here is <$> visitVect (awayFrom c) as
                   No _ => Nothing)
     else NoUse
callHead _ _ _ _ _ = NoUse

||| An application at a tail, to a continuation: a use where it applies the
||| `let`'s variable, or where it applies a call of the local definition
||| whose result is an action to the world, which is that call saturated
||| with the world.
appHead : {k : Nat} -> Continuation n m k -> Loc -> TermAt [] n -> TermAt [] n -> HeadOf k js m
appHead c@(Applying without) l f x = case headOf f [x] of
  (Var _ v, args) => case without v of
    Nothing => UseOf (toVect k args >>= \as => Jump l Here [] <$> visitVect (awayFrom c) as)
    Just _ => NoUse
  _ => NoUse
appHead c@(Running target _) l f x = case headOf f [x] of
  (Call {arity} _ callee _ is as, [world]) =>
    if callee.fn == target.fn
       then UseOf (case decEq (S arity) k of
                     Yes Refl => Jump l Here is <$> (snoc <$> visitVect (awayFrom c) as <*> visitTerm (awayFrom c) world)
                     No _ => Nothing)
       else NoUse
  _ => NoUse
appHead (Calling _) _ _ _ = NoUse

||| The head of a tie's operand at a tail, to a continuation: a call, read
||| as it is at a tail, since a tie gives its array on with no work. Only a
||| call's value is tied there, by what its callee's signature fixes, which
||| the callee's region states again (`tiedExits`); any other operand is
||| no tail.
tiedHead : {k : Nat} -> Continuation n m k -> TermAt [] n -> HeadOf k js m
tiedHead c (Call {arity} l callee _ is as) = callHead {arity} c l callee is as
tiedHead c _ = NoUse

mutual
  ||| The term with each use of the continuation a jump to it, the
  ||| outermost join point its tails see, those they saw already after it:
  ||| each use a tail position's head of a saturated application (a call of
  ||| the callee, the variable applied to `k` arguments, or the action a
  ||| call gives applied to the world) whose arguments hold no use, read
  ||| through the ties around it. Nothing where a use is anywhere else,
  ||| which makes the continuation a value and no join point. The test reads
  ||| the term alone, total, with no budget.
  export
  jumpsTo : {k : Nat} -> Continuation n m k -> TermAt js n -> Maybe (TermAt (k :: js) m)
  jumpsTo c (Var l x) = Var l <$> (awayFrom c).var x
  jumpsTo c (Literal l x) = pure (Literal l x)
  jumpsTo c (PrimApp l p stands as) = PrimApp l p stands <$> visitVect (awayFrom c) as
  jumpsTo c (Effect l p gives as w res) =
    (\as', w' => Effect l p gives as' w' res) <$> visitVect (awayFrom c) as <*> visitTerm (awayFrom c) w
  jumpsTo c (Call {arity} l callee stands is as) = case callHead {arity} c l callee is as of
    UseOf jump => jump
    NoUse => Call l callee stands is <$> ((awayFrom c).call callee.fn *> visitVect (awayFrom c) as)
  jumpsTo c (ConApp l con bs as) = ConApp l con bs <$> visitVect (awayFrom c) as
  jumpsTo c (Let l x b v body) = Let l x b <$> visitTerm (awayFrom c) v <*> jumpsTo (underCont {j = 1} c) body
  jumpsTo c (Case l fam x arms) = Case l fam <$> (awayFrom c).var x <*> jumpsArms c arms
  jumpsTo c (CaseLit l x arms) = CaseLit l <$> (awayFrom c).var x <*> jumpsLitArms c arms
  jumpsTo c (CaseNat l x arms) = CaseNat l <$> (awayFrom c).var x <*> jumpsNatArms c arms
  jumpsTo c (Lam l x b body) = Lam l x b <$> visitTerm (underVisit {k = 1} (awayFrom c)) body
  jumpsTo c (App l f x) = case appHead c l f x of
    UseOf jump => jump
    NoUse => App l <$> visitTerm (awayFrom c) f <*> visitTerm (awayFrom c) x
  jumpsTo c (Suspend l t body) = Suspend l t <$> visitTerm (awayFrom c) body
  jumpsTo c (Resume l e) = Resume l <$> visitTerm (awayFrom c) e
  jumpsTo c (Unreachable l) = pure (Unreachable l)
  jumpsTo c (Assume l a b body) = Assume l a b <$> jumpsTo c body
  jumpsTo c (Crash l m) = pure (Crash l m)
  jumpsTo c (CrashWith l m) = CrashWith l <$> visitTerm (awayFrom c) m
  jumpsTo c (NewWorld l) = pure (NewWorld l)
  jumpsTo c (Tensor l op) = Tensor l <$> visitOp (awayFrom c) op
  jumpsTo c (Tabulate {k = j} l ty es body) =
    Tabulate l ty <$> visitVect (awayFrom c) es <*> visitTerm (underVisit {k = j} (awayFrom c)) body
  jumpsTo c (TabulateIO {k = j} l ty es w body step done) =
    (\es', w', body' => TabulateIO l ty es' w' body' step done)
      <$> visitVect (awayFrom c) es <*> visitTerm (awayFrom c) w <*> visitTerm (underVisit {k = S j} (awayFrom c)) body
  jumpsTo c (Reduce l red acc el ty a j z x body) =
    Reduce l red acc el ty a j <$> visitTerm (awayFrom c) z <*> visitTerm (awayFrom c) x
                               <*> visitTerm (underVisit {k = 2} (awayFrom c)) body
  -- A tie gives its array on with no work, so a use inside the ties at a
  -- tail is at the tail. What they state of the call's value is stated
  -- where the join point's region gives that value (`tiedExits`), over its
  -- parameters, which the jump's arguments are; here it states nothing
  -- more, and holds no use.
  jumpsTo c (Tie l t x ds) = case throughTies x ds of
    (inner, stated) => case tiedHead c inner of
      UseOf jump => const <$> jump <*> visitStated (awayFrom c) stated
      NoUse => Tie l t <$> visitTerm (awayFrom c) x <*> visitStated (awayFrom c) ds
  jumpsTo c (ReadBack l e x cs body) =
    ReadBack l e <$> visitTerm (awayFrom c) x <*> visitAll (awayFrom c) cs <*> jumpsTo (underCont {j = 2} c) body
  jumpsTo c (ExtentsBack {k = j} l x body) =
    ExtentsBack l <$> visitTerm (awayFrom c) x <*> jumpsTo (underCont {j = S j} c) body
  -- A join op's regions and body are tails of the op; the join points they
  -- see gain the continuation's, outermost.
  jumpsTo c (Join {nonEmpty} l InBody targets body) =
    (\targets', body' => Join {nonEmpty} l InBody targets' body') <$> jumpsTargets c targets <*> jumpsTo c body
  jumpsTo c (Join {nonEmpty} l InEveryRegion targets body) =
    (\targets', body' => Join {nonEmpty} l InEveryRegion targets' body') <$> jumpsTargets c targets <*> jumpsTo c body
  jumpsTo c (Jump l e terms as) = Jump l (There e) terms <$> visitVect (awayFrom c) as

  jumpsArms : {k : Nat} -> Continuation n m k -> CaseArmsOf (AltAt js n) (TermAt js n) ->
              Maybe (CaseArmsOf (AltAt (k :: js) m) (TermAt (k :: js) m))
  jumpsArms c (Defaulted alts d) = Defaulted <$> jumpsAlts c alts <*> jumpsTo c d
  jumpsArms c (Exhaustive (alt ::: alts)) = (\a, as => Exhaustive (a ::: as)) <$> jumpsAlt c alt <*> jumpsAlts c alts

  jumpsAlt : {k : Nat} -> Continuation n m k -> AltAt js n -> Maybe (AltAt (k :: js) m)
  jumpsAlt c (MkAlt {k = j} con fs body) = MkAlt con fs <$> jumpsTo (underCont {j} c) body

  jumpsAlts : {k : Nat} -> Continuation n m k -> List (AltAt js n) -> Maybe (List (AltAt (k :: js) m))
  jumpsAlts c [] = pure []
  jumpsAlts c (alt :: alts) = (::) <$> jumpsAlt c alt <*> jumpsAlts c alts

  jumpsLits : {k : Nat} -> Continuation n m k -> List (kt, TermAt js n) -> Maybe (List (kt, TermAt (k :: js) m))
  jumpsLits c [] = pure []
  jumpsLits c ((kv, t) :: rest) = (\t', rest' => (kv, t') :: rest') <$> jumpsTo c t <*> jumpsLits c rest

  jumpsKeyed : {k : Nat} -> Continuation n m k -> LitArmsOf kt (TermAt js n) -> Maybe (LitArmsOf kt (TermAt (k :: js) m))
  jumpsKeyed c (LitDefault ((kv, t) ::: alts) d) =
    (\t', alts', d' => LitDefault ((kv, t') ::: alts') d') <$> jumpsTo c t <*> jumpsLits c alts <*> jumpsTo c d
  jumpsKeyed c (LitNoDefault ((kv, t) ::: alts)) =
    (\t', alts' => LitNoDefault ((kv, t') ::: alts')) <$> jumpsTo c t <*> jumpsLits c alts

  jumpsLitArms : {k : Nat} -> Continuation n m k -> LitMatch (TermAt js n) -> Maybe (LitMatch (TermAt (k :: js) m))
  jumpsLitArms c (OnlyDefault d) = OnlyDefault <$> jumpsTo c d
  jumpsLitArms c (OnInts t arms) = OnInts t <$> jumpsKeyed c arms
  jumpsLitArms c (OnChars arms) = OnChars <$> jumpsKeyed c arms
  jumpsLitArms c (OnStrings arms) = OnStrings <$> jumpsKeyed c arms
  jumpsLitArms c (OnBigs arms) = OnBigs <$> jumpsKeyed c arms

  jumpsNatArms : {k : Nat} -> Continuation n m k -> NatArmsOf (TermAt js n) (TermAt js (Under 1 n)) ->
                 Maybe (NatArmsOf (TermAt (k :: js) m) (TermAt (k :: js) (Under 1 m)))
  jumpsNatArms c (OnlyZero z) = OnlyZero <$> jumpsTo c z
  jumpsNatArms c (OnlySucc p s) = OnlySucc p <$> jumpsTo (underCont {j = 1} c) s
  jumpsNatArms c (Both z p s) = (\z', s' => Both z' p s') <$> jumpsTo c z <*> jumpsTo (underCont {j = 1} c) s

  jumpsTargets : {k : Nat} -> Continuation n m k -> All (Target s n) ts -> Maybe (All (Target (k :: s) m) ts)
  jumpsTargets c [] = pure []
  jumpsTargets c (t :: rest) = (::) <$> jumpsTarget c t <*> jumpsTargets c rest

  jumpsTarget : {k : Nat} -> Continuation n m k -> Target s n j -> Maybe (Target (k :: s) m j)
  jumpsTarget c (MkTarget {k = j} l code sorts names params body) =
    MkTarget {k = j} l code sorts names params <$> jumpsTo (underCont {j} c) body

||| The lambdas a term starts with, outermost first, each its name and
||| binder, and the body under them, the innermost one's parameter
||| `Bound 0`.
data Lambdas : Nat -> Type where
  MkLambdas : {k : Nat} -> Vect k (Shown, Binder) -> Term (Under k n) -> Lambdas n

lambdas : Term n -> Lambdas n
lambdas (Lam l x b body) = case lambdas body of
  MkLambdas {k} ps inner => MkLambdas ((x, b) :: ps) (replace {p = Term} (sym (plusSuccRightSucc k n)) inner)
lambdas t = MkLambdas [] t

||| The variables under a binder of `k` with the binder's own reversed: a
||| chain of lambdas binds its innermost parameter nearest, and a join
||| region, as a function does, its first.
inOrder : {k : Nat} -> Fin (Under k n) -> Fin (Under k n)
inOrder v = case splitUnder {k} v of
  Left i => Bound {n} (complement i)
  Right y => Free {k} y

||| A `let` the program writes (`Checked`): a join point when it binds a
||| lambda of `k` parameters that its body uses only as the head of an
||| application to `k` arguments in a tail position (`jumpsTo`), its region
||| the lambda's body; any other `let` a value. Every `let` that passes is
||| a join point by this test alone, so no later pass decides it.
export
letOf : Loc -> Shown -> Binder -> Term n -> Term (Under 1 n) -> Term n
letOf l x b v body = case lambdas v of
  MkLambdas {k = S j} ps inner => case jumpsTo {k = S j} (Applying dropped) body of
    Just body' => Join l InBody [MkTarget l Surrounding [] (map fst ps) (map snd ps) (rename (inOrder {k = S j}) inner)] body'
    Nothing => Let l x (Checked b) v body
  MkLambdas {k = Z} _ _ => Let l x (Checked b) v body
  where
    dropped : Fin (S n) -> Maybe (Fin n)
    dropped FZ = Nothing
    dropped (FS y) = Just y

------------------------------------------------------------------------------
-- The tails that give a term's value
------------------------------------------------------------------------------

||| What a tail knows of the join points in its scope: none, outside every
||| join op of the term; or what its type says, inside one.
public export
data Around : List Nat -> Type where
  Outermost : Around []
  UnderJoin : Around js

||| What is made of a tail that gives a term's value, in the scope `p` the
||| binders between the term and the tail make of the term's `n`, which the
||| embedding takes there: the tail, which holds no tail of its own, and
||| the term it becomes.
public export
AtTail : Nat -> Type
AtTail n = {0 js : List Nat} -> {0 p : Nat} -> Around js -> (Fin n -> Fin p) -> TermAt [] p -> TermAt js p

mutual
  ||| The term with each of its tails that gives its value made over by
  ||| `at`: through a `let`'s body, a match's arms, an assumption, a read's
  ||| body and a join op's regions and body. A jump gives its join point's
  ||| value, which that join op's regions make over, and a crash or an
  ||| unreachable gives none.
  export
  overTails : AtTail n -> Around js -> (Fin n -> Fin p) -> TermAt js p -> TermAt js p
  overTails at o e (Var l x) = at o e (Var l x)
  overTails at o e (Literal l x) = at o e (Literal l x)
  overTails at o e (PrimApp l pr stands as) = at o e (PrimApp l pr stands as)
  overTails at o e (Effect l pr gives as w res) = at o e (Effect l pr gives as w res)
  overTails at o e (Call l c stands is as) = at o e (Call l c stands is as)
  overTails at o e (ConApp l c bs as) = at o e (ConApp l c bs as)
  overTails at o e (Lam l x b body) = at o e (Lam l x b body)
  overTails at o e (App l f x) = at o e (App l f x)
  overTails at o e (Suspend l t body) = at o e (Suspend l t body)
  overTails at o e (Resume l x) = at o e (Resume l x)
  overTails at o e (NewWorld l) = at o e (NewWorld l)
  overTails at o e (Tensor l op) = at o e (Tensor l op)
  overTails at o e (Tabulate l ty es body) = at o e (Tabulate l ty es body)
  overTails at o e (TabulateIO l ty es w body step done) = at o e (TabulateIO l ty es w body step done)
  overTails at o e (Reduce l red acc el ty a j z x body) = at o e (Reduce l red acc el ty a j z x body)
  overTails at o e (Tie l t x ds) = at o e (Tie l t x ds)
  overTails at o e (Let l x b v body) = Let l x b v (overTails at o (Free {k = 1} . e) body)
  overTails at o e (Case l fam x arms) = Case l fam x (overArms at o e arms)
  overTails at o e (CaseLit l x arms) = CaseLit l x (overLitArms at o e arms)
  overTails at o e (CaseNat l x arms) = CaseNat l x (overNatArms at o e arms)
  overTails at o e (Assume l a b body) = Assume l a b (overTails at o e body)
  overTails at o e (ReadBack l el x cs body) = ReadBack l el x cs (overTails at o (Free {k = 2} . e) body)
  overTails at o e (ExtentsBack {k} l x body) = ExtentsBack l x (overTails at o (Free {k = S k} . e) body)
  overTails at o e (Join {nonEmpty} l scope targets body) =
    Join {nonEmpty} l scope (overTargets at e targets) (overTails at UnderJoin e body)
  overTails at o e (Jump l j terms as) = Jump l j terms as
  overTails at o e (Unreachable l) = Unreachable l
  overTails at o e (Crash l m) = Crash l m
  overTails at o e (CrashWith l m) = CrashWith l m

  overAlt : AtTail n -> Around js -> (Fin n -> Fin p) -> AltAt js p -> AltAt js p
  overAlt at o e (MkAlt {k} con fs body) = MkAlt con fs (overTails at o (Free {k} . e) body)

  overAlts : AtTail n -> Around js -> (Fin n -> Fin p) -> List (AltAt js p) -> List (AltAt js p)
  overAlts at o e [] = []
  overAlts at o e (alt :: alts) = overAlt at o e alt :: overAlts at o e alts

  overArms : AtTail n -> Around js -> (Fin n -> Fin p) -> CaseArmsOf (AltAt js p) (TermAt js p) ->
             CaseArmsOf (AltAt js p) (TermAt js p)
  overArms at o e (Defaulted alts d) = Defaulted (overAlts at o e alts) (overTails at o e d)
  overArms at o e (Exhaustive (alt ::: alts)) = Exhaustive (overAlt at o e alt ::: overAlts at o e alts)

  overLits : AtTail n -> Around js -> (Fin n -> Fin p) -> List (kt, TermAt js p) -> List (kt, TermAt js p)
  overLits at o e [] = []
  overLits at o e ((kv, t) :: rest) = (kv, overTails at o e t) :: overLits at o e rest

  overKeyed : AtTail n -> Around js -> (Fin n -> Fin p) -> LitArmsOf kt (TermAt js p) -> LitArmsOf kt (TermAt js p)
  overKeyed at o e (LitDefault ((kv, t) ::: alts) d) = LitDefault ((kv, overTails at o e t) ::: overLits at o e alts) (overTails at o e d)
  overKeyed at o e (LitNoDefault ((kv, t) ::: alts)) = LitNoDefault ((kv, overTails at o e t) ::: overLits at o e alts)

  overLitArms : AtTail n -> Around js -> (Fin n -> Fin p) -> LitMatch (TermAt js p) -> LitMatch (TermAt js p)
  overLitArms at o e (OnlyDefault d) = OnlyDefault (overTails at o e d)
  overLitArms at o e (OnInts t arms) = OnInts t (overKeyed at o e arms)
  overLitArms at o e (OnChars arms) = OnChars (overKeyed at o e arms)
  overLitArms at o e (OnStrings arms) = OnStrings (overKeyed at o e arms)
  overLitArms at o e (OnBigs arms) = OnBigs (overKeyed at o e arms)

  overNatArms : AtTail n -> Around js -> (Fin n -> Fin p) -> NatArmsOf (TermAt js p) (TermAt js (Under 1 p)) ->
                NatArmsOf (TermAt js p) (TermAt js (Under 1 p))
  overNatArms at o e (OnlyZero z) = OnlyZero (overTails at o e z)
  overNatArms at o e (OnlySucc x s) = OnlySucc x (overTails at o (Free {k = 1} . e) s)
  overNatArms at o e (Both z x s) = Both (overTails at o e z) x (overTails at o (Free {k = 1} . e) s)

  overTargets : AtTail n -> (Fin n -> Fin p) -> All (Target s p) ts -> All (Target s p) ts
  overTargets at e [] = []
  overTargets at e (MkTarget {k} l code sorts names params body :: rest) =
    MkTarget {k} l code sorts names params (overTails at UnderJoin (Free {k} . e) body) :: overTargets at e rest

||| An action's value run on the world `w` of its scope, at a tail: a
||| lambda of the world, outside every join op, is its body with its world
||| `w`, so a tail of that body that applies a call to the world is that
||| call saturated; any other action is applied to the world. A lambda's
||| body sees no join point, so it stands for a tail only where none is in
||| scope; inside a join op the lambda is applied as any action is.
running : Loc -> Fin n -> AtTail n
running l w Outermost e (Lam _ _ (MkBinder _ WorldT) body) =
  rename (\v => case splitUnder {k = 1} v of
                  Left _ => e w
                  Right y => y) body
running l w _ e t = App l t (Var l (e w))

||| What a function's signature fixes of its result's dynamic dimensions
||| (`ds`, over its parameters), stated of the value at a tail, of the
||| function's result type `ty`: what a call of it states of the value,
||| which a join point it becomes states where its region gives it.
tying : Loc -> Ty -> List (Nat, Stated (Term n)) -> AtTail n
tying l ty ds _ e t = Tie l ty t (map (\(a, s) => (a, map (rename e) s)) ds)

||| A function's body with each tail that gives its value tied (`tying`) to
||| what its signature fixes of its result's dynamic dimensions, over its
||| parameters: what each call of it states of the value it gives, stated
||| where its body gives it, so that a call of it a jump makes to its region
||| states nothing it did not. Every tail gives a value of the function's
||| result type `ty`.
export
tiedExits : Loc -> Ty -> List (Nat, Stated (Term n)) -> Term n -> Term n
tiedExits l ty [] body = body
tiedExits l ty ds@(_ :: _) body = overTails (tying l ty ds) Outermost id body

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

||| What Idris proved of a function instance's loops, which is where the
||| divergence of a call through it comes from: every loop through it is
||| a loop of the one Idris component (its strongly connected component of
||| Idris's call graph) named, whose size-change graphs decrease; it is a
||| function the frontend made with no loop of its own (the program's
||| root); or some loop through it is not proved to end, by the
||| definitions named. A function another one's lambda or delay became
||| takes its owner's.
public export
data Termination = Terminates ComponentId | Acyclic | MayDiverge (List1 Shown)

||| Where a function instance's definition stands: a function in its own
||| right, or a definition local to another, which Idris lifted out under a
||| name nested in it (a `case` or `with` block, a `where` or `let`
||| function), read once from its Idris name.
public export
data Standing = OwnFunction | LocalDefinition

%prefix_record_projections off

||| A function instance of full Core: its key; where its definition
||| stands; its telescope, the sorts of its erased index parameters (the
||| levels `0 .. p-1` of its body's scope); what a call of it holds
||| (`Callee`: its identity, its symbol, its runtime parameters' binders,
||| a parameter Idris erased being none, and its result), the one value
||| every call of it holds too; which index term each `?` of its
||| signature's tensors is (`Extents`); the name Idris gave each runtime
||| parameter; its body; and what Idris proved of its loops. Its
||| projections are postfix only: a prefix `extents` would be
||| `Shapes.extents` too.
public export
record TFn where
  constructor MkTFn
  key : InstanceKey
  standing : Standing
  telescope : List Sort
  arity : Nat
  callee : Callee arity
  extents : Extents arity
  paramNames : Vect arity Shown
  body : Term arity
  loc : Loc
  termination : Termination

%prefix_record_projections on

||| A local definition as a join region of a function whose telescope is
||| `q` levels deep: its code, its index parameters the region's erased
||| binders at the next levels, the region's parameters, and its body,
||| seeing the join points `s`, before the function's scope of `r`, every
||| level it names moved past the `q` already bound.
regionOf : (q : Nat) -> (f : TFn) -> {k : Nat} -> Vect k Shown -> Vect k Binder -> TermAt s k -> Target s r k
regionOf q f names params body =
  MkTarget {k} f.loc (LocalCode (shown f.key.origin)) (map (movedSort (MovedBy q)) f.telescope) names
           (map (movedBinder (MovedBy q)) params)
           (runIdentity (visitTerm (MkVisit (\x => Id (Bound {n = r} x)) (\_ => Id ()) (MovedBy q)) body))

||| A local definition's action run on the world: its body, in the scope of
||| its parameters and then the world, each tail that gives the action run
||| on the world (`running`), so a tail that applied a call to the world is
||| that call saturated with it.
ranOn : (f : TFn) -> (0 _ : ActionType f.callee.result) -> Term (S f.arity)
ranOn f _ = overTails (running f.loc last) Outermost id (rename weaken f.body)

||| The quantity an action takes the world at.
worldUses : ActionType t -> Uses
worldUses (OnWorld w _) = w

||| How every call of a local definition, in every function that reaches
||| it, jumps to it: a tail call of it with its parameters, its region its
||| body (`ByCall`); or, its result an action, a tail call of it applied to
||| the world, its region the action run on the world (`ByRun`). The two are
||| the problem's: a tail that gives the action and one that runs it give
||| values of two types, which no one region gives.
public export
data JumpsBy : TFn -> Type where
  ByCall : JumpsBy f
  ByRun : ActionType f.callee.result -> JumpsBy f

%prefix_record_projections off

||| A local definition that is a join point, by how its calls jump to it.
||| Its projections are postfix only: a prefix `definition` would be the
||| context's too.
public export
record LocalJoin where
  constructor MkLocalJoin
  definition : TFn
  jumps : JumpsBy definition

%prefix_record_projections on

||| The arity of a local join's join point: its parameters, then the world
||| for one whose calls run its action.
public export
pointArity : LocalJoin -> Nat
pointArity (MkLocalJoin f ByCall) = f.arity
pointArity (MkLocalJoin f (ByRun _)) = S f.arity

||| A local join's calls as the uses of a continuation (`jumpsTo`).
export
continuationOf : (m : LocalJoin) -> Continuation n n (pointArity m)
continuationOf (MkLocalJoin f ByCall) = Calling f.callee
continuationOf (MkLocalJoin f (ByRun a)) = Running f.callee a

||| A local join's region's body before the calls of local joins in it are
||| jumps: its body, or its action run on the world (`ranOn`).
export
regionBody : (m : LocalJoin) -> Term (pointArity m)
regionBody (MkLocalJoin f ByCall) = f.body
regionBody (MkLocalJoin f (ByRun a)) = ranOn f a

||| A local join as a join region of a function whose telescope is `q`
||| levels deep (`regionOf`): its parameters, then, for one whose calls run
||| its action, the world, at the quantity the action takes it.
export
regionAt : (q : Nat) -> (m : LocalJoin) -> TermAt s (pointArity m) -> Target s r (pointArity m)
regionAt q (MkLocalJoin f ByCall) body = regionOf q f f.paramNames f.callee.params body
regionAt q (MkLocalJoin f (ByRun a)) body =
  regionOf q f (snoc f.paramNames (shown "world")) (snoc f.callee.params (MkBinder (worldUses a) WorldT)) body

||| What Idris proved of a function's loops once the join regions of the
||| local definitions it holds are part of it: a loop of one that is not
||| proved to end is now a loop of the function's.
export
withRegions : Termination -> List TFn -> Termination
withRegions t [] = t
withRegions t (m :: ms) = withRegions (both t m.termination) ms
  where
    both : Termination -> Termination -> Termination
    both (MayDiverge a) (MayDiverge b) = MayDiverge (a ++ b)
    both (MayDiverge a) _ = MayDiverge a
    both _ (MayDiverge b) = MayDiverge b
    both own _ = own

||| A group of families: a strongly connected component of the graph of
||| family instances whose fields refer to each other (`Rose`'s `List (Rose
||| a)` is a member with `Rose`), found once, as the families are
||| registered, its members in the order they were registered.
public export
FamilyGroup : Type
FamilyGroup = List1 Family

||| A whole program in full Core: its family groups, in an order where a
||| group's fields refer only to its own members and to earlier groups; its
||| root, the only function the module exports, whose type says what kind
||| of program it is (`main : Int`, or IO); and its other functions. The
||| module writes the others, then the root.
public export
record Source where
  constructor MkSource
  groups : List FamilyGroup
  root : TFn
  others : List TFn

||| The most UTF-8 bytes a symbol has: a file name holds 255 on the targets'
||| file systems, and MLIR's IR tree dump names a directory after each
||| function's symbol, behind its op's name.
export
symbolBytes : Nat
symbolBytes = 200

||| The longest prefix of a string whose UTF-8 is at most `n` bytes.
export
prefixWithin : Nat -> String -> String
prefixWithin n s = pack (go n (unpack s))
  where
    go : Nat -> List Char -> List Char
    go _ [] = []
    go room (c :: cs) =
      let w = length (utf8 (singleton c)) in
      if w <= room then c :: go (room `minus` w) cs else []

||| A key printed whole: its origin, then its arguments in brackets when it
||| has any. An argument is a position of the definition, written as
||| `keyArgument` writes it.
export
keyPrint : String -> KeyArguments -> String
keyPrint origin NoArguments = origin
keyPrint origin arguments@(UpTo _ _) = fastConcat [origin, "[", joinBy ", " (argumentsText arguments), "]"]

||| A key as its symbol, a function of the key alone (no other key changes
||| it): its print whole, or, when the print drops part of the instance's
||| identity or is longer than symbolBytes, as much of it as fits, `;` and
||| the low 64 bits of the identity's hash as 16 hex digits. No print ends
||| in `;` and 16 hex digits: a print shows `;` only inside a string or
||| character literal, which ends in its quote.
export
keyText : InstanceKey -> String
keyText k = symbol k.print
  where
    symbol : KeyPrint -> String
    symbol Whole = keyPrint k.origin k.arguments
    symbol (Lossy h) = prefixWithin (symbolBytes `minus` 17) (keyPrint k.origin k.arguments) ++ ";" ++ hex16 h
