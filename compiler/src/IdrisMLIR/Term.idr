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

||| One `p k` per arity `k` of a list of join points, in the list's order:
||| the join regions of one op, or what a reader of a term keeps of each
||| join point in scope.
public export
data Each : (p : Nat -> Type) -> List Nat -> Type where
  Nil : Each p []
  (::) : p k -> Each p js -> Each p (k :: js)

||| What `Each` holds for one of its join points.
export
eachAt : Elem k js -> Each p js -> p k
eachAt Here (x :: _) = x
eachAt (There e) (_ :: xs) = eachAt e xs

||| What `Each` holds for the join points around an op, then for its own.
export
aroundThen : Each p js -> Each p ts -> Each p (js ++ ts)
aroundThen [] ys = ys
aroundThen (x :: xs) ys = x :: aroundThen xs ys

||| What `Each` holds, in order, as a list.
export
eachList : ({0 k : Nat} -> p k -> a) -> Each p ts -> List a
eachList f [] = []
eachList f (x :: xs) = f x :: eachList f xs

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
    ||| A suspended computation.
    Suspend : Loc -> TermAt [] n -> TermAt js n
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
    ||| An operation of the array language on its operands, giving a value
    ||| of `result`.
    Tensor : Loc -> (result : Ty) -> TensorOp (TermAt [] n) -> TermAt js n
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
    ||| A reduction of `x` along its axis after the frame of `z`, from
    ||| `z`'s accumulators, left to right in index order; the body binds
    ||| the accumulator (`Bound 0`) and the element or cell (`Bound 1`).
    ||| `FoldLast` gives the last accumulators (`z`'s type), `ScanLast`
    ||| every one, along that axis.
    Reduce : Loc -> Reduction -> (acc, elem, result : Ty) -> (z, x : TermAt [] n) -> TermAt [] (Under 2 n) ->
             TermAt js n
    ||| The array, the dynamic dimensions stated of it equal to what each
    ||| statement gives, axis by axis (an axis counted from 0, outermost
    ||| first).
    Tie : Loc -> TermAt [] n -> List (Nat, Stated (TermAt [] n)) -> TermAt js n
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
           Each (Target (regionsSee scope js ts) n) ts -> TermAt (js ++ ts) n -> TermAt js n
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
  visitTerm v (Suspend l body) = Suspend l <$> visitTerm v body
  visitTerm v (Resume l e) = Resume l <$> visitTerm v e
  visitTerm v (Unreachable l) = pure (Unreachable l)
  visitTerm v (Assume l a b body) = Assume l (moved v.levels a) (moved v.levels b) <$> visitTerm v body
  visitTerm v (Crash l m) = pure (Crash l m)
  visitTerm v (CrashWith l m) = CrashWith l <$> visitTerm v m
  visitTerm v (NewWorld l) = pure (NewWorld l)
  visitTerm v (Tensor l ty op) = Tensor l (movedTy v.levels ty) <$> visitOp v op
  visitTerm v (Tabulate {k} l ty es body) =
    Tabulate l (movedTy v.levels ty) <$> visitVect v es <*> visitTerm (underVisit {k} v) body
  visitTerm v (TabulateIO {k} l ty es w body step done) =
    (\es', w', body' => TabulateIO l (movedTy v.levels ty) es' w' body' step done)
      <$> visitVect v es <*> visitTerm v w <*> visitTerm (underVisit {k = S k} v) body
  visitTerm v (Reduce l r acc el ty z x body) =
    Reduce l r (movedTy v.levels acc) (movedTy v.levels el) (movedTy v.levels ty)
      <$> visitTerm v z <*> visitTerm v x <*> visitTerm (underVisit {k = 2} v) body
  visitTerm v (Tie l x ds) = Tie l <$> visitTerm v x <*> visitStated v ds
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
  visitOp v (Extent a x) = Extent a <$> visitTerm v x
  visitOp v (Extract x cs) = Extract <$> visitTerm v x <*> visitAll v cs
  visitOp v (Insert x y cs) = Insert <$> visitTerm v x <*> visitTerm v y <*> visitAll v cs
  visitOp v (Take a c x) = Take a <$> visitTerm v c <*> visitTerm v x
  visitOp v (Drop a c x) = Drop a <$> visitTerm v c <*> visitTerm v x
  visitOp v (Concat a x y) = Concat a <$> visitTerm v x <*> visitTerm v y
  visitOp v (Transpose a x) = Transpose a <$> visitTerm v x
  visitOp v (Reshape x es) = Reshape <$> visitTerm v x <*> visitAll v es

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

  visitTargets : Applicative g => Visit g n m -> Each (Target s n) ts -> g (Each (Target s m) ts)
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
    SuspendF : Loc -> f [] n -> TermF f js n
    ResumeF : Loc -> f [] n -> TermF f js n
    UnreachableF : Loc -> TermF f js n
    AssumeF : Loc -> ITerm -> ITerm -> f js n -> TermF f js n
    CrashF : Loc -> Cause -> TermF f js n
    CrashWithF : Loc -> f [] n -> TermF f js n
    NewWorldF : Loc -> TermF f js n
    TensorF : Loc -> Ty -> TensorOp (f [] n) -> TermF f js n
    TabulateF : {k : Nat} -> Loc -> Ty -> Vect k (f [] n) -> f [] (Under k n) -> TermF f js n
    TabulateIOF : {k : Nat} -> Loc -> Ty -> Vect k (f [] n) -> f [] n -> f [] (Under (S k) n) -> Con 2 -> Con 2 ->
                  TermF f js n
    ReduceF : Loc -> Reduction -> Ty -> Ty -> Ty -> f [] n -> f [] n -> f [] (Under 2 n) -> TermF f js n
    TieF : Loc -> f [] n -> List (Nat, Stated (f [] n)) -> TermF f js n
    ReadBackF : Loc -> Ty -> f [] n -> List (f [] n) -> f js (Under 2 n) -> TermF f js n
    ExtentsBackF : {k : Nat} -> Loc -> f [] n -> f js (Under (S k) n) -> TermF f js n
    JoinF : {0 ts : List Nat} -> Loc -> (scope : TokenScope) -> Each (TargetF f (regionsSee scope js ts) n) ts ->
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
hmap h (SuspendF l body) = SuspendF l (h body)
hmap h (ResumeF l e) = ResumeF l (h e)
hmap h (UnreachableF l) = UnreachableF l
hmap h (AssumeF l a b body) = AssumeF l a b (h body)
hmap h (CrashF l m) = CrashF l m
hmap h (CrashWithF l m) = CrashWithF l (h m)
hmap h (NewWorldF l) = NewWorldF l
hmap h (TensorF l ty op) = TensorF l ty (map h op)
hmap h (TabulateF l ty es body) = TabulateF l ty (map h es) (h body)
hmap h (TabulateIOF l ty es w body step done) = TabulateIOF l ty (map h es) (h w) (h body) step done
hmap h (ReduceF l r acc el ty z x body) = ReduceF l r acc el ty (h z) (h x) (h body)
hmap h (TieF l x ds) = TieF l (h x) (map (\(a, s) => (a, map h s)) ds)
hmap h (ReadBackF l e x cs body) = ReadBackF l e (h x) (map h cs) (h body)
hmap h (ExtentsBackF l x body) = ExtentsBackF l (h x) (h body)
hmap h (JoinF l scope targets body) = JoinF l scope (targetsMap targets) (h body)
  where
    targetsMap : Each (TargetF f s n) ts' -> Each (TargetF g s n) ts'
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
  para alg (Suspend l body) = alg (SuspendF l (sub alg body))
  para alg (Resume l e) = alg (ResumeF l (sub alg e))
  para alg (Unreachable l) = alg (UnreachableF l)
  para alg (Assume l a b body) = alg (AssumeF l a b (sub alg body))
  para alg (Crash l m) = alg (CrashF l m)
  para alg (CrashWith l m) = alg (CrashWithF l (sub alg m))
  para alg (NewWorld l) = alg (NewWorldF l)
  para alg (Tensor l ty op) = alg (TensorF l ty (paraOp alg op))
  para alg (Tabulate l ty es body) = alg (TabulateF l ty (paraVect alg es) (sub alg body))
  para alg (TabulateIO l ty es w body step done) =
    alg (TabulateIOF l ty (paraVect alg es) (sub alg w) (sub alg body) step done)
  para alg (Reduce l r acc el ty z x body) = alg (ReduceF l r acc el ty (sub alg z) (sub alg x) (sub alg body))
  para alg (Tie l x ds) = alg (TieF l (sub alg x) (paraStated alg ds))
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
  paraOp alg (Extent k x) = Extent k (sub alg x)
  paraOp alg (Extract x cs) = Extract (sub alg x) (paraAll alg cs)
  paraOp alg (Insert x v cs) = Insert (sub alg x) (sub alg v) (paraAll alg cs)
  paraOp alg (Take a k x) = Take a (sub alg k) (sub alg x)
  paraOp alg (Drop a k x) = Drop a (sub alg k) (sub alg x)
  paraOp alg (Concat a x y) = Concat a (sub alg x) (sub alg y)
  paraOp alg (Transpose a x) = Transpose a (sub alg x)
  paraOp alg (Reshape x es) = Reshape (sub alg x) (paraAll alg es)

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
                Each (Target s n) ts -> Each (TargetF (Sub f) s n) ts
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

||| A continuation the program as written makes, as its uses are written in
||| a term of scope `n`, which becomes one of scope `m` without it: a
||| variable applied to `k` arguments (a `let` of a lambda of `k`
||| parameters), the one variable `without` takes out; or a call of a local
||| definition of `k` parameters, by the callee every call of it holds.
public export
data Continuation : (n, m, k : Nat) -> Type where
  Applying : (without : Fin n -> Maybe (Fin m)) -> Continuation n m k
  Calling : Callee k -> Continuation n n k

||| The continuation under a binder of `j` variables: the binder's own are
||| none of it.
underCont : {j : Nat} -> Continuation n m k -> Continuation (Under j n) (Under j m) k
underCont (Applying without) = Applying (\x => case splitUnder {k = j} x of
                                               Left i => Just (Bound {n = m} i)
                                               Right y => Free {k = j} <$> without y)
underCont (Calling c) = Calling c

||| A position no tail of the term reaches, visited for a use of the
||| continuation, which such a position may not hold: it would be the
||| continuation as a value, or a call that returns.
awayFrom : Continuation n m k -> Visit Maybe n m
awayFrom (Applying without) = MkVisit without (\_ => Just ()) Unmoved
awayFrom (Calling c) = MkVisit Just (\fn => if fn == c.fn then Nothing else Just ()) Unmoved

||| The head of an application and its arguments, the first first.
headOf : TermAt [] n -> List (TermAt [] n) -> (TermAt [] n, List (TermAt [] n))
headOf (App _ f x) args = headOf f (x :: args)
headOf h args = (h, args)

mutual
  ||| The term with each use of the continuation a jump to it, the
  ||| outermost join point its tails see, those they saw already after it:
  ||| each use a tail position's head of a saturated application (a call of
  ||| the callee, or the variable applied to `k` arguments) whose arguments
  ||| hold no use. Nothing where a use is anywhere else, which makes the
  ||| continuation a value and no join point. The test reads the term
  ||| alone, total, with no budget.
  export
  jumpsTo : {k : Nat} -> Continuation n m k -> TermAt js n -> Maybe (TermAt (k :: js) m)
  jumpsTo c (Var l x) = Var l <$> (awayFrom c).var x
  jumpsTo c (Literal l x) = pure (Literal l x)
  jumpsTo c (PrimApp l p stands as) = PrimApp l p stands <$> visitVect (awayFrom c) as
  jumpsTo c (Effect l p gives as w res) =
    (\as', w' => Effect l p gives as' w' res) <$> visitVect (awayFrom c) as <*> visitTerm (awayFrom c) w
  jumpsTo c (Call {arity} l callee stands is as) = case c of
    Calling target =>
      if callee.fn == target.fn
         -- Every call of a callee holds the one signature its function is
         -- made with, so its arity is the continuation's: the check says to
         -- the types what the identity says already.
         then case decEq arity k of
                Yes Refl => Jump l Here is <$> visitVect (awayFrom c) as
                No _ => Nothing
         else Call l callee stands is <$> visitVect (awayFrom c) as
    Applying _ => Call l callee stands is <$> visitVect (awayFrom c) as
  jumpsTo c (ConApp l con bs as) = ConApp l con bs <$> visitVect (awayFrom c) as
  jumpsTo c (Let l x b v body) = Let l x b <$> visitTerm (awayFrom c) v <*> jumpsTo (underCont {j = 1} c) body
  jumpsTo c (Case l fam x arms) = Case l fam <$> (awayFrom c).var x <*> jumpsArms c arms
  jumpsTo c (CaseLit l x arms) = CaseLit l <$> (awayFrom c).var x <*> jumpsLitArms c arms
  jumpsTo c (CaseNat l x arms) = CaseNat l <$> (awayFrom c).var x <*> jumpsNatArms c arms
  jumpsTo c (Lam l x b body) = Lam l x b <$> visitTerm (underVisit {k = 1} (awayFrom c)) body
  jumpsTo c (App l f x) = case (c, headOf f [x]) of
    (Applying without, (Var _ v, args)) => case (without v, toVect k args) of
      (Nothing, Just as) => Jump l Here [] <$> visitVect (awayFrom c) as
      _ => App l <$> visitTerm (awayFrom c) f <*> visitTerm (awayFrom c) x
    _ => App l <$> visitTerm (awayFrom c) f <*> visitTerm (awayFrom c) x
  jumpsTo c (Suspend l body) = Suspend l <$> visitTerm (awayFrom c) body
  jumpsTo c (Resume l e) = Resume l <$> visitTerm (awayFrom c) e
  jumpsTo c (Unreachable l) = pure (Unreachable l)
  jumpsTo c (Assume l a b body) = Assume l a b <$> jumpsTo c body
  jumpsTo c (Crash l m) = pure (Crash l m)
  jumpsTo c (CrashWith l m) = CrashWith l <$> visitTerm (awayFrom c) m
  jumpsTo c (NewWorld l) = pure (NewWorld l)
  jumpsTo c (Tensor l ty op) = Tensor l ty <$> visitOp (awayFrom c) op
  jumpsTo c (Tabulate {k = j} l ty es body) =
    Tabulate l ty <$> visitVect (awayFrom c) es <*> visitTerm (underVisit {k = j} (awayFrom c)) body
  jumpsTo c (TabulateIO {k = j} l ty es w body step done) =
    (\es', w', body' => TabulateIO l ty es' w' body' step done)
      <$> visitVect (awayFrom c) es <*> visitTerm (awayFrom c) w <*> visitTerm (underVisit {k = S j} (awayFrom c)) body
  jumpsTo c (Reduce l r acc el ty z x body) =
    Reduce l r acc el ty <$> visitTerm (awayFrom c) z <*> visitTerm (awayFrom c) x
                         <*> visitTerm (underVisit {k = 2} (awayFrom c)) body
  jumpsTo c (Tie l x ds) = Tie l <$> visitTerm (awayFrom c) x <*> visitStated (awayFrom c) ds
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

  jumpsTargets : {k : Nat} -> Continuation n m k -> Each (Target s n) ts -> Maybe (Each (Target (k :: s) m) ts)
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
||| binders at the next levels, its parameters the region's, and its body,
||| seeing the join points `s`, before the function's scope of `r`, every
||| level it names moved past the `q` already bound.
export
regionOf : (q : Nat) -> (f : TFn) -> TermAt s f.arity -> Target s r f.arity
regionOf q f body =
  MkTarget {k = f.arity} f.loc (LocalCode (shown f.key.origin)) (map (movedSort (MovedBy q)) f.telescope) f.paramNames
           (map (movedBinder (MovedBy q)) f.callee.params)
           (runIdentity (visitTerm (MkVisit (\x => Id (Bound {n = r} x)) (\_ => Id ()) (MovedBy q)) body))

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
