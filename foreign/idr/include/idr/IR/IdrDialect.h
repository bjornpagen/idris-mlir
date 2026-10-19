// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect: what TableGen generates from IdrOps.td, with what the
// generated code needs declared around it, in the order it needs it: the
// grades, the traits and the guards' vocabulary (Traits.h), the resources
// and a data type's constructors before the generated attributes, types
// and interfaces, the flow vocabulary and its interface before the ops,
// and what reads the ops after them.
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
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "mlir/Interfaces/LoopLikeInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/ADT/BitmaskEnum.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <functional>
#include <optional>
#include <string>
#include <tuple>
#include <utility>
#include <variant>

// The enums, then the grades over them: the generated type builders name
// ::idr::Grade.
#include "idr/IR/Grades.h"
// The traits the generated ops are built on.
#include "idr/IR/Traits.h"

namespace idr {

// What a function may do when nothing says less: perform IO, crash and not
// return. It is idr.func's `effects` by default, so a function no pass has
// solved says so through its own accessor.
inline constexpr Effect anyEffect = Effect::io | Effect::crash | Effect::diverge;

// The resource that a possible crash writes to.
struct CrashResource : mlir::SideEffects::Resource::Base<CrashResource> {
  llvm::StringRef getName() const final { return "idr.crash"; }
};

// The resource that every IO op reads and writes, and that a crash and a
// possibly endless loop also write, so that no pass reorders either with
// output.
struct IOResource : mlir::SideEffects::Resource::Base<IOResource> {
  llvm::StringRef getName() const final { return "idr.io"; }
};

// The resource that idr.may_loop writes, so that a loop that may not end is
// never removed as dead.
struct DivergenceResource : mlir::SideEffects::Resource::Base<DivergenceResource> {
  llvm::StringRef getName() const final { return "idr.divergence"; }
};

// The resource that idr.lin.enter and idr.lin.use allocate their results
// on: no heap, only a new value that no pass may merge with another.
struct LinResource : mlir::SideEffects::Resource::Base<LinResource> {
  llvm::StringRef getName() const final { return "idr.lin"; }
};

// The resource a consumed reference is freed from.
struct ReferenceResource : mlir::SideEffects::Resource::Base<ReferenceResource> {
  llvm::StringRef getName() const final { return "idr.reference"; }
};

// Whether `operand`'s position takes over the reference its value holds,
// as the edges of its op's flow say (lib/IR/Effects.cpp): a use the op
// moves on or ends, a forwarded value, or an argument whose parameter owns
// it, which the program's stage says how to read. Given `callees`, the
// program's symbol table, a call's parameter is read from its callee's
// signature, as placement asks before the operands take their parameters'
// grades; without, from the operand's grade.
bool consumes(mlir::OpOperand &operand, const mlir::SymbolTable *callees = nullptr);

// A string that cannot be empty beyond what a constant shows: a non-empty
// constant, a string its builder says is never empty (one built with a
// character or a number in it), or an append of one.
bool knownNonEmpty(mlir::Value value);

namespace detail {
struct DataTypeStorage;
} // namespace detail

// A data type, which a constant constructor names before the types are
// declared (IdrTypes.td).
class DataType;

// What a value of a data type holds, the facts ValueFactsTypeInterface asks
// of the type that its body decides: a reference held in place, a world
// anywhere a value reaches. The type computes them once and keeps them
// beside its body (lib/IR/ValueFacts.cpp).
enum class Held : uint8_t {
  Nothing = 0,
  References = 1,
  World = 2,
  LLVM_MARK_AS_BITMASK_ENUM(World)
};
LLVM_ENABLE_BITMASK_ENUMS_IN_NAMESPACE();

// A constructor's tag: its position in its data type's body, the number a
// cell's header and a match's case hold. A type of its own, so that no
// field's index, case's position or count stands in for a tag, nor a tag
// for them: `Tag{n}` makes one where a position is read as a tag (a body's
// order, a parser, a stored attribute), and a cast reads the number back
// where it is stored or emitted.
enum class Tag : uint32_t {};

inline llvm::raw_ostream &operator<<(llvm::raw_ostream &os, Tag tag) {
  return os << static_cast<uint32_t>(tag);
}

// The part a constructor plays in its sum, by role and never by position,
// each role holding what only it has: a label names the function it runs
// and, in a memo sum, whether every force runs it (`byName`: the function
// reaches an observable effect, so the cell is never written). In
// CtorRole's order, the case the syntax, the bytecode and KindRule name.
namespace role {
struct Plain { bool operator==(const Plain &) const = default; };
struct ListNil { bool operator==(const ListNil &) const = default; };
struct ListCons { bool operator==(const ListCons &) const = default; };
struct Label {
  mlir::FlatSymbolRefAttr fn;
  bool byName = false;
  bool operator==(const Label &) const = default;
};
struct Running { bool operator==(const Running &) const = default; };
struct Forced { bool operator==(const Forced &) const = default; };
} // namespace role
using Role = std::variant<role::Plain, role::ListNil, role::ListCons, role::Label,
                          role::Running, role::Forced>;
static_assert(std::variant_size_v<Role> == getMaxEnumValForCtorRole() + 1,
              "a role per CtorRole case, in its order");
inline CtorRole kindOf(const Role &role) { return static_cast<CtorRole>(role.index()); }
// The role of case `kind` with nothing of its own yet: each alternative
// made empty, in CtorRole's order, so no case is written out. A reader
// that finds a label reads its payload after its case.
inline Role emptyRole(CtorRole kind) {
  static const auto empty = []<std::size_t... Case>(std::index_sequence<Case...>) {
    return std::array<Role, sizeof...(Case)>{Role(std::in_place_index<Case>)...};
  }(std::make_index_sequence<std::variant_size_v<Role>>());
  return empty[static_cast<std::size_t>(kind)];
}
struct Ctor {
  mlir::StringAttr name;
  llvm::ArrayRef<mlir::Type> fields;
  Role role;
  bool operator==(const Ctor &) const = default;
};

} // namespace idr

