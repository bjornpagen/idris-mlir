# idris-mlir's commands. GNU make.
#
#   make bootstrap         build the pinned toolchain into .toolchain/ (tools/bootstrap.sh all)
#   make doctor            what the build needs, and what is built
#   make verify-pins       the Idris submodule is at its staged gitlink, unmodified
#   make check             tests/spec: the pins, the commands and the layout;
#                          always, without a build
#   make build             the C++ dev preset, the packages in libs/, the Idris
#                          side's modules of the dialects (tools/dialects.sh)
#                          and the Idris compiler; after any code change
#   make test              tests/compiler, accept, reject, programs (each program twice: with
#                          its dumps checked, and without compile-time
#                          evaluation), determinism, registry, toolchain, fuzz,
#                          two-levels and bench (each benchmark on a small
#                          input); after compiler changes
#   make test-idr          tests/idr, the idr dialect, with FileCheck; after C++ or
#                          contract changes
#   make test-mlir-tools   tests/upstream, the upstream bugs still reproduce with the
#                          pinned tools; after changing upstream MLIR usage
#   make compile SRC=Main.idr OUT=prog
#   make bench             bench/run.sh; ARGS='--runs 3 fib' passes arguments
#
# The test commands run tests/Main.idr, a golden runner that runs each test
# in a process of its own; the whole run ends after 4 hours (times
# time_scale), so that nothing can hold the tree for ever. They
# take only='NAME...' and except='NAME...' (substrings of test paths such as
# programs/basic/hello), threads=N (default: the number of CPUs),
# INTERACTIVE=--interactive (offer to accept new output) and time_scale=N
# (multiplies every timeout: each command a test runs gets 60 s
# and each test 300 s, or what its run script sets). Each ends with the
# number of tests that passed and the list of those that failed, and fails
# if any did.

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
# Where the pinned tools are, from tools/toolchain.sh, which the scripts share.
toolchain = $(shell root='$(ROOT)'; . '$(ROOT)/tools/toolchain.sh'; printf '%s' "$$$(1)")
IDRIS_PREFIX := $(call toolchain,idris_prefix)
IDRIS2 := $(call toolchain,idris2)
CMAKE := $(call toolchain,cmake)
PINNED_CC := $(call toolchain,pinned_cc)
IDRIS_MLIR_CC := $(call toolchain,idris_mlir_cc)
COMPILER := $(ROOT)/compiler/build/exec/idris-mlir
PATHS_MODULE := $(ROOT)/compiler/src/IdrisMLIR/Frontend/Paths.idr
RUNNER := $(ROOT)/tests/build/exec/runtests
PINS := $(ROOT)/tools/verify-pins.sh

# Every command runs the pinned Idris, and no package path inherited from
# another installation. Its prefix is this checkout's own (`prefix`), so
# that the packages of libs/ it finds are this checkout's. CHEZ is the Chez
# Scheme it was built with.
unexport IDRIS2_PATH IDRIS2_PACKAGE_PATH IDRIS2_INC_CGS IDRIS2_INC_SRC IDRIS2_DATA IDRIS2_LIBS IDRIS2_CG IDRIS2_BOOT
CHECKOUT_PREFIX := $(call toolchain,checkout_prefix)
export IDRIS2_PREFIX := $(CHECKOUT_PREFIX)
export PATH := $(IDRIS_PREFIX)/bin:$(PATH)
export IDRIS_MLIR_ROOT := $(ROOT)
STAMPED_CHEZ := $(shell root='$(ROOT)'; . '$(ROOT)/tools/toolchain.sh'; stamp_field "$$idris_prefix" scheme)
ifneq ($(STAMPED_CHEZ),)
export CHEZ := $(STAMPED_CHEZ)
endif

threads ?= $(shell nproc 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null || echo 1)
only ?=
except ?=
INTERACTIVE ?=
time_scale ?= 1
export IDRIS_MLIR_TIME_SCALE := $(time_scale)
GOLDEN = --threads $(threads) $(INTERACTIVE) --only '$(only)' --except '$(except)'
# A runner that hangs fails instead of holding the tree's lock.
RUN_TESTS = timeout -k 10 $(shell echo $$(( 14400 * $(time_scale) ))) $(RUNNER) $(COMPILER)

.PHONY: help bootstrap doctor verify-pins env check build prefix libs paths test test-idr \
        test-mlir-tools runner compile bench
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

# The presets are the only interface for building C++.
build: libs
	@$(PINS) cmake ninja llvm sysroot
	cd $(ROOT) && $(CMAKE) --preset dev
	cd $(ROOT) && $(CMAKE) --build --preset dev
	@$(PINS) idris
	@$(MAKE) --no-print-directory paths
	$(ROOT)/tools/dialects.sh generate
	cd $(ROOT)/compiler && $(IDRIS2) --build idris-mlir.ipkg

