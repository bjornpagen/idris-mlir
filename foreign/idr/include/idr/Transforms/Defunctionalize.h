// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-defunctionalize: closures and suspensions of known labels become sums,
// by one dialect conversion of the module.
//
// Sums are keyed by (closure or lazy type, label set), not by type alone.
// Every slot that holds a closure or a suspension (a value, a function
// argument or result, a field of a constructor, the elements of arrays) has
// the key of its type and the labels the analysis (idr::Labels) found for
// it; a closure, suspension or constant used only where one larger set is
// expected takes that set. Slots decides every key before anything changes;
// the conversion's type converter answers from it, so a slot's type is its
// key's sum, and a value that moves into a slot of another key is rebuilt
// there by the converter's one materialization.
#ifndef IDR_TRANSFORMS_DEFUNCTIONALIZE_H
#define IDR_TRANSFORMS_DEFUNCTIONALIZE_H

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SmallVector.h"

#include <tuple>
#include <utility>

namespace idr {

#define GEN_PASS_DECL_IDRDEFUNCTIONALIZE
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

namespace idr::defunctionalize {

// The key of a slot: its closure or lazy type and the labels it may hold,
// sorted by name, or null labels when they are unknown. A null type means
// the slot holds neither.
using Key = std::pair<mlir::Type, mlir::ArrayAttr>;

// A key the analysis could not convert: a suspension's (`lazy`) or a
// closure's, and the op where the analysis lost its value.
struct UnknownKey {
  mlir::Operation *at;
  bool lazy;
};

// The key decision: the key of every slot of the module, how values move
// between them, which keys become sums and each sum's type. Built whole by
// the constructor from the analysis and read only afterwards. Keys are by
// the module's values as they were, which the conversion keeps alive until
// it ends; a value the conversion made has no key, and its type is its own.
class Slots {
public:
  Slots(mlir::ModuleOp module, Labels &labels, mlir::SymbolTable &symbols);

  static bool isEmpty(const Key &key) { return key.second && key.second.empty(); }
  static bool isLazy(const Key &key) { return key.first && llvm::isa<LazyType>(key.first); }

  Key keyOf(mlir::Value value) const { return values.lookup(value); }
  Key argumentKey(mlir::StringAttr fn, unsigned index) const;
  Key resultKey(mlir::StringAttr fn, unsigned index) const;
  Key fieldKey(mlir::SymbolRefAttr ctor, unsigned index) const {
    return fieldKey(ctor.getRootReference(), ctor.getLeafReference(), index);
  }
  Key fieldKey(mlir::StringAttr data, mlir::StringAttr ctor, unsigned index) const {
    return fields.lookup({data, ctor, index});
  }
  Key elementKey(mlir::Type element) const { return arrays.lookup(element); }
  // The slot a use of the module moves its value into, or a null key.
  Key sinkKey(mlir::OpOperand &use) const;

  bool isConverted(const Key &key) const { return converted.contains(key); }
  // Whether no value of the program is ever in a slot of `key`: a closure's
  // empty key, or a lazy one that no evaluated suspension has either.
  bool unreached(const Key &key) const { return isEmpty(key) && !evaluated.contains(key); }
  bool needsCoercion(const Key &from, const Key &to) const {
    return from != to && (isConverted(from) || isConverted(to));
  }
  // The sum of `key`, or null when the key stays as it is.
  mlir::Type sumOf(const Key &key) const {
    return isConverted(key) ? sums.lookup(key) : mlir::Type();
  }
  // The type of a slot of `key` whose type was `type`: its sum or its type
  // unchanged, linear when `type` is; with no key, `type` with the arrays
  // in it retyped by their elements' keys.
  mlir::Type typeOf(mlir::Type type, const Key &key) const;
  mlir::Type typeOf(mlir::Value value) const;
  mlir::Type arrayed(mlir::Type type) const;
  // The signature of `fn` and the field types of `ctor` as their slots
  // have them.
  mlir::FunctionType functionType(FuncOp fn) const;
  llvm::SmallVector<mlir::Type> fieldTypes(CtorOp ctor) const;
  // The types of the captures of `label` as a closure or suspension of
  // `key`, as converted, and of the value a cell of lazy `key` holds once
  // forced.
  llvm::SmallVector<mlir::Type> captureTypes(mlir::StringAttr label, const Key &key) const;
  mlir::Type forcedType(const Key &key) const;

