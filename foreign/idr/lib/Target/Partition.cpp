// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The partition of the optimized program into the bins whose code is
// generated at once, and the linkage the bins then read; reading one bin
// back out of the bitcode is Extract.cpp's. After O3 code generation is local to each function, so
// a bin holds whole components of the reference graph, each with the callee
// of its musttail calls (no tail call crosses an object), its comdat and an
// ifunc's resolver, grouped by the top-level namespace their names keep and
// cut by their hash, so a cut depends only on its neighbours. A constant
// whose address nothing tells apart is copied into each bin that reads it.

#include "idr/Target/Target.h"

#include "idr/IR/Symbols.h"
#include "idr/Support/Scc.h"
#include "idr/Support/Worklist.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/EquivalenceClasses.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/Twine.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalAlias.h"
#include "llvm/IR/GlobalIFunc.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/xxhash.h"

#include <bit>
#include <cstdint>
#include <numeric>
#include <optional>
#include <string>
#include <tuple>
#include <utility>
#include <variant>
#include <vector>

using namespace llvm;
using idr::target::Bin;
using idr::target::Partition;
using idr::target::binInstructions;

namespace {

// A part closes its bin when its hash, read as a fraction of 2^64, is below
// its share of the target: hash / (2^64 / target) < size says exactly that
// when the target is a power of two.
static_assert(std::has_single_bit(binInstructions));
constexpr std::uint64_t hashPerInstruction = ~std::uint64_t{0} / binInstructions + 1;

// An error of the partition's, which its caller reports as the compiler's.
Error internal(const Twine &what) { return createStringError(what); }

// What a function's body and operands (personality, prefix, prologue), a
// variable's initializer, an alias's aliasee or an ifunc's resolver names,
// through every constant expression and aggregate it holds. Each constant
// enters once.
SmallVector<const GlobalValue *> referencesOf(const GlobalValue &value) {
  idr::OnceWorklist<const Constant *> constants;
  auto collect = [&](const Value *operand) {
    if (auto *constant = dyn_cast<Constant>(operand))
      constants.push(constant);
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
  while (std::optional<const Constant *> constant = constants.pop()) {
    if (auto *global = dyn_cast<GlobalValue>(*constant)) {
      found.push_back(global);
      continue;
    }
    for (const Use &operand : (*constant)->operands())
      collect(operand.get());
  }
  return found;
}

// The top-level namespace a name keeps: what precedes its first dot, and
// one group, the empty one, for every name without a dot.
StringRef namespaceOf(StringRef name) {
  StringRef plain = GlobalValue::dropLLVMManglingEscape(name);
  return plain.contains('.') ? plain.take_front(plain.find('.')) : StringRef();
}

// The hash of a set of names, sorted, one per line: XXH3's 64 bits, which
// decide a part's cut and, spelled in hex, name a bin.
std::uint64_t hashOf(std::vector<StringRef> &names) {
  sort(names);
  return xxh3_64bits(arrayRefFromStringRef(join(names, "\n")));
}

// A bin's name: its hash in 16 lower-case hex digits, so that name order is
// hash order.
std::string nameOf(std::uint64_t hash) {
  std::string name;
  raw_string_ostream(name) << format_hex_no_prefix(hash, 16, /*Upper=*/false);
  return name;
}

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

// The components that stay together, and what the cut reads of them.
struct Part {
  SmallVector<unsigned> nodes;
  std::vector<StringRef> names;
  std::uint64_t size = 0, hash = 0;
  unsigned position = 0;
  StringRef group() const { return namespaceOf(names.front()); }
  auto order() const { return std::tuple(group(), hash, names.front(), position); }
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
  DenseMap<const GlobalValue *, unsigned> place;
  for (unsigned symbol = 0; symbol < at.size(); ++symbol)
    place[at[symbol]] = symbol;
  DenseSet<const GlobalObject *> aliased;
  for (GlobalAlias &alias : module.aliases())
    aliased.insert(alias.getAliaseeObject());

  // Roles: an available_externally body is the runtime's native half's,
  // which no bin defines, and none survives O3. Each symbol's role is
  // written once, here.
  Partition partition;
  partition.symbols.resize(at.size());
  using SymbolRole = std::variant<Partition::Declared, Partition::Copied, Node, Alias>;
  std::vector<SymbolRole> role(at.size(), Partition::Declared{});
  std::vector<unsigned> nodes;
  for (unsigned symbol = 0; symbol < at.size(); ++symbol) {
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
        !aliased.contains(variable)) {
      role[symbol] = Partition::Copied{};
      continue;
    }
    role[symbol] = Node{static_cast<unsigned>(nodes.size())};
    nodes.push_back(symbol);
  }
  // The node a symbol is, or an alias stands for; none for any other.
  auto baseOf = [&](unsigned symbol) -> std::optional<unsigned> {
    return std::visit(makeVisitor([](Node node) -> std::optional<unsigned> { return node.index; },
                                  [&](Alias alias) -> std::optional<unsigned> {
                                    if (!alias.base)
                                      return std::nullopt;
                                    if (const auto *node = std::get_if<Node>(&role[*alias.base]))
                                      return node->index;
                                    return std::nullopt;
                                  },
                                  [](const auto &) -> std::optional<unsigned> {
                                    return std::nullopt;
                                  }),
                      role[symbol]);
  };
  // Each symbol `from` names, a copied constant standing for what it names.
  // Each symbol enters once.
  auto reach = [&](unsigned from, function_ref<void(unsigned)> visit) {
    idr::OnceWorklist<unsigned> work;
    for (unsigned named : partition.symbols[from].refs)
      work.push(named);
    while (std::optional<unsigned> named = work.pop())
      std::visit(makeVisitor(
                     [&](Partition::Copied) {
                       for (unsigned next : partition.symbols[*named].refs)
                         work.push(next);
                     },
                     [&](const auto &) { visit(*named); }),
                 role[*named]);
  };

  // Components of the reference graph, then joined.
  SmallVector<SmallVector<unsigned>> successors(nodes.size());
  for (unsigned node = 0; node < nodes.size(); ++node)
    reach(nodes[node], [&](unsigned named) {
      if (std::optional<unsigned> base = baseOf(named))
        successors[node].push_back(*base);
    });
  EquivalenceClasses<unsigned> joined;
  for (unsigned node = 0; node < nodes.size(); ++node)
    joined.insert(node);
  for (const SmallVector<unsigned> &component : idr::components(successors))
    for (unsigned node : component)
      joined.unionSets(component.front(), node);
  auto join = [&](unsigned node, std::optional<unsigned> other) {
    if (other)
      joined.unionSets(node, *other);
  };
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
  for (Part &part : parts)
    part.hash = hashOf(part.names);
  std::vector<unsigned> order(parts.size());
  std::iota(order.begin(), order.end(), 0u);
  sort(order, [&](unsigned a, unsigned b) { return parts[a].order() < parts[b].order(); });

  // The cut: before a part, the open bin closes when the part would take it
  // past twice the target or is of another group; after it, when the bin
  // holds a quarter of the target and the part's hash says so.
  std::vector<SmallVector<unsigned>> cut;
  SmallVector<unsigned> open;
  std::uint64_t held = 0;
  auto close = [&] {
    cut.push_back(std::exchange(open, {}));
    held = 0;
  };
  for (unsigned index : order) {
    const Part &part = parts[index];
    if (!open.empty() && (parts[open.front()].group() != part.group() ||
                          held + part.size > 2 * binInstructions))
      close();
    open.push_back(index);
    held += part.size;
    if (held >= binInstructions / 4 && part.hash / hashPerInstruction < part.size)
      close();
  }
  if (!open.empty())
    close();

  // Bins named by the hash of their names, kept in name order.
  std::vector<std::pair<Bin, SmallVector<unsigned>>> named;
  for (SmallVector<unsigned> &chosen : cut) {
    Bin bin;
    std::vector<StringRef> names;
    for (unsigned index : chosen) {
      bin.instructions += parts[index].size;
      append_range(names, parts[index].names);
    }
    bin.name = nameOf(hashOf(names));
    named.emplace_back(std::move(bin), std::move(chosen));
  }
  sort(named, [](const auto &a, const auto &b) { return a.first.name < b.first.name; });
  for (unsigned index = 0; index + 1 < named.size(); ++index)
    if (named[index].first.name == named[index + 1].first.name)
      return internal("two bins are named " + named[index].first.name);
  // Every node is in one part and every part in one bin, so each node's
  // bin is written once.
  partition.members.resize(named.size());
  std::vector<unsigned> binOfNode(nodes.size());
  for (unsigned bin = 0; bin < named.size(); ++bin) {
    partition.binList.push_back(named[bin].first);
    for (unsigned index : named[bin].second)
      for (unsigned node : parts[index].nodes) {
        binOfNode[node] = bin;
        partition.members[bin].push_back(nodes[node]);
      }
  }
  // Each symbol's home, derived once from its role: a node lives in its
  // bin, an alias in its base's, with that bin's own symbols, and an alias
  // of nothing a bin defines is declared only.
  for (unsigned symbol = 0; symbol < at.size(); ++symbol) {
    std::optional<unsigned> base = baseOf(symbol);
    partition.symbols[symbol].home = std::visit(
        makeVisitor([](Partition::Declared) -> Home { return Partition::Declared{}; },
                    [](Partition::Copied) -> Home { return Partition::Copied{}; },
                    [&](Node node) -> Home { return Partition::Defined{binOfNode[node.index]}; },
                    [&](Alias) -> Home {
                      if (!base)
                        return Partition::Declared{};
                      partition.members[binOfNode[*base]].push_back(symbol);
                      return Partition::Defined{binOfNode[*base]};
                    }),
        role[symbol]);
  }

  // The linkage every bin reads: a local symbol another bin names, directly
  // or through a copy it holds, is defined once and named across objects.
  std::vector<bool> crosses(at.size(), false);
  for (unsigned bin = 0; bin < partition.members.size(); ++bin)
    for (unsigned symbol : partition.members[bin])
      reach(symbol, [&](unsigned other) {
        const auto *home = std::get_if<Partition::Defined>(&partition.symbols[other].home);
        crosses[other] =
            crosses[other] || (home && home->bin != bin && at[other]->hasLocalLinkage());
      });
  for (unsigned symbol = 0; symbol < at.size(); ++symbol) {
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
