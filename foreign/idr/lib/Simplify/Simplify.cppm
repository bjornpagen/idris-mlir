// idr.simplify: the simplify loop and the passes only it runs. A round runs
// the passes of simplifyRound in order, and rounds repeat until one changes
// nothing (round, structural, trace); within a round, every cycle of
// references keeps a loop breaker (breakers). Before the loop, a case block
// called once is inlined into its parent (contify).
export module idr.simplify;

export import :breakers;
export import :contify;
export import :round;
export import :structural;
export import :trace;
