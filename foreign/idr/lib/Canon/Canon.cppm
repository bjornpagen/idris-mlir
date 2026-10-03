// idr.canon: what the canonicalizations of the dialect's ops use besides
// their members: the patterns of idr.match and idr.match_lit (a match
// rebuilt, the values a consumer folds against, merging, case-of-case and
// sinking), the helpers of the apply, constructor and field hooks, output's
// patterns, and the dialect's own pattern on scf.while. The hooks that add
// or call them (MatchOp::getCanonicalizationPatterns, ...) are plain units
// of lib/Dialect, which import it.
export module idr.canon;

export import :boundbyenclosing;
export import :captures;
export import :caseofcase;
export import :closureof;
export import :eta;
export import :feeds;
export import :matchpatterns;
export import :meets;
export import :merge;
export import :putlist;
export import :putstr;
export import :readforwardedonce;
export import :rebuild;
export import :sink;
