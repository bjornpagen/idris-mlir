// Registration of the idr dialect, with what it attaches to other dialects.

#include "idr/Idr.h"

using namespace mlir;

void idr::registerIdr(DialectRegistry &registry) {
  registry.insert<IdrDialect>();
  registerCallEffects(registry);
}
