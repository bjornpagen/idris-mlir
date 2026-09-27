||| First-order Core to the `idr` contract (docs/architecture/08-idr-dialect.md).
|||
||| A body is emitted by a fold: the algebra turns each layer of `Code` into
||| an emitter, a function from the values of the variables in scope to the
||| operations it appends. Control flow is MLIR's blocks: a join point is a
||| block with arguments, a jump is `cf.br`, a match is `cf.switch` on the
||| tag or a chain of `cf.cond_br`, and a loop is a join point its own body
||| branches back to. The operations are `MLIR.MOp`s; `MLIR` prints them.
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

||| The block being written: its label, arguments and operations so far.
record Open where
  constructor MkOpen
  label : String
  args : List (Value, MType)
  ops : SnocList MOp

record ES where
  constructor MkES
  next : Nat
  labels : Nat
  current : Open
  done : SnocList Block
  ||| The block of each join point in scope.
  targets : SortedMap JoinId String
  ||| The result types of the function being emitted.
  results : List MType

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

label : E String
label = do
  st <- get
  put ({ labels $= S } st)
  pure ("^bb" ++ show (S st.labels))

push : MOp -> E ()
push o = modify { current.ops $= (:< o) }

||| Ends the current block with a terminator.
terminate : MOp -> E ()
terminate o = do
  push o
  st <- get
  put ({ done $= (:< MkBlock st.current.label st.current.args (st.current.ops <>> [])) } st)

||| Starts writing a block.
start : String -> List (Value, MType) -> E ()
start l as = modify { current := MkOpen l as [<] }

||| An operation with results.
opN : Loc -> String -> List TV -> List (String, Attr) -> List MType -> E (List TV)
opN l n args ps ts = do
  r <- fresh
  push (simple (Just (r, length ts)) n (map fst args) ps (map snd args) ts l)
  pure (case ts of
          [t] => [(r, t)]
          _ => zipWith (\i, t => (r ++ "#" ++ show i, t)) [0 .. length ts] ts)

||| An operation with one result.
op1 : Loc -> String -> List TV -> List (String, Attr) -> MType -> E TV
op1 l n args ps t = do
  r <- fresh
  push (simple (Just (r, 1)) n (map fst args) ps (map snd args) [t] l)
  pure (r, t)

||| A terminator branching to blocks.
branch : Loc -> String -> List TV -> List String -> List (String, Attr) -> E ()
branch l n args succs ps = terminate (MkMOp Nothing n (map fst args) succs ps [] [] (map snd args) [] l)

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
atom l env (AUndef t) = op1 l "ub.poison" [] [] (mtype t)

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
prim l DoubleHead [a] = op1 l "idr.double_head" [a] [] (I 32)
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

lookupData : Index p -> DataId -> E CData
lookupData ix d = maybe (internal ("unknown data " ++ show d)) pure (lookup d ix.datas)

single : Index p -> DataId -> E CCon
single ix d = do
  dt <- lookupData ix d
  case dt.cons of
    [c] => pure c
    _ => internal (show d ++ " does not have exactly one constructor")

con : Loc -> ConId -> List TV -> E TV
con l c vs = op1 l "idr.con" vs [("ctor", SymA [symbol c.dataId.name, symbol c.name])] (IdrData (symbol c.dataId.name))

||| An IO primitive, and the `IORes` value of its result and next world.
io : Index p -> Loc -> IOOp -> List TV -> DataId -> E TV
io ix l op vs res = do
  mk <- single ix res
  (val, w) <- case (op, vs) of
    (PutStr, [s, w0]) => unitWith mk (op1 l "idr.io.put_str" [s, w0] [] IdrWorld)
    (PutChar, [c, w0]) => unitWith mk (op1 l "idr.io.put_char" [c, w0] [] IdrWorld)
    (PutInt t, [n, w0]) => unitWith mk (op1 l "idr.io.put_int" [n, w0] (signedness (signed t)) IdrWorld)
    (Exit, [n, w0]) => unitWith mk (op1 l "idr.io.exit" [n, w0] [] IdrWorld)
    (PutDouble, [d, w0]) => unitWith mk (op1 l "idr.io.put_double" [d, w0] [] IdrWorld)
    (GetChar, [w0]) => pair <$> opN l "idr.io.get_char" [w0] [] [I 32, IdrWorld]
    (GetByte, [w0]) => pair <$> opN l "idr.io.get_byte" [w0] [] [I 32, IdrWorld]
    _ => internal ("io." ++ show op ++ " with the wrong arguments")
  con l mk.id [val, w]
  where
    pair : List TV -> (TV, TV)
    pair [a, b] = (a, b)
    pair _ = (("", I 32), ("", IdrWorld))
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

||| The values of an operation's results.
operation : Index p -> Loc -> List Param -> Op -> Env -> E (List TV)
operation ix l ps (OPrim p as) env = map pure (traverse (atom l env) as >>= prim l p)
operation ix l ps (OCall f as) env = do
  vs <- traverse (atom l env) as
  opN l "func.call" vs [("callee", SymA [symbol f.name])] (map (mtype . (.type)) ps)
