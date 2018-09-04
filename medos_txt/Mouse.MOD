IMPLEMENTATION MODULE Mouse;   (*NW 15.6.82*)
  FROM SYSTEM IMPORT ADDRESS, ADR, WORD;
  FROM DisplayDriver IMPORT BMDescriptor, BMD, DFF,
    ScreenWidth, ScreenHeight, LineHeight, CharWidth, BuildBMD;
  FROM Frames IMPORT Allocate, nil;

  CONST maxM = 7;  (*max no. of chars in menu line*)
        maxN = 7;  (*max no. of lines in menu*)
        MenuWidth = 64; MenuHeight = 116;
        CursorWidth = 16; CursorHeight = 16;

  TYPE DispMode = (replace, paint, invert, erase);
    Block = RECORD x,y,w,h: INTEGER END ;
    Pattern = RECORD L: CARDINAL;
                b: ARRAY [0..CursorHeight-1] OF BITSET;
              END ;

  VAR width, height: INTEGER;
      FontWidth, FontHeight: INTEGER;
      font: CARDINAL;
      cursor: Block;
      curpat, black: Pattern;
      SaveBMA: CARDINAL;  (*frame pointer*)
      SaveBMD: BMDescriptor;

  PROCEDURE GET(chan: CARDINAL; VAR val: WORD);
    CODE 240B
  END GET;

  PROCEDURE REPL(m: DispMode; VAR bmd: BMDescriptor;
                 VAR src: Pattern; VAR dest: Block);
    CODE 343B
  END REPL;

  PROCEDURE BBLT(m: DispMode; VAR DB: BMDescriptor;
                 VAR src, dest: Block; VAR SB: BMDescriptor);
    CODE 344B
  END BBLT;

  PROCEDURE DCH(VAR bmd: BMDescriptor; font: CARDINAL;
                VAR dest: Block; ch: CHAR);
    CODE 345B
  END DCH;

  PROCEDURE FlipCursor;
  BEGIN curOn := NOT curOn;
    REPL(invert, BMD, curpat, cursor)
  END FlipCursor;

  PROCEDURE TrackMouse;
  BEGIN GET(6,Mx); GET(7,My); GET(3,keys);
    IF Mx > width-CursorWidth THEN Mx := width-CursorWidth END ;
    IF My > height-CursorHeight THEN My := height-CursorHeight END ;
    IF (Mx # cursor.x) OR (My # cursor.y) THEN
      IF curOn THEN FlipCursor END ;
      cursor.x := Mx; cursor.y := My; FlipCursor
    END
  END TrackMouse;

  PROCEDURE ShowMenu(text: ARRAY OF CHAR; VAR sel: INTEGER);
    VAR y0, i, j, m, n: INTEGER;
      sel1, leng: INTEGER;
      blk, menu, SaveBlk: Block;

    PROCEDURE line(dx,dy,w,h: INTEGER);
    BEGIN blk.x := menu.x + dx; blk.y := menu.y + dy;
      blk.w := w; blk.h := h;
      REPL(replace, BMD, black, blk)
    END line;

    PROCEDURE invertField(k: INTEGER);
    BEGIN
      IF (0 < k) & (k <= n) THEN
        blk.x := menu.x+2; blk.y := menu.y + menu.h -2 - k*FontHeight;
        blk.w := menu.w-4; blk.h := FontHeight;
        REPL(invert, BMD, black, blk)
      END
    END invertField;

  BEGIN
    IF curOn & (keys # {}) THEN
      FlipCursor;  (*erase cursor and compute menu size*)
      i := 0; j := 0; m := 0; n := 1; leng := HIGH(text);
      WHILE i <= leng DO
        IF text[i] = "|" THEN n := n+1; j := 0
        ELSE j := j+1;
          IF j > m THEN m := j END
        END ;
        i := i+1
      END ;
      IF (m > maxM) OR (n > maxN) THEN HALT END ;
      WITH menu DO
        w := m * FontWidth +4; h := n * FontHeight +4;
        IF Mx > width-w THEN x := width-w ELSE x := Mx END ;
        IF My > height-h THEN y := height-h ELSE y := My END
      END ;
      WITH SaveBlk DO
        x := 0; y := 0; w := menu.w; h := menu.h
      END ;
      BBLT(replace, SaveBMD, menu, SaveBlk, BMD);
      REPL(erase, BMD, black, menu);
      line(0, 0, menu.w -2, 2); line(menu.w -2, 0, 2, menu.h -2);
      line(2, menu.h -2, menu.w -2, 2); line(0, 2, 2, menu.h -2);
      blk.x := menu.x +2; blk.y := menu.y + menu.h -2 -FontHeight;
      i := 0; j := 0; 
      WHILE i <= leng DO
        IF text[i] = "|" THEN
          blk.x := menu.x +2; blk.y := blk.y - FontHeight
        ELSE
          DCH(BMD, font, blk, text[i])
        END ;
        i := i+1
      END ;
      IF (sel <= 0) OR (sel > n) THEN sel := 1 END ;
      invertField(sel); y0 := My;
      REPEAT GET(3,keys); GET(7,My);
        sel1 := (y0-My) DIV FontHeight + sel;
        IF sel1 # sel THEN
          invertField(sel); invertField(sel1);
          y0 := My; sel := sel1
        END
      UNTIL keys = {};
      IF (sel < 0) OR (sel > n) THEN sel := 0 END ;
      BBLT(replace, BMD, SaveBlk, menu, SaveBMD);
      FlipCursor
    END
  END ShowMenu;

BEGIN curOn := FALSE; mode := 0; font := DFF();
  width := ScreenWidth(); height := ScreenHeight();
  FontHeight := LineHeight(); FontWidth := CharWidth();
  Allocate(SaveBMA, (MenuWidth DIV 16) * MenuHeight);
  IF SaveBMA = nil THEN HALT END ;
  BuildBMD(SaveBMA, MenuWidth, MenuHeight, SaveBMD);
  black.L := 1; black.b[0] := {0..15};
  WITH curpat DO L := 16;
    b[ 0] := {};         b[ 1] := {13};        b[ 2] := {12..14};
    b[ 3] := {11..13};   b[ 4] := {10..12};    b[ 5] := {9..11};
    b[ 6] := {8..10};    b[ 7] := {7.. 9};     b[ 8] := {0,6..8};
    b[ 9] := {0,1,5..7}; b[10] := {0..2,4..6}; b[11] := {0..5};
    b[12] := {0..4};     b[13] := {0..5};      b[14] := {0..6};
    b[15] := {0..7}
  END ;
  WITH cursor DO
    x := 0; y := 0; w := 16; h := 16
  END ;
END Mouse.
