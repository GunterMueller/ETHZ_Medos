(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          Program CommandFile:        *
*                                      *
*          CommandFile executes a      *
*          command file                *
*                                      *
*          Version 4  21.06.82         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

MODULE CommandFile;

  FROM FileSystem IMPORT File, Response, Lookup, Close, ReadChar;
  IMPORT TerminalBase;
  FROM FileNames IMPORT ReadFileName;
  FROM Terminal IMPORT Read, Write, WriteString, WriteLn;
  FROM SEK IMPORT CallComint;
  FROM Program IMPORT Status;

  CONST
    esc = 33C;
    eol = 36C;
    can = 30C;
    fnlength = 32;

  TYPE
    FileName = ARRAY [0..fnlength-1] OF CHAR;

  VAR
    ch: CHAR;
    inf: File; inch: CHAR;
    fn: FileName;
    ok: BOOLEAN;
    st: Status;

  PROCEDURE ReadProc(VAR ch: CHAR);
  BEGIN
    IF inf.eof THEN TerminalBase.Read(ch)
    ELSE
      ch := inch;
      REPEAT
        ReadChar(inf, inch);
      UNTIL (inch <> 0C) OR inf.eof;
    END;
  END ReadProc;

BEGIN
  LOOP
    WriteString(' command file > ');
    ReadFileName(fn, 'DK..COM');
    Read(ch);
    WHILE (ch <> esc) AND (ch <> can) AND (ch <> eol) AND (ch <> ' ') DO
      Read(ch)
    END;
    IF ch = esc THEN WriteString('  - no file'); WriteLn; EXIT END;
    IF fn[0] = 0C THEN WriteLn;
    ELSE
      Lookup(inf, fn, FALSE);
      IF inf.res = done THEN
        WriteLn;
        ReadChar(inf, inch);
        IF NOT inf.eof THEN
          TerminalBase.AssignRead(ReadProc, ok);
          IF NOT ok THEN
            WriteString(' - assignment of readprocedure to "TerminalBase" failed'); 
            WriteLn;
          ELSE
            REPEAT
              CallComint(FALSE, st);
            UNTIL inf.eof OR (st <> normal)
          END;
        END;
        Close(inf);
        EXIT
      ELSE WriteString(' - file not found'); WriteLn;
      END;
    END;
  END;
  WriteString(" End command file"); WriteLn;
END CommandFile.
