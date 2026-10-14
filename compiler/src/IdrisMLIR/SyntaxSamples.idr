-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| One sample of every type and attribute of the dialects' generated
||| syntax (IdrisMLIR.Syntax.*), and of every directive of the ops'
||| declarative syntax the generated printers write (IdrisMLIR.Dialect.*),
||| written as the frontend writes them: a module whose discardable
||| attributes hold the type and attribute samples and whose region holds
||| two data declarations and three functions of op samples. It is written
||| twice, to the two files its command line names: each op through its
||| dialect's printer, and each op in the generic form. The round trip
||| (tests/compiler/dialect-syntax) has idris-mlir-opt read both and print
||| them back, so that what the Idris printers write is what the C++ parsers
||| read, and the two are one module, so that the declarative text leaves
||| out nothing the generic text says. Every grade a frontend writes long is
||| sampled, the ones the dialect spells shorter among them, and a
||| constructor's cells nested as Idris writes them, which the parser reads
||| as a run.
|||
||| A generated sum that gains a constructor gains a mnemonic: this program
||| exits 1, naming every mnemonic of a sum MLIR.idr holds that no sample
||| has, and writes nothing.
module IdrisMLIR.SyntaxSamples

import IdrisMLIR.Dialect.Builtin as Builtin
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Syntax.Arith
import IdrisMLIR.Syntax.UB

import Data.List
import Data.String
import System
import System.File

%default total

str : MlirType
str = Idr StrType

big : MlirType
big = Idr BigType

box : MlirType
box = Idr (BoxType "T")

i64 : MlirType
i64 = IntegerType 64

world : MlirType
world = Idr (QType One Plain (Idr WorldType))

dataT : MlirType
dataT = Idr (DataType "T")

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

||| What a declaration is an instance of: an Idris definition at a type.
maybeNat : MlirAttr
maybeNat = Idr (InstanceAttr "Maybe" [StringAttr "Nat"])

