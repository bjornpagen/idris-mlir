// The guards that can never crash, erased, so that a proof is the guard's
// absence and lowering has nothing to check. A proof is a system of linear
// constraints over the integers (System) from the path to the guard, the
// bounds its loops keep their counters in (Induction), and which integers
// are the lengths of which arrays (Lengths). idr-in-bounds builds Lengths
// once for the module, then proves each function on its own
// (idr-in-bounds-prove): everything a proof needs of another function is a
// table of Lengths, filled before any guard goes.
#ifndef IDR_TRANSFORMS_INBOUNDS_H
#define IDR_TRANSFORMS_INBOUNDS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/DynamicAPInt.h"
#include "llvm/ADT/SmallVector.h"

#include <functional>
#include <memory>
#include <optional>
#include <tuple>
#include <vector>

namespace idr {
#define GEN_PASS_DECL_IDRINBOUNDS
#include "idr/Transforms/Passes.h.inc"

class Ranges;
} // namespace idr

namespace idr::inbounds {

// sum(coefficient * column) + constant, with unbounded coefficients.
struct Linear {
  llvm::SmallVector<std::pair<unsigned, llvm::DynamicAPInt>> terms;
  llvm::DynamicAPInt constant{0};

  static Linear of(unsigned column);
  static Linear constantOf(const llvm::DynamicAPInt &k);
  Linear &plus(const Linear &other, const llvm::DynamicAPInt &k);
  Linear &plus(int64_t k);
};
Linear operator-(Linear a, const Linear &b);
Linear operator+(Linear a, const Linear &b);

// 2^width.
llvm::DynamicAPInt power(unsigned width);
// The width of an integer the system has columns for; 0 for an index (the
// target's); none for anything else, i1 included (a branch's condition).
std::optional<unsigned> widthOf(mlir::Type type);
bool isColumn(mlir::Value value);

// The least and the greatest value of an integer.
using Bounds = std::pair<llvm::DynamicAPInt, llvm::DynamicAPInt>;
// The bounds a loop-carried integer is proven to keep at every iteration;
// none for any other value, or when none is known.
using CarriedBounds = std::function<std::optional<Bounds>(mlir::Value)>;
// Whether `array` has `max(size, 0)` elements wherever both are in scope at
// the guard a system is for.
using Related = std::function<bool(mlir::Value size, mlir::Value array)>;

class Lengths;

// What is known of the integers at one guard, as a system of linear
// constraints over the integers that MLIR's Presburger library decides
// exactly. A column is an SSA integer, as its latest value at the guard, or
// an array's length, or a witness the encoding needs. Every constraint is
// true of the run; one left out only makes the system prove less, so an op
// the encoding does not know is a column with its range alone. Integers are
// machine words, which wrap, and the wrapping is encoded exactly.
class System {
public:
  System(const Lengths &lengths, std::function<bool(mlir::Value)> admissible,
         CarriedBounds carried = nullptr, Related related = nullptr);

  // The column of `value`, with its range, and its definition if known.
  Linear of(mlir::Value value);
  // Whether `value`'s definition is known at the guard this system is for.
  bool known(mlir::Value value) const { return admissible(value); }
  // The integer a guard of `array` checks an index against.
  Linear sizeOf(mlir::Value length, std::optional<mlir::Value> array);
  // The length of the array `array` (its root's, which views share).
  Linear lengthOf(mlir::Value array);
  // A witness in [lo, hi].
  Linear fresh(const llvm::DynamicAPInt &lo, const llvm::DynamicAPInt &hi);
  void atLeastZero(Linear e) { rows.push_back({std::move(e), false}); }
  void zero(Linear e) { rows.push_back({std::move(e), true}); }
  void impossible() { atLeastZero(Linear().plus(-1)); }
  void within(const Linear &e, const llvm::DynamicAPInt &lo, const llvm::DynamicAPInt &hi);
  // The analysis's range of `value`, else its type's, within its loop's.
  std::optional<Bounds> rangeOf(mlir::Value value) const;
  // `x pred y` held, or did not.
  void compare(mlir::arith::CmpIPredicate predicate, mlir::Value x, mlir::Value y, bool holds);
  // The condition `condition` (an i1) held, or did not.
  void assume(mlir::Value condition, bool holds);
  // The arrays with length columns, and the values with columns, in the
  // order they got them.
  llvm::SmallVector<mlir::Value> roots() const;
  llvm::SmallVector<mlir::Value> values() const;
  // The array `array` has `max(size, 0)` elements. Said once per pair.
  void lengthIs(mlir::Value size, mlir::Value array);
  // Whether `max(a, 0)` and `max(b, 0)` are the same integer.
  bool sameClamp(mlir::Value a, mlir::Value b);
  // Whether no integers satisfy every constraint and `extra >= 0`.
  bool emptyWith(const Linear &extra) const;
  // Whether every integer the system allows for `value` is at least 0.
  bool nonNegative(mlir::Value value);

private:
  struct Row {
    Linear e;
    bool equality;
  };
  Linear clamped(mlir::Value value);
  Linear unsignedOf(mlir::Value x, unsigned width);
  void wrapped(const Linear &v, Linear e, unsigned width, bool noWrap, int64_t bound);
  void define(mlir::Value value, const Linear &v);

