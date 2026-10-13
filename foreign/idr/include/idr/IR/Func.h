// What the dialect registers for idr.func, idr.call and idr.return beyond
// their ops: the inliner's rules, which mirror func's for its own.
#ifndef IDR_IR_FUNC_H
#define IDR_IR_FUNC_H

#include "idr/IR/IdrDialect.h"

namespace idr {

// Every call, op and region of the dialect may be inlined; a return becomes
// the values it gives back, or a branch when the callee has several blocks.
void addInlinerInterface(IdrDialect &dialect);

} // namespace idr

#endif // IDR_IR_FUNC_H
