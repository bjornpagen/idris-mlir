# idr.ops: what the hooks of the dialect's ops and types use besides their
# members; the hooks themselves are plain units of lib/Dialect, which
# import it.
idr_library(idr_ops
	MODULES
		Ops.cppm
		BigBounds.cppm
		ByteBuffers.cppm
		Constants.cppm
		Does.cppm
		Elements.cppm
		Inliner.cppm
		IoEffects.cppm
		LinearRanges.cppm
		LoopBodies.cppm
		MatchRegions.cppm
		MatchSuccessors.cppm
		MatchSyntax.cppm
		NonNegative.cppm
		TakenRegions.cppm
		Untyped.cppm
		Words.cppm
	LINKS
		idr_mlir
		idr_ods
		idr_ranges
)
