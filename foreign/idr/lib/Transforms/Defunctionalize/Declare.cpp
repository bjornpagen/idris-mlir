// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every family the walk writes, declared before any function is rewritten.
//
// A closure family has one label per function of its key's set, in the
// order of their functions in the program, each naming its function and
// holding its captures; a memo family
// one per function, memoized or run by name, then its two states, its
// forced state holding the value. A family is indexed by the index
// variables its carrier mentions, in the order they occur, and each label
// binds its function's own index variables, its equation the terms its
// function's carrier has where the family's indices stand: so an apply's
// result type, which names those variables, is what each case's call gives
// once the case refines the indices.
//
// A capture or forced value that is itself a closure is held as its key's
// family, and a data family of the program whose field holds one is
// declared anew with the family in that field: so declarations reference
// one another, and a reference can close a cycle (a closure capturing a
// value of the family whose field holds it). Each strongly connected group
// of new declarations, as the solver layer's components find them over the
// references, is one group of families, its members referring to one
// another by position, declared after the groups it refers to.

#include "idr/Analysis/Labels.h"
#include "idr/Analysis/Solver/Components.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/STLExtras.h"

#include <deque>

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// The arguments a label of `carrier` is called with besides its captures:
// a closure's, or none, since every parameter of a suspended function is a
// capture.
unsigned arity(Type carrier) {
  auto fn = dyn_cast<FnType>(carrier);
  return fn ? static_cast<unsigned>(fn.getInputs().size()) : 0;
}

// The terms a data type's indices hold, one by one.
SmallVector<ArrayRef<families::TermNode>> termsOf(ArrayRef<families::TermNode> nodes) {
  SmallVector<ArrayRef<families::TermNode>> out;
  while (!nodes.empty()) {
    families::Term term(nodes);
    out.push_back(term.nodes());
    nodes = nodes.drop_front(term.nodes().size());
  }
  return out;
}

// Where `key`'s carrier names an index variable, the term `label`'s carrier
// names at the same place: the two are one type up to their variables, so
// the walk goes through both in step, and each variable's first occurrence
// gives its term. Each variable of the key, in the order it first occurs,
// is one of the family's indices.
struct Equation {
  SmallVector<std::uint64_t> levels;
  SmallVector<SmallVector<families::TermNode>> terms;
};
Equation equate(Type key, Type label) {
  Equation out;
  SmallVector<std::pair<Type, Type>> work{{key, label}};
  while (!work.empty()) {
    auto [k, l] = work.pop_back_val();
    k = unrestricted(k);
    l = unrestricted(l);
    if (auto kf = dyn_cast<FnType>(k)) {
      auto lf = cast<FnType>(l);
      for (auto [a, b] : llvm::reverse(llvm::zip_equal(kf.getResults(), lf.getResults())))
        work.push_back({a, b});
      for (auto [a, b] : llvm::reverse(llvm::zip_equal(kf.getInputs(), lf.getInputs())))
        work.push_back({a, b});
      continue;
    }
    if (auto ks = dyn_cast<ShapedType>(k)) {
      work.push_back({ks.getElementType(), cast<ShapedType>(l).getElementType()});
      continue;
    }
    auto kd = dyn_cast<DataType>(k);
    if (!kd)
      continue;
    auto ld = cast<DataType>(l);
    for (auto [mine, theirs] : llvm::zip_equal(termsOf(kd.getIndices()), termsOf(ld.getIndices())))
      if (mine.size() == 1 && mine.front().kind == families::TermKind::Level &&
          !llvm::is_contained(out.levels, mine.front().value)) {
        out.levels.push_back(mine.front().value);
        out.terms.emplace_back(theirs.begin(), theirs.end());
      }
  }
  return out;
}

// One new declaration, before its group is known: a key's family, or one
// member of a data family of the program declared anew.
struct ForKey {
  KeyId key;
};
struct ForData {
  FamilyAttr group;
  uint32_t member;
};
using Node = std::variant<ForKey, ForData>;

// A new declaration by its place among them, numbered by the decision.
struct DeclarationTag {
  using Minter = Decision;
};
using DeclarationId = Id<DeclarationTag>;

} // namespace

