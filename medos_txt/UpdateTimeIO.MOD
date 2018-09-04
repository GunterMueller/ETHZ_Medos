IMPLEMENTATION MODULE UpdateTimeIO; (* WW 15.6.83 *)

FROM Monitor IMPORT
  Time;

TYPE
  MonthName = ARRAY [0..2] OF CHAR;

VAR
  monthName: ARRAY [1..12] OF MonthName;
  monthLength: ARRAY [1..12] OF CARDINAL;


PROCEDURE ReadTime (VAR time: Time; VAR ok: BOOLEAN;
                    VAR ch: CHAR; Read: CharReadProc);
VAR
  da, mon, year, hour, min, sec: CARDINAL;

  PROCEDURE ReadCard (VAR c: CARDINAL; lim: CARDINAL; VAR ok: BOOLEAN);
  VAR dig: CARDINAL;
  BEGIN
    ok := TRUE;
    WHILE ch = ' ' DO Read(ch); END;
    IF ('0' <= ch) AND (ch <= '9') THEN
      c := 0;
      REPEAT
        dig := CARDINAL(ch) - CARDINAL('0');
        IF c > (65535-dig) DIV 10 THEN
          ok := FALSE;
          RETURN;
        END;
        c := 10*c + dig;
        IF c > lim THEN
          ok := FALSE;
          RETURN;
        END;
        Read(ch)
      UNTIL (ch < '0') OR (ch > '9');
    ELSE
      ok := FALSE;
    END;
  END ReadCard;

  PROCEDURE ReadMonth (VAR m: CARDINAL; VAR ok: BOOLEAN);
  VAR
    i: CARDINAL;
    name: MonthName;
  BEGIN
    ok := TRUE;
    WHILE ch = ' ' DO Read(ch); END;
    name := "   ";
    i := 0;
    LOOP
      IF ('a' <= ch) AND (ch <= 'z') THEN ch := CAP(ch); END;
      IF ('A' <= ch) AND (ch <= 'Z') THEN
        IF i > 2 THEN
          ok := FALSE;
          RETURN;
        END;
        name[i] := ch;
        INC(i);
        Read(ch);
      ELSE
        EXIT;
      END;
    END;
    m := 1;
    LOOP
      IF (name[0] = CAP(monthName[m,0])) AND
         (name[1] = CAP(monthName[m,1])) AND
         (name[2] = CAP(monthName[m,2])) THEN
        EXIT;
      END;
      INC(m);
      IF m > 12 THEN
        ok := FALSE;
        RETURN;
      END;
    END;
    IF da > monthLength[m] THEN ok := FALSE; END;
  END ReadMonth;

  PROCEDURE SkipChar (skipchar: CHAR; VAR ok: BOOLEAN);
  BEGIN
    ok := TRUE;
    LOOP
      IF ch <> ' ' THEN
        IF ch = skipchar THEN Read(ch);
        ELSE ok := FALSE;
        END;
        EXIT;
      END;
      Read(ch);
    END;
  END SkipChar;

BEGIN (* ReadTime *)
  ReadCard(da,31,ok);
  IF NOT ok THEN RETURN; END;
  SkipChar('.',ok);
  IF NOT ok THEN RETURN; END;
  ReadMonth(mon,ok);
  IF NOT ok THEN RETURN; END;
  SkipChar('.',ok);
  IF NOT ok THEN RETURN; END;
  ReadCard(year,99,ok);
  IF NOT ok THEN RETURN; END;
  ReadCard(hour,23,ok);
  IF NOT ok THEN RETURN; END;
  SkipChar(':',ok);
  IF NOT ok THEN RETURN; END;
  ReadCard(min,59,ok);
  IF NOT ok THEN RETURN; END;
  SkipChar(':',ok);
  IF NOT ok THEN RETURN; END;
  ReadCard(sec,59,ok);
  IF NOT ok THEN RETURN; END;
  time.day := (year*20B + mon)*40B + da;
  time.minute := hour * 60 + min;
  time.millisecond := sec * 1000;
END ReadTime;


PROCEDURE WriteTime (time: Time; Write: CharWriteProc; zerofill: CHAR);
VAR
  da, mon, year, hour, min, sec, i: CARDINAL;
BEGIN
  WITH time DO
    da := day MOD 40B;
    mon := day DIV 40B MOD 20B;
    year := day DIV 1000B;
  END;
  IF da >= 10 THEN Write(CHAR(da DIV 10 + CARDINAL('0')));
  ELSIF zerofill <> 0c THEN Write(zerofill);
  END;
  Write(CHAR(da MOD 10 + CARDINAL('0')));
  Write('.');
  IF (mon > 0) AND (mon <= 12) THEN
    FOR i := 0 TO 2 DO Write(monthName[mon,i]); END;
  ELSE
    FOR i := 0 TO 2 DO Write('?'); END;
  END;
  Write('.');
  Write(CHAR(year DIV 10 + CARDINAL('0')));
  Write(CHAR(year MOD 10 + CARDINAL('0')));

  WITH time DO
    min := minute MOD 60;
    hour := minute DIV 60;
    sec := millisecond DIV 1000;
  END;
  Write(' ');
  IF hour >= 10 THEN Write(CHAR(hour DIV 10 + CARDINAL('0')));
  ELSE Write(' ');
  END;
  Write(CHAR(hour MOD 10 + CARDINAL('0')));
  Write(':');
  Write(CHAR(min DIV 10 + CARDINAL('0')));
  Write(CHAR(min MOD 10 + CARDINAL('0')));
  Write(':');
  Write(CHAR(sec DIV 10 + CARDINAL('0')));
  Write(CHAR(sec MOD 10 + CARDINAL('0')));
END WriteTime;

BEGIN (* UpdateTimeIO *)
  monthName[1]  := "Jan"; monthLength[1]  := 31;
  monthName[2]  := "Feb"; monthLength[2]  := 29;
  monthName[3]  := "Mar"; monthLength[3]  := 31;
  monthName[4]  := "Apr"; monthLength[4]  := 30;
  monthName[5]  := "May"; monthLength[5]  := 31;
  monthName[6]  := "Jun"; monthLength[6]  := 30;
  monthName[7]  := "Jul"; monthLength[7]  := 31;
  monthName[8]  := "Aug"; monthLength[8]  := 31;
  monthName[9]  := "Sep"; monthLength[9]  := 30;
  monthName[10] := "Oct"; monthLength[10] := 31;
  monthName[11] := "Nov"; monthLength[11] := 30;
  monthName[12] := "Dec"; monthLength[12] := 31;

END UpdateTimeIO.
