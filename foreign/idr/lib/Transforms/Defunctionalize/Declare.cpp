// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every family the walk writes, declared before any function is rewritten,
// and every signature and constant as their slots have them.
//
// A closure family has one label per function of its key's set, in name
// order, each naming its function and holding its captures; a memo family
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
// of new declarations is one group of families, its members referring to
// one another by position, declared after the groups it refers to.

#include "idr/Analysis/Labels.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/SCCIterator.h"
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

} // namespace

LogicalResult Decision::declare(const llvm::DenseSet<StringAttr> &byName) {
  // Every new declaration: each key's, then each member of each data group
  // a slot reaches, through the fields of the program's data types.
  SmallVector<Node> nodes;
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
      DataType member = DataType::get(group, m, families::levelArgs(ctx, 0, group.indexCount(m)).getTerms());
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
              data.group, data.member,
              families::levelArgs(ctx, 0, data.group.indexCount(data.member)).getTerms());
          for (Tag tag : member.possibleTags()) {
            SmallVector<Field> fields;
            for (auto [i, field] : llvm::enumerate(member.ctor(tag).fields))
              fields.push_back({field, anchorKey(FlowAnchor::fieldOf(member, tag, static_cast<unsigned>(i)))});
            out.push_back(std::move(fields));
          }
        });
    return out;
  };
  std::vector<std::vector<unsigned>> edges(nodes.size() + 1);
  for (auto [at, node] : llvm::enumerate(nodes))
    for (const SmallVector<Field> &ctor : fieldsOf(node))
      for (const Field &field : ctor) {
        if (field.slot)
          edges[at].push_back(static_cast<unsigned>(ids.find(*field.slot)->second));
        AttrTypeWalker refs;
        refs.addWalk([&](DataType data) {
          if (std::optional<unsigned> to = nodeOfType(data))
            edges[at].push_back(*to);
        });
        refs.walk(field.type);
      }
  unsigned root = nodes.size();
  for (unsigned at = 0; at < root; ++at)
    edges[root].push_back(at);

  // Each group, callees first: its members' positions, then each member
  // declared with its references to the group by position and to earlier
  // groups by their types.
  SmallVector<DataType> made(nodes.size());
  SmallVector<std::optional<std::pair<unsigned, unsigned>>> placed(nodes.size());
  std::deque<SmallVector<Type>> fieldStore;
  std::deque<SmallVector<families::LabelDecl>> labelStore;
  std::deque<SmallVector<families::MemoLabelDecl>> memoStore;
  std::deque<SmallVector<families::CtorDecl>> ctorStore;
  std::deque<SmallVector<families::Sort>> sortStore;
  std::deque<SmallVector<families::TermNode>> termStore;

  struct Graph {
    const std::vector<std::vector<unsigned>> *edges;
    unsigned root;
  };
  Graph graph{&edges, root};
  std::vector<std::vector<unsigned>> sccs;
  {
    // An explicit Tarjan over the reference graph: no recursion follows the
    // depth of references.
    std::vector<int> index(nodes.size() + 1, -1), low(nodes.size() + 1, 0);
    std::vector<bool> onStack(nodes.size() + 1, false);
    std::vector<unsigned> stack;
    int counter = 0;
    struct Frame {
      unsigned node;
      unsigned next;
    };
    std::vector<Frame> frames{{root, 0}};
    index[root] = low[root] = counter++;
    stack.push_back(root);
    onStack[root] = true;
    while (!frames.empty()) {
      Frame &frame = frames.back();
      const std::vector<unsigned> &out = (*graph.edges)[frame.node];
      if (frame.next < out.size()) {
        unsigned to = out[frame.next++];
        if (index[to] < 0) {
          index[to] = low[to] = counter++;
          stack.push_back(to);
          onStack[to] = true;
          frames.push_back({to, 0});
        } else if (onStack[to]) {
          low[frame.node] = std::min(low[frame.node], index[to]);
        }
        continue;
      }
      unsigned done = frame.node;
      frames.pop_back();
      if (!frames.empty())
        low[frames.back().node] = std::min(low[frames.back().node], low[done]);
      if (low[done] != index[done])
        continue;
      std::vector<unsigned> scc;
      unsigned member;
      do {
        member = stack.back();
        stack.pop_back();
        onStack[member] = false;
        if (member != root)
          scc.push_back(member);
      } while (member != done);
      if (!scc.empty()) {
        llvm::sort(scc);
        sccs.push_back(std::move(scc));
      }
    }
  }

  for (const std::vector<unsigned> &scc : sccs) {
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
        return DataType::get(made[*to].getGroup(), made[*to].getMember(), data.getIndices());
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
                memos.push_back({byName.contains(label.getAttr()) ? families::Mode::ByName
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
                                        : families::Sort{families::SortKind::Opaque, 0, Attribute()});
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
      uint32_t indices = group.indexCount(static_cast<uint32_t>(position));
      made[node] = DataType::get(group, static_cast<uint32_t>(position),
                                 families::levelArgs(ctx, 0, indices).getTerms());
    }
  }

  // Each key's family, applied at its uses to the variables its carrier
  // names; and every old data type replaced by its new declaration.
  for (unsigned at = 0; at < families.size(); ++at)
    families[at].type = made[at];
  replacer.addReplacement([&](DataType data) -> std::optional<Type> {
    if (auto first = firstOf.find(data.getGroup()); first != firstOf.end()) {
      DataType now = made[first->second + data.getMember()];
      return DataType::get(now.getGroup(), now.getMember(), data.getIndices());
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

// A slot's type: its key's family applied to the variables the carrier
// names, at the carrier's grade; any other type remade where its parts
// hold slots.
Type Decision::typeOf(Type type, const Slot &slot) const {
  if (!slot)
    return const_cast<AttrTypeReplacer &>(replacer).replace(type);
  DataType family = familyOf(*slot).type;
  Equation vars = equate(slot->carrier, slot->carrier);
  SmallVector<families::TermNode> args;
  for (std::uint64_t level : vars.levels)
    args.push_back(families::TermNode{families::TermKind::Level, 0, 0, level, Attribute()});
  return graded(gradeOf(type), DataType::get(family.getGroup(), family.getMember(), args));
}

Tag Decision::tagOf(const Key &key, FlatSymbolRefAttr label) const {
  return Tag{*labels::positionIn(key.labels, label)};
}

void Decision::convertSignatures() {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    Signature &sig = signatures[fn.getSymNameAttr()];
    SmallVector<Type> inputs, results;
    for (auto [type, slot] : llvm::zip_equal(fn.getArgumentTypes(), sig.arguments))
      inputs.push_back(typeOf(type, slot));
    for (auto [type, slot] : llvm::zip_equal(fn.getResultTypes(), sig.results))
      results.push_back(typeOf(type, slot));
    sig.converted = FunctionType::get(ctx, inputs, results);
  }
}

// A constant held in `slot`, each closure in it its label's constructor in
// its slot's family, each constructor of a data family remade with its
// fields in their slots. A part shared by many constants is converted once
// per slot.
Attribute Decision::constantOf(Attribute value, const Slot &slot) const {
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

FailureOr<std::unique_ptr<Decision>> Decision::decide(ProgramOp program, const Labels &labels,
                                                      const llvm::DenseSet<StringAttr> &byName) {
  std::unique_ptr<Decision> decision(new Decision(program, labels));
  Decision &d = *decision;
  // Every signature first, which every other key of a parameter or a
  // result reads; then the widening, which reads the sinks; then every key
  // the program's values and types ask for.
  for (FuncOp fn : program.getOps<FuncOp>()) {
    Signature &sig = d.signatures[fn.getSymNameAttr()];
    for (BlockArgument arg : fn.getArguments())
      sig.arguments.push_back(d.keyWith(arg.getType(), FlowPoint::of(Value(arg))));
    auto name = FlatSymbolRefAttr::get(fn.getSymNameAttr());
    for (auto [j, type] : llvm::enumerate(fn.getResultTypes()))
      sig.results.push_back(d.keyWith(type, FlowPoint::result(name, static_cast<unsigned>(j))));
  }
  d.widen();
  for (FuncOp fn : program.getOps<FuncOp>()) {
    const Signature &sig = d.signature(fn.getSymNameAttr());
    for (const Slot &slot : llvm::concat<const Slot>(sig.arguments, sig.results))
      d.note(slot);
    for (Type type : fn.getFunctionType().getInputs())
      d.noteType(type);
    for (Type type : fn.getFunctionType().getResults())
      d.noteType(type);
    fn.walk([&](Operation *op) {
      for (Value result : op->getResults()) {
        d.note(d.keyOf(result));
        d.noteType(result.getType());
      }
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (Value arg : block.getArguments()) {
            d.note(d.keyOf(arg));
            d.noteType(arg.getType());
          }
    });
  }
  if (failed(d.declare(byName)))
    return failure();
  d.convertSignatures();
  // Each memo family's dispatch function, born rewritten.
  for (Family &family : d.families) {
    if (carrierOf(family.key) != Carrier::Lazy)
      continue;
    FailureOr<FuncOp> force = d.defineForce(family);
    if (failed(force))
      return failure();
    family.force = FlatSymbolRefAttr::get(force->getSymNameAttr());
    d.made.push_back(*force);
  }
  return decision;
}

} // namespace idr::defunctionalize
