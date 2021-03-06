(*******************************************************************************
TTTTTTTT            Input-Output-Handling / Part of                     TTTTTTTT
TTTTTTTT            MIA / Version 19 / 20.07.81 / G. Schild             TTTTTTTT
TTTTTTTT            MIA / Version 20 /  9.04.82 / W. Winiger            TTTTTTTT
*******************************************************************************)

IMPLEMENTATION MODULE TextIO;

FROM Terminal IMPORT Write;
FROM LongFiles IMPORT LongFileName, FileName, ReadInputChar, StopInput,
                      CreateFirstListing, WriteFirstListing, CatalogFirstListing,
                      ResetFirstListing, ReadFirstListing,
                      CreateSecondListing, WriteSecondListing, CloseListings;

FROM Storage IMPORT ALLOCATE, DEALLOCATE;

FROM BinFile IMPORT Copy, Code;

CONST newPage     = 14C;
      errorNumber = 33;          (* number of known errors *)

TYPE ErrorPtr  = POINTER TO ErrorLine;
     ErrorLine = RECORD next:ErrorPtr;
                        line:ARRAY [0..lineSize-6] OF CHAR
                 END;

VAR 
    errorMemory : ARRAY [1..errorNumber] OF BOOLEAN;
    hex : ARRAY [0..0Fh] OF CHAR;
    header : ARRAY [0..lineSize] OF CHAR;
    pageNr, lineNr,
    i : CARDINAL;
    errorInAssemblyRun : BOOLEAN;
    wrong : ErrorPtr;

PROCEDURE GetLine(VAR l:ARRAY OF CHAR;VAR itIsOver:BOOLEAN);
VAR ch : CHAR;
    i : CARDINAL;
BEGIN
i := 0;
itIsOver := FALSE;
  LOOP
  ReadInputChar(ch,itIsOver);
  IF itIsOver THEN EXIT END;
  IF ch = eol THEN EXIT END;
  IF i <= HIGH(l) THEN l[i] := ch END;
  IF i < HIGH(l) THEN INC(i) END
  END;
IF i <= HIGH(l) THEN l[i] := 0C END
END GetLine;

PROCEDURE PutHex(n:CARDINAL;VAR res:ARRAY OF CHAR);
VAR i : CARDINAL;
BEGIN
  FOR i := HIGH(res) TO 0 BY -1 DO
  res[i] := hex[n MOD 10h];
  n := n DIV 10h
  END;
  LOOP
  IF (res[i] <> "0") OR (i > HIGH(res)-1) THEN EXIT END;
  res[i] := " ";
  INC(i)
  END
END PutHex;

PROCEDURE PutNr(n:CARDINAL;VAR res:ARRAY OF CHAR);
VAR i : CARDINAL;
BEGIN
  FOR i := HIGH(res) TO 0 BY -1 DO
  res[i] := hex[n MOD 10];
  n := n DIV 10
  END;
  LOOP
  IF (res[i] <> "0") OR (i > HIGH(res)-1) THEN EXIT END;
  res[i] := " ";
  INC(i)
  END
END PutNr;

PROCEDURE PrintChar(ch:CHAR);
BEGIN
WriteFirstListing(ch);
IF (ch = eol) AND (lineNr < fullPage) THEN INC(lineNr) END
END PrintChar;

PROCEDURE Print(l:ARRAY OF CHAR);
VAR i : CARDINAL;
BEGIN
i := 0;
  LOOP
  IF (i > HIGH(l)) OR (l[i] = 0C) THEN EXIT END;
  PrintChar(l[i]);
  INC(i)
  END;
PrintChar(eol);
END Print;

PROCEDURE NewPage;
VAR q : ARRAY [0..2] OF CHAR;
    i : CARDINAL;
BEGIN
WriteFirstListing(newPage);
PrintChar(eol);
INC(pageNr);
lineNr := 0;
PutNr(pageNr,q);
FOR i := 0 TO 2 DO header[lineSize-2+i] := q[i] END;
Print(header);
PrintChar(eol)
END NewPage;

PROCEDURE SkipPage;
BEGIN lineNr := fullPage END SkipPage;

PROCEDURE LineCount():CARDINAL;
BEGIN  RETURN lineNr END LineCount;

PROCEDURE WriteList (VAR name: LongFileName);
VAR a, i, j : CARDINAL;
    c : Code;
    res : ARRAY [0..2] OF CHAR;
    ch : CHAR;
    noMap, noCode, eof : BOOLEAN;
BEGIN
  IF errorInAssemblyRun
  THEN
  CatalogFirstListing(name);
  RETURN
  END;
