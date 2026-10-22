// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The stack a program can take: its final module's calls, read once and
// checked, then weighed by the frames code generation reports.

#include "idr/Driver/StackBound.h"

#include "idr/Driver/Runtime.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/GraphTraits.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"
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
#include <utility>

// The bytes a leaf may use below its stack pointer without moving it, the
// target's ABI (CMakeLists.txt's entry): code generation reports a frame
// without them, and one leaf at the bottom of the deepest path may use them.
#ifndef IDRIS_MLIR_RED_ZONE_BYTES
#error "the target entry gives its red zone (IDRIS_MLIR_RED_ZONE_BYTES)"
#endif

using namespace idr::driver::stack;

template <>
struct llvm::GraphTraits<const Graph *> {
  using NodeRef = const Graph::Node *;
  using ChildIteratorType = std::vector<NodeRef>::const_iterator;
  static NodeRef getEntryNode(const Graph *graph) { return graph->root(); }
  static ChildIteratorType child_begin(NodeRef node) { return node->callees.begin(); }
  static ChildIteratorType child_end(NodeRef node) { return node->callees.end(); }
};

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
  Graph graph;
  graph.outsideFrame_ = recordedOne(module, recordedFrame);
  graph.outsideSignal_ = recordedOne(module, recordedSignal);
  llvm::StringMap<std::uint64_t> outside;
  if (const llvm::NamedMDNode *paths = module.getNamedMetadata(recordedPaths))
    for (const llvm::MDNode *path : paths->operands())
      if (auto *name = llvm::dyn_cast<llvm::MDString>(path->getOperand(0)))
        if (auto *bytes = llvm::mdconst::dyn_extract<llvm::ConstantInt>(path->getOperand(1)))
          outside[name->getString()] = bytes->getZExtValue();

  // Every compiled function, numbered once in the module's order, the root
  // before them; the nodes never move once made.
  std::size_t count = 1;
  for (const llvm::Function &function : module)
    count += compiled(function) ? 1 : 0;
  graph.nodes_.resize(count);
  llvm::DenseMap<const llvm::Function *, Node *> nodeOf;
  std::size_t next = 1;
  for (const llvm::Function &function : module)
    if (compiled(function)) {
      Node &node = graph.nodes_[next++];
      node.function = &function;
      if (function.hasFnAttribute(handlerMark))
        node.runs = Runs::OnSignalStack;
      nodeOf[&function] = &node;
    }
  std::vector<const llvm::Function *> addressed;
  for (const llvm::Function &function : module)
    if (compiled(function) && function.hasAddressTaken())
      addressed.push_back(&function);

  for (Node &node : llvm::drop_begin(graph.nodes_)) {
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
      auto edge = [&](const llvm::Function *callee) {
        node.callees.push_back(nodeOf.lookup(callee));
        node.calls.push_back(call);
      };
      if (const llvm::Function *callee = site->getCalledFunction()) {
        if (callee->isIntrinsic())
          continue;
        if (compiled(*callee)) {
          edge(callee);
          continue;
        }
        std::uint64_t path = outside.lookup(callee->getName());
        std::uint64_t &into = call == Call::MustTail ? node.outsideTail : node.outsideGrows;
        into = std::max(into, path);
        continue;
      }
      // A call through a pointer may reach any function whose address the
      // module takes and whose type the call's is.
      for (const llvm::Function *candidate : addressed)
        if (candidate->getFunctionType() == site->getFunctionType())
          edge(candidate);
    }
  }
  Node &root = graph.nodes_.front();
  for (Node &node : llvm::drop_begin(graph.nodes_)) {
    root.callees.push_back(&node);
    root.calls.push_back(Call::Grows);
  }

  // Recursion on a cycle of calls lives on frame stacks, so a cycle the
  // final module still has is tail calls alone; any other call on one is
  // the compiler's bug, and the stack would have no bound.
  std::vector<unsigned> component(graph.nodes_.size());
  unsigned id = 0;
  for (auto scc = llvm::scc_begin(static_cast<const Graph *>(&graph)); !scc.isAtEnd();
       ++scc, ++id) {
    for (const Node *member : *scc)
      component[member - graph.nodes_.data()] = id;
    if (!scc.hasCycle())
      continue;
    for (const Node *member : *scc)
      for (auto [callee, call] : llvm::zip_equal(member->callees, member->calls))
        if (component[callee - graph.nodes_.data()] == id && call == Call::Grows)
          return mlir::emitError(at) << "@" << member->function->getName() << " calls @"
                                     << callee->function->getName()
                                     << " on a cycle of calls with no musttail call, so the "
                                        "program's stack has no bound";
  }
  return graph;
}

