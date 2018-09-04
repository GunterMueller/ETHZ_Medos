(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          Program:                    *
*                                      *
*          Module for                  *
*          - program execution and     *
*          - storage management.       *
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

IMPLEMENTATION MODULE Program;

  IMPORT SYSTEM, Monitor, FileSystem, Terminal;

  FROM SYSTEM IMPORT ADDRESS;

 
  CONST
    codekeyadr     = 11B;  (* address of codekey *)
    modtopadr      = 12B;  (* address of moduletop *)
    prevmodtopadr  = 13B;  (* address of the previous moduletop *)
    minuserspace   =  40;  (* minimum space between stack and heap *)

  VAR
    heaptop, heapbottom: ADDRESS;

 
  MODULE ProgramHelper;
   
    FROM SYSTEM IMPORT ADDRESS, WORD, ADR;

    EXPORT
      SetStackLimit, GetStackLimit, GetStackTop;

 
    CONST
      sys = 247B;
      rtn = 354B;

    PROCEDURE GetStackLimit(): ADDRESS; 
    CODE 
      sys; 4;
    END GetStackLimit; 

     
    PROCEDURE SetStackLimit(limit: ADDRESS); 
    CODE 
      sys; 3; 
    END SetStackLimit; 


    PROCEDURE GetStackTop(): ADDRESS; 
     
      CONST woffset = 5;
 
      VAR w: WORD; 

    BEGIN 
      RETURN ADR(w) - woffset 
    END GetStackTop; 

  END ProgramHelper;


  PROCEDURE Terminate(st: Status);
  BEGIN
    IF st > callerr THEN st := callerr END;
    Monitor.Terminate(VAL(Monitor.Status, ORD(st)));
  END Terminate; 


  PROCEDURE MainProcess(): BOOLEAN; 
  BEGIN 
    RETURN heaptop = GetStackLimit() 
  END MainProcess;   

 
  PROCEDURE CurrentLevel(): CARDINAL;  
  BEGIN 
    RETURN Monitor.CurrentLevel() 
  END CurrentLevel; 
 
 
  PROCEDURE SharedLevel(): CARDINAL; 
  BEGIN 
    RETURN Monitor.SharedLevel() 
  END SharedLevel; 
 
     
  PROCEDURE AllocateHeap(quantum: CARDINAL): ADDRESS; 

    VAR limit, tos: ADDRESS;

  BEGIN 
    limit := GetStackLimit(); 
    IF heaptop = limit THEN (* correct stack *)
      tos := GetStackTop(); 
      IF quantum <= heaptop - tos - minuserspace THEN
        DEC(heaptop, quantum); 
      ELSIF heaptop - tos >= minuserspace THEN
        heaptop := tos + minuserspace 
      END; 
      SetStackLimit(heaptop) 
    END; 
    RETURN heaptop; 
  END AllocateHeap; 


  PROCEDURE DeallocateHeap(quantum: CARDINAL): ADDRESS; 

    VAR limit, tos: ADDRESS; 

  BEGIN 
    limit := GetStackLimit(); 
    IF heaptop = limit THEN (* correct stack *) 
      tos := GetStackTop(); 
      IF quantum <= heapbottom - heaptop THEN 
        INC(heaptop, quantum); 
      ELSE 
        heaptop := heapbottom 
      END; 
      SetStackLimit(heaptop) 
    END; 
    RETURN heaptop 
  END DeallocateHeap; 


  MODULE Executer; 

    IMPORT SYSTEM, Monitor, FileSystem;

    FROM SYSTEM IMPORT 
      PROCESS, NEWPROCESS, TRANSFER, ADDRESS, TSIZE; 

    FROM FileSystem IMPORT
      File, Lookup, Close, Flag, FlagSet, Doio;

    FROM Terminal IMPORT
      Write, WriteLn;

    IMPORT
      Status,
      GetStackLimit, SetStackLimit, GetStackTop, 
      MainProcess, CurrentLevel, SharedLevel,
      heaptop, heapbottom, 
      codekeyadr, modtopadr,
      prevmodtopadr;
 
    EXPORT Call;
 
    CONST
      dnlength = 3; devicename = 'DK.';
      fnlength = 32;
      pnlength = 16;
      modules = 128; 
      imports = 40;        (* maximal number of imported and *)
                           (* not already loaded modules     *)
      callworkspace = 40; 
      loaderworkspace = 480 + 12 * imports; 
      niladdress = 177777B;
 
    TYPE
      FileName     = ARRAY [0..fnlength-1] OF CHAR;
      ProgramName  = ARRAY [0..pnlength-1] OF CHAR; 
      ModuleNumber = [0..modules];  
      ModuleIndex  = [0..modules-1];
      FrameTable   = ARRAY ModuleIndex OF ADDRESS;
 
    VAR 
      codekey[codekeyadr]: CARDINAL;      (* code key *)
      moduletop[modtopadr]: ModuleNumber; (* loaded modules  *)
       
      dft[40B]: FrameTable;               (* data frame table *)

      prevmoduletop[prevmodtopadr]: ModuleNumber;

      programname: ProgramName;           (* parameters from Call *)
      state: Status;
      sharedbottom: ModuleNumber;    
      loadbase, maxloadadr: ADDRESS;                
      programproc: PROC; 
      caller, loader: PROCESS; 


    PROCEDURE Error(st: Status);
    BEGIN
      state := st;
    END Error;

    PROCEDURE WriteString(str: ARRAY OF CHAR);
      VAR ch: CHAR; i: CARDINAL;
    BEGIN
      i := 0;
      LOOP
        IF i > HIGH(str) THEN EXIT END;
        ch := str[i]; INC(i);
        IF (ch < 40C) OR (177C <= ch) THEN EXIT END;
        Write(ch)
      END;
    END WriteString;

    PROCEDURE Marker(ch: CHAR);
      VAR i: CARDINAL;
    BEGIN
      i := CurrentLevel() + 1;
      WHILE i > 0 DO Write(ch); DEC(i) END;
      Write(' ');
    END Marker;
 
 
    PROCEDURE Call(pn: ARRAY OF CHAR; sh: BOOLEAN; VAR st: Status); 

      CONST sys = 247B;

      VAR 
        oldmoduletop: ModuleNumber;  
        oldsharedbottom: ModuleIndex;
        oldheapbottom: ADDRESS;
        monst: Monitor.Status;
        son: PROCESS;
        c: CARDINAL; ch: CHAR; 


    BEGIN
      state := normal; 
      c := 0;
      LOOP
        IF c > HIGH(pn) THEN EXIT END;
        ch := pn[c];
        IF (ch <= 40C) OR (177C < ch) THEN EXIT END;
        IF c >= pnlength THEN Error(callerr); EXIT END;
        programname[c] := ch;
        INC(c);
      END;
      IF c < pnlength THEN programname[c] := 0C END;
      IF (state = normal) AND MainProcess() THEN 
        loadbase := GetStackTop() + callworkspace; 
        IF heaptop - loadbase >= loaderworkspace THEN 
          maxloadadr := heaptop - loaderworkspace; 
          oldmoduletop := moduletop; 
          IF NOT sh THEN
            oldsharedbottom := sharedbottom;
            sharedbottom := moduletop;
            oldheapbottom := heapbottom; 
            heapbottom := heaptop; 
          END;
          NEWPROCESS(ProgramLoader,maxloadadr,loaderworkspace,loader);
          TRANSFER(caller, loader);
          IF state = normal THEN 
            NEWPROCESS(programproc, loadbase, heaptop-loadbase, son);
            Monitor.Call(son, sh, monst);
            state := Status(monst);
            prevmoduletop := moduletop;
          END; 
          IF sh THEN
            SetStackLimit(heaptop); 
          ELSE 
            heaptop := heapbottom; 
            heapbottom := oldheapbottom; 
            sharedbottom := oldsharedbottom;
          END; 
          moduletop := oldmoduletop; 
        ELSE Error(maxspaceerr)
        END; 
      ELSE Error(callerr)
      END; 
      st := state;
    END Call; 

       
    PROCEDURE ProgramLoader;

       
      CONST
        keysize = 3;
        modidsize = 16; 
        prefixsize = 3;
 
      TYPE 
        ModuleIdent = ARRAY [0..modidsize-1] OF CHAR; 
        ModuleName =  RECORD 
                        key: ARRAY [0..keysize-1] OF CARDINAL;
                        ident: ModuleIdent; 
                      END; 
 
        ImportedModule =  RECORD 
                            mn: ModuleName;
                            mnr: ModuleIndex; 
                          END;   
        ImportNumber = [0..imports]; 
        ImportIndex = [0..imports-1];  

        Prefix = ARRAY [0..prefixsize-1] OF CHAR;
 
 
      VAR 
        importlist: ARRAY ImportIndex OF ImportedModule; 
        importtop, importsearchtop: ImportNumber; 
         
        programmodule: ModuleIndex;  (* Modulenumber of just loaded program *) 
         
        f: File;
        fn: FileName;               (* Global because of error messages *)

        modid: ModuleIdent; 
        c: CARDINAL;
        ch: CHAR;
        nameend: BOOLEAN; 
 
        storage: ModuleName;         (* initialized to 'Storage         ' *)
 

      PROCEDURE OpenFile(VAR f: File; pf: Prefix; mn: ModuleIdent);  
        VAR i: CARDINAL;
      BEGIN
        fn := devicename; 
        i := 0;
        WHILE (i < modidsize) AND (mn[i] <> 0C) DO
          fn[i+dnlength] := mn[i]; INC(i);
        END;
        INC(i, dnlength);
        fn[i  ] := '.'; fn[i+1] := 'O';
        fn[i+2] := 'B'; fn[i+3] := 'J';
        fn[i+4] := 0C;
        Lookup(f, fn, FALSE); 
        IF f.res <> FileSystem.done THEN 
          FOR i := fnlength-1 TO prefixsize + 1 + dnlength BY -1 DO 
            fn[i] := fn[i - (prefixsize + 1)]; 
          END; 
          FOR i := 0 TO prefixsize-1 DO 
            fn[i+dnlength] := pf[i]; 
          END; 
          fn[dnlength+prefixsize] := '.'; 
          Lookup(f, fn, FALSE);
        END 
      END OpenFile; 
 
 
      PROCEDURE InsertModule(VAR modnam: ModuleName; VAR mnr: ModuleNumber);
      BEGIN   
        mnr := moduletop;
        IF moduletop >= modules THEN Error(maxmoduleerr) 
        ELSIF importtop >= imports THEN Error(loaderr) 
        ELSE 
          WITH importlist[importtop] DO 
            mn := modnam; 
            dft[moduletop] := niladdress;
            mnr := moduletop; INC(moduletop); 
          END; 
          INC(importtop) 
        END;
      END InsertModule;
 
     
      PROCEDURE DeleteModule(importnr: ImportIndex); 
 
        VAR c: CARDINAL; 
 
      BEGIN 
        DEC(importtop);
        FOR c := importnr + 1 TO importtop DO 
          importlist[c - 1] := importlist[c] 
        END; 
        IF importsearchtop > importnr THEN DEC(importsearchtop) END;   
      END DeleteModule; 
 
 
      PROCEDURE LoadFile(VAR f: File; prog: BOOLEAN);

        TYPE 
          Symbol = (eofsy, codekeysy, modulesy, importsy,
                    ctext, dtext, fixup);
          SymbolSet = SET OF Symbol;
 
 
        MODULE InCode;
 
          FROM FileSystem IMPORT
            File, ReadWord;

          IMPORT
            Error,
            f, 
            Symbol, 
            state, Status;
 
          EXPORT 
            Getnum, Getsy, Skip, 
            sy, fs; 
 
          VAR 
            sy: Symbol; 
            fs: CARDINAL; 

           
          PROCEDURE Getnum(VAR n: CARDINAL);
          BEGIN
            IF fs = 0 THEN Error(filestructureerr); n := 0;
            ELSE DEC(fs); ReadWord(f, n);
              IF f.eof THEN n := 0 END;
            END;
 
          END Getnum; 
 
           
          PROCEDURE Skip;

            VAR n: CARDINAL;
 
          BEGIN 
            WHILE fs > 0 DO Getnum(n) END;
          END Skip; 
 
 
          PROCEDURE Getsy;

            VAR n: CARDINAL;
 
          BEGIN
            IF fs > 0 THEN Error(filestructureerr); Skip END; 
            fs := 1; Getnum(n);
            IF f.eof THEN sy := eofsy 
            ELSIF (200B <= n) AND (n <= 205B) THEN  
              sy := Symbol(n - 177B); 
              fs := 1; 
              Getnum(fs);
              IF f.eof THEN
                Error(filestructureerr); sy := eofsy;
              END;
            ELSIF n <= 377B THEN (* comment tables *)
              fs := 1; Getnum(fs); Skip; Getsy; 
            ELSE Error(filestructureerr); sy := eofsy; 
            END;
          END Getsy; 

 
        BEGIN
          fs := 0;
        END InCode; 
 
       
        PROCEDURE LoadModule(prog: BOOLEAN);

          CONST
            maxarea = 77777B;
 
          TYPE
            ModuleNamePtr = POINTER TO ModuleName;
            AreaPointer = POINTER TO ARRAY [0..maxarea] OF CARDINAL;
            Area = RECORD
                     ap: AreaPointer; (*pointer to the actual area*)
                     atop: CARDINAL;   (*uppermost used index + 1   *)
                     top: CARDINAL;    (*uppermost usable index + 1 *)
                    END; 
 
          VAR
            loctab: ARRAY ModuleIndex OF ModuleIndex; 
            loctabtop: ModuleNumber; 
            data, code: Area;
            found, compatible: BOOLEAN; 
            mnr: ModuleIndex; 
            imported: BOOLEAN; 
            importnr: ImportIndex; 
 
 
          PROCEDURE Getmn(VAR mn: ModuleName);

            VAR
              c, n: CARDINAL; 
              ch: CHAR; 
              oddpos, idend: BOOLEAN; 

 
            PROCEDURE Getch(VAR ch: CHAR);
            BEGIN   
              IF oddpos THEN ch := CHAR(n MOD 400B) 
              ELSE Getnum(n); ch := CHAR(n DIV 400B); 
              END;
              oddpos := NOT oddpos;
              IF (ch <= 40C) OR (177C <= ch) THEN ch := 0C END;
            END Getch;
 
 
          BEGIN
            oddpos := FALSE;
            IF fs >= 11 THEN
              WITH mn DO
                idend := FALSE;
                FOR c := 0 TO modidsize-1 DO
                  Getch(ch);
                  IF idend THEN ch := 0C END;
                  idend := ch = 0C;
                  ident[c] := ch;
                END;
                FOR c := 0 TO keysize-1 DO Getnum(key[c]) END;
              END; (* WITH *)
            ELSE Error(filestructureerr); Skip;       
            END;
          END Getmn; 
 
 
          PROCEDURE SkipModule; 
          BEGIN 
            REPEAT 
              Skip; Getsy   
            UNTIL sy IN SymbolSet{eofsy, codekeysy, modulesy}
          END SkipModule; 
 
 
          PROCEDURE Equal(VAR mn1, mn2: ModuleName; VAR eq, comp: BOOLEAN);
 
            (*  Equal compares mn1 and mn2. The results are defined as:

                eq := mn1.ident = mn2.ident;
                IF eq THEN comp := mn1.key = mn2.key END;             *)
 
            VAR c: CARDINAL;
               
          BEGIN 
            c := 0; eq := TRUE; 
            WHILE eq AND (c < modidsize) DO 
              eq := mn1.ident[c] = mn2.ident[c]; 
              INC(c) 
            END; 
            IF eq THEN 
              c := 0; comp := TRUE; 
              WHILE comp AND (c < keysize) DO
                comp := mn1.key[c] = mn2.key[c]; 
                INC(c) 
              END; 
            END;
          END Equal; 
 
 
          PROCEDURE Find(VAR mn: ModuleName; searchbottom: ModuleNumber); 
 
            (*  Find searches module mn under the modules in the 
                importlist and under the already loaded modules. 
                The result is returend into the following variables: 
                  found, compatible, mnr, imported, importnr.       *)
 
            TYPE
              CardPtr = POINTER TO CARDINAL;

            VAR 
              c: CARDINAL;
              cp: CardPtr; 
              mnp: ModuleNamePtr; 
 
          BEGIN   
            c := importtop; found := FALSE; 
            WHILE NOT found AND (c > 0) DO 
              DEC(c); 
              Equal(mn, importlist[c].mn, found, compatible); 
            END; 
            imported := found;
            IF found THEN 
              mnr := importlist[c].mnr; importnr := c; 
            ELSE 
              c := moduletop;
              WHILE NOT found AND (c > searchbottom) DO  
                DEC(c); 
                IF dft[c] <> niladdress THEN
                  cp := CardPtr(dft[c]);
                  mnp := ModuleNamePtr(cp^*2 - TSIZE(ModuleName));
                  Equal(mn, mnp^, found, compatible); 
                END; 
              END; 
              IF found THEN mnr := c END; 
            END;
          END Find; 
 
 
          PROCEDURE CodeKey;

            VAR actcodekey: CARDINAL;
  
          BEGIN
            IF sy = codekeysy THEN
              IF fs = 1 THEN
                Getnum(actcodekey);
                IF actcodekey <> codekey THEN
                  Error(codekeyerr); SkipModule
                ELSE Getsy;
                END;
              ELSE Error(filestructureerr); Skip
              END
            ELSIF codekey <> 0 THEN Error(codekeyerr)
            END;
          END CodeKey;
  
  
          PROCEDURE ModuleHeader; 
             
            VAR 
              modnam: ModuleName;
              mnptr: ModuleNamePtr; 
              modnr: ModuleNumber; 
              eq, comp: BOOLEAN;
              searchbottom: ModuleNumber;
              dtop: ADDRESS;
 
          BEGIN
            IF (fs < 12) OR (14 < fs) THEN
              Error(filestructureerr); Skip; Getsy;
            ELSE Getmn(modnam); Getnum(data.top);
              Skip; Getsy;
              modid := modnam.ident; (* saved for error messages *)
              IF prog THEN 
                Find(modnam, 0); 
                IF found THEN Error(programalreadyloaded);
                ELSE InsertModule(modnam, programmodule);
                END; 
              END;   
              Equal(modnam, storage, eq, comp);
              IF eq THEN searchbottom := sharedbottom
              ELSE searchbottom := 0
              END; 
              Find(modnam, searchbottom);
              IF found THEN 
                IF imported THEN
                  IF compatible THEN (* load the module *)
                    WITH data DO
                      ap := loadbase; 
                      dft[mnr] := ap;
                      atop := 0;
                      dtop := (loadbase + top) DIV 2 * 2 + 1;
                      (* ODD(dtop) *)
                    END;
                    mnptr := dtop;
                    (* ODD(dtop) AND ODD(TSIZE(ModuleName)) *)
                    INC(dtop, TSIZE(ModuleName));
                    (* EVEN(dtop) *)
                    IF maxloadadr <= dtop THEN
                      Error(maxspaceerr); 
                    ELSE  
                      loadbase := dtop;
                      (* EVEN(loadbase) *)
                      WITH code DO
                        ap := loadbase;
                        data.ap^[0] := ADDRESS(ap) DIV 2;
                        atop := 0; 
                        top := maxloadadr - ADDRESS(ap); 
                      END;
                      mnptr^ := importlist[importnr].mn; 
                      loctab[0] := mnr; loctabtop := 1;
                    END;   
                  ELSE
                    Error(incompatiblemodule);
                    Marker('-');
                    WriteString("Program.Call:  incompatible module");
                    WriteLn;
                    Marker(' ');
                    WriteString("  '");
                    WriteString(modnam.ident);
                    WriteString("' on file '");
                    WriteString(fn);
                    WriteString("' "); WriteLn;
                    SkipModule
                  END;
                  DeleteModule(importnr);
                ELSE SkipModule
                END; (* IF imported *)
              ELSE SkipModule;
              END; (* IF found *)
            END;
          END ModuleHeader;
 
 
          PROCEDURE Imports; 
             
            VAR
              mn: ModuleName;
              eq, comp: BOOLEAN; 
              searchbottom: ModuleNumber;
   
          BEGIN 
            WHILE fs >= 11 DO (* size of a modulename *)
              Getmn(mn);
              Equal(mn, storage, eq, comp);
              IF eq THEN searchbottom := sharedbottom
              ELSE searchbottom := 0
              END;
              Find(mn, searchbottom);
              IF found THEN 
                IF NOT compatible THEN
                  Error(incompatiblemodule);
                  Marker('-');
                  WriteString("Program.Call:  incompatible module");
                  WriteLn;
                  Marker(' ');
                  WriteString("  '");
                  WriteString(mn.ident);
                  WriteString("' imported by '");
                  WriteString(modid);
                  WriteString("' on file '");
                  WriteString(fn);
                  WriteString("' "); WriteLn;
                END; 
              ELSE InsertModule(mn, mnr) 
              END;   
              IF loctabtop < modules THEN
                loctab[loctabtop] := mnr; INC(loctabtop)
              ELSE Error(filestructureerr); Skip 
              END;
            END; 
            Getsy;
          END Imports; 
   
           
          PROCEDURE LoadText(VAR a: Area);
   
            VAR 
              offset, ltop, count: CARDINAL;

            PROCEDURE MoveWords(toa, froma: ADDRESS; cnt: CARDINAL);
            CODE
              340B
            END MoveWords; 
   
          BEGIN 
            IF fs = 0 THEN Error(filestructureerr); 
            ELSE Getnum(offset);
              WITH a DO
                ltop := offset + fs;
                IF ltop > top THEN    
                  Error(maxspaceerr); Skip 
                ELSE
                  IF ltop > atop THEN
                    atop := ltop;            
                    IF loadbase < ADDRESS(ap) + atop THEN
                      loadbase := ADDRESS(ap) + atop 
                    END; 
                  END;
                  LOOP
                    IF fs = 0 THEN EXIT END;
                    WITH f DO
                      IF flags * FlagSet{rd,bytemode,ef}<>FlagSet{rd} THEN
                        Error(filestructureerr); Skip; EXIT
                      END;
                      count := ina - ela;
                      IF count = 0 THEN Doio(f)
                      ELSE
                        IF count > fs THEN count := fs END;
                        MoveWords(ADDRESS(ap) + offset, ela, count);
                        INC(offset, count); INC(ela, count); 
                        DEC(fs, count);
                      END;
                    END;
                  END; 
                  WHILE fs > 0 DO 
                    Getnum(ap^[offset]); INC(offset); 
                  END 
                END
              END
            END; 
            Getsy
          END LoadText; 
   
   
          PROCEDURE Fixups; 

            VAR 
              offset, w, nr, nr1: CARDINAL;  
              oddpos: BOOLEAN; 
 
          BEGIN 
            WHILE fs > 0 DO 
              Getnum(offset); 
              oddpos := ODD(offset); offset := offset DIV 2; 
              WITH code DO
                IF offset >= atop THEN Error(filestructureerr)
                ELSE w := ap^[offset]; 
                  IF oddpos THEN nr := w MOD 400B
                  ELSE nr := w DIV 400B
                  END;
                  IF nr >= loctabtop THEN Error(filestructureerr) 
                  ELSE nr1 := loctab[nr];
                    IF oddpos THEN w := w - nr + nr1
                    ELSE w := w - nr*400B + nr1*400B
                    END; 
                    ap^[offset] := w;
                  END 
                END 
              END 
            END; 
            Getsy;
          END Fixups;

 
        BEGIN
          (* modulesy or codekeysy has always been read *) 
          CodeKey;
          IF (state=normal) AND (sy=modulesy) THEN ModuleHeader END; 
          IF (sy=importsy) AND (state=normal) THEN Imports END; 
          WHILE (state=normal) AND ((sy=ctext) OR (sy=dtext)) DO 
            IF sy = ctext THEN 
              LoadText(code);
              IF sy = fixup THEN Fixups END;
            ELSE LoadText(data);
            END; 
          END; (* WHILE *) 
          IF NOT (sy IN SymbolSet{eofsy, codekeysy, modulesy}) AND
             (state = normal) THEN 
            Error(filestructureerr); 
            SkipModule;
          END;
        END LoadModule; 
 
 
      BEGIN 
        Getsy;
        WHILE (state=normal) AND ((sy=modulesy) OR (sy=codekeysy)) DO 
          LoadModule(prog); 
          prog := FALSE; 
        END;
      END LoadFile; 
 
 
    BEGIN 
      storage.ident := 'Storage';
      FOR c := 7 TO modidsize-1 DO storage.ident[c] := 0C END;
      FOR c := 0 TO keysize-1 DO storage.key[c] := 0 END;
      programmodule := moduletop;
      importtop := 0; importsearchtop := 0; 
       
      nameend := FALSE;
      FOR c := 0 TO modidsize-1 DO
        ch := programname[c];
        IF nameend OR (ch<=40c) OR (177C<=ch) THEN ch := 0C END;
        nameend := ch = 0C;
        modid[c] := ch 
      END; 
 
      OpenFile(f, 'SYS', modid);
      IF f.res = FileSystem.done THEN 
        LoadFile(f, TRUE); 
        Close(f); 
        WHILE (importsearchtop < importtop) AND (state = normal) DO
          OpenFile(f, 'LIB', importlist[importsearchtop].mn.ident); 
          INC(importsearchtop); 
          IF f.res = FileSystem.done THEN 
            LoadFile(f, FALSE); 
            Close(f); 
          END; 
        END;
        IF state = normal THEN 
          IF importtop > 0 THEN
            Error(modulenotfound);
            Marker('-');
            WriteString('Program.Call:  module(s) not found:'); WriteLn;
            WHILE importtop > 0 DO
              DEC(importtop);
              Marker(' '); WriteString('  ');
              WriteString(importlist[importtop].mn.ident);
              WriteLn;
            END;
          ELSIF programmodule = moduletop THEN Error(programnotfound)
          ELSE 
            (* By the next statement, we make the just loaded 
               program callable as procedure variable 'programproc'.
               The procedure variable corresponds to procedure 0 of  
               module programmodule. *)  
            programproc := PROC( programmodule * 400B ); 
          END 
        END 
      ELSE Error(programnotfound)
      END;
      TRANSFER(loader, caller); 
    END ProgramLoader; 

   
  BEGIN
    sharedbottom := 1;
  END Executer; 


BEGIN
  heaptop := 177777B;   
  heapbottom := heaptop;   
END Program.

