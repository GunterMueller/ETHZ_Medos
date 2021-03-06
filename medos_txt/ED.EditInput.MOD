IMPLEMENTATION MODULE EditInput; (* vs I.11         Werner Winiger 5.7.83
                      =========  *)

  IMPORT Terminal;
  FROM TerminalBase IMPORT
    Read, AssignRead, Write, AssignWrite;
  IMPORT FileNames;
  FROM EditDisplay IMPORT
    area, command, Options, optionSet, HardCopy, Mline, Mcol, McolSel,
    ReadMB, ShowMsg, ShowChar, ShowFileName, Blink, ClearCaret;
  FROM EditFiles IMPORT
    replay, BkRead, BkWrite, BkSwitch, macro;

  CONST
    NULL  = 0c;
    LF    = 12c;
    CAPS  = 16c;
    CtrlP = 20c;
    DC3   = 23c;
    DC4   = 24c;
    ESC   = 33c;
    EOF   = 34c;
    EOL   = 36c;
    BLANK = 40c;
    DEL   = 177c;
    StringLength = 50;

  VAR
    lastCh : CHAR;
    transparent,
    putBack,
    umlauts,
    accents,
    softShiftLock,
    readingFilename,
    cleared      : BOOLEAN;
    buffer       : ARRAY [0..StringLength-1] OF CHAR;
    ix, ox,
    bufferLength : CARDINAL;

 
  PROCEDURE ReadAgain;
  BEGIN (*  ---------  *)
    putBack := TRUE;
  END ReadAgain;

 
  PROCEDURE BusyRead (VAR ch: CHAR);
  BEGIN (*  --------             *)
    transparent := TRUE;
    Read(ch);
    transparent := FALSE;
  END BusyRead;

 
  PROCEDURE ReadCh (VAR ch: CHAR);
  BEGIN (*  ------             *)
    Terminal.Read(ch);
  END ReadCh;

 
  PROCEDURE BkReadContext;
  BEGIN (*  ------------- *)
    area := BkRead();
    CASE area OF
      0: command := BkRead(); |
      1: Mline := BkRead();   |
      2: Mline := BkRead();
         Mcol := BkRead();
         McolSel := BOOLEAN(BkRead());
    END;
  END BkReadContext;

 
  PROCEDURE BkWriteContext;
  BEGIN (*  -------------- *)
    BkWrite(area);
    CASE area OF
      0: BkWrite(command); |
      1: BkWrite(Mline);   |
      2: BkWrite(Mline);
         BkWrite(Mcol);
         BkWrite(CARDINAL(McolSel));
    END;
  END BkWriteContext;

 
  PROCEDURE ReadMouse (VAR mb: CARDINAL);
  BEGIN (*  ---------                 *)
    IF replay OR macro THEN
      mb := BkRead();
      BkReadContext;
    ELSE
      REPEAT
        ReadMB(mb);
      UNTIL mb > 0;
      BkWrite(mb);
      BkWriteContext;
    END;
  END ReadMouse;

 
  PROCEDURE ReadKey (VAR ch: CHAR; VAR button: CARDINAL);
    VAR (*  -------                                   *)
      clock, clocks, mb: CARDINAL;
  BEGIN
    IF putBack THEN
      putBack := FALSE;
      ch := lastCh
    ELSIF replay OR macro THEN
      ch := CHAR(BkRead());
      IF ch = 0c THEN
        button := BkRead();
        BkReadContext;
      ELSE
        lastCh := ch;
      END;
    ELSE
      clock := 0;
      clocks := 0;
      LOOP
        INC(clock);
        IF clock = 1000 THEN
          Blink;
          clock := 0;
          IF pendingMsg THEN
            INC(clocks);
            IF clocks = 30 THEN
              ShowMsg("ready");
              pendingMsg := FALSE;
            END;
          END;
        END;
        Terminal.BusyRead(ch);
        IF ch > NULL THEN EXIT; END;
        ReadMB(mb);
        IF mb <> 0 THEN
          ch := 0c;
          button := mb;
          IF area = 1 THEN
            REPEAT
              ReadMB(mb);
            UNTIL mb = 0;
          END;
          BkWrite(0);
          BkWrite(button);
          BkWriteContext;
          ClearCaret;
          Blink;
          EXIT;
        END;
      END; (* loop *)
    END;
  END ReadKey;


  PROCEDURE Wait0Button (p: PROC);
    VAR (*  -----------        *)
      mb: CARDINAL;
  BEGIN
    IF replay OR macro THEN
      Mline := CARDINAL(BkRead());
      Mcol := CARDINAL(BkRead());
      p;
    ELSE
      REPEAT
        ReadMB(mb);
        p;
      UNTIL (mb = 0);
      BkWrite(Mline);
      BkWrite(Mcol);
    END;
  END Wait0Button;


  PROCEDURE WatchButtons (p: ButtonProc);
    VAR (*  ------------              *)
      mb: CARDINAL;
      buttons: CARDINAL;
      ch: CHAR;
  BEGIN
    IF replay OR macro THEN
      buttons := CARDINAL(BkRead());
      Mline := CARDINAL(BkRead());
      Mcol := CARDINAL(BkRead());
      McolSel := BOOLEAN(BkRead());
      p(buttons);
    ELSE
      buttons := 11;
      REPEAT
        ReadMB(mb);
        p(mb);
        IF KeySel IN optionSet THEN
          Terminal.BusyRead(ch);
          IF ch > NULL THEN
            IF (ch = 's') OR (ch = 'z') THEN     (* move *)
              IF buttons = 10 THEN buttons := 11;
              ELSE buttons := 10;
              END;
            ELSIF ch = 'c' THEN                  (* copy *)
              IF buttons = 9 THEN buttons := 11;
              ELSE buttons := 9;
              END;
            ELSIF (ch = 'd') OR (ch = 'x') THEN  (* delete *)
              IF buttons = 8 THEN buttons := 11;
              ELSE buttons := 8;
              END;
            ELSIF ch = ESC THEN
              buttons := 11;
            END;
            p(buttons);
          END;
        END;
        IF ButSel IN optionSet THEN
          IF mb = 5 THEN                         (* delete *)
            IF buttons = 8 THEN buttons := 11;
            ELSE buttons := 8;
            END;
            p(buttons);
            REPEAT
              ReadMB(mb);
              p(4);
            UNTIL mb # 5;
          ELSIF mb = 6 THEN                      (* copy *)
            IF buttons = 9 THEN buttons := 11;
            ELSE buttons := 9;
            END;
            p(buttons);
            REPEAT
              ReadMB(mb);
              p(4);
            UNTIL mb # 6;
          ELSIF mb = 7 THEN                      (* move *)
            IF buttons = 10 THEN buttons := 11;
            ELSE buttons := 10;
            END;
            p(buttons);
            REPEAT
              ReadMB(mb);
              p(4);
            UNTIL mb <= 4;
          END;
        END;
      UNTIL mb = 0;
      BkWrite(buttons);
      BkWrite(Mline);
      BkWrite(Mcol);
      BkWrite(CARDINAL(McolSel));
    END;
  END WatchButtons;


  PROCEDURE ReadString (VAR s: ARRAY OF CHAR; VAR l: CARDINAL);
    VAR (*  ----------                                      *)
      ch: CHAR;
    CONST
      Max = 39;   (* 50 - size('searching') *)
  BEGIN
    l := HIGH(s);
    REPEAT
      s[l] := NULL;
      DEC(l);
    UNTIL l = 0;

    LOOP
      Terminal.Read(ch);      
      IF ch = EOL THEN        
        EXIT;
      ELSIF (ch = DEL) AND (l > 0) THEN
        DEC(l);
        s[l] := NULL;
      ELSE
        s[l] := ch;
        INC(l);
        IF (ch = ESC) OR (l = Max) THEN EXIT; END;
      END;
      ShowMsg(s);
    END;
  END ReadString;


  PROCEDURE ReadOct (VAR ch: CHAR; VAR ok: BOOLEAN);
    VAR (*  -------                              *)
      c: CHAR;
      s: ARRAY [0..49] OF CHAR;
      ord, i: CARDINAL;
  BEGIN
    s := "ordinal number of a character in octal:           ";
    i := 49;
    REPEAT
      s[i] := NULL;
      DEC(i);
    UNTIL i = 39;
    INC(i);
    ch := 0c;
    ok := TRUE;
    LOOP
      ShowMsg(s);
      Terminal.Read(c);      
      IF (c = EOL) OR (c = BLANK) THEN        
        EXIT;
      ELSIF (c = DEL) AND (i > 40) THEN
        DEC(i);
        s[i] := NULL;
        ch := CHAR(CARDINAL(ch) DIV 10b);
      ELSIF (c >= '0') AND (c <= '7') THEN
        ord := 10b*CARDINAL(ch) + CARDINAL(c) - CARDINAL('0');
        IF ord < 400b THEN
          s[i] := c;
          INC(i);
          ch := CHAR(ord);
        END;
      ELSIF c = ESC THEN ok := FALSE; EXIT;
      END;
    END;
  END ReadOct;


  PROCEDURE EditRead (VAR ch: CHAR);
  BEGIN
    IF transparent THEN
      Read(ch);
    ELSIF putBack THEN
      putBack := FALSE;
      ch := lastCh
    ELSIF replay OR macro THEN
      IF ix < bufferLength THEN
        ch := buffer[ix];
        INC(ix);
      ELSE
        ch := CHAR(BkRead());
      END;
    ELSIF ix < bufferLength THEN
      ch := buffer[ix];
      INC(ix);
    ELSE
      LOOP
        Read(ch);
        IF ch = 0c THEN 
          RETURN;
        ELSIF (ch = CtrlP) AND (HardC IN optionSet) THEN
          HardCopy;
        ELSIF ch = LF THEN 
          ch := DEL; 
          EXIT;
        ELSIF ch = DC3 THEN
          accents := NOT accents;
          IF accents THEN umlauts := FALSE; END;
        ELSIF ch = DC4 THEN
          umlauts := NOT umlauts;
          IF umlauts THEN accents := FALSE; END;
        ELSIF ch = CAPS THEN
          softShiftLock := NOT softShiftLock;
        ELSIF (ch = EOF) AND readingFilename THEN
          BkSwitch;
        ELSE
          EXIT;
        END;
      END;
      IF accents THEN 
        CASE ch OF
          '`': ch := 206c;
        | '{': ch := 207c;
        | '~': ch := 210c;
        | '>': ch := 211c;
        | '|': ch := 212c;
        | '@': ch := 213c;
        | ']': ch := 214c;
        | '#': ch := 215c;
        | '$': ch := 216c;
        | '\': ch := 217c;
        | '[': ch := 220c;
        | '}': ch := 221c;
        | '^': ch := 222c;
        | '<': ch := 223c;
        ELSE
        END;
      ELSIF umlauts THEN 
        CASE ch OF
        '@': IF softShiftLock THEN ch := 200c ELSE ch := 203c; END; |
        '^': IF softShiftLock THEN ch := 201c ELSE ch := 204c; END; |
        '\': IF softShiftLock THEN ch := 202c ELSE ch := 205c; END; |
        '`': ch := 200c; |
        '~': ch := 201c; |
        '|': ch := 202c;
        ELSE
        END;
      END;
      IF softShiftLock THEN
        IF (ch >= 'a') AND (ch <='z') THEN
          ch := CAP(ch);
        ELSIF (ch < 'A') OR ((ch > 'Z') AND (ch < 177c)) THEN
          softShiftLock := FALSE;
        END;
      END;
      BkWrite(CARDINAL(ch));
    END;
    lastCh := ch;
  END EditRead;


  PROCEDURE EditWrite (ch: CHAR);
  BEGIN
    IF readingFilename THEN
      IF NOT cleared THEN
        cleared := TRUE;
        ShowFileName('  ');
      END;
      IF ch = DEL THEN
        DEC(ox);
        ShowChar(BLANK,ox);
      ELSE
        ShowChar(ch,ox);
        INC(ox);
      END;
    ELSE
      Write(ch);
    END;
  END EditWrite;


  PROCEDURE ReadFileName (VAR fn: ARRAY OF CHAR; VAR termCh: CHAR;
                          dfn,inp: ARRAY OF CHAR; inpLength: CARDINAL);
  BEGIN
    bufferLength := 0;
    WHILE bufferLength < inpLength DO
      buffer[bufferLength] := inp[bufferLength];
      INC(bufferLength);
    END;
    ox := 0;
    cleared := FALSE;
    readingFilename := TRUE;
    FileNames.ReadFileName(fn,dfn);
    readingFilename := FALSE;
    ReadCh(termCh);
    ix := 0;
    bufferLength := 0;
  END ReadFileName;


  PROCEDURE InitEditInput;
    VAR (*  -------------  *)
      done: BOOLEAN;
  BEGIN
    transparent := FALSE;
    putBack := FALSE;
    softShiftLock := FALSE;
    accents := FALSE;
    umlauts := Umlaut IN optionSet;
    ix := 0;
    bufferLength := 0;
    AssignRead(EditRead,done);
    IF NOT done THEN HALT; END;
    AssignWrite(EditWrite,done);
    IF NOT done THEN HALT; END;
  END InitEditInput;


END EditInput.
