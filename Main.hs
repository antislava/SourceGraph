{-
Copyright (C) 2009 Ivan Lazar Miljenovic <Ivan.Miljenovic@gmail.com>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- |
   Module      : Main
   Description : Analyse source code as a graph.
   Copyright   : (c) Ivan Lazar Miljenovic 2009
   License     : GPL-3 or later.
   Maintainer  : Ivan.Miljenovic@gmail.com

   The executable file for the /SourceGraph/ programme.

   This was written as part of my mathematics honours thesis,
   /Graph-Theoretic Analysis of the Relationships in Discrete Data/.
 -}
module Main where

import Parsing
import Parsing.Types(nameOfModule)
import Analyse

import Data.Graph.Analysis
import Data.Graph.Analysis.Reporting.Pandoc

import Distribution.Package
import Distribution.PackageDescription hiding (author)
import Distribution.PackageDescription.Parse
import Distribution.ModuleName(toFilePath)
import Distribution.Verbosity

import Data.Char(toLower)
import Data.List(nub)
import Data.Maybe(isJust, fromJust, catMaybes)
import qualified Data.Map as M
import System.IO(hPutStrLn, stderr)
import System.Directory( getCurrentDirectory
                       , doesDirectoryExist
                       , doesFileExist
                       , getDirectoryContents)
import System.FilePath( dropFileName
                      , dropExtension
                      , takeExtension
                      , isPathSeparator
                      , (</>)
                      , (<.>))
import System.Random(newStdGen)
import System.Environment(getArgs)
import Control.Monad(liftM)
import Control.Exception.Extensible(SomeException(..), try)

import Data.Version(showVersion)
import qualified Paths_SourceGraph as Paths(version)

-- -----------------------------------------------------------------------------

main :: IO ()
main = do input <- getArgs
          mInfo <- getPkgInfo input
          case mInfo of
            Nothing -> putErrLn "No parseable package information found."
            Just (f,(nm,exps))
                -> do let dir = dropFileName f
                      dir' <- if null dir
                                then getCurrentDirectory
                                else return dir
                      hms <- parseFilesFrom dir'
                      analyseCode dir nm exps hms

programmeName :: String
programmeName = "SourceGraph"

programmeVersion :: String
programmeVersion = showVersion Paths.version

putErrLn :: String -> IO ()
putErrLn = hPutStrLn stderr

-- -----------------------------------------------------------------------------

getPkgInfo :: [String] -> IO (Maybe (FilePath, (String, [ModName])))
getPkgInfo [] = do putErrLn "Please provide either a Cabal file \
                            \or a Haskell source file as an argument."
                   return Nothing
getPkgInfo [f]
    | isCabalFile f   = withF parseCabal
    | isHaskellFile f = withF parseMain
    where
      withF func = do ex <- doesFileExist f
                      if ex
                         then addF $ func f
                         else do putErrLn "The provided file does not exist."
                                 return Nothing
      addF = fmap (fmap ((,) f))
getPkgInfo _        = do putErrLn "Please provide a single Cabal \
                                  \or Haskell source file as an argument."
                         return Nothing

