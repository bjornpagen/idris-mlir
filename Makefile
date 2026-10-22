# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# idris-mlir's commands. GNU make.
#
#   make bootstrap         build the pinned toolchain into .toolchain/ (tools/bootstrap.sh all)
#   make doctor            what the build needs, and what is built
#   make verify-pins       the Idris submodule is at its staged gitlink, unmodified
#   make check             the tests of the repository (their `suite` file names
#                          check): the pins, the commands and the layout,
#                          the specification's generated files among them;
#                          and the checker's generated modules against
#                          knowngen (compiler/checker/known); always,
#                          without a build
#   make build             the C++ dev preset (PRESET=release or lint
#                          for another), the Idris side's modules of the
#                          dialects (tools/dialects.sh), the type checker
#                          (compiler/checker), the frontend, and the
#                          frontend's prefix: the packages the pinned Idris
#                          source ships and those in libs/; after any code
#                          change
#   make test              the compiled programs (each compiled once, with its
#                          dumps checked), the programs refused by one rule,
#                          and the scripts of the compiler, the runtime, the
#                          toolchain, the fuzzer and the benchmarks (each on a
#                          small input); after compiler changes
#   make test-idr          the dialect fixtures, the idr dialect with FileCheck
#                          and idr-expect; after C++ or contract changes
#   make test-mlir-tools   the tests whose `suite` file names it: each upstream bug
#                          on its reproducer with the pinned tools; after
#                          changing upstream MLIR usage
#   make test-unit         foreign/idr/unittests, the exhaustive boxes (googletest);
#                          after C++ changes, once make build has built them
#   make compile SRC=Main.idr OUT=prog
#                          idris-mlir, through tools/compile.sh
#   make bench             bench/run.sh; ARGS='--runs 3 fib' passes arguments
#   make self              the frontend compiled by itself (tools/self.sh): stages 1, 2
#                          and 3, stage 2 the same as stage 3, on the release build,
#                          which it makes first
#   make typecheck         whether the code compiles, without stage 2: foreign/idr by the
#                          host's clang against a TableGen-only LLVM/MLIR
#                          (tools/bootstrap.sh typecheck; nothing linked but
#                          idris-mlir-tblgen), the Idris side's modules of the
#                          dialects from it, and the Idris typecheck of
#                          libs/, the checker and the frontend; each part's log
#                          is in build/typecheck/logs, the C++ errors one per
#                          line in build/typecheck/errors.log
#
# Until a target's entry in CMakeLists.txt holds its measured stack sizes
# (IDRIS_MLIR_TOOL_STACK_BYTES, IDRIS_MLIR_TOOL_SIGNAL_BYTES,
# IDRIS_MLIR_OUTSIDE_STACK_BYTES), the C++ build's configure refuses, and
# the build that measures them, like every build before, is given
# provisional sizes, each -D<name>=<bytes>:
#   - make build: configure the preset once by hand, from the root, with
#     the pinned CMake, `cmake --preset <preset>
#     -DIDRIS_MLIR_IDRIS_PREFIX=<CHECKOUT_PREFIX> -D<name>=<bytes>...`;
#     make build configures without --fresh, so the build directory's cache
#     keeps them;
#   - make typecheck, whose configure is --fresh and drops the cache: a
#     preset of one's own in CMakeUserPresets.json, which no checkout
#     tracks, that inherits typecheck, keeps its binaryDir
#     (${sourceDir}/build/typecheck) and sets the three as cacheVariables,
#     with a build preset of the same name; then
#     `make typecheck TYPECHECK_PRESET=<name>`. A preset gives its cache
#     variables at every configure.
# The comment above the target entries says what is measured.
#
# The test commands run harness/Main.idr, a golden runner over tests/,
# where every test is one directory at one level, and its kind is what it
# holds (harness/README.md). It plans the runs and tallies them, and
# harness/runs.sh runs each test in a process of its own between the two;
# the whole run ends after 4 hours, so that nothing can hold the tree for
# ever, each command a test runs after 60 s and each test after 300 s, or
# what its run script sets. They take only='NAME...' and except='NAME...'
# (substrings of test names such as hello), and run NCPU tests at once
# (the one CPU budget below). Each ends with the number of tests that
# passed of those selected, the tests not run on this host, and the tests
# that failed or gave no verdict, and fails if any did.

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
# Where the pinned tools are, from tools/toolchain.sh, which the scripts share.
toolchain = $(shell root='$(ROOT)'; . '$(ROOT)/tools/toolchain.sh'; printf '%s' "$$$(1)")
IDRIS_PREFIX := $(call toolchain,idris_prefix)
IDRIS2 := $(call toolchain,idris2)
CMAKE := $(call toolchain,cmake)
# The C++ build's configure preset (CMakePresets.json, through
# tools/toolchain.sh), the same on every host; `make build PRESET=<name>`
# builds another of CMakePresets.json's, in build/<name>, through the same
# compiler cache.
DEV_PRESET := $(call toolchain,dev_preset)
PRESET := $(DEV_PRESET)
# idris-mlir, the one command, which the tests run; it runs the frontend
# beside it, which `build` links there from where Idris builds it.
COMPILER := $(call toolchain,idris_mlir)
FRONTEND := $(ROOT)/compiler/build/exec/idris-mlir-front
RUNNER := $(ROOT)/harness/build/exec/runtests
PINS := $(ROOT)/tools/verify-pins.sh

