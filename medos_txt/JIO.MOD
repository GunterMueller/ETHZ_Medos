(*********************************************)
(*                                           *)
(*                                           *)
       IMPLEMENTATION MODULE JIO;
(*                                           *)
(*          Author Jirka Hoppe               *)
(*      Institut fuer Informatik             *)
(*             ETH Zurich                    *)
(*            Switzerland                    *)
(*                                           *)
(*           version 4/11/82                 *)
(*                                           *)
(*********************************************)

  FROM Terminal IMPORT Read, Write, BusyRead, ReadAgain, WriteString, WriteLn;
  FROM SYSTEM IMPORT WORD;

PROCEDURE ReadEcho(VAR ch : CHAR);
  (* read from terminal and echo *)
  BEGIN Read(ch); Write(ch)
  END ReadEcho;

PROCEDURE StopByKey():BOOLEAN;
  VAR ch : CHAR;
BEGIN BusyRead(ch);
  IF ch<>0c THEN ReadAgain END;
  RETURN (ch<>0C)
END StopByKey;

PROCEDURE WaitForKey;
  VAR ch : CHAR;
  (* wait if a key was hit *)
BEGIN BusyRead(ch);
  IF ch<>0c THEN Read(ch) END;
END WaitForKey;

PROCEDURE ReadOct( VAR n : WORD);
  (* read a octal number -> ; delimiter -> delim *)
  VAR ch : CHAR; help : CARDINAL;
  BEGIN  help := 0; ReadEcho(ch);
    LOOP
      IF ch = 177c THEN help := help DIV 8
      ELSE
        IF (ch < '0') OR (ch > '7') THEN delim := ch; n := WORD(help);  EXIT END;
        IF help <= (17777b) THEN help := help*8 + (CARDINAL(ch) - CARDINAL('0'))
        ELSE Write(177c)
        END
      END;
      ReadEcho(ch);
    END
  END ReadOct; 

PROCEDURE WriteOct(n : WORD; length : CARDINAL);
  VAR buff : ARRAY [1..6] OF CHAR; i : CARDINAL;  nn : CARDINAL;
  BEGIN nn := CARDINAL(n);
    FOR i := 1 TO 6 DO
      buff[i] := CHAR( nn MOD 8 + 60b); nn := nn DIV 8;
    END;
    IF length > 6 THEN 
      FOR i := 1 TO length-6 DO Write(' ') END;
      length := 6
    END;
    FOR i := length TO 1 BY -1 DO Write(buff[i]) END;
  END WriteOct;

  PROCEDURE ReadHex(VAR n:WORD);
    VAR ch:CHAR; help:CARDINAL;
    BEGIN n:=WORD(0);
      ReadEcho(ch);
      IF (ch >= 'a') AND (ch<>177c) THEN ch := CAP(ch) END;
      WHILE (((ch>='0')AND(ch<='9')) OR ((ch>='A') AND (ch<='F'))) OR (ch=177c) DO
        IF ch = 177c THEN n :=WORD(CARDINAL(n) DIV 16);
        ELSE
          IF ch <= '9' THEN help:=CARDINAL(ch)-30h
                       ELSE help:=CARDINAL(ch)-37h
          END;
          n:=WORD(CARDINAL(n)*16+help);
        END;
        ReadEcho(ch);
        IF (ch >= 'a') AND (ch<>177c) THEN ch := CAP(ch) END;
      END;
      delim := ch
    END ReadHex;


PROCEDURE WriteHex(n : WORD; length : CARDINAL);
  VAR buff : ARRAY [1..4] OF CHAR; i : CARDINAL;  nn : CARDINAL;
      help : CARDINAL;
  BEGIN nn := CARDINAL(n);
    FOR i := 1 TO 4 DO
      help := nn MOD 16; nn := nn DIV 16;
      IF help <= 9 THEN buff[i] := CHAR(help+30h)
                   ELSE buff[i] := CHAR(help+37h)
      END
    END;
    IF length > 4 THEN 
      FOR i := 1 TO length-4 DO Write(' ') END;
      length := 4
    END;
    FOR i := length TO 1 BY -1 DO Write(buff[i]) END;
  END WriteHex;

PROCEDURE ReadDec(VAR w :WORD);
  VAR help : CARDINAL;
BEGIN
  help := 0; 
  ReadEcho(delim);
  WHILE ((delim>='0') AND (delim<='9')) OR (delim=177c) DO
    IF delim = 177c THEN help := help DIV 10
    ELSIF help < (177777b DIV 10) THEN help := help * 10 + (CARDINAL(delim)-CARDINAL('0'))
    ELSE Write(177c)
    END;
    ReadEcho(delim)
  END;
  w := WORD(help)
END ReadDec;

PROCEDURE WriteDec(w : WORD; length : CARDINAL);
  VAR s : ARRAY [0..4] OF CHAR;
      i, help, n : CARDINAL;
BEGIN help := CARDINAL(w); s := '     '; n := 0;
  REPEAT
    s[n] := CHAR(help MOD 10 + CARDINAL('0')); help := help DIV 10; INC(n)
  UNTIL help = 0;
  FOR i := length TO n+1 BY -1 DO Write(' ') END;
  FOR i := n-1 TO 0 BY -1 DO Write(s[i]) END;
END WriteDec;

PROCEDURE WriteStringLn(s : ARRAY OF CHAR);
  BEGIN
    WriteString(s); WriteLn
  END WriteStringLn;

PROCEDURE Assert(b : BOOLEAN; s : ARRAY OF CHAR);
  BEGIN
    IF NOT b THEN WriteString('ASSERTION VIOLATION:'); WriteString(s); WriteLn; HALT END
  END Assert;

BEGIN
  versionJIOMod := '4/11/82';
END JIO.  

 
