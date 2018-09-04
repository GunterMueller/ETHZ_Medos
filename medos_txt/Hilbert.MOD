MODULE Hilbert;   (*NW 29.12.81*)
  FROM Terminal IMPORT Read;
  FROM LineDrawing IMPORT width, height, Px, Py, clear, line;

  CONST SquareSize = 512; 
 
  VAR i,x0,y0,u: CARDINAL; ch: CHAR;

  PROCEDURE A(i: CARDINAL);
  BEGIN 
    IF i > 0 THEN
      D(i-1); line(4,u); A(i-1); line(6,u);
      A(i-1); line(0,u); B(i-1)
    END
  END A;

  PROCEDURE B(i: CARDINAL);
  BEGIN 
    IF i > 0 THEN
      C(i-1); line(2,u); B(i-1); line(0,u);
      B(i-1); line(6,u); A(i-1)
    END
  END B;

  PROCEDURE C(i: CARDINAL);
  BEGIN 
    IF i > 0 THEN
      B(i-1); line(0,u); C(i-1); line(2,u);
      C(i-1); line(4,u); D(i-1)
    END
  END C;

  PROCEDURE D(i: CARDINAL);
  BEGIN 
    IF i > 0 THEN
      A(i-1); line(6,u); D(i-1); line(4,u);
      D(i-1); line(2,u); C(i-1)
    END
  END D;

BEGIN clear;
  x0 := width DIV 2; y0 := height DIV 2;
  u := SquareSize; i := 0; 
  REPEAT i := i+1; u := u DIV 2;
    x0 := x0 + (u DIV 2); y0 := y0 + (u DIV 2);
    Px := x0; Py := y0; A(i); Read(ch)
  UNTIL (ch = 33C) OR (i = 6);
  clear
END Hilbert.
