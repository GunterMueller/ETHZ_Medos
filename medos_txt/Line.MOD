(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          Line:                       *
*                                      *
*          Line reads from and writes  *
*          to the asyncronous V24      *
*          connection. <cr><lf> is     *
*          converted to <eol> and      *
*          vice versa.                 * 
*                                      *
*          Version 2    5.10.80        *    
*          Version 4.2   9.5.83        *
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

IMPLEMENTATION MODULE Line;

  FROM SYSTEM IMPORT WORD;

  CONST
    linedata   =  4;
    linestatus =  5;
    donebit    = 14;
    freebit    = 15;

    cr         = 15C;
    lf         = 12C;
    eol        = 36C;  (* eol <> cr  for algorithm in Write *)

    (* Instructs for handling input and output.  *)
    readw  = 240B;         (* read a word from channel *)
    writew = 241B;         (* write a word to channel  *)


  PROCEDURE Get(channel: CARDINAL; VAR w: WORD);
  CODE
    readw
  END Get;

  PROCEDURE Put(channel: CARDINAL; w: WORD);
  CODE
    writew
  END Put;


  VAR
    crrec: BOOLEAN;
    oldch: CHAR;
    validoldch: BOOLEAN;

  PROCEDURE BusyRead(VAR ch: CHAR);
    VAR status: BITSET;
  BEGIN
    IF validoldch THEN
      ch := oldch; validoldch := FALSE
    ELSE
      Get(linestatus, status);
      IF donebit IN status THEN
        Get(linedata, ch);
        IF ch = cr THEN
          IF crrec THEN
            oldch := cr; validoldch := TRUE
          END;
          crrec := NOT crrec
        ELSIF ch = lf THEN
          IF crrec THEN
            ch := eol; crrec := FALSE
          END
        ELSIF crrec THEN
          oldch := ch; validoldch := TRUE;
          ch := cr; crrec := FALSE
        END
      ELSE ch := 0C
      END
    END
  END BusyRead;

  PROCEDURE Read(VAR ch: CHAR);
    VAR got: BOOLEAN;
  BEGIN 
    REPEAT
      BusyRead(ch)
    UNTIL ch <> 0C
  END Read;

  PROCEDURE Write(ch: CHAR);
    VAR status: BITSET;
  BEGIN
    IF ch = eol THEN
      Write(cr);
      ch := lf
    END;
    REPEAT
      Get(linestatus, status)
    UNTIL freebit IN status;
    Put(linedata, ch)
  END Write;

END Line.

