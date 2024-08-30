-- | The parser for Unison’s @Doc@ syntax.
--
--   This is completely independent of the Unison language, and requires a couple parsers to be passed in to then
--   provide a parser for @Doc@ applied to any host language.
--
-- - an identifer parser
-- - a code parser (that accepts a termination parser)
-- - a termination parser, for this parser to know when to give up
--
-- Each of those parsers is expected to satisfy @(`Ord` e, `P.MonadParsec` e `String` m)@.
module Unison.Syntax.Parser.Doc
  ( Tree,
    initialEnv,
    doc,
    untitledSection,
    sectionElem,
    leaf,

    -- * section elements
    section,
    eval,
    exampleBlock,
    codeBlock,
    list,
    bulletedList,
    numberedList,
    paragraph,

    -- * leaves
    link,
    namedLink,
    example,
    transclude,
    bold,
    italic,
    strikethrough,
    verbatim,
    source,
    foldedSource,
    evalInline,
    signatures,
    signatureInline,
    group,
    word,

    -- * other components
    column',
    embedLink,
    embedSignatureLink,
    join,
  )
where

import Control.Comonad.Cofree (Cofree ((:<)))
import Control.Monad.Reader qualified as R
import Data.Char (isControl, isSpace)
import Data.List qualified as List
import Data.List.Extra qualified as List
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.List.NonEmpty qualified as NonEmpty
import Text.Megaparsec qualified as P
import Text.Megaparsec.Char (char)
import Text.Megaparsec.Char qualified as CP
import Text.Megaparsec.Char.Lexer qualified as LP
import Unison.Parser.Ann (Ann, Annotated (..))
import Unison.Prelude hiding (join)
import Unison.Syntax.Lexer (column, line, lit, sepBy1', some', someTill', (<+>))
import Unison.Syntax.Lexer.Token (Token (Token), posP, tokenP)
import Unison.Syntax.Parser.Doc.Data

type Tree ident code = Cofree (Top ident code) Ann

data ParsingEnv = ParsingEnv
  { -- | Use a stack to remember the parent section and allow docSections within docSections.
    -- - 1 means we are inside a # Heading 1
    parentSections :: [Int],
    -- | 4 means we are inside a list starting at the fourth column
    parentListColumn :: Int
  }
  deriving (Show)

initialEnv :: ParsingEnv
initialEnv = ParsingEnv [0] 0

doc ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m end ->
  m (UntitledSection (Tree ident code))
doc ident code = flip R.runReaderT initialEnv . untitledSection . sectionElem ident code . void

-- | This is the actual `Doc` lexer. Unlike `doc2`, it doesn’t do any Unison-side lexing (i.e., it doesn’t know that
--   Unison wraps `Doc` literals in `}}`).
untitledSection :: (P.MonadParsec e String m) => m a -> m (UntitledSection a)
untitledSection a = UntitledSection <$> P.many (a <* CP.space)

sectionElem ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  R.ReaderT ParsingEnv m (Tree ident code)
sectionElem ident code docClose =
  fmap wrap' $
    section ident code docClose
      <|> lift (P.label "block eval (syntax: a fenced code block)" (eval code <|> exampleBlock code <|> codeBlock))
      <|> list ident code docClose
      <|> lift (paragraph ident code docClose)

paragraph ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  m (Top ident code (Tree ident code))
paragraph ident code docClose = fmap Paragraph . spaced docClose $ leafy ident code docClose

word :: (Ord e, P.MonadParsec e String m) => m end -> m (Leaf ident code void)
word closing = fmap Word . tokenP . P.try $ do
  let end = P.lookAhead $ void (P.satisfy isSpace) <|> void closing
  word <- P.manyTill (P.satisfy (\ch -> not (isSpace ch))) end
  guard (not $ reserved word || null word)
  pure word
  where
    reserved word = List.isPrefixOf "}}" word || all (== '#') word

leaf ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  m (Leaf ident code (Tree ident code))
leaf ident code closing =
  link ident
    <|> namedLink ident code closing
    <|> example code
    <|> transclude code
    <|> bold ident code closing
    <|> italic ident code closing
    <|> strikethrough ident code closing
    <|> verbatim
    <|> source ident code
    <|> foldedSource ident code
    <|> evalInline code
    <|> signatures ident
    <|> signatureInline ident
    <|> word closing

leafy ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  m (Leaf ident code (Tree ident code))
leafy ident code closing = do
  p <- leaf ident code closing
  after <- P.optional . P.try $ leafy ident code closing
  case after of
    Nothing -> pure p
    Just after -> group . pure $ p :| pure after

comma :: (P.MonadParsec e String m) => m String
comma = lit "," <* CP.space

source :: (Ord e, P.MonadParsec e String m) => m ident -> (m () -> m code) -> m (Leaf ident code a)
source ident = fmap Source . (lit "@source" *>) . sourceElements ident

foldedSource :: (Ord e, P.MonadParsec e String m) => m ident -> (m () -> m code) -> m (Leaf ident code a)
foldedSource ident = fmap FoldedSource . (lit "@foldedSource" *>) . sourceElements ident

sourceElements ::
  (Ord e, P.MonadParsec e String m) =>
  m ident ->
  (m () -> m code) ->
  m (NonEmpty (SourceElement ident (Leaf ident code Void)))
sourceElements ident code = do
  _ <- (lit " {" <|> lit "{") *> CP.space
  s <- sepBy1' srcElem comma
  _ <- lit "}"
  pure s
  where
    srcElem =
      SourceElement
        <$> embedLink ident
        <*> ( fmap (fromMaybe []) . P.optional $
                (lit "@") *> (CP.space *> annotations)
            )
      where
        annotation = fmap Left (tokenP ident) <|> fmap Right (transclude code) <* CP.space
        annotations = P.some (EmbedAnnotation <$> annotation)

signatures :: (Ord e, P.MonadParsec e String m) => m ident -> m (Leaf ident code a)
signatures ident = fmap Signature $ do
  _ <- (lit "@signatures" <|> lit "@signature") *> (lit " {" <|> lit "{") *> CP.space
  s <- sepBy1' (embedSignatureLink ident) comma
  _ <- lit "}"
  pure s

signatureInline :: (Ord e, P.MonadParsec e String m) => m ident -> m (Leaf ident code a)
signatureInline ident = fmap SignatureInline $ do
  _ <- lit "@inlineSignature" *> (lit " {" <|> lit "{") *> CP.space
  s <- embedSignatureLink ident
  _ <- lit "}"
  pure s

evalInline :: (P.MonadParsec e String m) => (m () -> m code) -> m (Leaf ident code a)
evalInline code = fmap EvalInline $ do
  _ <- lit "@eval" *> (lit " {" <|> lit "{") *> CP.space
  let inlineEvalClose = void $ lit "}"
  s <- code inlineEvalClose
  pure s

-- | Not an actual node, but this pattern is referenced in multiple places
embedLink :: (Ord e, P.MonadParsec e s m, P.TraversableStream s) => m ident -> m (EmbedLink ident)
embedLink = fmap EmbedLink . tokenP

embedSignatureLink :: (Ord e, P.MonadParsec e String m) => m ident -> m (EmbedSignatureLink ident)
embedSignatureLink ident = EmbedSignatureLink <$> tokenP ident <* CP.space

verbatim :: (Ord e, P.MonadParsec e String m) => m (Leaf ident code a)
verbatim =
  P.label "code (examples: ''**unformatted**'', `words` or '''_words_''')" $ do
    Token originalText start stop <- tokenP do
      -- a single backtick followed by a non-backtick is treated as monospaced
      let tick = P.try (lit "`" <* P.lookAhead (P.satisfy (/= '`')))
      -- also two or more ' followed by that number of closing '
      quotes <- tick <|> (lit "''" <+> P.takeWhileP Nothing (== '\''))
      P.someTill P.anySingle (lit quotes)
    let isMultiLine = line start /= line stop
    pure
      if isMultiLine
        then
          let trimmed = (trimAroundDelimiters originalText)
              txt = trimIndentFromVerbatimBlock (column start - 1) trimmed
           in -- If it's a multi-line verbatim block we trim any whitespace representing
              -- indentation from the pretty-printer. See 'trimIndentFromVerbatimBlock'
              Verbatim . Word $ Token txt start stop
        else Code . Word $ Token originalText start stop

example :: (P.MonadParsec e String m) => (m () -> m code) -> m (Leaf ident code void)
example code =
  P.label "inline code (examples: ``List.map f xs``, ``[1] :+ 2``)" $
    fmap Example $ do
      n <- P.try $ do
        _ <- lit "`"
        length <$> P.takeWhile1P (Just "backticks") (== '`')
      let end = void . lit $ replicate (n + 1) '`'
      CP.space *> code end

link :: (Ord e, P.MonadParsec e String m) => m ident -> m (Leaf ident code a)
link ident = P.label "link (examples: {type List}, {Nat.+})" $ Link <$> P.try (lit "{" *> embedLink ident <* lit "}")

transclude :: (P.MonadParsec e String m) => (m () -> m code) -> m (Leaf ident code a)
transclude code =
  fmap Transclude . P.label "transclusion (examples: {{ doc2 }}, {{ sepBy s [doc1, doc2] }})" $
    lit "{{" *> code (void $ lit "}}")

nonNewlineSpaces :: (P.MonadParsec e String m) => m String
nonNewlineSpaces = P.takeWhileP Nothing nonNewlineSpace
  where
    nonNewlineSpace ch = isSpace ch && ch /= '\n' && ch /= '\r'

eval :: (P.MonadParsec e String m, Annotated code) => (m () -> m code) -> m (Top ident code (Tree ident code))
eval code =
  Eval <$> do
    -- commit after seeing that ``` is on its own line
    fence <- P.try $ do
      fence <- lit "```" <+> P.takeWhileP Nothing (== '`')
      b <- all isSpace <$> P.lookAhead (P.takeWhileP Nothing (/= '\n'))
      fence <$ guard b
    CP.space *> code (void $ lit fence)

exampleBlock :: (P.MonadParsec e String m, Annotated code) => (m () -> m code) -> m (Top ident code (Tree ident code))
exampleBlock code =
  ExampleBlock
    <$> do
      void $ lit "@typecheck" <* CP.space
      fence <- lit "```" <+> P.takeWhileP Nothing (== '`')
      code . void $ lit fence

codeBlock :: (Ord e, P.MonadParsec e String m) => m (Top ident code (Tree ident code))
codeBlock = do
  column <- (\x -> x - 1) . toInteger . P.unPos <$> LP.indentLevel
  let tabWidth = toInteger . P.unPos $ P.defaultTabWidth
  fence <- lit "```" <+> P.takeWhileP Nothing (== '`')
  name <-
    nonNewlineSpaces
      *> tokenP (P.takeWhile1P Nothing (not . isSpace))
      <* nonNewlineSpaces
  _ <- void CP.eol
  verbatim <-
    tokenP $
      uncolumn column tabWidth . trimAroundDelimiters
        <$> P.someTill P.anySingle ([] <$ lit fence)
  pure $ CodeBlock name verbatim
  where
    uncolumn column tabWidth s =
      let skip col r | col < 1 = r
          skip col s@('\t' : _) | col < tabWidth = s
          skip col ('\t' : r) = skip (col - tabWidth) r
          skip col (c : r)
            | isSpace c && (not $ isControl c) =
                skip (col - 1) r
          skip _ s = s
       in List.intercalate "\n" $ skip column <$> lines s

emphasis ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  Char ->
  m ident ->
  (m () -> m code) ->
  m () ->
  m (Tree ident code)
emphasis delimiter ident code closing = do
  let start = some (P.satisfy (== delimiter))
  end <- P.try $ do
    end <- start
    P.lookAhead (P.satisfy (not . isSpace))
    pure end
  wrap' . Paragraph
    <$> someTill'
      (leafy ident code (closing <|> (void $ lit end)) <* void whitespaceWithoutParagraphBreak)
      (lit end)
  where
    -- Allows whitespace including up to one newline
    whitespaceWithoutParagraphBreak = void do
      void nonNewlineSpaces
      optional newline >>= \case
        Just _ -> void nonNewlineSpaces
        Nothing -> pure ()

bold ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  m (Leaf ident code (Tree ident code))
bold ident code = fmap Bold . emphasis '*' ident code

italic ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  m (Leaf ident code (Tree ident code))
italic ident code = fmap Italic . emphasis '_' ident code

strikethrough ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  m (Leaf ident code (Tree ident code))
strikethrough ident code = fmap Strikethrough . emphasis '~' ident code

namedLink ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  m (Leaf ident code (Tree ident code))
namedLink ident code docClose =
  P.label "hyperlink (example: [link name](https://destination.com))" do
    _ <- lit "["
    p <- spaced docClose . leafy ident code . void $ char ']'
    _ <- lit "]"
    _ <- lit "("
    target <- group $ fmap pure (link ident) <|> some' (transclude code <|> word (docClose <|> void (char ')')))
    _ <- lit ")"
    pure $ NamedLink (wrap' $ Paragraph p) target

sp :: (P.MonadParsec e String m) => m () -> m String
sp docClose = P.try $ do
  spaces <- P.takeWhile1P (Just "space") isSpace
  close <- P.optional (P.lookAhead docClose)
  case close of
    Nothing -> guard $ ok spaces
    Just _ -> pure ()
  pure spaces
  where
    ok s = length [() | '\n' <- s] < 2

spaced :: (P.MonadParsec e String m) => m () -> m a -> m (NonEmpty a)
spaced docClose p = some' $ p <* P.optional (sp docClose)

-- | Not an actual node, but this pattern is referenced in multiple places
list ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  R.ReaderT ParsingEnv m (Top ident code (Tree ident code))
list ident code docClose = bulletedList ident code docClose <|> numberedList ident code docClose

listSep :: (Ord e, R.MonadReader ParsingEnv m, P.MonadParsec e String m) => m ()
listSep = P.try $ newline *> nonNewlineSpaces *> P.lookAhead (void bulletedStart <|> void numberedStart)

bulletedStart :: (Ord e, R.MonadReader ParsingEnv m, P.MonadParsec e String m) => m (Int, [a])
bulletedStart = P.try $ do
  r <- listItemStart $ [] <$ P.satisfy bulletChar
  P.lookAhead (P.satisfy isSpace)
  pure r
  where
    bulletChar ch = ch == '*' || ch == '-' || ch == '+'

listItemStart :: (Ord e, R.MonadReader ParsingEnv m, P.MonadParsec e String m) => m a -> m (Int, a)
listItemStart gutter = P.try do
  nonNewlineSpaces
  col <- column <$> posP
  parentCol <- R.asks parentListColumn
  guard (col > parentCol)
  (col,) <$> gutter

numberedStart :: (Ord e, R.MonadReader ParsingEnv m, P.MonadParsec e String m) => m (Int, Token Word64)
numberedStart = listItemStart $ P.try (tokenP $ LP.decimal <* lit ".")

-- | FIXME: This should take a @`P` a@
numberedList ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  R.ReaderT ParsingEnv m (Top ident code (Tree ident code))
numberedList ident code docClose = NumberedList <$> sepBy1' numberedItem listSep
  where
    numberedItem = P.label "numbered list (examples: 1. item1, 8. start numbering at '8')" do
      (col, s) <- numberedStart
      (s,) <$> column' ident code docClose col

-- | FIXME: This should take a @`P` a@
bulletedList ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  R.ReaderT ParsingEnv m (Top ident code (Tree ident code))
bulletedList ident code docClose = BulletedList <$> sepBy1' bullet listSep
  where
    bullet = P.label "bullet (examples: * item1, - item2)" do
      (col, _) <- bulletedStart
      column' ident code docClose col

column' ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  Int ->
  R.ReaderT ParsingEnv m (Column (Tree ident code))
column' ident code docClose col =
  Column . wrap'
    <$> (nonNewlineSpaces *> listItemParagraph)
    <*> R.local (\e -> e {parentListColumn = col}) (P.optional $ listSep *> fmap wrap' (list ident code docClose))
  where
    listItemParagraph =
      Paragraph <$> do
        col <- column <$> posP
        some' (lift (leafy ident code docClose) <* sep col)
      where
        -- Trickiness here to support hard line breaks inside of
        -- a bulleted list, so for instance this parses as expected:
        --
        --   * uno dos
        --     tres quatro
        --   * alice bob
        --     carol dave eve
        sep col = do
          _ <- nonNewlineSpaces
          _ <-
            P.optional . P.try $
              newline
                *> nonNewlineSpaces
                *> do
                  col2 <- column <$> posP
                  guard $ col2 >= col
                  (P.notFollowedBy $ void numberedStart <|> void bulletedStart)
          pure ()

newline :: (P.MonadParsec e String m) => m String
newline = P.label "newline" $ lit "\n" <|> lit "\r\n"

-- |
--
-- > ## Section title
-- >
-- > A paragraph under this section.
-- > Part of the same paragraph. Blanklines separate paragraphs.
-- >
-- > ### A subsection title
-- >
-- > A paragraph under this subsection.
-- >
-- > # A section title (not a subsection)
section ::
  (Ord e, P.MonadParsec e String m, Annotated code) =>
  m ident ->
  (m () -> m code) ->
  m () ->
  R.ReaderT ParsingEnv m (Top ident code (Tree ident code))
section ident code docClose = do
  ns <- R.asks parentSections
  hashes <- lift $ P.try $ lit (replicate (head ns) '#') *> P.takeWhile1P Nothing (== '#') <* sp docClose
  title <- lift $ paragraph ident code docClose <* CP.space
  let m = length hashes + head ns
  body <-
    R.local (\env -> env {parentSections = m : tail ns}) $
      P.many (sectionElem ident code docClose <* CP.space)
  pure $ Section (wrap' title) body

-- | FIXME: This should just take a @`P` code@ and @`P` a@.
group :: (P.MonadParsec e s m) => m (NonEmpty (Leaf ident code a)) -> m (Leaf ident code a)
group = fmap Group . join

-- | FIXME: This should just take a @`P` a@
join :: (P.MonadParsec e s m) => m (NonEmpty a) -> m (Join a)
join = fmap Join

-- * utility functions

wrap' :: (Annotated code) => Top ident code (Tree ident code) -> Tree ident code
wrap' doc = ann doc :< doc

-- | If it's a multi-line verbatim block we trim any whitespace representing
-- indentation from the pretty-printer.
--
-- E.g.
--
-- @@
-- {{
--   # Heading
--     '''
--     code
--       indented
--     '''
-- }}
-- @@
--
-- Should lex to the text literal "code\n  indented".
--
-- If there's text in the literal that has LESS trailing whitespace than the
-- opening delimiters, we don't trim it at all. E.g.
--
-- @@
-- {{
--   # Heading
--     '''
--   code
--     '''
-- }}
-- @@
--
--  Is parsed as "  code".
--
--  Trim the expected amount of whitespace from a text literal:
--  >>> trimIndentFromVerbatimBlock 2 "  code\n    indented"
-- "code\n  indented"
--
-- If the text literal has less leading whitespace than the opening delimiters,
-- leave it as-is
-- >>> trimIndentFromVerbatimBlock 2 "code\n  indented"
-- "code\n  indented"
trimIndentFromVerbatimBlock :: Int -> String -> String
trimIndentFromVerbatimBlock leadingSpaces txt = fromMaybe txt $ do
  List.intercalate "\n" <$> for (lines txt) \line -> do
    -- If any 'stripPrefix' fails, we fail and return the unaltered text
    case List.stripPrefix (replicate leadingSpaces ' ') line of
      Just stripped -> Just stripped
      Nothing ->
        -- If it was a line with all white-space, just use an empty line,
        -- this can happen easily in editors which trim trailing whitespace.
        if all isSpace line
          then Just ""
          else Nothing

-- | Trim leading/trailing whitespace from around delimiters, e.g.
--
-- {{
--   '''___ <- whitespace here including newline
--   text block
-- 👇 or here
-- __'''
-- }}
-- >>> trimAroundDelimiters "  \n  text block \n  "
-- "  text block "
--
-- Should leave leading and trailing line untouched if it contains non-whitespace, e.g.:
--
-- '''  leading whitespace
--   text block
-- trailing whitespace:  '''
-- >>> trimAroundDelimiters "  leading whitespace\n  text block \ntrailing whitespace:  "
-- "  leading whitespace\n  text block \ntrailing whitespace:  "
--
-- Should keep trailing newline if it's the only thing on the line, e.g.:
--
-- '''
-- newline below
--
-- '''
-- >>> trimAroundDelimiters "\nnewline below\n\n"
-- "newline below\n\n"
trimAroundDelimiters :: String -> String
trimAroundDelimiters txt =
  txt
    & ( \s ->
          List.breakOn "\n" s
            & \case
              (prefix, suffix)
                | all isSpace prefix -> drop 1 suffix
                | otherwise -> prefix <> suffix
      )
    & ( \s ->
          List.breakOnEnd "\n" s
            & \case
              (_prefix, "") -> s
              (prefix, suffix)
                | all isSpace suffix -> dropTrailingNewline prefix
                | otherwise -> prefix <> suffix
      )
  where
    dropTrailingNewline = \case
      [] -> []
      (x : xs) -> NonEmpty.init (x NonEmpty.:| xs)
