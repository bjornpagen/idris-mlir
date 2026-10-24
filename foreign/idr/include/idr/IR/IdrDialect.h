// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect: what mlir-tblgen generates from the specification's
// printed ODS (idr/IR/Generated/*.td), with what the generated code needs
// declared before it, in the order it needs it: the grades and the
// lifetimes, the traits the ops are built on, the effect tree's resources
// the ops' effects name, a family's declaration, and what functions and
// calls hold; then the generated enums, attributes, dialect and types, the
// families' queries over them, the hooks the printed ODS names (custom
// directives, predicates, codecs, property hooks), the interfaces
// and the ops; then each partial op's guards, the constants the
// interfaces' defaults read of an op's class, and each op's declared
// effects; then the base the generated passes name. Nothing here restates
// a fact of the specification: every list over ops, types or cases is
// generated.
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
#include "mlir/Pass/Pass.h"

#include <cstdint>
#include <optional>
#include <string>

// The grades and the lifetimes, which the generated types' builders and
// constraints name.
#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
// The words the question interfaces answer in, which their methods name.
#include "idr/IR/Interfaces/Vocabulary.h"
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
// being one) and their counts; the hand storage classes the generated
// classes name, and every type class, whose name is all an attribute's
// members need where the attribute holds a type (a constant constructor's
// data type), the types' parameters holding attributes in turn, both lists
// printed from the specification; the hand functions the attribute and
// type interfaces' defaults call, which those interfaces call by qualified
// name where mlir-tblgen defines them; then its attributes: the dialect's
// helpers and the types' parameters name them. mlir-tblgen writes what it
// generates from the printed ODS beside this header; the specification's
// own C++ tables are under Generated/.
#include "idr/IR/Generated/EnumTraits.h.inc"
#include "idr/IR/Generated/Storages.h.inc"
#include "idr/IR/Generated/Defaults.h.inc"
#include "idr/IR/IdrAttrInterfaces.h.inc"
#define GET_ATTRDEF_CLASSES
#include "idr/IR/IdrAttrs.h.inc"

#include "idr/IR/IdrDialect.h.inc"

#include "idr/IR/IdrTypeInterfaces.h.inc"
#define GET_TYPEDEF_CLASSES
#include "idr/IR/IdrTypes.h.inc"

// What the C++ reads of a family and a data type beyond their generated
// classes, which it names. Among it, the refinement a region assumes as it
// is entered, which the hooks and the erased-binder interface return by
// value, so their callers, the interface's own definition among them, read
// it whole; and the name of the module's layouts, which a put into a
// lifetime is measured by and which the interface takes by reference.
#include "idr/IR/Families/Families.h"

// The hooks the printed ODS names (custom directives, predicates,
// parameter codecs, property hooks), after the types and attributes their
// signatures name; their definitions are hand C++ but for the termination
// proof's parser, printer and hash, which the specification prints beside
// the proof's bytecode codec (Generated/Wire.cpp.inc); a missing one is a
// link error.
#include "idr/IR/Generated/Hooks.h.inc"

// How a value moves and the join family's carrier, which the ops name,
// after the types its anchors hold; the template a big made of an integer
// reads its signedness from, which that interface's default calls; what
// intervals know of a guard's condition, which the guard interface decides;
// then the op interfaces, the flow interface among them. The control
// flow's skeleton rules, which name the ops, are their own header's
// (Control/Control.h).
#include "idr/IR/FlowEdges.h"
#include "idr/IR/Control/Family.h"
#include "idr/IR/Ops/BigOfInteger.h"
#include "idr/IR/Numeric/Intervals.h"
#include "idr/IR/IdrInterfaces.h.inc"

// The traits the ops' meanings give them: the one runtime fold, inline
// arithmetic, and the ops' own; and the one the ops that end an owner
// carry.
#include "idr/IR/Fold.h"
#include "idr/IR/FoldParts.h"
#include "idr/IR/Numeric/Trait.h"
#include "idr/IR/Ops/Traits.h"
#include "idr/IR/Counting/Traits.h"

#define GET_OP_CLASSES
#include "idr/IR/IdrOps.h.inc"

// Each partial op's guards (Guarded<Op>); how each big made of an integer
// reads it (BigOfInteger<Op>) and where each opener's memory comes from
// (LifetimeOpener<Op>), which the interfaces' defaults read, so every unit
// that instantiates an op's interfaces sees them, and an opener's trait
// never finds its constant missing; and each op's declared effects
// (Declared<Op>) with the typed half of the one query API, which reads them
// as constants and implements the generated `getEffects` from them, printed
// from the specification after the classes they specialize.
#include "idr/IR/Generated/Guards.h.inc"
// Each guard op's condition, its `decide` over where its operands' values
// come from, defined after the classes that declare it.
#include "idr/IR/Ops/Guards.h"
#include "idr/IR/Generated/BigOfInteger.h.inc"
#include "idr/IR/Generated/LifetimeOpener.h.inc"
#include "idr/IR/Effects/Declared.h"
#include "idr/IR/Generated/Effects.h.inc"

