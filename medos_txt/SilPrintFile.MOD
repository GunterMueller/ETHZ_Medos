MODULE SilPrintFile;
(* Program: Companion program to SIL for generating a print file.
   Date:    10.4.83
   Author:  N.Wirth
            Institut fur Informatik, ETH Zurich
            Switzerland  *)

  FROM Terminal IMPORT  Read, Write, WriteString, WriteLn;
  FROM FileSystem IMPORT  File, Response, Lookup, Create,
       SetPos, GetPos, ReadWord, WriteWord, SetOpen, Rename, Close;
  FROM Profile IMPORT  OpenProfile, FindKey,
       GetString, GetNumber, GetFileName, CloseProfile;

  CONST PageHeight = 2576;
    maxF = 3;   (*max font no.*)
    maxM = 1;   (*max macro no.*)
    LineCode = 7;
    NameLeng = 27;
    DEL = 177C; ESC = 33C;

  VAR ch: CHAR;
    i, j, tem: CARDINAL;
    copies, pages, PageNumber: CARDINAL;
    open: BOOLEAN;
    mac: BITSET;
    in, out: File;
    pos0, pos1: CARDINAL;  (*position of error in file*)
    name: ARRAY [0..NameLeng] OF CHAR;
    fontname: ARRAY [0..19] OF CHAR;
    BaseHeight: ARRAY [0..maxF] OF CARDINAL;
    key:  ARRAY [0..maxF] OF CHAR;
    macF: ARRAY [0..maxM] OF File;
    buf: ARRAY [0..49] OF CARDINAL;

  PROCEDURE ReadFileName(ext: ARRAY OF CHAR);
    VAR i,j: CARDINAL;
  BEGIN i := 3; j := 0;
    REPEAT Read(ch);
      IF ch = DEL THEN
        IF i > 3 THEN Write(DEL); i := i-1 END
      ELSIF ch > " " THEN
        IF i < NameLeng THEN Write(ch); name[i] := ch; i := i+1 END
      END
    UNTIL ch <= " ";
    IF (i > 3) & (name[i-1] = ".") & (i < NameLeng) THEN
      REPEAT ch := ext[j]; j := j+1;
        Write(ch); name[i] := ch; i := i+1
      UNTIL (j > HIGH(ext)) OR (i = NameLeng)
    END ;
    name[i] := 0C
  END ReadFileName;

  PROCEDURE ReadNumber(VAR n: CARDINAL);
    VAR i,j: CARDINAL;
        dig: ARRAY [0..7] OF CHAR;
  BEGIN i := 0; j := 0; n := 0;
    REPEAT Read(ch);
      IF ("0" <= ch) & (ch <= "9") THEN
        dig[i] := ch; i := i+1; Write(ch)
      ELSIF (ch = DEL) & (i > 0) THEN
        i := i-1; Write(DEL)
      END
    UNTIL ch <= " ";
    WHILE j < i DO
      n := 10*n + CARDINAL(dig[j]) - 60B; j := j+1
    END
  END ReadNumber;

  PROCEDURE WriteNumber(n: CARDINAL);
    VAR i: CARDINAL; d: ARRAY [0..3] OF CARDINAL;
  BEGIN i := 0;
    REPEAT d[i] := n MOD 10; n := n DIV 10; i := i+1
    UNTIL n = 0;
    REPEAT i := i-1; Write(CHAR(d[i]+60B))
    UNTIL i = 0
  END WriteNumber;

  PROCEDURE OutLine(X, Y, W, H: CARDINAL);
  BEGIN WriteWord(out, 1000B);   (*LineBlock*)
    WriteWord(out, X); WriteWord(out, Y);
    WriteWord(out, W); WriteWord(out, H);
  END OutLine;

  PROCEDURE OutText(VAR f: File; fon, X, Y: CARDINAL);
    VAR k, tem, L: CARDINAL;
  BEGIN WriteWord(out, 400B + fon);
    WriteWord(out, X); WriteWord(out, Y - BaseHeight[fon]);
    k := 0;
    REPEAT ReadWord(f, tem); buf[k] := tem; k := k+1
    UNTIL tem MOD 400B = 0;
    L := 2*k -1; k := 0;
    IF tem DIV 400B = 0 THEN L := L-1 END ;
    WriteWord(out, L*400B + buf[0] DIV 400B);
    WHILE L > 1 DO
      WriteWord(out, buf[k] MOD 400B * 400B + buf[k+1] DIV 400B);
      k := k+1; L := L-2
    END
  END OutText;

  PROCEDURE ReadMacro(VAR f: File; m, X0, Y0: CARDINAL);
    VAR pos, T, X, Y, W, H: CARDINAL;
  BEGIN SetPos(f,0,2*m); ReadWord(f, pos);
    IF pos # 0 THEN
      SetPos(f,0,2*pos); ReadWord(f, X);
      WHILE X < 170000B DO
        T := X DIV 10000B; X := (X MOD 10000B)*3 + X0;
        ReadWord(f, Y); Y := Y0 - 3*Y;
        ReadWord(f, W); ReadWord(f, H);
        IF T <= maxF THEN
          OutText(f, T, X, Y)
        ELSIF T < 6 THEN
          ReadWord(f,X)  (*recursive macro*)
        ELSIF T = LineCode THEN
          OutLine(X, Y-3*H, 3*W, 3*H)
        END ;
        ReadWord(f,X)
      END
    END
  END ReadMacro;

  PROCEDURE ProcessFile;
    VAR m, T, X, Y, W, H: CARDINAL;
  BEGIN ReadWord(in,X);
    WHILE NOT in.eof DO
      T := X DIV 10000B; X := X MOD 10000B *3;
      ReadWord(in,Y); Y := PageHeight - 3*Y;
      ReadWord(in,W); ReadWord(in,H);
      IF T <= maxF THEN
        OutText(in, T, X, Y)
      ELSIF T < 6 THEN (*Macro*)
        ReadWord(in,m);
        IF (T-4) IN mac THEN
          ReadMacro(macF[T-4], m, X, Y)
        END
      ELSIF T = LineCode THEN
        OutLine(X, Y-3*H+1, 3*W-1, 3*H-1)
      ELSE GetPos(in, pos0, pos1);
        WriteString(" bad input format"); HALT
      END ;
      ReadWord(in,X)
    END ;
    WriteWord(out, 2000B + copies);   (*PageBlock*)
    WriteWord(out, PageNumber); WriteWord(out, 0)
  END ProcessFile;