CreateSecondListing(name);
ResetFirstListing;
noMap := TRUE;
j := 0;
  LOOP   (* loop ueber alle Zeilen *)
  a := 0; i := 1; noCode := TRUE;
    LOOP   (* address lesen *)
    ReadFirstListing(ch,eof);
      IF eof
      THEN
      CloseListings;
      RETURN
      END;
    IF ch = 7C THEN noMap := FALSE; ch :=" " END;
    IF ch = eol THEN i := 0; INC(j) END;
    IF ch = newPage THEN i := 0; j := 0 END;
    IF ORD(ch) > 2Fh THEN a := a*10h+ORD(ch)-30h; noCode := FALSE END;
    IF ORD(ch) > 40h THEN a := a-7 END;
    WriteSecondListing(ch);
    IF i = 4 THEN EXIT END;
    INC(i)
    END;   (* ende address lesen *)
    INC(j);
      IF noMap
      THEN
      WriteSecondListing(" ");  (* Code oder blanks einfuegen *)
      IF noCode
      THEN IF j = 4
           THEN
             FOR i := 0 TO 4 DO
             WriteSecondListing(" ");
             WriteSecondListing(" ");
             WriteSecondListing(CHAR(34h-i))
             END
           ELSE FOR i := 0 TO 0Eh DO WriteSecondListing(" ") END
           END
      ELSE Copy(c,a);
           FOR i := 0 TO 4 DO 
           WriteSecondListing(' ');
           WriteSecondListing(hex[c[i] DIV 10h]);
           WriteSecondListing(hex[c[i] MOD 10h])
           END
      END;
      FOR i := 0 TO 1 DO WriteSecondListing(" ") END;
    END;
    LOOP   (* copy rest of the line *)
    ReadFirstListing(ch,eof);
    WriteSecondListing(ch);
    IF ch=eol THEN EXIT END
    END
  END
END  WriteList;

PROCEDURE Error(n,colnr:CARDINAL);
VAR q : ErrorPtr;
    i : CARDINAL; 
    hp, lp : CARDINAL;
BEGIN
q := wrong;
WHILE q^.next <> NIL DO q := q^.next END;
NEW(q^.next);
q := q^.next;
  WITH q^ DO
  next := NIL;
  FOR i := 0 TO 3 DO line[i] := "*" END;
  FOR i := 4 TO colnr-1 DO line[i]:=" " END;
  line[colnr] := "^";
    IF n < 10
    THEN line[1+colnr] := CHAR(n+30h);
         line[2+colnr] := 0C
    ELSE line[1+colnr] := CHAR((n DIV 10)+30h);
         line[2+colnr] := CHAR((n MOD 10)+30h);
         line[3+colnr] := 0C
    END
  END;
IF (n = 28) OR (n = 25)
THEN StopInput;
END;
errorInAssemblyRun := TRUE;
errorMemory[n] := TRUE;
Write('*');
END Error;

PROCEDURE Erratum(n:CARDINAL);
VAR hp, lp : CARDINAL;
BEGIN
IF (n = 28) OR (n = 25)
THEN StopInput;
END;
errorInAssemblyRun := TRUE;
errorMemory[n] := TRUE
END Erratum;

PROCEDURE ErrorList;
VAR q, r : ErrorPtr;
BEGIN
r := wrong^.next;
wrong^.next := NIL;
  LOOP
  IF r = NIL THEN RETURN END;
  IF lineNr = fullPage THEN NewPage END;
  Print(r^.line);
  q := r;
  r := r^.next;
  DISPOSE(q)
  END
END ErrorList;

PROCEDURE ErrorNotes;
VAR i : CARDINAL;
BEGIN
NewPage;
FOR i := 1 TO 6 DO PrintChar(eol) END;
Print(" Error Notes");
Print(" ***********");
PrintChar(eol);
  FOR i := 1 TO errorNumber DO
    IF errorMemory[i]  THEN
    CASE i OF
    1:  Print(" 1: '0' or '1' is expected") |
    2:  Print(" 2: unknown ALU destination") |
    3:  Print(" 3: unknown ALU function") |
    4:  Print(" 4: unknown ALU source") |
    5:  Print(" 5: unknown carry control") |
    6:  Print(" 6: unknown port address") |
    7:  Print(" 7: unknown shift control") |
    8:  Print(" 8: '-' or 'S'  is expected") |
    9:  Print(" 9: unknown program control") |
    10: Print("10: illegal shift count") |
    11: Print("11: shift count = 0 is required") |
    12: Print("12: this shift needs a shift count") |
    13: Print("13: constant expected") |
    14: Print("14: ") |
    15: Print("15: illegal BUS destination") |
    16: Print("16: illegal BUS source") |
    17: Print("17: there are still open Labels  ----- see special List") |
    18: Print("18: there are undeclared local labels") |
    19: Print("19: unknown condition code") |
    20: Print("20: in a regular instruction 'call' is illegal") |
    21: Print("21: end  of line before instruction is is completed") |
    22: Print("22: label or symbol is too long ") |
    23: Print("23: octal numbers contain characters from '0' to '7'") |
    24: Print("24: constant is too large") |
    25: Print("25: map overflow  (map range is 0..255)   -----  stops assembling") |
    26: Print("26: this label is defined twice") |
    27: Print("27: this is a jump to a unknown (too high) address") |
    28: Print("28: Micro Code Memory Overflow   -----  stops assembling") |
    29: Print("29: the used shift needs a shift count") |
    30: Print("30: this  combination of registers,destinations and sources is illegal") |
    31: Print("31: wrong stack control") |
    32: Print("32: unknown pseudo instruction") |
    33: Print("33: '-' or 'S' is expected")
    END;
    END;
  END;
END ErrorNotes;

PROCEDURE Correct():BOOLEAN;
BEGIN RETURN NOT errorInAssemblyRun END Correct;

BEGIN
CreateFirstListing;
errorInAssemblyRun := FALSE;
FOR i := 1 TO errorNumber DO errorMemory[i] := FALSE END;
NEW(wrong);
wrong^.next := NIL;
pageNr := 0;
lineNr := fullPage;
FOR i := 0 TO 9 DO hex[i] := CHAR(i+30h) END;
FOR i := 10 TO 15 DO hex[i] := CHAR(i+37h) END;
header :=
"     Informatik ETH Zuerich          Micro-Code-Assembler 'MIA'                     Page"
END TextIO.
