{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE OverloadedStrings #-}

-- | JavaScript AST types for code generation.
--
-- This module provides a minimal JavaScript AST sufficient for
-- transpiling Unison ANF to JavaScript. The AST is designed to
-- produce readable, debuggable output.
module Unison.Runtime.JavaScript.Types
  ( -- * Expressions
    JsExpr (..),
    JsLiteral (..),

    -- * Statements
    JsStmt (..),
    JsBody (..),

    -- * Declarations
    JsDecl (..),

    -- * Modules
    JsModule (..),

    -- * Helpers
    jsVar,
    jsInt,
    jsNat,
    jsFloat,
    jsBool,
    jsString,
    jsNull,
    jsCall,
    jsBinOp,
    jsArrow,
    jsReturn,
    jsConst,
    jsIf,
  )
where

import Data.Text (Text)

-- | JavaScript expressions
data JsExpr
  = -- | Variable reference
    JsVar Text
  | -- | Literal value
    JsLit JsLiteral
  | -- | Binary operation: @a op b@
    JsBinOp Text JsExpr JsExpr
  | -- | Unary operation: @op a@
    JsUnaryOp Text JsExpr
  | -- | Function call: @f(args)@
    JsCall JsExpr [JsExpr]
  | -- | Array/object indexing: @a[i]@
    JsIndex JsExpr JsExpr
  | -- | Property access: @a.prop@
    JsProp JsExpr Text
  | -- | Arrow function: @(params) => body@
    JsArrow [Text] JsBody
  | -- | Ternary conditional: @cond ? then : else@
    JsTernary JsExpr JsExpr JsExpr
  | -- | Array literal: @[a, b, c]@
    JsArray [JsExpr]
  | -- | Object literal: @{key: value, ...}@
    JsObject [(Text, JsExpr)]
  | -- | Yield expression (for generators): @yield expr@
    JsYield JsExpr
  | -- | Yield* expression (for generators): @yield* expr@
    JsYieldStar JsExpr
  | -- | Spread operator: @...expr@
    JsSpread JsExpr
  | -- | Raw JavaScript (escape hatch, use sparingly)
    JsRaw Text
  deriving (Show, Eq)

-- | JavaScript literal values
data JsLiteral
  = -- | BigInt literal (for Unison Int/Nat): @123n@
    JsInt Integer
  | -- | Number literal (for Unison Float): @123.45@
    JsFloat Double
  | -- | Boolean literal: @true@ or @false@
    JsBool Bool
  | -- | String literal: @"hello"@
    JsString Text
  | -- | null
    JsNull
  | -- | undefined
    JsUndefined
  deriving (Show, Eq)

-- | JavaScript statements
data JsStmt
  = -- | Expression statement: @expr;@
    JsExprStmt JsExpr
  | -- | Return statement: @return expr;@
    JsReturn JsExpr
  | -- | Let declaration: @let name = expr;@ or @let name;@
    JsLet Text (Maybe JsExpr)
  | -- | Const declaration: @const name = expr;@
    JsConst Text JsExpr
  | -- | If/else statement
    JsIf JsExpr [JsStmt] [JsStmt]
  | -- | While loop
    JsWhile JsExpr [JsStmt]
  | -- | Block of statements: @{ stmts }@
    JsBlock [JsStmt]
  | -- | Throw statement: @throw expr;@
    JsThrow JsExpr
  | -- | Continue statement
    JsContinue
  | -- | Break statement
    JsBreak
  deriving (Show, Eq)

-- | Arrow function body (concise or block)
data JsBody
  = -- | Concise arrow body: @=> expr@
    JsExprBody JsExpr
  | -- | Block arrow body: @=> { stmts }@
    JsBlockBody [JsStmt]
  deriving (Show, Eq)

-- | JavaScript top-level declarations
data JsDecl
  = -- | Function declaration: @function name(params) { body }@
    -- The Bool indicates if it's a generator function (function*)
    JsFunctionDecl Text [Text] [JsStmt] Bool
  | -- | Const declaration: @const name = expr;@
    JsConstDecl Text JsExpr
  | -- | Export declaration: @export { names }@
    JsExport [Text]
  | -- | Import declaration: @import { names } from "module"@
    JsImport [Text] Text
  deriving (Show, Eq)

-- | A complete JavaScript module
data JsModule = JsModule
  { -- | Import declarations
    jsImports :: [(Text, [Text])],
    -- | Top-level declarations
    jsDecls :: [JsDecl],
    -- | Exported names
    jsExports :: [Text]
  }
  deriving (Show, Eq)

-- Smart constructors for common patterns

-- | Create a variable reference
jsVar :: Text -> JsExpr
jsVar = JsVar

-- | Create a BigInt literal (for Int)
jsInt :: Integer -> JsExpr
jsInt = JsLit . JsInt

-- | Create a BigInt literal (for Nat, same as jsInt)
jsNat :: Integer -> JsExpr
jsNat = JsLit . JsInt

-- | Create a Number literal (for Float)
jsFloat :: Double -> JsExpr
jsFloat = JsLit . JsFloat

-- | Create a Boolean literal
jsBool :: Bool -> JsExpr
jsBool = JsLit . JsBool

-- | Create a String literal
jsString :: Text -> JsExpr
jsString = JsLit . JsString

-- | Create null
jsNull :: JsExpr
jsNull = JsLit JsNull

-- | Create a function call
jsCall :: JsExpr -> [JsExpr] -> JsExpr
jsCall = JsCall

-- | Create a binary operation
jsBinOp :: Text -> JsExpr -> JsExpr -> JsExpr
jsBinOp op a b = JsBinOp op a b

-- | Create an arrow function
jsArrow :: [Text] -> JsBody -> JsExpr
jsArrow = JsArrow

-- | Create a return statement
jsReturn :: JsExpr -> JsStmt
jsReturn = JsReturn

-- | Create a const declaration
jsConst :: Text -> JsExpr -> JsStmt
jsConst = JsConst

-- | Create an if statement
jsIf :: JsExpr -> [JsStmt] -> [JsStmt] -> JsStmt
jsIf = JsIf
