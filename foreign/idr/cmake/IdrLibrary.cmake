# idr_library(NAME [MODULES interface...] [UNITS unit...] [GLUE unit...]
#             [LINKS library...])
#
# The library of one module of lib/: its interface units, its
# implementation units, the plain units of its pass glue and op hooks, which
# include idr/Idr.h, and the libraries of exactly the modules it imports.
# A module is found only in the libraries a library links, so a unit that
# imports any other fails to build (tests/toolchain/module-imports). Every
# library is compiled as idr_build says, after idr_tablegen, with the
# language profile; one with plain units reuses idr_pch, the precompiled
# idr/Idr.h.
function(idr_library name)
	cmake_parse_arguments(PARSE_ARGV 1 arg "" "" "MODULES;UNITS;GLUE;LINKS")
	add_library(${name} STATIC)
	target_sources(${name}
		PUBLIC
			FILE_SET ${name} TYPE CXX_MODULES FILES ${arg_MODULES}
		PRIVATE
			${arg_UNITS}
			${arg_GLUE}
	)
	target_link_libraries(${name}
		PUBLIC idr_build
		PRIVATE ${arg_LINKS} idris_mlir_language_profile
	)
	add_dependencies(${name} idr_tablegen)
	# The MLIR API is not module-aware, so no target imports std: idr.mlir
	# wraps its headers instead.
	set_target_properties(${name} PROPERTIES
		CXX_MODULE_STD OFF
		CXX_SCAN_FOR_MODULES ON
	)
	if(arg_GLUE)
		target_precompile_headers(${name} REUSE_FROM idr_pch)
		set_source_files_properties(${arg_MODULES} ${arg_UNITS} PROPERTIES SKIP_PRECOMPILE_HEADERS ON)
	endif()
endfunction()
