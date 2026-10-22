// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The stack a program can take: its final module's calls, read once and
// checked, then weighed by the frames code generation reports.

#include "idr/Driver/StackBound.h"

#include "idr/Driver/Runtime.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/CodeGen/TargetFrameLowering.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Casting.h"
#include "llvm/Target/TargetMachine.h"

#include <algorithm>
#include <cstdlib>
#include <span>
#include <utility>

// The bytes a leaf may use below its stack pointer without moving it, the
// target's ABI (CMakeLists.txt's entry): code generation reports a frame
// without them, and one leaf at the bottom of the deepest path may use them.
#ifndef IDRIS_MLIR_RED_ZONE_BYTES
#error "the target entry gives its red zone (IDRIS_MLIR_RED_ZONE_BYTES)"
#endif

using namespace idr::driver::stack;

namespace {

// What the prepared runtime records of its native half, by name: the
// deepest path from each function its C ABI exports; its largest frame;
// its fault handler's deepest path.
constexpr llvm::StringLiteral recordedPaths = "idris.rt.stack";
constexpr llvm::StringLiteral recordedFrame = "idris.rt.frame";
constexpr llvm::StringLiteral recordedSignal = "idris.rt.signal";

// Code generation reports each frame it is asked of as a diagnostic, which
// this takes and nobody prints.
class Gatherer final : public llvm::DiagnosticHandler {
public:
  explicit Gatherer(Frames &frames) : frames(frames) {}

  bool handleDiagnostics(const llvm::DiagnosticInfo &info) override {
    if (const auto *size = llvm::dyn_cast<llvm::DiagnosticInfoStackSize>(&info)) {
      frames.add(size->getFunction().getName(), size->getStackSize());
      return true;
    }
    return false;
  }

private:
  Frames &frames;
};

// A function whose body the module's code generation compiles: a
// definition, not the prepared runtime's body available here to inline,
// which links to its native half.
bool compiled(const llvm::Function &function) {
  return !function.isDeclaration() && !function.hasAvailableExternallyLinkage();
}

using Component = idr::Partition<FunctionTag>::Component;

// The callees `node`, the function `f`, calls in the module by `call`: its
// row's first `grows` callees, or the rest.
idr::IdRange<FunctionId> callees(const idr::Csr<FunctionTag> &calls, const Graph::Node &node,
                                 FunctionId f, Call call) {
  std::span<const std::uint32_t> row = calls.rows(idr::Forward{}).row(f.index());
  return idr::IdRange<FunctionId>(call == Call::Grows ? row.first(node.grows)
                                                      : row.subspan(node.grows));
}

// The one value of a recorded tuple, or 0 where nothing was recorded.
std::uint64_t recordedOne(const llvm::Module &module, llvm::StringRef name) {
  const llvm::NamedMDNode *node = module.getNamedMetadata(name);
  if (node == nullptr || node->getNumOperands() == 0)
    return 0;
  auto *value = llvm::mdconst::dyn_extract<llvm::ConstantInt>(node->getOperand(0)->getOperand(0));
  return value == nullptr ? 0 : value->getZExtValue();
}

} // namespace

void Frames::join(const Frames &other) {
  for (const auto &entry : other.bytes_)
    bytes_[entry.getKey()] = entry.getValue();
}

std::uint64_t Frames::of(llvm::StringRef function) const {
  auto found = bytes_.find(function);
  return found == bytes_.end() ? 0 : found->getValue();
}

void idr::driver::stack::ask(llvm::Module &module) {
  for (llvm::Function &function : module)
    if (compiled(function))
      function.addFnAttr("warn-stack-size", "0");
}

std::unique_ptr<llvm::DiagnosticHandler> idr::driver::stack::gather(Frames &frames) {
  return std::make_unique<Gatherer>(frames);
}

