# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# What any library may use and that names nothing of the dialect: the
# actions a pass performs, and the profile instrumentation, which records
# nothing until a tool starts a trace, and names LLVM's passes and the
# functions and modules they run on (LLVM's Core). It links nothing of the
# dialect, so it reads none of the dialect's precompiled header either.
add_mlir_library(IdrSupport
	Actions.cpp
	Profile.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	LINK_COMPONENTS
	Core

	LINK_LIBS PUBLIC
	MLIRIR
	MLIRPass
	MLIRSupport
)
