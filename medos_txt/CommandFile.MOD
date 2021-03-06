(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          Program SEK.CommandFile:    *
*                                      *
*          CommandFile executes a      *
*          commandfile for SEK         *
*                                      *
*          Version 4  18.06.82         *    
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
  FROM SEK IMPORT CallComint, GetParameter;
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
  GetParameter(fn);
  IF fn[0] <> 0C THEN
    Lookup(inf, fn, FALSE);
    IF inf.res = done THEN
      ReadChar(inf, inch);
      IF NOT inf.eof THEN
        TerminalBase.AssignRead(ReadProc, ok);
        IF ok THEN
          REPEAT
            CallComint(FALSE, st);
          UNTIL inf.eof OR (st <> normal);
        END;
      END;
      Close(inf);
    END;
  END;
END CommandFile.