# Two Idris compilers run here, each on its own prefix, never one of
# another's: a TTC is read only by the compiler whose format it is, so a
# prefix is the packages one compiler built. The pinned Idris (IDRIS2) runs
# on its own prefix, IDRIS_PREFIX, which the bootstrap built and every
# checkout shares, where it builds the tests' runner. It installs what this
# checkout builds for it into HOST_PREFIX: the packages of libs/, which the
# checker and the frontend import and the benchmarks' Chez baseline uses;
# the type checker (compiler/checker), which it builds the frontend
# against; and the dialect's specification (compiler/spec), which the
# frontend and the runner import; it finds them there beside its own
# prelude and base. The frontend (FRONTEND) reads
# CHECKOUT_PREFIX, which holds only what it built itself: the packages of
# the pinned Idris source (`prefix`) and those of libs/ (`libs`). Every
# command inherits no package path from another installation, and CHEZ is
# the pinned Chez Scheme the pinned Idris was built with
# (tools/verify-pins.sh idris checks that), never one on PATH.
unexport IDRIS2_PATH IDRIS2_PACKAGE_PATH IDRIS2_INC_CGS IDRIS2_INC_SRC IDRIS2_DATA IDRIS2_LIBS IDRIS2_CG IDRIS2_BOOT
CHECKOUT_PREFIX := $(call toolchain,checkout_prefix)
# What every configure of the C++ build is told that tools/toolchain.sh
# decides: the Idris prefix the frontend reads, which idris-mlir records.
CONFIGURE_FACTS := -DIDRIS_MLIR_IDRIS_PREFIX='$(CHECKOUT_PREFIX)'
HOST_PREFIX := $(call toolchain,host_prefix)
# idris-mlir and its frontend read no environment: their prefix is an
# argument, by default the one `build` configures, CHECKOUT_PREFIX. What reads
# Idris's environment is upstream's test scripts, whose compiler
# (tools/upstream-idris/as-idris) passes it on as arguments.
export IDRIS2_PREFIX := $(CHECKOUT_PREFIX)
export PATH := $(IDRIS_PREFIX)/bin:$(PATH)
export IDRIS_MLIR_ROOT := $(ROOT)
# The names a test's `targets` file and expected.<name> files give this
# host (tools/host.sh), which the runner (harness/Main.idr) reads when it
# builds its pools, and harness/one.sh when it picks an expectation.
export IDRIS_MLIR_HOST_NAMES := $(call toolchain,host_names)
export CHEZ := $(call toolchain,chez_scheme)

