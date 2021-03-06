MODULE dump; (* prl 11.2.81 *)

  (* integration of module OutBase: LG 16.06.82 *)

FROM SYSTEM IMPORT
  ADR;

FROM FileSystem IMPORT
  File,
  Lookup, Close,
  Response,
  SetPos,
  SetRead,
  SetWrite,
  WriteChar;

FROM FileMessage IMPORT
  WriteResponse;

FROM Options IMPORT
  Termination,
  FileNameAndOptions,
  GetOption;

FROM Terminal IMPORT
  Write,
  WriteLn,
  WriteString,
  BusyRead,
  Read;

FROM ByteBlockIO IMPORT
  ReadBytes;

CONST
  DefaultFileSpec = 'DK.OBJ';
  OutFileDefault  = 'DK.DMP';
  WordFieldWidth  = 8;
  ByteFieldWidth  = 4;
  HexByteWidth    = 2;
  OctalByteWidth  = 3;
  HexWordWidth    = 4;
  OctalWordWidth  = 6;
  Eol = 36C;
  Can = 30C;
  Esc = 33C;

TYPE
  OptNames = ( Byte, Word,        (* Options for size of dumped item *)
               Ascii, Octal, Hex, (* Options for format of dump *)
               Output, Query, Start, End,
               BadOpt
             );
  SizeOpts = [Byte..Word];
  FormOpts = [Ascii..Hex];
  FormSet  = SET OF FormOpts;
  FilePointer = POINTER TO File;

VAR
  FileName, SaveFileName: ARRAY [0..30] OF CHAR;
  Size: SizeOpts;
  Formats: FormSet;
  F,OutFile: File;
  OFP: FilePointer;
  Term: Termination;
  OptFlg: BOOLEAN;

  StartAd, EndAd: CARDINAL;
  EndSet: BOOLEAN;

PROCEDURE PrintHelp;
BEGIN
  WriteString('Commands are of the form:'); WriteLn; WriteLn;
  WriteString('    { filename } {"/"option}'); WriteLn; WriteLn;
  WriteString('If the filename is not specified then the previous name is used.');
  WriteLn;
  WriteString('If no options specifying output format are given,'); WriteLn;
  WriteString('then the previous format is used. The default format is /octal/word.');
  WriteLn;
  WriteString('If more than one display format (Ascii, Octal or Hexadecimal)');
  WriteLn;
  WriteString('is given then each dumped item will be displayed'); WriteLn;
  WriteString('in each of the formats given. E.g.'); WriteLn; WriteLn;
  WriteString('    /byte/ascii/hex'); WriteLn; WriteLn;
  WriteString('Will display bytes as both Ascii characters and hex. numbers.');
  WriteLn;
  WriteString('Ascii codes from 0C to 40C are displayed as the'); WriteLn;
  WriteString('corresponding control code (1C is displayed as ^A).'); WriteLn;
  WriteString('Ascii codes >= 177C are displayed as octal numbers.'); WriteLn;
  WriteString('The leftmost column of the output is the address of the data and is in Octal,');
  WriteLn;
  WriteString('unless the /hex option has been used, and then it is in hexadecimal.');
  WriteLn;
  WriteString('Unless the /OUtput option is used, the dump will appear on the screen.');
  WriteLn;
  WriteString('The output may be paused by typing any character except ESCAPE or ^C and');
  WriteLn;
  WriteString('restarted by typing another character. Typing ESCAPE will stop the printout');
  WriteLn;
  WriteString('and ask for another file to dump.'); WriteLn;
  WriteString('The options /OUtput, /Startaddress and /Endaddress will cause dump');
  WriteLn;
  WriteString('to  prompt for further input.'); WriteLn;
  WriteString('Options may be typed in either UPPER or lower case.'); WriteLn;
  WriteString('In the list of options following, UPPER case denotes the'); WriteLn;
  WriteString('minimum abbreviation of the option name.'); WriteLn;
END PrintHelp;


MODULE BaseInput;

IMPORT
  Write,
  WriteLn,
  Read,
  Eol,
  Can;

EXPORT
  ReadHex,
  ReadOctal;

PROCEDURE ReadHex(VAR n: CARDINAL);
VAR
  nread: CARDINAL;
  c:     CHAR;
