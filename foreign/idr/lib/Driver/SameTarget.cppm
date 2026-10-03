// idr.driver:sametarget: whether two triples name one target.
export module idr.driver:sametarget;

import idr.mlir;

export namespace idr::driver {

// Whether code compiled for one triple runs where code for the other does:
// the same architecture, vendor, operating system and its version, and
// environment, however each is spelled. Clang writes the triple it was given
// in its normal form (arm64-apple-macosx14.0 becomes
// arm64-apple-macosx14.0.0), so the spelling is not compared.
bool sameTarget(const llvm::Triple &a, const llvm::Triple &b) {
  return a.getArch() == b.getArch() && a.getSubArch() == b.getSubArch() &&
         a.getVendor() == b.getVendor() && a.getOS() == b.getOS() &&
         a.getOSVersion() == b.getOSVersion() && a.getEnvironment() == b.getEnvironment() &&
         a.getObjectFormat() == b.getObjectFormat();
}

} // namespace idr::driver
