-- | Taking a merge's changes to the dependents without typechecking every one of them.
module Unison.Merge.Propagate
  ( propagateMerge,
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Unison.ABT qualified as ABT
import Unison.DataDeclaration (Decl)
import Unison.DataDeclaration qualified as Decl
import Unison.Name (Name)
import Unison.Names (Names (..))
import Unison.Names qualified as Names
import Unison.Parser.Ann (Ann)
import Unison.Prelude
import Unison.Reference (Reference' (ReferenceDerived), TermReference, TermReferenceId, TypeReference, TypeReferenceId)
import Unison.Reference qualified as Reference
import Unison.Referent qualified as Referent
import Unison.Symbol (Symbol)
import Unison.Term (Term)
import Unison.Term qualified as Term
import Unison.Type (Type)
import Unison.Type qualified as Type
import Unison.Typechecker.TypeLookup (TypeLookup (..))
import Unison.UnisonFile (TypecheckedUnisonFile)
import Unison.UnisonFile qualified as UF
import Unison.UnisonFile.Propagate
import Unison.Util.Defns (Defns (..), DefnsF)
import Unison.Util.Relation qualified as Relation
import Unison.Util.Set qualified as Set

-- | Where a reference in a dependent goes: to a dependent, or to something in the merged namespace.
data Target
  = Target'Dependent TermReferenceId
  | Target'Namespace TermReference
  deriving stock (Eq, Ord)

targetReference :: Target -> TermReference
targetReference = \case
  Target'Dependent ref -> Reference.fromId ref
  Target'Namespace ref -> ref

-- | @propagateMerge typecheck loadTypeLookup printed merged dependents@ gives the dependents of a merge their new
-- references, typechecking only the ones that could be affected ('typecheckFrontier').
--
-- Printing a dependent and parsing it in the merged namespace moves each reference by name, from a name in @printed@ to
-- whatever has that name in @merged@ or among the dependents. A reference with one destination can be substituted, and a
-- dependent that makes one without is left to the printer. A dependent's reference might be Alice's version of a name
-- whose dependent is Bob's, so 'typecheckFrontier' is given the dependents with their references moved.
--
-- @typecheck@ typechecks the dependent types and the named dependent terms, printed, with the given types for the
-- other terms. It returns 'Nothing' when only the slow path can tell.
propagateMerge ::
  forall m.
  (Monad m) =>
  (Map TermReference (Type Symbol Ann) -> Set Name -> m (Maybe (TypecheckedUnisonFile Symbol Ann))) ->
  (DefnsF Set TermReference TypeReference -> m (TypeLookup Symbol Ann)) ->
  Names ->
  Names ->
  DefnsF (Map Name) (TermReferenceId, (Term Symbol Ann, Type Symbol Ann)) (TypeReferenceId, Decl Symbol Ann) ->
  m (Maybe Propagated)
propagateMerge typecheck loadTypeLookup printed merged dependents = do
  let noFile = UF.typecheckedUnisonFile Map.empty Map.empty [] []

  declFile <- if Map.null dependents.types then pure (Just noFile) else typecheck Map.empty Set.empty

  case declFile of
    Nothing -> pure (Just Propagated'Failed)
    Just declFile -> do
      let termDestination :: TermReference -> Maybe Target
          termDestination ref =
            traverse targetOf (Set.toList (Names.namesForReferent printed (Referent.Ref ref))) >>= Set.asSingleton . Set.fromList
            where
              targetOf :: Name -> Maybe Target
              targetOf name =
                case Map.lookup name dependents.terms of
                  Just (dependent, _) -> Just (Target'Dependent dependent)
                  Nothing ->
                    Set.asSingleton (Relation.lookupDom name merged.terms) >>= \case
                      Referent.Ref new -> Just (Target'Namespace new)
                      Referent.Con _ _ -> Nothing

      let termRefs = foldMap (Term.termDependencies . fst . snd) dependents.terms
      let termDestinations = [(ref, termDestination ref) | ref <- Set.toList termRefs]

      -- The stored types of the references that move, and of where they go
      let movedTerms = [(ref, target) | (ref, Just target) <- termDestinations, ref /= targetReference target]
      storedTypes <-
        (.typeOfTerms)
          <$> loadTypeLookup
            Defns
              { terms = Set.fromList (concat [[ref, targetReference target] | (ref, target) <- movedTerms]),
                types = Set.empty
              }

      let typeDestination :: TypeReference -> Maybe TypeReference
          typeDestination ref =
            traverse targetOf (Set.toList (Names.namesForReference printed ref)) >>= Set.asSingleton . Set.fromList
            where
              targetOf :: Name -> Maybe TypeReference
              targetOf name
                | Map.member name dependents.types = Reference.fromId <$> Map.lookup name (fileDeclRefs declFile)
                | otherwise = Set.asSingleton (Relation.lookupDom name merged.types)

      let typeRefs =
            foldMap
              (\(_, (term, typ)) -> Term.typeDependencies term <> Term.constructorDependencies term <> Type.dependencies typ)
              dependents.terms
              <> foldMap Type.dependencies storedTypes
      let movedTypes = [(ref, new) | ref <- Set.toList typeRefs, Just new <- [typeDestination ref], ref /= new]

      storedDecls <-
        loadTypeLookup
          Defns
            { terms = Set.empty,
              types = Set.fromList (concat [[ref, new] | (ref, new) <- movedTypes])
            }

      -- Whether each type is an ability, if it has no parameters. A type's kind can't have changed if it has none
      -- before and after and doesn't switch between data and ability, and a substitution can't check any other.
      let abilityOf :: TypeReference -> Maybe Bool
          abilityOf ref =
            asum
              [ Map.lookup ref storedDecls.dataDecls >>= \decl -> False <$ guard (null (Decl.bound decl)),
                Map.lookup ref storedDecls.effectDecls >>= \decl -> True <$ guard (null (Decl.bound (Decl.toDataDecl decl))),
                Reference.toId ref >>= \id -> Map.lookup id fileDecls >>= \decl -> isLeft decl <$ guard (null (Decl.bound (Decl.asDataDecl decl)))
              ]

          fileDecls :: Map TypeReferenceId (Decl Symbol Ann)
          fileDecls =
            Map.fromList $
              [(ref, Right decl) | (ref, decl) <- Map.elems (UF.dataDeclarationsId' declFile)]
                ++ [(ref, Left decl) | (ref, decl) <- Map.elems (UF.effectDeclarationsId' declFile)]

      let typeUpdates =
            Map.fromList [(ref, new) | (ref, new) <- movedTypes, isJust (abilityOf ref), abilityOf ref == abilityOf new]

      let printedTypes =
            Set.filter (\ref -> Map.notMember ref typeUpdates && maybe True (/= ref) (typeDestination ref)) typeRefs

      let retype = retypeWith typeUpdates

      let printedTerms = Set.fromList [ref | (ref, Nothing) <- termDestinations]

      let toDependents = substitutions Map.empty dependents.terms

      -- The references that move to a dependent become the variable that names it, as its own references do
      let updated =
            Map.fromList
              [ (id, var)
              | (ReferenceDerived id, Target'Dependent dependent) <- movedTerms,
                Just var <- [Map.lookup dependent toDependents]
              ]
      let termUpdates = Map.fromList [(ref, new) | (ref, Target'Namespace new) <- movedTerms]

      let moved = Map.fromList [(ref, targetReference target) | (ref, target) <- movedTerms]

      let moveReferences :: Term Symbol Ann -> Term Symbol Ann
          moveReferences =
            ABT.visitPure \case
              term@(Term.Ref' ref) -> Term.ref (ABT.annotation term) <$> Map.lookup ref moved
              _ -> Nothing

      -- A reference that moves to something of another type is a change of type in its destination
      let changed =
            Set.fromList
              [ id
              | (ref, target) <- movedTerms,
                ReferenceDerived id <- [targetReference target],
                fmap retype (Map.lookup ref storedTypes) /= fmap retype (Map.lookup (targetReference target) storedTypes)
              ]

      let mustPrint :: Term Symbol Ann -> Type Symbol Ann -> Bool
          mustPrint term typ =
            not (Set.disjoint (Term.constructorDependencies term) (Map.keysSet typeUpdates))
              || not (Set.disjoint (Term.typeDependencies term <> Term.constructorDependencies term <> Type.dependencies typ) printedTypes)
              || not (Set.disjoint (Term.termDependencies term) printedTerms)
              || not (null [() | Term.TermLink' _ <- ABT.subterms term])

      let aliased :: TermReferenceId -> Bool
          aliased ref =
            Set.size (Names.namesForReferent printed (Referent.fromTermReferenceId ref)) > 1

      let seeds =
            printedDependents aliased Set.empty (substitutions updated dependents.terms) dependents.terms
              <> Map.keysSet (Map.filter (\(_, (term, typ)) -> mustPrint term typ) dependents.terms)

      let retyped =
            Map.fromList [(Reference.fromId ref, retype typ) | (ref, (_, typ)) <- Map.elems dependents.terms]

      frontier <-
        typecheckFrontier
          (\names -> fmap (termsNamed names) <$> typecheck retyped names)
          retype
          (fmap (second (first moveReferences)) dependents.terms)
          seeds
          changed

      pure case frontier of
        Frontier'GaveUp -> Nothing
        Frontier'Failed -> Just Propagated'Failed
        Frontier'Typechecked typechecked ->
          Propagated'File
            <$> substituteDependents noFile declFile updated termUpdates typeUpdates typechecked dependents.terms
