// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The partition of the optimized program into the bins whose code is
// generated at once, and the linkage the bins then read; the cut of its
// parts into bins is Bins.cpp's, and reading one bin back out of the
// bitcode Extract.cpp's. After O3 code generation is local to each
// function, so a bin holds whole components of the reference graph, each
// with the callee of its musttail calls (no tail call crosses an object),
// its comdat and an ifunc's resolver. A constant whose address nothing
// tells apart is copied into each bin that reads it.

#include "idr/Target/Target.h"

#include "idr/IR/Symbols.h"
#include "idr/Analysis/Solver/Components.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Support/Id.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/EquivalenceClasses.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalAlias.h"
#include "llvm/IR/GlobalIFunc.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"

#include <cassert>
#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

using namespace llvm;
using idr::target::Partition;

namespace {

// An error of the partition's, which its caller reports as the compiler's.
Error internal(const Twine &what) { return createStringError(what); }

// What a function's body and operands (personality, prefix, prologue), a
// variable's initializer, an alias's aliasee or an ifunc's resolver names,
// through every constant expression and aggregate it holds. Each constant
// enters once.
SmallVector<const GlobalValue *> referencesOf(const GlobalValue &value) {
  // LLVM's constants have no number of ours, so the walk keeps the ones it
  // met by address, for the one walk.
  SmallPtrSet<const Constant *, 16> met;
  std::vector<const Constant *> constants;
  auto collect = [&](const Value *operand) {
    if (auto *constant = dyn_cast<Constant>(operand); constant && met.insert(constant).second)
      constants.push_back(constant);
  };
  if (auto *function = dyn_cast<Function>(&value)) {
    for (const Use &operand : function->operands())
      collect(operand.get());
    for (const Instruction &instruction : instructions(*function))
      for (const Use &operand : instruction.operands())
        collect(operand.get());
  } else if (auto *variable = dyn_cast<GlobalVariable>(&value); variable && variable->hasInitializer()) {
    collect(variable->getInitializer());
  } else if (auto *alias = dyn_cast<GlobalAlias>(&value)) {
    collect(alias->getAliasee());
  } else if (auto *ifunc = dyn_cast<GlobalIFunc>(&value)) {
    collect(ifunc->getResolver());
  }
  SmallVector<const GlobalValue *> found;
  while (!constants.empty()) {
    const Constant *constant = constants.back();
    constants.pop_back();
    if (auto *global = dyn_cast<GlobalValue>(constant)) {
      found.push_back(global);
      continue;
    }
    for (const Use &operand : constant->operands())
      collect(operand.get());
  }
  return found;
}

// The nodes of the reference graph, numbered once by the partition, the
// one minter of their ids.
struct NodeMinter;
struct NodeTag {
  using Minter = NodeMinter;
};
using NodeId = idr::Id<NodeTag>;
struct NodeMinter {
  static idr::Count<NodeId> count(unsigned nodes) { return idr::Count<NodeId>(nodes); }
  static NodeId id(unsigned node) { return NodeId(node); }
};

// What a symbol of the optimized module is to the partition: declared only,
// a copied constant, one of the reference graph's nodes, which a bin
// defines, or an alias, which stands for the node of the object it aliases,
// if any. A declared role and a copied one are the homes of the same name
// (Partition::Declared, Partition::Copied).
struct Node {
  unsigned index;
};
struct Alias {
  // The symbol of the object it aliases, or none.
  std::optional<unsigned> base;
};

} // namespace

std::vector<GlobalValue *> Partition::positions(Module &module) {
  std::vector<GlobalValue *> at;
  for (GlobalValue &value : module.global_values())
    at.push_back(&value);
  return at;
}

