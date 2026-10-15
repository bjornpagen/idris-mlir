-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| One sample of every type and attribute of the dialects' generated
||| syntax (IdrisMLIR.Syntax.*) and of the builtin ones the frontend writes
||| (IdrisMLIR.MLIR), and ops of every shape the frontend's builders make
||| (IdrisMLIR.Dialect.*), written as the frontend writes them: one MLIR
||| bytecode file (IdrisMLIR.MLIR.Bytecode), at the path its command line
||| names. The module's discardable attributes hold the type and attribute
||| samples, each kept as its text, which the dialects' C++ parsers read;
||| its program holds functions of op samples: inherent attributes of each
||| kind, absent and present, variadic operands of several groups, several
||| results, regions nested in regions using the values around them, block
||| arguments, closures and suspensions of functions, a suspended value, an
||| array built, read, transposed, folded, scanned and made in the world's
||| order. The round trip
||| (tests/compiler/dialect-syntax) has idris-mlir-opt read the file and
||| print it, so that what the Idris side writes is what MLIR reads. Every
||| grade a frontend writes long is sampled, the ones the dialect spells
||| shorter among them.
|||
||| A generated sum that gains a constructor gains a mnemonic: this program
||| exits 1, naming every mnemonic of a sum MLIR.idr holds that no sample
||| has, and writes nothing.
module IdrisMLIR.SyntaxSamples

import IdrisMLIR.Dialect.Arith as Arith
import IdrisMLIR.Dialect.Builtin as Builtin
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.Tensor as Tensor
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.MLIR.Bytecode
import IdrisMLIR.Syntax.Arith
import IdrisMLIR.Syntax.UB

import Data.List
import Data.String
import System
import System.File

%default total

str : MlirType
str = idr StrType

big : MlirType
big = idr BigType

i64 : MlirType
i64 = IntegerType 64

world : MlirType
world = idr (QType One Plain (idr WorldType))

||| A constructor of no part a pass needs.
plainCtor : String -> List MlirType -> IdrCtor MlirType
plainCtor name fields = MkIdrCtor name fields False CtorRole.Plain Nothing

||| A list of naturals: base's list, recursive through itself, which its
||| own body names by its name alone, as the frontend writes it: the
||| dialect boxes what a cycle runs through.
natList : MlirType
natList =
  idr (DataType "List[Nat]"
        (Just (MkIdrSum BaseList
                 [ MkIdrCtor "Nil" [] False CtorRole.ListNil Nothing
                 , MkIdrCtor "Cons" [idr NatType, idr (DataType "List[Nat]" Nothing)] False CtorRole.ListCons Nothing ]
                 (Just ("Prelude.Types.List", ["Prelude.Types.Nat"])))))

||| A plain sum of two constructors, one holding a list: another type's
||| body spelled whole inside it.
dataT : MlirType
dataT =
  idr (DataType "T" (Just (MkIdrSum Plain [plainCtor "A" [i64, natList], plainCtor "Nil" []] Nothing)))

||| Each kind of sum the dialect has, and each part a constructor plays: a
||| label names its function.
kinds : List MlirType
kinds =
  [ idr (DataType "Pairs" (Just (MkIdrSum InPlace [plainCtor "P" [idr (QType One Plain i64)]] Nothing)))
  , idr (DataType "fn$sample"
          (Just (MkIdrSum Closures [MkIdrCtor "callee" [i64] False CtorRole.Label (Just "callee")] Nothing)))
  , idr (DataType "lazy$sample"
          (Just (MkIdrSum Memo [ MkIdrCtor "callee" [] True CtorRole.Label (Just "callee")
                               , MkIdrCtor "running" [] False CtorRole.Running Nothing
                               , MkIdrCtor "forced" [i64] False CtorRole.Forced Nothing ] Nothing)))
  ]

int : Integer -> MlirAttr
int n = IntegerAttr n i64

||| What a declaration is an instance of: an Idris definition at a type.
maybeNat : MlirAttr
maybeNat = idr (InstanceAttr "Maybe" [StringAttr "Nat"])

types : List MlirType
types =
  [ big
  , natList
  , idr (BoxType natList)
  , dataT
  , idr (DestType (idr (BoxType natList)))
  , idr (FnType (MkSignature [] []))
  , idr (FnType (MkSignature [i64] [i64]))
  , idr (FnType (MkSignature [i64] [i64, i64]))
  , idr (FnType (MkSignature [i64] [idr (FnType (MkSignature [i64] [i64]))]))
  , idr (LazyType (idr NatType))
  , idr NatType
  , idr (QType One Plain str)
  , idr (QType Many Own big)
  , idr (QType Many Excl (idr (BoxType natList)))
  , world
  , idr (QType One Own str)
  , idr (QType Many Borrow str)
  , str
  , idr TokenType
  , idr WorldType
  , RankedTensorType [Dynamic, Static 3] F64Type
  , RankedTensorType [] i64
  , RankedTensorType [Dynamic] (idr NatType)
  , idr (QType One Plain (RankedTensorType [Dynamic] i64))
  , MemRefType [Dynamic] (IntegerType 8) (Just (idr WorldSpaceAttr))
  , MemRefType [] i64 (Just (idr WorldSpaceAttr))
  , IndexType
  ] ++ kinds

