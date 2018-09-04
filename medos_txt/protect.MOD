MODULE DelProtUnprot;                     (* LG 26.08.82 *)

  FROM FileSystem IMPORT
    File, Rename, Close, Response,
    Command, FileCommand, DirectoryCommand;
  FROM NameSearch IMPORT FindNames, NextName;
  FROM Options IMPORT FileNameAndOptions, GetOption, Termination;
  FROM Terminal IMPORT Read, Write, WriteString, WriteLn;

  TYPE
    OperationKind = (DELETE, PROTECT, UNPROTECT);

  CONST
    operation = PROTECT;  (* choose one of the constants of OperationKind *)

  CONST
    optionlength = 10;
    devicelength = 8;
    namelength = 24;

  TYPE
    OptionKind = (nooption,
                  query, noquery,
                  equal, noequal,
                  continue, terminate,
                  illegal);
    OptionText = ARRAY [0 .. optionlength-1] OF CHAR;
    Option = RECORD
               minlength : CARDINAL;
               maxlength : CARDINAL;
               text : OptionText;
             END;
    DeviceName = ARRAY [0 .. devicelength - 1] OF CHAR;
    FileName = ARRAY [0 .. namelength - 1] OF CHAR;
    NameDescriptor = RECORD
                       name : FileName;
                       device : DeviceName;
                       len : CARDINAL;
                     END;

  VAR
    search : NameDescriptor;
    proceed : BOOLEAN;
    count : CARDINAL;
    options : ARRAY OptionKind OF Option;
    queryopt, equalopt, termopt : OptionKind;

  PROCEDURE InitOption(optkind: OptionKind; opttext: OptionText;
                       min, max: CARDINAL);
  BEGIN (* InitOption *)
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
    BEGIN (* FindOption *)
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
    GetOption(opttext, optlength);
    WHILE optlength > 0 DO
      FindOption(opttext, optlength, optkind);
      CASE optkind OF
        query, noquery : queryopt := optkind;
      | equal, noequal : equalopt := optkind;
      | continue, terminate : termopt := optkind;
      | illegal :
          WriteString(" ---- illegal option: ");
          WriteString(opttext);
          WriteLn;
          illegaloptions := TRUE;
      END; (* CASE *)
      GetOption(opttext, optlength);
    END;
  END InterpreteOptions;

  PROCEDURE AllNames;

    VAR
      f : File;
      fRes : Response;
      found : FileName;
      number, version : CARDINAL;
      ok : BOOLEAN;
      state : (normalyes, normalno, nottouch, prot, notprot, badfile, opfail);

    PROCEDURE WriteRes(resp: Response);
    BEGIN (* WriteRes *)
      WriteString(" : ");
      CASE resp OF
        done : WriteString("done");
      | notdone : WriteString("not done");
      | notsupported : WriteString("not supported");
      | callerror : WriteString("calling error");
      | unknownmedium : WriteString("unknown medium");
      | unknownfile : WriteString("unknown file");
      | paramerror : WriteString("parameter error");
      | toomanyfiles : WriteString("too many files");
      | eom : WriteString("end of medium");
      | deviceoff : WriteString("device off");
      | softparityerror : WriteString("memory parity error");
      | softprotected : WriteString("software protected");
      | softerror : WriteString("software error");
      | hardparityerror : WriteString("disk parity error");
      | hardprotected : WriteString("protected pack");
      | timeout : WriteString("timeout");
      | harderror : WriteString("hardware error");
      END; (* CASE *)
    END WriteRes;

    PROCEDURE AcceptYesNo;
      CONST eol = 36C;
            escape = 33C;
      VAR ch : CHAR;
    BEGIN (* AcceptYesNo *)
      LOOP
        Read(ch);
        IF (ch = 'y') OR (ch = 'Y') THEN state := normalyes; EXIT;
        ELSIF (ch = 'n') OR (ch = 'N') THEN state := normalno; EXIT;
        ELSIF ch = eol THEN state := normalno; EXIT;
        ELSIF ch = escape THEN state := normalno; proceed := FALSE; EXIT;
        END;
      END; (* LOOP *)
      IF state = normalyes THEN WriteString("yes");
      ELSE WriteString("no");
      END;
    END AcceptYesNo;

  BEGIN (* AllNames *)
    FindNames(search.device,  search.name, equalopt=equal);
    NextName(ok, found, number, version);
    WHILE proceed AND ok DO
      INC(count);
      WriteString("  ");
      WriteString(found);
      IF number >= 9 THEN state := normalyes;
      ELSE state := nottouch;
      END;
      IF state = normalyes THEN
        (* look for protection *)
        WITH f DO
          com := open;
          fileno := number;
          versionno := version;
          DirectoryCommand(f, search.device);
          IF res = done THEN
            com := getprotect;
            FileCommand(f);
            IF res <> done THEN
              state := badfile;
              fRes := res;
            ELSIF (operation = UNPROTECT) THEN
              IF NOT wrprotect THEN state := notprot END;
            ELSIF wrprotect THEN
              state := prot;
            END;
            IF state <> normalyes THEN Close(f) END;
          ELSE
            state := badfile;
            fRes := res;
          END;
        END; (* WITH *)
      END;
      IF state = normalyes THEN
        IF queryopt = query THEN
          IF operation = DELETE THEN WriteString(" delete? ");
          ELSIF operation = PROTECT THEN WriteString(" protect? ");
          ELSE WriteString(" unprotect? ");
          END;
          AcceptYesNo;
        END;
        IF state = normalyes THEN
          IF operation = DELETE THEN
            Rename(f, search.device);
          ELSE
            f.com := setprotect;
            f.wrprotect := operation = PROTECT;
            FileCommand(f);
          END;
          IF f.res <> done THEN state := opfail; fRes := f.res END;
        END;
        Close(f);
      ELSIF state = prot THEN
        WriteString(" - protected");
      ELSIF state = notprot THEN
        WriteString(" - not protected");
      ELSIF state = nottouch THEN
        WriteString(" - not touched");
      END;
      WriteLn;
      IF state >= badfile THEN
        WriteString(" ---- ");
        CASE state OF
          badfile : WriteString("bad file"); WriteRes(fRes);
        | opfail :
            IF operation = DELETE THEN WriteString("delete");
            ELSIF operation = PROTECT THEN WriteString("protect");
            ELSE WriteString("unprotect");
            END;
            WriteString(" operation failed");
            WriteRes(fRes);
        END;
        WriteLn;
      END;
      IF proceed THEN NextName(ok, found, number, version) END;
    END;
  END AllNames;

  PROCEDURE InputControl(display: ARRAY OF CHAR; VAR desc: NameDescriptor);
    CONST
      default = "DK.*.*";

    VAR
      termstat : Termination;
      cancel : BOOLEAN;
      oldqueryopt, oldequalopt, oldtermopt : OptionKind;
      inputName : ARRAY[0 .. devicelength + namelength - 1] OF CHAR;

    PROCEDURE SplitName;
      VAR ch : CHAR;
          ix : CARDINAL;
    BEGIN (* SplitName *)
      WITH desc DO
        ix := 0;
        (* copy device *)
        len := 0;
        LOOP
          IF len >= HIGH(device) THEN cancel := TRUE; EXIT END;
          ch := inputName[ix];
          INC(ix);
          IF (ch = '*') OR (ch = '%') OR (ch = 0C) THEN cancel := TRUE; EXIT END;
          IF ch = '.' THEN
            device[len] := 0C;
            EXIT;
          ELSE
            device[len] := ch;
            INC(len);
          END;
        END; (* LOOP *)
        (* copy name *)
        len := 0;
        LOOP
          IF len > HIGH(name) THEN EXIT END;
          IF ix > HIGH(inputName) THEN ch := 0C ELSE ch := inputName[ix] END;
          INC(ix);
          name[len] := ch;
          IF ch = 0C THEN EXIT END;
          INC(len);
        END; (* LOOP *)
      END; (* WITH *)
      IF cancel THEN
        WriteString(" ---- illegal device");
        WriteLn;
      END;
    END SplitName;

  BEGIN (* InputControl *)
    IF proceed THEN
      oldqueryopt := queryopt;
      oldequalopt := equalopt;
      oldtermopt := termopt;
      WITH desc DO
        LOOP
          WriteString(display);
          FileNameAndOptions(default, inputName, termstat, TRUE);
          WriteLn;
          IF termstat = normal THEN
            queryopt := oldqueryopt;
            equalopt := oldequalopt;
            termopt := oldtermopt;
            InterpreteOptions(cancel);
            IF NOT cancel THEN SplitName END;
            IF NOT cancel THEN EXIT END;
          ELSIF termstat = esc THEN
            proceed := FALSE; EXIT;
          END;
        END; (* LOOP *)
      END; (* WITH *)
    END;
  END InputControl;

BEGIN (* DelProtUnprot *)
  InitOption(query, "QUERY", 1, 5);
  InitOption(noquery, "NOQUERY", 3, 7);
  InitOption(equal, "EQUAL", 1, 5);
  InitOption(noequal, "NOEQUAL", 3, 7);
  InitOption(continue, "CONTINUE", 1, 8);
  InitOption(terminate, "TERMINATE", 1, 9);
  LOOP
    proceed := TRUE;
    queryopt := query;
    equalopt := noequal;
    termopt := terminate;
    IF operation = DELETE THEN InputControl(" delete> ", search);
    ELSIF operation = PROTECT THEN InputControl(" protect> ", search);
    ELSE InputControl(" unprotect> ", search);
    END;
    IF NOT proceed THEN EXIT END;
    WriteString(" operating on device :   ");
    WriteString(search.device);
    WriteLn;
    count := 0;
    AllNames;
    IF count = 0 THEN
      WriteString(" ---- no file found");
      WriteLn;
    END;
    IF termopt = terminate THEN EXIT END;
  END; (* LOOP *)
END DelProtUnprot.
