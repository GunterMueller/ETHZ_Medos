IMPLEMENTATION MODULE HermesByte;

FROM SYSTEM IMPORT WORD;


VAR  dummy   : CARDINAL;
     MaxTime : CARDINAL; (* current length of the time out *)


PROCEDURE PUT(chan : CARDINAL; value : WORD);
  CODE 241b
  END PUT;


PROCEDURE GET(chan : CARDINAL; VAR value : WORD);
  CODE 240b
  END GET;
 

PROCEDURE SendByte( b : CHAR);
  VAR st : BITSET;
  BEGIN
    REPEAT GET(5, st) UNTIL 15 IN st;
    PUT(4, b)
  END SendByte;

PROCEDURE ReceiveByte( VAR b : CHAR);
  VAR st : BITSET; retry : CARDINAL;
  BEGIN retry := MaxTime;
    LOOP
      GET(5, st);
      IF 14 IN st THEN GET(4,b); TimeOut := FALSE; EXIT END;
      IF 14 IN st THEN GET(4,b); TimeOut := FALSE; EXIT END;
      IF TimeOutOn THEN DEC(retry) END;
      IF 14 IN st THEN GET(4,b); TimeOut := FALSE; EXIT  END;
      IF retry = 0 THEN TimeOut := TRUE; EXIT END
    END
   END ReceiveByte;

PROCEDURE TimeOutLength(length : CARDINAL);
  BEGIN MaxTime := length
  END TimeOutLength;

BEGIN
  GET(4,dummy); (* reset uart *)
END HermesByte.
