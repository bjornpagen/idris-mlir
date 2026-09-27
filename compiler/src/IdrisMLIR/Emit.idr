||| First-order Core to the `idr` contract (docs/architecture/08-idr-dialect.md).
|||
||| A body is emitted by a fold: the algebra turns each layer of `Code` into
||| an emitter, a function from the values of the variables in scope to the
||| operations it appends and the value it produces. The operations are
||| `MLIR.MOp`s; `MLIR` prints them.
module IdrisMLIR.Emit

import IdrisMLIR.Code
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String

%default covering

------------------------------------------------------------------------------
-- Names and types
------------------------------------------------------------------------------

||| IDR-FN-2: injective mangling into an MLIR bare identifier.
export
symbol : String -> String
symbol s = case unpack s of
  [] => "_"
  (c :: cs) => (if isAlpha c || c == '_' then "" else "_") ++ concatMap escape (c :: cs)
  where
    escape : Char -> String
    escape c = if isAlphaNum c || c == '_' || c == '.'
                  then singleton c
                  else "$" ++ show (ord c) ++ "$"

mtype : VTy -> MType
mtype (IntT t) = I (width t)
mtype CharT = I 32
mtype StrT = IdrStr
mtype WorldT = IdrWorld
mtype ErasedT = IdrErased
mtype (DataT d) = IdrData (symbol d.name)
mtype DoubleT = F64

||| Two's complement bit pattern of `n` in `w` bits, read as signed.
twos : Nat -> Integer -> Integer
twos w n = let m = pow w
               r = n `mod` m
               r' = if r < 0 then r + m else r
           in if r' >= m `div` 2 then r' - m else r'
  where
    pow : Nat -> Integer
    pow Z = 1
    pow (S k) = 2 * pow k

------------------------------------------------------------------------------
-- The emission monad
------------------------------------------------------------------------------

record ES where
  constructor MkES
  next : Nat
  ops : SnocList MOp
  expected : List MType   -- the result types of the enclosing regions

E : Type -> Type
E = StateT ES (Either String)

||| A value with its type.
TV : Type
TV = (Value, MType)

Env : Type
Env = SortedMap VarId TV

internal : String -> E a
internal msg = lift (Left msg)

fresh : E String
fresh = do
  st <- get
  put ({ next $= S } st)
  pure ("%" ++ show st.next)

push : MOp -> E ()
push o = modify { ops $= (:< o) }

||| Runs an emitter inside a region whose result has type `t`.
expecting : MType -> E a -> E a
expecting t act = do
  modify { expected $= (t ::) }
  x <- act
  modify { expected $= drop 1 }
  pure x

||| Runs an emitter into a separate list of operations.
nested : E a -> E (a, List MOp)
nested act = do
  saved <- gets ops
  modify { ops := [<] }
  x <- act
  inner <- gets ops
  modify { ops := saved }
  pure (x, inner <>> [])

||| An operation with one result.
op1 : Loc -> String -> List TV -> List (String, Attr) -> MType -> E TV
op1 l n args ps t = do
  r <- fresh
  push (simple (Just (r, 1)) n (map fst args) ps (map snd args) [t] l)
  pure (r, t)

||| An operation without results.
op0 : Loc -> String -> List TV -> E ()
op0 l n args = push (simple Nothing n (map fst args) [] (map snd args) [] l)

||| A region of one block that ends by yielding the emitter's value.
yielding : Loc -> E TV -> E Region
yielding l act = do
  (_, ops) <- nested (act >>= \v => op0 l "scf.yield" [v])
  pure (MkRegion [] ops)

------------------------------------------------------------------------------
-- Atoms and primitives (IDR-IN-3)
------------------------------------------------------------------------------

constant : Loc -> Integer -> Nat -> E TV
constant l n w = op1 l "arith.constant" [] [("value", IntA (twos w n) (I w))] (I w)

