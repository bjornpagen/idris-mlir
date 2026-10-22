// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Patterns: a value's shape taken into the run's arena, the value a
// pattern stands for built again, and a shape a call no longer reads
// erased.
//
// A constructor is keyed only where its type fixes its fields' types: the
// copy builds the value again from the key alone, so a constructor whose
// fields name binders its application leaves open (a closure label's own
// index parameters, bound afresh by each case that takes it apart) is a
// runtime leaf. Each walk keeps its own stack: a shape is as deep as the
// constructors a call's arguments nest.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize::detail {

namespace {

// A constant the copy builds again as it was built here: the value of an
// op the dialect materializes.
std::optional<Attribute> constantOf(Value value) {
  Attribute known;
  Operation *def = value.getDefiningOp();
  if (!def || !def->hasTrait<OpTrait::ConstantLike>() || !matchPattern(value, m_Constant(&known)))
    return std::nullopt;
  return known;
}

// The constructor that built `value`, through the ops that only change its
// grade, where its type fixes its fields' types.
DataConOp constructorOf(Value value) {
  auto con = throughLinear(value).getDefiningOp<DataConOp>();
  if (!con)
    return {};
  DataType data = dataTypeOf(con.getResult().getType());
  if (!data || !data.determinedFields(con.getTag()))
    return {};
  return con;
}

// The field types of constructor `tag` at a position of `type`, which the
// key fixed only where the type determines them.
llvm::SmallVector<Type> fieldTypes(Type type, Tag tag) {
  return *dataTypeOf(unrestricted(type)).determinedFields(tag);
}

// Whether a position of `type` holds a value used at most once: a value
// there entered that quantity, which a rebuilt value enters again.
bool usedOncePosition(Type type) { return isLinear(type); }

// One node of a shape in pre-order: a hole, a constant, or a constructor
// over the next `arity` nodes' subtrees.
struct LeafNode {};
struct ConstNode {
  Attribute value;
};
struct ConNode {
  Tag tag;
  unsigned arity;
};
using ShapeNode = std::variant<LeafNode, ConstNode, ConNode>;

} // namespace

const Pattern *shapeOf(Arena &arena, Value value, SmallVectorImpl<Value> &leaves) {
  // The nodes in pre-order, the leaves in that order as they are met.
  SmallVector<ShapeNode> order;
  SmallVector<Value> work{value};
  while (!work.empty()) {
    Value at = work.pop_back_val();
    if (std::optional<Attribute> known = constantOf(at)) {
      order.push_back(ConstNode{*known});
      continue;
    }
    DataConOp con = constructorOf(at);
    if (!con) {
      order.push_back(LeafNode{});
      leaves.push_back(at);
      continue;
    }
    order.push_back(ConNode{con.getTag(), static_cast<unsigned>(con.getFields().size())});
    for (Value field : llvm::reverse(con.getFields()))
      work.push_back(field);
  }
  // Built from the last node back: a constructor's subtrees follow it in
  // pre-order, so they are built when it is reached.
  SmallVector<const Pattern *> built;
  for (const ShapeNode &node : llvm::reverse(order))
    idr::match(
        node, [&](LeafNode) { built.push_back(arena.hole()); },
        [&](const ConstNode &constant) { built.push_back(arena.constant(constant.value)); },
        [&](const ConNode &con) {
          SmallVector<const Pattern *> fields;
          for (unsigned i = 0; i < con.arity; ++i)
            fields.push_back(built.pop_back_val());
          built.push_back(arena.con(con.tag, fields));
        });
  return built.front();
}

bool isClosed(Value value) {
  SmallVector<Value> work{value};
  while (!work.empty()) {
    Value at = work.pop_back_val();
    if (matchPattern(at, m_Constant()))
      continue;
    auto con = at.getDefiningOp<DataConOp>();
    if (!con)
      return false;
    llvm::append_range(work, con.getFields());
  }
  return true;
}

// Each op that built the shape, through the ops that only change a grade,
// has one use: the call that reads it.
bool usedOnce(Value value) {
  SmallVector<Value> work{value};
  while (!work.empty()) {
    Value at = work.pop_back_val();
    Operation *def = at.getDefiningOp();
    bool builds = def && (isa<DataConOp>(def) || throughLinear(at) != at);
    if (!builds)
      continue;
    if (!at.hasOneUse())
      return false;
    llvm::append_range(work, def->getOperands());
  }
  return true;
}

