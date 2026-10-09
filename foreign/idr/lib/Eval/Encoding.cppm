// idr.eval:encoding: the results of a call as the child sends them to the
// compiler, and as the compiler reads them back.
export module idr.eval:encoding;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::eval {

namespace {

// The parts a constructor or a closure holds, in the order its entry names
// them: a plain constructor's fields; a run's cells' fields, cell after
// cell, then its tail; a closure's captures. A run's spine is walked
// through its cells, never through its fields, each of which would build
// the rest of the run.
SmallVector<Attribute> partsOf(Attribute value) {
  if (auto closure = dyn_cast<ClosureAttr>(value))
    return llvm::to_vector(closure.getCaptures());
  auto con = cast<ConAttr>(value);
  if (!con.isRun())
    return llvm::to_vector(con.getFields());
  SmallVector<Attribute> parts;
  for (ArrayAttr cell : con.getRunCells())
    llvm::append_range(parts, cell);
  parts.push_back(con.getTail());
  return parts;
}

} // namespace

// The attributes of the module that carries the table: its parts, and the
// position of each result.
inline constexpr llvm::StringLiteral partsName = "eval.parts";
inline constexpr llvm::StringLiteral resultsName = "eval.results";

} // namespace idr::eval

export namespace idr::eval {

// The results of a call as the child sends them to the compiler: MLIR
// bytecode of a flat table of their distinct parts, each part after the
// parts it holds, which it names by position. A constructor or closure
// part is [its constructor or function, the positions of its parts]; a
// run is [its constructor, the positions of its parts, [its number of
// cells, its spine]]; any other part is the constant itself.
//
// The table stays because it keeps sharing. Bytecode writes an idr.con by
// its assembly, and that text repeats a shared part at every use: a tree
// of 21 distinct constructors, each the two-fold parent of the one below,
// is 44 MB and takes 6.5 s to read back, where the same tree named by
// position is those 21 parts. The reader's deferred entries are linear
// with the carried patch, and a chain, which shares nothing, already is;
// the table is what stores a shared part once. A list is one part, its
// run, however long; the walk below is a stack because a result is as deep
// as the rest of the data it is (a tree, or a list of lists).
std::expected<std::string, std::string> encodeResults(ArrayRef<Attribute> values,
                                                     MLIRContext *ctx) {
  llvm::DenseMap<Attribute, int64_t> position;
  SmallVector<Attribute> table;
  struct Visit {
    Attribute value;
    bool expanded;
  };
  SmallVector<Visit> stack;
  for (Attribute root : values) {
    stack.push_back({root, false});
    while (!stack.empty()) {
      Visit visit = stack.back();
      if (position.contains(visit.value)) {
        stack.pop_back();
        continue;
      }
      bool composite = isa<ConAttr, ClosureAttr>(visit.value);
      if (composite && !visit.expanded) {
        stack.back().expanded = true;
        SmallVector<Attribute> parts = partsOf(visit.value);
        for (Attribute part : llvm::reverse(parts))
          if (!position.contains(part))
            stack.push_back({part, false});
        continue;
      }
      stack.pop_back();
      Attribute entry = visit.value;
      if (composite) {
        auto positions = llvm::map_to_vector(partsOf(visit.value),
                                             [&](Attribute part) { return position.at(part); });
        auto con = dyn_cast<ConAttr>(visit.value);
        Attribute head = con ? Attribute(con.getCtor())
                             : Attribute(cast<ClosureAttr>(visit.value).getCallee());
        SmallVector<Attribute> node{head, DenseI64ArrayAttr::get(ctx, positions)};
        if (con && con.isRun())
          node.push_back(DenseI64ArrayAttr::get(ctx, {static_cast<int64_t>(con.getRunLength()),
                                                      static_cast<int64_t>(con.getSpine())}));
        entry = ArrayAttr::get(ctx, node);
      }
      position[visit.value] = static_cast<int64_t>(table.size());
      table.push_back(entry);
    }
  }
  OwningOpRef<ModuleOp> holder = ModuleOp::create(UnknownLoc::get(ctx));
  (*holder)->setAttr(partsName, ArrayAttr::get(ctx, table));
  (*holder)->setAttr(resultsName,
                     DenseI64ArrayAttr::get(ctx, llvm::map_to_vector(values, [&](Attribute value) {
                                              return position.at(value);
                                            })));
  std::string bytes;
  llvm::raw_string_ostream os(bytes);
  if (failed(writeBytecodeToFile(*holder, os)))
    return std::unexpected(std::string("the results have no bytecode"));
  return bytes;
}

std::expected<SmallVector<Attribute>, std::string> decodeResults(StringRef bytes,
                                                                 MLIRContext *ctx) {
  Block holder;
  if (failed(readBytecodeFile(llvm::MemoryBufferRef(bytes, "idr-eval results"), &holder,
                              ParserConfig(ctx, /*verifyAfterParse=*/false))) ||
      holder.empty())
    return std::unexpected(std::string("the results' bytecode does not read"));
  Operation &module = holder.front();
  auto table = module.getAttrOfType<ArrayAttr>(partsName);
  auto roots = module.getAttrOfType<DenseI64ArrayAttr>(resultsName);
  if (!table || !roots)
    return std::unexpected(std::string("the results' bytecode holds no table"));
  SmallVector<Attribute> built;
  built.reserve(table.size());
  for (Attribute entry : table) {
    auto node = dyn_cast<ArrayAttr>(entry);
    if (!node) {
      built.push_back(entry);
      continue;
    }
    bool sized = node.size() == 2 || node.size() == 3;
    auto head = sized ? dyn_cast<SymbolRefAttr>(node[0]) : SymbolRefAttr();
    auto positions = sized ? dyn_cast<DenseI64ArrayAttr>(node[1]) : DenseI64ArrayAttr();
    auto run = node.size() == 3 ? dyn_cast<DenseI64ArrayAttr>(node[2]) : DenseI64ArrayAttr();
    if (!head || !positions || (node.size() == 3 && (!run || run.size() != 2)))
      return std::unexpected(std::string("a part of the results is malformed"));
    SmallVector<Attribute> parts;
    for (int64_t at : positions.asArrayRef()) {
      if (at < 0 || static_cast<size_t>(at) >= built.size())
        return std::unexpected(std::string("a part of the results holds one not before it"));
      parts.push_back(built[static_cast<size_t>(at)]);
    }
    // A constructor is named in its type (@T::@C), a function alone (@f).
    auto flat = dyn_cast<FlatSymbolRefAttr>(head);
    if (!run) {
      built.push_back(flat ? Attribute(ClosureAttr::get(ctx, flat, ArrayAttr::get(ctx, parts)))
                           : Attribute(ConAttr::get(ctx, head, ArrayAttr::get(ctx, parts))));
      continue;
    }
    // A run's cells, each its fields but the spine, then its tail.
    int64_t cells = run[0], spine = run[1];
    if (flat || cells < 2 || spine < 0 || parts.empty() ||
        (parts.size() - 1) % static_cast<size_t>(cells) != 0 ||
        static_cast<size_t>(spine) > (parts.size() - 1) / static_cast<size_t>(cells))
      return std::unexpected(std::string("a run in the results is malformed"));
    size_t width = (parts.size() - 1) / static_cast<size_t>(cells);
    SmallVector<ArrayAttr> fields;
    for (size_t cell = 0; cell < static_cast<size_t>(cells); ++cell)
      fields.push_back(ArrayAttr::get(ctx, ArrayRef(parts).slice(cell * width, width)));
    built.push_back(ConAttr::getRun(ctx, head, static_cast<unsigned>(spine), fields, parts.back()));
  }
  SmallVector<Attribute> values;
  for (int64_t at : roots.asArrayRef()) {
    if (at < 0 || static_cast<size_t>(at) >= built.size())
      return std::unexpected(std::string("a result is not in the table"));
    values.push_back(built[static_cast<size_t>(at)]);
  }
  return values;
}

} // namespace idr::eval
