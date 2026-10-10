# idris-mlir's commands. GNU make.
#
#   make bootstrap         build the pinned toolchain into .toolchain/ (tools/bootstrap.sh all)
#   make doctor            what the build needs, and what is built
#   make verify-pins       the Idris submodule is at its staged gitlink, unmodified
#   make check             tests/spec: the pins, the commands and the layout;
#                          always, without a build
#   make build             the C++ dev preset, the Idris side's modules of the
#                          dialects (tools/dialects.sh), the fork of Idris's
#                          compiler (compiler/idris), the frontend, and the
#                          frontend's prefix: the packages the pinned Idris
#                          source ships and those in libs/; after any code
#                          change
#   make test              tests/compiler, accept, reject, programs (each program twice: with
#                          its dumps checked, and without compile-time
#                          evaluation), determinism, registry, toolchain, fuzz,
#                          two-levels and bench (each benchmark on a small
#                          input); after compiler changes
#   make test-idr          tests/idr, the idr dialect, with FileCheck; after C++ or
#                          contract changes
#   make test-mlir-tools   tests/upstream, each upstream bug on its reproducer with the
#                          pinned tools; after changing upstream MLIR usage
#   make compile SRC=Main.idr OUT=prog
#                          idris-mlir, through tools/compile.sh
#   make bench             bench/run.sh; ARGS='--runs 3 fib' passes arguments
#
# The test commands run tests/Main.idr, a golden runner that runs each test
# in a process of its own; the whole run ends after 4 hours, so that nothing
# can hold the tree for ever, each command a test runs after 60 s and each
# test after 300 s, or what its run script sets. They take only='NAME...'
# and except='NAME...' (substrings of test paths such as
# programs/basic/hello), threads=N (default: the number of CPUs) and
# INTERACTIVE=--interactive (offer to accept new output). Each ends with the
# number of tests that passed and the list of those that failed, and fails
# if any did.

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
# Where the pinned tools are, from tools/toolchain.sh, which the scripts share.
toolchain = $(shell root='$(ROOT)'; . '$(ROOT)/tools/toolchain.sh'; printf '%s' "$$$(1)")
IDRIS_PREFIX := $(call toolchain,idris_prefix)
IDRIS2 := $(call toolchain,idris2)
CMAKE := $(call toolchain,cmake)
# The C++ build's configure preset (CMakePresets.json, through
# tools/toolchain.sh), the same on every host.
DEV_PRESET := $(call toolchain,dev_preset)
# idris-mlir, the one command, which the tests run; it runs the frontend
# beside it, which `build` links there from where Idris builds it.
COMPILER := $(call toolchain,idris_mlir)
IDRIS_MLIR_FRONT := $(call toolchain,idris_mlir_front)
FRONTEND := $(ROOT)/compiler/build/exec/idris-mlir-front
RUNNER := $(ROOT)/tests/build/exec/runtests
PINS := $(ROOT)/tools/verify-pins.sh

# Two Idris compilers run here, each on its own prefix, never one of
# another's: a TTC is read only by the compiler whose format it is, so a
# prefix is the packages one compiler built. The pinned Idris (IDRIS2) runs
# on its own prefix, IDRIS_PREFIX, which the bootstrap built and every
# checkout shares, where it builds the tests' runner. It installs what this
# checkout builds for it into HOST_PREFIX: the fork of its compiler
# (compiler/idris), which it builds the frontend against, and the packages
# of libs/, which the fork (mlir-linear) and the benchmarks' Chez baseline
# use; it finds them there beside its own prelude and base. The frontend (FRONTEND) reads
# CHECKOUT_PREFIX, which holds only what it built itself: the packages of
# the pinned Idris source (`prefix`) and those of libs/ (`libs`). Every
# command inherits no package path from another installation, and CHEZ is
# the pinned Chez Scheme the pinned Idris was built with
# (tools/verify-pins.sh idris checks that), never one on PATH.
unexport IDRIS2_PATH IDRIS2_PACKAGE_PATH IDRIS2_INC_CGS IDRIS2_INC_SRC IDRIS2_DATA IDRIS2_LIBS IDRIS2_CG IDRIS2_BOOT
CHECKOUT_PREFIX := $(call toolchain,checkout_prefix)
HOST_PREFIX := $(call toolchain,host_prefix)
# idris-mlir and its frontend read no environment: their prefix is an
# argument, by default the one `build` configures, CHECKOUT_PREFIX. What reads
# Idris's environment is upstream's test scripts, whose compiler
# (tests/upstream-idris/as-idris) passes it on as arguments.
export IDRIS2_PREFIX := $(CHECKOUT_PREFIX)
export PATH := $(IDRIS_PREFIX)/bin:$(PATH)
export IDRIS_MLIR_ROOT := $(ROOT)
# The names a test's `targets` file and expected.<name> files give this
# host (tools/host.sh), which the runner (tests/Main.idr) reads when it
# builds its pools, and tests/runner/one.sh when it picks an expectation.
export IDRIS_MLIR_HOST_NAMES := $(call toolchain,host_names)
export CHEZ := $(call toolchain,chez_scheme)