// An op is erased once it has no use left. Each op that builds a shape
// has one result, which loses its last use only when its last reader is
// erased, after which no reader is left to name it again: so a value is
// met twice before its op is erased only within one batch that names it
// twice (the values given, or one erased op's operands), and each batch
// reads each of its values once.
void eraseUnused(RewriterBase &rewriter, ArrayRef<Value> values) {
  SmallVector<Operation *> dead;
  auto consider = [&](ArrayRef<Value> batch) {
    for (auto [at, value] : llvm::enumerate(batch)) {
      if (llvm::is_contained(batch.take_front(at), value))
        continue;
      Operation *def = value.getDefiningOp();
      if (def && (isa<DataConOp>(def) || throughLinear(value) != value) && def->use_empty())
        dead.push_back(def);
    }
  };
  consider(values);
  while (!dead.empty()) {
    Operation *op = dead.pop_back_val();
    SmallVector<Value> operands(op->getOperands());
    rewriter.eraseOp(op);
    consider(operands);
  }
}

namespace {

// One step of a rebuild: a pattern to build at a position of a type, or a
// constructor whose fields, the last `arity` values built, are ready; or a
// value to enter a quantity-one position once built.
struct BuildAt {
  const Pattern *pattern;
  Type type;
};
struct MakeCon {
  Type type;
  Tag tag;
  unsigned arity;
};
struct Enter {
  Type type;
};
using RebuildStep = std::variant<BuildAt, MakeCon, Enter>;

} // namespace

// A hole is the next parameter, a quantity-one position enters what is
// built inside it, a constructor is built over its fields at their
// determined types, and a constant is the one the dialect materializes.
Value rebuild(OpBuilder &b, Location loc, const Pattern &pattern, Type type,
              ArrayRef<Value> holes, unsigned &next) {
  Dialect *idr = b.getContext()->getLoadedDialect<IdrDialect>();
  SmallVector<Value> built;
  SmallVector<RebuildStep> work{BuildAt{&pattern, type}};
  while (!work.empty()) {
    RebuildStep step = work.pop_back_val();
    idr::match(
        step,
        [&](const Enter &enter) {
          Value inner = built.pop_back_val();
          built.push_back(LinCastOp::create(b, loc, enter.type, inner).getResult());
        },
        [&](const MakeCon &make) {
          SmallVector<Value> fields(built.end() - make.arity, built.end());
          built.resize(built.size() - make.arity);
          built.push_back(DataConOp::create(b, loc, make.type, make.tag, fields).getResult());
        },
        [&](const BuildAt &at) {
          idr::match(
              at.pattern->get(), [&](Hole) { built.push_back(holes[next++]); },
              [&](const Con &con) {
                if (usedOncePosition(at.type)) {
                  work.push_back(Enter{at.type});
                  work.push_back(BuildAt{at.pattern, unrestricted(at.type)});
                  return;
                }
                SmallVector<Type> types = fieldTypes(at.type, con.tag);
                work.push_back(MakeCon{at.type, con.tag, static_cast<unsigned>(con.fields.size())});
                for (unsigned k = con.fields.size(); k-- > 0;)
                  work.push_back(BuildAt{con.fields[k], types[k]});
              },
              [&](const Const &constant) {
                built.push_back(idr->materializeConstant(b, constant.value, at.type, loc)->getResult(0));
              });
        });
  }
  return built.front();
}

void holeTypes(const Pattern &pattern, Type type, SmallVectorImpl<Type> &out) {
  SmallVector<std::pair<const Pattern *, Type>> work{{&pattern, type}};
  while (!work.empty()) {
    auto [at, position] = work.pop_back_val();
    idr::match(
        at->get(), [&](Hole) { out.push_back(position); },
        [&](const Con &con) {
          SmallVector<Type> types = fieldTypes(position, con.tag);
          for (unsigned k = con.fields.size(); k-- > 0;)
            work.push_back({con.fields[k], types[k]});
        },
        [](const Const &) {});
  }
}

} // namespace idr::specialize::detail
