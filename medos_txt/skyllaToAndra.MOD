MODULE skyllaToAndra; (*

Werner Winiger, Diser AG, Haldeneggsteig 5, CH-8006 Zuerich

Version 1.1: 14.2.83
Version 1.2: 16.5.83 *)

IMPORT FileSystem, Terminal;
FROM Terminal IMPORT
  Read, Write, WriteString, WriteLn;
FROM FileNames IMPORT
  ReadFileName;
FROM String IMPORT
  last, Length, Insert, InsertCh, Delete, Copy;
FROM LongSet IMPORT
  LONGSET, Contains, LongSetFromElement, EmptyLongSet, Include, Union;


CONST
  key = 340c;
  version = 0c;
  styleName = "DK.Skylla.STL";

  HT  = 11c;
  DEL = 177c;
  BOT = 300c; (* begin of tree *)
  EOT = 301c; (* end of tree *)
  STN = 302c;
  NTN = 303c;
  LTN = 304c;

  ESC = 33C;
  FS  = 34c;
  EOP = 35C;
  EOL = 36C;
  US = 37C;

  paragraphLook = 1;
  programLook = 2;
  formulaLook = 3;
  noteLook = 4;
  tableLook = 5;
  captionLook = 6;
  hilightLook = 11;
  emphasizeLook = 12;
  indentLook = 13;
  subtitleLook = 17;
  titleLook = 18;
  maintitleLook = 19;
  fontLook = 30;
  layoutLook = 31;


TYPE
  FormatMode = (NoFill, Fill);
  Command = (FirstPrio, SecondPrio, ThirdPrio, Ignore, Undefined);

VAR
  done: BOOLEAN;
  tempText,
  outDoc,
  inDoc: FileSystem.File;
  inName,
  outName,
  docName: ARRAY [0..31] OF CHAR;



