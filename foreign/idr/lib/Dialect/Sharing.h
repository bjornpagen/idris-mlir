// How the dialect's constants keep their shared parts shared when they are
// printed.
#pragma once

#include "idr/Idr.h"

namespace idr {

// Registers the aliases of the dialect's large constants.
void addSharingInterfaces(IdrDialect &dialect);

} // namespace idr
