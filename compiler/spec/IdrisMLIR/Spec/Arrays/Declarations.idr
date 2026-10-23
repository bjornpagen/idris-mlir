-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the arrays declare: the generating set and its yield, a step's
||| movements on buffers, mutable memory and its accesses, the read that
||| gives a value array back, the copy that first writes a buffer allocated
||| for it, the extent of an array to be made and the tie of its dimensions;
||| the memory space of mutable memory; the two interfaces the generating
||| set and the update share; the two hand predicates their operands are
||| checked by; and the skeleton rules on two accesses of one element of
||| mutable memory: a read and a write its update, a read of a write the
||| value written, a write overwritten unread gone.
module IdrisMLIR.Spec.Arrays.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Arrays.Generating
import IdrisMLIR.Spec.Arrays.Memory

%default total

------------------------------------------------------------------------------
-- The upstream ops arrays admit
------------------------------------------------------------------------------

||| An upstream op whose record's name carries its dialect, its own alias.
admitNamed : Dialect -> Ident -> Legal -> Writer -> Admitted
admitNamed d r legal writer = MkAdmitted d r r legal writer [] [] Nothing UpstreamFold

||| An upstream op whose record's name does not carry its dialect: its
||| alias does.
admitAliased : Dialect -> Ident -> Ident -> Legal -> Writer -> Admitted
admitAliased d r alias legal writer = MkAdmitted d r alias legal writer [] [] Nothing UpstreamFold

||| The tensor ops the frontend writes on arrays as values, which passes
||| also write (columns, structured loops, bufferization's preparation):
||| until bufferization makes them buffers.
tensorAdmitted : List Admitted
tensorAdmitted = map (\r : Ident => admitNamed Tensor r (between Higher First) FrontendWrites)
  [ "Tensor_CastOp", "Tensor_DimOp", "Tensor_EmptyOp", "Tensor_ExtractOp"
  , "Tensor_ExtractSliceOp", "Tensor_FromElementsOp", "Tensor_InsertOp"
  , "Tensor_InsertSliceOp", "Tensor_ExpandShapeOp", "Tensor_CollapseShapeOp" ]

||| The crossings between a cell's buffer and an array value the frontend
||| writes, and the fresh array bufferization's preparation makes: until
||| bufferization, which removes them.
bufferizationAdmitted : List Admitted
bufferizationAdmitted =
  [ admitNamed Bufferization "Bufferization_ToTensorOp" (between Higher First) FrontendWrites
  , admitNamed Bufferization "Bufferization_ToBufferOp" (between Higher First) FrontendWrites
  , admitNamed Bufferization "Bufferization_AllocTensorOp" (between First First) PassesOnly ]

||| A buffer's size, which the frontend reads, and the buffers bufferization
||| allocates, copies, reads and writes, until the lowering.
memrefAdmitted : List Admitted
memrefAdmitted =
  [ admitNamed MemRef "MemRef_DimOp" (between Higher Owned) FrontendWrites
  , admitNamed MemRef "MemRef_AllocOp" (between First Owned) PassesOnly
  , admitAliased MemRef "CopyOp" "MemRef_CopyOp" (between First Owned) PassesOnly
  , admitAliased MemRef "LoadOp" "MemRef_LoadOp" (between First Owned) PassesOnly
  , admitNamed MemRef "MemRef_StoreOp" (between First Owned) PassesOnly ]

||| The transpose the frontend writes, and the parallel ops structured loops
||| make of word ops, on tensors and then on buffers, until the lowering.
||| The yield ends the body of each: the transpose's body too, which the
||| frontend builds, so it enters with the transpose.
linalgAdmitted : List Admitted
linalgAdmitted =
  [ admitAliased Linalg "TransposeOp" "Linalg_TransposeOp" (between Higher Owned) FrontendWrites
  , admitAliased Linalg "GenericOp" "Linalg_GenericOp" (between First Owned) PassesOnly
  , admitNamed Linalg "Linalg_IndexOp" (between First Owned) PassesOnly
  , admitNamed Linalg "Linalg_YieldOp" (between Higher Owned) FrontendWrites ]

||| The loops arrays' passes make and read: `scf.for`, which structured
||| loops writes and the ordered loops after narrowing write again, until
||| the lowering; `scf.while` and its condition, which narrowing reads and
||| versions where the program's own loops stand once counted.
scfAdmitted : List Admitted
scfAdmitted =
  [ admitAliased SCF "ForOp" "SCF_ForOp" (between First Owned) PassesOnly
  , admitAliased SCF "WhileOp" "SCF_WhileOp" (between Owned Owned) PassesOnly
  , admitAliased SCF "ConditionOp" "SCF_ConditionOp" (between Owned Owned) PassesOnly ]

public export
declarations : Declarations
declarations = MkDeclarations
  { ops = generatingOps ++ memoryOps
  , types = []
  , attributes = [SomeAttr mutableAttr]
  , enums = []
  , tables = []
  , interfaces = generatingInterfacesDeclared
  , traits = []
  , directives = []
  , predicates = [valueBuffer, mutableArray]
  , resources = []
  , helpers = []
  , admitted = tensorAdmitted ++ bufferizationAdmitted ++ memrefAdmitted ++ linalgAdmitted
                 ++ scfAdmitted
  , rewrites = []
  , skeleton = memorySkeleton
  , headers = []
  }
