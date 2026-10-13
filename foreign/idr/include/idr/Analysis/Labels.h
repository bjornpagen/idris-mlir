// The labels (functions) each closure or suspension may hold, or unknown: a
// sparse forward dataflow analysis on MLIR's framework, interprocedural,
// solved once in the constructor. Values reach fields through one lattice
// anchor per (data type, constructor, field), written by idr.con and
// constants and read by idr.field and the regions of idr.match, and the
// elements of arrays through one anchor per element type, written by
// idr.array.new, idr.array.set and idr.array.generate and read by
// idr.array.get and the body of idr.array.fold. The framework follows only
// calls of symbols, so the analysis joins the rest itself: the entry
// arguments of a function get the captures of its closures and suspensions
// (idr.closure and idr.suspend ops and #idr.closure constants) and the
// arguments of every idr.apply that may call it, an idr.apply gets the
// results of every label it may call, and an idr.force those of every label
// its cell may hold. An evaluated suspension holds its value and no label.
//
// The analysis changes nothing, and nothing in it is filled on first ask
// but the anchors the solver uniques when one is read.
#ifndef IDR_ANALYSIS_LABELS_H
#define IDR_ANALYSIS_LABELS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Support/TypeID.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <iterator>
#include <tuple>

namespace idr {

// The labels a value may hold, sorted by name; `unknown` is the top, and
// the empty set, known, the bottom.
struct LabelSet {
  bool unknown = false;
  llvm::SmallVector<mlir::StringAttr> names;

  static LabelSet of(mlir::StringAttr name) {
    LabelSet out;
    out.names.push_back(name);
    return out;
  }

  static LabelSet top() {
    LabelSet out;
    out.unknown = true;
    return out;
  }

  static LabelSet join(const LabelSet &a, const LabelSet &b) {
    if (a.unknown || b.unknown)
      return top();
    LabelSet out;
    std::set_union(a.names.begin(), a.names.end(), b.names.begin(), b.names.end(),
                   std::back_inserter(out.names), [](mlir::StringAttr x, mlir::StringAttr y) {
                     return x.getValue() < y.getValue();
                   });
    return out;
  }

  bool mayHold(mlir::StringAttr name) const {
    return unknown || llvm::is_contained(names, name);
  }

  bool operator==(const LabelSet &other) const {
    return unknown == other.unknown && names == other.names;
  }

  void print(llvm::raw_ostream &os) const {
    if (unknown) {
      os << "unknown";
      return;
    }
    os << "{";
    llvm::interleaveComma(names, os, [&](mlir::StringAttr name) { os << "@" << name.getValue(); });
    os << "}";
  }
};

struct LabelLattice : mlir::dataflow::Lattice<LabelSet> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(LabelLattice)
  using Lattice::Lattice;
};

// A field of a constructor: (data type, constructor, index).
struct FieldAnchor
    : mlir::GenericLatticeAnchorBase<
          FieldAnchor, std::tuple<mlir::StringAttr, mlir::StringAttr, unsigned>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(FieldAnchor)
  using Base::Base;
  mlir::Location getLoc() const override {
    return mlir::UnknownLoc::get(std::get<0>(getValue()).getContext());
  }
  void print(llvm::raw_ostream &os) const override {
    auto [data, ctor, index] = getValue();
    os << "@" << data.getValue() << "::@" << ctor.getValue() << "[" << index << "]";
  }
};

// The elements of every array whose element type is this one: an array has
// one slot, as a constructor has one per field, and its element type, not
// the array value, names it, since a value of the type may be any array.
// Its rank does not: an IORef's one element and the elements of an array
// of the same type share the slot.
struct ElementsAnchor : mlir::GenericLatticeAnchorBase<ElementsAnchor, mlir::Type> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ElementsAnchor)
  using Base::Base;
  mlir::Location getLoc() const override { return mlir::UnknownLoc::get(getValue().getContext()); }
  void print(llvm::raw_ostream &os) const override { os << "elements of " << getValue(); }
};

// The labels a field, or the elements of arrays, may hold.
struct FieldLabels : mlir::AnalysisState {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(FieldLabels)
  using AnalysisState::AnalysisState;

  mlir::ChangeResult join(const LabelSet &other) {
    LabelSet joined = LabelSet::join(value, other);
    if (joined == value)
      return mlir::ChangeResult::NoChange;
    value = joined;
    return mlir::ChangeResult::Change;
  }

  void print(llvm::raw_ostream &os) const override { value.print(os); }

  LabelSet value;
};

// Whether the analysis follows the labels of a slot of `type`: a closure or
// a suspension, both of which name a function.
inline bool isKeyed(mlir::Type type) { return isClosureType(type) || isLazyType(type); }

// The index in its constructor of field `i` of a run's cell, which holds
// every field but the spine.
inline unsigned cellField(unsigned i, unsigned spine) { return i < spine ? i : i + 1; }

