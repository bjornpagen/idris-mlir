||| The operations of the contract that one layer of a term becomes:
||| literals, primitives, constructor applications and IO primitives.
module IdrisMLIR.Emit.Operations

import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.SortedMap
import Data.String

%default total

||| An operation with one result, of the type given.
export
value : Loc -> Ty -> String -> E Val
value l t text = do
  r <- fresh
  append (Line (r ++ " = " ++ text) (At l))
  pure (val r t Plain)

||| An operation without results.
export
statement : Loc -> String -> E ()
statement l text = append (Line text (At l))

export
names : List Val -> String
names vs = joinBy ", " (map (.name) vs)

export
types : Index -> List Val -> E String
types ix vs = joinBy ", " <$> traverse (valText ix) vs

||| A value where the contract expects it held as `mode`. A linear value
||| where a plain one is expected is used (`idr.lin.use`), its one use; a
||| plain value in a linear position enters it (`idr.lin.enter`), as Idris
||| lets any value fill a binder of quantity 1.
export
coerce : Index -> Loc -> Mode -> Val -> E Val
coerce ix l mode v = case (v.mode, mode) of
  (Linear, Plain) => value l v.type ("idr.lin.use " ++ v.name ++ " : " ++ !(valText ix v))
  (Plain, Linear) => do
    let entered = { mode := Linear } v
    r <- fresh
    append (Line (r ++ " = idr.lin.enter " ++ v.name ++ " : " ++ !(valText ix entered)) (At l))
    pure ({ name := r } entered)
  _ => pure v

||| A literal: integers and doubles are `arith.constant`,
||| strings and bigs `idr.constant`.
export
literal : Loc -> Lit -> E Val
literal l (LInt t n) = value l (IntT t) ("arith.constant " ++ show (twos (width t) n) ++ " : i" ++ show (width t))
literal l (LChar c) = value l CharT ("arith.constant " ++ show c ++ " : i32")
literal l (LDouble d) = value l DoubleT ("arith.constant " ++ floatLiteral d ++ " : f64")
literal l (LStr s) = value l StrT ("idr.constant " ++ utf8 s ++ " : !idr.str")
literal l (LBig n) = value l BigT ("idr.constant #idr.big<" ++ quoted (show n) ++ "> : !idr.big")
literal l (LNat n) = value l NatT ("idr.constant #idr.big<" ++ quoted (show n) ++ "> : !idr.nat")

export
erased : Loc -> E Val
erased l = do
  value l ErasedT "idr.constant #idr.erased : !idr.erased"

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

||| The `arith.cmpf` predicate: ordered, so false on NaN.
cmpf : Cmp -> String
cmpf CEq = "oeq"
cmpf CLt = "olt"
cmpf CLte = "ole"
cmpf CGt = "ogt"
cmpf CGte = "oge"

||| The `math` op of a C library function or exact operation.
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

||| A comparison's `i1` as an `Int`.
extend : Loc -> Val -> E Val
extend l c = value l (IntT IdrisInt) ("arith.extui " ++ c.name ++ " : i1 to i64")

||| The width and signedness of a fixed-width integer or `Char`.
intLike : Scalar -> Maybe (Nat, Bool)
intLike (SInt t) = Just (width t, signed t)
intLike SChar = Just (32, False)
intLike SDouble = Nothing

||| A primitive, on operands in Idris's order.
export
prim : Index -> Loc -> Prim -> List Val -> E Val
prim ix l (IntOp op t) [a, b] =
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
prim ix l (FloatOp op) [a, b] =
  let n = case op of
            FAdd => "arith.addf"
            FSub => "arith.subf"
            FMul => "arith.mulf"
            FDiv => "arith.divf"
  in value l DoubleT (n ++ " " ++ a.name ++ ", " ++ b.name ++ " : f64")
prim ix l Negate [a] = value l DoubleT ("arith.negf " ++ a.name ++ " : f64")
prim ix l (Math f) as = value l DoubleT (mathOp f ++ " " ++ names as ++ " : f64")
prim ix l (Compare c SDouble) [a, b] =
  extend l !(value l (IntT IdrisInt) ("arith.cmpf " ++ cmpf c ++ ", " ++ a.name ++ ", " ++ b.name ++ " : f64"))
