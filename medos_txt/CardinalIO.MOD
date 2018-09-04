(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          CardinalIO:                 *
*                                      *
*          Utility privat to MEDOS-2   *
*          for reading and writing     *
*          CARDINALS to an from the    *
*          Terminal.                   *
*                                      *
*          Version 2  25.09.80         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

IMPLEMENTATION MODULE CardinalIO;

  FROM Terminal IMPORT Read, ReadAgain, Write;

  CONST
    eol =  36C;
    esc =  33C;
    del = 177C;

  PROCEDURE ReadOct(VAR c: CARDINAL);
    VAR ch: CHAR; chcnt: CARDINAL;
  BEGIN
    chcnt := 0; (* written char's *)
    c := 0;     (* return value *)
    LOOP
      Read(ch);
      IF ('0' <= ch) AND (ch <= '7') THEN EXIT END;
      IF ch = esc THEN EXIT END;
      IF ch = ' ' THEN Write(' '); INC(chcnt) END;
      IF (ch = del) AND (chcnt > 0) THEN
        DEC(chcnt); Write(del)
      END;
    END;
    LOOP
      IF (ch = esc) OR (ch = eol) OR (ch = ' ') THEN EXIT END;
      IF (c <= 17777B) AND ('0' <= ch) AND (ch <= '7') THEN
        Write(ch); INC(chcnt);
        c := 10B * c + (CARDINAL(ch) - CARDINAL('0'));
      ELSIF (ch = del) AND (chcnt > 0) THEN
        DEC(chcnt); Write(del); c := c DIV 10B;
      END;
      Read(ch);
    END;
    ReadAgain;
  END ReadOct;

  PROCEDURE WriteOct(c: CARDINAL);
    VAR base: CARDINAL;
  BEGIN
    Write(' ');
    IF c >= 100000B THEN
      Write('1'); DEC(c, 100000B)
    ELSE Write('0')
    END;
    base := 10000B;
    WHILE base > 0 DO
      Write(CHAR(c DIV base + CARDINAL('0')));
      c := c MOD base; base := base DIV 10B;
    END;
  END WriteOct;

END CardinalIO.

