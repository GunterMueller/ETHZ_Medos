IMPLEMENTATION MODULE SilInput;   (*NW 22.1.83*)
  FROM SilDisplay IMPORT
    Yorg, BMWidth, BMHeight,
    PaintCursor, PaintMenu, RestoreMenuArea, InvertMenuField;
  FROM Terminal IMPORT BusyRead;

  CONST MK = 3; MX = 6; MY = 7;
    MouseChar = 240B;

  VAR x, y, xx, yy, f0:  INTEGER;
      C: CARDINAL;
      M0, M1: INTEGER;

  PROCEDURE GET(n: CARDINAL; VAR w: INTEGER);
    CODE 240B
  END GET;
     
  PROCEDURE SHL(x: INTEGER; n: CARDINAL): INTEGER;
    CODE 276B
  END SHL;

  PROCEDURE SHR(x: INTEGER; n: CARDINAL): INTEGER;
    CODE 277B
  END SHR;

  PROCEDURE GetMouse;
  BEGIN GET(MX,x); GET(MY,y);
    IF x > BMWidth THEN x := BMWidth END ;
    IF y > BMHeight THEN y := BMHeight END ;
    x := SHL(SHR(x,Grid),Grid); y := SHL(SHR(y,Grid),Grid)
  END GetMouse;
 
  PROCEDURE TrackCursor;
  BEGIN GetMouse;
    IF (x # x1) OR (y # y1-Yorg) THEN
      PaintCursor(x1,y1-Yorg);  (*clear it*)
      x1 := x; y1 := y+Yorg; PaintCursor(x,y)
    END
  END TrackCursor;

  PROCEDURE TrackField(old, max: INTEGER);
    VAR f1: INTEGER;
  BEGIN GET(MX,x); GET(MY,y); GET(MK,M1);
    f1 := (y-yy) DIV 12 + old;
    IF f1 # f0 THEN
      IF (0 <= f0) & (f0 < max) THEN InvertMenuField(f0) END ;
      IF (0 <= f1) & (f1 < max) THEN InvertMenuField(f1) END ;
      f0 := f1; xx := x+15
    END
  END TrackField;
 
  PROCEDURE Menu;
    VAR sec: BOOLEAN;
  BEGIN PaintCursor(x,y);  (*erase it*)
    PaintMenu(x,y,8,
      " grid| width| font| put | get | mac0| mac1| exit ||");
    InvertMenuField(C); f0 := C; xx := x+15; yy := y;
    REPEAT TrackField(C, 8);
      sec := (0 <= f0) & (f0 < 3) & (x > xx)
    UNTIL (M1 = 0) OR sec;
    RestoreMenuArea; yy := y;
    IF (3 <= f0) & (f0 < 8) OR sec THEN
      C := f0; com := f0 + MouseChar + 10B
    ELSE com := MouseChar
    END ;
    IF sec THEN  (*0 <= f0 < 3*)
      IF C = 0 THEN (*grid*)
        PaintMenu(x,y,4, "   1|   2|   4|   8||");
        f0 := Grid; InvertMenuField(f0);
        REPEAT TrackField(Grid, 4) UNTIL M1 = 0
      ELSIF C = 1 THEN (*width*)
        PaintMenu(x,y,4, "   1|   2|   3|   4||");
        f0 := LineWidth-1; InvertMenuField(f0);
        REPEAT TrackField(LineWidth-1, 4) UNTIL M1 = 0
      ELSIF C = 2 THEN (*font*)
        PaintMenu(x,y,4, FontMenu);
        f0 := CurrentFont; InvertMenuField(f0);
        REPEAT TrackField(CurrentFont, 4) UNTIL M1 = 0
      END ;
      IF (0 <= f0) & (f0 < 4) THEN com1 := f0
        ELSE com := MouseChar
      END;
      RestoreMenuArea
    END
  END Menu;

  PROCEDURE ReadKey;  (*get next key*)
    VAR ch: CHAR;
  BEGIN (*no cursor on screen*)
    GetMouse; x1 := x; y1 := y+Yorg;
    PaintCursor(x,y);
    REPEAT TrackCursor; BusyRead(ch); GET(MK,M0)
    UNTIL (ch # 0C) OR (M0 # 0);
    IF M0 = 2 THEN Menu
    ELSIF M0 # 0 THEN
      x0 := x1; y0 := y1;
      REPEAT TrackCursor; GET(MK,M1);
          IF M0 < M1 THEN M0 := M1 END
      UNTIL M1 = 0;
      PaintCursor(x1, y1-Yorg); com := M0 + MouseChar
    ELSE
      PaintCursor(x1, y1-Yorg); com := CARDINAL(ch);
      IF Umlaut THEN
        IF ch = "`" THEN com := 200B
        ELSIF ch = "~" THEN com := 201B
        ELSIF ch = "|" THEN com := 202B
        ELSIF ch = "@" THEN com := 203B
        ELSIF ch = "^" THEN com := 204B
        ELSIF ch = "\" THEN com := 205B
        ELSIF ch = "$" THEN com := 206B
        END
      END
    END
  END ReadKey;

BEGIN
  Grid := 2; LineWidth := 1; CurrentFont := 0;
  Umlaut := FALSE; C := 4
END SilInput.
