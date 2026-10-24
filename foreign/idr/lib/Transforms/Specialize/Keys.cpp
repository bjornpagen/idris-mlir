// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The pattern key of a call: a copy is keyed by its owner (the function it
// is cloned from) and a pattern per parameter of the owner, so keys made at
// calls of the owner and of its copies compare.
//
// A call specializes on an argument only where the parameter's binding
// time, as the call sees it, is fixed (offline partial evaluation). A call
// that stays within the recursion of the component its requester stands
// for sees the callee's binding times: only a parameter every recursive
// call passes on unchanged keys a copy, so the recursion keeps one key, and
// what varies along it is passed as a value. A call that enters the
// component from outside sees every parameter fixed. Inside a chain of
// copies a parameter specializes again only on a closure: a closure static
// at a later call is new knowledge, where data would re-abstract what the
// key already fixed.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize::detail {

namespace {

// Whether a value of `type` is a closure: a value of a closure family
// defunctionalization declared.
bool isClosureValue(Type type) {
  DataType data = dataTypeOf(type);
  return data && data.closures().has_value();
}

bool isLabelCarrier(Type type) {
  DataType data = dataTypeOf(type);
  return data && (data.closures() || data.memo());
}

// Where a call specializes: on a fixed parameter, and inside a chain of
// copies only on a closure.
enum class Into : bool { Held, Copy };
bool specializesOn(BindingTime time, Into into, Type type) {
  return time == BindingTime::Fixed && (into == Into::Held || isClosureValue(type));
}

// One argument of a call: its pattern and its runtime leaves in pre-order.
struct Shaped {
  const Pattern *shape;
  SmallVector<Value> leaves;
};

// `own`'s patterns with each hole filled by the shape of the argument at
// its position: the i-th hole of a copy's key, met in pre-order, is its
// parameter i. A constructor of `own`'s patterns is one the copy builds
// from its parameters, its call passing the parts and holding no such
// cell, so the copy keyed here builds it again with no second identity.
// Built from each pattern's last node back, with no recursion.
SmallVector<const Pattern *> fill(Arena &arena, const PatternKey &own, ArrayRef<Shaped> args,
                                  SmallVectorImpl<Value> &values) {
  // The nodes of every pattern in pre-order, each hole replaced by its
  // argument's shape as a whole subtree.
  struct Sub {
    const Pattern *whole;
  };
  struct Rebuild {
    Tag tag;
    unsigned arity;
  };
  using Node = std::variant<Sub, Rebuild>;
  SmallVector<const Pattern *> out;
  unsigned next = 0;
  for (const Pattern *param : own.params) {
    SmallVector<Node> order;
    SmallVector<const Pattern *> work{param};
    while (!work.empty()) {
      const Pattern *at = work.pop_back_val();
      idr::match(
          at->get(),
          [&](Hole) {
            const Shaped &arg = args[next++];
            llvm::append_range(values, arg.leaves);
            order.push_back(Sub{arg.shape});
          },
          [&](const Con &con) {
            order.push_back(Rebuild{con.tag, static_cast<unsigned>(con.fields.size())});
            for (const Pattern *field : llvm::reverse(con.fields))
              work.push_back(field);
          },
          [&](const Const &) { order.push_back(Sub{at}); });
    }
    SmallVector<const Pattern *> built;
    for (const Node &node : llvm::reverse(order))
      idr::match(
          node, [&](const Sub &sub) { built.push_back(sub.whole); },
          [&](const Rebuild &make) {
            SmallVector<const Pattern *> fields;
            for (unsigned i = 0; i < make.arity; ++i)
              fields.push_back(built.pop_back_val());
            built.push_back(arena.con(make.tag, fields));
          });
    out.push_back(built.front());
  }
  return out;
}

} // namespace

std::optional<PatternWant> composeKey(Arena &arena, FunctionCallOpInterface call,
                                      FunctionId owner, const PatternKey *own,
                                      ArrayRef<BindingTime> seen) {
  // A closed call is left to run at run time.
  if (llvm::all_of(call.getArgs(), isClosed))
    return std::nullopt;
  Into into = own ? Into::Copy : Into::Held;
  SmallVector<Shaped> args;
  bool any = false;
  for (auto [operand, time] : llvm::zip_equal(call.getArgs(), seen)) {
    Shaped &arg = args.emplace_back(Shaped{arena.hole(), {operand}});
    if (!specializesOn(time, into, operand.getType()))
      continue;
    SmallVector<Value> leaves;
    const Pattern *shape = shapeOf(arena, operand, leaves);
    if (!shape->hasStructure())
      continue;
    // A leaf used once moves into the copy's call, so the shape that held
    // it must die with the call it feeds, or the leaf is used twice.
    if (llvm::any_of(leaves, [](Value leaf) { return isLinear(leaf.getType()); }) &&
        !usedOnce(operand))
      continue;
    arg = Shaped{shape, std::move(leaves)};
    any = true;
  }
  if (!any)
    return std::nullopt;
  PatternWant want;
  if (own) {
    want.key = arena.key(own->owner, fill(arena, *own, args, want.leaves));
    return want;
  }
  SmallVector<const Pattern *> params;
  for (Shaped &arg : args) {
    params.push_back(arg.shape);
    llvm::append_range(want.leaves, arg.leaves);
  }
  want.key = arena.key(owner, params);
  return want;
}

