||| One sample of every type and attribute of the dialects' generated
||| syntax (IdrisMLIR.Syntax.*), written as the frontend writes them: a
||| module whose discardable attributes hold the samples, which the round
||| trip (tests/compiler/dialect-syntax) has idris-mlir-opt read and print
||| back, so that what the Idris printers write is what the C++ parsers
||| read. Every grade a frontend writes long is sampled, the ones the dialect
||| spells shorter among them, and a constructor's cells nested as Idris
||| writes them, which the parser reads as a run.
|||
||| A generated sum that gains a constructor gains a mnemonic: this program
||| exits 1, naming every mnemonic of a sum MLIR.idr holds that no sample
||| has, and prints nothing.
module IdrisMLIR.SyntaxSamples

import IdrisMLIR.Dialect.Builtin as Builtin
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Syntax.Arith
import IdrisMLIR.Syntax.UB

import Data.List
import Data.String
import System

%default total

str : MlirType
str = Idr StrType

big : MlirType
big = Idr BigType

box : MlirType
box = Idr (BoxType "T")

i64 : MlirType
i64 = IntegerType 64

int : Integer -> MlirAttr
int n = IntegerAttr n i64

||| A constructor of `List`, by name.
list : String -> SymbolRef
list c = MkSymbolRef "List" [c]

nil : MlirAttr
nil = Idr (ConAttr (list "Nil") [[]] Nothing 0)

||| `Cons x xs`, a plain constructor of one cell.
cons : MlirAttr -> MlirAttr -> MlirAttr
cons x xs = Idr (ConAttr (list "Cons") [[x, xs]] Nothing 0)

types : List MlirType
types =
  [ big
  , box
  , Idr (DataType "T")
  , Idr (DestType box)
  , Idr (FnType (MkSignature [] []))
  , Idr (FnType (MkSignature [i64] [i64]))
  , Idr (FnType (MkSignature [i64] [i64, i64]))
  , Idr (FnType (MkSignature [i64] [Idr (FnType (MkSignature [i64] [i64]))]))
  , Idr (LazyType (Idr NatType))
  , Idr NatType
  , Idr (QType One Plain str)
  , Idr (QType Many Own big)
  , Idr (QType Many Excl box)
  , Idr (QType Zero Plain NoneType)
  , Idr (QType One Plain (Idr WorldType))
  , Idr (QType One Own str)
  , Idr (QType Many Borrow str)
  , str
  , Idr TokenType
  , Idr WorldType
  ]

key : MlirAttr
key = Idr (SpecKeyAttr "f" [Idr (KeyHoleAttr 0), int 7])

attrs : List MlirAttr
attrs =
  [ Idr (BigAttr "-12345678901234567890")
  , Idr (CloneAttr "f_clone" key)
  , Idr (ClosureAttr "g" [int 1, StringAttr "two"])
  , nil
  , cons (int 1) (cons (int 2) (cons (int 3) nil))
  , Idr (ConAttr (list "Cons") [[int 1], [int 2]] (Just nil) 1)
  , Idr (EffectAttr [])
  , Idr (EffectAttr [Io, Crash])
  , Idr ErasedAttr
  , Idr (KeyApplyAttr "f" 2)
  , Idr (KeyApplyFieldAttr "f" 2 "Cons" 1)
  , Idr (KeyClosureAttr "g" [Idr (KeyHoleAttr 1)])
  , Idr (KeyConAttr "List" "Cons" [Idr (KeyHoleAttr 2), Idr (KeyConAttr "List" "Nil" [])])
  , Idr (KeyHoleAttr 3)
  , key
  , Arith (FastMathFlagsAttr [])
  , Arith (FastMathFlagsAttr [Nnan, Ninf])
  , Arith (IntegerOverflowFlagsAttr [Nsw, Nuw])
  , UB PoisonAttr
  ]

||| The mnemonics of the generated sums that no sample has, each with its
||| dialect and whether it is a type.
unsampled : List String
unsampled =
  missing "idr type" idrTypeMnemonics (mapMaybe idrType types)
    ++ missing "idr attribute" idrAttrMnemonics (mapMaybe idrAttr attrs)
    ++ missing "arith attribute" arithAttrMnemonics (mapMaybe arithAttr attrs)
    ++ missing "ub attribute" ubAttrMnemonics (mapMaybe ubAttr attrs)
  where
    missing : String -> List String -> List String -> List String
    missing what mnemonics sampled =
      map (\m => what ++ " " ++ m) (filter (\m => not (elem m sampled)) mnemonics)
    idrType : MlirType -> Maybe String
    idrType (Idr x) = Just (idrTypeMnemonic x)
    idrType _ = Nothing
    idrAttr : MlirAttr -> Maybe String
    idrAttr (Idr x) = Just (idrAttrMnemonic x)
    idrAttr _ = Nothing
    arithAttr : MlirAttr -> Maybe String
    arithAttr (Arith x) = Just (arithAttrMnemonic x)
    arithAttr _ = Nothing
    ubAttr : MlirAttr -> Maybe String
    ubAttr (UB x) = Just (ubAttrMnemonic x)
    ubAttr _ = Nothing

||| The samples, named `stem` and their index in two digits, so that the
||| dictionary the parser sorts keeps their order.
named : String -> List MlirAttr -> List NamedAttr
named stem samples =
  zipWith (\i, a => (stem ++ padLeft 2 '0' (show i), a)) [0 .. length samples] samples

covering
main : IO ()
main = do
  let missed = unsampled
  unless (null missed) $ die ("syntax-samples: no sample of " ++ joinBy ", " missed)
  -- The samples are no program's, so the module is at no location.
  putStr (showModule (At noLoc)
                     ({ attributes := named "sample.t" (map TypeAttr types)
                                      ++ named "sample.a" attrs }
                        (Builtin.moduleOp (MkRegion [] []))))
