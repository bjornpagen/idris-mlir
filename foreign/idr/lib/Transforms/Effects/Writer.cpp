// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one writer of rows: each function's own part read in parallel, the
// parts joined over the program graph's components callees first, and
// every function and call that changed written back in parallel. A write
// through a parameter is a node of one marking over every function's
// write-admitting parameters, a call that passes a parameter on to a
// written one its edge; the atoms are the summary solve's; the amounts one
// pass callees first, since a put passed along a cycle has no bound.

#include "idr/Transforms/Effects.h"

#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/Mark.h"
#include "idr/Analysis/Solver/SummarizeImpl.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"
#include "idr/Support/Match.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <cstdint>
#include <utility>
#include <vector>

using namespace mlir;
using namespace idr;
using namespace idr::rows;
using solver::FunctionId;

template IndexVector<FunctionId, effects::Row>
solver::summarize<CalleesFirst, AtomsProblem>(const solver::ProgramGraph &, const AtomsProblem &,
                                             mlir::MLIRContext &);

namespace {

//===----------------------------------------------------------------------===//
// Each body, read once
//===----------------------------------------------------------------------===//

// A lifetime a call passes on to its callee's put parameter `theirs`, and
// what it is of the caller's own record.
struct PassedOn {
  std::uint32_t theirs;
  RecordPart mine;
};

// A call as the writer reads it: its callee, where a write through each of
// its write-admitting operands lands for the caller, in order, and each
// lifetime it passes on to a put parameter.
struct Site {
  CallOp call;
  FunctionId callee;
  Runs runs;
  llvm::SmallVector<Lands, 2> writes;
  llvm::SmallVector<PassedOn, 1> puts;
};

// What one body does by itself, and its calls, read once.
struct Own {
  Derived derived;
  llvm::SmallVector<Site, 4> sites;
};

// The part each parameter of `fn` admits, by the callee's own signature:
// its index arguments change no grade and no lifetime's kind.
Site siteOf(CallOp call, FunctionId callee, FuncOp fn, const Fold &fold, Runs runs) {
  Site site{call, callee, runs, {}, {}};
  ParameterParts theirs(fn.getArgumentTypes());
  for (auto [index, operand] : llvm::enumerate(call.getArgs()))
    idr::match(
        theirs[static_cast<unsigned>(index)],
        [&](WritePart) { site.writes.push_back(fold.landing(operand)); },
        [&](PutPart part) { site.puts.push_back({part.position, fold.partOf(operand)}); },
        [](NoPart) {});
  return site;
}

// The writer's reader: a call is recorded, and its callee's row joined
// over the components, never read off the call, which may be stale.
struct Calls {
  const solver::ProgramGraph &graph;
  llvm::SmallVectorImpl<Site> &sites;

