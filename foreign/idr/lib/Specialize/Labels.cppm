// idr.specialize:labels: the closure labels a pattern names.
export module idr.specialize:labels;

import idr.mlir;
import idr.dialect;

import :pattern;

using namespace mlir;

export namespace idr::specialize {

// The functions `pattern` names as closure labels.
void labels(const Pattern &pattern, llvm::SmallVectorImpl<mlir::FlatSymbolRefAttr> &out) {
  std::visit(Match{[](const Hole &) {},
                   [&](const Constant &c) {
                     Attribute(c.value).walk(
                         [&](ClosureAttr closure) { out.push_back(closure.getCallee()); });
                   },
                   [&](const Con &con) {
                     for (const Pattern &field : con.fields)
                       labels(field, out);
                   },
                   [&](const Closure &closure) {
                     out.push_back(closure.callee);
                     for (const Pattern &capture : closure.captures)
                       labels(capture, out);
                   },
                   [&](const Linear &linear) { labels(linear.value.front(), out); }},
             pattern.node);
}

} // namespace idr::specialize