# The one CPU budget (tools/host.sh: IDRIS_MLIR_NCPU, else every CPU):
# make's own job count, the test runner's threads, bootstrap's jobs and
# each compilation's --num-threads all read this one number. Set
# NCPU=N (or IDRIS_MLIR_NCPU=N) to leave the machine headroom.
NCPU ?= $(call toolchain,ncpu)
export IDRIS_MLIR_NCPU := $(NCPU)
only ?=
except ?=
GOLDEN = --threads $(NCPU) --only '$(only)' --except '$(except)'
# The tests running at once share the budget: the runner runs NCPU of
# them, and each compilation a test makes takes one thread of it, so that
# a step's time limit measures the step, not the load the other tests make.
# A runner that hangs fails instead of holding the tree's lock; without
# coreutils' timeout (tools/host.sh) no test command runs.
TIMEOUT := $(call toolchain,timeout_cmd)
TIMEOUT_MISSING := $(call toolchain,timeout_missing)
RUN_TESTS = IDRIS_MLIR_NCPU=1 $(or $(TIMEOUT),$(error $(TIMEOUT_MISSING))) -k 10 14400 sh $(ROOT)/harness/runs.sh $(RUNNER) $(COMPILER)

.PHONY: help bootstrap doctor verify-pins env check build checker spec frontend prefix libs host-libs \
        test test-idr test-mlir-tools test-unit runner knowngen compile bench self self-checker self-spec typecheck \
        typecheck-configure typecheck-tblgen typecheck-cxx typecheck-dialects typecheck-libs \
        typecheck-checker typecheck-frontend
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
# prefix with a frontend older than the checker.
build:
	@$(PINS) cmake ninja llvm sysroot
	cd $(ROOT) && $(CMAKE) --preset $(PRESET) $(CONFIGURE_FACTS)
	cd $(ROOT) && $(CMAKE) --build --preset $(PRESET) --parallel $(NCPU)
	@$(PINS) idris
	$(ROOT)/tools/dialects.sh generate
	@$(MAKE) --no-print-directory frontend
	ln -sfn '$(FRONTEND)' '$(ROOT)/build/$(PRESET)/foreign/idr/idris-mlir-front'
	@$(MAKE) --no-print-directory libs

# The pinned Idris's directory of packages under a prefix, where it installs
# a package and finds one (<prefix>/idris2-<version>), in a recipe's shell.
libdir = $$(IDRIS2_PREFIX='$(1)' '$(IDRIS2)' --libdir)

# install COMMAND,PREFIX,SOURCES: each package directory of SOURCES, named
# as its .ipkg, installed into PREFIX by COMMAND (a compiler with its
# environment), in order, as each may need the ones before. Each is built
# from nothing in a copy beside the prefix, PREFIX-src: the sources it is
# built from are only read, and a build directory beside them may hold
# another compiler's TTCs, or the same compiler's from before the checker
# changed. A package's earlier installation is removed first, so that no
# module it has dropped stays installed.
install = packages=$$($(1) --libdir) && mkdir -p '$(2)-src' && \
	for source in $(3); do \
	  name=$$(basename "$$source") && copy='$(2)-src'/"$$name" && \
	  rm -rf "$$packages/$$name"-[0-9]* "$$copy" && \
	  cp -R "$$source" "$$copy" && rm -rf "$$copy/build" && \
	  (cd "$$copy" && $(1) --install "$$name.ipkg") || exit 1; \
	done

