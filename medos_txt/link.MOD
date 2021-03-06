(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          Linker:                     *
*                                      *
*          The Linker copys all        *
*          object code files needed    *
*          for the execution of a      *
*          program in Medos-2 onto     *
*          one file.                   * 
*                                      *
*          Version 3  24.06.82         *    modified : LG 13.08.82
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

MODULE Linker;

  FROM SYSTEM IMPORT ADDRESS, TSIZE;
  FROM FileSystem IMPORT
    File, Response, Create, Close,
    Reset, ReadWord, WriteWord;
  FROM FileLookup IMPORT LookupFile;
  FROM FilePool IMPORT FilePointer, GetFileFromPool, ReturnFileToPool;
  FROM Options IMPORT GetOption;
  FROM Terminal IMPORT Read, Write, WriteString, WriteLn;

  
  CONST 
    codekeyadr     =     11B;  (* address of codekey *)
    moduletopadr   =     15B;  (* address of modules in SEK *)
    dftadr         =     40B;  (* address of data frame table *)
    modules        =     128; 
    imports        = modules;
    keysize        =       3;
    modidsize      =      16; 
    niladdress     = 177777B;
    fnlength       =      32;
    esc            =     33C;
    eol            =     36C;
 
  TYPE
    FileName     = ARRAY [0..fnlength-1] OF CHAR; 
    ModuleNumber = [0..modules];  
    ModuleIndex  = [0..modules-1];
    FrameTable   = ARRAY ModuleIndex OF ADDRESS;
    ModuleIdent  = ARRAY [0..modidsize-1] OF CHAR; 
    ModuleName   =  RECORD 
                      key: ARRAY [0..keysize-1] OF CARDINAL;
                      ident: ModuleIdent; 
                      END;
    ImportNumber = [0..imports]; 
    ImportIndex  = [0..imports-1];  
    Status       = (normal, 
                    programnotfound, programalreadyloaded,
                    modulenotfound, codekeyerr,
                    incompatiblefound, incompatibleimport,
                    maxspaceerr, maxmoduleerr, 
                    filestructureerr, fileerr,
                    loaderr);
 
  VAR 
    codekey[codekeyadr]: CARDINAL;          (* code key *)
    moduletop[moduletopadr]: CARDINAL;      (* modules in SEK *)
    dft[dftadr]: FrameTable;                (* data frame table *)

    importlist: ARRAY ImportIndex OF ModuleName; 
    handledtop, importtop, importsearchtop: ImportNumber; 
         
    progfptr: FilePointer; progfno: CARDINAL; progfn: FileName;
    infptr: FilePointer;   infno: CARDINAL;   infn: FileName;
    outf: File;
         
    state: Status;
    ok: BOOLEAN;
    query: BOOLEAN;
    str, ext, optstr, libname: ARRAY [0..19] OF CHAR;
    optlgth: CARDINAL;
    err: BOOLEAN;
    c: CARDINAL;
    ch: CHAR;
    escaped: BOOLEAN;
 

  PROCEDURE Error(st: Status);
  BEGIN (* should be called with st <> normal *)
    ok := FALSE;
    state := st;
    WriteString('  ---- ');
    CASE st OF
      programnotfound:      WriteString('program not found') |
      programalreadyloaded: WriteString('program already loaded') |
      modulenotfound:       WriteString('module not found') |
      incompatiblefound:    WriteString('incompatible module found') |
      incompatibleimport:   WriteString('incompatible module imported') |
      maxspaceerr:          WriteString('not enough space') |
      maxmoduleerr:         WriteString('too many modules') |
      codekeyerr:           WriteString('illegal type of code') |
      filestructureerr:     WriteString('error in filestructure') |
      fileerr:              WriteString('some file error') |
      loaderr:              WriteString('some load error') 
    ELSE WriteString(' linker error') 
    END;
    WriteLn; 
  END Error;

  PROCEDURE WriteModuleName(str: ARRAY OF CHAR);
    VAR ch: CHAR; i: CARDINAL;
  BEGIN
    i := 0;
    LOOP
      IF i > HIGH(str) THEN EXIT END;
      ch := str[i]; INC(i);
      IF (ch < 40C) OR (177C <= ch) THEN EXIT END;
      Write(ch)
    END;
    WHILE i < modidsize DO Write(' '); INC(i) END;
  END WriteModuleName;

  
  PROCEDURE InsertModule(VAR modnam: ModuleName);
  BEGIN
    IF importtop >= imports THEN Error(loaderr) 
    ELSE importlist[importtop] := modnam; INC(importtop) 
    END;
  END InsertModule;

 
  PROCEDURE DeleteModule(importno: ImportIndex); 
    VAR c: CARDINAL; mn: ModuleName;
  BEGIN
    mn := importlist[importno];
    c := importno;
    WHILE c > handledtop DO
      DEC(c);
      importlist[c + 1] := importlist[c]; 
    END;
    importlist[handledtop] := mn;
    INC(handledtop); 
    IF importsearchtop <= importno THEN INC(importsearchtop) END;
  END DeleteModule; 
 
 
  PROCEDURE LoadFile(VAR inf: File; prog: BOOLEAN);

    TYPE 
      Symbol = (eofsy, codekeysy, modulesy, importsy,
                ctext, dtext, fixup);
      SymbolSet = SET OF Symbol;
 
 
    MODULE InCode;
 
      IMPORT
        File, inf, ReadWord, 
        Symbol, 
        Error,
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
        ELSE DEC(fs); ReadWord(inf, n);
          IF inf.eof THEN n := 0 END;
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
        IF inf.eof THEN sy := eofsy 
        ELSIF (200B <= n) AND (n <= 205B) THEN  
          sy := Symbol(n - 177B); 
          fs := 1; 
          Getnum(fs);
          IF inf.eof THEN
            Error(filestructureerr); sy := eofsy;
          END; 
        ELSE Error(filestructureerr); sy := eofsy; 
        END;
      END Getsy; 

    BEGIN
      fs := 0;
    END InCode; 

        
    MODULE OutCode;

      IMPORT outf, WriteWord, Symbol;

      EXPORT Putsy, Putnum;

      PROCEDURE Putnum(num: CARDINAL);
      BEGIN
        WriteWord(outf, num);
      END Putnum;

      PROCEDURE Putsy(sy: Symbol; fs: CARDINAL);
      BEGIN
        WriteWord(outf, CARDINAL(sy) + 177B);
        WriteWord(outf, fs);
      END Putsy;

    END OutCode;


    PROCEDURE LoadModule(prog: BOOLEAN);

      TYPE
        ModuleNamePtr = POINTER TO ModuleName;
 
      VAR
        found, compatible: BOOLEAN; 
        imported: BOOLEAN; 
        importno: ImportIndex; 
 
 
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


      PROCEDURE Putmn(mn: ModuleName);
        VAR c: CARDINAL;
      BEGIN
        WITH mn DO
          FOR c := 0 TO modidsize-1 BY 2 DO
            Putnum(CARDINAL(ident[c])*400B + CARDINAL(ident[c+1]));
          END;
          FOR c := 0 TO keysize-1 DO Putnum(key[c]) END;
        END;
      END Putmn;


      PROCEDURE CopyFrame;
        VAR c: CARDINAL;
      BEGIN
        WHILE fs > 0 DO Getnum(c); Putnum(c) END
      END CopyFrame;


      PROCEDURE PutGetsy;
      BEGIN
        Putsy(sy, fs); CopyFrame; Getsy;
      END PutGetsy;
 
 
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
 
 
      PROCEDURE Find(VAR mn: ModuleName); 
 
        (*  Find searches module mn under the modules in the 
            importlist and under the already loaded modules. 
            The result is returend into the following variables: 
              found, compatible, imported, importno.            *)
 
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
          Equal(mn, importlist[c], found, compatible); 
        END; 
        imported := found AND (c >= handledtop);
        IF found THEN 
          importno := c; 
        ELSE 
          c := moduletop;
          WHILE NOT found AND (c > 0) DO  
            DEC(c); 
            IF dft[c] <> niladdress THEN
              cp := CardPtr(dft[c]);
              mnp := ModuleNamePtr(cp^*2 - TSIZE(ModuleName));
              Equal(mn, mnp^, found, compatible); 
            END; 
          END; 
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
        ELSE Error(codekeyerr)
        END;
      END CodeKey;
  
  
      PROCEDURE ModuleHeader; 
             
        VAR 
          modnam: ModuleName;
          mnptr: ModuleNamePtr; 
          modno: ModuleNumber; 
          datasize: CARDINAL;
          ch: CHAR;
 
      BEGIN
        IF (fs <> 12) AND (fs <> 14) THEN Error(filestructureerr); Skip;
        ELSE
          Getmn(modnam); Getnum(datasize);
          Skip; (* two supplementary words: codesize and flags *)
          Getsy;
          IF prog THEN InsertModule(modnam) END; 
          Find(modnam);
          IF found THEN 
            IF imported THEN
              WriteString('      ');
              WriteModuleName(modnam.ident);
              IF compatible THEN (* load the module *)
                IF query AND NOT prog THEN
                  WriteString(' ?  ');
                  LOOP
                    Read(ch);
                    IF (ch = 'n') OR (ch = 'N') THEN
                      WriteString('no');
                      SkipModule;
                      EXIT;
                    ELSIF ch = esc THEN
                      WriteString('escaped');
                      REPEAT SkipModule UNTIL sy=eofsy;
                      escaped := TRUE;
                      EXIT;  
                    ELSIF (ch = 'y') OR (ch = 'Y') OR (ch = eol) THEN
                      WriteString('yes'); 
                      Putsy(codekeysy, 1); Putnum(codekey);
                      Putsy(modulesy, 12);
                      Putmn(modnam);  Putnum(datasize);
                      DeleteModule(importno);
                      EXIT;
                    END
                  END;
                ELSE
                  Putsy(codekeysy, 1); Putnum(codekey);
                  Putsy(modulesy, 12);
                  Putmn(modnam); Putnum(datasize);
                  DeleteModule(importno);
                END; 
              ELSE
                Error(incompatiblefound);
                SkipModule;
                DeleteModule(importno);
              END;
              WriteLn;
            ELSE
              SkipModule;
            END; (* IF imported *)
          ELSE SkipModule;
          END; (* IF found *)
        END;
      END ModuleHeader;
 
 
      PROCEDURE Imports; 
        VAR mn: ModuleName;
      BEGIN
        Putsy(sy, fs); 
        WHILE fs >= 11 DO (* size of a modulename *)
          Getmn(mn); Putmn(mn);
          Find(mn);
          IF found THEN 
            IF NOT compatible THEN
              Error(incompatibleimport);
              WriteString('  ----   ');
              WriteString(mn.ident);
              WriteLn;
            END; 
          ELSE InsertModule(mn) 
          END;   
        END; 
        Getsy;
      END Imports; 
 

    BEGIN
      (* modulesy or codekeysy has always been read *) 
      CodeKey;
      IF (state=normal) AND (sy=modulesy) THEN ModuleHeader END; 
      IF (sy=importsy) AND (state=normal) THEN Imports END; 
      WHILE (state=normal) AND ((sy=ctext) OR (sy=dtext)) DO 
        IF sy = ctext THEN 
          PutGetsy;
          IF sy = fixup THEN PutGetsy END;
        ELSE PutGetsy;
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
  handledtop := 0; importtop := 0; importsearchtop := 0;
  state := normal; 
  escaped := FALSE;
       
  WriteString(' Linker V3.4 for Medos-2'); WriteLn;
  str := 'object file'; ext := 'OBJ';
  LOOP
    LookupFile(str, ext, progfno, TRUE, FALSE, TRUE, progfn, ok);
    IF ok THEN
      query := FALSE;
      GetFileFromPool(progfno, progfptr, err);
      LOOP
        GetOption(optstr, optlgth);
        IF optlgth = 0 THEN EXIT END;
        IF CAP(optstr[0]) = 'Q' THEN query := TRUE
        ELSE ok := FALSE
        END;
      END;
      IF ok THEN EXIT
      ELSE 
        Close(progfptr^);
        ReturnFileToPool(progfptr);
      END;
    ELSE EXIT
    END;
  END;
  IF ok THEN
    Create(outf, 'DK');
    ok := outf.res = done;
    IF ok THEN
      LoadFile(progfptr^, TRUE);
      WHILE (importsearchtop < importtop) AND NOT escaped DO
        LookupFile(importlist[importsearchtop].ident, ext, infno,
                   query, TRUE, FALSE, infn, ok);
        INC(importsearchtop);
        IF ok THEN
          GetFileFromPool(infno, infptr, err);
          LoadFile(infptr^, FALSE);
          Close(infptr^);
          ReturnFileToPool(infptr);
        END;
      END;
      IF (state=normal) AND NOT escaped THEN
        Reset(progfptr^); Reset(outf);
        LOOP
          ReadWord(outf, c);
          IF outf.eof THEN EXIT END;
          WriteWord(progfptr^, c);
        END;
      END;
      Close(outf)
    END;
    Close(progfptr^);
  END;
  IF (state <> normal) OR escaped THEN
    WriteString(' ----  linkage unsuccessful');
    WriteLn; 
  END;
  WriteString(' end of linkage'); WriteLn;
END Linker.