threads ?= $(shell nproc 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null || echo 1)
only ?=
except ?=
INTERACTIVE ?=
GOLDEN = --threads $(threads) $(INTERACTIVE) --only '$(only)' --except '$(except)'
# A runner that hangs fails instead of holding the tree's lock; without
# coreutils' timeout (tools/host.sh) no test command runs.
TIMEOUT := $(call toolchain,timeout_cmd)
TIMEOUT_MISSING := $(call toolchain,timeout_missing)
RUN_TESTS = $(or $(TIMEOUT),$(error $(TIMEOUT_MISSING))) -k 10 14400 $(RUNNER) $(COMPILER)

.PHONY: help bootstrap doctor verify-pins env check build fork frontend prefix libs host-libs \
        test test-idr test-mlir-tools runner compile bench
.DEFAULT_GOAL := help

# `make` alone lists the commands: the comment that starts this file.
help:
	@sed -n '/^#/!q; s/^# \{0,1\}//p' $(ROOT)/Makefile

bootstrap:
	$(ROOT)/tools/bootstrap.sh all

doctor:
	@$(ROOT)/tools/doctor.sh

verify-pins:
	@$(PINS)

# The environment the commands run in.
env:
	@env | grep -E '^(IDRIS2_[A-Z_]*|CHEZ|IDRIS_MLIR_ROOT)=' | sort

# The presets are the only interface for building C++. idris-mlir's
# default prefix is CHECKOUT_PREFIX, the one `prefix` and `libs` build,
# whatever it is set to here. The frontend is linked beside idris-mlir,
# where idris-mlir runs it, and its prefix comes after the frontend, which
# builds it: one make after the other, so that no parallel make builds the
# prefix with a frontend older than the fork.
build:
	@$(PINS) cmake ninja llvm sysroot
	cd $(ROOT) && $(CMAKE) --preset $(DEV_PRESET) -DIDRIS_MLIR_IDRIS_PREFIX='$(CHECKOUT_PREFIX)'
	cd $(ROOT) && $(CMAKE) --build --preset $(DEV_PRESET)
	@$(PINS) idris
	$(ROOT)/tools/dialects.sh generate
	@$(MAKE) --no-print-directory frontend
	ln -sfn '$(FRONTEND)' '$(IDRIS_MLIR_FRONT)'
	@$(MAKE) --no-print-directory libs

# The pinned Idris's directory of packages under a prefix, where it installs
# a package and finds one (<prefix>/idris2-<version>), in a recipe's shell.
libdir = $$(IDRIS2_PREFIX='$(1)' '$(IDRIS2)' --libdir)

