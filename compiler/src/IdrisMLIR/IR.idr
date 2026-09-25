||| The compiler's own typed IR. Independent of Idris compiler internals.
|||
||| Version 0 covers first-order functions over fixed-width integers. Binder
||| quantities are kept until the erasure pass, so erased does not silently
||| mean absent.
module IdrisMLIR.IR

import Data.List
import Data.String

%default total

public export
data Quantity = Q0 | Q1 | QW

public export
Eq Quantity where
  Q0 == Q0 = True
  Q1 == Q1 = True
  QW == QW = True
  _ == _ = False

public export
Show Quantity where
  show Q0 = "0"
  show Q1 = "1"
  show QW = "w"

||| Fixed-width integers: `IdrisInt` is Idris `Int` (64-bit, signed), `SIntN` is
||| `IntN`, and `UIntN` is `BitsN`.
public export
data IntTy : Type where
  IdrisInt, SInt8, SInt16, SInt32, SInt64, UInt8, UInt16, UInt32, UInt64 : IntTy

public export
Show IntTy where
  show IdrisInt = "Int"
  show SInt8 = "Int8"
  show SInt16 = "Int16"
  show SInt32 = "Int32"
  show SInt64 = "Int64"
  show UInt8 = "Bits8"
  show UInt16 = "Bits16"
  show UInt32 = "Bits32"
  show UInt64 = "Bits64"

public export
Eq IntTy where
  a == b = show a == show b

public export
width : IntTy -> Nat
width IdrisInt = 64
width SInt8 = 8
width SInt16 = 16
width SInt32 = 32
width SInt64 = 64
width UInt8 = 8
width UInt16 = 16
width UInt32 = 32
width UInt64 = 64

public export
signed : IntTy -> Bool
signed UInt8 = False
signed UInt16 = False
signed UInt32 = False
signed UInt64 = False
signed _ = True

||| `Irrelevant` types are only valid for quantity-0 binders.
public export
data Ty = IntT IntTy | Irrelevant

public export
Show Ty where
  show (IntT t) = show t
  show Irrelevant = "_"

||| Comparisons return `Int` 1 or 0, as Idris primitives do.
public export
data PrimOp = Add | Sub | Mul | Lt | Lte | Eq | Gte | Gt

public export
Show PrimOp where
  show Add = "add"
  show Sub = "sub"
  show Mul = "mul"
  show Lt = "lt"
  show Lte = "lte"
  show Eq = "eq"
  show Gte = "gte"
  show Gt = "gt"

public export
isComparison : PrimOp -> Bool
isComparison Add = False
isComparison Sub = False
isComparison Mul = False
isComparison _ = True

||| Variables are unique numbers within a function.
public export
data Expr : Type where
  Var : Nat -> Expr
  Lit : IntTy -> Integer -> Expr
  Prim : PrimOp -> IntTy -> Expr -> Expr -> Expr
  Cast : (from : IntTy) -> (to : IntTy) -> Expr -> Expr
  Call : (fn : String) -> List Expr -> Expr
  Let : Nat -> Ty -> Expr -> Expr -> Expr
  ||| Match an integer against literals, with a required default.
  Switch : IntTy -> Expr -> List (Integer, Expr) -> Expr -> Expr
  ||| A type or other compile-time-only argument.
  CompileTime : Expr

public export
record Param where
  constructor MkParam
  var : Nat
  quantity : Quantity
  type : Ty

public export
record Fn where
  constructor MkFn
  name : String
  params : List Param
  result : IntTy
  body : Expr

public export
record Program where
  constructor MkProgram
  functions : List Fn
  ||| The Idris `main : Int`, if any; it becomes the process exit status.
  entry : Maybe String

covering
showExpr : Expr -> String
showExpr (Var v) = "%" ++ show v
showExpr (Lit t n) = show n ++ ":" ++ show t
showExpr (Prim op t a b) = "(" ++ show op ++ ":" ++ show t ++ " " ++ showExpr a ++ " " ++ showExpr b ++ ")"
showExpr (Cast from to e) = "(cast " ++ show from ++ "->" ++ show to ++ " " ++ showExpr e ++ ")"
showExpr (Call fn args) = "(" ++ unwords (fn :: map showExpr args) ++ ")"
showExpr (Let v t e body) = "(let %" ++ show v ++ ":" ++ show t ++ " " ++ showExpr e ++ " " ++ showExpr body ++ ")"
showExpr (Switch t e alts def) =
  "(switch:" ++ show t ++ " " ++ showExpr e ++ concatMap alt alts ++ " [_ " ++ showExpr def ++ "])"
  where
    alt : (Integer, Expr) -> String
    alt (n, rhs) = " [" ++ show n ++ " " ++ showExpr rhs ++ "]"
showExpr CompileTime = "_"

||| Deterministic text form, for inspection and tests.
export covering
showProgram : Program -> String
showProgram prog = unlines (map showFn prog.functions ++ entryLine prog.entry)
  where
    showParam : Param -> String
    showParam p = "(" ++ show p.quantity ++ " %" ++ show p.var ++ " : " ++ show p.type ++ ")"

    showFn : Fn -> String
    showFn fn = "fn " ++ fn.name ++ " " ++ unwords (map showParam fn.params)
             ++ " : " ++ show fn.result ++ " = " ++ showExpr fn.body

    entryLine : Maybe String -> List String
    entryLine Nothing = []
    entryLine (Just e) = ["entry " ++ e]
