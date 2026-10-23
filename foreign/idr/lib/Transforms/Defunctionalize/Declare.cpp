// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every family the walk writes, declared before any function is rewritten.
//
// A closure family has one label per function of its key's set, in the
// order of their functions in the program, each naming its function and
// holding its captures; a memo family one per function, memoized or run by
// name, then its two states, its forced state holding the value. A family
// is indexed by every index term its carrier names, one index per place a
// term stands (each index of a data type, the binders' terms its refinement
// keeps, a natural's), of the sort of that place; each label binds its
// function's own index variables, its equation the terms its function's
// carrier names at the same places. So a label's binders are what the
// case's refinement solves them to, wherever they stand in a term, and an
// apply's result type is what each case's call gives with nothing after
// the call to relate them.
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
#include "idr/IR/Symbols.h"
#include "idr/Support/Id.h"
#include "idr/Support/Match.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/Endian.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/xxhash.h"

#include <array>
#include <deque>

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// The arguments a label of `carrier` is called with besides its captures,
// as the carrier answers: a closure's inputs, or none for a suspension.
unsigned arity(const LabelCarrier &carrier) {
  return match(carrier, [](const OneOf<carrying::Closure, carrying::Suspension> auto &labels) {
    return labels.arity();
  });
}

// The name of a key's family: its kind and the digest of the key, its
// carrier's content and its labels', each word written low byte first. Two
// keys are two families, so no two members of one group share a name, and
// a key names its family alike in every process and on every target.
StringAttr nameOf(MLIRContext *ctx, const Key &key) {
  llvm::XXH128_hash_t carrier = stableDigest(key.carrier), labels = stableDigest(key.labels);
  std::array<std::uint64_t, 4> words{carrier.low64, carrier.high64, labels.low64, labels.high64};
  std::array<std::uint8_t, 32> bytes;
  for (auto [at, word] : llvm::enumerate(words))
    llvm::support::endian::write64le(bytes.data() + 8 * at, word);
  llvm::XXH128_hash_t digest = llvm::xxh3_128bits(bytes);
  llvm::SmallString<40> name(match(
      labelCarrierOf(key), [](const carrying::Closure &) -> llvm::StringRef { return "fn."; },
      [](const carrying::Suspension &) -> llvm::StringRef { return "lazy."; }));
  llvm::raw_svector_ostream os(name);
  os << llvm::format_hex_no_prefix(digest.high64, 16)
     << llvm::format_hex_no_prefix(digest.low64, 16);
  return StringAttr::get(ctx, name);
}