# The type checker (compiler/checker, the package idris-mlir-checker),
# built by the pinned Idris and installed for it into HOST_PREFIX, never
# into the pinned prefix, which every checkout shares; its prelude and base
# are the pinned prefix's, and the packages of libs/ it imports
# (mlir-linear, mlir-array) are HOST_PREFIX's, installed first
# (host-libs). Again whenever a file of it changes, its package removed
# first, so that no module it has dropped stays installed.
CHECKER_SOURCES := $(ROOT)/compiler/checker/idris-mlir-checker.ipkg $(shell find '$(ROOT)/compiler/checker/src' -name '*.idr' 2> /dev/null)
CHECKER_STAMP := $(HOST_PREFIX)/$(call toolchain,checker_stamp)
HOST_LIBS_STAMP := $(HOST_PREFIX)/$(call toolchain,host_libs_stamp)
checker: $(CHECKER_STAMP)
$(CHECKER_STAMP): $(CHECKER_SOURCES) $(HOST_LIBS_STAMP) $(wildcard $(IDRIS_PREFIX)/provenance.json)
	@$(PINS) idris
	@mkdir -p '$(HOST_PREFIX)' && packages="$(call libdir,$(HOST_PREFIX))" && rm -rf "$$packages"/idris-mlir-checker-*
	cd $(ROOT)/compiler/checker && export IDRIS2_PREFIX='$(HOST_PREFIX)' IDRIS2_PACKAGE_PATH="$(call libdir,$(IDRIS_PREFIX))" && \
	  $(IDRIS2) --install idris-mlir-checker.ipkg
	@touch $@

# The dialect's specification (compiler/spec, the package idris-mlir-spec),
# built by the pinned Idris and installed for it into HOST_PREFIX, where
# the frontend, syntax-samples and the tests' runner import it. Again
# whenever a file of it changes, its package removed first, so that no
# module it has dropped stays installed. Only this file reads its stamp.
SPEC_SOURCES := $(ROOT)/compiler/spec/spec.ipkg $(shell find '$(ROOT)/compiler/spec' -name build -prune -o -name '*.idr' -print 2> /dev/null)
SPEC_STAMP := $(HOST_PREFIX)/.spec-installed
spec: $(SPEC_STAMP)
$(SPEC_STAMP): $(SPEC_SOURCES) $(wildcard $(IDRIS_PREFIX)/provenance.json)
	@$(PINS) idris
	@mkdir -p '$(HOST_PREFIX)' && packages="$(call libdir,$(HOST_PREFIX))" && rm -rf "$$packages"/idris-mlir-spec-*
	cd $(ROOT)/compiler/spec && export IDRIS2_PREFIX='$(HOST_PREFIX)' IDRIS2_PACKAGE_PATH="$(call libdir,$(IDRIS_PREFIX))" && \
	  $(IDRIS2) --install spec.ipkg
	@touch $@

# The frontend, by the pinned Idris, against the checker, the specification
# and the packages of libs/ (HOST_PREFIX) and the pinned prelude and base.
# Beside it, syntax-samples (the specification and mlir-hash), which writes
# one sample of every type and attribute of the generated syntax for
# tests/dialect-syntax.
frontend: checker spec
	@$(PINS) idris
	cd $(ROOT)/compiler && export IDRIS2_PREFIX='$(IDRIS_PREFIX)' IDRIS2_PACKAGE_PATH="$(call libdir,$(HOST_PREFIX))" && \
	  $(IDRIS2) --build idris-mlir.ipkg && $(IDRIS2) --build syntax-samples.ipkg

