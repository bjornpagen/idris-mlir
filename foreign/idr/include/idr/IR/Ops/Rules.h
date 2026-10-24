// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rules of the guards and of output, which the specification
// names (IdrisMLIR.Spec.Ops.Rewrites) and the e-graph's engine runs: each
// rooted at one op or one interface of ours, `decide` reading what the
// e-graph knows of the root's operands and asking for an edit or nothing,
// `rewrite` carrying out a Rewrite on the input between the e-graph's two
// rounds, re-reading its root as it now is. A guard and an output are
// ordered by their effects, so no rule on them is a pure rewrite: each is
// one-way, and none reorders two ops one resource orders.
#ifndef IDR_IR_OPS_RULES_H
#define IDR_IR_OPS_RULES_H

#include "idr/Transforms/EGraph.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/LLVM.h"

#include <optional>

namespace idr {

class GuardOpInterface;
class CheckNonemptyOp;
class IoPutStrOp;

// Whether a string is never empty: a non-empty constant, a string a builder
// makes never empty (one built with a character or a number in it, the
// trait NeverEmpty), or an append of such a string and another, through
// appends none other shares. A guard that the string is not empty, and a
// literal match's case of the empty string, read it.
bool neverEmpty(mlir::Value str);

// Erases what follows `op` in its block, the last first: control never gets
// past `op` (a crash, or a match none of whose regions yields). Every rule
// that ends a block calls this one. The dialect's library holds it because
// every rule library links the dialect, never the reverse. A value made
// after `op` is used only by ops after it in the same block, since a region
// has one block until the lowering, so erasing the last first leaves each
// op with no user; the rewriter checks that.
void eraseAfter(mlir::RewriterBase &rewriter, mlir::Operation *op);

} // namespace idr

namespace idr::egraph {

// A guard whose condition holds on its operands' constants or intervals
// gives its operand: a proof is the absence of the guard. One whose
// condition fails is a crash of its cause at its site, with no test at run
// time: a statically certain crash, where evaluation reaches it, and
// nothing after it in its block runs. The crash takes the operand the guard
// found false where its cause's line reads it.
struct GuardDecided {
  using Root = GuardOpInterface;
  static std::optional<Edit> decide(Root guard, const OperandFacts &facts);
  static void rewrite(Root guard, const Rewrite &choice, mlir::RewriterBase &rewriter);
};

// A guard of the value an identical guard gave, the same op on the same
// other operands, gives it: the first checked it.
struct GuardRepeated {
  using Root = GuardOpInterface;
  static std::optional<Edit> decide(Root guard, const OperandFacts &facts);
  static void rewrite(Root guard, const Rewrite &choice, mlir::RewriterBase &rewriter);
};

// A guard of a string a builder makes never empty (one built with a
// character or a number in it, the trait NeverEmpty), or of an append of
// such a string and another, gives its string.
struct NeverEmptyString {
  using Root = CheckNonemptyOp;
  static std::optional<Edit> decide(Root guard, const OperandFacts &facts);
  static void rewrite(Root guard, const Rewrite &choice, mlir::RewriterBase &rewriter);
};

// Writing an append writes its two strings, in order: a string built only
// to be written is never built.
struct OutputOfAppend {
  using Root = IoPutStrOp;
  static std::optional<Edit> decide(Root output, const OperandFacts &facts);
  static void rewrite(Root output, const Rewrite &choice, mlir::RewriterBase &rewriter);
};

// Writing a cons writes its character, then its string.
struct OutputOfCons {
  using Root = IoPutStrOp;
  static std::optional<Edit> decide(Root output, const OperandFacts &facts);
  static void rewrite(Root output, const Rewrite &choice, mlir::RewriterBase &rewriter);
};

// Writing a one-character string writes the character.
struct OutputOfChar {
  using Root = IoPutStrOp;
  static std::optional<Edit> decide(Root output, const OperandFacts &facts);
  static void rewrite(Root output, const Rewrite &choice, mlir::RewriterBase &rewriter);
};

// Writing the empty string writes nothing.
struct OutputOfNothing {
  using Root = IoPutStrOp;
  static std::optional<Edit> decide(Root output, const OperandFacts &facts);
  static void rewrite(Root output, const Rewrite &choice, mlir::RewriterBase &rewriter);
};

} // namespace idr::egraph

#endif // IDR_IR_OPS_RULES_H
