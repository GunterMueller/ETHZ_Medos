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
*     MCPublic:                         *
*                                       * 
*     public part of the common base    *
*     of the Modula-2 compiler          *
*                                       * 
*     Version C19 of 29.09.82           *
*                                       *
*     Institut fuer Informatik          *
*     ETH-Zuerich                       *
*     CH-8092 Zuerich                   *
*                                       *
****************************************)

IMPLEMENTATION MODULE MCPublic;   (* LG *)

  IMPORT Storage (* for initialisation of storage procedures *),
         MemoryFiles (* for initialisation of memory files *);

  FROM Program IMPORT Status, Call, Terminate; 
  FROM ProgramMessage IMPORT WriteStatus;
  FROM CompFile IMPORT File, Close, Delete;
  FROM WriteStrings IMPORT WriteString, WriteLn;

  TYPE
    Passes = (init, pass1, pass2, pass3, pass4, lister, terminate);
    ProgName = ARRAY [0..23] OF CHAR;

  VAR
    passindicator: Passes;
    exerror : Status;
    message : ARRAY [0..23] OF CHAR;
    prognam : ProgName;
  
  PROCEDURE ReturnFile(VAR f: File; ft: Filetype; close: BOOLEAN);
    VAR
      done : BOOLEAN;
      string : ARRAY [0..2] OF CHAR;
  BEGIN (* ReturnFile *)
    IF ft IN openfiles THEN
      IF close THEN Close(f,done);
      ELSE Delete(f,done);
      END;
      IF NOT done THEN
        IF close THEN
          Delete(f,done);
          WriteString(" ---- not catalogued : ");
        ELSE
          Close(f,done);
          WriteString(" ---- not deleted : ");
        END;
        CASE ft OF
          il1 : string := "il1";
        | il2 : string := "il2";
        | asc : string := "asc";
        | mod : string := "mod";
        | lst : string := "lst";
        | sym : string := "sym";
        | ref : string := "ref";
        | obj : string := "obj";
        END;
        WriteString(string);
        WriteLn;
      END;
    END;
  END ReturnFile;

BEGIN (* MCPublic *)
  compstat := Statset{};
  openfiles := Fileset{};
  passindicator := init;
  LOOP
    CASE passindicator OF
      init:
        message := "Modula-2 Compiler C19";
        prognam := "C19.Init";
    | pass1:
        message := "p1";
        prognam := "C19.Pass1";
    | pass2:
        message := "p2";
        prognam := "C19.Pass2";
    | pass3:
        IF defs IN compstat THEN
          IF globerrs IN compstat THEN (* listing generation *)
            IF listings IN compstat THEN
              message := "lister";
              prognam := "C19.Lister";
              passindicator := terminate;
            ELSE EXIT;
            END;
          ELSE (* symbol file generation *)
            message := "symfile";
            prognam := "C19.Symfile";
          END;
        ELSE
          message := "p3";
          prognam := "C19.Pass3";
        END;
    | pass4:
        IF (globerrs IN compstat) OR (defs IN compstat) THEN (* listing *)
          IF listings IN compstat THEN
            message := "lister";
            prognam := "C19.Lister";
            passindicator := terminate;
          ELSE EXIT;
          END;
        ELSE
          message := "p4";
          prognam := "C19.Pass4";
        END;
    | lister:
        IF listings IN compstat THEN
          message := "lister";
          prognam := "C19.Lister";
          INCL(compstat,finis);
          passindicator := terminate;
        ELSE EXIT;
        END;
    END; (* CASE *)
    WriteString(message);
    WriteLn;
    Call(prognam,TRUE,exerror);
    IF exerror = normal THEN (* Call executed *)
      IF symerrs IN compstat THEN (* stop compilation *)
        WriteString(" ---- symbolfiles missing");
        WriteLn;
        EXCL(compstat,compiles);
        EXIT;
      END;
      IF passerrs IN compstat THEN (* error handling *)
        INCL(compstat,globerrs);
        WriteString(" ---- error");
        WriteLn;
      END;
      IF (passindicator = terminate) OR NOT (compiles IN compstat) THEN EXIT END;
      EXCL(compstat,passerrs);
      INC(passindicator);
    ELSE (* cancel execution *)
      WriteString(" ---- ");
      WriteString(prognam);
      WriteStatus(exerror);
      WriteLn;
      EXCL(compstat,compiles);
      EXIT;
    END;
  END; (* LOOP *)
  (* termination *)
  ReturnFile(il1File,il1,FALSE);
  ReturnFile(il2File,il2,FALSE);
  ReturnFile(ascFile,asc,FALSE);
  ReturnFile(modFile,mod,TRUE);
  ReturnFile(lstFile,lst,compiles IN compstat);
  ReturnFile(symFile,sym,
    compstat*Statset{globerrs,syms,compiles}=Statset{syms,compiles});
  ReturnFile(refFile,ref,
    compstat*Statset{globerrs,defs,compiles}=Statset{compiles});
  ReturnFile(objFile,obj,
    compstat*Statset{globerrs,defs,compiles}=Statset{compiles});
  WriteString("end compilation");
  WriteLn;
  IF exerror <> normal THEN Terminate(warned) END;
END MCPublic.