prim ix l (Compare c s) [a, b] = case intLike s of
  Just (w, sgn) =>
    extend l !(value l (IntT IdrisInt)
                 ("arith.cmpi " ++ cmpi c sgn ++ ", " ++ a.name ++ ", " ++ b.name ++ " : i" ++ show w))
  Nothing => internal ("a comparison of " ++ show s)
prim ix l (Cast from to) [a] = case (from, to) of
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
prim ix l StrAppend [a, b] = value l StrT ("idr.str.append " ++ a.name ++ ", " ++ b.name)
prim ix l StrCons [c, s] = value l StrT ("idr.str.cons " ++ c.name ++ ", " ++ s.name)
prim ix l StrLength [s] = value l (IntT IdrisInt) ("idr.str.length " ++ s.name)
prim ix l StrHead [s] = value l CharT ("idr.str.head " ++ s.name)
prim ix l StrTail [s] = value l StrT ("idr.str.tail " ++ s.name)
prim ix l StrIndex [s, i] = value l CharT ("idr.str.index " ++ s.name ++ ", " ++ i.name)
prim ix l StrReverse [s] = value l StrT ("idr.str.reverse " ++ s.name)
-- Idris takes the start, the length, then the string.
prim ix l StrSubstr [start, len, s] =
  value l StrT ("idr.str.substr " ++ s.name ++ ", " ++ start.name ++ ", " ++ len.name)
prim ix l (StrCompare c) [a, b] =
  extend l !(value l (IntT IdrisInt) ("idr.str.cmp " ++ show c ++ " " ++ a.name ++ ", " ++ b.name))
prim ix l (ToStr (SInt t)) [x] = value l StrT ("idr.str.show " ++ signedness t ++ x.name ++ " : i" ++ show (width t))
prim ix l (ToStr SChar) [c] = value l StrT ("idr.str.from_char " ++ c.name)
prim ix l (ToStr SDouble) [x] = value l StrT ("idr.str.show " ++ x.name ++ " : f64")
prim ix l (FromStr (SInt t)) [s] = value l (IntT t) ("idr.str.to_int " ++ signedness t ++ s.name ++ " : i" ++ show (width t))
prim ix l (FromStr SDouble) [s] = value l DoubleT ("idr.str.to_double " ++ s.name)
prim ix l (BigArith op) [a, b] = value l BigT ("idr.big." ++ show op ++ " " ++ a.name ++ ", " ++ b.name)
prim ix l BigNegate [a] = value l BigT ("idr.big.neg " ++ a.name)
prim ix l (BigCompare c) [a, b] =
  extend l !(value l (IntT IdrisInt) ("idr.big.cmp " ++ show c ++ " " ++ a.name ++ ", " ++ b.name))
prim ix l (ToBig (SInt t)) [x] = value l BigT ("idr.big.from_int " ++ signedness t ++ x.name ++ " : i" ++ show (width t))
prim ix l (ToBig SChar) [c] = value l BigT ("idr.big.from_int unsigned " ++ c.name ++ " : i32")
prim ix l (ToBig SDouble) [d] = value l BigT ("idr.big.from_double " ++ d.name)
prim ix l (FromBig (SInt t)) [b] = value l (IntT t) ("idr.big.to_int " ++ b.name ++ " : i" ++ show (width t))
prim ix l (FromBig SDouble) [b] = value l DoubleT ("idr.big.to_double " ++ b.name)
-- The code point if the integer is one, else 0; `idr.to_char`
-- decides for the integers an `i64` holds, and 0 stands for the rest.
prim ix l (FromBig SChar) [b] = do
  lo <- literal l (LBig 0)
  hi <- literal l (LBig 0x10FFFF)
  ge <- value l (IntT IdrisInt) ("idr.big.cmp gte " ++ b.name ++ ", " ++ lo.name)
  le <- value l (IntT IdrisInt) ("idr.big.cmp lte " ++ b.name ++ ", " ++ hi.name)
  inRange <- value l (IntT IdrisInt) ("arith.andi " ++ ge.name ++ ", " ++ le.name ++ " : i1")
  n <- value l (IntT IdrisInt) ("idr.big.to_int " ++ b.name ++ " : i64")
  outside <- literal l (LInt IdrisInt (-1))
  m <- value l (IntT IdrisInt) ("arith.select " ++ inRange.name ++ ", " ++ n.name ++ ", " ++ outside.name ++ " : i64")
  value l CharT ("idr.to_char signed " ++ m.name ++ " : i64")
