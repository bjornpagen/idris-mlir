// Specialization: idr-specialize, which clones a callee for a consumed
// result (raising) and for the static parts of its arguments
// (specialization), and calls the clone; idr-redirect, which calls a clone
// the module already holds, per function; and idr-binding-times, which
// reports what a call may specialize on. What the library's units share is
// in idr::specialize.
#ifndef IDR_TRANSFORMS_SPECIALIZE_H
#define IDR_TRANSFORMS_SPECIALIZE_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Support/Actions.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <variant>
#include <vector>

namespace idr {

#define GEN_PASS_DECL_IDRSPECIALIZE
#define GEN_PASS_DECL_IDRREDIRECT
#define GEN_PASS_DECL_IDRBINDINGTIMES
#include "idr/Transforms/Passes.h.inc"

class Holds;
class References;

// idr-specialize raises a call into a clone that takes its consumer.
struct RaiseAction : support::TaggedAction<RaiseAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-raise";
};

// idr-specialize redirects a call to a clone of its callee.
struct SpecializeCloneAction : support::TaggedAction<SpecializeCloneAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-specialize-clone";
};

} // namespace idr

namespace idr::specialize {

struct Statistics {
  uint64_t clones = 0;
  uint64_t raised = 0;
  uint64_t shared = 0;
  // The static arguments specialized on, by the binding time of their
  // parameter.
  uint64_t free = 0;
  uint64_t fixed = 0;
  uint64_t decreasing = 0;
  uint64_t bounded = 0;
};

// The static shape of a value: what is known of it where it is built, over
// the runtime leaves it holds. A pattern is a hole (a runtime leaf), a
// constant, or a constructor or closure over the patterns of its operands.
// A shape is taken once per argument of a call, with its leaves; the clone
// is rebuilt from the pattern alone, each hole standing for the parameter
// that holds its leaf, so that what the key says and what the clone
// computes cannot differ.
struct Pattern;

// A runtime leaf: which leaf of its key it is, counting the key's holes in
// order. How often the clone may use it is its type's to say: a leaf reached
// through a linear parameter, field or capture has a linear type.
struct Hole {
  unsigned index;
};

struct Constant {
  mlir::Attribute value;
};

struct Con {
  mlir::SymbolRefAttr ctor; // `@T::@C`
  std::vector<Pattern> fields;
};

struct Closure {
  mlir::FlatSymbolRefAttr callee;
  std::vector<Pattern> captures;
};

// A value entered into a linear type (`idr.lin.enter`): rebuilt, it enters
// again, so the clone keeps the quantity Idris proved.
struct Linear {
  // Exactly one: the pattern of the value that entered.
  std::vector<Pattern> value;
};

struct Pattern {
  std::variant<Hole, Constant, Con, Closure, Linear> node;
  mlir::Type type;
  // Where the value was built: the ops that rebuild it are reported there.
  mlir::LocationAttr loc;

