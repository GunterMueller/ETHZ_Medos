MODULE update; (* WW 27.6.83 *)

FROM Terminal IMPORT
  Read, Write, WriteString, WriteLn;
FROM CursorStuff IMPORT
  MenuSelection;
FROM FileSystem IMPORT
  File, Response, Create, Lookup, Close, Rename, Reset, ReadChar;
FROM FileNames IMPORT
  ReadFileName;
FROM String IMPORT
  Copy, Insert, InsertCh, first, last;
FROM HermesLine IMPORT
  FileName;
FROM Hermes IMPORT
  InitConnection, XferFile;
FROM Monitor IMPORT
  Time;
FROM UpdateTimeIO IMPORT
  WriteTime;
FROM UpdateProfileIO IMPORT
  OpenProfile, ReadDirectories, GetDirectoryName, GetDirectoryTime,
  MarkUserProfile, CloseProfile;
FROM UpdateDirInput IMPORT
  DirEntry, ReleaseCode, OpenDirectory, GetNextEntry, CloseDirectory;


CONST
  FF  = 14c;
  ESC = 33c;
  EOL = 36c;

TYPE
  YesNo = (Yes, No, Esc);

VAR
  querryDelete,
  querryCopy,
  ok: BOOLEAN;
  numberOfDirectories,
  d: CARDINAL;


PROCEDURE GetYesNoAnswer (question, menu: ARRAY OF CHAR; VAR answer: YesNo);
VAR
  menuText: ARRAY [0..199] OF CHAR;
  ch: CHAR;
  command: CARDINAL;
BEGIN
  WriteString(question);
  Copy(menuText,menu,first,last);
  Insert(menuText,last,"|yes|no|esc");
  LOOP
    ch := ' ';
    command := MenuSelection(menuText);
    CASE command OF
    0:
      Read(ch);
      IF CAP(ch) = 'Y' THEN answer := Yes;
      ELSIF CAP(ch) = 'N' THEN answer := No;
      ELSIF ch = ESC THEN answer := Esc;
      ELSE ch := '?';
      END; |
    1: 
      ch := '?'; |
    2:
      answer := Yes; |
    3:
      answer := No; |
    4:
      answer := Esc;
    END;
    IF ch = '?' THEN
      Write('?');
    ELSE
      CASE answer OF
      Yes:
        WriteString("yes"); |
      No:
        WriteString("no"); |
      Esc:
        WriteString("esc");
      END;
      EXIT;
    END;
  END;
END GetYesNoAnswer;


PROCEDURE Prompt (max: CARDINAL; VAR d: CARDINAL; VAR delQuerry,copQuerry: BOOLEAN);
VAR
  menuString: ARRAY [0..199] OF CHAR;
  name: FileName;
  ch: CHAR;
  response: YesNo;

BEGIN
  WriteString(" which directory do you want to update:");
  WriteLn;
  menuString := "*UPDATE";
  FOR d := 1 TO max DO
    InsertCh(menuString,last,'|');
    GetDirectoryName(d,name);
    Insert(menuString,last,name);
  END;
  Insert(menuString,last,"|esc");

  LOOP
    d := MenuSelection(menuString);
    IF d = 0 THEN
      Read(ch);
      IF ch = ESC THEN
        WriteString(" esc");
        EXIT;
      END; 
    ELSIF d > max+1 THEN
      d := 0;
      EXIT;
    ELSIF d > 1 THEN
      DEC(d);
      EXIT;
    END;
  END;

  IF d > 0 THEN
    GetYesNoAnswer(" delete/querry ? (y/n) ","*DELETE/Q",response);
    CASE response OF
    Yes:
      delQuerry := TRUE; |
    No:
      delQuerry := FALSE; |
    Esc:
      d := 0;
    END;
    IF d > 0 THEN
      WriteLn;
      GetYesNoAnswer(" copy/querry ? (y/n) ","*COPY/Q",response);
      CASE response OF
      Yes:
        copQuerry := TRUE; |
      No:
        copQuerry := FALSE; |
      Esc:
        d := 0;
      END;
    END;
  END;
  WriteLn;
END Prompt;


