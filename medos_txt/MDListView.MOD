IMPLEMENTATION MODULE MDListView;  (* C. Binding,
                                      minor modifications by Ch.J.; HK.B. 10.6.81 *)
  (* module should be redesigned; postboned, because I dream from using the "standard"
     editor to implement the list-view *)
(*$T-*) (*$R-*)
  IMPORT Terminal;
  FROM CardinalIO IMPORT ReadOct;
  FROM FileSystem IMPORT 
    File, Lookup, SetRead, Reset, ReadChar, Response,
    Close, SetPos, GetPos, Length;
  FROM WindowHandler IMPORT OpenWindow, Window, FreeLines, PutOnTop,
    CloseWindow, CreateWindow, WindowSignal, SignalSet, WriteChar, FullScreen;
  FROM CursorRelations IMPORT
    Inside, DownCharPos, RightCharPos, UpDotPos, RightDotPos;
  FROM CursorStuff IMPORT MenuSelection;
  FROM WindowDialogue IMPORT 
    InstallWindow, RemoveWindow;
  IMPORT WindowHandler; (*GetPos <> FileSystem.Getpos*)
  FROM OutWindow IMPORT Write, WriteS, WriteC, WriteO, WriteLn;

  FROM MDUtility IMPORT ResetWindow;
  FROM MDFileControl IMPORT
    FileType, lstFile, lstOpen, OpenFile;


  CONST 
      EOL = 36C;
      Llength = 80;                 (*length of textline*)


  VAR
    listwindow, disp: Window;
    whdone: BOOLEAN;                  (*for OpenWindow*)
    winx, winy, winw, winh: CARDINAL;
    endtext: BOOLEAN;                 (*end of listfile*)
    ch: CHAR;                         (*of listfile; NEVER terminal*)
    lineNr, linePC: CARDINAL;         (*present line identification*)
    filelength:
      RECORD                          (*length of listfile in blocks and bytes*)
        block, byte: CARDINAL
      END;
    textlength: CARDINAL;             (*length of listfile in nr of lines*)
    codelength: CARDINAL;             (*length of code of the listing*)
    line: ARRAY[0..Llength] OF CHAR;
    nrLines: CARDINAL;                (*number of lines in the window*)

    firstVisibleLine: CARDINAL;       (*set by the display procedure*)
    viewActive: BOOLEAN;


PROCEDURE SkipBackListFile(nr: CARDINAL);
  (*to jump back on listfile the equivalent of nr bytes*)
  VAR lblock, lbyte: CARDINAL;
 BEGIN
  IF endtext THEN
    endtext := FALSE; ch:= ' '
  END;
  GetPos(lstFile, lblock, lbyte);
  IF lbyte > nr THEN
    lbyte:= lbyte  - nr;
    SetPos(lstFile, lblock, lbyte);
  ELSIF (lblock > 0) THEN
    DEC(lblock);
    lbyte:= 177777B - nr;
    SetPos(lstFile, lblock, lbyte);
  ELSE
    Reset(lstFile); SetRead(lstFile);
    endtext := FALSE; ch:= ' '
  END;
END SkipBackListFile;


PROCEDURE RepositionListFile(rellength, totlength, marge: CARDINAL);
  (*to implement the flip command for long list files (< 100B blocks)*)
  VAR rtl: CARDINAL;          (*relativ textlength*)
      lblock, lbyte, offset: CARDINAL;
BEGIN
  endtext := FALSE;
  WITH filelength DO
    (*compress block and byte in one word if necessary*)
    IF block < 1 THEN
      rtl:= byte
    ELSIF block < 10B THEN
      rtl:= block * 20000B + byte DIV 10B
    ELSIF block < 100B THEN
      rtl:= block * 2000B + byte DIV 100B
    ELSE 
      rtl:= 0;
      Terminal.WriteString('-- file too long'); Terminal.WriteLn
    END;
    (*calulate the offset*)
    offset:= rellength * (rtl DIV totlength);   (*0 <= offset <= 177777B*)
    (*restore lblock and lbyte out of one word*)
    IF block < 1 THEN
      lblock:= 0; lbyte:= offset
    ELSIF block < 10B THEN
      lblock:= offset DIV 20000B;
      lbyte:= (offset MOD 20000B) * 10B
    ELSIF block < 100B THEN
      lblock:= offset DIV 2000B;
      lbyte:= (offset MOD 2000B) * 100B
    END;
    (*reposition file*)
    IF block = lblock THEN  (*possibility of eof..*)
      IF byte > marge DIV 2 THEN    (*against underflow..*)
        IF lbyte > byte - marge DIV 2 THEN
          IF lbyte > marge DIV 2 THEN
            lbyte:= lbyte - marge DIV 2
          ELSIF lblock > 0 THEN
            lblock:= block - 1;
            lbyte:= 177777B - marge DIV 2
          ELSE lbyte:= 0
          END;
        END;
      ELSE lbyte:= 0
      END;
    END;
    SetPos(lstFile, lblock, lbyte);
  END;
