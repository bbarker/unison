{-# OPTIONS_GHC -Wno-unused-top-binds #-}
{-# OPTIONS_GHC -Wno-unused-local-binds #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}
{-# OPTIONS_GHC -Wno-unused-matches #-}

-- {-# LANGUAGE DoAndIfThenElse     #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ViewPatterns        #-}
{-# LANGUAGE RecordWildCards     #-}


module Unison.CommandLine.OutputMessages where

import Unison.Codebase.Editor.Output
import qualified Unison.Codebase.Editor.Output       as E
import qualified Unison.Codebase.Editor.TodoOutput       as TO
import Unison.Codebase.Editor.SlurpResult (SlurpResult(..))
import qualified Unison.Codebase.Editor.SearchResult' as SR'


--import Debug.Trace
import Control.Lens (over, _1)
import           Control.Monad                 (when, unless, join)
import           Data.Bifunctor                (bimap, first)
import           Data.Foldable                 (toList, traverse_)
import           Data.List                     (sortOn, stripPrefix)
import           Data.List.Extra               (nubOrdOn, nubOrd)
import qualified Data.ListLike                 as LL
import           Data.ListLike                 (ListLike)
import           Data.Maybe                    (fromMaybe)
import           Data.Map                      (Map)
import qualified Data.Map                      as Map
import qualified Data.Set                      as Set
import           Data.Set                      (Set)
import           Data.String                   (IsString, fromString)
import           Data.Text                     (Text)
import qualified Data.Text                     as Text
import           Data.Text.IO                  (readFile, writeFile)
import           Data.Tuple.Extra              (dupe)
import           Prelude                       hiding (readFile, writeFile)
import qualified System.Console.ANSI           as Console
import           System.Directory              (canonicalizePath, doesFileExist)
import qualified Unison.ABT                    as ABT
import qualified Unison.UnisonFile             as UF
import qualified Unison.Codebase               as Codebase
import           Unison.Codebase.GitError
import qualified Unison.Codebase.Path          as Path
import qualified Unison.Codebase.Patch         as Patch
import           Unison.Codebase.Patch         (Patch(..))
import qualified Unison.Codebase.TermEdit      as TermEdit
import qualified Unison.Codebase.TypeEdit      as TypeEdit
import           Unison.CommandLine             ( bigproblem
                                                , tip
                                                , note
                                                )
import           Unison.PrettyTerminal          ( clearCurrentLine
                                                , putPretty'
                                                , putPrettyLn
                                                , putPrettyLn'
                                                )
import           Unison.CommandLine.InputPatterns (makeExample, makeExample')
import qualified Unison.CommandLine.InputPatterns as IP
import qualified Unison.DataDeclaration        as DD
import qualified Unison.DeclPrinter            as DeclPrinter
import qualified Unison.HashQualified          as HQ
import qualified Unison.HashQualified'         as HQ'
import           Unison.Name                   (Name)
import qualified Unison.Name                   as Name
import           Unison.NamePrinter            (prettyHashQualified,
                                                prettyName, prettyShortHash,
                                                styleHashQualified,
                                                styleHashQualified', prettyHashQualified')
import           Unison.Names2                 (Names'(..), Names, Names0)
import qualified Unison.Names2                 as Names
import qualified Unison.Names3                 as Names
import           Unison.Parser                 (Ann, startingLine)
import qualified Unison.PrettyPrintEnv         as PPE
import qualified Unison.Codebase.Runtime       as Runtime
import           Unison.PrintError              ( prettyParseError
                                                , printNoteWithSource
                                                , prettyResolutionFailures
                                                )
import qualified Unison.Reference              as Reference
import           Unison.Reference              ( Reference )
import qualified Unison.Referent               as Referent
import qualified Unison.Result                 as Result
import qualified Unison.Term                   as Term
import           Unison.Term                   (AnnotatedTerm)
import qualified Unison.TermPrinter            as TermPrinter
import qualified Unison.Typechecker.TypeLookup as TL
import qualified Unison.Typechecker            as Typechecker
import qualified Unison.TypePrinter            as TypePrinter
import qualified Unison.Util.ColorText         as CT
import           Unison.Util.Monoid             ( intercalateMap
                                                , unlessM
                                                )
import qualified Unison.Util.Pretty            as P
import qualified Unison.Util.Relation          as R
import           Unison.Var                    (Var)
import qualified Unison.Var                    as Var
import qualified Unison.Codebase.Editor.SlurpResult as SlurpResult
import           System.Directory               ( getHomeDirectory )
import Unison.Codebase.Editor.DisplayThing (DisplayThing(MissingThing, BuiltinThing, RegularThing))
import qualified Unison.Codebase.Editor.Input as Input
import qualified Unison.Hash as Hash
import qualified Unison.Codebase.Causal as Causal
import qualified Unison.Codebase.Editor.RemoteRepo as RemoteRepo
import qualified Unison.Util.List              as List
import Data.Tuple (swap)

shortenDirectory :: FilePath -> IO FilePath
shortenDirectory dir = do
  home <- getHomeDirectory
  pure $ case stripPrefix home dir of
    Just d  -> "~" <> d
    Nothing -> dir

renderFileName :: FilePath -> IO (P.Pretty CT.ColorText)
renderFileName dir = P.group . P.blue . fromString <$> shortenDirectory dir

notifyUser :: forall v . Var v => FilePath -> Output v -> IO ()
notifyUser dir o = case o of
  -- Success (MergeBranchI _ _) ->
  --   putPrettyLn $ P.bold "Merged. " <> "Here's what's " <> makeExample' IP.todo <> " after the merge:"
  Success _    -> putPrettyLn $ P.bold "Done."
  WarnIncomingRootBranch hashes -> pure ()
  -- todo: resurrect this code once it's not triggered by update+propagate
--  WarnIncomingRootBranch hashes -> putPrettyLn $
--    if null hashes then P.wrap $
--      "Please let someone know I generated an empty IncomingRootBranch"
--                 <> " event, which shouldn't be possible!"
--    else P.lines
--      [ P.wrap $ (if length hashes == 1 then "A" else "Some")
--         <> "codebase" <> P.plural hashes "root" <> "appeared unexpectedly"
--         <> "with" <> P.group (P.plural hashes "hash" <> ":")
--      , ""
--      , (P.indentN 2 . P.oxfordCommas)
--                (map (P.text . Hash.base32Hex . Causal.unRawHash) $ toList hashes)
--      , ""
--      , P.wrap $ "but I'm not sure what to do about it."
--          <> "If you're feeling lucky, you can try deleting one of the heads"
--          <> "from `.unison/v1/branches/head/`, but please make a backup first."
--          <> "There will be a better way of handling this in the future. 😅"
--      ]

  DisplayDefinitions outputLoc ppe types terms ->
    displayDefinitions outputLoc ppe types terms
  DisplayLinks ppe md types terms ->
    if Map.null md then putPrettyLn $ P.wrap "Nothing to show here. Use the "
      <> IP.makeExample' IP.link <> " command to add links from this definition."
    else
      putPrettyLn $ intercalateMap "\n\n" go (Map.toList md)
      where
      go (key, rs) =
        displayDefinitions' ppe (Map.restrictKeys types rs)
                                (Map.restrictKeys terms rs)
  TestResults stats ppe _showSuccess _showFailures oks fails -> case stats of
    CachedTests 0 _ -> putPrettyLn . P.callout "😶" $ "No tests to run."
    CachedTests n n' | n == n' -> putPrettyLn $
      P.lines [ cache, "", displayTestResults True ppe oks fails ]
    CachedTests n m -> putPretty' $
      if m == 0 then "✅  "
      else P.indentN 2 $
           P.lines [ "", cache, "", displayTestResults False ppe oks fails, "", "✅  " ]
      where
    NewlyComputed -> do
      clearCurrentLine
      putPretty' $ "  " <> P.bold "New test results:"
      putPrettyLn $ P.lines ["", displayTestResults True ppe oks fails ]
    where
      cache = P.bold "Cached test results " <> "(`help testcache` to learn more)"

  TestIncrementalOutputStart ppe (n,total) r _src -> do
    putPretty' $ P.shown (total - n) <> " tests left to run, current test: "
              <> (P.syntaxToColor $ prettyHashQualified (PPE.termName ppe $ Referent.Ref r))

  TestIncrementalOutputEnd _ppe (n,total) _r result -> do
    clearCurrentLine
    if isTestOk result then putPretty' "  ✅  "
    else putPretty' "  🚫  "

  LinkFailure input -> putPrettyLn . P.warnCallout . P.shown $ input
  EvaluationFailure err -> putPrettyLn err
  SearchTermsNotFound hqs | null hqs -> return ()
  SearchTermsNotFound hqs ->
    putPrettyLn
      $  P.warnCallout "The following names were not found in the codebase. Check your spelling."
      <> P.newline
      <> (P.syntaxToColor $ P.indent "  " (P.lines (prettyHashQualified <$> hqs)))
  PatchNotFound input _ ->
    putPrettyLn . P.warnCallout $ "I don't know about that patch."
  TermNotFound input _ ->
    putPrettyLn . P.warnCallout $ "I don't know about that term."
  TypeNotFound input _ ->
    putPrettyLn . P.warnCallout $ "I don't know about that type."
  TermAlreadyExists input _ _ ->
    putPrettyLn . P.warnCallout $ "A term by that name already exists."
  TypeAlreadyExists input _ _ ->
    putPrettyLn . P.warnCallout $ "A type by that name already exists."
  PatchAlreadyExists input _ ->
    putPrettyLn . P.warnCallout $ "A patch by that name already exists."
  CantDelete input ppe failed failedDependents -> putPrettyLn . P.warnCallout $
    P.lines [
      P.wrap "I couldn't delete ",
      "", P.indentN 2 $ listOfDefinitions' ppe False True failed,
      "",
      "because it's still being used by these definitions:",
      "", P.indentN 2 $ listOfDefinitions' ppe False True failedDependents
    ]
  CantUndo reason -> case reason of
    CantUndoPastStart -> putPrettyLn . P.warnCallout $ "Nothing more to undo."
    CantUndoPastMerge -> putPrettyLn . P.warnCallout $ "Sorry, I can't undo a merge (not implemented yet)."
  NoUnisonFile -> do
    dir' <- canonicalizePath dir
    fileName <- renderFileName dir'
    putPrettyLn . P.callout "😶" $ P.lines
      [ P.wrap "There's nothing for me to add right now."
      , ""
      , P.column2 [(P.bold "Hint:", msg fileName)] ]
    where
    msg dir = P.wrap
      $  "I'm currently watching for definitions in .u files under the"
      <> dir
      <> "directory. Make sure you've updated something there before using the"
      <> makeExample' IP.add <> "or" <> makeExample' IP.update
      <> "commands."
  BranchNotFound _ b ->
    putPrettyLn . P.warnCallout $ "The namespace " <> P.blue (P.shown b) <> " doesn't exist."
  CreatedNewBranch path -> putPrettyLn $
    "☝️  The namespace " <> P.blue (P.shown path) <> " is empty."
 -- RenameOutput rootPath oldName newName r -> do
  --   nameChange "rename" "renamed" oldName newName r
  -- AliasOutput rootPath existingName newName r -> do
  --   nameChange "alias" "aliased" existingName newName r
  DeletedEverything ->
    putPrettyLn . P.wrap . P.lines $
      ["Okay, I deleted everything except the history."
      ,"Use " <> IP.makeExample' IP.undo <> " to undo, or "
        <> IP.makeExample' IP.mergeBuiltins
        <> " to restore the absolute "
        <> "basics to the current path."]
  DeleteEverythingConfirmation ->
    putPrettyLn . P.warnCallout . P.lines $
      ["Are you sure you want to clear away everything?"
      ,"You could use " <> IP.makeExample' IP.cd
        <> " to switch to a new namespace instead."]
  DeleteBranchConfirmation _uniqueDeletions -> error "todo"
    -- let
    --   pretty (branchName, (ppe, results)) =
    --     header $ listOfDefinitions' ppe False results
    --     where
    --     header = plural uniqueDeletions id ((P.text branchName <> ":") `P.hang`)
    --
    -- in putPrettyLn . P.warnCallout
    --   $ P.wrap ("The"
    --   <> plural uniqueDeletions "namespace contains" "namespaces contain"
    --   <> "definitions that don't exist in any other branches:")
    --   <> P.border 2 (mconcat (fmap pretty uniqueDeletions))
    --   <> P.newline
    --   <> P.wrap "Please repeat the same command to confirm the deletion."
  ListOfDefinitions ppe detailed showAll results ->
     listOfDefinitions ppe detailed showAll results
  ListNames [] [] -> putPrettyLn . P.callout "😶" $
    P.wrap "I couldn't find anything by that name."
  ListNames terms types -> putPrettyLn . P.sepNonEmpty "\n\n" $ [
    formatTerms terms, formatTypes types ]
    where
    formatTerms tms =
      P.lines . P.nonEmpty $ P.plural tms (P.blue "Term") : (go <$> tms) where
      go (ref, hqs) = P.column2
        [ ("Hash:", P.syntaxToColor $ prettyHashQualified (HQ.fromReferent ref))
        , ("Names: ", P.group (P.spaced (P.bold . P.syntaxToColor . prettyHashQualified' <$> toList hqs)))
        ]
    formatTypes types =
      P.lines . P.nonEmpty $ P.plural types (P.blue "Type") : (go <$> types) where
      go (ref, hqs) = P.column2
        [ ("Hash:", P.syntaxToColor $ prettyHashQualified (HQ.fromReference ref))
        , ("Names:", P.group (P.spaced (P.bold . P.syntaxToColor . prettyHashQualified' <$> toList hqs)))
        ]
  -- > names foo
  --   Terms:
  --     Hash: #asdflkjasdflkjasdf
  --     Names: .util.frobnicate foo blarg.mcgee
  --
  --   Term (with hash #asldfkjsdlfkjsdf): .util.frobnicate, foo, blarg.mcgee
  --   Types (with hash #hsdflkjsdfsldkfj): Optional, Maybe, foo


  SlurpOutput input ppe s -> let
    isPast = case input of Input.AddI{} -> True
                           Input.UpdateI{} -> True
                           _ -> False
    in putPrettyLn $ SlurpResult.pretty isPast ppe s

  NoExactTypeMatches ->
    putPrettyLn . P.callout "☝️" $ P.wrap "I couldn't find exact type matches, resorting to fuzzy matching..."
  TypeParseError input src e ->
    putPrettyLn . P.fatalCallout $ P.lines [
      P.wrap "I couldn't parse the type you supplied:",
      "",
      prettyParseError src e
    ]
  ParseResolutionFailures input src es -> putPrettyLn $
    prettyResolutionFailures src es
  TypeHasFreeVars input typ ->
    putPrettyLn . P.warnCallout $ P.lines [
      P.wrap "The type uses these names, but I'm not sure what they are:",
      P.sep ", " (map (P.text . Var.name) . toList $ ABT.freeVars typ)
    ]
  ParseErrors src es -> do
    Console.setTitle "Unison ☹︎"
    traverse_ (putPrettyLn . prettyParseError (Text.unpack src)) es
  TypeErrors src ppenv notes -> do
    Console.setTitle "Unison ☹︎"
    let showNote =
          intercalateMap "\n\n" (printNoteWithSource ppenv (Text.unpack src))
            . map Result.TypeError
    putPrettyLn . showNote $ notes
  Evaluated fileContents ppe bindings watches ->
    if null watches then putStrLn ""
    else
      -- todo: hashqualify binding names if necessary to distinguish them from
      --       defs in the codebase.  In some cases it's fine for bindings to
      --       shadow codebase names, but you don't want it to capture them in
      --       the decompiled output.
      let prettyBindings = P.bracket . P.lines $
            P.wrap "The watch expression(s) reference these definitions:" : "" :
            [(P.syntaxToColor $ TermPrinter.prettyBinding ppe (HQ.unsafeFromVar v) b)
            | (v, b) <- bindings]
          prettyWatches = P.sep "\n\n" [
            watchPrinter fileContents ppe ann kind evald isCacheHit |
            (ann,kind,evald,isCacheHit) <-
              sortOn (\(a,_,_,_)->a) . toList $ watches ]
      -- todo: use P.nonempty
      in putPrettyLn $ if null bindings then prettyWatches
                       else prettyBindings <> "\n" <> prettyWatches

  DisplayConflicts termNamespace typeNamespace -> do
    showConflicts "terms" terms
    showConflicts "types" types
    where
    terms    = R.dom termNamespace
    types    = R.dom typeNamespace
    showConflicts :: Foldable f => String -> f Name -> IO ()
    showConflicts thingsName things =
      unless (null things) $ do
        putStrLn $ "🙅 These " <> thingsName <> " have conflicts: "
        traverse_ (\x -> putStrLn ("  " ++ Name.toString x)) things
    -- TODO: Present conflicting TermEdits and TypeEdits
    -- if we ever allow users to edit hashes directly.
  FileChangeEvent _sourceName _src -> putStrLn ""
  Typechecked sourceName ppe slurpResult uf -> do
    Console.setTitle "Unison ✅"
    let fileStatusMsg = SlurpResult.pretty False ppe slurpResult
    if UF.nonEmpty uf then do
      fileName <- renderFileName $ Text.unpack sourceName
      if fileStatusMsg == mempty then do
        putPrettyLn' . P.okCallout $ fileName <> " changed."
      else
        if SlurpResult.isAllDuplicates slurpResult then
          putPrettyLn' . (P.newline <>) . P.okCallout . P.wrap $ "I found and"
           <> P.bold "typechecked" <> "the definitions in "
           <> P.group (fileName <> ".")
           <> "This file " <> P.bold "has been previously added" <> "to the codebase."
        else do
          putPrettyLn' . (P.newline <>) . P.linesSpaced $ [
            P.okCallout . P.wrap $ "I found and"
             <> P.bold "typechecked" <> "these definitions in "
             <> P.group (fileName <> ".")
             <> "If you do an "
             <> IP.makeExample' IP.add
             <> " or "
             <> IP.makeExample' IP.update
             <> ", here's how your codebase would"
             <> "change:"
            , P.indentN 2 $ SlurpResult.pretty False ppe slurpResult
            ]
      putPrettyLn' ""
      putPrettyLn' . P.wrap $ "Now evaluating any watch expressions"
                           <> "(lines starting with `>`)... "
                           <> P.group (P.hiBlack "Ctrl+C cancels.")
    else when (null $ UF.watchComponents uf) $ putPrettyLn' . P.wrap $
      "I loaded " <> P.text sourceName <> " and didn't find anything."
  TodoOutput names todo -> todoOutput names todo
  GitError input e -> putPrettyLn $ case e of
    NoGit -> P.wrap $
      "I couldn't find git. Make sure it's installed and on your path."
    NoRemoteRepoAt p -> P.wrap
       $ "I couldn't access a git "
      <> "repository at " <> P.group (P.text p <> ".")
      <> "Make sure the repo exists "
      <> "and that you have access to it."
    NoLocalRepoAt p -> P.wrap
       $ "The directory at " <> P.string p
      <> "doesn't seem to contain a git repository."
    CheckoutFailed t -> P.wrap
       $ "I couldn't do a git checkout of "
      <> P.group (P.text t <> ".")
      <> "Make sure there's a branch or commit with that name."
    PushDestinationHasNewStuff url treeish diff -> P.callout "⏸" . P.lines $ [
      P.wrap $ "The repository at" <> P.blue (P.text url)
            <> (if Text.null treeish then ""
                else "at revision" <> P.blue (P.text treeish))
            <> "has some changes I don't know about:",
      "", P.indentN 2 (prettyDiff Nothing diff), "",
      P.wrap $ "If you want to " <> push <> "you can do:", "",
       P.indentN 2 pull, "",
       P.wrap $
         "to merge these changes locally." <>
         "Then try your" <> push <> "again."
      ]
      where
      push = P.group . P.backticked $ IP.patternName IP.push
      pull = case input of
        Input.PushRemoteBranchI Nothing p ->
          P.sep " " [IP.patternName IP.pull, P.shown p ]
        Input.PushRemoteBranchI (Just r) p -> P.sepNonEmpty " " [
          IP.patternName IP.pull,
          P.text (RemoteRepo.url r),
          P.shown p,
          if RemoteRepo.commit r /= "master" then P.text (RemoteRepo.commit r)
          else "" ]
        _ -> "⁉️ Unison bug - push command expected"
    SomeOtherError msg -> P.callout "‼" . P.lines $ [
      P.wrap "I ran into an error:", "",
      P.indentN 2 (P.text msg), "",
      P.wrap $ "Check the logging messages above for more info."
      ]
  ListEdits patch ppe -> do
    let
      types = Patch._typeEdits patch
      terms = Patch._termEdits patch

      prettyTermEdit (r, TermEdit.Deprecate) =
        (P.syntaxToColor . prettyHashQualified . PPE.termName ppe . Referent.Ref $ r
        , "-> (deprecated)")
      prettyTermEdit (r, TermEdit.Replace r' _typing) =
        (P.syntaxToColor . prettyHashQualified . PPE.termName ppe . Referent.Ref $ r
        , "-> " <> (P.syntaxToColor . prettyHashQualified . PPE.termName ppe . Referent.Ref $ r'))
      prettyTypeEdit (r, TypeEdit.Deprecate) =
        (P.syntaxToColor . prettyHashQualified $ PPE.typeName ppe r
        , "-> (deprecated)")
      prettyTypeEdit (r, TypeEdit.Replace r') =
        (P.syntaxToColor . prettyHashQualified $ PPE.typeName ppe r
        , "-> " <> (P.syntaxToColor . prettyHashQualified . PPE.typeName ppe $ r'))
    unless (R.null types) $
       putPrettyLn $ "Edited Types:" `P.hang`
        P.column2 (prettyTypeEdit <$> R.toList types)
    unless (R.null terms) $
       putPrettyLn $ "Edited Terms:" `P.hang`
        P.column2 (prettyTermEdit <$> R.toList terms)
    when (R.null types && R.null terms)
         (putPrettyLn "This patch is empty.")
  BustedBuiltins (Set.toList -> new) (Set.toList -> old) ->
    -- todo: this could be prettier!  Have a nice list like `find` gives, but
    -- that requires querying the codebase to determine term types.  Probably
    -- the only built-in types will be primitive types like `Int`, so no need
    -- to look up decl types.
    -- When we add builtin terms, they may depend on new derived types, so
    -- these derived types should be added to the branch too; but not
    -- necessarily ever be automatically deprecated.  (A library curator might
    -- deprecate them; more work needs to go into the idea of sharing deprecations and stuff.
    putPrettyLn . P.warnCallout . P.lines $
      case (new, old) of
        ([],[]) -> error "BustedBuiltins busted, as there were no busted builtins."
        ([], old) ->
          P.wrap ("This codebase includes some builtins that are considered deprecated. Use the " <> makeExample' IP.updateBuiltins <> " command when you're ready to work on eliminating them from your codebase:")
            : ""
            : fmap (P.text . Reference.toText) old
        (new, []) -> P.wrap ("This version of Unison provides builtins that are not part of your codebase. Use " <> makeExample' IP.updateBuiltins <> " to add them:")
          : "" : fmap (P.text . Reference.toText) new
        (new@(_:_), old@(_:_)) ->
          [ P.wrap
            ("Sorry and/or good news!  This version of Unison supports a different set of builtins than this codebase uses.  You can use "
            <> makeExample' IP.updateBuiltins
            <> " to add the ones you're missing and deprecate the ones I'm missing. 😉"
            )
          , "You're missing:" `P.hang` P.lines (fmap (P.text . Reference.toText) new)
          , "I'm missing:" `P.hang` P.lines (fmap (P.text . Reference.toText) old)
          ]
  ListOfPatches patches ->
    -- todo: make this prettier
    putPrettyLn . P.lines . fmap prettyName $ toList patches
  NoConfiguredGitUrl pp p ->
    putPrettyLn . P.fatalCallout . P.wrap $
      "I don't know where to " <>
        pushPull "push to!" "pull from!" pp <>
          (if Path.isRoot' p then ""
           else "Add a line like `GitUrl." <> prettyPath' p
                <> " = <some-git-url>' to .unisonConfig. "
          )
          <> "Type `help " <> pushPull "push" "pull" pp <>
          "` for more information."
  NotImplemented -> putPrettyLn $ P.wrap "That's not implemented yet. Sorry! 😬"
  BranchAlreadyExists _ _ -> putPrettyLn "That namespace already exists."
  TypeAmbiguous _ _ _ -> putPrettyLn "That type is ambiguous."
  TermAmbiguous _ _ _ -> putPrettyLn "That term is ambiguous."
  BadDestinationBranch _ _ -> putPrettyLn "That destination namespace is bad."
  TermNotFound' _ _ -> putPrettyLn "That term was not found."
  BranchDiff _ _ -> putPrettyLn "Those namespaces are different."
  NothingToPatch _patchPath dest -> putPrettyLn $
    P.callout "😶" . P.wrap
       $ "This had no effect. Perhaps the patch has already been applied"
      <> "or it doesn't intersect with the definitions in"
      <> P.group (prettyPath' dest <> ".")
  PatchNeedsToBeConflictFree -> putPrettyLn "A patch needs to be conflict-free."
  PatchInvolvesExternalDependents _ _ ->
    putPrettyLn "That patch involves external dependents."
  ShowDiff input diff -> putPrettyLn $ case input of
    Input.UndoI -> P.callout "⏪" . P.lines $ [
      "Here's the changes I undid:", "",
      prettyDiff (Just 10) diff
      ]
    Input.MergeLocalBranchI src dest -> P.callout "🆕" . P.lines $
      [ P.wrap $
          "Here's what's changed in " <> prettyPath' dest <> "after the merge:"
      , ""
      , prettyDiff (Just 10) diff
      , ""
      , tip "You can always `undo` if this wasn't what you wanted."
      ]
    Input.PullRemoteBranchI _ dest ->
      if Names.isEmptyDiff diff then
        "✅  Looks like " <> prettyPath' dest <> " is up to date."
      else P.callout "🆕" . P.lines $ [
        P.wrap $ "Here's what's changed in " <> prettyPath' dest <> "after the pull:", "",
        prettyDiff (Just 10) diff, "",
        tip "You can always `undo` if this wasn't what you wanted." ]
    Input.PreviewMergeLocalBranchI src dest ->
      P.callout "🔎"
        . P.lines
        $ [ P.wrap
          $  "Here's what would change in "
          <> prettyPath' dest
          <> "after the merge:"
          , ""
          , prettyDiff Nothing diff
          ]
    _ -> prettyDiff Nothing diff
  NothingTodo input -> putPrettyLn . P.callout "😶" $ case input of
    Input.MergeLocalBranchI src dest ->
      P.wrap $ "The merge had no effect, since the destination"
            <> P.shown dest <> "is at or ahead of the source"
            <> P.group (P.shown src <> ".")
    Input.PreviewMergeLocalBranchI src dest ->
      P.wrap $ "The merge will have no effect, since the destination"
            <> P.shown dest <> "is at or ahead of the source"
            <> P.group (P.shown src <> ".")
    _ -> "Nothing to do."
  DumpBitBooster head map -> let
    go output []          = output
    go output (head : queue) = case Map.lookup head map of
      Nothing -> go (renderLine head [] : output) queue
      Just tails -> go (renderLine head tails : output) (queue ++ tails)
      where
      renderHash = take 10 . Text.unpack . Hash.base32Hex . Causal.unRawHash
      renderLine head tail =
        (renderHash head) ++ "|" ++ intercalateMap " " renderHash tail ++
          case Map.lookup (Hash.base32Hex . Causal.unRawHash $ head) tags of
            Just t -> "|tag: " ++ t
            Nothing -> ""
      -- some specific hashes that we want to label in the output
      tags :: Map Text String
      tags = Map.fromList . fmap swap $
        [ ("unisonbase 2019/8/6",  "54s9qjhaonotuo4sp6ujanq7brngk32f30qt5uj61jb461h9fcca6vv5levnoo498bavne4p65lut6k6a7rekaruruh9fsl19agu8j8")
        , ("unisonbase 2019/8/5",  "focmbmg7ca7ht7opvjaqen58fobu3lijfa9adqp7a1l1rlkactd7okoimpfmd0ftfmlch8gucleh54t3rd1e7f13fgei86hnsr6dt1g")
        , ("unisonbase 2019/7/31", "jm2ltsg8hh2b3c3re7aru6e71oepkqlc3skr2v7bqm4h1qgl3srucnmjcl1nb8c9ltdv56dpsgpdur1jhpfs6n5h43kig5bs4vs50co")
        , ("unisonbase 2019/7/25", "an1kuqsa9ca8tqll92m20tvrmdfk0eksplgjbda13evdlngbcn5q72h8u6nb86ojr7cvnemjp70h8cq1n95osgid1koraq3uk377g7g")
        , ("ucm m1b", "o6qocrqcqht2djicb1gcmm5ct4nr45f8g10m86bidjt8meqablp0070qae2tvutnvk4m9l7o1bkakg49c74gduo9eati20ojf0bendo")
        , ("ucm m1, m1a", "auheev8io1fns2pdcnpf85edsddj27crpo9ajdujum78dsncvfdcdu5o7qt186bob417dgmbd26m8idod86080bfivng1edminu3hug")
        ]

    in do
      traverse_ putStrLn (reverse . nubOrd $ go [] [head])
      putStrLn ""
      putStrLn "Paste that output into http://bit-booster.com/graph.html"
  where
  _nameChange _cmd _pastTenseCmd _oldName _newName _r = error "todo"
  -- do
  --   when (not . Set.null $ E.changedSuccessfully r) . putPrettyLn . P.okCallout $
  --     P.wrap $ "I" <> pastTenseCmd <> "the"
  --       <> ns (E.changedSuccessfully r)
  --       <> P.blue (prettyName oldName)
  --       <> "to" <> P.group (P.green (prettyName newName) <> ".")
  --   when (not . Set.null $ E.oldNameConflicted r) . putPrettyLn . P.warnCallout $
  --     (P.wrap $ "I couldn't" <> cmd <> "the"
  --          <> ns (E.oldNameConflicted r)
  --          <> P.blue (prettyName oldName)
  --          <> "to" <> P.green (prettyName newName)
  --          <> "because of conflicts.")
  --     <> "\n\n"
  --     <> tip ("Use " <> makeExample' IP.todo <> " to view more information on conflicts and remaining work.")
  --   when (not . Set.null $ E.newNameAlreadyExists r) . putPrettyLn . P.warnCallout $
  --     (P.wrap $ "I couldn't" <> cmd <> P.blue (prettyName oldName)
  --          <> "to" <> P.green (prettyName newName)
  --          <> "because the "
  --          <> ns (E.newNameAlreadyExists r)
  --          <> "already exist(s).")
  --     <> "\n\n"
  --     <> tip
  --        ("Use" <> makeExample IP.rename [prettyName newName, "<newname>"] <> "to make" <> prettyName newName <> "available.")
--    where
--      ns targets = P.oxfordCommas $
--        map (fromString . Names.renderNameTarget) (toList targets)

prettyPath' :: Path.Path' -> P.Pretty P.ColorText
prettyPath' p' =
  if Path.isCurrentPath p'
  then "the current namespace"
  else P.blue (P.shown p')

formatMissingStuff :: (Show tm, Show typ) =>
  [(HQ.HashQualified, tm)] -> [(HQ.HashQualified, typ)] -> P.Pretty P.ColorText
formatMissingStuff terms types =
  (unlessM (null terms) . P.fatalCallout $
    P.wrap "The following terms have a missing or corrupted type signature:"
    <> "\n\n"
    <> P.column2 [ (P.syntaxToColor $ prettyHashQualified name, fromString (show ref)) | (name, ref) <- terms ]) <>
  (unlessM (null types) . P.fatalCallout $
    P.wrap "The following types weren't found in the codebase:"
    <> "\n\n"
    <> P.column2 [ (P.syntaxToColor $ prettyHashQualified name, fromString (show ref)) | (name, ref) <- types ])

displayDefinitions' :: Var v => Ord a1
  => PPE.PrettyPrintEnv
  -> Map Reference.Reference (DisplayThing (DD.Decl v a1))
  -> Map Reference.Reference (DisplayThing (Unison.Term.AnnotatedTerm v a1))
  -> P.Pretty P.ColorText
displayDefinitions' ppe types terms = P.syntaxToColor $ P.sep "\n\n" (prettyTypes <> prettyTerms)
  where
  prettyTerms = map go . Map.toList
             -- sort by name
             $ Map.mapKeys (first (PPE.termName ppe . Referent.Ref) . dupe) terms
  prettyTypes = map go2 . Map.toList
              $ Map.mapKeys (first (PPE.typeName ppe) . dupe) types
  go ((n, r), dt) =
    case dt of
      MissingThing r -> missing n r
      BuiltinThing -> builtin n
      RegularThing tm -> TermPrinter.prettyBinding ppe n tm
  go2 ((n, r), dt) =
    case dt of
      MissingThing r -> missing n r
      BuiltinThing -> builtin n
      RegularThing decl -> case decl of
        Left d  -> DeclPrinter.prettyEffectDecl ppe r n d
        Right d -> DeclPrinter.prettyDataDecl ppe r n d
  builtin n = P.wrap $ "--" <> prettyHashQualified n <> " is built-in."
  missing n r = P.wrap (
    "-- The name " <> prettyHashQualified n <> " is assigned to the "
    <> "reference " <> fromString (show r ++ ",")
    <> "which is missing from the codebase.")
    <> P.newline
    <> tip "You might need to repair the codebase manually."

displayDefinitions :: Var v => Ord a1 =>
  Maybe FilePath
  -> PPE.PrettyPrintEnv
  -> Map Reference.Reference (DisplayThing (DD.Decl v a1))
  -> Map Reference.Reference (DisplayThing (Unison.Term.AnnotatedTerm v a1))
  -> IO ()
displayDefinitions outputLoc ppe types terms | Map.null types && Map.null terms =
  return ()
displayDefinitions outputLoc ppe types terms =
  maybe displayOnly scratchAndDisplay outputLoc
  where
  displayOnly = putPrettyLn code
  scratchAndDisplay path = do
    path' <- canonicalizePath path
    prependToFile code path'
    putPrettyLn (message code path')
    where
    prependToFile code path = do
      existingContents <- do
        exists <- doesFileExist path
        if exists then readFile path
        else pure ""
      writeFile path . Text.pack . P.toPlain 80 $
        P.lines [ code, ""
                , "---- " <> "Anything below this line is ignored by Unison."
                , "", P.text existingContents ]
    message code path =
      P.callout "☝️" $ P.lines [
        P.wrap $ "I added these definitions to the top of " <> fromString path,
        "",
        P.indentN 2 code,
        "",
        P.wrap $
          "You can edit them there, then do" <> makeExample' IP.update <>
          "to replace the definitions currently in this namespace."
      ]
  code = displayDefinitions' ppe types terms

displayTestResults :: Bool -- whether to show the tip
                   -> PPE.PrettyPrintEnv
                   -> [(Reference, Text)]
                   -> [(Reference, Text)]
                   -> P.Pretty CT.ColorText
displayTestResults showTip ppe oks fails = let
  name r = P.text (HQ.toText $ PPE.termName ppe (Referent.Ref r))
  okMsg =
    if null oks then mempty
    else P.column2 [ (P.green "◉ " <> name r, "  " <> P.green (P.text msg)) | (r, msg) <- oks ]
  okSummary =
    if null oks then mempty
    else "✅ " <> P.bold (P.num (length oks)) <> P.green " test(s) passing"
  failMsg =
    if null fails then mempty
    else P.column2 [ (P.red "✗ " <> name r, "  " <> P.red (P.text msg)) | (r, msg) <- fails ]
  failSummary =
    if null fails then mempty
    else "🚫 " <> P.bold (P.num (length fails)) <> P.red " test(s) failing"
  tipMsg =
    if not showTip || (null oks && null fails) then mempty
    else tip $ "Use " <> P.blue ("view " <> name (fst $ head (fails ++ oks))) <> "to view the source of a test."
  in if null oks && null fails then "😶 No tests available."
     else P.sep "\n\n" . P.nonEmpty $ [
          okMsg, failMsg,
          P.sep ", " . P.nonEmpty $ [failSummary, okSummary], tipMsg]

unsafePrettyTermResultSig' :: Var v =>
  PPE.PrettyPrintEnv -> SR'.TermResult' v a -> P.Pretty P.ColorText
unsafePrettyTermResultSig' ppe = \case
  SR'.TermResult' (HQ'.toHQ -> name) (Just typ) _r _aliases ->
    head (TypePrinter.prettySignatures' ppe [(name,typ)])
  _ -> error "Don't pass Nothing"

-- produces:
-- -- #5v5UtREE1fTiyTsTK2zJ1YNqfiF25SkfUnnji86Lms#0
-- Optional.None, Maybe.Nothing : Maybe a
unsafePrettyTermResultSigFull' :: Var v =>
  PPE.PrettyPrintEnv -> SR'.TermResult' v a -> P.Pretty P.ColorText
unsafePrettyTermResultSigFull' ppe = \case
  SR'.TermResult' (HQ'.toHQ -> hq) (Just typ) r (Set.map HQ'.toHQ -> aliases) ->
   P.lines
    [ P.hiBlack "-- " <> greyHash (HQ.fromReferent r)
    , P.group $
      P.commas (fmap greyHash $ hq : toList aliases) <> " : "
      <> (P.syntaxToColor $ TypePrinter.pretty0 ppe mempty (-1) typ)
    , mempty
    ]
  _ -> error "Don't pass Nothing"
  where greyHash = styleHashQualified' id P.hiBlack

prettyTypeResultHeader' :: Var v => SR'.TypeResult' v a -> P.Pretty P.ColorText
prettyTypeResultHeader' (SR'.TypeResult' (HQ'.toHQ -> name) dt r _aliases) =
  prettyDeclTriple (name, r, dt)

-- produces:
-- -- #5v5UtREE1fTiyTsTK2zJ1YNqfiF25SkfUnnji86Lms
-- type Optional
-- type Maybe
prettyTypeResultHeaderFull' :: Var v => SR'.TypeResult' v a -> P.Pretty P.ColorText
prettyTypeResultHeaderFull' (SR'.TypeResult' (HQ'.toHQ -> name) dt r (Set.map HQ'.toHQ -> aliases)) =
  P.lines stuff <> P.newline
  where
  stuff =
    (P.hiBlack "-- " <> greyHash (HQ.fromReference r)) :
      fmap (\name -> prettyDeclTriple (name, r, dt))
           (name : toList aliases)
    where greyHash = styleHashQualified' id P.hiBlack


-- todo: maybe delete this
prettyAliases ::
  (Foldable t, ListLike s Char, IsString s) => t HQ.HashQualified -> P.Pretty s
prettyAliases aliases = if length aliases < 2 then mempty else error "todo"
  -- (P.commented . (:[]) . P.wrap . P.commas . fmap prettyHashQualified' . toList) aliases <> P.newline

prettyDeclTriple :: Var v =>
  (HQ.HashQualified, Reference.Reference, DisplayThing (DD.Decl v a))
  -> P.Pretty P.ColorText
prettyDeclTriple (name, _, displayDecl) = case displayDecl of
   BuiltinThing -> P.hiBlack "builtin " <> P.hiBlue "type " <> P.blue (P.syntaxToColor $ prettyHashQualified name)
   MissingThing _ -> mempty -- these need to be handled elsewhere
   RegularThing decl -> case decl of
     Left ed -> P.syntaxToColor $ DeclPrinter.prettyEffectHeader name ed
     Right dd   -> P.syntaxToColor $ DeclPrinter.prettyDataHeader name dd

prettyDeclPair :: Var v =>
  PPE.PrettyPrintEnv -> (Reference, DisplayThing (DD.Decl v a))
  -> P.Pretty P.ColorText
prettyDeclPair ppe (r, dt) = prettyDeclTriple (PPE.typeName ppe r, r, dt)

renderNameConflicts :: Set.Set Name -> Set.Set Name -> P.Pretty CT.ColorText
renderNameConflicts conflictedTypeNames conflictedTermNames =
  unlessM (null allNames) $ P.callout "❓" . P.sep "\n\n" . P.nonEmpty $ [
    showConflictedNames "types" conflictedTypeNames,
    showConflictedNames "terms" conflictedTermNames,
    tip $ "This occurs when merging branches that both independently introduce the same name. Use "
        <> makeExample IP.view (prettyName <$> take 3 allNames)
        <> "to see the conflicting defintions, then use "
        <> makeExample' (if (not . null) conflictedTypeNames
                         then IP.renameType else IP.renameTerm)
        <> "to resolve the conflicts."
  ]
  where
    allNames = toList (conflictedTermNames <> conflictedTypeNames)
    showConflictedNames things conflictedNames =
      unlessM (Set.null conflictedNames) $
        P.wrap ("These" <> P.bold (things <> "have conflicting definitions:"))
        `P.hang` P.commas (P.blue . prettyName <$> toList conflictedNames)

renderEditConflicts ::
  PPE.PrettyPrintEnv -> Patch -> P.Pretty CT.ColorText
renderEditConflicts ppe Patch{..} =
  unlessM (null editConflicts) . P.callout "❓" . P.sep "\n\n" $ [
    P.wrap $ "These" <> P.bold "definitions were edited differently"
          <> "in namespaces that have been merged into this one."
          <> "You'll have to tell me what to use as the new definition:",
    P.indentN 2 (P.lines (formatConflict <$> editConflicts))
--    , tip $ "Use " <> makeExample IP.resolve [name (head editConflicts), " <replacement>"] <> " to pick a replacement." -- todo: eventually something with `edit`
    ]
  where
    -- todo: could possibly simplify all of this, but today is a copy/paste day.
    editConflicts :: [Either (Reference, Set TypeEdit.TypeEdit) (Reference, Set TermEdit.TermEdit)]
    editConflicts =
      (fmap Left . Map.toList . R.toMultimap . R.filterManyDom $ _typeEdits) <>
      (fmap Right . Map.toList . R.toMultimap . R.filterManyDom $ _termEdits)
    name = either (typeName . fst) (termName . fst)
    typeName r = styleHashQualified P.bold (PPE.typeName ppe r)
    termName r = styleHashQualified P.bold (PPE.termName ppe (Referent.Ref r))
    formatTypeEdits (r, toList -> es) = P.wrap $
      "The type" <> typeName r <> "was" <>
      (if TypeEdit.Deprecate `elem` es
      then "deprecated and also replaced with"
      else "replaced with") <>
      P.oxfordCommas [ typeName r | TypeEdit.Replace r <- es ]
    formatTermEdits (r, toList -> es) = P.wrap $
      "The term" <> termName r <> "was" <>
      (if TermEdit.Deprecate `elem` es
      then "deprecated and also replaced with"
      else "replaced with") <>
      P.oxfordCommas [ termName r | TermEdit.Replace r _ <- es ]
    formatConflict = either formatTypeEdits formatTermEdits

todoOutput :: Var v => PPE.PrettyPrintEnv -> TO.TodoOutput v a -> IO ()
todoOutput ppe todo =
  if noConflicts && noEdits
  then putPrettyLn $ P.okCallout "No conflicts or edits in progress."
  else putPrettyLn (todoConflicts <> todoEdits)
  where
  noConflicts = TO.nameConflicts todo == mempty
             && TO.editConflicts todo == Patch.empty
  noEdits = TO.todoScore todo == 0
  (frontierTerms, frontierTypes) = TO.todoFrontier todo
  (dirtyTerms, dirtyTypes) = TO.todoFrontierDependents todo
  corruptTerms =
    [ (PPE.termName ppe (Referent.Ref r), r) | (r, Nothing) <- frontierTerms ]
  corruptTypes =
    [ (PPE.typeName ppe r, r) | (r, MissingThing _) <- frontierTypes ]
  goodTerms ts =
    [ (PPE.termName ppe (Referent.Ref r), typ) | (r, Just typ) <- ts ]
  todoConflicts = if noConflicts then mempty else P.lines . P.nonEmpty $
    [ renderEditConflicts ppe (TO.editConflicts todo)
    , renderNameConflicts conflictedTypeNames conflictedTermNames ]
    where
    -- If a conflict is both an edit and a name conflict, we show it in the edit
    -- conflicts section
    c :: Names0
    c = removeEditConflicts (TO.editConflicts todo) (TO.nameConflicts todo)
    conflictedTypeNames = (R.dom . Names.types) c
    conflictedTermNames = (R.dom . Names.terms) c
    -- e.g. `foo#a` has been independently updated to `foo#b` and `foo#c`.
    -- This means there will be a name conflict:
    --    foo -> #b
    --    foo -> #c
    -- as well as an edit conflict:
    --    #a -> #b
    --    #a -> #c
    -- We want to hide/ignore the name conflicts that are also targets of an
    -- edit conflict, so that the edit conflict will be dealt with first.
    -- For example, if hash `h` has multiple edit targets { #x, #y, #z, ...},
    -- we'll temporarily remove name conflicts pointing to { #x, #y, #z, ...}.
    removeEditConflicts :: Ord n => Patch -> Names' n -> Names' n
    removeEditConflicts Patch{..} Names{..} = Names terms' types' where
      terms' = R.filterRan (`Set.notMember` conflictedTermEditTargets) terms
      types' = R.filterRan (`Set.notMember` conflictedTypeEditTargets) types
      conflictedTypeEditTargets :: Set Reference
      conflictedTypeEditTargets =
        Set.fromList $ toList (R.ran typeEditConflicts) >>= TypeEdit.references
      conflictedTermEditTargets :: Set Referent.Referent
      conflictedTermEditTargets =
        Set.fromList . fmap Referent.Ref
          $ toList (R.ran termEditConflicts) >>= TermEdit.references
      typeEditConflicts = R.filterDom (`R.manyDom` _typeEdits) _typeEdits
      termEditConflicts = R.filterDom (`R.manyDom` _termEdits) _termEdits


  todoEdits = unlessM noEdits . P.callout "🚧" . P.sep "\n\n" . P.nonEmpty $
      [ P.wrap ("The namespace has" <> fromString (show (TO.todoScore todo))
              <> "transitive dependent(s) left to upgrade."
              <> "Your edit frontier is the dependents of these definitions:")
      , P.indentN 2 . P.lines $ (
          (prettyDeclPair ppe <$> toList frontierTypes) ++
          TypePrinter.prettySignatures' ppe (goodTerms frontierTerms)
          )
      , P.wrap "I recommend working on them in the following order:"
      , P.indentN 2 . P.lines $
          let unscore (_score,a,b) = (a,b)
          in (prettyDeclPair ppe . unscore <$> toList dirtyTypes) ++
             TypePrinter.prettySignatures'
                ppe
                (goodTerms $ unscore <$> dirtyTerms)
      , formatMissingStuff corruptTerms corruptTypes
      ]

listOfDefinitions ::
  Var v => PPE.PrettyPrintEnv -> E.ListDetailed -> E.ShowAll -> [SR'.SearchResult' v a] -> IO ()
listOfDefinitions ppe detailed showAll results =
  putPrettyLn $ listOfDefinitions' ppe detailed showAll results

noResults :: P.Pretty P.ColorText
noResults = P.callout "😶" $
    P.wrap $ "No results. Check your spelling, or try using tab completion "
          <> "to supply command arguments."

listOfDefinitions' :: Var v
                   => PPE.PrettyPrintEnv -- for printing types of terms :-\
                   -> E.ListDetailed
                   -> E.ShowAll
                   -> [SR'.SearchResult' v a]
                   -> P.Pretty P.ColorText
listOfDefinitions' ppe detailed showAll results =
  if null results then noResults
  else P.lines . P.nonEmpty $ prettyNumberedResults :
    [ if len <= cap then mempty
      else P.lines [ "... " <> P.shown (len - cap) <> " more"
                   , ""
                   , P.wrap $
                       "The" <> makeExample IP.findAll [] <>
                       "command shows all results." ]
    ,formatMissingStuff termsWithMissingTypes missingTypes
    ,unlessM (null missingBuiltins) . bigproblem $ P.wrap
      "I encountered an inconsistency in the codebase; these definitions refer to built-ins that this version of unison doesn't know about:" `P.hang`
        P.column2 ( (P.bold "Name", P.bold "Built-in")
                  -- : ("-", "-")
                  : fmap (bimap (P.syntaxToColor . prettyHashQualified)
                                (P.text . Referent.toText)) missingBuiltins)
    ]
  where
  len = length results
  cap = if detailed || showAll then len else 15
  prettyNumberedResults =
    P.numbered (\i -> P.hiBlack . fromString $ show i <> ".")
               (take cap prettyResults)
  -- todo: group this by namespace
  prettyResults =
    map (SR'.foldResult' renderTerm renderType)
        (filter (not.missingType) results)
    where
      (renderTerm, renderType) =
        if detailed then
          (unsafePrettyTermResultSigFull' ppe, prettyTypeResultHeaderFull')
        else
          (unsafePrettyTermResultSig' ppe, prettyTypeResultHeader')
  missingType (SR'.Tm _ Nothing _ _)          = True
  missingType (SR'.Tp _ (MissingThing _) _ _) = True
  missingType _                             = False
  -- termsWithTypes = [(name,t) | (name, Just t) <- sigs0 ]
  --   where sigs0 = (\(name, _, typ) -> (name, typ)) <$> terms
  termsWithMissingTypes =
    [ (HQ'.toHQ name, r)
    | SR'.Tm name Nothing (Referent.Ref (Reference.DerivedId r)) _ <- results ]
  missingTypes = nubOrdOn snd $
    [ (HQ'.toHQ name, Reference.DerivedId r)
    | SR'.Tp name (MissingThing r) _ _ <- results ] <>
    [ (HQ'.toHQ name, r)
    | SR'.Tm name Nothing (Referent.toTypeReference -> Just r) _ <- results]
  missingBuiltins = results >>= \case
    SR'.Tm name Nothing r@(Referent.Ref (Reference.Builtin _)) _ -> [(HQ'.toHQ name,r)]
    _ -> []

watchPrinter
  :: Var v
  => Text
  -> PPE.PrettyPrintEnv
  -> Ann
  -> UF.WatchKind
  -> Codebase.Term v ()
  -> Runtime.IsCacheHit
  -> P.Pretty P.ColorText
watchPrinter src ppe ann kind term isHit =
  P.bracket
    $ let
        lines        = Text.lines src
        lineNum      = fromMaybe 1 $ startingLine ann
        lineNumWidth = length (show lineNum)
        extra        = "     " <> replicate (length kind) ' ' -- for the ` | > ` after the line number
        line         = lines !! (lineNum - 1)
        addCache p = if isHit then p <> " (cached)" else p
        renderTest (Term.App' (Term.Constructor' _ id) (Term.Text' msg)) =
          "\n" <> if id == DD.okConstructorId
            then addCache
              (P.green "✅ " <> P.bold "Passed" <> P.green (P.text msg'))
            else if id == DD.failConstructorId
              then addCache
                (P.red "🚫 " <> P.bold "FAILED" <> P.red (P.text msg'))
              else P.red "❓ " <> TermPrinter.pretty ppe term
            where
              msg' = if Text.take 1 msg == " " then msg
                     else " " <> msg

        renderTest x =
          fromString $ "\n Unison bug: " <> show x <> " is not a test."
      in
        P.lines
          [ fromString (show lineNum) <> " | " <> P.text line
          , case (kind, term) of
            (UF.TestWatch, Term.Sequence' tests) -> foldMap renderTest tests
            _ -> P.lines
              [ fromString (replicate lineNumWidth ' ')
              <> fromString extra
              <> (if isHit then id else P.purple) "⧩"
              , P.indentN (lineNumWidth + length extra)
              . (if isHit then id else P.bold)
              $ TermPrinter.pretty ppe term
              ]
          ]

filestatusTip :: P.Pretty CT.ColorText
filestatusTip = tip "Use `help filestatus` to learn more."

prettyDiff :: Maybe Int -> Names.Diff -> P.Pretty P.ColorText
prettyDiff cap diff = let
  orig = Names.originalNames diff
  adds = Names.addedNames diff
  removes = Names.removedNames diff
  addedTerms = [ n | (n,r) <- R.toList (Names.terms0 adds)
                   , not $ R.memberRan r (Names.terms0 removes) ]
  addedTypes = [ n | (n,r) <- R.toList (Names.types0 adds)
                   , not $ R.memberRan r (Names.types0 removes) ]
  added = Name.sortNames . nubOrd $ (addedTerms <> addedTypes)

  removedTerms = [ n | (n,r) <- R.toList (Names.terms0 removes)
                     , not $ R.memberRan r (Names.terms0 adds)
                     , Set.notMember n addedTermsSet ] where
    addedTermsSet = Set.fromList addedTerms
  removedTypes = [ n | (n,r) <- R.toList (Names.types0 removes)
                     , not $ R.memberRan r (Names.types0 adds)
                     , Set.notMember n addedTypesSet ] where
    addedTypesSet = Set.fromList addedTypes
  removed = Name.sortNames . nubOrd $ (removedTerms <> removedTypes)

  movedTerms = [ (n,n2) | (n,r) <- R.toList (Names.terms0 removes)
                        , n2 <- toList (R.lookupRan r (Names.terms adds)) ]
  movedTypes = [ (n,n2) | (n,r) <- R.toList (Names.types removes)
                        , n2 <- toList (R.lookupRan r (Names.types adds)) ]
  moved = Name.sortNamed fst . nubOrd $ (movedTerms <> movedTypes)

  copiedTerms = List.multimap [
    (n,n2) | (n2,r) <- R.toList (Names.terms0 adds)
           , not (R.memberRan r (Names.terms0 removes))
           , n <- toList (R.lookupRan r (Names.terms0 orig)) ]
  copiedTypes = List.multimap [
    (n,n2) | (n2,r) <- R.toList (Names.types0 adds)
           , not (R.memberRan r (Names.types0 removes))
           , n <- toList (R.lookupRan r (Names.types0 orig)) ]
  copied = Name.sortNamed fst $
    Map.toList (Map.unionWith (<>) copiedTerms copiedTypes)
  in
  P.sepNonEmpty "\n\n" [
     if not $ null added then
       P.lines [
         -- todo: split out updates
         P.green "+ Adds / updates:", "",
         P.indentN 2 . P.wrap $
           P.excerptSep cap " " (prettyName <$> added)
       ]
     else mempty,
     if not $ null removed then
       P.lines [
         P.hiBlack "- Deletes:", "",
         P.indentN 2 . P.wrap $
           P.excerptSep cap " " (prettyName <$> removed)
       ]
     else mempty,
     if not $ null moved then
       P.lines [
         P.purple "> Moves:", "",
         P.indentN 2 $
           P.excerptColumn2Headed cap
             (P.hiBlack "Original name", P.hiBlack "New name")
             [ (prettyName n,prettyName n2) | (n, n2) <- moved ]
       ]
     else mempty,
     if not $ null copied then
       P.lines [
         P.yellow "= Copies:", "",
         P.indentN 2 $
           P.excerptColumn2Headed cap
             (P.hiBlack "Original name", P.hiBlack "New name(s)")
             [ (prettyName n, P.sep " " (prettyName <$> ns))
             | (n, ns) <- copied ]
       ]
     else mempty
   ]

isTestOk :: Codebase.Term v Ann -> Bool
isTestOk tm = case tm of
  Term.Sequence' ts -> all isSuccess ts where
    isSuccess (Term.App' (Term.Constructor' ref cid) _) =
      cid == DD.okConstructorId &&
      ref == DD.testResultRef
    isSuccess _ = False
  _ -> False
