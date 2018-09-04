IMPLEMENTATION MODULE graphPattern;

  (* Copyright: DISER AG *)
  (* Author: Leo Geissmann, DISER Zurich *)
  (* Version: 1 *)
  (* Date: 83.09.02 *)
  (* Purpose: Painting of predefined patterns on bitmap *)

  IMPORT
    Screen;

  FROM WindowHandler IMPORT
    Window, BlockDescriptor, Mode, Replicate;

  CONST
    maxpat = 12; (* maximal number of different patterns *)

  TYPE
    PatternDescriptor =
      RECORD
        height : CARDINAL; (* assigned pattern height *)
        pattern : ARRAY [1 .. 10] OF BITSET; (* pattern *)
      END;

   VAR
     pat : ARRAY [1 .. maxpat] OF PatternDescriptor; (* pattern source *)

  PROCEDURE PaintPattern(
              patnum : CARDINAL; (* number of pattern to be painted *)
              patwindow : Window; (* window for painting *)
              paintblock : BlockDescriptor; (* painted region *)
              paintmode : Mode); (* mode of painting *)
  BEGIN (* PaintPattern *)
    Replicate(patwindow, paintblock, paintmode, pat[patnum]);
  END PaintPattern;

BEGIN (* graphPattern *)
  (* initialization of patterns *)
  pat[1].height := 4;
  pat[1].pattern[1] := {1..3, 5..7, 9..11, 13..15};
  pat[1].pattern[2] := {0, 2..4, 6..8, 10..12, 14..15};
  pat[1].pattern[3] := {0..1, 3..5, 7..9, 11..13, 15};
  pat[1].pattern[4] := {0..2, 4..6, 8..10, 12..14};
  pat[2].height := 4;
  pat[2].pattern[1] := {1, 3..7, 9, 11..15};
  pat[2].pattern[2] := {0..15};
  pat[2].pattern[3] := {0..3, 5, 7..11, 13, 15};
  pat[2].pattern[4] := {0..15};
  pat[3].height := 4;
  pat[3].pattern[1] := {0..2, 4..6, 8..10, 12..14};
  pat[3].pattern[2] := {0..1, 3..5, 7..9, 11..13, 15};
  pat[3].pattern[3] := {0, 2..4, 6..8, 10..12, 14..15};
  pat[3].pattern[4] := {1..3, 5..7, 9..11, 13..15};
  pat[4].height := 4;
  pat[4].pattern[1] := {1..3, 5..7, 9..11, 13..15};
  pat[4].pattern[2] := {1..3, 5..7, 9..11, 13..15};
  pat[4].pattern[3] := {0..1, 3..5, 7..9, 11..13, 15};
  pat[4].pattern[4] := {0..1, 3..5, 7..9, 11..13, 15};
  pat[5].height := 4;
  pat[5].pattern[1] := {0..3, 5, 7..11, 13, 15};
  pat[5].pattern[2] := {0, 2, 4..8, 10, 12..15};
  pat[5].pattern[3] := {1, 3..7, 9, 11..15};
  pat[5].pattern[4] := {0..4, 6, 8..12, 14};
  pat[6].height := 4;
  pat[6].pattern[1] := {1, 3..7, 9, 11..15};
  pat[6].pattern[2] := {0, 2, 4..8, 10, 12..15};
  pat[6].pattern[3] := {0..3, 5, 7..11, 13, 15};
  pat[6].pattern[4] := {0..4, 6, 8..12, 14};
  pat[7].height := 4;
  pat[7].pattern[1] := {};
  pat[7].pattern[2] := {0..15};
  pat[7].pattern[3] := {0..15};
  pat[7].pattern[4] := {};
  pat[8].height := 1;
  pat[8].pattern[1] := {0, 1, 4, 5, 8, 9, 12, 13};
  pat[9].height := 4;
  pat[9].pattern[1] := {0..1, 4..5, 8..9, 12..13};
  pat[9].pattern[2] := {1..2, 5..6, 9..10, 13..14};
  pat[9].pattern[3] := {0, 3..4, 7..8, 11..12, 15};
  pat[9].pattern[4] := {2..3, 6..7, 10..11, 14..15};
  pat[10].height := 4;
  pat[10].pattern[1] := {0..2, 4..6, 8..10, 12..14};
  pat[10].pattern[2] := {0, 2..4, 6..8, 10..12, 14..15};
  pat[10].pattern[3] := {1..3, 5..7, 9..11, 13..15};
  pat[10].pattern[4] := {0..1, 3..5, 7..9, 11..13, 15};
  pat[11].height := 0;
  pat[12].height := 1;
  pat[12].pattern[1] := {0..15};
END graphPattern.
