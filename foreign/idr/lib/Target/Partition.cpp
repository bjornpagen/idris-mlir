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

#include "idr/Support/Scc.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/EquivalenceClasses.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
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
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace llvm;
using idr::target::Bin;
using idr::target::Partition;
using idr::target::binInstructions;

namespace {

// The prefix no C name has, under which a symbol another bin reads is named.
constexpr StringLiteral reservedPrefix = "__idr.";

// A part closes its bin when its hash, read as a fraction of 2^64, is below
// its share of the target: hash / (2^64 / target) < size says exactly that
// when the target is a power of two.
static_assert(std::has_single_bit(binInstructions));
constexpr std::uint64_t hashPerInstruction = ~std::uint64_t{0} / binInstructions + 1;

Error internal(const Twine &what) { return createStringError("internal error: " + what); }

// The global values `value` names, through every constant expression and
// aggregate it holds.
void collect(const Value *value, SmallPtrSetImpl<const Constant *> &seen,
             SmallVectorImpl<const GlobalValue *> &found) {
  auto *constant = dyn_cast<Constant>(value);
  if (!constant || !seen.insert(constant).second)
    return;
  if (auto *global = dyn_cast<GlobalValue>(constant))
    return found.push_back(global);
  for (const Use &operand : constant->operands())
    collect(operand.get(), seen, found);
}

// What a function's body and operands (personality, prefix, prologue), a
// variable's initializer, an alias's aliasee or an ifunc's resolver names.
SmallVector<const GlobalValue *> referencesOf(const GlobalValue &value) {
  SmallPtrSet<const Constant *, 16> seen;
  SmallVector<const GlobalValue *> found;
  if (auto *function = dyn_cast<Function>(&value)) {
    for (const Use &operand : function->operands())
      collect(operand.get(), seen, found);
    for (const Instruction &instruction : instructions(*function))
      for (const Use &operand : instruction.operands())
        collect(operand.get(), seen, found);
  } else if (auto *variable = dyn_cast<GlobalVariable>(&value); variable && variable->hasInitializer()) {
    collect(variable->getInitializer(), seen, found);
  } else if (auto *alias = dyn_cast<GlobalAlias>(&value)) {
    collect(alias->getAliasee(), seen, found);
  } else if (auto *ifunc = dyn_cast<GlobalIFunc>(&value)) {
    collect(ifunc->getResolver(), seen, found);
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

enum class Kind : unsigned char { Declared, Node, Copied, Alias };

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

  // Kinds: an available_externally body is the runtime's native half's,
  // which no bin defines, and none survives O3.
  Partition partition;
  partition.symbols.resize(at.size());
  std::vector<Kind> kind(at.size(), Kind::Declared);
  std::vector<int> nodeOf(at.size(), -1);
  std::vector<unsigned> nodes;
  for (unsigned symbol = 0; symbol < at.size(); ++symbol) {
    GlobalValue *value = at[symbol];
    for (const GlobalValue *named : referencesOf(*value))
      partition.symbols[symbol].refs.push_back(place.lookup(named));
    if (value->isDeclaration() || value->hasAvailableExternallyLinkage())
      continue;
    auto *variable = dyn_cast<GlobalVariable>(value);
    bool copied = variable && variable->isConstant() && variable->hasLocalLinkage() &&
                  variable->hasAtLeastLocalUnnamedAddr() && !variable->hasComdat() &&
                  !aliased.contains(variable);
    kind[symbol] = isa<GlobalAlias>(value) ? Kind::Alias : copied ? Kind::Copied : Kind::Node;
    partition.symbols[symbol].copied = copied;
    if (kind[symbol] == Kind::Node) {
      nodeOf[symbol] = static_cast<int>(nodes.size());
      nodes.push_back(symbol);
    }
  }
  // The node a symbol is or an alias stands for, or none.
  auto baseOf = [&](unsigned symbol) {
    if (kind[symbol] != Kind::Alias)
      return nodeOf[symbol];
    const GlobalObject *base = cast<GlobalAlias>(at[symbol])->getAliaseeObject();
    return base ? nodeOf[place.lookup(base)] : -1;
  };
  // Each symbol `from` names, a copied constant standing for what it names.
  auto reach = [&](unsigned from, function_ref<void(unsigned)> visit) {
    SmallVector<unsigned> work = to_vector(partition.symbols[from].refs);
    DenseSet<unsigned> seen;
    while (!work.empty())
      if (unsigned named = work.pop_back_val(); seen.insert(named).second) {
        if (kind[named] == Kind::Copied)
          append_range(work, partition.symbols[named].refs);
        else
          visit(named);
      }
  };

  // Components of the reference graph, then joined.
  SmallVector<SmallVector<unsigned>> successors(nodes.size());
  for (unsigned node = 0; node < nodes.size(); ++node)
    reach(nodes[node], [&](unsigned named) {
      if (int base = baseOf(named); base >= 0)
        successors[node].push_back(static_cast<unsigned>(base));
    });
  EquivalenceClasses<unsigned> joined;
  for (unsigned node = 0; node < nodes.size(); ++node)
    joined.insert(node);
  for (const SmallVector<unsigned> &component : idr::components(successors))
    for (unsigned node : component)
      joined.unionSets(component.front(), node);
  auto join = [&](unsigned node, int other) {
    if (other >= 0)
      joined.unionSets(node, static_cast<unsigned>(other));
  };
  DenseMap<const Comdat *, unsigned> comdatNode;
  for (unsigned node = 0; node < nodes.size(); ++node) {
    auto *object = cast<GlobalObject>(at[nodes[node]]);
    if (const Comdat *comdat = object->getComdat())
      join(node, static_cast<int>(comdatNode.try_emplace(comdat, node).first->second));
    if (auto *ifunc = dyn_cast<GlobalIFunc>(object); ifunc && ifunc->getResolverFunction())
      join(node, nodeOf[place.lookup(ifunc->getResolverFunction())]);
    if (auto *function = dyn_cast<Function>(object))
      for (const Instruction &instruction : instructions(*function))
        if (auto *call = dyn_cast<CallInst>(&instruction); call && call->isMustTailCall())
          if (const Function *callee = call->getCalledFunction())
            join(node, nodeOf[place.lookup(callee)]);
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
  partition.members.resize(named.size());
  for (unsigned bin = 0; bin < named.size(); ++bin) {
    partition.binList.push_back(named[bin].first);
    for (unsigned index : named[bin].second)
      for (unsigned node : parts[index].nodes) {
        partition.symbols[nodes[node]].bin = static_cast<int>(bin);
        partition.members[bin].push_back(nodes[node]);
      }
  }
  for (unsigned symbol = 0; symbol < at.size(); ++symbol)
    if (int base = baseOf(symbol); kind[symbol] == Kind::Alias && base >= 0) {
      int bin = partition.symbols[nodes[static_cast<unsigned>(base)]].bin;
      partition.symbols[symbol].bin = bin;
      partition.members[static_cast<unsigned>(bin)].push_back(symbol);
    }

  // The linkage every bin reads: a local symbol another bin names, directly
  // or through a copy it holds, is defined once and named across objects.
  std::vector<bool> crosses(at.size(), false);
  for (unsigned bin = 0; bin < partition.members.size(); ++bin)
    for (unsigned symbol : partition.members[bin])
      reach(symbol, [&](unsigned other) {
        int home = partition.symbols[other].bin;
        crosses[other] = crosses[other] || (home >= 0 && home != static_cast<int>(bin) &&
                                            at[other]->hasLocalLinkage());
      });
  for (unsigned symbol = 0; symbol < at.size(); ++symbol) {
    if (!crosses[symbol])
      continue;
    GlobalValue *value = at[symbol];
    StringRef name = GlobalValue::dropLLVMManglingEscape(value->getName());
    if (name.empty())
      return internal("an unnamed symbol is read by two bins, and a symbol across objects needs a name");
    std::string wanted = name.starts_with(reservedPrefix) ? name.str() : (reservedPrefix + name).str();
    if (wanted != value->getName()) {
      if (module.getNamedValue(wanted))
        return internal("the reserved name " + wanted + " of " + value->getName() + " is taken");
      value->setName(wanted);
    }
    value->setLinkage(GlobalValue::ExternalLinkage);
    value->setVisibility(GlobalValue::HiddenVisibility);
    value->setDSOLocal(true);
  }
  return partition;
}
