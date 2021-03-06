IMPLEMENTATION MODULE OutFile; (* Ch. Jacobi, N. Wirth; version 10.6.81 *)
  (*$T-*) (*$R-*)
  FROM SYSTEM IMPORT WORD;
  FROM FileSystem IMPORT File;
  IMPORT FileSystem;

  PROCEDURE WriteChar(VAR f: File; ch: CHAR);
  BEGIN FileSystem.WriteChar(f,ch)
  END WriteChar;
      
  PROCEDURE WriteLine(VAR f: File);
  BEGIN WriteChar(f,36C)
  END WriteLine;

  PROCEDURE WriteText(VAR f: File; s: ARRAY OF CHAR; length: CARDINAL);   
    VAR l, h: CARDINAL; 
  BEGIN
    l := 0; h := HIGH(s);
    WHILE (l<=h) AND (s[l]<>0C) DO
      WriteChar(f, s[l]); INC(l)
    END;
    FOR h := l+1 TO length DO WriteChar(f, " ") END
  END WriteText;
    
  PROCEDURE WriteInt(VAR f: File; value: INTEGER; length: CARDINAL);
    VAR i,n: CARDINAL;
        a: ARRAY [0..6] OF CHAR;
  BEGIN
    IF length=0 THEN WriteChar(f," ") END;
    IF value=(-32767-1) THEN  i := 5;
      a[0] := "8"; a[1] := "6"; a[2] := "7";
      a[3] := "2"; a[4] := "3";
    ELSE
      i := 0; n := ABS(value);
      REPEAT a[i] := CHAR(n MOD 10 + CARDINAL("0"));
        n := n DIV 10; INC(i)
      UNTIL n = 0;
    END;
    IF value<0 THEN a[i] := "-"; INC(i) END;
    WHILE length>i DO WriteChar(f," "); DEC(length) END;
    REPEAT DEC(i); WriteChar(f,a[i]) UNTIL i=0
  END WriteInt;
 
  PROCEDURE WriteCard(VAR f: File; value: CARDINAL; length: CARDINAL);
    VAR i: CARDINAL;
        a: ARRAY [0..6] OF CHAR;
  BEGIN
    IF length=0 THEN WriteChar(f," ") END;
    i := 0; 
    REPEAT a[i] := CHAR(value MOD 10 + CARDINAL("0"));
      value := value DIV 10; INC(i)
    UNTIL value = 0;
    WHILE length>i DO WriteChar(f," "); DEC(length) END;
    REPEAT DEC(i); WriteChar(f,a[i]) UNTIL i=0
  END WriteCard;
  
  PROCEDURE WriteOct(VAR f: File; value: WORD; length: CARDINAL);
    VAR i, n: CARDINAL;
        a: ARRAY [0..6] OF CHAR;
  BEGIN
    IF length=0 THEN WriteChar(f," ") END;
    i := 0; n := CARDINAL(value);
    REPEAT a[i] := CHAR(n MOD 8 + CARDINAL("0"));
      n := n DIV 8; INC(i)
    UNTIL n=0;
    WHILE length>6 DO WriteChar(f," "); DEC(length) END;
    WHILE length>i DO WriteChar(f,"0"); DEC(length) END;
    REPEAT DEC(i); WriteChar(f,a[i]) UNTIL i=0
  END WriteOct;

END OutFile.

