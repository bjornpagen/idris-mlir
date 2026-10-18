// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The in-process part of a compilation, from a module to the objects of
// its bins: the refusals a module of the frontend's holds, re-emitted; a
// handoff module through the idr pipeline in one pass manager and then
// LLVM, the pipeline's output through LLVM alone; and what the compiler
// registers for it, which is what it runs and nothing else.

#include "idr/Conversion/Runtime.h"
#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Compile.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Runtime.h"
#include "idr/Driver/Verdict.h"
#include "idr/IR/IdrDialect.h"
#include "idr/InitIdr.h"
#include "idr/Support/Profile.h"
#include "idr/Target/Target.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Conversion/ArithToLLVM/ArithToLLVM.h"
#include "mlir/Conversion/ControlFlowToLLVM/ControlFlowToLLVM.h"
#include "mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h"
#include "mlir/Conversion/IndexToLLVM/IndexToLLVM.h"
#include "mlir/Conversion/MathToLLVM/MathToLLVM.h"
#include "mlir/Conversion/MemRefToLLVM/MemRefToLLVM.h"
#include "mlir/Conversion/Passes.h"
#include "mlir/Conversion/UBToLLVM/UBToLLVM.h"
#include "mlir/Conversion/VectorToLLVM/ConvertVectorToLLVM.h"
#include "mlir/Debug/BreakpointManagers/TagBreakpointManager.h"
#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Affine/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Arith/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Arith/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/DLTI/DLTI.h"
#include "mlir/Dialect/Func/Extensions/InlinerExtension.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/Transforms/InlinerInterfaceImpl.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Linalg/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Linalg/Passes.h"
#include "mlir/Dialect/Linalg/TransformOps/DialectExtension.h"
#include "mlir/Dialect/Linalg/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Linalg/Transforms/SubsetInsertionOpInterfaceImpl.h"
#include "mlir/Dialect/Linalg/Transforms/TilingInterfaceImpl.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/MemRef/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/MemRef/Transforms/Passes.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/Tensor/IR/TensorInferTypeOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/Transforms/BufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Tensor/Transforms/SubsetInsertionOpInterfaceImpl.h"
#include "mlir/Dialect/Transform/IR/TransformDialect.h"
#include "mlir/Dialect/Transform/Transforms/Passes.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Dialect/Vector/IR/ValueBoundsOpInterfaceImpl.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/Dialect/Vector/TransformOps/VectorTransformOps.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/CastInterfaces.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Support/Timing.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Export.h"
#include "mlir/Transforms/Passes.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/ThreadPool.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Triple.h"
#include "llvm/Transforms/IPO/Internalize.h"

#include <memory>
#include <string>
#include <variant>

using namespace idr::driver;

