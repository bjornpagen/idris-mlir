// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The stack a program can take, a fact of its code computed once code
// generation has laid out every frame: the deepest path of calls through
// the final module, each frame its own size, a call in tail position
// replacing its caller's frame rather than stacking on it. The program's
// recursion on a call cycle lives on frame stacks in the heap, so the only
// cycles left are tail calls, `musttail`; any other call on a cycle is the
// compiler's bug, refused here, since no bound would hold. The runtime
// reserves what this says (idris_rt_program_built), and its guard is the
// largest frame: compiled code takes no stack probes, because no frame can
// step over a guard the build made at least as large as every frame.
#ifndef IDR_DRIVER_STACKBOUND_H
#define IDR_DRIVER_STACKBOUND_H

#include "idr/Analysis/Solver/Components.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/IR/MLIRContext.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/IR/DiagnosticHandler.h"

#include <cstdint>
#include <memory>

namespace llvm {
class Function;
class Module;
class TargetMachine;
} // namespace llvm

namespace idr::driver::stack {

// Each function's frame as code generation laid it out, by name: the
// stack-size diagnostic it reports of every function asked (`ask`). Each
// context code is generated in gathers its own, and the driver joins them:
// a bin's functions are its own context's, so a name is the one identity
// they share with the final module's. The context that reports a name ends
// before the name is read, so each is copied once into the frames' own
// arena; the arena and the map's table are the footprint's, both sized by
// the program's functions.
class Frames {
public:
  void add(llvm::StringRef function, std::uint64_t bytes);
  void join(const Frames &other);
  // The bytes code generation reported, 0 for a function that reported
  // none: one whose frame is empty.
  std::uint64_t of(llvm::StringRef function) const { return bytes_.lookup(function); }

private:
  footprint::BumpPtrAllocator names;
  footprint::DenseMap<llvm::StringRef, std::uint64_t> bytes_;
};

// Asks code generation for every defined function's frame: each reports
// its size, as a diagnostic, to its context's handler.
void ask(llvm::Module &module);

// A context's handler that gathers the frames into `frames` and leaves
// every other diagnostic to the default handling.
std::unique_ptr<llvm::DiagnosticHandler> gather(Frames &frames);

// What the runtime reads of a program's stack: the deepest path's bytes,
// the largest frame, and the deepest path from the fault handler, which
// runs on the signal stack.
struct Need {
  std::uint64_t stack;
  std::uint64_t frame;
  std::uint64_t signal;
};

// Whether a call grows the stack by its caller's frame, or replaces it.
enum class Call : std::uint8_t { Grows, MustTail };

// Which stack a function's code may run on: the program's, or the signal
// stack, where the kernel calls the fault handler.
enum class Runs : std::uint8_t { OnStack, OnSignalStack };

class Graph;

// A function the module compiles, numbered once, in the module's order, by
// the graph that reads it.
struct FunctionTag {
  using Minter = Graph;
};
using FunctionId = Id<FunctionTag>;

// The final module's calls, read once, before code generation, with what
// the prepared runtime recorded of its native half's (a call into a body of
// it the program did not inline stacks that body's frames): the solver
// layer's graph over the functions' ids, each function's row its callees
// in the module, those its calls grow the stack by first, then those it
// tail-calls, and its components, callees first.
class Graph {
public:
  struct Node {
    const llvm::Function *function;
    // Whether the kernel calls it on a fault, on the signal stack.
    Runs runs;
    // The deepest path through a callee outside the module the runtime
    // recorded, by how it is called; 0 for the C library's and GMP's, which
    // the runtime's margin holds.
    std::uint64_t outsideGrows = 0;
    std::uint64_t outsideTail = 0;
    // How many of its row's callees, the first, its calls grow the stack
    // by; the rest it tail-calls.
    std::uint32_t grows = 0;
  };

  // The graph of `module`, refused as the compiler's error in `context`
  // when a call on a cycle is no tail call, or a frame's size is known only
  // at run time.
  static mlir::FailureOr<Graph> of(const llvm::Module &module, mlir::MLIRContext &context);

  // The need, once code generation has given every frame: each frame its
  // bytes and the slot the target's call leaves below it, the deepest path
  // then, once, the red zone a leaf may use below its stack pointer; the
  // largest frame; the fault handler's deepest path and its red zone. What
  // the prepared runtime recorded counts as the module's own.
  Need need(const Frames &frames, const llvm::TargetMachine &machine) const;

  // What the prepared runtime records of its native half, for the programs
  // that call into it: the deepest path from each function it defines, which
  // a program names once it inlines a body that calls one; the largest
  // frame; and the fault handler's deepest path, with its red zone.
  void record(llvm::Module &runtime, const Frames &frames, const llvm::TargetMachine &machine) const;

private:
  // Each function's frame and the deepest path from each component, weighed
  // once for a need and a record.
  struct Weighed;

  Graph(IndexVector<FunctionId, Node> nodes, Csr<FunctionTag> calls,
        Partition<FunctionTag> components, std::uint64_t outsideFrame,
        std::uint64_t outsideSignal);

  Weighed weigh(const Frames &frames, const llvm::TargetMachine &machine) const;
  Need needOf(const Weighed &weighed) const;

  IndexVector<FunctionId, Node> nodes;
  Csr<FunctionTag> calls;
  Partition<FunctionTag> components;
  // What the prepared runtime recorded: its largest frame and its fault
  // handler's deepest path.
  std::uint64_t outsideFrame;
  std::uint64_t outsideSignal;
};

} // namespace idr::driver::stack

#endif // IDR_DRIVER_STACKBOUND_H