// The levels a member of `group` binds as its own index variables, from 0:
// one per index, and a level is a 32-bit number.
IndexArgsAttr ownLevels(MLIRContext *ctx, FamilyAttr group, uint32_t member) {
  return families::levelArgs(ctx, 0, static_cast<std::uint32_t>(group.indices(member).size()));
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

LogicalResult Decision::declare(const IndexVector<solver::FunctionId, effects::Row> &atoms) {
  // Every new declaration: each key's, then each member of each data group
  // a slot reaches, through the fields of the program's data types.
  footprint::Vector<Node> nodes;
  for (unsigned at = 0; at < families.size(); ++at)
    nodes.push_back(ForKey{static_cast<KeyId>(at)});
  footprint::DenseMap<FamilyAttr, unsigned> firstOf;
  AttrTypeWalker groups;
  groups.addWalk([&](DataType data) {
    FamilyAttr group = data.getGroup();
    if (firstOf.contains(group))
      return;
    bool holds = false;
    for (uint32_t m = 0; m < group.getMembers().size() && !holds; ++m) {
      DataType member = DataType::get(ctx, group, m, ownLevels(ctx, group, m).getTerms());
      for (Tag tag : member.possibleTags())
        for (Type field : member.ctor(tag).fields)
          holds = holds || carriesLabels(field);
    }
    if (!holds)
      return;
    // Declaration nodes are numbered by 32-bit ids.
    firstOf[group] = static_cast<unsigned>(nodes.size());
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
          LabelCarrier carrier = labelCarrierOf(k);
          for (auto label : k.labels.getAsRange<FlatSymbolRefAttr>()) {
            const Signature &sig = signature(graph.id(label));
            FuncOp fn = labels.function(label.getAttr());
            unsigned n = fn.getNumArguments() - arity(carrier);
            SmallVector<Field> captures;
            for (unsigned i = 0; i < n; ++i)
              captures.push_back({fn.getArgumentTypes()[i], sig.arguments[i]});
            out.push_back(std::move(captures));
          }
          // A memo family's two states follow its labels: the unforced,
          // which holds nothing, and the forced, which holds the value.
          match(
              carrier, [](const carrying::Closure &) {},
              [&](const carrying::Suspension &suspension) {
                LazyType lazy = suspension.type.get();
                out.push_back({});
                out.push_back(
                    {{overPositions(lazy.getValue()), anchorKey(FlowAnchor::forcedOf(lazy))}});
              });
        },
        [&](ForData data) {
          DataType member = DataType::get(ctx, data.group, data.member,
                                          ownLevels(ctx, data.group, data.member).getTerms());
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
  footprint::Vector<DataType> declared(nodes.size());
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
    // A slot's family is at the terms the field's own type names, in the
    // scope of the declaration that holds it.
    auto inGroup = [&](Type type, const Slot &slot) -> Type {
      Type held = type;
      if (slot) {
        unsigned to = static_cast<unsigned>(ids.find(*slot)->second);
        SmallVector<families::TermNode> terms = indexTermsOf(unrestricted(type)).nodes;
        if (std::find(scc.begin(), scc.end(), to) != scc.end())
          held = SelfType::get(ctx, static_cast<uint32_t>(placed[to]->second), terms);
        else
          held = DataType::get(ctx, declared[to].getGroup(), declared[to].getMember(), terms);
        return graded(gradeOf(type), held);
      }
      AttrTypeReplacer local;
      local.addReplacement([&](DataType data) -> std::optional<Type> {
        std::optional<unsigned> to = nodeOfType(data);
        if (!to)
          return std::nullopt;
        if (std::find(scc.begin(), scc.end(), *to) != scc.end())
          return SelfType::get(ctx, static_cast<uint32_t>(placed[*to]->second), data.getIndices());
        return DataType::get(ctx, declared[*to].getGroup(), declared[*to].getMember(), data.getIndices());
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
            LabelCarrier carrier = labelCarrierOf(k);
            SmallVector<families::LabelDecl> &decls = labelStore.emplace_back();
            SmallVector<families::MemoLabelDecl> &memos = memoStore.emplace_back();
            // The family's indices: each place of an index term the key's
            // carrier names, by its sort, whatever labels it has.
            SmallVector<families::Sort> &indices =
                sortStore.emplace_back(indexTermsOf(k.carrier).sorts);
            for (auto [at, label] : llvm::enumerate(k.labels.getAsRange<FlatSymbolRefAttr>())) {
              FuncOp fn = labels.function(label.getAttr());
              SmallVector<Type> &fields = fieldStore.emplace_back();
              for (const Field &field : ctors[at])
                fields.push_back(inGroup(field.type, field.slot));
              // The label's carrier: its parameters after its captures and
              // its results, in its own variables; its equation the terms it
              // names at the family's places.
              FunctionType type = fn.getFunctionType();
              unsigned n = type.getNumInputs() - arity(carrier);
              Type own = match(
                  carrier,
                  [&](const carrying::Closure &) -> Type {
                    return FnType::get(ctx, type.getInputs().drop_front(n), type.getResults());
                  },
                  [&](const carrying::Suspension &) -> Type {
                    return LazyType::get(ctx, type.getResult(0));
                  });
              SmallVector<families::TermNode> &terms =
                  termStore.emplace_back(indexTermsOf(own).nodes);
              ArrayRef<families::Sort> binders;
              if (IndexBindersAttr bound = fn.getBindersAttr())
                binders = bound.getSorts();
              families::LabelDecl decl{label.getAttr(), label, binders, terms, fields};
              match(
                  carrier, [&](const carrying::Closure &) { decls.push_back(decl); },
                  [&](const carrying::Suspension &) {
                    memos.push_back({atoms[graph.id(label)].contains(effects::Atom::io)
                                         ? Mode::ByName
                                         : Mode::Memoized,
                                     decl});
                  });
            }
            StringAttr name = nameOf(ctx, k);
            return match(
                carrier,
                [&](const carrying::Closure &) -> families::Member {
                  return families::ClosuresMember{name, indices, decls};
                },
                [&](const carrying::Suspension &) -> families::Member {
                  Type forced = ctors.back().empty()
                                    ? Type()
                                    : inGroup(ctors.back().front().type, ctors.back().front().slot);
                  return families::MemoMember{name, indices, memos, forced};
                });
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
                [](const OneOf<families::ClosuresMember, families::MemoMember,
                               families::FramesMember> auto &other) -> families::Member {
                  return other;
                });
          }));
    }
    FamilyAttr group = FamilyAttr::get(ctx, members);
    for (auto [position, node] : llvm::enumerate(scc)) {
      auto indices = static_cast<uint32_t>(group.indices(static_cast<uint32_t>(position)).size());
      declared[node] = DataType::get(ctx, group, static_cast<uint32_t>(position),
                                 families::levelArgs(ctx, 0, indices).getTerms());
    }
  }

  // Each key's family, applied at its uses to the index terms its carrier
  // names; and every old data type replaced by its new declaration, at its
  // own indices and refined as it was, since a member declared anew keeps
  // its constructors in their order. The replacer reads these tables for
  // the decision's life, so it holds its own.
  for (unsigned at = 0; at < families.size(); ++at) {
    families[at].type = declared[at];
    families[at].at = DataType::get(ctx, declared[at].getGroup(), declared[at].getMember(),
                                    indexTermsOf(families[at].key.carrier).nodes);
  }
  replacer.addReplacement([this, firsts = std::move(firstOf),
                           remade = std::move(declared)](DataType data) -> std::optional<Type> {
    auto first = firsts.find(data.getGroup());
    if (first == firsts.end())
      return std::nullopt;
    DataType now = remade[first->second + data.getMember()];
    DataType out = DataType::get(ctx, now.getGroup(), now.getMember(), data.getIndices());
    if (!data.getRefinement())
      return out;
    const families::TagSet &tags = data.possibleTags();
    if (tags.size() == 1 && !data.getBinders().empty())
      return out.refinedTo(tags.front(), data.getBinders());
    return out.refined(SmallVector<Tag>(tags.begin(), tags.end()));
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
