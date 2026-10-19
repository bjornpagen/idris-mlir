-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Full Core: the higher-order language
||| that `Frontend.Translate` produces from checked TT and `Emit` writes as
||| MLIR.
|||
||| `Term n` is a term in a scope of `n` variables, each a de Bruijn index
||| (`Fin n`, `0` the innermost): a binder of `k` variables holds a
||| `Term (Under k n)`, its own variables first, then the scope's outside
||| it. A closed term is a `Term 0`; a function's body is a `Term arity`,
||| parameter `i` being `i`, as in Idris's case trees. An unbound variable
||| is a type error. The scope is counted by a number, not named by a type
||| of variables, so that a traversal under a binder recurses at the same
||| types, only at another number.
|||
||| Renaming is `rename`, under a binder by `liftRen`. Every other traversal
||| is a fold over the base functor `TermF`: `cata`, or `para` where the
||| algebra needs a part as it was.
|||
||| A lambda's or a `Delay`'s body stays in the scope it is written in, as a
||| `let`'s does: renaming enters it, and the variables of that scope it
||| uses are its captures. `Emit` writes it as a function of its own, which
||| the closure or the suspension names with its captures.
module IdrisMLIR.Term

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.Facts
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Types

import Data.Fin
import Data.Fin.Split
import Data.List
import Data.List1
import Data.Maybe
import Data.SortedMap
import Data.String
import Data.Vect

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

||| A renaming under a binder of `k` variables: the binder's own stay, the
||| others are renamed.
export
liftRen : {k : Nat} -> (Fin n -> Fin m) -> Fin (Under k n) -> Fin (Under k m)
liftRen f v = case splitUnder {k} v of
  Left i => Bound {n = m} i
  Right x => Free {k} (f x)

------------------------------------------------------------------------------
-- Constructors and data instances
------------------------------------------------------------------------------

||| A constructor of a data instance, of `k` fields (its runtime fields, not
||| its parameters, each as it binds), with its identity and its name
||| within its data type, as the module and the dump print it
||| (`Types.shortName`). Every reference to a constructor holds it.
public export
record Con (k : Nat) where
  constructor MkCon
  id : ConId
  name : String
  fields : Vect k Binder
  loc : Loc

||| A constructor's tag: Idris's, its identity's position (`id.index`).
public export
(.tag) : Con k -> Nat
(.tag) c = finToNat c.id.index

