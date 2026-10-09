# idr.canon: what the canonicalizations of the dialect's ops use besides
# their members; the hooks that add them are plain units of lib/Dialect,
# which import it. (lib/Canonicalize is the idr-canonicalize pass.)
idr_library(idr_canon
	MODULES
		Canon.cppm
		BoundByEnclosing.cppm
		Captures.cppm
		CaseOfCase.cppm
		ClosureOf.cppm
		Eta.cppm
		Feeds.cppm
		MatchPatterns.cppm
		Meets.cppm
		Merge.cppm
		MoveOut.cppm
		PutList.cppm
		PutStr.cppm
		Rebuild.cppm
		Sink.cppm
	LINKS
		idr_mlir
		idr_ods
)
