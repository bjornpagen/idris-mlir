// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rules of the matches and the join points, which the
// specification names (IdrisMLIR.Spec.Control.Rules) and the e-graph's
// engine runs; it names the ops by declaration alone. The join family's
// carrier, which the generated ops need first, is Control/Family.h.
#ifndef IDR_IR_CONTROL_CONTROL_H
#define IDR_IR_CONTROL_CONTROL_H

#include "idr/Transforms/EGraph.h"

#include "mlir/Support/LLVM.h"

#include <optional>

namespace idr {

class MatchOp;
class MatchLitOp;
class JoinOp;
class LoopOp;
class MatchOpInterface;
class JoinPointsOpInterface;

} // namespace idr

// The rewrites of the matches and the join points, one-way rules of the
// e-graph's skeleton (idr::egraph::SkeletonRule, idr/Transforms/EGraph.h):
// each rooted at one op or one interface of ours; `decide` reads what the
// e-graph knows of the root's operands and asks for an edit or nothing,
// and `rewrite` carries out a Rewrite once the root's operands are written
// back. The rewrites edit the root's own regions (their yields, their
// arguments, the uses in them), which the engine writes back after.
namespace idr::egraph {

// A match whose region a known scrutinee takes keeps that region alone, or
// becomes it where the scrutinee's type leaves that constructor alone.
struct TakenCase {
  using Root = MatchOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// A literal match on a constant runs the region its literal takes.
struct TakenLiteral {
  using Root = MatchLitOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// In case k of a literal match, the scrutinee is the literal k.
struct LiteralInCase {
  using Root = MatchLitOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// A default the scrutinee's type leaves no constructor for never runs.
struct DeadDefault {
  using Root = MatchOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// A match none of whose regions yields gives nothing, and nothing follows.
struct AllExits {
  using Root = MatchOpInterface;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// A result of a match no op uses goes, with every yield's operand for it.
struct DeadResults {
  using Root = MatchOpInterface;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// The consumer's cases become join regions shared by the producer's arms;
// the arms whose yielded constructor is known take a copy of the dispatch.
struct CaseOfCase {
  using Root = MatchOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// A result of a join point's op no op uses goes, with every yield's operand.
struct DeadJoinResults {
  using Root = JoinPointsOpInterface;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// An idr.loop whose join regions never jump to its own op is an idr.join.
struct LoopToJoin {
  using Root = LoopOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// A join region no jump reaches goes; a group left with none is its body.
struct DeadJoinRegions {
  using Root = JoinOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// The same, for an idr.loop.
struct DeadLoopRegions {
  using Root = LoopOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// A join region reached by one jump, the body's own end, runs there.
struct InlineSingleJump {
  using Root = JoinOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// A parameter its join region never reads goes, with every jump's argument.
struct DeadJoinParameters {
  using Root = JoinOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

// The same, for an idr.loop.
struct DeadLoopParameters {
  using Root = LoopOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, mlir::RewriterBase &rewriter);
};

} // namespace idr::egraph

#endif // IDR_IR_CONTROL_CONTROL_H
