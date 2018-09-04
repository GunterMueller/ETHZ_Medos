IMPLEMENTATION MODULE EditDocuments; (* vs I.11      NW 10.1.80, WW 3.2.82
                      =============  *)

  FROM EditHeap IMPORT
    ALLOCATE, InitEditHeap;
  FROM Storage IMPORT
    DEALLOCATE;
  FROM EditFiles IMPORT
    FileNo, InsFno, thisCH, nextCH, prevCH, CharPos, DelChar, PutChar,
    OutChar, InitEditFiles;

  CONST
    NULL = 0c;

  TYPE
    PiecePtr = POINTER TO Piece;

    Piece    = RECORD
                 next, prev: PiecePtr;
                 FPN, CHN: CARDINAL;
                 length: CARDINAL;
               END;

    Buffer   = RECORD
                 length: CharNo;
                 firstPiece, lastPiece: PiecePtr
               END;
 
  VAR
    marker       : ARRAY DocNo OF PiecePtr;
    P            : PiecePtr;     (*current scan position*)
    M            : CharNo;
    lastInsPiece : PiecePtr;
    BUF          : Buffer;

  
  PROCEDURE CopyPiece (p: PiecePtr): PiecePtr;
    VAR (*  ---------            *)
      np: PiecePtr;
  BEGIN NEW(np); np^ := p^; RETURN np
  END CopyPiece;

  PROCEDURE createDoc (d: DocNo);
    VAR (*  ---------         *)
      np: PiecePtr;
  BEGIN NEW(np);
    WITH np^ DO
      FPN := InsFno; CHN := 0; length := 1; prev := np; next := np
    END ;
    marker[d] := np
  END createDoc;

  PROCEDURE inputDoc (d: DocNo; f: FileNo; n: CARDINAL);
    VAR (*  --------                                 *)
      p,p0: PiecePtr;
  BEGIN p0 := marker[d]; NEW(p);
    WITH p^ DO
      FPN := f; CHN := 0; length := n;
      prev := p0; next := p0
    END ;
    p0^.next := p; p0^.prev := p
  END inputDoc;

  PROCEDURE outputDoc (d: DocNo);
    VAR (*  ---------         *)
      p0,p1: PiecePtr; n: CARDINAL;
  BEGIN p0 := marker[d]; p1 := p0^.next;
    WHILE p1 # p0 DO
      OutChar(thisCH(p1^.FPN, p1^.CHN)); n := p1^.length-1;
      WHILE n > 0 DO
        OutChar(nextCH()); DEC(n)
      END ;
      p1 := p1^.next
    END
  END outputDoc;

  PROCEDURE delDoc (d: DocNo);
    VAR (*  ------         *)
      p0, p1: PiecePtr;
  BEGIN 
    p1 := marker[d];
    REPEAT
      p0 := p1;
      p1 := p0^.next;
      DISPOSE(p0);
    UNTIL p1 = marker[d];
  END delDoc;

  PROCEDURE thisChar (d: DocNo; n: CharNo): CHAR;
  BEGIN (*  --------                    *)
    P := marker[d]^.next; M := n; currentIndex := n;
    WHILE P^.length <= M DO
      M := M - P^.length; P := P^.next
    END ;
    RETURN thisCH(P^.FPN, P^.CHN + M)
  END thisChar;
 
  PROCEDURE nextChar (): CHAR;
  BEGIN (*  -------- *)
    INC(M);
    IF M < P^.length THEN 
      INC(currentIndex); RETURN nextCH()
    ELSE
      IF currentIndex < 0FFFFh
      THEN INC(currentIndex);
      ELSE currentIndex := 0;
      END;
      P := P^.next; M := 0; RETURN thisCH(P^.FPN, P^.CHN)
    END
  END nextChar;
 
  PROCEDURE prevChar (): CHAR;
  BEGIN (*  -------- *)
    IF M > 0 THEN 
      DEC(currentIndex);
      DEC(M);
      RETURN prevCH()
    ELSE  
      IF currentIndex > 0
      THEN DEC(currentIndex);
      ELSE currentIndex := 0FFFFh;
      END;
      P := P^.prev; M := P^.length - 1;
      RETURN thisCH(P^.FPN, P^.CHN + M)
    END
  END prevChar;

  PROCEDURE length (d: DocNo): CharNo;
    VAR (*  ------         *)
      p, p0: PiecePtr; n: CharNo;
  BEGIN p0 := marker[d]; p := p0^.next; n := 0;
    WHILE p # p0 DO
      n := n + p^.length; p := p^.next
    END ;
    RETURN n
  END length;

  PROCEDURE findPos (d: DocNo; n: CharNo; (*
            ------- *)         VAR p: PiecePtr; VAR m: CARDINAL);
    VAR p0: PiecePtr; n0: CharNo;
  BEGIN p0 := marker[d]^.next; n0 := n;
    WHILE p0^.length <= n0 DO
      n0 := n0 - p0^.length; p0 := p0^.next
    END ;
    p := p0; m := n0
  END findPos;

  PROCEDURE incpos (p: PiecePtr; n: CARDINAL);
  BEGIN (*  ------                         *)
    DEC(p^.length, n); INC(p^.CHN, n)
  END incpos;

  PROCEDURE insertBuffer (d: DocNo; m: CharNo; VAR leng: CharNo);
    VAR (*  ------------                                      *)
      p0,p1,p2,p3,p4: PiecePtr; n: CARDINAL;
  BEGIN
    p3 := BUF.firstPiece;
    IF p3 # NIL THEN
      findPos(d,m,p0,n);
      IF n = 0 THEN 
        p2 := p0; p0 := p2^.prev 
      ELSE
        p2 := CopyPiece(p0); p0^.length := n; incpos(p2,n);
        IF p0 = lastInsPiece THEN lastInsPiece := NIL; END;
        p2^.next^.prev := p2
      END;
      p4 := BUF.lastPiece^.next;
      REPEAT p1 := CopyPiece(p3); p0^.next := p1;
        p1^.prev := p0; p0 := p1; p3 := p3^.next
      UNTIL p3 = p4;
      p0^.next := p2; p2^.prev := p0
    END ;
    leng := BUF.length
   END insertBuffer;

  PROCEDURE selectBuffer (d: DocNo; m1,m2: CharNo);
    VAR (*  ------------                        *)
      p0,p1,p2,p3,pA,pB: PiecePtr;
      n1,n2: CARDINAL;
  BEGIN
    WITH BUF DO 
      IF lastPiece # NIL THEN
        p1 := firstPiece;
        lastPiece^.next := firstPiece;
        REPEAT
          p0 := p1;
          p1 := p0^.next;
          DISPOSE(p0);
        UNTIL p1 = firstPiece;
      END;
    END;
    findPos(d,m1,p1,n1); findPos(d,m2,p2,n2); INC(n2);
    p0 := p1^.prev; p3 := p2^.next;
    IF n2 < p2^.length THEN
      pB := CopyPiece(p2); incpos(pB,n2);
      p2^.length := n2; p3^.prev := pB;
      pB^.prev := p2; p2^.next := pB;
    END ;
    IF n1 > 0 THEN
      pA := CopyPiece(p1); pA^.length := n1;
      incpos(p1,n1); p0^.next := pA;
      pA^.next := p1; p1^.prev := pA;
    END ;
    WITH BUF DO
      length := m2-m1+1;
      pA := CopyPiece(p1);
      firstPiece := pA;
      WHILE p1 # p2 DO
        p1 := p1^.next;
        pB := CopyPiece(p1);
        pB^.prev := pA;
        pA^.next := pB;
        pA := pB;
      END;
      lastPiece  := pA;
    END;
  END selectBuffer;

  PROCEDURE delete;
    VAR (*  ------ *)
      p1, p2: PiecePtr;
  BEGIN
    WITH BUF DO
      p1 := firstPiece^.prev; (* selectBuffer kept these pointers *)
      p2 := lastPiece^.next;
    END;
    p1^.next := p2;
    p2^.prev := p1;
  END delete;

  PROCEDURE insertedBetween (p0,p2: PiecePtr): PiecePtr;
    VAR (*  ---------------                *)
      p1: PiecePtr;
  BEGIN NEW(p1);
    WITH p1^ DO
      FPN := InsFno; CHN := CharPos(); length := 0;
      prev := p0; next := p2
    END ;
    lastInsPiece := p1; p0^.next := p1; p2^.prev := p1; RETURN p1
  END insertedBetween;

  PROCEDURE insertChar (ch: CHAR; d: DocNo; m: CharNo);
    VAR (*  ----------                              *)
      p0,p1,p2: PiecePtr; n: CARDINAL;
  BEGIN findPos(d,m,p0,n);
    IF n = 0 THEN
      p1 := p0^.prev;
      IF p1 # lastInsPiece THEN p1 := insertedBetween(p1,p0); END
    ELSE
      p2 := CopyPiece(p0); p0^.length := n; incpos(p2, n);
      p2^.next^.prev := p2; p1 := insertedBetween(p0,p2)
    END ;
    PutChar(ch); INC(p1^.length);
  END insertChar;

  PROCEDURE delChar (d: DocNo; m: CharNo; VAR done: BOOLEAN);
    VAR (*  -------                                       *)
      p0,p1: PiecePtr; n: CARDINAL;
  BEGIN 
    findPos(d,m,p0,n);
    IF n > 0 THEN
      p1 :=  CopyPiece(p0); p1^.length := n-1; incpos(p0, n);
      p1^.next := p0;
      p1^.prev^.next := p1;
      p0^.prev := p1;
    ELSE
      p1 := p0^.prev;
      DEC(p1^.length);
    END;
    IF p1^.length = 0 THEN  (*delete piece*)
      p1^.prev^.next := p1^.next; p1^.next^.prev := p1^.prev;
      DISPOSE(p1);
    END;
    done := TRUE;(*!!! change definition*)
    lastInsPiece := NIL;
  END delChar;

  PROCEDURE readBuffer (d: DocNo; m1,m2: CharNo; 
                        VAR s: ARRAY OF CHAR; VAR length: CARDINAL);
    VAR (*  ----------                                           *)
      maxLength: CARDINAL;
    CONST
      Max = 39;   (* 50 - size('searching') *)
  BEGIN
    maxLength := m2 - m1 + 1;
    IF Max < maxLength THEN maxLength := Max; END;
    length := 0;
    s[length] := thisChar(d,m1);
    LOOP
      INC(length);
      IF length >= maxLength THEN EXIT END;
      s[length] := nextChar();
    END;
    s[length] := NULL;
  END readBuffer;

  PROCEDURE InitEditDocuments;
  BEGIN (*  -----------------  *)
    InitEditHeap;
    InitEditFiles;
    lastInsPiece := NIL;
    WITH BUF DO
      firstPiece := NIL;
      lastPiece  := NIL;
      length := 0;
    END;
  END InitEditDocuments;

END EditDocuments.
