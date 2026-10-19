# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
build:
	.toolchain/cmake/bin/cmake --preset dev
	.toolchain/cmake/bin/cmake --build --preset dev
	cd compiler && ../.toolchain/idris2/bin/idris2 --build compiler.ipkg
	echo "the presets run ninja and clang++ for us"