BEGIN
  nread := 0;
  n := 0;
  LOOP
    Read(c);
    CASE c OF
    '0'..'9':
      IF n < 10000B THEN    (* Check for overflow *)
        n := n * 16 + (CARDINAL(c) - CARDINAL('0'));
        Write(c); INC(nread);
      END; |

    'A'..'F','a'..'f':
      IF n < 10000B THEN    (* Check for overflow *)
        n := n * 16 + (CARDINAL(CAP(c)) - CARDINAL('A') + 10);
        Write(c); INC(nread);
      END; |

    ' ',Eol:
      IF nread > 0 THEN
        WriteLn;
        EXIT;
      END; |

    177C:
      IF nread > 0 THEN
        Write(c);
        n := n DIV 16;
        DEC(nread);
      END; |

    Can:
      WHILE nread > 0 DO
        Write(177C);
        DEC(nread);
      END;
      n := 0;
    END;
  END;
END ReadHex;

PROCEDURE ReadOctal(VAR n: CARDINAL);
VAR
  nread: CARDINAL;
  c:     CHAR;
BEGIN
  nread := 0;
  n := 0;
  LOOP
    Read(c);
    CASE c OF
    '0'..'7':
      IF n < 20000B THEN    (* Check for overflow *)
        n := n * 8 + (CARDINAL(c) - CARDINAL('0'));
        Write(c); INC(nread);
      END; |

    ' ',Eol:
      IF nread > 0 THEN
        WriteLn;
        EXIT;
      END; |

    177C:
      IF nread > 0 THEN
        Write(c);
        n := n DIV 8;
        DEC(nread);
      END;  |

    Can:
      WHILE nread > 0 DO
        Write(177C);
      END;
      n := 0;
    END;
  END;
END ReadOctal;

END BaseInput;

MODULE OutBase;

IMPORT
  FilePointer,
  Write,
  WriteLn,
  File,
  WriteChar;

EXPORT
  Base,
  FWriteBase,
  FWrite,
  FWriteLn;

CONST
  WordSize = 16;
  Eol = 36C;

TYPE
  Base = [2..16];
  (* FilePointer = POINTER TO File; *)

VAR
  HexTab: ARRAY [0..15] OF CHAR;

PROCEDURE FWrite(F:FilePointer; c: CHAR);
    (* Output a CHAR on file F -- If F is NIL Then output on the Terminal *)
BEGIN
  IF F = NIL THEN
    Write(c);
  ELSE
    WriteChar(F^, c);
  END;
END FWrite;

PROCEDURE FWriteLn(F:FilePointer);
BEGIN
  IF F = NIL THEN
    WriteLn;
  ELSE
    WriteChar(F^, Eol);
  END;
END FWriteLn;

PROCEDURE FWriteBase(F:FilePointer; n:CARDINAL; b:Base; w:CARDINAL);
    (* Output an Unsigned Number to file F *)
    (* in base b, min. field width w       *)
VAR
  Nbuf: ARRAY [0..WordSize-1] OF CHAR;
  i, j: CARDINAL;

BEGIN
  IF w = 0 THEN
    Write(' ');
  END;

  i := 0;
  REPEAT
    Nbuf[i] := HexTab[n MOD b];
    n := n DIV b;
    INC(i);
  UNTIL n = 0;

  FOR j := i TO w-1 DO
    FWrite(F, '0');
  END;

  FOR j := i-1 TO 0 BY -1 DO
    FWrite(F, Nbuf[j]);
  END;
END FWriteBase;

BEGIN

  HexTab := '0123456789abcdef';

END OutBase;

MODULE DoOpts;

IMPORT
  OptNames;

IMPORT
  Write,
  WriteString,
  WriteLn;

EXPORT
  LookupOpt,
  PrintOpts;

CONST
  MaxEnts = 10;

TYPE
  OTEntry = RECORD
              Name: ARRAY [0..15] OF CHAR;
              Opt:  OptNames;
            END;

VAR
  OptTbl:  ARRAY [0..MaxEnts-1] OF OTEntry;

PROCEDURE IsLowerCase(c: CHAR): BOOLEAN;
BEGIN
  RETURN((c >= 'a') AND (c <= 'z'));
END IsLowerCase;

PROCEDURE Cap(c: CHAR): CHAR;
BEGIN
  IF IsLowerCase(c) THEN
    RETURN(CAP(c));
  ELSE
    RETURN(c);
  END;
END Cap;