// Calls `visit(field, index)` for each field of `con` with its index in the
// constructor: a plain con's fields, or a run's cells, each without its
// spine field, which is the next cell, and then its tail, which fills the
// last cell's spine. A run is walked by its cells, never through its spine,
// which builds the rest of the run at each step.
inline void eachField(ConAttr con, llvm::function_ref<void(mlir::Attribute, unsigned)> visit) {
  if (!con.isRun()) {
    for (auto [i, field] : llvm::enumerate(con.getFields()))
      visit(field, static_cast<unsigned>(i));
    return;
  }
  unsigned spine = con.getSpine();
  for (mlir::ArrayAttr cell : con.getRunCells())
    for (auto [i, field] : llvm::enumerate(cell))
      visit(field, cellField(static_cast<unsigned>(i), spine));
  visit(con.getTail(), spine);
}

class Labels {
public:
  Labels(mlir::Operation *module, mlir::AnalysisManager &am);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<Labels>() || !pa.isPreserved<mlir::SymbolTable>();
  }

  // Whether the solver did not reach its fixpoint, which leaves every
  // answer below meaningless.
  bool failed() const { return diverged; }

  // What the analysis found for `value`, with the label of the closure,
  // suspension or constant that defines it.
  LabelSet labelsOf(mlir::Value value) const;
  // What field `index` of `ctor`, `@T::@C`, may hold.
  LabelSet fieldLabels(mlir::SymbolRefAttr ctor, unsigned index);
  // What the elements of arrays of `element` may hold.
  LabelSet elementLabels(mlir::Type element);

  // Whether a closure is inside the constant `attr`. A constant shares its
  // parts, so a tree may have far more paths than distinct parts: each part
  // of the module's constants was looked at once, and a walk of a constant
  // skips a part with no closure in it.
  bool holdsClosure(mlir::Attribute attr) const;

  // The sites the framework does not follow. The closure ops and closure
  // constants (their captures) of each label; the suspensions, which name a
  // function the way a closure does and whose captures flow into it, but
  // whose function is not a label an apply may call: a force calls it.
  llvm::ArrayRef<ClosureOp> closures(mlir::StringAttr label) const {
    return find(closureOps, label);
  }
  llvm::ArrayRef<mlir::ArrayAttr> closureConstants(mlir::StringAttr label) const {
    return find(constantClosures, label);
  }
  llvm::ArrayRef<SuspendOp> suspensions(mlir::StringAttr label) const {
    return find(suspendOps, label);
  }
  llvm::ArrayRef<mlir::ArrayAttr> suspensionConstants(mlir::StringAttr label) const {
    return find(suspendConstants, label);
  }
  llvm::ArrayRef<ApplyOp> applies() const { return applyOps; }
  // The applies that may call `label`, the function of a closure op or a
  // closure constant: those whose callee's type is its signature without
  // its captures. A suspension's function is no label.
  llvm::ArrayRef<ApplyOp> appliesFor(mlir::StringAttr label) const {
    return find(candidates, label);
  }
  // Whether `fn` is referenced other than by a call, a closure or a
  // constant, or is public: whoever names it may call it with anything.
  bool escapes(FuncOp fn) const {
    return fn.isPublic() || escaping.contains(fn.getSymNameAttr());
  }

  FuncOp function(mlir::StringAttr name) const { return table.lookup<FuncOp>(name); }
  // The type of field `index` of `ctor`, `@T::@C`, as declared, or null.
  mlir::Type fieldType(mlir::SymbolRefAttr ctor, unsigned index) const;

private:
  template <typename Map>
  static llvm::ArrayRef<typename Map::mapped_type::value_type>
  find(const Map &map, typename Map::key_type key) {
    auto it = map.find(key);
    if (it == map.end())
      return {};
    return it->second;
  }

  void gather(mlir::Operation *module);
  // Calls `visit(closure, type)` for each closure attribute inside `attr`, a
  // constant of type `type`.
  void closuresIn(mlir::Attribute attr, mlir::Type type,
                  llvm::function_ref<void(ClosureAttr, mlir::Type)> visit) const;

  mlir::SymbolTable &table;
  llvm::DenseMap<mlir::StringAttr, llvm::SmallVector<ClosureOp>> closureOps;
  llvm::DenseMap<mlir::StringAttr, llvm::SmallVector<mlir::ArrayAttr>> constantClosures;
  llvm::DenseMap<mlir::StringAttr, llvm::SmallVector<SuspendOp>> suspendOps;
  llvm::DenseMap<mlir::StringAttr, llvm::SmallVector<mlir::ArrayAttr>> suspendConstants;
  llvm::SmallVector<ApplyOp> applyOps;
  llvm::DenseMap<mlir::StringAttr, llvm::SmallVector<ApplyOp>> candidates;
  llvm::DenseSet<mlir::StringAttr> escaping;
  // holdsClosure's answers for every part of the module's constants.
  llvm::DenseMap<mlir::Attribute, bool> closureFree;
  mlir::DataFlowSolver solver;
  bool diverged = false;
};

} // namespace idr

#endif // IDR_ANALYSIS_LABELS_H