END RepositionListFile;
    

  PROCEDURE Nextch;
    (*read next character from file listfile, set endtext if EOF encountered*)
  BEGIN 
    ReadChar(lstFile, ch);  
    endtext := lstFile.eof 
  END Nextch;


PROCEDURE NextLine;
  (*skips to beginning of next line and reads LineNr and LinePC*)
BEGIN 
  (*skip to beginning of next line*)
  WHILE (ch<>EOL) AND NOT endtext DO Nextch END;
  (*skip to LineNr*)
  WHILE NOT (((ch >= '0') AND (ch <= '9')) OR endtext) DO Nextch END;
  (*get LineNr*)
  IF NOT endtext THEN lineNr := 0 END;
  WHILE ((ch >= '0') AND (ch <= '9')) AND NOT endtext DO
    lineNr := lineNr*10 + (ORD(ch)-ORD('0'));
    Nextch;
  END;
  (*skip to LinePC*)
  WHILE NOT (((ch >= '0') AND (ch <= '7')) OR endtext) DO Nextch END;
  (*get LinePC*)
  IF NOT endtext THEN linePC := 0 END;
  WHILE ((ch >= '0') AND (ch <= '7')) AND NOT endtext DO
    linePC := linePC*10B + (CARDINAL(ch)-CARDINAL('0'));
    Nextch;
  END;
END NextLine;


PROCEDURE GetLine;
  (*read line into buffer*)
  VAR i: CARDINAL;
BEGIN 
  IF NOT endtext THEN
    i:=0; 
    (*read to end of line*)
    LOOP
      IF (ch=EOL) OR (i>Llength) (*OR endtext*) THEN
        IF i<=Llength THEN line[i] := 0C END;
        EXIT
      END; 
      line[i] := ch; Nextch;
      INC(i);
    END
  END;
END GetLine;
 

  PROCEDURE InitListFile;
  BEGIN 
    Reset(lstFile); SetRead(lstFile);
    IF lstFile.res = done THEN
      WITH filelength DO
        Length(lstFile, block, byte)
      END;
      RepositionListFile(9, 10, 200);
      Nextch;
      codelength := 0;
      REPEAT NextLine; 
        IF codelength<linePC THEN
          codelength := linePC
        END;
      UNTIL endtext;
      textlength := lineNr; 
      lineNr := 0; linePC := 0;
      Reset(lstFile); SetRead(lstFile);
    END;
    endtext := FALSE; ch := ' '; 
  END InitListFile;


  PROCEDURE ShowList(mod: CARDINAL; pc: CARDINAL);
    VAR new: BOOLEAN;
  BEGIN
    IF NOT whdone THEN RETURN END;
    OpenFile(mod, lstfile, new);
    viewActive := lstOpen;
    IF viewActive THEN
      InitListFile;
      ResetWindow(listwindow);
      ShowAtPC(pc)
    ELSE
      ResetWindow(listwindow);
      WriteS(listwindow, "   no listing file");
    END;
  END ShowList;

   
PROCEDURE DisplayLine;
  (*displays a line into ListWindow*)
BEGIN
  WriteC(listwindow, lineNr, 6);
  Write(listwindow, " ");
  WriteO(listwindow, linePC, 7);
  WriteS(listwindow, line);
END DisplayLine;


PROCEDURE SearchInList(value: CARDINAL; kind: BOOLEAN);
  (*to search value in listing either linePC or lineNr*)
  VAR ug, og, totpos, pos, prec: CARDINAL;
BEGIN
  InitListFile; 
  IF kind THEN 
    totpos := codelength;
    prec := 20
  ELSE 
    totpos := textlength;
    prec := 2
  END;
  IF totpos<1 THEN totpos := 1 END;
  ug := 0; 
  og := totpos; 
  REPEAT
    RepositionListFile((og + ug) DIV 2, totpos, 100);
    Nextch; NextLine;
    IF kind THEN pos := linePC ELSE pos := lineNr END;
    IF pos < value THEN
      ug := (og + ug) DIV 2
    ELSE
      og := (og + ug) DIV 2
    END;
  UNTIL (og - ug) <= prec;
  SkipBackListFile(nrLines*Llength DIV 2); Nextch;
END SearchInList;


PROCEDURE ShowAtLine(l: INTEGER);
  VAR i: CARDINAL;
      nr: CARDINAL;