key : MlirAttr
key = idr (SpecKeyAttr "f" [idr (KeyHoleAttr 0), int 7])

attrs : List MlirAttr
attrs =
  [ idr (BigAttr (-12345678901234567890))
  , idr (ClosureAttr "g" [int 1, StringAttr "two"])
  , idr (EffectAttr [])
  , idr (EffectAttr [Io, Crash])
  , maybeNat
  , idr (KeyRaiseAttr "f" "idr.match")
  , idr (RuleAttr Rule.Cycle)
  , idr (KeyConAttr 1 [idr (KeyHoleAttr 2), idr (KeyConAttr 0 [])])
  , idr (KeyHoleAttr 3)
  , key
  , idr WorldSpaceAttr
  , arith (FastMathFlagsAttr [])
  , arith (FastMathFlagsAttr [Nnan, Ninf])
  , arith (IntegerOverflowFlagsAttr [Nsw, Nuw])
  , ub PoisonAttr
  , UnitAttr
  , BoolAttr True
  , FloatAttr 0.5 F64Type
  , StringAttr "a string with \"quotes\" and \x00e9"
  , SymbolRefAttr (MkSymbolRef "T" ["A"])
  , TypeAttr dataT
  , ArrayAttr [int 1, StringAttr "b"]
  , DenseI32ArrayAttr [1, 0, 2]
  , DenseI64ArrayAttr [0, dynamicExtent, 4]
  , DenseI64ArrayAttr []
  , DictionaryAttr [("a", int 1), ("b", UnitAttr)]
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
    idrType (Idr x _) = Just (idrTypeMnemonic x)
    idrType _ = Nothing
    idrAttr : MlirAttr -> Maybe String
    idrAttr (Idr x _) = Just (idrAttrMnemonic x)
    idrAttr _ = Nothing
    arithAttr : MlirAttr -> Maybe String
    arithAttr (Arith x _) = Just (arithAttrMnemonic x)
    arithAttr _ = Nothing
    ubAttr : MlirAttr -> Maybe String
    ubAttr (UB x _) = Just (ubAttrMnemonic x)
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

index : Integer -> Op
index n = Arith.constantOp (IntegerAttr n IndexType) IndexType

||| One op of each shape, in a function of the values they use: the root
||| the program names.
sample : Statement
sample =
  let v = MkValue "%v" dataT
      n = MkValue "%n" i64
      s = MkValue "%s" str
      w0 = MkValue "%w0" world
      x = MkValue "%x" i64
      lin = idr (QType One Plain i64)
      fn = idr (FnType (MkSignature [i64] [i64]))
      lazy = idr (LazyType i64)
      vec = RankedTensorType [Dynamic] i64
      scalar = RankedTensorType [] i64
      matrix = RankedTensorType [Static 2, Static 3] i64
      i = MkValue "%i" IndexType
      c0 = MkValue "%c0" IndexType
      c1 = MkValue "%c1" IndexType
      c4 = MkValue "%c4" IndexType
  in stmt (Idr.funcOp {instance = Just maybeNat} "sample"
            (FunctionType (MkSignature [dataT, i64, str, world] [i64, world]))
            (block [v, n, s, w0]
               [ binding "%tag" (Idr.tagOp v i64)
                 -- A field and constructors, each named by its tag: of
                 -- none and of fields, one of another type.
               , binding "%field" (Idr.fieldOp v 0 0 i64)
               , binding "%nil" (Idr.conOp 0 [] natList [])
               , binding "%a" (Idr.conOp 0 [n, MkValue "%nil" natList] dataT [])
               , binding "%checked" (Idr.checkNonzeroOp n "div" i64)
               , binding "%cmp" (Idr.strCmpOp CmpPredicate.Lt s s (IntegerType 1))
               , binding "%lin" (Idr.linEnterOp n lin)
               , binding "%used" (Idr.linUseOp (MkValue "%lin" lin) i64)
                 -- A closure and a suspension of functions, and a value
                 -- suspended.
               , binding "%f" (Idr.closureOp "callee" [] fn)
               , binding "%lazy" (Idr.suspendOp "thunk" [n] lazy)
               , binding "%held" (Idr.delayOp n lazy)
               , binding "%applied" (Idr.applyOp (MkValue "%f" fn) [n] [i64])
                 -- A match whose region uses a value from above and holds a
                 -- match of its own.
               , binding "%m" (Idr.matchOp v [0, 1]
                                 [ block [MkValue "%y" i64, MkValue "%ys" natList]
                                     [ binding "%inner" (Idr.matchLitOp n [int 0]
                                         [ block [] [stmt (Idr.yieldOp [MkValue "%y" i64])]
                                         , block [] [stmt (Idr.yieldOp [n])] ] [i64])
                                     , stmt (Idr.yieldOp [MkValue "%inner" i64]) ]
                                 , block [] [stmt (Idr.yieldOp [MkValue "%checked" i64])] ] [i64])
                 -- An array made from its indices, written, read, sliced,
                 -- transposed, folded and scanned.
               , binding "%c0" (index 0)
               , binding "%c1" (index 1)
               , binding "%c4" (index 4)
               , binding "%t" (Idr.tabulateOp [c4]
                                 (block [i] [ binding "%iv" (Arith.indexCastOp i i64)
                                            , stmt (Idr.arrayYieldOp [MkValue "%iv" i64]) ]) [vec])
               , binding "%t1" (Tensor.insertOp n (MkValue "%t" vec) [c0] vec)
               , binding "%e" (Tensor.extractOp (MkValue "%t1" vec) [c1] i64)
               , binding "%slice" (Tensor.extractSliceOp (MkValue "%t1" vec) [] [] [] [1] [2] [1]
                                     (RankedTensorType [Static 2] i64))
               , binding "%mat" (Tensor.emptyOp [] matrix)
               , binding "%tr" (Idr.transposeOp (MkValue "%mat" matrix) [1, 0]
                                  (RankedTensorType [Static 3, Static 2] i64))
               , binding "%z" (Tensor.fromElementsOp [n] scalar)
               , binding "%sum" (Idr.foldLastOp [MkValue "%z" scalar] c4 (accumulate "fold") [scalar])
               , binding "%sums" (Idr.scanLastOp [MkValue "%z" scalar] c4 (accumulate "scan") [vec])
                 -- Operands and results of the world, two results, and an
                 -- array made in the world's order.
               , binding "%w1" (Idr.ioPutStrOp s w0 world)
               , binding "%io" (Idr.tabulateIoOp [c4] (MkValue "%w1" world)
                                  (block [i, MkValue "%ww" world]
                                     [stmt (Idr.arrayYieldOp [n, MkValue "%ww" world])]) [vec] world)
               , binding "%b" (Idr.ioGetByteOp (MkValue "%io#1" world) (IntegerType 32) world)
               , binding "%r" (Idr.callOp "callee" [n] [i64])
                 -- A discardable attribute, on an op of no operands and no
                 -- results.
               , stmt ({ attributes := [("sample.y", UnitAttr)] } Idr.mayLoopOp)
               , stmt (Idr.returnOp [MkValue "%r" i64, MkValue "%b#1" world])
               ]))
  where
    -- A fold's region: the index along its axis and the accumulator, the
    -- array's element there added to it.
    accumulate : String -> Region
    accumulate stem =
      let j = MkValue ("%" ++ stem ++ "j") IndexType
          acc = MkValue ("%" ++ stem ++ "acc") i64
          el = MkValue ("%" ++ stem ++ "el") i64
          next = MkValue ("%" ++ stem ++ "next") i64
      in block [j, acc] [ binding el.name (Tensor.extractOp (MkValue "%t1" (RankedTensorType [Dynamic] i64)) [j] i64)
                        , binding next.name (Arith.addiOp acc el i64)
                        , stmt (Idr.arrayYieldOp [next]) ]

||| A function called and closed over by `@sample`.
callee : Statement
callee =
  let a = MkValue "%a" i64
  in stmt (Idr.funcOp {total' = True} "callee"
            (FunctionType (MkSignature [i64] [i64])) (block [a] [stmt (Idr.returnOp [a])]))

||| A function `@sample` suspends.
thunk : Statement
thunk =
  let a = MkValue "%a" i64
  in stmt (Idr.funcOp {noInline = True} "thunk"
            (FunctionType (MkSignature [i64] [i64])) (block [a] [stmt (Idr.returnOp [a])]))

||| A function that returns nothing.
nothing : Statement
nothing =
  stmt (Idr.funcOp "nothing" (FunctionType (MkSignature [] []))
         (block [] [stmt (Idr.returnOp [])]))

||| The module, with the type and attribute samples as its discardable
||| attributes, and the program of the op samples, whose root is `@sample`.
containers : List Container
containers =
  [ (At noLoc, \body => { attributes := named "sample.t" (map TypeAttr types) ++ named "sample.a" attrs }
                          (Builtin.moduleOp body))
  , (At noLoc, Idr.programOp "samples" "sample" Stage.Higher) ]

||| Writes the samples to `path`.
writeSamples : String -> IO ()
writeSamples path = do
  Right w <- newWriter
    | Left e => die ("syntax-samples: " ++ e)
  for_ [sample, callee, thunk, nothing] $ \s => do
    Right () <- writeTopLevel w s
      | Left e => die ("syntax-samples: " ++ e)
    pure ()
  Right h <- openFile path WriteTruncate
    | Left e => die ("syntax-samples: writing " ++ path ++ ": " ++ show e)
  Right () <- finish w h containers
    | Left e => die ("syntax-samples: " ++ e)
  closeFile h
main : IO ()
main = do
  let missed = unsampled
  unless (null missed) $ die ("syntax-samples: no sample of " ++ joinBy ", " missed)
  [_, path] <- getArgs
    | _ => die "usage: syntax-samples OUT.mlirbc"
  writeSamples path
