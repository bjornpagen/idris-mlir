// idr.support:taggedaction: an action of MLIR's action framework whose only
// distinction is its tag. The passes that count or skip a transform
// (perform) each name one; the identity, the printing and the TypeID are
// this.
export module idr.support:taggedaction;

import idr.mlir;

export namespace idr::support {

// An action named `Derived::tag`. The TypeID is owned here, one per action:
// MLIR finds it by `resolveTypeID`, and a module type has no implicit id
// that stays unique where the action is built.
template <typename Derived>
struct TaggedAction : mlir::tracing::ActionImpl<Derived> {
  using mlir::tracing::ActionImpl<Derived>::ActionImpl;

  static mlir::TypeID resolveTypeID() {
    static mlir::SelfOwningTypeID id;
    return id;
  }

  void print(llvm::raw_ostream &os) const override { os << '`' << Derived::tag << '`'; }
};

} // namespace idr::support