  bool isHole() const { return std::holds_alternative<Hole>(node); }
};

// The visitor of a pattern's node: one callable per case.
template <typename... Cases> struct Match : Cases... {
  using Cases::operator()...;
};

// One argument of a call: its pattern, whose holes are numbered from 0 and
// then among the key's, its runtime leaves in that order, and the binding
// time of its parameter.
struct Argument {
  Pattern pattern;
  llvm::SmallVector<mlir::Value> leaves;
  BindingTime time;
};

// A call's specialization key, composed over the patterns of its owner's
// parameters: the arguments, the value the call passes for each hole of
// the key, and for each argument the holes it fills.
struct Composed {
  llvm::SmallVector<Argument> args;
  SpecKeyAttr key;
  llvm::SmallVector<mlir::Value> values;
  llvm::SmallVector<llvm::SmallVector<unsigned>> held;
};

// The single consumer of a call's result that raising moves into a clone of
// the callee: the elimination that is all its one use does with it. It is
// op handles, passed by value as ops are.
using Consumer = idr::Elimination;

// A call of a generation, with the function it names.
struct Call {
  idr::CallOp call;
  idr::FuncOp callee;
};

// A clone a generation made, and whether it unrolls a decreasing
// parameter, which settles whether it breaks its callee's loop.
struct Entry {
  idr::FuncOp clone;
  bool unrolls;
};

// What the boundary finds in one clone once it is canonicalized: its calls
// of functions, in walk order, and whether it refers to any function.
struct Slot {
  llvm::SmallVector<Call> calls;
  bool refers = false;
};

// Patterns (Patterns.cpp).
Pattern leafOf(mlir::Value value, unsigned index);
Pattern shapeOf(mlir::Value value, llvm::SmallVectorImpl<mlir::Value> &leaves);
mlir::Value rebuild(mlir::OpBuilder &b, const Pattern &pattern, llvm::ArrayRef<mlir::Value> holes);
void renumber(Pattern &pattern, unsigned &next);
void labels(const Pattern &pattern, llvm::SmallVectorImpl<mlir::FlatSymbolRefAttr> &out);
bool hasStructure(const Pattern &pattern);
uint64_t unrollSize(const Pattern &pattern);
bool isClosed(mlir::Value value);
bool usedOnce(mlir::Value value);
void eraseUnused(mlir::RewriterBase &rewriter, llvm::ArrayRef<mlir::Value> values);

// Keys (Keys.cpp).
mlir::Attribute keyOf(const Pattern &pattern);
std::optional<Composed> composeKey(idr::CallOp call, const CloneTable &clones,
                                   const BindingTimes &times);

// Raising's condition and key (Consumer.cpp).
std::optional<Consumer> consumerOf(idr::CallOp call, const Holds &holds);
mlir::Attribute raiseKey(idr::CallOp call, Consumer consumer);

// Calling a clone (Redirect.cpp): a raised one with the consumer it took,
// a specialization without.
std::optional<idr::CallOp> redirect(mlir::RewriterBase &rewriter, idr::CallOp call,
                                    const Clone &clone, llvm::ArrayRef<mlir::Value> operands,
                                    std::optional<Consumer> consumer);

// Making clones, and the boundary between generations (Clones.cpp).
mlir::FailureOr<idr::FuncOp> makeClone(mlir::RewriterBase &rewriter, idr::FuncOp from,
                                       mlir::StringAttr owner, CloneTable::Kind kind,
                                       mlir::Operation *at, mlir::SymbolTable &symbols,
                                       const CloneTable &clones);
void giveFirstFacts(idr::FuncOp clone, idr::FuncOp origin, llvm::ArrayRef<idr::FuncOp> labels,
                    const Holds &holds);
Slot canonicalizeAndCollect(idr::FuncOp clone, const mlir::FrozenRewritePatternSet &patterns,
                            const mlir::SymbolTable &symbols);
llvm::SmallVector<Call> settle(llvm::ArrayRef<Entry> made, llvm::ArrayRef<Slot> slots);

// One run of idr-specialize over the analyses it holds. It raises, then
// specializes, every call of every function, and of every clone made on the
// way, a generation at a time.
class Specializer {
public:
  Specializer(mlir::ModuleOp module, mlir::SymbolTable &symbols, const References &references,
              CloneTable &clones, const BindingTimes &times, const Holds &holds,
              const mlir::FrozenRewritePatternSet &patterns);

  // Fails once a budget is spent.
  mlir::LogicalResult run();

  Statistics stats;
  // Whether a call was replaced or a clone made.
  bool changed = false;

private:
  // What raising produced: the call to specialize, and the function it
  // names. A null call means `call` was not raised.
  struct Raised {
    idr::CallOp call;
    idr::FuncOp callee;
  };

  // Raising (Raise.cpp).
  mlir::FailureOr<Raised> raise(idr::CallOp call, idr::FuncOp callee);
  mlir::FailureOr<const Clone *> makeRaised(idr::FuncOp callee, idr::CallOp call,
                                            Consumer c, mlir::Attribute key);
  // Specialization (Specialization.cpp).
  mlir::LogicalResult specialize(idr::CallOp call, idr::FuncOp callee);
  void substitute(idr::FuncOp clone, const Composed &composed);

  mlir::ModuleOp module;
  mlir::SymbolTable &symbols;
  const References &references;
  CloneTable &clones;
  const BindingTimes &times;
  const Holds &holds;
  const mlir::FrozenRewritePatternSet &patterns;
  mlir::IRRewriter rewriter;
  // The clones this generation made, in the order it made them.
  llvm::SmallVector<Entry> made;
};

} // namespace idr::specialize

#endif // IDR_TRANSFORMS_SPECIALIZE_H
