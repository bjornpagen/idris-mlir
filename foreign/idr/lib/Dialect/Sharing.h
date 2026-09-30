// How the dialect's constants keep their shared parts shared when they are
// written out, in MLIR bytecode and in text.
#pragma once

#include "idr/Idr.h"

namespace idr {

// Registers the dialect's bytecode encoding of its value attributes and the
// aliases of its large constants.
void addSharingInterfaces(IdrDialect &dialect);

} // namespace idr