  // Every key by first appearance, with its sum when it is converted.
  const llvm::MapVector<Key, mlir::Type> &keys() const { return sums; }
  llvm::SmallVector<UnknownKey> unknownKeys() const;
  unsigned numClosures() const;

  Labels &labels() const { return analysis; }
  mlir::SymbolTable &symbols() const { return table; }

private:
  // A value moves from a slot of `from` into a slot of `to`.
  struct Flow {
    Key from, to;
  };

  // A function as the module declares it, with the key of each argument
  // and result. Read by name, so that a signature the conversion has
  // already changed answers as it did before.
  struct Signature {
    mlir::FunctionType type;
    bool external = false;
    llvm::SmallVector<Key> arguments, results;
  };

  // Keying (Keys.cpp).
  static unsigned arity(mlir::Type type);
  static bool within(const Key &a, const Key &b);
  Key keyOf(mlir::Type type, const LabelSet &labels) const;
  Key unknown(mlir::Type type) const;
  const Signature *signature(mlir::StringAttr fn) const;
  bool fits(mlir::StringAttr label, mlir::Type type) const;
  unsigned captures(mlir::StringAttr label, mlir::Type type) const;
  Key forced(const Key &key) const;
  void keyFields();
  void keyArrays();
  void keyFunctions();
  void keyValues();
  void keyForces();
  void note(const Key &key, mlir::Operation *at);
  void noteArrays(mlir::Type type, mlir::Operation *at);
  void order();

  // Moves (Moves.cpp).
  Key sinkOf(mlir::OpOperand &use) const;
  static bool isFollowed(mlir::Operation *op);
  void widen();
  void move(mlir::Operation *at, const Key &from, const Key &to);
  void constantSources(mlir::Attribute attr, const Key &slot);
  void gatherSources();
  void unifySuspensions();
  void connect();
  void connect(ApplyOp apply);

  // The decision (Decide.cpp).
  bool canCoerce(const Key &from, const Key &to) const;
  bool convertible(const Key &key) const;
  void holds(mlir::Type type, const Key &key, llvm::SmallVectorImpl<Key> &out,
             llvm::DenseSet<mlir::StringAttr> &seen) const;
  void decide();

  mlir::ModuleOp module;
  Labels &analysis;
  mlir::SymbolTable &table;
  mlir::MLIRContext *ctx;

  llvm::DenseMap<mlir::Value, Key> values;
  llvm::DenseMap<mlir::StringAttr, Signature> functions;
  llvm::DenseMap<std::tuple<mlir::StringAttr, mlir::StringAttr, unsigned>, Key> fields;
  // By element type.
  llvm::DenseMap<mlir::Type, Key> arrays;
  // Every key by first appearance, with its sum once numbered, and the op
  // it first appears at. A converted key's sum is unboxed, or boxed when
  // the key is on a cycle of captures, which only a heap cell can end, or
  // when it is a suspension's, whose cell has one memo.
  llvm::MapVector<Key, mlir::Type> sums;
  llvm::DenseMap<Key, mlir::Operation *> firstSeen;
  // The slot each keyed operand of the module moves its value into.
  llvm::DenseMap<std::pair<mlir::Operation *, unsigned>, Key> sinks;
  llvm::SmallVector<Flow> flows;
  // A closure, suspension or constant of a label in a slot of a key.
  llvm::SmallVector<std::pair<mlir::StringAttr, Key>> sources;
  // A shared part of a constant, in a slot, is sourced once.
  llvm::DenseSet<std::pair<mlir::Attribute, Key>> sourced;
  // The first op where a value of each key meets a slot whose labels the
  // analysis does not know: where it lost that value.
  llvm::DenseMap<Key, mlir::Operation *> lost;
  // The keys of evaluated suspensions: a lazy key without a label that
  // still holds values, each in its cell's forced state.
  llvm::DenseSet<Key> evaluated;
  llvm::DenseSet<Key> converted;
  llvm::DenseSet<Key> cyclic;
};

// The types of the conversion: a value's is its slot's (Slots::typeOf), and
// a value that moves into a slot of another key is rebuilt in that key's
// sum by the one target materialization.
class SlotTypeConverter : public mlir::TypeConverter {
public:
  explicit SlotTypeConverter(Slots &slots);

