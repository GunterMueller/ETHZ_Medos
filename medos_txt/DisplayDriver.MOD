IMPLEMENTATION MODULE DisplayDriver;   (*NW 24.6.82*)

  FROM SYSTEM IMPORT ADDRESS, ADR, WORD;
  FROM Frames IMPORT Allocate, ChangeSize, Size;
  FROM DefaultFont IMPORT defaultFont;
  FROM Monitor IMPORT SharedLevel, TermProcedure;

  TYPE
    BlkDesc = RECORD x, y, w, h: CARDINAL END;
    Pattern = RECORD leng, val: CARDINAL END;

  VAR
    newDisplay: BOOLEAN;
    SWidth, SHeight: CARDINAL;    (*of screen*)
    BMDesc: ARRAY [0..6] OF WORD;
    BMX: POINTER TO BMDescriptor;
    bmLevel: CARDINAL;            (*shared level of actually shown bitmap*)
    width, height: CARDINAL;      (*width of character, height of line*)
    Height: CARDINAL;             (*of bitmap, changed by SetBitmap*)
    BMA: CARDINAL;                (*bitmap frame pointer*)
    B: BlkDesc;
    white: Pattern;
    a: ADDRESS;

  PROCEDURE GET(chan: CARDINAL; VAR val: CARDINAL);
    CODE 240B
  END GET;

  PROCEDURE PUT(chan, val: WORD);
    CODE 241B
  END PUT;

  PROCEDURE REPL(mode: CARDINAL; VAR bmd: BMDescriptor;
                 VAR src: Pattern; VAR dest: BlkDesc);
    CODE 343B
  END REPL;

  PROCEDURE BBLT(mode: CARDINAL; VAR dmp: BMDescriptor;
                 VAR sblk, dblk: BlkDesc; VAR smp: BMDescriptor);
    CODE 344B
  END BBLT;

  PROCEDURE DCH(VAR bmd: BMDescriptor; font: CARDINAL;
                VAR blk: BlkDesc;  ch: CHAR);
    CODE 345B
  END DCH;

  PROCEDURE ROR(x,n: CARDINAL): CARDINAL;
    CODE 275B
  END ROR;


  PROCEDURE ScreenWidth(): CARDINAL;
  BEGIN  RETURN SWidth
  END ScreenWidth;

  PROCEDURE ScreenHeight(): CARDINAL;
  BEGIN  RETURN SHeight
  END ScreenHeight;

  PROCEDURE Show(VAR bmd: BMDescriptor; on: BOOLEAN);
  BEGIN
    IF (bmLevel = 0) OR (bmLevel = SharedLevel()) THEN
      IF ROR(bmd.f, 2) = BMA THEN  bmLevel := 0
      ELSE bmLevel := SharedLevel()
      END;
      IF newDisplay THEN
        PUT(75B, ROR(bmd.f, 2)); PUT(74B, on)
      ELSE
        BMX^ := bmd;
        IF NOT on THEN BMX^.w := 0 END;
        PUT(0, BMX)
      END
    END
  END Show;

  PROCEDURE BuildBMD(fp, w, h: CARDINAL; VAR bmd: BMDescriptor);
  BEGIN
    IF h < 2 THEN HALT END;
    bmd.f := ROR(fp, 14); bmd.h := h-2;
    bmd.w := w DIV 16; bmd.z := 0
  END BuildBMD;


  PROCEDURE DFF(): CARDINAL;  (*Default Font Frame*)
  BEGIN  RETURN defaultFont
  END DFF;

  PROCEDURE CharWidth(): CARDINAL;
  BEGIN  RETURN width
  END CharWidth;

  PROCEDURE LineHeight(): CARDINAL;
  BEGIN  RETURN height
  END LineHeight;


  PROCEDURE BMF(): CARDINAL;  (*BitMap Frame*)
  BEGIN  RETURN BMA
  END BMF;

  PROCEDURE MapHeight(): CARDINAL;
  BEGIN  RETURN Height
  END MapHeight;

  PROCEDURE clear;
  BEGIN
    B.x := 0; B.w := SWidth; B.y := 0; B.h := Height;
    REPL(0, BMD, white, B);
    B.h := height; B.y := Height-height
  END clear;

  PROCEDURE ChangeBitmap(h: CARDINAL; VAR done: BOOLEAN);
    (*sets bitmap Height*)
  BEGIN
    IF (h >= 2*height) AND NOT ODD(h) THEN
      IF h # Height THEN
        ChangeSize(BMA, h*(SWidth DIV 16), done);
        IF done THEN
          Height := h;
          BuildBMD(BMA, SWidth, Height, BMD);
          clear;
          IF bmLevel = 0 THEN Show(BMD, TRUE) END;
        END
      ELSE done := TRUE
      END
    ELSE done := FALSE
    END
  END ChangeBitmap;

  PROCEDURE scroll;
    VAR S, D: BlkDesc;
  BEGIN (*scroll up one line and clear the buttom line*)
    WITH S DO
      x := 0; w := SWidth; y := B.y; h := Height-y - height;
    END ;
    D := S; D.y := S.y + height; BBLT(0, BMD, S, D, BMD);
    S.h := height; REPL(0, BMD, white, S);
  END scroll;

  PROCEDURE Write(ch: CHAR);
    (*the following control characters are interpreted:
      10C BS  backspace one character
      12C LF  next line, same x position
      14C FF  clear page
      15C CR  return to start of line
      30C CAN clear line
      36C EOL next line
     177C DEL backspace one character and clear it *)
  BEGIN
    IF ch = 177C THEN
      IF B.x >= width THEN
        B.w := width; B.x := B.x - width;
        REPL(0, BMD, white, B);
        B.w := SWidth - B.x;
      END;
    ELSIF ch >= 40C THEN
      IF B.w < width THEN Write(36C) END ;
      DCH(BMD, defaultFont, B, ch)
    ELSIF ch = 36C THEN
      Write(15C); Write(12C)
    ELSIF ch = 30C THEN
      B.x := 0; B.w := SWidth; REPL(0, BMD, white, B)
    ELSIF ch = 15C THEN
      B.x := 0; B.w := SWidth
    ELSIF ch = 14C THEN clear
    ELSIF ch = 12C THEN
      IF B.y >= height THEN
        B.y := B.y - height
      ELSE scroll
      END
    ELSIF ch = 10C THEN
      IF B.x >= width THEN
        B.x := B.x - width; B.w := SWidth - B.x;
      END
    END
  END Write;

  PROCEDURE reset;
  BEGIN
    BuildBMD(BMA, SWidth, Height, BMD);
    IF bmLevel >= SharedLevel() THEN bmLevel := 0 END;
    IF bmLevel = 0 THEN Show(BMD, TRUE) END;
  END reset;

BEGIN
  GET(0, a);
  newDisplay := ODD(a);
  IF newDisplay THEN GET(74B, a);
    SWidth := (a MOD 32 + 1) * 64;
    SHeight := (a DIV 32 MOD 1024 + 1) * 2;
  ELSE SWidth := 768; SHeight := 592;
  END;
  BMX := (ADR(BMDesc)+3) DIV 4*4; (*align*)
  a := defaultFont*4 - 2; height := CARDINAL(a^) MOD 400B +2;
  a := a+1; width := CARDINAL(a^);
  white.leng := 1; white.val := 0;
  Height := SHeight;
  Allocate(BMA, SWidth DIV 16 * Height);
  BuildBMD(BMA, SWidth, Height, BMD);
  clear;
  bmLevel := 0;
  Show(BMD, TRUE);
  TermProcedure(reset);
END DisplayDriver.