atom : Loc -> Env -> Atom -> E TV
atom l env (AVar x) = maybe (internal ("unbound variable " ++ show x)) pure (lookup x env)
atom l env (ALit (LInt t n)) = constant l n (width t)
atom l env (ALit (LChar c)) = constant l c 32
atom l env (ALit (LStr s)) = op1 l "idr.str.lit" [] [("value", BytesA s)] IdrStr
atom l env (ALit (LDouble d)) = op1 l "arith.constant" [] [("value", FloatA d)] F64
atom l env (ALit (LBig _)) = internal "an Integer literal at runtime (SEM-BIG-1)"
atom l env AErased = op1 l "idr.erased" [] [] IdrErased

signedness : Bool -> List (String, Attr)
signedness s = if s then [("is_signed", UnitA)] else []

||| The `arith.cmpf` predicate: ordered, so false when an operand is NaN
||| (oeq 1, ogt 2, oge 3, olt 4, ole 5; SEM-DBL-2).
fpredicate : Cmp -> Integer
fpredicate CEq = 1
fpredicate CGt = 2
fpredicate CGte = 3
fpredicate CLt = 4
fpredicate CLte = 5

||| The `math` op of a C library function or exact operation (SEM-DBL-3).
mathOp : MathFn -> String
mathOp Exp = "math.exp"
mathOp Log = "math.log"
mathOp Pow = "math.powf"
mathOp Sin = "math.sin"
mathOp Cos = "math.cos"
mathOp Tan = "math.tan"
mathOp ASin = "math.asin"
mathOp ACos = "math.acos"
mathOp ATan = "math.atan"
mathOp Sqrt = "math.sqrt"
mathOp Floor = "math.floor"
mathOp Ceiling = "math.ceil"

||| The `arith.cmpi` predicate (eq 0, slt 2, sle 3, sgt 4, sge 5, ult 6, ...).
predicate : Cmp -> Bool -> Integer
predicate CEq _ = 0
predicate CLt s = if s then 2 else 6
predicate CLte s = if s then 3 else 7
predicate CGt s = if s then 4 else 8
predicate CGte s = if s then 5 else 9

prim : Loc -> Prim -> List TV -> E TV
prim l (IntOp op t) [a, b] = case op of
  Add => arith "arith.addi"
  Sub => arith "arith.subi"
  Mul => arith "arith.muli"
  And => arith "arith.andi"
  Or => arith "arith.ori"
  Xor => arith "arith.xori"
  Div => op1 l "idr.div" [a, b] (signedness (signed t)) (I (width t))
  Mod => op1 l "idr.mod" [a, b] (signedness (signed t)) (I (width t))
  where
    arith : String -> E TV
    arith n = op1 l n [a, b] [] (I (width t))
prim l (FloatOp op) [a, b] = op1 l name [a, b] [] F64
  where
    name : String
    name = case op of
      FAdd => "arith.addf"
      FSub => "arith.subf"
      FMul => "arith.mulf"
      FDiv => "arith.divf"
prim l Negate [a] = op1 l "arith.negf" [a] [] F64
prim l (Math f) as = op1 l (mathOp f) as [] F64
prim l (Compare c SDouble) [a, b] = do
  r <- op1 l "arith.cmpf" [a, b] [("predicate", IntA (fpredicate c) (I 64))] (I 1)
  op1 l "arith.extui" [r] [] (I 64)
prim l (Compare c s) [a, b] = do
  let sgn = case s of
              SInt t => signed t
              _ => False
  r <- op1 l "arith.cmpi" [a, b] [("predicate", IntA (predicate c sgn) (I 64))] (I 1)
  op1 l "arith.extui" [r] [] (I 64)
