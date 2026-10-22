-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The upstream ODS the dialect is written in, as closed sets: each name a
||| case, its record and the file that defines it facts of the case, so a
||| name is spelled once and a misspelt one is no Idris value. Only what the
||| dialect uses; a construct the dialect needs and this lacks is added here
||| first, as a case with its facts.
module IdrisMLIR.Spec.Core.Upstream

import IdrisMLIR.Spec.Core.Text

%default total

------------------------------------------------------------------------------
-- Builtin types an operand, result or parameter may be
------------------------------------------------------------------------------

||| The builtin and upstream type constraints the dialect names.
public export
data UpType
  = AnyTypeC
  | I1C
  | I8C
  | I16C
  | I32C
  | I64C
  | IndexC
  | F64C
  | AnySignlessIntegerC
  | AnySignlessIntegerOrIndexC
  | AnyFloatC
  | AnyMemRefC
  | AnyRankedOrUnrankedMemRefC
  | AnyRankedTensorC
  | AnyTensorC
  | AnyShapedC
  | NoneTypeC
  | TransformHandleC
  | TransformParamC
  | TokenC
  | FunctionTypeC

public export
upTypeRecord : UpType -> Ident
upTypeRecord AnyTypeC = ident "AnyType"
upTypeRecord I1C = ident "I1"
upTypeRecord I8C = ident "I8"
upTypeRecord I16C = ident "I16"
upTypeRecord I32C = ident "I32"
upTypeRecord I64C = ident "I64"
upTypeRecord IndexC = ident "Index"
upTypeRecord F64C = ident "F64"
upTypeRecord AnySignlessIntegerC = ident "AnySignlessInteger"
upTypeRecord AnySignlessIntegerOrIndexC = ident "AnySignlessIntegerOrIndex"
upTypeRecord AnyFloatC = ident "AnyFloat"
upTypeRecord AnyMemRefC = ident "AnyMemRef"
upTypeRecord AnyRankedOrUnrankedMemRefC = ident "AnyRankedOrUnrankedMemRef"
upTypeRecord AnyRankedTensorC = ident "AnyRankedTensor"
upTypeRecord AnyTensorC = ident "AnyTensor"
upTypeRecord AnyShapedC = ident "AnyShaped"
upTypeRecord NoneTypeC = ident "NoneType"
upTypeRecord TransformHandleC = ident "TransformHandleTypeInterface"
upTypeRecord TransformParamC = ident "TransformParamTypeInterface"
upTypeRecord TokenC = ident "Token"
upTypeRecord FunctionTypeC = ident "FunctionType"

------------------------------------------------------------------------------
-- Builtin attributes an inherent attribute may be
------------------------------------------------------------------------------

public export
data UpAttr
  = StrAttrC
  | SymbolNameAttrC
  | FlatSymbolRefAttrC
  | SymbolRefAttrC
  | I32AttrC
  | I64AttrC
  | IndexAttrC
  | APIntAttrC
  | F64AttrC
  | TypeAttrC
  | ArrayAttrC
  | DictionaryAttrC
  | DenseI32ArrayAttrC
  | DenseI64ArrayAttrC
  | AnyAttrC
  | TypedAttrC
  | DictArrayAttrC

public export
upAttrRecord : UpAttr -> Ident
upAttrRecord StrAttrC = ident "StrAttr"
upAttrRecord SymbolNameAttrC = ident "SymbolNameAttr"
upAttrRecord FlatSymbolRefAttrC = ident "FlatSymbolRefAttr"
upAttrRecord SymbolRefAttrC = ident "SymbolRefAttr"
upAttrRecord I32AttrC = ident "I32Attr"
upAttrRecord I64AttrC = ident "I64Attr"
upAttrRecord IndexAttrC = ident "IndexAttr"
upAttrRecord APIntAttrC = ident "APIntAttr"
upAttrRecord F64AttrC = ident "F64Attr"
upAttrRecord TypeAttrC = ident "TypeAttr"
upAttrRecord ArrayAttrC = ident "ArrayAttr"
upAttrRecord DictionaryAttrC = ident "DictionaryAttr"
upAttrRecord DenseI32ArrayAttrC = ident "DenseI32ArrayAttr"
upAttrRecord DenseI64ArrayAttrC = ident "DenseI64ArrayAttr"
upAttrRecord AnyAttrC = ident "AnyAttr"
upAttrRecord TypedAttrC = ident "TypedAttrInterface"
upAttrRecord DictArrayAttrC = ident "DictArrayAttr"

