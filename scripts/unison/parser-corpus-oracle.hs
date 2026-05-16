{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM)
import Data.Functor.Identity (Identity (..), runIdentity)
import Data.List (isSuffixOf, sort)
import qualified Data.Map as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import System.Directory (doesDirectoryExist, listDirectory, makeAbsolute)
import System.Environment (getArgs)
import System.FilePath ((</>), makeRelative)
import Unison.Builtin qualified as B
import Unison.Parser.Ann qualified as ParserAnn
import Unison.Parsers qualified as Parsers
import Unison.PrintError (prettyParseError)
import Unison.Symbol (Symbol)
import Unison.Syntax.Parser qualified as Parser
import Unison.UnisonFile.Type qualified as UF
import Unison.Util.Pretty qualified as Pr

data Options = Options
  { repoRoot :: FilePath,
    outputPath :: FilePath,
    maxCases :: Maybe Int
  }

defaultOptions :: Options
defaultOptions =
  Options
    { repoRoot = ".",
      outputPath = "scripts/unison/baselines/parser-corpus/reference-parse-kinds.tsv",
      maxCases = Nothing
    }

usage :: String
usage =
  unlines
    [ "Usage: stack runghc scripts/unison/parser-corpus-oracle.hs [options]",
      "",
      "Options:",
      "  --repo-root PATH   Repository root (default: .)",
      "  --output PATH      Output TSV path",
      "  --max-cases N      Limit number of files (for quick iteration)",
      "  -h, --help         Show this help"
    ]

parseArgs :: Options -> [String] -> Either String Options
parseArgs opts = \case
  [] -> Right opts
  ["-h"] -> Left usage
  ["--help"] -> Left usage
  "--repo-root" : path : rest -> parseArgs opts {repoRoot = path} rest
  "--output" : path : rest -> parseArgs opts {outputPath = path} rest
  "--max-cases" : n : rest -> case reads n of
    [(k, "")] | k >= 0 -> parseArgs opts {maxCases = Just k} rest
    _ -> Left ("Invalid --max-cases value: " <> n)
  bad : _ -> Left ("Unknown argument: " <> bad)

findUnisonFiles :: FilePath -> IO [FilePath]
findUnisonFiles root = do
  entries <- listDirectory root
  paths <- forM entries $ \entry -> do
    let path = root </> entry
    isDir <- doesDirectoryExist path
    if isDir
      then findUnisonFiles path
      else pure [path | ".u" `isSuffixOf` entry]
  pure (concat paths)

sanitizeDetail :: String -> String
sanitizeDetail =
  map
    ( \c ->
        if c == '\t' || c == '\n' || c == '\r' then ' ' else c
    )

sanitizeFieldText :: Text.Text -> Text.Text
sanitizeFieldText =
  Text.map
    ( \c ->
        if c == '\t' || c == '\n' || c == '\r' then ' ' else c
    )

renderSymbolList :: [Text.Text] -> Text.Text
renderSymbolList symbols = Text.intercalate "," (sort (map sanitizeFieldText symbols))

renderShapeSummary :: UF.UnisonFile Symbol ParserAnn.Ann -> Text.Text
renderShapeSummary uf =
  let termNames = map (Text.pack . show) (Map.keys (UF.terms uf))
      typeNames = map (Text.pack . show) (Map.keys (UF.dataDeclarationsId uf))
      abilityNames = map (Text.pack . show) (Map.keys (UF.effectDeclarationsId uf))
   in
    Text.concat
      [ "terms=",
        renderSymbolList termNames,
        ";types=",
        renderSymbolList typeNames,
        ";abilities=",
        renderSymbolList abilityNames
      ]

parsingEnv :: Parser.ParsingEnv Identity
parsingEnv =
  Parser.ParsingEnv
    { Parser.uniqueNames = mempty,
      Parser.uniqueTypeGuid = \_ -> pure Nothing,
      Parser.names = B.names,
      Parser.maybeNamespace = Nothing,
      Parser.localNamespacePrefixedTypesAndConstructors = mempty
    }

oracleRow :: FilePath -> FilePath -> IO Text.Text
oracleRow absRepoRoot absPath = do
  source <- readFile absPath
  let repoRel = makeRelative absRepoRoot absPath
      parsed :: Either (Parser.Err Symbol) (UF.UnisonFile Symbol ParserAnn.Ann)
      parsed = runIdentity (Parsers.parseFile absPath source parsingEnv)
  case parsed of
    Right uf ->
      let shape = renderShapeSummary uf
       in pure (Text.pack repoRel <> "\tsuccess\treference-parser\t\t" <> shape)
    Left err -> do
      let rendered = Pr.toPlain 80 (prettyParseError source (err :: Parser.Err Symbol))
          oneLine = sanitizeDetail (Text.unpack rendered)
      pure (Text.pack repoRel <> "\tfailure\treference-parser\t" <> Text.pack oneLine <> "\t")

main :: IO ()
main = do
  args <- getArgs
  case parseArgs defaultOptions args of
    Left msg -> putStrLn msg
    Right opts -> do
      absRepoRoot <- makeAbsolute (repoRoot opts)
      let roots =
            [ absRepoRoot </> "unison-src",
              absRepoRoot </> "unison-cli-integration" </> "integration-tests" </> "IntegrationTests"
            ]
      filesPerRoot <- forM roots $ \root -> do
        exists <- doesDirectoryExist root
        if exists then findUnisonFiles root else pure []
      let allFiles0 = sort (concat filesPerRoot)
          allFiles = maybe allFiles0 (`take` allFiles0) (maxCases opts)
      rows <- mapM (oracleRow absRepoRoot) allFiles
      let header = "repo_path\texpected\texpected_source\texpected_detail\texpected_shape"
          outText = Text.unlines (header : rows)
      TextIO.writeFile (outputPath opts) outText
      putStrLn ("wrote " <> show (length allFiles) <> " rows to " <> outputPath opts)