-- SEM-INT-7, SEM-CHAR-3
prim l (Cast from to) [a] = case (from, to) of
  (SInt f, SInt t) => resize (width f) (signed f) (width t)
  (SChar, SInt t) => resize 32 False (width t)
  (SInt f, SChar) => op1 l "idr.to_char" [a] (signedness (signed f)) (I 32)
  (SChar, SChar) => pure a
  -- SEM-DBL-4
  (SInt f, SDouble) => op1 l (if signed f then "arith.sitofp" else "arith.uitofp") [a] [] F64
  (SDouble, SInt t) => op1 l "idr.to_int" [a] [] (I (width t))
  (SDouble, SDouble) => pure a
  _ => internal ("cast " ++ show from ++ " to " ++ show to)
  where
    resize : Nat -> Bool -> Nat -> E TV
    resize f s t = if f == t then pure a
                   else if f > t then op1 l "arith.trunci" [a] [] (I t)
                   else op1 l (if s then "arith.extsi" else "arith.extui") [a] [] (I t)
prim l p _ = internal ("primitive " ++ show p ++ " with the wrong arguments")

------------------------------------------------------------------------------
-- Operations
------------------------------------------------------------------------------

||| The emitter of a body; `Nothing` when it cannot return.
Emitter : Type
Emitter = Maybe (Env -> E TV)

lookupData : Index -> DataId -> E CData
lookupData ix d = maybe (internal ("unknown data " ++ show d)) pure (lookup d ix.datas)

single : Index -> DataId -> E CCon
single ix d = do
  dt <- lookupData ix d
  case dt.cons of
    [c] => pure c
    _ => internal (show d ++ " does not have exactly one constructor")

con : Loc -> ConId -> List TV -> E TV
con l c vs = op1 l "idr.con" vs [("ctor", SymA [symbol c.dataId.name, symbol c.name])] (IdrData (symbol c.dataId.name))

||| An IO primitive, and the `IORes` value of its result and next world.
io : Index -> Loc -> IOOp -> List TV -> DataId -> E TV
io ix l op vs res = do
  mk <- single ix res
  (val, w) <- case (op, vs) of
    (PutStr, [s, w0]) => unitWith mk (op1 l "idr.io.put_str" [s, w0] [] IdrWorld)
    (PutChar, [c, w0]) => unitWith mk (op1 l "idr.io.put_char" [c, w0] [] IdrWorld)
    (PutInt t, [n, w0]) => unitWith mk (op1 l "idr.io.put_int" [n, w0] (signedness (signed t)) IdrWorld)
    (Exit, [n, w0]) => unitWith mk (op1 l "idr.io.exit" [n, w0] [] IdrWorld)
    (PutDouble, [d, w0]) => unitWith mk (op1 l "idr.io.put_double" [d, w0] [] IdrWorld)
    (GetChar, [w0]) => do
      r <- fresh
      push (simple (Just (r, 2)) "idr.io.get_char" [fst w0] [] [snd w0] [I 32, IdrWorld] l)
      pure ((r ++ "#0", I 32), (r ++ "#1", IdrWorld))
    _ => internal ("io." ++ show op ++ " with the wrong arguments")
  con l mk.id [val, w]
  where
    ||| The unit value of an IO result, built after the operation.
    unitWith : CCon -> E TV -> E (TV, TV)
    unitWith mk act = do
      w <- act
      case map (.type) mk.fields of
        [DataT u, _] => do
          unit <- single ix u
          v <- con l unit.id []
          pure (v, w)
        _ => internal (show res ++ " does not hold a unit value")

indexed : List a -> List (Nat, a)
indexed = go 0
  where
    go : Nat -> List a -> List (Nat, a)
    go _ [] = []
    go i (x :: xs) = (i, x) :: go (S i) xs

||| IDR-MATCH-2: the default region is the match's default, or else its last
||| alternative that can return. Alternatives that cannot are left out.
operation : Index -> Loc -> VTy -> Op Emitter -> Env -> E TV
operation ix l t (OPrim p as) env = traverse (atom l env) as >>= prim l p
operation ix l t (OCall f as) env = do
  vs <- traverse (atom l env) as
  op1 l "func.call" vs [("callee", SymA [symbol f.name])] (mtype t)
operation ix l t (OCon c as) env = traverse (atom l env) as >>= con l c
operation ix l t (OField a c i) env = do
  v <- atom l env a
  op1 l "idr.field" [v] [("ctor", SymA [symbol c.name]), ("index", IntA (cast i) (I 64))] (mtype t)
