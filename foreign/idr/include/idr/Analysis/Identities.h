// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions of one component of the direct calls that give back one of
// their arguments, found together: what idr-identity makes every call of
// them.
//
// Every function of the component starts out assumed to give back each
// argument that could be its result: of the result's type at any quantity.
// A function that does not, under what is assumed of the rest, loses the
// assumption, and the functions that call it are checked again. Each check
// can only drop an assumption, and there are finitely many, so the work
// ends; what is left is the greatest fixpoint, so the functions of a
// mutual recursion are found together, and whatever order the functions
// are checked in finds the same ones. A callee outside the component is
// final, and what it gives back is read frozen. Each function is walked
// once before that fixpoint, into a record of how its body is built; what
// remains of the assumptions is read off that record, so the arguments
// share one walk and a requeued caller is not walked again.
//
// A function of a program in the owned stage gives back nothing, since a
// counted value there cannot stand for a fresh one; nor does one that takes
// a world, whose call is where its effects are ordered.
#ifndef IDR_ANALYSIS_IDENTITIES_H
#define IDR_ANALYSIS_IDENTITIES_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <tuple>

namespace idr::identities {

// What the solve reads of a callee that is not in the component it solves:
// what it gives back, frozen, and whether its `effects` say it returns.
struct Callee {
  std::optional<unsigned> givesBack;
  bool returns = false;
};
using Outside = llvm::function_ref<Callee(mlir::StringAttr callee)>;

// The argument each function of `component` gives back, if it gives one
// back, in the order of `component`. `outside` answers for a callee that is
// not in `component`.
llvm::SmallVector<std::optional<unsigned>> givesBackOf(llvm::ArrayRef<FuncOp> component,
                                                      Outside outside);

// The functions of the component, by name.
using Members = llvm::DenseMap<mlir::StringAttr, FuncOp>;

// The parameters of each function, by name, assumed to be given back.
using Assumed = llvm::DenseMap<mlir::StringAttr, llvm::SmallVector<unsigned, 1>>;

// The arguments `fn` could give back.
llvm::SmallVector<unsigned, 1> candidates(FuncOp fn);

// The parts of a function's argument: the argument itself, and what the
// matches and reads of the function take out of it. A part is a path from
// the argument, each step a field of a constructor or the predecessor of a
// natural (the field of its successor, as Idris shapes a natural). Two
// values that take the same path are the same part, however each was read:
// values never change, so a constructor rebuilt from the fields one match
// bound is as good as one rebuilt from another read of the same part. A
// part's depth, its steps below the argument, is what makes a recursion on
// parts end: each step is a strictly smaller value, and a value is finite.
struct Part {
  unsigned parent = 0;
  // The field's constructor, by its tag in its data type; none for the
  // predecessor of a natural.
  std::optional<unsigned> tag;
  unsigned field = 0;
  unsigned depth = 0;
  // The part's value, at no grade.
  mlir::Type type;
};

// The parts of one argument met so far, each once.
class Parts {
public:
  // The argument itself.
  static constexpr unsigned whole = 0;

  explicit Parts(mlir::Type argument);
  const Part &operator[](unsigned part) const { return parts[part]; }
  // Field `index`, of type `type`, of the part `parent` built by the
  // constructor of tag `tag`.
  unsigned field(unsigned parent, unsigned tag, unsigned index, mlir::Type type) {
    return step(parent, tag, index, type);
  }
  // The predecessor of the natural `parent`, which is not zero.
  unsigned predecessor(unsigned parent) {
    return step(parent, std::nullopt, 0, parts[parent].type);
  }

private:
  unsigned step(unsigned parent, std::optional<unsigned> tag, unsigned index, mlir::Type type);

  llvm::SmallVector<Part> parts;
  llvm::DenseMap<std::tuple<unsigned, std::optional<unsigned>, unsigned>, unsigned> steps;
};

// One walk of a function, for every argument it might give back
// (IdentitiesRecord.cpp), and what it gives back under a set of
// assumptions, read off the walk (IdentitiesRebuilds.cpp).
class Record {
public:
  Record(FuncOp fn, llvm::ArrayRef<unsigned> candidates, const Members &members, Outside outside);