namespace {

// A function's frame: what code generation reported, and the slot below it
// the target's call leaves, its return address where the call pushes one.
std::uint64_t frameOf(const Graph::Node &node, const Frames &frames,
                      const llvm::TargetMachine &machine) {
  if (node.function == nullptr)
    return 0;
  const llvm::TargetFrameLowering *lowering =
      machine.getSubtargetImpl(*node.function)->getFrameLowering();
  return frames.of(node.function->getName()) +
         static_cast<std::uint64_t>(std::abs(lowering->getOffsetOfLocalArea()));
}

// The deepest path from each node, callees first: a component is one
// weight, since a tail call within it replaces a frame by another of it,
// and every member reaches every other; a call that grows stacks the
// callee's path on the caller's frame, a tail call replaces the frame. A
// callee outside the component was weighed before it: LLVM's walk of
// components (scc_iterator) gives callees first.
std::vector<std::uint64_t> weights(const Graph &graph, const Frames &frames,
                                   const llvm::TargetMachine &machine) {
  constexpr unsigned unseen = ~0u;
  std::vector<std::uint64_t> weight(graph.size());
  std::vector<unsigned> component(graph.size(), unseen);
  const Graph::Node *base = graph.root();
  unsigned id = 0;
  for (auto scc = llvm::scc_begin(&graph); !scc.isAtEnd(); ++scc, ++id) {
    const std::vector<const Graph::Node *> &members = *scc;
    for (const Graph::Node *member : members)
      component[member - base] = id;
    std::uint64_t heaviest = 0;
    for (const Graph::Node *member : members) {
      std::uint64_t frame = frameOf(*member, frames, machine);
      std::uint64_t path = std::max({frame, frame + member->outsideGrows, member->outsideTail});
      for (auto [callee, call] : llvm::zip_equal(member->callees, member->calls)) {
        if (component[callee - base] == id)
          continue;
        std::uint64_t below = weight[callee - base];
        path = std::max(path, call == Call::Grows ? frame + below : below);
      }
      heaviest = std::max(heaviest, path);
    }
    for (const Graph::Node *member : members)
      weight[member - base] = heaviest;
  }
  return weight;
}

} // namespace

Need Graph::need(const Frames &frames, const llvm::TargetMachine &machine) const {
  std::vector<std::uint64_t> weight = weights(*this, frames, machine);
  std::uint64_t frame = 0, handler = 0;
  for (std::size_t i = 1; i < nodes_.size(); ++i) {
    frame = std::max(frame, frameOf(nodes_[i], frames, machine));
    if (nodes_[i].runs == Runs::OnSignalStack)
      handler = std::max(handler, weight[i]);
  }
  // What the runtime recorded of its native half holds its red zone
  // already; the module's own paths take it once, at the bottom.
  return Need{weight.front() + IDRIS_MLIR_RED_ZONE_BYTES,
              std::max(frame, outsideFrame_),
              std::max(handler + IDRIS_MLIR_RED_ZONE_BYTES, outsideSignal_)};
}

void Graph::record(llvm::Module &runtime, const Frames &frames,
                   const llvm::TargetMachine &machine) const {
  std::vector<std::uint64_t> weight = weights(*this, frames, machine);
  Need need = this->need(frames, machine);
  llvm::LLVMContext &context = runtime.getContext();
  auto integer = [&](std::uint64_t value) {
    return llvm::ConstantAsMetadata::get(
        llvm::ConstantInt::get(llvm::Type::getInt64Ty(context), value));
  };
  llvm::NamedMDNode *paths = runtime.getOrInsertNamedMetadata(recordedPaths);
  for (std::size_t i = 1; i < nodes_.size(); ++i) {
    const llvm::Function *function = nodes_[i].function;
    if (function->hasLocalLinkage())
      continue;
    paths->addOperand(
        llvm::MDNode::get(context, {llvm::MDString::get(context, function->getName()),
                                    integer(weight[i])}));
  }
  runtime.getOrInsertNamedMetadata(recordedFrame)
      ->addOperand(llvm::MDNode::get(context, {integer(need.frame)}));
  runtime.getOrInsertNamedMetadata(recordedSignal)
      ->addOperand(llvm::MDNode::get(context, {integer(need.signal)}));
}
