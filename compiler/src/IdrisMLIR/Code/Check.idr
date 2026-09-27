||| The invariants of first-order Core (docs/architecture/05-middle-ir.md,
||| CORE-INV-*, CORE-CHECK-1), checked before `Emit`. A failure is an internal
||| compiler error: every user error is reported earlier.
|||
||| Much of what this module once checked now holds by construction: `VTy`
||| has no function or `Lazy` type (CORE-INV-2), string primitives are not
||| `Prim`s (CORE-INV-10), and every argument is an atom. What is left is
||| scoping, typing, quantities, coverage, data and the world.
module IdrisMLIR.Code.Check

import IdrisMLIR.Code
import IdrisMLIR.Ids
import IdrisMLIR.Rule
import IdrisMLIR.Types

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.String

%default total

||| A violated invariant and what violates it.
public export
Err : Type
Err = (Rule, String)

||| The variables in scope, with their quantities and types.
Scope : Type
Scope = SortedMap VarId (Quantity, VTy)

||| What a body is checked into: in a scope, its result type, or `Nothing`
||| when it cannot return.
Checker : Type
Checker = Scope -> Either Err (Maybe VTy)

fail : Rule -> String -> Either Err a
fail r msg = Left (r, msg)

require : Bool -> Rule -> String -> Either Err ()
require ok r msg = unless ok (fail r msg)

atomTy : Scope -> Atom -> Either Err VTy
atomTy sc (AVar x) = case lookup x sc of
  Nothing => fail CoreInv1 ("unbound variable " ++ show x)
  Just (Q0, _) => fail CoreInv5 ("quantity-0 variable " ++ show x ++ " used at runtime")
  Just (_, t) => Right t
atomTy _ (ALit l) = maybe (fail CoreInv2 "an Integer literal at runtime") Right (value (litTy l))
atomTy _ AErased = Right ErasedT

||| An argument in a position of the given quantity and type (CORE-INV-3).
arg : Scope -> (Quantity, VTy) -> Atom -> Either Err ()
arg sc (Q0, t) AErased = require (t == ErasedT) CoreInv3 "a quantity-0 position whose type is not Erased"
arg sc (Q0, _) _ = fail CoreInv3 "a quantity-0 position whose argument is not erased"
arg sc (_, t) a = do
  t' <- atomTy sc a
  require (t == t') CoreInv3 ("expected " ++ show t ++ ", got " ++ show t')

arguments : Scope -> List (Quantity, VTy) -> List Atom -> String -> Either Err ()
arguments sc ps as what = do
  require (length ps == length as) CoreInv2 (what ++ " with " ++ show (length as) ++ " arguments")
  traverse_ (uncurry (arg sc)) (zip ps as)

