MODULE Draw;    (*NW 5.1.82*)
  FROM Terminal IMPORT BusyRead;
  FROM LineDrawing IMPORT
    width, height, Px, Py, dot, line, area, clear;
  FROM Mouse IMPORT
    keys, Mx, My, FlipCursor, TrackMouse, ShowMenu;

  CONST L = 512;  (*SquareSize*)

  VAR i, color, x0, y0, x1, y1: INTEGER;
      minx, maxx, miny, maxy: INTEGER;
      ch:  CHAR;

  PROCEDURE SetScreen;
  BEGIN area(1,0,0,width,height);
    Px := minx; Py := miny; area(0,Px,Py,L,L);
    line(0,L); line(2,L); line(4,L); line(6,L)
  END SetScreen;

BEGIN
  minx := (width-L) DIV 2; miny := (height-L) DIV 2;
  maxx := minx + L; maxy := miny + L; color := 3;
  SetScreen; FlipCursor; (*switch cursor on*)
  REPEAT TrackMouse;
    IF 14 IN keys THEN
      i := color+1; ShowMenu("white|grey0|grey1|black", i);
      IF i # 0 THEN color := i-1 END
    ELSIF (15 IN keys) & (minx <= Mx) & (Mx < maxx)
         & (miny <= My) & (My < maxy) THEN
      x1 := (Mx - minx) DIV 8; y1 := (My - miny) DIV 8;
      IF (x1 # x0) OR (y1 # y0) THEN
        FlipCursor;  (*off*)
        area(color, minx + x1*8, miny + y1*8, 8, 8);
        x0 := x1; y0 := y1;
        FlipCursor  (*on*)
      END 
    END ;
    BusyRead(ch);
    IF ch = 177C THEN
      FlipCursor; SetScreen; FlipCursor
    END
  UNTIL ch = 33C;
  clear
END Draw.