||| A data instance's constructors, in tag order, and the sum they are: a
||| plain sum; a sum whose cells every program is checked to rebuild in
||| place and hold exclusive (the registry's `InPlaceType`); or base's list,
||| its nil and its cons, which the string builders take apart (the
||| registry's `ListType`).
public export
data DataShape
  = PlainSum (List (k ** Con k))
  | InPlaceSum (List (k ** Con k))
  | BaseListSum (Con 0) (Con 2)

||| A data instance. Its key is what it is an instance of, and its Idris
||| name is the key's origin. It says nothing of how its values are laid
||| out: whether a value is boxed is the dialect's decision, made once from
||| the type graph.
public export
record Data where
  constructor MkData
  id : DataId
  key : InstanceKey
  shape : DataShape
  loc : Loc

||| A data instance's constructors, in tag order.
public export
consOf : Data -> List (k ** Con k)
consOf d = case d.shape of
  PlainSum cs => cs
  InPlaceSum cs => cs
  BaseListSum nil cons => [(0 ** nil), (2 ** cons)]

------------------------------------------------------------------------------
-- Terms
------------------------------------------------------------------------------

||| What an IO primitive gives besides the next world, as its result kind
||| says: no value, whose `IORes` holds the unit constructor named; or a
||| value, its op's first result.
public export
data IOGives : IOResult -> Type where
  GivesUnit : Con 0 -> IOGives WorldOnly
  GivesValue : IOGives ValueThenWorld

||| A match's possible alternatives and its default, or alternatives that
||| cover every constructor, at least one: a match with no possible arm is
||| `Unreachable`.
public export
data CaseArmsOf alt t = Defaulted (List alt) t | Exhaustive (List1 alt)

||| A match on a literal's possible alternatives and its default, or, when
||| Idris proved the default impossible, at least one alternative.
public export
data LitArmsOf t = LitDefault (List (Lit, t)) t | LitNoDefault (List1 (Lit, t))

||| A match on a natural's possible arms: zero, a successor binding its
||| predecessor (named), or both.
public export
data NatArmsOf z s = OnlyZero z | OnlySucc Shown s | Both z Shown s

mutual
  public export
  data Term : Nat -> Type where
    Var : Loc -> Fin n -> Term n
    Literal : Loc -> Lit -> Term n
    ||| A primitive, and the library definition it stands for when the
    ||| registry lowered that definition's call to it: the dump writes it,
    ||| so that what a program uses can be read off its Core, and nothing
    ||| computes with it.
    PrimApp : {k : Nat} -> Loc -> Prim k -> (standsFor : Maybe Shown) -> Vect k (Term n) -> Term n
    ||| An IO primitive on its arguments, which end with the world, giving
    ||| the `IORes` (`res`) of what it gives and the next world.
    Effect : Loc -> (p : IOPrim) -> IOGives (ioResult p) -> List (Term n) -> (res : Con 2) -> Term n
    ||| A saturated call, and the library definition it stands for when the
    ||| registry lowered that definition's call to it, as for a primitive.
    Call : Loc -> FnId -> (standsFor : Maybe Shown) -> List (Term n) -> Term n
    ||| A saturated constructor application; parameters are not fields.
    ConApp : {k : Nat} -> Loc -> Con k -> Vect k (Term n) -> Term n
    ||| `let`, with its variable's name and how it is used. TTC does not
    ||| keep let types: `Emit` synthesizes them.
    Let : Loc -> (name : Shown) -> Quantity -> Term n -> Term (Under 1 n) -> Term n
    Case : Loc -> Fin n -> CaseArmsOf (Alt n) (Term n) -> Term n
    CaseLit : Loc -> Fin n -> LitArmsOf (Term n) -> Term n
    ||| A match on a `Nat`-like value: zero, or a successor, whose
    ||| predecessor the successor's arm binds. The predecessor exists only
    ||| there, where the value is not zero.
    CaseNat : Loc -> Fin n -> NatArmsOf (Term n) (Term (Under 1 n)) -> Term n
    ||| A lambda; its body binds the parameter (`Bound 0`), named as Idris
    ||| named it.
    Lam : Loc -> (name : Shown) -> Binder -> Term (Under 1 n) -> Term n
    App : Loc -> Term n -> Term n -> Term n
    ||| A suspended computation.
    Suspend : Loc -> Term n -> Term n
    Resume : Loc -> Term n -> Term n
    ||| A term Idris proved never runs: a match with no possible arm.
    Unreachable : Loc -> Term n
    ||| A case the definition does not cover: a crash, its message fixed.
    Crash : Loc -> String -> Term n
    ||| A trusted library's crash with a message computed at run time.
    CrashWith : Loc -> Term n -> Term n
    ||| A world forged where a trusted library runs an IO action for a pure
    ||| value (`unsafePerformIO`): the first world of a chain of its own.
    ||| Its op performs IO and takes no world, so it is neither a pure nor
    ||| an IO primitive.
    NewWorld : Loc -> Term n
    ||| An operation of the array language on its operands, giving a value
    ||| of `result`.
    Tensor : Loc -> (result : Ty) -> TensorOp (Term n) -> Term n
    ||| A new array of `result` (a `TensorT`) of the extents given
    ||| (naturals, one per axis of the shape tabulated, outermost first),
    ||| each element or cell the body's value; the body binds the
    ||| coordinates, coordinate j (outermost first) being `Bound j`, a
    ||| natural.
    Tabulate : {k : Nat} -> Loc -> (result : Ty) -> Vect k (Term n) -> Term (Under k n) -> Term n
    ||| A new array of `result` (a `TensorT`) of the extents given, made in
    ||| the world's order: the body binds the coordinates (`Bound 0` to
    ||| `Bound (k - 1)`, outermost first) and the world before it (`Bound
    ||| k`), and gives the `IORes` (`step`) of the element and the world
    ||| after it, once per index in row-major order, never when the array is
    ||| empty. Its value is the `IORes` (`done`) of the array and the last
    ||| world; `world` is the first.
    TabulateIO : {k : Nat} -> Loc -> (result : Ty) -> Vect k (Term n) -> (world : Term n)
              -> Term (Under (S k) n) -> (step, done : Con 2) -> Term n
    ||| A reduction of `x` along its axis after the frame of `z`, from
    ||| `z`'s accumulators, left to right in index order; the body binds
    ||| the accumulator (`Bound 0`) and the element or cell (`Bound 1`).
    ||| `FoldLast` gives the last accumulators (`z`'s type), `ScanLast`
    ||| every one, along that axis.
    Reduce : Loc -> Reduction -> (acc, elem, result : Ty) -> (z, x : Term n) -> Term (Under 2 n) -> Term n
    ||| The array, the dynamic dimensions stated of it equal to what each
    ||| statement gives, axis by axis (an axis counted from 0, outermost
    ||| first).
    Tie : Loc -> Term n -> List (Nat, Stated (Term n)) -> Term n

  ||| A constructor alternative binds the constructor's fields (not its
  ||| parameters), each named as its pattern variable: field `i` is
  ||| `Bound i`, bound as the constructor holds it.
  public export
  data Alt : Nat -> Type where
    MkAlt : {k : Nat} -> Con k -> Vect k Shown -> Term (Under k n) -> Alt n

||| A match's arms.
public export
CaseArms : Nat -> Type
CaseArms n = CaseArmsOf (Alt n) (Term n)

||| A match on a literal's arms.
public export
LitArms : Nat -> Type
LitArms n = LitArmsOf (Term n)

||| A match on a natural's arms.
public export
NatArms : Nat -> Type
NatArms n = NatArmsOf (Term n) (Term (Under 1 n))

-- Renaming, by structural recursion through `Term` and `Alt` together.

mutual
  ||| The term with each variable renamed.
  export
  rename : (Fin n -> Fin m) -> Term n -> Term m
  rename f (Var l x) = Var l (f x)
  rename f (Literal l x) = Literal l x
  rename f (PrimApp l p stands as) = PrimApp l p stands (renameVect f as)
  rename f (Effect l p gives as res) = Effect l p gives (renameAll f as) res
  rename f (Call l fn stands as) = Call l fn stands (renameAll f as)
  rename f (ConApp l c as) = ConApp l c (renameVect f as)
  rename f (Let l x q v b) = Let l x q (rename f v) (rename (liftRen {k = 1} f) b)
  rename f (Case l x arms) = Case l (f x) (renameArms f arms)
  rename f (CaseLit l x arms) = CaseLit l (f x) (renameLitArms f arms)
  rename f (CaseNat l x arms) = CaseNat l (f x) (renameNatArms f arms)
  rename f (Lam l x b body) = Lam l x b (rename (liftRen {k = 1} f) body)
  rename f (App l g x) = App l (rename f g) (rename f x)
  rename f (Suspend l body) = Suspend l (rename f body)
  rename f (Resume l e) = Resume l (rename f e)
  rename f (Unreachable l) = Unreachable l
  rename f (Crash l m) = Crash l m
  rename f (CrashWith l m) = CrashWith l (rename f m)
  rename f (NewWorld l) = NewWorld l
  rename f (Tensor l ty op) = Tensor l ty (renameOp f op)
  rename f (Tabulate {k} l ty es body) = Tabulate l ty (renameVect f es) (rename (liftRen {k} f) body)
  rename f (TabulateIO {k} l ty es w body step done) =
    TabulateIO l ty (renameVect f es) (rename f w) (rename (liftRen {k = S k} f) body) step done
  rename f (Reduce l r acc el ty z x body) = Reduce l r acc el ty (rename f z) (rename f x) (rename (liftRen {k = 2} f) body)
  rename f (Tie l x ds) = Tie l (rename f x) (renameStated f ds)

  renameAll : (Fin n -> Fin m) -> List (Term n) -> List (Term m)
  renameAll f [] = []
  renameAll f (t :: ts) = rename f t :: renameAll f ts

  renameVect : (Fin n -> Fin m) -> Vect k (Term n) -> Vect k (Term m)
  renameVect f [] = []
  renameVect f (t :: ts) = rename f t :: renameVect f ts

  renameOp : (Fin n -> Fin m) -> TensorOp (Term n) -> TensorOp (Term m)
  renameOp f (Extent k x) = Extent k (rename f x)
  renameOp f (Extract x cs) = Extract (rename f x) (renameAll f cs)
  renameOp f (Insert x v cs) = Insert (rename f x) (rename f v) (renameAll f cs)
  renameOp f (Take a k x) = Take a (rename f k) (rename f x)
  renameOp f (Drop a k x) = Drop a (rename f k) (rename f x)
  renameOp f (Concat a x y) = Concat a (rename f x) (rename f y)
  renameOp f (Transpose a x) = Transpose a (rename f x)
  renameOp f (Reshape x es) = Reshape (rename f x) (renameAll f es)

  renameStated : (Fin n -> Fin m) -> List (Nat, Stated (Term n)) -> List (Nat, Stated (Term m))
  renameStated f [] = []
  renameStated f ((a, SameAs t) :: ds) = (a, SameAs (rename f t)) :: renameStated f ds
  renameStated f ((a, Natural t) :: ds) = (a, Natural (rename f t)) :: renameStated f ds

  renameLits : (Fin n -> Fin m) -> List (Lit, Term n) -> List (Lit, Term m)
  renameLits f [] = []
  renameLits f ((k, t) :: rest) = (k, rename f t) :: renameLits f rest

  renameLitArms : (Fin n -> Fin m) -> LitArms n -> LitArms m
  renameLitArms f (LitDefault alts d) = LitDefault (renameLits f alts) (rename f d)
  renameLitArms f (LitNoDefault ((k, t) ::: alts)) = LitNoDefault ((k, rename f t) ::: renameLits f alts)

  renameNatArms : (Fin n -> Fin m) -> NatArms n -> NatArms m
  renameNatArms f (OnlyZero z) = OnlyZero (rename f z)
  renameNatArms f (OnlySucc p s) = OnlySucc p (rename (liftRen {k = 1} f) s)
  renameNatArms f (Both z p s) = Both (rename f z) p (rename (liftRen {k = 1} f) s)

  renameAlt : (Fin n -> Fin m) -> Alt n -> Alt m
  renameAlt f (MkAlt {k} c fs body) = MkAlt c fs (rename (liftRen {k} f) body)

  renameAlts : (Fin n -> Fin m) -> List (Alt n) -> List (Alt m)
  renameAlts f [] = []
  renameAlts f (alt :: alts) = renameAlt f alt :: renameAlts f alts

  renameArms : (Fin n -> Fin m) -> CaseArms n -> CaseArms m
  renameArms f (Defaulted alts d) = Defaulted (renameAlts f alts) (rename f d)
  renameArms f (Exhaustive (alt ::: alts)) = Exhaustive (renameAlt f alt ::: renameAlts f alts)

||| The term under a binder of `k` variables it does not use.
export
weakenUnder : (k : Nat) -> Term n -> Term (Under k n)
weakenUnder k = rename (Free {k})

------------------------------------------------------------------------------
-- The base functor and its folds
------------------------------------------------------------------------------

mutual
  ||| One layer of `Term`, its subterms replaced by `f` at their scopes: a
  ||| higher-order base functor, since a subterm under a binder is in a
  ||| larger scope than the term itself.
  public export
  data TermF : (Nat -> Type) -> Nat -> Type where
    VarF : Loc -> Fin n -> TermF f n
    LiteralF : Loc -> Lit -> TermF f n
    PrimAppF : {k : Nat} -> Loc -> Prim k -> Maybe Shown -> Vect k (f n) -> TermF f n
    EffectF : Loc -> (p : IOPrim) -> IOGives (ioResult p) -> List (f n) -> Con 2 -> TermF f n
    CallF : Loc -> FnId -> Maybe Shown -> List (f n) -> TermF f n
    ConAppF : {k : Nat} -> Loc -> Con k -> Vect k (f n) -> TermF f n
    LetF : Loc -> Shown -> Quantity -> f n -> f (Under 1 n) -> TermF f n
    CaseF : Loc -> Fin n -> CaseArmsOf (AltF f n) (f n) -> TermF f n
    CaseLitF : Loc -> Fin n -> LitArmsOf (f n) -> TermF f n
    CaseNatF : Loc -> Fin n -> NatArmsOf (f n) (f (Under 1 n)) -> TermF f n
    LamF : Loc -> Shown -> Binder -> f (Under 1 n) -> TermF f n
    AppF : Loc -> f n -> f n -> TermF f n
    SuspendF : Loc -> f n -> TermF f n
    ResumeF : Loc -> f n -> TermF f n
    UnreachableF : Loc -> TermF f n
    CrashF : Loc -> String -> TermF f n
    CrashWithF : Loc -> f n -> TermF f n
    NewWorldF : Loc -> TermF f n
    TensorF : Loc -> Ty -> TensorOp (f n) -> TermF f n
    TabulateF : {k : Nat} -> Loc -> Ty -> Vect k (f n) -> f (Under k n) -> TermF f n
    TabulateIOF : {k : Nat} -> Loc -> Ty -> Vect k (f n) -> f n -> f (Under (S k) n) -> Con 2 -> Con 2 -> TermF f n
    ReduceF : Loc -> Reduction -> Ty -> Ty -> Ty -> f n -> f n -> f (Under 2 n) -> TermF f n
    TieF : Loc -> f n -> List (Nat, Stated (f n)) -> TermF f n

  public export
  data AltF : (Nat -> Type) -> Nat -> Type where
    MkAltF : {k : Nat} -> Con k -> Vect k Shown -> f (Under k n) -> AltF f n

||| A subterm as it was, with what the fold made of it (for `para`).
public export
record Sub (f : Nat -> Type) (n : Nat) where
  constructor MkSub
  term : Term n
  result : f n

||| The action of `TermF` on a natural transformation.
export
hmap : ({0 m : Nat} -> f m -> g m) -> TermF f n -> TermF g n
hmap h (VarF l x) = VarF l x
hmap h (LiteralF l x) = LiteralF l x
hmap h (PrimAppF l p stands as) = PrimAppF l p stands (map h as)
hmap h (EffectF l p gives as res) = EffectF l p gives (map h as) res
hmap h (CallF l fn stands as) = CallF l fn stands (map h as)
hmap h (ConAppF l c as) = ConAppF l c (map h as)
hmap h (LetF l x q v b) = LetF l x q (h v) (h b)
hmap h (CaseF l x arms) = CaseF l x (armsMap arms)
  where
    alt : AltF f n -> AltF g n
    alt (MkAltF c fs b) = MkAltF c fs (h b)
    armsMap : CaseArmsOf (AltF f n) (f n) -> CaseArmsOf (AltF g n) (g n)
    armsMap (Defaulted alts d) = Defaulted (map alt alts) (h d)
    armsMap (Exhaustive alts) = Exhaustive (map alt alts)
hmap h (CaseLitF l x arms) = CaseLitF l x (armsMap arms)
  where
    armsMap : LitArmsOf (f n) -> LitArmsOf (g n)
    armsMap (LitDefault alts d) = LitDefault (map (\(k, e) => (k, h e)) alts) (h d)
    armsMap (LitNoDefault alts) = LitNoDefault (map (\(k, e) => (k, h e)) alts)
hmap h (CaseNatF l x arms) = CaseNatF l x (armsMap arms)
  where
    armsMap : NatArmsOf (f n) (f (Under 1 n)) -> NatArmsOf (g n) (g (Under 1 n))
    armsMap (OnlyZero z) = OnlyZero (h z)
    armsMap (OnlySucc p s) = OnlySucc p (h s)
    armsMap (Both z p s) = Both (h z) p (h s)
hmap h (LamF l x b body) = LamF l x b (h body)
hmap h (AppF l f x) = AppF l (h f) (h x)
hmap h (SuspendF l body) = SuspendF l (h body)
hmap h (ResumeF l e) = ResumeF l (h e)
hmap h (UnreachableF l) = UnreachableF l
hmap h (CrashF l m) = CrashF l m
hmap h (CrashWithF l m) = CrashWithF l (h m)
hmap h (NewWorldF l) = NewWorldF l
hmap h (TensorF l ty op) = TensorF l ty (map h op)
hmap h (TabulateF l ty es body) = TabulateF l ty (map h es) (h body)
hmap h (TabulateIOF l ty es w body step done) = TabulateIOF l ty (map h es) (h w) (h body) step done
hmap h (ReduceF l r acc el ty z x body) = ReduceF l r acc el ty (h z) (h x) (h body)
hmap h (TieF l x ds) = TieF l (h x) (map (\(a, s) => (a, map h s)) ds)

mutual
  ||| The paramorphism: each layer with its subterms as they were and as the
  ||| algebra made them.
  export
  para : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) -> Term n -> f n
  para alg (Var l x) = alg (VarF l x)
  para alg (Literal l x) = alg (LiteralF l x)
  para alg (PrimApp l p stands as) = alg (PrimAppF l p stands (paraVect alg as))
  para alg (Effect l p gives as res) = alg (EffectF l p gives (paraAll alg as) res)
  para alg (Call l fn stands as) = alg (CallF l fn stands (paraAll alg as))
  para alg (ConApp l c as) = alg (ConAppF l c (paraVect alg as))
  para alg (Let l x q v b) = alg (LetF l x q (sub alg v) (sub alg b))
  para alg (Case l x arms) = alg (CaseF l x (paraArms alg arms))
  para alg (CaseLit l x arms) = alg (CaseLitF l x (paraLitArms alg arms))
  para alg (CaseNat l x arms) = alg (CaseNatF l x (paraNatArms alg arms))
  para alg (Lam l x b body) = alg (LamF l x b (sub alg body))
  para alg (App l f x) = alg (AppF l (sub alg f) (sub alg x))
  para alg (Suspend l body) = alg (SuspendF l (sub alg body))
  para alg (Resume l e) = alg (ResumeF l (sub alg e))
  para alg (Unreachable l) = alg (UnreachableF l)
  para alg (Crash l m) = alg (CrashF l m)
  para alg (CrashWith l m) = alg (CrashWithF l (sub alg m))
  para alg (NewWorld l) = alg (NewWorldF l)
  para alg (Tensor l ty op) = alg (TensorF l ty (paraOp alg op))
  para alg (Tabulate l ty es body) = alg (TabulateF l ty (paraVect alg es) (sub alg body))
  para alg (TabulateIO l ty es w body step done) =
    alg (TabulateIOF l ty (paraVect alg es) (sub alg w) (sub alg body) step done)
  para alg (Reduce l r acc el ty z x body) = alg (ReduceF l r acc el ty (sub alg z) (sub alg x) (sub alg body))
  para alg (Tie l x ds) = alg (TieF l (sub alg x) (paraStated alg ds))

  sub : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) -> Term n -> Sub f n
  sub alg t = MkSub t (para alg t)

  paraAll : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
            List (Term n) -> List (Sub f n)
  paraAll alg [] = []
  paraAll alg (t :: ts) = sub alg t :: paraAll alg ts

  paraVect : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
             Vect k (Term n) -> Vect k (Sub f n)
  paraVect alg [] = []
  paraVect alg (t :: ts) = sub alg t :: paraVect alg ts

  paraOp : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
           TensorOp (Term n) -> TensorOp (Sub f n)
  paraOp alg (Extent k x) = Extent k (sub alg x)
  paraOp alg (Extract x cs) = Extract (sub alg x) (paraAll alg cs)
  paraOp alg (Insert x v cs) = Insert (sub alg x) (sub alg v) (paraAll alg cs)
  paraOp alg (Take a k x) = Take a (sub alg k) (sub alg x)
  paraOp alg (Drop a k x) = Drop a (sub alg k) (sub alg x)
  paraOp alg (Concat a x y) = Concat a (sub alg x) (sub alg y)
  paraOp alg (Transpose a x) = Transpose a (sub alg x)
  paraOp alg (Reshape x es) = Reshape (sub alg x) (paraAll alg es)

  paraStated : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
               List (Nat, Stated (Term n)) -> List (Nat, Stated (Sub f n))
  paraStated alg [] = []
  paraStated alg ((a, SameAs t) :: ds) = (a, SameAs (sub alg t)) :: paraStated alg ds
  paraStated alg ((a, Natural t) :: ds) = (a, Natural (sub alg t)) :: paraStated alg ds

  paraLits : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
             List (Lit, Term n) -> List (Lit, Sub f n)
  paraLits alg [] = []
  paraLits alg ((k, t) :: rest) = (k, sub alg t) :: paraLits alg rest

  paraLitArms : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
                LitArms n -> LitArmsOf (Sub f n)
  paraLitArms alg (LitDefault alts d) = LitDefault (paraLits alg alts) (sub alg d)
  paraLitArms alg (LitNoDefault ((k, t) ::: alts)) = LitNoDefault ((k, sub alg t) ::: paraLits alg alts)

  paraNatArms : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
                NatArms n -> NatArmsOf (Sub f n) (Sub f (Under 1 n))
  paraNatArms alg (OnlyZero z) = OnlyZero (sub alg z)
  paraNatArms alg (OnlySucc p s) = OnlySucc p (sub alg s)
  paraNatArms alg (Both z p s) = Both (sub alg z) p (sub alg s)

  paraAlt : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
            Alt n -> AltF (Sub f) n
  paraAlt alg (MkAlt c fs body) = MkAltF c fs (sub alg body)

  paraAlts : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
             List (Alt n) -> List (AltF (Sub f) n)
  paraAlts alg [] = []
  paraAlts alg (alt :: rest) = paraAlt alg alt :: paraAlts alg rest

  paraArms : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
             CaseArms n -> CaseArmsOf (AltF (Sub f) n) (Sub f n)
  paraArms alg (Defaulted alts d) = Defaulted (paraAlts alg alts) (sub alg d)
  paraArms alg (Exhaustive (alt ::: alts)) = Exhaustive (paraAlt alg alt ::: paraAlts alg alts)