  const Lengths &lengths;
  std::function<bool(mlir::Value)> admissible;
  CarriedBounds carried;
  Related related;
  llvm::DenseMap<mlir::Value, unsigned> columns;
  llvm::DenseMap<mlir::Value, unsigned> lengthColumns;
  llvm::DenseSet<std::pair<mlir::Value, mlir::Value>> stated;
  llvm::SmallVector<Row> rows;
  unsigned count = 0;
  unsigned definitions = 0;
};

// Whether a value is known at `op`: computed before it on every path, or in
// the before block of a loop whose body, holding `op`, runs on what it computed.
std::function<bool(mlir::Value)> knownAt(mlir::Operation *op, mlir::DominanceInfo &dominance);
// Adds what the path from its function's entry to `at` says.
void pathFacts(mlir::Operation *at, System &system);
// The Euclidean quotients among the values `system` already holds, divided
// by a positive constant.
void relateQuotients(System &system);

// The bounds each scf.while keeps its carried integers in, each proven the
// first time it is asked about, by induction over the iterations.
class Induction {
public:
  Induction(const Lengths &lengths, mlir::DominanceInfo &dominance)
      : lengths(lengths), dominance(dominance) {}
  // The bounds of `value` at every iteration of the loop that carries it,
  // or of the value its condition forwarded as `value` to its body; none
  // for any other value, or one being proven.
  std::optional<Bounds> boundsOf(mlir::Value value);
  CarriedBounds asCarried() {
    return [this](mlir::Value value) { return boundsOf(value); };
  }

private:
  std::optional<Bounds> prove(mlir::scf::WhileOp loop, mlir::BlockArgument x);
  const Lengths &lengths;
  mlir::DominanceInfo &dominance;
  llvm::DenseMap<mlir::Value, std::optional<Bounds>> proven;
};

// A component of the record it was read from: a field read, a take's
// field, a match case's argument. Views are not stripped here.
struct Component {
  mlir::Value record;
  mlir::StringAttr ctor;
  uint64_t index;
};
std::optional<Component> componentOf(mlir::Value value);
// The array `dim` measures: an array's one dimension is its length.
std::optional<mlir::Value> dimensionOf(mlir::memref::DimOp dim);
// What `value` clamps at 0 from below: `x` when it is `max(x, c)`, either
// way round, for a constant `c` of at most 0.
std::optional<mlir::Value> clampOf(mlir::Value value);
// The array whose length `length` is: its one dimension made i64.
std::optional<mlir::Value> measured(mlir::Value length);
std::optional<unsigned> positionIn(mlir::ValueRange inputs, mlir::Value value);

// A pair whose values are both bound at one join that is not inside one
// function: a function's parameters, bound by its calls, or its results,
// bound by its returns. A size and an array; a size and the array field of
// a record; or a record's size field and array field. Each holds or not for
// the whole module, so it is decided once and read by every function.
struct InterfaceKey {
  enum class Side : unsigned { Parameters, Results };
  enum class Shape : unsigned { Pair, Component, Fields };
  mlir::Operation *function = nullptr;
  Side side = Side::Parameters;
  Shape shape = Shape::Pair;
  // The size's position and the array's or the record's (Fields: the record's).
  unsigned first = 0;
  unsigned second = 0;
  // For Component the array field; for Fields the size and the array field.
  mlir::StringAttr ctor = {};
  unsigned field = 0;
  unsigned other = 0;

