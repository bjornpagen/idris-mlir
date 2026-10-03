// idr.ops:gradesyntax: the generic spelling of a grade, in !idr.q.
export module idr.ops:gradesyntax;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

namespace {

constexpr StringRef quantityNames[] = {"0", "1", "w"};
constexpr StringRef permissionNames[] = {"", "borrow", "own", "excl"};

} // namespace

export namespace idr::ops {

// The generic spelling of a grade: the quantity, then the permission when
// there is one to say: `1`, `w own`, `1 excl`.
void printGrade(AsmPrinter &printer, Grade grade) {
  printer << quantityNames[static_cast<unsigned>(grade.quantity)];
  if (grade.permission != Permission::None)
    printer << ' ' << permissionNames[static_cast<unsigned>(grade.permission)];
}

std::optional<Grade> parseGrade(AsmParser &parser) {
  Grade grade;
  uint64_t number = 0;
  StringRef word;
  OptionalParseResult parsed = parser.parseOptionalInteger(number);
  if (parsed.has_value() && succeeded(*parsed) && number <= 1) {
    grade.quantity = number == 0 ? Quantity::Zero : Quantity::One;
  } else if (!parsed.has_value() && succeeded(parser.parseOptionalKeyword("w"))) {
    grade.quantity = Quantity::Many;
  } else {
    parser.emitError(parser.getCurrentLocation(), "expects a quantity 0, 1 or w");
    return std::nullopt;
  }
  if (succeeded(parser.parseOptionalKeyword(&word))) {
    auto permission = llvm::find(permissionNames, word);
    if (permission == std::end(permissionNames)) {
      parser.emitError(parser.getCurrentLocation(), "expects a permission borrow, own or excl");
      return std::nullopt;
    }
    grade.permission = static_cast<Permission>(permission - std::begin(permissionNames));
  }
  return grade;
}

} // namespace idr::ops
