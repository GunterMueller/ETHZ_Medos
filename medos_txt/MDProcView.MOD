IMPLEMENTATION MODULE MDProcView; (*Carl Binding; modified by C.J. 6.6.81*)
(*  (*$T-*) (*$R-*) *)
  FROM SYSTEM IMPORT ADDRESS;
  IMPORT Terminal;
  FROM WindowHandler IMPORT
    Window, OpenWindow, Clear, GetPos, FreeLines, PutOnTop, CloseWindow,
    CreateWindow, WindowSignal, SignalSet, DefaultWindow, FullScreen;
  FROM CursorRelations IMPORT
    Inside, DownCharPos, RightCharPos, UpDotPos, RightDotPos;
  FROM CursorStuff IMPORT MenuSelection, TrackCursor;
  FROM WindowDialogue IMPORT 
    InstallWindow, RemoveWindow;
  FROM OutWindow IMPORT Write, WriteC, WriteO, WriteS, WriteT, WriteLn;

  FROM DumpFileHandler IMPORT Mem;
  FROM MDUtility IMPORT ResetWindow;
  FROM MDListView IMPORT ShowList;
  FROM MDModuleHandler IMPORT modTab, modLoaded;
  FROM MDProcHandler IMPORT
    ProcIdent, ChainRecord, 
    BuildNewChain,
    procesPtr, chain, chainmax, chaincut;
  FROM MDDataView IMPORT ShowProcData;
  FROM Inspect IMPORT Show;


  CONST  EOL = 36C; 


  VAR
    procDisplayed: BOOLEAN;    (*to check openwindow*)
    actTop: CARDINAL;
    procwindow, disp: Window;
    winx, winy, winw, winh: CARDINAL;
    currentProcess: CARDINAL;


  PROCEDURE DisplayErrorCause(cause: CARDINAL; w: Window);
  BEGIN
    CASE INTEGER(cause) OF
      0: WriteS(w, ' no error  ')            |
      1: WriteS(w, ' illegal instruction ')  |
      2: WriteS(w, ' priority error ')       |
      3: WriteS(w, ' storage overflow ')     |
      4: WriteS(w, ' range error ')          |
      5: WriteS(w, ' adressing error ')      |
      6: WriteS(w, ' floating overflow ')    |
      7: WriteS(w, ' cardinal overflow ')    |
      8: WriteS(w, ' integer overflow ')     |
      9: WriteS(w, ' function return error ')|
     10: WriteS(w, ' HALT called')           |
     11: WriteS(w, ' assertion violation ')  |
     12: WriteS(w, ' warned ')               |
     13: WriteS(w, ' stopped ')              | 
     14: WriteS(w, ' call error ') 
    ELSE 
      WriteS(w, ' not specified error ')
    END;
  END DisplayErrorCause;


  PROCEDURE DisplayChain(n: CARDINAL);

    PROCEDURE DisplayChainEl(n: CARDINAL);

    BEGIN
      WriteS(procwindow, '   ');
      WITH chain^[n] DO
        IF knowncall THEN
          IF procNr = 0 THEN
            WriteS(procwindow, 'initialization   of ')
          ELSE 
            WriteT(procwindow, procName, 16);
            WriteS(procwindow, ' in ');
          END;
          IF modNr<modLoaded THEN 
            WriteT(procwindow, modTab[modNr]^.modName, 16);
          ELSE WriteS(procwindow, ' ?              ') 
          END;
          WriteS(procwindow, ' at');
          WriteO(procwindow, procPC, 7);
          WriteS(procwindow, ' (');
          WriteO(procwindow, base, 7);
          Write(procwindow, ")");
          IF pVar THEN WriteS(procwindow, ' pv') END  
        ELSE
          WriteS(procwindow, ' unknown call instr., pc: ');
          WriteO(procwindow, procPC, 7);
          WriteS(procwindow, ' base: ');
          WriteO(procwindow, base, 7);
