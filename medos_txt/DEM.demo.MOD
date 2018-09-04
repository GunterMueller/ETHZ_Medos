MODULE demo; (* Brook Richan 1.4.83 *)

FROM Program        IMPORT   Status, Call;
FROM ProgramMessage IMPORT   WriteStatus;
FROM Terminal       IMPORT   Read, Write, WriteString, WriteLn;
FROM FileSystem     IMPORT   File, Response, Lookup, Reset, ReadChar;
FROM FileNames      IMPORT   ReadFileName;
FROM Screen         IMPORT   LoadFont, Font, SetDefaultFont,
                              GetDefaultFont, GetDefaultBitmap,
                              GetMaxBlock, BlockDescriptor, Bitmap,
                              SetDotPos, GetDotPos, ReturnFont;
IMPORT TerminalBase;
IMPORT Terminal;

CONST
  FF = 14c;
  EOL = 36C;
  maxfonts = 5;

  CRcnvt   = 41C; (* ! *)
  ESCcnvt  = 43C; (* # *)
  WAITcnvt = 46C; (* & *)

  CRcode   = 36C;
  ESCcode  = 33C;
  WAITcode = 01C;

VAR
  runfile:   File;
  runname:   ARRAY [0..31] OF CHAR;

  fonts:   ARRAY [1..maxfonts] OF Font;
  fontdefined: ARRAY [1..maxfonts] OF BOOLEAN;

  command: CHAR;
  i:  CARDINAL;
  dfltfnt:   Font;
  s:  ARRAY [0..70] OF CHAR;

  SCRX:  CARDINAL;
  SCRY:  CARDINAL;


MODULE OwnTerminal; (* based on module by Werner Winiger *)

FROM TerminalBase IMPORT
  Read, AssignRead;
FROM Terminal IMPORT
  WriteString;

IMPORT WaitSeconds, WAITcode;

EXPORT DepositChar, DepositString, InitBuffer;

CONST
  bufferLength = 512;

VAR
  buffer: ARRAY [1..bufferLength] OF CHAR;
  bufferContent,
  in, out: CARDINAL;


PROCEDURE DepositChar (ch: CHAR);
BEGIN
  IF bufferContent < bufferLength THEN
    INC(bufferContent);
    buffer[in] := ch;
    in := (in MOD bufferLength) + 1;
  END;
END DepositChar;


PROCEDURE DepositString (s: ARRAY OF CHAR);
VAR i: CARDINAL;
BEGIN
  i := 0;
  LOOP
    IF s[i] = 0c THEN EXIT; END;
    DepositChar(s[i]);
    INC(i);
    IF i > HIGH(s) THEN EXIT; END;
  END;
END DepositString;


PROCEDURE FetchChar (VAR ch: CHAR);
BEGIN
  IF bufferContent = 0 THEN
    ch := 0c;
  ELSE
    DEC(bufferContent);
    ch := buffer[out];
    out := (out MOD bufferLength) + 1;
  END;
END FetchChar;


PROCEDURE KeyboardInput (VAR ch: CHAR);
BEGIN
  FetchChar(ch);
  REPEAT
    IF ch = 0c THEN
      Read(ch);
    ELSE
      IF ch = WAITcode THEN
        FetchChar(ch);
        WaitSeconds (ORD(ch));
        FetchChar(ch);
      END;
    END;
  UNTIL ch <> WAITcode;
END KeyboardInput;


PROCEDURE InitBuffer;
BEGIN
  bufferContent := 0;
  in := 1;
  out := 1;
END InitBuffer;


PROCEDURE InitOwnTerminal;
VAR ok: BOOLEAN;
BEGIN
  InitBuffer;
  AssignRead(KeyboardInput,ok);
  IF NOT ok THEN
    WriteString("assign to read not done ");
    HALT;
  END;
END InitOwnTerminal;

BEGIN
  InitOwnTerminal;
END OwnTerminal;


(* - - - - - *)


PROCEDURE ReadString (VAR f: File; VAR s: ARRAY OF CHAR);
VAR  i:  CARDINAL;
     ch: CHAR;
BEGIN
  i := 0;
  ReadChar (f, ch);
  WHILE (f.res = done) AND (f.eof = FALSE) AND (ch <> EOL) AND (i <= HIGH(s)) DO
    s [i] := ch;
    INC (i);
    ReadChar (f, ch);
  END;
  s [i] := 0C;
END ReadString;


PROCEDURE ReadInt (VAR f: File; VAR n: CARDINAL);
VAR  i:  INTEGER;
     ch: CHAR;
BEGIN
  n := 0;
  ReadChar (f, ch);
  WHILE (f.res = done) AND (ch > ' ') DO
    n := n * 10 + ORD(ch)-ORD('0');
    ReadChar (f, ch);
  END;
END ReadInt;


PROCEDURE WaitSeconds (nseconds: CARDINAL);
VAR    i,j,k: CARDINAL;
BEGIN
  FOR i := 1 TO nseconds DO
    FOR j := 1 TO 100 DO
      FOR k := 1 TO 1630 DO
      END;
    END;
  END;
END WaitSeconds;


PROCEDURE FontSet;
VAR  ch:  CHAR;
     fontnum: CARDINAL;
BEGIN
  ReadChar (runfile, ch);
  fontnum := ORD(ch)-ORD('0');
  IF fontnum > maxfonts THEN
    fontnum := maxfonts;
  END;
  IF fontnum = 0 THEN
    fontnum := 1;
  END;
  IF fontdefined [fontnum] = TRUE THEN
    SetDefaultFont (fonts [fontnum]);
  END;
END FontSet;


PROCEDURE PositionSet;
VAR x,y: CARDINAL;
BEGIN
  ReadInt (runfile, x);
  ReadInt (runfile, y);
  SetDotPos (x,SCRY - y);
END PositionSet;


PROCEDURE TextWrite;
VAR  s:  ARRAY [0..79] OF CHAR;
BEGIN
  ReadString (runfile, s);
  WriteString (s);
  SetDefaultFont (dfltfnt);
END TextWrite;


PROCEDURE Fontread;
VAR  ch:  CHAR;
     doneflag: BOOLEAN;
     fnt:  Font;
     fontnum: CARDINAL;
     fontname: ARRAY [0..31] OF CHAR;
BEGIN
  ReadChar (runfile, ch);
  fontnum := ORD(ch)-ORD('0');
  IF fontnum > maxfonts THEN
    fontnum := maxfonts;
  END;
  IF fontnum = 0 THEN
    fontnum := 1;
  END;
  ReadString (runfile, fontname);
  IF fontdefined [fontnum] = FALSE THEN
    LoadFont (fnt, fontname, doneflag);
    IF doneflag THEN
      fonts [fontnum] := fnt;
      fontdefined [fontnum] := TRUE;
    END;
  END;
END Fontread;


PROCEDURE Returnfont;
VAR  ch:  CHAR;
     fontnum: CARDINAL;
     dummy: ARRAY [0..31] OF CHAR;
BEGIN
  ReadChar (runfile, ch);
  fontnum := ORD(ch)-ORD('0');
  IF fontnum > maxfonts THEN
    fontnum := maxfonts;
  END;
  IF fontnum = 0 THEN
    fontnum := 1;
  END;
  ReadString (runfile, dummy);
  IF fontdefined [fontnum] = TRUE THEN
    ReturnFont (fonts [fontnum]);
    fontdefined [fontnum] := FALSE;
  END;
END Returnfont;


PROCEDURE Display;
VAR  ch:   CHAR;
     s:  ARRAY [0..79] OF CHAR;
     x,y:  CARDINAL;
BEGIN
  FontSet;
  ReadChar (runfile, ch); (* ignore space *)
  PositionSet;
  TextWrite;
END Display;


PROCEDURE Position;
BEGIN
  PositionSet;
END Position;


PROCEDURE Text;
BEGIN
  FontSet;
  TextWrite;
END Text;


PROCEDURE Wait;
VAR seconds: CARDINAL;
BEGIN
  ReadInt (runfile, seconds);
  WaitSeconds (seconds);
END Wait;


PROCEDURE CallProg;
VAR st: Status;
    progname: ARRAY [0..31] OF CHAR;
BEGIN
  ReadString (runfile, progname);
  Call(progname,FALSE,st);
  IF st <> normal THEN
    WriteStatus(st);
    WriteLn;
  END;
END CallProg;


PROCEDURE InsertForRead;
VAR i: CARDINAL;
    s: ARRAY [0..81] OF CHAR;
    ch: CHAR;
BEGIN
  ReadString (runfile, s);
  i := 0;
  WHILE (i <= HIGH(s)) AND (s [i] <> 0C) DO
    ch := s [i];
    INC (i);
    IF ch = CRcnvt THEN
      DepositChar (CRcode);
    ELSIF ch = ESCcnvt THEN
      DepositChar (ESCcode);
    ELSIF ch = WAITcnvt THEN
      DepositChar (WAITcode);
      DepositChar (CHR(ORD(s [i])-ORD('0')));
      INC (i);
    ELSE
      DepositChar (ch);
    END;
  END;
END InsertForRead;


PROCEDURE Init;
VAR  bm:  Bitmap;
     blk: BlockDescriptor;
BEGIN
  GetDefaultFont (dfltfnt);
  FOR i := 1 TO maxfonts DO
    fontdefined [i] := FALSE;
  END;
  GetDefaultBitmap (bm);
  GetMaxBlock (blk, bm);
  SCRX := blk.w;
  SCRY := blk.h;
END Init;


BEGIN
  Init;

  WriteString (' demo run file> ');
  ReadFileName (runname, 'DK..DEMO');
  Read (command);
  Lookup (runfile, runname, FALSE);

  WHILE runfile.res = done DO
    IF runfile.eof = TRUE THEN
      Reset (runfile);
    END;
    ReadChar (runfile, command);
    IF    command = 'f' THEN
      Fontread;
    ELSIF command = 'g' THEN
      Returnfont;
    ELSIF command = 'd' THEN
      Display;
    ELSIF command = 'p' THEN
      Position;
    ELSIF command = 't' THEN
      Text;
    ELSIF command = 'n' THEN
      WriteLn;
      ReadString (runfile, s);
    ELSIF command = 's' THEN
      Write (FF);
      ReadString (runfile, s);
    ELSIF command = 'w' THEN
      Wait;
    ELSIF command = 'c' THEN
      CallProg;
    ELSIF command = 'i' THEN
      InsertForRead;
    ELSIF command = 'r' THEN
      InitBuffer;
      ReadString (runfile, s);
    ELSE
      ReadString (runfile, s);
    END;
  END;

END demo.