prim ix l BigShow [b] = value l StrT ("idr.big.show " ++ b.name)
prim ix l BigRead [s] = value l BigT ("idr.big.from_str " ++ s.name)
prim ix l NatAdd [a, b] = value l NatT ("idr.big.add " ++ a.name ++ ", " ++ b.name ++ " : !idr.nat")
prim ix l NatMul [a, b] = value l NatT ("idr.big.mul " ++ a.name ++ ", " ++ b.name ++ " : !idr.nat")
prim ix l (NatCompare c) [a, b] =
  extend l !(value l (IntT IdrisInt) ("idr.big.cmp " ++ show c ++ " " ++ a.name ++ ", " ++ b.name ++ " : !idr.nat"))
prim ix l NatToBig [n] = value l BigT ("idr.nat.to_big " ++ n.name)
prim ix l NatFromBig [b] = value l NatT ("idr.nat.from_big " ++ b.name)
-- The length of an array is its memref's dimension, an index, as an `Int`.
prim ix l (ArrayLength e) [a] = do
  at <- typeText ix (ArrayT e)
  zero <- fresh
  append (Line (zero ++ " = arith.constant 0 : index") (At l))
  n <- fresh
  append (Line (n ++ " = memref.dim " ++ a.name ++ ", " ++ zero ++ " : " ++ at) (At l))
  value l (IntT IdrisInt) ("arith.index_cast " ++ n ++ " : index to i64")
prim ix l p vs = internal ("the primitive " ++ show p ++ " with " ++ show (length vs) ++ " operands")

||| A constructor application (`idr.con`); a box's allocates.
export
con : Index -> Loc -> Con -> List Val -> E Val
con ix l c vs0 = do
  let t = DataT c.id.dataId
  vs <- traverse (\(f, v) => coerce ix l (binderMode f) v) (zip c.fields vs0)
  res <- typeText ix t
  value l t ("idr.con " ++ symbol (mangle c.id.dataId.name) ++ "::" ++ symbol (mangle c.id.name) ++
             "(" ++ names vs ++ ") : (" ++ !(types ix vs) ++ ") -> " ++ res)

mutual
  ||| The value a variable names: itself, or the constructor a match took
  ||| apart, built again from its fields as the region holds them
  ||| (`Val.rebuild`); in the owned stage the cell it came from is reused.
  export
  force : Index -> Loc -> Val -> E Val
  force ix l (MkVal n t m Nothing) = pure (MkVal n t m Nothing)
  force ix l (MkVal n t m (Just (c, fs))) = do
    Just k <- pure (lookup c ix.cons)
      | Nothing => internal ("the constructor " ++ show c ++ ", which is not declared")
    con ix l k !(forceAll ix l fs)

  forceAll : Index -> Loc -> List Val -> E (List Val)
  forceAll ix l [] = pure []
  forceAll ix l (v :: vs) = (::) <$> force ix l v <*> forceAll ix l vs

||| The one constructor of a data instance.
only : Index -> DataId -> E Con
only ix d = case (.cons) <$> lookup d ix.datas of
  Just [c] => pure c
  _ => internal (show d ++ " does not have exactly one constructor")

||| A buffer's element.
byte : Ty
byte = IntT UInt8