||| The catamorphism: each layer with what the algebra made of its subterms.
export
cata : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF f m -> f m) -> Term n -> f n
cata alg = para (\layer => alg (hmap (.result) layer))

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

||| A function instance of full Core: its key, and its runtime parameters,
||| each with the name Idris gave it; a parameter Idris erased is not one.
public export
record TFn where
  constructor MkTFn
  id : FnId
  key : InstanceKey
  arity : Nat
  params : Vect arity (Shown, Binder)
  result : Ty
  body : Term arity
  loc : Loc
  facts : Facts

||| A whole program in full Core: its data instances, its root, the only
||| function the module exports, whose type says what kind of program it is
||| (`main : Int`, or world-passing IO), and its other functions. The
||| module and the dump write the others, then the root.
public export
record Source where
  constructor MkSource
  datas : List IdrisMLIR.Term.Data
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

||| A key as its symbol, the symbol of a function or data instance in the
||| Core dump and in the module alike, a function of the key alone (no other
||| key changes it): its print whole, or, when the print drops part of the
||| instance's identity or is longer than symbolBytes, as much of it as
||| fits, `;` and the low 64 bits of the identity's hash as 16 hex digits.
||| No print ends in `;` and 16 hex digits: a print shows `;` only inside a
||| string or character literal, which ends in its quote.
export
keyText : InstanceKey -> String
keyText k = symbol k.print
  where
    symbol : KeyPrint -> String
    symbol Whole = keyPrint k.origin k.arguments
    symbol (Lossy h) = prefixWithin (symbolBytes `minus` 17) (keyPrint k.origin k.arguments) ++ ";" ++ hex16 h

