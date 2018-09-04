(*******************************************************************************
BBBBBBBB           Handling of the binary Code-File / Part of           BBBBBBBB
BBBBBBBB           MIA / Version 19 / 20.07.81 / G. Schild              BBBBBBBB
*******************************************************************************)

IMPLEMENTATION MODULE BinFile;

FROM FileSystem IMPORT File,WriteWord,WriteChar,SetWrite,SetModify,
                       SetOpen,SetPos,GetPos,Lookup,Close;

VAR mcm:ARRAY [0..mcmSize] OF Code; (* micro-code-memory *)
    i : CARDINAL;
    c : Code;

PROCEDURE Store(c:Code;madr:CARDINAL);
BEGIN mcm[madr] := c END Store;

PROCEDURE Update(adrValue,madr:CARDINAL);
BEGIN
  mcm[madr,0] := adrValue DIV 10h;
  mcm[madr,1] := mcm[madr,1] + 10h * (adrValue MOD 10h)
END Update;

PROCEDURE Copy(VAR c:Code;madr:CARDINAL);
BEGIN c := mcm[madr] END Copy;

PROCEDURE WriteMotorola(m1,m2,m3,m4,m5:ARRAY OF CHAR);
VAR b : ARRAY [1..5] OF File;
    l : ARRAY [1..5],[0..73] OF CHAR;
    x : ARRAY [1..5] OF CARDINAL;
    h : ARRAY [0..0Fh] OF CHAR;
    rand : ARRAY [0..73] OF CHAR;
    i, j, k, z : CARDINAL;
    c1, c2 : CHAR;

  PROCEDURE Put(a,n:CARDINAL;VAR q,p:CHAR);
  BEGIN
  q := h[a DIV 10h]; p := h[a MOD 10h];
  x[n] := x[n] + a
  END Put;

  PROCEDURE WriteLine(VAR f:File;q:ARRAY OF CHAR);
  VAR i : CARDINAL;
  BEGIN
  i := 0;
    LOOP
    WriteChar(f,q[i]);
    INC(i);
    IF i > 73 THEN EXIT END;
    IF q[i] = " " THEN EXIT END
    END;
  WriteChar(f,36c)
  END WriteLine;

BEGIN                                                  (* inizialisieren *)
FOR i := 0 TO 0Fh DO h[i] := CHAR(i + 30h + (i DIV 0Ah)*7) END;
rand[0] := "S"; rand[1] := "0";
rand[2] := "0"; rand[3] := "3";
rand[4] := "0"; rand[5] := "0";
rand[6] := "0"; rand[7] := "0";
rand[8] := "F"; rand[9] := "C";
FOR i := 10 TO 73 DO rand[i] := " " END;
Lookup(b[1],m1,TRUE);
Lookup(b[2],m2,TRUE);
Lookup(b[3],m3,TRUE);
Lookup(b[4],m4,TRUE);
Lookup(b[5],m5,TRUE);
FOR i := 1 TO 5 DO l[i,0] := "S"; l[i,1] := "1"; WriteLine(b[i],rand) END;
rand[1] := "9";
j := 0;
  LOOP                                                 (* code schreiben *)
  FOR i := 1 TO 5 DO x[i] := 0; FOR k := 2 TO 73 DO l[i,k] := " " END END;
    LOOP  (* leerer code \berlesen *)
    IF j > mcmSize THEN EXIT END;
    IF mcm[j,0] < 8000h THEN EXIT END;
    INC(j)
    END;
    IF j > mcmSize
    THEN EXIT
    ELSE  (* start adresse schreiben *)
    FOR i := 1 TO 5 DO Put(j DIV 100h,i,c1,c2); l[i,4] := c1; l[i,5] := c2;
                       Put(j MOD 100h,i,c1,c2); l[i,6] := c1; l[i,7] := c2
                       END
    END;
  z := 8;
    LOOP  (* code einer zeile schreiben *)
    IF j > mcmSize THEN EXIT END;
    IF (mcm[j,0] = 8000h) OR (z = 72) THEN EXIT END;
    FOR i := 1 TO 5 DO Put(mcm[j,5-i],i,c1,c2); l[i,z] := c1; l[i,z+1] := c2 END;
    INC(j); INC(z,2)
    END;
  FOR i := 1 TO 5 DO Put((z-2) DIV 2,i,c1,c2); l[i,2] := c1; l[i,3] := c2;
                     Put(0FFh-(x[i] MOD 100h),i,c1,c2); l[i,z] := c1; l[i,z+1] := c2;
                     WriteLine(b[i],l[i]) END  (* zeile abgesclossen *)
  END;  (* code fertig geschrieben *)
FOR i := 1 TO 5 DO WriteLine(b[i],rand); Close(b[i]) END
END WriteMotorola;

PROCEDURE WriteCode(name:ARRAY OF CHAR);
VAR b:File;
    titel : ARRAY [0..29] OF CHAR;
    loOld, loNew, hiOld, hiNew,           (* block-start-positions on file b*)
    i, j : CARDINAL;
    second : BOOLEAN;

  PROCEDURE FillIn(VAR f:File;aa,za,ab,zb:CARDINAL);
  BEGIN
  SetOpen(f); SetPos(f,ab,zb);
  SetModify(f); WriteWord(f,aa); WriteWord(f,za);
  SetOpen(f); SetPos(f,aa,za);
  SetWrite(f)
  END FillIn;

  PROCEDURE Titel(adr:CARDINAL);
  VAR i : CARDINAL;
  BEGIN
  GetPos(b,hiNew,loNew);
  IF ODD(loNew)
  THEN WriteChar(b,0c); GetPos(b,hiNew,loNew)
  END;
    IF second 
    THEN FillIn(b,hiNew,loNew,hiOld,loOld)
    ELSE second:=TRUE
    END;
  hiOld := hiNew;
  loOld := loNew;
  WriteWord(b,0);
  WriteWord(b,0);
  WriteWord(b,CARDINAL("d"));
  FOR i := 0 TO 29 DO WriteWord(b,titel[i]) END;
  WriteWord(b,40);
  WriteWord(b,adr);
  WriteWord(b,0)
  END Titel;

BEGIN
i := 0;                                     (* compose titel *)
  LOOP
  IF (i=30) OR (name[i]=0C) THEN EXIT END;
  titel[i] := name[i];
  INC(i)
  END;
FOR j := i TO 29 DO titel[j] := " " END;    (* titel stored *)
Lookup(b,name,TRUE);                        (* initialization *)
second := FALSE;
i := 0;
  LOOP                                      (* start writing *)
    LOOP
    IF i > mcmSize THEN EXIT END;
    IF mcm[i,0] < 100h THEN EXIT END;
    INC(i)
    END;
  IF i > mcmSize THEN EXIT END;
  Titel(i);
    LOOP
    FOR j := 4 TO 0 BY -1 DO WriteChar(b,CHAR(mcm[i,j])) END;
    INC(i);
    IF i > mcmSize THEN EXIT END;
    IF mcm[i,0] > 100h THEN EXIT END
    END
  END;
GetPos(b,hiNew,loNew);
FillIn(b,hiNew,loNew,hiOld,loOld);
Close(b)
END WriteCode;

BEGIN
c[0] := 8000h; (* to mark the code of this instruction not stored *)
c[1] := 0;
c[2] := 0;
c[3] := 0;
c[4] := 0FFh;
FOR i := 0 TO mcmSize DO mcm[i] := c END
END BinFile.
