// idr.ownership:reachesonlyatoms: static data that reaches no cell but
// atoms, which is in every exclusive tree.
export module idr.ownership:reachesonlyatoms;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

namespace {

// Whether the constant `attr` reaches no cell but atoms: a box constructor
// without fields, a constructor of an unboxed sum whose fields reach none
// either, or a value that is no box or sum at all (a number, a static
// string or big, which nothing takes apart). A closure is a cell. A run is
// read cell by cell and then its tail, never field by field along its
// spine, which would rebuild the rest of the run at every step: its cells
// hold every field but the one that links them.
bool onlyAtoms(Operation *from, Attribute attr) {
  if (isa<ClosureAttr>(attr))
    return false;
  auto con = dyn_cast<ConAttr>(attr);
  if (!con)
    return true;
  auto data = SymbolTable::lookupNearestSymbolFrom<DataOp>(
      from, FlatSymbolRefAttr::get(con.getCtor().getRootReference()));
  if (!data)
    return false;
  // The cells of a run have at least the field that links them. A memo
  // cell is written by its first force, so it is never an atom, even in a
  // state without fields.
  if (data.getBox())
    return !isMemo(data) && !con.isRun() && con.getFields().empty();
  auto atoms = [&](ArrayAttr fields) {
    return llvm::all_of(fields, [&](Attribute field) { return onlyAtoms(from, field); });
  };
  return llvm::all_of(con.getCells(), atoms) && (!con.isRun() || onlyAtoms(from, con.getTail()));
}

} // namespace

// Whether `view` is static data that reaches no cell but atoms: a constant
// nullary constructor (an atom, a static cell with no fields), or a constant
// unboxed sum, which has no cell, whose fields reach none either (a pair of
// empty lists). No take hands out a cell of it, since an atom has no fields
// to take and a sum no cell; no count reaches it, nothing frees or writes
// it. So whoever else holds it changes nothing a consumer of exclusivity
// does: it is in every exclusive tree. A static box with fields is not: a
// take of it would hand out its cell as a token to build in.
export bool reachesOnlyAtoms(Value view) {
  Attribute attr;
  return matchPattern(view, m_Constant(&attr)) && onlyAtoms(view.getDefiningOp(), attr);
}

} // namespace idr::ownership
