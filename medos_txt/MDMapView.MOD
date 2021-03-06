IMPLEMENTATION MODULE MDMapView;  (* HK.B. modified Ch.J 10.11.81*)
(*  (*$T-*) (*$R-*) *)
  FROM Monitor IMPORT CurrentLevel;
  IMPORT Terminal;
  FROM WindowHandler IMPORT
    Window, OpenWindow, Clear, GetPos, FreeLines, PutOnTop, CloseWindow,
    CreateWindow, WindowSignal, SignalSet, FullScreen;
  FROM CursorRelations IMPORT
    Inside, DownCharPos, UpDotPos, RightDotPos;
  FROM CursorStuff IMPORT MenuSelection, TrackCursor;
  FROM WindowDialogue IMPORT 
    InstallWindow, RemoveWindow;
  FROM OutWindow IMPORT Write, WriteS, WriteT, WriteO, WriteC, WriteLn;

  FROM MDUtility IMPORT ResetWindow;
  FROM MDModuleHandler IMPORT 
    maxModNum,
    ModIdent, ModulPointer, ModulRecord,
    modLoaded, modTab;

  FROM MDListView IMPORT ShowList;
  FROM MDDataView IMPORT ShowModData;
  FROM Inspect IMPORT Show;

  CONST
    EOL = 36c;

  VAR 
    mapwindow, disp: Window;
    topModule: CARDINAL;
    winx, winy, winw, winh: CARDINAL;
    mapViewLevel: CARDINAL;


  PROCEDURE SelectModule(VAR m: CARDINAL; VAR done: BOOLEAN);
  BEGIN
    done := modLoaded>0;
    IF done THEN
      Terminal.WriteString("select a module"); Terminal.WriteLn;
      done := (TrackCursor()<>0) AND Inside(mapwindow) AND (RightDotPos(mapwindow)>=16);
    END;
    IF done THEN
      m := DownCharPos(mapwindow)+topModule;
      done := m<modLoaded
    END;
  END SelectModule;


  PROCEDURE OldSelectModule(VAR m: CARDINAL; VAR done: BOOLEAN);
  BEGIN
    done := (modLoaded>0) AND Inside(mapwindow);
    IF done THEN m := DownCharPos(mapwindow)+topModule;
      done := m<modLoaded
    END  
  END OldSelectModule;


  PROCEDURE DisplayMap(m: CARDINAL);

    PROCEDURE DisplayModulEl(m: CARDINAL);
    BEGIN
      WITH modTab[m]^ DO
        WriteC(mapwindow, m, 6);
        Write(mapwindow, " ");
        WriteT(mapwindow, modName, 16);
        WriteO(mapwindow, base, 7);
        IF base<177775B THEN
          CASE INTEGER(initFlag) OF
            0: WriteS(mapwindow, ' not init') |
            1: (* initialized *)
          ELSE WriteS(mapwindow, ' ill.init')
          END
        ELSE WriteS(mapwindow, ' ill.base') 
        END
      END
    END DisplayModulEl;

  BEGIN (*DisplayMap*)
    ResetWindow(mapwindow);
    IF m>modLoaded THEN m := modLoaded END;
    IF modLoaded<=FreeLines(mapwindow) THEN m := 0
    ELSIF modLoaded-m<FreeLines(mapwindow) THEN 
      m := modLoaded-FreeLines(mapwindow)
    END;
    topModule := m;
    LOOP
      IF m>=modLoaded THEN EXIT END;
      DisplayModulEl(m); m := m+1;
      IF FreeLines(mapwindow)<=0 THEN EXIT END;
      WriteLn(mapwindow);
    END;
  END DisplayMap;


  PROCEDURE ScrollupMap;
  BEGIN
    DisplayMap(topModule+DownCharPos(mapwindow))
  END ScrollupMap;


  PROCEDURE ScrolldownMap;
    VAR n: INTEGER;
  BEGIN
    Clear(mapwindow);
    n := INTEGER(topModule)-INTEGER(FreeLines(mapwindow))+INTEGER(DownCharPos(mapwindow));
    IF n<0 THEN n := 0 END;
    DisplayMap(n)
  END ScrolldownMap;             


  PROCEDURE FlipMap;
  BEGIN
    DisplayMap(((mapwindow^.innerblk.h-UpDotPos(mapwindow)) DIV 16) *
               (modLoaded DIV (mapwindow^.innerblk.h DIV 16)))
  END FlipMap;


  PROCEDURE MapHandling(w: Window; callReason: CARDINAL);
    VAR m: CARDINAL; b: BOOLEAN;
  BEGIN 
    IF callReason=4 THEN (*...*) 
    ELSIF callReason=5 THEN
      CloseWindow(mapwindow)
    ELSIF Inside(mapwindow) AND (RightDotPos(mapwindow)<=16) THEN
      CASE callReason OF
        1: ScrollupMap |
        2: FlipMap |
        3: ScrolldownMap  
        ELSE
      END
    ELSIF (callReason=1) AND (Inside(mapwindow)) THEN
      OldSelectModule(m, b);
      IF b THEN
        ShowModData(m); ShowList(m, 0);
      END;
    ELSE
      PutOnTop(mapwindow); 
      CASE MenuSelection(" MAP| data| list| memory| remove") OF
        2: SelectModule(m, b);
           IF b THEN ShowModData(m) END|
        3: SelectModule(m, b);
           IF b THEN ShowList(m, 0) END|
        4: SelectModule(m, b);
           IF b THEN Show(modTab[m]^.base) END|
        5: RemoveWindow(mapwindow); CloseWindow(mapwindow)
        ELSE
      END
    END
  END MapHandling;


  PROCEDURE MapControl(w: Window; s: WindowSignal);
  BEGIN
    IF s IN SignalSet{redraw, moved, changed, fontchanged, opened} THEN
      DisplayMap(topModule)
    ELSIF s = closed THEN
      mapViewLevel := 177777B;
      winx := w^.outerblk.x;
      winy := w^.outerblk.y;
      winw := w^.outerblk.w;
      winh := w^.outerblk.h
    END
  END MapControl;


  PROCEDURE InitMapView;
    VAR done: BOOLEAN;
  BEGIN
    IF mapViewLevel # 177777B THEN PutOnTop(mapwindow)
    ELSE
      topModule := 255;
      CreateWindow(mapwindow, winx, winy, winw, winh,
                   "   load map", FALSE, MapControl, done);
      IF done THEN 
        InstallWindow(mapwindow, {1..5}, MapHandling,
            SignalSet{moved, changed, fontchanged}, done);
        IF NOT done THEN CloseWindow(mapwindow)
        ELSE mapViewLevel := CurrentLevel()
        END
      END;
    END
  END InitMapView;


  PROCEDURE TerminateMapView;
  BEGIN
    IF mapViewLevel >= CurrentLevel() THEN
       mapViewLevel := 177777B
    END;
  END TerminateMapView;


BEGIN
  disp := FullScreen();
  WITH disp^.outerblk DO
    winx := 440; winy := 155; winw := 323; winh := 131;
    IF w<768 THEN winx := 312; winy := 5; winh := 147 END;
    IF winh>h THEN winh := h DIV 2 END;
  END;
  mapViewLevel := 177777B;
  InitMapView;
END MDMapView.



