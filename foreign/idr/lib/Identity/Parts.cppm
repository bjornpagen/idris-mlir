// idr.identity:parts: the parts of a function's argument: the argument
// itself, and what the matches and reads of the function take out of it.
//
// A part is a path from the argument, each step a field of a constructor
// or the predecessor of a natural (the field of its successor, as Idris
// shapes a natural). Two values that take the same path are the same part,
// however each was read: values never change, so a constructor rebuilt from
// the fields one match bound is as good as one rebuilt from another read
// of the same part. A part's depth, its steps below the argument, is what
// makes a recursion on parts end: each step is a strictly smaller value,
// and a value is finite.
export module idr.identity:parts;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::identity {

// The argument, or one step from the part `parent`: field `field` of the
// constructor `ctor` (its name in its declaration), or, with no
// constructor, the predecessor of a natural. `type` is the part's value,
// at no grade.
struct Part {
  unsigned parent = 0;
  StringAttr ctor;
  unsigned field = 0;
  unsigned depth = 0;
  Type type;
};

// The parts of one argument met so far, each once.
class Parts {
public:
  // The argument itself.
  static constexpr unsigned whole = 0;

  explicit Parts(Type argument) { parts.push_back({0, {}, 0, 0, unrestricted(argument)}); }

  const Part &operator[](unsigned part) const { return parts[part]; }

  // Field `index`, of type `type`, of the part `parent` built by `ctor`.
  unsigned field(unsigned parent, StringAttr ctor, unsigned index, Type type) {
    return step(parent, ctor, index, type);
  }

  // The predecessor of the natural `parent`, which is not zero.
  unsigned predecessor(unsigned parent) {
    Type natural = parts[parent].type;
    return step(parent, {}, 0, natural);
  }

private:
  unsigned step(unsigned parent, StringAttr ctor, unsigned index, Type type) {
    auto [it, inserted] = steps.try_emplace(std::make_tuple(parent, ctor, index),
                                            static_cast<unsigned>(parts.size()));
    if (inserted) {
      Part next{parent, ctor, index, parts[parent].depth + 1, unrestricted(type)};
      parts.push_back(next);
    }
    return it->second;
  }

  SmallVector<Part> parts;
  DenseMap<std::tuple<unsigned, StringAttr, unsigned>, unsigned> steps;
};

} // namespace idr::identity
