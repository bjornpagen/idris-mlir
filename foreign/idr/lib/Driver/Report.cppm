// idr.driver:report: every diagnostic idris-mlir prints of its own. One shape: the
// tool's name, the message, a newline. The exit status is the caller's; a
// signal handler cannot use this, and writes the same words itself.
export module idr.driver:report;

import idr.mlir;

export namespace idr::driver {

// `idris-mlir: <what is streamed>`, then a newline. A temporary lives for
// the whole statement, so the newline follows the last piece.
struct Report {
  Report() { llvm::errs() << "idris-mlir: "; }
  ~Report() { llvm::errs() << '\n'; }
  Report(const Report &) = delete;
  Report &operator=(const Report &) = delete;

  template <typename T>
  Report &operator<<(const T &value) {
    llvm::errs() << value;
    return *this;
  }
};

// `idris-mlir: cannot write <path>: <reason>`. `path` is whatever the
// call streamed before: a string, a path, the output option.
template <typename Path>
void cannotWrite(const Path &path, const std::error_code &error) {
  Report() << "cannot write " << path << ": " << error.message();
}

} // namespace idr::driver