PROCEDURE Match(Name, TblEnt: ARRAY OF CHAR): BOOLEAN;
VAR
  i: CARDINAL;
BEGIN  (* Compulsory part of name in TblEnt is in CAPITALS, optional part in lower case *)
  i := 0;
  LOOP
    IF i >= HIGH(TblEnt) THEN
      RETURN FALSE;
    END;
    IF i >= HIGH(Name) THEN
      RETURN IsLowerCase(TblEnt[i]);
    END;
 
    IF TblEnt[i] = 0C THEN
      RETURN Name[i] = 0C;
    END;

    IF Name[i] = 0C THEN
      RETURN IsLowerCase(TblEnt[i]);
    END;

    IF Cap(Name[i]) <> Cap(TblEnt[i]) THEN
      RETURN FALSE;
    END;
    INC(i);
  END;
END Match;

PROCEDURE LookupOpt(OptName: ARRAY OF CHAR): OptNames;
VAR
  o: CARDINAL;

BEGIN
  o := 0;

  WHILE (OptTbl[o].Opt <> BadOpt) AND (NOT Match(OptName, OptTbl[o].Name)) DO
    INC(o);
  END;
  RETURN(OptTbl[o].Opt);
END LookupOpt;

PROCEDURE PrintOpts;
VAR
  o, i: CARDINAL;
BEGIN
  o := 0;
  WHILE OptTbl[o].Opt <> BadOpt DO
    Write(' ');
    WITH OptTbl[o] DO
      i := 0;
      WHILE (i <= HIGH(Name)) AND (Name[i] <> 0C) DO Write(Name[i]); INC(i) END;
      WHILE i <= HIGH(Name) DO Write(' '); INC(i) END;
    END;
    INC(o);
    IF o MOD 4 = 0 THEN WriteLn; END;
  END;
  IF o MOD 4 <> 0 THEN WriteLn; END;
END PrintOpts;

BEGIN
  (* Option name table initialisation.                      *)
  (* Capitals denote the minimum abbreviation of the option *)
  (* The names must be inserted in the table in order of    *)
  (* increasing length of min. abbreviation                 *)

  OptTbl[0].Name := "Byte"; OptTbl[0].Opt := Byte;
  OptTbl[1].Name := "Word"; OptTbl[1].Opt := Word;
  OptTbl[2].Name := "Ascii"; OptTbl[2].Opt := Ascii;
  OptTbl[3].Name := "Octal"; OptTbl[3].Opt := Octal;
  OptTbl[4].Name := "Hexadecimal"; OptTbl[4].Opt := Hex;
  OptTbl[5].Name := "Startaddress"; OptTbl[5].Opt := Start;
  OptTbl[6].Name := "Endaddress"; OptTbl[6].Opt := End;
  OptTbl[7].Name := "OUtput"; OptTbl[7].Opt := Output;
  OptTbl[8].Name := "HELP"; OptTbl[8].Opt := Query;
  OptTbl[9].Name := ""; OptTbl[9].Opt := BadOpt;        (* Last Entry MUST BE BadOpt *)
END DoOpts;


PROCEDURE Stop(): BOOLEAN;

VAR
  c: CHAR;

BEGIN
  BusyRead(c);

  IF c = Esc THEN
    RETURN(TRUE);
  END;

  IF c <> 0C THEN
    Read(c);
  END;

  IF c = Esc THEN
    RETURN(TRUE);
  END;
  RETURN(FALSE);
END Stop;

PROCEDURE WriteSpace(n: INTEGER);
BEGIN
  WHILE n > 0 DO
    FWrite(OFP, ' '); DEC(n);
  END;
END WriteSpace;

PROCEDURE WriteAsc(c:CHAR);
BEGIN
  IF c < ' ' THEN
    WriteSpace(ByteFieldWidth-2); FWrite(OFP, '^');
    FWrite(OFP, CHAR(CARDINAL(c) + CARDINAL('@')));
  ELSIF c < 177C THEN
    WriteSpace(ByteFieldWidth-1); FWrite(OFP, c);
  ELSE
    WriteSpace(ByteFieldWidth-OctalByteWidth);
    FWriteBase(OFP, CARDINAL(c), 8, OctalByteWidth);
  END;
END WriteAsc;

PROCEDURE ProcessOpts(VAR OptsOK:BOOLEAN);
TYPE
  OptSet = SET OF OptNames;
