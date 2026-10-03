// idr.driver:members: the members of the runtime archive, and their bitcode.
export module idr.driver:members;

import idr.mlir;

import :options;

export namespace idr::driver {

// One member of the runtime archive, and its bitcode.
struct Member {
  std::string name;
  llvm::MemoryBufferRef bitcode;
};

// Every member of the runtime archive carries its bitcode as the target
// entry's flags compile it (a fat LTO object's section, say), where LLVM's
// object reader finds it whatever the object's format; this is the bitcode
// of each.
bool readMembers(const llvm::MemoryBuffer &archiveBuffer, std::vector<Member> &members) {
  auto archive = llvm::object::Archive::create(archiveBuffer.getMemBufferRef());
  if (!archive) {
    llvm::errs() << "idris-mlir-cc: runtime " << runtimePath << ": "
                 << llvm::toString(archive.takeError()) << "\n";
    return false;
  }
  llvm::Error error = llvm::Error::success();
  for (const llvm::object::Archive::Child &child : (*archive)->children(error)) {
    auto name = child.getName();
    auto buffer = child.getMemoryBufferRef();
    if (!name || !buffer) {
      llvm::errs() << "idris-mlir-cc: runtime " << runtimePath << ": unreadable member\n";
      llvm::consumeError(name.takeError());
      llvm::consumeError(buffer.takeError());
      llvm::consumeError(std::move(error));
      return false;
    }
    auto bitcode = llvm::object::IRObjectFile::findBitcodeInMemBuffer(*buffer);
    if (!bitcode) {
      llvm::errs() << "idris-mlir-cc: runtime member " << *name
                   << " carries no bitcode, which every member of the runtime's archive must: "
                   << llvm::toString(bitcode.takeError()) << "\n";
      llvm::consumeError(std::move(error));
      return false;
    }
    members.push_back({name->str(), *bitcode});
  }
  if (error) {
    llvm::errs() << "idris-mlir-cc: runtime " << runtimePath << ": "
                 << llvm::toString(std::move(error)) << "\n";
    return false;
  }
  return true;
}

} // namespace idr::driver
