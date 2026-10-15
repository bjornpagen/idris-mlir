// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-defunctionalize: every closure and suspension becomes a constructor of
// a sum, every apply a match over its callee's sum, every force a call of
// its memo sum's dispatch function, by a conversion of each function.
//
// Sums are keyed by (carrier, label set): every slot that holds a closure or
// a suspension (a value, a function's parameter or result, a field of a data
// type, the elements of a shaped type, the forced state of a lazy type) has
// the key of its carrier and the labels the solve (idr::Labels) found for
// it. Every key becomes a sum: a closure key one constructor per label,
// holding its captures, none when no label reaches it; a lazy key a memo sum
// of its labels and the cell's two states, and a dispatch function that
// matches the cell's state, `<sum>.force`. A label's constructor names its
// function, so what it runs is read from the constructor, never from a
// name. Every sum is made with its body, and every dispatch function
// defined, before any function is converted; the conversion of a function
// reads that decision and a plan of its own values, so functions convert in
// parallel, and it changes the type of a closure or a suspension alone.
// Then one remap makes every data type whose body holds a slot anew with
// the slots' sums, a sum whose captures hold one among them, and retypes
// the program.
#ifndef IDR_TRANSFORMS_DEFUNCTIONALIZE_H
#define IDR_TRANSFORMS_DEFUNCTIONALIZE_H

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SmallVector.h"

#include <memory>
#include <optional>
#include <utility>

namespace idr {

#define GEN_PASS_DECL_IDRDEFUNCTIONALIZE
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

namespace idr::defunctionalize {

// The key of a slot: its carrier and the labels it may hold, the solve's
// uniqued ArrayAttr. A null carrier means the slot holds neither a closure
// nor a suspension.
using Key = std::pair<mlir::Type, mlir::ArrayAttr>;

// A function as the program declared it, and as its slots have it.
struct Signature {
  mlir::FunctionType type;
  mlir::FunctionType converted;
  llvm::SmallVector<Key> arguments, results;
};

// What the conversion of one function reads of its own values, made from
// the decision before the function's conversion starts: the type and key
// of each closure or suspension it had, and the slot each operand of one
// moves its value into. Any other value keeps its type, and a value the
// conversion makes has its own.
struct Plan {
  llvm::DenseMap<mlir::Value, mlir::Type> types;
  llvm::DenseMap<mlir::Value, Key> keys;
  llvm::DenseMap<mlir::OpOperand *, Key> sinks;
};

// The decision: the key of every slot, the sum of every key, every
// function's signature, every memo sum's dispatch function. Built whole,
// serially, and read only afterwards, from any thread.
class Slots {
public:
  Slots(ProgramOp program, Labels &labels, mlir::SymbolTable &symbols);

  // Makes every sum with its body, a memo label `by_name` when `byName`
  // says so, and names each memo sum's dispatch function. Fails, with an
  // internal error, when two keys meet on one name or a body is no sum.
  mlir::LogicalResult declare(llvm::function_ref<bool(FuncOp)> byName);
  // Defines each memo sum's dispatch function and adds it to the program
  // (Forces.cpp); after declare, before any function converts.
  void defineForces();
  // Once every function is converted: every data type whose body holds a
  // slot made anew with the slots' sums, transitively, and the program
  // retyped.
  mlir::LogicalResult remake();

  static bool isLazy(const Key &key) { return key.first && llvm::isa<LazyType>(key.first); }
  // Whether no label reaches a slot of `key`: no value is ever in it.
  static bool isEmpty(const Key &key) { return key.first && key.second.empty(); }
  static bool needsCoercion(const Key &from, const Key &to) {
    return from.first && to.first && from != to;
  }

  // Keys (Keys.cpp).
  Key keyAt(const FlowPoint &point) const;
  Key anchorKey(const FlowAnchor &anchor) const;
  Key keyOf(mlir::Value value) const;
  Key argumentKey(mlir::StringAttr fn, unsigned index) const;
  Key resultKey(mlir::StringAttr fn, unsigned index) const;
  Key fieldKey(DataType data, unsigned tag, unsigned index) const;
  Key elementKey(mlir::Type element) const;
  Key forcedKey(mlir::Type lazy) const;

  // Types (Declare.cpp). The value type of `key`'s sum; the type of a slot
  // of `key` whose type was `type`, which is `type` for a slot of no key.
  mlir::Type sumOf(const Key &key) const;
  mlir::Type typeOf(mlir::Type type, const Key &key) const;
  const Signature &signature(mlir::StringAttr fn) const;
  // The tag of the constructor of `label` in the sum of `key`: a key's
  // labels, in name order, are its sum's first constructors, in tag order.
  unsigned labelTag(const Key &key, mlir::FlatSymbolRefAttr label) const;
  // The dispatch function of a lazy key's memo sum, by its symbol.
  mlir::FlatSymbolRefAttr forceOf(const Key &key) const;

  // The plan of one function, made just before its conversion.
  Plan plan(FuncOp fn) const;
  // The value of `constant` converted to its slot, or null for a constant
  // the program did not hold.
  mlir::Attribute constantOf(mlir::Operation *constant) const { return constants.lookup(constant); }

