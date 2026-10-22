// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The custom directives of the ops that build a constructor value and of a
// dup, which the generated parsers and printers call by name: the fields
// an idr.data.con is given, those an idr.cell.init writes (a field written
// later through its destination, `dest`), and an idr.count.dup's result,
// counted unless another grade is written.

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr {

namespace {

// `%a : A`: a field given, with its type.
ParseResult parseField(OpAsmParser &parser,
                       SmallVectorImpl<OpAsmParser::UnresolvedOperand> &fields,
                       SmallVectorImpl<Type> &types) {
  return failure(parser.parseOperand(fields.emplace_back()) ||
                 parser.parseColonType(types.emplace_back()));
}

} // namespace

// `(%a : A, %b : B)`: every field of a constructor value, given with its
// type.
ParseResult parseFields(OpAsmParser &parser,
                        SmallVectorImpl<OpAsmParser::UnresolvedOperand> &fields,
                        SmallVectorImpl<Type> &types) {
  return parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren,
                                        [&]() { return parseField(parser, fields, types); });
}

void printFields(OpAsmPrinter &printer, Operation *, OperandRange fields, TypeRange types) {
  printer << '(';
  llvm::interleaveComma(llvm::zip_equal(fields, types), printer, [&](auto field) {
    printer << std::get<0>(field) << " : " << std::get<1>(field);
  });
  printer << ')';
}

// `(%a : A, dest, %b : B)`: the fields a cell's init writes, and a hole as
// `dest`; `holes` are the holes' positions, ascending, which the
// destinations' directive reads.
ParseResult parseFieldsWithHoles(OpAsmParser &parser,
                                 SmallVectorImpl<OpAsmParser::UnresolvedOperand> &fields,
                                 SmallVectorImpl<Type> &types, DenseI32ArrayAttr &holes) {
  SmallVector<int32_t> at;
  int32_t index = 0;
  if (parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren, [&]() -> ParseResult {
        if (succeeded(parser.parseOptionalKeyword("dest")))
          at.push_back(index);
        else if (failed(parseField(parser, fields, types)))
          return failure();
        ++index;
        return success();
      }))
    return failure();
  holes = parser.getBuilder().getDenseI32ArrayAttr(at);
  return success();
}

void printFieldsWithHoles(OpAsmPrinter &printer, Operation *, OperandRange fields,
                          TypeRange types, DenseI32ArrayAttr holes) {
  ArrayRef<int32_t> at = holes ? holes.asArrayRef() : ArrayRef<int32_t>();
  printer << '(';
  size_t given = 0;
  for (size_t index = 0, n = fields.size() + at.size(); index < n; ++index) {
    if (index)
      printer << ", ";
    if (given == fields.size() || llvm::is_contained(at, static_cast<int32_t>(index))) {
      printer << "dest";
      continue;
    }
    printer << fields[given] << " : " << types[given];
    ++given;
  }
  printer << ')';
}

// A dup's result: the value counted, claiming nothing of its sharing, unless
// another grade is written, `-> T`.
ParseResult parseCountedResult(OpAsmParser &parser, Type &type, Type value) {
  if (succeeded(parser.parseOptionalArrow()))
    return parser.parseType(type);
  type = atHold(value, Hold::counted());
  return success();
}

void printCountedResult(OpAsmPrinter &printer, Operation *, Type type, Type value) {
  if (type != atHold(value, Hold::counted()))
    printer << " -> " << type;
}

} // namespace idr
