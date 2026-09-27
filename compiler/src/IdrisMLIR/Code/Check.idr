||| The invariants of first-order Core (docs/architecture/05-middle-ir.md,
||| CORE-INV-*, CORE-CHECK-1), checked before `Emit`. A failure is an internal
||| compiler error: every user error is reported earlier.
|||
||| Much of what this module once checked now holds by construction: `VTy`
||| has no function or `Lazy` type (CORE-INV-2), string primitives are not
||| `Prim`s (CORE-INV-10), region operations occur only in `Code Mem`, and
||| every argument is an atom. What is left is scoping, typing, quantities,
||| coverage, data and the world.
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

||| What is in scope: variables with their quantities and types, join points
||| with the types of their parameters, and the function's result types.
record Scope where
  constructor MkScope
  vars : SortedMap VarId (Quantity, VTy)
  joins : SortedMap JoinId (List (Quantity, VTy))
  results : List VTy

Checker : Type
Checker = Scope -> Either Err ()

fail : Rule -> String -> Either Err a
fail r msg = Left (r, msg)

require : Bool -> Rule -> String -> Either Err ()
require ok r msg = unless ok (fail r msg)

atomTy : Scope -> Atom -> Either Err VTy
atomTy sc (AVar x) = case lookup x sc.vars of
  Nothing => fail CoreInv1 ("unbound variable " ++ show x)
  Just (Q0, _) => fail CoreInv5 ("quantity-0 variable " ++ show x ++ " used at runtime")
  Just (_, t) => Right t
atomTy _ (ALit l) = maybe (fail CoreInv2 "an Integer literal at runtime") Right (value (litTy l))
atomTy _ AErased = Right ErasedT
atomTy _ (AUndef t) = Right t

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
ioValue : Index p -> IOOp -> VTy -> Bool
ioValue ix GetChar t = t == CharT
ioValue ix GetByte t = t == CharT
ioValue ix _ (DataT d) = case lookup d ix.datas of
  Just dt => case dt.cons of
    [c] => null c.fields
    _ => False
  Nothing => False
ioValue ix _ _ = False

||| Checks that an operation has the types of the variables it binds.
op : Index p -> Scope -> List VTy -> Op -> Either Err ()
op ix sc ts (OPrim p as) = do
  arguments sc (map (QW,) (primArgs p)) as (show p)
  require (ts == [primResult p]) CoreInv3 (show p ++ " bound at types " ++ show ts)
op ix sc ts (OCall f as) = do
  Just g <- pure (lookup f ix.fns)
    | Nothing => fail CoreInv2 ("call of unknown function " ++ show f)
  arguments sc (map (\p => (p.quantity, p.type)) g.params) as ("a call of " ++ show f)
  require (g.results == ts) CoreInv3 ("a call of " ++ show f ++ " bound at types " ++ show ts)
op ix sc ts (OCon c as) = do
  Just con <- pure (lookup c ix.cons)
    | Nothing => fail CoreInv2 ("unknown constructor " ++ show c ++ " of " ++ show c.dataId)
  arguments sc (fieldsOf con) as ("constructor " ++ show c)
  require (ts == [DataT c.dataId]) CoreInv3 ("constructor " ++ show c ++ " bound at types " ++ show ts)
op ix sc ts (OField a c i) = do
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
  require (ts == [f.type]) CoreInv3 ("field " ++ show i ++ " of " ++ show c ++ " bound at types " ++ show ts)
op ix sc ts (OIO o as r) = do
  require (ts == [DataT r]) CoreInv3 ("io." ++ show o ++ " bound at types " ++ show ts)
  Just dt <- pure (lookup r ix.datas)
    | Nothing => fail CoreInv3 ("unknown IO result " ++ show r)
  [MkCCon _ _ [MkCField _ val, MkCField _ WorldT] _] <- pure dt.cons
    | _ => fail CoreInv3 (show r ++ " is not an IO result")
  require (ioValue ix o val) CoreInv3 ("io." ++ show o ++ " cannot return " ++ show val)
  arguments sc (map (QW,) (ioArgs o) ++ [(Q1, WorldT)]) as ("io." ++ show o)

bindParams : Scope -> List Param -> Scope
bindParams sc ps = { vars $= \m => foldl (\m', p => insert p.var (p.quantity, p.type) m') m ps } sc

||| A quantity-0 binding holds the erased value (IDR-MATCH-4), and a
||| parameter is erased exactly when its quantity is 0.
erasure : List Param -> Either Err ()
erasure ps = for_ ps $ \p =>
  require ((p.quantity == Q0) == (p.type == ErasedT)) CoreInv3
          (show p.var ++ " is erased exactly when its quantity is 0")

