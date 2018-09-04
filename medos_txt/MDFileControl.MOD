IMPLEMENTATION MODULE MDFileControl; (*Ch. Jacobi 6.6.81*)
  FROM Terminal IMPORT Read, Write, WriteLn, WriteString;
  FROM FileSystem IMPORT File, Response, Lookup, Close, Reset, SetRead;
  FROM FileMessage IMPORT WriteResponse;
  FROM FileNames IMPORT ReadFileName;

  FROM MDModuleHandler IMPORT modTab, modLoaded;

(*  (*$T-*) (*$R-*) *)

  CONST 
    maxMod = 127;
    ESC = 33C; 


  TYPE
    FileName = ARRAY [0..27] OF CHAR;
    NameRecord = 
      RECORD
        init, exist: BOOLEAN;
        name: FileName;
      END;
    
  VAR 
    fnames: ARRAY [0..maxMod] , FileType OF NameRecord;
              
    i: CARDINAL;
    openedF: ARRAY FileType OF CARDINAL;
    ext: ARRAY FileType OF 
           ARRAY [0..2] OF CHAR;
    temname: FileName;
    ch: CHAR;


  PROCEDURE BuildDefFileName(VAR fn: FileName; name, extension: ARRAY OF CHAR);
    (* extension must be ARRAY 0..2 ! *)
    VAR i, highfn: CARDINAL; full: BOOLEAN;
  BEGIN 
    fn[0]:= 'D'; fn[1]:= 'K'; fn[2] := '.'; i := 0;
    LOOP
      IF (name[i]=0C) OR (name[i]=" ") THEN EXIT END;
      fn[i+3]:= name[i]; 
      INC(i);
      IF (i>HIGH(name)) OR (i>(HIGH(fn)-4-3)) THEN EXIT END;
    END;
    fn[i+3] := '.'; fn[i+4] := extension[0];  
    fn[i+5] := extension[1]; fn[i+6] := extension[2]; 
    IF (i+7) <= HIGH(fn) THEN fn[i+7]:= 0C END;
  END BuildDefFileName;


  PROCEDURE GetFileName(VAR rfn: FileName; dfn: FileName);
    VAR ch: CHAR;
  BEGIN 
    WriteString(" ("); WriteString(dfn); WriteString(") ");
    ReadFileName(rfn, dfn); Read(ch);
    IF ch=ESC THEN rfn[0] := 0C
    ELSIF rfn[0]=0C THEN rfn := dfn
    END
  END GetFileName;


  PROCEDURE OpenFile(moduleNumber: CARDINAL;
                     fileType: FileType; VAR new: BOOLEAN);
    VAR ok: BOOLEAN;

    PROCEDURE OpenAFile(VAR f: File; moduleNumber: CARDINAL;
                        fileType: FileType; VAR nr: NameRecord; 
                        new: BOOLEAN);
    BEGIN
      new := openedF[fileType]<>moduleNumber;
      IF new THEN
        Close(f);
        WITH nr DO
          IF init THEN 
            IF exist THEN
              Lookup(f, name, FALSE); 
              IF f.res=done THEN ok := TRUE
              ELSE
                WriteString("-- file not attached:"); 
                WriteString(name); WriteLn;
              END
            END;
          ELSE (*not init*)
            init := TRUE;
            BuildDefFileName(temname, modTab[moduleNumber]^.modName, ext[fileType]);
            IF query THEN
              LOOP
                CASE fileType OF
                  reffile: WriteString("reference file for ")|
                  lstfile: WriteString("listing file for ")
                END;
                WriteString(modTab[moduleNumber]^.modName); WriteLn;
                GetFileName(name, temname);
                IF name[0]=0c THEN 
                  WriteString(" no file"); WriteLn;
                  EXIT
                END;
                Lookup(f, name, FALSE); Write(" "); WriteResponse(f.res); WriteLn;
                IF f.res=done THEN
                  ok := TRUE; EXIT
                ELSE
                  WriteString(" -- repeat"); WriteLn;
                END;
              END
            ELSE (*not query*)
              name := temname;
              Lookup(f, name, FALSE);
              WriteString("open "); WriteString(name); Write(" "); 
              WriteResponse(f.res); WriteLn;
              ok := f.res=done
            END;
            exist := ok
          END; (*if init*)
        END;
      ELSE (*not new*)
        ok := TRUE
      END;
      IF ok THEN 
        Reset(f); SetRead(f)
      END
    END OpenAFile;

  BEGIN
    ok := FALSE;
    IF moduleNumber<modLoaded THEN   
      CASE fileType OF
        reffile: OpenAFile(refFile, moduleNumber, fileType,
                   fnames[moduleNumber, fileType], new)|
        lstfile: OpenAFile(lstFile, moduleNumber, fileType, 
                   fnames[moduleNumber, fileType], new)
      END;
    END;
    IF ok THEN openedF[fileType] := moduleNumber
    ELSE openedF[fileType] := maxMod+1
    END;
    CASE fileType OF
      reffile: refOpen := ok|
      lstfile: lstOpen := ok
    END;
  END OpenFile;


BEGIN
  WriteString("ask for ref, lst filenames ? (y/-):");
  Read(ch);
  query := (ch="y") OR (ch="Y");
  IF query THEN WriteString(" yes") ELSE WriteString(" no") END;
  WriteLn;
  refOpen := FALSE;
  lstOpen := FALSE;
  openedF[lstfile] := maxMod+1;
  openedF[reffile] := maxMod+1; 
  ext[lstfile] := "LST";
  ext[reffile] := "REF";
  FOR i := 0 TO maxMod DO
    fnames[i, lstfile].init := FALSE;
    fnames[i, reffile].init := FALSE;
  END
END MDFileControl.




