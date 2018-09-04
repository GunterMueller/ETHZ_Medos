IMPLEMENTATION MODULE EditHeap; (* vs I.11          Werner Winiger 24.4.81
                      ========  *)

  FROM SYSTEM IMPORT
    ADDRESS, ADR;
  IMPORT Storage;
  FROM EditDisplay IMPORT
    InitEditDisplay, SysErr, ShowMsg;
 
 
  CONST
    resSize = 300;

  VAR 
    res       : ADDRESS;  
    secondTime: BOOLEAN;

  PROCEDURE Warning;
    VAR (*  -------  *)
      i,j: CARDINAL;
  BEGIN 
    FOR i := 0 TO 4 DO
      ShowMsg('');
      FOR j := 0 TO 10000 DO END;
      ShowMsg('HEAP LOW !!! (Exit and restart !)');
      FOR j := 0 TO 10000 DO END;
    END;
  END Warning;

  PROCEDURE H (): CARDINAL;
  CODE
    247b; (* SYS     *)
      4 ; (* push(H) *)
  END H;
 
  PROCEDURE ALLOCATE (VAR p: ADDRESS; psize: CARDINAL);
    VAR (*  --------                                *)
      stack: CARDINAL;
  BEGIN
    IF (H() - ADR(stack)) <= 600b THEN
      IF secondTime THEN
        IF ((H() - ADR(stack)) > 500b) AND Storage.Available(psize)
        THEN Storage.ALLOCATE(p,psize); Warning;
        ELSE SysErr('Heap overflow!  I warned you !!!');
        END;
      ELSE
        Warning;
        Storage.DEALLOCATE(res,resSize);
        IF Storage.Available(psize)
        THEN Storage.ALLOCATE(p,psize);
        ELSE SysErr('paech gha!');
        END;
        secondTime := TRUE;
      END;
    ELSE
      Storage.ALLOCATE(p,psize);
    END;
  END ALLOCATE;


  PROCEDURE InitEditHeap;
  BEGIN (*  ------------  *)
    InitEditDisplay;
    Storage.ALLOCATE(res,resSize);
    secondTime := FALSE;
  END InitEditHeap;

END EditHeap.