VAR
  Len:    CARDINAL;
  Opt:    ARRAY [0..30] OF CHAR;
  Option: OptNames;
  Set:    BOOLEAN;
  DoLater:OptSet;
  OutFileName: ARRAY [0..30] OF CHAR;
  OutTerm: Termination;

BEGIN
  WriteLn;
  Set := FALSE;
  DoLater := OptSet{};
  OptsOK := TRUE;
  LOOP
    GetOption(Opt, Len);
    IF Len = 0 THEN
      EXIT;
    END;
    Option := LookupOpt(Opt);
    CASE Option OF
    Ascii:
      IF NOT Set THEN
        Set := TRUE;
        Formats := FormSet{};
      END;
      INCL(Formats, Ascii); |

    Byte:
      Size := Byte; |

    Hex:
      IF NOT Set THEN
        Set := TRUE;
        Formats := FormSet{};
      END;
      INCL(Formats, Hex); |

    Octal:
      IF NOT Set THEN
        Set := TRUE;
        Formats := FormSet{};
      END;
      INCL(Formats, Octal); |

    Word:
      Size := Word; |

    Output,Start,End:
      INCL(DoLater, Option); |

    Query:
      PrintHelp;
      WriteString(' Options:'); WriteLn;
      PrintOpts;
      OptsOK := FALSE; |

    BadOpt:
      WriteString(' ---- Unknown option "'); WriteString(Opt); Write('"'); WriteLn;
      WriteString(' Type /HELP for legal options'); WriteLn;
      OptsOK := FALSE;
    END;
  END;

  IF OptsOK AND (Output IN DoLater) THEN
    WriteString(' Output File> ');
    FileNameAndOptions(OutFileDefault, OutFileName, OutTerm, FALSE);
    WriteLn;
    CASE OutTerm OF
    normal:
      Lookup(OutFile, OutFileName, TRUE);
      IF OutFile.res <> done THEN
        WriteString(' ---- ');
        WriteString(OutFileName); WriteResponse(OutFile.res); WriteLn;
      ELSE
        OFP := ADR(OutFile);
        WriteString(' Dump output to: '); WriteString(OutFileName); WriteLn;
      END; |
    can, esc, empty:
      OptsOK := FALSE;
    END;
  END;

  StartAd := 0; EndAd := 0; EndSet := FALSE;

  IF OptsOK AND (Start IN DoLater) THEN
    IF Hex IN Formats THEN
      WriteString(' Hex start address>'); ReadHex(StartAd);
    ELSE
      WriteString(' Octal start address>'); ReadOctal(StartAd);
    END;
  END;

  IF OptsOK AND (End IN DoLater) THEN
    IF Hex IN Formats THEN
      WriteString(' Hex end address>'); ReadHex(EndAd);
    ELSE
      WriteString(' Octal end address>'); ReadOctal(EndAd);
    END;
    EndSet := TRUE;
  END;
END ProcessOpts;

PROCEDURE WriteAddr(addr: CARDINAL; VAR AddrDone: BOOLEAN);
BEGIN
  IF AddrDone THEN
    WriteSpace(8);
  ELSE
    AddrDone := TRUE;
    IF Hex IN Formats THEN
      FWriteBase(OFP, addr, 16, HexWordWidth); WriteSpace(WordFieldWidth-HexWordWidth);
    ELSE
      FWriteBase(OFP, addr, 8, OctalWordWidth); WriteSpace(WordFieldWidth-OctalWordWidth);
    END;
  END;
END WriteAddr;

PROCEDURE WriteByteData(buf: ARRAY OF CHAR; len, base, width, field: CARDINAL);

VAR
  i: CARDINAL;

BEGIN
  FOR i := 0 TO len-1 DO
    WriteSpace(field-width); FWriteBase(OFP, CARDINAL(buf[i]), base, width);
  END;
  FWriteLn(OFP);
END WriteByteData;

PROCEDURE WriteWordData(buf: ARRAY OF CARDINAL; len, base, width, field: CARDINAL);

VAR
  i: CARDINAL;

BEGIN
  FOR i := 0 TO len-1 DO
    WriteSpace(field-width); FWriteBase(OFP, buf[i], base, width);
  END;
  FWriteLn(OFP);
END WriteWordData;

PROCEDURE DumpByte;
VAR
  buf: ARRAY [0..15] OF CHAR;
  addr: CARDINAL;
  i, readlen, len: CARDINAL;
  AddrDone: BOOLEAN;

