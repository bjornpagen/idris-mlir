// !idr.q: a type at a grade, and its canonical forms.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// The canonical forms: a plain type is (many, plain) and is never written
// as a grade; a grade is of a carrier, never of a grade; nothing is owned
// at quantity zero; the erased value, of no carrier, is at quantity zero;
// the world is at (one, plain) only; a linear value has a runtime type.
LogicalResult QType::verify(function_ref<InFlightDiagnostic()> emitError, Quantity quantity,
                            Permission permission, Type value) {
  Grade grade{quantity, permission};
  if (grade.plain())
    return emitError() << "expects a grade other than (many, plain), which is the plain type";
  if (isa<QType>(value))
    return emitError() << "expects a grade of a plain type, got one of " << value;
  if (grade.quantity == Quantity::Zero && grade.permission != Permission::Plain)
    return emitError() << "expects nothing owned at quantity zero";
  if (isa<NoneType>(value) != (grade.quantity == Quantity::Zero))
    return emitError() << "expects the erased value, and only it, at quantity zero";
  if (isa<WorldType>(value)) {
    if (grade != Grade{Quantity::One, Permission::Plain})
      return emitError() << "expects the world at (one, plain)";
    return success();
  }
  // A runtime type: one a field may have, or a token, which is owned.
  if (grade.quantity != Quantity::Zero && !isFieldType(value) && !isa<TokenType>(value))
    return emitError() << "expects a grade of a runtime type, got " << value;
  return success();
}