namespace {

// The dialects a handoff module is written in, as the frontend writes one,
// with their flow models: what a module that holds an idr.program may hold
// (moduleKindOf), and the first part of what the compiler registers.
void registerHandoff(mlir::DialectRegistry &registry) {
  idr::registerIdrDialects(registry);
  registry.insert<mlir::arith::ArithDialect, mlir::math::MathDialect, mlir::ub::UBDialect,
                  mlir::memref::MemRefDialect, mlir::tensor::TensorDialect,
                  mlir::scf::SCFDialect>();
}

// What a module is, by what it holds, never by an option: the frontend's, a
// handoff module, which holds an idr.program and goes through the pipeline
// and then LLVM; or the pipeline's output, the LLVM dialect alone, which
// goes to LLVM as it is, compiled for the target it names, which a module
// of it must name for the build's triple.
struct Handoff {};
struct Lowered {
  mlir::LLVM::TargetAttr target;
};

// The module's kind: an idr.program among its ops makes it a handoff
// module, whose every op must be of a dialect the frontend writes;
// otherwise every op must be the LLVM dialect's, and the module must name
// its target for the build's triple. An error at the first op that is not,
// naming it (idris-mlir prints no op on a diagnostic), or at the module
// that names no such target: a module half lowered (an arith op in an
// llvm.func) is neither kind, and LLVM's translation would fail on it with
// no word of why.
mlir::FailureOr<std::variant<Handoff, Lowered>>
moduleKindOf(mlir::ModuleOp module, const mlir::DialectRegistry &handoff) {
  auto written = [&](mlir::Operation *op) {
    return static_cast<bool>(handoff.getDialectAllocator(op->getName().getDialectNamespace()));
  };
  auto lowered = [](mlir::Operation *op) {
    return mlir::isa<mlir::LLVM::LLVMDialect>(op->getDialect());
  };
  // The ops a module of its kind holds, and what an op it may not hold is
  // said to be.
  struct Holds {
    llvm::function_ref<bool(mlir::Operation *)> op;
    llvm::StringLiteral otherwise;
  };
  bool handsOff = !module.getOps<idr::ProgramOp>().empty();
  const Holds holds =
      handsOff ? Holds{written, "is of no dialect the frontend writes, in a module that holds an "
                                "idr.program"}
               : Holds{lowered, "is no op of the LLVM dialect, in a module that holds no "
                                "idr.program: such a module is the pipeline's output"};
  mlir::WalkResult walked =
      module.getBody()->walk<mlir::WalkOrder::PreOrder>([&](mlir::Operation *op) {
        if (holds.op(op))
          return mlir::WalkResult::advance();
        op->emitOpError(holds.otherwise);
        return mlir::WalkResult::interrupt();
      });
  if (walked.wasInterrupted())
    return mlir::failure();
  if (handsOff)
    return std::variant<Handoff, Lowered>(Handoff{});
  auto target = module->getAttrOfType<mlir::LLVM::TargetAttr>(
      mlir::LLVM::LLVMDialect::getTargetAttrName());
  if (!target)
    return module.emitError()
           << "names no target (#llvm.target): a module of the LLVM dialect alone, the "
              "pipeline's output, is compiled for the target it names";
  // The runtime it is linked with and every link are for the build's
  // triple; a module lowered for another cannot join them.
  if (target.getTriple().getValue() != targetTriple)
    return module.emitError() << "is compiled for " << target.getTriple().getValue()
                              << ", and idris-mlir for " << targetTriple;
  return std::variant<Handoff, Lowered>(Lowered{target});
}

// The pipeline, idr-target first, in one manager, so that what a pass
// preserves the next one finds. --stats, LLVM's own option, prints its
// statistics too; MLIR's own pass-manager options (IR printing, the module
// after each pass with -mlir-print-ir-tree-dir, crash reproducers,
// -mlir-pass-statistics) apply to it, which the command line's reading
// has checked they can. The report's instrumentation reads each pass's
// statistics around each of its runs, before MLIR merges the copies'
// statistics to print them. The timer is added last: the instrumentations
// unwind in reverse, so it stops before IR is printed, and a pass's row is
// the pass's own time. The manager goes, and prints its statistics, before
// LLVM starts.
mlir::LogicalResult runPipeline(mlir::ModuleOp module, Outcome &outcome,
                                mlir::TimingScope &rootTiming) {
  mlir::PassManager pm(module.getContext());
  if (llvm::AreStatisticsEnabled())
    pm.enableStatistics(mlir::PassDisplayMode::List);
  mlir::LogicalResult ran = mlir::applyPassManagerCLOptions(pm);
  if (mlir::succeeded(ran)) {
    idr::profile::addInstrumentation(pm);
    pm.addInstrumentation(foldStatistics(outcome));
    pm.enableTiming(rootTiming);
    // The module's target, which every pass reads: idr-entry tells the
    // runtime's entry which of its features to test; the object code is
    // compiled for it.
    pm.addPass(idr::createIdrTarget());
    idr::buildPipeline(pm);
    ran = pm.run(module);
  }
  // Any error stops the compilation, whether or not what reported it
  // failed: an error from a pass that then goes on is an error all the
  // same. A failure that reported none is the compiler's, said here, the
  // one place a pipeline's failure can come without its error.
  if (outcome.verdict() != Verdict::Accepted)
    return mlir::failure();
  if (mlir::failed(ran))
    return mlir::emitError(mlir::UnknownLoc::get(module.getContext()))
           << "the pipeline failed and reported no error";
  return mlir::success();
}

// LLVM IR, joined with the runtime into one module; every symbol but the
// process entry internalized; LLVM's O3 pipeline once, on the whole
// program; then the optimized module cut into bins, each compiled to
// object code for the module's target on `pool`. Each stage has a timer of
// its own, so -mlir-timing says which one a compilation spends its time on.
mlir::LogicalResult toObjects(mlir::ModuleOp module, mlir::LLVM::TargetAttr moduleTarget,
                              llvm::StringRef runtime, Artifacts &artifacts,
                              const llvm::Target &target, const llvm::Triple &triple,
                              llvm::ThreadPoolInterface &pool, mlir::TimingScope &rootTiming) {
  mlir::MLIRContext &context = *module.getContext();
  mlir::Location unknown = mlir::UnknownLoc::get(&context);
  mlir::TimingScope llvmTiming = rootTiming.nest("LLVM");
  std::string features =
      moduleTarget.getFeatures() ? moduleTarget.getFeatures().getFeaturesString() : "";
  llvm::StringRef cpu = moduleTarget.getChip().getValue();
  llvm::Expected<std::unique_ptr<llvm::TargetMachine>> made =
      idr::target::machine(target, triple, cpu, features);
  if (!made)
    return mlir::emitError(unknown) << llvm::toString(made.takeError());
  llvm::TargetMachine &machine = **made;
  llvm::LLVMContext llvmContext;
  std::unique_ptr<llvm::Module> llvmModule;
  {
    IDR_ZONE_IN("translate", LLVM);
    mlir::TimingScope stage = llvmTiming.nest("translate");
    llvmModule = mlir::translateModuleToLLVMIR(module, llvmContext);
    if (!llvmModule)
      return mlir::emitError(unknown) << "translation to LLVM IR failed";
    llvmModule->setTargetTriple(triple);
    llvmModule->setDataLayout(machine.createDataLayout());
    // Every target's executables are position-independent.
    llvmModule->setPICLevel(llvm::PICLevel::BigPIC);
    llvmModule->setPIELevel(llvm::PIELevel::Large);
  }
  {
    IDR_ZONE_IN("link runtime", LLVM);
    mlir::TimingScope stage = llvmTiming.nest("link runtime");
    if (mlir::failed(linkRuntime(*llvmModule, module, runtime, target, triple, machine)))
      return mlir::failure();
    // The program is whole, so nothing but the process entry the lowering
    // makes is visible outside it; O3 then removes what the entry does not
    // reach. The runtime's available_externally bodies stay as they are: a
    // declaration with a body.
    llvm::internalizeModule(*llvmModule, [](const llvm::GlobalValue &value) {
      return value.getName() == idr::conversion::entrySymbol;
    });
  }
  {
    IDR_ZONE_IN("optimize", LLVM);
    mlir::TimingScope stage = llvmTiming.nest("optimize");
    idr::target::optimize(*llvmModule, machine);
  }
  // After O3 code generation is local to each function, so the bins are
  // compiled at once; how many there are follows from the module's size,
  // never from the pool's.
  IDR_ZONE_IN("codegen", LLVM);
  mlir::TimingScope stage = llvmTiming.nest("codegen");
  return writeObjects(*llvmModule, target, triple, cpu, features, pool, artifacts, context);
}

// The refusals the frontend left in the module in place of a program, in
// the dialect's discardable attribute (IdrBase.td's `refusals`): an array of
// #idr.refusal, one per refusal, in the order found. Each is emitted as the
// driver's diagnostic, its rule as data: the driver is their one printer,
// and foldDiagnostics their one fold into the verdict.
void reemitRefusals(mlir::ModuleOp module) {
  auto *dialect = module->getContext()->getOrLoadDialect<idr::IdrDialect>();
  mlir::ArrayAttr refusals = dialect->getRefusalsAttrHelper().getAttr(module);
  // A module the frontend could compile holds a program and no refusal.
  if (!refusals)
    return;
  for (idr::RefusalAttr refusal : refusals.getAsRange<idr::RefusalAttr>())
    idr::refuse(refusal.getLoc(), refusal.getRule()) << refusal.getMessage();
}

} // namespace

