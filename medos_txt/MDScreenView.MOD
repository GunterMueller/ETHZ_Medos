IMPLEMENTATION MODULE MDScreenView; (*H.K. Buehrer, 5.4.82*)

  FROM SYSTEM IMPORT WORD, ADDRESS, ADR;
  FROM Monitor IMPORT CurrentLevel;
  FROM Terminal IMPORT WriteString, WriteLn;
  FROM Screen IMPORT 
    Bitmap, Mode, BlockDescriptor, Replicate, BlockTransfer, 
    UseBitmap, CreateBitmap, ReturnBitmap;
  FROM WindowHandler IMPORT 
    Window, CreateWindow, CloseWindow, Clear, PutOnTop, 
    WindowSignal, SignalSet, FullScreen;
  FROM WindowDialogue IMPORT InstallWindow, RemoveWindow;
  FROM CursorRelations IMPORT Inside, UpDotPos, RightDotPos;
  FROM CursorStuff IMPORT
    MenuSelection, TrackCursor, ReleaseCursor, xpos, ypos;

  FROM MDUtility IMPORT Same;
  FROM DumpFileHandler IMPORT Mem, ReadMemBlock;
  FROM Inspect IMPORT Installate, CalledAddr;
  FROM MDModuleHandler IMPORT modTab, modLoaded;
  FROM MDDialogView IMPORT InstallDialogCommand;

  CONST
    leftbrd = 16;
    rightbrd = 6;
    upbrd = 28;
    downbrd = 6;

  VAR
    screenwindow: Window;
    screenViewLevel: CARDINAL;
    screeninverted, viewOk: BOOLEAN;

    (*bitmap info:*)
    addr: ADDRESS;        (*address of bm descriptor table *)
    bitmapfp,             (*frame address    of current hardbitmap *)
    bitmapw, bitmaph,     (*width and height  "    "        "    " *)
    subx,suby,subw,subh,  (*coordinates of current sub bitmap *)
    right, down: CARDINAL;(*bitmap point displaied in the left upper corner*)
    
    (*globals,read only:*)
    maxright, maxdown,
    winx, winy, winw, winh,                       (*screenwindow^.outerblk *)
    insidex, insidey, insidew, insideh: CARDINAL; (*block inside border*)
    buffer: ARRAY [0..2*1024 DIV 16-1+3] OF BITSET;
    bufaddr: ADDRESS;
    bufbm: Bitmap;


  PROCEDURE PaintBorder(bm: Bitmap; blx, bly, blw, blh: CARDINAL);
    VAR line: RECORD size, pat: CARDINAL END;
        lineBlock: BlockDescriptor;
  BEGIN
    line.size := 1; line.pat := 177777B;
    WITH lineBlock DO
      x := blx; y := bly; w := 1; h := blh;
      Replicate(bm, lineBlock, replace, line);
      x := blx+blw-1;
      Replicate(bm, lineBlock, replace, line);
      x := blx; w := blw; h := 1;
      Replicate(bm, lineBlock, replace, line);
      y := bly+blh-1;
      Replicate(bm, lineBlock, replace, line);
    END;
  END PaintBorder;


  PROCEDURE DisplayBitmap;
    VAR fp,offset, (*frame address, address offset of current bm line *)
        fpinc, n, absright, absdown: CARDINAL;
        bufblk, winblk: BlockDescriptor;
        pattern: RECORD size, pat: CARDINAL END;
  BEGIN
    Clear(screenwindow);
    PaintBorder(screenwindow^.bm, insidex-1, insidey-1,insidew+2,insideh+2);
    pattern.size := 1; pattern.pat := 177777B;
    absright := subx+right; absdown := bitmaph-(suby+subh)+down;
    fpinc := bitmapw DIV 16; 
    fp := bitmapfp+((absdown*fpinc+(absright DIV 16)) DIV 4);
    offset := (absdown*fpinc+(absright DIV 16)) MOD 4;
    n := ((insidew+15) DIV 16)+4;
    WITH bufblk DO
      y := 1; w := insidew; h := 1;
    END;
    WITH winblk DO
      x := insidex; y := insidey+insideh-1; w := insidew; h := 1;
    END;
    WHILE winblk.y >= insidey DO
      bufblk.x := (absright MOD 16)+16*offset;
      ReadMemBlock(fp, n, bufaddr);
      IF screeninverted THEN Replicate(bufbm, bufblk,invert, pattern) END;
      BlockTransfer(screenwindow^.bm, winblk, replace, bufbm, bufblk);
      INC(fp, (offset+fpinc) DIV 4); offset := (offset+fpinc) MOD 4;
      DEC(winblk.y);
    END;
  END DisplayBitmap;


  PROCEDURE Min(a, b: CARDINAL): CARDINAL;
  BEGIN
    IF a < b THEN RETURN a
    ELSE RETURN b END
  END Min;


  PROCEDURE SetGlobals;
  BEGIN
    WITH screenwindow^.outerblk DO
      winx := x; winy := y; winw := w; winh := h
    END;
    IF (winw > leftbrd+rightbrd+2) AND (winh > upbrd+downbrd+2) THEN
      insidew := Min(winw-2-leftbrd-rightbrd,subw);
      insideh := Min(winh-2-upbrd-downbrd,subh);
      insidex := leftbrd; insidey := winh-2-upbrd-insideh;
      maxright := subw-insidew; maxdown := subh-insideh;
      right := Min(right,maxright); down := Min(down,maxdown);
    ELSE
      insidex := 1; insidey := 1; insidew := 0; insideh := 0;
      WriteString("-- window too small"); WriteLn;
    END
  END SetGlobals;


  PROCEDURE InvertScreen;
    VAR pattern: RECORD size, pat: CARDINAL END;
        insideblk: BlockDescriptor;
  BEGIN
    screeninverted := NOT screeninverted;
    IF screenwindow^.overlaid THEN
      DisplayBitmap
    ELSE
      pattern.size := 1; pattern.pat := 177777B;
      WITH insideblk DO
        x := insidex; y := insidey; w := insidew; h := insideh
      END;
      Replicate(screenwindow^.bm, insideblk, invert, pattern);
    END
  END InvertScreen;


  PROCEDURE Picture;
    CONST scal = 8;
    VAR savebm: Bitmap;
        saveblk, pictblk, inblk: BlockDescriptor;
        pattern: RECORD size, pat:CARDINAL END;
        done: BOOLEAN;
        buttons: BITSET;
        fullScreen: Window;
  BEGIN
    fullScreen := FullScreen();
    WITH saveblk DO
      x := 0; y :=0;
      w := (maxright DIV scal)+(insidew DIV scal)+4;
      h := (maxdown DIV scal)+(insideh DIV scal)+4;
      CreateBitmap(savebm,w,h,done);
    END;
    IF NOT done THEN WriteString("-- no space"); WriteLn; RETURN END;
    WITH pictblk DO
      w := saveblk.w; h := saveblk.h;
      x := winx+RightDotPos(screenwindow); x := x-Min(x, w);
      y := Min(winy+UpDotPos(screenwindow), fullScreen^.outerblk.h -h);
      BlockTransfer(savebm, saveblk, replace, fullScreen^.bm, pictblk);
      pattern.size := 1; pattern.pat := 0;
      Replicate(fullScreen^.bm, pictblk, replace, pattern);
      PaintBorder(fullScreen^.bm, x, y, w, h);
    END;
    WITH inblk DO
      w := (insidew DIV scal); h := (insideh DIV scal);
      x := pictblk.x+(right DIV scal)+2;
      y := pictblk.y+pictblk.h-(down DIV scal)-h-2;
    END;
    pattern.pat := 177777B;
    Replicate(fullScreen^.bm, inblk, replace, pattern);
    ReleaseCursor(FALSE, buttons);
    BlockTransfer(fullScreen^.bm, pictblk, replace, savebm, saveblk);
    ReturnBitmap(savebm);
    (*
    IF {2,3}*buttons # {} THEN
      WITH pictblk DO
        IF (xpos > x) AND (xpos < x+w) AND (ypos > y) AND (ypos < y+h) THEN
          right := Min(scal*(xpos-x-1), maxright);
          down := maxdown-Min(scal*(ypos-y-1), maxdown);
          DisplayScreen;
        END
      END;
    END
    *)
  END Picture;


  PROCEDURE ScreenControl(w: Window; s: WindowSignal);
  BEGIN
    IF s IN SignalSet{moved, changed, opened} THEN
      SetGlobals;
      DisplayBitmap
    ELSIF s = redraw THEN
      DisplayBitmap
    ELSIF s = closed THEN
      screenViewLevel := 177777B;
    END;
  END ScreenControl;


  PROCEDURE ScreenHandling(w: Window; callReason: CARDINAL);

    PROCEDURE ShiftLeft;
    BEGIN
      IF (right < maxright) AND (xpos > winx+insidex) AND (xpos < winx+winw) THEN  
        right := Min(right+xpos-(winx+insidex),maxright);
        DisplayBitmap
      ELSE
        PutOnTop(screenwindow)
      END
    END ShiftLeft;

    PROCEDURE ShiftRight;
      VAR offset: CARDINAL;
    BEGIN
      offset := winx+insidex+insidew;
      IF (right > 0) AND (xpos > winx) AND (offset > xpos) THEN
        IF offset-xpos > right THEN
          right := 0
        ELSE
          right := right-(offset-xpos)
        END;
        DisplayBitmap
      ELSE 
        PutOnTop(screenwindow)
      END
    END ShiftRight;

    PROCEDURE FlipH;
    BEGIN
      IF (xpos > winx) AND (xpos < winx+winw) THEN
        right := TRUNC(FLOAT(maxright)*FLOAT(xpos-winx)/FLOAT(winw));
        DisplayBitmap
      END
    END FlipH;

    PROCEDURE ScrollUp;
    BEGIN
      IF down < maxdown THEN
        down := Min(down+insidey+insideh-UpDotPos(screenwindow),maxdown);
        DisplayBitmap
      ELSE
        PutOnTop(screenwindow)
      END
    END ScrollUp;

    PROCEDURE ScrollDown;
      VAR offset: CARDINAL;
    BEGIN
      offset := UpDotPos(screenwindow);
      IF (down >0) AND (offset > insidey) THEN
        IF offset-insidey > down THEN
          down := 0
        ELSE 
          down := down-(offset-insidey)
        END;
        DisplayBitmap
      ELSE
        PutOnTop(screenwindow)
      END
    END ScrollDown;

    PROCEDURE FlipV;
    BEGIN
      down := maxdown-TRUNC(FLOAT(maxdown)*FLOAT(UpDotPos(screenwindow))
                            /FLOAT(insidey+insideh));
      DisplayBitmap
    END FlipV;

  BEGIN(*ScreenHandling *)
    IF callReason = 5 THEN
      CloseWindow(screenwindow)
    ELSIF callReason = 4 THEN (*empty *)
    ELSIF NOT Inside(screenwindow) OR (UpDotPos(screenwindow) >= insidey+insideh) THEN
      CASE TrackCursor() OF
        1: ShiftLeft |
        2: FlipH     |
        3: ShiftRight
      ELSE
      END;
    ELSIF RightDotPos(screenwindow) < insidex THEN
      CASE callReason OF
        1: ScrollUp   |
        2: FlipV      |
        3: ScrollDown 
      ELSE
      END;
    ELSIF callReason >= 2 THEN
      CASE MenuSelection(" SCREEN| invert| redraw| remove") OF
        2: InvertScreen               |
        3: DisplayBitmap              |
        4: RemoveWindow(screenwindow);
           CloseWindow(screenwindow)
      ELSE
      END;
    ELSIF callReason = 1 THEN
      Picture;
    END
  END ScreenHandling;


  PROCEDURE BitmapTabAddr(): ADDRESS;
    CONST relBmTabAddr = 3;
    VAR m: CARDINAL;
        addr: ADDRESS;
  BEGIN
    m := 0;
    LOOP 
      IF m >= modLoaded THEN
        addr := NIL; EXIT
      ELSIF modTab[m] # NIL THEN
        IF Same(modTab[m]^.modName, "Screen          ") THEN
          addr := Mem(modTab[m]^.base+relBmTabAddr); EXIT
        END
      END;
      INC(m)
    END;
    RETURN addr
  END BitmapTabAddr;


  PROCEDURE ReadBitmapInfo(bmNr: CARDINAL);
    CONST maxBM = 40;
          bmRecWidth = 9 (*words *);
    VAR bmAddr, hardAddr: ADDRESS;
  BEGIN
    IF (bmNr <= maxBM) AND (addr < 177777B-bmRecWidth*bmNr-8)
                  AND (Mem(addr+bmRecWidth*bmNr+8) # 177777B) THEN
      bmAddr := addr+bmRecWidth*bmNr;
      hardAddr := Mem(bmAddr+0);
      subx := Mem(bmAddr+1); suby := Mem(bmAddr+2);
      subw := Mem(bmAddr+3); subh := Mem(bmAddr+4);
      bitmapfp := Mem(hardAddr); bitmapfp := (bitmapfp DIV 4) + (bitmapfp MOD 4)*40000B;
      IF (hardAddr <= 177774B) AND (Mem(hardAddr+1) <= 128)
                              AND (Mem(hardAddr+2) <= 2046) THEN
        bitmapw := 16*Mem(hardAddr+1); bitmaph := 2+Mem(hardAddr+2);
        right := 0; down := 0;
        IF (subx <= 177777B-subw) AND (subx+subw <= bitmapw)
            AND (suby <= 177777B-subh) AND (suby+subh <= bitmaph)
        THEN RETURN (* bitmap ok !!! *)
        END
      END
    END;
    (* else *)
    WriteString("-- illegal bitmapdescriptor"); WriteLn;
    bitmapw := 0; bitmaph := 0;
    subx := 0; suby := 0; subw := 0; subh := 0;
  END ReadBitmapInfo;

  PROCEDURE RetryWithDD;
    VAR m, addr: CARDINAL;
  BEGIN
    m := 0;
    LOOP 
      IF m >= modLoaded THEN RETURN
      ELSIF modTab[m] # NIL THEN
        IF Same(modTab[m]^.modName, "DisplayDriver   ") THEN
          addr := Mem(modTab[m]^.base+3); EXIT
        END
      END;
      INC(m)
    END;
    IF addr>177773B THEN RETURN END;
    (* addr is address of DisplayDriver.BMD *)
    m := Mem(addr); bitmapfp := (m DIV 4) + (m MOD 4)*40000B;
    bitmapw := Mem(addr+1); 
    bitmaph := Mem(addr+2);
    IF (bitmapw>128) OR (bitmaph>2046) THEN RETURN END;
    bitmapw := 16*bitmapw; bitmaph := 2+bitmaph;
    subx := 0; suby := 0; subw := bitmapw; subh := bitmaph;
    right := 0; down := 0;
    viewOk := TRUE;
    InstallDialogCommand(InitScreenView," screen");
  END RetryWithDD;



  PROCEDURE ShowBitmap;
  BEGIN
    ReadBitmapInfo(Mem(CalledAddr()));
    screeninverted := FALSE;
    IF screenViewLevel = 177777B THEN
      InitScreenView
    ELSE
      SetGlobals; 
      DisplayBitmap
    END;
  END ShowBitmap;


  PROCEDURE InitScreenView;
    VAR done: BOOLEAN;
  BEGIN
    IF NOT viewOk THEN RETURN END;
    IF screenViewLevel # 177777B THEN PutOnTop(screenwindow)
    ELSE
      CreateWindow(screenwindow, winx, winy, winw, winh,
                   "   screen", FALSE, ScreenControl, done);
      IF done THEN 
        InstallWindow(screenwindow, {1..5}, ScreenHandling,
            SignalSet{moved, changed, fontchanged}, done);
        IF NOT done THEN
          CloseWindow(screenwindow)
        ELSE
          screenViewLevel := CurrentLevel()
        END
      END;
    END
  END InitScreenView;


  PROCEDURE TerminateScreenView;
  BEGIN
    IF screenViewLevel >= CurrentLevel() THEN
       screenViewLevel := 177777B
    END;
  END TerminateScreenView;


BEGIN (*MDScreenView *)
  viewOk := FALSE;
  winx := 100; winy := 200; winw := 400; winh := 300;
  screenViewLevel := 177777B;
  bufaddr := (ADR(buffer)+3) DIV 4 * 4;
  UseBitmap(bufbm, 1024, 2, bufaddr DIV 4, 2*1024 DIV 16, screeninverted);
  IF NOT screeninverted THEN RETURN END;
  screeninverted := FALSE;
  addr := BitmapTabAddr();
  IF addr # NIL THEN
    viewOk := TRUE;
    ReadBitmapInfo(0);
    InstallDialogCommand(InitScreenView," screen");
    Installate(" bitmap", ShowBitmap)
  ELSE
    RetryWithDD;
  END;
END MDScreenView.  
