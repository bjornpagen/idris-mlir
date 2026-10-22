// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every signature and constant as their slots have them: a slot's type is
// its key's family at the key's own variables, at the slot's grade; a
// signature is its slots' types, set on its function before any body is
// rewritten; a constant holding a closure is its label's constructor in its
// slot's family. The workers' walks read these from any thread, so what
// they keep as they go (the replacer's types, the constants converted) is
// taken under one lock.

#include "idr/Analysis/Labels.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/STLExtras.h"

#include <mutex>

using namespace mlir;

namespace idr::defunctionalize {

// A slot's type: its key's family applied to the variables the carrier
// names, at the carrier's grade; any other type remade where its parts
// hold slots. The replacer keeps what it made, so a worker takes it under
// the lock.
Type Decision::typeOf(Type type, const Slot &slot) const {
  if (!slot) {
    std::lock_guard lock(replacing);
    return const_cast<AttrTypeReplacer &>(replacer).replace(type);
  }
  const Family &family = familyOf(*slot);
  return graded(gradeOf(type),
                DataType::get(ctx, family.type.getGroup(), family.type.getMember(), family.args));
}

Tag Decision::tagOf(const Key &key, FlatSymbolRefAttr label) const {
  return Tag{*labels.positionIn(key.labels, label)};
}

// Every function's type set to its converted signature here, serially,
// before any body is rewritten: a call the rewrite or a dispatch function
// builds reads its callee's type, which no worker writes then.
void Decision::convertSignatures() {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    Signature &sig = signatures[fn.getSymNameAttr()];
    SmallVector<Type> inputs, results;
    for (auto [type, slot] : llvm::zip_equal(fn.getArgumentTypes(), sig.arguments))
      inputs.push_back(typeOf(type, slot));
    for (auto [type, slot] : llvm::zip_equal(fn.getResultTypes(), sig.results))
      results.push_back(typeOf(type, slot));
    sig.converted = FunctionType::get(ctx, inputs, results);
    fn.setFunctionType(sig.converted);
  }
}

// A constant held in `slot`, each closure in it its label's constructor in
// its slot's family, each constructor of a data family remade with its
// fields in their slots. A part shared by many constants is converted once
// per slot; the parts known, the conversions made and the replacer's types
// are kept, so a worker reads and adds to them under the lock.
Attribute Decision::constantOf(Attribute value, const Slot &slot) const {
  std::lock_guard lock(replacing);
  if (!const_cast<ClosureParts &>(holding).holds(value))
    return value;
  // A part is converted once per slot it is held in, the slot named by its
  // family's type, or by nothing where it holds no closure itself.
  auto keyFor = [&](Attribute part, const Slot &s) {
    return std::pair(part, s ? Attribute(TypeAttr::get(familyOf(*s).type)) : Attribute());
  };
  if (auto found = converted.find(keyFor(value, slot)); found != converted.end())
    return found->second;
  // The parts in post-order with their slots, each built once its fields are.
  struct Visit {
    Attribute part;
    Slot slot;
    bool expanded;
  };
  SmallVector<Visit> work{{value, slot, false}};
  auto &done = converted;
  auto fieldSlots = [&](Attribute part, const Slot &s) {
    SmallVector<std::pair<Attribute, Slot>> out;
    if (auto closure = dyn_cast<ClosureAttr>(part)) {
      const Signature &sig = signature(closure.getCallee().getAttr());
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        out.push_back({capture, sig.arguments[i]});
    } else if (auto con = dyn_cast<ConAttr>(part)) {
      DataType data = con.getData();
      con.walkFields([&](Attribute field, unsigned i) {
        out.push_back({field, anchorKey(FlowAnchor::fieldOf(data, con.getTag(), i))});
      });
    }
    return out;
  };
  while (!work.empty()) {
    Visit &visit = work.back();
    auto key = keyFor(visit.part, visit.slot);
    if (done.contains(key) || !const_cast<ClosureParts &>(holding).holds(visit.part)) {
      if (!done.contains(key))
        done[key] = visit.part;
      work.pop_back();
      continue;
    }
    SmallVector<std::pair<Attribute, Slot>> parts = fieldSlots(visit.part, visit.slot);
    if (!visit.expanded) {
      visit.expanded = true;
      for (auto &[part, s] : parts)
        work.push_back({part, s, false});
      continue;
    }
    SmallVector<Attribute> fields;
    for (auto &[part, s] : parts)
      fields.push_back(done.at(keyFor(part, s)));
    Attribute result;
    if (auto closure = dyn_cast<ClosureAttr>(visit.part)) {
      DataType family = cast<DataType>(unrestricted(typeOf(visit.slot->carrier, visit.slot)));
      result = ConAttr::get(ctx, family.refinedTo(tagOf(*visit.slot, closure.getCallee()), {}),
                            ArrayAttr::get(ctx, fields));
    } else {
      auto con = cast<ConAttr>(visit.part);
      Type remade = const_cast<AttrTypeReplacer &>(replacer).replace(con.getType());
      result = ConAttr::get(ctx, remade, ArrayAttr::get(ctx, fields));
    }
    done[key] = result;
    work.pop_back();
  }
  return done.at(keyFor(value, slot));
}

} // namespace idr::defunctionalize
