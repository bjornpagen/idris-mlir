// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How the dialect's text stays readable: a family is written once at the top
// of the text, by an alias, and named by it wherever a type applies it,
// since its declaration would otherwise be spelled out at every use. The
// alias is a name for the reader; nothing is decided from it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Families/Families.h"

#include "mlir/IR/OpImplementation.h"

using namespace mlir;
using namespace idr;

namespace {

// Every family is an alias, numbered by the printer where two share it.
struct IdrAsmInterface : OpAsmDialectInterface {
  using OpAsmDialectInterface::OpAsmDialectInterface;

  AliasResult getAlias(Attribute attr, raw_ostream &os) const override {
    if (!isa<FamilyAttr>(attr))
      return AliasResult::NoAlias;
    os << "family";
    return AliasResult::OverridableAlias;
  }
};

} // namespace

void idr::detail::addAsmInterface(IdrDialect &dialect) {
  dialect.addInterfaces<IdrAsmInterface>();
}
