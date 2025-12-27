{-# LANGUAGE OverloadedStrings #-}

-- | Intrinsic mappings from Unison primitive operations to JavaScript.
--
-- This module provides JavaScript implementations for all Unison
-- primitive operations (POp). Most operations map directly to
-- JavaScript operators or built-in functions.
--
-- Notes on number representation:
-- - Unison Int/Nat use arbitrary precision, mapped to JavaScript BigInt
-- - Unison Float uses 64-bit IEEE 754, mapped to JavaScript Number
-- - BigInt operations use the 'n' suffix for literals (e.g., 1n)
module Unison.Runtime.JavaScript.Intrinsics
  ( emitPOp,
    runtimeFunctions,
  )
where

import Data.Text (Text)
import Unison.Runtime.ANF.POp (POp (..))
import Unison.Runtime.JavaScript.Types

-- | Emit JavaScript for a primitive operation
emitPOp :: POp -> [JsExpr] -> JsExpr
emitPOp op args = case op of
  -- Int operations (BigInt)
  ADDI -> binOp "+" args
  SUBI -> binOp "-" args
  MULI -> binOp "*" args
  DIVI -> binOp "/" args -- BigInt division truncates
  MODI -> binOp "%" args
  SGNI -> jsCall (jsVar "$signum") args
  NEGI -> JsUnaryOp "-" (head args)
  POWI -> jsCall (jsVar "$pow") args -- BigInt doesn't have **
  SHLI -> binOp "<<" args
  SHRI -> binOp ">>" args
  ANDI -> binOp "&" args
  IORI -> binOp "|" args
  XORI -> binOp "^" args
  COMI -> JsUnaryOp "~" (head args)
  INCI -> binOp "+" [head args, jsInt 1]
  DECI -> binOp "-" [head args, jsInt 1]
  LEQI -> binOp "<=" args
  LESI -> binOp "<" args
  EQLI -> binOp "===" args
  NEQI -> binOp "!==" args
  TRNC -> jsCall (jsVar "$truncate0") args
  -- Nat operations (BigInt, but unsigned semantics)
  ADDN -> binOp "+" args
  SUBN -> jsCall (jsVar "$natSub") args -- saturating subtraction
  DRPN -> jsCall (jsVar "$natSub") args -- same as SUBN
  MULN -> binOp "*" args
  DIVN -> binOp "/" args
  MODN -> binOp "%" args
  TZRO -> jsCall (jsVar "$trailingZeros") args
  LZRO -> jsCall (jsVar "$leadingZeros") args
  POPC -> jsCall (jsVar "$popCount") args
  POWN -> jsCall (jsVar "$pow") args
  SHLN -> binOp "<<" args
  SHRN -> binOp ">>" args
  ANDN -> binOp "&" args
  IORN -> binOp "|" args
  XORN -> binOp "^" args
  COMN -> JsUnaryOp "~" (head args)
  INCN -> binOp "+" [head args, jsInt 1]
  DECN -> binOp "-" [head args, jsInt 1]
  LEQN -> binOp "<=" args
  LESN -> binOp "<" args
  EQLN -> binOp "===" args
  NEQN -> binOp "!==" args
  -- Float operations (Number)
  ADDF -> binOp "+" args
  SUBF -> binOp "-" args
  MULF -> binOp "*" args
  DIVF -> binOp "/" args
  MINF -> jsCall (jsVar "Math.min") args
  MAXF -> jsCall (jsVar "Math.max") args
  LEQF -> binOp "<=" args
  LESF -> binOp "<" args
  EQLF -> binOp "===" args
  NEQF -> binOp "!==" args
  POWF -> jsCall (jsVar "Math.pow") args
  EXPF -> jsCall (jsVar "Math.exp") args
  SQRT -> jsCall (jsVar "Math.sqrt") args
  LOGF -> jsCall (jsVar "Math.log") args
  LOGB -> jsCall (jsVar "$logBase") args
  ABSF -> jsCall (jsVar "Math.abs") args
  CEIL -> jsCall (jsVar "Math.ceil") args
  FLOR -> jsCall (jsVar "Math.floor") args
  TRNF -> jsCall (jsVar "Math.trunc") args
  RNDF -> jsCall (jsVar "Math.round") args
  -- Trig (Float -> Float)
  COSF -> jsCall (jsVar "Math.cos") args
  ACOS -> jsCall (jsVar "Math.acos") args
  COSH -> jsCall (jsVar "Math.cosh") args
  ACSH -> jsCall (jsVar "Math.acosh") args
  SINF -> jsCall (jsVar "Math.sin") args
  ASIN -> jsCall (jsVar "Math.asin") args
  SINH -> jsCall (jsVar "Math.sinh") args
  ASNH -> jsCall (jsVar "Math.asinh") args
  TANF -> jsCall (jsVar "Math.tan") args
  ATAN -> jsCall (jsVar "Math.atan") args
  TANH -> jsCall (jsVar "Math.tanh") args
  ATNH -> jsCall (jsVar "Math.atanh") args
  ATN2 -> jsCall (jsVar "Math.atan2") args
  -- Text operations
  CATT -> binOp "+" args
  TAKT -> jsCall (JsProp (head args) "substring") [jsInt 0, args !! 1]
  DRPT -> jsCall (JsProp (head args) "substring") [args !! 1]
  SIZT -> JsProp (head args) "length"
  IXOT -> jsCall (jsVar "$textIndexOf") args
  UCNS -> jsCall (jsVar "$textUncons") args
  USNC -> jsCall (jsVar "$textUnsnoc") args
  EQLT -> binOp "===" args
  LEQT -> binOp "<=" args
  PAKT -> jsCall (JsProp (jsVar "Array") "from") [head args, jsArrow ["c"] (JsExprBody (jsVar "c"))]
  UPKT -> jsCall (JsProp (head args) "split") [jsString ""]
  -- Sequence/List operations
  CATS -> jsCall (JsProp (head args) "concat") [args !! 1]
  TAKS -> jsCall (JsProp (head args) "slice") [jsInt 0, args !! 1]
  DRPS -> jsCall (JsProp (head args) "slice") [args !! 1]
  SIZS -> JsProp (head args) "length"
  CONS -> JsArray [head args, JsSpread (args !! 1)]
  SNOC -> jsCall (JsProp (head args) "concat") [JsArray [args !! 1]]
  IDXS -> JsIndex (head args) (args !! 1)
  BLDS -> jsCall (jsVar "$buildList") args
  VWLS -> jsCall (jsVar "$viewLeft") args
  VWRS -> jsCall (jsVar "$viewRight") args
  SPLL -> jsCall (jsVar "$splitLeft") args
  SPLR -> jsCall (jsVar "$splitRight") args
  -- Bytes operations
  PAKB -> jsCall (jsVar "$packBytes") args
  UPKB -> jsCall (jsVar "$unpackBytes") args
  TAKB -> jsCall (JsProp (head args) "slice") [jsInt 0, args !! 1]
  DRPB -> jsCall (JsProp (head args) "slice") [args !! 1]
  IXOB -> jsCall (jsVar "$bytesIndexOf") args
  IDXB -> JsIndex (head args) (args !! 1)
  SIZB -> JsProp (head args) "length"
  FLTB -> jsCall (jsVar "$flattenBytes") args
  CATB -> jsCall (jsVar "$concatBytes") args
  -- Conversion operations
  ITOF -> jsCall (jsVar "Number") args
  NTOF -> jsCall (jsVar "Number") args
  ITOT -> jsCall (JsProp (head args) "toString") []
  NTOT -> jsCall (JsProp (head args) "toString") []
  TTOI -> jsCall (jsVar "$textToInt") args
  TTON -> jsCall (jsVar "$textToNat") args
  TTOF -> jsCall (jsVar "parseFloat") args
  FTOT -> jsCall (JsProp (head args) "toString") []
  CAST -> head args -- Type cast is a no-op at runtime
  -- Concurrency (not supported in pure JS, stub)
  FORK -> jsCall (jsVar "$fork") args
  -- Universal operations
  EQLU -> jsCall (jsVar "$deepEqual") args
  CMPU -> jsCall (jsVar "$compare") args
  LEQU -> jsCall (jsVar "$lessOrEqual") args
  LESU -> jsCall (jsVar "$lessThan") args
  EROR -> jsCall (jsVar "$error") args
  -- Code operations (not supported, stubs)
  MISS -> jsCall (jsVar "$isMissing") args
  CACH -> jsCall (jsVar "$cache") args
  LKUP -> jsCall (jsVar "$lookup") args
  LOAD -> jsCall (jsVar "$load") args
  CVLD -> jsCall (jsVar "$validate") args
  SDBX -> jsCall (jsVar "$sandbox") args
  VALU -> jsCall (jsVar "$value") args
  TLTT -> jsCall (jsVar "$termLinkToText") args
  -- Debug operations
  PRNT -> jsCall (JsProp (jsVar "console") "log") args
  INFO -> jsCall (JsProp (jsVar "console") "info") args
  TRCE -> jsCall (jsVar "$trace") args
  DBTX -> jsCall (jsVar "$debugText") args
  -- STM (not supported, stubs)
  ATOM -> jsCall (jsVar "$atomically") args
  TFRC -> jsCall (jsVar "$tryForce") args
  SDBL -> jsCall (jsVar "$sandboxLinks") args
  SDBV -> jsCall (jsVar "$sandboxValues") args
  -- Refs (mutable references)
  REFN -> jsCall (jsVar "$refNew") args
  REFR -> jsCall (jsVar "$refRead") args
  REFW -> jsCall (jsVar "$refWrite") args
  RCAS -> jsCall (jsVar "$refCas") args
  RRFC -> jsCall (jsVar "$refReadForCas") args
  TIKR -> jsCall (jsVar "$ticketRead") args
  -- Boolean operations
  NOTB -> JsUnaryOp "!" (head args)
  ANDB -> binOp "&&" args
  IORB -> binOp "||" args

-- | Helper for binary operators
binOp :: Text -> [JsExpr] -> JsExpr
binOp op [a, b] = JsBinOp op a b
binOp op xs = error $ "binOp " <> show op <> " requires exactly 2 arguments, got " <> show (length xs)

-- | Runtime helper functions that need to be included
--
-- These are small JavaScript functions that implement operations
-- that don't have direct JS equivalents.
runtimeFunctions :: Text
runtimeFunctions =
  "// Unison-to-JavaScript runtime helpers\n\
  \\n\
  \// Saturating subtraction for Nat\n\
  \const $natSub = (a, b) => { const r = a - b; return r < 0n ? 0n : r; };\n\
  \\n\
  \// BigInt power (** doesn't work with BigInt in all cases)\n\
  \const $pow = (base, exp) => {\n\
  \  if (exp < 0n) return 0n;\n\
  \  let result = 1n;\n\
  \  while (exp > 0n) {\n\
  \    if (exp % 2n === 1n) result *= base;\n\
  \    base *= base;\n\
  \    exp /= 2n;\n\
  \  }\n\
  \  return result;\n\
  \};\n\
  \\n\
  \// Signum for BigInt\n\
  \const $signum = (n) => n > 0n ? 1n : n < 0n ? -1n : 0n;\n\
  \\n\
  \// Truncate to zero (for negative division)\n\
  \const $truncate0 = (n) => n < 0n ? -(-n / 1n) : n / 1n;\n\
  \\n\
  \// Log base for Float\n\
  \const $logBase = (base, x) => Math.log(x) / Math.log(base);\n\
  \\n\
  \// Trailing zeros for BigInt\n\
  \const $trailingZeros = (n) => {\n\
  \  if (n === 0n) return 64n;\n\
  \  let count = 0n;\n\
  \  while ((n & 1n) === 0n) { n >>= 1n; count++; }\n\
  \  return count;\n\
  \};\n\
  \\n\
  \// Leading zeros for BigInt (assuming 64-bit)\n\
  \const $leadingZeros = (n) => {\n\
  \  if (n === 0n) return 64n;\n\
  \  let count = 0n;\n\
  \  let mask = 1n << 63n;\n\
  \  while ((n & mask) === 0n && mask > 0n) { mask >>= 1n; count++; }\n\
  \  return count;\n\
  \};\n\
  \\n\
  \// Pop count for BigInt\n\
  \const $popCount = (n) => {\n\
  \  let count = 0n;\n\
  \  while (n > 0n) { count += n & 1n; n >>= 1n; }\n\
  \  return count;\n\
  \};\n\
  \\n\
  \// Text indexOf returning Optional\n\
  \const $textIndexOf = (needle, haystack) => {\n\
  \  const idx = haystack.indexOf(needle);\n\
  \  return idx === -1 ? { tag: 0 } : { tag: 1, value: BigInt(idx) };\n\
  \};\n\
  \\n\
  \// Text uncons\n\
  \const $textUncons = (s) => {\n\
  \  if (s.length === 0) return { tag: 0 };\n\
  \  return { tag: 1, value: [s[0], s.slice(1)] };\n\
  \};\n\
  \\n\
  \// Text unsnoc\n\
  \const $textUnsnoc = (s) => {\n\
  \  if (s.length === 0) return { tag: 0 };\n\
  \  return { tag: 1, value: [s.slice(0, -1), s[s.length - 1]] };\n\
  \};\n\
  \\n\
  \// List view left\n\
  \const $viewLeft = (xs) => {\n\
  \  if (xs.length === 0) return { tag: 0 };\n\
  \  return { tag: 1, value: [xs[0], xs.slice(1)] };\n\
  \};\n\
  \\n\
  \// List view right\n\
  \const $viewRight = (xs) => {\n\
  \  if (xs.length === 0) return { tag: 0 };\n\
  \  return { tag: 1, value: [xs.slice(0, -1), xs[xs.length - 1]] };\n\
  \};\n\
  \\n\
  \// Deep equality\n\
  \const $deepEqual = (a, b) => {\n\
  \  if (a === b) return true;\n\
  \  if (typeof a !== typeof b) return false;\n\
  \  if (typeof a !== 'object' || a === null) return false;\n\
  \  if (a.tag !== b.tag) return false;\n\
  \  if (Array.isArray(a.fields) && Array.isArray(b.fields)) {\n\
  \    if (a.fields.length !== b.fields.length) return false;\n\
  \    return a.fields.every((f, i) => $deepEqual(f, b.fields[i]));\n\
  \  }\n\
  \  if (Array.isArray(a) && Array.isArray(b)) {\n\
  \    if (a.length !== b.length) return false;\n\
  \    return a.every((el, i) => $deepEqual(el, b[i]));\n\
  \  }\n\
  \  return false;\n\
  \};\n\
  \\n\
  \// Comparison\n\
  \const $compare = (a, b) => a < b ? -1n : a > b ? 1n : 0n;\n\
  \const $lessOrEqual = (a, b) => $compare(a, b) <= 0n;\n\
  \const $lessThan = (a, b) => $compare(a, b) < 0n;\n\
  \\n\
  \// Error\n\
  \const $error = (msg) => { throw new Error(msg); };\n\
  \\n\
  \// Trace (debug)\n\
  \const $trace = (msg, val) => { console.log(msg, val); return val; };\n\
  \\n\
  \// Mutable references\n\
  \const $refNew = (val) => ({ value: val });\n\
  \const $refRead = (ref) => ref.value;\n\
  \const $refWrite = (ref, val) => { ref.value = val; };\n\
  \const $refCas = (ref, expected, newVal) => {\n\
  \  if ($deepEqual(ref.value, expected)) { ref.value = newVal; return true; }\n\
  \  return false;\n\
  \};\n\
  \\n\
  \// Text to Int/Nat\n\
  \const $textToInt = (s) => {\n\
  \  try { return { tag: 1, value: BigInt(s) }; }\n\
  \  catch { return { tag: 0 }; }\n\
  \};\n\
  \const $textToNat = (s) => {\n\
  \  try {\n\
  \    const n = BigInt(s);\n\
  \    return n >= 0n ? { tag: 1, value: n } : { tag: 0 };\n\
  \  } catch { return { tag: 0 }; }\n\
  \};\n\
  \\n\
  \// Effect runtime\n\
  \function $runEffect(gen, handlers) {\n\
  \  const iter = typeof gen === 'function' ? gen() : gen;\n\
  \  function step(input) {\n\
  \    const { done, value } = iter.next(input);\n\
  \    if (done) return value;\n\
  \    if (value && value.type === 'effect') {\n\
  \      const handler = handlers[value.ability];\n\
  \      if (handler && handler[value.op]) {\n\
  \        return handler[value.op](value.args, step);\n\
  \      }\n\
  \      throw new Error(`Unhandled effect: ${value.ability}.${value.op}`);\n\
  \    }\n\
  \    return step(value);\n\
  \  }\n\
  \  return step(undefined);\n\
  \}\n\
  \\n\
  \// Perform an effect\n\
  \function* $perform(ability, op, args) {\n\
  \  return yield { type: 'effect', ability, op, args };\n\
  \}\n\
  \\n\
  \// Data constructor\n\
  \const $con = (tag, ...fields) => ({ tag, fields });\n\
  \"
