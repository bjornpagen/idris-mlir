// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The analysis behind idr-in-bounds: everything a proof needs of the whole
// module, computed once and then only read. The calls of each private
// function, the returns of each function, what each result gives back and
// whether each pair bound at an interface holds are all settled here, on
// the pass's thread, before any function's guards are judged; a function's
// proofs then run beside its siblings', which erase guards in their own
// bodies while this is read.
//
// Lengths is computed serially. Its parts that look like one function's
// are not: the returned arrays are a fixpoint over the calls, and every
// interface question follows calls and returns into other functions,
// sharing one memo so that a pair one question settled is not asked again.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Analysis/Ranges.h"
#include "idr/Transforms/InBounds.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::inbounds {

namespace {

// Where a function's parameters or results are sizes, arrays and records.
struct Positions {
  SmallVector<unsigned> sizes;
  SmallVector<unsigned> arrays;
  SmallVector<std::pair<unsigned, DataOp>> records;
};

bool isSize(Type type) { return unrestricted(type).isInteger(64); }

bool hasLength(Type type) { return isRank1Array(unrestricted(type)); }

Positions positionsOf(TypeRange types, SymbolTable &symbols) {
  Positions positions;
  for (auto [i, type] : llvm::enumerate(types)) {
    auto position = static_cast<unsigned>(i);
    if (isSize(type))
      positions.sizes.push_back(position);
    else if (hasLength(type))
      positions.arrays.push_back(position);
    else if (DataOp data = lookupData(symbols, type))
      positions.records.push_back({position, data});
  }
  return positions;
}

// Every pair a side of `fn` binds that a question of a function may meet: a
// size and an array, a size and an array field of a record's constructor,
// a size field and an array field of one constructor.
void keysOf(FuncOp fn, InterfaceKey::Side side, TypeRange types, SymbolTable &symbols,
            SmallVectorImpl<InterfaceKey> &keys) {
  Positions at = positionsOf(types, symbols);
  using Shape = InterfaceKey::Shape;
  for (unsigned size : at.sizes)
    for (unsigned array : at.arrays)
      keys.push_back({fn, side, Shape::Pair, size, array});
  for (auto [record, data] : at.records)
    for (CtorOp ctor : data.getCtors()) {
      SmallVector<unsigned> sizeFields, arrayFields;
      for (unsigned k = 0, e = static_cast<unsigned>(ctor.getFieldTypes().size()); k < e; ++k) {
        if (isSize(ctor.getFieldType(k)))
          sizeFields.push_back(k);
        else if (hasLength(ctor.getFieldType(k)))
          arrayFields.push_back(k);
      }
      for (unsigned field : arrayFields) {
        for (unsigned size : at.sizes)
          keys.push_back({fn, side, Shape::Component, size, record, ctor.getSymNameAttr(), field});
        for (unsigned sizeField : sizeFields)
          keys.push_back(
              {fn, side, Shape::Fields, record, record, ctor.getSymNameAttr(), sizeField, field});
      }
    }
}

} // namespace

Lengths::Lengths(Operation *op, AnalysisManager &am) : ranges(am.getAnalysis<Ranges>()) {
  auto module = cast<ModuleOp>(op);
  SymbolTable &symbols = am.getAnalysis<SymbolTable>();
  // Only a guard of an index asks about lengths; a module without one pays
  // for none of the tables.
  bool asks = false;
  module.walk([&](CheckInBoundsOp) {
    asks = true;
    return WalkResult::interrupt();
  });
  if (!asks)
    return;
  // The returns of a function are the terminators of its body's blocks, an
  // idr.return being a terminator of the function itself.
  for (auto fn : module.getOps<FuncOp>()) {
    if (fn.isExternal())
      continue;
    SmallVector<ReturnOp> &rets = returns[fn];
    for (Block &block : fn.getBody())
      if (auto ret = dyn_cast<ReturnOp>(block.getTerminator()))
        rets.push_back(ret);
  }
  // A function whose address is taken (a closure of it, a constant, a
  // reference from a declaration) or that is public binds its parameters
  // where nothing is known, so it has no list of calls.
  SymbolTableCollection collection;
  SymbolUserMap users(collection, module);
  for (auto fn : module.getOps<FuncOp>()) {
    if (!fn.isPrivate() || fn.isExternal())
      continue;
    SmallVector<CallOp> sites;
    bool direct = llvm::all_of(users.getUsers(fn), [&](Operation *user) {
      auto call = dyn_cast<CallOp>(user);
      if (!call || call.getCallee() != fn.getSymName())
        return false;
      sites.push_back(call);
      return true;
    });
    if (direct)
      calls.try_emplace(fn, std::move(sites));
  }
  Local whole(*this, symbols, am.getAnalysis<DominanceInfo>(), FuncOp());
  returned = returnedOrigins(module, whole);
  // Each key is one question, settled with every pair it reaches; a later
  // key that reaches a settled pair reads it.
  SmallVector<InterfaceKey> keys;
  for (auto fn : module.getOps<FuncOp>()) {
    if (calls.contains(fn))
      keysOf(fn, InterfaceKey::Side::Parameters, fn.getArgumentTypes(), symbols, keys);
    if (!fn.isExternal())
      keysOf(fn, InterfaceKey::Side::Results, fn.getResultTypes(), symbols, keys);
  }
  for (const InterfaceKey &key : keys)
    whole.holds(key);
  interfaces = whole.interfaces();
}

