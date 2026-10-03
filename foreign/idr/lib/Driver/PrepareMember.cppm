// idr.driver:preparemember: a member of the runtime, readied to join a
// program.
export module idr.driver:preparemember;

import idr.mlir;

import :markannotated;
import :options;
import :sametarget;

export namespace idr::driver {

// The runtime is constant-initialized, and its `used` markers exist
// for separate compilation only. LinkOnlyNeeded always links appending
// globals, so constructors would run in every program, and `used` would keep
// dead runtime code (and its libc calls) in every executable: constructors are
// rejected, `used` markers dropped. Annotations become marks, then are
// dropped too. Prepared bitcode passes through unchanged: it is a member
// that was prepared already.
bool prepareMember(llvm::Module &member, llvm::StringRef name) {
  if (!sameTarget(member.getTargetTriple(), llvm::Triple(targetTriple))) {
    llvm::errs() << "idris-mlir-cc: runtime member " << name << " is compiled for "
                 << member.getTargetTriple().str() << ", and programs for " << targetTriple
                 << "\n";
    return false;
  }
  markAnnotated(member);
  if (llvm::GlobalVariable *annotations = member.getNamedGlobal("llvm.global.annotations"))
    annotations->eraseFromParent();
  // An empty list of constructors, which clang writes for some translation
  // units, lists none.
  for (llvm::StringRef array : {"llvm.global_ctors", "llvm.global_dtors"})
    if (llvm::GlobalVariable *global = member.getNamedGlobal(array)) {
      if (llvm::cast<llvm::ArrayType>(global->getValueType())->getNumElements() == 0) {
        global->eraseFromParent();
        continue;
      }
      llvm::errs() << "idris-mlir-cc: runtime member " << name
                   << " has static constructors or destructors; the runtime must be "
                      "constant-initialized\n";
      return false;
    }
  for (llvm::StringRef array : {"llvm.used", "llvm.compiler.used"})
    if (llvm::GlobalVariable *global = member.getNamedGlobal(array))
      global->eraseFromParent();
  for (const llvm::GlobalVariable &global : member.globals())
    if (global.hasAppendingLinkage()) {
      llvm::errs() << "idris-mlir-cc: unsupported (runtime): runtime member " << name
                   << " defines the appending global " << global.getName() << "\n";
      return false;
    }
  return true;
}

} // namespace idr::driver
