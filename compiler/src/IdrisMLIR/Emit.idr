||| Full Core to the contract (08-idr-dialect.md): one module in
||| the custom syntax of the `idr`, `func`, `arith`, `math` and `ub`
||| dialects.
|||
||| A body is written by one fold over `Term`, a paramorphism: the algebra
||| turns each layer into an emitter, which, given the values of the
||| variables in scope and the type the context expects, appends the layer's
||| operations and returns its value. The alternatives Idris proved
||| impossible are left out, which is why the algebra sees each subterm as it
||| was. Control flow is regions: a match is `idr.match` or `idr.match_lit`,
||| and a lambda or `Delay` is a lifted function whose leading parameters are
||| its captures.
|||
||| Types are synthesized as they are written, bidirectionally: every
||| emitter returns its value's type (TTC drops the types of `let`s,
||| FE-TR-1), and a context that knows the type it expects passes it down, for
||| the one term whose type its parts do not give, a closure whose body never
||| returns.
module IdrisMLIR.Emit

import IdrisMLIR.Facts
import IdrisMLIR.Graph
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Loop breakers (OPT-PIPE-3)
------------------------------------------------------------------------------

||| A function of the emitted module: an instance, or a function lifted
||| from a lambda or `Delay`, by its label.
data Node = FnNode FnId | LamNode Label

Eq Node where
  FnNode a == FnNode b = a == b
  LamNode a == LamNode b = a == b
  _ == _ = False

Ord Node where
  compare (FnNode a) (FnNode b) = compare a b
  compare (FnNode _) (LamNode _) = LT
  compare (LamNode _) (FnNode _) = GT
  compare (LamNode a) (LamNode b) = compare a b

||| What a term refers to: the functions it calls or closes over at its own
||| level, and the functions lifted from it, each with its own references.
Refs : Type -> Type
Refs _ = (List Node, List (Node, List Node))

||| The references of several subterms.
mergeRefs : List (List Node, List (Node, List Node)) -> (List Node, List (Node, List Node))
mergeRefs rs = (concatMap fst rs, concatMap snd rs)

refs : {0 b : Type} -> TermF Refs b -> Refs b
refs (CallF _ fn as) = let (here, below) = mergeRefs as in (FnNode fn :: here, below)
refs (LamF _ lbl _ _ (here, below)) = ([LamNode lbl], (LamNode lbl, here) :: below)
refs (SuspendF _ lbl _ (here, below)) = ([LamNode lbl], (LamNode lbl, here) :: below)
refs (VarF _ _) = ([], [])
refs (LiteralF _ _) = ([], [])
refs (ErasedF _) = ([], [])
refs (PrimAppF _ _ as) = mergeRefs as
refs (EffectF _ _ as _) = mergeRefs as
refs (ConAppF _ _ as) = mergeRefs as
refs (LetF _ _ v b) = mergeRefs [v, b]
refs (CaseF _ _ alts d) = mergeRefs (map (\(MkAltF _ _ b) => b) alts ++ toList d)
refs (CaseLitF _ _ alts d) = mergeRefs (map snd alts ++ [d])
refs (AppF _ f x) = mergeRefs [f, x]
refs (ResumeF _ e) = e
refs (UnreachableF _) = ([], [])
refs (CrashF _ _) = ([], [])