  void call(CallOp call, Fold &fold, Runs runs) {
    FunctionId callee = graph.id(call.getCalleeAttr());
    sites.push_back(siteOf(call, callee, graph.op(callee), fold, runs));
  }
  Read other(Operation *, Fold &, Runs) { return Read::ByDeclaration; }
};

//===----------------------------------------------------------------------===//
// Writes through parameters
//===----------------------------------------------------------------------===//

class WriteNodes;
struct WriteTag {
  using Minter = WriteNodes;
};
using WriteNode = Id<WriteTag>;

// The write-admitting parameters of a set of functions, one node each:
// function `owner`'s parameter at `position` among its write-admitting
// ones. Owners are numbered by whoever builds the nodes.
class WriteNodes {
public:
  explicit WriteNodes(std::span<const std::uint32_t> writable) {
    first.reserve(writable.size());
    for (std::uint32_t count : writable) {
      first.push_back(total);
      total += count;
    }
  }
  Count<WriteNode> count() const { return Count<WriteNode>(total); }
  WriteNode at(std::uint32_t owner, std::uint32_t position) const {
    return WriteNode(first[owner] + position);
  }

private:
  std::vector<std::uint32_t> first;
  std::uint32_t total = 0;
};

// One function of a set the marking reads: its number among the set, and
// what its body does by itself.
struct Owner {
  std::uint32_t ordinal;
  const Own *own;
};

// Every write-admitting parameter written through: each written by its own
// body, then each passed on to a written parameter of a callee, marked from
// callee to caller. `ordinalOf` numbers a site's callee among the owners.
template <class OrdinalOf>
BitSet<WriteNode> markWrites(const WriteNodes &nodes, llvm::ArrayRef<Owner> owners,
                             OrdinalOf &&ordinalOf) {
  CsrBuilder<WriteTag> edges(nodes.count());
  std::vector<WriteNode> seeds;
  for (const Owner &owner : owners) {
    for (unsigned position : owner.own->derived.written.set_bits())
      seeds.push_back(nodes.at(owner.ordinal, position));
    for (const Site &site : owner.own->sites)
      for (auto [k, lands] : llvm::enumerate(site.writes))
        idr::match(
            lands,
            [&](Through through) {
              edges.edge(nodes.at(ordinalOf(site.callee), static_cast<std::uint32_t>(k)),
                         nodes.at(owner.ordinal, through.position));
            },
            [](Local) {}, [](Elsewhere) {});
  }
  Csr<WriteTag> graph = std::move(edges).finish();
  return mark<Forward>(graph, std::span<const WriteNode>(seeds));
}

// A write through a callee's written parameter, passed something the
// caller neither acquired nor was given through a write-admitting
// parameter of its own, writes memory a caller of the caller may see.
template <class OrdinalOf>
effects::Row writesElsewhere(const llvm::SmallVectorImpl<Site> &sites, const WriteNodes &nodes,
                             const BitSet<WriteNode> &written, OrdinalOf &&ordinalOf) {
  effects::Row row;
  for (const Site &site : sites)
    for (auto [k, lands] : llvm::enumerate(site.writes))
      idr::match(
          lands,
          [&](Elsewhere) {
            if (written.test(nodes.at(ordinalOf(site.callee), static_cast<std::uint32_t>(k))))
              row = effects::Row{effects::Atom::write};
          },
          [](Local) {}, [](Through) {});
  return row;
}

// The positions a function never writes through, as its record lists them;
// none, as absence says.
DenseI32ArrayAttr untouchedOf(MLIRContext *context, std::uint32_t owner, std::uint32_t writable,
                              const WriteNodes &nodes, const BitSet<WriteNode> &written) {
  llvm::SmallVector<std::int32_t> untouched;
  for (std::uint32_t position = 0; position < writable; ++position)
    if (!written.test(nodes.at(owner, position)))
      untouched.push_back(static_cast<std::int32_t>(position));
  if (untouched.empty())
    return {};
  return DenseI32ArrayAttr::get(context, untouched);
}

// The bounded amounts of a function's put parameters, as its record lists
// them; none, as absence says.
PutBoundsAttr boundsOf(MLIRContext *context, llvm::ArrayRef<Amount> puts) {
  llvm::SmallVector<PutBound> bounds;
  for (auto [position, amount] : llvm::enumerate(puts))
    amount.fold(
        [&](std::uint64_t bytes) {
          bounds.push_back({static_cast<std::uint32_t>(position), bytes});
        },
        [] {});
  if (bounds.empty())
    return {};
  return PutBoundsAttr::get(context, bounds);
}

// What a site passes on into the caller's put parameters: the callee's
// amount, or no bound where the callee lies on the caller's cycle or the
// call in a region that runs again.
template <class TheirsOf>
void passOn(llvm::MutableArrayRef<Amount> mine, const Site &site, TheirsOf &&theirsOf) {
  for (const PassedOn &passed : site.puts)
    idr::match(
        passed.mine,
        [&](PutPart part) {
          Amount theirs = theirsOf(passed.theirs);
          if (!theirs.none() && site.runs == Runs::Repeatedly)
            theirs = Amount::unbounded();
          mine[part.position] = mine[part.position].plus(theirs);
        },
        [](WritePart) {}, [](NoPart) {});
}

// Whether every function of a cycle was proved by Idris in one and the same
// component of its own, the one way a cycle of ours is known to end.
template <class Members>
bool provedTogether(Members &&members) {
  FuncOp first = *std::begin(members);
  return idr::match(
      first.getTermination(), [](Unproved) { return false; }, [](Acyclic) { return false; },
      [&](InComponent in) {
        return llvm::all_of(members, [&](FuncOp fn) {
          return fn.getTermination() == Termination{in};
        });
      });
}

} // namespace

//===----------------------------------------------------------------------===//
// The program
//===----------------------------------------------------------------------===//

void rows::detail::addCycles(const solver::ProgramGraph &graph,
                             IndexVector<FunctionId, effects::Row> &own) {
  for (solver::SccId component : graph.sccCount().ids()) {
    IdRange<FunctionId> members = graph.members(component);
    if (members.size() == 1 && !graph.callsItself(members.front()))
      continue;
    if (provedTogether(llvm::map_range(members, [&](FunctionId f) { return graph.op(f); })))
      continue;
    for (FunctionId f : members)
      own[f] = own[f] | effects::Row{effects::Atom::divergence};
  }
}

