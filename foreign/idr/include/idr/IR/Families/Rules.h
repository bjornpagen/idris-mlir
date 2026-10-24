// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rules of constructor values, which the specification names
// (IdrisMLIR.Spec.Families.Dialect) and the e-graph's engine runs: a field
// of a value a constructor built is the field it was given, and a
// constructor rebuilt from every field of a value is that value. Each reads
// a variadic group by position, which no pattern of the rule tables can, so
// each is hand C++ meeting idr::egraph::SkeletonRule; it names the ops by
// declaration alone.
#ifndef IDR_IR_FAMILIES_RULES_H
#define IDR_IR_FAMILIES_RULES_H

#include "idr/Transforms/EGraph.h"

#include "mlir/IR/Value.h"
#include "mlir/Support/LLVM.h"

#include <optional>

namespace idr {

class DataConOp;
class DataFieldOp;
} // namespace idr

namespace idr::egraph {

// A field read the e-graph keeps in place (a memo cell's, which a force
// writes) of a value an idr.data.con built is the field it was given; a
// read that floats is that field by its own fold's meaning, givenField's.
struct FieldOfCon {
  using Root = DataFieldOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, const Rewrite &rewrite, mlir::RewriterBase &rewriter);
};

// A constructor rebuilt from every field of a value refined to it is that
// value (record eta), except where its result's identity is read.
struct ConEta {
  using Root = DataConOp;
  static std::optional<Edit> decide(Root op, const OperandFacts &facts);
  static void rewrite(Root op, const Rewrite &rewrite, mlir::RewriterBase &rewriter);
};

} // namespace idr::egraph

#endif // IDR_IR_FAMILIES_RULES_H
