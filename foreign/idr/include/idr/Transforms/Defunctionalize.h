// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-defunctionalize: every closure and suspension becomes a constructor
// of a family the pass declares, every apply a match over its callee's
// family whose cases call the labels, every force a call of its memo
// family's dispatch function, on the program as the frontend wrote it.
//
// Types first: a decision, made whole and serially, writes the label
// solve's answer into types (each slot's key, each key's family, every
// signature, every memo family's dispatch function, every constant), and
// reads each function's edits off the solve: each value whose type
// changes, each move between two keys, each closure op and what replaces
// it, with every type and attribute those edits build made then, in the
// program's order. Then one walk per function, in parallel, makes its
// edits from the decision alone, through a const reference: no worker
// makes a type or an attribute, reads the solve, or looks a symbol up. No
// conversion driver and no pattern set.
//
// A key is a slot's carrier at no grade and the labels the solve found for
// it. A closure key becomes a closure family, one label per function of
// its set; a lazy key a memo family, its labels each memoized or run by
// name, then its two states. A label runs by name exactly when its row
// reads or writes the outside: memoizing it would run its effect once
// instead of at each demand. Its row is the one derivation of rows, joined
// over the program graph, which is born in the decision: the label solve's
// runs complete it, each a call of the label it runs, until the rewrite
// makes every run a call of its own.
#ifndef IDR_TRANSFORMS_DEFUNCTIONALIZE_H
#define IDR_TRANSFORMS_DEFUNCTIONALIZE_H

#include "idr/Analysis/Labels.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/Effects/Vocabulary.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"
#include "idr/Transforms/EGraph.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <memory>
#include <optional>
#include <tuple>
#include <variant>