  // What the statistics record (Decide.cpp).
  unsigned numSums() const { return static_cast<unsigned>(sums.size()); }
  unsigned numConstructors() const;

private:
  // A key's sum: its name, made from the key's content, and the data type,
  // once made.
  struct Sum {
    mlir::StringAttr name;
    DataType type;
  };

  Key keyWith(mlir::Type carrier, const FlowPoint &point) const;

  // Every key the program may ask for (Keys.cpp).
  void noteValue(mlir::Value value);
  void noteType(mlir::Type type);
  void noteData(DataType data);
  void noteKey(const Key &key);
  unsigned captures(mlir::StringAttr label, mlir::Type carrier) const;

  // Widening (Moves.cpp).
  void widen();
  Key sinkKey(mlir::OpOperand &use) const;

  // The names (Decide.cpp).
  mlir::LogicalResult name();

  // The bodies and the constants (Declare.cpp).
  DataType define(const Key &key, llvm::function_ref<bool(FuncOp)> byName);
  mlir::Type slotType(mlir::Type type, const Key &key,
                      llvm::function_ref<bool(FuncOp)> byName);
  DataType::Body body(const Key &key, llvm::function_ref<bool(FuncOp)> byName,
                      llvm::SmallVectorImpl<llvm::SmallVector<mlir::Type>> &fields);
  mlir::Attribute convertConstant(mlir::Attribute attr, const Key &slot);
  bool holdsClosure(mlir::Attribute attr);

  // The dispatch function of one memo sum (Forces.cpp).
  FuncOp defineForce(const Key &key, DataType sum);

  ProgramOp program;
  Labels &analysis;
  mlir::SymbolTable &table;
  mlir::MLIRContext *ctx;

  // A closure, suspension or constant whose every use moves it into one
  // key that holds its own takes that key.
  llvm::DenseMap<mlir::Value, Key> widened;
  // Every key, in the order met, with its sum.
  llvm::MapVector<Key, Sum> sums;
  // Whether a sum's body was no sum: an internal error, reported by define.
  bool broken = false;
  // Every type met while the keys are noted, each looked into once: the
  // data types' bodies, the shaped types' elements.
  mlir::AttrTypeWalker types;
  llvm::DenseMap<mlir::StringAttr, Signature> signatures;
  // Each lazy key's dispatch function, by its symbol.
  llvm::DenseMap<Key, mlir::FlatSymbolRefAttr> forces;
  // Each constant of the program converted to its slot, and the parts of
  // constants already converted or looked into.
  llvm::DenseMap<mlir::Operation *, mlir::Attribute> constants;
  llvm::DenseMap<std::pair<mlir::Attribute, Key>, mlir::Attribute> convertedParts;
  llvm::DenseMap<mlir::Attribute, bool> holding;
};

// The types of one function's conversion: a value's is its plan's, and a
// value that moves into a slot of another key is rebuilt in that key's sum.
class SlotTypeConverter : public mlir::TypeConverter {
public:
  SlotTypeConverter(const Slots &slots, const Plan &plan);

  const Slots &slots() const { return decision; }
  const Plan &plan() const { return own; }

  mlir::Type typeOf(mlir::Value value) const;
  Key keyOf(mlir::Value value) const { return own.keys.lookup(value); }
  Key sinkKey(mlir::OpOperand &use) const { return own.sinks.lookup(&use); }

  // Whether `value` already has its slot's type, and whether `op`'s
  // operands, results and block arguments all do and no operand owes a
  // move into a slot of another key.
  bool legal(mlir::Value value) const { return typeOf(value) == value.getType(); }
  bool legal(mlir::Operation *op) const;

  // `value` of `from` as a value of `to`, whose slot's type is `sink`:
  // itself when no move is owed, poison where the move never runs, else
  // the rebuild of every constructor of `from`'s sum in `to`'s; null when
  // `to`'s sum lacks one, a move the solve did not allow.
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
  const Slots &decision;
  const Plan &own;
};

// The conversion's pattern for one op, tried ahead of the generic one.
template <typename Op>
class SlotPattern : public mlir::OpConversionPattern<Op> {
public:
  SlotPattern(const SlotTypeConverter &converter, mlir::MLIRContext *ctx)
      : mlir::OpConversionPattern<Op>(converter, ctx, /*benefit=*/2) {}

protected:
  const SlotTypeConverter &converter() const {
    return *this->template getTypeConverter<SlotTypeConverter>();
  }
  const Slots &slots() const { return converter().slots(); }
};

// The patterns of the closures, suspensions, applies, forces, constants
// and signatures, and the generic one that retypes every other op; and
// those of idr.call and idr.return, which move their values into the slots
// of the function they call or return from.
void populateDefunctionalizePatterns(mlir::RewritePatternSet &patterns,
                                     const SlotTypeConverter &converter);
void populateCallOpTypeConversionPattern(mlir::RewritePatternSet &patterns,
                                         const SlotTypeConverter &converter);
void populateReturnOpTypeConversionPattern(mlir::RewritePatternSet &patterns,
                                           const SlotTypeConverter &converter);

} // namespace idr::defunctionalize

#endif // IDR_TRANSFORMS_DEFUNCTIONALIZE_H