# The frontend's prefix, CHECKOUT_PREFIX: the packages the pinned Idris
# source ships (its Makefile's IDRIS2_LIBRARIES, in their order: prelude,
# base, and the others, which a program that asks for one is refused by
# name), each built and installed by the frontend. The checker decides
# what a TTC holds, so the prefix is made again from nothing when the
# checker changes, by a frontend built since.
IDRIS_SOURCE := $(ROOT)/third_party/Idris2
IDRIS_LIBS := $(shell sed -n 's/^IDRIS2_LIBRARIES[[:space:]]*=//p' '$(IDRIS_SOURCE)/Makefile' 2> /dev/null)
PREFIX_STAMP := $(CHECKOUT_PREFIX)/$(call toolchain,prefix_stamp)
prefix: $(PREFIX_STAMP)
$(PREFIX_STAMP): $(CHECKER_STAMP)
	@$(PINS) source
	@[ '$(FRONTEND)' -nt '$(CHECKER_STAMP)' ] || \
	  { echo 'error: $(FRONTEND) was not built since the checker was installed; run: make build' >&2; exit 1; }
	@rm -rf '$(CHECKOUT_PREFIX)' '$(CHECKOUT_PREFIX)-src' && mkdir -p '$(CHECKOUT_PREFIX)'
	$(call install,'$(FRONTEND)' --prefix '$(CHECKOUT_PREFIX)',$(CHECKOUT_PREFIX),$(addprefix $(IDRIS_SOURCE)/libs/,$(IDRIS_LIBS)))
	@touch $@

# The packages this compiler ships (libs/), installed by the frontend into
# its prefix (-p mlir-linear, -p mlir-array, -p mlir-hash,
# -p mlir-relational), in dependency order, again whenever one of their
# sources changes.
SHIPPED := $(ROOT)/libs/mlir-linear $(ROOT)/libs/mlir-array $(ROOT)/libs/mlir-hash $(ROOT)/libs/mlir-relational
SHIPPED_SOURCES := $(shell find $(SHIPPED) -name build -prune -o \( -name '*.idr' -o -name '*.ipkg' \) -print 2> /dev/null)
LIBS_STAMP := $(CHECKOUT_PREFIX)/$(call toolchain,libs_stamp)
libs: $(LIBS_STAMP)
$(LIBS_STAMP): $(PREFIX_STAMP) $(SHIPPED_SOURCES)
	$(call install,'$(FRONTEND)' --prefix '$(CHECKOUT_PREFIX)',$(CHECKOUT_PREFIX),$(SHIPPED))
	@touch $@

# The packages of libs/ for the pinned Idris too, installed into
# HOST_PREFIX: the checker imports mlir-linear and mlir-array, the frontend
# mlir-hash, and the benchmarks' Chez baseline compiles the programs that
# use them. Again whenever one of their sources changes.
host-libs: $(HOST_LIBS_STAMP)
$(HOST_LIBS_STAMP): $(wildcard $(IDRIS_PREFIX)/provenance.json) $(SHIPPED_SOURCES)
	@$(PINS) idris
	@mkdir -p '$(HOST_PREFIX)'
	$(call install,IDRIS2_PREFIX='$(HOST_PREFIX)' IDRIS2_PACKAGE_PATH="$(call libdir,$(IDRIS_PREFIX))" '$(IDRIS2)',$(HOST_PREFIX),$(SHIPPED))
	@touch $@

# The type checker as a package of the frontend's prefix, installed by
# the frontend, so that the frontend can compile itself (-p
# idris-mlir-checker): from a copy of compiler/checker, its earlier
# installation removed first, again whenever a file of it changes.
SELF_CHECKER_STAMP := $(CHECKOUT_PREFIX)/$(call toolchain,checker_stamp)
self-checker: $(SELF_CHECKER_STAMP)
$(SELF_CHECKER_STAMP): $(CHECKER_SOURCES) $(LIBS_STAMP)
	@packages=$$('$(FRONTEND)' --prefix '$(CHECKOUT_PREFIX)' --libdir) && rm -rf "$$packages"/idris-mlir-checker-* \
	  '$(CHECKOUT_PREFIX)-src/idris-mlir-checker' && mkdir -p '$(CHECKOUT_PREFIX)-src' && \
	  cp -R '$(ROOT)/compiler/checker' '$(CHECKOUT_PREFIX)-src/idris-mlir-checker' && \
	  rm -rf '$(CHECKOUT_PREFIX)-src/idris-mlir-checker/build'
	cd '$(CHECKOUT_PREFIX)-src/idris-mlir-checker' && '$(FRONTEND)' --prefix '$(CHECKOUT_PREFIX)' --install idris-mlir-checker.ipkg
	@touch $@

