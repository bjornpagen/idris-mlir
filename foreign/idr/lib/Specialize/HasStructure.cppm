// idr.specialize:hasstructure: whether a pattern has structure.
export module idr.specialize:hasstructure;

import idr.mlir;
import idr.dialect;

import :pattern;

using namespace mlir;

export namespace idr::specialize {

// Whether `pattern` has structure: a constructor or a closure, as a node
// or as a constant. A lone scalar is none: a number specialized on would
// make a clone per value, where LLVM weighs constant arguments better.
bool hasStructure(const Pattern &pattern) {
  return std::visit(Match{[](const Hole &) { return false; },
                          [](const Constant &c) { return isa<ConAttr, ClosureAttr>(c.value); },
                          [](const Con &) { return true; }, [](const Closure &) { return true; },
                          [](const Linear &l) { return hasStructure(l.value.front()); }},
                    pattern.node);
}

} // namespace idr::specialize
