-- | @project.push@ input handler
module Unison.Codebase.Editor.HandleInput.ProjectPush
  ( projectPush,
  )
where

import Control.Lens ((^.))
import Data.Text as Text
import qualified Text.Builder
import qualified U.Codebase.Sqlite.Queries as Queries
import Unison.Cli.Monad (Cli)
import qualified Unison.Cli.Monad as Cli
import Unison.Cli.ProjectUtils (getCurrentProjectBranch, loggeth)
import qualified Unison.Cli.Share.Projects as Share
import qualified Unison.Codebase.Editor.HandleInput.AuthLogin as AuthLogin
import Unison.Prelude
import Unison.Project (ProjectAndBranch, ProjectBranchName, ProjectName, classifyProjectName)
import qualified Unison.Share.API.Projects as Share.API
import qualified Unison.Share.Codeserver as Codeserver
import qualified Unison.Sqlite as Sqlite
import Witch (unsafeFrom)

-- | Push a project branch.
projectPush :: Maybe (ProjectAndBranch ProjectName (Maybe ProjectBranchName)) -> Cli ()
projectPush maybeProjectAndBranch = do
  (projectId, currentBranchId) <-
    getCurrentProjectBranch & onNothingM do
      loggeth ["Not currently on a branch"]
      Cli.returnEarlyWithoutOutput

  -- Resolve where to push:
  --   if (project/branch names provided)
  --     if (ids in remote_project / remote_project_branch tables)
  --       use those
  --     else
  --       ask Share
  --   else if (default push location exists),
  --     if (its remote branch id is non-null)
  --       use that
  --     else
  --       if (this branch name exists in that project)
  --         use that
  --       else
  --         create a branch with this name
  --   else
  --     ask Share for my username
  --     if (I'm not logged in)
  --       fail -- don't know where to push
  --     else
  --

  case maybeProjectAndBranch of
    Nothing -> do
      Cli.runTransaction oinkResolveRemoteIds >>= \case
        Nothing -> do
          loggeth ["We don't have a remote branch mapping for this branch or any ancestor"]
          loggeth ["Getting current logged-in user on Share"]
          myUserHandle <- oinkGetLoggedInUser
          loggeth ["Got current logged-in user on Share: ", myUserHandle]
          project <- Cli.runTransaction (Queries.expectProject projectId)
          let localProjectName = unsafeFrom @Text (project ^. #name)
          let remoteProjectName =
                case classifyProjectName localProjectName of
                  (Nothing, name) ->
                    Text.Builder.run $
                      Text.Builder.char '@'
                        <> Text.Builder.text myUserHandle
                        <> Text.Builder.char '/'
                        <> Text.Builder.text name
                  (Just _, _) -> into @Text localProjectName
          loggeth ["Making create-project request for project", remoteProjectName]
          response <-
            Share.createProject Share.API.CreateProjectRequest {projectName = remoteProjectName} & onLeftM \err -> do
              loggeth ["Creating a project failed"]
              loggeth [tShow err]
              Cli.returnEarlyWithoutOutput
          remoteProject <-
            case response of
              Share.API.CreateProjectResponseBadRequest -> do
                loggeth ["Share says: bad request"]
                Cli.returnEarlyWithoutOutput
              Share.API.CreateProjectResponseUnauthorized -> do
                loggeth ["Share says: unauthorized"]
                Cli.returnEarlyWithoutOutput
              Share.API.CreateProjectResponseSuccess remoteProject -> pure remoteProject
          loggeth ["Share says: success!"]
          loggeth [tShow remoteProject]
          -- TODO push this branch
          Cli.returnEarlyWithoutOutput
        Just projectAndBranch ->
          case projectAndBranch ^. #branch of
            Nothing -> do
              let ancestorRemoteProjectId = projectAndBranch ^. #project
              loggeth ["We don't have a remote branch mapping, but our ancestor maps to project: ", ancestorRemoteProjectId]
              loggeth ["Creating remote branch not implemented"]
              Cli.returnEarlyWithoutOutput
            Just remoteBranchId -> do
              let remoteProjectId = projectAndBranch ^. #project
              loggeth ["Found remote branch mapping: ", remoteProjectId, ":", remoteBranchId]
              loggeth ["Pushing to existing branch not implemented"]
              Cli.returnEarlyWithoutOutput
    Just projectAndBranch -> do
      let _projectName = projectAndBranch ^. #project
      let _branchName = fromMaybe (unsafeFrom @Text "main") (projectAndBranch ^. #branch)
      loggeth ["Specifying project/branch to push to not implemented"]
      Cli.returnEarlyWithoutOutput

oinkResolveRemoteIds :: Sqlite.Transaction (Maybe (ProjectAndBranch Text (Maybe Text)))
oinkResolveRemoteIds = undefined

oinkGetLoggedInUser :: Cli Text
oinkGetLoggedInUser = do
  AuthLogin.ensureAuthenticatedWithCodeserver Codeserver.defaultCodeserver
  wundefined
