# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# cmake -DARCHIVES=<path>;... -DOUTPUT=... -P RuntimeDigest.cmake: the unit
# that lists each runtime archive the build made, by its file's name and
# the SHA-256 digest of the file, as idr::driver::builtArchives
# (idr/Driver/BuiltRuntime.h) answers it.
set(entries "")
foreach(archive IN LISTS ARCHIVES)
	file(SHA256 "${archive}" digest)
	get_filename_component(name "${archive}" NAME)
	string(APPEND entries "      {\"${name}\", \"${digest}\"},\n")
endforeach()
file(CONFIGURE OUTPUT "${OUTPUT}" CONTENT [=[
// Generated from the runtime's archives by RuntimeDigest.cmake. Do not edit.
#include "idr/Driver/BuiltRuntime.h"

llvm::ArrayRef<idr::driver::BuiltArchive> idr::driver::builtArchives() {
  static constexpr BuiltArchive archives[] = {
@entries@  };
  return archives;
}
]=] @ONLY)
