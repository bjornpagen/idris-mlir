// Specialization: a call is redirected to a clone of its callee in which the
// static parts of its arguments are substituted, and whose parameters are
// their runtime leaves.
//
// A call specializes on an argument only when the parameter's binding time
// allows it (BindingTimes.h): anything static when the callee is on no
// cycle, and otherwise only for a fixed parameter, or a decreasing or
// bounded one whose static value is small. Every other argument is a
// runtime leaf, however static. A closed call is idr-eval's, and a world
// carries no value to specialize around.
//
// A clone is keyed by its owner (the function it was first cloned from) and
// the patterns of the owner's parameters, so that keys made at calls of the
// owner and of its clones compare. The key goes into the table before the
// clone is simplified, so the clone's own calls with its key, a fixed
// parameter passed on unchanged, become self calls: that, and the finite
// supply of keys the binding times allow, is why a run ends.
//
// Inside a chain of clones, a clone's parameter specializes again only when
// it is a closure: a closure static at a later call is new knowledge, where
// data would re-abstract what the key already fixed.

#include "Specialize/Specializer.h"

import idr.facts;
import idr.support;

using namespace mlir;

namespace idr::specialize {

namespace {

// One argument of a call: its pattern, whose holes are numbered from 0 and
// then among the key's, and its runtime leaves in that order.
struct Argument {
  Pattern pattern;
  SmallVector<Value> leaves;
  BindingTime time;
};

// The key of a call as the patterns of its owner's parameters; the value the
// call passes for each hole of the key, none for a hole whose parameter the
// callee no longer has; and for each of the callee's parameters, the holes
// its argument fills.
struct Composed {
  SmallVector<Attribute> patterns;
  SmallVector<std::optional<Value>> values;
  SmallVector<SmallVector<unsigned>> held;
};

// Whether a call specializes on a static argument of a parameter of
// binding time `time`: inside a chain of clones only on a closure, which is
// new knowledge where data would re-abstract what the key already fixed.
bool specializesOn(BindingTime time, bool intoClone, Type type) {
  return time != BindingTime::Other && (!intoClone || isa<FnType>(unrestricted(type)));
}

// Appends argument `arg` to `out` as the key's next holes, and returns its
// pattern as a key.
Attribute append(Argument &arg, SmallVector<unsigned> &held, Composed &out) {
  unsigned next = static_cast<unsigned>(out.values.size());
  unsigned first = next;
  renumber(arg.pattern, next);
  for (unsigned hole = first; hole < next; ++hole)
    held.push_back(hole);
  llvm::append_range(out.values, arg.leaves);
  return keyOf(arg.pattern);
}

// `part` of a clone's key with each hole that `paramOf` maps to a parameter
// filled with that argument's pattern.
Attribute fill(Attribute part, const llvm::DenseMap<unsigned, unsigned> &paramOf,
               MutableArrayRef<Argument> args, Composed &out) {
  MLIRContext *ctx = part.getContext();
  if (auto hole = dyn_cast<KeyHoleAttr>(part)) {
    auto it = paramOf.find(hole.getIndex());
    if (it != paramOf.end())
      return append(args[it->second], out.held[it->second], out);
    out.values.push_back(std::nullopt);
    return KeyHoleAttr::get(ctx, static_cast<unsigned>(out.values.size() - 1));
  }
  auto parts = [&](ArrayAttr from) {
    return ArrayAttr::get(ctx, llvm::map_to_vector(from, [&](Attribute inner) {
                            return fill(inner, paramOf, args, out);
                          }));
  };
  if (auto con = dyn_cast<KeyConAttr>(part))
    return KeyConAttr::get(ctx, con.getData(), con.getCtor(), parts(con.getFields()));
  if (auto closure = dyn_cast<KeyClosureAttr>(part))
    return KeyClosureAttr::get(ctx, closure.getCallee(), parts(closure.getCaptures()));
  return part;
}

// Replaces each parameter of `clone` whose argument is static by that
// argument's pattern, rebuilt over new parameters for its leaves; every
// parameter records the hole of the key it holds, and a new one how often
// the clone uses it.
void substitute(func::FuncOp clone, ArrayRef<Argument> args, const Composed &key) {
  MLIRContext *ctx = clone.getContext();
  unsigned arity = clone.getNumArguments();
  SmallVector<unsigned> positions;
  SmallVector<Type> types;
  SmallVector<DictionaryAttr> attrs;
  SmallVector<Location> locs;
  for (unsigned p = 0; p < arity; ++p) {
    const Argument &arg = args[p];
    if (arg.pattern.isHole()) {
      positions.push_back(arity);
      types.push_back(clone.getArgument(p).getType());
      attrs.push_back(parameterAttrs(ctx, key.held[p].front(), clone.getArgAttrDict(p)));
      locs.push_back(clone.getArgument(p).getLoc());
      continue;
    }
    // A leaf keeps its type, and with it how often it may be used.
    for (auto [leaf, hole] : llvm::zip(arg.leaves, key.held[p])) {
      positions.push_back(arity);
      types.push_back(leaf.getType());
      attrs.push_back(parameterAttrs(ctx, hole));
      locs.push_back(leaf.getLoc());
    }
  }
  (void)clone.insertArguments(positions, types, attrs, locs);

  Block &entry = clone.getBody().front();
  SmallVector<Value> holes(key.values.size());
  unsigned next = arity;
  for (unsigned p = 0; p < arity; ++p)
    for (unsigned hole : key.held[p])
      holes[hole] = entry.getArgument(next++);
  OpBuilder b = OpBuilder::atBlockBegin(&entry);
  for (unsigned p = 0; p < arity; ++p)
    entry.getArgument(p).replaceAllUsesWith(rebuild(b, args[p].pattern, holes));
  llvm::BitVector originals(clone.getNumArguments());
  originals.set(0, arity);
  (void)clone.eraseArguments(originals);
}

void count(Statistics &stats, BindingTime time) {
  switch (time) {
  case BindingTime::Free:
    ++stats.free;
    return;
  case BindingTime::Fixed:
    ++stats.fixed;
    return;
  case BindingTime::Decreasing:
    ++stats.decreasing;
    return;
  case BindingTime::Bounded:
    ++stats.bounded;
    return;
  case BindingTime::Other:
    return;
  }
}

} // namespace

LogicalResult Specializer::specialize(func::CallOp call) {
  auto callee = clones.symbols().lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
  if (!callee || callee.isExternal() || llvm::all_of(call.getOperands(), [](Value v) {
        return isErased(v.getType()) || isWorld(v.getType()) || isClosed(v);
      }))
    return success();
  const Clone *own = clones.specialization(callee);

  SmallVector<Argument> args;
  bool any = false;
  for (auto [i, operand] : llvm::enumerate(call.getOperands())) {
    unsigned index = static_cast<unsigned>(i);
    std::optional<BindingTime> time = times.of(callee, index);
    // A function made in this run has no binding times until the next.
    if (!time)
      return success();
    Argument &arg = args.emplace_back(Argument{leafOf(operand, 0), {operand}, *time});
    if (!specializesOn(*time, own, operand.getType()))
      continue;
    SmallVector<Value> leaves;
    Pattern shape = shapeOf(operand, leaves);
    // An unrolling parameter counts down scalars too (a Nat), but only as
    // far as the value is small.
    bool unrolls = *time == BindingTime::Decreasing || *time == BindingTime::Bounded;
    if (shape.isHole() || (unrolls ? unrollSize(shape) > kUnrollLimit : !hasStructure(shape)))
      continue;
    // A linear leaf moves into the clone's call, so the shape that held it
    // must die with the call it feeds: else the leaf is used twice.
    if (llvm::any_of(leaves, [](Value leaf) { return isLinear(leaf.getType()); }) &&
        !usedOnce(operand))
      continue;
    arg.pattern = std::move(shape);
    arg.leaves = std::move(leaves);
    any = true;
  }
  if (!any)
    return success();

  MLIRContext *ctx = module.getContext();
  Composed composed;
  composed.held.resize(args.size());
  if (own) {
    llvm::DenseMap<unsigned, unsigned> paramOf;
    for (auto [p, hole] : llvm::enumerate(own->holes))
      paramOf[hole] = static_cast<unsigned>(p);
    for (Attribute part : cast<SpecKeyAttr>(own->key).getPatterns())
      composed.patterns.push_back(fill(part, paramOf, args, composed));
  } else {
    for (auto [p, arg] : llvm::enumerate(args))
      composed.patterns.push_back(append(arg, composed.held[p], composed));
  }
  auto key = SpecKeyAttr::get(ctx, clones.ownerOf(callee), ArrayAttr::get(ctx, composed.patterns));

  // Making the clone and calling it is one action, which a debug counter
  // may skip: then there is no clone and the call stays.
  LogicalResult result = success();
  support::perform<support::SpecializeCloneAction>(call, [&] {
    const Clone *clone = clones.lookup(key);
    if (clone) {
      ++stats.shared;
    } else {
      FailureOr<func::FuncOp> made = clones.copy(callee, key.getOrigin(), "spec", call);
      if (failed(made)) {
        result = failure();
        return;
      }
      // A chain of clones on a static shape is acyclic, and inlining it is
      // what exposes the shape to its consumer: a clone is no loop breaker.
      made->setNoInline(false);
      substitute(*made, args, composed);
      SmallVector<FlatSymbolRefAttr> named;
      for (const Argument &arg : args)
        labels(arg.pattern, named);
      facts::inherit(*made, callee, llvm::map_to_vector(named, [&](FlatSymbolRefAttr name) {
                     return clones.symbols().lookup<func::FuncOp>(name.getAttr());
                   }));
      for (const Argument &arg : args)
        if (!arg.pattern.isHole())
          count(stats, arg.time);
      ++stats.clones;
      // Into the table before it is simplified: the clone's own calls with
      // its key call it.
      clone = &clones.add(key, *made);
      canonicalize(clone->fn);
      work.push_back(clone->fn);
    }
    std::optional<SmallVector<Value>> operands = operandsFor(*clone, composed.values);
    if (!operands)
      return;
    OpBuilder b(call);
    auto replacement = func::CallOp::create(b, call.getLoc(), clone->fn, *operands);
    replacement->setDiscardableAttrs(call->getDiscardableAttrDictionary());
    call.replaceAllUsesWith(replacement.getResults());
    SmallVector<Value> old(call.getOperands());
    call.erase();
    eraseUnused(old);
  });
  return result;
}

} // namespace idr::specialize
