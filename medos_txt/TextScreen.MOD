IMPLEMENTATION MODULE TextScreen; (* Ch. Jacobi  30.10.80 *) 

  (*$T-*) (*$R-*)

  FROM SYSTEM IMPORT WORD, ADR;
  FROM ScreenDriver2 IMPORT
    BlockDescriptor,
    charH, charWmax, charWmin,
    absWindow, absLine,
    bitmapHint;
  IMPORT ScreenDriver2, Terminal;


  TYPE 
    Mode = (replace, paint, invert, erase);

  VAR
    whitePattern: RECORD a,b: CARDINAL END;

  CONST
    BS  =  10C;
    LF  =  12C;
    FF  =  14C;
    CR  =  15C;
    EOL =  36C;
    DEL = 177C;

  PROCEDURE Write(ch: CHAR);
  BEGIN 
    Terminal.Write(ch)
  END Write;

  PROCEDURE TSFreeChars(): CARDINAL;
    (* returns number of free characters in the currend line *)
  BEGIN 
    RETURN absLine.w DIV charWmax
  END TSFreeChars;

  PROCEDURE TSFreeLines(): CARDINAL;
    (* returns number of empty lines *)
  BEGIN 
    RETURN (absLine.y-absWindow.y) DIV absLine.h
  END TSFreeLines;

  PROCEDURE TSGetPos(VAR line, pos: CARDINAL);
    (* gets position; units are characters and lines *)
  BEGIN 
    line := (absWindow.y + absWindow.h - (absLine.y+absLine.h)) DIV absLine.h;
    pos := (absLine.x - absWindow.x) DIV charWmin;
  END TSGetPos;

  PROCEDURE TSSetPos(line, pos: CARDINAL);
    (* sets position; units are characters and lines *)
  BEGIN 
    absLine.h := charH + charH DIV 10 + 1;
    IF ((absWindow.w-2) DIV charWmin)<pos THEN pos := 0 END; 
    IF (absWindow.h DIV absLine.h)<line THEN line := 0 END;
    absLine.w := 0; (*if CTRL-C in between position not correct but INSIDE*)
    absLine.x := absWindow.x+pos*charWmin;
    absLine.w := absWindow.x+absWindow.w-absLine.x;
    absLine.y := absWindow.y + absWindow.h - absLine.h*(line+1);
  END TSSetPos;

  PROCEDURE TSClearLines(n: CARDINAL);
    VAR blk1, blk2: BlockDescriptor; i: CARDINAL;
  BEGIN
    ScreenDriver2.ClearChars(177777B);
    IF absWindow.h DIV absLine.h < n THEN
      (* clears the whole screen *)
      Write(FF); RETURN
    ELSE (* don't clear the whole screen *)
      IF (absLine.x<=absWindow.x+1) AND (n>0) THEN DEC(n) END;
      IF n=0 THEN RETURN END;  (***current microcoding of REPL*)
      i := n*absLine.h;
      blk1 := absWindow;
      IF (absLine.y-blk1.y) >= i THEN
        (* clears a fraction of the screen *)
        blk1.h := i;
        blk1.y := absLine.y-i;
        REPLi(replace, bitmapHint, ADR(whitePattern), blk1);
      ELSE
        (* scrolling is needed *)

        n := absWindow.h DIV absLine.h - n; (*is new line position*)
        i := ((absWindow.h+absWindow.y-absLine.y) DIV absLine.h-n)*absLine.h;
             (* number of points to scroll*)

        blk1.h := n*absLine.h;
        blk1.y := absWindow.h+absWindow.y-blk1.h;
        INC(absLine.y, i);
        blk2 := blk1; 
        DEC(blk2.y, i);  
        BBLTi(replace, bitmapHint, blk2, blk1, bitmapHint);
        (* clear the rest *)

        blk1.h := blk1.y-absWindow.y;
        blk1.y := absWindow.y;
        REPLi(replace, bitmapHint, ADR(whitePattern), blk1);
      END  
    END;
  END TSClearLines;

    PROCEDURE DCHi(bma: WORD; font: WORD; VAR line: BlockDescriptor; ch: CHAR);
    CODE 345B
    END DCHi;
 
    PROCEDURE REPLi(m: Mode; bm: WORD; patAddr: WORD; VAR dest: BlockDescriptor);
    CODE 343B
    END REPLi;

    PROCEDURE BBLTi(m: Mode; dbma: WORD; VAR s,d: BlockDescriptor; sbma: WORD );
    CODE 344B
    END BBLTi;

  PROCEDURE FreeChars(): CARDINAL;
    (* returns number of free characters in the currend line *)
  BEGIN 
     RETURN ScreenDriver2.actualProcRec.freeChars()
  END FreeChars;

  PROCEDURE FreeLines(): CARDINAL;
    (* returns number of empty lines *)
  BEGIN 
    RETURN ScreenDriver2.actualProcRec.freeLines()
  END FreeLines;

  PROCEDURE GetPos(VAR line, pos: CARDINAL);
    (* gets position; units are characters and lines *)
  BEGIN 
    ScreenDriver2.actualProcRec.getPos(line, pos)
  END GetPos;

  PROCEDURE SetPos(line, pos: CARDINAL);
    (* sets position; units are characters and lines *)
  BEGIN 
    ScreenDriver2.actualProcRec.setPos(line, pos)
  END SetPos;

  PROCEDURE ClearChars(n: CARDINAL);
  BEGIN
    ScreenDriver2.actualProcRec.clearChars(n)
  END ClearChars;

  PROCEDURE ClearLines(n: CARDINAL);
  BEGIN
    ScreenDriver2.actualProcRec.clearLines(n)
  END ClearLines;

  VAR tr: ScreenDriver2.TextProcRecord;
BEGIN
  WITH whitePattern DO 
    a := 1;  b := 0 
  END;
  IF NOT ScreenDriver2.actualProcRec.windowHandler THEN 
    WITH tr DO
      write := ScreenDriver2.WriteChar;
      freeLines := TSFreeLines; 
      freeChars := TSFreeChars;
      getPos := TSGetPos;
      setPos := TSSetPos;
      clearChars := ScreenDriver2.ClearChars;
      clearLines := TSClearLines;
      (* setBlkPos *)
      (* getBlkPos *)
      windowHandler := FALSE;
    END;
    ScreenDriver2.SetProcRec(tr)
  END
END TextScreen.

 
