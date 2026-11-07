-- | Taking a change to the dependents of what it changed, typechecking only the ones that could be affected, for
-- @update@, @upgrade@ and @merge@.
module Unison.UnisonFile.Propagate
  ( Frontier (..),
    Propagated (..),
    fileDeclRefs,
    printedDependents,
    retypeWith,
    substituteDependents,
    substitutions,
    termRefsIn,
    termsNamed,
    typeUpdatesOf,
    typecheckDependentsAlways,
    typecheckFrontier,
  )
where

import Control.Lens (_3)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import System.Environment (lookupEnv)
import System.IO.Unsafe (unsafePerformIO)
import Unison.ABT qualified as ABT
import Unison.Hash (Hash)
import Unison.Name (Name)
import Unison.Parser.Ann (Ann)
import Unison.Prelude
import Unison.Reference (TermReference, TermReferenceId, TypeReference, TypeReferenceId)
import Unison.Reference qualified as Reference
import Unison.Symbol (Symbol)
import Unison.Syntax.Name qualified as Name (toVar, unsafeParseVar)
import Unison.Term (Term)
import Unison.Term qualified as Term
import Unison.Type (Type)
import Unison.Type qualified as Type
import Unison.UnisonFile (TypecheckedUnisonFile)
import Unison.UnisonFile qualified as UF
import Unison.Util.BiMultimap (BiMultimap)
import Unison.Util.BiMultimap qualified as BiMultimap
import Unison.Util.Set qualified as Set

