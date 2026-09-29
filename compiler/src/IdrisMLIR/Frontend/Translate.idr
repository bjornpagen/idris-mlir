||| Checked TT to full Core. Reads compile-time case trees (`treeCT`) and
||| types; monomorphises on demand, with Idris's own normalizer doing all
||| type-level computation.
|||
||| Scopes carry over from TT: a TT term in scope `vars` becomes a `Term a`,
||| with an environment saying what each TT variable stands for. A TT index
||| is a position in that environment; type arguments have no Core variable.
module IdrisMLIR.Frontend.Translate

import public IdrisMLIR.Frontend.Translate.Errors
import public IdrisMLIR.Frontend.Translate.Hooks
import public IdrisMLIR.Frontend.Translate.Programs
import public IdrisMLIR.Frontend.Translate.State