------------------------------------------------------------------------------
-- Printing
------------------------------------------------------------------------------

||| How the dump names a function and a data instance.
public export
record Names where
  constructor MkNames
  fnName : FnId -> String
  dataName : DataId -> String

||| Each function and data instance of a program by its key printed; an id
||| the program does not declare, by itself.
export
sourceNames : Source -> Names
sourceNames p =
  let fns = SortedMap.fromList (map (\f => (f.id, keyText f.key)) (p.root :: p.others))
      datas = SortedMap.fromList (map (\d => (d.id, keyText d.key)) p.datas)
  in MkNames (\f => fromMaybe (show f) (lookup f fns)) (\d => fromMaybe (show d) (lookup d datas))

indent : Nat -> String
indent d = replicate (2 * d) ' '

||| What the printer makes of a term in scope `n`: given each variable's de
||| Bruijn index (`#0` is the innermost) and the indentation depth.
Printed : Nat -> Type
Printed n = (Fin n -> Nat) -> Nat -> String

||| The indices under a binder of `k` variables.
under : {k : Nat} -> (Fin n -> Nat) -> Fin (Under k n) -> Nat
under ix v = case splitUnder {k} v of
  Left i => finToNat i
  Right x => k + ix x

||| The library definition a lowered primitive or call stands for, in braces
||| after its head, as an implementation is written after its method.
standing : Maybe Shown -> String
standing Nothing = ""
standing (Just q) = "{" ++ show q ++ "}"

