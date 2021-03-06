IMPLEMENTATION MODULE MouseCoords; (* WW restored 83/07/04 *)

FROM SYSTEM IMPORT WORD;
FROM DisplayDriver IMPORT ScreenWidth, ScreenHeight;


CONST
  MX = 6;
  MY = 7;
  MB = 3;

VAR
  absX,
  absY,
  lastX,
  lastY,
  width,
  height: CARDINAL;


PROCEDURE GET (chanel: CARDINAL; VAR value: WORD);
CODE
  240b;
END GET;

PROCEDURE SetMouse (x,y: CARDINAL);
BEGIN
  absX := 8000h - 8000h MOD width + x;
  absY := 8000h - 8000h MOD height  + y;
END SetMouse;

PROCEDURE MoveMouse (dx,dy: INTEGER);
BEGIN
  IF dx < 0 THEN DEC(absX,CARDINAL(-dx));
  ELSE INC(absX,CARDINAL(dx));
  END;
  IF dy < 0 THEN DEC(absY,CARDINAL(-dy));
  ELSE INC(absY,CARDINAL(dy));
  END;
END MoveMouse;

PROCEDURE SetMouseWindow (w,h: CARDINAL);
BEGIN
  absX := absX MOD width;
  width := w;
  absY := absY MOD height;
  height := h;
  SetMouse(absX,absY);
END SetMouseWindow;

PROCEDURE GetMouse (VAR x,y,b: CARDINAL);
VAR
  currentX,
  currentY: CARDINAL;
BEGIN
  GET(MB,b);
  GET(MX,currentX);
  INC(absX,currentX);
  DEC(absX,lastX);
  IF (lastX < 100h) AND (currentX > 300h) THEN DEC(absX,400h);
  ELSIF (lastX > 300h) AND (currentX < 100h) THEN INC(absX,400h);
  END;
  GET(MY,currentY);
  INC(absY,currentY);
  DEC(absY,lastY);
  IF (lastY < 100h) AND (currentY > 300h) THEN DEC(absY,400h);
  ELSIF (lastY > 300h) AND (currentY < 100h) THEN INC(absY,400h);
  END;
  lastX := currentX;
  lastY := currentY;
  x := absX MOD width;
  y := absY MOD height;
END GetMouse;

BEGIN
  width := ScreenWidth();
  height := ScreenHeight();
  absX := width DIV 2;
  absY := height DIV 2;
  GET(MX,lastX);
  GET(MY,lastY);
  SetMouse(absX,absY);
END MouseCoords.