  using Tuple = std::tuple<mlir::Operation *, unsigned, unsigned, unsigned, unsigned,
                           mlir::StringAttr, unsigned, unsigned>;
  Tuple tuple() const;
};

// A value bound from several places: the value each place gives it, in an
// order every value of the same join (`key`) shares. When `local`, every
// place is inside `owner` or is `owner`, where a value defined before it
// keeps one value throughout. A join that is not local lists no places: it
// is the parameter or the result `position` of `function`, an interface.
struct Join {
  const void *key;
  mlir::Operation *owner;
  bool local;
  llvm::SmallVector<mlir::Value> incoming;
  mlir::Operation *function = nullptr;
  InterfaceKey::Side side = InterfaceKey::Side::Parameters;
  unsigned position = 0;
};

// A projection of a record: field `index` of constructor `ctor`.
struct Proj {
  mlir::StringAttr ctor;
  uint64_t index;
};

// What a result of a function is, in terms of its parameters: not yet
// constrained, no one argument, one argument with the projections still to
// read from it, or a constructor each return built, with what each field is.
struct Origin {
  enum Kind { Unknown, None, Argument, Built } kind = Unknown;
  unsigned argument = 0;
  llvm::SmallVector<Proj, 4> inside;
  mlir::StringAttr ctor;
  std::vector<Origin> fields;

  static Origin unknown() { return {}; }
  static Origin none();
  static Origin arg(unsigned index, llvm::ArrayRef<Proj> path);
  // A constructor none of whose fields is an argument is none: no read of
  // it is an argument either.
  static Origin built(mlir::StringAttr ctor, std::vector<Origin> fields);
  bool operator==(const Origin &other) const;
  Origin meet(const Origin &other) const;
  Origin project(Proj proj) const;
};

// An array a call gives back, as the operand of `call` it is, so that a size
// the same call gives back beside it is read the same way.
struct GivenBack {
  CallOp call;
  mlir::Value value;
};

// Which integers are the lengths of which arrays, across the module's calls,
// built eagerly once and then only read, from several threads at once.
class Lengths {
public:
  class Local;

  Lengths(mlir::Operation *module, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // The range the module's solver recorded for `value`; none where the
  // analysis never reached it, which proves nothing.
  std::optional<mlir::ConstantIntRanges> rangeOf(mlir::Value value) const;
  // The calls of a private function every use of which is a direct call:
  // the only places its parameters are bound. Null for any other function.
  const llvm::SmallVector<CallOp> *callsOf(FuncOp fn) const;
  llvm::ArrayRef<ReturnOp> returnsOf(FuncOp fn) const;
  // What result `slot` of `fn` gives back; none for a function not solved.
  const Origin &given(FuncOp fn, unsigned slot) const;
  // Whether the pair bound at an interface holds everywhere it is bound.
  bool interface(const InterfaceKey &key) const;
  // The relation asked within one function, on that function's values.
  Local local(FuncOp fn, const mlir::SymbolTable &symbols, mlir::DominanceInfo &dominance) const;

private:
  const Ranges &ranges;
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<CallOp>> calls;
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<ReturnOp>> returns;
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<Origin>> returned;
  llvm::DenseMap<InterfaceKey::Tuple, bool> interfaces;
  Origin missing = Origin::none();
};

// The questions of one function, with every mutable thing they keep: the
// pair graph's memo, the clamp cache, the scratch of the given-back walk.
// The constructor of Lengths asks through one with no function, which
// follows an interface into the callers or the returns that bind it; the
// Local of a function reads the interface from the table instead.
class Lengths::Local {
public:
  // Whether `array` has `max(size, 0)` elements wherever both are in scope.
  bool related(mlir::Value size, mlir::Value array);
  // The caller-side value `value` is, when a call gives it back.
  std::optional<GivenBack> givenBack(mlir::Value value);
  // Whether `key` holds, deciding it with every pair it needs; the states
  // of every interface decided so far.
  bool holds(const InterfaceKey &key);
  llvm::DenseMap<InterfaceKey::Tuple, bool> interfaces() const;

  const Lengths &lengths() const { return *owner; }
  const mlir::SymbolTable &symbols() const { return *table; }
  mlir::DominanceInfo &dominance() const { return *dominanceInfo; }
  bool expands() const { return !fn; }

private:
  friend class Lengths;
  Local(const Lengths &analysis, const mlir::SymbolTable &symbolTable, mlir::DominanceInfo &info,
        FuncOp function)
      : owner(&analysis), table(&symbolTable), dominanceInfo(&info), fn(function) {}

