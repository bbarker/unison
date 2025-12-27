{-# LANGUAGE OverloadedStrings #-}

-- | Render JavaScript AST to Text.
--
-- This module provides functions to convert the JavaScript AST
-- to readable, properly formatted JavaScript source code.
module Unison.Runtime.JavaScript.Render
  ( -- * Rendering
    renderModule,
    renderDecl,
    renderStmt,
    renderExpr,

    -- * Configuration
    RenderConfig (..),
    defaultConfig,
    minifiedConfig,
  )
where

import Data.List (intersperse)
import Data.Text (Text)
import Data.Text qualified as Text
import Unison.Runtime.JavaScript.Types

-- | Configuration for rendering
data RenderConfig = RenderConfig
  { -- | Indentation string (e.g., "  " for 2 spaces)
    rcIndent :: Text,
    -- | Whether to include newlines
    rcNewlines :: Bool,
    -- | Whether to include spaces around operators
    rcSpaces :: Bool
  }
  deriving (Show, Eq)

-- | Default configuration: 2-space indentation, newlines, spaces
defaultConfig :: RenderConfig
defaultConfig =
  RenderConfig
    { rcIndent = "  ",
      rcNewlines = True,
      rcSpaces = True
    }

-- | Minified configuration: no indentation, no newlines, minimal spaces
minifiedConfig :: RenderConfig
minifiedConfig =
  RenderConfig
    { rcIndent = "",
      rcNewlines = False,
      rcSpaces = False
    }

-- | Render a complete module
renderModule :: RenderConfig -> JsModule -> Text
renderModule cfg (JsModule imports decls exports) =
  Text.concat
    [ renderImports cfg imports,
      if null imports then "" else newline cfg,
      Text.concat $ intersperse (newline cfg <> newline cfg) (map (renderDecl cfg 0) decls),
      if null exports then "" else newline cfg <> renderExports cfg exports
    ]

-- | Render import declarations
renderImports :: RenderConfig -> [(Text, [Text])] -> Text
renderImports cfg imports =
  Text.concat $ intersperse (newline cfg) $ map renderImport imports
  where
    renderImport (modName, names) =
      "import { " <> Text.intercalate ", " names <> " } from " <> quote modName <> ";"

-- | Render export declaration
renderExports :: RenderConfig -> [Text] -> Text
renderExports _cfg names =
  "export { " <> Text.intercalate ", " names <> " };"

-- | Render a top-level declaration
renderDecl :: RenderConfig -> Int -> JsDecl -> Text
renderDecl cfg depth decl = case decl of
  JsFunctionDecl name params body isGenerator ->
    let fnKeyword = if isGenerator then "function* " else "function "
        paramsText = "(" <> Text.intercalate ", " params <> ")"
        bodyText = renderBlock cfg depth body
     in fnKeyword <> name <> paramsText <> space cfg <> bodyText
  JsConstDecl name expr ->
    "const " <> name <> space cfg <> "=" <> space cfg <> renderExpr cfg depth expr <> ";"
  JsExport names ->
    renderExports cfg names
  JsImport names modName ->
    "import { " <> Text.intercalate ", " names <> " } from " <> quote modName <> ";"

-- | Render a block of statements
renderBlock :: RenderConfig -> Int -> [JsStmt] -> Text
renderBlock cfg depth stmts =
  "{"
    <> newline cfg
    <> Text.concat (map (\s -> indent cfg (depth + 1) <> renderStmt cfg (depth + 1) s <> newline cfg) stmts)
    <> indent cfg depth
    <> "}"

-- | Render a statement
renderStmt :: RenderConfig -> Int -> JsStmt -> Text
renderStmt cfg depth stmt = case stmt of
  JsExprStmt expr ->
    renderExpr cfg depth expr <> ";"
  JsReturn expr ->
    "return " <> renderExpr cfg depth expr <> ";"
  JsLet name Nothing ->
    "let " <> name <> ";"
  JsLet name (Just expr) ->
    "let " <> name <> space cfg <> "=" <> space cfg <> renderExpr cfg depth expr <> ";"
  JsConst name expr ->
    "const " <> name <> space cfg <> "=" <> space cfg <> renderExpr cfg depth expr <> ";"
  JsIf cond thenStmts elseStmts ->
    "if ("
      <> renderExpr cfg depth cond
      <> ")"
      <> space cfg
      <> renderBlock cfg depth thenStmts
      <> if null elseStmts
        then ""
        else space cfg <> "else" <> space cfg <> renderBlock cfg depth elseStmts
  JsWhile cond body ->
    "while (" <> renderExpr cfg depth cond <> ")" <> space cfg <> renderBlock cfg depth body
  JsBlock stmts ->
    renderBlock cfg depth stmts
  JsThrow expr ->
    "throw " <> renderExpr cfg depth expr <> ";"
  JsContinue ->
    "continue;"
  JsBreak ->
    "break;"

-- | Render an expression
renderExpr :: RenderConfig -> Int -> JsExpr -> Text
renderExpr cfg depth expr = case expr of
  JsVar name ->
    name
  JsLit lit ->
    renderLiteral lit
  JsBinOp op left right ->
    "(" <> renderExpr cfg depth left <> space cfg <> op <> space cfg <> renderExpr cfg depth right <> ")"
  JsUnaryOp op operand ->
    op <> renderExpr cfg depth operand
  JsCall fn args ->
    renderExpr cfg depth fn <> "(" <> Text.intercalate ", " (map (renderExpr cfg depth) args) <> ")"
  JsIndex arr idx ->
    renderExpr cfg depth arr <> "[" <> renderExpr cfg depth idx <> "]"
  JsProp obj prop ->
    renderExpr cfg depth obj <> "." <> prop
  JsArrow params body ->
    let paramsText = case params of
          [p] -> p
          _ -> "(" <> Text.intercalate ", " params <> ")"
     in paramsText <> space cfg <> "=>" <> space cfg <> renderBody cfg depth body
  JsTernary cond thenExpr elseExpr ->
    "("
      <> renderExpr cfg depth cond
      <> space cfg
      <> "?"
      <> space cfg
      <> renderExpr cfg depth thenExpr
      <> space cfg
      <> ":"
      <> space cfg
      <> renderExpr cfg depth elseExpr
      <> ")"
  JsArray elems ->
    "[" <> Text.intercalate ", " (map (renderExpr cfg depth) elems) <> "]"
  JsObject props ->
    let renderProp (k, v) = k <> ":" <> space cfg <> renderExpr cfg depth v
     in "{" <> space cfg <> Text.intercalate ", " (map renderProp props) <> space cfg <> "}"
  JsYield e ->
    "yield " <> renderExpr cfg depth e
  JsYieldStar e ->
    "yield* " <> renderExpr cfg depth e
  JsSpread e ->
    "..." <> renderExpr cfg depth e
  JsRaw text ->
    text

-- | Render an arrow function body
renderBody :: RenderConfig -> Int -> JsBody -> Text
renderBody cfg depth body = case body of
  JsExprBody expr ->
    renderExpr cfg depth expr
  JsBlockBody stmts ->
    renderBlock cfg depth stmts

-- | Render a literal value
renderLiteral :: JsLiteral -> Text
renderLiteral lit = case lit of
  JsInt n ->
    Text.pack (show n) <> "n"
  JsFloat f ->
    Text.pack (show f)
  JsBool True ->
    "true"
  JsBool False ->
    "false"
  JsString s ->
    quote s
  JsNull ->
    "null"
  JsUndefined ->
    "undefined"

-- Helper functions

-- | Add indentation
indent :: RenderConfig -> Int -> Text
indent cfg n = Text.concat $ replicate n (rcIndent cfg)

-- | Newline or empty if minified
newline :: RenderConfig -> Text
newline cfg = if rcNewlines cfg then "\n" else ""

-- | Space or empty if minified
space :: RenderConfig -> Text
space cfg = if rcSpaces cfg then " " else ""

-- | Quote a string with proper escaping
quote :: Text -> Text
quote s = "\"" <> escapeString s <> "\""

-- | Escape special characters in a string
escapeString :: Text -> Text
escapeString =
  Text.concatMap escapeChar
  where
    escapeChar c = case c of
      '"' -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\r' -> "\\r"
      '\t' -> "\\t"
      _ -> Text.singleton c
