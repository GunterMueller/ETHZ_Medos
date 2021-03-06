IMPLEMENTATION MODULE graphLegend;

  (* Copyright: DISER AG *)
  (* Author: Leo Geissmann, DISER Zurich *)
  (* Version: 1 *)
  (* Date: 83.09.02 *)
  (* Purpose: Painting of a legend in a window *)

  IMPORT
    WindowHandler,
    graphPattern;

  FROM WindowHandler IMPORT
    Window, BlockDescriptor, Mode, Replicate, WriteChar, SetDotPos;

  FROM graphPattern IMPORT
    PaintPattern;

  TYPE
    FullPattern =
      RECORD
        height : CARDINAL; (* pattern height *)
        pattern : BITSET;  (* pattern *)
      END;

  VAR
    legendwindow : Window;         (* window of legend *)
    legendblock : BlockDescriptor; (* legend area in legendwindow *)
    legendcount : CARDINAL;        (* counter of displayed legends *)
    fullpat : FullPattern;         (* pattern *)

  PROCEDURE InitLegend(
              wind : Window;          (* legend window *)
              x, y, w, h : CARDINAL); (* legend area *)
  BEGIN (* InitLegend *)
    legendwindow := wind;
    legendblock.x := x;
    legendblock.y := y;
    legendblock.w := w;
    legendblock.h := h;
    legendcount := 0;
    (* clear legend area *)
    Replicate(legendwindow, legendblock, erase, fullpat);
  END InitLegend;

  PROCEDURE NextLegend(
              legend : ARRAY OF CHAR; (* legend text *)
              patnum : CARDINAL);     (* pattern number *)
    CONST
      legenddistance = 40;            (* distance of legends *)
      patternwidth = 35;              (* width of displayed pattern *)
      patternheight = 25;             (* height of displayed pattern *)
      textindent = patternwidth + 15; (* indentation of legend text *)

    VAR
      legendpos : CARDINAL;           (* y position of legend *)
      patternblock : BlockDescriptor; (* block for pattern display *)
      ix : CARDINAL;                  (* index *)

  BEGIN (* NextLegend *)
    legendcount := legendcount + 1;
    legendpos := legendblock.h -
                 legendcount * legenddistance +
                 legenddistance - patternheight;
    WITH legendwindow^ DO
      (* paint background *)
      patternblock.x := legendblock.x;
      patternblock.y := legendblock.y + legendpos;
      patternblock.w := patternwidth;
      patternblock.h := patternheight;
      Replicate(legendwindow, patternblock, replace, fullpat);
      (* paint pattern *)
      patternblock.x := patternblock.x + 1;
      patternblock.y := patternblock.y + 1;
      patternblock.w := patternwidth - 2;
      patternblock.h := patternheight - 2;
      PaintPattern(patnum, legendwindow, patternblock, invert);
    END;
    (* display legend text *)
    SetDotPos(legendwindow,
              legendblock.x + textindent,
              legendblock.y + legendpos + 5);
    ix := 0;
    WHILE (ix <= HIGH(legend)) AND (legend[ix] <> 0C) DO
      WriteChar(legendwindow, legend[ix]);
      ix := ix + 1;
    END;
  END NextLegend;

BEGIN (* graphLegend *)
  fullpat.height := 1;
  fullpat.pattern := {0 .. 15};
  legendcount := 0;
END graphLegend.