namespace idr {

#define GEN_PASS_DECL_IDRDEFUNCTIONALIZE
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

namespace idr::defunctionalize {

// The key of a slot that holds a closure or a suspension.
struct Key {
  mlir::Type carrier;
  mlir::ArrayAttr labels;
  bool operator==(const Key &) const = default;
};

// Whether a key is a suspension's, whose family is a memo family.
enum class Carrier : bool { Closure, Lazy };
inline Carrier carrierOf(const Key &key) {
  return llvm::isa<LazyType>(key.carrier) ? Carrier::Lazy : Carrier::Closure;
}

// A slot: a key, or no key where the slot holds neither.
using Slot = std::optional<Key>;

// A key's place in the decision: dense, in the order the keys were met,
// which is the order every walk over them takes.
enum class KeyId : std::uint32_t {};
// A match and a coercion the edits build, by their places in the decision.
enum class MatchId : std::uint32_t {};
enum class CoercionId : std::uint32_t {};

} // namespace idr::defunctionalize

template <> struct llvm::DenseMapInfo<idr::defunctionalize::Key> {
  using Key = idr::defunctionalize::Key;
  static Key getEmptyKey() {
    return {llvm::DenseMapInfo<mlir::Type>::getEmptyKey(), mlir::ArrayAttr()};
  }
  static Key getTombstoneKey() {
    return {llvm::DenseMapInfo<mlir::Type>::getTombstoneKey(), mlir::ArrayAttr()};
  }
  static unsigned getHashValue(const Key &key) {
    return llvm::hash_combine(key.carrier, key.labels.getAsOpaquePointer());
  }
  static bool isEqual(const Key &a, const Key &b) { return a == b; }
};

namespace idr::defunctionalize {

// How a force calls its memo family's dispatch function: the function and
// its name, the cell's indices it passes, and what the function takes and
// gives at them.
struct Dispatcher {
  FuncOp fn;
  mlir::FlatSymbolRefAttr name;
  IndexArgsAttr indices;
  mlir::Type takes, gives;
};

// What the decision holds for one key: its family's declaration; the
// family applied to the key's own index variables, in the order its
// carrier first names them, which every slot of the key holds; and for a
// lazy key, how a force calls its dispatch function.
struct Family {
  Key key;
  DataType type;
  DataType at;
  Dispatcher force;
};

// A function's signature as its slots have it.
struct Signature {
  mlir::FunctionType converted;
  llvm::SmallVector<Slot> arguments, results;
};

// A function whose body runs a label, by its id in the program graph: its
// row in the graph holds each label it runs as a call until the rewrite
// makes every run a call of its own, and is read again from those calls.
struct Runner {
  solver::FunctionId id;
  FuncOp fn;
};

// What a match over a family binds for one label, at the depth it is built
// at: the constructor's binders as the next levels, the value refined to
// it at the value's grade, and each field as a read gives it.
struct Case {
  IndexArgsAttr binders;
  mlir::Type refined;
  llvm::SmallVector<mlir::Type> fields;
};
// A label's function, as a case calls it: its name, and its converted
// signature at the case's binders, which the call passes as its indices.
struct Callee {
  FuncOp fn;
  mlir::FlatSymbolRefAttr name;
  mlir::FunctionType bound;
};
// A match over the family of a value of one type, built at one depth: its
// cases, one per label in tag order, and the labels' functions as each case
// calls them.
struct Match {
  mlir::DenseI32ArrayAttr tags;
  llvm::SmallVector<Case> cases;
  llvm::SmallVector<Callee> callees;
};

// A constructor: its type, refined to it at the grade it is built at, and
// each field as it holds it.
struct Built {
  mlir::Type type;
  llvm::SmallVector<mlir::Type> fields;
};
// A move between two keys: a match over the value's family whose cases
// rebuild each label's constructor in the sink's, one per case, at the
// sink's type; or, where no label reaches one of the two, a move that
// never runs, the program's poison.
struct Rebuild {
  MatchId over;
  mlir::Type sink;
  llvm::SmallVector<Built> into;
};
struct NeverRuns {
  mlir::Type sink;
};
using Coercion = std::variant<Rebuild, NeverRuns>;

// One function's edits, in the order the walk makes them.
//
// A value whose type changes, and its new type.
struct Retype {
  mlir::Value value;
  mlir::Type type;
};
// An operand whose value moves between two keys.
struct Move {
  mlir::OpOperand *use;
  CoercionId coercion;
};
// A closure, a suspension or an evaluated suspension: its constructor,
// whose fields are the op's operands.
struct Construct {
  mlir::Operation *op;
  Built built;
};
// An apply: a match over its callee's family whose cases call the labels,
// in each case the argument and result moves where the apply's keys and the
// label's differ; or, where no label reaches its callee, values the program
// never has.
struct CaseMoves {
  llvm::SmallVector<std::optional<CoercionId>> arguments, results;
};
struct Dispatch {
  FnApplyOp op;
  MatchId match;
  llvm::SmallVector<CaseMoves> cases;
};
struct Unreached {
  FnApplyOp op;
};
using Apply = std::variant<Dispatch, Unreached>;
// A force: a call of its cell's dispatch function, the value moved out of
// the forced state's slot into the force's where the two differ.
struct Force {
  LazyForceOp op;
  KeyId memo;
  std::optional<CoercionId> moved;
};
// A constant holding a closure, converted to its slot.
struct Constant {
  ConstantOp op;
  mlir::Attribute value;
};
struct Edits {
  FuncOp fn;
  footprint::Vector<Retype> retypes;
  footprint::Vector<Move> moves;
  footprint::Vector<Construct> constructs;
  footprint::Vector<Apply> applies;
  footprint::Vector<Force> forces;
  footprint::Vector<Constant> constants;
};

// The decision. It exists only whole: `decide`, its one maker, returns it
// once every part is made, so no reader meets a key without its family, a
// signature not yet converted, or an edit without its types. It is read
// only afterwards, from any thread, through const references.
class Decision {
public:
  // Every key the program asks for, each key's family, every signature,
  // each memo family's dispatch function added to the program, and each
  // function's edits with every type and attribute they build. Before any
  // type changes, `graph`, the program's calls, takes the label solve's runs
  // as calls, and every function's atoms are joined over it, the join's
  // work added to `work`: a label whose row reads or writes the outside
  // runs by name. Failure, after an internal error, only where the
  // compiler broke its own invariant.
  static mlir::FailureOr<std::unique_ptr<Decision>>
  decide(ProgramOp program, const Labels &labels, solver::ProgramGraph &graph, solver::Work &work);

  // Each function the program had, with its edits, in the program's order.
  llvm::ArrayRef<Edits> edits() const { return planned; }
  const Family &family(KeyId id) const { return families[static_cast<unsigned>(id)]; }
  const Match &match(MatchId id) const { return matches[static_cast<unsigned>(id)]; }
  const Coercion &coercion(CoercionId id) const {
    return coercions[static_cast<unsigned>(id)];
  }
  // The index a read of field `index` names.
  mlir::IntegerAttr fieldIndex(unsigned index) const { return fieldIndices[index]; }
  mlir::ub::PoisonAttr poison() const { return poisoned; }

  // Every force function the decision defined.
  llvm::ArrayRef<FuncOp> forces() const { return made; }
  // Every function whose row the decision gave the labels it runs.
  llvm::ArrayRef<Runner> runners() const { return running; }

  unsigned numFamilies() const { return static_cast<unsigned>(families.size()); }

private:
  Decision(ProgramOp program, const Labels &labels);

  // The keys (Decide.cpp).
  Slot keyWith(mlir::Type carrier, const FlowPoint &point) const;
  Slot anchorKey(const FlowAnchor &anchor) const;
  Slot keyOf(mlir::Value value) const;
  Slot sinkOf(mlir::OpOperand &use) const;
  const Signature &signature(mlir::StringAttr fn) const { return signatures.find(fn)->second; }
  KeyId idOf(const Key &key) const { return ids.find(key)->second; }
  const Family &familyOf(const Key &key) const { return family(idOf(key)); }
  void note(llvm::ArrayRef<Slot> slots, llvm::ArrayRef<mlir::Type> types);
  void slotsIn(mlir::Type type, llvm::SmallVectorImpl<Slot> &out) const;
  void widen();

