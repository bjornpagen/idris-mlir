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
// then one walk per function, in parallel, gives each value its type in
// place and replaces each closure op by what it means, reading the
// decision and nothing else. No conversion driver, no pattern set and no
// type made on a worker: every family and type the walk needs is made in
// the decision.
//
// A key is a slot's carrier at no grade and the labels the solve found for
// it. A closure key becomes a closure family, one label per function of
// its set; a lazy key a memo family, its labels each memoized or run by
// name, then its two states. A label runs by name exactly when its row
// reads or writes the outside: memoizing it would run its effect once
// instead of at each demand.
#ifndef IDR_TRANSFORMS_DEFUNCTIONALIZE_H
#define IDR_TRANSFORMS_DEFUNCTIONALIZE_H

#include "idr/Analysis/Labels.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/EGraph.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallVector.h"

#include <memory>
#include <optional>

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

// What the decision holds for one key: its family's type, and for a lazy
// key its dispatch function.
struct Family {
  Key key;
  DataType type;
  mlir::FlatSymbolRefAttr force;
};

// A function's signature as its slots have it.
struct Signature {
  mlir::FunctionType converted;
  llvm::SmallVector<Slot> arguments, results;
};

// The decision. It exists only whole: `decide`, its one maker, returns it
// once every part is made, so no reader meets a key without its family or
// a signature not yet converted. It is read only afterwards, from any
// thread.
class Decision {
public:
  // Every key the program asks for, each key's family, every signature,
  // each memo family's dispatch function added to the program, every
  // constant converted. `byName` holds each label whose row reads or writes
  // the outside. Failure, after an internal error, only where the compiler
  // broke its own invariant.
  static mlir::FailureOr<std::unique_ptr<Decision>>
  decide(ProgramOp program, const Labels &labels, const llvm::DenseSet<mlir::StringAttr> &byName);

  // Keys of the slots the walk meets.
  Slot keyOf(mlir::Value value) const;
  Slot sinkOf(mlir::OpOperand &use) const;
  const Signature &signature(mlir::StringAttr fn) const { return signatures.find(fn)->second; }

  // The type of a slot whose type was `type`: its key's family at `type`'s
  // grade, or `type` itself, its composites remade for their own slots.
  mlir::Type typeOf(mlir::Type type, const Slot &slot) const;
  const Family &familyOf(const Key &key) const { return families[static_cast<unsigned>(ids.find(key)->second)]; }
  // The tag of `label`'s constructor in `key`'s family: a key's labels, in
  // the order of their functions in the program, are its family's tags in
  // order.
  Tag tagOf(const Key &key, mlir::FlatSymbolRefAttr label) const;
  // A constant of the program converted to its slots, or the constant
  // itself where it holds no closure.
  mlir::Attribute constantOf(mlir::Attribute value, const Slot &slot) const;
  // Every force function the decision defined.
  llvm::ArrayRef<FuncOp> forces() const { return made; }

  unsigned numFamilies() const { return static_cast<unsigned>(families.size()); }

private:
  Decision(ProgramOp program, const Labels &labels);

  // The keys (Decide.cpp).
  Slot keyWith(mlir::Type carrier, const FlowPoint &point) const;
  Slot anchorKey(const FlowAnchor &anchor) const;
  void note(const Slot &slot);
  void noteType(mlir::Type type);
  void widen();

  // The families, signatures and constants (Declare.cpp).
  mlir::LogicalResult declare(const llvm::DenseSet<mlir::StringAttr> &byName);
  void convertSignatures();
  void convertConstants();

  // The dispatch functions (Forces.cpp).
  mlir::FailureOr<FuncOp> defineForce(const Family &family);

  ProgramOp program;
  const Labels &labels;
  mlir::MLIRContext *ctx;

  // A closure, suspension or constant whose every use moves it into one
  // key that holds its own labels takes that key.
  llvm::DenseMap<mlir::Value, Key> widened;
  // Every key, by its dense id in the order met.
  llvm::DenseMap<Key, KeyId> ids;
  llvm::SmallVector<Family> families;
  llvm::DenseMap<mlir::StringAttr, Signature> signatures;
  // Every type the program names, remade where its parts hold a slot:
  // the program's data families whose fields hold closures, the shaped
  // types whose elements do.
  mlir::AttrTypeReplacer replacer;
  // Each part of the program's constants converted in its slot.
  mutable llvm::DenseMap<std::pair<mlir::Attribute, mlir::Attribute>, mlir::Attribute> converted;
  llvm::SmallVector<FuncOp> made;
  ClosureParts holding;
};

// One function, from the decision alone: each value of a closure or a
// suspension its family's type, every other value its type remade, each
// move between two keys a coercion, each closure op what it means. The
// ops it replaces are erased once the walk ends, so no value the solve
// names is freed while the walk reads the solve.
mlir::LogicalResult rewrite(FuncOp fn, const Decision &decision);

// `value`, of key `from`'s family, as a value of `to`'s, whose labels hold
// `from`'s: a match rebuilding each of `from`'s constructors in `to`'s.
mlir::Value coerce(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value, const Key &from,
                   const Key &to, const Decision &decision);

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
