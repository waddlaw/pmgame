{-# LANGUAGE OverloadedStrings #-}

module View.Core
  ( attributes,
    putInDialogBox,
    renderVerticalSpace,
  )
where

import Brick.AttrMap (AttrMap, attrMap)
import Brick.Types (Widget (..))
import Brick.Util (bg, on)
import Brick.Widgets.Border
  ( borderAttr,
    borderWithLabel,
  )
import Brick.Widgets.Border.Style (unicodeRounded)
import Brick.Widgets.Center (center)
import Brick.Widgets.Core
  ( fill,
    hLimit,
    txt,
    vBox,
    vLimit,
    withAttr,
    withBorderStyle,
  )
import Brick.Widgets.Edit (editFocusedAttr)
import qualified Data.Text as Txt
import qualified Graphics.Vty as V
import Model.Types (Name (..))
import Model.Utilities (maxDialogWidth)

---------------------------------------------------------------------
---------------------------------------------------------------------
-- Core attributes and utilities for drawing widgets

-- =============================================================== --
-- Utilities

putInDialogBox :: Txt.Text -> Widget Name -> [Widget Name]
-- ^ Render a widget in a bordered box with the specified title.
--  Used for displaying information between game plays.
putInDialogBox title widget =
  let header = withAttr "info" . txt $ title
      formatted =
        [ renderVerticalSpace 1,
          widget,
          renderVerticalSpace 1
        ]
   in [ withAttr "background"
          . center
          . withBorderStyle unicodeRounded
          . borderWithLabel header
          . hLimit maxDialogWidth
          . vBox
          $ formatted
      ]

renderVerticalSpace :: Int -> Widget Name
-- ^ Spacer for separating vertically stacked widgets.
renderVerticalSpace n = vLimit n . withAttr "background" . fill $ ' '

-- =============================================================== --
-- Attributes

bold :: V.Attr -> V.Attr
bold = flip V.withStyle V.bold

attributes :: AttrMap
attributes =
  attrMap
    V.defAttr
    [ ("player", on V.black V.brightYellow),
      ("blueMaze", on V.blue V.black),
      ("pinkMaze", on V.magenta V.black),
      ("cyanMaze", on V.cyan V.black),
      ("redMaze", on V.red V.black),
      ("whiteMaze", on V.white V.black),
      ("deathMaze", on V.brightBlack V.black),
      ("oneway", on V.red V.black),
      ("pellet", on V.white V.black),
      ("pwrPellet", on V.cyan V.black),
      ("flashPwrPellet", on V.brightCyan V.black),
      ("score", on V.white V.black),
      ("info", on V.white V.black),
      ("blinky", on V.black V.red),
      ("pinky", on V.black V.brightMagenta),
      ("inky", on V.black V.brightCyan),
      ("clyde", on V.black V.yellow),
      ("blueGhost", on V.white V.blue),
      ("whiteGhost", on V.black V.white),
      ("ghostEyes", on V.cyan V.black),
      ("cherry", bold $ on V.red V.black),
      ("strawberry", bold $ on V.brightMagenta V.black),
      ("orange", bold $ on V.yellow V.black),
      ("apple", bold $ on V.brightRed V.black),
      ("melon", bold $ on V.green V.black),
      ("galaxian", bold $ on V.cyan V.black),
      ("bell", bold $ on V.yellow V.black),
      ("key", bold $ on V.brightYellow V.black),
      ("background", bg V.black),
      ("highScore", on V.yellow V.black),
      ("pelletText", bold $ on V.cyan V.black),
      ("ghostText", bold $ on V.brightBlue V.black),
      ("controls", on V.brightBlack V.black),
      ("focusControls", on V.cyan V.black),
      (borderAttr, on V.blue V.black),
      (editFocusedAttr, on V.white V.brightBlack)
    ]