// Each label of the closures the key fixes, at the parameters' types,
// when it fixes closures alone. A walk with its own stack: entering a
// closure pushes its label on the path, and leaving it pops, so a closure
// of a label already on the path is a chain a recursion could walk.
Fixes fixes(const PatternKey &key, TypeRange params) {
  struct Visit {
    const Pattern *pattern;
    Type type;
  };
  struct Leave {};
  using Step = std::variant<Visit, Leave>;
  FixesClosures out;
  SmallVector<FlatSymbolRefAttr> path;
  SmallVector<Step> work;
  for (auto [pattern, type] : llvm::reverse(llvm::zip_equal(key.params, params)))
    work.push_back(Visit{pattern, type});
  while (!work.empty()) {
    Step step = work.pop_back_val();
    bool data = idr::match(
        step,
        [&](Leave) {
          path.pop_back();
          return false;
        },
        [&](const Visit &visit) {
          DataType family = dataTypeOf(visit.type);
          std::optional<families::ClosuresView> closures =
              family ? family.closures() : std::nullopt;
          return idr::match(
              visit.pattern->get(), [](Hole) { return false; },
              [&](const Con &con) {
                // A constructor of a data family is data a recursion walks.
                if (!closures)
                  return true;
                FlatSymbolRefAttr label = closures->labels()[static_cast<unsigned>(con.tag)].fn;
                if (llvm::is_contained(path, label))
                  return true;
                out.labels.push_back(label);
                path.push_back(label);
                work.push_back(Leave{});
                SmallVector<Type> fields = *family.determinedFields(con.tag);
                for (size_t k = con.fields.size(); k-- > 0;)
                  work.push_back(Visit{con.fields[k], fields[k]});
                return false;
              },
              [&](const Const &constant) {
                // A scalar is data at a parameter and what a closure carries
                // inside one; a constant constructor is data unless it is a
                // closure of one cell, whose captures are constants, each
                // closure among them read as a closure node is.
                auto con = dyn_cast<ConAttr>(constant.value);
                if (!con)
                  return path.empty();
                if (!closures || con.getRunLength() > 1)
                  return true;
                struct Held {
                  ConAttr con;
                  DataType family;
                  SmallVector<FlatSymbolRefAttr> path;
                };
                SmallVector<Held> constants{{con, family, path}};
                while (!constants.empty()) {
                  Held at = constants.pop_back_val();
                  std::optional<families::ClosuresView> view = at.family.closures();
                  FlatSymbolRefAttr label = view->labels()[static_cast<unsigned>(at.con.getTag())].fn;
                  if (llvm::is_contained(at.path, label))
                    return true;
                  out.labels.push_back(label);
                  at.path.push_back(label);
                  SmallVector<Type> fields = *at.family.determinedFields(at.con.getTag());
                  bool data = false;
                  at.con.walkFields([&](Attribute capture, unsigned i) {
                    auto inner = dyn_cast<ConAttr>(capture);
                    if (!inner)
                      return;
                    DataType held = dataTypeOf(fields[i]);
                    if (!held || !held.closures() || inner.getRunLength() > 1) {
                      data = true;
                      return;
                    }
                    constants.push_back({inner, held, at.path});
                  });
                  if (data)
                    return true;
                }
                return false;
              });
        });
    if (data)
      return FixesData{};
  }
  return out;
}

namespace {

// Whether `value`, or a closure among the parts of a constructor that
// built it, is used by something else too.
bool sharedPart(Value value) {
  SmallVector<Value> work{value};
  while (!work.empty()) {
    Value at = work.pop_back_val();
    Value made = throughLinear(at);
    if (isClosureValue(at.getType()) && (!at.hasOneUse() || !made.hasOneUse()))
      return true;
    if (auto built = made.getDefiningOp<DataConOp>())
      llvm::append_range(work, built.getFields());
  }
  return false;
}

} // namespace

bool sharesClosure(FunctionCallOpInterface call) {
  return llvm::any_of(call.getArgs(), sharedPart);
}

// Every closure or suspension the call passes is a constructor its caller
// built for this call alone, and one at least.
std::optional<SmallVector<BindingTime>> appliesBuiltClosures(FunctionCallOpInterface call) {
  SmallVector<BindingTime> times;
  bool any = false;
  for (Value arg : call.getArgs()) {
    if (!isLabelCarrier(arg.getType())) {
      times.push_back(BindingTime::Varies);
      continue;
    }
    Value made = throughLinear(arg);
    if (!made.getDefiningOp<DataConOp>() || !arg.hasOneUse() || !made.hasOneUse())
      return std::nullopt;
    times.push_back(BindingTime::Fixed);
    any = true;
  }
  if (!any)
    return std::nullopt;
  return times;
}

} // namespace idr::specialize::detail