BEGIN
  addr := StartAd;
  SetPos(F, 0, addr);

  LOOP
    readlen := 16 - addr MOD 16;

    IF EndSet AND (addr >= EndAd) THEN
      EXIT;
    END;

    ReadBytes(F, ADR(buf), readlen, len);
    IF len = 0 THEN
      EXIT;
    END;
    AddrDone := FALSE;
    IF Hex IN Formats THEN
      WriteAddr(addr,AddrDone); WriteSpace(4*(16-readlen));
      WriteByteData(buf, len, 16, HexByteWidth, ByteFieldWidth);
    END;
    IF Octal IN Formats THEN
      WriteAddr(addr,AddrDone); WriteSpace(4*(16-readlen));
      WriteByteData(buf, len, 8, OctalByteWidth, ByteFieldWidth);
    END;
    IF Ascii IN Formats THEN
      WriteAddr(addr,AddrDone); WriteSpace(4*(16-readlen));
      FOR i := 0 TO len-1 DO
        WriteAsc(buf[i]);
      END;
      FWriteLn(OFP);
    END;
    INC(addr, len);
    IF Stop() THEN
      EXIT
    END;
  END
END DumpByte;

PROCEDURE DumpWord;
VAR
  buf: ARRAY [0..7] OF CARDINAL;
  addr: CARDINAL;
  i, readlen, len: CARDINAL;
  AddrDone: BOOLEAN;

BEGIN
  IF ODD(StartAd) THEN
    addr := StartAd - 1;
  ELSE
    addr := StartAd;
  END;
  SetPos(F, 0, addr);

  LOOP
    readlen := (16 - addr MOD 16) DIV 2;

    IF EndSet AND (addr >= EndAd) THEN
      EXIT;
    END;

    ReadBytes(F, ADR(buf), readlen * 2, len);
    len := len DIV 2;
    IF len = 0 THEN
      EXIT;
    END;
    AddrDone := FALSE;
    IF Hex IN Formats THEN
      WriteAddr(addr,AddrDone); WriteSpace(8*(8-readlen));
      WriteWordData(buf, len, 16, HexWordWidth, WordFieldWidth);
    END;
    IF Octal IN Formats THEN
      WriteAddr(addr,AddrDone); WriteSpace(8*(8-readlen));
      WriteWordData(buf, len, 8, OctalWordWidth, WordFieldWidth);
    END;
    IF Ascii IN Formats THEN
      WriteAddr(addr,AddrDone); WriteSpace(8*(8-readlen));
      FOR i := 0 TO len-1 DO
        WriteAsc(CHAR(buf[i] DIV 256)); WriteAsc(CHAR(buf[i] MOD 256));
      END;
      FWriteLn(OFP);
    END;
    INC(addr, len*2);
    IF Stop() THEN
      EXIT;
    END;
  END;
END DumpWord;

PROCEDURE Dump;
BEGIN
  Lookup(F, FileName, FALSE);
  IF F.res <> done THEN
    WriteString(' ---- ');
    WriteString(FileName); WriteResponse(F.res); WriteLn;
  END;
  SetRead(F);
  
  CASE Size OF
    Byte:
      DumpByte; |
    Word:
      DumpWord;
  END;

  Close(F);
  IF OFP <> NIL THEN
    Close(OFP^);
    OFP := NIL;
  END;
END Dump;

BEGIN
  Size := Word; Formats := FormSet{Octal};
  SaveFileName[0] := 0C;
  OFP := NIL;
  WriteString(' Type /help for assistance'); WriteLn;

  LOOP

    WriteString(' file to dump> ');
    FileNameAndOptions(DefaultFileSpec, FileName, Term, TRUE);

    CASE Term OF
      normal:
        SaveFileName := FileName;
        ProcessOpts(OptFlg);
        IF OptFlg THEN
          Dump;
        END; |
      empty:
        ProcessOpts(OptFlg);
        IF OptFlg AND (SaveFileName[0] <> 0C) THEN
          WriteString(' Using previous filename:"');
          WriteString(SaveFileName); Write('"');
          WriteLn;
          FileName := SaveFileName;
          Dump;
        END; |
      can:
        Write('?'); WriteLn; |
      esc:
        WriteLn;
        EXIT;
    END
  END

END dump.