||| The types a primitive's call fixes, in angle brackets after its head.
typeArgs : Names -> List Ty -> String
typeArgs names [] = ""
typeArgs names ts = "<" ++ joinBy ", " (map (tyText names.dataName) ts) ++ ">"

printer : Names -> TermF Printed n -> Printed n
printer names (VarF _ x) ix d = "#" ++ show (ix x)
printer names (LiteralF _ x) ix d = show x
printer names (PrimAppF _ p stands as) ix d =
  show p ++ standing stands ++ "(" ++ joinBy ", " (map (\a => a ix d) (toList as)) ++ ")"
printer names (EffectF _ p _ as _) ix d =
  "io." ++ ioName p ++ "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")"
printer names (CallF _ fn stands as) ix d = names.fnName fn ++ standing stands ++ "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")"
printer names (ConAppF _ c as) ix d =
  names.dataName c.id.dataId ++ "::" ++ c.name ++ "(" ++ joinBy ", " (map (\a => a ix d) (toList as)) ++ ")"
printer names (LetF _ _ q v b) ix d =
  "let " ++ quantityText q ++ " = " ++ v ix (S d) ++ "\n" ++ indent d ++ b (under {k = 1} ix) d
printer names (CaseF _ x arms) ix d = "case #" ++ show (ix x) ++ " of" ++ armsText arms
  where
    alt : AltF Printed n -> String
    alt (MkAltF {k} c fs body) =
      "\n" ++ indent (S d) ++ c.name ++ "/" ++ show k ++ " => " ++ body (under {k} ix) (S (S d))
    armsText : CaseArmsOf (AltF Printed n) (Printed n) -> String
    armsText (Defaulted alts def) = concatMap alt alts ++ "\n" ++ indent (S d) ++ "_ => " ++ def ix (S (S d))
    armsText (Exhaustive alts) = concatMap alt (forget alts)