(*
          WriteLn(procwindow);
          WriteS(procwindow, '    ret. addr. ');
          WriteO(procwindow, procRA, 7)
*)
        END;
      END;
      IF n=0 THEN 
        WriteS(procwindow, ' <==')  (*top procedure of stack*)
      END;
      IF chaincut THEN WriteS(procwindow, ' ...')
      ELSIF (n+1)=chainmax THEN
        WriteS(procwindow, ' xxx')  (*bottom procedure of stack*)
      END;
    END DisplayChainEl;

  BEGIN (*DisplayChain*)
    IF (n<chainmax) THEN 
      actTop := n;
      ResetWindow(procwindow);
      LOOP
        IF n>=chainmax THEN EXIT END;
        DisplayChainEl(n);
        IF FreeLines(procwindow)>0 THEN 
          WriteLn(procwindow);
          n := n+1;
        ELSE EXIT 
        END
      END
    END;
  END DisplayChain;


  PROCEDURE ScrollupProc;
  BEGIN
    DisplayChain(actTop+DownCharPos(procwindow))
  END ScrollupProc;


  PROCEDURE ScrolldownProc;
    VAR n: INTEGER;
  BEGIN
    Clear(procwindow);
    n := INTEGER(actTop)-INTEGER(FreeLines(procwindow))+INTEGER(DownCharPos(procwindow));
    IF n<0 THEN n := 0 END;
    DisplayChain(n)
  END ScrolldownProc;             


  PROCEDURE FlipProc;
  BEGIN
    DisplayChain(((procwindow^.innerblk.h-UpDotPos(procwindow)) DIV 16) *
                 (chainmax DIV (procwindow^.innerblk.h DIV 16)));
  END FlipProc;


  PROCEDURE Proclist(n: CARDINAL);
  BEGIN
    IF n<chainmax THEN
      ShowList(chain^[n].modNr, chain^[n].procPC)  
    END 
  END Proclist;


  PROCEDURE Procdata(n: CARDINAL);
  BEGIN
    IF n<chainmax THEN
      ShowProcData(n)
    END  
  END Procdata;

 
  PROCEDURE SelectElem(VAR m: CARDINAL; VAR done: BOOLEAN);
  BEGIN
    done := chainmax>0;
    IF done THEN
      Terminal.WriteString("select a procedure"); Terminal.WriteLn;
      done := (TrackCursor()<>0) AND Inside(procwindow) AND (RightDotPos(procwindow)>=16);
    END;
    IF done THEN
      m := DownCharPos(procwindow)+actTop;
      done := m<chainmax
    END;
  END SelectElem;


  PROCEDURE OldSelectElem(VAR m: CARDINAL; VAR done: BOOLEAN);
  BEGIN
    done := (chainmax>0) AND Inside(procwindow);
    IF done THEN m := DownCharPos(procwindow)+actTop;
      done := m<chainmax
    END  
  END OldSelectElem;


  PROCEDURE ProcChainHandling(pw: Window; reason: CARDINAL);
    VAR n: CARDINAL; b: BOOLEAN;
  BEGIN 
    IF reason=4 THEN RETURN END;
    IF Inside(procwindow) AND (RightDotPos(procwindow)<=16) THEN
      CASE reason OF
        1: ScrollupProc |
        2: FlipProc |
        3: ScrolldownProc
        ELSE (*error*)  
      END
    ELSIF (reason=1) AND (Inside(procwindow)) THEN
      OldSelectElem(n, b);
      IF b THEN
        Procdata(n);
        Proclist(n)
      END
    ELSE
      PutOnTop(procwindow); 
      CASE MenuSelection(" PROC| data| list| mark") OF
        2: SelectElem(n, b);
           IF b THEN 
             Procdata(n)
           END|
        3: SelectElem(n, b);
           IF b THEN 
             Proclist(n)
           END|
        4: SelectElem(n, b);
           IF b THEN 
             IF n<chainmax THEN
               Show(chain^[n].base)
             END
           END
        ELSE
      END
    END
  END ProcChainHandling;


  PROCEDURE ProcChainControl(w: Window; s: WindowSignal);
  BEGIN
    IF s IN SignalSet{redraw, moved, changed, fontchanged} THEN
      DisplayChain(actTop)
    END
  END ProcChainControl;


  PROCEDURE ShowProcedureChain;
  BEGIN
    IF procDisplayed THEN
      DisplayChain(actTop)
    END
  END ShowProcedureChain;


  PROCEDURE DebugProcess(p: CARDINAL; unusedParameter: BOOLEAN);
  BEGIN
    actTop := 0;
    IF (p < (177777B - 30B)) AND procDisplayed THEN
      IF p # currentProcess THEN
        Terminal.WriteString('builds the procedure chain');
        Terminal.WriteLn;
        BuildNewChain(p);
        currentProcess := p
      END;
      IF chainmax = 0 THEN
        Terminal.WriteString('-- empty process chain');
        Terminal.WriteLn;
        ResetWindow(procwindow);
      ELSE
        DisplayChain(0);
        ShowProcData(0);
        ShowList(chain^[0].modNr, chain^[0].procPC);
      END;
      Terminal.WriteString('error cause:');
      Terminal.WriteLn;
      DisplayErrorCause(Mem(p+6), DefaultWindow()); Terminal.WriteLn;
    END;
  END DebugProcess;


BEGIN (*MDProcView *)
  currentProcess := 177777B;
  disp := FullScreen();
  WITH disp^.outerblk DO
    winx := 5; winy := 290; winw := 537; winh := 131;
    IF w<768 THEN winy := 157; winw := w-10; winh := 167 END;
    IF winh>h THEN winh := h DIV 2 END;
  END;
  CreateWindow(procwindow, winx, winy, winw, winh,
    "   procedure call chain",
    FALSE, ProcChainControl, procDisplayed);
  IF procDisplayed THEN 
    ResetWindow(procwindow); 
    InstallWindow(procwindow,
        {1..4}, ProcChainHandling,
        SignalSet{moved, changed, fontchanged},
        procDisplayed);
  END;
  IF NOT procDisplayed THEN 
    Terminal.WriteString("-- debugger error: procview");
    Terminal.WriteLn; 
  END;
END MDProcView.
 