PROCEDURE Document;

  PROCEDURE Write (ch: CHAR);
  BEGIN
    FileSystem.WriteChar(outDoc,ch);
  END Write;

  PROCEDURE WriteHeader;
  VAR
    i: CARDINAL;
    s: ARRAY [0..31] OF CHAR;
  BEGIN
    Write(0c);
    Write(key);
    Write(0c);
    Write(version);
    s := styleName;
    i := 0;
    REPEAT
      Write(s[i]);
      INC(i);
    UNTIL s[i] = 0c;
  END WriteHeader;


  PROCEDURE ProcessFile;
  VAR 
    l: CARDINAL;
    ch: CHAR;
    firstNode: BOOLEAN;
    paraLooks,
    lastLooks,
    altLooks: LONGSET;
    curFont: CARDINAL;
    curMode: FormatMode;


    PROCEDURE ReadCh;
    BEGIN
      FileSystem.ReadChar(inDoc,ch);
    END ReadCh;
      

    PROCEDURE StartTopNode;
    BEGIN
      Write(BOT);
      Write(CHAR(340b+layoutLook));
    END StartTopNode;


    PROCEDURE TerminateTopNode;
    BEGIN
      Write(EOT);
    END TerminateTopNode;


    PROCEDURE ProcessLooks;
    VAR
      command: Command;
      dummy: LONGSET;

      PROCEDURE FormatLine;
      VAR tem: CARDINAL;

        PROCEDURE ReadNum (VAR num: CARDINAL);
        BEGIN num := 0;
          REPEAT ReadCh UNTIL ch # " ";
          WHILE ("0" <= ch) & (ch <= "9") DO
            num := 10*num + CARDINAL(ch) - 60B; ReadCh
          END
        END ReadNum;

        PROCEDURE SkipTabs;
        BEGIN
          REPEAT
            ReadNum(tem);
          UNTIL (ch = ".");
        END SkipTabs;

        PROCEDURE Enter (comm: Command; look: CARDINAL;
                         mode: FormatMode; font: CARDINAL);
        BEGIN
          CASE command OF
          Undefined, Ignore, ThirdPrio:
            command := comm;
            IF comm = ThirdPrio THEN
              Include(altLooks,look);
            ELSIF (comm = SecondPrio) OR (comm = FirstPrio) THEN
              paraLooks := LongSetFromElement(look);
              curMode := mode;
              IF font < 8 THEN curFont := font; END;
            END; |
          SecondPrio:
            IF comm = ThirdPrio THEN
              Include(altLooks,look);
            ELSIF (comm = SecondPrio) OR (comm = FirstPrio) THEN
              command := comm;
              paraLooks := LongSetFromElement(look);
              curMode := mode;
              IF font < 8 THEN curFont := font; END;
            END; |
          FirstPrio:
            IF comm = ThirdPrio THEN
              Include(altLooks,look);
            ELSIF comm = FirstPrio THEN
              command := comm;
              paraLooks := LongSetFromElement(look);
              curMode := mode;
              IF font < 8 THEN curFont := font; END;
            END;;
          END;
        END Enter;

      BEGIN (* FormatLine *)
        WHILE ch # EOL DO
          IF ch = "+" THEN
            Enter(FirstPrio,paragraphLook,Fill,0);
            ReadCh;
          ELSIF ch = "-" THEN
            Enter(FirstPrio,programLook,NoFill,7);
            ReadCh;
          ELSIF ch = "=" THEN
            Enter(FirstPrio,programLook,NoFill,7);
            ReadCh;
          ELSIF ch = "<" THEN
            Enter(FirstPrio,noteLook,Fill,3);
            ReadCh;
          ELSIF ch = "/" THEN
            Enter(FirstPrio,formulaLook,NoFill,0);
            ReadCh;
          ELSIF ch = "T" THEN
            Enter(FirstPrio,tableLook,NoFill,7);
            ReadCh;
          ELSIF ch = ":" THEN
            Enter(FirstPrio,captionLook,Fill,0);
            ReadCh;
          ELSIF ch = "A" THEN
            Enter(FirstPrio,maintitleLook,NoFill,5);
            ReadCh;
          ELSIF ch = "B" THEN
            Enter(FirstPrio,titleLook,NoFill,4);
            ReadCh;
          ELSIF ch = "C" THEN
            Enter(FirstPrio,subtitleLook,NoFill,2);
            ReadCh;
          ELSIF ch = "a" THEN 
            Enter(SecondPrio,paragraphLook,Fill,0);
            ReadCh;
          ELSIF ch = "n" THEN 
            Enter(SecondPrio,formulaLook,NoFill,0);
            ReadCh;
          ELSIF ch = "c" THEN 
            Enter(SecondPrio,captionLook,Fill,0);
            ReadCh;
          ELSIF ch = "x" THEN
            ReadNum(tem);
            IF tem > 0 THEN Enter(ThirdPrio,indentLook,NoFill,8); END;
          ELSIF ch = "f" THEN
            ReadCh;
            IF ch = "1" THEN Enter(ThirdPrio,hilightLook,NoFill,8);
            ELSIF ch = "2" THEN Enter(ThirdPrio,emphasizeLook,NoFill,8);
            ELSE Enter(Ignore,0,NoFill,8);
            END;
          ELSIF ch = "y" THEN
            Enter(Ignore,0,NoFill,8);
            ReadNum(tem);
          ELSIF ch = "Y" THEN
            Enter(Ignore,0,NoFill,8);
            ReadNum(tem);
          ELSIF ch = "w" THEN 
            Enter(Ignore,0,NoFill,8);
            ReadNum(tem);
          ELSIF ch = "t" THEN
            Enter(Ignore,0,NoFill,8);
            SkipTabs;
          ELSIF (ch = "p") THEN
            Enter(Ignore,0,NoFill,8);
            ReadCh;
          ELSE ReadCh;
          END
        END;
        ReadCh
      END FormatLine;

    BEGIN (* ProcessLooks *)
      paraLooks := EmptyLongSet();
      altLooks := EmptyLongSet();
      command := Undefined;
      REPEAT
        ReadCh; FormatLine;
      UNTIL (ch # EOP) OR inDoc.eof;

      dummy := paraLooks;
      IF command >= ThirdPrio THEN paraLooks := Union(altLooks,lastLooks);
      ELSE paraLooks := Union(altLooks,paraLooks);
      END;
      lastLooks := dummy;
    END ProcessLooks;


  PROCEDURE ProcessText (supressEOL: BOOLEAN);
  VAR
    blanks,
    length: CARDINAL;
    fontlook: LONGSET;

    PROCEDURE WriteTextNode (theLast: BOOLEAN);

      PROCEDURE WriteLooks (looks: LONGSET);
      VAR l: CARDINAL;
      BEGIN
        FOR l := 1 TO 31 DO
          IF Contains(looks,l) THEN
            Write(CHAR(340b+l));
          END;
        END;
      END WriteLooks;

      PROCEDURE WriteNode (looks: LONGSET);
      BEGIN
        IF length < 300b THEN
          Write(STN);
          WriteLooks(looks);
          Write(CHAR(length));
        ELSIF length <= 8000h THEN
          Write(NTN);
          WriteLooks(looks);
          Write(CHAR(length DIV 100h));
          Write(CHAR(length MOD 100h));
        ELSE
          Write(LTN);
          WriteLooks(looks);
          Write(0c);
          Write(0c);
          Write(CHAR(length DIV 100h));
          Write(CHAR(length MOD 100h));
        END;
      END WriteNode;

    BEGIN (* WriteTextNode *)
      IF length = 0 THEN RETURN; END;
      IF firstNode THEN
        IF theLast (* and the only *)THEN
          WriteNode(paraLooks);
        ELSE
          Write(BOT);
          WriteLooks(paraLooks);
          WriteNode(EmptyLongSet());
        END;
      ELSE
        WriteNode(fontlook);
      END;
      firstNode := FALSE;
      length := 0;
    END WriteTextNode;

  BEGIN (* ProcessText *)
    FileSystem.WriteChar(tempText,EOL); 
    length := 1;
    fontlook := EmptyLongSet();

    LOOP
      IF (ch = EOP) OR inDoc.eof THEN EXIT;
      ELSIF ch = " " THEN
        blanks := 0;
        REPEAT
          INC(blanks);
          ReadCh;
        UNTIL ch # " ";
        IF ch # EOL THEN
          INC(length,blanks);
          REPEAT
            FileSystem.WriteChar(tempText," ");
            DEC(blanks);
          UNTIL blanks = 0;
        END;
      ELSIF ch = EOL THEN
        ReadCh;
        IF supressEOL THEN
          IF ch = EOL THEN
            FileSystem.WriteChar(tempText,EOL);
            INC(length);
            REPEAT
              FileSystem.WriteChar(tempText,EOL);
              INC(length);
              ReadCh;
            UNTIL ch # EOL;
          ELSE
            FileSystem.WriteChar(tempText,' ');
            INC(length);
          END;
        ELSE
          FileSystem.WriteChar(tempText,EOL);
          INC(length);
        END;
      ELSIF ch = US THEN
        ReadCh;
        IF ch = " " THEN
          FileSystem.WriteChar(tempText,HT);
          INC(length)
        ELSIF (ch = "0") OR (ORD(ch)-ORD('0') = curFont) THEN
          WriteTextNode(FALSE);
          fontlook := EmptyLongSet();
        ELSIF ch = "1" THEN
          WriteTextNode(FALSE);
          fontlook := LongSetFromElement(hilightLook);
        ELSIF ch = "2" THEN
          WriteTextNode(FALSE);
          fontlook := LongSetFromElement(emphasizeLook);
        ELSIF (ch > "2") AND (ch <= "7") THEN
          WriteTextNode(FALSE);
          fontlook := LongSetFromElement(fontLook)
        END;
        ReadCh;
      ELSE
        FileSystem.WriteChar(tempText,ch);
        INC(length);
        ReadCh;
      END;
    END;
    IF supressEOL THEN
      FileSystem.WriteChar(tempText,EOL);
      INC(length);
    END;

    IF firstNode THEN
      WriteTextNode(TRUE);
    ELSE
      WriteTextNode(TRUE); (* WriteTextNode changes firstNode *)
      Write(EOT);
    END;
  END ProcessText;

  BEGIN (* ProcessFile *)
    StartTopNode;
    lastLooks := EmptyLongSet();
    curMode := NoFill;
    curFont := 0;
    ReadCh;
    IF ch # EOP THEN 
      paraLooks := EmptyLongSet();
      firstNode := TRUE;
      ProcessText(FALSE); 
    END;
    WHILE (NOT inDoc.eof) DO
      firstNode := TRUE;
      ProcessLooks;
      ProcessText(curMode <> NoFill);
    END;
    TerminateTopNode;
  END ProcessFile;

  PROCEDURE CopyText;
  VAR ch: CHAR;
  BEGIN
    FileSystem.Reset(tempText);
    LOOP
      FileSystem.ReadChar(tempText,ch);
      IF tempText.eof THEN EXIT; END;
      Write(ch);
    END;
    FileSystem.Reset(outDoc);
    IF outDoc.res # FileSystem.done THEN
      WriteString(' conversion not done'); WriteLn;
      HALT;
    END;
  END CopyText;

BEGIN (* Document *)
  WriteHeader;
  ProcessFile;
  CopyText;
END Document;

PROCEDURE OpenFiles (VAR ok: BOOLEAN);
VAR 
  ch: CHAR;
  i,j: CARDINAL;
BEGIN
  ok := FALSE;
  WriteString(" SkyllaToAndra 1.1"); WriteLn;
  FileSystem.Create(tempText,'DK');
  LOOP
    WriteString(' skylla file > ');
    ReadFileName(inName,'DK.tem.TEXT');
    Read(ch);
    IF ch = ESC THEN RETURN; END;
    FileSystem.Lookup(inDoc,inName,FALSE);
    IF inDoc.res = FileSystem.done THEN EXIT; END;
    WriteString(' file not found'); WriteLn;
  END;
  docName := inName;
  i := 0;
  LOOP
    IF docName[i] = '.' THEN j := i; END;
    INC(i);
    IF docName[i] = 0c THEN EXIT; END;
  END;
  docName[j] := 0c;
  outName := docName;
  Insert(outName,last,".DOC");
  LOOP
    WriteLn; WriteString(' andra doc   > ');
    ReadFileName(outName,outName);
    Read(ch);
    IF ch = ESC THEN RETURN; END;
    FileSystem.Lookup(outDoc,outName,TRUE);
    IF outDoc.res = FileSystem.done THEN EXIT; END;
    WriteString(' file not opened');
  END;
  WriteLn;
  ok := TRUE;
END OpenFiles;

PROCEDURE CloseFiles;
BEGIN
  FileSystem.Close(tempText);
  FileSystem.Close(outDoc);
  FileSystem.Close(inDoc);
END CloseFiles;

BEGIN
  OpenFiles(done);
  IF done THEN Document; END;
  CloseFiles;
END skyllaToAndra.
