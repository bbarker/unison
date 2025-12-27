{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Emit JavaScript from Unison ANF.
--
-- This module converts Unison A-Normal Form (ANF) to JavaScript AST.
-- The emitted JavaScript uses:
-- - BigInt for Int/Nat (arbitrary precision)
-- - Number for Float (64-bit IEEE 754)
-- - Generators for effectful code
-- - Tagged objects for algebraic data types
module Unison.Runtime.JavaScript.Emit
  ( -- * Main entry points
    emitGroup,
    emitModule,

    -- * Configuration
    EmitConfig (..),
    defaultEmitConfig,

    -- * Context
    EmitCtx,
    initCtx,
  )
where

import Control.Monad (forM_, forM, when, foldM)
import Control.Monad.State.Strict
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Unison.ABT.Normalized qualified as ABTN
import Unison.Hash qualified as Hash
import Unison.Reference (Reference)
import Unison.Reference qualified as Reference
import Unison.Runtime.ANF
  ( ANormal,
    Branched (..),
    Func (..),
    Lit (..),
    Mem (..),
    SuperGroup (..),
    SuperNormal (..),
    pattern TApp,
    pattern TBLit,
    pattern TFOp,
    pattern TFrc,
    pattern THnd,
    pattern TLet,
    pattern TLets,
    pattern TLit,
    pattern TMatch,
    pattern TName,
    pattern TPrm,
    pattern TShift,
    pattern TVar,
  )
import Unison.Runtime.TypeTags (CTag (..))
import Unison.Runtime.ANF.POp (POp)
import Unison.Runtime.JavaScript.Intrinsics (emitPOp, runtimeFunctions)
import Unison.Runtime.JavaScript.Render (RenderConfig, defaultConfig, renderDecl, renderModule)
import Unison.Runtime.JavaScript.Types
import Unison.Symbol (Symbol)
import Unison.Util.EnumContainers qualified as EC
import Unison.Util.Text qualified as Util.Text
import Unison.Var (Var)
import Unison.Var qualified as Var

-- | Configuration for JavaScript emission
data EmitConfig = EmitConfig
  { -- | Include runtime helper functions
    ecIncludeRuntime :: Bool,
    -- | Use generators for all code (even pure)
    ecAlwaysGenerators :: Bool,
    -- | Render configuration
    ecRenderConfig :: RenderConfig
  }
  deriving (Show, Eq)

-- | Default configuration
defaultEmitConfig :: EmitConfig
defaultEmitConfig =
  EmitConfig
    { ecIncludeRuntime = True,
      ecAlwaysGenerators = False,
      ecRenderConfig = defaultConfig
    }

-- | Emission context
data EmitCtx v = EmitCtx
  { -- | Map from Unison variable to JS name
    ctxVarNames :: Map v Text,
    -- | Map from Reference to JS name
    ctxRefNames :: Map Reference Text,
    -- | Fresh name counter
    ctxCounter :: Int,
    -- | Are we in generator mode?
    ctxIsGenerator :: Bool,
    -- | Names of recursive functions in the current group
    ctxRecursive :: Set.Set v
  }
  deriving (Show)

-- | Emission monad
type Emit v a = State (EmitCtx v) a

-- | Initialize context
initCtx :: EmitCtx v
initCtx =
  EmitCtx
    { ctxVarNames = Map.empty,
      ctxRefNames = Map.empty,
      ctxCounter = 0,
      ctxIsGenerator = False,
      ctxRecursive = Set.empty
    }

-- | Generate a fresh variable name
freshName :: Text -> Emit v Text
freshName prefix = do
  n <- gets ctxCounter
  modify $ \ctx -> ctx {ctxCounter = n + 1}
  pure $ prefix <> Text.pack (show n)

-- | Add a variable binding
bindVar :: (Var v) => v -> Emit v Text
bindVar v = do
  name <- freshName (sanitizeName (Var.name v))
  modify $ \ctx -> ctx {ctxVarNames = Map.insert v name (ctxVarNames ctx)}
  pure name

-- | Look up a variable
lookupVar :: (Var v) => v -> Emit v (Maybe Text)
lookupVar v = gets (Map.lookup v . ctxVarNames)

-- | Get or create a name for a variable
getVarName :: (Var v) => v -> Emit v Text
getVarName v = do
  mname <- lookupVar v
  case mname of
    Just name -> pure name
    Nothing -> bindVar v

-- | Emit a SuperGroup as a JS module
emitModule :: (Var v) => EmitConfig -> Text -> SuperGroup Reference v -> Text
emitModule cfg mainName group =
  let (decls, _ctx) = runState (emitGroup mainName group) initCtx
      runtime = if ecIncludeRuntime cfg then runtimeFunctions <> "\n\n" else ""
      modul = JsModule [] decls [mainName]
   in runtime <> renderModule (ecRenderConfig cfg) modul

-- | Emit a SuperGroup as JS declarations
emitGroup :: (Var v) => Text -> SuperGroup Reference v -> Emit v [JsDecl]
emitGroup mainName (Rec {group = subgroups, entry = entryFn}) = do
  -- Emit the main entry function
  let Lambda {conventions = ccs, bound = body} = entryFn
  let params = zipWith (\idx _ -> "$" <> Text.pack (show idx)) [0 :: Int ..] ccs
  forM_ (zip params ccs) $ \(pname, _cc) -> do
    _nm <- freshName pname
    -- bind parameter to name (simplified - need to handle properly)
    modify $ \ctx -> ctx {ctxVarNames = Map.empty}
  stmts <- emitNormal body
  let isGen = False -- TODO: detect if generator needed
  let entryDecl = JsFunctionDecl mainName params stmts isGen

  -- Emit any mutual recursive functions in the group
  subDecls <- forM (zip [0 :: Int ..] subgroups) $ \(fnIdx, (varName, Lambda {conventions = fnCcs, bound = fnBody})) -> do
    let fnName = mainName <> "_" <> Text.pack (show (Var.name varName)) <> "_" <> Text.pack (show fnIdx)
    let fnParams = zipWith (\pIdx _ -> "$" <> Text.pack (show pIdx)) [0 :: Int ..] fnCcs
    modify $ \ctx -> ctx {ctxVarNames = Map.empty}
    fnStmts <- emitNormal fnBody
    pure $ JsFunctionDecl fnName fnParams fnStmts False
  pure (entryDecl : subDecls)

-- | Emit ANormal to JS statements
emitNormal :: forall v. (Var v) => ANormal Reference v -> Emit v [JsStmt]
emitNormal anf = case anf of
  -- Let binding
  TLets _dir vs mems bound body -> do
    boundExpr <- emitNormalExpr bound
    names <- forM vs $ \v -> freshName (Text.pack (show (Var.name v)))
    let bindings = zipWith JsConst names (repeat boundExpr) -- simplified
    bodyStmts <- emitNormal body
    pure $ bindings ++ bodyStmts

  -- Single let binding (common case)
  TLet _dir var _mem bound body -> do
    boundExpr <- emitNormalExpr bound
    name <- bindVar var
    bodyStmts <- emitNormal body
    pure $ JsConst name boundExpr : bodyStmts

  -- Named closure
  TName v fn args body -> do
    name <- bindVar v
    fnExpr <- case fn of
      Left ref -> pure $ JsVar (refToName ref)
      Right fv -> JsVar <$> getVarName fv
    argExprs <- mapM getVarExpr args
    let closureExpr = case argExprs of
          [] -> fnExpr
          _ -> JsCall fnExpr argExprs
    bodyStmts <- emitNormal body
    pure $ JsConst name closureExpr : bodyStmts

  -- Variable reference (terminal)
  TVar v -> do
    name <- getVarName v
    pure [JsReturn (JsVar name)]

  -- Literal (terminal)
  TLit lit -> do
    expr <- emitLit lit
    pure [JsReturn expr]

  -- Boxed literal (terminal)
  TBLit lit -> do
    expr <- emitLit lit
    pure [JsReturn expr]

  -- Function application (terminal)
  TApp func args -> do
    result <- emitApp func args
    pure [JsReturn result]

  -- Primitive operation (terminal)
  TPrm op args -> do
    argExprs <- mapM getVarExpr args
    pure [JsReturn (emitPOp op argExprs)]

  -- Foreign operation (terminal)
  TFOp fop args -> do
    argExprs <- mapM getVarExpr args
    let fnName = "$foreign_" <> Text.pack (show fop)
    pure [JsReturn (JsCall (JsVar fnName) argExprs)]

  -- Force (thunk evaluation)
  TFrc v -> do
    name <- getVarName v
    pure [JsReturn (JsCall (JsVar name) [])]

  -- Pattern match
  TMatch v branches -> do
    scrutExpr <- getVarExpr v
    emitMatch scrutExpr branches

  -- Effect shift (request an effect)
  TShift ref _shiftVar body -> do
    modify $ \ctx -> ctx {ctxIsGenerator = True}
    let abilityName = refToName ref
    bodyStmts <- emitNormal body
    let yieldExpr =
          JsYield
            ( JsObject
                [ ("type", JsLit (JsString "effect")),
                  ("ability", JsLit (JsString abilityName))
                ]
            )
    pure $ JsExprStmt yieldExpr : bodyStmts

  -- Effect handler
  THnd refs scrutineeVar _affineVar body -> do
    modify $ \ctx -> ctx {ctxIsGenerator = True}
    scrutExpr <- getVarExpr scrutineeVar
    bodyStmts <- emitNormal body
    -- Simplified handler emission
    let handlerNames = map refToName refs
    let handlersObj =
          JsObject $
            map (\n -> (n, JsObject [])) handlerNames
    pure $
      JsConst "$handlers" handlersObj
        : bodyStmts
        ++ [JsReturn (JsCall (JsVar "$runEffect") [scrutExpr, JsVar "$handlers"])]

  -- Fallback for unhandled cases
  _ -> pure [JsReturn (JsCall (JsVar "$unimplemented") [])]

-- | Emit an ANormal expression (non-terminal)
emitNormalExpr :: (Var v) => ANormal Reference v -> Emit v JsExpr
emitNormalExpr anf = case anf of
  TVar v -> getVarExpr v
  TLit lit -> emitLit lit
  TBLit lit -> emitLit lit
  TApp func args -> emitApp func args
  TPrm op args -> do
    argExprs <- mapM getVarExpr args
    pure $ emitPOp op argExprs
  TFrc v -> do
    name <- getVarName v
    pure $ JsCall (JsVar name) []
  _ -> pure $ JsCall (JsVar "$unimplemented") []

-- | Emit function application
emitApp :: (Var v) => Func Reference v -> [v] -> Emit v JsExpr
emitApp func args = do
  argExprs <- mapM getVarExpr args
  case func of
    FVar v -> do
      fnName <- getVarName v
      pure $ JsCall (JsVar fnName) argExprs
    FComb ref ->
      pure $ JsCall (JsVar (refToName ref)) argExprs
    FCon ref (CTag tag) ->
      pure $ JsCall (JsVar "$con") (JsLit (JsInt (fromIntegral tag)) : argExprs)
    FReq ref (CTag tag) -> do
      modify $ \ctx -> ctx {ctxIsGenerator = True}
      let abilityName = refToName ref
      pure $
        JsYieldStar $
          JsCall
            (JsVar "$perform")
            [ JsLit (JsString abilityName),
              JsLit (JsInt (fromIntegral tag)),
              JsArray argExprs
            ]
    FPrim (Left pop) ->
      pure $ emitPOp pop argExprs
    FPrim (Right _fop) ->
      pure $ JsCall (JsVar "$foreignOp") argExprs
    FCont v -> do
      kName <- getVarName v
      pure $ JsCall (JsVar kName) argExprs

-- | Emit a literal
emitLit :: Lit Reference -> Emit v JsExpr
emitLit lit = case lit of
  I i -> pure $ JsLit (JsInt (fromIntegral i))
  N n -> pure $ JsLit (JsInt (fromIntegral n))
  F f -> pure $ JsLit (JsFloat f)
  T t -> pure $ JsLit (JsString (Util.Text.toText t))
  C c -> pure $ JsLit (JsString (Text.singleton c))
  LM _ref -> pure $ JsLit JsNull -- Term link (simplified)
  LY _ref -> pure $ JsLit JsNull -- Type link (simplified)

-- | Emit pattern match
emitMatch :: (Var v) => JsExpr -> Branched Reference (ANormal Reference v) -> Emit v [JsStmt]
emitMatch scrutinee branches = case branches of
  MatchIntegral cases maybeDefault -> do
    let tagExpr = scrutinee
    stmts <- emitIntCases tagExpr (EC.mapToList cases)
    defStmts <- case maybeDefault of
      Nothing -> pure []
      Just def -> emitNormal def
    pure $ stmts ++ defStmts
  MatchData _ref cases maybeDefault -> do
    let tagExpr = JsProp scrutinee "tag"
    stmts <- emitDataCases scrutinee tagExpr (EC.mapToList cases)
    defStmts <- case maybeDefault of
      Nothing -> pure []
      Just def -> emitNormal def
    pure $ stmts ++ defStmts
  MatchText cases maybeDefault -> do
    stmts <- emitTextCases scrutinee (Map.toList cases)
    defStmts <- case maybeDefault of
      Nothing -> pure []
      Just def -> emitNormal def
    pure $ stmts ++ defStmts
  MatchEmpty ->
    pure [JsThrow (JsLit (JsString "empty match"))]
  MatchSum cases -> do
    let tagExpr = JsProp scrutinee "tag"
    emitSumCases scrutinee tagExpr (EC.mapToList cases)
  MatchRequest _cases _default ->
    -- Effect request matching (complex, simplified here)
    pure [JsReturn (JsCall (JsVar "$matchRequest") [scrutinee])]
  MatchNumeric _ref cases maybeDefault -> do
    stmts <- emitIntCases scrutinee (EC.mapToList cases)
    defStmts <- case maybeDefault of
      Nothing -> pure []
      Just def -> emitNormal def
    pure $ stmts ++ defStmts

-- | Emit integer case branches
emitIntCases :: (Var v) => JsExpr -> [(Word64, ANormal Reference v)] -> Emit v [JsStmt]
emitIntCases scrutinee cases = do
  foldM (emitIntCase scrutinee) [] (reverse cases)
  where
    emitIntCase scrut acc (val, body) = do
      bodyStmts <- emitNormal body
      let cond = JsBinOp "===" scrut (JsLit (JsInt (fromIntegral val)))
      pure [JsIf cond bodyStmts acc]

-- | Emit data constructor cases
emitDataCases :: (Var v) => JsExpr -> JsExpr -> [(CTag, ([Mem], ANormal Reference v))] -> Emit v [JsStmt]
emitDataCases scrutinee tagExpr cases = do
  foldM (emitDataCase scrutinee tagExpr) [] (reverse cases)
  where
    emitDataCase scrut tag acc (CTag ctag, (mems, body)) = do
      -- Bind constructor fields
      bindings <- forM (zip [0 :: Int ..] mems) $ \(i, _mem) -> do
        name <- freshName "$field"
        pure $ JsConst name (JsIndex (JsProp scrut "fields") (JsLit (JsInt (fromIntegral i))))
      bodyStmts <- emitNormal body
      let cond = JsBinOp "===" tag (JsLit (JsInt (fromIntegral ctag)))
      pure [JsIf cond (bindings ++ bodyStmts) acc]

-- | Emit sum type cases
emitSumCases :: (Var v) => JsExpr -> JsExpr -> [(Word64, ([Mem], ANormal Reference v))] -> Emit v [JsStmt]
emitSumCases scrutinee tagExpr cases = do
  foldM (emitSumCase scrutinee tagExpr) [] (reverse cases)
  where
    emitSumCase scrut tag acc (ctag, (mems, body)) = do
      bindings <- forM (zip [0 :: Int ..] mems) $ \(i, _mem) -> do
        name <- freshName "$field"
        pure $ JsConst name (JsIndex (JsProp scrut "fields") (JsLit (JsInt (fromIntegral i))))
      bodyStmts <- emitNormal body
      let cond = JsBinOp "===" tag (JsLit (JsInt (fromIntegral ctag)))
      pure [JsIf cond (bindings ++ bodyStmts) acc]

-- | Emit text case branches
emitTextCases :: (Var v) => JsExpr -> [(Util.Text.Text, ANormal Reference v)] -> Emit v [JsStmt]
emitTextCases scrutinee cases = do
  foldM (emitTextCase scrutinee) [] (reverse cases)
  where
    emitTextCase scrut acc (txt, body) = do
      bodyStmts <- emitNormal body
      let cond = JsBinOp "===" scrut (JsLit (JsString (Util.Text.toText txt)))
      pure [JsIf cond bodyStmts acc]

-- | Get JS expression for a variable
getVarExpr :: (Var v) => v -> Emit v JsExpr
getVarExpr v = JsVar <$> getVarName v

-- | Convert a Reference to a JS-safe name
refToName :: Reference -> Text
refToName ref = case ref of
  Reference.Builtin name -> "$builtin_" <> sanitizeName name
  Reference.DerivedId (Reference.Id hash _) ->
    "$h" <> Text.take 10 (Hash.toBase32HexText hash)

-- | Sanitize a name for use as a JS identifier
sanitizeName :: Text -> Text
sanitizeName = Text.map sanitizeChar
  where
    sanitizeChar c
      | c `elem` ['a' .. 'z'] = c
      | c `elem` ['A' .. 'Z'] = c
      | c `elem` ['0' .. '9'] = c
      | c == '_' = c
      | otherwise = '_'