Expected<Partition> Partition::of(Module &module) {
  for (GlobalVariable &variable : module.globals())
    if (variable.hasAppendingLinkage())
      return internal("the optimized module holds the appending global " + variable.getName() +
                      ", which belongs to every object and so to no one bin");
  std::vector<GlobalValue *> at = positions(module);
  // The numbering itself: LLVM's global values carry no number of ours, so
  // a symbol named by address is turned into its place here, once, and
  // every later step reads places. A place is `unsigned`, as LLVM numbers a
  // module's values when it writes the bitcode each bin is read back from,
  // and as its BitVector counts; so the count is taken in that type once,
  // here, where the range is LLVM's own.
  assert(at.size() <= std::numeric_limits<unsigned>::max() &&
         "LLVM numbers a module's values as unsigned");
  auto numSymbols = static_cast<unsigned>(at.size());
  DenseMap<const GlobalValue *, unsigned> place;
  for (unsigned symbol = 0; symbol < numSymbols; ++symbol)
    place[at[symbol]] = symbol;
  // The objects an alias names, by place.
  BitVector aliased(numSymbols);
  for (GlobalAlias &alias : module.aliases())
    if (const GlobalObject *object = alias.getAliaseeObject())
      aliased.set(place.lookup(object));

  // Roles: an available_externally body is the runtime's native half's,
  // which no bin defines, and none survives O3. Each symbol's role is
  // written once, here.
  Partition partition;
  partition.symbols.resize(numSymbols);
  using SymbolRole = std::variant<Partition::Declared, Partition::Copied, Node, Alias>;
  std::vector<SymbolRole> role(numSymbols, Partition::Declared{});
  std::vector<unsigned> nodes;
  for (unsigned symbol = 0; symbol < numSymbols; ++symbol) {
    GlobalValue *value = at[symbol];
    for (const GlobalValue *named : referencesOf(*value))
      partition.symbols[symbol].refs.push_back(place.lookup(named));
    if (value->isDeclaration() || value->hasAvailableExternallyLinkage())
      continue;
    if (auto *alias = dyn_cast<GlobalAlias>(value)) {
      const GlobalObject *object = alias->getAliaseeObject();
      role[symbol] = Alias{object ? std::optional<unsigned>(place.lookup(object)) : std::nullopt};
      continue;
    }
    auto *variable = dyn_cast<GlobalVariable>(value);
    if (variable && variable->isConstant() && variable->hasLocalLinkage() &&
        variable->hasAtLeastLocalUnnamedAddr() && !variable->hasComdat() &&
        !aliased.test(symbol)) {
      role[symbol] = Partition::Copied{};
      continue;
    }
    role[symbol] = Node{static_cast<unsigned>(nodes.size())};
    nodes.push_back(symbol);
  }
  // The node a symbol is, or an alias stands for; none for any other.
  auto baseOf = [&](unsigned symbol) -> std::optional<unsigned> {
    auto nodeOf = [](const SymbolRole &of) {
      return idr::match(
          of, [](Node node) -> std::optional<unsigned> { return node.index; },
          [](const idr::OneOf<Partition::Declared, Partition::Copied, Alias> auto &)
              -> std::optional<unsigned> { return std::nullopt; });
    };
    return idr::match(
        role[symbol], [](Node node) -> std::optional<unsigned> { return node.index; },
        [&](Alias alias) -> std::optional<unsigned> {
          return alias.base ? nodeOf(role[*alias.base]) : std::nullopt;
        },
        [](const idr::OneOf<Partition::Declared, Partition::Copied> auto &)
            -> std::optional<unsigned> { return std::nullopt; });
  };
  // Each symbol `from` names, a copied constant standing for what it names.
  // Each symbol enters once.
  auto reach = [&](unsigned from, auto &&visit) {
    BitVector met(numSymbols);
    std::vector<unsigned> work;
    auto push = [&](unsigned named) {
      if (!met.test(named)) {
        met.set(named);
        work.push_back(named);
      }
    };
    for (unsigned named : partition.symbols[from].refs)
      push(named);
    while (!work.empty()) {
      unsigned named = work.back();
      work.pop_back();
      idr::match(
          role[named],
          [&](Partition::Copied) {
            for (unsigned next : partition.symbols[named].refs)
              push(next);
          },
          [&](const idr::OneOf<Partition::Declared, Node, Alias> auto &) { visit(named); });
    }
  };

  // Components of the reference graph, then joined.
  auto count = static_cast<unsigned>(nodes.size());
  idr::CsrBuilder<NodeTag> edges(NodeMinter::count(count));
  for (unsigned node = 0; node < count; ++node)
    reach(nodes[node], [&](unsigned named) {
      if (std::optional<unsigned> base = baseOf(named))
        edges.edge(NodeMinter::id(node), NodeMinter::id(*base));
    });
  idr::Partition<NodeTag> components = idr::components(std::move(edges).finish());
  EquivalenceClasses<unsigned> joined;
  for (unsigned node = 0; node < count; ++node)
    joined.insert(node);
  for (auto component : components.size().ids()) {
    auto members = components.members(component);
    for (NodeId node : members)
      joined.unionSets(members.front().index(), node.index());
  }
  auto join = [&](unsigned node, std::optional<unsigned> other) {
    if (other)
      joined.unionSets(node, *other);
  };
  // LLVM's comdats have no number of ours, so the first node of each is
  // kept by address, for this one partition.
  DenseMap<const Comdat *, unsigned> comdatNode;
  for (unsigned node = 0; node < nodes.size(); ++node) {
    auto *object = cast<GlobalObject>(at[nodes[node]]);
    if (const Comdat *comdat = object->getComdat())
      join(node, comdatNode.try_emplace(comdat, node).first->second);
    if (auto *ifunc = dyn_cast<GlobalIFunc>(object); ifunc && ifunc->getResolverFunction())
      join(node, baseOf(place.lookup(ifunc->getResolverFunction())));
    if (auto *function = dyn_cast<Function>(object))
      for (const Instruction &instruction : instructions(*function))
        if (auto *call = dyn_cast<CallInst>(&instruction); call && call->isMustTailCall())
          if (const Function *callee = call->getCalledFunction())
            join(node, baseOf(place.lookup(callee)));
  }

  // The parts, numbered as their first node comes in module order.
  std::vector<Part> parts;
  DenseMap<unsigned, unsigned> partOf;
  for (unsigned node = 0; node < nodes.size(); ++node) {
    auto [it, fresh] = partOf.try_emplace(joined.getLeaderValue(node), static_cast<unsigned>(parts.size()));
    if (fresh)
      parts.emplace_back().position = nodes[node];
    Part &part = parts[it->second];
    part.nodes.push_back(node);
    part.names.push_back(at[nodes[node]]->getName());
    if (auto *function = dyn_cast<Function>(at[nodes[node]]))
      part.size += function->getInstructionCount();
  }
  Expected<std::vector<Cut>> named = cut(parts);
  if (!named)
    return named.takeError();
  // Every node is in one part and every part in one bin, so each node's
  // bin is written once.
  partition.members.resize(named->size());
  std::vector<unsigned> binOfNode(nodes.size());
  for (unsigned bin = 0; bin < named->size(); ++bin) {
    partition.binList.push_back((*named)[bin].bin);
    for (unsigned index : (*named)[bin].parts)
      for (unsigned node : parts[index].nodes) {
        binOfNode[node] = bin;
        partition.members[bin].push_back(nodes[node]);
      }
  }
  // Each symbol's home, derived once from its role: a node lives in its
  // bin, an alias in its base's, with that bin's own symbols, and an alias
  // of nothing a bin defines is declared only.
  for (unsigned symbol = 0; symbol < numSymbols; ++symbol) {
    std::optional<unsigned> base = baseOf(symbol);
    partition.symbols[symbol].home = idr::match(
        role[symbol], [](Partition::Declared) -> Home { return Partition::Declared{}; },
        [](Partition::Copied) -> Home { return Partition::Copied{}; },
        [&](Node node) -> Home { return Partition::Defined{binOfNode[node.index]}; },
        [&](Alias) -> Home {
          if (!base)
            return Partition::Declared{};
          partition.members[binOfNode[*base]].push_back(symbol);
          return Partition::Defined{binOfNode[*base]};
        });
  }

  // The linkage every bin reads: a local symbol another bin names, directly
  // or through a copy it holds, is defined once and named across objects.
  std::vector<bool> crosses(numSymbols, false);
  for (unsigned bin = 0; bin < partition.members.size(); ++bin)
    for (unsigned symbol : partition.members[bin])
      reach(symbol, [&](unsigned other) {
        idr::match(
            partition.symbols[other].home,
            [&](Partition::Defined home) {
              if (home.bin != bin && at[other]->hasLocalLinkage())
                crosses[other] = true;
            },
            [](const idr::OneOf<Partition::Declared, Partition::Copied> auto &) {});
      });
  for (unsigned symbol = 0; symbol < numSymbols; ++symbol) {
    if (!crosses[symbol])
      continue;
    GlobalValue *value = at[symbol];
    StringRef name = GlobalValue::dropLLVMManglingEscape(value->getName());
    if (name.empty())
      return internal("an unnamed symbol is read by two bins, and a symbol across objects needs a name");
    // A name of its own, reserved for a symbol two bins read: no mangled
    // name, no C name and no other reserved name is one (idr::reservedName),
    // and two distinct names give two.
    value->setName(idr::reservedName("bin", name));
    value->setLinkage(GlobalValue::ExternalLinkage);
    value->setVisibility(GlobalValue::HiddenVisibility);
    value->setDSOLocal(true);
  }
  return partition;
}