bool Lengths::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Lengths>() || !pa.isPreserved<Ranges>() || !pa.isPreserved<SymbolTable>();
}

std::optional<ConstantIntRanges> Lengths::rangeOf(Value value) const { return ranges.rangeOf(value); }

const SmallVector<CallOp> *Lengths::callsOf(FuncOp fn) const {
  auto it = calls.find(fn);
  return it == calls.end() ? nullptr : &it->second;
}

ArrayRef<ReturnOp> Lengths::returnsOf(FuncOp fn) const {
  auto it = returns.find(fn);
  return it == returns.end() ? ArrayRef<ReturnOp>() : ArrayRef<ReturnOp>(it->second);
}

Origin Origin::none() {
  Origin o;
  o.kind = None;
  return o;
}

Origin Origin::arg(unsigned index, ArrayRef<Proj> path) {
  Origin o;
  o.kind = Argument;
  o.argument = index;
  o.inside.assign(path.begin(), path.end());
  return o;
}

Origin Origin::built(StringAttr ctor, std::vector<Origin> fields) {
  if (llvm::all_of(fields, [](const Origin &field) { return field.kind == None; }))
    return none();
  Origin o;
  o.kind = Built;
  o.ctor = ctor;
  o.fields = std::move(fields);
  return o;
}

bool Origin::operator==(const Origin &other) const {
  if (kind != other.kind)
    return false;
  if (kind == Built)
    return ctor == other.ctor && fields == other.fields;
  if (kind != Argument)
    return true;
  return argument == other.argument &&
         llvm::equal(inside, other.inside,
                     [](const Proj &a, const Proj &b) { return a.ctor == b.ctor && a.index == b.index; });
}

// Two constructors of one name meet field by field. A constructor and an
// argument meet field by field too, the argument's field being the
// argument read so: what any read of the meet is, is the meet of what that
// read of each is.
Origin Origin::meet(const Origin &other) const {
  if (kind == Unknown)
    return other;
  if (other.kind == Unknown || *this == other)
    return *this;
  const Origin *b = kind == Built ? this : other.kind == Built ? &other : nullptr;
  const Origin &rest = b == this ? other : *this;
  if (!b || (rest.kind != Built && rest.kind != Argument))
    return none();
  if (rest.kind == Built && (rest.ctor != b->ctor || rest.fields.size() != b->fields.size()))
    return none();
  std::vector<Origin> met;
  for (auto [k, field] : llvm::enumerate(b->fields))
    met.push_back(field.meet(rest.kind == Built ? rest.fields[k] : rest.project({b->ctor, k})));
  return built(b->ctor, std::move(met));
}

Origin Origin::project(Proj proj) const {
  switch (kind) {
  case Unknown:
  case None:
    return *this;
  case Argument: {
    Origin o = *this;
    o.inside.push_back(proj);
    return o;
  }
  case Built:
    if (ctor == proj.ctor && proj.index < fields.size())
      return fields[proj.index];
    return none();
  }
  return none();
}

const Origin &Lengths::given(FuncOp fn, unsigned slot) const {
  auto it = returned.find(fn);
  if (it == returned.end() || slot >= it->second.size())
    return missing;
  return it->second[slot];
}

bool Lengths::interface(const InterfaceKey &key) const { return interfaces.lookup(key.tuple()); }

// The constructor asks its keys through these.
bool Lengths::Local::holds(const InterfaceKey &key) {
  Question start;
  start.kind = Kind::Interface;
  start.key = key;
  return holds(start);
}

DenseMap<InterfaceKey::Tuple, bool> Lengths::Local::interfaces() const {
  DenseMap<InterfaceKey::Tuple, bool> states;
  for (auto [key, id] : interfaceNodes)
    states[key] = nodes[id].state == State::Held;
  return states;
}

Lengths::Local Lengths::local(FuncOp fn, const SymbolTable &symbols, DominanceInfo &dominance) const {
  return Local(*this, symbols, dominance, fn);
}

} // namespace idr::inbounds