# The dialect's specification as a package of the frontend's prefix too,
# installed by the frontend, which imports it when it compiles itself
# (-p idris-mlir-spec), as it does mlir-hash, which `libs` installs: from a
# copy of compiler/spec, its earlier installation removed first, again
# whenever a file of it changes.
SELF_SPEC_STAMP := $(CHECKOUT_PREFIX)/.spec-installed
self-spec: $(SELF_SPEC_STAMP)
$(SELF_SPEC_STAMP): $(SPEC_SOURCES) $(LIBS_STAMP)
	@packages=$$('$(FRONTEND)' --prefix '$(CHECKOUT_PREFIX)' --libdir) && rm -rf "$$packages"/idris-mlir-spec-* \
	  '$(CHECKOUT_PREFIX)-src/spec' && mkdir -p '$(CHECKOUT_PREFIX)-src' && \
	  cp -R '$(ROOT)/compiler/spec' '$(CHECKOUT_PREFIX)-src/spec' && \
	  rm -rf '$(CHECKOUT_PREFIX)-src/spec/build'
	cd '$(CHECKOUT_PREFIX)-src/spec' && '$(FRONTEND)' --prefix '$(CHECKOUT_PREFIX)' --install spec.ipkg
	@touch $@

# The self compile runs the optimized build's pipeline (tools/self.sh),
# built here first.
SELF_PRESET := $(call toolchain,self_preset)
self: self-checker self-spec
	@$(PINS) built llvm sysroot
	@$(MAKE) --no-print-directory build PRESET=$(SELF_PRESET)
	$(ROOT)/tools/self.sh

# Every test command rebuilds the runner while other runs may be using it.
# So it is built aside, in build/stage, one build at a time (a mkdir
# mutex, tools/host.sh), and installed by renaming each file over the old
# one: a running runner keeps the files it started with, which rewriting
# them in place would corrupt under it. The files are the launcher and
# whatever the Chez backend put beside it, its support library named as
# the host names one (.so, .dylib). The pinned Idris builds it on its own
# prefix, against the specification it imports, which `spec` installs into
# HOST_PREFIX.
runner: spec
	@$(PINS) idris
	cd $(ROOT)/harness && mkdir -p build/exec/runtests_app && . $(ROOT)/tools/host.sh && \
	export IDRIS2_PREFIX='$(IDRIS_PREFIX)' IDRIS2_PACKAGE_PATH="$(call libdir,$(HOST_PREFIX))" && \
	with_lock build/.runner.mutex sh -c ' \
	  $(IDRIS2) --build-dir build/stage --build harness.ipkg || exit 1; \
	  cd build/stage/exec && for file in runtests runtests_app/*; do \
	    cp -p $$file ../../exec/$$file.new.$$$$ && \
	      mv -f ../../exec/$$file.new.$$$$ ../../exec/$$file || exit 1; \
	  done'

# knowngen (compiler/checker/known), which prints the checker's modules
# its vocabularies define, built by the pinned Idris outside the checkout's
# sources. `make check` runs its check beside the suite, whose
# spec-current holds the specification's generated files the same way:
# both run, and a difference in either fails the command.
KNOWNGEN_BUILD := $(ROOT)/build/knowngen
KNOWNGEN := $(KNOWNGEN_BUILD)/exec/knowngen
knowngen:
	@$(PINS) idris
	cd $(ROOT)/compiler/checker/known && \
	  IDRIS2_PREFIX='$(IDRIS_PREFIX)' $(IDRIS2) --build-dir '$(KNOWNGEN_BUILD)' --build known.ipkg

