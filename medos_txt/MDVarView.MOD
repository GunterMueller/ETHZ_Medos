IMPLEMENTATION MODULE MDVarView;  (* P. Karrer 7.7.82; error corrections Ch. j.*)
(*  (*$T-*) (*$R-*) *)
  FROM SYSTEM IMPORT WORD;
  FROM Program IMPORT CurrentLevel;
  IMPORT Terminal;
  FROM WindowHandler IMPORT Window, CloseWindow, SetPos,
    GetPos, OpenWindow, FreeLines, FreeChars, PutOnTop,
    CreateWindow, WindowSignal, SignalSet, FullScreen,
    DefaultWindow, ClearChars;
  FROM CursorStuff IMPORT TrackCursor, MenuSelection;
  FROM CursorRelations IMPORT
    Inside, DownCharPos, RightCharPos, UpDotPos, RightDotPos;
  FROM WindowDialogue IMPORT InstallWindow, RemoveWindow;
  FROM OutWindow IMPORT Write, WriteLn, WriteT, WriteS,
    WriteO, WriteI, WriteC;

  FROM DumpFileHandler IMPORT Mem;
  FROM Inspect IMPORT Show;
  FROM MDProcessView IMPORT ShowProcess;
  FROM MDDataHandler IMPORT
    RefSymbol, Ident, ConstPtr, FieldPtr, TypeDescPtr,
    UseTypeInfo, ReturnTypeInfo;
  FROM MDUtility IMPORT DisplayIdent, DisplayReal,
    ResetWindow, ResetLowWindow;


  CONST EOL = 36C;
        stklen = 50;

  VAR
    acttype: TypeDescPtr;
    actaddr: CARDINAL;
    acttop: CARDINAL;
    varwindow: Window;
    varDisplayed: BOOLEAN;
    varViewLevel: CARDINAL;
    gvarname: Ident;
    gvartype: TypeDescPtr;
    viewLow, viewHigh: CARDINAL;
    viewlength: CARDINAL;
    compsperline, compLength: CARDINAL; (*used for array components*)
    arrOfChar, textmode, valToDisplay: BOOLEAN;
    stkBottom, stkTop: CARDINAL;
    nrChars: CARDINAL;

    stk: ARRAY [0..stklen - 1] OF
           RECORD
             sAddr: CARDINAL;
             sType: TypeDescPtr;
             CASE RefSymbol OF
               recordRS:
                 selectedfield : FieldPtr |
               arrayRS:
                 selectedcomp: CARDINAL
             END
           END;

    menu: ARRAY [0..70] OF CHAR;
    menuCommand: ARRAY [0..6] OF CARDINAL;

    stL: ARRAY [integerRS..pointerRS] OF CARDINAL;
      (* standard length *)
 

  PROCEDURE Letter(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch>="A") AND (ch<="Z") OR (ch>="a") AND (ch<="z")
  END Letter;

  PROCEDURE Printable(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch > 37C) AND (ch < 177C)
  END Printable;

  PROCEDURE ConstP(p: TypeDescPtr; n: CARDINAL): ConstPtr;
    VAR q: ConstPtr;
  BEGIN
    q := p^.firstconst;
    LOOP
      IF q = NIL THEN EXIT END;
      IF q^.constnum = n THEN EXIT END;
      q := q^.nextconst
    END;
    RETURN q
  END ConstP;

  PROCEDURE FieldP(p: TypeDescPtr; n: CARDINAL): FieldPtr;
    VAR q: FieldPtr; i: CARDINAL;
  BEGIN
    i := 0;
    q := p^.firstfield;
    LOOP
      IF q = NIL THEN EXIT END;
      IF i = n THEN EXIT END;
      INC(i);
      q := q^.nextfield
    END;
    RETURN q
  END FieldP;

  PROCEDURE Space(n: CARDINAL; w: Window);
  BEGIN
    FOR n := 1 TO n DO Write(w, " ") END
  END Space;

  PROCEDURE DisplayType(p: TypeDescPtr; len: CARDINAL; w: Window);
    VAR i: CARDINAL;
  BEGIN 
    IF len = 0 THEN Write(w, " ") END;
    WITH p^ DO
      CASE typekind OF
        subrRS:
          i := ValLength(min, 0, subrtype) + ValLength(max, 0, subrtype) + 4;
          Write(w, "[");
          DisplayValue(min, 0, subrtype, 1, w);
          WriteS(w, "..");
          DisplayValue(max, 0, subrtype, 1, w);
          Write(w, "]");
          IF len > i THEN Space(len - i, w) END |
        enumRS:
          Write(w, "("); i := 5;
          IF firstconst <> NIL THEN
            i := IdLength(firstconst^.constname) + i;
            WriteS(w, firstconst^.constname)
          END;
          WriteS(w, ",..)");
          IF len > i THEN Space(len - i, w) END |
        arrayRS:   WriteT(w, "ARRAY", len) |
        pointerRS: WriteT(w, "POINTER", len) |
        setRS:     WriteT(w, "SET", len) |
        arrdynRS:  WriteT(w, "dyn ARRAY", len) |
        recordRS:  WriteT(w, "RECORD", len) |
        hiddenRS:  WriteT(w, "hidden", len) |
        openRS:    WriteT(w, "open", len)
      ELSE (* standard type *) 
        WriteT(w, typename, len)
      END 
    END
  END DisplayType;

  PROCEDURE String(p: TypeDescPtr; sz: CARDINAL): BOOLEAN;
    (* p is an ARRAY OF CHAR with size <= sz *)
    VAR q: TypeDescPtr; s: CARDINAL;
  BEGIN
    WITH p^ DO
      IF typekind = arrayRS THEN
        s := typesize; q := arrEltype
      ELSIF typekind = arrdynRS THEN
        s := typesize DIV 2 + 1; q := eltype
      ELSE RETURN FALSE
      END;
    END;
    WITH q^ DO
      RETURN ((typekind = charRS) OR (typekind = subrRS) AND
              (subrtype^.typekind = charRS)) AND (s <= sz)
    END
  END String;

  PROCEDURE StrLength(addr, sz: CARDINAL): CARDINAL;
    VAR i, maxad, wor: CARDINAL;
  BEGIN
    IF sz = 0 THEN RETURN 0 END;
    IF (177777B-sz) < addr THEN maxad := 177777B
    ELSE maxad := addr + sz - 1
    END;
    i := 0;
    LOOP
      wor := Mem(addr);
      IF NOT Printable(CHAR(wor DIV 400B)) THEN EXIT END;
      INC(i);
      IF NOT Printable(CHAR(wor MOD 400B)) THEN EXIT END;
      INC(i); 
      IF addr = maxad THEN EXIT END;
      INC(addr);
    END;
    RETURN i
  END StrLength;

  PROCEDURE DisplayStr(addr, sz: CARDINAL; ret: BOOLEAN; w: Window);
    VAR wor, maxad: CARDINAL; ch: CHAR;
  BEGIN
    IF sz = 0 THEN RETURN END;
    IF (177777B-sz) < addr THEN maxad := 177777B
    ELSE maxad := addr + sz - 1
    END;
    LOOP
      wor := Mem(addr);
      ch := CHAR(wor DIV 400B);
      IF Printable(ch) THEN
        Write(w, ch);
      ELSIF ret THEN EXIT
      ELSE Write(w, ".")
      END;
      ch := CHAR (wor MOD 400B);
      IF Printable(ch) THEN
        Write(w, ch);
      ELSIF ret THEN EXIT
      ELSE Write(w, ".")
      END;
      IF addr = maxad THEN EXIT END;
      INC(addr)
    END (* LOOP *)
  END DisplayStr;                                  

  PROCEDURE DisplayTypeIdOrType(p: TypeDescPtr; len: CARDINAL; w: Window);
  BEGIN
    WITH p^ DO
      IF Letter(typename[0]) THEN
        WriteT(w, typename, len)
      ELSE DisplayType(p, len, w)
      END
    END
  END DisplayTypeIdOrType;

  PROCEDURE DisplayValue(value: WORD; addr: CARDINAL;
                         type: TypeDescPtr; len: CARDINAL; w: Window);
    (* display value according to type rightbounded in a field of
       (at least) len Characters *)
    VAR
      realrec:
        RECORD
          CASE CARDINAL OF
            0: l, h: CARDINAL |
            1: r: REAL
          END
        END;

      q: ConstPtr;
      i, c: CARDINAL;

      PROCEDURE DisplayRText(text: Ident);
        VAR i: CARDINAL;
      BEGIN i := IdLength(text);
        IF i < len THEN
          Space(len - i, w);
        END;
        WriteT(w, text, i)
      END DisplayRText;

  BEGIN 
    WITH type^ DO
      CASE typekind OF
        bitsetRS..processRS, setRS, hiddenRS:   WriteO(w, value, len) |
        pointerRS:
          IF CARDINAL(value) = 177777B THEN DisplayRText("NIL")
          ELSE WriteO(w, value, len) END |
        integerRS:  WriteI(w, INTEGER(value), len) |
        cardinalRS: WriteC(w, CARDINAL(value), len) |
        charRS:
          c := ValLength(value, 0, type);
          IF len > c THEN Space(len-c, w) END;
          c := CARDINAL(value);
          IF c >= 400B THEN
            DisplayRText("<undef>")
          ELSE
            c := c MOD 400B;
            IF (c < 40B) OR (c >176B) THEN
              IF c >=100B THEN
                Write(w, CHAR(c DIV 100B + ORD("0")));
              END;
              IF c >= 10B THEN
                Write(w, CHAR(c MOD 100B DIV 10B + ORD("0")))
              END;
              Write(w, CHAR(c MOD 10B + ORD("0")));
              Write(w, "C");
            ELSE
              Write(w, '"'); Write(w, CHAR(c)); Write(w, '"')
            END
          END |
        booleanRS:
          IF CARDINAL(value) = ORD(TRUE) THEN DisplayRText("TRUE")
            ELSIF CARDINAL(value) = ORD(FALSE) THEN DisplayRText("FALSE")
            ELSE DisplayRText("<undef>")
          END |
        subrRS:  DisplayValue(value, addr, subrtype, len, w) |
        enumRS:
          q := ConstP(type, CARDINAL(value));
          IF q <> NIL THEN DisplayRText(q^.constname);
            ELSE DisplayRText("<undef>")
          END |
        realRS:
          IF len < 12 THEN len := 12 END;
          realrec.l := Mem(addr);
          realrec.h := Mem(addr+1);
          DisplayReal(realrec.r, len, w) |
        arrayRS, arrdynRS:
          IF String(type, 8) THEN
            IF typekind = arrayRS THEN c := typesize
            ELSE c := typesize DIV 2 + 1
            END;
            i := StrLength(addr, c) + 2;
            IF len > i THEN Space(len - i, w) END;
            Write(w, '"');
            DisplayStr(addr, c, TRUE, w);
            Write(w, '"')
          END
      ELSE (* do nothing for structured vars *)
      END 
    END 
  END DisplayValue;

  PROCEDURE DisplayStandard(val: WORD; addr: CARDINAL;
              type: TypeDescPtr; w: Window);
  BEGIN
    WITH type^ DO
      IF (typekind >= integerRS) AND (typekind <= pointerRS) THEN
        IF typekind = subrRS THEN
          DisplayStandard(val, addr, subrtype, w)
        ELSE DisplayValue(val, addr, type, stL[typekind], w)
        END
      ELSIF String(type, 8) THEN
        IF typekind = arrayRS THEN
          DisplayValue(val, addr, type, 2 * typesize + 3, w)
        ELSE (* arrdynRS *)
          DisplayValue(val, addr, type, typesize + 4, w)
        END
      ELSIF typekind = hiddenRS THEN WriteO(w, val, 7)
      END
    END
  END DisplayStandard;

  PROCEDURE StandardLength(type: TypeDescPtr): CARDINAL;
  BEGIN
    WITH type^ DO
      IF (typekind>= integerRS) AND (typekind <= pointerRS) THEN
        IF typekind = subrRS THEN RETURN StandardLength(subrtype)
          ELSE RETURN stL[typekind]
        END
      ELSIF String(type, 8) THEN
        IF typekind = arrayRS THEN RETURN 2*typesize+3
          ELSE RETURN typesize+4
        END
      ELSIF typekind = hiddenRS THEN RETURN 7
      ELSE RETURN 0
      END
    END
  END StandardLength;

  PROCEDURE IdLength(a: Ident): CARDINAL;
    VAR i: CARDINAL;
  BEGIN
    i := 0;
    WHILE (i <= 15) AND (a[i] <> 0C) DO INC(i) END;
    RETURN i
  END IdLength;

  PROCEDURE CardLength(x: WORD): CARDINAL;
    VAR i, y: CARDINAL;
  BEGIN
    i := 1;
    y := CARDINAL(x);
    WHILE y > 9 DO
      y := y DIV 10; INC(i)
    END;
    RETURN i
  END CardLength;

  PROCEDURE ValLength(val: WORD; addr: CARDINAL; type: TypeDescPtr): CARDINAL;
    (* number of chars used for DisplayValue(.., 1, w) *)
    VAR p: ConstPtr;
  BEGIN
    WITH type^ DO
      CASE typekind OF
        cardinalRS:  RETURN CardLength(val) |
        integerRS:
          IF INTEGER(val) < 0 THEN RETURN CardLength(177777B-CARDINAL(val)+1) + 1
            ELSE RETURN CardLength(val)
          END |
        charRS:
          IF CARDINAL(val) > 377B THEN RETURN 7 (* "<undef>" *)
            ELSIF CARDINAL(val) > 176B THEN RETURN 4
            ELSIF CARDINAL(val) > 7B THEN RETURN 3
            ELSE  RETURN 2
          END |
        booleanRS:
          IF CARDINAL(val) = ORD(TRUE) THEN RETURN 4
            ELSIF CARDINAL(val) = ORD(FALSE) THEN RETURN 5
            ELSE RETURN 7 (* "<undef>" *)
          END |
        enumRS:
          p := ConstP(type, CARDINAL(val));
          IF p <> NIL THEN RETURN IdLength(p^.constname)
            ELSE RETURN 7 (* "<undef>" *)
          END |
        subrRS:
          RETURN ValLength(val, 0, subrtype) |
        arrayRS:
          IF String(type, 8) THEN RETURN StrLength(addr, typesize) + 2
            ELSE RETURN 0
          END |
        arrdynRS:
          IF String(type, 8) THEN
            RETURN StrLength(addr, typesize DIV 2 + 1) + 2
          ELSE RETURN 0
          END
      ELSE RETURN 0
      END 
    END 
  END ValLength;

  PROCEDURE DisplayVar(name: Ident; addr: CARDINAL; value: WORD;
                       type: TypeDescPtr; w: Window);
    VAR idL, fc, vL, ln, pos, i: CARDINAL;
  BEGIN
    fc := FreeChars(w);
    IF fc > 61 THEN fc := 61 END;
    vL := ValLength(value, addr, type);
    IF fc > 30 THEN (* display address *)
      i := vL + 11
    ELSE i := vL + 4
    END;
    IF fc > (i + 16) THEN idL := (fc - i) DIV 2
    ELSE idL := 8;
    END;
    IF idL > 16 THEN idL := 16 END;
    i := 2 * idL + 4;
    IF fc > 30 THEN i := i + 7 END;
    IF fc < (i + 7) THEN vL := 7
    ELSE vL := fc - i
    END;
    WriteS(w, "  ");
    DisplayIdent(name, idL, w); Write(w, " ");
    DisplayValue(value, addr, type, vL, w);
    CASE type^.typekind OF
      arrayRS, arrdynRS, recordRS:
        IF NOT String(type, 8) THEN
          IF vL > 7 THEN Space(vL-7, w) END;
          WriteS(w, " *");
          WriteC(w, type^.typesize, 5)
        END;
      ELSE
    END;
    Write(w, " ");
    DisplayTypeIdOrType(type, idL, w);
    IF fc > 30 THEN
      i := fc - 7;
      GetPos(w, ln, pos); SetPos(w, ln, i);
      IF pos > i THEN ClearChars(w, pos - i) END;
      WriteO(w, addr, 7)
    END
  END DisplayVar;

  PROCEDURE SimpleType(p: TypeDescPtr): BOOLEAN;
  BEGIN
    WITH p^ DO
      RETURN (typekind >= undefRS) AND (typekind <= processRS)
    END
  END SimpleType;


  PROCEDURE DisplayTypeLine;
  BEGIN
    WriteS(varwindow, "  TYPE: ");
    WITH acttype^ DO
      IF NOT SimpleType(acttype) AND Letter(typename[0]) THEN
        WriteS(varwindow, typename);
        WriteS(varwindow, " = ");
      END;
      CASE typekind OF
        arrayRS:
          WriteS(varwindow, "ARRAY ");
          DisplayTypeIdOrType(indextype, 1, varwindow);
          WriteS(varwindow, " OF ");
          DisplayTypeIdOrType(arrEltype, 1, varwindow) |
        recordRS:
          WriteS(varwindow, "RECORD Size ");
          WriteC(varwindow, typesize, 1) |
        arrdynRS:
          WriteS(varwindow, "dyn ARRAY [0..");
          WriteC(varwindow, typesize, 1);
          WriteS(varwindow, "] OF ");
          DisplayTypeIdOrType(eltype, 1, varwindow) |
        setRS:
          WriteS(varwindow, "SET OF ");
          DisplayTypeIdOrType(eltype, 1, varwindow) |
        pointerRS:
          WriteS(varwindow, "POINTER TO ");
          DisplayTypeIdOrType(eltype, 1, varwindow) |
        subrRS:
          DisplayType(acttype, 1, varwindow);
          WriteS(varwindow, " subr of ");
          DisplayTypeIdOrType(subrtype, 1, varwindow) |
        enumRS:
          WriteS(varwindow, " enumeration with ");
          WriteC(varwindow, nrOfConsts, 1);
          WriteS(varwindow, " elements") 
      ELSE
        DisplayType(acttype, 1, varwindow)
      END 
    END 
  END DisplayTypeLine;

  PROCEDURE DisplayHeader;
    VAR s, i, k, nrc, ln, pos: CARDINAL; p: TypeDescPtr;
  BEGIN
    i := 0; s := stkTop;
    IF nrChars > 30 THEN (* display address *)
      nrc := nrChars - 9
    ELSE nrc := nrChars - 2
    END;
    LOOP
      IF s = stkBottom THEN p := NIL; EXIT END;
      DEC(s);
      WITH stk[s MOD stklen] DO
        WITH sType^ DO
          CASE typekind OF
            recordRS:
              WITH selectedfield^ DO
                k := IdLength(fieldname) + 1;
                p := fieldtype;
              END |
            arrayRS:
              k := ValLength(selectedcomp, 0, indextype) + 2;
              p := arrEltype |
            arrdynRS:
              k := CardLength(selectedcomp) + 2;
              p := eltype |
            pointerRS:
              k := 1; p := eltype
          ELSE k := 0; p := sType
          END
        END (* WITH sType^ *)
      END; (* WITH stk[s] *)
      IF p^.typekind = pointerRS THEN INC(i) END;
      IF (i + k) >= nrc THEN INC(s); EXIT
      ELSE i := i + k
      END
    END; (* LOOP *)
    WriteS(varwindow, "  ");
    IF s = 0 THEN
      p := gvartype;
      k := IdLength(gvarname);
      IF p^.typekind = pointerRS THEN INC(i) END;
      IF (i + k) <= nrc THEN
        WriteS(varwindow, gvarname); i := i + k - 1
      ELSE Write(varwindow, "*")
      END
    ELSE Write(varwindow, "*")
    END;
    IF (p <> NIL) THEN
      IF (i < nrc) THEN
        IF p^.typekind = pointerRS THEN
          Write(varwindow, "^")
        END
      ELSE DEC(i)
      END
    END; (* i = length - 1 *)
    WHILE s < stkTop DO
      WITH stk[s MOD stklen] DO
        WITH sType^ DO
          CASE typekind OF
            recordRS:
              Write(varwindow,".");
              WITH selectedfield^ DO
                WriteS(varwindow, fieldname);
                p := fieldtype
              END |
            arrayRS:
              Write(varwindow, "[");
              DisplayValue(selectedcomp, 0, indextype, 1, varwindow);
              Write(varwindow, "]");
              p := arrEltype |
            arrdynRS:
             Write(varwindow, "[");
              WriteC(varwindow, selectedcomp, 1);
              Write(varwindow, "]");
              p := eltype |
            pointerRS:
              Write(varwindow, "^"); p := eltype
          ELSE p := sType
          END;
        END
      END;
      IF p^.typekind = pointerRS THEN
        Write(varwindow, "^")
      END;
      INC(s)
    END; (* WHILE *)
    IF nrChars > 30 THEN WriteO(varwindow, actaddr, 6 + nrc - i) END
  END DisplayHeader;

  PROCEDURE SelectableType(type: TypeDescPtr): BOOLEAN;
  BEGIN
    WITH type^ DO
      RETURN (typekind >= setRS) OR (typekind = bitsetRS)
              OR (typekind = addressRS) OR (typekind = processRS)
    END
  END SelectableType;

  PROCEDURE SetViewGlobals(type: TypeDescPtr);
    VAR i: CARDINAL;

    PROCEDURE SetElGlobals(type: TypeDescPtr);
    BEGIN
      WITH type^ DO
        CASE typekind OF
          enumRS:    viewLow := 0; viewHigh := nrOfConsts - 1 |
          subrRS:    viewLow := min; viewHigh := max |
          booleanRS: viewLow := 0; viewHigh := 1 |
          charRS:    viewLow := 0; viewHigh := 377B
          ELSE
        END
      END
    END SetElGlobals;

    PROCEDURE SetArrayGlobals;
    BEGIN
      IF viewLow <= viewHigh THEN  viewlength := viewHigh - viewLow
      ELSE (* low index < 0 *)
        viewlength := viewHigh + (177777B-viewLow+1);
      END;
      IF nrLines > 1 THEN
        IF arrOfChar AND textmode THEN
          compsperline := (nrChars - 2) DIV 2 * 2;
          compLength := 1
        ELSE
          i := viewlength  DIV (nrLines - 1) + 1;
          compsperline := nrChars DIV compLength;
          IF compsperline > i THEN compsperline := i END;
        END;
        IF compsperline = 0 THEN compsperline := 1 END;
        viewlength := viewlength DIV compsperline
      END
    END SetArrayGlobals;

    PROCEDURE ConstructMenu;
      VAR m, n: CARDINAL; b: BOOLEAN;

      PROCEDURE EnterCommand(a: ARRAY OF CHAR; c: CARDINAL);
        VAR i: CARDINAL;
      BEGIN
        FOR i := 0 TO HIGH(a) DO
          menu[n] := a[i]; INC(n)
        END;
        menuCommand[m] := c; INC(m)
      END EnterCommand;

    BEGIN (* ConstructMenu *)
      m := 1; n := 0; menuCommand[0] := 0;
      EnterCommand(" VAR|", 0);
      EnterCommand(" select|", 6);
      IF stkTop > stkBottom THEN EnterCommand(" father|", 1) END;
      IF arrOfChar THEN
        IF textmode THEN EnterCommand(" normal|", 2)
        ELSE EnterCommand(" text|", 2)
        END
      END;
      b := FALSE;
      WITH acttype^ DO
        IF typekind = arrayRS THEN
          b := SelectableType(arrEltype);
          IF b THEN
            WITH indextype^ DO
              IF typekind = subrRS THEN
                WITH subrtype^ DO
                  b := (typekind = cardinalRS) OR (typekind = integerRS)
                END
              END
            END
          END
        ELSIF typekind = arrdynRS THEN
          b := SelectableType(eltype)
        END;
        IF b THEN EnterCommand(" index|", 3) END
      END;
      EnterCommand(" memory|", 4);
      EnterCommand(" remove", 5);
      menu[n] := 0C
    END ConstructMenu;

  BEGIN (* SetViewGlobals *)
    WITH type^ DO
      CASE typekind OF
        arrayRS:
          SetElGlobals(indextype);
          i := StandardLength(arrEltype);
          valToDisplay := i <> 0;
          compLength := StandardLength(indextype)+ i + 2;
          SetArrayGlobals |
        arrdynRS:
          viewLow := 0; viewHigh := typesize;
          compLength := StandardLength(eltype) + 8;
          valToDisplay := compLength <> 8;
          SetArrayGlobals |
        setRS:
          SetElGlobals(eltype); viewlength := 0 |
        recordRS:
          viewLow := 0;
          IF nrOfFields > 0 THEN
            viewHigh := nrOfFields - 1; viewlength := viewHigh
          ELSE viewHigh := 0; viewlength := 0
          END |
        bitsetRS:
          viewLow := 0; viewHigh := 15; viewlength := 0;
      ELSE viewLow := 0; viewHigh := 0; viewlength := 0;
      END 
    END; 
    ConstructMenu
  END SetViewGlobals;

  PROCEDURE Check(addr: CARDINAL; type: TypeDescPtr;
                  VAR ok: BOOLEAN);
    VAR sz: CARDINAL;
  BEGIN
    WITH type^ DO
      IF typekind = arrdynRS THEN
        sz := typesize; (* HIGH *)
        IF String(type, 177777B) THEN sz := sz DIV 2 END;
        sz := (sz + 1)* eltype^.typesize
      ELSE sz := typesize
      END;
    END;
    ok := (177777B - addr) >= sz;
    IF NOT ok THEN
      Terminal.WriteString("-- bad address");
      Terminal.WriteLn
    END
  END Check;

  PROCEDURE Selectable(type: TypeDescPtr; addr: CARDINAL): BOOLEAN;
    VAR ok: BOOLEAN; ad: CARDINAL;
  BEGIN
    WITH type^ DO
      IF typekind = pointerRS THEN
        ad := Mem(addr);
        IF ad = CARDINAL(NIL) THEN RETURN FALSE END;
        Check(ad, eltype, ok); RETURN ok
      ELSE RETURN (typekind >= setRS) OR (typekind = bitsetRS)
      END
    END
  END Selectable;

  PROCEDURE ShowVar(name: Ident; type: TypeDescPtr; addr: CARDINAL);
    VAR ok: BOOLEAN;
  BEGIN
    WITH type^ DO
      IF typekind = addressRS THEN
        Show(Mem(addr)); RETURN
      ELSIF typekind = processRS THEN
        ShowProcess(Mem(addr)); RETURN
      END
    END;
    IF NOT Selectable(type, addr) THEN RETURN END;
    Check(addr, type, ok);
    IF NOT ok THEN RETURN END;
    IF varViewLevel = 177777B THEN InitVarView END;
    IF varViewLevel = 177777B THEN RETURN END;
    UseTypeInfo;
    gvarname := name; gvartype := type;
    acttype := type; actaddr := addr;
    stkBottom := 0; stkTop := 0;
    varDisplayed := TRUE;
    ShowSelectedVar;
  END ShowVar;

  PROCEDURE ShowActVar;
  BEGIN
    ResetWindow(varwindow);
    DisplayHeader; WriteLn(varwindow);
    DisplayTypeLine; WriteLn(varwindow);
    ShowVarData;
  END ShowActVar;

  PROCEDURE ShowSelectedVar;
    VAR ad: CARDINAL;
  BEGIN
    WITH acttype^ DO
      IF typekind = pointerRS THEN
        ad := Mem(actaddr);
        IF ad <> CARDINAL(NIL) THEN
          actaddr := ad; acttype := acttype^.eltype
        END
      END
    END;
    ShowNewVar
  END ShowSelectedVar;

  PROCEDURE ShowNewVar;
    VAR ad: CARDINAL;
  BEGIN
    arrOfChar := String(acttype, 177777B);
    textmode := FALSE;
    SetViewGlobals(acttype);
    acttop := 0;
    ShowActVar
  END ShowNewVar;

  PROCEDURE ShowRecord;
    VAR q: FieldPtr; i: CARDINAL;
  BEGIN
    q := acttype^.firstfield;
    i := 0;
    LOOP
      IF q = NIL THEN EXIT END;
      WITH q^ DO
        IF i >= acttop THEN
          DisplayVar(fieldname, actaddr+offset, Mem(actaddr+offset),
                     fieldtype, varwindow);
          IF FreeLines(varwindow) = 0 THEN EXIT END;
          WriteLn(varwindow);
        END;
        q := nextfield;
        INC(i)
      END;
    END (* LOOP *)
  END ShowRecord;

  PROCEDURE ShowArray;
    VAR addr, sz, i, c, inx: CARDINAL;
        arrdyn, highbyte: BOOLEAN;
        elType: TypeDescPtr;
  BEGIN
    WITH acttype^ DO
      arrdyn := typekind = arrdynRS;
      IF arrdyn THEN elType := eltype
      ELSE elType := arrEltype
      END;
      sz := elType^.typesize;
      i := acttop * compsperline;
      IF (177777B - i) >= viewLow THEN
        inx := viewLow + i
      ELSE inx := viewLow -  (177777B - i) - 1
      END;      
      IF arrOfChar THEN
        highbyte := ODD(i);
        i := i DIV 2
      ELSE highbyte := FALSE
      END;
      addr := actaddr + i * sz;
      i := 1;
      WriteS(varwindow, "  ");
      LOOP
        IF NOT textmode THEN
          IF arrdyn THEN WriteC(varwindow, CARDINAL(inx), 6)
          ELSE DisplayStandard(inx, 0, indextype, varwindow)
          END
        END;
        IF arrOfChar THEN
          IF highbyte THEN c := Mem(addr) MOD 400B
          ELSE c := Mem(addr) DIV 400B
          END;
          IF textmode THEN
            IF Printable(CHAR(c)) THEN
              Write(varwindow, CHAR(c))
            ELSE Write(varwindow, ".")
            END
          ELSE DisplayStandard(c, 0, elType, varwindow)
          END;
          highbyte := NOT highbyte
        ELSIF valToDisplay THEN
          DisplayStandard(Mem(addr), addr, arrEltype, varwindow);
        END;
        IF i >= compsperline THEN
          IF FreeLines(varwindow) = 0 THEN EXIT END;
          WriteLn(varwindow); i := 1;
          WriteS(varwindow, "  ")
        ELSE
          IF NOT textmode THEN WriteS(varwindow, "  ") END;
          INC(i);
        END;
        IF(inx = viewHigh) THEN EXIT END;
        IF inx = 177777B THEN inx := 0 ELSE INC(inx) END;
        IF NOT highbyte THEN addr := addr + sz END;
      END
    END
  END ShowArray;

  PROCEDURE ShowSet(setElType: TypeDescPtr);
    VAR i, j, k: CARDINAL;
      setofcard, empty: BOOLEAN;
      val: BITSET;
  BEGIN
    val := BITSET(Mem(actaddr));
    WITH setElType^ DO
      setofcard := (setElType = NIL) OR (typekind = subrRS)
                   AND (subrtype^.typekind = cardinalRS);
    END;
    empty := TRUE; i := viewLow;
    WriteS(varwindow, "  {");
    LOOP
      IF i IN val THEN
        IF empty THEN empty := FALSE
        ELSE
          Write(varwindow, ",");
          IF setofcard THEN k := CardLength(i)
          ELSE k := ValLength(i, 0, setElType)
          END;
          IF FreeChars(varwindow) <= k THEN
            IF FreeLines(varwindow) = 0 THEN RETURN END;
            WriteLn(varwindow); WriteS(varwindow, "  ");
          END
        END;
        IF setofcard THEN WriteC(varwindow, i, 1)
        ELSE DisplayValue(i, 0, setElType, 1, varwindow)
        END;
      END;
      IF i = viewHigh THEN EXIT END;
      INC(i)
    END; 
    Write(varwindow, "}")
  END ShowSet;
      
  PROCEDURE ShowVarData;
  BEGIN
    CASE acttype^.typekind OF
      recordRS: ShowRecord  |
      arrayRS, arrdynRS: ShowArray |
      setRS: ShowSet(acttype^.eltype) |
      bitsetRS: ShowSet(NIL)
    ELSE
      WriteS(varwindow, "  value: ");
      DisplayStandard(Mem(actaddr), actaddr, acttype, varwindow);
    END
  END ShowVarData;

  VAR
    disp: Window;
    winx, winy, winw, winh: CARDINAL;
    nrLines: CARDINAL;

  PROCEDURE SetGlobals;
  BEGIN
    ResetWindow(varwindow);
    nrChars := FreeChars(varwindow);
    IF nrChars < 2 THEN nrChars := 2 END;
    nrLines := FreeLines(varwindow)
  END SetGlobals;


  PROCEDURE InitVarView;
    VAR ok: BOOLEAN;
  BEGIN
    IF varViewLevel <> 177777B THEN PutOnTop(varwindow)
    ELSE
      CreateWindow(varwindow, winx, winy, winw, winh,
                   "   variable", FALSE,
                   VarViewControl, ok);
      IF ok THEN
        InstallWindow(varwindow, {1..5}, VarHandler,
                      SignalSet{moved, changed, fontchanged}, ok);
        IF NOT ok THEN CloseWindow(varwindow)
        ELSE varViewLevel := CurrentLevel()
        END
      END
    END
  END InitVarView;

  PROCEDURE VarViewResetLevel;
  BEGIN
    IF varViewLevel >= CurrentLevel() THEN
      varViewLevel := 177777B
    END
  END VarViewResetLevel;

  PROCEDURE Push(type: TypeDescPtr; addr: CARDINAL;
                 selected: WORD);
  BEGIN
    WITH stk[stkTop MOD stklen] DO
      sType := type; sAddr := addr;
      selectedcomp := CARDINAL(selected);
    END;
    INC(stkTop);
    IF stkTop >= stklen THEN
      IF stkTop > stklen THEN INC(stkBottom)
      ELSE Terminal.WriteString("stack full"); Terminal.WriteLn
      END
    END
  END Push;

  PROCEDURE Pull(VAR type: TypeDescPtr; VAR addr: CARDINAL);
  BEGIN
    IF stkTop > stkBottom THEN
      DEC(stkTop);
      WITH stk[stkTop MOD stklen] DO
        type := sType; addr := sAddr
      END
    END
  END Pull;

  PROCEDURE Selection(newtype: TypeDescPtr; newaddr: CARDINAL;
                      selected: WORD);
  BEGIN
    WITH newtype^ DO
      IF typekind = addressRS THEN Show(Mem(newaddr))
      ELSIF typekind = processRS THEN ShowProcess(Mem(newaddr))
      ELSIF Selectable(newtype, newaddr)
            OR (acttype^.typekind = pointerRS) THEN
        Push(acttype, actaddr, selected);
        acttype := newtype;
        actaddr := newaddr;
        ShowSelectedVar;
      END
    END
  END Selection;

  PROCEDURE Select;
    VAR offset: CARDINAL; q: FieldPtr;
        newaddr, sel: CARDINAL;
        newtype: TypeDescPtr;
        ok: BOOLEAN;

    PROCEDURE SelectIndex(elType: TypeDescPtr);
      VAR i, j, k, sz: CARDINAL;
    BEGIN
      IF NOT SelectableType(elType) THEN
        newtype := NIL; RETURN
      END;
      i := RightCharPos(varwindow);
      IF i > 2 THEN i := (i - 2) DIV compLength ELSE i := 0 END;
      IF i >= compsperline THEN i := compsperline - 1 END;
      IF viewLow > viewHigh THEN
        k := viewHigh + (177777B - viewLow + 1)
      ELSE k := viewHigh - viewLow
      END;
      j := offset * compsperline;
      IF (177777B - j) > i THEN i := i + j
      ELSE i := 177777B
      END; 
      IF i > k  THEN i := k END;
      IF (177777B - i) >= viewLow THEN sel := viewLow + i
      ELSE sel := viewLow - (177777B - i + 1)
      END;
      newaddr := actaddr + i * elType^.typesize;
      newtype := elType
    END SelectIndex;

  BEGIN (* Select *)
    IF NOT Inside(varwindow) THEN RETURN END;
    offset := DownCharPos(varwindow);
    IF offset >= 2 THEN
      offset := offset - 2;
      IF (177777B - offset) < acttop THEN
        offset := 177777B
      ELSE offset := acttop + offset
      END;
      IF offset > viewlength THEN offset := viewlength END;
      WITH acttype^ DO
        CASE typekind OF
          arrayRS:  SelectIndex(arrEltype) |
          arrdynRS: SelectIndex(eltype) |
          recordRS:
            q := FieldP(acttype, offset);
            sel := CARDINAL(q);
            IF q <> NIL THEN
              newaddr := actaddr + q^.offset;
              newtype := q^.fieldtype
            ELSE newtype := NIL
            END |
          pointerRS:
            newaddr := Mem(actaddr);
            newtype := eltype;
            Check(newaddr, newtype, ok);
            IF NOT ok THEN newtype := NIL END 
          ELSE newtype := NIL;
        END; 
      END;
      IF newtype <> NIL THEN Selection(newtype, newaddr, sel) END
    ELSE (* DownCharPos < 2 *)
    END
  END Select;

  PROCEDURE SelectFather;
  BEGIN
    IF stkTop > stkBottom THEN
      Pull(acttype, actaddr);
      ShowNewVar
    END
  END SelectFather;

  PROCEDURE TypeIndex;
    VAR ch: CHAR; c, offs: CARDINAL; neg, inRange: BOOLEAN;
        i: INTEGER; newtype: TypeDescPtr; newaddr: CARDINAL;

    PROCEDURE ReadNum(VAR card: CARDINAL; VAR neg: BOOLEAN);
    BEGIN
      card := 0; Terminal.Read(ch); neg := ch = "-";
      IF neg THEN Terminal.Write(ch); Terminal.Read(ch) END;
      WHILE (card < 6553) AND (ch >= "0") AND (ch <= "9") DO
        card := 10 * card + (ORD(ch) - ORD("0"));
        Terminal.Write(ch); Terminal.Read(ch)
      END
    END ReadNum;      

  BEGIN
    Terminal.WriteString("enter index"); Terminal.WriteLn;
    ReadNum(c, neg); Terminal.WriteLn;
    IF neg AND (c <> 0) THEN c := 177777B - c + 1 END;
    i := INTEGER(c);
    IF INTEGER(viewLow) < 0 THEN
      inRange := (i >= INTEGER(viewLow)) AND (i <= INTEGER(viewHigh));
    ELSE
      inRange := (c >= viewLow) AND (c <= viewHigh);
    END;
    IF inRange THEN
      IF viewLow > viewHigh THEN
        offs := c + (177777B - viewLow + 1)
      ELSE offs := c - viewLow
      END;
      WITH acttype^ DO
        IF typekind = arrayRS THEN
          newaddr := actaddr + offs * arrEltype^.typesize;
          newtype := arrEltype
        ELSE (* arrdynRS *)
          newaddr := actaddr + offs * eltype^.typesize;
          newtype := eltype
        END
      END;
      Selection(newtype, newaddr, c)      
    ELSE
      Terminal.WriteString("-- index out of range"); Terminal.WriteLn
    END
  END TypeIndex;

  PROCEDURE VarViewControl(w: Window; s: WindowSignal);
  BEGIN
    IF s IN SignalSet{redraw, moved, changed,  fontchanged, opened} THEN
      SetGlobals;
      IF varDisplayed THEN
        IF s IN SignalSet{changed, fontchanged} THEN
          SetViewGlobals(acttype)
        END;
        ShowActVar
      END
    ELSIF s = closed THEN
      WITH w^.outerblk DO
        winx := x; winy := y; winh := h; winw := w
      END;
      varDisplayed := FALSE;
      ReturnTypeInfo;
      varViewLevel := 177777B
    END
  END VarViewControl;

  PROCEDURE ScrollUp;
    VAR offset: CARDINAL;
  BEGIN
    offset := DownCharPos(varwindow);
    IF offset >= 2 THEN
      offset := offset - 2;
      IF (177777B - offset) < acttop THEN acttop := 177777B
      ELSE acttop := acttop + offset
      END;
      IF acttop > viewlength THEN acttop := viewlength END;
      ShowActVar
    END
  END ScrollUp;

  PROCEDURE ScrollDown;
    VAR offset: INTEGER;
  BEGIN
    offset := INTEGER(nrLines)-INTEGER(DownCharPos(varwindow));
    IF offset > 0 THEN
      IF offset < INTEGER(acttop) THEN
        acttop := acttop - CARDINAL(offset)
      ELSE acttop := 0
      END;
      ShowActVar
    END
  END ScrollDown;

  PROCEDURE Flip;
    VAR offset: CARDINAL;
  BEGIN
    IF nrLines > 0 THEN
      offset := DownCharPos(varwindow);
      IF offset > nrLines THEN offset := nrLines END;
      acttop := offset * (viewlength DIV nrLines);
    END;
    ShowActVar
  END Flip;

  PROCEDURE VarHandler(w: Window; reason: CARDINAL);
    VAR i: CARDINAL; ch: CHAR;
  BEGIN
    IF NOT varDisplayed THEN 
      IF MenuSelection("no selection| remove")=2 THEN 
        RemoveWindow(varwindow); CloseWindow(varwindow)
      ELSE Terminal.BusyRead(ch)
      END;
      RETURN 
    END;
    IF reason IN {1..3} THEN
      IF NOT Inside(varwindow) THEN SelectFather
      ELSIF RightDotPos(varwindow) <= 16 THEN
        CASE reason OF
          1: ScrollUp |
          2: Flip |
          3: ScrollDown
        END;
      ELSE
        CASE reason OF
          1: Select |
          2, 3:
             CASE menuCommand[MenuSelection(menu)] OF
               1: SelectFather |
               2: textmode := NOT textmode;
                  SetViewGlobals(acttype);
                  acttop := 0; ShowActVar |
               3: TypeIndex |
               4: Show(actaddr) |
               5: RemoveWindow(varwindow); CloseWindow(varwindow) |
               6: Terminal.WriteString("select a component"); 
                  Terminal.WriteLn;
                  i := TrackCursor(); Select
             ELSE PutOnTop(varwindow)
             END
        END
      END
    ELSIF reason = 5 THEN CloseWindow(varwindow)
    END
  END VarHandler;

BEGIN (* MDVarView *)
  stkBottom := 0; stkTop := 0;
  disp := FullScreen();
  WITH disp^.outerblk DO
    winx := 5; winy := 4; winw := 430; winh := 147; 
    IF w <= 640 THEN winy := 329; winw := w-10;  winh := 163 END;
    IF winh>h THEN winh := h DIV 2 END
  END;
  stL[integerRS] := 7; stL[cardinalRS] := 6; stL[charRS] := 5;
  stL[booleanRS] := 8; stL[realRS] := 14; stL[bitsetRS] := 7;
  stL[proctypRS] := 7; stL[wordRS] := 7; stL[addressRS] := 7;
  stL[processRS] := 7; stL[enumRS] :=17; stL[setRS] := 7;
  stL[pointerRS] := 7;
  varDisplayed := FALSE; varViewLevel := 177777B;
  InitVarView;
END MDVarView.
