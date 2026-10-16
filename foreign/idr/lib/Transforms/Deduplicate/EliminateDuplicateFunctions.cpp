// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions:
// https://llvm.org/LICENSE.txt
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//
// Modified by Bjorn Pagen, 2026, from Modular's 9211931: on idr.func in an idr.program, ordered by its functions' symbol uses through llvm::scc_iterator and run on MLIR's thread pool for KGEN's call graph and AsyncRT, classes compared by idr::deduplicate through the renames found below them, and every rename made by one DataRemap.
// PIN(eliminate-duplicate-functions)
//
// idr-deduplicate: of each class of idr.funcs that are one function twice
// over, the lexicographically smallest stays, every use of the others
// names it, and the others are erased.
//
// Monomorphisation writes one function per instantiation, and what Idris
// erased is gone from some of them alike, so a stage0 program holds
// thousands of second copies, each work for every later pass. Classes are
// found bottom-up over the functions' references, every symbol use a body
// holds: a call's callee, and before defunctionalization a closure's or a
// suspension's label, which no call graph sees. When two callers are
// compared, their callees' classes are known, and each is read through
// them: callers that differ only in which copy they name become one class
// in the same run, and a second run finds nothing.
//
// Every function is a candidate but a member of a cycle of two or more
// functions: one renamed into another would rewrite the recursion between
// them into a recursion the comparison did not prove. Every use of a
// merged function is renamed, wherever it is: in a body, as the program's
// root, or as a label's function in a data type's body, which a body being
// set once means a new data type (DataRemap). The round's renames are one
// remap.
//
// The references' components are processed by height, so a class, whose
// members always share a height, is whole before any function above it is
// read through it. Within one height the hashing runs in parallel and the
// classes are formed serially in program order; the kept name is a
// function of the class alone, so the output is the same at any thread
// count.

#include "idr/Transforms/Deduplicate.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Actions.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/Location.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

#include <algorithm>
#include <unordered_map>
#include <vector>

namespace idr {
#define GEN_PASS_DEF_IDRDEDUPLICATE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// idr-deduplicate merges one class of identical functions into its first;
// the unit is the function kept. The action is the decision: a class it
// skips names no rename, so every function above it reads its members as
// they are named, and no member goes.
struct DeduplicateMergeAction : idr::support::TaggedAction<DeduplicateMergeAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-deduplicate-merge";
};

struct EliminateDuplicateFunctionsPass
    : idr::impl::IdrDeduplicateBase<EliminateDuplicateFunctionsPass> {
  void runOnOperation() override;
};