-- | The reference of each type in a file, by name.
fileDeclRefs :: TypecheckedUnisonFile Symbol Ann -> Map Name TypeReferenceId
fileDeclRefs file =
  Map.fromList $
    [(Name.unsafeParseVar var, ref) | (var, (ref, _)) <- Map.toList (UF.dataDeclarationsId' file)]
      ++ [(Name.unsafeParseVar var, ref) | (var, (ref, _)) <- Map.toList (UF.effectDeclarationsId' file)]

-- | Set @UNISON_UPDATE_TYPECHECK_DEPENDENTS@ to typecheck an update's dependents again even when no type changed, the
-- way `update` always did.
typecheckDependentsAlways :: Bool
typecheckDependentsAlways =
  isJust . unsafePerformIO $ lookupEnv "UNISON_UPDATE_TYPECHECK_DEPENDENTS"
{-# NOINLINE typecheckDependentsAlways #-}

-- | The outcome of propagating an update to its dependents: the file to save, or a dependent that doesn't typecheck.
data Propagated
  = Propagated'File (TypecheckedUnisonFile Symbol Ann)
  | Propagated'Failed

-- | How 'typecheckFrontier' ends.
data Frontier
  = Frontier'Typechecked (Map Name (Term Symbol Ann, Type Symbol Ann))
  | Frontier'Failed
  | Frontier'GaveUp

-- | What each term reference becomes in the file: an updated term or a dependent, as a variable.
substitutions ::
  Map TermReferenceId Symbol ->
  Map Name (TermReferenceId, (Term Symbol Ann, Type Symbol Ann)) ->
  Map TermReferenceId Symbol
substitutions updated dependents =
  updated <> Map.fromList [(ref, Name.toVar name) | (name, (ref, _)) <- Map.toList dependents]

-- | The term references a term makes.
termRefsIn :: Term Symbol Ann -> Set TermReferenceId
termRefsIn term =
  Set.fromList [ref | Term.Ref' (Reference.DerivedId ref) <- ABT.subterms term]

-- | The references in a term whose substitution would be captured by a local variable of the same name.
capturedIn :: Map TermReferenceId Symbol -> Term Symbol Ann -> Set TermReferenceId
capturedIn replacements term =
  Set.filter (maybe False (`Set.member` binders term) . (`Map.lookup` replacements)) (termRefsIn term)
  where
    binders :: Term Symbol Ann -> Set Symbol
    binders subterm =
      case ABT.out subterm of
        ABT.Var _ -> Set.empty
        ABT.Cycle body -> binders body
        ABT.Abs var body -> Set.insert var (binders body)
        ABT.Tm body -> foldMap binders body

-- | @typeUpdatesOf namespaceTypes declRefs oldRefs@ works out where each old type reference goes, given the new reference
-- of each name the file defines. The names of a type usually go together; when they don't (one of two aliases is
-- updated, or a recursive type printed under two names leaves its cycle) a reference to it follows whichever name is
-- printed, so it can't be substituted and is returned in the second part instead.
typeUpdatesOf ::
  BiMultimap TypeReference Name ->
  Map Name TypeReferenceId ->
  [TypeReferenceId] ->
  (Map TypeReference TypeReference, Set TypeReference)
typeUpdatesOf namespaceTypes declRefs oldRefs =
  ( Map.fromList
      [ (old, new)
      | (old, targets) <- destinations,
        Just new <- [Set.asSingleton targets],
        new /= old
      ],
    Set.fromList [old | (old, targets) <- destinations, Set.size targets > 1]
  )
  where
    destinations :: [(TypeReference, Set TypeReference)]
    destinations =
      [ (old, Set.map (\name -> maybe old Reference.fromId (Map.lookup name declRefs)) (BiMultimap.lookupDom old namespaceTypes))
      | old <- map Reference.fromId oldRefs
      ]

-- | @typecheckFrontier typecheck retype dependents seeds changed@ typechecks again the dependents in @seeds@ and the
-- ones that refer to a term whose type changed, then the ones that refer to one of those whose type changed in turn,
-- and so on: the type-preserving frontier of #904. Each round typechecks everything found so far, since the next round
-- may refer to it. A type is compared with the old one as @retype@ gives it, with the new references of updated types.
--
-- A dependent outside the frontier keeps its type, so the frontier can be typechecked against its old reference, given
-- that type, and 'substituteDependents' then replaces the reference. Dependents are printed with their signatures, so
-- the frontier usually ends one round past the update.
--
-- It fails when a dependent doesn't typecheck, and gives up (for the slow path to run instead) when the frontier is
-- still growing after ten rounds, or a round doesn't give back every dependent it was asked about.
typecheckFrontier ::
  (Monad m) =>
  (Set Name -> m (Maybe (Map Name (Term Symbol Ann, Type Symbol Ann)))) ->
  (Type Symbol Ann -> Type Symbol Ann) ->
  Map Name (TermReferenceId, (Term Symbol Ann, Type Symbol Ann)) ->
  Set Name ->
  Set TermReferenceId ->
  m Frontier
typecheckFrontier typecheck retype dependents seeds =
  go (10 :: Int) Set.empty Map.empty
  where
    go rounds frontier typechecked changed
      | Set.null next = pure (Frontier'Typechecked typechecked)
      | rounds == 0 = pure Frontier'GaveUp
      | otherwise =
          typecheck frontier' >>= \case
            Nothing -> pure Frontier'Failed
            Just typechecked'
              | Map.keysSet typechecked' == frontier' -> go (rounds - 1) frontier' typechecked' (changed <> changedIn typechecked')
              | otherwise -> pure Frontier'GaveUp
      where
        next =
          Map.keysSet $
            Map.filterWithKey
              (\name (_, (term, _)) -> Set.notMember name frontier && (Set.member name seeds || refersTo changed term))
              dependents
        frontier' = frontier <> next

    changedIn :: Map Name (Term Symbol Ann, Type Symbol Ann) -> Set TermReferenceId
    changedIn typechecked =
      Set.fromList
        [ ref
        | (name, (_, typ)) <- Map.toList typechecked,
          Just (ref, (_, oldType)) <- [Map.lookup name dependents],
          typ /= retype oldType
        ]

    refersTo :: Set TermReferenceId -> Term Symbol Ann -> Bool
    refersTo refs term =
      not (Set.disjoint refs (termRefsIn term))

-- | A stored type with every updated type's new reference in place of its old one. An ability's new reference can sort
-- differently from its old one, and a list of abilities is kept sorted, so the list is sorted again.
retypeWith :: Map TypeReference TypeReference -> Type Symbol Ann -> Type Symbol Ann
retypeWith typeUpdates
  | Map.null typeUpdates = id
  | otherwise = Type.cleanupAbilityLists . Type.updateDependencies typeUpdates

-- | The named terms in a typechecked file, with their types. A test in the codebase prints as a test watch, so those
-- count too.
termsNamed :: Set Name -> TypecheckedUnisonFile Symbol Ann -> Map Name (Term Symbol Ann, Type Symbol Ann)
termsNamed names typechecked =
  Map.fromList
    [ (name, (term, typ))
    | (var, _, term, typ) <- concat (UF.topLevelComponents typechecked),
      let name = Name.unsafeParseVar var,
      Set.member name names
    ]

-- | @substituteDependents file declFile updated termUpdates typeUpdates typechecked dependents@ gives every dependent
-- its new references and hashes it with the file and the types in @declFile@: the ones in @typechecked@ as they
-- typechecked, and the rest as they are stored. @termUpdates@ holds the references that move to a term outside the file,
-- as an upgrade's do. A term link is left alone, as printing and parsing leaves it: the parser resolves it
-- against the namespace and the file's constructors, not the file's terms (a dependent with a link to a constructor of
-- an updated type is typechecked again instead). A type link takes the type's new reference, as the parser resolves it
-- to the type printed into the file.
--
-- Returns 'Nothing' when a substitution would still be captured by a local variable. That is a safety check: the
-- dependents where it could happen are printed ('printedDependents'), and an update's own file refers to nothing that
-- is substituted.
substituteDependents ::
  TypecheckedUnisonFile Symbol Ann ->
  TypecheckedUnisonFile Symbol Ann ->
  Map TermReferenceId Symbol ->
  Map TermReference TermReference ->
  Map TypeReference TypeReference ->
  Map Name (Term Symbol Ann, Type Symbol Ann) ->
  Map Name (TermReferenceId, (Term Symbol Ann, Type Symbol Ann)) ->
  Maybe (TypecheckedUnisonFile Symbol Ann)
substituteDependents file declFile updated termUpdates typeUpdates typechecked dependents = do
  let replacements = substitutions updated dependents

  let replaceTerms :: Term Symbol Ann -> Term Symbol Ann
      replaceTerms =
        ABT.visitPure \case
          term@(Term.Ref' ref) ->
            case Reference.toId ref >>= (`Map.lookup` replacements) of
              Just var -> Just (Term.var (ABT.annotation term) var)
              Nothing -> Term.ref (ABT.annotation term) <$> Map.lookup ref termUpdates
          _ -> Nothing

  -- Annotations and type links inside a term name types, which take their new references, as the parser resolves them
  -- to the types printed into the file
  let replaceTypes :: Term Symbol Ann -> Term Symbol Ann
      replaceTypes =
        ABT.rebuildUp \case
          Term.Ann term typ -> Term.Ann term (Type.updateDependencies typeUpdates typ)
          Term.TypeLink ref -> Term.TypeLink (Map.findWithDefault ref ref typeUpdates)
          other -> other

  let dependentBindings :: [[(Symbol, Ann, Term Symbol Ann, Type Symbol Ann)]]
      dependentBindings =
        [ [(Name.toVar name, ABT.annotation term, term, retypeWith typeUpdates typ)]
        | (name, (_, stored)) <- Map.toList dependents,
          let (term, typ) = Map.findWithDefault stored name typechecked
        ]

  let everyTerm =
        [term | (_, _, term, _) <- concat dependentBindings ++ concat (UF.topLevelComponents' file)]
          ++ [term | (_, terms) <- UF.watchComponents file, (_, _, term, _) <- terms]
  guard (all (Set.null . capturedIn replacements) everyTerm)

  let replaceIn = map (over _3 (replaceTerms . replaceTypes))
  pure $
    UF.typecheckedUnisonFile
      (UF.dataDeclarationsId' declFile)
      (UF.effectDeclarationsId' declFile)
      (map replaceIn (UF.topLevelComponents' file ++ dependentBindings))
      (map (second replaceIn) (UF.watchComponents file))

-- | @printedDependents aliased aliasedUpdates replacements dependents@ gives the dependents that have to be printed
-- rather than substituted, because a printer's choice of name matters to them: the ones that refer to something in
-- @aliasedUpdates@ or to a recursive dependent with an alias, and the ones a substitution would be captured in, with the
-- dependents it would have put there.
printedDependents ::
  (TermReferenceId -> Bool) ->
  Set TermReferenceId ->
  Map TermReferenceId Symbol ->
  Map Name (TermReferenceId, (Term Symbol Ann, Type Symbol Ann)) ->
  Set Name
printedDependents aliased aliasedUpdates replacements dependents =
  Map.keysSet (Map.filter (\(ref, (term, _)) -> mustPrint ref term) dependents)
  where
    -- The components holding a recursive dependent with an alias
    aliasedCycles :: Set Hash
    aliasedCycles =
      Set.fromList
        [ Reference.idToHash ref
        | (ref, (term, _)) <- Map.elems dependents,
          aliased ref,
          Set.member (Reference.idToHash ref) (Set.map Reference.idToHash (termRefsIn term))
        ]

    captured :: Set TermReferenceId
    captured =
      foldMap (capturedIn replacements . fst . snd) dependents

    mustPrint :: TermReferenceId -> Term Symbol Ann -> Bool
    mustPrint ref term =
      let refs = termRefsIn term
       in not (Set.disjoint refs aliasedUpdates)
            || not (Set.disjoint (Set.map Reference.idToHash refs) aliasedCycles)
            || not (Set.null (capturedIn replacements term))
            || Set.member ref captured
