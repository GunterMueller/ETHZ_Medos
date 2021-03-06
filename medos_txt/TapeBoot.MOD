MODULE TapeBoot;
(* Jirka Hoppe   21/1/83
this module converts the format of a boot file as produced by
the program BootLink to the standart Motorola load format
this format may be loaded by the diagnostic processor *)
FROM Terminal IMPORT Read, Write, WriteString, WriteLn;
FROM FileSystem IMPORT File, Lookup, Close, WriteChar, ReadWord, Response;
FROM FileNames IMPORT ReadFileName;
FROM FileMessage IMPORT WriteResponse;

CONST maxLine = 10h;

VAR
  boot, tape : File;
  word       : CARDINAL;
  infn, outfn: ARRAY [0..24] OF CHAR;
  lineCount : CARDINAL;
  size      : CARDINAL;
  adr       : CARDINAL;
  xsum      : CARDINAL;
  i         : CARDINAL;
  ch        : CHAR;

PROCEDURE WriteHex(x : CARDINAL);
BEGIN
  IF x < 10 THEN WriteChar(tape, CHAR(x+ORD('0')))
  ELSE WriteChar(tape, CHAR(x+37h))
  END
END WriteHex;

PROCEDURE WriteByte(b : CARDINAL);
BEGIN
  WriteHex(b DIV 10h); WriteHex(b MOD 10h)
END WriteByte;

BEGIN
  WriteString('boot file>');
  ReadFileName(infn, 'DK..ABS'); Read(ch); WriteLn;
  Lookup(boot, infn, FALSE);
  IF boot.res <> done THEN
    WriteResponse(boot.res); RETURN
  END;

  WriteString('tape file>');
  ReadFileName(outfn, infn); Read(ch); WriteLn;
  Lookup(tape, outfn, TRUE);
  IF tape.res <> done THEN
    WriteResponse(tape.res); RETURN
  END;

  WriteChar(tape,'S'); WriteChar(tape,'0');
  WriteChar(tape,'0'); WriteChar(tape,'1');
  WriteChar(tape,'F'); WriteChar(tape,'E');
  WriteChar(tape, 36c);
  LOOP
    ReadWord(boot, size); (*size*)
    IF boot.eof OR (size=0) THEN EXIT END;

    ReadWord(boot, adr); (* address *)
    LOOP
      WriteChar(tape,'S'); WriteChar(tape,'2');
      IF size-1 > maxLine THEN lineCount := maxLine
      ELSE lineCount := size-1
      END;
      WriteByte(lineCount*2+3); (* count of bytes *)
      WriteByte(adr DIV 100H); WriteByte(adr MOD 100h); (* load adr *)
      xsum := ((lineCount*2+3)+ (adr DIV 256) + (adr MOD 256) )  MOD 256;
      FOR i := 1 TO lineCount DO
        ReadWord(boot, word);
        WriteByte(word DIV 100h); WriteByte(word MOD 100h);
        xsum := (xsum + (word DIV 256) + (word MOD 256) )  MOD 256;
      END;
      WriteByte(377b-xsum);
      WriteChar(tape, 36c);
      IF size -1> maxLine THEN
        size := size - maxLine;
      ELSE EXIT
      END;
      adr := adr + maxLine;
    END;
  END;
  WriteChar(tape,'S'); WriteChar(tape,'9');
  WriteChar(tape,'0'); WriteChar(tape,'1');
  WriteChar(tape,'F'); WriteChar(tape,'E');
  WriteChar(tape, 36c);

  Close(boot); Close(tape)
END TapeBoot.
