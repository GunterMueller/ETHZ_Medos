MODULE list;  (* Werner Winiger 7.10.82 *)


FROM FileSystem IMPORT 
  File, Response, Lookup, Close, ReadChar;
FROM DisplayDriver IMPORT 
  ScreenHeight, LineHeight;
FROM Options IMPORT 
  FileNameAndOptions, GetOption, Termination;
FROM FileNames IMPORT 
  ReadFileName, Identifiers, IdentifierPosition;
FROM Terminal IMPORT 
  Write, WriteString, WriteLn, Read, BusyRead, ReadAgain;


CONST
  NULL  =  0c;
  FF    = 14c;
  HELP  = 23c;
  ESC   = 33c;
  EOL   = 36c;
  BLANK = 40c;


VAR
  opt,fN   : ARRAY[0..31] OF CHAR;
  term     : Termination;
  f        : File;
  ch       : CHAR;
  l, length,
  freeLines: CARDINAL;
  pageWise,
  ok       : BOOLEAN;


PROCEDURE List;
VAR 
  ch: CHAR;
  screenLines: CARDINAL;
BEGIN
  screenLines := ScreenHeight() DIV LineHeight() - 1;
  WriteLn;
  IF pageWise THEN
    LOOP
      freeLines := screenLines;
      REPEAT
        REPEAT
          ReadChar(f,ch);
          IF f.eof THEN EXIT; END;
          IF (ch >= BLANK) AND (ch <= 205c) OR (ch = EOL) THEN Write(ch);
          ELSE Write('?');
          END;
        UNTIL ch = EOL;
        DEC(freeLines);
      UNTIL freeLines = 0;

      WriteString('...');
      Read(ch);
      IF ch = ESC THEN 
        WriteLn;
        EXIT; 
      END;
      Write(FF);
    END;
  ELSE
    LOOP
      REPEAT
        ReadChar(f,ch);
        IF f.eof THEN EXIT; END;
        IF (ch >= BLANK) AND (ch <= 205c) OR (ch = EOL) THEN Write(ch);
        ELSE Write('?');
        END;
      UNTIL ch = EOL;
      BusyRead(ch);
      IF ch <> NULL THEN
        IF ch = ESC THEN EXIT; END;
        Read(ch);
        IF ch = ESC THEN EXIT; END;
      END;
    END;
    WriteLn;
  END;
END List;


BEGIN
  WriteString(' list> ');
  Read(ch);
  IF (ch = '?') OR (ch = HELP) THEN
    WriteString('available options are:'); WriteLn;
    WriteString(' P Paging'); WriteLn;
    WriteString(' list> ');
  ELSE
    ReadAgain;
  END;
  FileNameAndOptions('DK.tem.LST',fN,term,TRUE);
  IF term <> normal THEN
    WriteLn;
    RETURN; 
  END;
  
  Lookup(f,fN,FALSE);
  IF f.res <> done THEN
    WriteString(' not found');
    WriteLn;
    length := 1; (* to avoid listing *)
  ELSE
    pageWise := FALSE;
    LOOP
      GetOption(opt,length);
      IF length = 0 THEN EXIT; END;
      IF opt[0] = 'P' THEN  
        pageWise := TRUE;
      ELSE 
        WriteString(' illegal option: ');
        WriteString(opt);
        WriteLn;
        EXIT;
      END;
    END;
  END;
  IF length = 0 THEN List; END;
  Close(f);
END list.
