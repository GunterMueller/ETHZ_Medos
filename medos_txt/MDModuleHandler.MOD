IMPLEMENTATION MODULE MDModuleHandler;  (* Ch.J. 3.11.81*)
(*(*$T-*) (*$R-*)*)
  FROM SYSTEM IMPORT ADR, ADDRESS;
  FROM Storage IMPORT ALLOCATE;
  FROM Terminal IMPORT Read, BusyRead, WriteString, WriteLn;
  FROM OutTerminal IMPORT WriteO;
  FROM DumpFileHandler IMPORT Code, Mem, OpenDumpFile;
  FROM MDWhatToDebug IMPORT debuglife;

  CONST
    AddrOfLoadedModules = 10;
    AddrOfDataFrameTable = 40B;


  PROCEDURE ModuleName(mn: CARDINAL; VAR name: ModIdent);
    (*finds the name of Module mn of the dataFrameTable*)
    VAR j, lf, lg: CARDINAL;
        ch: CHAR;
  BEGIN
    FOR j := 0 TO HIGH(name) DO name[j] := ' ' END;
    j := 0;
    IF mn >= maxModNum THEN
      WriteString('-- illegal modulenumber'); WriteO(mn, 7); WriteLn;
    ELSE
      lg := Mem(AddrOfDataFrameTable+mn);
      lf := Mem(lg);
      IF lf < 4 THEN WriteString('-- illegal modulepointer'); 
        WriteO(lf, 7); WriteLn;
      ELSE
        lf := lf-4;  (*now pointing to modulename*)
        LOOP
          IF j > HIGH(name) THEN EXIT END;
          ch := CHAR(Code(lf, j));
          IF (ch<' ') OR (ch>=177C) THEN EXIT END;
          name[j] := ch; 
          INC(j);
        END;
      END; 
    END; 
  END ModuleName;


  PROCEDURE BuildMap;
    (*to build the load map*)
    VAR i: CARDINAL; 
  BEGIN
    WriteString('builds the load map'); WriteLn;
    FOR i := 0 TO maxModNum-1 DO modTab[i] := NIL END;
    i := Mem(AddrOfLoadedModules);
    IF i = 0 THEN
      WriteString('-- no loaded modules'); WriteLn;
      modLoaded :=0;
    ELSE
      IF i >= maxModNum THEN
        WriteString('-- illegal modul count:'); 
        WriteO(i, 7); WriteLn;
        modLoaded := maxModNum;
      ELSE modLoaded := i
      END;
      FOR i := 0 TO modLoaded-1 DO
        NEW(modTab[i]);
        WITH modTab[i]^ DO
          ModuleName(i, modName);
          base := Mem(AddrOfDataFrameTable+i);
          dataInfo := NIL;
          listInfo := NIL;
          IF base < 177777B THEN initFlag := Mem(base+1) END;
        END;
      END;
    END; 
  END BuildMap;

BEGIN
  IF NOT debuglife THEN OpenDumpFile(TRUE) END;
  BuildMap
END MDModuleHandler.