// The attributes come first: the dialect's helpers for its discardable
// attributes and the types' parameters name them.
#define GET_ATTRDEF_CLASSES
#include "idr/IR/IdrAttrs.h.inc"

#include "idr/IR/IdrDialect.h.inc"

#include "idr/IR/IdrInterfaces.h.inc"
#include "idr/IR/IdrTypeInterfaces.h.inc"

#define GET_TYPEDEF_CLASSES
#include "idr/IR/IdrTypes.h.inc"

// How a value moves, and the flow interface every op that moves one holds,
// which the ops name: after the types, which its anchors hold.
#include "idr/IR/FlowEdges.h"

#define GET_OP_CLASSES
#include "idr/IR/IdrOps.h.inc"

// Each guarded op's guards (Guarded), generated from its marks.
#include "idr/IR/IdrGuards.inc"

namespace idr {

// The names a memo sum gives its two states, which their roles
// (CtorRole::Running, CtorRole::Forced) identify; a reader finds them by
// role, never by name.
inline constexpr llvm::StringLiteral memoRunning = "running";
inline constexpr llvm::StringLiteral memoForced = "forced";

// The most static data a folded constant may take: a folded op whose result
// can outgrow its operands (a big shifted left). A larger one would make the
// executable larger than computing it at runtime does, and the compilation
// slower, so it stays, to run at runtime. The value is never at stake, only
// the size and the speed.
inline constexpr uint64_t constantBytes = uint64_t{1} << 20;

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
// diagnostic.
std::optional<Rule> refusalRule(mlir::Diagnostic &diagnostic);

// The custom directives of the matches' assembly formats (IdrMatchOps.td),
// defined in lib/IR/OpsMatchSyntax.cpp, which the generated parsers and
// printers call by name.
mlir::ParseResult parseResultTypes(mlir::OpAsmParser &parser,
                                   llvm::SmallVectorImpl<mlir::Type> &types);
void printResultTypes(mlir::OpAsmPrinter &printer, mlir::Operation *op, mlir::TypeRange types);
mlir::ParseResult
parseMatchCases(mlir::OpAsmParser &parser, mlir::Type scrutineeType,
                mlir::DenseI32ArrayAttr &cases,
                llvm::SmallVectorImpl<std::unique_ptr<mlir::Region>> &caseRegions);
void printMatchCases(mlir::OpAsmPrinter &printer, mlir::Operation *op, mlir::Type scrutineeType,
                     mlir::DenseI32ArrayAttr cases,
                     llvm::MutableArrayRef<mlir::Region> caseRegions);
mlir::ParseResult
parseLiteralCases(mlir::OpAsmParser &parser, mlir::Type scrutineeType, mlir::ArrayAttr &cases,
                  llvm::SmallVectorImpl<std::unique_ptr<mlir::Region>> &caseRegions);
void printLiteralCases(mlir::OpAsmPrinter &printer, mlir::Operation *op, mlir::Type scrutineeType,
                       mlir::ArrayAttr cases, llvm::MutableArrayRef<mlir::Region> caseRegions);
mlir::ParseResult parseDefaultCase(mlir::OpAsmParser &parser, mlir::Region &defaultRegion);
void printDefaultCase(mlir::OpAsmPrinter &printer, mlir::Operation *op,
                      mlir::Region &defaultRegion);

namespace detail {
// Adds the dialect's asm interface: the aliases of its data types and of
// its large constants.
void addAsmInterface(IdrDialect &dialect);

// Adds the dialect's bytecode interface: its types written by the records
// of IdrBytecode.td, and the module's table of data types read.
void addBytecodeInterface(IdrDialect &dialect);

// What the ops that hold a constructor's tag share (lib/IR/OpsCon.cpp): the
// constructor `tag` of the data type of a value of `type`, or failure after
// an error at `op`.
mlir::FailureOr<std::reference_wrapper<const Ctor>> ctorAt(mlir::Operation *op, mlir::Type type,
                                                           Tag tag);

// Whether the fields `op` writes are its cell's constructor's, in order,
// the holes aside, each at the field's type or owned: idr.cell.init's
// declared constraint, which its generated verifier calls
// (lib/IR/OpsCon.cpp).
bool fillsCell(CellInitOp op);
} // namespace detail

} // namespace idr

#endif // IDR_IR_IDRDIALECT_H