||| OPT-PIPE-3: the loop breakers, as in GHC ("Secrets of the Glasgow
||| Haskell Compiler inliner", Peyton Jones and Marlow), on full Core's call
||| graph, where a function refers to what it calls and to the closures it
||| builds: enough functions that every cycle through two or more contains
||| one. In each cycle the breaker is the first function in program order
||| that is not from a library the registry breaks last (*Break last*), or
||| the first function if all are; then the rest of the cycle is cut the
||| same way. Program order is each instance, then the functions lifted from
||| it by label.
breakers : List TFn -> SortedSet Node
breakers fns =
  let perFn = map (\f => (f, cata refs f.body)) fns
      nodes = concatMap (\(f, (here, below)) => (FnNode f.id, here) :: sortBy (\a, b => compare (fst a) (fst b)) below) perFn
      edges = the (SortedMap Node (List Node)) (fromList nodes)
      library = the (SortedSet Node)
                  (fromList (concatMap (\(f, (_, below)) =>
                               if covers BreakLast f.loc.origin then FnNode f.id :: map fst below else [])
                             perFn))
      order = map fst nodes
  in SortedSet.fromList (within (\n => fromMaybe [] (lookup n edges)) library (length order) order)
  where
    within : (Node -> List Node) -> SortedSet Node -> Nat -> List Node -> List Node
    within next library Z _ = []
    within next library (S k) ns = concatMap cut (components next ns)
      where
        cut : List Node -> List Node
        cut [_] = []
        cut c = case find (not . (`contains` library)) c <|> head' c of
          Just b => b :: within next library k (delete b c)
          Nothing => []

------------------------------------------------------------------------------
-- The program's declarations
------------------------------------------------------------------------------

record Index where
  constructor MkIndex
  datas : SortedMap DataId Data
  cons : SortedMap ConId Con
  fns : SortedMap FnId TFn
  breakers : SortedSet Node

index : Source -> Index
index src =
  MkIndex (fromList (map (\d => (d.id, d)) src.datas))
          (fromList (concatMap (\d => map (\c => (c.id, c)) d.cons) src.datas))
          (fromList (map (\f => (f.id, f)) src.fns))
          (breakers src.fns)

------------------------------------------------------------------------------
-- The emission monad
------------------------------------------------------------------------------

||| The function being written: its symbol (which names the functions
||| lifted from it), its Idris name and whether Idris proved it terminating.
record Owner where
  constructor MkOwner
  symbol : String
  idrisName : Shown
  terminating : Bool

record ES where
  constructor MkES
  ||| The next SSA number of the function being written.
  next : Nat
  ||| The operations of the region being written.
  ops : SnocList Op
  ||| The functions lifted so far from the function being written.
  lifted : SnocList Op
  owner : Owner

E : Type -> Type
E = StateT ES (Either String)

||| DIAG-ICE-1: what `Emit` cannot write is a bug of the frontend.
internal : String -> E a
internal msg = lift (Left msg)

fresh : E String
fresh = do
  st <- get
  put ({ next $= S } st)
  pure ("%" ++ show st.next)

append : Op -> E ()
append o = modify { ops $= (:< o) }

||| The operations `act` appends, apart from the current region's.
collect : E a -> E (a, List Op)
collect act = do
  saved <- gets (.ops)
  modify { ops := [<] }
  x <- act
  inner <- gets (.ops)
  modify { ops := saved }
  pure (x, inner <>> [])

||| A value in scope: its SSA name, its type and the quantity it is bound
||| with.
record Val where
  constructor MkVal
  name : String
  type : Ty
  quantity : Quantity

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

||| The contract type of a Core type (IDR-TY-*).
mtype : Index -> Ty -> E MType
mtype ix (IntT t) = pure (I (width t))
mtype ix CharT = pure (I 32)
mtype ix DoubleT = pure F64
mtype ix StrT = pure Str
mtype ix BigT = pure Big
mtype ix WorldT = pure World
mtype ix ErasedT = pure Erased
mtype ix (DataT d) = case lookup d ix.datas of
  Just dt => pure (case dt.repr of
                     Sop => Data (mangle d.name)
                     Box => Boxed (mangle d.name))
  Nothing => internal ("unknown data " ++ show d)
mtype ix (FunT _ a r) = pure (Fn [!(mtype ix a)] [!(mtype ix r)])
mtype ix (LazyT r) = pure (Fn [] [!(mtype ix r)])

typeText : Index -> Ty -> E String
typeText ix t = showType <$> mtype ix t

||| IDR-FN-1: `"0"` exactly on an erased value.
quantityOf : Ty -> Quantity -> E Quantity
quantityOf ErasedT _ = pure Q0
quantityOf t Q0 = internal ("a quantity-0 binder of type " ++ show t)
quantityOf _ q = pure q

||| A typed parameter with its quantity: `%3: i64 {idr.quantity = "w"}`.
param : Index -> Val -> E String
param ix v = do
  q <- quantityOf v.type v.quantity
  pure (v.name ++ ": " ++ !(typeText ix v.type) ++ " {idr.quantity = " ++ quoted (show q) ++ "}")

------------------------------------------------------------------------------
-- Operations
------------------------------------------------------------------------------

||| An operation with one result, of the type given.
value : Loc -> Ty -> String -> E Val
value l t text = do
  r <- fresh
  append (Line (r ++ " = " ++ text) (At l))
  pure (MkVal r t QW)

||| An operation without results.
statement : Loc -> String -> E ()
statement l text = append (Line text (At l))

names : List Val -> String
names vs = joinBy ", " (map (.name) vs)

types : Index -> List Val -> E String
types ix vs = joinBy ", " <$> traverse (typeText ix . (.type)) vs

||| A literal (SEM-LIT-1): integers and doubles are `arith.constant`,
||| strings and bigs `idr.constant`.
literal : Loc -> Lit -> E Val
literal l (LInt t n) = value l (IntT t) ("arith.constant " ++ show (twos (width t) n) ++ " : i" ++ show (width t))
literal l (LChar c) = value l CharT ("arith.constant " ++ show c ++ " : i32")
literal l (LDouble d) = value l DoubleT ("arith.constant " ++ floatLiteral d ++ " : f64")
literal l (LStr s) = value l StrT ("idr.constant " ++ utf8 s ++ " : !idr.str")
literal l (LBig n) = value l BigT ("idr.constant #idr.big<" ++ quoted (show n) ++ "> : !idr.big")

erased : Loc -> E Val
erased l = do
  v <- value l ErasedT "idr.constant #idr.erased : !idr.erased"
  pure ({ quantity := Q0 } v)

||| The word before an integer operand that says how to read it.
signedness : IntTy -> String
signedness t = if signed t then "signed " else "unsigned "

||| The `arith.cmpi` predicate: `Char`s compare as code points.
cmpi : Cmp -> Bool -> String
cmpi CEq _ = "eq"
cmpi CLt s = if s then "slt" else "ult"
cmpi CLte s = if s then "sle" else "ule"
cmpi CGt s = if s then "sgt" else "ugt"
cmpi CGte s = if s then "sge" else "uge"

||| The `arith.cmpf` predicate: ordered, so false on NaN (SEM-DBL-2).
cmpf : Cmp -> String
cmpf CEq = "oeq"
cmpf CLt = "olt"
cmpf CLte = "ole"
cmpf CGt = "ogt"
cmpf CGte = "oge"

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

||| A comparison's `i1` as an `Int` (IDR-IN-3).
extend : Loc -> Val -> E Val
extend l c = value l (IntT IdrisInt) ("arith.extui " ++ c.name ++ " : i1 to i64")

||| The width and signedness of a fixed-width integer or `Char`.
intLike : Scalar -> Maybe (Nat, Bool)
intLike (SInt t) = Just (width t, signed t)
intLike SChar = Just (32, False)
intLike SDouble = Nothing

||| A primitive (IDR-IN-3), on operands in
||| Idris's order.
prim : Loc -> Prim -> List Val -> E Val
prim l (IntOp op t) [a, b] =
  let w = " : i" ++ show (width t)
      two = a.name ++ ", " ++ b.name
      arith = \n => value l (IntT t) (n ++ " " ++ two ++ w)
  in case op of
       Add => arith "arith.addi"
       Sub => arith "arith.subi"
       Mul => arith "arith.muli"
       And => arith "arith.andi"
       Or => arith "arith.ori"
       Xor => arith "arith.xori"
       Div => value l (IntT t) ("idr.div " ++ (if signed t then "signed " else "") ++ two ++ w)
       Mod => value l (IntT t) ("idr.mod " ++ (if signed t then "signed " else "") ++ two ++ w)
prim l (FloatOp op) [a, b] =
  let n = case op of
            FAdd => "arith.addf"
            FSub => "arith.subf"
            FMul => "arith.mulf"
            FDiv => "arith.divf"
  in value l DoubleT (n ++ " " ++ a.name ++ ", " ++ b.name ++ " : f64")
prim l Negate [a] = value l DoubleT ("arith.negf " ++ a.name ++ " : f64")
prim l (Math f) as = value l DoubleT (mathOp f ++ " " ++ names as ++ " : f64")
prim l (Compare c SDouble) [a, b] =
  extend l !(value l (IntT IdrisInt) ("arith.cmpf " ++ cmpf c ++ ", " ++ a.name ++ ", " ++ b.name ++ " : f64"))
prim l (Compare c s) [a, b] = case intLike s of
  Just (w, sgn) =>
    extend l !(value l (IntT IdrisInt)
                 ("arith.cmpi " ++ cmpi c sgn ++ ", " ++ a.name ++ ", " ++ b.name ++ " : i" ++ show w))
  Nothing => internal ("a comparison of " ++ show s)
-- SEM-INT-7, SEM-CHAR-3, SEM-DBL-4
prim l (Cast from to) [a] = case (from, to) of
  (SInt f, SChar) => value l CharT ("idr.to_char " ++ (if signed f then "signed " else "") ++ a.name ++ " : i" ++ show (width f))
  (SInt f, SDouble) =>
    value l DoubleT ((if signed f then "arith.sitofp " else "arith.uitofp ") ++ a.name ++ " : i" ++ show (width f) ++ " to f64")
  (SDouble, SInt t) => value l (IntT t) ("idr.to_int " ++ a.name ++ " : i" ++ show (width t))
  (SDouble, SDouble) => pure a
  (SChar, SChar) => pure a
  (f, t) => case (intLike f, intLike t) of
    (Just (fw, fs), Just (tw, _)) =>
      if fw == tw then pure ({ type := scalarTy t } a)
      else if fw > tw then value l (scalarTy t) ("arith.trunci " ++ a.name ++ " : i" ++ show fw ++ " to i" ++ show tw)
      else value l (scalarTy t) ((if fs then "arith.extsi " else "arith.extui ") ++ a.name ++
                                 " : i" ++ show fw ++ " to i" ++ show tw)
    _ => internal ("a cast from " ++ show f ++ " to " ++ show t)
prim l StrAppend [a, b] = value l StrT ("idr.str.append " ++ a.name ++ ", " ++ b.name)
prim l StrCons [c, s] = value l StrT ("idr.str.cons " ++ c.name ++ ", " ++ s.name)
prim l StrLength [s] = value l (IntT IdrisInt) ("idr.str.length " ++ s.name)
prim l StrHead [s] = value l CharT ("idr.str.head " ++ s.name)
prim l StrTail [s] = value l StrT ("idr.str.tail " ++ s.name)
prim l StrIndex [s, i] = value l CharT ("idr.str.index " ++ s.name ++ ", " ++ i.name)
prim l StrReverse [s] = value l StrT ("idr.str.reverse " ++ s.name)
-- Idris takes the start, the length, then the string.
prim l StrSubstr [start, len, s] =
  value l StrT ("idr.str.substr " ++ s.name ++ ", " ++ start.name ++ ", " ++ len.name)
prim l (StrCompare c) [a, b] =
  extend l !(value l (IntT IdrisInt) ("idr.str.cmp " ++ show c ++ " " ++ a.name ++ ", " ++ b.name))
prim l (ToStr (SInt t)) [x] = value l StrT ("idr.str.show " ++ signedness t ++ x.name ++ " : i" ++ show (width t))
prim l (ToStr SChar) [c] = value l StrT ("idr.str.from_char " ++ c.name)
prim l (ToStr SDouble) [x] = value l StrT ("idr.str.show " ++ x.name ++ " : f64")
prim l (FromStr (SInt t)) [s] = value l (IntT t) ("idr.str.to_int " ++ signedness t ++ s.name ++ " : i" ++ show (width t))
prim l (FromStr SDouble) [s] = value l DoubleT ("idr.str.to_double " ++ s.name)
prim l (BigArith op) [a, b] = value l BigT ("idr.big." ++ show op ++ " " ++ a.name ++ ", " ++ b.name)
prim l BigNegate [a] = value l BigT ("idr.big.neg " ++ a.name)
prim l (BigCompare c) [a, b] =
  extend l !(value l (IntT IdrisInt) ("idr.big.cmp " ++ show c ++ " " ++ a.name ++ ", " ++ b.name))
prim l (ToBig (SInt t)) [x] = value l BigT ("idr.big.from_int " ++ signedness t ++ x.name ++ " : i" ++ show (width t))
prim l (ToBig SChar) [c] = value l BigT ("idr.big.from_int unsigned " ++ c.name ++ " : i32")
prim l (ToBig SDouble) [d] = value l BigT ("idr.big.from_double " ++ d.name)
prim l (FromBig (SInt t)) [b] = value l (IntT t) ("idr.big.to_int " ++ b.name ++ " : i" ++ show (width t))
prim l (FromBig SDouble) [b] = value l DoubleT ("idr.big.to_double " ++ b.name)
-- SEM-CHAR-3: the code point if the integer is one, else 0; `idr.to_char`
-- decides for the integers an `i64` holds, and 0 stands for the rest.
prim l (FromBig SChar) [b] = do
  lo <- literal l (LBig 0)
  hi <- literal l (LBig 0x10FFFF)
  ge <- value l (IntT IdrisInt) ("idr.big.cmp gte " ++ b.name ++ ", " ++ lo.name)
  le <- value l (IntT IdrisInt) ("idr.big.cmp lte " ++ b.name ++ ", " ++ hi.name)
  inRange <- value l (IntT IdrisInt) ("arith.andi " ++ ge.name ++ ", " ++ le.name ++ " : i1")
  n <- value l (IntT IdrisInt) ("idr.big.to_int " ++ b.name ++ " : i64")
  outside <- literal l (LInt IdrisInt (-1))
  m <- value l (IntT IdrisInt) ("arith.select " ++ inRange.name ++ ", " ++ n.name ++ ", " ++ outside.name ++ " : i64")
  value l CharT ("idr.to_char signed " ++ m.name ++ " : i64")
prim l BigShow [b] = value l StrT ("idr.big.show " ++ b.name)
prim l BigRead [s] = value l BigT ("idr.big.from_str " ++ s.name)
prim l p vs = internal ("the primitive " ++ show p ++ " with " ++ show (length vs) ++ " operands")

||| A constructor application (`idr.con`); a box's allocates.
con : Index -> Loc -> Con -> List Val -> E Val
con ix l c vs = do
  let t = DataT c.id.dataId
  res <- typeText ix t
  value l t ("idr.con " ++ symbol (mangle c.id.dataId.name) ++ "::" ++ symbol (mangle c.id.name) ++
             "(" ++ names vs ++ ") : (" ++ !(types ix vs) ++ ") -> " ++ res)

||| The one constructor of a data instance.
only : Index -> DataId -> E Con
only ix d = case (.cons) <$> lookup d ix.datas of
  Just [c] => pure c
  _ => internal (show d ++ " does not have exactly one constructor")

||| An IO primitive (IDR-IO-1), and the `IORes` of its result and next
||| world.
io : Index -> Loc -> IOOp -> List Val -> DataId -> E Val
io ix l op vs res = do
  mk <- only ix res
  (x, w) <- case (op, vs) of
    (PutStr, [s, w0]) => withUnit mk !(value l WorldT ("idr.io.put_str " ++ s.name ++ ", " ++ w0.name))
    (PutChar, [c, w0]) => withUnit mk !(value l WorldT ("idr.io.put_char " ++ c.name ++ ", " ++ w0.name))
    (GetByte, [w0]) => do
      r <- fresh
      append (Line (r ++ ":2 = idr.io.get_byte " ++ w0.name) (At l))
      pure (MkVal (r ++ "#0") CharT QW, MkVal (r ++ "#1") WorldT Q1)
    _ => internal ("io." ++ show op ++ " with the wrong operands")
  con ix l mk [x, w]
  where
    ||| The unit value of an IO result, built after the operation.
    withUnit : Con -> Val -> E (Val, Val)
    withUnit mk w = case map (.type) mk.fields of
      [DataT u, _] => pure (!(con ix l !(only ix u) []), { quantity := Q1 } w)
      _ => internal (show res ++ " does not hold a unit value")

------------------------------------------------------------------------------
-- Bodies
------------------------------------------------------------------------------

||| What the fold makes of a term in scope `b`: given the values of its
||| variables and the type its context expects, if known, it appends the
||| term's operations and returns its value, or `Nothing` when the term
||| never returns (its region then ends in `ub.unreachable`).
Em : Type -> Type
Em b = (b -> Val) -> Maybe Ty -> E (Maybe Val)

||| The values of a binder's variables, over those outside.
bind : Vect k Val -> (b -> Val) -> Under k b -> Val
bind vs env (Bound i) = index i vs
bind vs env (Free x) = env x

||| Operands, left to right (SEM-EVAL-2), each checked against the type
||| its position expects; `Nothing` once one never returns.
operands : (b -> Val) -> List (Sub Em b) -> List Ty -> E (Maybe (List Val))
operands env [] _ = pure (Just [])
operands env (a :: as) ts = do
  Just v <- a.result env (head' ts)
    | Nothing => pure Nothing
  map (map (v ::)) (operands env as (drop 1 ts))

||| Is a term a branch Idris proved impossible? It is left out
||| (IDR-MATCH-2).
excluded : Sub Em b -> Bool
excluded s = case s.term of
  Unreachable _ => True
  _ => False

||| A region of a match: its header, its operations, and its value, which
||| it yields.
record Region where
  constructor MkRegion
  header : String
  result : Maybe Val
  ops : List Op

||| A match, from its regions: results when a region yields, and none,
||| followed by `ub.unreachable`, when no region returns.
match : Index -> Loc -> String -> List Region -> E (Maybe Val)
match ix l head regions =
  case map (.type) (head' (mapMaybe (.result) regions)) of
    Just t => do
      rt <- typeText ix t
      body <- traverse (close rt) regions
      r <- fresh
      append (Nest (r ++ " = " ++ head ++ " -> (" ++ rt ++ ") {") body "}" (Just (At l)))
      pure (Just (MkVal r t QW))
    Nothing => do
      body <- traverse (close "") regions
      append (Nest (head ++ " -> () {") body "}" (Just (At l)))
      statement l "ub.unreachable"
      pure Nothing
  where
    close : String -> Region -> E Op
    close rt reg = case reg.result of
      Just v => pure (Nest reg.header (reg.ops ++ [Line ("idr.yield " ++ v.name ++ " : " ++ !(typeText ix v.type)) (At l)]) "}" Nothing)
      Nothing => pure (Nest reg.header reg.ops "}" Nothing)

||| A literal as a key of `idr.match_lit`.
key : Lit -> String
key (LInt t n) = show (twos (width t) n)
key (LChar c) = show c
key (LStr s) = utf8 s
key (LBig n) = "#idr.big<" ++ quoted (show n) ++ ">"
key (LDouble d) = floatLiteral d

||| Starts a function: its own SSA numbers and operations, the owner's
||| lifted functions kept.
inFunction : E a -> E (a, List Op)
inFunction act = do
  st <- get
  put ({ next := 0, ops := [<] } st)
  x <- act
  inner <- gets (.ops)
  modify { next := st.next, ops := st.ops }
  pure (x, inner <>> [])

||| The attributes of a function: `idr.total` when Idris proved it
||| terminating, `no_inline` on a loop breaker (IDR-FN-1).
attributes : Bool -> Bool -> String
attributes terminates breaker =
  case the (List String) ((if terminates then ["idr.total"] else []) ++ (if breaker then ["no_inline"] else [])) of
    [] => ""
    as => " attributes {" ++ joinBy ", " as ++ "}"

||| The end of a function's body, of result type `rt`: its value, returned.
||| A body that never returns ends in `ub.unreachable` inside its regions
||| only; at the top level a poison value is returned in its place
||| (IDR-CRASH-1), because the pinned inliner cannot inline a body that ends
||| in `ub.unreachable` (PINS.md: inline-unreachable).
epilogue : Loc -> String -> Maybe Val -> List Op -> List Op
epilogue l rt (Just v) ops = ops ++ [Line ("func.return " ++ v.name ++ " : " ++ rt) (At l)]
epilogue l rt Nothing ops =
  reverse (dropEnd (reverse ops)) ++
    [ Line ("%never = ub.poison : " ++ rt) (At l)
    , Line ("func.return %never : " ++ rt) (At l) ]
  where
    dropEnd : List Op -> List Op
    dropEnd (Line "ub.unreachable" _ :: rest) = rest
    dropEnd rest = rest

||| A lifted function: private, its captures first, then its parameters.
||| Its body is the closure's, and it is what the closure calls.
lifted : Index -> Loc -> Label -> Vect k Val -> Vect m Val -> Maybe Ty ->
         (Vect k Val -> Vect m Val -> E (Maybe Val)) -> E (String, Ty)
lifted ix l lbl caps ps expected body = do
  own <- gets (.owner)
  let sym = own.symbol ++ "$lam" ++ show lbl.index
  ((params, res), ops) <- inFunction $ do
    cs <- traverse renamed caps
    ps' <- traverse renamed ps
    res <- body cs ps'
    pure (toList cs ++ toList ps', res)
  t <- case map (.type) res <|> expected of
         Just t => pure t
         Nothing => internal ("the result type of " ++ show lbl ++ ", whose body never returns")
  rt <- typeText ix t
  header <- traverse (param ix) params
  let fn = Nest ("func.func private " ++ symbol sym ++ "(" ++ joinBy ", " header ++ ") -> " ++ rt ++
                 attributes own.terminating (contains (LamNode lbl) ix.breakers) ++ " {")
                (epilogue l rt res ops) "}" (Just (Named own.idrisName l))
  modify { lifted $= (:< fn) }
  pure (sym, t)
  where
    renamed : Val -> E Val
    renamed v = (\n => { name := n } v) <$> fresh

||| The algebra: one layer of `Term` to its emitter.
alg : {0 b : Type} -> Index -> TermF (Sub Em) b -> Em b
alg ix (VarF _ x) env _ = pure (Just (env x))
alg ix (LiteralF l x) env _ = Just <$> literal l x
alg ix (ErasedF l) env _ = Just <$> erased l
alg ix (PrimAppF l p as) env _ = do
  Just vs <- operands env as (primArgs p)
    | Nothing => pure Nothing
  Just <$> prim l p vs
alg ix (EffectF l op as res) env _ = do
  Just vs <- operands env as (ioArgs op ++ [WorldT])
    | Nothing => pure Nothing
  Just <$> io ix l op vs res
alg ix (CallF l fn as) env _ = do
  Just f <- pure (lookup fn ix.fns)
    | Nothing => internal ("a call of " ++ show fn ++ ", which is not in the program")
  Just vs <- operands env as (map (.type) (toList f.params))
    | Nothing => pure Nothing
  rt <- typeText ix f.result
  Just <$> value l f.result ("func.call " ++ symbol (mangle fn.name) ++ "(" ++ names vs ++ ") : (" ++
                             !(types ix vs) ++ ") -> " ++ rt)
alg ix (ConAppF l c as) env _ = do
  Just k <- pure (lookup c ix.cons)
    | Nothing => internal ("the constructor " ++ show c ++ " of " ++ show c.dataId ++ ", which is not declared")
  Just vs <- operands env as (map (.type) k.fields)
    | Nothing => pure Nothing
  Just <$> con ix l k vs
-- IDR-MATCH-4: a `let` binds an SSA value; its type is its value's.
alg ix (LetF _ q v b) env expected = do
  Just x <- v.result env Nothing
    | Nothing => pure Nothing
  b.result (bind [{ quantity := q } x] env) expected
alg ix (CaseF l x alts def) env expected = do
  let scrut = env x
  DataT d <- pure scrut.type
    | t => internal ("a match on a value of type " ++ show t)
  Just decl <- pure (lookup d ix.datas)
    | Nothing => internal ("a match on " ++ show d ++ ", which is not declared")
  st <- typeText ix scrut.type
  cases <- traverse alternative (filter (\(MkAltF _ _ b) => not (excluded b)) alts)
  dflt <- case def of
    Just e => if excluded e then pure [] else do
      (res, ops) <- collect (e.result env expected)
      pure [MkRegion "default {" res ops]
    Nothing => pure []
  case cases ++ dflt of
    [] => do
      statement l "ub.unreachable"
      pure Nothing
    regions => match ix l ("idr.match " ++ scrut.name ++ " : " ++ st) regions
  where
    alternative : AltF (Sub Em) b -> E Region
    alternative (MkAltF c fs body) = do
      vals <- traverse (\f => (\n => MkVal n f.type f.quantity) <$> fresh) fs
      args <- traverse (\v => (\t => v.name ++ ": " ++ t) <$> typeText ix v.type) (toList vals)
      (res, ops) <- collect (body.result (bind vals env) expected)
      pure (MkRegion ("case " ++ symbol (mangle c.name) ++ "(" ++ joinBy ", " args ++ ") {") res ops)
alg ix (CaseLitF l x alts def) env expected = do
  let scrut = env x
  let live = filter (not . excluded . snd) alts
  -- A default Idris proved impossible is left out: the last possible
  -- alternative stands for it.
  let (cases, final) = if excluded def
                          then case reverse live of
                                 ((_, e) :: rest) => (reverse rest, Just e)
                                 [] => ([], Nothing)
                          else (live, Just def)
  case (cases, final) of
    (_, Nothing) => do
      statement l "ub.unreachable"
      pure Nothing
    ([], Just e) => e.result env expected
    (_, Just e) => do
      st <- typeText ix scrut.type
      regions <- traverse (\(k, c) => do
                             (res, ops) <- collect (c.result env expected)
                             pure (MkRegion ("case " ++ key k ++ " {") res ops)) cases
      (res, ops) <- collect (e.result env expected)
      match ix l ("idr.match_lit " ++ scrut.name ++ " : " ++ st) (regions ++ [MkRegion "default {" res ops])
alg ix (LamF l lbl caps b body) env expected = do
  let capVals = map env caps
  let result = case expected of
                 Just (FunT _ _ r) => Just r
                 _ => Nothing
  (sym, rt) <- lifted ix l lbl capVals [MkVal "" b.type b.quantity] result
                 (\cs, [p] => body.result (bind [p] (\i => index i cs)) result)
  let t = FunT b.quantity b.type rt
  Just <$> closure sym (toList capVals) t
  where
    closure : String -> List Val -> Ty -> E Val
    closure sym cs t = value l t ("idr.closure " ++ symbol sym ++ "(" ++ names cs ++ ") : (" ++
                                  !(types ix cs) ++ ") -> " ++ !(typeText ix t))
alg ix (AppF l f x) env expected = do
  Just fv <- f.result env Nothing
    | Nothing => pure Nothing
  FunT _ a r <- pure fv.type
    | t => internal ("an application of a value of type " ++ show t)
  Just xv <- x.result env (Just a)
    | Nothing => pure Nothing
  Just <$> value l r ("idr.apply " ++ fv.name ++ "(" ++ xv.name ++ ") : " ++ !(typeText ix fv.type))
alg ix (SuspendF l lbl caps body) env expected = do
  let capVals = map env caps
  let result = case expected of
                 Just (LazyT r) => Just r
                 _ => Nothing
  (sym, rt) <- lifted ix l lbl capVals [] result (\cs, _ => body.result (\i => index i cs) result)
  let t = LazyT rt
  Just <$> value l t ("idr.closure " ++ symbol sym ++ "(" ++ names (toList capVals) ++ ") : (" ++
                      !(types ix (toList capVals)) ++ ") -> " ++ !(typeText ix t))
alg ix (ResumeF l e) env expected = do
  Just ev <- e.result env Nothing
    | Nothing => pure Nothing
  LazyT r <- pure ev.type
    | t => internal ("a force of a value of type " ++ show t)
  Just <$> value l r ("idr.apply " ++ ev.name ++ "() : " ++ !(typeText ix ev.type))
alg ix (UnreachableF l) env _ = do
  statement l "ub.unreachable"
  pure Nothing
-- SEM-CRASH-2, IDR-CRASH-1
alg ix (CrashF l msg) env _ = do
  statement l ("idr.crash " ++ utf8 msg)
  statement l "ub.unreachable"
  pure Nothing

------------------------------------------------------------------------------
-- Declarations
------------------------------------------------------------------------------

||| IDR-DATA-5: a declaration is located by its Idris name.
dataDecl : Index -> Data -> E Op
dataDecl ix d = do
  ctors <- traverse ctor d.cons
  pure (Nest ("idr.data " ++ symbol (mangle d.id.name) ++ (case d.repr of
                                                              Sop => ""
                                                              Box => " box") ++ " {")
             ctors "}" (Just (Named d.idrisName d.loc)))
  where
    ctor : Con -> E Op
    ctor c = do
      ts <- traverse (typeText ix . (.type)) c.fields
      qs <- traverse (\f => quantityOf f.type f.quantity) c.fields
      pure (Line ("idr.ctor " ++ symbol (mangle c.id.name) ++ " tag " ++ show c.tag ++
                  " (" ++ joinBy ", " ts ++ ") {quantities = [" ++ joinBy ", " (map (quoted . show) qs) ++ "]}")
                 (Named c.idrisName c.loc))

||| A function, and the functions lifted from it. Only the root is public.
function : Index -> FnId -> TFn -> E (List Op)
function ix root f = do
  let sym = mangle f.id.name
  modify { owner := MkOwner sym f.idrisName f.facts.terminating.holds, lifted := [<] }
  ((params, res), ops) <- inFunction $ do
    params <- traverse (\b => (\n => MkVal n b.type b.quantity) <$> fresh) f.params
    res <- para alg' f.body (\i => index i params) (Just f.result)
    pure (params, res)
  rt <- typeText ix f.result
  header <- traverse (param ix) (toList params)
  let visibility = if f.id == root then "" else "private "
  let fn = Nest ("func.func " ++ visibility ++ symbol sym ++ "(" ++ joinBy ", " header ++ ") -> " ++ rt ++
                 attributes f.facts.terminating.holds (contains (FnNode f.id) ix.breakers) ++ " {")
                (epilogue f.loc rt res ops) "}" (Just (Named f.idrisName f.loc))
  inner <- gets (.lifted)
  pure (fn :: (inner <>> []))
  where
    alg' : {0 b : Type} -> TermF (Sub Em) b -> Em b
    alg' = alg ix

||| The contract text of a program (docs/architecture/08-idr-dialect.md).
export
emit : Source -> Either String String
emit src = do
  let ix = index src
  let start = MkES 0 [<] [<] (MkOwner "" (shown "") False)
  (_, ops) <- runStateT start $ do
    datas <- traverse (dataDecl ix) src.datas
    fns <- traverse (function ix src.root) src.fns
    pure (datas ++ concat fns)
  pure (showModule "idr.program" ops)