||| Upstream's attribute constraints that confine another (`ConfinedAttr`).
public export
data UpConfinement
  = NonNegativeArray
  | StrictlySortedArray
  | IntNonNegative

public export
confinementRecord : UpConfinement -> String
confinementRecord NonNegativeArray = "DenseArrayNonNegative<DenseI32ArrayAttr>"
confinementRecord StrictlySortedArray = "DenseArrayStrictlySorted<DenseI32ArrayAttr>"
confinementRecord IntNonNegative = "IntNonNegative"

------------------------------------------------------------------------------
-- Interfaces
------------------------------------------------------------------------------

||| Upstream's op, type and attribute interfaces the dialect implements, and
||| the ODS file that defines each.
public export
data UpInterface
  = BytecodeOp
  | CallOp
  | Callable
  | FunctionOp
  | SymbolUser
  | RegionBranch
  | RegionBranchTerminator
  | HasBreakingControlFlow
  | RegionExitTerminator
  | LoopLike
  | InferType
  | InferIntRange
  | MemoryEffects
  | Speculatable
  | OpAsm
  | OpAsmType
  | DestinationStyle
  | Tiling
  | ViewLike
  | ReifyRankedShapedType
  | ValueBounds
  | TransformOp
  | TransformEffects
  | ShapedType
  | TensorLike
  | BufferLike
  | MemRefElementType
  | TypedAttr

public export
upInterfaceRecord : UpInterface -> Ident
upInterfaceRecord BytecodeOp = ident "BytecodeOpInterface"
upInterfaceRecord CallOp = ident "CallOpInterface"
upInterfaceRecord Callable = ident "CallableOpInterface"
upInterfaceRecord FunctionOp = ident "FunctionOpInterface"
upInterfaceRecord SymbolUser = ident "SymbolUserOpInterface"
upInterfaceRecord RegionBranch = ident "RegionBranchOpInterface"
upInterfaceRecord RegionBranchTerminator = ident "RegionBranchTerminatorOpInterface"
upInterfaceRecord HasBreakingControlFlow = ident "HasBreakingControlFlowOpInterface"
upInterfaceRecord RegionExitTerminator = ident "RegionExitTerminatorOpInterface"
upInterfaceRecord LoopLike = ident "LoopLikeOpInterface"
upInterfaceRecord InferType = ident "InferTypeOpInterface"
upInterfaceRecord InferIntRange = ident "InferIntRangeInterface"
upInterfaceRecord MemoryEffects = ident "MemoryEffectsOpInterface"
upInterfaceRecord Speculatable = ident "ConditionallySpeculatable"
upInterfaceRecord OpAsm = ident "OpAsmOpInterface"
upInterfaceRecord OpAsmType = ident "OpAsmTypeInterface"
upInterfaceRecord DestinationStyle = ident "DestinationStyleOpInterface"
upInterfaceRecord Tiling = ident "TilingInterface"
upInterfaceRecord ViewLike = ident "ViewLikeOpInterface"
upInterfaceRecord ReifyRankedShapedType = ident "ReifyRankedShapedTypeOpInterface"
upInterfaceRecord ValueBounds = ident "ValueBoundsOpInterface"
upInterfaceRecord TransformOp = ident "TransformOpInterface"
upInterfaceRecord TransformEffects = ident "MemoryEffectsOpInterface"
upInterfaceRecord ShapedType = ident "ShapedTypeInterface"
upInterfaceRecord TensorLike = ident "TensorLikeTypeInterface"
upInterfaceRecord BufferLike = ident "BufferLikeTypeInterface"
upInterfaceRecord MemRefElementType = ident "MemRefElementTypeInterface"
upInterfaceRecord TypedAttr = ident "TypedAttrInterface"

