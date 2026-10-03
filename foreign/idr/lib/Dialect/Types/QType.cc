// !idr.q: a type at a grade, its canonical forms and its generic spelling.

#include "idr/Idr.h"

#include "mlir/IR/DialectImplementation.h"

import idr.ops;

using namespace mlir;
using namespace idr;

// The canonical forms: a plain type is (ω, ·) and is never written as a
// grade; a grade is of a carrier, never of a grade; nothing is owned at
// quantity 0; the erased value, of no carrier, is at quantity 0; the world
// is at (1, ·) only; a linear value has a runtime type.
LogicalResult QType::verify(function_ref<InFlightDiagnostic()> emitError, Grade grade,
                            Type value) {
  if (grade.plain())
    return emitError() << "expects a grade other than (w, .), which is the plain type";
  if (isa<QType>(value))
    return emitError() << "expects a grade of a plain type, got one of " << value;
  if (grade.quantity == Quantity::Zero && grade.permission != Permission::None)
    return emitError() << "expects nothing owned at quantity 0";
  if (isa<NoneType>(value) != (grade.quantity == Quantity::Zero))
    return emitError() << "expects the erased value, and only it, at quantity 0";
  if (isa<WorldType>(value)) {
    if (grade != Grade{Quantity::One, Permission::None})
      return emitError() << "expects the world at quantity 1, owning nothing";
    return success();
  }
  // A runtime type: one a field may have, or a token, which is owned.
  if (grade.quantity != Quantity::Zero && !isFieldType(value) && !isa<TokenType>(value))
    return emitError() << "expects a grade of a runtime type, got " << value;
  return success();
}

// `!idr.q<GRADE, T>`, the generic spelling; `!idr.q<0>` for the erased
// value. The spellings lin, erased and world are the dialect's to parse
// and print.
Type QType::parse(AsmParser &parser) {
  if (parser.parseLess())
    return {};
  std::optional<Grade> grade = ops::parseGrade(parser);
  if (!grade)
    return {};
  Type value = NoneType::get(parser.getContext());
  if (succeeded(parser.parseOptionalComma()) && parser.parseType(value))
    return {};
  if (parser.parseGreater())
    return {};
  return QType::getChecked([&] { return parser.emitError(parser.getCurrentLocation()); },
                           parser.getContext(), *grade, value);
}

void QType::print(AsmPrinter &printer) const {
  printer << '<';
  ops::printGrade(printer, getGrade());
  if (!isa<NoneType>(getValue()))
    printer << ", " << getValue();
  printer << '>';
}
