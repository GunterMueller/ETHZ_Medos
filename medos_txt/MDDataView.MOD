IMPLEMENTATION MODULE MDDataView;  (* redesigned P. Karrer 28.6.82 *)

(* (*$T-*) (*R-*) *)

  FROM SYSTEM IMPORT WORD;
  IMPORT Terminal;
  FROM WindowHandler IMPORT Window,
    GetPos, OpenWindow, FreeLines, PutOnTop,
    CreateWindow, WindowSignal, SignalSet, FullScreen;
  FROM CursorStuff IMPORT TrackCursor, MenuSelection;
  FROM CursorRelations IMPORT
    Inside, DownCharPos, RightCharPos, UpDotPos, RightDotPos;
  FROM WindowDialogue IMPORT 
    InstallWindow;

  FROM DumpFileHandler IMPORT Mem;
  FROM Inspect IMPORT Show;
  FROM OutWindow IMPORT WriteLn, WriteS;
  FROM MDDataHandler IMPORT
    RefSymbol, Ident, CreateProcData, CreateModData,
    DataChainPtr, ConstPtr, FieldPtr, TypeDescPtr;
  FROM MDUtility IMPORT
    ResetWindow, ResetLowWindow;
  FROM MDModuleHandler IMPORT modTab, modLoaded, ModIdent;
  FROM MDProcHandler IMPORT chain, chainmax;
  FROM MDVarView IMPORT ShowVar, DisplayVar;

  CONST
    EOL = 36C;

  VAR
    actptr: DataChainPtr;
    acttop: CARDINAL;
    datawindow: Window;
    nrLines: CARDINAL;
    insideHeight: CARDINAL;
    gloModName: ModIdent;
    datachainlength: CARDINAL;


  PROCEDURE  DisplayNodeAndChain;

    PROCEDURE DataChainLength(p: DataChainPtr): CARDINAL;
      VAR i: CARDINAL;
    BEGIN
      p := p^.datachain;
      i := 0;
      WHILE p <> NIL DO
        INC(i); p := p^.next
      END;
      RETURN i
    END DataChainLength;

  BEGIN (* DisplayNodeAndChain *)
    ResetWindow(datawindow);
    IF actptr = NIL THEN
      WriteS(datawindow, "   no reference file"); RETURN
    END;
    WITH actptr^ DO
      IF objecttype = moduleRS THEN
        WriteS(datawindow, "  MODULE   ");
        WriteS(datawindow, objectname);
        IF father <> NIL THEN
          WriteS(datawindow, "  local to  ");
          WriteS(datawindow, father^.objectname)
        END
      ELSE
        WriteS(datawindow, "  PROCEDURE  ");
        WriteS(datawindow, objectname);
        WriteS(datawindow, "  in  ");
        WriteS(datawindow, gloModName);
      END;
    END; 
    WriteLn(datawindow);
    datachainlength := DataChainLength(actptr);
    DisplayChain;
  END DisplayNodeAndChain;


  PROCEDURE DisplayChain;
    VAR i: CARDINAL; p: DataChainPtr;
  BEGIN
    p := actptr^.datachain;
    i := 0;
    IF p = NIL THEN
      WriteS(datawindow, "  no local data");
      RETURN
    END;
    LOOP
      IF i >= acttop THEN
        WITH p^ DO
          IF objecttype = moduleRS THEN
            WriteS(datawindow, "  ");
            WriteS(datawindow, objectname);
            WriteS(datawindow, " local module");
          ELSE 
            DisplayVar(objectname, varAddr, varValue, varType, datawindow)
          END
        END;
        IF FreeLines(datawindow) = 0 THEN EXIT END;
        WriteLn(datawindow);
      END;
      p:= p^.next;
      IF p = NIL THEN EXIT END;
      INC(i)
    END 
  END DisplayChain;


  PROCEDURE ShowProcData(n: CARDINAL);
  BEGIN
    IF n < chainmax THEN
      WITH chain^[n] DO
        IF knowncall THEN
          CreateProcData(n, actptr);
          gloModName := modTab[modNr]^.modName;
          acttop := 0;
          DisplayNodeAndChain;
        END
      END
    END;
  END ShowProcData;


  PROCEDURE ShowModData(m: CARDINAL);
  BEGIN
    IF m < modLoaded THEN
      CreateModData(m, actptr);
      acttop := 0;
      DisplayNodeAndChain;
    END;
  END ShowModData;

  PROCEDURE DataP(p: DataChainPtr; n: CARDINAL): DataChainPtr;
    VAR q: DataChainPtr; i: CARDINAL;
  BEGIN
    i := 0;
    IF p = NIL THEN RETURN NIL END;
    q := p^.datachain;
    LOOP
      IF q = NIL THEN EXIT END;
      INC(i);
      IF i >= n THEN EXIT END;
      q := q^.next
    END;
    RETURN q
  END DataP;

  PROCEDURE SelectAddr;
    VAR but: CARDINAL; p: DataChainPtr;
  BEGIN
    Terminal.WriteString("select variable"); Terminal.WriteLn;
    but := TrackCursor();
    IF Inside(datawindow) THEN
      p := DataP(actptr, acttop + DownCharPos(datawindow));
      IF p <> NIL THEN
        IF p^.objecttype = varRS THEN Show(p^.varAddr) END
      END
    END
  END SelectAddr;

  PROCEDURE SelectFather;
  BEGIN
    IF actptr^.father <> NIL THEN
      actptr := actptr^.father;
      acttop := 0;
      DisplayNodeAndChain
    END
  END SelectFather;

  PROCEDURE Selection;
    VAR p: DataChainPtr; offset: CARDINAL;
  BEGIN
    IF Inside(datawindow) THEN
      offset := DownCharPos(datawindow);
      IF offset > 0 THEN
        p := DataP(actptr, acttop + offset);
        IF p <> NIL THEN
          WITH p^ DO
            IF objecttype = varRS THEN
              ShowVar(objectname, varType, varAddr)
            ELSIF objecttype = moduleRS THEN
              actptr := p; acttop := 0;
              DisplayNodeAndChain
            END
          END
        END
      ELSE SelectFather
      END
    END
  END Selection;

  PROCEDURE Select;
    VAR but: CARDINAL;
  BEGIN
    Terminal.WriteString("select a data object"); Terminal.WriteLn;
    but := TrackCursor();
    Selection
  END Select;

  PROCEDURE DataHandler(w: Window; reason: CARDINAL);
    VAR p: DataChainPtr; n: CARDINAL;

    PROCEDURE ScrollUp;
      VAR offset: CARDINAL;
    BEGIN
      offset := DownCharPos(datawindow);
      IF offset > 1 THEN
        acttop := acttop + offset -1;
        IF acttop >= datachainlength THEN
          IF datachainlength > 0 THEN acttop := datachainlength - 1
          ELSE acttop := 0
          END
        END;
        DisplayNodeAndChain
      END
    END ScrollUp;

    PROCEDURE Flip;
      VAR offset: CARDINAL;
    BEGIN
      acttop := DownCharPos(datawindow) * (datachainlength DIV nrLines);
      IF acttop >= datachainlength THEN
        IF datachainlength > 0 THEN acttop := datachainlength - 1
        ELSE acttop := 0
        END
      END;
      DisplayNodeAndChain;
    END Flip;

    PROCEDURE ScrollDown;
      VAR offset: INTEGER;
    BEGIN
      offset := INTEGER(nrLines) - INTEGER(DownCharPos(datawindow));
      IF offset > 0 THEN
        IF offset >= INTEGER(acttop) THEN acttop := 0
        ELSE acttop := acttop - CARDINAL(offset)
        END;
        DisplayNodeAndChain;
      END
    END ScrollDown;

  BEGIN (* DataHandler *)
    IF actptr = NIL THEN
      n := MenuSelection("NO DATA INFO|")
    ELSIF Inside(datawindow) AND (RightDotPos(datawindow)<=16) THEN
      CASE reason OF
        1: ScrollUp |
        2: Flip|
        3: ScrollDown
      ELSE
      END
    ELSIF reason = 1 THEN Selection
    ELSE
      PutOnTop(datawindow);
      IF actptr^.father <> NIL THEN
        n := MenuSelection(" DATA| memory| select| father")
      ELSE
        n := MenuSelection(" DATA| memory| select");
      END;
      CASE n OF
        2: SelectAddr |
        3: Select |
        4: SelectFather
      ELSE
      END
    END
  END DataHandler;

  PROCEDURE SetGlobals;
  BEGIN
    ResetWindow(datawindow);
    insideHeight := datawindow^.innerblk.h;
    nrLines := FreeLines(datawindow);
  END SetGlobals;

  PROCEDURE DataControl(w: Window; s: WindowSignal);
  BEGIN
    IF s IN SignalSet{redraw, moved, changed, fontchanged} THEN
      SetGlobals;
      DisplayNodeAndChain
    END
  END DataControl;

  VAR
    winx, winy, winw, winh: CARDINAL;
    disp: Window; dataDisplayed: BOOLEAN;

BEGIN (* MDDataView *)
  disp := FullScreen();
  WITH disp^.outerblk DO
    IF w > h THEN
      winx := 5; winy := 155; winw := w-338; winh := 131
    ELSE
      winx := 5; winy := h-335; winw := w-209; winh := 147
    END
  END;
  CreateWindow(datawindow, winx, winy, winw, winh,
    "   data",
    FALSE, DataControl, dataDisplayed);
  IF dataDisplayed THEN
    SetGlobals;
    InstallWindow(datawindow,
      {1..4}, DataHandler,
      SignalSet{moved, changed, fontchanged},
      dataDisplayed)
  END;
  IF NOT dataDisplayed THEN
    Terminal.WriteString("data window not created"); Terminal.WriteLn
  END;
END MDDataView.
