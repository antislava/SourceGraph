{-
Copyright (C) 2009 Ivan Lazar Miljenovic <Ivan.Miljenovic@gmail.com>

This file is part of SourceGraph.

SourceGraph is free software; you can redistribute it and/or modify
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
   Module      : Analyse
   Description : Analyse Haskell software
   Copyright   : (c) Ivan Lazar Miljenovic 2009
   License     : GPL-3 or later.
   Maintainer  : Ivan.Miljenovic@gmail.com

   Analyse Haskell software
 -}
module Analyse(analyse, sgLegend) where

import Analyse.Module
import Analyse.Imports
import Analyse.Everything
import Analyse.Utils
import Parsing.Types

import Data.Graph.Analysis hiding (Bold)
import Data.GraphViz.Types
import Data.GraphViz.Attributes

import System.Random(RandomGen)

-- | Analyse an entire Haskell project.  Takes in a random seed,
--   the list of exported modules and the parsed Haskell code in
--   'HaskellModules' form.
analyse            :: (RandomGen g) => g -> [ModName] -> ParsedModules
                   -> [DocElement]
analyse g exps hms = [ analyseEverything g exps hms
                     , analyseImports exps hms
                     , analyseModules hms
                     ]

sgLegend :: [(DocGraph, DocInline)]
sgLegend = [ esCall
           , mods
           , esLoc
           , esData
           , esClass
           , esExp
           ]

esCall, mods, esLoc, esData, esClass, esExp :: (DocGraph, DocInline)

esCall = (dg', Text "Two normal functions with a function call.")
    where
      dg' = ("legend_call", Text "Function Call", dg)
      dg = mkLegendGraph ns es
      nAs = [Shape BoxShape, FillColor innerNode]
      ns = [ (1, Label (StrLabel "f") : nAs)
           , (2, Label (StrLabel "g") : nAs)
           ]
      eAs = [Color [ColorName "black"]]
      es = [(1,2,eAs)]

mods = (dg', Text "Two normal modules with a module import.")
    where
      dg' = ("legend_mods", Text "Module Import", dg)
      dg = mkLegendGraph ns es
      nAs = [Shape Tab, FillColor innerNode]
      ns = [ (1, Label (StrLabel "Foo") : nAs)
           , (2, Label (StrLabel "Bar") : nAs)
           ]
      es = [(1,2,[])]

esLoc = (dg', Text "Entities from different modules.")
    where
      dg' = ("legend_loc", Text "From module", dg)
      dg = mkLegendGraph ns es
      nAs = [FillColor innerNode]
      ns = [ (1, Label (StrLabel "Current module")
                   : Style [SItem Bold []] : nAs)
           , (2, Label (StrLabel "Other project module")
                   : Style [SItem Solid []] : nAs)
           , (3, Label (StrLabel "Known external module")
                   : Style [SItem Dashed []] : nAs)
           , (4, Label (StrLabel "Unknown external module")
                   : Style [SItem Dotted []] : nAs)
           ]
      es = []

esData = (dg', Text "Data type declaration.")
    where
      dg' = ("legend_data", Text "Data type declaration", dg)
      dg = mkLegendGraph ns es
      nAs = [FillColor innerNode]
      ns = [ (1, Label (StrLabel "Constructor")
                   : Shape Box3D : nAs)
           , (2, Label (StrLabel "Record function")
                   : Shape Component : nAs)
           ]
      es = [(2,1,[ Color [ColorName "magenta"], ArrowTail oDot, ArrowHead vee])]

esClass = (dg', Text "Class and instance declarations.")
    where
      dg' = ("legend_class", Text "Class declaration", dg)
      dg = mkLegendGraph ns es
      nAs = [FillColor innerNode]
      ns = [ (1, Label (StrLabel "Class function")
                   : Shape DoubleOctagon : nAs)
           , (2, Label (StrLabel "Default instance")
                   : Shape Octagon : nAs)
           , (3, Label (StrLabel "Instance for data type")
                   : Shape Octagon : nAs)
           ]
      eAs = [Dir NoDir]
      es = [ (2,1, Color [ColorName "navy"] : eAs)
           , (3,1, Color [ColorName "turquoise"] : eAs)
           ]

esExp = (dg', Text "Entity location classification.")
    where
      dg' = ("legend_loc2", Text "Entity Location", dg)
      dg = mkLegendGraph ns es
      ns = [ (1, [ Label (StrLabel "Un-exported root entity")
                 , FillColor unExportedRoot])
           , (2, [ Label (StrLabel "Exported root entity")
                 , FillColor exportedRoot])
           , (3, [ Label (StrLabel "Exported non-root entity")
                 , FillColor exportedInner])
           , (4, [ Label (StrLabel "Leaf entity")
                 , FillColor leafNode])
           , (5, [ Label (StrLabel "Normal entity")
                 , FillColor innerNode])
           ]
      es = []

mkLegendGraph       :: [(Int,Attributes)] -> [(Int,Int,Attributes)]
                       -> DotGraph Node
mkLegendGraph ns es = DotGraph { strictGraph   = False
                               , directedGraph = True
                               , graphID       = Nothing
                               , graphStatements
                                   = DotStmts { attrStmts = [nodeAttrs]
                                              , subGraphs = []
                                              , nodeStmts = map mkN ns
                                              , edgeStmts = map mkE es
                                              }
                               }
    where
      mkN (n,as)   = DotNode n as
      mkE (f,t,as) = DotEdge f t True as
