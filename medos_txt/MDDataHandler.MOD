IMPLEMENTATION MODULE MDDataHandler;  (* P. Karrer 5.7.82 *)
                                      (* multiple corrections Ch. J. *)
(*  (*$T-*) (*$R-*) *)

  FROM SYSTEM IMPORT WORD;
  FROM Terminal IMPORT WriteString, WriteLn;
  FROM Storage IMPORT ALLOCATE, DEALLOCATE;
  FROM DumpFileHandler IMPORT Mem;

  FROM MDProcHandler IMPORT chain, chainmax;
  FROM MDModuleHandler IMPORT modTab;

  IMPORT FileSystem, Terminal, MDFileControl;

  (*FROM MDRefFileHandler IMPORT GetSym, GetNum, GetIdent, OpenRefFile; *)

  CONST debugMe = FALSE;

  MODULE MDRefFileHandler;  (*Carl Binding; modified by C.J. 3.6.81*)
    FROM FileSystem IMPORT 
      File, Lookup, Close, ReadWord, Response, SetRead, Reset; 
    FROM Terminal IMPORT WriteString, WriteLn; 
    FROM MDFileControl IMPORT refFile, refOpen, reffile, OpenFile;
    IMPORT RefSymbol, Ident;
    EXPORT (*QUALIFIED*) OpenRefFile, GetSym, GetNum, GetIdent;

    VAR
      highbyte: BOOLEAN;      (*using which part of curword*)
      curword: CARDINAL;      (*current word read (16 bit)*)

    PROCEDURE OpenRefFile(mn: CARDINAL; VAR ok: BOOLEAN);
      VAR new: BOOLEAN;
    BEGIN
      OpenFile(mn, reffile, new);
      ok := refOpen;
      highbyte := FALSE;
    END OpenRefFile;

    PROCEDURE ReadRefCh(VAR ch: CHAR);
      (* read one byte from the ref file *)
    BEGIN
      IF highbyte THEN
        ch := CHAR(curword DIV 256);
        highbyte := FALSE
      ELSE
        ReadWord(refFile, curword);
        ch := CHAR(curword MOD 256);
        highbyte := TRUE
      END;
    END ReadRefCh;

    PROCEDURE GetSym(VAR sym: RefSymbol);
      (* read one ref symbol *)
      VAR ch: CHAR;
    BEGIN
      ReadRefCh(ch);
      IF (CARDINAL(ch)<=CARDINAL(relRS)) AND NOT refFile.eof THEN
        sym := RefSymbol(ch)
      ELSE sym := undefRS
      END
    END GetSym;

    PROCEDURE GetNum(VAR num: CARDINAL);
      (* reads a number from the ref file *)
      VAR ch: CHAR;
    BEGIN
      ReadRefCh(ch);
      num := CARDINAL(ch) * 400B;
      ReadRefCh(ch);
      num := num + CARDINAL(ch);
    END GetNum;

    PROCEDURE GetIdent(VAR name: Ident);
      (* reads an identifier from the ref file *)
      VAR ch: CHAR;
          i: CARDINAL;
    BEGIN
      i := 0;
      (* read at most 'Idlength' characters *)
       REPEAT
         ReadRefCh(ch);
         name[i] := ch;
         INC(i);
       UNTIL (ch = 0C) OR (i > HIGH(name));
       (* skip remaining characters *)
       WHILE (ch<>0C) AND NOT refFile.eof DO ReadRefCh(ch) END;
    END GetIdent;

  END MDRefFileHandler;


  MODULE StandardTypes;
    IMPORT TypeDescPtr, RefSymbol, Ident, ALLOCATE;
    EXPORT standardType;

    VAR standardType: ARRAY [undefRS..processRS] OF TypeDescPtr;

    PROCEDURE EnterStandardType(name: Ident; type: RefSymbol; size: CARDINAL);
    BEGIN
      NEW(standardType[type]);
      WITH standardType[type]^ DO
        typename := name; typekind := type; typesize := size; 
        nexttype := NIL;    (*not used*)
        typenum := 177777B; (*not used*)
      END
    END EnterStandardType;

  BEGIN
    EnterStandardType("undef", undefRS, 1);
    EnterStandardType("INTEGER", integerRS, 1);
    EnterStandardType("CARDINAL", cardinalRS, 1);
    EnterStandardType("CHAR", charRS, 1);
    EnterStandardType("BOOLEAN", booleanRS, 1);
    EnterStandardType("REAL", realRS, 2);
    EnterStandardType("BITSET", bitsetRS, 1);
    EnterStandardType("PROCEDURE", proctypRS, 1);
    EnterStandardType("WORD", wordRS, 1);
    EnterStandardType("ADDRESS", addressRS, 1);
    EnterStandardType("PROCESS", processRS, 1);
  END StandardTypes;


  VAR
    dataroot: DataChainPtr;
    typeroot: TypeDescPtr;
    alterTyperoot: TypeDescPtr;
    alterChainUsed: BOOLEAN;    (* set by UseTypeInfo, ReturnTypeInfo*)
    actModNum: CARDINAL;
    error: BOOLEAN;

  PROCEDURE DeleteTypeChain(VAR p: TypeDescPtr);
    VAR q: TypeDescPtr;

    PROCEDURE DeleteFields(VAR p: FieldPtr);
      VAR q: FieldPtr;
    BEGIN
      WHILE p <> NIL DO
        q := p;
        p := p^.nextfield;
        DISPOSE(q);
      END
    END DeleteFields;

    PROCEDURE DeleteConstants(VAR p: ConstPtr);
      VAR q: ConstPtr;
    BEGIN
      WHILE p <> NIL DO
        q := p;
        p := p^.nextconst;
        DISPOSE(q);
      END
    END DeleteConstants;

  BEGIN (* DeleteTypeChain *)
    WHILE p <> NIL DO
      q := p;
      WITH p^ DO
        IF typekind = enumRS THEN DeleteConstants(firstconst)
        ELSIF typekind = recordRS THEN DeleteFields(firstfield)
        END;
        p := nexttype;
        DISPOSE(q);
      END 
    END 
  END DeleteTypeChain;

  PROCEDURE DeleteDataChain(VAR p: DataChainPtr);
    VAR q: DataChainPtr;
  BEGIN
    WHILE p <> NIL DO
      q := p;
      WITH p^ DO
        IF (objecttype = moduleRS) OR (objecttype = procRS) THEN
          DeleteDataChain(datachain)
        END;
        p := next;
        DISPOSE(q);
      END
    END;
  END DeleteDataChain;


  PROCEDURE ProcRefInfo(n: CARDINAL);
    VAR ok: BOOLEAN;
        sym: RefSymbol;
        i, pNr: CARDINAL;
        name: Ident;
  BEGIN 
    WITH chain^[n] DO
      OpenRefFile(modNr, ok);
      IF ok THEN FindRefHead(procNr, sym, name) END;
      IF NOT ok OR (sym=undefRS) THEN
        procName := 'PROCEDURE       ';i := 12;
        pNr := procNr;
        WHILE pNr > 0 DO
          procName[i] := CHAR((pNr MOD 10)+ CARDINAL('0'));
          pNr := pNr DIV 10; DEC(i)
        END
      ELSE
        FOR i := 0 TO 15 DO procName[i] := name[i] END;
        isLocalMod := (sym=moduleRS) AND (procNr>0)
      END
    END
  END ProcRefInfo;

  PROCEDURE CreateProcData(n: CARDINAL; VAR root: DataChainPtr);
    VAR ok: BOOLEAN; baseaddress: CARDINAL;
  BEGIN
    WITH chain^[n] DO
      IF NOT knowncall THEN RETURN END;
      DeleteDataChain(dataroot);
      OpenRefFile(modNr,ok);
      IF ok THEN
        IF isLocalMod THEN
          LOOP
            INC(n);
            IF n >= chainmax THEN RETURN END;
            IF chain^[n].knowncall THEN
              IF NOT chain^[n].isLocalMod THEN EXIT END
            END
          END;
          baseaddress := chain^[n].base
        ELSE baseaddress := base
        END;
        CreateDataTree(procNr, modNr, baseaddress);
        root := dataroot;
      ELSE root := NIL
      END
    END; 
  END CreateProcData;

  PROCEDURE CreateModData(m: CARDINAL; VAR root: DataChainPtr);
    VAR ok: BOOLEAN;
  BEGIN
    IF modTab[m] <> NIL THEN
      DeleteDataChain(dataroot);
      OpenRefFile(m, ok);
      IF ok THEN
        CreateDataTree(0, m, modTab[m]^.base);
        root := dataroot;
      ELSE root := NIL
      END
    END
  END CreateModData;

  PROCEDURE UseTypeInfo;  (*saves type tree for commands of varview
                            called by dataview*)
  BEGIN
    ReturnTypeInfo;
    alterTyperoot := typeroot;
    alterChainUsed := TRUE
  END UseTypeInfo;

  PROCEDURE ReturnTypeInfo;
  BEGIN
    IF (alterTyperoot<>NIL) AND (alterTyperoot<>typeroot) THEN 
      DeleteTypeChain(alterTyperoot) 
    END;
    alterChainUsed := FALSE;
  END ReturnTypeInfo;

  PROCEDURE Error;
  BEGIN
    IF NOT error THEN
      error := TRUE;
      WriteString("-- bad reference file"); WriteLn;
    END
  END Error;

  PROCEDURE SkipTypeRef;
    VAR sym: RefSymbol; num: CARDINAL;
  BEGIN
    GetSym(sym);
    IF sym = typerefRS THEN GetNum(num)
    ELSIF (sym<undefRS) OR (sym>processRS) THEN Error
    END
  END SkipTypeRef;

  PROCEDURE SkipType;
    VAR sym: RefSymbol; num: CARDINAL; name: Ident;

    PROCEDURE SkipConstants;
      VAR sym: RefSymbol; name: Ident; num: CARDINAL;
    BEGIN
      GetSym(sym);
      WHILE sym = constRS DO
        GetNum(num);
        GetIdent(name);
        GetSym(sym)
      END;
      IF sym <> endRS THEN Error END;
    END SkipConstants;

    PROCEDURE SkipFields;
      VAR sym: RefSymbol; num: CARDINAL; name: Ident;
    BEGIN
      GetSym(sym);
      WHILE sym = fieldRS DO
        GetNum(num); GetIdent(name);
        SkipTypeRef;
        GetSym(sym)
      END;
      IF sym <> endRS THEN Error END;
    END SkipFields;

  BEGIN (* SkipType *)
    GetNum(num); GetIdent(name);
    GetSym(sym); GetNum(num);
    CASE sym OF
      subrRS:
        GetNum(num); GetNum(num);
        SkipTypeRef |
      enumRS:   SkipConstants |      
      setRS, pointerRS, arrdynRS, openRS:
        SkipTypeRef |
      arrayRS:  SkipTypeRef; SkipTypeRef |
      recordRS: SkipFields |
      hiddenRS:
    ELSE Error
    END
  END SkipType;

  PROCEDURE SkipVar;
    VAR addrmode: RefSymbol; name: Ident;
        num: CARDINAL;
  BEGIN
    GetNum(num); GetSym(addrmode);
    CASE addrmode OF
      absRS, indRS, relRS:
    ELSE Error; RETURN
    END;
    GetNum(num); GetIdent(name);
    SkipTypeRef
  END SkipVar;

  PROCEDURE FindRefHead(objectnumber: CARDINAL; VAR sym: RefSymbol; VAR name: Ident);
    VAR objno: CARDINAL;
  BEGIN
    error := FALSE;
    GetSym(sym);
    IF sym <> reffileRS THEN Error END;
    GetNum(objno);
    IF objno <> 40B THEN Error END;
    GetSym(sym);
    IF sym <> moduleRS THEN Error END;
    LOOP
      IF error THEN EXIT END;
      CASE sym OF
        moduleRS, procRS:
          GetRefHead(objno, name);
          IF objno = objectnumber THEN EXIT END |
        varRS:  SkipVar |
        typeRS: SkipType |
        endRS:
      ELSE EXIT
      END;
      GetSym(sym)
    END;
    IF error THEN sym := undefRS END
  END FindRefHead;
 
  PROCEDURE GetRefHead(VAR objno: CARDINAL; VAR name: Ident);
    VAR lno: CARDINAL;
  BEGIN
    GetNum(lno); GetNum(objno); GetIdent(name);
  END GetRefHead;


  PROCEDURE CreateDataTree(objectnumber, modulenumber: CARDINAL;
              baseaddress: CARDINAL);
    VAR acttreeptr, actdataptr: DataChainPtr;

    PROCEDURE InsertDataEl(p: DataChainPtr);
    BEGIN
      p^.next := NIL;
      IF actdataptr<>NIL THEN actdataptr^.next := p;
      ELSIF acttreeptr<>NIL THEN 
        IF (acttreeptr^.objecttype=moduleRS) OR (acttreeptr^.objecttype=procRS) THEN
          acttreeptr^.datachain := p
        ELSIF debugMe THEN HALT 
        ELSE (* bad debugger error *)
        END;
      ELSE dataroot := p
      END;
      IF (p^.objecttype=moduleRS) OR (p^.objecttype=procRS) THEN
        p^.father := acttreeptr;
        acttreeptr := p;
        actdataptr := NIL;
      ELSE actdataptr := p
      END
    END InsertDataEl;

    PROCEDURE ExitStructure;
    BEGIN
      actdataptr := acttreeptr;
      IF acttreeptr<>NIL THEN acttreeptr := acttreeptr^.father
      ELSIF debugMe THEN HALT
      END
    END ExitStructure;

    PROCEDURE NewTypeDesc(VAR p: TypeDescPtr);
    BEGIN
      NEW(p);
      WITH p^ DO
        nexttype := typeroot; typenum := 177777B; typename := "";
        typesize := 0; typekind := undefRS; 
        IF alterChainUsed AND (alterTyperoot=typeroot) THEN
          alterTyperoot := p
        END
      END;
      typeroot := p
    END NewTypeDesc;

    PROCEDURE SearchType(tnum: CARDINAL; VAR p: TypeDescPtr);
    BEGIN
      p := typeroot;
      LOOP
        IF p = NIL THEN EXIT END;
        IF p^.typenum = tnum THEN EXIT END;
        p := p^.nexttype
      END
    END SearchType;

    PROCEDURE RFTypeRef(VAR p: TypeDescPtr);
      VAR sym: RefSymbol; tnum: CARDINAL;
    BEGIN
      GetSym(sym);
      IF sym = typerefRS THEN
        GetNum(tnum);
        SearchType(tnum, p);
        IF p = NIL THEN (* forward reference *)
          NewTypeDesc(p);
          p^.typenum := tnum;
          p^.typekind := undefRS
        ELSIF p^.typekind = openRS THEN
          p := p^.eltype
        END
      ELSIF (sym >= undefRS) AND (sym <= processRS) THEN
        p := standardType[sym]
      ELSE Error
      END
    END RFTypeRef;

    PROCEDURE RFConstants(VAR p: ConstPtr; VAR n: CARDINAL);
      VAR sym: RefSymbol;
          q: ConstPtr;
    BEGIN
      GetSym(sym);
      n := 0;
      IF sym <> constRS THEN p := NIL; RETURN END;
      NEW(p); q := p;
      LOOP
        INC(n);
        WITH q^ DO
          GetNum(constnum);
          GetIdent(constname);
          GetSym(sym);
          IF sym <> constRS THEN
            IF sym <> endRS THEN Error END;
            nextconst := NIL; EXIT
          END;
          NEW(nextconst); q := nextconst
        END 
      END 
    END RFConstants;

    PROCEDURE RFFields(VAR p: FieldPtr; VAR n: CARDINAL);
      VAR sym: RefSymbol;
          q: FieldPtr;
    BEGIN
      GetSym(sym);
      n := 0;
      IF sym <> fieldRS THEN p := NIL; RETURN END;
      NEW(p); q := p;
      LOOP
        INC(n);
        WITH q^ DO
          GetNum(offset);
          GetIdent(fieldname);
          RFTypeRef(fieldtype);
          GetSym(sym);
          IF sym  <> fieldRS THEN
            IF sym <> endRS THEN Error END;
            nextfield := NIL; EXIT
          END; 
          NEW(nextfield); q := nextfield
        END 
      END 
    END RFFields;

    PROCEDURE RFType;
      VAR locptr: TypeDescPtr;
          tnum: CARDINAL;
    BEGIN
      GetNum(tnum);
      SearchType(tnum, locptr);
      IF locptr = NIL THEN (* no forward reference to this type *)
        NewTypeDesc(locptr)
      END;
      WITH locptr^ DO
        typenum := tnum;
        GetIdent(typename);
        GetSym(typekind);
        GetNum(typesize);
        CASE typekind OF
          setRS, pointerRS, arrdynRS, openRS:
            RFTypeRef(eltype) |
          subrRS:
            GetNum(min); GetNum(max);
            RFTypeRef(subrtype) |
          enumRS:
            RFConstants(firstconst, nrOfConsts) |
          arrayRS:
            RFTypeRef(indextype); RFTypeRef(arrEltype) |
          recordRS:
            RFFields(firstfield, nrOfFields) |
          hiddenRS:
        ELSE Error
        END 
      END 
    END RFType;

    PROCEDURE RFVar;
      VAR lno, addr: CARDINAL;
          addrmode: RefSymbol;
          p: DataChainPtr;
    BEGIN
      GetNum(lno); GetSym(addrmode); GetNum(addr);
      NEW(p);
      WITH p^ DO
        objecttype := varRS;
        CASE addrmode OF
          absRS: varAddr := addr |
          relRS: varAddr := baseaddress+addr |
          indRS: varAddr := Mem(baseaddress+addr)
        ELSE Error
        END;
        varValue := WORD(Mem(varAddr));
        GetIdent(objectname);
        RFTypeRef(varType);
        WITH varType^ DO
          IF typekind = arrdynRS THEN
            typesize := Mem(baseaddress + addr + 1)
          END
        END;
      END; 
      InsertDataEl(p)
    END RFVar;

    PROCEDURE RFModProc(name: Ident; objtype: RefSymbol);
      VAR p: DataChainPtr;
    BEGIN
      IF (objtype<>moduleRS) AND (objtype<>procRS) THEN
        IF debugMe THEN HALT ELSE (* bad debugger error *) objtype := procRS END;
      END;
      NEW(p);
      WITH p^ DO
        objecttype := objtype; objectname := name;
        father := NIL; datachain := NIL
      END;
      InsertDataEl(p);
    END RFModProc;

    VAR
      sym: RefSymbol; 
      objno: CARDINAL; 
      name: Ident; 
      newModule: BOOLEAN;

      lev: CARDINAL;        (*  current level *)
      foundlevel: CARDINAL; (*  0: NOT yet found or completely handled; 
                               >0: level where found *)
      skiplevels: CARDINAL; (* additional levels which are to skip *)

  BEGIN (* CreateDataTree *)
    lev := 0; skiplevels := 0; foundlevel := 0; 
    acttreeptr := NIL; actdataptr := NIL;
    error := FALSE; newModule := FALSE;
    GetSym(sym); IF sym <> reffileRS THEN Error; RETURN END;
    GetNum(objno); IF objno <> 40B THEN Error; RETURN END;
    GetSym(sym); IF sym <> moduleRS THEN Error; RETURN END;
    newModule := actModNum <> modulenumber;
    IF newModule THEN
      IF alterChainUsed AND (alterTyperoot=typeroot) THEN
        typeroot := NIL
      END;
      DeleteTypeChain(typeroot);
      actModNum := modulenumber;
    END;
    LOOP
      CASE sym OF

        moduleRS:
          INC(lev); GetRefHead(objno, name);
          IF skiplevels > 0 THEN INC(skiplevels)
          ELSIF objno = objectnumber THEN 
            foundlevel := lev; RFModProc(name, moduleRS)
          ELSIF foundlevel>0 THEN 
            RFModProc(name, moduleRS)
          END |

        procRS:
          INC(lev); GetRefHead(objno, name);
          IF skiplevels > 0 THEN INC(skiplevels)
          ELSIF objno = objectnumber THEN 
            foundlevel := lev; RFModProc(name, procRS)
          ELSIF foundlevel>0 THEN INC(skiplevels)
          END |

        endRS:
          DEC(lev); IF lev=0 THEN EXIT END;
          IF skiplevels>0 THEN DEC(skiplevels)
          ELSIF lev<foundlevel THEN foundlevel := 0 
          ELSIF foundlevel>0 THEN ExitStructure
          END |

        varRS: 
          IF (foundlevel>0) AND (skiplevels=0) THEN RFVar ELSE SkipVar END|

        typeRS: 
          IF newModule THEN RFType ELSE SkipType END;

        ELSE Error
      END; 
      IF error THEN EXIT END;
      GetSym(sym);
    END; 
    IF error THEN
      IF newModule THEN DeleteTypeChain(typeroot) END;
      DeleteDataChain(dataroot)
    END;
  END CreateDataTree;

 
BEGIN
  dataroot := NIL; typeroot := NIL; alterChainUsed := FALSE;
  alterTyperoot := NIL; actModNum := 177777B;
END MDDataHandler.
