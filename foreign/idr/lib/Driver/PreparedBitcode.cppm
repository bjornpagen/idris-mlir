// idr.driver:preparedbitcode: the prepared runtime's bitcode.
export module idr.driver:preparedbitcode;

import idr.mlir;

import :besideobject;
import :options;

export namespace idr::driver {

// The prepared runtime's bitcode, where its container keeps it: a bitcode
// file is itself; an object, of any format LLVM's object reader knows,
// holds it in the section the container names, or, with none named, the
// file beside it does.
llvm::Expected<llvm::MemoryBufferRef> preparedBitcode(llvm::MemoryBufferRef file,
                                                      std::unique_ptr<llvm::MemoryBuffer> &beside) {
  if (llvm::identify_magic(file.getBuffer()) == llvm::file_magic::bitcode)
    return file;
  if (runtimeBitcodeSection.empty()) {
    std::string path = besideObject(runtimePath);
    auto read = llvm::MemoryBuffer::getFile(path, /*IsText=*/false,
                                            /*RequiresNullTerminator=*/false);
    if (!read)
      return llvm::createStringError(read.getError(), "cannot read " + path);
    beside = std::move(*read);
    return beside->getMemBufferRef();
  }
  auto object = llvm::object::ObjectFile::createObjectFile(file);
  if (!object)
    return object.takeError();
  for (const llvm::object::SectionRef &section : (*object)->sections()) {
    llvm::Expected<llvm::StringRef> name = section.getName();
    if (!name)
      return name.takeError();
    if (*name != runtimeBitcodeSection)
      continue;
    llvm::Expected<llvm::StringRef> contents = section.getContents();
    if (!contents)
      return contents.takeError();
    return llvm::MemoryBufferRef(*contents, file.getBufferIdentifier());
  }
  return llvm::createStringError("the object has no section " + runtimeBitcodeSection);
}

} // namespace idr::driver