printer names (CaseLitF _ x arms) ix d = "case #" ++ show (ix x) ++ " of" ++ armsText arms
  where
    lit : (Lit, Printed n) -> String
    lit (k, e) = "\n" ++ indent (S d) ++ show k ++ " => " ++ e ix (S (S d))
    armsText : LitArmsOf (Printed n) -> String
    armsText (LitDefault alts def) = concatMap lit alts ++ "\n" ++ indent (S d) ++ "_ => " ++ def ix (S (S d))
    armsText (LitNoDefault alts) = concatMap lit (forget alts)
printer names (CaseNatF _ x arms) ix d = "case #" ++ show (ix x) ++ " of" ++ armsText arms
  where
    zero : Printed n -> String
    zero z = "\n" ++ indent (S d) ++ "0 => " ++ z ix (S (S d))
    succ : Printed (Under 1 n) -> String
    succ s = "\n" ++ indent (S d) ++ "S _ => " ++ s (under {k = 1} ix) (S (S d))
    armsText : NatArmsOf (Printed n) (Printed (Under 1 n)) -> String
    armsText (OnlyZero z) = zero z
    armsText (OnlySucc _ s) = succ s
    armsText (Both z _ s) = zero z ++ succ s
printer names (LamF _ _ b body) ix d =
  "\\(" ++ binderText names.dataName b ++ ") => " ++ body (under {k = 1} ix) d