void idr::driver::registerCompiler(mlir::DialectRegistry &registry) {
  // The transform ops the schedule library is written in, before the
  // library (registerIdrDialects): an extension applies in the order it was
  // added, and the library's own extension parses it.
  mlir::linalg::registerTransformDialectExtension(registry);
  mlir::vector::registerTransformDialectExtension(registry);
  registerHandoff(registry);
  // The pipeline's output's, and the dialects its passes load.
  registry.insert<mlir::LLVM::LLVMDialect, mlir::DLTIDialect, mlir::func::FuncDialect,
                  mlir::cf::ControlFlowDialect, mlir::linalg::LinalgDialect,
                  mlir::bufferization::BufferizationDialect, mlir::affine::AffineDialect,
                  mlir::vector::VectorDialect, mlir::transform::TransformDialect>();
  // The models of them the passes read. idr-bufferize's One-Shot asks each
  // op on tensors for its bufferization, and its empty-tensor elimination
  // asks an insertion for its subset; the narrowing, the loop structuring
  // and upstream's folds and tiling ask an op for its value bounds;
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
  // each that promises them: those the pipeline lowers, and index, which
  // the schedule's linalg transform ops load.
  mlir::arith::registerConvertArithToLLVMInterface(registry);
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
  // Each upstream pass the pipeline adds (buildPipeline).
  mlir::registerCSEPass();
  mlir::registerRemoveDeadValuesPass();
  mlir::registerSymbolDCEPass();
  mlir::transform::registerInterpreterPass();
  mlir::registerConvertLinalgToLoopsPass();
  mlir::registerConvertVectorToSCF();
  mlir::memref::registerExpandStridedMetadataPass();
  mlir::registerLowerAffinePass();
  mlir::registerSCFToControlFlowPass();
  mlir::registerConvertVectorToLLVMPass();
  mlir::registerConvertToLLVMPass();
  mlir::registerReconcileUnrealizedCastsPass();
}

