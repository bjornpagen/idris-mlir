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
  pure (MkVal r t Plain)

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
-- The code point if the integer is one, else 0; `idr.to_char`
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
export
con : Index -> Loc -> Con -> List Val -> E Val
con ix l c vs0 = do
  let t = DataT c.id.dataId
  vs <- traverse (\(f, v) => coerce ix l (binderMode f) v) (zip c.fields vs0)
  res <- typeText ix t
  value l t ("idr.con " ++ symbol (mangle c.id.dataId.name) ++ "::" ++ symbol (mangle c.id.name) ++
             "(" ++ names vs ++ ") : (" ++ !(types ix vs) ++ ") -> " ++ res)

||| The one constructor of a data instance.
only : Index -> DataId -> E Con
only ix d = case (.cons) <$> lookup d ix.datas of
  Just [c] => pure c
  _ => internal (show d ++ " does not have exactly one constructor")

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
      pure (MkVal (r ++ "#0") CharT Plain, MkVal (r ++ "#1") WorldT Plain)
    _ => internal ("io." ++ show op ++ " with the wrong operands")
  con ix l mk [x, w]
  where
    ||| The unit value of an IO result, built after the operation.
    withUnit : Con -> Val -> E (Val, Val)
    withUnit mk w = case map typeOf mk.fields of
      [DataT u, _] => pure (!(con ix l !(only ix u) []), w)
      _ => internal (show res ++ " does not hold a unit value")
