// idr.specialize:renumber: numbering a pattern's holes.
export module idr.specialize:renumber;

import idr.mlir;

import :pattern;

export namespace idr::specialize {

// `pattern` with its holes numbered from `next`, which advances past them.
void renumber(Pattern &pattern, unsigned &next) {
  std::visit(Match{[&](Hole &hole) { hole.index = next++; }, [](Constant &) {},
                   [&](Con &con) {
                     for (Pattern &field : con.fields)
                       renumber(field, next);
                   },
                   [&](Closure &closure) {
                     for (Pattern &capture : closure.captures)
                       renumber(capture, next);
                   },
                   [&](Linear &linear) { renumber(linear.value.front(), next); }},
             pattern.node);
}

} // namespace idr::specialize
