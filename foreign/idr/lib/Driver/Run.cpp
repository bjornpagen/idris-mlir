// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The in-process part of a compilation, from a module to the objects of
// its bins: the refusals a module of the frontend's holds, re-emitted; a
// handoff module through the idr pipeline in one pass manager and then
// LLVM, the pipeline's output through LLVM alone. What the compiler
// registers for it is Register.cpp's.

#include "idr/Conversion/Runtime.h"
#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Compile.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Runtime.h"
#include "idr/Driver/Verdict.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Profile.h"
#include "idr/Target/Target.h"
#include "idr/Transforms/Contracts.h"
#include "idr/Transforms/Expect.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Debug/BreakpointManagers/TagBreakpointManager.h"
#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Support/Timing.h"
#include "mlir/Target/LLVMIR/Export.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
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

#include <cstdint>
#include <memory>
#include <string>
#include <variant>

using namespace idr::driver;

namespace {

// What a module is, by what it holds, never by an option: the frontend's, a
// handoff module, which holds an idr.program and goes through the pipeline
// and then LLVM; or the pipeline's output, the LLVM dialect alone, which
// goes to LLVM as it is, compiled for the target it names, which a module
// of it must name: the build's, the one target idris-mlir compiles for.
struct Handoff {};
struct Lowered {};

// The module's kind: an idr.program among its ops makes it a handoff
// module, whose every op must be of a dialect the frontend writes;
// otherwise every op must be the LLVM dialect's, and the module must name
// the build's target. An error at the first op that is not,
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
  // The runtime it is linked with, every link and the machine its code is
  // compiled by are for the build's target, the program's CPU among it; a
  // module lowered for another cannot join them.
  mlir::LLVM::TargetAttr built = idr::target::programTarget(module.getContext());
  if (target != built)
    return module.emitError() << "is compiled for " << target << ", and idris-mlir for "
                              << built;
  return std::variant<Handoff, Lowered>(Lowered{});
}

