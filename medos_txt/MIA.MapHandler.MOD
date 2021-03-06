(*******************************************************************************
MMMMMMMM            Handling of the binary Map-File / Part of           MMMMMMMM
MMMMMMMM            MIA / Version 19 / 20.07.81 / G. Schild             MMMMMMMM
*******************************************************************************)

IMPLEMENTATION MODULE MapHandler;

FROM TextIO IMPORT Print, PrintChar, NewPage, PutHex, eol;

FROM FileSystem IMPORT File,Lookup, Close, WriteWord;

VAR map : ARRAY [0..0FFh] OF CARDINAL;
    i : CARDINAL;
    empty : BOOLEAN;

PROCEDURE EnterMap(loadAdr,mapIndex:CARDINAL);
BEGIN empty := FALSE; map[mapIndex] := loadAdr END EnterMap;

PROCEDURE WriteMap(name:ARRAY OF CHAR);
VAR m : File;
    j : CARDINAL;
BEGIN
IF empty THEN RETURN END;  
Lookup(m,name,TRUE);
WriteWord(m,0);
WriteWord(m,456);
WriteWord(m,CARDINAL("d"));
i := 0;
  LOOP
  IF (i = 30) OR (name[i] = 0C) THEN EXIT END;
  WriteWord(m,name[i]);
  INC(i)
  END;
FOR j := i TO 29 DO WriteWord(m," ") END;
WriteWord(m,12);
WriteWord(m,0);
WriteWord(m,0);
  FOR i := 0 TO 0FFh BY 4 DO
  WriteWord(m,(map[i] MOD 1000h)*10h + (map[i+1] MOD 1000h) DIV 100h);
  WriteWord(m,(map[i+1] MOD 1000h)*100h + (map[i+2] MOD 1000h) DIV 10h);
  WriteWord(m,(map[i+2] MOD 1000h)*1000h + (map[i+3] MOD 1000h));
  END;
Close(m)
END WriteMap;

PROCEDURE PrintMap;
CONST noEntry = "    ****";
VAR q : ARRAY [0..75] OF CHAR;
    r : ARRAY [0..7] OF CHAR;
    s : ARRAY [0..3] OF CHAR;
    octal : ARRAY [0..7] OF CHAR;
    a, i, j, n, m : CARDINAL;

  PROCEDURE PutOct(n:CARDINAL;VAR res:ARRAY OF CHAR);
  VAR i : CARDINAL;
  BEGIN
    FOR i := HIGH(res) TO 0 BY -1 DO
    res[i] := octal[n MOD 10B];
    n := n DIV 10B
    END;
    LOOP
    IF (res[i] <> "0") OR (i > HIGH(res)-1) THEN EXIT END;
    res[i] := " ";
    INC(i)
    END
  END PutOct;

BEGIN
IF empty THEN RETURN END;
NewPage;
PrintChar(7C);
PrintChar(eol);
FOR i := 0 TO 7 DO octal[i] := CHAR(30h+i) END;
FOR i := 0 TO 75 DO q[i] := " " END;
Print("                  Table of the MAP Entries");
Print("                  ************************");
PrintChar(eol);
  FOR i := 0 TO 7 DO
  PutHex(i*20h,r);
  FOR j := 0 TO 7 DO q[12+i*8+j] := r[j] END
  END;
Print(q);
  FOR i := 0 TO 7 DO
  PutOct(i*40B,r);
  FOR j := 0 TO 7 DO q[12+i*8+j] := r[j] END
  END;
Print(q);
PrintChar(eol);
  FOR m := 0 TO 3 DO
    FOR n := 0 TO 7 DO
    PutHex(m*8+n,r);
    FOR i := 0 TO 7 DO q[i] := r[i] END;
    PutOct(m*8+n,s);
    FOR i := 0 TO 3 DO q[8+i] := s[i] END;
      FOR j:=0 TO 7 DO
      a := j*20h+m*8+n;
        IF map[a] < 1000h
        THEN PutHex(map[a],r)
        ELSE r := noEntry
        END;
      FOR i := 0 TO 7 DO q[12+j*8+i] := r[i] END
      END;
    Print(q)
    END;
  PrintChar(eol)
  END
END PrintMap;

BEGIN
  FOR i := 0 TO 0FFh DO map[i] := 8000h END;
  empty := TRUE
END MapHandler.
