// !idr.fn: a closure's type, its inputs and results as a function type.

#include "idr/Idr.h"

#include "mlir/IR/DialectImplementation.h"

using namespace mlir;
using namespace idr;

FunctionType FnType::getFunctionType() const {
  return FunctionType::get(getContext(), getInputs(), getResults());
}

// `!idr.fn<(A...) -> (R...)>`, with both lists always parenthesized.
Type FnType::parse(AsmParser &parser) {
  SmallVector<Type> inputs, results;
  auto list = [&](SmallVectorImpl<Type> &types) {
    return parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren, [&] {
      return parser.parseType(types.emplace_back());
    });
  };
  if (parser.parseLess() || list(inputs) || parser.parseArrow() || list(results) ||
      parser.parseGreater())
    return {};
  return FnType::get(parser.getContext(), inputs, results);
}

void FnType::print(AsmPrinter &printer) const {
  printer << "<(";
  llvm::interleaveComma(getInputs(), printer);
  printer << ") -> (";
  llvm::interleaveComma(getResults(), printer);
  printer << ")>";
}
