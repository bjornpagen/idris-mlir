// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Tail.h - What becomes of a function's tail positions ---------------===//
//
// A self tail call becomes the next iteration of a loop (idr-tail-loops:
// the while-do form of a body that is a decision, or the general loop); a
// self call whose result is a field of the constructor a tail returns
// becomes a tail call that writes the field (idr-trmc); a self call a tail
// adds becomes a tail call that carries the sum (idr-accumulate); and a
// result a function always returns as one of its arguments, as such loops
// and recursions thread a value through, is dropped
// (idr-returned-arguments). These are the declarations the units of the
// library share.
//
//===----------------------------------------------------------------------===//

#ifndef IDR_TRANSFORMS_TAIL_H
#define IDR_TRANSFORMS_TAIL_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/raw_ostream.h"

#include <cstddef>
#include <optional>
#include <utility>
#include <variant>

namespace idr {
#define GEN_PASS_DECL_IDRACCUMULATE
#define GEN_PASS_DECL_IDRFRAMES
#define GEN_PASS_DECL_IDRTRMC
#define GEN_PASS_DECL_IDRTAILLOOPS
#define GEN_PASS_DECL_IDRRETURNEDARGUMENTS
#define GEN_PASS_DECL_IDRRETURNEDARGUMENTSDROP
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::tail {

//===----------------------------------------------------------------------===//
// The shape of tail positions
//===----------------------------------------------------------------------===//

// The blocks in tail position of `block`: itself, or through the match in
// tail position, the blocks of its regions. Collects; changes nothing.
void forTails(mlir::Block &block, llvm::function_ref<void(mlir::Block &)> f);

// Whether `block`, which ends in a tail position, reaches a self call of
// `fn` in tail position, through the matches in tail position on the way.
bool reachesTailCall(mlir::Block &block, FuncOp fn);

//===----------------------------------------------------------------------===//
// Copies
//===----------------------------------------------------------------------===//

// The name of the copy of `fn` of kind `kind` (`acc`, `trmc`), from content:
// a function has at most one copy of each kind, and both are in the name,
// so the key is empty. A symbol of that name in `symbols` is something
// else, which is an internal error at `fn`, reported here.
mlir::FailureOr<mlir::StringAttr> copyName(FuncOp fn, llvm::StringRef kind, mlir::SymbolTable &symbols);

//===----------------------------------------------------------------------===//
// Loops
//===----------------------------------------------------------------------===//

// The body of a function that decides once per call whether to go round
// again: the match whose results it returns, the region of it that ends in
// the self tail call, and the one that reaches none.
struct Decision {
  MatchOpInterface match;
  mlir::Region &loops;
  mlir::Region &exits;
};

// The while-do loop of a function whose body is a decision, or failure,
// with the function as it was, when what the regions need from the body
// cannot pass from one iteration to the next as plain values.
mlir::FailureOr<mlir::scf::WhileOp> whileDo(FuncOp fn, Decision decision, mlir::RewriterBase &rewriter);

// The general loop: the whole body in the before region of an scf.while,
// with a payload at every tail position.
mlir::scf::WhileOp generalLoop(FuncOp fn, mlir::RewriterBase &rewriter);

//===----------------------------------------------------------------------===//
// Accumulators
//===----------------------------------------------------------------------===//

// Whether `value` is the constant zero, the identity of addition.
bool isZero(mlir::Value value);

// Erases every op of `block`, last first, so each goes after its users.
void clearBlock(mlir::RewriterBase &rewriter, mlir::Block &block);

// Whether `fn` is `f(0) = 0`, `f(n) = f(n - 1) + 1` on one natural, whose
// result is that natural, or that natural as an Integer.
bool isCountdown(FuncOp fn);

// Makes `fn`, a countdown, return its argument.
void returnArgument(FuncOp fn, mlir::RewriterBase &rewriter);

// A self call of `fn` as an accumulator tail: the call itself is the tail
// (the sum passes on unchanged, and there is no addition), or it is the
// one operand of the addition `add` the tail returns, and `addend`, the
// other, does not depend on a self call.
struct Site {
  struct Addition {
    BigAddOp add;
    mlir::Value addend;
  };
  CallOp call;
  std::optional<Addition> addition;
};

// The accumulator tails of `fn`, or none when a self call is not one or
// none of them is an addition.
llvm::SmallVector<Site> accumulatorSites(FuncOp fn);

//===----------------------------------------------------------------------===//
// Returned arguments
//===----------------------------------------------------------------------===//

// Which result of which lowered function is always one of its arguments:
// an analysis of the module, one sparse forward dataflow solved by
// upstream's solver. Only a private func.func every use of which is a
// direct call is eligible to drop one: its signature is the rewrite's to
// change. A function's own rewrite and its callers' read only this, by
// name, so none reads a sibling while that sibling may be changing.
class Returned {
public:
  // What a value is known to be: unconstrained yet (what every value
  // starts as, the bottom, and what a value only code that never runs
  // gives stays), the argument at an index of its function, or no one
  // argument (the top). What two paths give joins to what they agree on.
  class Known {
  public:
    Known() = default;
    static Known arg(unsigned index) { return Known(State(std::in_place_index<1>, index)); }
    static Known none() { return Known(State(NoOne{})); }

    // The argument the value is, when it is one.
    std::optional<unsigned> argument() const {
      if (const unsigned *index = std::get_if<unsigned>(&state))
        return *index;
      return std::nullopt;
    }

    // What two paths give, together.
    static Known join(const Known &a, const Known &b) {
      if (std::holds_alternative<Unconstrained>(a.state) || a == b)
        return b;
      if (std::holds_alternative<Unconstrained>(b.state))
        return a;
      return none();
    }

    bool operator==(const Known &) const = default;

    void print(llvm::raw_ostream &os) const;

  private:
    struct Unconstrained {
      bool operator==(const Unconstrained &) const = default;
    };
    struct NoOne {
      bool operator==(const NoOne &) const = default;
    };
    using State = std::variant<Unconstrained, unsigned, NoOne>;

    explicit Known(State state) : state(state) {}

    State state;
  };

  // A result of a function, as it was before any was dropped: its type,
  // and what it is known to be.
  struct Result {
    mlir::Type type;
    Known known;
  };

  // A function that drops a result: its results.
  struct Function {
    llvm::SmallVector<Result> results;

    // The results that stay, by position.
    llvm::SmallVector<unsigned> kept() const;
  };

  // The solve of `module`, a builtin.module of func.func.
  Returned(mlir::Operation *module, mlir::AnalysisManager &am);

  // The function named `name` when it drops a result, or null.
  const Function *dropping(mlir::StringAttr name) const;
  // Whether the function named `name` drops a result or calls one that
  // does: the only functions the rewrite changes.
  bool changes(mlir::StringAttr name) const { return changed.contains(name); }
  // How many results drop, over every function.
  unsigned dropped() const { return numDropped; }

private:
  // The functions that drop a result, and no other.
  llvm::DenseMap<mlir::StringAttr, Function> functions;
  llvm::DenseSet<mlir::StringAttr> changed;
  unsigned numDropped = 0;
};

} // namespace idr::tail

#endif // IDR_TRANSFORMS_TAIL_H
