// idr.eval:encoding: the results of a call as the child sends them to the
// compiler, and as the compiler reads them back.
export module idr.eval:encoding;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::eval {

namespace {

// The fields of a constructor or the captures of a closure; null for any
// other constant, which holds no parts.
ArrayAttr partsOf(Attribute value) {
  if (auto con = dyn_cast<ConAttr>(value))
    return con.getFields();
  if (auto closure = dyn_cast<ClosureAttr>(value))
    return closure.getCaptures();
  return {};
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
// part is [its constructor or function, the positions of its fields or
// captures]; any other part is the constant itself. The table is as deep
// as one part whatever the depth of the results, so it is read in time
// linear in its size, and a part shared by many is in it once.
std::expected<std::string, std::string> encodeResults(ArrayRef<Attribute> values,
                                                     MLIRContext *ctx) {
  llvm::DenseMap<Attribute, int64_t> position;
  SmallVector<Attribute> table;
  // Each part after its own parts, by a walk with an explicit stack, since
  // a result is as deep as the data it is (a list of a million elements).
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
      ArrayAttr parts = partsOf(visit.value);
      if (parts && !visit.expanded) {
        stack.back().expanded = true;
        for (Attribute part : llvm::reverse(parts))
          if (!position.contains(part))
            stack.push_back({part, false});
        continue;
      }
      stack.pop_back();
      Attribute entry = visit.value;
      if (parts) {
        auto positions = llvm::map_to_vector(parts, [&](Attribute part) { return position.at(part); });
        Attribute head = isa<ConAttr>(visit.value)
                             ? Attribute(cast<ConAttr>(visit.value).getCtor())
                             : Attribute(cast<ClosureAttr>(visit.value).getCallee());
        entry = ArrayAttr::get(ctx, {head, DenseI64ArrayAttr::get(ctx, positions)});
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
    auto head = node.size() == 2 ? dyn_cast<SymbolRefAttr>(node[0]) : SymbolRefAttr();
    auto positions = node.size() == 2 ? dyn_cast<DenseI64ArrayAttr>(node[1]) : DenseI64ArrayAttr();
    if (!head || !positions)
      return std::unexpected(std::string("a part of the results is malformed"));
    SmallVector<Attribute> parts;
    for (int64_t at : positions.asArrayRef()) {
      if (at < 0 || static_cast<size_t>(at) >= built.size())
        return std::unexpected(std::string("a part of the results holds one not before it"));
      parts.push_back(built[static_cast<size_t>(at)]);
    }
    // A constructor is named in its type (@T::@C), a function alone (@f).
    auto flat = dyn_cast<FlatSymbolRefAttr>(head);
    built.push_back(flat ? Attribute(ClosureAttr::get(ctx, flat, ArrayAttr::get(ctx, parts)))
                         : Attribute(ConAttr::get(ctx, head, ArrayAttr::get(ctx, parts))));
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
