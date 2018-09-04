(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          Comint:                     *
*                                      *
*          Comint is an overlay to     *
*          SEK, the main program in    *
*          MEDOS-2.                    *
*                                      *
*          Version 4  21.06.82         *    
*          Version 42 10.12.82         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

MODULE Comint;
  
  (* This command interpreter should be called from Module SEK
     and should be considdered as an overlay to Module SEK.   *) 

  IMPORT SYSTEM, FileSystem, DiskSystem;
  
  FROM SEK IMPORT 
    PreviousStatus, NextProgram, SetParameter,
    Login, LeaveLogin, TestDK;

  FROM UserIdentification IMPORT User, SetUser;
       
  FROM Monitor IMPORT SetTime, GetTime, Time; 
  
  FROM Program IMPORT Status; 
  
  FROM Terminal IMPORT 
    BusyRead, ReadAgain, Write, WriteString, WriteLn;

  FROM CardinalIO IMPORT WriteOct;
 
  FROM FileSystem IMPORT
    File, Response, Lookup, Close, Reset, ReadWord, WriteWord, SetModify;

  IMPORT DisplayDriver;
  
  
  CONST
    eol = 36C;
    esc = 33C;
    can = 30C;
    ff  = 14C;
    del = 177C;
    namelength = 16;
    versiontext = 'SEK.Comint V4.2';
    versiondate = '25.10.82';
    defaultday = 25 + 10*40B + 82*1000B;
    firstday = 1 + 1*40B + 1*1000B;
    nogroup = 0; nomember = 0;
    pwlength = 32;
    promtchar = '*';
    commandfile = 'SEK4.CommandFile';
    startfile = 'DK.SEK.Start.COM';
    idlefile = 'DK.SEK.Idle.COM';
    maxidlesecs = 3 * 60;

  TYPE
    Name = ARRAY [0..namelength-1] OF CHAR;
    CC = (unknown, letter, digit, point, colon, help,
          blank, lineend, escape, delete, cancel);
    CCS = SET OF CC;
  
  VAR
    name: Name;
    pos, oldpos: CARDINAL;
    ch, cch: CHAR; cc: CC;
    fromterminal: BOOLEAN;
    let, dig, dot: BOOLEAN;
    letexp, nodotexp: BOOLEAN;
    c: CARDINAL;
    tabulated: BOOLEAN;
    prevst: Status;
    t: Time;
    d, m, y, dd, dm, dy, dday: CARDINAL;
    u: User;
    defg, defm, actg, actm: CARDINAL;
    pw: ARRAY [0..pwlength-1] OF CHAR;
    f: File;
    ok: BOOLEAN;
    fccs, efccs: CCS;
    
  
  PROCEDURE CharClass(ch: CHAR): CC;
  BEGIN
    IF ('A' <= ch) AND (ch <= 'Z') OR
       ('a' <= ch) AND (ch <= 'z') THEN RETURN letter
    ELSIF ('0' <= ch) AND (ch <= '9') THEN RETURN digit
    ELSIF ch = eol THEN RETURN lineend
    ELSIF ch = ' ' THEN RETURN blank
    ELSIF ch = '.' THEN RETURN point
    ELSIF ch = del THEN RETURN delete
    ELSIF ch = esc THEN RETURN escape
    ELSIF ch = can THEN RETURN cancel
    ELSIF ch = '?' THEN RETURN help
    ELSIF ch = ':' THEN RETURN colon
    ELSE RETURN unknown
    END;
  END CharClass;

  MODULE Scheduler;
  
    FROM SYSTEM IMPORT
      ADDRESS, PROCESS, NEWPROCESS, TRANSFER;
  
    EXPORT CreateProcess, Pass;
  
    CONST
      procs = 3;
  
    VAR
      ptab: ARRAY [0..procs-1] OF PROCESS;
      cur, top: [0..procs];
  
    PROCEDURE CreateProcess(p: PROC; a: ADDRESS; s: CARDINAL);
    BEGIN
      IF top < procs THEN
        NEWPROCESS(p, a, s, ptab[top]);
        INC(top);
      END;
    END CreateProcess;
  
    PROCEDURE Pass;
      VAR old: [0..procs-1];
    BEGIN
      old := cur;
      cur := (cur+1) MOD top;
      IF old <> cur THEN TRANSFER(ptab[old], ptab[cur]) END;
    END Pass;
  
  BEGIN
    cur := 0; top := 1;
  END Scheduler;


  PROCEDURE NextChar;
  BEGIN
    LOOP
      BusyRead(ch);
      IF ch <> 0C THEN EXIT END;
      Pass;
    END;
    cc := CharClass(ch);
    idle := FALSE;
  END NextChar;
  

  MODULE Searcher;
    
    IMPORT CreateProcess, Pass;
    FROM DisplayDriver IMPORT LineHeight, MapHeight;
    IMPORT
      NextChar, ch,
      esc, ff, Write, WriteLn, WriteString,
      Name, namelength, name, pos;
    FROM FileSystem IMPORT Response;
    IMPORT DiskSystem;
    FROM DiskSystem IMPORT fname, ExternalName, ReadName;
    FROM SYSTEM IMPORT WORD, ADR, SIZE;
  
    EXPORT
      filled,
      selectname, selectsys, selectpos,
      checked, found,
      deltab,
      CheckName,
      ListNames;
  
    CONST
      stacklength = 400;
      prognames = 800;
  
    TYPE
      NameEntry = RECORD
                    pn: Name;
                    sys: BOOLEAN;
                 END;

    VAR
      stack: ARRAY [0..stacklength-1] OF WORD;
      tab: ARRAY [0..prognames-1] OF NameEntry;
      tabtop: CARDINAL;
      tabtops: ARRAY [0..namelength] OF [0..prognames];
      selectname: Name; 
      selectsys: BOOLEAN;
      selectpos: [0..namelength];
      deltab: ARRAY [0..namelength] OF CARDINAL;
      filled: BOOLEAN;
      checked, found: BOOLEAN;
      c: CARDINAL;
  
    PROCEDURE EqualNames(VAR n1, n2: Name): BOOLEAN;
      VAR pos: CARDINAL;
    BEGIN
      pos := 0;
      LOOP
        IF pos >= namelength THEN RETURN TRUE END;
        IF n1[pos] <> n2[pos] THEN RETURN FALSE END;
        INC(pos)
      END;
    END EqualNames;
  
    PROCEDURE InsertExternalName(en: ExternalName; top: CARDINAL; sysname: BOOLEAN);
  
      CONST
        enlength = 24;
  
      VAR
        c: CARDINAL; na: Name;
  
    BEGIN
      IF (top <= namelength) AND (tabtop < prognames) THEN
        c := 0;
        WHILE c < top DO na[c] := en[c]; INC(c) END;
        WHILE c < namelength DO na[c] := 0C; INC(c) END;
        c := 0;
        LOOP
          IF c >= tabtop THEN
            WITH tab[tabtop] DO
              pn := na;
              sys := sysname;
            END;
            INC(tabtop);
            EXIT;
          END;
          WITH tab[c] DO
            IF EqualNames(pn, na) THEN
              sys := sys AND sysname;
              EXIT;
            END;
          END;
          INC(c);
        END;
      END;
    END InsertExternalName;
                
    PROCEDURE SearchProc;
  
      CONST
        externallength = 24;
  
      VAR
        fno: CARDINAL;
        res: Response;
        na: DiskSystem.Name;
        p, top: CARDINAL;
        pn: NameEntry;
        c: CARDINAL;
        low, high: CARDINAL;
        ch: CHAR;
  
    BEGIN
      (* fill the tab with the names of existing programs *)
      tabtop := 0;
      fno := 0;
      LOOP
        ReadName(fno, na, res);
        IF res <> done THEN EXIT END;
        WITH na DO
          IF nk = fname THEN
            top := 0;
            LOOP
              IF (en[top] = 0C) OR (en[top] = ' ') THEN EXIT END;
              INC(top);
              IF top >= externallength THEN EXIT END;
            END;
            IF (top >= 4) AND 
               (en[top-4] = '.') AND (en[top-3] = 'O') AND 
               (en[top-2] = 'B') AND (en[top-1] = 'J') THEN
              DEC(top, 4);
              InsertExternalName(en, top, FALSE);
              IF (top > 4) AND
                 (en[0] = 'S') AND (en[1] = 'Y') AND 
                 (en[2] = 'S') AND (en[3] = '.') THEN
                FOR p := 0 TO top-4 DO en[p] := en[p+4] END;
                DEC(top, 4);
                InsertExternalName(en, top, TRUE);
              END;
            END;
          END;
        END;
        IF fno MOD 16 = 0 THEN Pass END;
        INC(fno);
        IF fno >= 768 THEN EXIT END;
      END;
      filled := TRUE;
  
      (* execute selecting part *)
      tabtops[0] := tabtop;
      LOOP
        IF selectpos < pos THEN
          ch := name[selectpos];
          low := 0; high := tabtops[selectpos];
          c := 0;
          WHILE c < high DO
            IF tab[c].pn[ selectpos] = ch THEN
              pn := tab[c]; tab[c] := tab[low]; tab[low] := pn;
              INC(low);
            END;
            INC(c);
          END;
          INC(selectpos);
          tabtops[selectpos] := low;
          deltab[selectpos] := 1;
          IF low > 0 THEN
            LOOP
              IF selectpos >= namelength THEN EXIT END;
              ch := tab[0].pn[selectpos];
              IF ch = 0C THEN EXIT END;
              IF (pos > selectpos) AND (ch <> name[selectpos]) THEN EXIT END;
              c := 0;
              WHILE c < low DO
                IF tab[c].pn[selectpos] <> ch THEN EXIT END;
                INC(c);
              END;
              INC(selectpos);
              tabtops[selectpos] := low;
              deltab[selectpos] := 1 + deltab[selectpos-1];
            END;
          END;
          selectname := tab[0].pn;
          selectsys := tab[0].sys;
        END;
        Pass;
      END;
    END SearchProc;

  PROCEDURE CheckName;
    VAR c: CARDINAL;
  BEGIN
    checked := filled;
    IF filled THEN
      WHILE selectpos < pos DO Pass END;
    END;
    IF checked THEN
      c := 0;
      LOOP
        IF c >= tabtops[selectpos] THEN found := FALSE; EXIT END;
        WITH tab[c] DO
          IF (pos >= namelength) OR (pn[pos] = 0C) THEN 
            selectname := pn; selectsys := sys;
            found := TRUE;
            EXIT;
          END;
        END;
        INC(c);
      END;
    END;
  END CheckName;
  
  PROCEDURE ListNames;
  
    VAR
      c, p, linesOnScreen: CARDINAL;
  
  BEGIN
    IF MapHeight() >= 5*LineHeight() THEN
      linesOnScreen := MapHeight() DIV LineHeight() - 1
    ELSE linesOnScreen := 10000
    END;
    WHILE NOT filled OR (selectpos < pos) DO Pass END;
    IF tabtops[pos] = 0 THEN
      WriteLn;
      WriteString('  no such program found'); WriteLn
    ELSE
      c := 0;
      LOOP
        IF c >=  tabtops[pos] THEN EXIT END;
        WriteString('  ');
        p := 0;
        LOOP
          IF p >= namelength THEN EXIT END;
          ch := tab[c].pn[p];
          IF ch <= ' ' THEN EXIT END;
          Write(ch);
          INC(p);
        END;
        WriteLn;
        INC(c);
        IF (c MOD linesOnScreen = 0) AND (c < tabtops[pos]) THEN
          WriteString('  ...');
          NextChar;
          IF ch = esc THEN WriteLn; EXIT END;
          Write(ff);
        END;
      END;
    END;
    WriteLn;
  END ListNames;
      
  BEGIN
    filled := FALSE;
    deltab[0] := 0;
    selectpos := 0;
    CreateProcess(SearchProc, ADR(stack), SIZE(stack));
  END Searcher;


  MODULE Surveyor;

    IMPORT
      CreateProcess, Pass,
      WriteString, Write, WriteLn, ff,
      Time, GetTime,
      maxidlesecs,
      NextProgram, SetParameter, commandfile, idlefile,
      TestDK,
      File, Response, Lookup, Close;

    FROM DisplayDriver IMPORT ScreenWidth, ScreenHeight, MapHeight;
    IMPORT DisplayDriver;

    FROM SYSTEM IMPORT WORD, ADR, SIZE;
    IMPORT SYSTEM;

    EXPORT idle, diskok;

    VAR
      idle, diskok: BOOLEAN;
      stack: ARRAY [1..300] OF WORD;

    PROCEDURE Pause;

      VAR
        t: Time;
        old, new: CARDINAL;

    BEGIN
      WITH t DO
        GetTime(t);
        old := millisecond;
        new := (old+1000) MOD 60000;
        LOOP
          Pass;
          GetTime(t);
          IF new >= old THEN
            IF (millisecond < old) OR (millisecond >= new) THEN EXIT END;
          ELSE
            IF (millisecond < old) AND (millisecond >= new) THEN EXIT END;
          END;
        END;
      END;
    END Pause;

    MODULE Lilith;  (*NW 15.6.82*)
      FROM SYSTEM IMPORT ADDRESS, ADR;
      IMPORT Time, GetTime;
      FROM DisplayDriver IMPORT BMDescriptor, BMD, ScreenWidth, ScreenHeight;

      EXPORT ShowLilith, MoveLilith;

      TYPE Block = RECORD x,y,w,h: INTEGER END;
           Pattern = RECORD L: CARDINAL; v: ARRAY [0..15] OF CARDINAL END ;

      VAR i, Width, Height: INTEGER;
        ch: CHAR;
        x,y,dx,dy: INTEGER;
        blk: Block;
        pat: Pattern;

      PROCEDURE REPL(mode: CARDINAL; bmd: BMDescriptor;
                     VAR src: Pattern; VAR dst: Block);
        CODE 343B
      END REPL;

      PROCEDURE ShowLilith;
      BEGIN
        REPL(2, BMD, pat, blk);
      END ShowLilith;

      PROCEDURE MoveLilith;
      BEGIN
        REPL(2, BMD, pat, blk);
        x := blk.x + dx;
        IF x <= 0 THEN x := -x; dx := -dx
        ELSIF x >= Width THEN x := 2*Width - x; dx := -dx
        END ;
        y := blk.y + dy;
        IF y <= 0 THEN y := -y; dy := -dy
        ELSIF y >= Height THEN y := 2*Height - y; dy := -dy
        END ;
        blk.x := x; blk.y := y;
        REPL(2, BMD, pat, blk);
      END MoveLilith;

    BEGIN
      Width := ScreenWidth()-16; Height := ScreenHeight()-16;
      pat.L := 16; pat.v[0] := 3740B;
      pat.v[ 1] := 017770B; pat.v[ 2] := 037774B; pat.v[ 3] := 037774B;
      pat.v[ 4] := 070616B; pat.v[ 5] := 077776B; pat.v[ 6] := 074636B;
      pat.v[ 7] := 074636B; pat.v[ 8] := 077776B; pat.v[ 9] := 077776B;
      pat.v[10] := 076676B; pat.v[11] := 174037B; pat.v[12] := 176077B;
      pat.v[13] := 157773B; pat.v[14] := 107761B; pat.v[15] := 101701B;
      WITH blk DO
        x := 235; y := 538; w := 16; h := 16
      END ;
      dx := 351; dy := 411;
    END Lilith;

    PROCEDURE Survey;

      VAR
        idlesecs: CARDINAL;
        f: File;
        t: Time; freelines: CARDINAL;

    BEGIN
      idlesecs := 0;
      LOOP
        IF idle THEN
          IF idlesecs <= maxidlesecs THEN INC(idlesecs) END;
          IF idlesecs = maxidlesecs THEN
            Lookup(f, idlefile, FALSE);
            IF f.res = done THEN
              WriteLn;
              Close(f);
              NextProgram(commandfile); SetParameter(idlefile);
              EXIT;
            END;
          END;
        ELSE
          idlesecs := 0; idle := TRUE
        END;
        IF NOT TestDK(FALSE) THEN
          diskok := FALSE;
          Write(ff);
          IF (ScreenWidth() >= 640) AND (ScreenHeight() >= 592) AND
             (MapHeight() = ScreenHeight()) THEN
            ShowLilith;
            REPEAT
              Pause; Pause;
              MoveLilith;
            UNTIL TestDK(TRUE);
          ELSE
            GetTime(t);
            freelines := t.millisecond DIV 4000;
            LOOP
              WriteLn;
              IF freelines = 0 THEN EXIT END;
              DEC (freelines);
            END;
            WriteString("    *************************************"); WriteLn;
            WriteString("   *                                   *"); WriteLn;
            WriteString("  *                                   *"); WriteLn;
            WriteString(" *       I'm   j u s t   waiting     *"); WriteLn;
            WriteString("  *                                   *"); WriteLn;
            WriteString("   *                                   *"); WriteLn;
            WriteString("    *************************************"); WriteLn;
          END;
          EXIT
        END;
        Pause;
      END;
    END Survey;

  BEGIN
    idle := FALSE; diskok := TRUE;
    CreateProcess(Survey, ADR(stack), SIZE(stack));
  END Surveyor;

  
  PROCEDURE WriteStatus(st: Status);

    PROCEDURE WriteS(s: ARRAY OF CHAR);
      VAR c, l: CARDINAL;
    BEGIN
      l := 0;
      WHILE (l <= HIGH(s)) AND (s[l] <> 0C) DO INC(l) END;
      INC(l, 2);
      FOR c := 1 TO l DO Write(' ') END;
      FOR c := 1 TO l DO Write(del) END;
      Write(' ');
      WriteString(s)
    END WriteS;

  BEGIN
    CASE st OF
      normal:               WriteS('normal') |
      instructionerr:       WriteS('instruction error') |
      priorityerr:          WriteS('priority error') |
      spaceerr:             WriteS('stack overflow') |
      rangeerr:             WriteS('range error') |
      addressoverflow:      WriteS('address overflow') |
      realoverflow:         WriteS('REAL overflow') |
      cardinaloverflow:     WriteS('CARDINAL overflow') |
      integeroverflow:      WriteS('INTEGER overflow') | 
      functionerr:          WriteS('function return error') | 
      halted:               WriteS('HALT called') | 
      asserted:             WriteS('Assertion error') | 
      warned:               WriteS('warning') | 
      stopped:              WriteS('stopped') | 
      callerr:              WriteS('Call error') |
      programnotfound:      WriteS('program not found') |
      programalreadyloaded: WriteS('program already loaded') |
      modulenotfound:       WriteS('module not found') |
      incompatiblemodule:   WriteS('incompatible module') |
      maxspaceerr:          WriteS('not enough space') |
      maxmoduleerr:         WriteS('too many modules') |
      codekeyerr:           WriteS('illegal type of code') |
      filestructureerr:     WriteS('error in filestructure') |
      fileerr:              WriteS('some file error') |
      loaderr:              WriteS('some load error') 
    ELSE
      Write(' ');
      WriteString('illegal Program Status:');
      WriteOct(CARDINAL(st)) 
    END; 
  END WriteStatus; 

  PROCEDURE WriteCard(c: CARDINAL);
    VAR base: CARDINAL;
  BEGIN
    base := 1;
    WHILE base <= c DIV 10 DO base := 10 * base END;
    REPEAT
      Write(CHR(ORD('0') + c DIV base));
      c := c MOD base;
      base := base DIV 10
    UNTIL base = 0;
  END WriteCard;

  PROCEDURE ReadCard(VAR c: CARDINAL; min, max, default: CARDINAL; fccs, efccs: CCS);
  BEGIN
    WHILE NOT (cc IN fccs + efccs + CCS{digit}) DO NextChar END;
    IF cc = digit THEN
      c := 0;
      REPEAT
        c := 10*c + ORD(ch) - ORD('0');
        IF c <= max THEN Write(ch) ELSE c := c DIV 10 END;
        REPEAT
          NextChar;
        UNTIL (cc IN CCS{digit} + efccs) OR (c >= min) AND (cc IN fccs);
      UNTIL cc IN fccs + efccs;
    ELSE
      c := default;
      IF cc IN fccs THEN WriteCard(c) END;
    END;
  END ReadCard;

  PROCEDURE ConvertPassword(password: ARRAY OF CHAR; VAR pw1, pw2: CARDINAL);
    VAR c, h: CARDINAL;
  BEGIN
    pw1 := 0; pw2 := 0;
    c := 0;
    WHILE (c <= HIGH(password)) AND (password[c] <> 0C) DO
      h := pw2; pw2 := pw1;
      pw1 := (h MOD 509 + 1) * 127 + ORD(password[c]);
      INC(c)
    END
  END ConvertPassword;

  
BEGIN
  (* initialize the scanner variables (condition for the searcher) *)
  pos := 0;

  (* Write the status of previous program. *)
  prevst := PreviousStatus();
  IF prevst <> normal THEN
    IF (prevst <> normal) AND
       (prevst <> warned) AND
       (prevst <> modulenotfound) AND
       (prevst <> incompatiblemodule)
    THEN 
      WriteStatus(prevst); WriteLn; 
    END;
    RETURN
  END;
  
  IF Login() THEN
    WriteString(versiontext);
    WriteString('  ');
    WriteString(versiondate);
    WriteLn; WriteLn;
    GetTime(t);
    IF t.day <= firstday THEN
      t.day := firstday;
      SetTime(t);
    END;
    Lookup(f, 'DK.SEK.Login.INFO', TRUE);
    IF f.res = done THEN
      ReadWord(f, dday);
      IF f.eof OR (dday <= firstday) THEN dday := defaultday END;
      ReadWord(f, defg); ReadWord(f, defm);
      IF f.eof THEN  defg := nogroup; defm := nomember END;
    ELSE defg := nogroup; defm := nomember;
    END;
    dd := dday MOD 40B;
    dm := dday DIV 40B MOD 20B;
    dy := dday DIV 1000B;
    WriteString(' old date = ');
    WriteCard(dd); Write('.');
    WriteCard(dm); Write('.');
    WriteCard(dy); WriteLn;
    IF t.day <> dday THEN
      LOOP
        WriteString(' new date > ');
        NextChar;
        ReadCard(d, 1, 31, dd, CCS{blank, lineend, point}, CCS{delete, escape, cancel});
        IF cc IN CCS{blank, lineend, point} THEN Write('.') END;
        IF ch = '.' THEN NextChar END;
        ReadCard(m, 1, 12, dm, CCS{blank, lineend, point}, CCS{delete, escape, cancel});
        IF cc IN CCS{blank, lineend, point} THEN Write('.') END;
        IF ch = '.' THEN NextChar END;
        ReadCard(y, 1, 99, dy, CCS{blank, lineend}, CCS{delete, escape, cancel});
        WriteLn;
        IF cc IN CCS{blank, lineend} THEN
          GetTime(t); 
          t.day := (y * 20B + m) * 40B + d;
          SetTime(t);
          GetTime(t);
          IF t.day > firstday THEN EXIT END;
        END;
      END;
    END;
    WriteLn;
    WriteString(" old user = ");
    IF defg = nogroup THEN WriteString("no previous user");
    ELSE WriteCard(defg); Write(':'); WriteCard(defm);
    END;
    WriteLn;
    LOOP
      WriteString(" new user > ");
      NextChar;
      ReadCard(actg, 0, 177777B, defg, CCS{blank, lineend, colon}, CCS{delete, escape, cancel});
      IF actg <> nogroup THEN
        IF cc IN CCS{blank, lineend, colon} THEN Write(':') END;
        IF ch = ':' THEN NextChar END;
        ReadCard(actm, 0, 177777B, defm, CCS{blank, lineend}, CCS{delete, escape, cancel});
      END;
      IF ch = esc THEN actg := nogroup END;
      IF actg = nogroup THEN
        WriteString("  -- no user");
        actm := nomember;
      END;
      WriteLn;
      IF NOT (cc IN CCS{delete, cancel}) THEN EXIT END;
    END;
    WriteLn;
    u.member := actm; u.group := actg;
    WriteString(" password > ");
    c := 0;
    REPEAT
      NextChar;
      IF ((cc = letter) OR (cc = digit) AND (c > 0)) AND (c < pwlength) THEN
        pw[c] := ch; INC(c); Write('%');
      ELSIF (ch = del) AND (c > 0) THEN
        DEC(c); Write(del);
      ELSIF cc IN CCS{escape, cancel} THEN
        WHILE c > 0 DO DEC(c); Write(del); END;
      END;
    UNTIL cc IN CCS{blank, lineend, escape};
    IF c = 0 THEN WriteString("  -- no password") END;
    WriteLn; WriteLn;
    IF c < pwlength THEN pw[c] := 0C END;
    ConvertPassword(pw, u.password1, u.password2);
    SetUser(u, ok);
    Reset(f);
    SetModify(f);
    WriteWord(f, t.day);
    WriteWord(f, u.group);
    WriteWord(f, u.member);
    Close(f);
    LeaveLogin;
    Lookup(f, startfile, FALSE);
    ok := f.res = done;
    IF ok THEN
      Close(f);
      NextProgram(commandfile); SetParameter(startfile);
    END;
    RETURN;
  END;
  
  (* Read the name of next program to execute. *) 
  REPEAT

    Write(promtchar); 

    pos := 0; oldpos := 0; tabulated := FALSE;
    LOOP
      letexp := (pos = 0) OR (name[pos-1] = '.');
      nodotexp := letexp OR (pos=namelength-1); 
  
      LOOP (* get next ch *)
        IF tabulated THEN
          ch := 0C;
        ELSE
          BusyRead(ch);
          IF ch <> 0C THEN
            IF diskok THEN idle := FALSE
            ELSE ch := 0C (* ignore keyboard *)
            END;
          END;
          IF ch = ' ' THEN 
            tabulated := TRUE; ch := 0C;
            REPEAT Pass UNTIL filled AND (selectpos >= pos);
          END;
        END;
        fromterminal := ch <> 0C;
        IF fromterminal THEN
          IF selectpos > pos THEN selectpos := pos END;
          cc := CharClass(ch);
          EXIT;
        ELSIF selectpos > pos THEN
          ch := selectname[pos];
          cc := CharClass(ch);
          EXIT;
        ELSIF tabulated THEN
          ch := ' '; cc := blank; tabulated := FALSE;
          EXIT
        END;
        Pass;
      END; (* LOOP *)
  
      cch := CAP(ch);
      IF ch = del THEN
        IF pos <= selectpos THEN c := deltab[pos] ELSE c := 1 END;
        DEC(pos, c);
        WHILE c > 0 DO Write(del); DEC(c) END;
        oldpos := pos;
        IF selectpos >= pos THEN selectpos := pos - deltab[pos] END;
      ELSIF (ch = can) OR (ch = esc) THEN
        WHILE pos > 0 DO DEC(pos); Write(del) END;
        selectpos := 0; oldpos := 0;
        IF ch = esc THEN
          WriteString(' End SEK.Comint'); WriteLn;
          EXIT
        END;
      ELSIF ((ch=eol) OR (ch=' ')) AND (pos=0) THEN WriteLn; EXIT
      ELSIF (ch=ff) AND (pos=0) THEN Write(ch); EXIT
      ELSIF ch = '?' THEN
        Write('?'); WriteLn;
        ListNames;
        c := 0;
        Write(promtchar);
        WHILE c < pos DO Write(name[c]); INC(c) END;
      ELSE
        let := ('A' <= cch) AND (cch <= 'Z');
        dig := ('0' <= ch) AND (ch <= '9');
        dot := ch = '.';
        IF let OR dig OR dot THEN
          IF fromterminal AND (oldpos < pos) AND (ch = name[oldpos]) THEN
            INC(oldpos);
          ELSIF (pos < namelength) AND
                (let OR NOT letexp) AND
                (NOT dot OR NOT nodotexp)
          THEN
            name[pos] := ch; Write(ch); INC(pos);
            IF fromterminal THEN oldpos := pos END;
          END
        ELSIF NOT letexp  AND ((ch = eol) OR (ch = ' ')) THEN
          IF pos < namelength THEN name[pos] := 0C END;
          WriteLn;
          CheckName;
          IF checked AND found AND selectsys AND (pos <= namelength-4) THEN
            FOR c := namelength-1 TO 4 BY -1 DO
              name[c] := name[c-4];
            END;
            name[0] := 'S'; name[1] := 'Y';
            name[2] := 'S'; name[3] := '.';
          END;
          NextProgram(name);
          EXIT
        END;
      END;
    END;
  UNTIL (pos > 0) OR (ch = esc);
  
END Comint.
  