check: runner knowngen
	@status=0; \
	$(or $(TIMEOUT),$(error $(TIMEOUT_MISSING))) -k 10 60 '$(KNOWNGEN)' check '$(ROOT)' || status=1; \
	cd $(ROOT)/tests && $(RUN_TESTS) --suite check $(GOLDEN) || status=1; \
	exit $$status

test: runner libs
	@$(PINS) built llvm sysroot
	cd $(ROOT)/tests && $(RUN_TESTS) --suite test $(GOLDEN)

test-idr: runner
	@$(PINS) built llvm test-tools sysroot
	cd $(ROOT)/tests && $(RUN_TESTS) --suite test-idr $(GOLDEN)

# Idris's bug is checked through the frontend, whose type checker carries
# the fix, so the suite needs it and its prefix.
test-mlir-tools: runner libs
	@$(PINS) built llvm sysroot
	cd $(ROOT)/tests && $(RUN_TESTS) --suite test-mlir-tools $(GOLDEN)

# The exhaustive boxes (foreign/idr/unittests): each googletest program the
# build made there, under the timeout every test command has. The largest
# box makes some 10^7 runtime calls of nanoseconds each, so one still
# running after 600 s has hung.
test-unit:
	@$(PINS) built llvm sysroot
	@boxes=$$(find '$(ROOT)/build/$(PRESET)/foreign/idr/unittests' -maxdepth 1 -type f -name 'idr-box-*' -perm -u+x 2> /dev/null | LC_ALL=C sort); \
	if [ -z "$$boxes" ]; then echo 'test-unit: no box is built (make build builds them)' >&2; exit 1; fi; \
	failed=; for box in $$boxes; do \
	  echo "==> $${box##*/}"; \
	  $(or $(TIMEOUT),$(error $(TIMEOUT_MISSING))) -k 10 600 "$$box" || failed="$$failed $${box##*/}"; \
	done; \
	if [ -n "$$failed" ]; then echo "test-unit: failed:$$failed" >&2; exit 1; fi

compile:
	@test -n '$(SRC)' && test -n '$(OUT)' || { echo 'usage: make compile SRC=Main.idr OUT=prog' >&2; exit 2; }
	@$(PINS) built idris prefix sysroot
	@$(ROOT)/tools/compile.sh '$(abspath $(SRC))' '$(abspath $(OUT))'

bench: libs host-libs
	@$(PINS) built idris prefix sysroot
	$(ROOT)/bench/run.sh $(ARGS)

# Whether the code compiles where stage 2 is not built, which takes hours:
# the typecheck bootstrap step builds LLVM and MLIR's TableGen and headers
# alone, and the typecheck preset compiles every unit of foreign/idr with
# the host's clang against them (CMakeLists.txt's IDRIS_MLIR_TYPECHECK).
# Then the parts below, each with its log in TYPECHECK_LOGS, after the
# parts it needs (part:needed): idris-mlir-tblgen, the one tool linked,
# writes the Idris side's modules of the dialects; the C++ build keeps
# going past a failed unit, and its errors (the compiler's, and TableGen's
# at the location of the note that follows them) are listed one per line,
# file:line: message, in TYPECHECK_ERRORS; and the pinned Idris checks
# libs/ and the checker, installed into HOST_PREFIX as `host-libs` and
# `checker` install them, since each is a package of the next, and the frontend
# against them and the specification `spec` installs (--typecheck: no code
# is generated). The summary names each
# part that failed or did not run; any failure fails the command.
TYPECHECK_PRESET := $(call toolchain,typecheck_preset)
TYPECHECK_DIR := $(call toolchain,typecheck_prefix)
TYPECHECK_LOGS := $(TYPECHECK_DIR)/logs
TYPECHECK_ERRORS := $(TYPECHECK_DIR)/errors.log
TYPECHECK_PARTS := configure tblgen:configure cxx:configure dialects:tblgen libs checker:libs frontend:checker

