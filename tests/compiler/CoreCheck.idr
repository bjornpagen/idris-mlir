||| CORE-CHECK-1: the checks of Core on hand-built invalid Core. Each case
||| names the invariant it breaks; the check must reject it with that
||| invariant.
|||
||| Some invalid Core cannot be built at all: a lambda, a function or `Lazy`
||| type, or a string operation in first-order Core (CORE-INV-2, CORE-INV-3,
||| CORE-INV-10), and an unbound variable in full Core (CORE-INV-1).
|||
||| rule: CORE-CHECK-1, CORE-INV-1, CORE-INV-2, CORE-INV-3, CORE-INV-5, CORE-INV-6
||| rule: CORE-INV-7, CORE-INV-8, CORE-INV-9, DIAG-ICE-1
module Main

import IdrisMLIR.Code
import IdrisMLIR.Code.Check
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Term.Check
import IdrisMLIR.Types

import Data.List
import Data.String
import Data.Vect
import System

l : Loc
l = noLoc

int : VTy
int = IntT IdrisInt

v : Nat -> VarId
v = MkVarId

var : Nat -> Atom
var = AVar . v

lit : Integer -> Atom
lit n = ALit (LInt IdrisInt n)

let' : Nat -> VTy -> Op Code -> Code -> Code
let' x t = Bind l (v x) QW t

ret : Atom -> Code
ret = Ret l

param : Nat -> Quantity -> VTy -> Param
param x = MkParam (v x)

fn : String -> List Param -> VTy -> Code -> CFn
fn n ps r b = MkCFn (MkFnId n) n ps r b l True Nothing

prog : List CData -> List CFn -> Target
prog ds fs = MkTarget ds fs (MkFnId "main") IntEntry

dataT : String -> List (String, List CField) -> CData
dataT n cs = MkCData (MkDataId n) n (zipWith (\i, (c, fs) => MkCCon (MkConId (MkDataId n) c) i fs l) [0 .. length cs] cs) l

con : String -> String -> ConId
con d c = MkConId (MkDataId d) c

unit : CData
unit = dataT "Unit" [("MkUnit", [])]

ioRes : CData
ioRes = dataT "IORes" [("MkIORes", [MkCField QW (DataT (MkDataId "Unit")), MkCField Q1 WorldT])]

shape : CData
shape = dataT "Shape" [("Circle", [MkCField QW int]), ("Square", [MkCField QW int])]

callF : Atom -> Code
callF a = let' 1 int (OCall (MkFnId "f") [a]) (ret (var 1))

