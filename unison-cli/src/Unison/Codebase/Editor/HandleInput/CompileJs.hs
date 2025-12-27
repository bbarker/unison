-- | @compile.js@ input handler - compiles a Unison term to JavaScript.
module Unison.Codebase.Editor.HandleInput.CompileJs
  ( handleCompileJs,
  )
where

import Control.Monad.Reader.Class (ask)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import Unison.Cli.Monad (Cli, Env (..))
import Unison.Cli.Monad qualified as Cli
import Unison.Codebase qualified as Codebase
import Unison.Codebase.Editor.HandleInput.TermResolution (resolveTermRef)
import Unison.Codebase.Editor.Output qualified as Output
import Unison.HashQualified qualified as HQ
import Unison.Name (Name)
import Unison.Prelude
import Unison.Reference qualified as Reference
import Unison.Runtime.ANF qualified as ANF
import Unison.Runtime.JavaScript.Emit qualified as JsEmit
import Unison.Syntax.HashQualified qualified as HQ (toText)
import Unison.Util.Pretty qualified as P

handleCompileJs :: FilePath -> HQ.HashQualified Name -> Cli ()
handleCompileJs outputPath termName = do
  env <- ask
  -- Resolve the term reference (any term, not just main functions)
  ref <- resolveTermRef termName

  -- Get the term from the codebase
  mTerm <- Cli.runTransaction $ case ref of
    Reference.Builtin _ ->
      pure Nothing
    Reference.DerivedId refId ->
      Codebase.getTerm env.codebase refId

  case mTerm of
    Nothing -> do
      Cli.respond $ Output.Literal $ P.lines
        [ P.wrap $ "Could not find term: " <> P.text (HQ.toText termName)
        ]
    Just term -> do
      -- Get the term name for the generated JavaScript
      let nameText = HQ.toText termName

      -- Strip type annotations and convert to ANF using the runtime's superNormalize
      -- deannotate removes Ann wrappers, which superNormalize doesn't handle
      let anfGroup = ANF.superNormalize (ANF.deannotate term)

      -- Emit JavaScript
      let jsCode = JsEmit.emitModule JsEmit.defaultEmitConfig nameText anfGroup

      -- Write to file
      liftIO $ Text.writeFile outputPath jsCode

      Cli.respond $ Output.Literal $ P.lines
        [ P.wrap $ "Compiled " <> P.text (HQ.toText termName) <> " to " <> P.string outputPath
        ]