// The site a crash a pass builds carries, read off a location.
#include "idr/IR/Ops/Sites.h"

namespace idr {

// The base of every pass whose record names the stage it requires,
// `Requires`, and the one it leaves, `Sets`: the record's printed
// baseClass, inside which upstream's generator names the pass `DerivedT`,
// so the base calls the pass's own body with no virtual. It finds the
// program the pass runs on (the anchor, the program around it, or the one
// program of a module), refuses a program at another stage, runs the pass
// on it (DerivedT::runOnProgram, handed the program it found), and leaves
// the program at `Sets` unless the pass failed. A pass that runs at any
// stage derives from upstream's base instead. It is declared here, after
// the program op and the stages it reads, because every unit that defines
// a pass reaches this header through its area's header or directly, and
// the generated definition names it with nothing else included.
template <typename DerivedT, typename OpT, Stage Requires, Stage Sets>
class StagedPass : public mlir::OperationPass<OpT> {
  // Where the program is from the anchor, as the anchor's ODS says: its
  // parent, for an op whose parent the program is (HasParent: a function);
  // the anchor itself, for the op of ours whose run covers the whole
  // program (CheckedRoot); else one of the anchor's ops, the module's.
  enum class Found : std::uint8_t { Parent, Anchor, AmongOps };
  static constexpr Found found =
      OpT::template hasTrait<mlir::OpTrait::HasParent<ProgramOp>::Impl>() ? Found::Parent
      : OpT::template hasTrait<CheckedRoot>()                               ? Found::Anchor
                                                                            : Found::AmongOps;

  // A pass on an op inside the program runs beside its siblings, which
  // read the program's stage; only a pass on an op that holds the whole
  // program may change it. The specification's pipeline type refuses the
  // case before any C++ exists; this states the same of the class.
  static_assert(Requires == Sets || found != Found::Parent,
                "a pass on a function leaves the stage it found");

protected:
  explicit StagedPass(mlir::TypeID passID) : mlir::OperationPass<OpT>(passID) {}
  StagedPass(const StagedPass &) = default;

private:
  void runOnOperation() final {
    OpT anchor = this->getOperation();
    ProgramOp program;
    if constexpr (found == Found::Parent) {
      program = llvm::cast<ProgramOp>(anchor->getParentOp());
    } else if constexpr (found == Found::Anchor) {
      program = anchor;
    } else {
      // A module may hold any number of programs, as MLIR sees it; the
      // pass runs on its one.
      auto programs = anchor.template getOps<ProgramOp>();
      if (!llvm::hasSingleElement(programs)) {
        anchor.emitError("internal error: ")
            << this->getArgument() << " runs on a module that holds one program, not "
            << llvm::range_size(programs);
        return this->signalPassFailure();
      }
      program = *programs.begin();
    }
    if (program.getStage() != Requires) {
      anchor->emitError("internal error: ")
          << this->getArgument() << " runs on a program at " << stringifyStage(Requires)
          << ", not " << stringifyStage(program.getStage());
      return this->signalPassFailure();
    }
    static_cast<DerivedT &>(*this).runOnProgram(program);
    if constexpr (Requires != Sets)
      if (!this->getPassState().irAndPassFailed.getInt())
        program.setStage(Sets);
  }
};

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
// dialect's identities and the e-graph's literals both read; keyInteger is
// its converse.
std::optional<llvm::APInt> integerAt(mlir::Type type, std::int64_t value);

// The integer an attribute is, as a key or a constant holds it: what a key
// of ours that is an integer answers (IntegerKeyAttrInterface, a big's), or
// upstream's integer attribute, a word's. Nothing for any other attribute,
// or none. The one rule from a constant to its integer.
std::optional<llvm::APInt> keyInteger(mlir::Attribute attr);

// How a value of `type`, through its grade, is read as a number, as its
// type answers (NumericTypeInterface): a type that does not answer is read
// as a word's bits.
NumericReading numericReadingOf(mlir::Type type);

// Whether a value of `type`, through its grade, is an Integer the big ops
// take, its constant a #idr.big, as its type answers (NumericTypeInterface):
// a type that does not answer is none.
bool isCarriedAsBig(mlir::Type type);

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

// Attaches ConstantAttrInterface to upstream's constants a constant's fields
// and static data hold: the builtin strings, integers and floats.
void addUpstreamConstants(IdrDialect &dialect);
} // namespace detail

} // namespace idr

// Each composite fold's condition, its `meaning` over where a constant
// lives, defined after everything the conditions read: the classes that
// declare it, and what the symbols' header says of values (Ops/Folds.h).
#include "idr/IR/Ops/Folds.h"

#endif // IDR_IR_IDRDIALECT_H