LogicalResult Decision::declare(const solver::ProgramGraph &calls,
                                const IndexVector<solver::FunctionId, effects::Row> &atoms) {
  // Every new declaration: each key's, then each member of each data group
  // a slot reaches, through the fields of the program's data types.
  footprint::Vector<Node> nodes;
  for (unsigned at = 0; at < families.size(); ++at)
    nodes.push_back(ForKey{static_cast<KeyId>(at)});
  llvm::DenseMap<FamilyAttr, unsigned> firstOf;
  AttrTypeWalker groups;
  groups.addWalk([&](DataType data) {
    FamilyAttr group = data.getGroup();
    if (firstOf.contains(group))
      return;
    bool holds = false;
    for (uint32_t m = 0; m < group.getMembers().size() && !holds; ++m) {
      DataType member = DataType::get(ctx, group, m,
                                      families::levelArgs(ctx, 0, group.indices(m).size()).getTerms());
      for (Tag tag : member.possibleTags())
        for (Type field : member.ctor(tag).fields)
          holds = holds || carriesLabels(field);
    }
    if (!holds)
      return;
    firstOf[group] = nodes.size();
    for (uint32_t m = 0; m < group.getMembers().size(); ++m)
      nodes.push_back(ForData{group, m});
  });
  program.walk([&](Operation *op) {
    for (Type type : op->getResultTypes())
      groups.walk(type);
  });

  // What each declaration refers to among the new ones, and the graph of
  // those references, condensed into groups callees first.
  auto nodeOfType = [&](Type type) -> std::optional<unsigned> {
    if (carriesLabels(type))
      return std::nullopt;
    if (auto data = dyn_cast<DataType>(unrestricted(type)))
      if (auto first = firstOf.find(data.getGroup()); first != firstOf.end())
        return first->second + data.getMember();
    return std::nullopt;
  };
  // The type a field of `type` holds, with each slot's key: a capture of a
  // label is its parameter's slot, a forced value the lazy key's anchor, a
  // field of a data family its anchor.
  struct Field {
    Type type;
    Slot slot;
  };
  auto fieldsOf = [&](const Node &node) {
    SmallVector<SmallVector<Field>> out;
    idr::match(
        node,
        [&](ForKey key) {
          const Key &k = families[static_cast<unsigned>(key.key)].key;
          for (auto label : k.labels.getAsRange<FlatSymbolRefAttr>()) {
            const Signature &sig = signature(label.getAttr());
            FuncOp fn = labels.function(label.getAttr());
            unsigned n = fn.getNumArguments() - arity(k.carrier);
            SmallVector<Field> captures;
            for (unsigned i = 0; i < n; ++i)
              captures.push_back({fn.getArgumentTypes()[i], sig.arguments[i]});
            out.push_back(std::move(captures));
          }
          if (carrierOf(k) == Carrier::Lazy) {
            auto lazy = cast<LazyType>(k.carrier);
            out.push_back({});
            out.push_back({{lazy.getValue(), anchorKey(FlowAnchor::forcedOf(lazy))}});
          }
        },
        [&](ForData data) {
          DataType member = DataType::get(
              ctx, data.group, data.member,
              families::levelArgs(ctx, 0, data.group.indices(data.member).size()).getTerms());
          for (Tag tag : member.possibleTags()) {
            SmallVector<Field> fields;
            for (auto [i, field] : llvm::enumerate(member.ctor(tag).fields))
              fields.push_back({field, anchorKey(FlowAnchor::fieldOf(member, tag, static_cast<unsigned>(i)))});
            out.push_back(std::move(fields));
          }
        });
    return out;
  };
  // The references between the new declarations, and their groups, callees
  // first, each group's members in the order the declarations were met.
  CsrBuilder<DeclarationTag> references(Count<DeclarationId>(static_cast<std::uint32_t>(nodes.size())));
  for (auto [at, node] : llvm::enumerate(nodes)) {
    DeclarationId from(static_cast<std::uint32_t>(at));
    for (const SmallVector<Field> &ctor : fieldsOf(node))
      for (const Field &field : ctor) {
        if (field.slot)
          references.edge(from, DeclarationId(static_cast<std::uint32_t>(ids.find(*field.slot)->second)));
        AttrTypeWalker refs;
        refs.addWalk([&](DataType data) {
          if (std::optional<unsigned> to = nodeOfType(data))
            references.edge(from, DeclarationId(*to));
        });
        refs.walk(field.type);
      }
  }
  Partition<DeclarationTag> groupsOf = components(std::move(references).finish());
  footprint::Vector<footprint::Vector<unsigned>> sccs;
  for (auto group : groupsOf.size().ids()) {
    footprint::Vector<unsigned> &scc = sccs.emplace_back();
    for (DeclarationId member : groupsOf.members(group))
      scc.push_back(member.index());
    llvm::sort(scc);
  }

  // Each group, callees first: its members' positions, then each member
  // declared with its references to the group by position and to earlier
  // groups by their types.
  footprint::Vector<DataType> made(nodes.size());
  footprint::Vector<std::optional<std::pair<unsigned, unsigned>>> placed(nodes.size());
  std::deque<SmallVector<Type>> fieldStore;
  std::deque<SmallVector<families::LabelDecl>> labelStore;
  std::deque<SmallVector<families::MemoLabelDecl>> memoStore;
  std::deque<SmallVector<families::CtorDecl>> ctorStore;
  std::deque<SmallVector<families::Sort>> sortStore;
  std::deque<SmallVector<families::TermNode>> termStore;

  for (const footprint::Vector<unsigned> &scc : sccs) {
    for (auto [position, node] : llvm::enumerate(scc))
      placed[node] = std::pair(static_cast<unsigned>(&scc - sccs.data()), static_cast<unsigned>(position));
    // A field's type in the group: a slot's key family, a reference to a
    // member of this group a self type, any other new declaration its type.
    auto inGroup = [&](Type type, const Slot &slot) -> Type {
      Type held = type;
      if (slot) {
        unsigned to = static_cast<unsigned>(ids.find(*slot)->second);
        if (std::find(scc.begin(), scc.end(), to) != scc.end())
          held = SelfType::get(ctx, static_cast<uint32_t>(placed[to]->second), {});
        else
          held = made[to];
        return graded(gradeOf(type), held);
      }
      AttrTypeReplacer local;
      local.addReplacement([&](DataType data) -> std::optional<Type> {
        std::optional<unsigned> to = nodeOfType(data);
        if (!to)
          return std::nullopt;
        if (std::find(scc.begin(), scc.end(), *to) != scc.end())
          return SelfType::get(ctx, static_cast<uint32_t>(placed[*to]->second), data.getIndices());
        return DataType::get(ctx, made[*to].getGroup(), made[*to].getMember(), data.getIndices());
      });
      return local.replace(held);
    };
    SmallVector<families::Member> members;
    for (unsigned node : scc) {
      SmallVector<SmallVector<Field>> ctors = fieldsOf(nodes[node]);
      members.push_back(idr::match(
          nodes[node],
          [&](ForKey key) -> families::Member {
            const Key &k = families[static_cast<unsigned>(key.key)].key;
            SmallVector<families::LabelDecl> &decls = labelStore.emplace_back();
            SmallVector<families::MemoLabelDecl> &memos = memoStore.emplace_back();
            SmallVector<families::Sort> &indices = sortStore.emplace_back();
            for (auto [at, label] : llvm::enumerate(k.labels.getAsRange<FlatSymbolRefAttr>())) {
              FuncOp fn = labels.function(label.getAttr());
              SmallVector<Type> &fields = fieldStore.emplace_back();
              for (const Field &field : ctors[at])
                fields.push_back(inGroup(field.type, field.slot));
              // The label's carrier: its parameters after its captures and
              // its results, in its own variables.
              FunctionType type = fn.getFunctionType();
              unsigned n = type.getNumInputs() - arity(k.carrier);
              Type own = carrierOf(k) == Carrier::Lazy
                             ? Type(LazyType::get(ctx, type.getResult(0)))
                             : Type(FnType::get(ctx, type.getInputs().drop_front(n), type.getResults()));
              Equation equation = equate(k.carrier, own);
              SmallVector<families::TermNode> &terms = termStore.emplace_back();
              for (const SmallVector<families::TermNode> &term : equation.terms)
                llvm::append_range(terms, term);
              ArrayRef<families::Sort> binders;
              if (IndexBindersAttr bound = fn.getBindersAttr())
                binders = bound.getSorts();
              families::LabelDecl decl{label.getAttr(), label, binders, terms, fields};
              if (carrierOf(k) == Carrier::Lazy)
                memos.push_back({atoms[calls.id(label)].contains(effects::Atom::io)
                                     ? families::Mode::ByName
                                     : families::Mode::Memoized,
                                 decl});
              else
                decls.push_back(decl);
              // The family's indices: the key's variables, sorted as the
              // label function binds them where its equation names one.
              if (at == 0)
                for (const SmallVector<families::TermNode> &term : equation.terms)
                  indices.push_back(term.size() == 1 && term.front().kind == families::TermKind::Level &&
                                            term.front().value < binders.size()
                                        ? binders[term.front().value]
                                        : families::Sort{families::SortKind::OpaqueSort, 0, Attribute()});
            }
            StringAttr name = StringAttr::get(ctx, carrierOf(k) == Carrier::Lazy ? "lazy" : "fn");
            if (carrierOf(k) == Carrier::Closure)
              return families::ClosuresMember{name, indices, decls};
            Type forced = ctors.back().empty() ? Type() : inGroup(ctors.back().front().type, ctors.back().front().slot);
            return families::MemoMember{name, indices, memos, forced};
          },
          [&](ForData data) -> families::Member {
            // The member as declared, each field remade for its slot. Only
            // a data member holds the program's own slots: the families a
            // pass declares come after this one.
            return idr::match(
                data.group.getMembers()[data.member],
                [&](const families::DataMember &declared) -> families::Member {
                  SmallVector<families::CtorDecl> &ctorsOut = ctorStore.emplace_back();
                  for (auto [ctor, fields] : llvm::zip_equal(declared.ctors, ctors)) {
                    SmallVector<Type> &types = fieldStore.emplace_back();
                    for (const Field &field : fields)
                      types.push_back(inGroup(field.type, field.slot));
                    ctorsOut.push_back({ctor.label, ctor.binders, ctor.equation, types});
                  }
                  return families::DataMember{declared.label, declared.loc, declared.promise,
                                              declared.indices, ctorsOut};
                },
                [](const auto &other) -> families::Member { return other; });
          }));
    }
    FamilyAttr group = FamilyAttr::get(ctx, members);
    for (auto [position, node] : llvm::enumerate(scc)) {
      auto indices = static_cast<uint32_t>(group.indices(static_cast<uint32_t>(position)).size());
      made[node] = DataType::get(ctx, group, static_cast<uint32_t>(position),
                                 families::levelArgs(ctx, 0, indices).getTerms());
    }
  }

  // Each key's family, applied at its uses to the variables its carrier
  // names; and every old data type replaced by its new declaration, which
  // the replacer reads for the decision's life, so it holds its own tables.
  for (unsigned at = 0; at < families.size(); ++at) {
    families[at].type = made[at];
    for (std::uint64_t level : equate(families[at].key.carrier, families[at].key.carrier).levels)
      families[at].args.push_back(families::TermNode{families::TermKind::Level, 0, 0, level, Attribute()});
  }
  replacer.addReplacement([this, firsts = std::move(firstOf),
                           remade = std::move(made)](DataType data) -> std::optional<Type> {
    if (auto first = firsts.find(data.getGroup()); first != firsts.end()) {
      DataType now = remade[first->second + data.getMember()];
      return DataType::get(ctx, now.getGroup(), now.getMember(), data.getIndices());
    }
    return std::nullopt;
  });
  replacer.addReplacement([&](ShapedType shaped) -> std::optional<Type> {
    Type element = shaped.getElementType();
    if (!carriesLabels(element))
      return std::nullopt;
    return shaped.clone(typeOf(element, anchorKey(FlowAnchor::elementsOf(element))));
  });
  return success();
}

} // namespace idr::defunctionalize