printer names (AppF _ f x) ix d = "(" ++ f ix d ++ " " ++ x ix d ++ ")"
printer names (SuspendF _ body) ix d = "delay (" ++ body ix d ++ ")"
printer names (ResumeF _ e) ix d = "force (" ++ e ix d ++ ")"
printer names (UnreachableF _) ix d = "unreachable"
printer names (CrashF _ m) ix d = "crash " ++ show m
printer names (CrashWithF _ m) ix d = "idr.crash_str(" ++ m ix d ++ ")"
printer names (NewWorldF _) ix d = "new-world"
printer names (TensorF _ ty op) ix d =
  "tensor." ++ tensorOpName op ++ typeArgs names [ty] ++ "(" ++ joinBy ", " (map (\a => a ix d) (toList op)) ++ ")"
printer names (TabulateF {k} _ ty es body) ix d =
  "tabulate" ++ typeArgs names [ty] ++ "(" ++ joinBy ", " (map (\e => e ix d) (toList es)) ++ ")/" ++
  show k ++ " => " ++ body (under {k} ix) d
printer names (TabulateIOF {k} _ ty es w body _ _) ix d =
  "io.tabulate" ++ typeArgs names [ty] ++ "(" ++ joinBy ", " (map (\e => e ix d) (toList es)) ++ "; " ++
  w ix d ++ ")/" ++ show (S k) ++ " => " ++ body (under {k = S k} ix) d