types : List MlirType
types =
  [ big
  , box
  , dataT
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
  , world
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
  , maybeNat
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

------------------------------------------------------------------------------
-- Ops
------------------------------------------------------------------------------

-- The samples are no program's, so every op and block argument is at no
-- location.

||| An op whose results the statement names `r`.
binding : String -> Op -> Statement
binding r o = MkStatement (Just r) o (At noLoc)

||| An op with no result.
stmt : Op -> Statement
stmt o = MkStatement Nothing o (At noLoc)

||| A region of one block, which binds `vs`.
block : List Value -> List Statement -> Region
block vs ss = MkRegion (map (\v => MkArgument v (At noLoc)) vs) ss

||| `@T`, a sum of two constructors, with a discardable attribute: a symbol
||| name, `attr-dict-with-keyword`, and a region. The constructors are
||| written generic: their syntax has a custom directive.
sumDecl : Statement
sumDecl =
  stmt ({ attributes := [("sample.x", int 1)] }
         (Idr.dataOp "T" (block [] [stmt (Idr.ctorOp "A" [i64]), stmt (Idr.ctorOp "Nil" [])])))

||| A box that is an instance of an Idris type: an optional group on a unit
||| attribute, one on an optional attribute, which is a dialect attribute
||| written qualified, and a symbol name that must be quoted.
boxDecl : Statement
boxDecl =
  stmt (Idr.dataOp {box = True} {instance = Just maybeNat} "Maybe[Nat]"
         (block [] [stmt (Idr.ctorOp "Just" [i64])]))

||| One op of each directive, in a function of the values they use.
sample : Statement
sample =
  let v = MkValue "%v" dataT
      n = MkValue "%n" i64
      s = MkValue "%s" str
      w0 = MkValue "%w0" world
      x = MkValue "%x" i64
      lin = Idr (QType One Plain i64)
  in stmt (Idr.funcOp "sample" (FunctionType (MkSignature [dataT, i64, str, world] [i64, world]))
            (block [v, n, s, w0]
               [ -- An operand, and the type directive of one.
                 binding "%tag" (Idr.tagOp v i64)
                 -- A symbol reference, an integer without its type, and two
                 -- type directives.
               , binding "%field" (Idr.fieldOp v "A" 0 i64)
                 -- A variadic operand, and `functional-type` of it.
               , binding "%a" (Idr.conOp (MkSymbolRef "T" ["A"]) [n] dataT)
                 -- The variadic operand empty.
               , binding "%nil" (Idr.conOp (MkSymbolRef "T" ["Nil"]) [] dataT)
                 -- A string attribute.
               , binding "%checked" (Idr.checkNonzeroOp n "div" i64)
                 -- An integer enum by its keyword, and every type buildable.
               , binding "%cmp" (Idr.strCmpOp CmpPredicate.Lt s s (IntegerType 1))
                 -- `qualified`, into a linear position and out of it once.
               , binding "%lin" (Idr.linEnterOp n lin)
               , binding "%used" (Idr.linUseOp (MkValue "%lin" lin) i64)
                 -- A region last, and an optional group on a variadic
                 -- operand, there, with the type directive of it.
               , binding "%lam" (Idr.lambdaOp (block [x] [stmt (Idr.yieldOp [x, x])])
                                           (Idr (FnType (MkSignature [i64] [i64, i64]))))
                 -- The optional group absent.
               , binding "%unit" (Idr.lambdaOp (block [] [stmt (Idr.yieldOp [])])
                                            (Idr (FnType (MkSignature [] []))))
                 -- A region that uses a value from above.
               , binding "%lazy" (Idr.delayOp (block [] [stmt (Idr.yieldOp [n])])
                                             (Idr (LazyType i64)))
                 -- Operands of buildable types, the world threaded.
               , binding "%w1" (Idr.ioPutStrOp s w0 world)
                 -- Two results.
               , binding "%b" (Idr.ioGetByteOp (MkValue "%w1" world) (IntegerType 32) world)
                 -- A call, `functional-type` of variadic results.
               , binding "%r" (Idr.callOp "callee" [n] [i64])
                 -- `attr-dict` holding a unit attribute, of an op of no
                 -- operands and no results.
               , stmt ({ attributes := [("sample.y", UnitAttr)] } Idr.mayLoopOp)
               , stmt (Idr.returnOp [MkValue "%r" i64, MkValue "%b#1" world])
               ]))

||| A function called by `@sample`.
callee : Statement
callee =
  let a = MkValue "%a" i64
  in stmt (Idr.funcOp "callee" (FunctionType (MkSignature [i64] [i64]))
            (block [a] [stmt (Idr.returnOp [a])]))

||| A function that returns nothing: the optional group of `idr.return`
||| absent.
nothing : Statement
nothing =
  stmt (Idr.funcOp "nothing" (FunctionType (MkSignature [] []))
         (block [] [stmt (Idr.returnOp [])]))

||| The module: the type and attribute samples as its discardable
||| attributes, and the op samples in its region.
sampleModule : Op
sampleModule =
  { attributes := named "sample.t" (map TypeAttr types) ++ named "sample.a" attrs }
    (Builtin.moduleOp (block [] [sumDecl, boxDecl, sample, callee, nothing]))

||| Each op through its dialect's printer, which writes it generic where its
||| syntax is not one the printer writes.
covering
declarative : Format
declarative o = Idr.printOp o <|> Builtin.printOp o

||| Each op generic.
generic : Format
generic _ = Nothing

||| Writes the module to `path`, each op as `format` writes it.
covering
writeSamples : String -> Format -> IO ()
writeSamples path format = do
  Right () <- writeFile path (showModule format (At noLoc) sampleModule)
    | Left e => die ("syntax-samples: writing " ++ path ++ ": " ++ show e)
  pure ()

covering
main : IO ()
main = do
  let missed = unsampled
  unless (null missed) $ die ("syntax-samples: no sample of " ++ joinBy ", " missed)
  [_, declared, plain] <- getArgs
    | _ => die "usage: syntax-samples DECLARATIVE GENERIC"
  writeSamples declared declarative
  writeSamples plain generic
