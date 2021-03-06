MODULE Bars;  (*NW 19.6.82*)
  FROM DisplayDriver IMPORT
    BMDescriptor, BMD, ScreenWidth, ScreenHeight, Show;
  FROM Terminal IMPORT Read, Write, WriteString;

  TYPE Pattern = RECORD leng: CARDINAL; val: BITSET END ;
       Block = RECORD x,y,w,h: CARDINAL END ;

  VAR ch: CHAR;
     h, y, maxWidth, maxHeight: CARDINAL;
     B:   ARRAY ["0".."9"] OF BITSET;
     pat: Pattern;
     blk: Block;

  PROCEDURE REPL(mode: CARDINAL; VAR bmd: BMDescriptor;
                 VAR src: Pattern; VAR dst: Block);
    CODE 343B
  END REPL;

  PROCEDURE DDT(m: CARDINAL; VAR bmd: BMDescriptor;
                x, y: CARDINAL);
    CODE 342B
  END DDT;

  PROCEDURE PaintSquares;
    VAR x,y: CARDINAL;
  BEGIN blk.w := 16; blk.h := 16; pat.val := {};
    y := 0;
    REPEAT blk.y := y; pat.val := pat.val / {0..15};
      x := 0;
      REPEAT blk.x := x; pat.val := pat.val / {0..15};
        REPL(0, BMD, pat, blk); x := x+16
      UNTIL x = maxWidth;
      y := y+16
    UNTIL y = maxHeight
  END PaintSquares;

BEGIN
  WriteString("options:"); Write(36C);
  WriteString("  0..9  horiz. lines"); Write(36C);
  WriteString("  a..z  vert. lines"); Write(36C);
  WriteString("  #  /  [ ]  esc"); Write(36C);
  Read(ch); pat.leng := 1;
  B["0"] := {0,2,4,6,8,10,12,14}; B["1"] := {0,1,4,5,8,9,12,13};
  B["2"] := {0..3, 8..11}; B["3"] := {0..7};
  B["4"] := {0,8}; B["5"] := {1,9};
  B["6"] := {6,14}; B["7"] := {7,15};
  B["8"] := {1..7, 9..15}; B["9"] := {0, 2..8, 10..15};
  maxWidth := ScreenWidth(); maxHeight := ScreenHeight();
  WHILE ch # 33C DO
    IF ch = "#" THEN PaintSquares
    ELSIF ("0" <= ch) & (ch <= "9") THEN
      pat.val := B[ch];
      blk.x := 0; blk.y := 0; blk.w := maxWidth; blk.h := maxHeight;
      REPL(0, BMD, pat, blk)
    ELSIF ("a" <= ch) & (ch <= "z") THEN
      h := CARDINAL(ch) - 140B; y := maxHeight;
      blk.x := 0; blk.w := maxWidth; blk.h := h;
      REPEAT
        pat.val := {}; y := y-h; blk.y := y;
        REPL(0, BMD, pat, blk);
        pat.val := {0..15}; y := y-h; blk.y := y;
        REPL(0, BMD, pat, blk)
      UNTIL y < 2*h;
      pat.val := {}; blk.y := 0; blk.h := y;
      REPL(0, BMD, pat, blk)
    ELSIF ch = "/" THEN
      blk.x := 0; blk.y := 0; blk.w := maxWidth; blk.h := maxHeight;
      pat.val := {}; REPL(0, BMD, pat, blk);
      IF maxWidth < maxHeight THEN h := maxWidth ELSE h := maxHeight END ;
      FOR y := 0 TO h-1 DO DDT(1, BMD, y, y) END
    ELSIF ch = "[" THEN Show(BMD, TRUE)
    ELSIF ch = "]" THEN Show(BMD, FALSE)
    END ;
    Read(ch)
  END ;
  Write(14C)
END Bars.