printer names (ReduceF _ r acc el ty z x body) ix d =
  show r ++ typeArgs names [acc, el, ty] ++ "(" ++ z ix d ++ ", " ++ x ix d ++ ")/2 => " ++
  body (under {k = 2} ix) d
printer names (TieF _ x ds) ix d =
  "tie(" ++ x ix d ++ "; " ++ joinBy ", " (map dim ds) ++ ")"
  where
    dim : (Nat, Stated (Printed n)) -> String
    dim (a, SameAs e) = show a ++ "=" ++ e ix d
    dim (a, Natural e) = show a ++ "=" ++ e ix d

||| A function body, parameter `i` being `#i`, each function and data
||| instance named by `names`.
export
showBody : Names -> Term n -> Nat -> String
showBody names t = cata (printer names) t finToNat

||| A data instance's kind of sum, as the dump writes it after its key.
kindText : DataShape -> String
kindText (PlainSum _) = ""
kindText (InPlaceSum _) = " (" ++ show SumKind.InPlace ++ ")"
kindText (BaseListSum _ _) = " (" ++ show SumKind.BaseList ++ ")"

export
showSource : Source -> String
showSource p =
  let names = sourceNames p
  in unlines (map (dataDecl names) p.datas ++ map (fnDecl names) (p.others ++ [p.root]) ++
              ["root " ++ names.fnName p.root.id])
  where
    con : Names -> String -> (k ** Con k) -> String
    con names role (_ ** c) =
      "\n  " ++ c.name ++ " tag " ++ show c.tag ++ " (" ++
      joinBy ", " (map (binderText names.dataName) (toList c.fields)) ++ ")" ++ role
    dataDecl : Names -> IdrisMLIR.Term.Data -> String
    dataDecl names d = "data " ++ keyText d.key ++ kindText d.shape ++ conText d.shape ++ "\n"
      where
        conText : DataShape -> String
        conText (PlainSum cs) = concatMap (con names "") cs
        conText (InPlaceSum cs) = concatMap (con names "") cs
        conText (BaseListSum nil cons) =
          con names (" " ++ show CtorRole.ListNil) (0 ** nil) ++ con names (" " ++ show CtorRole.ListCons) (2 ** cons)
    fnDecl : Names -> TFn -> String
    fnDecl names f = keyText f.key ++ " " ++
                     concatMap (\(_, b) => "(" ++ binderText names.dataName b ++ ") ") (toList f.params) ++
                     ": " ++ tyText names.dataName f.result ++ " =\n  " ++ showBody names f.body 1 ++ "\n"