PROCEDURE UpdateDirectory (d: CARDINAL; delQuerry,copQuerry: BOOLEAN);
VAR
  ok, eof,
  escaped: BOOLEAN;
  dirName: FileName;
  lastDate: Time;
  dirEntry: DirEntry;


PROCEDURE TryToDelete (name: FileName; VAR exit: BOOLEAN);
VAR response: YesNo;

  PROCEDURE Delete (name: FileName);
  VAR file: File;
  BEGIN
    Insert(name,first,"DK.");
    Lookup(file,name,FALSE);
    IF file.res = done THEN
      Rename(file,"");
      Close(file);
      WriteString(" deleted");
    ELSE
      WriteString(" ---- file did not exist");
    END;
  END Delete;

BEGIN
  exit := FALSE;
  IF delQuerry THEN
    GetYesNoAnswer(" ? (y/n) ","*DELETE",response);
    CASE response OF
    Yes:
      Delete(name); |
    No:
      |
    Esc:
      exit := TRUE;
    END;
  ELSE
    Delete(name);
  END;
END TryToDelete;


PROCEDURE TryToCopy (name: FileName; VAR exit: BOOLEAN);
VAR
  ch: CHAR;
  localName: FileName;
  response: YesNo;
  command: CARDINAL;

  PROCEDURE Copy (from,to: FileName);
  VAR
    file: File;
    ok: BOOLEAN;
  BEGIN
    Lookup(file,to,TRUE);
    IF file.res = done THEN
      XferFile(from,file,ok);
      IF NOT ok THEN WriteString(" ---- xfer not done"); END;
      Close(file);
    ELSE
      WriteString(" ---- open file not done;");
    END;
  END Copy;

BEGIN
  exit := FALSE;
  Insert(name,first,"DK.");
  IF copQuerry THEN
    GetYesNoAnswer(" ? (y/n) ","*COPY",response);
    CASE response OF
    Yes:
      LOOP
        WriteString(" to> ");
        command := MenuSelection("*FileName|use default|esc");
        IF command = 0 THEN
          ReadFileName(localName,name);
          Read(ch);
          IF localName[0] <> 0c THEN EXIT; END;
          IF (ch = EOL) OR (ch = ' ') THEN command := 2;
          ELSIF ch = ESC THEN command := 3;
          ELSE command := 1;
          END;
        END;
        CASE command OF
        1:
          WriteLn; |
        2:
          localName := name;
          WriteString(localName);
          EXIT; |
        3:
          WriteString("esc");
          exit := TRUE;
          RETURN;
        END;
      END;
      Copy(name,localName); |
    No:
      |
    Esc:
      exit := TRUE;
    END;
  ELSE
    Copy(name,name);
  END;
END TryToCopy;


BEGIN (* UpdateDirectory *)
  OpenDirectory(d,dirEntry,ok);
  IF ok THEN
    GetDirectoryTime(d,lastDate);
    escaped := FALSE;
    LOOP
      WITH dirEntry DO
        IF code = toDelete THEN
          IF delQuerry THEN WriteString(" delete ");
          ELSE WriteString(" deleting ");
          END;
        ELSE
          IF copQuerry THEN WriteString(" update ");
          ELSE WriteString(" updating ");
          END;
        END;
        WriteString(name);
        WriteString(" of ");
        WriteTime(date,Write,0c);
        IF code = toDelete THEN TryToDelete(name,escaped);
        ELSE TryToCopy(name,escaped);
        END;
        WriteLn;
        IF escaped THEN EXIT; END;
        lastDate := date;
      END;
      GetNextEntry(dirEntry,eof);
      IF eof THEN EXIT; END;
    END;
    MarkUserProfile(d,lastDate);
  END;
  CloseDirectory;
END UpdateDirectory;


BEGIN (* update *)
  OpenProfile(ok);
  IF NOT ok THEN RETURN; END;
  ReadDirectories(numberOfDirectories);
  InitConnection(ok);
  IF NOT ok THEN
    WriteString(" ---- no connection to master disk");
    WriteLn;
  ELSE
    LOOP
      Prompt(numberOfDirectories,d,querryDelete,querryCopy);
      IF d = 0 THEN EXIT; END;
      UpdateDirectory(d,querryDelete,querryCopy);
    END;
  END;
  CloseProfile;
  Write(FF);
END update.