||| The upstream ODS file that defines each interface, which a printed file
||| that names it includes.
public export
upInterfaceInclude : UpInterface -> String
upInterfaceInclude BytecodeOp = "mlir/Bytecode/BytecodeOpInterface.td"
upInterfaceInclude CallOp = "mlir/Interfaces/CallInterfaces.td"
upInterfaceInclude Callable = "mlir/Interfaces/CallInterfaces.td"
upInterfaceInclude FunctionOp = "mlir/Interfaces/FunctionInterfaces.td"
upInterfaceInclude SymbolUser = "mlir/IR/SymbolInterfaces.td"
upInterfaceInclude RegionBranch = "mlir/Interfaces/ControlFlowInterfaces.td"
upInterfaceInclude RegionBranchTerminator = "mlir/Interfaces/ControlFlowInterfaces.td"
upInterfaceInclude HasBreakingControlFlow = "mlir/Interfaces/ControlFlowInterfaces.td"
upInterfaceInclude RegionExitTerminator = "mlir/Interfaces/ControlFlowInterfaces.td"
upInterfaceInclude LoopLike = "mlir/Interfaces/LoopLikeInterface.td"
upInterfaceInclude InferType = "mlir/Interfaces/InferTypeOpInterface.td"
upInterfaceInclude InferIntRange = "mlir/Interfaces/InferIntRangeInterface.td"
upInterfaceInclude MemoryEffects = "mlir/Interfaces/SideEffectInterfaces.td"
upInterfaceInclude Speculatable = "mlir/Interfaces/SideEffectInterfaces.td"
upInterfaceInclude OpAsm = "mlir/IR/OpAsmInterface.td"
upInterfaceInclude OpAsmType = "mlir/IR/OpAsmInterface.td"
upInterfaceInclude DestinationStyle = "mlir/Interfaces/DestinationStyleOpInterface.td"
upInterfaceInclude Tiling = "mlir/Interfaces/TilingInterface.td"
upInterfaceInclude ViewLike = "mlir/Interfaces/ViewLikeInterface.td"
upInterfaceInclude ReifyRankedShapedType = "mlir/Interfaces/InferTypeOpInterface.td"
upInterfaceInclude ValueBounds = "mlir/Interfaces/ValueBoundsOpInterface.td"
upInterfaceInclude TransformOp = "mlir/Dialect/Transform/Interfaces/TransformInterfaces.td"
upInterfaceInclude TransformEffects = "mlir/Dialect/Transform/Interfaces/TransformInterfaces.td"
upInterfaceInclude ShapedType = "mlir/IR/BuiltinTypeInterfaces.td"
upInterfaceInclude TensorLike = "mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.td"
upInterfaceInclude BufferLike = "mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.td"
upInterfaceInclude MemRefElementType = "mlir/IR/BuiltinTypeInterfaces.td"
upInterfaceInclude TypedAttr = "mlir/IR/BuiltinAttributeInterfaces.td"

||| Every upstream ODS file a printed op file includes: the base classes,
||| and each interface's file is added by what names it.
public export
odsBaseIncludes : List String
odsBaseIncludes =
  [ "mlir/IR/OpBase.td"
  , "mlir/IR/AttrTypeBase.td"
  , "mlir/IR/EnumAttr.td"
  , "mlir/IR/Properties.td"
  , "mlir/IR/SymbolInterfaces.td"
  , "mlir/IR/BuiltinAttributes.td"
  , "mlir/IR/BuiltinTypeInterfaces.td"
  , "mlir/IR/OpAsmInterface.td"
  , "mlir/Interfaces/SideEffectInterfaces.td"
  , "mlir/Interfaces/ControlFlowInterfaces.td"
  ]