mlir::FailureOr<Graph> Graph::of(const llvm::Module &module, mlir::MLIRContext &context) {
  mlir::Location at = mlir::UnknownLoc::get(&context);
  llvm::StringMap<std::uint64_t> outside;
  if (const llvm::NamedMDNode *paths = module.getNamedMetadata(recordedPaths))
    for (const llvm::MDNode *path : paths->operands())
      if (auto *name = llvm::dyn_cast<llvm::MDString>(path->getOperand(0)))
        if (auto *bytes = llvm::mdconst::dyn_extract<llvm::ConstantInt>(path->getOperand(1)))
          outside[name->getString()] = bytes->getZExtValue();

  // Every compiled function, numbered once in the module's order. LLVM
  // numbers no function, so a callee is found by its id through one map,
  // made here, where the module is read: a hashed map, which takes no
  // allocator.
  idr::footprint::Vector<const llvm::Function *> compiledFunctions;
  for (const llvm::Function &function : module)
    if (compiled(function))
      compiledFunctions.push_back(&function);
  idr::Count<FunctionId> count(static_cast<std::uint32_t>(compiledFunctions.size()));
  idr::IndexVector<FunctionId, Node> nodes(count, [&](FunctionId f) {
    const llvm::Function *function = compiledFunctions[f.index()];
    return Node{function, function->hasFnAttribute(handlerMark) ? Runs::OnSignalStack
                                                                : Runs::OnStack};
  });
  llvm::DenseMap<const llvm::Function *, FunctionId> idOf;
  idr::footprint::Vector<FunctionId> addressed;
  for (FunctionId f : count.ids()) {
    idOf.try_emplace(nodes[f].function, f);
    if (nodes[f].function->hasAddressTaken())
      addressed.push_back(f);
  }

  // Each function's row: the callees its calls grow the stack by, then
  // those it tail-calls, gathered for one function at a time.
  idr::CsrBuilder<FunctionTag> rows(count);
  idr::footprint::Vector<FunctionId> growing, tail;
  for (FunctionId f : count.ids()) {
    Node &node = nodes[f];
    growing.clear();
    tail.clear();
    for (const llvm::Instruction &instruction : llvm::instructions(*node.function)) {
      // A frame of a size known only at run time is one code generation
      // cannot report, so no bound holds over it.
      if (const auto *alloca = llvm::dyn_cast<llvm::AllocaInst>(&instruction))
        if (!alloca->isStaticAlloca())
          return mlir::emitError(at) << "@" << node.function->getName()
                                     << " has a frame whose size is known only at run time, so "
                                        "the program's stack has no bound";
      const auto *site = llvm::dyn_cast<llvm::CallBase>(&instruction);
      if (site == nullptr || site->isInlineAsm())
        continue;
      Call call = site->isMustTailCall() ? Call::MustTail : Call::Grows;
      idr::footprint::Vector<FunctionId> &into = call == Call::Grows ? growing : tail;
      if (const llvm::Function *callee = site->getCalledFunction()) {
        if (callee->isIntrinsic())
          continue;
        if (compiled(*callee)) {
          into.push_back(idOf.find(callee)->second);
          continue;
        }
        std::uint64_t path = outside.lookup(callee->getName());
        std::uint64_t &deepest = call == Call::MustTail ? node.outsideTail : node.outsideGrows;
        deepest = std::max(deepest, path);
        continue;
      }
      // A call through a pointer may reach any function whose address the
      // module takes and whose type the call's is.
      for (FunctionId candidate : addressed)
        if (nodes[candidate].function->getFunctionType() == site->getFunctionType())
          into.push_back(candidate);
    }
    node.grows = static_cast<std::uint32_t>(growing.size());
    for (FunctionId callee : growing)
      rows.edge(f, callee);
    for (FunctionId callee : tail)
      rows.edge(f, callee);
  }
  idr::Csr<FunctionTag> calls = std::move(rows).finish();
  idr::Partition<FunctionTag> components = idr::components(calls);

  // Recursion on a cycle of calls lives on frame stacks, so a cycle the
  // final module still has is tail calls alone; any other call on one is
  // the compiler's bug, and the stack would have no bound.
  for (Component c : components.size().ids()) {
    if (!components.cyclic(c))
      continue;
    for (FunctionId member : components.members(c))
      for (FunctionId callee : callees(calls, nodes[member], member, Call::Grows))
        if (components.componentOf(callee) == c)
          return mlir::emitError(at) << "@" << nodes[member].function->getName() << " calls @"
                                     << nodes[callee].function->getName()
                                     << " on a cycle of calls with no musttail call, so the "
                                        "program's stack has no bound";
  }
  return Graph(std::move(nodes), std::move(calls), std::move(components),
               recordedOne(module, recordedFrame), recordedOne(module, recordedSignal));
}

Graph::Graph(idr::IndexVector<FunctionId, Node> nodes, idr::Csr<FunctionTag> calls,
             idr::Partition<FunctionTag> components, std::uint64_t outsideFrame,
             std::uint64_t outsideSignal)
    : nodes(std::move(nodes)), calls(std::move(calls)), components(std::move(components)),
      outsideFrame(outsideFrame), outsideSignal(outsideSignal) {}

