(****************************************
*                                       *
*     MODULA-2 Multi-Pass Compiler      *
*     ****************************      *
*                                       *
*     Implementation for Lilith         *
*                                       *
*     running on Lilith Computer        *
*                                       *
*                                       *
*     MCInit:                           *
*                                       *
*     initialisation part               *
*     of the Modula-2 compiler          *
*                                       *
*     Version C19 of 22.07.82           *
*                                       *
*     Institut fuer Informatik          *
*     ETH-Zuerich                       *
*     CH-8092 Zuerich                   *
*                                       *
****************************************)

MODULE MCInit;   (* LG *)

  FROM Monitor IMPORT Time, GetTime;
  FROM CompFile IMPORT File, Create, Delete, Close;
  FROM Options IMPORT GetOption;
  FROM FileNames IMPORT Identifiers, IdentifierPosition;
  FROM WriteStrings IMPORT WriteString, WriteLn;
  FROM MCLookup IMPORT LookupFile;
  FROM MCPublic IMPORT
    il1File, il2File, ascFile,
    modFile, lstFile, symFile, refFile, objFile,
    Compilerstatus, Statset, compstat,
    Filetype, Fileset, openfiles,
    comptime, symfileextension;

  CONST
    null = 0C;
    optionlength = 10;

  TYPE
    OptionKind = (nooption,
                  query, noquery,  (* explicit query for symbol files *)
                  list, nolist,    (* generation of a listing file *)
                  small, large,    (* size of compiled module, work files in memory *)
                  version,         (* display of compiler version *)
                  illegal);
    OptionText = ARRAY [0 .. optionlength-1] OF CHAR;
    Option = RECORD
               minlength : CARDINAL;
               maxlength : CARDINAL;
               text : OptionText;
             END;

  VAR
    compiling : BOOLEAN; (* compiler may run *)
    newtime : Time;
    options : ARRAY OptionKind OF Option;
    qopt, mopt, lopt, vopt : OptionKind;

  PROCEDURE InitOption(optkind: OptionKind; opttext: OptionText;
                       min, max: CARDINAL);
  BEGIN
    WITH options[optkind] DO
      text := opttext;
      minlength := min;
      maxlength := max;
    END;
  END InitOption;

  PROCEDURE InterpreteOptions(VAR illegaloptions: BOOLEAN);
    VAR opttext : OptionText;
        optlength : CARDINAL;
        optkind : OptionKind;

    PROCEDURE FindOption(VAR opttext: OptionText; optlength: CARDINAL;
                         VAR optkind: OptionKind);
      VAR opk : OptionKind;
          found : BOOLEAN;
          ix : CARDINAL;
    BEGIN
      opk := nooption; INC(opk);
      found := FALSE;
      WHILE NOT found AND (opk < illegal) DO
        WITH options[opk] DO
          IF (minlength<=optlength) AND (optlength<=maxlength) THEN
            ix := 0;
            WHILE (ix < optlength) AND (opttext[ix] = text[ix]) DO
              INC(ix);
            END;
            found := ix = optlength;
          END;
        END;
        IF NOT found THEN INC(opk) END;
      END;
      optkind := opk;
    END FindOption;

  BEGIN (* InterpreteOptions *)
    illegaloptions := FALSE;
    GetOption(opttext,optlength);
    WHILE optlength > 0 DO
      FindOption(opttext,optlength,optkind);
      CASE optkind OF
        query, noquery : qopt := optkind;
       |small, large : mopt := optkind;
       |list, nolist : lopt := optkind;
       |version : vopt := optkind;
       |illegal :
          WriteString(" ---- illegal option: ");
          WriteString(opttext);
          WriteLn;
          illegaloptions := TRUE;
      END; (* CASE *)
      GetOption(opttext,optlength);
    END;
  END InterpreteOptions;

  PROCEDURE InitCompilation;

    CONST
      namelength = 32;

    TYPE
      String = ARRAY [0..19] OF CHAR;
      FileName = ARRAY [0 .. namelength - 1] OF CHAR;

    VAR
      prompt, extension : String;
      done : BOOLEAN;
      illegal : BOOLEAN;
      idents : CARDINAL;
      extpos : CARDINAL;
      modName : FileName;
      workName : FileName;
      symName : FileName;
      refName : FileName;
      objName : FileName;
      lstName : FileName;

    PROCEDURE CreateFile(VAR f: File; name: FileName; ft: Filetype);
      VAR done : BOOLEAN;
    BEGIN
      Create(f,name,done);
      IF done THEN
        INCL(openfiles,ft);
      ELSE
        compiling := FALSE;
        WriteString(" ---- file creation failed : ");
        WriteString(name);
        WriteLn;
      END;
    END CreateFile;

    PROCEDURE ReturnFile(f: File; done, close: BOOLEAN);
    BEGIN
      IF done THEN
        IF close THEN Close(f,done);
        ELSE Delete(f,done);
        END;
      END;
    END ReturnFile;

    PROCEDURE FixName(ext: ARRAY OF CHAR; VAR fname: FileName);
      VAR ix, pos : CARDINAL;
    BEGIN
      ix := 0;
      pos := extpos;
      fname := modName;
      WHILE (ix <= HIGH(ext)) AND (ext[ix] <> null) AND
            (pos <= HIGH(fname)) DO
        fname[pos] := ext[ix];
        INC(pos);
        INC(ix);
      END;
      IF pos <= HIGH(fname) THEN fname[pos] := null END;
    END FixName;

  BEGIN
    (* get compilation time *)
    GetTime(newtime);
    WITH newtime DO
      comptime[0] := day;
      comptime[1] := minute;
      comptime[2] := millisecond;
    END;
    prompt := "source file";
    extension := "MOD";
    (* read source file name *)
    LOOP
      (* reset options *)
      qopt := noquery;
      mopt := small;
      lopt := list;
      vopt := nooption;
      (* lookup for source file *)
      LookupFile(prompt,"",extension,modFile,TRUE,FALSE,TRUE,modName,done);
      IF done THEN
        InterpreteOptions(illegal);
        IF NOT illegal THEN (* test on device and extension *)
          idents := Identifiers(modName);
          IF idents >= 2 THEN
            extpos := IdentifierPosition(modName,idents - 1);
            IF (IdentifierPosition(modName,1) <> 3) OR 
               (modName[0] <> 'D') OR (modName[1] <> 'K') THEN
              illegal := TRUE;
              WriteString(" ---- illegal device");
              WriteLn;
            END;
          ELSE
            illegal := TRUE;
            WriteString(" ---- extension missing");
            WriteLn;
          END;
        END;
        IF illegal THEN
          Close(modFile,done);
        ELSE
          compiling := TRUE;
          INCL(openfiles,mod);
          EXIT;
        END;
      ELSE
        compiling := FALSE;
        WriteString(" ---- no compilation");
        WriteLn;
        EXIT;
      END;
    END; (* LOOP *)
  
    IF compiling THEN
      (* use option information *)
      IF qopt = query THEN INCL(compstat,querys) END;
      IF mopt = small THEN workName := "MF.work" ELSE workName := "DK.work" END;
      IF lopt = list THEN INCL(compstat,listings) END;
      IF vopt = version THEN (* display version information *)
        WriteString(" Modula-2 compiler for Lilith");
        WriteLn;
        WriteString(" version C19 of July 1982");
        WriteLn;
        WriteString(" for operating system Medos-2 V4");
        WriteLn;
        WriteString(" running on Lilith");
        WriteLn;
      END;
      (* fix file names of generated files with new extensions *)
      symfileextension := "SYM";
      FixName(symfileextension,symName);
      FixName("REF",refName);
      FixName("OBJ",objName);
      FixName("LST",lstName);
      (* create compiler work files *)
      CreateFile(il1File,workName,il1); (* interpass file *)
      CreateFile(il2File,workName,il2); (* interpass file *)
      CreateFile(ascFile,workName,asc); (* identifier table file *)
      (* create generated files *)
      CreateFile(symFile,symName,sym); (* symbol file *)
      CreateFile(refFile,refName,ref); (* reference file *)
      CreateFile(objFile,objName,obj); (* object code file *)
      IF lopt = list THEN CreateFile(lstFile,lstName,lst) END; (* listing file *)
    END;
  END InitCompilation;

BEGIN (* MCInit *)
  InitOption(query,"QUERY",1,5);
  InitOption(noquery,"NOQUERY",3,7);
  InitOption(small,"SMALL",2,5);
  InitOption(large,"LARGE",2,5);
  InitOption(list,"LISTING",4,7);
  InitOption(nolist,"NOLISTING",1,9);
  InitOption(version,"VERSION",1,7);
  InitCompilation;
  IF compiling THEN INCL(compstat,compiles) END;
END MCInit.