parseCabal    :: FilePath -> IO (Maybe (String, [ModName]))
parseCabal fp = do gpd <- try $ readPackageDescription silent fp
                   case gpd of
                     (Right gpd')           -> return (Just $ parse gpd')
                     (Left SomeException{}) -> return Nothing
    where
      parse pd = (nm, exps')
          where
            cbl = packageDescription pd
            nm = pName . pkgName $ package cbl
            pName (PackageName nm') = nm'
            cexes :: [Executable]
            cexes = map (condTreeData .snd) $ condExecutables pd
            exes = executables cbl
            clib = condLibrary pd
            lib = library cbl
            moduleNames = map toFilePath
            exps | not $ null cexes = nub $ map (dropExtension . modulePath) cexes
                 | not $ null exes  = nub . map dropExtension . moduleNames $ exeModules cbl
                 | isJust clib      = moduleNames . exposedModules . condTreeData
                                      $ fromJust clib
                 | isJust lib       = moduleNames . exposedModules $ fromJust lib
                 | otherwise        = error "No exposed modules"
            exps' = map fpToModule exps

isCabalFile :: FilePath -> Bool
isCabalFile = hasExt "cabal"

parseMain    :: FilePath -> IO (Maybe (String, [ModName]))
parseMain fp = do pms <- parseHaskellFiles [fp]
                  let mn = fst $ M.findMin pms
                  return $ Just (nameOfModule mn, [mn])

-- | Determine if this is the path of a Haskell file.
isHaskellFile    :: FilePath -> Bool
isHaskellFile fp = any (flip hasExt fp) haskellExtensions

hasExt     :: String -> FilePath -> Bool
hasExt ext = (==) ext . drop 1 . takeExtension

fpToModule :: FilePath -> ModName
fpToModule = createModule . map pSep
    where
      pSep c
          | isPathSeparator c = moduleSep
          | otherwise         = c

-- -----------------------------------------------------------------------------

-- | Recursively parse all files from this directory
parseFilesFrom    :: FilePath -> IO ParsedModules
parseFilesFrom fp = parseHaskellFiles =<< getHaskellFilesFrom fp

parseHaskellFiles :: [FilePath] -> IO ParsedModules
parseHaskellFiles = liftM parseHaskell . readFiles

-- -----------------------------------------------------------------------------

-- Reading in the files.

-- | Recursively find all Haskell source files from the current directory.
getHaskellFilesFrom :: FilePath -> IO [FilePath]
getHaskellFilesFrom fp
    = do isDir <- doesDirectoryExist fp -- Ensure it's a directory.
         if isDir
            then do r <- try getFilesIn -- Ensure we can read the directory.
                    case r of
                      (Right fs)             -> return fs
                      (Left SomeException{}) -> return []
            else return []
    where
      -- Filter out "." and ".." to stop infinite recursion.
      nonTrivialContents :: IO [FilePath]
      nonTrivialContents = do contents <- getDirectoryContents fp
                              let contents' = filter (not . isTrivial) contents
                              return $ map (fp </>) contents'
      getFilesIn :: IO [FilePath]
      getFilesIn = do contents <- nonTrivialContents
                      (dirs,files) <- partitionM doesDirectoryExist contents
                      let hFiles = filter isHaskellFile files
                      recursiveFiles <- concatMapM getHaskellFilesFrom dirs
                      return (hFiles ++ recursiveFiles)

haskellExtensions :: [FilePath]
haskellExtensions = ["hs","lhs"]

-- | Read in all the files that it can.
readFiles :: [FilePath] -> IO [FileContents]
readFiles = liftM catMaybes . mapM readFileContents

-- | Try to read the given file.
readFileContents   :: FilePath -> IO (Maybe FileContents)
readFileContents f = do cnts <- try $ readFile f
                        case cnts of
                          (Right str)            -> return $ Just (f,str)
                          (Left SomeException{}) -> return Nothing

-- | A version of 'concatMap' for use in monads.
concatMapM   :: (Monad m) => (a -> m [b]) -> [a] -> m [b]
concatMapM f = liftM concat . mapM f

-- | A version of 'partition' for use in monads.
partitionM      :: (Monad m) => (a -> m Bool) -> [a] -> m ([a], [a])
partitionM _ [] = return ([],[])
partitionM p (x:xs) = do ~(ts,fs) <- partitionM p xs
                         matches <- p x
                         if matches
                            then return (x:ts,fs)
                            else return (ts,x:fs)

-- | Trivial paths are the current directory, the parent directory and
--   such directories
isTrivial               :: FilePath -> Bool
isTrivial "."           = True
isTrivial ".."          = True
isTrivial "_darcs"      = True
isTrivial "dist"        = True
isTrivial "HLInt.hs"    = True
isTrivial f | isSetup f = True
isTrivial _             = False

lowerCase :: String -> String
lowerCase = map toLower

isSetup   :: String -> Bool
isSetup f = lowerCase f `elem` map ("setup" <.>) haskellExtensions

-- -----------------------------------------------------------------------------

analyseCode                :: FilePath -> String -> [ModName]
                           -> ParsedModules -> IO ()
analyseCode fp nm exps hms = do d <- today
                                g <- newStdGen
                                let dc = doc d g
                                docOut <- createDocument pandocHtml dc
                                case docOut of
                                  Just path -> success path
                                  Nothing   -> failure
    where
      graphdir = "graphs"
      doc d g = Doc { rootDirectory  = rt
                    , fileFront      = nm
                    , graphDirectory = graphdir
                    , title          = t
                    , author         = a
                    , date           = d
                    , content        = msg : c g
                    }
      rt = fp </> programmeName
      sv s v = s ++ " (version " ++ v ++ ")"
      t = Grouping [Text "Analysis of", Text nm]
      a = unwords [ "Analysed by", sv programmeName programmeVersion
                  , "using", sv "Graphalyze" version]
      c g = analyse g exps hms
      success fp' = putStrLn $ unwords ["Report generated at:",fp']
      failure = putErrLn "Unable to generate report"
      msg = Paragraph [ Text "Please note that the source-code analysis in this\
                             \ document is not necessarily perfect: "
                      , Emphasis $ Text programmeName
                      , Text " is "
                      , Bold $ Text "not"
                      , Text " a refactoring tool, and does not take into \
                             \account Class declarations and record functions."
                      ]