# install COMMAND,PREFIX,SOURCES: each package directory of SOURCES, named
# as its .ipkg, installed into PREFIX by COMMAND (a compiler with its
# environment), in order, as each may need the ones before. Each is built
# from nothing in a copy beside the prefix, PREFIX-src: the sources it is
# built from are only read, and a build directory beside them may hold
# another compiler's TTCs, or the same compiler's from before the fork
# changed. A package's earlier installation is removed first, so that no
# module it has dropped stays installed.
install = packages=$$($(1) --libdir) && mkdir -p '$(2)-src' && \
	for source in $(3); do \
	  name=$$(basename "$$source") && copy='$(2)-src'/"$$name" && \
	  rm -rf "$$packages/$$name"-[0-9]* "$$copy" && \
	  cp -R "$$source" "$$copy" && rm -rf "$$copy/build" && \
	  (cd "$$copy" && $(1) --install "$$name.ipkg") || exit 1; \
	done

# The fork of Idris's compiler, built by the pinned Idris and installed for
# it into HOST_PREFIX, never into the pinned prefix, which every checkout
# shares; its prelude and base are the pinned prefix's, and its
# mlir-linear (the growable arrays of its tables) the one `host-libs`
# installs beside it. Again whenever a file of the fork or of those
# packages changes, its package removed first, so that no module the fork
# has dropped stays installed.
FORK_SOURCES := $(ROOT)/compiler/idris/idris-compiler.ipkg $(shell find '$(ROOT)/compiler/idris/src' -name '*.idr' 2> /dev/null)
FORK_STAMP := $(HOST_PREFIX)/$(call toolchain,fork_stamp)
HOST_LIBS_STAMP := $(HOST_PREFIX)/$(call toolchain,host_libs_stamp)
fork: $(FORK_STAMP)
$(FORK_STAMP): $(FORK_SOURCES) $(HOST_LIBS_STAMP) $(wildcard $(IDRIS_PREFIX)/provenance.json)
	@$(PINS) idris
	@mkdir -p '$(HOST_PREFIX)' && packages="$(call libdir,$(HOST_PREFIX))" && rm -rf "$$packages"/idris-compiler-*
	cd $(ROOT)/compiler/idris && export IDRIS2_PREFIX='$(HOST_PREFIX)' IDRIS2_PACKAGE_PATH="$(call libdir,$(IDRIS_PREFIX))" && \
	  $(IDRIS2) --install idris-compiler.ipkg
	@touch $@

# The frontend, by the pinned Idris, against the fork (HOST_PREFIX) and the
# pinned prelude and base. Beside it, syntax-samples (base only), which
# writes one sample of every type and attribute of the generated syntax for
# tests/compiler/dialect-syntax.
frontend: fork
	@$(PINS) idris
	cd $(ROOT)/compiler && export IDRIS2_PREFIX='$(IDRIS_PREFIX)' IDRIS2_PACKAGE_PATH="$(call libdir,$(HOST_PREFIX))" && \
	  $(IDRIS2) --build idris-mlir.ipkg && $(IDRIS2) --build syntax-samples.ipkg

# The frontend's prefix, CHECKOUT_PREFIX: the packages the pinned Idris
# source ships (its Makefile's IDRIS2_LIBRARIES, in their order: prelude,
# base, and the others, which a program that asks for one is refused by
# name), each built and installed by the frontend. The fork decides what a
# TTC holds, so the prefix is made again from nothing when the fork
# changes, by a frontend built since.
IDRIS_SOURCE := $(ROOT)/third_party/Idris2
IDRIS_LIBS := $(shell sed -n 's/^IDRIS2_LIBRARIES[[:space:]]*=//p' '$(IDRIS_SOURCE)/Makefile' 2> /dev/null)
PREFIX_STAMP := $(CHECKOUT_PREFIX)/$(call toolchain,prefix_stamp)
prefix: $(PREFIX_STAMP)
$(PREFIX_STAMP): $(FORK_STAMP)
	@$(PINS) source
	@[ '$(FRONTEND)' -nt '$(FORK_STAMP)' ] || \
	  { echo 'error: $(FRONTEND) was not built since the fork was installed; run: make build' >&2; exit 1; }
	@rm -rf '$(CHECKOUT_PREFIX)' '$(CHECKOUT_PREFIX)-src' && mkdir -p '$(CHECKOUT_PREFIX)'
	$(call install,'$(FRONTEND)' --prefix '$(CHECKOUT_PREFIX)',$(CHECKOUT_PREFIX),$(addprefix $(IDRIS_SOURCE)/libs/,$(IDRIS_LIBS)))
	@touch $@

