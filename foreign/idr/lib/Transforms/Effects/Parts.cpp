// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the writers of rows read of each body and how its parts join, for
// the program's writer and a component's alike: a call read as a site; a
// write through a parameter as a node of one marking over every owner's
// write-admitting parameters, a call that passes a parameter on to a
// written one its edge, marked from callee to caller; the write a callee
// makes elsewhere for its caller; and the record's attributes, made by the
// writer serially so no worker makes one.

#include "idr/Transforms/Effects.h"

#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/Mark.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <span>
#include <utility>

using namespace mlir;
using namespace idr;
using namespace idr::rows;
using namespace idr::rows::writer;
using solver::FunctionId;

Site idr::rows::writer::siteOf(CallOp call, FunctionId callee, std::uint32_t ordinal, FuncOp fn,
                               const Fold &fold, Runs runs) {
  Site site{call, callee, ordinal, runs, {}, {}};
  ParameterParts theirs(fn.getArgumentTypes());
  for (auto [index, operand] : llvm::enumerate(call.getArgs()))
    idr::match(
        theirs[static_cast<unsigned>(index)],
        [&](WritePart) { site.writes.push_back(fold.landing(operand)); },
        [&](PutPart part) { site.puts.push_back({part.position, fold.partOf(operand)}); },
        [](NoPart) {});
  return site;
}

BitSet<WriteNode> idr::rows::writer::markWrites(const WriteNodes &nodes,
                                                llvm::ArrayRef<Owner> owners) {
  CsrBuilder<WriteTag> edges(nodes.count());
  footprint::Vector<WriteNode> seeds;
  for (const Owner &owner : owners) {
    for (unsigned position : owner.own->derived.written.set_bits())
      seeds.push_back(nodes.at(owner.ordinal, position));
    for (const Site &site : owner.own->sites)
      for (auto [k, lands] : llvm::enumerate(site.writes))
        idr::match(
            lands,
            [&](Through through) {
              edges.edge(nodes.at(site.ordinal, static_cast<std::uint32_t>(k)),
                         nodes.at(owner.ordinal, through.position));
            },
            [](Local) {}, [](Elsewhere) {});
  }
  Csr<WriteTag> graph = std::move(edges).finish();
  return mark<Forward>(graph, std::span<const WriteNode>(seeds));
}

effects::Row idr::rows::writer::writesElsewhere(llvm::ArrayRef<Site> sites,
                                                const WriteNodes &nodes,
                                                const BitSet<WriteNode> &written) {
  effects::Row row;
  for (const Site &site : sites)
    for (auto [k, lands] : llvm::enumerate(site.writes))
      idr::match(
          lands,
          [&](Elsewhere) {
            if (written.test(nodes.at(site.ordinal, static_cast<std::uint32_t>(k))))
              row = effects::Row{effects::Atom::write};
          },
          [](Local) {}, [](Through) {});
  return row;
}

DenseI32ArrayAttr idr::rows::writer::untouchedOf(MLIRContext *context, std::uint32_t owner,
                                                 std::uint32_t writable, const WriteNodes &nodes,
                                                 const BitSet<WriteNode> &written) {
  llvm::SmallVector<std::int32_t> untouched;
  for (std::uint32_t position = 0; position < writable; ++position)
    if (!written.test(nodes.at(owner, position)))
      untouched.push_back(static_cast<std::int32_t>(position));
  if (untouched.empty())
    return {};
  return DenseI32ArrayAttr::get(context, untouched);
}

PutBoundsAttr idr::rows::writer::boundsOf(MLIRContext *context, llvm::ArrayRef<Amount> puts) {
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