operation ix l t (OCrash _) env = internal "a crash is emitted by its block"
operation ix l t (OIO op as res) env = do
  vs <- traverse (atom l env) as
  io ix l op vs res
operation ix l t (OCase x bs def) env = do
  scrut <- atom l env x
  let live = mapMaybe (\b => map (MkBranch b.con b.fields) b.body) bs
  (cases, deflt) <- case (join def, reverse live) of
    (Just e, _) => pure (live, yielding l (e env))
    (Nothing, b :: rest) => pure (reverse rest, alternative scrut b)
    (Nothing, []) => internal "a match that cannot return"
  tag <- op1 l "idr.tag" [scrut] [] Index
  tags <- traverse (\b => (.tag) <$> conOf b.con) cases
  dr <- deflt
  crs <- traverse (alternative scrut) cases
  r <- fresh
  push (MkMOp (Just (r, 1)) "scf.index_switch" [fst tag] [("cases", I64ArrayA (map cast tags))]
              (dr :: crs) [] [Index] [mtype t] l)
  pure (r, mtype t)
  where
    conOf : ConId -> E CCon
    conOf c = maybe (internal ("unknown constructor " ++ show c)) pure (lookup c ix.cons)
    ||| An alternative: reads the fields it binds, then yields its value.
    alternative : TV -> Branch (Env -> E TV) -> E Region
    alternative scrut b = do
      c <- conOf b.con
      yielding l $ do
        fs <- for (zip b.fields (indexed c.fields)) $ \(y, (i, f)) =>
          if f.type == ErasedT then pure Nothing
          else Just . (y,) <$> op1 c.loc "idr.field" [scrut]
                                   [("ctor", SymA [symbol c.id.name]), ("index", IntA (cast i) (I 64))]
                                   (mtype f.type)
        b.body (foldl (\m, (y, v) => insert y v m) env (catMaybes fs))
-- IDR-MATCH-3: a chain of comparisons, in alternative order.
operation ix l t (OCaseLit x as def) env = do
  scrut <- atom l env x
  let live = mapMaybe (\(k, e) => (k,) <$> e) as
  case (def, reverse live) of
    (Just e, _) => chain scrut live e
    (Nothing, (_, e) :: rest) => chain scrut (reverse rest) e
    (Nothing, []) => internal "a match that cannot return"
  where
    chain : TV -> List (Lit, Env -> E TV) -> (Env -> E TV) -> E TV
    chain scrut [] final = final env
    chain scrut ((k, e) :: rest) final = do
      kv <- atom l env (ALit k)
      c <- op1 l "arith.cmpi" [scrut, kv] [("predicate", IntA 0 (I 64))] (I 1)
      thenR <- yielding l (e env)
      elseR <- yielding l (chain scrut rest final)
      r <- fresh
      push (MkMOp (Just (r, 1)) "scf.if" [fst c] [] [thenR, elseR] [] [I 1] [mtype t] l)
      pure (r, mtype t)

||| The algebra: one layer of `Code` to its emitter.
body : Index -> CodeF Emitter -> Emitter
-- SEM-CRASH-2: a crash ends its region, with a value of the region's type.
body ix (BindF l x q t (OCrash m) k) = Just $ \env => do
  (r :: _) <- gets expected
    | [] => internal "a crash outside a region"
  op1 l "idr.crash" [] [("message", StrA m)] r
body ix (BindF l x q t o k) = Just $ \env => do
  -- IDR-MATCH-4: a quantity-0 binding is the erased value.
  v <- if q == Q0 then atom l env AErased else expecting (mtype t) (operation ix l t o env)
  case k of
    Just rest => rest (insert x v env)
    Nothing => internal "code after a binding cannot return"
body ix (RetF l a) = Just (\env => atom l env a)
body ix (AbsurdF _) = Nothing

------------------------------------------------------------------------------
-- Declarations
------------------------------------------------------------------------------