  // The program graph completed by the label solve's runs: each function
  // that runs labels holds each as a call of no tail kind yet, which the
  // atoms' join never reads (Decide.cpp).
  void complete(solver::ProgramGraph &graph,
                IndexVector<solver::FunctionId, footprint::Vector<solver::FunctionId>> &ran);

  // The families (Declare.cpp); `atoms` is each function's row over
  // `calls`, the completed graph.
  mlir::LogicalResult declare(const solver::ProgramGraph &calls,
                              const IndexVector<solver::FunctionId, effects::Row> &atoms);

  // Types (Convert.cpp): every signature converted and set on its
  // function; the type of a slot whose type was `type`, its key's family at
  // `type`'s grade or `type` itself, its composites remade for their own
  // slots; a constant converted to its slot; the tag of `label`'s
  // constructor in `key`'s family; and the constructors, matches and
  // coercions the edits build, each match and coercion made once.
  void convertSignatures();
  mlir::Type typeOf(mlir::Type type, const Slot &slot);
  mlir::Attribute constantOf(mlir::Attribute value, const Slot &slot);
  Tag tagOf(const Key &key, mlir::FlatSymbolRefAttr label) const;
  Built constructorOf(DataType family, Tag tag, Grade grade,
                      llvm::ArrayRef<families::TermNode> binders);
  MatchId matchOver(mlir::Type value, unsigned depth, mlir::ArrayAttr set);
  CoercionId coercionOf(mlir::Type value, const Key &from, const Key &to, unsigned depth);

  // The dispatch functions (Forces.cpp).
  mlir::FailureOr<FuncOp> defineForce(const Family &family);

  // Each function's edits (Edits.cpp).
  mlir::FailureOr<Edits> plan(FuncOp fn);

  ProgramOp program;
  const Labels &labels;
  mlir::MLIRContext *ctx;

  // A closure, suspension or constant whose every use moves it into one
  // key that holds its own labels takes that key.
  llvm::DenseMap<mlir::Value, Key> widened;
  // Every key, by its dense id in the order met.
  llvm::DenseMap<Key, KeyId> ids;
  footprint::Vector<Family> families;
  llvm::DenseMap<mlir::StringAttr, Signature> signatures;
  // Every type the program names, remade where its parts hold a slot:
  // the program's data families whose fields hold closures, the shaped
  // types whose elements do.
  mlir::AttrTypeReplacer replacer;
  // Each part of the program's constants converted in its slot.
  llvm::DenseMap<std::pair<mlir::Attribute, mlir::Attribute>, mlir::Attribute> converted;
  ClosureParts holding;
  // The matches and coercions the edits build, each once: a match by the
  // type of the value it matches and its depth, a coercion by that, the
  // key it moves into and its depth.
  footprint::Vector<Match> matches;
  footprint::Vector<Coercion> coercions;
  llvm::DenseMap<std::pair<mlir::Type, unsigned>, MatchId> matchIds;
  llvm::DenseMap<std::tuple<mlir::Type, unsigned, unsigned>, CoercionId> coercionIds;
  footprint::Vector<mlir::IntegerAttr> fieldIndices;
  mlir::ub::PoisonAttr poisoned;
  footprint::Vector<Edits> planned;
  footprint::Vector<FuncOp> made;
  footprint::Vector<Runner> running;
};

// One function's edits, from the decision alone: each value its new type,
// each move between two keys a coercion, each closure op what it means.
// The ops it replaces are erased once the walk ends; each call it made then
// takes its tail fact where it stands.
void rewrite(const Edits &edits, const Decision &decision);

// `value` given where `type` is asked: where only their uses differ, a
// grade cast; where their indices or refinements differ, a reindex, never
// a cast that forgets how the two are related. The refinements around it
// check the reindex: a case's equation makes a label's type at the case's
// binders its family's at the enclosing scope's, and a constructor refined
// to one tag stands for its family with no equation. The two never differ
// in both: a label's carrier is its key's up to its variables.
mlir::Value givenAs(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value, mlir::Type type);

} // namespace idr::defunctionalize

namespace idr::egraph {

// The e-graph's rule over an exchange whose cell a constructor built for
// it alone: no other reference reads the cell, so no reader sees it running
// or forced, and the exchange is its label's run in place, the captures the
// constructor's fields and the value given nowhere.
struct ForceFreshCell {
  using Root = MemoRunOp;
  static std::optional<Edit> decide(MemoRunOp run, const OperandFacts &facts);
  static void rewrite(MemoRunOp run, const Rewrite &chosen, mlir::RewriterBase &rewriter);
};
static_assert(SkeletonRule<ForceFreshCell>);

} // namespace idr::egraph

#endif // IDR_TRANSFORMS_DEFUNCTIONALIZE_H