litOf : VTy -> Lit -> Bool
litOf (IntT t) (LInt t' _) = t == t'
litOf CharT (LChar _) = True
litOf _ _ = False

unique : Ord a => List a -> Bool
unique xs = length (Prelude.toList (the (SortedSet a) (fromList xs))) == length xs

fieldsOf : CCon -> List (Quantity, VTy)
fieldsOf c = map (\f => (f.quantity, f.type)) c.fields

||| The value an IO primitive returns in its `IORes`.
ioValue : Index -> IOOp -> VTy -> Bool
ioValue ix GetChar t = t == CharT
ioValue ix GetByte t = t == CharT
ioValue ix _ (DataT d) = case lookup d ix.datas of
  Just dt => case dt.cons of
    [c] => null c.fields
    _ => False
  Nothing => False
ioValue ix _ _ = False

||| A branch's result: it returns the expected type, or cannot return.
branch : VTy -> Either Err (Maybe VTy) -> Either Err ()
branch t r = do
  Just t' <- r
    | Nothing => pure ()
  require (t == t') CoreInv3 ("an alternative of type " ++ show t' ++ " in a match of type " ++ show t)

||| Checks that an operation, with its branches already folded, has type `t`.
op : Index -> Scope -> VTy -> Op Checker -> Either Err ()
op ix sc t (OPrim p as) = do
  arguments sc (map (QW,) (primArgs p)) as (show p)
  require (primResult p == t) CoreInv3 (show p ++ " bound at type " ++ show t)
op ix sc t (OCall f as) = do
  Just g <- pure (lookup f ix.fns)
    | Nothing => fail CoreInv2 ("call of unknown function " ++ show f)
  arguments sc (map (\p => (p.quantity, p.type)) g.params) as ("a call of " ++ show f)
  require (g.result == t) CoreInv3 ("a call of " ++ show f ++ " bound at type " ++ show t)
op ix sc t (OCon c as) = do
  Just con <- pure (lookup c ix.cons)
    | Nothing => fail CoreInv2 ("unknown constructor " ++ show c ++ " of " ++ show c.dataId)
  arguments sc (fieldsOf con) as ("constructor " ++ show c)
  require (DataT c.dataId == t) CoreInv3 ("constructor " ++ show c ++ " bound at type " ++ show t)
op ix sc t (OField a c i) = do
  s <- atomTy sc a
  require (s == DataT c.dataId) CoreInv3 ("a field of " ++ show c ++ " read from a value of type " ++ show s)
  Just dt <- pure (lookup c.dataId ix.datas)
    | Nothing => fail CoreInv3 ("unknown data " ++ show c.dataId)
  [con] <- pure dt.cons
    | _ => fail CoreInv6 ("a field read from " ++ show dt.id ++ ", which has several constructors")
  require (con.id == c) CoreInv6 (show c ++ " is not the constructor of " ++ show dt.id)
  Just f <- pure (getAt i con.fields)
    | Nothing => fail CoreInv3 (show c ++ " has no field " ++ show i)
  require (f.quantity /= Q0) CoreInv5 ("an erased field of " ++ show c ++ " read at runtime")
  require (f.type == t) CoreInv3 ("field " ++ show i ++ " of " ++ show c ++ " bound at type " ++ show t)
op ix sc t (OCrash _) = require (t == ErasedT) CoreInv3 ("a crash bound at type " ++ show t)
op ix sc t (OIO o as r) = do
  require (DataT r == t) CoreInv3 ("io." ++ show o ++ " bound at type " ++ show t)
  Just dt <- pure (lookup r ix.datas)
    | Nothing => fail CoreInv3 ("unknown IO result " ++ show r)
  [MkCCon _ _ [MkCField _ val, MkCField _ WorldT] _] <- pure dt.cons
    | _ => fail CoreInv3 (show r ++ " is not an IO result")
  require (ioValue ix o val) CoreInv3 ("io." ++ show o ++ " cannot return " ++ show val)
  arguments sc (map (QW,) (ioArgs o) ++ [(Q1, WorldT)]) as ("io." ++ show o)
op ix sc t (OCase x bs def) = do
  DataT d <- atomTy sc x
    | s => fail CoreInv6 ("constructor match on " ++ show x ++ " of type " ++ show s)
  Just dt <- pure (lookup d ix.datas)
    | Nothing => fail CoreInv3 ("unknown data " ++ show d)
  require (unique (map (.con) bs)) CoreInv6 "duplicate alternatives"
  -- CORE-INV-6: exhaustive; impossible alternatives are present, as `Absurd`.
  require (isJust def || all (\c => elem c.id (map (.con) bs)) dt.cons) CoreInv6
          ("a match on " ++ show d ++ " that does not cover every constructor")
  for_ bs $ \b => do
    Just con <- pure (find (\c => c.id == b.con) dt.cons)
      | Nothing => fail CoreInv6 (show b.con ++ " is not a constructor of " ++ show d)
    require (length b.fields == length con.fields) CoreInv6
            ("alternative " ++ show b.con ++ " binds the wrong number of fields")
    branch t (b.body (foldl (\s, (y, qt) => insert y qt s) sc (zip b.fields (fieldsOf con))))
  traverse_ (\e => branch t (e sc)) def
op ix sc t (OCaseLit x as def) = do
  s <- atomTy sc x
  require (all (litOf s . fst) as) CoreInv6 ("a literal that is not of type " ++ show s)
  require (unique (map (show . fst) as)) CoreInv6 "duplicate literals"
  traverse_ (\(_, e) => branch t (e sc)) as
  branch t (def sc)

||| The typing algebra of a body.
typing : Index -> Code -> Checker
typing ix = cata alg
  where
    alg : CodeF Checker -> Checker
    alg (BindF _ x q t o k) sc = do
      -- A quantity-0 binding holds the erased value (IDR-MATCH-4).
      if q == Q0
         then require (t == ErasedT) CoreInv3 ("a quantity-0 binding of type " ++ show t)
         else op ix sc t o
      k (insert x (q, t) sc)
    alg (RetF _ a) sc = Just <$> atomTy sc a
    alg (AbsurdF _) sc = Right Nothing

||| CORE-INV-6: every match has an alternative that can return. A match whose
||| alternatives are all impossible could not return either, and `Simplify`
||| makes the code around it `Absurd` instead. The algebra computes whether
||| code can return, and whether it contains such a match.
deadMatch : Code -> Bool
deadMatch c = snd (cata alg c)
  where
    alg : CodeF (Bool, Bool) -> (Bool, Bool)
    alg (BindF _ _ _ _ o (live, bad)) =
      let branches = toList o
          matchLive = case o of
                        OCase {} => any fst branches
                        OCaseLit {} => any fst branches
                        _ => True
      in (matchLive && live, not matchLive || any snd branches || bad)
    alg (RetF _ _) = (True, False)
    alg (AbsurdF _) = (False, False)

||| Variables of type %World: parameters, bindings and fields.
worldVars : Index -> CFn -> List VarId
worldVars ix fn = [p.var | p <- fn.params, p.type == WorldT] ++ cata alg fn.body
  where
    alg : CodeF (List VarId) -> List VarId
    alg (BindF _ x _ t o k) =
      (if t == WorldT then [x] else []) ++ fields o ++ concat o ++ k
      where
        fields : Op (List VarId) -> List VarId
        fields (OCase _ bs _) =
          concatMap (\b => case lookup b.con ix.cons of
                             Just c => [y | (y, f) <- zip b.fields c.fields, f.type == WorldT]
                             Nothing => []) bs
        fields _ = []
    alg _ = []

checkData : Index -> CData -> Either Err ()
checkData ix d = do
  require (map (.tag) d.cons == take (length d.cons) [0 .. length d.cons]) CoreInv7
          ("the tags of " ++ show d.id ++ " are not 0..n-1")
  for_ d.cons $ \c => for_ c.fields $ \f => do
    require ((f.quantity == Q0) == (f.type == ErasedT)) CoreInv3
            ("a field of " ++ show c.id ++ " is erased exactly when its quantity is 0")
    case f.type of
      DataT n => require (isJust (lookup n ix.datas)) CoreInv3 ("unknown data " ++ show n)
      _ => pure ()

||| Runtime containment is acyclic (CORE-INV-7).
acyclic : Index -> List CData -> Either Err ()
acyclic ix ds = traverse_ (\d => go (length ds) [d.id] d) ds
  where
    go : Nat -> List DataId -> CData -> Either Err ()
    go Z _ _ = pure ()
    go (S fuel) path d = for_ d.cons $ \c => for_ c.fields $ \f => case f.type of
      DataT n => if elem n path
                    then fail CoreInv7 (show n ++ " contains itself")
                    else maybe (pure ()) (go fuel (n :: path)) (lookup n ix.datas)
      _ => pure ()

||| Functions reachable from the root (CORE-INV-8).
reachable : Index -> FnId -> SortedSet FnId
reachable ix root = go (length (keys ix.fns) + 1) empty [root]
  where
    go : Nat -> SortedSet FnId -> List FnId -> SortedSet FnId
    go Z seen _ = seen
    go _ seen [] = seen
    go (S fuel) seen (f :: rest) =
      if contains f seen then go (S fuel) seen rest   -- `rest` is shorter
      else go fuel (insert f seen) (rest ++ maybe [] (calls . (.body)) (lookup f ix.fns))

checkFn : Index -> SortedSet FnId -> CFn -> Either Err ()
checkFn ix live' fn = do
  require (contains fn.id live') CoreInv8 "unreachable from the root"
  for_ (fn.result :: map (.type) fn.params) $ \t => case t of
    DataT d => require (isJust (lookup d ix.datas)) CoreInv3 ("unknown data " ++ show d)
    _ => pure ()
  for_ fn.params $ \p =>
    require ((p.quantity == Q0) == (p.type == ErasedT)) CoreInv3
            ("parameter " ++ show p.var ++ " is erased exactly when its quantity is 0")
  require (unique (map (.var) fn.params ++ binders fn.body)) CoreInv1 "a variable is bound twice"
  require (not (deadMatch fn.body)) CoreInv6 "a match whose alternatives are all impossible"
  r <- typing ix fn.body (fromList [(p.var, (p.quantity, p.type)) | p <- fn.params])
  traverse_ (\t => require (t == fn.result) CoreInv3
                     ("the body has type " ++ show t ++ ", not " ++ show fn.result)) r
  let us = uses fn.body
  for_ (worldVars ix fn) $ \w =>
    require (fromMaybe 0 (lookup w us) <= 1) CoreInv9
            ("the world " ++ show w ++ " is used more than once on a path")

||| Every invariant of first-order Core (CORE-CHECK-1).
export
check : Target -> Either Err ()
check t = do
  let ix = index t
  require (isJust (lookup t.root ix.fns)) CoreInv8 "the root is missing"
  require (unique (map (.id) t.fns)) CoreInv8 "a function is defined twice"
  traverse_ (checkData ix) t.datas
  acyclic ix t.datas
  let live' = reachable ix t.root
  traverse_ (checkFn ix live') t.fns
