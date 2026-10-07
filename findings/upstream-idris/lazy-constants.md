# Lazy constants are not memoized

`allschemes/memo002` builds a `Lazy Nat` by adding the previous constant
to itself ten times, twenty deep. Chez memoizes each constant, so forcing
the last one is two hundred additions. Without that memoization the same
term is 10^20 additions and does not finish.

This compiler's `Lazy` is a closure. Forcing it runs the closure again.
Caching the result is an update of the suspension, which is the runtime's
meaning of `Lazy` (Chez's weak memo), not an Idris function and not a
special case of this test. `memo001` is the strict `Nat` of the same shape
and folds. `memo003` asks for `%cg chez lazy=weakMemo`, which stays
rejected as a user pragma.

Compiling `memo002` does not finish within a minute: compile-time
evaluation follows the same unmemoized term.