  // The subset of `asked`, in that order, that the walk gives back under
  // `assumed`. When the calls this read last consulted still stand as they
  // did, the previous answer stands with them: a requeue that changed
  // nothing those calls rely on does not read the record through again.
  llvm::SmallVector<unsigned, 1> givesBack(llvm::ArrayRef<unsigned> asked, const Assumed &assumed);

private:
  // What a part is known to be where a value stands for it: built by the
  // constructor of a tag, a literal, or neither.
  struct Known {
    std::optional<unsigned> tag;
    mlir::Attribute literal;
  };
  // A match the use sits in, inner first, as knownAt walks parent regions:
  // the constructor or the literal the region the use is in takes, when
  // the region names one.
  struct Frame {
    int scrutinee = -1;
    bool lit = false;
    std::optional<unsigned> tag;
    mlir::Attribute literal;
  };
  // One region of a match: empty fails, unreachable is skipped, a yield
  // must rebuild.
  struct Arm {
    bool empty = false;
    bool unreachable = false;
    bool yield = false;
    llvm::SmallVector<int, 1> values;
    llvm::SmallVector<Frame, 2> frames;
  };
  // How a value is built. Calls are the only place an assumption is read;
  // everything else is fixed by the walk.
  struct Node {
    enum Kind : uint8_t { Dead, Entry, MatchArg, Copy, Field, Pred, Call, Con, Add, Join, Const };
    Kind kind = Dead;
    // Entry: which function argument. MatchArg and Field: which field.
    // Join: which result.
    unsigned arg = 0;
    int src = -1;
    // MatchArg in a case, Field, Con and a constant of a constructor: the
    // constructor's tag.
    unsigned tag = 0;
    mlir::StringAttr callee;
    mlir::Type type;
    mlir::Attribute attr;
    bool memo = false;
    bool deflt = false;
    bool returns = false;
    bool allocates = false;
    bool isCon = false;
    bool conRun = false;
    // A constant of a constructor with no fields: the one value it has.
    bool fieldless = false;
    llvm::SmallVector<int, 4> ops;
    llvm::SmallVector<mlir::Type, 4> types;
    unsigned side = 0;
  };
  struct Ret {
    int value = -1;
    llvm::SmallVector<Frame, 2> frames;
  };
  // The assumption list a read of the record consulted, copied so a later
  // drop compares unequal.
  struct Snapshot {
    mlir::StringAttr name;
    std::optional<llvm::SmallVector<unsigned, 1>> params;
  };
  struct Memo {
    unsigned epoch = 0;
    llvm::SmallVector<std::optional<unsigned>, 1> parts;
  };

  // The walk.
  static bool memoType(mlir::Type type);
  static std::optional<unsigned> remaining(MatchOp match);
  int place(mlir::Value value, Node node);
  int intern(mlir::Value value);
  int internArg(mlir::BlockArgument arg);
  int defineCall(CallOp call);
  void encodeConst(Node &node, mlir::Value value, mlir::Attribute constant);
  int internJoin(mlir::Operation *op, unsigned number);
  llvm::SmallVector<Arm, 2> armsOf(mlir::Operation *op);
  int internResult(mlir::OpResult result);
  llvm::SmallVector<Frame, 2> framesAt(mlir::Operation *at);
  bool record(ReturnOp ret);
  bool scan(mlir::Region &region);
  bool accept(mlir::Operation &op);

  // The reading.
  bool stable(const Assumed &assumed) const;
  void readCallee(mlir::StringAttr name);
  void fill(std::size_t node);
  std::optional<unsigned> partOf(int node, unsigned slot);
  std::optional<unsigned> singleCtor(mlir::Type type);
  Known knownAt(unsigned part, llvm::ArrayRef<Frame> frames, unsigned slot);
  bool rebuilds(int node, unsigned part, llvm::ArrayRef<Frame> frames, unsigned slot);
  bool rebuildsCon(std::size_t node, unsigned part, llvm::ArrayRef<Frame> frames, unsigned slot);
  bool rebuildsSuccessor(std::size_t node, unsigned part, llvm::ArrayRef<Frame> frames,
                         unsigned slot);
  bool rebuildsJoin(std::size_t node, unsigned part, unsigned slot);
  bool rebuildsConstant(std::size_t node, unsigned part, llvm::ArrayRef<Frame> frames,
                        unsigned slot);
  void evaluate(const Assumed &assumed);

  FuncOp fn;
  const Members &members;
  Outside outside;
  bool possible = true;
  llvm::SmallVector<unsigned, 1> arguments;
  llvm::DenseMap<unsigned, unsigned> index;
  llvm::SmallVector<Parts, 1> parts;
  llvm::SmallVector<Node, 16> nodes;
  llvm::SmallVector<Memo, 16> memo;
  llvm::DenseMap<mlir::Value, int> ids;
  llvm::SmallVector<llvm::SmallVector<Arm, 2>, 1> joins;
  llvm::SmallVector<int, 2> reliant;
  llvm::SmallVector<Ret, 1> rets;
  llvm::DenseMap<mlir::Type, std::optional<unsigned>> oneCtor;

  const Assumed *live = nullptr;
  bool cached = false;
  unsigned epoch = 0;
  llvm::SmallVector<bool, 1> answered;
  llvm::SmallVector<Snapshot, 2> saved;
  llvm::DenseSet<mlir::StringAttr> consulted;
};

} // namespace idr::identities

#endif // IDR_ANALYSIS_IDENTITIES_H
