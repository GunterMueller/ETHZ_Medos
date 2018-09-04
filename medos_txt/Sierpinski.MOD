MODULE Sierpinski;   (*NW 29.12.81*)
  FROM Terminal IMPORT Read;
  FROM LineDrawing IMPORT width, height, Px, Py, clear, line;

  CONST SquareSize = 512;

  VAR i,h,x0,y0: CARDINAL; ch: CHAR;

  PROCEDURE A(k: CARDINAL);
  BEGIN
    IF k > 0 THEN
      A(k-1); line(7, h); B(k-1); line(0, 2*h);
      D(k-1); line(1, h); A(k-1)
    END
  END A;

  PROCEDURE B(k: CARDINAL);
  BEGIN
    IF k > 0 THEN
      B(k-1); line(5, h); C(k-1); line(6, 2*h);
      A(k-1); line(7, h); B(k-1)
    END
  END B;

  PROCEDURE C(k: CARDINAL);
  BEGIN
    IF k > 0 THEN
      C(k-1); line(3, h); D(k-1); line(4, 2*h);
      B(k-1); line(5, h); C(k-1)
    END
  END C;

  PROCEDURE D(k: CARDINAL);
  BEGIN
    IF k > 0 THEN
      D(k-1); line(1, h); A(k-1); line(2, 2*h);
      C(k-1); line(3, h); D(k-1)
    END
  END D;

BEGIN clear; i := 0; h := SquareSize DIV 4;;
  x0 := CARDINAL(width) DIV 2; y0 := CARDINAL(height) DIV 2 + h;
  REPEAT i := i+1; x0 := x0-h; 
    h := h DIV 2; y0 := y0+h; Px := x0; Py := y0;
    A(i); line(7,h); B(i); line(5,h);
    C(i); line(3,h); D(i); line(1,h); Read(ch)
  UNTIL (i = 6) OR (ch = 33C);
  clear
END Sierpinski.
