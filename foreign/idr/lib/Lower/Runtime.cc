// Runtime helpers and static data for idr-lower.

#include "Lower/Runtime.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Parser/Parser.h"

using namespace mlir;

namespace idr::lower {

namespace {

constexpr const char *runtimeSource =
#include "Runtime.mlir.inc"
    ;

} // namespace

LogicalResult Runtime::require(StringRef name) {
  if (!helpers) {
    helpers = parseSourceString<ModuleOp>(runtimeSource, module.getContext());
    if (!helpers)
      return module.emitError("internal error: idr runtime helpers do not parse");
  }
  SmallVector<StringRef> work{name};
  while (!work.empty()) {
    StringRef next = work.pop_back_val();
    if (module.lookupSymbol(next))
      continue;
    Operation *op = helpers->lookupSymbol(next);
    if (!op)
      return module.emitError("internal error: missing idr helper ") << next;
    OpBuilder b(module.getBodyRegion());
    b.setInsertionPointToEnd(module.getBody());
    b.clone(*op);
    op->walk([&](Operation *inner) {
      for (NamedAttribute attr : inner->getAttrs())
        attr.getValue().walk([&](FlatSymbolRefAttr ref) {
          work.push_back(ref.getValue());
        });
    });
  }
  return success();
}

void Runtime::declareString(StringRef bytes) {
  if (bytes.empty() || strings.count(bytes))
    return;
  std::string name = ("__idr_str_" + Twine(strings.size())).str();
  strings[bytes] = name;
  OpBuilder b(module.getBodyRegion());
  b.setInsertionPointToStart(module.getBody());
  auto arrayType = LLVM::LLVMArrayType::get(b.getI8Type(), bytes.size());
  LLVM::GlobalOp::create(b, module.getLoc(), arrayType, /*isConstant=*/true,
                         LLVM::Linkage::Internal, name, b.getStringAttr(bytes),
                         /*alignment=*/0);
}

std::pair<Value, Value> Runtime::string(OpBuilder &b, Location loc, StringRef bytes) const {
  auto ptrType = LLVM::LLVMPointerType::get(b.getContext());
  Value len = arith::ConstantOp::create(
      b, loc, b.getI64IntegerAttr(static_cast<int64_t>(bytes.size())));
  if (bytes.empty())
    return {LLVM::ZeroOp::create(b, loc, ptrType), len};
  Value addr = LLVM::AddressOfOp::create(b, loc, ptrType, strings.lookup(bytes));
  return {addr, len};
}

namespace {

std::string describe(Location loc) {
  if (auto file = dyn_cast<FileLineColLoc>(loc))
    return (file.getFilename().getValue() + ":" + Twine(file.getLine()) + ":" +
            Twine(file.getColumn()))
        .str();
  if (auto fused = dyn_cast<FusedLoc>(loc))
    for (Location inner : fused.getLocations())
      if (auto text = describe(inner); !text.empty())
        return text;
  if (auto named = dyn_cast<NameLoc>(loc))
    return describe(named.getChildLoc());
  if (auto site = dyn_cast<CallSiteLoc>(loc))
    return describe(site.getCallee());
  return "";
}

} // namespace

std::string crashMessage(Location loc, StringRef cause) {
  std::string where = describe(loc);
  return ("idris-mlir: " + cause + (where.empty() ? "" : " at " + where) + "\n").str();
}

bool divisorKnownNonZero(Value divisor) {
  APInt known;
  return matchPattern(divisor, m_ConstantInt(&known)) && !known.isZero();
}

bool knownFinite(Value value) {
  FloatAttr constant;
  return matchPattern(value, m_Constant(&constant)) && constant.getValue().isFinite();
}

// Calls @__idr_crash with a message naming the cause and the Idris location.
void emitCrash(OpBuilder &b, Location loc, const Runtime &runtime, StringRef cause) {
  auto [ptr, len] = runtime.string(b, loc, crashMessage(loc, cause));
  func::CallOp::create(b, loc, "__idr_crash", TypeRange{}, ValueRange{ptr, len});
}

} // namespace idr::lower
