{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

----------------------------------------------------------------------
-- |
-- Module: Licensor
-- Description:
--
--
--
----------------------------------------------------------------------

module Licensor
  ( LiLicense(..)
  , LiPackage(..)
  , getDependencies
  , getPackage
  , orderPackagesByLicense
  , version
  )
  where

-- base
import qualified Control.Exception as Exception
import Data.Monoid ((<>))
import Data.Version (Version)
import System.IO

-- bytestring
import qualified Data.ByteString.Lazy as ByteString

-- Cabal
import Distribution.License
import Distribution.Package
import Distribution.PackageDescription
import Distribution.PackageDescription.Parse
import Distribution.Simple.Utils
import Distribution.Text
import Distribution.Verbosity

-- containers
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

-- directory
import System.Directory

-- http-conduit
--import Network.HTTP.Client.Conduit
import Network.HTTP.Simple

-- licensor
import qualified Paths_licensor

-- process
import System.Process


-- |
--
--

newtype LiLicense = LiLicense { getLicense :: License }
  deriving (Eq, Read, Show, Text)


-- |
--
--

instance Ord LiLicense where
  compare =
    comparing display


-- |
--
--

data LiPackage =
  LiPackage
    { liPackageId :: PackageIdentifier
    , liPackageDependencies :: Set LiPackage
    , liPackageLicense :: License
    }


-- |
--
--

getPackage :: IO (Maybe PackageDescription)
getPackage = do
  currentDirectory <- getCurrentDirectory
  fmap getPackageDescription <$> findPackageDesc currentDirectory
    >>= either (const (return Nothing)) (fmap Just)


-- |
--
--

getPackageDescription :: FilePath -> IO PackageDescription
getPackageDescription =
  fmap packageDescription . readPackageDescription silent


-- |
--
--

getDependencies :: IO (Maybe (Set PackageIdentifier))
getDependencies =
  fmap Set.fromList . sequence . fmap simpleParse . lines
    <$> readProcess "stack" ["list-dependencies", "--separator", "-"] ""


-- |
--
--

getPackageLicense :: PackageIdentifier -> IO (Maybe LiLicense)
getPackageLicense p@PackageIdentifier{..} = do
  putStr $ display p ++ "..."
  let
    url =
      "GET https://hackage.haskell.org/package/"
        <> display p
        <> "/"
        <> unPackageName pkgName
        <> ".cabal"

  req <- parseRequest url
  eitherPd <- Exception.try $ fmap getResponseBody (httpLBS req)

  case eitherPd of
    Left (_ :: HttpException) ->
      return Nothing

    Right pd -> do

      (file, handle) <- openTempFile "/tmp" "licensor"
      hClose handle
      ByteString.writeFile file pd
      PackageDescription{license} <- getPackageDescription file
      hClose handle
      removeFile file

      putStrLn $ display license

      return $ Just (LiLicense license)


-- |
--
--

orderPackagesByLicense
  :: PackageIdentifier
  -> Set PackageIdentifier
  -> IO (Map LiLicense (Set PackageIdentifier), Set PackageIdentifier)
orderPackagesByLicense p =
  let
    insertPackage package orderedPackages' = do
      maybeLicense <- getPackageLicense package

      (orderedPackages, failed) <- orderedPackages'
      return $
        if p == package
          then
            (orderedPackages, failed)
          else
            case maybeLicense of
              Nothing ->
                ( orderedPackages, Set.insert package failed
                )

              Just license ->
                ( Map.insertWith
                    Set.union
                    license
                    (Set.singleton package)
                    orderedPackages
                , failed
                )
  in
    foldr insertPackage (pure (mempty, mempty))


-- |
--
--

version :: Version
version =
  Paths_licensor.version