dataDecl : CData -> MOp
dataDecl d =
  MkMOp Nothing "idr.data" [] [("sym_name", StrA (symbol d.id.name))]
        [MkRegion [] (map ctor d.cons)] [("idr.name", StrA d.idrisName)] [] [] d.loc
  where
    ctor : CCon -> MOp
    ctor c = MkMOp Nothing "idr.ctor" []
               [ ("field_types", ArrayA (map (TypeA . mtype . (.type)) c.fields))
               , ("quantities", ArrayA (map (StrA . show . (.quantity)) c.fields))
               , ("sym_name", StrA (symbol c.id.name))
               , ("tag", IntA (cast c.tag) (I 64)) ]
               [] [("idr.name", StrA c.id.name)] [] [] c.loc

||| A value of a type, for a body that cannot return: it is never used.
inhabitant : Index -> Loc -> Nat -> VTy -> E (Maybe TV)
inhabitant ix l fuel (IntT t) = Just <$> constant l 0 (width t)
inhabitant ix l fuel CharT = Just <$> constant l 0 32
inhabitant ix l fuel StrT = Just <$> op1 l "idr.str.lit" [] [("value", BytesA "")] IdrStr
inhabitant ix l fuel ErasedT = Just <$> op1 l "idr.erased" [] [] IdrErased
inhabitant ix l fuel DoubleT = Just <$> op1 l "arith.constant" [] [("value", FloatA 0.0)] F64
inhabitant ix l fuel WorldT = pure Nothing
inhabitant ix l Z (DataT d) = pure Nothing
inhabitant ix l (S fuel) (DataT d) = do
  dt <- lookupData ix d
  case dt.cons of
    (c :: _) => do
      fs <- traverse (inhabitant ix l fuel . (.type)) c.fields
      maybe (pure Nothing) (map Just . con l c.id) (sequence fs)
    [] => pure Nothing

function : Index -> SortedSet FnId -> CFn -> E MOp
function ix breakers fn = do
  let params = map (\p => ("%a" ++ show p.var.index, p)) fn.params
  let env = fromList (map (\(n, p) => (p.var, (n, mtype p.type))) params)
  let res = mtype fn.result
  (_, ops) <- nested $ expecting res $ do
    v <- case cata (body ix) fn.body of
      Just e => e env
      -- Nothing reaches this body: return any value of the type, or call
      -- the function itself when there is none (the call never runs).
      Nothing => do
        dflt <- inhabitant ix fn.loc (length (keys ix.datas) + 1) fn.result
        case dflt of
          Just v => pure v
          Nothing => op1 fn.loc "func.call" (map (\(n, p) => (n, mtype p.type)) params)
                         [("callee", SymA [symbol fn.id.name])] res
    op0 fn.loc "func.return" [v]
  let argAttrs = if null params then []
                 else [("arg_attrs", ArrayA (map (\(_, p) => DictA [("idr.quantity", StrA (show p.quantity))]) params))]
  pure (MkMOp Nothing "func.func" []
              (argAttrs ++ [ ("function_type", TypeA (FunctionT (map (mtype . (.type)) fn.params) [res]))
                           , ("sym_name", StrA (symbol fn.id.name))
                           , ("sym_visibility", StrA "private") ]
               ++ (if contains fn.id breakers then [("no_inline", UnitA)] else []))
              [MkRegion (map (\(n, p) => (n, mtype p.type)) params) ops]
              [("idr.name", StrA fn.idrisName)] [] [] fn.loc)

||| The contract text of a first-order program.
export
emit : Target -> Either String String
emit t = do
  let ix = index t
  (st, fns) <- runStateT (MkES 0 [<] []) (traverse (function ix (loopBreakers t.fns)) t.fns)
  let kind = case t.entry of
               IntEntry => "int"
               IOEntry => "io"
  pure (showModule [ ("idr.version", IntA (cast (version t)) (I 64))
                   , ("idr.entry", SymA [symbol t.root.name])
                   , ("idr.entry_kind", StrA kind) ]
                   (map dataDecl t.datas ++ fns))