||| An IO primitive, and the `IORes` of its result and next
||| world.
export
io : Index -> Loc -> IOOp -> List Val -> DataId -> E Val
io ix l op vs res = do
  mk <- only ix res
  (x, w) <- case (op, vs) of
    (PutStr, [s, w0]) => withUnit mk !(value l WorldT ("idr.io.put_str " ++ s.name ++ ", " ++ w0.name))
    (PutChar, [c, w0]) => withUnit mk !(value l WorldT ("idr.io.put_char " ++ c.name ++ ", " ++ w0.name))
    (GetByte, [w0]) => do
      r <- fresh
      append (Line (r ++ ":2 = idr.io.get_byte " ++ w0.name) (At l))
      pure (val (r ++ "#0") CharT Plain, val (r ++ "#1") WorldT Plain)
    (GetLine, [w0]) => do
      r <- fresh
      append (Line (r ++ ":2 = idr.io.get_line " ++ w0.name) (At l))
      pure (val (r ++ "#0") StrT Plain, val (r ++ "#1") WorldT Plain)
    (Array NewArray e, [n, x, w0]) => do
      r <- fresh
      et <- typeText ix e
      at <- typeText ix (ArrayT e)
      append (Line (r ++ ":2 = idr.array.new " ++ n.name ++ ", " ++ x.name ++ ", " ++ w0.name ++
                    " : " ++ et ++ " -> " ++ at) (At l))
      pure (val (r ++ "#0") (ArrayT e) Plain, val (r ++ "#1") WorldT Plain)
    (Array GetArray e, [a, i, w0]) => do
      r <- fresh
      et <- typeText ix e
      at <- typeText ix (ArrayT e)
      append (Line (r ++ ":2 = idr.array.get " ++ a.name ++ "[" ++ i.name ++ "], " ++ w0.name ++
                    " : " ++ at ++ " -> " ++ et) (At l))
      pure (val (r ++ "#0") e Plain, val (r ++ "#1") WorldT Plain)
    (Array SetArray e, [a, i, x, w0]) => do
      et <- typeText ix e
      at <- typeText ix (ArrayT e)
      withUnit mk !(value l WorldT ("idr.array.set " ++ a.name ++ "[" ++ i.name ++ "], " ++ x.name ++
                                    ", " ++ w0.name ++ " : " ++ at ++ ", " ++ et))
    -- A buffer is an array of bytes: a new one is zero bytes, a byte read
    -- as an Int is widened, an Int written as a byte must be one.
    (BufferNew, [n, w0]) => do
      z <- value l byte "arith.constant 0 : i8"
      r <- fresh
      append (Line (r ++ ":2 = idr.array.new " ++ n.name ++ ", " ++ z.name ++ ", " ++ w0.name ++
                    " : i8 -> " ++ !(typeText ix (ArrayT byte))) (At l))
      pure (val (r ++ "#0") (ArrayT byte) Plain, val (r ++ "#1") WorldT Plain)
    (BufferGet, [a, i, w0]) => do
      r <- fresh
      append (Line (r ++ ":2 = idr.array.get " ++ a.name ++ "[" ++ i.name ++ "], " ++ w0.name ++
                    " : " ++ !(typeText ix (ArrayT byte)) ++ " -> i8") (At l))
      x <- value l (IntT IdrisInt) ("arith.extui " ++ r ++ "#0 : i8 to i64")
      pure (x, val (r ++ "#1") WorldT Plain)
    (BufferSet, [a, i, x, w0]) => do
      b <- value l byte ("idr.to_byte " ++ x.name)
      withUnit mk !(value l WorldT ("idr.array.set " ++ a.name ++ "[" ++ i.name ++ "], " ++ b.name ++
                                    ", " ++ w0.name ++ " : " ++ !(typeText ix (ArrayT byte)) ++ ", i8"))
    -- Bytes between a buffer and a standard stream's handle.
    (WriteBytes, [h, a, o, n, w0]) => bytes "idr.io.write_bytes" h a o n w0
    (ReadBytes, [h, a, o, n, w0]) => bytes "idr.io.read_bytes" h a o n w0
    (Eof, [h, w0]) => do
      r <- fresh
      append (Line (r ++ ":2 = idr.io.eof " ++ h.name ++ ", " ++ w0.name) (At l))
      pure (val (r ++ "#0") (IntT IdrisInt) Plain, val (r ++ "#1") WorldT Plain)
    _ => internal ("io." ++ show op ++ " with the wrong operands")
  con ix l mk [x, w]
  where
    bytes : String -> Val -> Val -> Val -> Val -> Val -> E (Val, Val)
    bytes opName h a o n w0 = do
      r <- fresh
      append (Line (r ++ ":2 = " ++ opName ++ " " ++ h.name ++ ", " ++ a.name ++ "[" ++ o.name ++ ", " ++
                    n.name ++ "], " ++ w0.name ++ " : " ++ !(typeText ix (ArrayT byte))) (At l))
      pure (val (r ++ "#0") (IntT IdrisInt) Plain, val (r ++ "#1") WorldT Plain)

    ||| The unit value of an IO result, built after the operation.
    withUnit : Con -> Val -> E (Val, Val)
    withUnit mk w = case map typeOf mk.fields of
      [DataT u, _] => pure (!(con ix l !(only ix u) []), w)
      _ => internal (show res ++ " does not hold a unit value")
