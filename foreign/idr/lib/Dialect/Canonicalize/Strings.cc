// Output and the first character of a string being built: the DRR patterns
// of Canonicalize.td, and the empty string, which DRR cannot match. Output
// of a list (idr.io.put_list) takes one step of the list it meets
// (idr.canon).

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {
#include "idr/IdrCanonicalize.inc"
} // namespace

import idr.canon;

void PutStrOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_PutStrOfAppend, Idr_PutStrOfCons, Idr_PutStrOfFromChar, Idr_PutStrOfShowInt,
              Idr_PutStrOfShowDouble, Idr_PutStrOfPack, Idr_PutStrOfConcat>(context);
  canon::addPutStrOfEmpty(results, context);
}

void PutListOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addPutListPatterns(results, context);
}

void StrHeadOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_HeadOfCons, Idr_HeadOfShowInt, Idr_HeadOfShowDouble>(context);
}