operation ix l ps (OCon c as) env = map pure (traverse (atom l env) as >>= con l c)
operation ix l ps (OField a c i) env = do
  v <- atom l env a
  t <- case ps of
         [p] => pure (mtype p.type)
         _ => internal "a field read with other than one result"
  map pure (op1 l "idr.field" [v] [("ctor", SymA [symbol c.name]), ("index", IntA (cast i) (I 64))] t)
operation ix l ps (OIO op as res) env = do
  vs <- traverse (atom l env) as
  map pure (io ix l op vs res)

------------------------------------------------------------------------------
-- Bodies
------------------------------------------------------------------------------

||| The emitter of a body, which ends its block; `Nothing` when it cannot be
||| reached.
Emitter : Type
Emitter = Maybe (Env -> E ())

indexed : List a -> List (Nat, a)
indexed = go 0
  where
    go : Nat -> List a -> List (Nat, a)
    go _ [] = []
    go i (x :: xs) = (i, x) :: go (S i) xs

bindAll : Env -> List Param -> List TV -> Env
bindAll env ps vs = foldl (\m, (p, v) => insert p.var v m) env (zip ps vs)

||| IDR-MATCH-2: the alternatives that can be reached; the default is the
||| match's default, or else its last reachable alternative.
split : List (a, Env -> E ()) -> Maybe (Env -> E ()) -> E (List (a, Env -> E ()), Env -> E ())
split live (Just d) = pure (live, d)
split live Nothing = case reverse live of
  ((_, d) :: rest) => pure (reverse rest, d)
  [] => internal "a match that cannot be reached"

||| The algebra: one layer of `Code` to its emitter.
body : Index Mem -> CodeF Mem Emitter -> Emitter
body ix (LetF l ps o k) = do
  rest <- k
  pure $ \env => do
    -- IDR-MATCH-4: a quantity-0 binding is the erased value.
    vs <- if all ((== Q0) . (.quantity)) ps
            then traverse (\_ => atom l env AErased) ps
            else operation ix l ps o env
    rest (bindAll env ps vs)
body ix (JoinF l j ps b k) = do
  rest <- k
  pure $ \env => do
    lbl <- label
    names <- traverse (const fresh) ps
    let args = zip names (map (mtype . (.type)) ps)
    modify { targets $= insert j lbl }
    rest env
    case b of
      Just inside => do
        start lbl args
        inside (bindAll env ps args)
      -- Nothing reaches the join point's body: nothing jumps to it.
      Nothing => pure ()
body ix (JumpF l j as) = Just $ \env => do
  vs <- traverse (atom l env) as
  Just lbl <- gets (lookup j . targets)
    | Nothing => internal ("a jump to " ++ show j ++ ", which is not in scope")
  branch l "cf.br" vs [lbl] []
body ix (CaseF l x bs d) = Just $ \env => do
  scrut <- atom l env x
  let live = mapMaybe (\b => (\e => (b, e)) <$> b.body) bs
  (cases, deflt) <- split (map (\(b, e) => (MkBranch b.con b.fields (), e)) live) (join d)
  -- The default reads the fields of the alternative it stands for.
  let dflt = case (join d, reverse live) of
               (Just _, _) => Nothing
               (Nothing, (b, _) :: _) => Just (MkBranch b.con b.fields ())
               _ => Nothing
  case cases of
    -- One alternative can be reached: no choice is made.
    [] => alternative env scrut dflt deflt
    _ => do
      tag <- op1 l "idr.tag" [scrut] [] (I 64)
      tags <- traverse (\(b, _) => (.tag) <$> conOf b.con) cases
      dlbl <- label
      clbls <- traverse (const label) cases
      branch l "cf.switch" [tag] (dlbl :: clbls)
             [ ("case_operand_segments", I32ArrayA (map (const 0) cases))
             , ("case_values", DenseI64A (map cast tags))
             , ("operandSegmentSizes", I32ArrayA [1, 0, 0]) ]
      start dlbl []
      alternative env scrut dflt deflt
      for_ (zip clbls cases) $ \(lbl, (b, e)) => do
        start lbl []
        alternative env scrut (Just b) e
  where
    conOf : ConId -> E CCon
    conOf c = maybe (internal ("unknown constructor " ++ show c)) pure (lookup c ix.cons)
    ||| An alternative: reads the fields it binds, then runs.
    alternative : Env -> TV -> Maybe (Branch ()) -> (Env -> E ()) -> E ()
    alternative env scrut b e = do
      case b of
        Nothing => e env
        Just br => do
          c <- conOf br.con
          fs <- for (zip br.fields (indexed c.fields)) $ \(y, (i, f)) =>
            if f.type == ErasedT then pure Nothing
            else Just . (y,) <$> op1 c.loc "idr.field" [scrut]
                                     [("ctor", SymA [symbol c.id.name]), ("index", IntA (cast i) (I 64))]
                                     (mtype f.type)
          e (foldl (\m, (y, v) => insert y v m) env (catMaybes fs))
