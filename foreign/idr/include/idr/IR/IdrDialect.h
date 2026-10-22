// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect: what mlir-tblgen generates from the specification's
// printed ODS (idr/IR/Generated/*.td), with what the generated code needs
// declared before it, in the order it needs it: the grades and the
// lifetimes, the quantity handles builders take, the traits the ops are
// built on, the effect tree's resources the ops' effects name, and the hand
// hooks the printed ODS names (custom directives, predicates, codecs); then
// the generated enums, attributes, dialect, interfaces, types and ops; then
// each partial op's guards. Nothing here restates a fact of the
// specification: every list over ops, types or cases is generated.
#ifndef IDR_IR_IDRDIALECT_H
#define IDR_IR_IDRDIALECT_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/RegionKindInterface.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/DestinationStyleOpInterface.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "mlir/Interfaces/LoopLikeInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/TilingInterface.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "mlir/Interfaces/ViewLikeInterface.h"

#include <cstdint>
#include <optional>
#include <string>

// The grades and the lifetimes, which the generated types' builders and
// constraints name.
#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
// The quantity handles, which builders of counting's ops take.
#include "idr/IR/Quantities.h"
// The traits the generated ops are built on.
#include "idr/IR/Traits.h"
// The effect system's words and sets, the tree's states among them, which
// the ops' printed effects and the effect interface name.
#include "idr/IR/Effects/Set.h"

// The dialect's enums (which Grades.h includes, the graded type's parameter
// being one) and their counts, then its attributes: the dialect's helpers
// and the types' parameters name them. mlir-tblgen writes what it generates
// from the printed ODS beside this header; the specification's own C++
// tables are under Generated/.
#include "idr/IR/Generated/EnumTraits.h.inc"
#include "idr/IR/IdrAttrInterfaces.h.inc"
#define GET_ATTRDEF_CLASSES
#include "idr/IR/IdrAttrs.h.inc"

#include "idr/IR/IdrDialect.h.inc"

#include "idr/IR/IdrTypeInterfaces.h.inc"
#define GET_TYPEDEF_CLASSES
#include "idr/IR/IdrTypes.h.inc"

// The hand hooks the printed ODS names (custom directives, predicates,
// parameter codecs), after the types and attributes their signatures name;
// their definitions are hand C++, a missing one a link error.
#include "idr/IR/Generated/Hooks.h.inc"

// What idr.func and idr.call hold beyond their generated classes, which
// their attributes name: it reads types alone.
#include "idr/IR/Func.h"

// How a value moves and the control-flow vocabulary the ops name, after the
// types its anchors hold; then the op interfaces, the flow interface among
// them.
#include "idr/IR/FlowEdges.h"
#include "idr/IR/Control/Control.h"
#include "idr/IR/IdrInterfaces.h.inc"

// The traits the ops' meanings give them: the one runtime fold, inline
// arithmetic, and the ops' own.
#include "idr/IR/Fold.h"
#include "idr/IR/Numeric/Trait.h"
#include "idr/IR/Ops/Traits.h"

#define GET_OP_CLASSES
#include "idr/IR/IdrOps.h.inc"

// Each partial op's guards (Guarded<Op>), and each op's declared effects
// (Declared<Op>) with the one query API that reads them, printed from the
// specification after the classes they specialize.
#include "idr/IR/Generated/Guards.h.inc"
#include "idr/IR/Effects/Query.h"
#include "idr/IR/Generated/Effects.h.inc"

namespace idr {

// The words a refusal by `rule` begins with, its separator included:
// `unsupported (<phrase>): ` for a construct this compiler does not compile,
// none for a program Idris itself rejects (the user-error category), whose
// message is Idris's own. The one place they are written.
std::string refusalHead(Rule rule);

// A refusal of the program by `rule`: an error at `loc`, or at `op`, whose
// message begins with refusalHead(rule), the caller streaming what was found
// after it. The rule is the diagnostic's metadata, data a handler reads
// (refusalRule), not printed text.
mlir::InFlightDiagnostic refuse(mlir::Location loc, Rule rule);
mlir::InFlightDiagnostic refuse(mlir::Operation *op, Rule rule);

// The rule a diagnostic refuses the program by; nothing for any other
// diagnostic: a diagnostic that is no refusal is the one case the metadata
// lacks a rule, which the problem has.
std::optional<Rule> refusalRule(mlir::Diagnostic &diagnostic);

namespace detail {
// Adds the dialect's asm interface: the aliases of its families.
void addAsmInterface(IdrDialect &dialect);

// Adds the dialect's bytecode interface: every type and attribute written
// by its generated record.
void addBytecodeInterface(IdrDialect &dialect);
} // namespace detail

} // namespace idr

#endif // IDR_IR_IDRDIALECT_H