typecheck:
	$(ROOT)/tools/bootstrap.sh cmake ninja chez idris typecheck
	@mkdir -p '$(TYPECHECK_LOGS)'; ok=; failed=; skipped=; \
	for entry in $(TYPECHECK_PARTS); do \
	  part=$${entry%%:*}; needed=; case $$entry in *:*) needed=$${entry#*:} ;; esac; \
	  case " $$ok " in *" $$needed "*) ;; *) if [ -n "$$needed" ]; then \
	    echo "==> typecheck $$part: not run, as $$needed did not succeed"; skipped="$$skipped $$part"; continue; fi ;; esac; \
	  log='$(TYPECHECK_LOGS)'/$$part.log; echo "==> typecheck $$part (log: $$log)"; \
	  if $(MAKE) --no-print-directory typecheck-$$part > "$$log" 2>&1; then ok="$$ok $$part"; \
	  else failed="$$failed $$part"; tail -n 15 "$$log" | sed 's/^/    | /'; fi; \
	done; \
	echo '==> typecheck summary'; \
	echo "    succeeded:$${ok:- none}"; echo "    failed:$${failed:- none}"; echo "    not run:$${skipped:- none}"; \
	if [ -s '$(TYPECHECK_ERRORS)' ]; then \
	  echo "    C++ errors: $$(wc -l < '$(TYPECHECK_ERRORS)' | tr -d ' '), one per line in $(TYPECHECK_ERRORS)"; fi; \
	[ -z "$$failed$$skipped" ]

# Afresh each time: the toolchain file is the bootstrap's, and a cached
# check would outlive a change of it. Ninja recompiles only what changed.
typecheck-configure:
	cd $(ROOT) && $(CMAKE) --preset $(TYPECHECK_PRESET) --fresh $(CONFIGURE_FACTS)

typecheck-tblgen:
	cd $(ROOT) && $(CMAKE) --build --preset $(TYPECHECK_PRESET) --parallel $(NCPU) --target idris-mlir-tblgen

typecheck-cxx:
	@rm -f '$(TYPECHECK_ERRORS)'
	cd $(ROOT) && { $(CMAKE) --build --preset $(TYPECHECK_PRESET) --parallel $(NCPU) -- -k 0 2>&1; echo $$? > '$(TYPECHECK_ERRORS).status'; } | \
	  tee '$(TYPECHECK_DIR)/build.log'
	@awk -v root='$(ROOT)/' ' \
	  function out(loc, msg) { line = loc ": " msg; if (!seen[line]++) print line } \
	  { if (index($$0, root) == 1) $$0 = substr($$0, length(root) + 1) } \
	  pending != "" && /^[^ :]+:[0-9]+:[0-9]+: note: / { split($$0, f, ":"); out(f[1] ":" f[2], pending); pending = ""; next } \
	  /^[^ :]+:[0-9]+:[0-9]+: (fatal )?error: / { \
	    split($$0, f, ":"); msg = $$0; sub(/^[^ :]+:[0-9]+:[0-9]+: (fatal )?error: /, "", msg); out(f[1] ":" f[2], msg); next } \
	  /^error: / { if (pending != "") out("?", pending); pending = substr($$0, 8) } \
	  END { if (pending != "") out("?", pending) }' '$(TYPECHECK_DIR)/build.log' > '$(TYPECHECK_ERRORS)'
	@status=$$(cat '$(TYPECHECK_ERRORS).status'); rm -f '$(TYPECHECK_ERRORS).status'; exit $$status

typecheck-dialects:
	$(ROOT)/tools/dialects.sh generate typecheck

typecheck-libs: host-libs

typecheck-checker: checker

typecheck-frontend: checker spec
	@$(PINS) idris
	cd $(ROOT)/compiler && export IDRIS2_PREFIX='$(IDRIS_PREFIX)' IDRIS2_PACKAGE_PATH="$(call libdir,$(HOST_PREFIX))" && \
	  $(IDRIS2) --typecheck idris-mlir.ipkg && $(IDRIS2) --typecheck syntax-samples.ipkg