||| The typing algebra of a body.
typing : Index p -> Code p -> Checker
typing ix = cata alg
  where
    alg : CodeF q Checker -> Checker
    alg (LetF _ ps o k) sc = do
      erasure ps
      unless (all ((== Q0) . (.quantity)) ps) $ op ix sc (map (.type) ps) o
      k (bindParams sc ps)
    alg (JoinF _ j ps b k) sc = do
      erasure ps
      let sc' = { joins $= insert j (map (\p => (p.quantity, p.type)) ps) } sc
      b (bindParams sc' ps)
      k sc'
    alg (JumpF _ j as) sc = do
      Just ts <- pure (lookup j sc.joins)
        | Nothing => fail CoreInv1 ("a jump to " ++ show j ++ ", which is not in scope")
      arguments sc ts as ("a jump to " ++ show j)
    alg (CaseF _ x bs def) sc = do
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
        b.body ({ vars $= \m => foldl (\m', (y, qt) => insert y qt m') m (zip b.fields (fieldsOf con)) } sc)
      traverse_ (\e => e sc) def
    alg (CaseLitF _ x as def) sc = do
      s <- atomTy sc x
      require (all (litOf s . fst) as) CoreInv6 ("a literal that is not of type " ++ show s)
      require (unique (map (show . fst) as)) CoreInv6 "duplicate literals"
      traverse_ (\(_, e) => e sc) as
      def sc
    alg (RetF _ as) sc = do
      ts <- traverse (atomTy sc) as
      require (ts == sc.results) CoreInv3 ("a result of types " ++ show ts ++ ", not " ++ show sc.results)
    alg (CrashF _ _) sc = pure ()
    alg (AbsurdF _) sc = pure ()
    alg (MarkF _ x k) sc = k ({ vars $= insert x (QW, IntT UInt64) } sc)
    alg (ReleaseF _ x k) sc = do
      _ <- atomTy sc (AVar x)
      k sc

||| CORE-INV-6: every match has an alternative that can be reached. A match
||| whose alternatives are all impossible could not be reached either, and
||| `Simplify` makes the code around it `Absurd` instead. The algebra
||| computes whether code can be reached, and whether it contains such a
||| match.
deadMatch : Code p -> Bool
deadMatch c = snd (cata alg c)
  where
    alg : CodeF q (Bool, Bool) -> (Bool, Bool)
    alg (LetF _ _ _ (live, bad)) = (live, bad)
    alg (JoinF _ _ _ (_, bb) (live, bk)) = (live, bb || bk)
    alg (CaseF _ _ bs d) =
      let parts = map (.body) bs ++ toList d
      in (any fst parts, not (any fst parts) || any snd parts)
    alg (CaseLitF _ _ as d) =
      let parts = d :: map snd as
      in (any fst parts, not (any fst parts) || any snd parts)
    alg (AbsurdF _) = (False, False)
    alg (MarkF _ _ k) = k
    alg (ReleaseF _ _ k) = k
    alg _ = (True, False)

||| Variables of type %World: parameters, bindings, join parameters and
||| fields.
worldVars : Index p -> CFn p -> List VarId
worldVars ix fn = [p.var | p <- fn.params, p.type == WorldT] ++ cata alg fn.body
  where
    worlds : List Param -> List VarId
    worlds ps = [p.var | p <- ps, p.type == WorldT]
    alg : CodeF q (List VarId) -> List VarId
    alg (LetF _ ps _ k) = worlds ps ++ k
    alg (JoinF _ _ ps b k) = worlds ps ++ b ++ k
    alg (CaseF _ _ bs d) =
      concatMap (\b => case lookup b.con ix.cons of
                         Just c => [y | (y, f) <- zip b.fields c.fields, f.type == WorldT]
                         Nothing => []) bs ++
      concatMap (.body) bs ++ fromMaybe [] d
    alg other = concat other

checkData : Index p -> CData -> Either Err ()
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
acyclic : Index p -> List CData -> Either Err ()
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
reachable : Index p -> FnId -> SortedSet FnId
reachable ix root = go (length (keys ix.fns) + 1) empty [root]
  where
    go : Nat -> SortedSet FnId -> List FnId -> SortedSet FnId
    go Z seen _ = seen
    go _ seen [] = seen
    go (S fuel) seen (f :: rest) =
      if contains f seen then go (S fuel) seen rest   -- `rest` is shorter
      else go fuel (insert f seen) (rest ++ maybe [] (calls . (.body)) (lookup f ix.fns))

checkFn : Index p -> SortedSet FnId -> CFn p -> Either Err ()
checkFn ix live' fn = do
  require (contains fn.id live') CoreInv8 "unreachable from the root"
  for_ (fn.results ++ map (.type) fn.params) $ \t => case t of
    DataT d => require (isJust (lookup d ix.datas)) CoreInv3 ("unknown data " ++ show d)
    _ => pure ()
  erasure fn.params
  require (unique (map (.var) fn.params ++ binders fn.body)) CoreInv1 "a variable is bound twice"
  require (unique (joins fn.body)) CoreInv1 "a join point is declared twice"
  require (not (deadMatch fn.body)) CoreInv6 "a match whose alternatives are all impossible"
  typing ix fn.body (MkScope (fromList [(p.var, (p.quantity, p.type)) | p <- fn.params]) empty fn.results)
  let us = uses fn.body
  let again = the (SortedSet VarId) (fromList (loopOuterUses fn.body))
  for_ (worldVars ix fn) $ \w =>
    require (fromMaybe 0 (lookup w us) <= 1 && not (contains w again)) CoreInv9
            ("the world " ++ show w ++ " is used more than once on a path")

||| Every invariant of first-order Core (CORE-CHECK-1).
export
check : Target p -> Either Err ()
check t = do
  let ix = index t
  require (isJust (lookup t.root ix.fns)) CoreInv8 "the root is missing"
  require (unique (map (.id) t.fns)) CoreInv8 "a function is defined twice"
  traverse_ (checkData ix) t.datas
  acyclic ix t.datas
  let live' = reachable ix t.root
  traverse_ (checkFn ix live') t.fns