# This checkout's Idris prefix, build/idris2: every entry of the pinned
# prefix linked, except the packages this compiler ships (libs/), which
# `libs` installs here. The pinned prefix is shared by every checkout of the
# repository (a worktree links .toolchain), so a package installed there
# would be whichever checkout installed last. Made again after a bootstrap.
SHIPPED := $(notdir $(patsubst %/,%,$(wildcard $(ROOT)/libs/*/)))
PREFIX_STAMP := $(CHECKOUT_PREFIX)/.linked
prefix: $(PREFIX_STAMP)
$(PREFIX_STAMP): $(wildcard $(IDRIS_PREFIX)/provenance.json)
	@$(PINS) idris
	@rm -rf '$(CHECKOUT_PREFIX)' && mkdir -p '$(CHECKOUT_PREFIX)' && \
	for top in '$(IDRIS_PREFIX)'/*; do \
	  case $${top##*/} in \
	    idris2-*) mkdir '$(CHECKOUT_PREFIX)'/"$${top##*/}" || exit 1; \
	      for entry in "$$top"/*; do \
	        shipped=no; \
	        for lib in $(SHIPPED); do case $${entry##*/} in "$$lib"-*) shipped=yes ;; esac; done; \
	        [ $$shipped = yes ] || ln -s "$$entry" '$(CHECKOUT_PREFIX)'/"$${top##*/}"/ || exit 1; \
	      done ;; \
	    *) ln -s "$$top" '$(CHECKOUT_PREFIX)'/ || exit 1 ;; \
	  esac; \
	done
	@touch $@

# The packages this compiler ships (libs/), installed into this checkout's
# prefix, where the pinned Idris's backend and this compiler find them alike
# (-p mlir-linear), again whenever one of their sources changes.
LIBS_STAMP := $(CHECKOUT_PREFIX)/.libs-installed
libs: $(LIBS_STAMP)
$(LIBS_STAMP): $(PREFIX_STAMP) $(wildcard $(ROOT)/libs/mlir-linear/*.ipkg $(ROOT)/libs/mlir-linear/Linear/*.idr)
	@$(PINS) idris
	cd $(ROOT)/libs/mlir-linear && $(IDRIS2) --install mlir-linear.ipkg
	@touch $@

# The -o path runs the tools recorded here, never PATH, links the runtime
# idris-mlir-cc reads, and links for the target it compiles for with the
# arguments it prints (--print-link-flags), each an Idris string.
paths:
	@runtime=$$('$(IDRIS_MLIR_CC)' --print-runtime) && \
	printed=$$('$(IDRIS_MLIR_CC)' --print-link-flags) && \
	flags=$$(printf '%s\n' "$$printed" | sed 's/[\\"]/\\&/g; s/.*/"&"/' | paste -sd, -) && { printf '%s\n' \
	    '||| Generated by make build: the pinned tools the -o path runs, the' \
	    '||| runtime idris-mlir-cc reads, which every executable links, and what' \
	    '||| links an executable for the target it compiles for, after its object,' \
	    '||| the runtime and -o. Do not edit.' \
	    'module IdrisMLIR.Frontend.Paths' '' \
	    'export' 'idrisMlirCc : String' 'idrisMlirCc = "$(IDRIS_MLIR_CC)"' '' \
	    'export' 'pinnedCc : String' 'pinnedCc = "$(PINNED_CC)"' '' \
	    'export' 'runtime : String' "runtime = \"$$runtime\"" '' \
	    'export' 'linkFlags : List String' "linkFlags = [$$flags]"; } > '$(PATHS_MODULE).new'
	@if cmp -s '$(PATHS_MODULE).new' '$(PATHS_MODULE)'; then \
	    rm '$(PATHS_MODULE).new'; else mv '$(PATHS_MODULE).new' '$(PATHS_MODULE)'; fi

# Every test command rebuilds the runner while other runs may be using it.
# So it is built aside, in build/stage, one build at a time, and installed
# by renaming each file over the old one: a running runner keeps the files
# it started with, which rewriting them in place would corrupt under it.
RUNNER_FILES = runtests runtests_app/runtests.so runtests_app/runtests.ss \
               runtests_app/libidris2_support.so runtests_app/compileChez
runner: prefix
	@$(PINS) idris
	cd $(ROOT)/tests && mkdir -p build/exec/runtests_app && flock build/.runner.lock sh -c ' \
	  $(IDRIS2) --build-dir build/stage --build tests.ipkg || exit 1; \
	  for file in $(RUNNER_FILES); do \
	    cp -p build/stage/exec/$$file build/exec/$$file.new.$$$$ && \
	      mv -f build/exec/$$file.new.$$$$ build/exec/$$file || exit 1; \
	  done'

check: runner
	cd $(ROOT)/tests && $(RUN_TESTS) --suite check $(GOLDEN)

test: runner libs
	@$(PINS) built llvm sysroot
	cd $(ROOT)/tests && $(RUN_TESTS) --suite test $(GOLDEN)

test-idr: runner
	@$(PINS) built llvm test-tools sysroot
	cd $(ROOT)/tests && $(RUN_TESTS) --suite test-idr $(GOLDEN)

test-mlir-tools: runner
	@$(PINS) llvm sysroot
	cd $(ROOT)/tests && $(RUN_TESTS) --suite test-mlir-tools $(GOLDEN)

compile:
	@test -n '$(SRC)' && test -n '$(OUT)' || { echo 'usage: make compile SRC=Main.idr OUT=prog' >&2; exit 2; }
	@$(PINS) built idris sysroot
	@$(ROOT)/tools/compile.sh '$(abspath $(SRC))' '$(abspath $(OUT))'

bench: libs
	@$(PINS) built idris sysroot
	$(ROOT)/bench/run.sh $(ARGS)
