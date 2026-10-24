// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the compiler registers, which is what it runs and nothing else:
// the dialects a handoff module is written in, the pipeline's and its
// output's, the models of them its passes read, the translations to LLVM
// IR, and the passes the pipeline adds.

#include "idr/Driver/Compile.h"
#include "idr/IR/Generated/WrittenDialects.h.inc"
#include "idr/InitIdr.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Conversion/ArithToLLVM/ArithToLLVM.h"
#include "mlir/Conversion/ComplexToLLVM/ComplexToLLVM.h"
#include "mlir/Conversion/ControlFlowToLLVM/ControlFlowToLLVM.h"
#include "mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h"
#include "mlir/Conversion/IndexToLLVM/IndexToLLVM.h"
#include "mlir/Conversion/MathToLLVM/MathToLLVM.h"
#include "mlir/Conversion/MemRefToLLVM/MemRefToLLVM.h"
#include "mlir/Conversion/UBToLLVM/UBToLLVM.h"
#include "mlir/Conversion/VectorToLLVM/ConvertVectorToLLVM.h"
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Affine/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Arith/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Arith/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/DLTI/DLTI.h"
#include "mlir/Dialect/Func/Extensions/InlinerExtension.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/Transforms/InlinerInterfaceImpl.h"
#include "mlir/Dialect/Linalg/IR/InferIntRangeInterfaceImpl.h"
#include "mlir/Dialect/Linalg/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Linalg/TransformOps/DialectExtension.h"
#include "mlir/Dialect/Linalg/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Linalg/Transforms/SubsetInsertionOpInterfaceImpl.h"
#include "mlir/Dialect/Linalg/Transforms/TilingInterfaceImpl.h"
#include "mlir/Dialect/MemRef/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/SCF/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/IR/TensorInferTypeOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/Transforms/SubsetInsertionOpInterfaceImpl.h"
#include "mlir/Dialect/Transform/IR/TransformDialect.h"
#include "mlir/Dialect/Vector/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/Dialect/Vector/TransformOps/VectorTransformOps.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/Interfaces/CastInterfaces.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"

#include <concepts>

namespace {

// Each dialect of the list, registered.
template <std::derived_from<mlir::Dialect>... Dialects>
void insertAll(mlir::DialectRegistry &registry, idr::DialectList<Dialects...>) {
  registry.insert<Dialects...>();
}

} // namespace

void idr::driver::registerCompiler(mlir::DialectRegistry &registry) {
  // The transform ops the schedule library is written in, before the
  // library (registerIdrDialects): an extension applies in the order it was
  // added, and the library's own extension builds it of them.
  mlir::linalg::registerTransformDialectExtension(registry);
  mlir::vector::registerTransformDialectExtension(registry);
  // The dialects a handoff module is written in, as the frontend writes
  // one: ours, with the flow models of the upstream ops it holds, and the
  // upstream dialects the frontend writes an op of, the specification's
  // list, by which run tells a module's ops too.
  idr::registerIdrDialects(registry);
  insertAll(registry, idr::WrittenDialects{});
  // The pipeline's output's, and the dialects its passes load.
  registry.insert<mlir::LLVM::LLVMDialect, mlir::DLTIDialect, mlir::func::FuncDialect,
                  mlir::cf::ControlFlowDialect, mlir::affine::AffineDialect,
                  mlir::vector::VectorDialect, mlir::transform::TransformDialect>();
  // The models of them the passes read. idr-bufferize's One-Shot asks each
  // op on tensors for its bufferization, and its empty-tensor elimination
  // asks an insertion for its subset; the narrowing, the loop structuring
  // and upstream's folds and tiling ask an op for its value bounds, and the
  // narrowing's range analysis asks a loop's index for its range;
  // bufferization asks a tensor op for its shape; the schedule tiles a loop
  // by its tiling interface; and the vectorizer and bufferization ask an op
  // whether it is a cast.
  mlir::arith::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::bufferization::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::linalg::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::scf::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::tensor::registerBufferizableOpInterfaceExternalModels(registry);
  mlir::linalg::registerSubsetOpInterfaceExternalModels(registry);
  mlir::tensor::registerSubsetOpInterfaceExternalModels(registry);
  mlir::linalg::registerInferIntRangeInterfaceExternalModels(registry);
  mlir::affine::registerValueBoundsOpInterfaceExternalModels(registry);
  mlir::arith::registerValueBoundsOpInterfaceExternalModels(registry);
  mlir::bufferization::registerValueBoundsOpInterfaceExternalModels(registry);
  mlir::linalg::registerValueBoundsOpInterfaceExternalModels(registry);
  mlir::memref::registerValueBoundsOpInterfaceExternalModels(registry);
  mlir::scf::registerValueBoundsOpInterfaceExternalModels(registry);
  mlir::tensor::registerValueBoundsOpInterfaceExternalModels(registry);
  mlir::vector::registerValueBoundsOpInterfaceExternalModels(registry);
  mlir::tensor::registerInferTypeOpInterfaceExternalModels(registry);
  mlir::linalg::registerTilingInterfaceExternalModels(registry);
  mlir::builtin::registerCastOpInterfaceExternalModels(registry);
  // Every inliner the optimizer makes asks each loaded dialect for its
  // inliner interface, which func and LLVM promise.
  mlir::func::registerInlinerExtension(registry);
  mlir::LLVM::registerInlinerInterface(registry);
  // convert-to-llvm takes the patterns of every loaded dialect, and asks
  // each that promises them: those the pipeline lowers, index, which the
  // schedule's linalg transform ops load, and complex, which tensor loads.
  mlir::arith::registerConvertArithToLLVMInterface(registry);
  mlir::registerConvertComplexToLLVMInterface(registry);
  mlir::cf::registerConvertControlFlowToLLVMInterface(registry);
  mlir::registerConvertFuncToLLVMInterface(registry);
  mlir::index::registerConvertIndexToLLVMInterface(registry);
  mlir::registerConvertMathToLLVMInterface(registry);
  mlir::registerConvertMemRefToLLVMInterface(registry);
  mlir::ub::registerConvertUBToLLVMInterface(registry);
  mlir::vector::registerConvertVectorToLLVMInterface(registry);
  // The module's translation to LLVM IR.
  mlir::registerBuiltinDialectTranslation(registry);
  mlir::registerLLVMDialectTranslation(registry);
}

void idr::driver::registerCompilerPasses() {
  idr::registerIdrPasses();
  idr::registerUpstreamPasses();
}
