IMPLEMENTATION MODULE Inspect;  (*Carl Binding; modified by C.J. 3.6.81*)
(* (*$T-*) (*$R-*) *)
  FROM Monitor IMPORT CurrentLevel;
  FROM SYSTEM IMPORT WORD;
  FROM Terminal IMPORT Read, BusyRead, WriteString, WriteLn;
  FROM CardinalIO IMPORT ReadOct;
  FROM WindowHandler IMPORT CreateWindow, Window, FreeLines, CloseWindow, Clear,
    Replicate, BlockDescriptor, Mode, WriteChar, PutOnTop,
    WindowSignal, SignalSet, IgnoreWindowSignal, FullScreen;
  FROM CursorRelations IMPORT
    Inside, DownCharPos, RightCharPos, UpDotPos, RightDotPos;
  FROM CursorStuff IMPORT TrackCursor, MenuSelection;
  FROM WindowDialogue IMPORT 
    InstallWindow, CreateInstallWindow, RemoveWindow;
  FROM Screen IMPORT CharWidth;
  FROM OutWindow IMPORT 
    WriteC, WriteI, WriteO;

  FROM DumpFileHandler IMPORT Mem;



  TYPE DispMode = (hex, oct, int, card, byt, cha);  (*display mode of core*)

  CONST
    EOL = 36C; 
    maxcommands = 8;
    mincommands = 5;
    maxmenulen = 100;

  VAR 
    corewindow, disp: Window;
    coreViewLevel: CARDINAL;
    winx, winy, winw, winh: CARDINAL;

    addr: CARDINAL;          (*startaddress of memory extract*)
    md: DispMode;            (*display mode of the memory extract*)
    wordsperline: CARDINAL; 
    linePos: CARDINAL;       (*position of flip line*)
    insideHeight: CARDINAL;                       
    nrLine: CARDINAL;

    black: RECORD size1, pat177777B: CARDINAL END;

    command: ARRAY [mincommands..maxcommands] OF PROC;
    menu: ARRAY [0..maxmenulen] OF CHAR;
    menulength, commandcount: CARDINAL;
    specAddr: CARDINAL; 


  PROCEDURE Installate(a: ARRAY OF CHAR; p: PROC);
    VAR i, high: CARDINAL;
        remove: ARRAY [0..7] OF CHAR;
  BEGIN
    high := HIGH(a);
    IF (commandcount <= maxcommands) AND (menulength+high+8 < maxmenulen) THEN
      i := 0;
      WHILE (i <= high) AND (a[i] # 0C) DO
        menu[menulength] := a[i];
        INC(i); INC(menulength);
      END;
      remove := "| remove";
      FOR i := 0 TO 7 DO menu[menulength+i] := remove[i] END;
      menu[menulength+8] := 0C; INC(menulength);
      command[commandcount] := p;
      INC(commandcount);
    END
  END Installate;


  PROCEDURE CalledAddr(): CARDINAL;
  BEGIN
    RETURN specAddr
  END CalledAddr;


  PROCEDURE SpecialProc(n: CARDINAL);
     VAR done: BOOLEAN;
  BEGIN
    IF (n >= mincommands) AND (n < commandcount) THEN
      RandomAddr(specAddr, TRUE, done);
      IF done THEN command[n] END;
    ELSIF n = commandcount THEN
      RemoveWindow(corewindow);
      CloseWindow(corewindow)
    END
  END SpecialProc;


  PROCEDURE PaintFlipLine;
    VAR FlipLineBlock: BlockDescriptor;
  BEGIN
    FlipLineBlock.x := linePos;
    FlipLineBlock.y := 0;
    FlipLineBlock.w := 1;
    FlipLineBlock.h := insideHeight;
    Replicate(corewindow, FlipLineBlock, replace, black); 
  END PaintFlipLine;


  PROCEDURE DisplayCore(laddr: CARDINAL; lmd: DispMode);
    VAR i, j: CARDINAL;

    PROCEDURE DisplayByte(VAR w: Window; wor: WORD);
      VAR i, d, card, lbyte, hbyte: CARDINAL;
    BEGIN card := CARDINAL(wor); d := 100B;
      hbyte := card DIV 400B; lbyte := card MOD 400B;
      REPEAT 
        i := hbyte DIV d MOD 10B;
        WriteChar(w, CHAR(i+ORD('0')));
        d := d DIV 10B
      UNTIL d=0;
      WriteChar(w, " "); d := 100B;
      REPEAT
        i := lbyte DIV d MOD 10B;
        WriteChar(w, CHAR(i+ORD('0')));
        d := d DIV 10B
      UNTIL d=0;
    END DisplayByte;

    PROCEDURE DisplayChar(VAR w: Window; wor: WORD);
      VAR card, hbyte, lbyte: CARDINAL;
    BEGIN card := CARDINAL(wor);
      hbyte := card DIV 400B; lbyte := card MOD 400B;
      WriteChar(w, " ");
      IF (hbyte < 40B) OR (hbyte > 177B) THEN WriteChar(w, ".");
      ELSE WriteChar(w, CHAR(hbyte)) END;
      IF (lbyte < 40B) OR (lbyte > 177B) THEN WriteChar(w, ".");
      ELSE WriteChar(w, CHAR(lbyte)) END;
    END DisplayChar;

    PROCEDURE DisplayHex(VAR w: Window; wor: WORD);
      VAR card, d, i: CARDINAL;
    BEGIN WriteChar(w, " ");
      d := 1000H; card := CARDINAL(wor);
      REPEAT
        i:= card DIV d MOD 10H;
        IF (i >= 0) AND (i <=9) THEN WriteChar(w, CHAR(i+ORD('0')))
        ELSE WriteChar(w, CHAR(i-10+ORD('A'))) 
        END;
        d := d DIV 10H
      UNTIL d= 0;
    END DisplayHex;

  BEGIN (*DisplayCore *)
    Clear(corewindow);
    PaintFlipLine;
    addr := laddr; md := lmd;
    FOR i:= 0 TO nrLine DO 
      WriteO(corewindow, laddr, 7);
      WriteChar(corewindow, " "); 
      FOR j:= 1 TO wordsperline DO
        WriteChar(corewindow, " ");
        CASE md OF
          hex:  DisplayHex(corewindow, Mem(laddr))         |
          oct:  WriteO(corewindow, Mem(laddr), 7)          |
          int:  WriteI(corewindow, INTEGER(Mem(laddr)), 7) |
          card: WriteC(corewindow, Mem(laddr), 6)          |
          byt:  DisplayByte(corewindow, Mem(laddr))        |
          cha:  DisplayChar(corewindow, Mem(laddr)) 
        END;(*case*)
        IF laddr = 177777B THEN RETURN END;
        INC(laddr)
      END;(*FOR j *)
      IF i <> nrLine THEN WriteChar(corewindow, EOL) END;
    END;(*FOR i *)
  END DisplayCore;


  PROCEDURE RandomAddr(VAR faddr: CARDINAL; newPos: BOOLEAN; VAR done: BOOLEAN);
    (*to select the address of any word of the view *)

    VAR downPos, rightPos, offset: CARDINAL;

    PROCEDURE SelectOldWord(VAR done: BOOLEAN);
    BEGIN 
      done := Inside(corewindow);
      IF done THEN 
        downPos := DownCharPos(corewindow);
        rightPos := RightCharPos(corewindow);
      END;
    END SelectOldWord;

    PROCEDURE SelectWord(VAR done: BOOLEAN);
      VAR but: BITSET;
    BEGIN 
      WriteString('select a core word'); WriteLn;
      done := (TrackCursor()<>0) AND Inside(corewindow);
      IF done THEN 
        downPos := DownCharPos(corewindow);
        rightPos := RightCharPos(corewindow);
      ELSE
        WriteString('-- not selected'); WriteLn;
      END;
    END SelectWord;

  BEGIN (*RandomAddr *)
    faddr := addr;
    IF newPos THEN  
      SelectWord(done);
    ELSE
      SelectOldWord(done)
    END;
    IF NOT done THEN RETURN END;
    IF rightPos >= 9 THEN rightPos := rightPos-9  (*compensate address*)
    ELSE 
      WriteString('-- address word selected'); WriteLn;
      done := FALSE; RETURN
    END;
    CASE md OF
      oct:  rightPos := rightPos DIV 8 |
      hex:  rightPos := rightPos DIV 6 |
      byt:  rightPos := rightPos DIV 8 |
      card: rightPos := rightPos DIV 7 |
      cha:  rightPos := rightPos DIV 4 |
      int:  rightPos := rightPos DIV 8 
    END;
    IF (rightPos < wordsperline) AND (downPos <= nrLine) THEN  
      offset := downPos*wordsperline+rightPos;
      IF 177777B-offset > faddr THEN
        faddr := faddr + offset
      ELSE faddr := 177777B
      END
    ELSE
      WriteString('-- bad word selected'); WriteLn;
      done := FALSE
    END;
  END RandomAddr;


  PROCEDURE Show(startaddr: CARDINAL);
  BEGIN 
    addr := startaddr; 
    IF coreViewLevel = 177777B THEN 
      InitInspect
    ELSE
      DisplayCore(addr, md)
    END
  END Show;


  PROCEDURE CoreViewHandler(corewindow: Window; callReason: CARDINAL);
    VAR ch: CHAR;
        selection: CARDINAL;

    PROCEDURE Scrollup;
      VAR offset: CARDINAL;
    BEGIN
      offset := DownCharPos(corewindow)*wordsperline;
      IF (177777B-offset)>=addr THEN addr := addr + offset
      ELSE addr := 177777B END;
      DisplayCore(addr, md) 
    END Scrollup;
      
    PROCEDURE Flip;
    BEGIN
      addr := (insideHeight-UpDotPos(corewindow)) * (177777B DIV insideHeight);
      DisplayCore(addr, md) 
    END Flip;

    PROCEDURE Scrolldown;
      VAR offset: CARDINAL;
    BEGIN
      offset := DownCharPos(corewindow);
      IF offset>nrLine THEN offset := 0
      ELSE offset := (nrLine-offset)*wordsperline
      END;
      IF addr>=offset THEN addr := addr - offset 
      ELSE addr := 0 
      END;
      DisplayCore(addr, md)
    END Scrolldown;
 
    PROCEDURE TypeAddr;
      VAR ch: CHAR;
    BEGIN
      WriteString('enter adress: ');
      ReadOct(addr); Read(ch); WriteLn;
      DisplayCore(addr, md) 
    END TypeAddr;

    PROCEDURE Deferred(ask: BOOLEAN);
      VAR done: BOOLEAN;
    BEGIN
      RandomAddr(addr, ask, done);
      IF done THEN
        addr := Mem(addr);
        DisplayCore(addr, md) 
      END
    END Deferred;

    PROCEDURE SelectMode;
      VAR ch: CHAR; oldMode: DispMode;
    BEGIN
      oldMode := md;
      CASE MenuSelection("* MODE| octal| hex| byte| char| card| int") OF
        0: Read(ch) |
        2: md := oct |
        3: md := hex |
        4: md := byt |
        5: md := cha |
        6: md := card |
        7: md := int
        ELSE 
      END;
      IF md<>oldMode THEN DisplayCore(addr, md) END     
    END SelectMode;

  BEGIN (*CoreViewHandler*)
    IF callReason IN {1..3} THEN 
      IF Inside(corewindow) AND (RightDotPos(corewindow)<=linePos) THEN
        IF callReason=1 THEN Scrollup 
        ELSIF callReason=3 THEN Scrolldown 
        ELSE Flip   
        END
      ELSIF callReason=1 THEN Deferred(FALSE)
      ELSE 
        PutOnTop(corewindow);
        selection := MenuSelection(menu);
        CASE selection OF
          2              : Deferred(TRUE) |
          3              : TypeAddr |
          4              : SelectMode |
          5..maxcommands : SpecialProc(selection)
          ELSE 
        END;
      END;
    ELSIF callReason=5 THEN
      CloseWindow(corewindow)
    END
  END CoreViewHandler;


  PROCEDURE SetGlobals;
    VAR l: CARDINAL;
  BEGIN
    Clear(corewindow);
    insideHeight := corewindow^.innerblk.h;
    nrLine := FreeLines(corewindow);
    l := CharWidth(corewindow^.font, "0"); (*character size*)
    linePos := 8*l+4;
    l := corewindow^.innerblk.w DIV l; (*characters per line*)
    IF l>17 THEN
      DEC(l, 17);                      (*compensate address and first dataword*)
      l := l DIV 8 + 1;                (*words and add first dataword*)
    ELSE
      l := 0; linePos := 0;
    END;
    IF l>=4 THEN wordsperline := l DIV 4 * 4;
    ELSE wordsperline := l
    END;
  END SetGlobals;


  PROCEDURE ResetCoreView;
  BEGIN
    DisplayCore(addr, md)
  END ResetCoreView;


  PROCEDURE CoreViewControl(w: Window; ws: WindowSignal);
  BEGIN
    IF ws IN SignalSet{moved, changed, fontchanged, opened} THEN 
      SetGlobals; ResetCoreView 
    ELSIF ws=redraw THEN ResetCoreView
    ELSIF ws=closed THEN
       coreViewLevel := 177777B;
       winx := w^.outerblk.x;
       winy := w^.outerblk.y;
       winw := w^.outerblk.w;
       winh := w^.outerblk.h;
    END;
  END CoreViewControl;


  PROCEDURE InitInspect;
    VAR done: BOOLEAN;
  BEGIN
    IF coreViewLevel # 177777B THEN
      PutOnTop(corewindow)
    ELSE
      CreateWindow(corewindow, winx, winy, winw, winh,
                   "   memory", FALSE, CoreViewControl, done);
      IF done THEN
        InstallWindow(corewindow, {1..5, 15}, CoreViewHandler,
                      SignalSet{moved, changed, fontchanged}, done);
        IF NOT done THEN
          CloseWindow(corewindow)
        ELSE
          coreViewLevel := CurrentLevel()
        END
      END;
    END
  END InitInspect;


  PROCEDURE TerminateInspect;
  BEGIN
    IF coreViewLevel >= CurrentLevel() THEN
      coreViewLevel := 177777B
    END;
  END TerminateInspect;


BEGIN
  disp := FullScreen();
  WITH disp^.outerblk DO
    winx := 318; winy := 440; winw := 430; winh := 90;
    IF w<768 THEN winx := 190; winy := 664 END;
    IF winh>h THEN winh := h DIV 4 END;
  END;
  md := oct; addr := 0; 
  black.size1 := 1;
  black.pat177777B := 177777B;
  menu := "MEMORY| ind| addr| mode| remove";
  commandcount := 5; menulength :=24;
  coreViewLevel := 177777B;
END Inspect.
