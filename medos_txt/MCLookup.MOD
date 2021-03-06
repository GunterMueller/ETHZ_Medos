(****************************************
*                                       *
*     MODULA-2 Multi-Pass Compiler      *
*     ****************************      *
*                                       *
*     Implementation for Lilith         *
*                                       *
*                                       *
*     MCLookup:                         *
*                                       *
*     Lookup on files according to      *
*     different searching strategies    *
*                                       *
*     Version C19 of 23.07.82           *
*                                       *
*     Institut fuer Informatik          *
*     ETH-Zuerich                       *
*     CH-8092 Zuerich                   *
*                                       *
****************************************)

IMPLEMENTATION MODULE MCLookup;    (* LG *)
  (* $T- *)

  FROM CompFile IMPORT File, Open;
  FROM Options IMPORT FileNameAndOptions, Termination;
  FROM Terminal IMPORT Write, WriteString, WriteLn;

  CONST null = 0C;  (* null character *)

  PROCEDURE LookupFile(prompt: ARRAY OF CHAR;
                       name: ARRAY OF CHAR;
                       defext: ARRAY OF CHAR;
                       VAR file: File;
                       query, acceptdefault, acceptoptions: BOOLEAN;
                       VAR acceptedfilename: ARRAY OF CHAR;
                       VAR goodfile: BOOLEAN);

    (* prompt        : string is displayed on terminal *)
    (* name          : for construction of a default file name *)
    (* defext        : default extension of searched file *)
    (* file          : opened file *)
    (* query         : explicit asking for file name *)
    (* acceptdefault : accept a default file name *)
    (* acceptoptions : accept options appended to file name *)
    (*                 options are not evaluated *)
    (* goodfile      : lookup was successful *)

    CONST namelength = 32;

    TYPE Text = ARRAY [0..15] OF CHAR;
         FileName = ARRAY [0 .. namelength - 1] OF CHAR;

    VAR dname, fname : FileName;
        termstat : Termination;
        ix, hix : CARDINAL;
        searching : BOOLEAN;
        cancel : BOOLEAN;
        lookup, default : BOOLEAN;
        done : BOOLEAN;

    PROCEDURE ErrorMessage(mess: Text);
    BEGIN
      WriteLn;
      WriteString("  ---- ");
      WriteString(mess);
    END ErrorMessage;

  BEGIN
    (* initialisation *)
    searching := TRUE;
    goodfile := FALSE;
    (* generate default filename *)
    dname := "DK.";
    ix := 3;
    IF acceptdefault THEN
      hix := 0;
      WHILE (hix < 16) AND (hix <= HIGH(name)) AND (name[hix] <> null) DO
        dname[ix] := name[hix];
        INC(hix);
        INC(ix);
      END;
    END;
    dname[ix] := "."; INC(ix);
    hix := 0;
    WHILE (ix <= HIGH(dname)) AND (hix <= HIGH(defext)) AND
          (defext[hix] <> null) DO
      dname[ix] := defext[hix];
      INC(ix); INC(hix);
    END;
    WHILE ix <= HIGH(dname) DO dname[ix] := null; INC(ix) END;
    (* search file *)
    WHILE searching DO
      Write(' '); 
      WriteString(prompt);
      lookup := FALSE;
      IF query THEN
        Write('>'); Write(' ');
        FileNameAndOptions(dname,fname,termstat,acceptoptions);
        IF termstat = normal THEN
          lookup := TRUE; default := FALSE;
        ELSIF termstat = esc THEN
          searching := FALSE;
        ELSIF termstat = empty THEN
          IF acceptdefault THEN 
            lookup := TRUE; default := TRUE;
            fname := dname;
          ELSE
            ErrorMessage("no default file");
          END;
        END;
      ELSE (* NOT query *)
        Write(':'); Write(' ');
        lookup := TRUE; default := TRUE;
        fname := dname;
        searching := FALSE; (* go ahead when file not found *)
      END;
      IF lookup THEN
        IF default THEN
          fname := dname;
        END;
        Open(file,fname,done);
        IF default AND NOT done THEN
          fname := "DK.LIB.";
          ix := 7; hix := 3;
          WHILE ix <= HIGH(fname) DO
            fname[ix] := dname[hix];
            INC(ix); INC(hix);
          END;
          Open(file,fname,done);
        END;
        IF done THEN (* file found *)
          IF default THEN (* write file name *)
            WriteString(fname);
          END;
          goodfile := TRUE;
          searching := FALSE;
        ELSE
          IF default THEN ErrorMessage("no file found");
          ELSE ErrorMessage("file not found");
          END;
        END;
      END;
      WriteLn;
    END;  (* WHILE *)
    IF goodfile THEN
      ix := 0;
      WHILE (ix <= HIGH(fname)) AND (ix <= HIGH(acceptedfilename)) DO
        acceptedfilename[ix] := fname[ix];
        INC(ix);
      END;
      IF ix <= HIGH(acceptedfilename) THEN
        acceptedfilename[ix] := null;
      END;
    END;
  END LookupFile;   

  (* $T= *)
END MCLookup.
