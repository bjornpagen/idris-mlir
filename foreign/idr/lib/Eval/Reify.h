// Reading a result of compile-time evaluation back as a constant attribute,
// through the layouts idr-lower built it in.
// Runs in idr-eval's child, on the memory of the JITed code.
#pragma once

#include "Lower/Layout.h"

#include <expected>
#include <string>

namespace idr::eval {

// Why the results of a call were not read back.
struct Unread {
  enum class Why {
    // They take more static data than a result may.
    TooLarge,
    // The memory holds what no layout describes: an internal error.
    Unreadable,
  };
  Why why;
  std::string message;
};

class Reifier {
public:
  // `codes` maps the address of the code of each label's closures to the
  // label's number; the results of one call may take `budget` bytes of
  // static data.
  Reifier(lower::Layouts &l, llvm::DenseMap<uint64_t, unsigned> codes, uint64_t budget)
      : layouts(l), codes(std::move(codes)), budget(budget) {}

  // The values of `types` whose components are the words of `slots`, one
  // 8-byte slot each, or why they are not read.
  std::expected<llvm::SmallVector<mlir::Attribute>, Unread>
  results(llvm::ArrayRef<mlir::Type> types, llvm::ArrayRef<uint64_t> slots);

private:
  // The value of type `type` whose components are the next words of
  // `words`; advances `words`. Null once `unread` says why not.
  mlir::Attribute value(mlir::Type type, llvm::ArrayRef<uint64_t> &words);
  // The value in the cell or string `word` points to (or, for a big, the
  // word itself), read once however many values share it.
  mlir::Attribute object(mlir::Type type, uint64_t word);
  // The components of `slots` in the cell at `cell`, one word each.
  llvm::SmallVector<uint64_t> read(const char *cell, llvm::ArrayRef<lower::Slot> slots);
  mlir::Attribute constructor(DataOp data, CtorOp ctor,
                              llvm::function_ref<llvm::SmallVector<uint64_t>(unsigned field)> fields);
  // Counts `bytes` more of static data against the budget.
  bool spend(uint64_t bytes);
  mlir::Attribute refuse(Unread::Why why, std::string message);

  lower::Layouts &layouts;
  llvm::DenseMap<uint64_t, unsigned> codes;
  uint64_t budget;
  uint64_t spent = 0;
  std::optional<Unread> unread;
  // The values read, by address and type: the results of a round share
  // cells, and so do the constants read from them.
  llvm::DenseMap<std::pair<uint64_t, mlir::Type>, mlir::Attribute> seen;
};

// The results of a call as the child sends them to the compiler: MLIR
// bytecode of a flat table of their distinct parts, each part after the
// parts it holds, which it names by position. A constructor or closure
// part is [its constructor or function, the positions of its fields or
// captures]; any other part is the constant itself. The table is as deep
// as one part whatever the depth of the results, so it is read in time
// linear in its size, and a part shared by many is in it once.
std::expected<std::string, std::string> encodeResults(llvm::ArrayRef<mlir::Attribute> values,
                                                     mlir::MLIRContext *ctx);
std::expected<llvm::SmallVector<mlir::Attribute>, std::string>
decodeResults(llvm::StringRef bytes, mlir::MLIRContext *ctx);

} // namespace idr::eval
