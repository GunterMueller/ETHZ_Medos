MODULE Edit; (* vs I.11                             NW 15.1.80, WW 5.7.83
       ====

       module overview:

         +-----------------------------------------+
         |                Display                  |
         +-----------------------------------------+
           |   |                          |      |
           |   |                          |      |
           |   |  +-------+   +-------+   |      |
           |   |  |Storage|   |   FS  |   |      |
           |   |  +-------+   +-------+   |      |
           |   |      |           |       |      |
           |   +---+  |           |       |      |
           |   |   |  |           |       |      |
           |   |   v  v           v       v      |
           |   | +-------+   +-----------------+ |
           |   | | Heap  |   |      Files      | |
           |   | +-------+   +-----------------+ |
           |   |   |   |       |     |   |   |   |
           |   |   |   |       |     |   |   |   |
           |   |   |   v       v     |   |   v   v
           |   |   | +-------------+ |   | +-----------+ 
           |   |   | |  Documents  | |   | |   Input   |
           |   |   | +-------------+ |   | +-----------+   
           |   |   |        |        |   |       |
           |   |   |        |        |   |       |
           |   v   v        v        v   |       |
           | +-------------------------+ |       |
           | |         Windows         | |       |
           | +-------------------------+ |       |
           |              |              |       |
           |              |              |       |
           v              v              v       v
       +---------------------------------------------+
       |                    Edit                     |
       +---------------------------------------------+
*)

  FROM UserProfile IMPORT
    LookupUserProfile, CloseUserProfile, SetReadPos, SetWritePos,
    ReadItem, WriteGroupId, WriteItemId, WriteItem;
  FROM EditFonts IMPORT
    controlCharsAvailable;
  FROM EditDisplay IMPORT
    fontName, command, area, Options, OptionSET, optionSet, StopDisplay,
    ShowFileName, ShowChar, ShowMsg;
  FROM EditFiles IMPORT
    replay, FileNo, OpenFile, CloseFiles, BkSwitch, BkSave,
    learning, macro, InitLearning, InitMacro;
  FROM EditInput IMPORT
    BusyRead, ReadCh, ReadMouse, ReadKey, ReadAgain, pendingMsg,
    Wait0Button, WatchButtons, ReadString, ReadOct, ReadFileName,
    InitEditInput;
  FROM FileNames IMPORT
    Identifiers, IdentifierPosition;
  FROM EditWindows IMPORT
    TraceCursor, selected, Deselect, StartSelection, ContinueSelection,
    StopSelection, ScrollUp, ScrollDown, Flip, windowCount,
    SetBar, RemoveBar, LetBar, LastLine, MoveBar, windowOK,
    WindowType, GetTypeAndName, AlreadyWritten, FileNameNew,
    OpenWindow, CloseWindow,  ClearDocument, RemoveDocument, OpenDocument,
    PutDocument, BackupDocument, Backspace, Insert, InsertLine,
    InsertSection, DeleteSection, SaveSection, ReadBuffer, Find,
    InitEditWindows;

  CONST
    NULL    = 0c;
    TAB     = 11c;
    FF      = 14c;
    OCT     = 17c;
    HELP    = 23c;
    ESC     = 33c;
    EOF     = 34c;
    GS      = 35c;
    EOL     = 36c;
    BLANK   = 40c;
    DEL     = 177c;
    StringLength = 50;
    FileNameLength = 32;

  TYPE
    String = ARRAY [0..StringLength-1] OF CHAR;
    FileName = ARRAY [0..FileNameLength-1] OF CHAR;

  VAR
    ch, stop        : CHAR;
    endOfGroup, ok  : BOOLEAN;
    windowType      : WindowType;
    item, i,
    mb, length,
    helpLength      : CARDINAL;
    defaultName,
    fN, outputN     : FileName;
    SearchString, 
    helpStr         : String;
    id, value       : ARRAY [0..29] OF CHAR;
    lastAction      : CARDINAL;


  PROCEDURE ShowError (e: CARDINAL);
    VAR
      str: String;
  BEGIN
    CASE e OF
    0: Concatenate(fN," not found",str);
       ShowMsg(str); |
    1: ShowMsg("too many files open"); |
    2: ShowMsg("this file already has been written"); |
    3: ShowMsg("file too long");|
    4: ShowMsg("split window: no space"); |
    5: ShowMsg("create document: no space"); |
    6: ShowMsg("[only Y for writing the file, N else]"); |
    7: ShowMsg("this document already has been written"); |
    8: ShowMsg("this file already exists"); |
    9: Concatenate(SearchString," not found",str);
       ShowMsg(str); |
    10:ShowMsg("no selection"); |
    11:ShowMsg("file protected");
    END; 
    pendingMsg := TRUE;
  END ShowError;

  PROCEDURE ShowState (s: CARDINAL);
    VAR
      str: String;
  BEGIN
    CASE s OF
    0: ShowMsg("ready"); |
    1: Concatenate("old str = ",SearchString,str);
       ShowMsg(str); |
    2: Concatenate("searching ",SearchString,str);
       ShowMsg(str); |
    3: |
    4: ShowMsg("move bar"); |
    5: ShowMsg("split window"); |
    6: ShowMsg("create document"); |
    7: ShowMsg("writing"); |
    8: ShowMsg("select"); |
    9: ShowMsg("position"); |
    10: ShowMsg("set caret");
    END;
  END ShowState;

  PROCEDURE ShowDialog (d: CARDINAL);
  BEGIN
    CASE d OF
    0: ShowMsg("read which file? [RETURN=new document]"); |
    1: ShowMsg("[Button1=set caret; B2=get the menu; B3=select]"); |
    2: ShowMsg("[ESC=stop the replay; any other key=continue]"); |
    3: ShowMsg("find what? [B1=find old string; ?=show old string]"); |
    4: ShowMsg("[B1=move bar/split window; B3=create document]"); |
    5: ShowMsg("close which window? [B1]"); |
    6: ShowMsg("write the document? [Y/N]"); |
    7: ShowMsg("what filename? [RETURN=backup input file]"); |
    8: ShowMsg("exit without writing the document? [Y/N]");  |
    9: ShowMsg("read which file?");  |
    10: ShowMsg("what filename?");
    END;
  END ShowDialog;

  PROCEDURE ShowLastAction;
  BEGIN
    CASE lastAction OF
    0: ShowMsg("open document"); |
    1: ShowMsg("copy"); |
    2: ShowMsg("insert"); |
    3: ShowMsg("save"); |
    4: ShowMsg("delete"); |
    5: ShowMsg("escape"); |
    6: ShowMsg("find"); |
    7: ShowMsg("split window"); |
    8: ShowMsg("close window"); |
    9: ShowMsg("scroll up"); |
    10: ShowMsg("flip"); |
    11: ShowMsg("scroll down"); |
    12: ShowMsg("set mark"); |
    13: ShowMsg("select"); |
    14: ShowMsg("replay"); |
    15: ShowMsg("execute macro"); |
    16: ShowMsg("move bar"); |
    17: ShowMsg("learning"); |
    18: ShowMsg("stop learning"); |
    19: ShowMsg("keyboard input"); |
    20: ShowMsg("end of macro");
    END;
    pendingMsg := TRUE;
  END ShowLastAction;
 
  PROCEDURE Concatenate (s1,s2: ARRAY OF CHAR; VAR s3: ARRAY OF CHAR);
    VAR (*  -----------                                            *)
      k,k2,high,high2,high3: CARDINAL;
  BEGIN
    high3 := HIGH(s3);
    IF HIGH(s1) < high3
    THEN high := HIGH(s1);
    ELSE high := high3;
    END;
    
    k := 0;
    WHILE (k <= high) AND (s1[k] # NULL) DO
      s3[k] := s1[k];
      INC(k);
    END;

    high2 := HIGH(s2);
    k2 := 0;
    WHILE (k2 <= high2) AND (s2[k2] # NULL) AND (k <= high3) DO
      s3[k] := s2[k2];
      INC(k); INC(k2);
    END;

    IF k <= high3
    THEN s3[k] := NULL;
    END;
  END Concatenate;

  PROCEDURE NoOp;
  END NoOp;

  PROCEDURE Default (fN: FileName; extLST: BOOLEAN);
    VAR
      extpos: CARDINAL;
  BEGIN
    defaultName := fN;
    IF NOT extLST THEN RETURN; END;
    extpos := Identifiers(fN);
    extpos := IdentifierPosition(fN,extpos-1);
    defaultName[extpos]   := 'L';
    IF extpos = 31 THEN RETURN; END;
    defaultName[extpos+1] := 'S';
    IF extpos = 30 THEN RETURN; END;
    defaultName[extpos+2] := 'T';
    IF extpos = 29 THEN RETURN; END;
    defaultName[extpos+3] := NULL;
  END Default;

  PROCEDURE OpenDoc (VAR inp: ARRAY OF CHAR; l: CARDINAL; firstDoc: BOOLEAN); 
    VAR (*  -------                                                       *)
      f: FileNo; fl: CARDINAL; ch: CHAR;
  BEGIN
    ClearDocument;
    IF l = 0 THEN ShowDialog(0);
    ELSE ShowDialog(9);
    END;
    LOOP
      ReadFileName(fN,ch,defaultName,inp,l);
      IF fN[0] # 0C THEN
        OpenFile(fN,f,fl);
        IF f # 0 THEN
          OpenDocument(f,fl);
          Default(fN,TRUE);
          ShowState(0);
          EXIT;
        ELSE
          ShowError(fl); (* 0,1,2 or 3 *)
          Default(fN,FALSE);
          helpLength := 0;
          IF NOT firstDoc THEN
            RemoveDocument;
            EXIT;
          END;
        END;
      ELSE
        IF ch = ESC THEN RemoveDocument;
        ELSE OpenDocument(0,0);
        END;
        ShowState(0);
        EXIT;
      END;
    END;
  END OpenDoc;

  PROCEDURE OpenFirstDoc;
    VAR (*  ------------ *)
      f: FileNo; fl: CARDINAL;
  BEGIN
    IF NewVs IN optionSet THEN
      OpenFile("DK.PUB.Edit.I11.TXT",f,fl);
      IF f = 0 THEN 
        OpenDoc(helpStr,0,TRUE);
      ELSE 
        ClearDocument;
        OpenDocument(f,fl);
      END;
    ELSE
      OpenDoc(helpStr,0,TRUE);
    END;
  END OpenFirstDoc;

  PROCEDURE ReadSelection (VAR helpStr: ARRAY OF CHAR; VAR helpLength: CARDINAL);
    VAR
      i: CARDINAL;
      ch: CHAR;
  BEGIN
    IF selected THEN 
      ReadBuffer(helpStr,helpLength);
      i := 0;
      LOOP
        IF i = helpLength THEN EXIT; END;
        ch := helpStr[i];
        IF (i = 32) OR (ch = BLANK) OR (ch = EOL) OR (ch = "/") THEN
          helpLength := i;
          EXIT;
        END;
        INC(i);
      END;
    ELSE
      helpLength := 0;
    END;
  END ReadSelection;
  
  PROCEDURE Equal (VAR id1: ARRAY OF CHAR; id2: ARRAY OF CHAR): BOOLEAN;
    VAR
      i: CARDINAL;
  BEGIN
    i := 0;
    LOOP
      IF (i > HIGH(id1)) OR (i > HIGH(id2)) THEN EXIT; END;
      IF (id1[i] = 0c) AND (id2[i] = 0c) THEN RETURN TRUE; END;
      IF id1[i] # id2[i] THEN RETURN FALSE; END;
      INC(i);
    END;
    RETURN ((i > HIGH(id1)) OR (id1[i] = 0c))
       AND ((i > HIGH(id2)) OR (id2[i] = 0c));
  END Equal;
  
  PROCEDURE ItemNr (VAR id: ARRAY OF CHAR): CARDINAL;
  BEGIN
    IF Equal(id,"SelectionFeedBack") THEN RETURN 0; END;
    IF Equal(id,"SelectionTypes") THEN RETURN 1; END;
    IF Equal(id,"Version") THEN RETURN 3; END;
    IF Equal(id,"HardCopy") THEN RETURN 4; END;
    IF Equal(id,"Macros") THEN RETURN 5; END;
    IF Equal(id,"Font") THEN RETURN 6; END;
    IF Equal(id,"ControlKeys") THEN RETURN 8; END;
    IF Equal(id,"Caret") THEN RETURN 9; END;
    IF Equal(id,"Umlaut") THEN RETURN 10; END;
    RETURN 99;
  END ItemNr;

BEGIN
  optionSet := OptionSET{NewVs};
  fontName[0] := 0c;
  LookupUserProfile(TRUE,ok);
  IF NOT ok THEN HALT; END;
  SetReadPos("Editor","",ok);
  IF ok THEN
    LOOP
      ReadItem(id,value,endOfGroup);
      IF endOfGroup THEN EXIT; END;
      item := ItemNr(id);
      CASE item OF
      0: IF Equal(value,"inverted") THEN INCL(optionSet,SelInv); END; |
      1: IF Equal(value,"from keyboard") THEN INCL(optionSet,KeySel);
         ELSIF Equal(value,"from buttons") THEN INCL(optionSet,ButSel); END; |
      3: IF Equal(value,"I.11") THEN EXCL(optionSet,NewVs); END; |
      4: IF Equal(value,"enabled") THEN INCL(optionSet,HardC); END; |
      5: IF Equal(value,"enabled") THEN INCL(optionSet,MacEnbl); END; |
      6: INCL(optionSet,ExoFont);
         i := 0;
         REPEAT
           fontName[i] := value[i];
           INC(i);
         UNTIL value[i-1] = 0c; |
      8: IF Equal(value,"enabled") THEN INCL(optionSet,CtrlInp); END; |
      9: IF Equal(value,"after insertion") THEN INCL(optionSet,MovCar); END; |
      10:IF Equal(value,"per default") THEN INCL(optionSet,Umlaut); END;
      ELSE
      END; (* CASE *)
    END;
    IF NewVs IN optionSet THEN
      SetWritePos("Editor","Version",ok);
      IF NOT ok THEN HALT; END;
      WriteItem("           I.11");
    END;
  ELSE
    SetWritePos("","",ok);
    IF ok THEN
      WriteGroupId("Editor");
      WriteItemId("Version");
      WriteItem("          I.11");
      WriteItemId("SelectionFeedBack");
      WriteItem("inverted");
      INCL(optionSet,SelInv);
      WriteItemId("Caret");
      WriteItem("            after insertion");
      INCL(optionSet,MovCar);
      WriteItemId("Umlaut");
      WriteItem("           per default");
      INCL(optionSet,Umlaut);
    ELSE
      HALT;
    END;
  END;
  CloseUserProfile;
  InitEditWindows;
  InitEditInput;

  IF ExoFont IN optionSet THEN 
    INCL(optionSet,SelInv); 
    EXCL(optionSet,KeySel); 
    EXCL(optionSet,ButSel);
  END;
  IF NOT(SelInv IN optionSet) THEN 
    EXCL(optionSet,KeySel); 
    EXCL(optionSet,ButSel); 
  END;

  helpStr := '';
  defaultName := 'DK.Temp.MOD';
  lastAction := 0;
  SearchString := '**** ';
  length := 5;
  OpenFirstDoc;
  IF NOT pendingMsg THEN ShowDialog(1); END;

  LOOP
    ReadKey(ch,mb);
    pendingMsg := FALSE;
    IF replay THEN
      BusyRead(stop);
      IF stop <> NULL THEN
        ShowDialog(2);
        REPEAT BusyRead(stop); UNTIL stop <> NULL;
        IF stop = ESC THEN ch := EOF; END;
      END;
      IF ch = EOF THEN
        BkSwitch;
        ShowState(0);
        lastAction := 14;
        ReadKey(ch,mb);
        pendingMsg := FALSE;
      END;
    ELSE
      BkSave;
    END;

    IF ch = 0c THEN                 (* mouse button pressed *)
      CASE area OF
      0: (*select and execute a command*)
         CASE command OF
           0: IF selected THEN
                lastAction := 1;
                SaveSection; 
              ELSE
                lastAction := 2; 
              END;
              InsertSection; |
           1: IF selected
              THEN SaveSection; lastAction := 3;
              ELSE ShowError(10);
              END |
           2: IF selected
              THEN DeleteSection; lastAction := 4;
              ELSE ShowError(10)
              END |
           3: IF selected THEN
                ReadBuffer(SearchString,helpLength);
              ELSE
                ShowDialog(3);
                ReadKey(ch,mb);
                IF (ch = '?') OR (ch = HELP) THEN
                  ShowState(1);
                  ReadKey(ch,mb);
                END;
                IF ch <> 0c THEN
                  ReadAgain;
                  ReadString(helpStr,helpLength);
                  IF (helpLength > 0) AND (helpStr[helpLength-1] = ESC)
                  THEN helpLength := 0;
                  ELSE Concatenate(helpStr,"",SearchString);
                  END;
                ELSE
                  Wait0Button(NoOp);
                  IF mb = 1 THEN helpLength := length; (* button 1 *)
                  ELSE helpLength := 0;
                  END;
                END;
              END;
              IF helpLength = 0 THEN
                lastAction := 5;
              ELSE
                length := helpLength;
                ShowState(2);
                Find(SearchString,length,ok);
                IF NOT ok THEN
                  ShowError(9);
                  macro := FALSE;
                END;
                lastAction := 6;
              END; |
           4: ShowDialog(4);
              ReadKey(ch,mb);
              IF ch = 0c THEN                 (* mouse button pressed *)
                IF area = 2 THEN
                  CASE mb OF
                  1: IF LastLine() THEN
                       ShowState(4);
                       Wait0Button(MoveBar);
                       LetBar;
                       lastAction := 16;
                     ELSE
                       ShowState(5);
                       SetBar(3);
                       Wait0Button(MoveBar);
                       IF windowOK THEN
                         OpenWindow;
                       ELSE
                         RemoveBar;
                         ShowError(4);
                       END;
                       lastAction := 7;
                     END; |
                  2: lastAction := 5; |
                  4: ReadSelection(helpStr,helpLength);
                     ShowState(6);
                     SetBar(0);
                     Wait0Button(MoveBar);
                     IF windowOK THEN
                       OpenDoc(helpStr,helpLength,FALSE);
                     ELSE
                       RemoveBar;
                       ShowError(5);
                     END;
                     lastAction := 0;
                  ELSE
                  END;
                END;
              ELSE
                lastAction := 5;
                IF ch # ESC THEN ReadAgain; END;
              END; |
           5: IF windowCount > 1 THEN
                ShowDialog(5);
                ReadKey(ch,mb);
                IF (ch = 0c) AND (mb = 1) THEN (* button 1 *)
                  Wait0Button(TraceCursor);
                ELSE
                  mb := 0;
                  IF (ch <> 0c) AND (ch # ESC) THEN ReadAgain; END;
                END;
              ELSE
                mb := 1;
                area := 2; (* read only !?! *)
              END;
              IF (mb = 1) AND (area = 2) THEN
                GetTypeAndName(windowType, fN);
                IF windowType # SubWindow THEN
                  ReadSelection(helpStr,helpLength);
                  ShowFileName(fN);
                  ShowDialog(6);
                  LOOP
                    ReadCh(ch);
                    IF (CAP(ch) = "Y") OR (CAP(ch) = "N")
                    OR (ch = ESC) THEN EXIT;
                    END;
                    ShowError(6);
                  END;
                  IF CAP(ch) = "Y" THEN
                    IF helpLength = 0 THEN ShowDialog(7);
                    ELSE ShowDialog(10);
                    END;
                    ReadFileName(outputN,ch,fN,helpStr,helpLength);
                    IF outputN[0] = 0C THEN
                      IF (ch = BLANK) OR (ch = EOL) THEN (* backup *)
                        IF AlreadyWritten(fN) THEN
                          ShowError(7);
                        ELSE
                          ShowState(7);
                          ShowFileName(fN);
                          BackupDocument(ok);
                          IF ok THEN IF windowType = TopWindow THEN EXIT; END;
                          ELSE ShowError(11);
                          END;
                        END;
                        lastAction := 8;
                      ELSE
                        lastAction := 5;
                      END;
                    ELSE
                      IF FileNameNew(outputN) THEN
                        ShowState(7);
                        PutDocument(ok);
                        IF ok THEN IF windowType = TopWindow THEN EXIT; END;
                        ELSE HALT; (* Put should never return NOT ok *)
                        END;
                      ELSE
                        ShowError(8);
                      END;
                      lastAction := 8;
                    END;
                  ELSIF CAP(ch) = "N" THEN
                    IF windowType = TopWindow THEN
                      ShowDialog(8);
                      ReadCh(ch);
                      IF CAP(ch) = 'Y' THEN EXIT; (* from the main loop *)
                      ELSE lastAction := 5;
                      END;
                    ELSE
                      CloseWindow;
                      lastAction := 8;
                    END;
                  ELSE
                    ShowState(0);
                    lastAction := 5;
                  END;
                ELSE
                  CloseWindow;
                  lastAction := 8;
                END;
              ELSE
                lastAction := 5;
              END;
         END |
      1: (*arrow is in scroll bar area*)
         ShowState(9);
         CASE mb OF
         1: ScrollUp;
            lastAction := 9; |
         2: Flip;
            lastAction := 10; |
         4: ScrollDown;
            lastAction := 11;
         ELSE
         END |
      2: (*arrow is in text area*)
         CASE mb OF
         1: ShowState(10);
            Wait0Button(TraceCursor);
            lastAction := 12; |
         4: ShowState(8);
            StartSelection;
            WatchButtons(ContinueSelection);
            StopSelection;
            lastAction := 13;
         ELSE
         END
      END;
    ELSE                                (* keyboard input *)
      lastAction := 19;
      IF ch = DEL THEN Backspace;
      ELSIF ch = EOL THEN InsertLine;
      ELSIF ch >= GS THEN Insert(ch);
      ELSIF ch = ESC THEN Deselect;
      ELSIF ch =  FF THEN Insert(FF);
      ELSIF ch = TAB THEN Insert(BLANK); Insert(BLANK);
      ELSIF ch = OCT THEN 
        IF controlCharsAvailable AND (CtrlInp IN optionSet) THEN 
          ReadOct(ch, ok);
          IF ok THEN Insert(ch); END;
          ShowState(0);
        END;
      ELSIF ch = HELP THEN ShowLastAction;
      ELSIF (ch = 21c) (*ENTER*) AND (MacEnbl IN optionSet) THEN
        IF macro THEN macro := FALSE; lastAction := 20;
        ELSIF learning THEN learning := FALSE; lastAction := 18;
        ELSE InitLearning; lastAction := 17;
        END;
      ELSIF (ch = 22c) (*PRINT*) AND (MacEnbl IN optionSet) THEN
        IF macro THEN macro := FALSE; lastAction := 20;
        ELSE learning := FALSE; InitMacro;
        END;
      ELSE (* control characters *)
        IF controlCharsAvailable AND (CtrlInp IN optionSet) THEN Insert(ch); END;
      END;
      pendingMsg := TRUE; (* to avoid writing "ready" for every key *)
    END;
    IF NOT pendingMsg THEN ShowState(0); END;
  END; (* LOOP *)

  CloseFiles;
  StopDisplay;
END Edit.