mlir::FailureOr<const llvm::Target *> idr::driver::nativeTarget(const llvm::Triple &triple,
                                                                mlir::MLIRContext &context) {
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  // The runtime linked into the program carries inline assembly.
  llvm::InitializeNativeTargetAsmParser();
  std::string error;
  if (const llvm::Target *target = llvm::TargetRegistry::lookupTarget(triple, error))
    return target;
  return mlir::emitError(mlir::UnknownLoc::get(&context)) << error;
}

mlir::LogicalResult idr::driver::run(int made, const Compile &invocation, Artifacts &artifacts,
                                     mlir::MLIRContext &context, llvm::SourceMgr &sources,
                                     llvm::ThreadPoolInterface &pool,
                                     mlir::TimingScope &rootTiming, Outcome &outcome) {
  llvm::Triple triple(targetTriple);
  mlir::FailureOr<const llvm::Target *> target = nativeTarget(triple, context);
  if (mlir::failed(target))
    return mlir::failure();
  // -mlir-timing, MLIR's own option, times the parse (with the verification
  // that follows it), each pass and LLVM's stages, under the compilation's
  // root.
  mlir::OwningOpRef<mlir::ModuleOp> module;
  {
    IDR_ZONE_IN("parse", Parse);
    mlir::TimingScope parseTiming = rootTiming.nest("parse");
    module = mlir::parseSourceFile<mlir::ModuleOp>(artifacts.modulePath(), sources, &context);
  }
  // The parser and the verifier, some of whose rules are the user's (a type
  // that can reach itself through an array), have said why.
  if (!module)
    return mlir::failure();
  reemitRefusals(*module);
  if (outcome.verdict() != Verdict::Accepted)
    return mlir::failure();
  // A frontend that failed and found nothing of the program's to refuse is
  // the compiler's.
  if (made != ok)
    return mlir::emitError(mlir::UnknownLoc::get(&context))
           << "the frontend exited with status " << made << ", and its module holds no refusal";
  mlir::DialectRegistry handoff;
  registerHandoff(handoff);
  mlir::FailureOr<std::variant<Handoff, Lowered>> kind = moduleKindOf(*module, handoff);
  if (mlir::failed(kind))
    return mlir::failure();

  // MLIR's action handler: -log-actions-to and -profile-actions-to, which
  // --log-actions-tags narrows. With no tag given every action is logged,
  // which an empty filter would not do.
  mlir::tracing::DebugConfig debugConfig = mlir::tracing::DebugConfig::createFromCLOptions();
  mlir::tracing::TagBreakpointManager loggedTags;
  for (const std::string &tag : invocation.tags)
    loggedTags.addBreakpoint(tag);
  if (!invocation.tags.empty())
    debugConfig.addLogActionLocFilter(&loggedTags);
  mlir::tracing::InstallDebugHandler debugHandler(context, debugConfig);

  // The target the module is compiled for: a lowered module's own, a handoff
  // module's as idr-target, the pipeline's first pass, wrote it.
  mlir::FailureOr<mlir::LLVM::TargetAttr> moduleTarget = std::visit(
      llvm::makeVisitor(
          [&](Handoff) -> mlir::FailureOr<mlir::LLVM::TargetAttr> {
            if (mlir::failed(runPipeline(*module, outcome, rootTiming)))
              return mlir::failure();
            return llvm::cast<mlir::LLVM::TargetAttr>(
                (*module)->getAttr(mlir::LLVM::LLVMDialect::getTargetAttrName()));
          },
          [](const Lowered &lowered) -> mlir::FailureOr<mlir::LLVM::TargetAttr> {
            return lowered.target;
          }),
      *kind);
  if (mlir::failed(moduleTarget))
    return mlir::failure();
  return toObjects(*module, *moduleTarget, invocation.runtime, artifacts, **target, triple, pool,
                   rootTiming);
}
