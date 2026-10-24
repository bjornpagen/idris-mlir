-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Text.PrettyPrint.Prettyprinter.Render.String

import Data.String
import Libraries.Text.PrettyPrint.Prettyprinter.Doc

%default total

export
renderString : SimpleDocStream ann -> String
renderString SEmpty = neutral
renderString (SChar c rest) = singleton c <+> renderString rest
renderString (SText l t rest) = t <+> renderString rest
renderString (SLine l rest) = singleton '\n' <+> textSpaces l <+> renderString rest
renderString (SAnnPush ann rest) = renderString rest
renderString (SAnnPop rest) = renderString rest