namespace {

// A function's frame: what code generation reported, and the slot below it
// the target's call leaves, its return address where the call pushes one.
std::uint64_t frameOf(const llvm::Function &function, const Frames &frames,
                      const llvm::TargetMachine &machine) {
  const llvm::TargetFrameLowering *lowering =
      machine.getSubtargetImpl(function)->getFrameLowering();
  return frames.of(function.getName()) +
         static_cast<std::uint64_t>(std::abs(lowering->getOffsetOfLocalArea()));
}

} // namespace

struct Graph::Weighed {
  idr::IndexVector<FunctionId, std::uint64_t> frame;
  idr::IndexVector<Component, std::uint64_t> path;
};

// The deepest path from each component, callees first: a component is one
// weight, since a tail call within it replaces a frame by another of it,
// and every member reaches every other; a call that grows stacks the
// callee's path on the caller's frame, a tail call replaces the frame. A
// callee outside the component was weighed before it: the partition's
// components come callees first.
Graph::Weighed Graph::weigh(const Frames &frames, const llvm::TargetMachine &machine) const {
  Weighed weighed{idr::IndexVector<FunctionId, std::uint64_t>(
                      nodes.size(),
                      [&](FunctionId f) { return frameOf(*nodes[f].function, frames, machine); }),
                  idr::IndexVector<Component, std::uint64_t>(components.size())};
  for (Component c : components.size().ids()) {
    std::uint64_t heaviest = 0;
    for (FunctionId member : components.members(c)) {
      const Node &node = nodes[member];
      std::uint64_t frame = weighed.frame[member];
      std::uint64_t path = std::max({frame, frame + node.outsideGrows, node.outsideTail});
      for (FunctionId callee : callees(calls, node, member, Call::Grows))
        if (Component below = components.componentOf(callee); below != c)
          path = std::max(path, frame + weighed.path[below]);
      for (FunctionId callee : callees(calls, node, member, Call::MustTail))
        if (Component below = components.componentOf(callee); below != c)
          path = std::max(path, weighed.path[below]);
      heaviest = std::max(heaviest, path);
    }
    weighed.path[c] = heaviest;
  }
  return weighed;
}

// The deepest path from any function, the largest frame and the fault
// handler's deepest path. What the runtime recorded of its native half
// holds its red zone already; the module's own paths take it once, at the
// bottom.
Need Graph::needOf(const Weighed &weighed) const {
  std::uint64_t stack = 0, frame = 0, handler = 0;
  for (FunctionId f : nodes.size().ids()) {
    std::uint64_t path = weighed.path[components.componentOf(f)];
    stack = std::max(stack, path);
    frame = std::max(frame, weighed.frame[f]);
    if (nodes[f].runs == Runs::OnSignalStack)
      handler = std::max(handler, path);
  }
  return Need{stack + IDRIS_MLIR_RED_ZONE_BYTES, std::max(frame, outsideFrame),
              std::max(handler + IDRIS_MLIR_RED_ZONE_BYTES, outsideSignal)};
}

Need Graph::need(const Frames &frames, const llvm::TargetMachine &machine) const {
  return needOf(weigh(frames, machine));
}

void Graph::record(llvm::Module &runtime, const Frames &frames,
                   const llvm::TargetMachine &machine) const {
  Weighed weighed = weigh(frames, machine);
  Need need = needOf(weighed);
  llvm::LLVMContext &context = runtime.getContext();
  auto integer = [&](std::uint64_t value) {
    return llvm::ConstantAsMetadata::get(
        llvm::ConstantInt::get(llvm::Type::getInt64Ty(context), value));
  };
  llvm::NamedMDNode *paths = runtime.getOrInsertNamedMetadata(recordedPaths);
  for (FunctionId f : nodes.size().ids()) {
    const llvm::Function *function = nodes[f].function;
    if (function->hasLocalLinkage())
      continue;
    paths->addOperand(llvm::MDNode::get(
        context, {llvm::MDString::get(context, function->getName()),
                  integer(weighed.path[components.componentOf(f)])}));
  }
  runtime.getOrInsertNamedMetadata(recordedFrame)
      ->addOperand(llvm::MDNode::get(context, {integer(need.frame)}));
  runtime.getOrInsertNamedMetadata(recordedSignal)
      ->addOperand(llvm::MDNode::get(context, {integer(need.signal)}));
}