void rows::write(ProgramOp program, const solver::ProgramGraph &graph) {
  MLIRContext *context = program.getContext();
  IdRange<FunctionId> functions = graph.functions();

  // Each body by itself, in parallel, each into its own slot.
  IndexVector<FunctionId, Own> own = graph.table(Own{});
  parallelFor(context, 0, functions.size(), [&](std::size_t at) {
    FunctionId f = functions[at];
    Calls reader{graph, own[f].sites};
    own[f].derived = derive(graph.op(f), reader);
  });

  // Writes through parameters, marked from callee to caller; then the
  // write each makes elsewhere joins its caller's own atoms. A function's
  // number is its id's: a gap has no parameter.
  std::vector<std::uint32_t> writable(graph.size().value(), 0);
  std::vector<Owner> owners;
  for (FunctionId f : functions) {
    writable[f.index()] = static_cast<std::uint32_t>(own[f].derived.written.size());
    owners.push_back({f.index(), &own[f]});
  }
  WriteNodes nodes(writable);
  auto ordinalOf = [](FunctionId callee) { return callee.index(); };
  BitSet<WriteNode> written = markWrites(nodes, owners, ordinalOf);

  // The atoms: each function's own, the writes it makes elsewhere through
  // its callees, its cycle's divergence; joined callees first.
  AtomsProblem atoms{graph.table(effects::Row{})};
  for (FunctionId f : functions)
    atoms.own[f] = own[f].derived.atoms | writesElsewhere(own[f].sites, nodes, written, ordinalOf);
  detail::addCycles(graph, atoms.own);
  IndexVector<FunctionId, effects::Row> joined =
      solver::summarize<CalleesFirst>(graph, atoms, *context);

  // The amounts, callees first: a callee in another component is final
  // when its caller is read, and one in the caller's own component lies on
  // a cycle with it, so what it puts has no bound.
  IndexVector<FunctionId, llvm::SmallVector<Amount, 2>> puts =
      graph.table(llvm::SmallVector<Amount, 2>{});
  for (FunctionId f : graph.bottomUp()) {
    puts[f] = own[f].derived.puts;
    for (const Site &site : own[f].sites)
      passOn(puts[f], site, [&](std::uint32_t theirs) {
        return graph.sccOf(site.callee) == graph.sccOf(f) ? Amount::unbounded()
                                                          : puts[site.callee][theirs];
      });
  }

  // Every record's attributes, made here, serially, so no worker makes one.
  IndexVector<FunctionId, DenseI32ArrayAttr> untouched = graph.table(DenseI32ArrayAttr{});
  IndexVector<FunctionId, PutBoundsAttr> bounded = graph.table(PutBoundsAttr{});
  for (FunctionId f : functions) {
    untouched[f] = untouchedOf(context, f.index(), writable[f.index()], nodes, written);
    bounded[f] = boundsOf(context, puts[f]);
  }

  // Each function and its calls, in parallel: a worker writes its own
  // function's ops alone, reading the tables.
  parallelFor(context, 0, functions.size(), [&](std::size_t at) {
    FunctionId f = functions[at];
    FuncOp fn = graph.op(f);
    if (fn.getRow() != joined[f])
      fn.setRow(joined[f]);
    fn.setUntouchedAttr(untouched[f]);
    fn.setBoundedAttr(bounded[f]);
    for (const Site &site : own[f].sites) {
      if (site.call.getRow() != joined[site.callee])
        site.call.setRow(joined[site.callee]);
      site.call.setUntouchedAttr(untouched[site.callee]);
    }
  });
}

//===----------------------------------------------------------------------===//
// Widening
//===----------------------------------------------------------------------===//

void rows::widen(ProgramOp program, effects::Row atoms) {
  llvm::SmallVector<FuncOp> functions(program.getOps<FuncOp>());
  parallelForEach(program.getContext(), functions, [&](FuncOp fn) {
    fn.setRow(fn.getRow() | atoms);
    fn.setUntouchedAttr({});
    fn.walk([&](CallOp call) {
      call.setRow(call.getRow() | atoms);
      call.setUntouchedAttr({});
    });
  });
}

//===----------------------------------------------------------------------===//
// One of the optimizer's components
//===----------------------------------------------------------------------===//

namespace {

// The optimizer's reader for one component: a call of a member is
// recorded, joined over the component; a call of a final callee holds the
// callee's row already, which it gives. What a final callee puts into a
// lifetime is not on its call, so a put parameter passed on to one has no
// bound: lifetimes are decided after the optimizer, so none is passed yet.
template <class N>
struct ComponentCalls {
  const N &names;
  llvm::ArrayRef<std::pair<FunctionId, unsigned>> byId;
  std::span<const solver::Member> members;
  llvm::SmallVectorImpl<Site> &sites;