||| main calls area on a circle; area's body is given.
area : Code -> Target
area body = prog [shape]
  [ fn "main" [] int (let' 1 (DataT (MkDataId "Shape")) (OCon (con "Shape" "Circle") [lit 2])
                       (let' 2 int (OCall (MkFnId "area") [var 1]) (ret (var 2))))
  , fn "area" [param 1 QW (DataT (MkDataId "Shape"))] int body ]

||| (name, program, expected rule or Nothing for a valid program)
cases : List (String, Target, Maybe Rule)
cases =
  [ ("valid", prog [] [fn "main" [] int (ret (lit 1))], Nothing)
  , ("unbound variable", prog [] [fn "main" [] int (ret (var 7))], Just CoreInv1)
  , ("variable bound twice", prog []
      [fn "main" [] int (let' 1 int (OPrim (IntOp Add IdrisInt) [lit 1, lit 2])
                          (let' 1 int (OPrim (IntOp Add IdrisInt) [lit 1, lit 2]) (ret (var 1))))], Just CoreInv1)
  , ("call with the wrong arity", prog []
      [fn "main" [] int (let' 1 int (OCall (MkFnId "f") []) (ret (var 1))),
       fn "f" [param 2 QW int] int (ret (var 2))], Just CoreInv2)
  , ("quantity-0 argument not erased", prog []
      [fn "main" [] int (callF (lit 1)), fn "f" [param 2 Q0 ErasedT] int (ret (lit 2))], Just CoreInv3)
  , ("ill-typed call", prog []
      [fn "main" [] int (callF (ALit (LChar 65))), fn "f" [param 2 QW int] int (ret (var 2))], Just CoreInv3)
  , ("quantity-0 variable used", prog []
      [fn "main" [] int (callF AErased), fn "f" [param 2 Q0 ErasedT] int (ret (var 2))], Just CoreInv5)
  , ("duplicate alternatives", area
      (let' 4 int (OCase (var 1) [MkBranch (con "Shape" "Circle") [v 2] (ret (var 2)),
                                  MkBranch (con "Shape" "Circle") [v 3] (ret (var 3))] (Just (ret (lit 0))))
         (ret (var 4))), Just CoreInv6)
  , ("match that does not cover", area
      (let' 4 int (OCase (var 1) [MkBranch (con "Shape" "Circle") [v 2] (ret (var 2))] Nothing)
         (ret (var 4))), Just CoreInv6)
  , ("impossible alternative", area
      (let' 4 int (OCase (var 1) [MkBranch (con "Shape" "Circle") [v 2] (ret (var 2)),
                                  MkBranch (con "Shape" "Square") [v 3] (Absurd l)] Nothing)
         (ret (var 4))), Nothing)
  , ("match whose alternatives are all impossible", area
      (let' 4 int (OCase (var 1) [MkBranch (con "Shape" "Circle") [v 2] (Absurd l),
                                  MkBranch (con "Shape" "Square") [v 3] (Absurd l)] Nothing)
         (ret (var 4))), Just CoreInv6)
  , ("literal of the wrong type", prog []
      [fn "main" [] int (let' 1 int (OPrim (IntOp Add IdrisInt) [lit 1, lit 2])
                          (let' 2 int (OCaseLit (var 1) [(LChar 65, ret (lit 1))] (ret (lit 2))) (ret (var 2))))],
      Just CoreInv6)
  , ("field of data with several constructors", area
      (let' 4 int (OField (var 1) (con "Shape" "Circle") 0) (ret (var 4))), Just CoreInv6)
  , ("tags not 0..n-1", prog [MkCData (MkDataId "T") "T" [MkCCon (con "T" "A") 1 [] l] l]
      [fn "main" [] int (let' 1 (DataT (MkDataId "T")) (OCon (con "T" "A") []) (ret (lit 0)))], Just CoreInv7)
  , ("recursive data", prog [dataT "L" [("Nil", []), ("Cons", [MkCField QW (DataT (MkDataId "L"))])]]
      [fn "main" [] int (ret (lit 0))], Just CoreInv7)
  , ("unreachable function", prog [] [fn "main" [] int (ret (lit 1)), fn "dead" [] int (ret (lit 2))], Just CoreInv8)
  , ("world used twice", MkTarget [unit, ioRes]
      [fn "main" [param 1 Q1 WorldT] (DataT (MkDataId "IORes"))
         (let' 2 (DataT (MkDataId "IORes")) (OIO PutChar [ALit (LChar 65), var 1] (MkDataId "IORes"))
            (let' 3 (DataT (MkDataId "IORes")) (OIO PutChar [ALit (LChar 66), var 1] (MkDataId "IORes"))
               (ret (var 3))))]
      (MkFnId "main") IOEntry, Just CoreInv9)
  ]

||| Full Core after Translate: references and arities.
fullCases : List (String, Source, Maybe Rule)
fullCases =
  [ ("full Core: valid", source [tfn "main" [] (Literal l (LInt IdrisInt 1))], Nothing)
  , ("full Core: call with the wrong arity",
      source [tfn "main" [] (Call l (MkFnId "main") [Literal l (LInt IdrisInt 1)])], Just CoreInv2)
  , ("full Core: unknown function", source [tfn "main" [] (Call l (MkFnId "g") [])], Just CoreInv2)
  ]
  where
    tfn : String -> Vect 0 Binder -> Term 0 -> TFn
    tfn n ps b = MkTFn (MkFnId n) n 0 ps (V int) b l True
    source : List TFn -> Source
    source fs = MkSource [] fs (MkFnId "main") IntEntry

report : String -> Either (Rule, String) () -> Maybe Rule -> IO Bool
report name got rule = do
  let ok = case (got, rule) of
             (Right (), Nothing) => True
             (Left (r, _), Just r') => show r == show r'
             _ => False
  let what = the String (case got of
                           Right () => "accepted"
                           Left (r, m) => show r ++ ": " ++ m)
  putStrLn ((if ok then "ok   " else "FAIL ") ++ name ++ ": " ++ what)
  pure ok

main : IO ()
main = do
  first <- for cases $ \(name, p, rule) => report name (check p) rule
  full <- for fullCases $ \(name, s, rule) => report name (checkSource s) rule
  if all id (first ++ full) then exitSuccess else exitFailure
