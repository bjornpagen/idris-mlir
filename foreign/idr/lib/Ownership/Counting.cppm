// idr.ownership:counting: which values hold references, as one run over a
// module counts them.
export module idr.ownership:counting;

import idr.mlir;
import idr.dialect;

import :isstatic;

using namespace mlir;

namespace idr::ownership {

// Which values of a module hold references: a type's answer is
// idr::holdsReferences, asked once per type, and the stage is the one the
// run is in. idr-rc grades as it goes, so it says which side of grading
// the signatures it is on; the verifier runs in the owned stage only.
export class Counting {
public:
  Counting(Operation *module, bool ownedStage) : module(module), graded(ownedStage) {}

  bool counted(Type type) {
    auto [known, fresh] = answers.try_emplace(type, false);
    if (fresh)
      known->second = holdsReferences(type, symbols, module);
    return known->second;
  }

  // Whether `value` holds references: its type does, and it is not static.
  bool tracked(Value value) { return counted(value.getType()) && !isStatic(value); }

  // Whether the signatures are graded: a parameter is then owned, or a
  // view the function borrows (isBorrowed).
  bool ownedStage() const { return graded; }

private:
  Operation *module;
  bool graded;
  SymbolTableCollection symbols;
  llvm::DenseMap<Type, bool> answers;
};

} // namespace idr::ownership