  // The member a callee is, if it is one.
  const solver::Member *memberOf(FunctionId callee) const {
    auto at = llvm::lower_bound(byId, callee, [](const std::pair<FunctionId, unsigned> &entry,
                                                 FunctionId id) { return entry.first < id; });
    if (at == byId.end() || at->first != callee)
      return nullptr;
    return &members[at->second];
  }

  void call(CallOp call, Fold &fold, Runs runs) {
    FunctionId callee = names.id(call.getCalleeAttr());
    if (const solver::Member *member = memberOf(callee)) {
      sites.push_back(siteOf(call, callee, member->fn, fold, runs));
      return;
    }
    CallCopies copies;
    copies.call(call, fold, runs);
    for (Value operand : call.getArgs())
      if (admitsPuts(operand.getType()))
        fold.put(operand, Amount::unbounded(), runs);
  }
  Read other(Operation *, Fold &, Runs) { return Read::ByDeclaration; }
};

} // namespace

template <solver::FunctionNames N>
void rows::writeComponent(std::span<const solver::Member> members, const N &names) {
  MLIRContext *context = members.front().fn.getContext();
  llvm::SmallVector<std::pair<FunctionId, unsigned>> byId;
  for (auto [index, member] : llvm::enumerate(members))
    byId.push_back({member.id, static_cast<unsigned>(index)});
  llvm::sort(byId, [](const auto &a, const auto &b) { return a.first < b.first; });
  auto ordinalOf = [&](FunctionId callee) {
    return llvm::lower_bound(byId, callee,
                             [](const std::pair<FunctionId, unsigned> &entry, FunctionId id) {
                               return entry.first < id;
                             })
        ->second;
  };

  // Each member by itself.
  llvm::SmallVector<Own> own(members.size());
  for (auto [index, member] : llvm::enumerate(members)) {
    ComponentCalls<N> reader{names, byId, members, own[index].sites};
    own[index].derived = derive(member.fn, reader);
  }

  // Writes through parameters, within the component: a final callee's are
  // on its calls, read by the fold already.
  std::vector<std::uint32_t> writable;
  std::vector<Owner> owners;
  for (auto [index, mine] : llvm::enumerate(own)) {
    writable.push_back(static_cast<std::uint32_t>(mine.derived.written.size()));
    owners.push_back({static_cast<std::uint32_t>(index), &mine});
  }
  WriteNodes nodes(writable);
  BitSet<WriteNode> written = markWrites(nodes, owners, ordinalOf);

  // One row for every member: what each does and what each writes
  // elsewhere through another, and the cycle's divergence.
  effects::Row row;
  for (const Own &mine : own)
    row = row | mine.derived.atoms | writesElsewhere(mine.sites, nodes, written, ordinalOf);
  auto callsItself = [&](auto entry) {
    auto [index, member] = entry;
    return llvm::any_of(own[index].sites, [&](const Site &site) { return site.callee == member.id; });
  };
  if ((members.size() > 1 || llvm::any_of(llvm::enumerate(members), callsItself)) &&
      !provedTogether(llvm::map_range(members, [](const solver::Member &m) { return m.fn; })))
    row = row | effects::Row{effects::Atom::divergence};

  // The members' amounts: a put passed on to a member lies on the cycle.
  llvm::SmallVector<DenseI32ArrayAttr> untouched;
  llvm::SmallVector<PutBoundsAttr> bounded;
  for (auto [index, mine] : llvm::enumerate(own)) {
    llvm::SmallVector<Amount, 2> puts = mine.derived.puts;
    for (const Site &site : mine.sites)
      passOn(puts, site, [](std::uint32_t) { return Amount::unbounded(); });
    auto owner = static_cast<std::uint32_t>(index);
    untouched.push_back(untouchedOf(context, owner, writable[owner], nodes, written));
    bounded.push_back(boundsOf(context, puts));
  }

  for (auto [index, member] : llvm::enumerate(members)) {
    member.fn.setRow(row);
    member.fn.setUntouchedAttr(untouched[index]);
    member.fn.setBoundedAttr(bounded[index]);
    for (const Site &site : own[index].sites) {
      site.call.setRow(row);
      site.call.setUntouchedAttr(untouched[ordinalOf(site.callee)]);
    }
  }
}

template void rows::writeComponent<solver::ProgramGraph>(std::span<const solver::Member>,
                                                         const solver::ProgramGraph &);
template void rows::writeComponent<solver::Editor>(std::span<const solver::Member>,
                                                   const solver::Editor &);
