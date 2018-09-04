IMPLEMENTATION MODULE LineDrawing;   (*NW 14.6.82*)
  FROM SYSTEM IMPORT ADDRESS, ADR, WORD;
  IMPORT DisplayDriver;
  FROM DisplayDriver IMPORT
    BMDescriptor, BMF, BMD, DFF, LineHeight, ScreenWidth, ScreenHeight;
  FROM FileSystem IMPORT File, WriteWord;
  FROM ByteBlockIO IMPORT WriteBytes;

  TYPE Block = RECORD x,y,w,h: INTEGER END ;
       Pattern = RECORD L: CARDINAL;
                    b0,b1,b2,b3,b4,b5: BITSET
                 END ;

  VAR font: CARDINAL;  (*frame pointer*)
      blk, sblk: Block;
      pat: ARRAY [0..3] OF Pattern;

  PROCEDURE GET(chan: CARDINAL; VAR val: WORD);
    CODE 240B
  END GET;

  PROCEDURE DDT(m: PaintMode; VAR bmd: BMDescriptor; x,y: INTEGER);
    CODE 342B
  END DDT;

  PROCEDURE REPL(m: PaintMode; VAR bmd: BMDescriptor;
                 VAR src: Pattern; VAR dest: Block);
    CODE 343B
  END REPL;

  PROCEDURE BBLT(m: PaintMode; VAR DB: BMDescriptor;
                 VAR src, dest: Block; VAR SB: BMDescriptor);
    CODE 344B
  END BBLT;

  PROCEDURE DCH(VAR bmd: BMDescriptor; font: CARDINAL;
                VAR dest: Block;  ch: CHAR);
    CODE 345B
  END DCH;

  PROCEDURE MOVF(db, dst, sb, src, n: CARDINAL);
    CODE 337B
  END MOVF;

  PROCEDURE dot(c: CARDINAL; x,y: INTEGER);
  BEGIN
    IF x >= width THEN x := width-1 END ;
    IF y >= height THEN y := height-1 END ;
    IF c = 0 THEN DDT(erase, BMD, x, y)
             ELSE DDT(replace, BMD, x, y)
    END
  END dot;

  PROCEDURE line(d,n: CARDINAL);
  BEGIN 
    CASE d OF
    0: REPEAT Px := Px+1;
         DDT(replace, BMD, Px, Py); n := n-1
       UNTIL n = 0 |
    1: REPEAT Px := Px+1; Py := Py+1;
         DDT(replace, BMD, Px, Py); n := n-1
       UNTIL n = 0 |
    2: REPEAT Py := Py+1;
         DDT(replace, BMD, Px, Py); n := n-1
       UNTIL n = 0 |
    3: REPEAT Px := Px-1; Py := Py+1;
         DDT(replace, BMD, Px, Py); n := n-1
       UNTIL n = 0 |
    4: REPEAT Px := Px-1;
         DDT(replace, BMD, Px, Py); n := n-1
       UNTIL n = 0 |
    5: REPEAT Px := Px-1; Py := Py-1;
         DDT(replace, BMD, Px, Py); n := n-1
       UNTIL n = 0 |
    6: REPEAT Py := Py-1;
         DDT(replace, BMD, Px, Py); n := n-1
       UNTIL n = 0 |
    7: REPEAT Px := Px+1; Py := Py-1;
         DDT(replace, BMD, Px, Py); n := n-1
       UNTIL n = 0  
    END
  END line;

  PROCEDURE area(color: CARDINAL; X,Y,W,H: INTEGER);
  BEGIN
    IF (X <= width) & (Y < height) THEN
      IF X+W > width THEN W := width-X END ;
      IF Y+H > height THEN H := height-Y END ;
      WITH blk DO
        x := X; y := Y; w := W; h := H
      END ;
      REPL(mode, BMD, pat[color MOD 4], blk)
    END
  END area;

  PROCEDURE copyArea(sx,sy,dx,dy,dw,dh: INTEGER);
  BEGIN
    IF (sx < width) & (sy < height) &
       (dx < width) & (dy < height) THEN
      IF dx+dw > width THEN dw := width - dx END ;
      IF dy+dh > height THEN dh := height - dy END ;
      sblk.x := sx; sblk.y := sy;
      WITH blk DO
        x := dx; y := dy; w := dw; h := dh
      END ;
      BBLT(mode, BMD, sblk, blk, BMD)
    END
  END copyArea;

  PROCEDURE clear;
  BEGIN mode := replace; area(0, 0, 0, width, height)
  END clear;

  PROCEDURE Write(ch: CHAR);
  BEGIN
    WITH blk DO
      x := Px; y := Py; w := width - Px; h := CharHeight;
      IF w >= CharWidth THEN
        DCH(BMD, font, blk, ch); Px := x
      END
    END
  END Write;

  PROCEDURE WriteString(s: ARRAY OF CHAR);
    VAR i: CARDINAL;
  BEGIN i := 0;
    WITH blk DO
      x := Px; y := Py; w := width - Px; h := CharHeight;
      WHILE (i <= HIGH(s)) & (w >= CharWidth) DO
        DCH(BMD, font, blk, s[i]); i := i+1
      END ;
      Px := x
    END
  END WriteString;

  PROCEDURE WriteBitmap(VAR f: File);
    VAR i: CARDINAL; a,fr,n: ADDRESS;
        buf: ARRAY [0..47] OF WORD;
  BEGIN WriteWord(f,0);
    a := 0; fr := BMF(); n := width DIV 16;
    FOR i := 1 TO height DO
      MOVF(0, ADR(buf), fr, a, n);
      WriteBytes(f, ADR(buf), 2*n); a := a+n
    END ;
  END WriteBitmap;

BEGIN width := ScreenWidth(); height := ScreenHeight();
  CharWidth := DisplayDriver.CharWidth(); CharHeight := LineHeight();
  font := DFF(); mode := replace; Px := 0; Py := 0;
  WITH pat[3] DO
    L := 1; b0 := {0..15}
  END ;
  WITH pat[2] DO
    L := 2; b0 := {0,2,4,6,8,10,12,14}; b1 := {1,3,5,7,9,11,13,15}
  END ;
  WITH pat[1] DO
    L := 6; b0 := {0,4,8,12}; b1 := {}; b2 := {};
    b3 := {2,6,10,14}; b4 := {}; b5 := {}
  END ;
  WITH pat[0] DO
    L := 1; b0 := {}
  END
END LineDrawing.
