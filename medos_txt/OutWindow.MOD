IMPLEMENTATION MODULE OutWindow; (* Ch. Jacobi; version 10.6.81 18.8.80 *)
  (*$T-*) (*$R-*)
  FROM SYSTEM IMPORT WORD;
  FROM WindowHandler IMPORT Window, WriteChar, FreeChars;

  PROCEDURE Write(w: Window; ch: CHAR);
  BEGIN 
    IF (FreeChars(w)>0) OR (ch<" ") OR (ch=177C) THEN
      WriteChar(w, ch)
    END
  END Write;
       
  PROCEDURE WriteLn(w: Window);
  BEGIN WriteChar(w, 36C)
  END WriteLn;

  PROCEDURE WriteS(w: Window; s: ARRAY OF CHAR);
    VAR l: CARDINAL;
  BEGIN
    FOR l := 0 TO HIGH(s) DO
      IF s[l]=0c THEN RETURN END;
      Write(w, s[l])
    END; 
  END WriteS;
    
  PROCEDURE WriteT(w: Window; s: ARRAY OF CHAR; length: CARDINAL);   
    VAR l, h: CARDINAL; 
  BEGIN
    l := 0; h := HIGH(s);
    WHILE (l<=h) AND (s[l]<>0C) DO
      Write(w, s[l]); INC(l)
    END;
    FOR h := l+1 TO length DO Write(w, " ") END
  END WriteT;
    
  PROCEDURE WriteI(w: Window; value: INTEGER; length: CARDINAL);
    VAR i,n: CARDINAL;
      a: ARRAY [0..6] OF CHAR;
  BEGIN
    IF length=0 THEN Write(w, " ") END;
    IF value=(-32767-1) THEN 
      a[0] := "8"; a[1] := "6"; a[2] := "7";
      a[3] := "2"; a[4] := "3"; i := 5;
    ELSE
      i := 0; n := ABS(value);
      REPEAT a[i] := CHAR(n MOD 10 + CARDINAL("0"));
        n := n DIV 10; INC(i)
      UNTIL n = 0;
    END;
    IF value<0 THEN a[i] := "-"; INC(i) END;
    IF length<i THEN length := i END;
    IF (FreeChars(w)>=length) THEN
      WHILE length>i DO WriteChar(w, " "); DEC(length) END;
      REPEAT DEC(i); WriteChar(w, a[i]) UNTIL i=0
    END
  END WriteI;
   
  PROCEDURE WriteC(w: Window; value: CARDINAL; length: CARDINAL);
    VAR i: CARDINAL;
      a: ARRAY [0..6] OF CHAR;
  BEGIN
    IF length=0 THEN Write(w, " ") END;
    i := 0; 
    REPEAT a[i] := CHAR(value MOD 10 + CARDINAL("0"));
      value := value DIV 10; INC(i)
    UNTIL value = 0;
    IF length<i THEN length := i END;
    IF (FreeChars(w)>=length) THEN
      WHILE length>i DO WriteChar(w, " "); DEC(length) END;
      REPEAT DEC(i); WriteChar(w, a[i]) UNTIL i=0
    END
  END WriteC;
  
  PROCEDURE WriteO(w: Window; value: WORD; length: CARDINAL);
    VAR i, n: CARDINAL;
      a: ARRAY [0..6] OF CHAR;
  BEGIN
    IF length=0 THEN Write(w, " ") END;
    i := 0; n := CARDINAL(value);
    REPEAT a[i] := CHAR(n MOD 8 + CARDINAL("0"));
      n := n DIV 8; INC(i)
    UNTIL n=0;
    IF length<i THEN length := i END;
    IF (FreeChars(w)>=length) THEN
      WHILE length>6 DO WriteChar(w, " "); DEC(length) END;
      WHILE length>i DO WriteChar(w, "0"); DEC(length) END;
      REPEAT DEC(i); WriteChar(w, a[i]) UNTIL i=0
    END
  END WriteO;
  
END OutWindow.

