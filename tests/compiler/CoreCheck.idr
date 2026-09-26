||| CORE-CHECK-1: Core.Check on hand-built invalid Core. Each case names the
||| invariant it breaks; the check must reject it with that invariant.
|||
||| rule: CORE-CHECK-1, CORE-INV-1, CORE-INV-2, CORE-INV-3, CORE-INV-5, CORE-INV-6
||| rule: CORE-INV-7, CORE-INV-8, CORE-INV-9, CORE-INV-10, DIAG-ICE-1
module Main

import IdrisMLIR.Core
import IdrisMLIR.Core.Check

import Data.List
import Data.String
import System

l : Loc
l = noLoc

int : Ty
int = IntT IdrisInt

lit : Integer -> Expr
lit n = ELit l (LInt IdrisInt n)

fn : String -> List Param -> Ty -> Expr -> Fn
fn n ps r b = MkFn n n ps r b l True

prog : List Data -> List Fn -> Program
prog ds fs = MkProgram ds fs "main" IntEntry 0

unit : Data
unit = MkData "Builtin.Unit" "Builtin.Unit" [MkCon "Builtin.MkUnit" "Builtin.MkUnit" 0 [] l] l

ioRes : Data
ioRes = MkData "IORes" "IORes" [MkCon "MkIORes" "MkIORes" 0 [MkField QW (DataT "Builtin.Unit"), MkField Q1 WorldT] l] l

shape : Data
shape = MkData "Shape" "Shape"
          [ MkCon "Circle" "Circle" 0 [MkField QW int] l
          , MkCon "Square" "Square" 1 [MkField QW int] l ] l

||| (name, program, expected rule or "" for a valid program)
cases : List (String, Program, String)
cases =
  [ ("valid", prog [] [fn "main" [] int (lit 1)], "")
  , ("unbound variable", prog [] [fn "main" [] int (EVar l 7)], "CORE-INV-1")
  , ("variable bound twice", prog []
      [fn "main" [] int (ELet l 1 QW int (lit 1) (ELet l 1 QW int (lit 2) (EVar l 1)))], "CORE-INV-1")
  , ("lambda survives", prog [] [fn "main" [] int (EApp l (ELam l 1 QW int (EVar l 1)) (lit 3))], "CORE-INV-2")
  , ("call with the wrong arity", prog []
      [fn "main" [] int (ECall l "f" []), fn "f" [MkParam 1 QW int] int (EVar l 1)], "CORE-INV-2")
  , ("function type", prog []
      [fn "main" [] int (ELet l 1 QW (FunT QW int int) (lit 1) (lit 2))], "CORE-INV-3")
  , ("quantity-0 argument not erased", prog []
      [fn "main" [] int (ECall l "f" [lit 1]), fn "f" [MkParam 1 Q0 ErasedT] int (lit 2)], "CORE-INV-3")
  , ("ill-typed call", prog []
      [fn "main" [] int (ECall l "f" [ELit l (LChar 65)]), fn "f" [MkParam 1 QW int] int (EVar l 1)], "CORE-INV-3")
  , ("quantity-0 variable used", prog []
      [fn "main" [] int (ECall l "f" [EErased l]), fn "f" [MkParam 1 Q0 ErasedT] int (EVar l 1)], "CORE-INV-5")
  , ("duplicate alternatives", prog [shape]
      [fn "main" [] int (ECall l "area" [ECon l "Shape" "Circle" [lit 2]]),
       fn "area" [MkParam 1 QW (DataT "Shape")] int
         (EMatchCon l 1 [MkConAlt "Circle" [2] (EVar l 2), MkConAlt "Circle" [3] (EVar l 3)] (Just (lit 0)))], "CORE-INV-6")
  , ("match that does not cover", prog [shape]
      [fn "main" [] int (ECall l "area" [ECon l "Shape" "Circle" [lit 2]]),
       fn "area" [MkParam 1 QW (DataT "Shape")] int
         (EMatchCon l 1 [MkConAlt "Circle" [2] (EVar l 2)] Nothing)], "CORE-INV-6")
  , ("literal of the wrong type", prog []
      [fn "main" [] int (ELet l 1 QW int (lit 1) (EMatchLit l 1 [(LChar 65, lit 1)] (lit 2)))], "CORE-INV-6")
  , ("tags not 0..n-1", prog [MkData "T" "T" [MkCon "A" "A" 1 [] l] l]
      [fn "main" [] int (ELet l 1 QW (DataT "T") (ECon l "T" "A" []) (lit 0))], "CORE-INV-7")
  , ("recursive data", prog [MkData "L" "L" [MkCon "Nil" "Nil" 0 [] l, MkCon "Cons" "Cons" 1 [MkField QW (DataT "L")] l] l]
      [fn "main" [] int (lit 0)], "CORE-INV-7")
  , ("unreachable function", prog [] [fn "main" [] int (lit 1), fn "dead" [] int (lit 2)], "CORE-INV-8")
  , ("world used twice", MkProgram [unit, ioRes]
      [fn "main" [MkParam 1 Q1 WorldT] (DataT "IORes")
         (ELet l 2 QW (DataT "IORes") (EIO l PutChar [ELit l (LChar 65), EVar l 1] "IORes")
            (EIO l PutChar [ELit l (LChar 66), EVar l 1] "IORes"))]
      "main" IOEntry 1, "CORE-INV-9")
  , ("string operation", prog []
      [fn "main" [] int (EPrim l StrLength [ELit l (LStr "abc")])], "CORE-INV-10")
  ]

main : IO ()
main = do
  results <- for cases $ \(name, p, rule) => do
    let got = checkFirstOrder p
    let ok = case (got, rule) of
               (Right (), "") => True
               (Left msg, r) => r /= "" && isPrefixOf r msg
               _ => False
    putStrLn ((if ok then "ok   " else "FAIL ") ++ name ++ ": " ++ either id (const "accepted") got)
    pure ok
  -- The full-Core subset accepts lambdas but still needs closed terms.
  let fullOk = case (checkFull (prog [] [fn "main" [] int (EApp l (ELam l 1 QW int (EVar l 1)) (lit 3))]),
                     checkFull (prog [] [fn "main" [] int (ELam l 1 QW int (EVar l 2))])) of
                 (Right (), Left msg) => isPrefixOf "CORE-INV-1" msg
                 _ => False
  putStrLn ((if fullOk then "ok   " else "FAIL ") ++ "full Core subset")
  if all id results && fullOk then exitSuccess else exitFailure
