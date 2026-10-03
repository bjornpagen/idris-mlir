// idr.ownership:cells: the lattice of exclusivity: what is known of a
// value's cell graph. Nothing here is exported: exclusivity's steps share
// it.
export module idr.ownership:cells;

import idr.mlir;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::ownership {

// What is known of a value's cell graph: nothing yet (the optimistic
// start), a tree of cells this value alone reaches, or cells another
// reference may reach.
enum class Sharing : uint8_t { Unknown, Exclusive, Shared };

struct Cells {
  Sharing sharing = Sharing::Unknown;

  static Cells of(Sharing sharing) { return {sharing}; }

  static Cells join(const Cells &a, const Cells &b) {
    return of(std::max(a.sharing, b.sharing));
  }

  bool operator==(const Cells &) const = default;

  void print(raw_ostream &os) const {
    switch (sharing) {
    case Sharing::Unknown:
      os << "unknown";
      return;
    case Sharing::Exclusive:
      os << "exclusive";
      return;
    case Sharing::Shared:
      os << "shared";
      return;
    }
  }
};

struct CellsLattice : Lattice<Cells> {
  // The lattice's identity, which MLIR's TypeID finds by this name.
  static TypeID resolveTypeID() {
    static SelfOwningTypeID id;
    return id;
  }
  using Lattice::Lattice;
};

} // namespace idr::ownership
