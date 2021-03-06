IMPLEMENTATION MODULE MDProcHandler; (*C.B; modified by Ch.J. 3.6.81*)

  FROM SYSTEM IMPORT ADR, ADDRESS;
  FROM Storage IMPORT ALLOCATE;
  FROM Terminal IMPORT Read, BusyRead, WriteString, WriteLn;
  FROM OutTerminal IMPORT WriteO;

  FROM DumpFileHandler IMPORT Code, Mem;
  FROM MDDataHandler IMPORT ProcRefInfo;
  FROM MDModuleHandler IMPORT
    maxModNum,
    ModIdent, ModulPointer, ModulRecord,
    modLoaded, modTab;

(*
  TYPE 
    ProcIdent = ARRAY [0..15] OF CHAR;

    ChainRecord = 
      RECORD 
        base: CARDINAL;          (*is dynamic link; not data base*)
        procPC: CARDINAL;
        CASE knowncall: BOOLEAN OF
          TRUE:
            procNr: CARDINAL;
            modNr: CARDINAL;
            pVar: BOOLEAN;
            dataInfo: ADDRESS;   
              (*initialized NIL;   only modified if reference found*)
            isLocalMod: BOOLEAN; 
              (*initialized FALSE; only modified if reference found*)
            procName: ProcIdent 
        END
      END;

    ChainArray = ARRAY [0..4000] OF ChainRecord;

  VAR 
    chain: POINTER TO ChainArray;
    chainmax: CARDINAL; is size; not high
    chaincut: BOOLEAN;

*)

  CONST chainhigh=50;
 
  VAR pchain:  POINTER TO ARRAY [0..chainhigh] OF ChainRecord;


  CONST
    CX  = 355B;
    CI  = 356B;
    CF  = 357B;
    CL  = 360B;
    CLn = 360B;

    AddrOfLoadedModules = 10;
    dataFrameLength = maxModNum;
    AddrOfDataFrameTable = 40B;

  VAR
    error: BOOLEAN; (*side effect of ModuleNumber*)


  PROCEDURE ModuleNumber(nDL: CARDINAL): CARDINAL;
    VAR lF, lDL, lRA, lG: CARDINAL;
  BEGIN
    REPEAT (* termination proof:  assert dynamic link decreases*)
      lDL := nDL;
      IF (lDL<=1) OR (lDL>177774B) THEN (* erronous; no other possibility *)
        WriteString("-- invalid dynamic link"); WriteLn;
        error := TRUE;
        RETURN 0 
      END;
      nDL := Mem(lDL+1);
      IF nDL>=lDL THEN (*error*)
        WriteString("-- increasing dynamic link"); WriteLn;
        error := TRUE;
        RETURN 0 (*against infinite loop*)
      END;
      lRA := Mem(lDL+2);
    UNTIL lRA>=100000B;
    lRA := lRA - 100000B;
    IF lRA<3 THEN (*does not occurs on compiler produced procedure*)
       WriteString("-- invalid return address"); WriteLn;
       error := TRUE;
       RETURN 0 
    END;
    lG := Mem(lDL+0); (* but G register of calling .. *)
    lF := Mem(lG);    (* F register of calling procedure *)
    IF Code(lF, lRA-1)=CF THEN
      RETURN Mem(lDL-1) DIV 400B  (*call formal*)    
    ELSIF Code(lF, lRA-3B)=CX THEN
      RETURN Code(lF, lRA-2B) (*call external*)
    ELSE (*base procedure of a process*)
      RETURN Mem(lDL-1) DIV 400B  (*call formal*)
    END;
  END ModuleNumber;


  PROCEDURE BuildNewChain(p: CARDINAL);
    VAR n, lpc, lDL: CARDINAL;
        lMod, lG, lF, lRA, c: CARDINAL;
        newmodule: BOOLEAN;
  BEGIN
  (*not yet implemented
    WHILE chainmax > 0 DO
      DEC(chainmax);
      IF chain^[chainmax].knowncall THEN
        DeleteData(chain^[chainmax].dataInfo)
      END 
    END;
  *) chainmax := 0; (*shortcut*)
    chaincut := FALSE;
    error := FALSE; 
    newmodule := TRUE;

    procesPtr := p;
    lG := Mem(p); lDL := Mem(p+1); lpc := Mem(p+2);
    (*search for first external or formal call to get f reg*)
    lMod := ModuleNumber(lDL);
    IF (lMod >= dataFrameLength) OR (lMod >= modLoaded) THEN 
      WriteString("-- modulenumber to big"); WriteLn;
    ELSIF lG<>Mem(AddrOfDataFrameTable+lMod) THEN 
      WriteString("-- G differs from data frame table"); WriteLn;
    ELSE
      lF := Mem(lG);
      (*build chain*)
      LOOP
        IF chainmax>=chainhigh THEN
          WriteString('-- skipped'); WriteLn;
          chaincut := TRUE;
          EXIT
        END;
        IF (lDL<=1) OR (lDL>177774B) THEN
          IF lDL<>0 THEN 
            WriteString('-- illegal dynamic link');
            WriteO(lDL, 7); WriteLn;
          END;
          EXIT
        END;
        IF newmodule THEN 
          lMod := ModuleNumber(lDL);
          IF error THEN EXIT END;
        END;
        lRA := Mem(lDL+2);
        IF (lRA MOD 100000B) < 3 THEN          
          WriteString('-- bad return adress'); WriteLn;
          EXIT
        END;
        WITH pchain^[chainmax] DO
          knowncall := TRUE;
          pVar := FALSE; dataInfo := NIL;
          isLocalMod := FALSE;
          modNr := lMod; procPC := lpc;
          IF lRA >= 100000B THEN     (*external call*)
            newmodule := TRUE;
            lRA := lRA-100000B;
            lG := Mem(lDL+0); lF := Mem(lG);
            IF Code(lF, lRA-1)=CF THEN
              pVar := TRUE;
              procNr := Mem(lDL-1) MOD 400B
            ELSIF Code(lF,lRA-3)=CX THEN
              procNr := Code(lF,lRA-1)
            ELSE (*base procedure of a process*)
              pVar := TRUE;
              procNr := Mem(lDL-1) MOD 400B
            END
          ELSE                        (*internal call*)
            newmodule := FALSE;
            c := Code(lF, lRA-1);
            IF c > CLn THEN           (*CL1 ..CL15*)
              procNr := c - CLn
            ELSIF (Code(lF, lRA-2)=CL) OR (Code(lF, lRA-2)=CI) THEN
              procNr := c
            ELSE 
              knowncall := FALSE
            END;
          END;
          IF procNr<>0 THEN base := lDL               (*local data*)
          ELSE 
            base := Mem(AddrOfDataFrameTable+lMod)    (*global data*)
          END;
          IF knowncall THEN ProcRefInfo(chainmax) END 
        END; (*with *)
        lDL := Mem(lDL+1);   (*go to next procedure mark*)
        lpc := lRA;          (*pc of new mark equivalent to 
                               ret. addr. of old*)
        INC(chainmax)
      END;
    END;
    FOR c := chainmax TO chainhigh DO
      WITH pchain^[c] DO
        base := 0; procPC := 0; knowncall := FALSE
      END
    END;
  END BuildNewChain;


BEGIN
  chaincut := FALSE;
  NEW(pchain);
  chain := ADDRESS(pchain);
  chainmax := 0;
END MDProcHandler.
