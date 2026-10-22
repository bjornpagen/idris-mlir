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

namespace families {

// The field `read` takes from the constructor `con` built its value with:
// the field given, where the read takes it at the type it was given, a
// field used once only by the constructor's one read of it, and the value's
// built state still holds where it is read; null otherwise. One answer for
// the fold, over the input, and for the rule, over the e-graph's form.
mlir::Value givenField(DataConOp con, DataFieldOp read);

} // namespace families

} // namespace idr

namespace idr::egraph {

// A field of a value an idr.data.con built is the field it was given.
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