  enum class Kind : unsigned { Pair, Component, Fields, Interface };
  enum class State { Open, Held, Broken };
  // A size and an array (a, b); a size and the array field `i` of record b;
  // the size field `i` and the array field `j` of record a; an interface.
  struct Question {
    Kind kind = Kind::Pair;
    mlir::Value a, b;
    mlir::StringAttr ctor;
    unsigned i = 0, j = 0;
    // How many records were followed to reach this one.
    unsigned depth = 0;
    InterfaceKey key;
  };
  struct Node {
    Question question;
    State state = State::Open;
    llvm::SmallVector<unsigned> needs = {};
    llvm::SmallVector<unsigned> neededBy = {};
  };
  using ValueKey =
      std::tuple<unsigned, mlir::Value, mlir::Value, mlir::StringAttr, unsigned, unsigned>;

  bool holds(const Question &question);
  void solve(llvm::SmallVectorImpl<unsigned> &fresh);
  unsigned nodeOf(const Question &question, llvm::SmallVectorImpl<unsigned> &fresh);
  std::optional<llvm::SmallVector<Question>> needsOf(const Question &question);
  std::optional<llvm::SmallVector<Question>> pairNeeds(mlir::Value size, mlir::Value array);
  std::optional<llvm::SmallVector<Question>> componentNeeds(const Question &question);
  std::optional<llvm::SmallVector<Question>> fieldNeeds(const Question &question);
  std::optional<llvm::SmallVector<Question>> interfaceNeeds(const InterfaceKey &key);
  bool clampsEqual(mlir::Value size, mlir::Value made);
  bool agrees(mlir::Value size, mlir::Value made, llvm::DenseSet<mlir::Value> &seen);
  bool atPoint(mlir::Operation *at, mlir::Value condition, bool holds, mlir::Value size,
               mlir::Value made, llvm::DenseSet<mlir::Value> &seen);
  bool eachEdge(mlir::RegionBranchOpInterface branch, mlir::Value size, mlir::Value made,
                llvm::DenseSet<mlir::Value> &seen);
  std::optional<GivenBack> fromCall(CallOp call, unsigned slot, llvm::ArrayRef<Proj> path);
  mlir::Value materialize(mlir::Value value, llvm::ArrayRef<Proj> path);

  const Lengths *owner;
  const mlir::SymbolTable *table;
  mlir::DominanceInfo *dominanceInfo;
  FuncOp fn;
  llvm::DenseMap<ValueKey, unsigned> valueNodes;
  llvm::DenseMap<InterfaceKey::Tuple, unsigned> interfaceNodes;
  llvm::SmallVector<Node> nodes;
  llvm::DenseMap<std::pair<mlir::Value, mlir::Value>, bool> clampCache;
  llvm::DenseSet<std::pair<mlir::Value, mlir::Value>> clampOpen;
  llvm::DenseSet<mlir::Value> chasing;
};

// The join `value` is bound at, or none when it is computed by one op or
// bound where not every place is known.
std::optional<Join> joinOf(mlir::Value value, const Lengths::Local &lengths);

// What each function's results are, as the greatest fixpoint over the
// module's calls; `whole` is the constructor's Local, for the joins.
llvm::DenseMap<mlir::Operation *, llvm::SmallVector<Origin>>
returnedOrigins(mlir::ModuleOp module, const Lengths::Local &whole);

// When `index` is `x & (c - 1)`, `c` is a positive power of two the system
// already knows, and `array`'s length is `c`: `0 <= index < c`.
void relateMask(System &system, Lengths::Local &lengths, mlir::DominanceInfo &dominance,
                mlir::Operation *at, mlir::Value array, mlir::Value index);

// The array of the access whose index is `guard`'s result, directly or
// through the access's own guard. None when no array access takes it.
std::optional<mlir::Value> accessedArray(CheckInBoundsOp guard);
// The array whose length `guard`'s length stands for: the one it measures,
// else the one its access reads.
std::optional<mlir::Value> guardedArray(CheckInBoundsOp guard);

// The proofs of one idr.func, run only by idr-in-bounds under the Lengths
// and the SymbolTable it computed for the module.
std::unique_ptr<mlir::Pass> createProveInBoundsPass();

} // namespace idr::inbounds

#endif // IDR_TRANSFORMS_INBOUNDS_H