BEGIN 
  IF l>=0 THEN nr := l ELSE nr := 0 END;
  IF nr>=textlength THEN 
    IF textlength>nrLines THEN nr := textlength-nrLines+1
    ELSE nr := 0 END
  END;
  firstVisibleLine := nr;
  ResetWindow(listwindow);
  (*searches correct line*)
  SkipBackListFile(nrLines*Llength*2);
  Nextch;
  REPEAT NextLine UNTIL (lineNr>=nr) OR endtext;
  (*displays lines further*)
  IF NOT endtext THEN GetLine END;
  i := 0;
  LOOP
    IF endtext THEN EXIT END;
    DisplayLine;
    INC(i);
    IF i>=nrLines THEN EXIT END;
    WriteLn(listwindow);
    NextLine; GetLine;
  END;
END ShowAtLine;


PROCEDURE ShowAtPC(pc: CARDINAL);
BEGIN
  SearchInList(pc, TRUE);
  REPEAT NextLine UNTIL (linePC >= pc) OR endtext;
  IF endtext THEN
    Terminal.WriteString('-- pc value not found'); Terminal.WriteLn;
  END;
  IF lineNr>(nrLines DIV 2) THEN DEC(lineNr,nrLines DIV 2)  
  ELSE lineNr := 0 
  END;
  ShowAtLine(lineNr)
END ShowAtPC; 


PROCEDURE ListHandler(lw: Window; reason: CARDINAL);

  PROCEDURE PositionInListing;

    PROCEDURE Scrollup;
    BEGIN
      ShowAtLine(firstVisibleLine+DownCharPos(listwindow)) 
    END Scrollup;

    PROCEDURE Flip;
      VAR insideHeight: CARDINAL;
    BEGIN
      insideHeight := listwindow^.innerblk.h;
      RepositionListFile(insideHeight-UpDotPos(listwindow), insideHeight, nrLines*Llength);
      Nextch; NextLine;
      ShowAtLine(lineNr)
    END Flip;

    PROCEDURE Scrolldown;
      VAR up: INTEGER;
    BEGIN
      up := INTEGER(nrLines)-INTEGER(DownCharPos(listwindow))-1;
      ShowAtLine(INTEGER(firstVisibleLine)-up)
    END Scrolldown;

  BEGIN (*PositionInListing*)
    CASE reason OF
      1: Scrollup |
      2: Flip|
      3: Scrolldown 
    ELSE (*error*)
    END
  END PositionInListing;


  PROCEDURE SearchLine;
    VAR l: CARDINAL;

    PROCEDURE ReadCard(VAR l: CARDINAL);
      VAR c: CARDINAL; ch: CHAR; 
    BEGIN
      c := 0;
      Terminal.Read(ch); 
      WHILE (c<6000) AND (ch<="9") AND (ch>="0") DO
        Terminal.Write(ch);
        c := 10*c + (ORD(ch)-ORD("0"));
        Terminal.Read(ch)
      END;
      l := c
    END ReadCard;

  BEGIN (*SearchLine *)
    Terminal.WriteString('enter Line: ');
    ReadCard(l); Terminal.WriteLn;
    ShowAtLine(ORD(l))
  END SearchLine;               
  

  PROCEDURE SearchPc;
    VAR ch: CHAR; pc: CARDINAL;
  BEGIN
    Terminal.WriteString('enter pc: ');
    ReadOct(pc); Terminal.Read(ch); Terminal.WriteLn;
    ShowAtPC(pc)
  END SearchPc;               
  
BEGIN (*ListHandler *) 
  IF viewActive THEN
    IF Inside(listwindow) AND (RightDotPos(listwindow)<=16) THEN
      PositionInListing;
    ELSE
      PutOnTop(listwindow);
      CASE MenuSelection(" LIST| line| pc") OF
        2: SearchLine|
        3: SearchPc
        ELSE
      END
    END
  ELSE reason := MenuSelection("NO LIST FILE|");
  END
END ListHandler;


  PROCEDURE ListController(w: Window; s: WindowSignal);
  BEGIN
    IF s IN SignalSet{redraw, moved..opened, enddefault} THEN
      ResetWindow(listwindow);
      nrLines := FreeLines(listwindow)+1;
      IF viewActive THEN
        ShowAtLine(firstVisibleLine) 
      END
    END
  END ListController;


  PROCEDURE TerminateListView;
  BEGIN
    (* not used *)
  END TerminateListView;


BEGIN (*ListView*)
  viewActive := FALSE;
  disp := FullScreen();
  WITH disp^.outerblk DO
    winx := 5; winy := 425; winw := w-10; winh := 165;
    IF w<768 THEN winy := 649; winh := 179 END;
    IF winh>h THEN winh := h DIV 3 END;
  END;
  CreateWindow(listwindow, winx, winy, winw, winh, 
    "   program",
    FALSE, ListController, whdone);
  IF whdone THEN
    ResetWindow(listwindow);
    nrLines := FreeLines(listwindow)+1;
    InstallWindow(listwindow,
      {1..4}, ListHandler,
      SignalSet{moved, changed, fontchanged}, whdone)
  END;
  IF NOT whdone THEN
    Terminal.WriteString("list window not created"); Terminal.WriteLn
  END;
END MDListView.