// The pipeline, idr-target first, in one manager, so that what a pass
// preserves the next one finds. --stats, LLVM's own option, prints its
// statistics too; MLIR's own pass-manager options (IR printing, the module
// after each pass with -mlir-print-ir-tree-dir, crash reproducers,
// -mlir-pass-statistics) apply to it, which the command line's reading
// has checked they can. The report's instrumentation reads each pass's
// statistics around each of its runs, before MLIR merges the copies'
// statistics to print them, and the report counts each run's footprint,
// the bytes the shared containers held beyond what they held when it
// began, under `<pass>.footprint`, summed over the runs of every copy as a
// statistic is. The timer is added last: the instrumentations unwind in
// reverse, so it stops before IR is printed, and a pass's row is the
// pass's own time. A test's checks come first, as idris-mlir-opt
// installs them, so the profile times each pass without them: under
// --idr-contracts the contracts, and the properties --idr-expect-at states
// of the stages. The pass manager instruments no end of its own pipeline,
// so each check's last word on the module it left is asked here. The
// manager goes, and prints its statistics, before LLVM starts.
mlir::LogicalResult runPipeline(mlir::ModuleOp module, const Compile &invocation,
                                Outcome &outcome, mlir::TimingScope &rootTiming) {
  mlir::PassManager pm(module.getContext());
  if (llvm::AreStatisticsEnabled())
    pm.enableStatistics(mlir::PassDisplayMode::List);
  mlir::LogicalResult ran = mlir::applyPassManagerCLOptions(pm);
  idr::ContractInstrumentation *contracts = nullptr;
  idr::expect::StageInstrumentation *stages = nullptr;
  if (mlir::succeeded(ran)) {
    if (invocation.checks == PassChecks::Contracts) {
      auto owned = std::make_unique<idr::ContractInstrumentation>();
      contracts = owned.get();
      pm.addInstrumentation(std::move(owned));
    }
    if (!invocation.stages.empty()) {
      auto owned = std::make_unique<idr::expect::StageInstrumentation>(invocation.stages);
      stages = owned.get();
      pm.addInstrumentation(std::move(owned));
    }
    idr::profile::addInstrumentation(pm);
    // A pass with no argument is no step of the pipeline but the manager's
    // adaptor that runs a nest of them, whose name is a sentence the
    // report's one-word key cannot hold; what its nest holds is each nested
    // pass's own footprint.
    pm.addInstrumentation(
        idr::profile::footprints([&outcome](mlir::Pass &pass, std::uint64_t bytes) {
          if (!pass.getArgument().empty())
            outcome.count((llvm::Twine(pass.getArgument()) + ".footprint").str(), bytes);
        }));
    pm.addInstrumentation(foldStatistics(outcome));
    pm.enableTiming(rootTiming);
    // The module's target, which every pass reads: idr-entry tells the
    // runtime's entry which of its features to test; the object code is
    // compiled for it.
    pm.addPass(idr::createIdrTarget());
    idr::buildPipeline(pm);
    ran = pm.run(module);
    if (mlir::succeeded(ran) && contracts != nullptr)
      ran = contracts->finish(module);
    if (mlir::succeeded(ran) && stages != nullptr)
      ran = stages->finish(module);
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
// object code for the module's target, the build's, on `pool`. Each stage
// has a timer of its own, so -mlir-timing says which one a compilation
// spends its time on.
mlir::LogicalResult toObjects(mlir::ModuleOp module, llvm::StringRef runtime,
                              Artifacts &artifacts, const llvm::Target &target,
                              const llvm::Triple &triple, llvm::ThreadPoolInterface &pool,
                              mlir::TimingScope &rootTiming) {
  mlir::MLIRContext &context = *module.getContext();
  mlir::Location unknown = mlir::UnknownLoc::get(&context);
  mlir::TimingScope llvmTiming = rootTiming.nest("LLVM");
  llvm::Expected<std::unique_ptr<llvm::TargetMachine>> made = idr::target::machine(target);
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
    if (mlir::failed(linkRuntime(*llvmModule, module, runtime, machine)))
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
  return writeObjects(*llvmModule, target, triple, pool, artifacts, context);
}

// The refusals the frontend left in the module in place of a program: one
// idr.refusal op each, at the module's top level, in the order found, its
// site the op's location and its rule a property. Each is emitted as the
// driver's diagnostic, its rule as data: the driver is their one printer,
// and foldDiagnostics their one fold into the verdict. A module the
// frontend could compile holds a program and no refusal.
void reemitRefusals(mlir::ModuleOp module) {
  for (idr::RefusalOp refusal : module.getOps<idr::RefusalOp>())
    idr::refuse(refusal.getLoc(), refusal.getRule()) << refusal.getMessage();
}

} // namespace

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
  llvm::Triple triple(idr::target::triple);
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
  // --log-actions-tags narrows, or else the debug counter that skips the
  // actions a test draws. With no tag given every action is logged, which
  // an empty filter would not do.
  mlir::tracing::DebugConfig debugConfig = mlir::tracing::DebugConfig::createFromCLOptions();
  mlir::tracing::TagBreakpointManager loggedTags;
  for (const std::string &tag : invocation.tags)
    loggedTags.addBreakpoint(tag);
  if (!invocation.tags.empty())
    debugConfig.addLogActionLocFilter(&loggedTags);
  mlir::tracing::InstallDebugHandler debugHandler(context, debugConfig);

  // A handoff module goes through the pipeline, whose first pass,
  // idr-target, writes the build's target on it; a lowered module names it
  // already.
  mlir::LogicalResult lowered = std::visit(
      llvm::makeVisitor(
          [&](Handoff) { return runPipeline(*module, invocation, outcome, rootTiming); },
          [](Lowered) { return mlir::success(); }),
      *kind);
  if (mlir::failed(lowered))
    return mlir::failure();
  return toObjects(*module, invocation.runtime, artifacts, **target, triple, pool, rootTiming);
}