-- IDR-MATCH-3: a chain of comparisons, in alternative order.
body ix (CaseLitF l x as d) = Just $ \env => do
  scrut <- atom l env x
  let live = mapMaybe (\(k, e) => (k,) <$> e) as
  (cases, deflt) <- split live d
  chain env scrut cases deflt
  where
    chain : Env -> TV -> List (Lit, Env -> E ()) -> (Env -> E ()) -> E ()
    chain env scrut [] final = final env
    chain env scrut ((k, e) :: rest) final = do
      kv <- atom l env (ALit k)
      c <- op1 l "arith.cmpi" [scrut, kv] [("predicate", IntA 0 (I 64))] (I 1)
      yes <- label
      no <- label
      branch l "cf.cond_br" [c] [yes, no] [("operandSegmentSizes", I32ArrayA [1, 0, 0])]
      start yes []
      e env
      start no []
      chain env scrut rest final
body ix (RetF l as) = Just $ \env => do
  vs <- traverse (atom l env) as
  terminate (simple Nothing "func.return" (map fst vs) [] (map snd vs) [] l)
-- SEM-CRASH-2: a crash ends its block with values of the function's result
-- types, which are never produced.
body ix (CrashF l m) = Just $ \env => do
  ts <- gets results
  vs <- opN l "idr.crash" [] [("message", StrA m)] ts
  terminate (simple Nothing "func.return" (map fst vs) [] (map snd vs) [] l)
body ix (AbsurdF _) = Nothing
body ix (MarkF l x k) = k
body ix (ReleaseF l x k) = k

------------------------------------------------------------------------------
-- Declarations
------------------------------------------------------------------------------

dataDecl : CData -> MOp
dataDecl d =
  MkMOp Nothing "idr.data" [] [] [("sym_name", StrA (symbol d.id.name))]
        [single [] (map ctor d.cons)] [("idr.name", StrA d.idrisName)] [] [] d.loc
  where
    ctor : CCon -> MOp
    ctor c = MkMOp Nothing "idr.ctor" [] []
               [ ("field_types", ArrayA (map (TypeA . mtype . (.type)) c.fields))
               , ("quantities", ArrayA (map (StrA . show . (.quantity)) c.fields))
               , ("sym_name", StrA (symbol c.id.name))
               , ("tag", IntA (cast c.tag) (I 64)) ]
               [] [("idr.name", StrA c.id.name)] [] [] c.loc

||| A value of a type, for a body that cannot be reached: it is never used.
inhabitant : Index p -> Loc -> Nat -> VTy -> E (Maybe TV)
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

function : Index Mem -> SortedSet FnId -> CFn Mem -> E MOp
function ix breakers fn = do
  let params = map (\p => ("%a" ++ show p.var.index, p)) fn.params
  let env = the Env (fromList (map (\(n, p) => (p.var, (n, mtype p.type))) params))
  let args = map (\(n, p) => (n, mtype p.type)) params
  let res = map mtype fn.results
  modify { current := MkOpen "^bb0" args [<], done := [<], targets := empty, results := res, labels := 0 }
  case cata (body ix) fn.body of
    Just e => e env
    -- Nothing reaches this body: return any value of the types, or call the
    -- function itself when there is none (the call never runs).
    Nothing => do
      dflts <- traverse (inhabitant ix fn.loc (length (keys ix.datas) + 1)) fn.results
      vs <- maybe (opN fn.loc "func.call" args [("callee", SymA [symbol fn.id.name])] res)
                   pure (the (Maybe (List TV)) (sequence dflts))
      terminate (simple Nothing "func.return" (map (\(v, _) => v) vs) [] (map (\(_, t) => t) vs) [] fn.loc)
  blocks <- gets done
  let argAttrs = if null params then []
                 else [("arg_attrs", ArrayA (map (\(_, p) => DictA [("idr.quantity", StrA (show p.quantity))]) params))]
  pure (MkMOp Nothing "func.func" [] []
              (argAttrs ++ [ ("function_type", TypeA (FunctionT (map (mtype . (.type)) fn.params) res))
                           , ("sym_name", StrA (symbol fn.id.name))
                           , ("sym_visibility", StrA "private") ]
               ++ (if contains fn.id breakers then [("no_inline", UnitA)] else []))
              [MkRegion (blocks <>> [])]
              [("idr.name", StrA fn.idrisName)] [] [] fn.loc)

||| The contract text of a first-order program.
export
emit : Target Mem -> Either String String
emit t = do
  let ix = index t
  (st, fns) <- runStateT (MkES 0 0 (MkOpen "^bb0" [] [<]) [<] empty [])
                         (traverse (function ix (loopBreakers t.fns)) t.fns)
  let kind = case t.entry of
               IntEntry => "int"
               IOEntry => "io"
  pure (showModule [ ("idr.version", IntA (cast (version t)) (I 64))
                   , ("idr.entry", SymA [symbol t.root.name])
                   , ("idr.entry_kind", StrA kind) ]
                   (map dataDecl t.datas ++ fns))
