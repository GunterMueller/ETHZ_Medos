MODULE hpcopy; (*                               Werner Winiger 1.8.80
       ======                                   Jirka Hoppe 31.10.80 
                                                Werner Winiger 6.10.82 *)

                  IMPORT V24;
  FROM FileSystem IMPORT Lookup, File, Close, Response, ReadChar, WriteChar;
  FROM Terminal IMPORT Write, WriteLn, Read, ReadAgain, WriteString;
  FROM FileNames IMPORT ReadFileName;
  FROM FileMessage IMPORT WriteResponse;

  CONST
    DC1 = 21c;
    HB  = "  ";
    NULL= 0c;
    ESC = 33c;
    CR  = 15c;
    LF  = 12c;
    EOL = 36c;
    RS  = 36c;

  VAR
    online, ok, fromHP: BOOLEAN;
    name: ARRAY [0..32] OF CHAR;
    f: File;
    ch: CHAR;
    line : ARRAY [0..256] OF CHAR; (* local storage *)
    i, linx : CARDINAL; (* index in line *)

  PROCEDURE CheckHP (VAR ok: BOOLEAN); 
    VAR (*  -------                *)
      try: CARDINAL;
      ch: CHAR;
      got : BOOLEAN;
  BEGIN
    V24.BusyRead(ch, got); (* overread any character *)
    V24.Write(ESC); V24.Write('^'); V24.Write(DC1);
    ok := FALSE;
    try := 0;
    ch := NULL;
    LOOP
      V24.BusyRead(ch, got);
      IF got THEN EXIT END;
      INC(try);
      IF try = 42000 THEN RETURN END;
    END;

    ok := ch = ESC;

    FOR try := 0 TO 7ffh DO 
     V24.BusyRead(ch, got)
    END; 
   END CheckHP;

PROCEDURE StartLineRead;
BEGIN (*  --------------- *)
  V24.Write(ESC); V24.Write('&'); V24.Write('p');
  V24.Write('0'); V24.Write('R'); V24.Write(DC1);
END StartLineRead;

PROCEDURE WriteLine;
  VAR (*  --------- *)
    ch: CHAR;
BEGIN
  ReadChar(f,ch);
  IF f.eof THEN RETURN; END;

  V24.Write(ESC); V24.Write('&');
  V24.Write('p'); V24.Write('2');
  V24.Write('d'); V24.Write('W');

  LOOP 
    IF ch = EOL
    THEN  V24.Write(CR); V24.Write(LF); EXIT;
    ELSE V24.Write(ch);
    END;
    ReadChar(f,ch);
    IF f.eof THEN ch := EOL; END;
  END;

  V24.Write(DC1);
  V24.Read(ch); V24.Read(ch); V24.Read(ch); (* handshake: F/S, CR, LF *)
END WriteLine;

PROCEDURE MarkFile;
BEGIN (*  -------- *)
  V24.Write(ESC); V24.Write('&');
  V24.Write('p'); V24.Write('5');
  V24.Write('C');
END MarkFile;


BEGIN
  CheckHP(online);
  IF NOT online THEN
    WriteString(' HP not ready'); WriteLn;
    RETURN;
  END;

  LOOP
    WriteString(' copy from> ');
    Read(ch);
    IF ch = 'm' THEN
      fromHP := FALSE;
      WriteString('ME:');
      EXIT;
    ELSIF ch = 'y' THEN
      fromHP := TRUE;
      WriteString('YOU:');
      WriteLn;
      WriteString('        to> ME:');
      EXIT;
    END;
    Write(ch);
    Write('?');
    WriteLn;
  END;
  ReadFileName(name,"DK.Temp.MOD");
  Read(ch);

  Lookup(f,name,fromHP);
  IF f.res # done THEN
    WriteString(' Lookup '); WriteResponse(f.res);
  ELSE
    IF fromHP THEN
      LOOP (* file *)
        StartLineRead; linx := 0;
        LOOP (* one line *)
          V24.Read(ch);
          CASE ch OF
          RS:  EXIT;
        | CR:  V24.Read(ch);
               IF ch = LF
               THEN line[linx] := EOL;
               ELSE line[linx] := CR; INC(linx); line[linx] :=ch;
               END; EXIT;
        | LF:  line[linx] := EOL; EXIT;
          ELSE line[linx] := ch;
          END (*case*);
          INC(linx)
        END;
        IF (ch=RS) THEN EXIT END;
        FOR i := 0 TO linx DO WriteChar(f, line[i]) END;
      END;
    ELSE
      WriteLn;
      WriteString('        to> YOU:');
      REPEAT WriteLine; UNTIL f.eof;
      MarkFile;
    END;
    Close(f);
    WriteLn;
    WriteString(' done'); (* believe it or not *)
  END;
  WriteLn;
END hpcopy.
