(******************************************************************************
LLLLLLLL            Label-Management / Part of                          LLLLLLLL
LLLLLLLL            MIA / Version 19 / 20.07.81 / G. Schild             LLLLLLLL
*******************************************************************************)

IMPLEMENTATION MODULE Labels;

FROM BinFile IMPORT Update;

FROM TextIO IMPORT Print, PrintChar, NewPage, LineCount,
                   PutHex, Erratum, eol, fullPage, lineSize;

FROM Storage IMPORT ALLOCATE, DEALLOCATE;

CONST maxLab  = 400;

TYPE TLab     = RECORD  name:Label;
                        madr:CARDINAL
                END;
     ListPtr  = POINTER TO OLab;
     RefPtr   = POINTER TO Reference;
     OLab     = RECORD  name:Label;
                        next:ListPtr;
                        follow:RefPtr
                END;
     Reference= RECORD  madr:CARDINAL;
                        follow:RefPtr
                END;

VAR labTab : ARRAY [1..maxLab] OF TLab;
    firstGlobal, lastGlobal,
    firstLokal, lastLokal,
    firstIllegal, lastIllegal : ListPtr;
    topGlobal, topLokal, index : CARDINAL;
    localChar : CHAR;
    exclLocal : BOOLEAN;

PROCEDURE OpenJump():BOOLEAN;
BEGIN
RETURN NOT((firstGlobal = NIL) AND (firstLokal = NIL) AND (firstIllegal = NIL))
END OpenJump;

PROCEDURE CutLocalLab(VAR res:Response);
BEGIN
topLokal := topGlobal;
  IF firstLokal <> NIL 
  THEN AppendList(firstLokal,lastLokal);
  firstLokal := NIL; lastLokal := NIL;
  res := warning
  ELSE res := done
  END
END CutLocalLab;

PROCEDURE SetLocalChar(ch:CHAR;on:BOOLEAN;VAR res:Response);
BEGIN localChar := ch; exclLocal := on; CutLocalLab(res) END SetLocalChar;

PROCEDURE Global(name:Label):BOOLEAN;
BEGIN
IF exclLocal
THEN RETURN name[0] <> localChar
ELSE RETURN name[0] = localChar
END
END Global;

PROCEDURE Equal(l1,l2:Label):BOOLEAN;
VAR i : CARDINAL;
BEGIN
FOR i := 0 TO 9 DO IF l1[i] <> l2[i] THEN RETURN FALSE END END;
RETURN TRUE
END Equal;

PROCEDURE Exist(name:Label):BOOLEAN;
VAR z : CARDINAL;
BEGIN
  IF Global(name)
  THEN index := 1; z := topGlobal
  ELSE index := topGlobal+1; z := topLokal
  END;
  LOOP
  IF index > z THEN RETURN FALSE END;
  IF Equal(labTab[index].name,name) THEN RETURN TRUE END;
  INC(index)
  END;
END Exist;

PROCEDURE Known(name:Label):ListPtr;
VAR z : ListPtr;
BEGIN
  IF Global(name)
  THEN z := firstGlobal
  ELSE z := firstLokal
  END;
  LOOP
  IF z = NIL THEN RETURN NIL END;
  IF Equal(z^.name,name) THEN RETURN z END;
  z := z^.next
  END 
END Known;

PROCEDURE AppendRef(place:ListPtr;adr:CARDINAL);
VAR q : RefPtr;
BEGIN
q := place^.follow;
LOOP
IF q^.follow = NIL THEN EXIT END;
q := q^.follow
END;
NEW(q^.follow);
  WITH q^.follow^ DO 
  madr := adr;
  follow := NIL
  END
END AppendRef;

PROCEDURE AppendLab(name:Label;maddr:CARDINAL);
VAR a : ListPtr;
BEGIN
NEW(a);
a^.name := name;
a^.next := NIL;
NEW(a^.follow);
  WITH a^.follow^ DO 
  madr := maddr;
  follow := NIL
  END;
  IF Global(name)
  THEN
    IF firstGlobal = NIL
    THEN firstGlobal := a
    ELSE lastGlobal^.next := a
    END;
  lastGlobal := a
  ELSE
    IF firstLokal = NIL
    THEN firstLokal := a
    ELSE lastLokal^.next := a
    END;
  lastLokal := a
  END
END AppendLab;

PROCEDURE AppendList(p,q:ListPtr);
BEGIN
  IF firstIllegal = NIL
  THEN firstIllegal := p
  ELSE lastIllegal^.next := p
  END;
