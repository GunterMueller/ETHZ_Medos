IMPLEMENTATION MODULE EditDisplay; (* vs I.11       Werner Winiger 24.6.82
                      ===========  *)
  
  FROM SYSTEM IMPORT
    WORD, ADDRESS, ADR;
  FROM FileSystem IMPORT
    File, Response, Lookup, Close;
  FROM BitmapIO IMPORT
    WriteBitmap;
  FROM Terminal IMPORT
    Write;
  FROM Screen IMPORT
    Bitmap, Font, Mode, BlockDescriptor, GetSystemBitmap,
    GetDefaultBitmap, GetMaxBlock, CreateBitmap, CreateSubBitmap,
    IsSubBitmap, DisplayChar, BlockTransfer, Replicate;
  FROM ScreenResources0 IMPORT
    PToBMD, PToFontFramePointer;
  FROM EditFonts IMPORT
    charSize, lineSize, menuLineSize, menuCharSize, defaultFont, editFont,
    controlCharsAvailable, LoadFonts;
  FROM MouseCoords IMPORT
    SetMouseWindow, SetMouse, MoveMouse, GetMouse;

  CONST
    NULL      = 0c;
    FF        = 14c;
    EOF       = 34c;
    GS        = 35c;
    EOL       = 36c;
    US        = 37c;
    BLANK     = 40c;
    DEL       = 177c;
    EMPTY     = 377c;

    maxLine   = 75;   (* for GACHA8 on the *)
    LL        = 128;  (*  832 x 640 screen *)
    MsgLength = 49;
    maxchar    = (maxLine+1)*LL-1;
    maxCommand  = 5;
    CommandWidth = 6;
    SBW          = 26; (* scroll bar width *)
    cursorHeight = 12;

  TYPE
    SquarePattern = RECORD
      size: CARDINAL;
      bits: ARRAY [1..16] OF CARDINAL;
    END;

  VAR
    windowbar: ARRAY [0..19] OF RECORD
      y,pat: CARDINAL;
    END;
    caretSet: BOOLEAN;
    caretPat: SquarePattern;
    markSet: ARRAY [1..2] OF BOOLEAN;
    mark: ARRAY [1..2] OF BlockDescriptor;
    markPat: ARRAY [1..2] OF SquarePattern;
    cursorPat: ARRAY [0..2] OF SquarePattern;
    selectPat: ARRAY [0..6] OF SquarePattern;
    whitePat, blackPat, barPat: ARRAY [0..1] OF CARDINAL;
    text: ARRAY [0..maxchar] OF CHAR;
    defBMD,
    editFontAddr: ADDRESS;
    inWindow: BOOLEAN;
    defWindow, menuWindow: Bitmap;
    innerblk,
    cursor, bar, selection, caret,
    saveArea, menuSource, menuArea, line,
    message, filename, fNchar, char,
    menuCursor, fromline, toline, menuline: BlockDescriptor;
    origoX, leftX, leftXplus, leftXminus, rightX, origoY, bottomY, 
    lastLineY, topY, msgX, msgW, fnX, fnW, msgChars,
    menuHeight, menuWidth, comm, mxl, mxh, myl, myh: CARDINAL;
    currentCursor: RECORD
      cx,cy,
      carea: CARDINAL;
      on: BOOLEAN;
    END;
    pict: ARRAY [0..12] OF CHAR;

  PROCEDURE DCH (BMD: ADDRESS; FONT: WORD;
                 VAR pos: BlockDescriptor; ch: CHAR);
  CODE
    345b;
  END DCH;

  PROCEDURE REPL (m: Mode; BMD, pat: ADDRESS;
                  VAR pos: BlockDescriptor);
  CODE
    343b;
  END REPL;

  PROCEDURE HardCopy;
    VAR  (* -------- *)
      f: File;
  BEGIN
    Lookup(f,pict,TRUE);
    IF f.res = done THEN
      WriteBitmap(f,defWindow);
      Close(f);
      pict[7] := CHAR(CARDINAL(pict[7])+1);
    END;
  END HardCopy;

  PROCEDURE WriteString (s: ARRAY OF CHAR; pos: BlockDescriptor; w: Bitmap; f: Font); 
    VAR  (* -----------                                                           *)
      i: CARDINAL;
  BEGIN
    Replicate(w,pos,erase,blackPat);
    i := 0;
    WHILE (i <= HIGH(s)) AND (s[i] # NULL) AND (INTEGER(pos.w) > 0) DO
      DisplayChar(w,pos,f,s[i]);
      INC(i);
    END;
  END WriteString;


  PROCEDURE Hline (w: Bitmap; x0,y0,w0,h0: CARDINAL);
  BEGIN (*  -----                                 *)
    WITH line DO
      x := x0;
      y := y0;
      w := w0;
      h := h0;
    END;
    Replicate(w,line,replace,blackPat);
  END Hline;


  PROCEDURE Vline (w: Bitmap; x0,y0,w0,h0: CARDINAL);
  BEGIN (*  -----                                 *)
    WITH line DO
      x := x0;
      y := y0;
      w := w0;
      h := h0;
    END;
    Replicate(w,line,replace,blackPat);
  END Vline;


  PROCEDURE MIN (c0,c1: CARDINAL): CARDINAL;
  BEGIN (*  ---                *)
    IF c0 < c1
    THEN RETURN c0
    ELSE RETURN c1
    END;
  END MIN;


  PROCEDURE InvertCursor;
  BEGIN (*  ------------ *)
    WITH currentCursor DO
      Replicate(defWindow,cursor,invert,cursorPat[carea]);
      on := NOT on;
    END;
  END InvertCursor;

 
  PROCEDURE DrawCursor (areaC,xC,yC: CARDINAL);
  BEGIN (*  ----------                      *)
    WITH currentCursor DO
      IF (NOT on)
      OR ( (areaC=0) & ((myh-8-yC) DIV menuLineSize # comm) )
      OR (xC # cx) OR (yC # cy)
      THEN
        IF on THEN InvertCursor; END;
        WITH cursor DO
          CASE areaC OF
          0: comm := (myh-8-yC) DIV menuLineSize;
             x := origoX + mxl + 5;
             y := origoY + myl + menuHeight - 25 - comm*menuLineSize;
             w := 6*menuCharSize + 4;
             h := menuLineSize; |
          1: x := origoX + xC;
             y := origoY + yC - 13;
             w := 8;
             h := 16; |
          2: x := origoX + xC;
             y := origoY + yC - 11;
             w := 12;
             h := cursorHeight; 
          END;      
        END;
        carea := areaC;
        cx := xC;
        cy := yC;
        InvertCursor;
      END;
    END;
  END DrawCursor;


  PROCEDURE MenuOn (Mx,My: CARDINAL);
    VAR (*  ------                *)
      deltaY: INTEGER;
  BEGIN
    InvertCursor;
    IF Mx < menuWidth DIV 2
    THEN mxl := 0;
    ELSE mxl := MIN(Mx - menuWidth DIV 2, rightX-menuWidth);
    END;
    mxh := menuWidth - 1 + mxl;

    deltaY := (maxCommand-command) * menuLineSize + 14;
    IF My < CARDINAL(deltaY) + bottomY
    THEN myl := bottomY
    ELSE myl := MIN(My-CARDINAL(deltaY), topY-menuHeight);
    END;
    myh := menuHeight - 1 + myl;

    menuArea.x := origoX+mxl;
    menuArea.y := origoY+myl;
    BlockTransfer(menuWindow,saveArea,replace,defWindow,menuArea);
    BlockTransfer(defWindow,menuArea,replace,menuWindow,menuSource);

    deltaY := INTEGER(myl) - INTEGER(My) + deltaY;
    MoveMouse(0,deltaY);
  END MenuOn;


  PROCEDURE MenuOff;
    VAR (*  -------  *)
  BEGIN
    InvertCursor;
    BlockTransfer(defWindow,menuArea,replace,menuWindow,saveArea);
  END MenuOff;


  PROCEDURE ReadMB (VAR mb: CARDINAL);
    VAR (*  ------                 *)
      Mx, My: CARDINAL;
  BEGIN
    GetMouse(Mx,My,mb);
    INC(My,lastLineY);
    IF Mx < origoX+SBW-2 THEN
      area := 1;                (* scroll bar *)
    ELSE
      IF mb # 2 THEN
        area := 2;              (* text *)
        IF Mx < leftXminus THEN Mcol := 0;
        ELSE Mcol := (Mx-leftXminus) DIV charSize;
        END;
        McolSel := (Mcol = 0) OR (Mcol = ((Mx-leftX) DIV charSize));
        IF Mcol > columns-1 THEN Mcol := columns-1; McolSel := TRUE; END;
      ELSE
        MenuOn(Mx,My);          (* menu *)
        comm := command;
        REPEAT
          GetMouse(Mx,My,mb);
          IF (mb = 3) AND (HardC IN optionSet) THEN HardCopy; END;
          INC(My,lastLineY);
          IF (Mx<mxl) OR (Mx>mxh)
          OR (My<myl+7) OR (My>myh-8)
          THEN 
            area := 2;
            WITH menuCursor DO
              x := mxl+6;
              y := myl+menuHeight-lineSize-7;
              w := menuWidth-12;
              h := menuLineSize;
            END;
          ELSE 
            area := 0;
          END;
          DrawCursor(area,Mx,My);
        UNTIL mb = 0;
        IF area = 0 THEN
          mb := 2; (* ? wozu ? *)
          command := comm;
        END;
        MenuOff;
      END;
    END;

    Mline := (topY-My) DIV lineSize;
    IF area = 0
    THEN DrawCursor(2,Mx,My);
    ELSE DrawCursor(area,Mx,My);
    END;
  END ReadMB;


  PROCEDURE NewWindowBar (L,mode: CARDINAL): CARDINAL;
    VAR (*  ------------                 *)
      i,l: CARDINAL;
  BEGIN
    i := 0; 
    l := lastLineY-1 + CARDINAL(INTEGER(lines-1)-INTEGER(L))*lineSize;
    WHILE windowbar[i].y # 0 DO INC(i); END;

    WITH windowbar[i] DO
      y := origoY+l;
      bar.y := origoY+l;
      IF mode = 0
      THEN pat := 0FFFFh;
      ELSE pat := 0F0Fh
      END;
      barPat[1] := pat;
    END;
    Replicate(defWindow,bar,invert,barPat);
    RETURN i;
  END NewWindowBar;


  PROCEDURE MoveWindowBar (i,L: CARDINAL);
    VAR (*  -------------              *)
      l: CARDINAL;
  BEGIN
    l := lastLineY-1 + (lines-1-L)*lineSize;
    WITH windowbar[i] DO
      bar.y := y;
      barPat[1] := pat;
      Replicate(defWindow,bar,invert,barPat);
      y := origoY+l;
      bar.y := origoY+l;
    END;
    Replicate(defWindow,bar,invert,barPat);
  END MoveWindowBar;


  PROCEDURE DeleteWindowBar (i: CARDINAL);
  BEGIN (*  ---------------            *)
    WITH windowbar[i] DO
      bar.y := y;
      y     := 0;
      barPat[1] := pat;
    END;
    Replicate(defWindow,bar,invert,barPat);
  END DeleteWindowBar;


  PROCEDURE ShowMsg (s: ARRAY OF CHAR);
  BEGIN (*  -------                 *)
    IF currentCursor.cy < bottomY+cursorHeight THEN
      InvertCursor;
      WriteString(s,message,defWindow,editFont);
      InvertCursor;
    ELSE
      WriteString(s,message,defWindow,editFont);
    END;
  END ShowMsg;


  PROCEDURE ShowChar (ch: CHAR; k: CARDINAL);
  BEGIN (*  --------                      *)
    fNchar.x := fnX + k*charSize;
    fNchar.w := charSize;
    IF currentCursor.cy < bottomY+cursorHeight THEN
      InvertCursor;
      IF ch = BLANK
      THEN Replicate(defWindow,fNchar,erase,blackPat);
      ELSE DisplayChar(defWindow,fNchar,editFont,ch);
      END;
      InvertCursor;
    ELSE
      IF ch = BLANK
      THEN Replicate(defWindow,fNchar,erase,blackPat);
      ELSE DisplayChar(defWindow,fNchar,editFont,ch);
      END;
    END;
  END ShowChar;


  PROCEDURE ShowFileName (fN: ARRAY OF CHAR);
  BEGIN (*  ------------                  *)
    IF currentCursor.cy < bottomY+cursorHeight THEN
      InvertCursor;
      WriteString(fN,filename,defWindow,editFont);
      InvertCursor;
    ELSE
      WriteString(fN,filename,defWindow,editFont);
    END;
  END ShowFileName;


  PROCEDURE SysErr (s: ARRAY OF CHAR);
  BEGIN (*  ------                 *)
    ShowMsg(s);
    Replicate(defWindow,message,invert,blackPat);
    HALT;
  END SysErr;

 
  PROCEDURE SetCaret (l,n: CARDINAL);
  BEGIN (*  --------              *)
    IF caretSet THEN Replicate(defWindow,caret,invert,caretPat); END;

    WITH caret DO
      x := origoX+leftX + n*charSize - 4;
      y := origoY+lastLineY + (lines-1-l)*lineSize;
    END;
    Replicate(defWindow,caret,invert,caretPat);
    caretSet := TRUE;
  END SetCaret;


  PROCEDURE ClearCaret;
  BEGIN (*  ----------  *)
    IF caretSet THEN
      caretSet := FALSE;
      Replicate(defWindow,caret,invert,caretPat);
    END;
  END ClearCaret;


  PROCEDURE Invert (line,fromCol,toCol,pat: CARDINAL);
  BEGIN (*  ------ *)
    WITH selection DO
      x := origoX+leftX + fromCol*charSize;
      y := origoY+lastLineY+1 + (lines-1-line)*lineSize;
      w := (toCol-fromCol+1) * charSize;
      IF pat = 4 THEN h := 2;
      ELSE h := lineSize-2;
      END;
    END;
    Replicate(defWindow,selection,invert,selectPat[pat]);
  END Invert;

 
  PROCEDURE SetMark (i,l,n: CARDINAL);
  BEGIN (*  -------                *)
    IF markSet[i] THEN Replicate(defWindow,mark[i],invert,markPat[i]); END;

    WITH mark[i] DO
      x := origoX+leftX + n*charSize;
      y := origoY+lastLineY + (lines-1-l)*lineSize;
    END;
    Replicate(defWindow,mark[i],invert,markPat[i]);
    markSet[i] := TRUE;
  END SetMark;


  PROCEDURE ClearMark (i: CARDINAL);
  BEGIN (*  ---------            *)
    IF markSet[i] THEN
      markSet[i] := FALSE;
      Replicate(defWindow,mark[i],invert,markPat[i]);
    END;
  END ClearMark;


  PROCEDURE Blink;
  BEGIN (*  ----- *)
    caretSet := NOT caretSet;
    Replicate(defWindow,caret,invert,caretPat);
  END Blink;


  PROCEDURE Clear (VAR x0,x1: CARDINAL);
  BEGIN (*  -----                    *)
    WITH char DO
      x := origoX+leftX + (x0 MOD columns)*charSize;
      y := origoY+lastLineY + (lines-1-x0 DIV columns)*lineSize;
      w := (x1-x0+1) * charSize;
    END;
    Replicate(defWindow,char,erase,blackPat);
    REPEAT
      text[x0] := EMPTY;
      INC(x0);
    UNTIL x0 > x1;
  END Clear;


  PROCEDURE ClearLines (L0,L1: CARDINAL);
    VAR (*  ----------                *)
      L,x0,x1: CARDINAL;
  BEGIN
    x0 := L0*columns; x1 := x0+columns-1;
    FOR L := L0 TO L1 DO 
      Clear(x0,x1);
      INC(x1,columns);
    END;
  END ClearLines;


  PROCEDURE CopyL (from,to: CARDINAL);
    VAR (*  -----                  *)
      x0,x1: CARDINAL;
  BEGIN
    fromline.y := origoY+lastLineY + (lines-1-from)*lineSize;
    toline.y   := origoY+lastLineY + (lines-1-to)*lineSize;
    BlockTransfer(defWindow,toline,replace,defWindow,fromline);

    x1 := to*columns;
    FOR x0 := from*columns TO (from+1)*columns - 1  DO
      text[x1] := text[x0];
      INC(x1);
    END;
  END CopyL;


  PROCEDURE PreviousChar (VAR L,C: CARDINAL): CHAR;
    VAR (*  ------------                  *)
      i,k: CARDINAL;
      ch: CHAR; l: CARDINAL;
  BEGIN
    i := L*columns + C;
    k := C + 1;
    LOOP  (* assumes text not empty *)
      REPEAT 
        IF text[i] # EMPTY THEN 
          C := k - 1;
          RETURN text[i];
        END;
        DEC(k); DEC(i);
      UNTIL k=0;
      k := columns;
      DEC(L);
    END;    
  END PreviousChar;

VAR nrEqual,iL,i1,i3: CARDINAL;
    equal: BOOLEAN;

  PROCEDURE PaintLine (i: CARDINAL);
  BEGIN (*  ---------            *)
    iL := i;
    i1 := iL * columns;
    i3 := i1 + columns-1;
    nrEqual := 0;
    equal := TRUE;
  END PaintLine;

  PROCEDURE PaintCH (CH: CHAR; VAR i: CARDINAL);
  BEGIN (*  -------                          *)
    equal := equal AND (text[i] = CH);
    IF equal THEN 
      INC(nrEqual);
    ELSE
      IF controlCharsAvailable THEN
        text[i] := CH;
      ELSE
        CASE CH OF
          EOF..'~'  : text[i] := CH; |
          200c..205c: text[i] := CH;
          ELSE        text[i] := '?';
        END; (* CASE *)
      END;
    END; (* IF equal *)

    IF (CH=EOL) OR (CH=EOF) THEN
      WHILE i3 > i DO
        text[i3] := EMPTY;
        DEC(i3);
      END;
    END; 

    IF i = i3 THEN
      WITH char DO
        x := origoX+leftX + nrEqual*charSize;
        y := origoY+lastLineY + (lines-1-iL)*lineSize;
        w := (columns - nrEqual)*charSize;
      END;
      IF inWindow THEN
        Replicate(defWindow,char,replace,whitePat);
        INC(i1,nrEqual);
        WHILE i1 <= i DO
          DisplayChar(defWindow,char,editFont,text[i1]);
          INC(i1);
        END;
      ELSE
        REPL(replace,defBMD,ADR(whitePat),char);
        INC(i1,nrEqual);
        WHILE i1 <= i DO
          DCH(defBMD,editFontAddr^,char,text[i1]);
          INC(i1);
        END;
      END;
      i := 0; (* result to Paint *)
    ELSE
      INC(i);
    END;
  END PaintCH;


  PROCEDURE empty (L: CARDINAL): BOOLEAN;
  BEGIN (*  -----            *)
    RETURN text[columns*L] = EMPTY;
  END empty;


  PROCEDURE StopDisplay;
  BEGIN (*  -----------  *)
    Write(FF);
  END StopDisplay;


  PROCEDURE InitEditDisplay;
    VAR (*  ---------------  *)
      i: CARDINAL;
      done: BOOLEAN;
      subBitmap: Bitmap;
  BEGIN
    pict := 'DK.Edit0.PICT';
    barPat[0] := 1;
    blackPat[0] := 1;
    blackPat[1] := 0FFFFh;
    whitePat[0] := 1;
    whitePat[1] := 0;

    WITH cursorPat[0] DO  (* menubox *)
      size := 1;
      bits[1]  := 0FFFFh;
    END;
 
    WITH cursorPat[1] DO  (* double arrow *)
      size := 16;
      bits[1]  :=  1800h;
      bits[2]  :=  3C00h;
      bits[3]  :=  7E00h;
      bits[4]  := 0DB00h;
      bits[5]  :=  9900h;
      bits[6]  :=  1800h;
      bits[7]  :=  1800h;
      bits[8]  :=  1800h;
      bits[9]  :=  1800h;
      bits[10] :=  1800h;
      bits[11] :=  1800h;
      bits[12] :=  9900h;
      bits[13] := 0DB00h;
      bits[14] :=  7E00h;
      bits[15] :=  3C00h;
      bits[16] :=  1800h;
    END;
 
    WITH cursorPat[2] DO  (* arrow *)
      size := 12;
      bits[1]  := 0FC00h;
      bits[2]  := 0F000h;
      bits[3]  := 0F800h;
      bits[4]  := 0FC00h;
      bits[5]  := 0BE00h;
      bits[6]  := 09F00h;
      bits[7]  :=  0F80h;
      bits[8]  :=   7C0h;
      bits[9]  :=   3E0h;
      bits[10] :=   1F0h;
      bits[11] :=   0F0h;
      bits[12] :=    60h;
    END;
 
    WITH caretPat DO
      size := 14;
      bits[1]  := 000h;
      bits[2]  := 000h;
      bits[3]  := 000h;
      bits[4]  := 000h;
      bits[5]  := 000h;
      bits[6]  := 000h;
      bits[7]  := 01800h;
      bits[8]  := 01800h;
      bits[9]  := 03C00h;
      bits[10] := 03C00h;
      bits[11] := 07E00h;
      bits[12] := 07E00h;
      bits[13] := 0FF00h;
      bits[14] := 0FF00h;
    END;
 
    WITH selectPat[0] DO
      size := 13;
      bits[1]  := 0FFFFh;
      bits[2]  := 0FFFFh;
      bits[3]  := 0FFFFh;
      bits[4]  := 0FFFFh;
      bits[5]  := 0FFFFh;
      bits[6]  := 0FFFFh;
      bits[7]  := 0FFFFh;
      bits[8]  := 0FFFFh;
      bits[9]  := 0FFFFh;
      bits[10] := 0FFFFh;
      bits[11] := 0FFFFh;
      bits[12] := 0FFFFh;
      bits[13] := 0FFFFh;
    END;
 
    WITH selectPat[1] DO
      size := 13;
      bits[1]  := 0FFFFh;
      bits[2]  := 0FFFFh;
      bits[3]  := 0FFFFh;
      bits[4]  := 0FFFFh;
      bits[5]  := 0FFFFh;
      bits[6]  := 0FFFFh;
      bits[7]  := 0FFFFh;
      bits[8]  := 0FFFFh;
      bits[9]  := 0FFFFh;
      bits[10] := 0FFFFh;
      bits[11] := 0FFFFh;
      bits[12] :=  3333h;
      bits[13] :=  3333h;
    END;
 
    WITH selectPat[2] DO
      size := 13;
      bits[1]  :=  3333h;
      bits[2]  :=  3333h;
      bits[3]  := 0FFFFh;
      bits[4]  := 0FFFFh;
      bits[5]  := 0FFFFh;
      bits[6]  := 0FFFFh;
      bits[7]  := 0FFFFh;
      bits[8]  := 0FFFFh;
      bits[9]  := 0FFFFh;
      bits[10] := 0FFFFh;
      bits[11] := 0FFFFh;
      bits[12] := 0FFFFh;
      bits[13] := 0FFFFh;
    END;
 
    WITH selectPat[3] DO
      size := 13;
      bits[1]  :=  3333h;
      bits[2]  :=  3333h;
      bits[3]  := 0FFFFh;
      bits[4]  := 0FFFFh;
      bits[5]  := 0FFFFh;
      bits[6]  := 0FFFFh;
      bits[7]  := 0FFFFh;
      bits[8]  := 0FFFFh;
      bits[9]  := 0FFFFh;
      bits[10] := 0FFFFh;
      bits[11] := 0FFFFh;
      bits[12] :=  3333h;
      bits[13] :=  3333h;
    END;
 
    WITH selectPat[4] DO
      size := 2;
      bits[1]  := 0CCCCh;
      bits[2]  := 0CCCCh;
    END;
 
    WITH selectPat[5] DO
      size := 13;
      bits[1]  := 0CCCCh;
      bits[2]  := 0CCCCh;
      bits[3]  :=     0h;
      bits[4]  :=     0h;
      bits[5]  :=     0h;
      bits[6]  :=     0h;
      bits[7]  :=     0h;
      bits[8]  :=     0h;
      bits[9]  :=     0h;
      bits[10] :=     0h;
      bits[11] :=     0h;
      bits[12] :=     0h;
      bits[13] :=     0h;
    END;
 
    WITH selectPat[6] DO
      size := 13;
      bits[1]  := 0CCCCh;
      bits[2]  := 0CCCCh;
      bits[3]  :=     0h;
      bits[4]  :=     0h;
      bits[5]  :=     0h;
      bits[6]  :=     0h;
      bits[7]  :=     0h;
      bits[8]  :=     0h;
      bits[9]  :=     0h;
      bits[10] :=     0h;
      bits[11] :=     0h;
      bits[12] := 0CCCCh;
      bits[13] := 0CCCCh;
    END;

    caret.w := 8;
    caret.h := 14;
    caretSet := FALSE;
 
    WITH markPat[1] DO
      size := 14;
      bits[1]  := 0FF00h;
      bits[2]  := 0FF00h;
      bits[3]  := 0FC00h;
      bits[4]  := 0FC00h;
      bits[5]  := 0F800h;
      bits[6]  := 0F800h;
      bits[7]  := 0F000h;
      bits[8]  := 0F000h;
      bits[9]  := 0E000h;
      bits[10] := 0E000h;
      bits[11] := 0C000h;
      bits[12] := 0C000h;
      bits[13] :=     0h;
      bits[14] :=     0h;
    END;
 
    WITH markPat[2] DO
      size := 14;
      bits[1]  :=     0h;
      bits[2]  :=     0h;
      bits[3]  :=   300h;
      bits[4]  :=   300h;
      bits[5]  :=   700h;
      bits[6]  :=   700h;
      bits[7]  :=  0F00h;
      bits[8]  :=  0F00h;
      bits[9]  :=  1F00h;
      bits[10] :=  1F00h;
      bits[11] :=  3F00h;
      bits[12] :=  3F00h;
      bits[13] := 0FF00h;
      bits[14] := 0FF00h;
    END;

    FOR i := 1 TO 2 DO
      mark[i].w := 8;
      mark[i].h := 14;
      markSet[i] := FALSE;
    END;

    GetDefaultBitmap(defWindow);
    inWindow := IsSubBitmap(defWindow);
    LoadFonts(fontName);
    IF lineSize = menuLineSize THEN EXCL(optionSet,ExoFont); END;

    GetMaxBlock(innerblk,defWindow);
    IF inWindow THEN
      origoX := 0;
      origoY := 0;
    ELSE
      editFontAddr := PToFontFramePointer(editFont);
      CreateSubBitmap(subBitmap,defWindow,innerblk,done);
      defWindow := subBitmap;
      defBMD := PToBMD(defWindow);
      origoX := 2;
      origoY := 2;
    END;
    leftX := SBW+6;
    leftXplus := leftX + charSize DIV 2;
    leftXminus := leftX - charSize DIV 2;
    rightX := innerblk.w - 2*origoX;
    columns := (rightX-leftX-1) DIV charSize;
    bottomY := lineSize+2;
    topY := innerblk.h - 2*origoY;
    lines := (topY-bottomY-1) DIV lineSize;
    lastLineY := topY-lines*lineSize+1;
    IF lines*columns-1 > maxchar THEN HALT; END;

    IF  columns < 36 THEN
      fnX := origoX + leftX;
      fnW := columns*charSize;
      msgX := 0;
      msgW := 0;
    ELSE
      msgX := origoX + leftX;
      msgW := (columns-33)*charSize;
      fnX := msgX + msgW + charSize;
      fnW := 32*charSize;
    END;

    Write(FF); 

    IF inWindow THEN
      Hline(defWindow, 0, bottomY, rightX, 1);
      Vline(defWindow, SBW, bottomY, 1, topY-bottomY);
    ELSE
      Hline(defWindow, 2,  origoY+topY+1,          rightX, 1);
      Hline(defWindow, 2,    origoY+topY,           SBW+2, 1);
      Hline(defWindow, 0, origoY+bottomY, 2*origoX+rightX, 2);
      Hline(defWindow, 0,              0, 2*origoX+rightX, 2);

      Vline(defWindow,             0,              0, 2, 2*origoY+topY);
      Vline(defWindow,    origoX+SBW, origoY+bottomY, 2, topY-bottomY);
      Vline(defWindow, origoX+rightX,              0, 2, 2*origoY+topY);
    END;
    
    menuHeight := (maxCommand+1)*menuLineSize + 14;
    menuWidth := CommandWidth*menuCharSize + 16;

    CreateBitmap(menuWindow, menuWidth, 2*menuHeight, done);
    GetMaxBlock(menuline,menuWindow);
    Replicate(menuWindow,menuline,replace,whitePat);

    Hline(menuWindow, 0, 2*menuHeight-2, menuWidth, 2);
    Hline(menuWindow, 0,     menuHeight, menuWidth, 2);

    Vline(menuWindow,           0, menuHeight, 2, menuHeight);
    Vline(menuWindow, menuWidth-2, menuHeight, 2, menuHeight);

    WITH menuline DO
      x := 7;
      y := 2*menuHeight - 25;
      w := CommandWidth*menuCharSize;
      h := menuLineSize;
    END;

    WriteString("INSERT",menuline,menuWindow,defaultFont);
    DEC(menuline.y,menuLineSize);
    WriteString(" SAVE ",menuline,menuWindow,defaultFont);
    DEC(menuline.y,menuLineSize);
    WriteString("DELETE",menuline,menuWindow,defaultFont);
    DEC(menuline.y,menuLineSize);
    WriteString(" FIND ",menuline,menuWindow,defaultFont);
    DEC(menuline.y,menuLineSize);
    WriteString("WINDOW",menuline,menuWindow,defaultFont);
    DEC(menuline.y,menuLineSize);
    WriteString("CLOSE ",menuline,menuWindow,defaultFont);
 
    FOR i := 0 TO 7 DO windowbar[i].y := 0; END;
    WITH bar DO
      x := SBW+origoX+2;
      w := rightX-SBW-2;
      h := 1;
    END;

    WITH message DO
      x := msgX;
      y := origoY + 1;
      w := msgW;
      h := lineSize;
    END;   

    WITH filename DO
      x := fnX;
      y := origoY + 1;
      w := fnW;
      h := lineSize;
    END;

    WITH fNchar DO
      y := origoY + 1;
      w := charSize;
      h := lineSize;
    END;

    WITH fromline DO
      x := origoX+leftX;
      w := columns * charSize;
      h := lineSize-1;
    END;

    toline := fromline;

    char.h := lineSize-1;

    ClearLines(0,lines-1);

    SetMouseWindow(rightX,lines*lineSize-1);
    currentCursor.on := FALSE;
    DrawCursor(2,rightX DIV 2, topY DIV 2);
    SetMouse(rightX DIV 2, topY DIV 2 - lastLineY);

    IF msgW < 10*charSize THEN ShowFileName("Editor I.11");
    ELSE ShowMsg("Editor I.11");
    END;

    WITH saveArea DO
      x := 0;
      y := 0;
      w := menuWidth;
      h := menuHeight;
    END;

    WITH menuSource DO
      x := 0;
      y := menuHeight;
      w := menuWidth;
      h := menuHeight;
    END;

    WITH menuArea DO
      w := menuWidth;
      h := menuHeight;
    END;

    command := 4; (* window *)
  END InitEditDisplay;

END EditDisplay.