  Slots &slots() const { return keys; }

  // Whether `value` already has its slot's type, and whether `op`'s
  // operands, results and block arguments all do and no operand owes a
  // move into a slot of another key.
  bool legal(mlir::Value value) const { return keys.typeOf(value) == value.getType(); }
  bool legal(mlir::Operation *op) const;

  // `value` of `from` as a value of `to`, whose slot's type is `sink`:
  // itself when no move is owed, the program's poison where the move never
  // runs, else the materialization; null when the target sum cannot hold
  // it, a move the decision did not allow.
  mlir::Value coerce(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value, const Key &from,
                     const Key &to, mlir::Type sink) const;
  // The remapped value of `use` moved into the use's slot.
  mlir::Value coerceOperand(mlir::OpBuilder &b, mlir::OpOperand &use, mlir::Value remapped) const;
  // Each operand of `op`, as the conversion remapped it, moved into its
  // slot; fails when one cannot be.
  mlir::LogicalResult coerceOperands(mlir::OpBuilder &b, mlir::Operation *op,
                                     mlir::ValueRange remapped,
                                     llvm::SmallVectorImpl<mlir::Value> &out) const;

private:
  mlir::Value rebuild(mlir::OpBuilder &b, mlir::Type to, mlir::Value value,
                      mlir::Location loc) const;

  Slots &keys;
};

// The conversion's pattern for one op, tried ahead of the generic one,
// which reads the key decision through its converter.
template <typename Op>
class SlotPattern : public mlir::OpConversionPattern<Op> {
public:
  SlotPattern(const SlotTypeConverter &converter, mlir::MLIRContext *ctx)
      : mlir::OpConversionPattern<Op>(converter, ctx, /*benefit=*/2) {}

protected:
  const SlotTypeConverter &converter() const {
    return *this->template getTypeConverter<SlotTypeConverter>();
  }
  Slots &slots() const { return converter().slots(); }
};

// Declares the sum of every converted key at the module's start, through
// the key decision's symbol table; fails, having declared nothing, if a
// sum's name is taken.
mlir::LogicalResult declareSums(mlir::ModuleOp module, const Slots &slots);

// The patterns of the closures, suspensions, applies, forces, constants,
// declarations and signatures, and the generic one that retypes every other
// op; and those of idr.call and idr.return, which move their values into
// the slots of the function they call or return from.
void populateDefunctionalizePatterns(mlir::RewritePatternSet &patterns,
                                     const SlotTypeConverter &converter);
void populateCallOpTypeConversionPattern(mlir::RewritePatternSet &patterns,
                                         const SlotTypeConverter &converter);
void populateReturnOpTypeConversionPattern(mlir::RewritePatternSet &patterns,
                                           const SlotTypeConverter &converter);

// Marks `by_name` each label constructor of a memo sum of the converted
// module whose function reaches an observable effect, unless a static
// constant names that label.
void markByName(mlir::ModuleOp module, mlir::SymbolTable &symbols);

} // namespace idr::defunctionalize

#endif // IDR_TRANSFORMS_DEFUNCTIONALIZE_H