lastIllegal := q
END AppendList;

PROCEDURE Clear(id:Label;value:CARDINAL);
VAR a, b : ListPtr;
    p, q : RefPtr;
    gl : BOOLEAN;
BEGIN
gl := Global(id);
  IF gl
  THEN a := firstGlobal
  ELSE a := firstLokal
  END;
b := a;
  LOOP
  IF a = NIL THEN RETURN END;
  IF Equal(a^.name,id) THEN EXIT END;
  b := a; a := a^.next
  END;
  IF a = b
  THEN IF gl
    THEN firstGlobal := a^.next;
      IF lastGlobal = b THEN lastGlobal := a^.next END
    ELSE firstLokal := a^.next;
      IF lastLokal = b THEN lastLokal := a^.next END
    END
  ELSE
  b^.next := a^.next;
    IF a = lastGlobal THEN lastGlobal := b
    ELSIF a = lastLokal THEN lastLokal := b
    END
  END;
q := a^.follow;
DISPOSE(a);
  REPEAT Update(value,q^.madr);
  p := q; q := q^.follow; DISPOSE(p)
  UNTIL q = NIL
END Clear;
 
PROCEDURE FixLab(name:Label;madr:CARDINAL):CARDINAL;
VAR a : ListPtr;
BEGIN
  IF Exist(name)
  THEN RETURN labTab[index].madr
  ELSE a := Known(name);
    IF a = NIL
    THEN AppendLab(name,madr)
    ELSE AppendRef(a,madr)
    END;
  RETURN 0
  END
END FixLab;

PROCEDURE InsertLab(id:Label;value:CARDINAL;VAR res:Response);
BEGIN
IF Exist(id) THEN res := twice; RETURN END;
  IF Global(id)
  THEN INC(topGlobal);
  IF topGlobal > maxLab THEN res := overflow; RETURN END;
  CutLocalLab(res)
  ELSE INC(topLokal);
  IF topLokal > maxLab THEN res := overflow; RETURN END;
  END;
  WITH labTab[topLokal] DO
  name := id; madr := value
  END;
res := done;
Clear(id,value)
END InsertLab;

PROCEDURE PrintLabList;

  PROCEDURE ListHeader;
  BEGIN
  NewPage;
  Print(" List of the undeclared Labels");
  Print(" *****************************");
  PrintChar(eol)
  END ListHeader;

  PROCEDURE PageHeader;
  BEGIN
  Print("Label-Name      References");
  PrintChar(eol)
  END PageHeader;

  PROCEDURE SingleLab;
  VAR s : RefPtr;
      q : ARRAY [0..lineSize] OF CHAR;
      x : ARRAY [0..4] OF CHAR;
      i, z : CARDINAL;
  BEGIN
  FOR i := 0 TO 9 DO q[i] := firstIllegal^.name[i] END;
  z := 10;
  FOR i := 10 TO lineSize DO q[i] := " " END;
  s := firstIllegal^.follow;
  firstIllegal := firstIllegal^.next;
    LOOP
    PutHex(s^.madr,x);
    FOR i := 0 TO 4 DO q[z+i] := x[i] END;
    z := z+5;
      IF z > lineSize-1 
      THEN Print(q);
        IF s^.follow = NIL
        THEN EXIT
        ELSE FOR i := 0 TO lineSize DO q[i] := " " END;
        z := 10;
          IF LineCount() = fullPage
          THEN NewPage; PageHeader
          END
        END
      END;
    s := s^.follow;
    IF s = NIL THEN Print(q); EXIT END
    END
  END SingleLab;

BEGIN
Erratum(17);
IF firstLokal <> NIL THEN AppendList(firstLokal,lastLokal) END;
IF firstGlobal <> NIL THEN AppendList(firstGlobal,lastGlobal) END;
ListHeader;
PageHeader;
  LOOP
    LOOP
    IF (LineCount() > fullPage) OR (firstIllegal = NIL) THEN EXIT END;
    SingleLab
    END;
  IF firstIllegal = NIL THEN EXIT END;
  NewPage;
  PageHeader
  END
END PrintLabList;

BEGIN
topGlobal    := 0;
topLokal     := 0;
firstGlobal  := NIL;
firstLokal   := NIL;
firstIllegal := NIL;
lastGlobal   := NIL;
lastLokal    := NIL;
lastIllegal  := NIL;
exclLocal    := TRUE;
localChar    := " "
END Labels.
