IMPLEMENTATION MODULE Memory;   (*NW 28.4.82*)
  FROM Program IMPORT AllocateHeap, DeallocateHeap;
  FROM Terminal IMPORT WriteString, WriteLn;
  FROM SYSTEM IMPORT ADDRESS;

  VAR current, hold, last: ADDRESS;

  PROCEDURE New(n: CARDINAL): ADDRESS;
  BEGIN
    IF current < last-n THEN
      current := current + n; RETURN current - n
    ELSE
      WriteString(" not enough space"); WriteLn; RETURN NIL
    END
  END New;

  PROCEDURE Mark;
  BEGIN hold := current
  END Mark;

  PROCEDURE Reset;
  BEGIN current := hold
  END Reset;

  PROCEDURE Init;
  BEGIN last := AllocateHeap(0); current := AllocateHeap(177776B);
    current := DeallocateHeap(4000B); Mark
  END Init
END Memory.