BEGIN WriteString(" SilPrintFile 4.3    Profile: (-/c) ");
  REPEAT Read(ch) UNTIL (ch <= " ") OR (ch = "c");
  IF ch = "c" THEN Write("c"); OpenProfile('"SILc"')
              ELSE OpenProfile('"SIL"')
  END ;
  WriteLn; name := "DK.";
  WriteString("out> "); ReadFileName("PRT"); Lookup(out, name, TRUE);
  IF out.res = done THEN
    WriteLn; WriteWord(out, 162703B);  (*header*)
    open := TRUE; i := 0; key := "'F*'";
    REPEAT key[2] := CHAR(i+60B); FindKey(key);
      GetString(fontname); GetNumber(BaseHeight[i]);
      WriteWord(out, 1400B + i);  (*FontBlock*)
      j := 0;
      REPEAT tem := CARDINAL(fontname[j]) * 400B;
        IF tem > 0 THEN
          j := j+1; tem := CARDINAL(fontname[j]) + tem
        END ;
        WriteWord(out, tem); j := j+1
      UNTIL tem MOD 400B = 0;
      i := i+1
    UNTIL i > maxF;
    i := 0; key := "'M*'"; mac := {}; open := TRUE;
    REPEAT key[2] := CHAR(i+60B); FindKey(key);
      GetFileName(name, "SILM");
      IF name[3] # "0" THEN
        Lookup(macF[i], name, FALSE);
        IF macF[i].res # done THEN
          WriteLn; WriteString(name); WriteString(" missing");
          open := FALSE
        ELSE INCL(mac, i)
        END
      END ;
      i := i+1
    UNTIL (i > maxM) OR NOT open;
    CloseProfile; pages := 0; PageNumber := 0;
    IF open THEN
      LOOP WriteString(" in> "); ReadFileName("SIL");
        IF ch = ESC THEN EXIT END ;
        Lookup(in, name, FALSE);
        IF in.res = done THEN
          WriteString(" copies> ");
          REPEAT Read(ch) UNTIL ("0" <= ch) & (ch <= "9");
          Write(ch); copies := CARDINAL(ch) - 60B;
          IF copies > 0 THEN
            PageNumber := PageNumber + 1; ProcessFile
          END ;
          Close(in); pages := pages + copies
        ELSE WriteString(" not found")
        END ;
        WriteLn
      END ;
      Close(out);
      IF 0 IN mac THEN Close(macF[0]) END ;
      IF 1 IN mac THEN Close(macF[1]) END
    END ;
    WriteNumber(pages); WriteString(" pages to print")
  ELSE  WriteString(" not opened")
  END ;
  WriteLn
END SilPrintFile.
