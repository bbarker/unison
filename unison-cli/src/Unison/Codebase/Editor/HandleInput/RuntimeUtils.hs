module Unison.Codebase.Editor.HandleInput.RuntimeUtils
  ( evalUnisonTerm,
    evalUnisonTermE,
    displayDecompileErrors,
  )
where

import Control.Lens
import Control.Monad.Reader (ask)
import Unison.Cli.Monad (Cli)
import Unison.Cli.Monad qualified as Cli
import Unison.Codebase qualified as Codebase
import Unison.Codebase.Editor.Output
import Unison.Codebase.Runtime qualified as Runtime
import Unison.Hashing.V2.Convert qualified as Hashing
import Unison.Parser.Ann (Ann (..))
import Unison.Parser.Ann qualified as Ann
import Unison.Prelude
import Unison.PrettyPrintEnv qualified as PPE
import Unison.Reference qualified as Reference
import Unison.Symbol (Symbol)
import Unison.Term (Term)
import Unison.Term qualified as Term
import Unison.Util.Pretty qualified as P
import Unison.WatchKind qualified as WK

displayDecompileErrors :: [Runtime.Error] -> Cli ()
displayDecompileErrors errs = Cli.respond (PrintMessage msg)
  where
    msg =
      P.lines $
        [ P.warnCallout "I had trouble decompiling some results.",
          "",
          "The following errors were encountered:"
        ]
          ++ fmap (P.indentN 2) errs

-- | Evaluate a single closed definition.
evalUnisonTermE ::
  Bool ->
  PPE.PrettyPrintEnv ->
  Bool ->
  Term Symbol Ann ->
  Cli (Either Runtime.Error (Term Symbol Ann))
evalUnisonTermE sandbox ppe useCache tm = do
  Cli.Env {codebase, runtime, sandboxedRuntime} <- ask
  let theRuntime = if sandbox then sandboxedRuntime else runtime

  let watchCache :: Reference.Id -> IO (Maybe (Term Symbol ()))
      watchCache ref = do
        maybeTerm <- Codebase.runTransaction codebase (Codebase.lookupWatchCache codebase ref)
        pure (Term.amap (\(_ :: Ann) -> ()) <$> maybeTerm)

  let cache = if useCache then watchCache else Runtime.noCache
  r <- liftIO (Runtime.evaluateTerm' (Codebase.toCodeLookup codebase) cache ppe theRuntime tm)
  when useCache do
    case r of
      Right (errs, tmr)
        -- don't cache when there were errors
        | null errs ->
            Cli.runTransaction do
              Codebase.putWatch
                WK.RegularWatch
                (Hashing.hashClosedTerm tm)
                (Term.amap (const Ann.External) tmr)
        | otherwise -> displayDecompileErrors errs
      Left _ -> pure ()
  pure $ r <&> Term.amap (\() -> Ann.External) . snd

-- | Evaluate a single closed definition.
evalUnisonTerm ::
  Bool ->
  PPE.PrettyPrintEnv ->
  Bool ->
  Term Symbol Ann ->
  Cli (Term Symbol Ann)
evalUnisonTerm sandbox ppe useCache tm =
  evalUnisonTermE sandbox ppe useCache tm & onLeftM \err ->
    Cli.returnEarly (EvaluationFailure err)
