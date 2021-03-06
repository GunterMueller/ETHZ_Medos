(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          Storage:                    *
*                                      *
*          ALLOCATE and DEALLOCATE,    *
*          procedures called by        *
*          NEW and DISPOSE in          *
*          MODULA-2, can be imported   *
*          from this module.           * 
*                                      *
*          Version 4  18.06.82         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

(*  Note: 
      This version of Storage uses module Program in it's im-
      plementation. Restrictions for the use of program are
      valid for Storage too:
        
      Storage can only be used in the 'main' program or in
      routines activated (directly or indirectly) by it.
                                                                *)

IMPLEMENTATION MODULE Storage;

  FROM SYSTEM IMPORT
    ADDRESS, ADR;
 
  FROM Program IMPORT 
    AllocateHeap, DeallocateHeap,
    SharedLevel;

  FROM Terminal IMPORT
    WriteString, WriteLn;

  TYPE
    HeaderPointer = POINTER TO Header;
    Header =  RECORD
                next: HeaderPointer;
                size: CARDINAL; 
              END;

  VAR 
    freelist: HeaderPointer; 
    header: Header;
    highaddr, lowaddr: ADDRESS;
    sharedlevel: CARDINAL;


  PROCEDURE ALLOCATE(VAR a: ADDRESS; s: CARDINAL);

  VAR 
    last, this: HeaderPointer;       
    top: ADDRESS; 
  
  BEGIN 
    IF s = 0 THEN a := lowaddr
    ELSE
      IF s = 1 THEN s := 2 END; 
      last := freelist; this := header.next; 
      LOOP 
        IF this = freelist THEN
          IF sharedlevel <> SharedLevel() THEN
            WriteString('- Storage.ALLOCATE: not shared ALLOCATE'); WriteLn;
            HALT
          ELSE 
            top := AllocateHeap(0); 
            lowaddr := AllocateHeap(s); 
            IF top - lowaddr = s THEN
              a := lowaddr; EXIT 
            ELSE 
              lowaddr := DeallocateHeap(top - lowaddr); 
              WriteString('- Storage.ALLOCATE: heap overflow'); WriteLn; 
              HALT 
            END 
          END
        ELSIF this^.size = s THEN 
          a := this; 
          last^.next := this^.next;  
          EXIT 
        ELSIF this^.size >= s + 2 THEN
          DEC(this^.size, s); 
          a := ADDRESS(this) + this^.size; 
          EXIT 
        END; 
        last := this; this := this^.next 
      END 
    END;
  END ALLOCATE;   
 

  PROCEDURE DEALLOCATE(VAR a:ADDRESS; s: CARDINAL); 
 
    VAR
      last, this, new: HeaderPointer;
      thisaddr, topaddr, top: ADDRESS;
 
  BEGIN
    IF s > 0 THEN
      IF s = 1 THEN s := 2 END;
      IF 177777B - s < a THEN top := 177777B ELSE top := a + s END;
      IF (top <= highaddr) AND (a >= lowaddr) THEN
        last := freelist; this := header.next; 
        WHILE ADDRESS(this) > top DO
          last := this; this := this^.next; 
        END; 
        LOOP 
          thisaddr := ADDRESS(this); 
          topaddr := thisaddr + this^.size; 
          IF a > topaddr THEN EXIT END; 
          IF topaddr > top THEN top := topaddr END;
          IF thisaddr < a THEN a := thisaddr END; 
          this := this^.next; 
        END; 
        IF (lowaddr = a) AND (lowaddr = AllocateHeap(0)) 
           AND (sharedlevel = SharedLevel())
        THEN
          lowaddr := DeallocateHeap(top-a);
          last^.next := freelist;
        ELSE
          new := a;
          last^.next := new; 
          WITH new^ DO 
            next := this; 
            size := top - a 
          END;
        END; 
      ELSE
        WriteString('- Storage.DEALLOCATE: bad pointer'); WriteLn;
        HALT;
      END; 
    END;
    a := NIL; 
  END DEALLOCATE; 
 
 
  PROCEDURE Available(s: CARDINAL): BOOLEAN;

  VAR 
    last, this: HeaderPointer;       
    top: ADDRESS; actualsize: CARDINAL;
    av: BOOLEAN;
  
  BEGIN 
    IF s = 0 THEN RETURN TRUE
    ELSE
      IF s = 1 THEN s := 2 END; 
      last := freelist; this := header.next; 
      LOOP 
        IF this = freelist THEN
          IF sharedlevel = SharedLevel() THEN 
            top := AllocateHeap(0); 
            lowaddr := AllocateHeap(s); 
            actualsize := top - lowaddr; 
            av := actualsize = s; 
            lowaddr := DeallocateHeap(actualsize);
          ELSE av := FALSE
          END; 
          RETURN av 
        ELSIF (this^.size = s) OR (this^.size >= s+2) THEN
          RETURN TRUE
        END; 
        last := this; this := this^.next 
      END 
    END;
  END Available;   


BEGIN
  freelist := ADDRESS(ADR(header));
  header.next := freelist; 
  header.size := 0; 
  highaddr := AllocateHeap(0);
  lowaddr := highaddr; 
  sharedlevel := SharedLevel();
END Storage.


