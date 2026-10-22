-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The dialects of the contract, once: ours and the upstream dialects whose
||| ops the specification admits (the frontend writes them, a pass reads
||| them, or an op of ours is defined in them, as the schedule's transform
||| op is). The frontend's writer numbers dialects by this, the D51 backend
||| prints one admitted record file per upstream dialect from it, and no
||| dialect is named by a string anywhere else.
module IdrisMLIR.Spec.Core.Dialect

import IdrisMLIR.Spec.Core.Text

import Data.List1

%default total

public export
data Dialect
  = Idr
  | Builtin
  | Arith
  | Math
  | MemRef
  | Tensor
  | UB
  | Linalg
  | Bufferization
  | SCF
  | Transform

||| Every dialect, in declaration order: the order the writer numbers them.
public export
dialects : List Dialect
dialects = [Idr, Builtin, Arith, Math, MemRef, Tensor, UB, Linalg, Bufferization, SCF, Transform]

||| The dialect's namespace in the IR: `arith` in `arith.addi`.
public export
namespaceWord : Dialect -> Word
namespaceWord Idr = word "idr"
namespaceWord Builtin = word "builtin"
namespaceWord Arith = word "arith"
namespaceWord Math = word "math"
namespaceWord MemRef = word "memref"
namespaceWord Tensor = word "tensor"
namespaceWord UB = word "ub"
namespaceWord Linalg = word "linalg"
namespaceWord Bufferization = word "bufferization"
namespaceWord SCF = word "scf"
namespaceWord Transform = word "transform"

||| The dialect's record in upstream's ODS, which an admitted op's record
||| and an op defined in it name.
public export
odsDialect : Dialect -> Ident
odsDialect Idr = ident "Idr_Dialect"
odsDialect Builtin = ident "Builtin_Dialect"
odsDialect Arith = ident "Arith_Dialect"
odsDialect Math = ident "Math_Dialect"
odsDialect MemRef = ident "MemRef_Dialect"
odsDialect Tensor = ident "Tensor_Dialect"
odsDialect UB = ident "UB_Dialect"
odsDialect Linalg = ident "Linalg_Dialect"
odsDialect Bufferization = ident "Bufferization_Dialect"
odsDialect SCF = ident "SCF_Dialect"
odsDialect Transform = ident "Transform_Dialect"

||| The upstream ODS file that defines the dialect's ops, which an admitted
||| record file includes; ours is printed.
public export
odsInclude : Dialect -> String
odsInclude Idr = "idr/IR/Generated/IdrOps.td"
odsInclude Builtin = "mlir/IR/BuiltinOps.td"
odsInclude Arith = "mlir/Dialect/Arith/IR/ArithOps.td"
odsInclude Math = "mlir/Dialect/Math/IR/MathOps.td"
odsInclude MemRef = "mlir/Dialect/MemRef/IR/MemRefOps.td"
odsInclude Tensor = "mlir/Dialect/Tensor/IR/TensorOps.td"
odsInclude UB = "mlir/Dialect/UB/IR/UBOps.td"
odsInclude Linalg = "mlir/Dialect/Linalg/IR/LinalgStructuredOps.td"
odsInclude Bufferization = "mlir/Dialect/Bufferization/IR/BufferizationOps.td"
odsInclude SCF = "mlir/Dialect/SCF/IR/SCFOps.td"
odsInclude Transform = "mlir/Dialect/Transform/IR/TransformOps.td"

||| The C++ header that declares the dialect's ops: the classes its
||| admitted ops' aliases name are declared there, so the aliases' header
||| includes it.
public export
cppHeader : Dialect -> String
cppHeader Idr = "idr/IR/IdrDialect.h"
cppHeader Builtin = "mlir/IR/BuiltinOps.h"
cppHeader Arith = "mlir/Dialect/Arith/IR/Arith.h"
cppHeader Math = "mlir/Dialect/Math/IR/Math.h"
cppHeader MemRef = "mlir/Dialect/MemRef/IR/MemRef.h"
cppHeader Tensor = "mlir/Dialect/Tensor/IR/Tensor.h"
cppHeader UB = "mlir/Dialect/UB/IR/UBOps.h"
cppHeader Linalg = "mlir/Dialect/Linalg/IR/Linalg.h"
cppHeader Bufferization = "mlir/Dialect/Bufferization/IR/Bufferization.h"
cppHeader SCF = "mlir/Dialect/SCF/IR/SCF.h"
cppHeader Transform = "mlir/Dialect/Transform/IR/TransformOps.h"

||| Upstream's file of the dialect's bytecode records, under MLIR's include
||| directory, where the frontend writes the dialect's types and attributes
||| in bytecode: its writer's entries are generated from those records.
||| None where the frontend writes them as text, and none for ours, whose
||| entries the specification prints itself.
public export
bytecodeRecords : Dialect -> Maybe String
bytecodeRecords Idr = Nothing
bytecodeRecords Builtin = Just "mlir/IR/BuiltinDialectBytecode.td"
bytecodeRecords Arith = Nothing
bytecodeRecords Math = Nothing
bytecodeRecords MemRef = Nothing
bytecodeRecords Tensor = Nothing
bytecodeRecords UB = Nothing
bytecodeRecords Linalg = Nothing
bytecodeRecords Bufferization = Nothing
bytecodeRecords SCF = Nothing
bytecodeRecords Transform = Nothing

||| The dialect in an identifier: the admitted record file's and the Idris
||| module's name, `IdrAdmittedArith.td`, `IdrisMLIR.Dialect.Arith`.
public export
dialectName : Dialect -> Ident
dialectName Idr = ident "Idr"
dialectName Builtin = ident "Builtin"
dialectName Arith = ident "Arith"
dialectName Math = ident "Math"
dialectName MemRef = ident "MemRef"
dialectName Tensor = ident "Tensor"
dialectName UB = ident "UB"
dialectName Linalg = ident "Linalg"
dialectName Bufferization = ident "Bufferization"
dialectName SCF = ident "SCF"
dialectName Transform = ident "Transform"

||| The dialects whose ops the specification admits from upstream: every one
||| but ours.
public export
upstreamDialects : List Dialect
upstreamDialects = [Builtin, Arith, Math, MemRef, Tensor, UB, Linalg, Bufferization, SCF, Transform]
