// Escape analysis of boxes: which cells can outlive the frame that builds
// them.
//
// A reference to a cell is held by SSA values and parameters, and by the
// fields of other cells and of unboxed sums. Within a function the analysis
// follows it through a graph of nodes, each a value in one of two modes: a
// box value stands for the reference it holds (shallow), or for everything
// reachable from it through fields, its own reference too (deep). An
// unboxed sum has no reference of its own, so its only node is deep. The
// edges:
//   - a value to the values MLIR says it is forwarded to (the successor
//     inputs of a region branch: a match's result for a yield, an
//     scf.while's arguments and results for its initial values and its
//     terminators' operands), to an arith.select's result, and into and out
//     of a linear type (idr.lin.enter, idr.lin.use), in the same mode:
//     linearity has no runtime form, and a value used once may still be
//     used where it escapes;
//   - a deep value to what reading it gives (idr.field, the arguments of a
//     match's case regions), deep, and a deep box to its own reference;
//   - a value stored in a constructor to the constructor's value, deep.
// A node escapes when it reaches a use that lets it go: a return, a
// closure's capture, an idr.apply, a call of a function without a body or
// of a parameter whose node escapes, or any op this analysis does not know.
// Reading a box (idr.field, idr.tag, a match's scrutinee) lets nothing go.
//
// A parameter's nodes are summarized over the module's calls as the least
// solution, so a parameter a function only passes to itself does not escape
// through that call. A cell passed to a parameter whose node does not escape
// is live only while the call runs, inside the caller's frame.
//
// The cell an idr.con builds lives in one stack slot per con, in its
// function's entry block. So it also escapes when the con may run again in
// the same frame while the cell is live: the cell must not be forwarded by
// a terminator of a loop around the con, which carries values to the next
// iteration or out of the loop, nor passed to a self tail call of the
// function, which idr-tail-loops makes the next iteration of a loop. A con
// counts only in a function body of one block whose regions on the way are
// those of matches (at most one runs, once) and of scf.while (one
// iteration at a time); anywhere else it escapes.
#pragma once

#include "idr/Idr.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <utility>

namespace idr::stack {

class Escapes {
public:
  // Computes the summaries of every parameter of the module's functions.
  explicit Escapes(mlir::ModuleOp module);

  // Whether the cell that `con`, a box's constructor, builds may outlive its
  // frame, or be live when `con` runs again in the same frame.
  bool mayEscape(ConOp con);

  enum class Mode : uint8_t { Shallow, Deep };
  using Node = std::pair<mlir::Value, Mode>;
  // The node of `value` in `mode`; a sum's only node is deep.
  static Node node(mlir::Value value, Mode mode);

private:
  // Where the nodes of a function are followed: `repeating` are the ops
  // that may run a con again in the same frame (its loops, and the function
  // itself for its self tail calls); none, for the function's parameters.
  struct Frame {
    mlir::func::FuncOp fn;
    llvm::ArrayRef<mlir::Operation *> repeating;
  };

  // Where a use sends a node: to other nodes (none for a read), or nowhere
  // this analysis can follow (nullopt), which is an escape.
  using Flow = std::optional<llvm::SmallVector<Node, 2>>;

  // The nodes of the frame's function that escape.
  llvm::DenseSet<Node> escaping(const Frame &frame) const;
  Flow flow(mlir::OpOperand &use, Mode mode, const Frame &frame,
            const mlir::RegionBranchSuccessorMapping &forwards) const;

  mlir::ModuleOp module;
  mlir::SymbolTable symbols;
  // The nodes of parameters that escape.
  llvm::DenseSet<Node> parameters;
  // The escaping nodes of a function around the cons of one innermost loop
  // (null for none), once the summaries are final.
  llvm::DenseMap<std::pair<mlir::Operation *, mlir::Operation *>, llvm::DenseSet<Node>> cache;
};

} // namespace idr::stack
