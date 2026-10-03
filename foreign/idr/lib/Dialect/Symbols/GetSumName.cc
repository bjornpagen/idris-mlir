// The declaration a !idr.data or !idr.box type names.

#include "idr/Idr.h"

#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

FlatSymbolRefAttr idr::getSumName(Type type) {
  return TypeSwitch<Type, FlatSymbolRefAttr>(unrestricted(type))
      .Case<DataType, BoxType>([](auto sum) { return sum.getName(); })
      .Default([](Type) { return nullptr; });
}