void EliminateDuplicateFunctionsPass::runOnOperation() {
  idr::ProgramOp program = getOperation();
  MLIRContext *context = &getContext();
  SmallVector<idr::FuncOp> fns(program.getOps<idr::FuncOp>());
  llvm::DenseMap<StringAttr, unsigned> index;
  for (auto [at, fn] : llvm::enumerate(fns))
    index.try_emplace(fn.getSymNameAttr(), static_cast<unsigned>(at));

  // What each function's body names, each once, in the order upstream's
  // walk of its symbol uses meets them; none for a body whose uses that
  // walk cannot see (an op that may be a symbol table it does not know),
  // which could not be renamed either.
  std::vector<std::optional<SmallVector<unsigned>>> named(fns.size());
  parallelFor(context, 0, fns.size(), [&](size_t at) {
    std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&fns[at].getBody());
    if (!uses)
      return;
    llvm::SetVector<unsigned> each;
    for (SymbolTable::SymbolUse use : *uses)
      if (auto found = index.find(use.getSymbolRef().getRootReference());
          found != index.end() && found->second != at)
        each.insert(found->second);
    named[at] = each.takeVector();
  });
  SmallVector<SmallVector<unsigned>> names;
  for (auto [fn, each] : llvm::zip_equal(fns, named)) {
    if (!each) {
      fn.emitError("internal error: idr-deduplicate: an op that may be a symbol table hides "
                   "this function's symbol uses");
      return signalPassFailure();
    }
    names.push_back(std::move(*each));
  }

  // Each function's height over the components, callees first. The
  // candidates of each height are the functions on no cycle of two or
  // more, in program order.
  SmallVector<unsigned> componentOf(fns.size()), height(fns.size());
  SmallVector<SmallVector<unsigned>> components = idr::components(names);
  unsigned tallest = 0;
  for (auto [c, members] : llvm::enumerate(components)) {
    for (unsigned member : members)
      componentOf[member] = static_cast<unsigned>(c);
    unsigned top = 0;
    for (unsigned member : members)
      for (unsigned callee : names[member])
        if (componentOf[callee] != c)
          top = std::max(top, height[callee] + 1);
    for (unsigned member : members)
      height[member] = top;
    tallest = std::max(tallest, top);
  }
  SmallVector<SmallVector<unsigned>> byHeight(fns.empty() ? 0 : tallest + 1);
  for (auto [at, h] : llvm::enumerate(height))
    if (components[componentOf[at]].size() == 1)
      byHeight[h].push_back(static_cast<unsigned>(at));

  // Each merged function's name to the lexicographically smallest symbol of
  // its class, and each class of two or more, its members in symbol order.
  idr::DataRemap::Renames renames;
  SmallVector<SmallVector<idr::FuncOp>> classes;

  for (const SmallVector<unsigned> &level : byHeight) {
    SmallVector<unsigned> hashes(level.size());
    parallelFor(context, 0, level.size(), [&](size_t i) {
      hashes[i] = static_cast<unsigned>(
          static_cast<size_t>(idr::deduplicate::hashFunction(fns[level[i]], renames)));
    });

    // Each candidate joins the class of the first one before it that is
    // the same function, or begins one.
    std::unordered_map<unsigned, SmallVector<unsigned, 1>> byHash;
    SmallVector<SmallVector<idr::FuncOp>> formed;
    for (auto [at, hash] : llvm::zip_equal(level, hashes)) {
      idr::FuncOp fn = fns[at];
      SmallVector<unsigned, 1> &bucket = byHash[hash];
      auto same = llvm::find_if(bucket, [&](unsigned c) {
        return idr::deduplicate::sameFunction(formed[c].front(), fn, renames);
      });
      if (same != bucket.end()) {
        formed[*same].push_back(fn);
      } else {
        bucket.push_back(static_cast<unsigned>(formed.size()));
        formed.push_back({fn});
      }
    }

    // Once the classes of this height are formed, every function above it
    // reads a member of one as the smallest symbol of its class.
    for (SmallVector<idr::FuncOp> &members : formed) {
      if (members.size() < 2)
        continue;
      llvm::sort(members, [](idr::FuncOp lhs, idr::FuncOp rhs) {
        return lhs.getSymName() < rhs.getSymName();
      });
      (void)idr::support::perform<DeduplicateMergeAction>(members.front(), [&] {
        for (idr::FuncOp member : llvm::drop_begin(members))
          renames[member.getSymNameAttr()] = members.front().getSymNameAttr();
        classes.push_back(std::move(members));
      });
    }
  }

  if (classes.empty())
    return markAllAnalysesPreserved();

  // The one kept carries every member's location, so that what was written
  // for any of them finds it.
  for (SmallVector<idr::FuncOp> &members : classes) {
    auto locations = llvm::map_to_vector(members, [](idr::FuncOp member) { return member.getLoc(); });
    members.front()->setLoc(FusedLoc::get(context, locations));
  }
  numGroups += classes.size();

  // One remap renames every use of a merged function, and remakes each data
  // type whose body names a merged label; the duplicates go, serially, in
  // program order, and the program's root, an attribute of the program
  // itself, names the one kept of its class.
  StringAttr root = renames.lookup(program.getRootAttr().getAttr());
  FailureOr<std::unique_ptr<idr::DataRemap>> remap = idr::DataRemap::create(
      program, "dedup",
      [](Type, std::optional<idr::DataRemap::FieldPlace>) -> std::optional<Type> {
        return std::nullopt;
      },
      {}, renames);
  if (failed(remap))
    return signalPassFailure();
  SymbolTable &symbols = getAnalysis<SymbolTable>();
  for (idr::FuncOp fn : fns) {
    if (!renames.contains(fn.getSymNameAttr()))
      continue;
    symbols.erase(fn);
    ++numMerged;
  }
  if (root)
    program.setRootAttr(FlatSymbolRefAttr::get(root));
  (*remap)->retype(program);
  markAnalysesPreserved<SymbolTable>();
}

} // namespace
