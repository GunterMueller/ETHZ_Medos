MODULE showstyle;  (*

Werner Winiger, Diser AG, Haldeneggsteig 5, CH-8006 Zuerich

Version 1.1: 15.1.83
Version 1.2: 16.5.83: ReadStyleName fixed *)


FROM FileSystem IMPORT 
  File, Response, Lookup, Close, ReadChar;
FROM Options IMPORT 
  FileNameAndOptions, GetOption, Termination;
FROM FileNames IMPORT 
  ReadFileName;
FROM Terminal IMPORT 
  Write, WriteString, WriteLn, Read;


CONST
  DocumentKey = 340c;
  DocumentVersion = 0;
  BOT = 300c; (* begin of tree *)
  LTN = 304c; (* long text node *)
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
  length   : CARDINAL;
  continue,
  ok       : BOOLEAN;


PROCEDURE ShowStyleName;
  VAR ch: CHAR;

    PROCEDURE ReadHeader; (* key, version, style *)

      PROCEDURE ReadStyleName;
        VAR i: CARDINAL;
        BEGIN
          i := 0;
          LOOP
            ReadChar(f,ch);
            IF (ch < BOT) OR (ch > LTN) THEN
              IF i > 31 THEN
                WriteString(' ---- style name too long');
                EXIT;
              END;
              Write(ch);
            ELSE
              EXIT;
            END;
            INC(i);
          END;
        END ReadStyleName;

    BEGIN (* ReadHeader *)
        ReadChar(f,ch); (* key mod 400b *)
        IF ch # DocumentKey THEN
          WriteString('illegal document key');
        ELSE
          ReadChar(f,ch);
          IF ch # CHR(DocumentVersion DIV 400b) THEN
            WriteString('illegal document version');
          ELSE
            ReadChar(f,ch);
            IF ch # CHR(DocumentVersion MOD 400b) THEN
              WriteString('illegal document version');
            ELSE
              ReadStyleName;
            END;
          END;
        END;
    END ReadHeader;

BEGIN
  ReadChar(f,ch);
  WriteString(': ');
  IF ch = 0c THEN ReadHeader;
  ELSE WriteString('is not an andra document');
  END;
END ShowStyleName;


BEGIN
  REPEAT
    WriteString(' get style of document> ');
    FileNameAndOptions('DK.tem.DOC',fN,term,TRUE);
    IF term <> normal THEN
      WriteLn;
      RETURN; 
    END;
    ok := TRUE;
    Lookup(f,fN,FALSE);
    IF f.res <> done THEN
      WriteString(' not found');
      WriteLn;
      ok := FALSE;
    END;
    continue := FALSE;
    LOOP
      GetOption(opt,length);
      IF length = 0 THEN EXIT; END;
      IF opt[0] = 'C' THEN  
        continue := TRUE;
      ELSE 
        WriteString(' illegal option: ');
        WriteString(opt);
        WriteLn;
        ok := FALSE;
        EXIT;
      END;
    END;
    IF ok THEN
      ShowStyleName;
      WriteLn;
    END;
    Close(f);
  UNTIL NOT continue;
END showstyle.
