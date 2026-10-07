// idr.tail: what becomes of a function's tail positions. A self tail call
// becomes the next iteration of a loop (loops: the while-do form of a body
// that is a decision, whileDo, or the general loop, loop); a self call
// whose result is a field of the constructor a tail returns becomes a tail
// call that writes the field (trmc); a self call a tail adds becomes a tail
// call that carries the sum (accumulator); and a result a function always returns
// as one of its arguments, as such loops and recursions thread a value
// through, is dropped (returned).
export module idr.tail;

export import :accumulator;
export import :decision;
export import :loop;
export import :loops;
export import :reaches;
export import :returned;
export import :trmc;
export import :whileDo;
