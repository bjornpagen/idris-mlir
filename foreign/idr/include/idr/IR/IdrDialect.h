// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect: what mlir-tblgen generates from the specification's
// printed ODS (idr/IR/Generated/*.td), with what the generated code needs
// declared before it, in the order it needs it: the grades and the
// lifetimes, the traits the ops are built on, the effect tree's resources
// the ops' effects name, a family's declaration, and what functions and
// calls hold; then the generated enums, attributes, dialect and types, the
// families' queries over them, the hand hooks the printed ODS names
// (custom directives, predicates, codecs, property hooks), the interfaces
// and the ops; then each partial op's guards and each op's declared
// effects. Nothing here restates a fact of the specification: every list
// over ops, types or cases is generated.
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
#include "mlir/IR/TypeUtilities.h"
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
// The traits the generated ops are built on.
#include "idr/IR/Traits.h"
// The effect system's words and sets, the tree's states among them, which
// the ops' printed effects and the effect interface name; the template the
// interface's default calls is declared there, before the interface.
#include "idr/IR/Effects/Set.h"
// A family's declaration, its index terms and sorts, which the generated
// attributes' and types' parameters and members name. The one set of
// constructors a data type leaves possible is defined with the queries over
// the generated classes (Families.h); its members name it by reference, so
// its name is enough here.
#include "idr/IR/Families/Declaration.h"
namespace idr::families {
class TagSet;
} // namespace idr::families
// What idr.func and idr.call hold beyond their generated classes, which
// their attributes and properties name: it reads types alone.
#include "idr/IR/Func.h"

// The dialect's enums (which Grades.h includes, the graded type's parameter
// being one) and their counts, the hand storage classes the generated
// classes name, then its attributes: the dialect's helpers and the types'
// parameters name them. mlir-tblgen writes what it generates from the
// printed ODS beside this header; the specification's own C++ tables are
// under Generated/.
#include "idr/IR/Generated/EnumTraits.h.inc"
#include "idr/IR/Generated/Storages.h.inc"
#include "idr/IR/IdrAttrInterfaces.h.inc"
#define GET_ATTRDEF_CLASSES
#include "idr/IR/IdrAttrs.h.inc"

#include "idr/IR/IdrDialect.h.inc"

#include "idr/IR/IdrTypeInterfaces.h.inc"
#define GET_TYPEDEF_CLASSES
#include "idr/IR/IdrTypes.h.inc"

// The dialect's types as the closed list a match over an mlir::Type folds:
// every class mlir-tblgen generates, from the list it prints beside their
// definitions, so a class the specification adds joins every match.
#include "idr/Support/Match.h"
namespace idr {
struct DialectTypes : TypeClasses<
#define GET_TYPEDEF_LIST
#include "idr/IR/IdrTypes.cpp.inc"
                          > {};
} // namespace idr

// What the C++ reads of a family and a data type beyond their generated
// classes, which it names.
#include "idr/IR/Families/Families.h"

// The hand hooks the printed ODS names (custom directives, predicates,
// parameter codecs, property hooks), after the types and attributes their
// signatures name; their definitions are hand C++, a missing one a link
// error.
#include "idr/IR/Generated/Hooks.h.inc"

// How a value moves and the join family's carrier, which the ops name,
// after the types its anchors hold; the template a big made of an integer
// reads its signedness from, which that interface's default calls; then
// the op interfaces, the flow interface among them. The control flow's
// skeleton rules, which name the ops, are their own header's
// (Control/Control.h).
#include "idr/IR/FlowEdges.h"
#include "idr/IR/Control/Family.h"
#include "idr/IR/Ops/BigOfInteger.h"
#include "idr/IR/IdrInterfaces.h.inc"

// The traits the ops' meanings give them: the one runtime fold, inline
// arithmetic, and the ops' own.
#include "idr/IR/Fold.h"
#include "idr/IR/Numeric/Trait.h"
#include "idr/IR/Ops/Traits.h"

#define GET_OP_CLASSES
#include "idr/IR/IdrOps.h.inc"

// Each partial op's guards (Guarded<Op>), and each op's declared effects
// (Declared<Op>) with the typed half of the one query API, which reads them
// as constants and implements the generated `getEffects` from them, printed
// from the specification after the classes they specialize.
#include "idr/IR/Generated/Guards.h.inc"
#include "idr/IR/Effects/Declared.h"
#include "idr/IR/Generated/Effects.h.inc"

// The site a crash a pass builds carries, read off a location.
#include "idr/IR/Ops/Sites.h"

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

// The integer `value` at `type`, as its constants hold it: of 64 bits at a
// big, and at a natural where it is not negative; of the type's width at an
// integer or an index where it fits. Nothing where `value` is no value of
// the type. The one rule from an integer to a constant's value, which the
// dialect's identities and the rewrite graph's literals both read.
std::optional<llvm::APInt> integerAt(mlir::Type type, std::int64_t value);

namespace laws {
// The identity of `op`'s operation, as the constant the dialect
// materializes at its result's type, where the specification calls the
// operation exactly associative with an identity (Generated/Laws.h.inc):
// what an accumulator starts from. Nothing for any other op, and nothing at
// a type the identity is no value of.
std::optional<mlir::Attribute> identityOf(mlir::Operation *op);
} // namespace laws

namespace detail {
// Adds the dialect's asm interface: the aliases of its families.
void addAsmInterface(IdrDialect &dialect);

// Adds the dialect's bytecode interface: every type and attribute written
// by its generated record.
void addBytecodeInterface(IdrDialect &dialect);
} // namespace detail

} // namespace idr

#endif // IDR_IR_IDRDIALECT_H
