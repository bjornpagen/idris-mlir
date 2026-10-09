// idr.driver:compile: one compilation, the whole chain: the frontend for
// Idris source, the pipeline and LLVM in process, and the link, each timed
// under one root, so that -mlir-timing reports the whole command.
export module idr.driver:compile;

import idr.mlir;

import :artifacts;
import :frontend;
import :link;
import :options;
import :run;

export namespace idr::driver {

// The chain, from the input to the artifacts, which are kept only once
// every step succeeded; an exit status.
int compile(llvm::StringRef frontendPath, Input kind, Artifacts &artifacts) {
  mlir::DefaultTimingManager timings;
  mlir::applyDefaultTimingManagerCLOptions(timings);
  mlir::TimingScope rootTiming = timings.getRootScope();
  if (kind == Input::Idris) {
    mlir::TimingScope frontendTiming = rootTiming.nest("frontend");
    if (int status = frontend(frontendPath, inputPath, artifacts))
      return status;
  }
  if (int status = run(artifacts.modulePath, artifacts.objectPath, rootTiming))
    return status;
  if (!objectOnly) {
    mlir::TimingScope linkTiming = rootTiming.nest("link");
    if (int status = link(artifacts))
      return status;
  }
  artifacts.keep();
  return ok;
}

} // namespace idr::driver