# The packages this compiler ships (libs/), installed by the frontend into
# its prefix (-p mlir-linear), again whenever one of their sources changes.
SHIPPED := $(patsubst %/,%,$(wildcard $(ROOT)/libs/*/))
SHIPPED_SOURCES := $(shell find $(SHIPPED) -name build -prune -o \( -name '*.idr' -o -name '*.ipkg' \) -print 2> /dev/null)
LIBS_STAMP := $(CHECKOUT_PREFIX)/$(call toolchain,libs_stamp)
libs: $(LIBS_STAMP)
$(LIBS_STAMP): $(PREFIX_STAMP) $(SHIPPED_SOURCES)
	$(call install,'$(FRONTEND)' --prefix '$(CHECKOUT_PREFIX)',$(CHECKOUT_PREFIX),$(SHIPPED))
	@touch $@

# The packages of libs/ for the pinned Idris too, installed into
# HOST_PREFIX: the fork depends on mlir-linear, and the benchmarks' Chez
# baseline compiles the programs that use them. Again whenever one of
# their sources changes.
host-libs: $(HOST_LIBS_STAMP)
$(HOST_LIBS_STAMP): $(wildcard $(IDRIS_PREFIX)/provenance.json) $(SHIPPED_SOURCES)
	@$(PINS) idris
	@mkdir -p '$(HOST_PREFIX)'
	$(call install,IDRIS2_PREFIX='$(HOST_PREFIX)' IDRIS2_PACKAGE_PATH="$(call libdir,$(IDRIS_PREFIX))" '$(IDRIS2)',$(HOST_PREFIX),$(SHIPPED))
	@touch $@

# Every test command rebuilds the runner while other runs may be using it.
# So it is built aside, in build/stage, one build at a time (a mkdir
# mutex, tools/host.sh), and installed by renaming each file over the old
# one: a running runner keeps the files it started with, which rewriting
# them in place would corrupt under it. The files are the launcher and
# whatever the Chez backend put beside it, its support library named as
# the host names one (.so, .dylib). The pinned Idris builds it on its own
# prefix, whose contrib and test it uses.
runner:
	@$(PINS) idris
	cd $(ROOT)/tests && mkdir -p build/exec/runtests_app && . $(ROOT)/tools/host.sh && \
	export IDRIS2_PREFIX='$(IDRIS_PREFIX)' && with_lock build/.runner.mutex sh -c ' \
	  $(IDRIS2) --build-dir build/stage --build tests.ipkg || exit 1; \
	  cd build/stage/exec && for file in runtests runtests_app/*; do \
	    cp -p $$file ../../exec/$$file.new.$$$$ && \
	      mv -f ../../exec/$$file.new.$$$$ ../../exec/$$file || exit 1; \
	  done'

check: runner
	cd $(ROOT)/tests && $(RUN_TESTS) --suite check $(GOLDEN)

test: runner libs
	@$(PINS) built llvm sysroot
	cd $(ROOT)/tests && $(RUN_TESTS) --suite test $(GOLDEN)

test-idr: runner
	@$(PINS) built llvm test-tools sysroot
	cd $(ROOT)/tests && $(RUN_TESTS) --suite test-idr $(GOLDEN)

# Idris's bug is checked through the frontend, whose fork of Idris's
# compiler carries the fix, so the suite needs it and its prefix.
test-mlir-tools: runner libs
	@$(PINS) built llvm sysroot
	cd $(ROOT)/tests && $(RUN_TESTS) --suite test-mlir-tools $(GOLDEN)

compile:
	@test -n '$(SRC)' && test -n '$(OUT)' || { echo 'usage: make compile SRC=Main.idr OUT=prog' >&2; exit 2; }
	@$(PINS) built idris prefix sysroot
	@$(ROOT)/tools/compile.sh '$(abspath $(SRC))' '$(abspath $(OUT))'

bench: libs host-libs
	@$(PINS) built idris prefix sysroot
	$(ROOT)/bench/run.sh $(ARGS)
