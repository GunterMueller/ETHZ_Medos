MODULE Rectangles;   (*NW 26.8.81*)
  FROM Terminal IMPORT Read, BusyRead;
  FROM LineDrawing IMPORT
    width, height, PaintMode, mode, area, clear;

  VAR x0,y0,dx0,dy0, x1,y1,dx1,dy1, X,Y: INTEGER;
    ch:  CHAR;

BEGIN clear; mode := invert;
  x0 := 0; y0 := 0; dx0 := 12; dy0 := 28;
  x1 := 0; y1 := 0; dx1 := 20; dy1 := 44;
  REPEAT 
   REPEAT
    x0 := x0 + dx0;
    IF x0 < 0 THEN x0 := -x0; dx0 := -dx0
      ELSIF x0 > width THEN x0 := 2*width - x0; dx0 := -dx0
    END ;
    y0 := y0 + dy0;
    IF y0 < 0 THEN y0 := -y0; dy0 := -dy0
      ELSIF y0 > height THEN y0 := 2*height - y0; dy0 := -dy0
    END ;
    x1 := x1 + dx1;
    IF x1 < 0 THEN x1 := -x1; dx1 := -dx1
      ELSIF x1 > width THEN x1 := 2*width - x1; dx1 := -dx1
    END ;
    y1 := y1 + dy1;
    IF y1 < 0 THEN y1 := -y1; dy1 := -dy1
      ELSIF y1 > height THEN y1 := 2*height - y1; dy1 := -dy1
    END ;
    IF x0 < x1 THEN X := x0 ELSE X := x1 END ;
    IF y0 < y1 THEN Y := y0 ELSE Y := y1 END ;
    area(3, X, Y, ABS(x0-x1), ABS(y0-y1));
    BusyRead(ch)
   UNTIL ch # 0C;
   Read(ch);
  UNTIL ch = 33C;
  clear
END Rectangles.
