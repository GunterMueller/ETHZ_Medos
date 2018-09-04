MODULE CopRen;               (* LG 31.08.82 *)

  FROM SYSTEM IMPORT WORD, ADR;
  FROM FileSystem IMPORT
    File, Response, Command, FileCommand, DirectoryCommand,
    Lookup, Create, Rename, SetRead, SetWrite, SetOpen, Close;
  FROM ByteBlockIO IMPORT ReadBytes, WriteBytes;
  FROM NameSearch IMPORT FindNames, NextName;
  FROM Options IMPORT FileNameAndOptions, GetOption, Termination;
  FROM Terminal IMPORT Read, WriteString, WriteLn;

  TYPE 
    OperationKind = (COPY, RENAME);

  CONST
    operation = COPY;  (* choose one of the constants of OperationKind *)

  CONST
    maxpos = 24;
    optionlength = 10;
    devicelength = 8;
    namelength = 24;
    maxFileNum = 768;
    bits = 16;
    fileTableLength = maxFileNum DIV bits;

  TYPE
    FileName = ARRAY [0 .. namelength - 1] OF CHAR;
    DeviceName = ARRAY [0 .. devicelength - 1] OF CHAR;
    ValueProtocoll = ARRAY [1..maxpos] OF CARDINAL;
    Values = ARRAY [1..maxpos] OF BOOLEAN;
    Positions = ARRAY [0..maxpos] OF CARDINAL;
    NameDescriptor = RECORD
                       name : FileName;
                       device : DeviceName;
                       val : Values;
                       prot : ValueProtocoll;
                       pos : Positions;
                       max : CARDINAL;
                       len : CARDINAL;
                     END;
    OptionKind = (nooption,
                  query, noquery,
                  equal, noequal,
                  replace, noreplace,
                  continue, terminate,
                  illegal);
    OptionText = ARRAY [0 .. optionlength-1] OF CHAR;
    Option = RECORD
               minlength : CARDINAL;
               maxlength : CARDINAL;
               text : OptionText;
             END;

  VAR
    to, from, found : NameDescriptor;
    maxprot : CARDINAL;
    proceed : BOOLEAN;
    matching : BOOLEAN;
    samedevice : BOOLEAN;
    count : CARDINAL;
    options : ARRAY OptionKind OF Option;
    queryopt, equalopt, replopt, termopt : OptionKind;
    fileTable : ARRAY [0..fileTableLength] OF BITSET;
    entertable : BOOLEAN;

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
      | replace, noreplace : replopt := optkind;
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

  PROCEDURE UpdatePositions(VAR ok: BOOLEAN);
    VAR foundpos : Positions;
        ix : CARDINAL;
        uplowEqual : BOOLEAN;

    PROCEDURE Match(fromix, foundix: CARDINAL): BOOLEAN;
      (* check match of strings in fromName and foundName *)
      (* algorithm allows fillers '*' in fromName *)
    BEGIN (* Match *)
      LOOP
        foundpos[fromix] := foundix;
        IF fromix = from.len THEN
          RETURN foundix = found.len;
        END;
        IF from.name[fromix] = '*' THEN
          INC(fromix);
          WHILE foundix <= found.len DO
            IF Match(fromix, foundix) THEN RETURN TRUE END;
            INC(foundix);
          END;
          IF (from.name[fromix]='.') AND ((fromix=1) OR (from.name[fromix-2]='.')) THEN
            (* leading string "*." could be handled as empty *)
            (* or string ".*." could be handled as "." *)
            (* first value of foundix is assigned to foundpos[fromix-1] *)
            IF Match(fromix+1, foundpos[fromix-1]) THEN
              (* update positions in foundpos *)
              IF fromix > 1 THEN
                (* match position of '*' to position of leading '.' *)
                foundpos[fromix-1] := foundpos[fromix-2];
              END;
              (* match position of '.' to position of leading '*' *)
              foundpos[fromix] := foundpos[fromix-1];
              RETURN TRUE;
            END;
          END;
          RETURN FALSE;
        ELSIF foundix = found.len THEN
          IF (from.name[fromix] = '.') AND (fromix + 2 = from.len) THEN INC(fromix);
          ELSE RETURN FALSE;
          END;
        ELSIF (from.name[fromix] = found.name[foundix]) OR
            (from.name[fromix] = '%') OR
            uplowEqual AND (CAP(from.name[fromix]) = CAP(found.name[foundix]))
        THEN
          INC(fromix);
          INC(foundix);
        ELSE RETURN FALSE;
        END;
      END; (* LOOP *)
    END Match;

  BEGIN (* UpdatePositions *)
    uplowEqual := equalopt = equal;
    WITH found DO
      len := 0;
      WHILE (len <= HIGH(name)) AND (name[len] <> ' ') DO INC(len) END;
      ok := Match(0, 0);
      IF ok THEN
        FOR ix := 1 TO from.max DO pos[ix] := foundpos[from.pos[ix]] END;
      END;
    END; (* WITH *)
  END UpdatePositions;

  PROCEDURE MergeNames(VAR merged: FileName; VAR ok: BOOLEAN);
    VAR mix : CARDINAL;
        fp, tp: CARDINAL;
        oldfp, oldtp : CARDINAL;
        ix : CARDINAL;

    PROCEDURE CopyString(VAR name: FileName; start, stop: CARDINAL);
      VAR ix : CARDINAL;
      (* start and stop refer to a (possibly non existent) period *)
      (* or if their value is zero to the beginning of the name *)
      (* copy a part of the name to mergerd if start < stop *)
    BEGIN (* CopyString *)
      ix := start;
      IF ix > 0 THEN INC(ix) END;
      (* ix refers to the beginning of an identifier *)
      IF (mix > 0) AND (ix < stop) THEN
        IF mix >= HIGH(merged) THEN ok := FALSE; (* last character must not be a '.' *)
        ELSE merged[mix] := '.';
        END;
        INC(mix);
      END;
      WHILE (ix < stop) AND ok  DO
        IF mix > HIGH(merged) THEN ok := FALSE;
        ELSE merged[mix] := name[ix];
        END;
        INC(mix);
        INC(ix);
      END;
    END CopyString;

  BEGIN (* MergeNames *)
    ok := TRUE;
    ix := 2;
    oldfp := 1; oldtp := 1;
    mix := 0;
    WHILE ok AND (ix <= maxprot) DO
      fp := from.prot[ix];
      tp := to.prot[ix];
      IF tp - oldtp = 0 THEN (* delete *)
      ELSIF fp - oldfp = 0 THEN (* insert *)
        CopyString(to.name, to.pos[oldtp], to.pos[tp]);
      ELSE
        IF to.val[oldtp] THEN (* keep *)
          CopyString(found.name, found.pos[oldfp], found.pos[fp]);
        ELSE (* replace *)
          CopyString(to.name, to.pos[oldtp], to.pos[tp]);
        END;
      END;
      oldtp := tp;
      oldfp := fp;
      INC(ix);
    END; (* WHILE *)
    WHILE mix <= HIGH(merged) DO merged[mix] := ' '; INC(mix) END;
  END MergeNames;

  PROCEDURE FileOperation(number, version: CARDINAL; VAR merged: FileName);

    CONST
      buffsize = 30000B;

    VAR
      fromFile, toFile : File;
      fromRes, toRes : Response;
      buff : ARRAY [1..buffsize] OF WORD;
      bytenum : CARDINAL;
      constrName : ARRAY [0 .. devicelength + namelength - 1] OF CHAR;
      state : (normalyes, normalno, fromfail, tofail, toprot, tobad, toold, opfail);

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

    PROCEDURE ConstructName(VAR device: DeviceName; VAR name: FileName);
      VAR ix, ix1 : CARDINAL;
    BEGIN (* ConstructName *)
      ix := 0;
      WHILE (ix <= HIGH(device)) AND (device[ix] <> 0C) DO
        constrName[ix] := device[ix];
        INC(ix);
      END;
      constrName[ix] := '.'; INC(ix);
      ix1 := 0;
      WHILE (ix1 <= HIGH(name)) AND (name[ix1] <> ' ') DO
        constrName[ix] := name[ix1];
        INC(ix);
        INC(ix1);
      END;
      IF ix <= HIGH(constrName) THEN constrName[ix] := 0C END;
    END ConstructName;

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

  BEGIN (* FileOperation *)
    WriteString("  ");
    WriteString(found.name);
    WriteString(" to ");
    WriteString(merged);
    IF queryopt = query THEN
      IF operation = COPY THEN WriteString(" copy? ");
      ELSE WriteString(" rename? ");
      END;
      AcceptYesNo;
    ELSE state := normalyes;
    END;
    (* lookup on 'from-file' *)
    IF state = normalyes THEN
      WITH fromFile DO
        fileno := number;
        versionno := version;
        com := open;
        DirectoryCommand(fromFile, from.device);
        IF res <> done THEN
          state := fromfail;
          fromRes := res;
        END;
      END; (* WITH *)
    END;
    ConstructName(to.device, merged);
    (* lookup on 'to-file' *)
    IF state = normalyes THEN
      Lookup(toFile, constrName, FALSE);
      IF toFile.res = done THEN
        IF (replopt = nooption) AND (queryopt = query) THEN
          WriteString(" replace? ");
          AcceptYesNo;
        ELSIF replopt <> replace THEN
          state := toold;
        END;
        (* check protection *)
        IF state = normalyes THEN
          WITH toFile DO
            com := getprotect;
            FileCommand(toFile);
            IF res <> done THEN
              state := tobad;
              toRes := res;
            ELSIF wrprotect THEN
              state := toprot;
            END;
          END; (* WITH *)
        END;
        IF (operation = RENAME) AND (state = normalyes) THEN (* purge 'to-file' *)
          Rename(toFile, to.device);
          IF toFile.res <> done THEN state := tobad; toRes := toFile.res END;
        END;
        IF (operation = RENAME) OR (state <> normalyes) THEN Close(toFile) END;
      ELSIF toFile.res = notdone THEN
        IF operation = COPY THEN
          Create(toFile, to.device);
          IF toFile.res = done THEN
            Rename(toFile, constrName);
            IF toFile.res <> done THEN
              state := tobad;
              toRes := toFile.res;
              Close(toFile);
            END;
          ELSE state := tofail; toRes := toFile.res;
          END;
        END;
      ELSE
        state := tobad; toRes := toFile.res;
      END;
      IF state <> normalyes THEN Close(fromFile) END;
    END;
    (* execution of the operation *)
    IF state = normalyes THEN
      IF operation = COPY THEN
        WITH toFile DO
          com := getinternal;
          FileCommand(toFile);
          IF (res = done) AND entertable THEN
            (* entry of new generated toFile *)
            INCL(fileTable[fileno DIV bits], fileno MOD bits);
          END;
        END; (* WITH *)
        SetRead(fromFile); SetWrite(toFile);
        IF (fromFile.res <> done) OR (toFile.res <> done) THEN state := opfail END;
        WHILE (state = normalyes) AND NOT fromFile.eof DO
          ReadBytes(fromFile, ADR(buff), buffsize*2, bytenum);
          WriteBytes(toFile, ADR(buff), bytenum);
          IF (fromFile.res <> done) OR (toFile.res <> done) THEN state := opfail END;
        END;
        IF state = normalyes THEN
          SetOpen(fromFile); SetOpen(toFile);
          IF (fromFile.res <> done) OR (toFile.res <> done) THEN state := opfail END;
        END;
        IF state <> normalyes THEN fromRes := fromFile.res; toRes := toFile.res END;
        Close(fromFile); Close(toFile);
      ELSIF operation = RENAME THEN
        Rename(fromFile, constrName);
        IF fromFile.res <> done THEN state := opfail; fromRes := fromFile.res END;
        Close(fromFile);
      END;
    END;
    WriteLn;
    IF state > normalno THEN
      WriteString(" ---- ");
      CASE state OF
        fromfail : WriteString("lookup on 'from-file' failed"); WriteRes(fromRes);
      | tofail : WriteString("creation of 'to-file' failed"); WriteRes(toRes);
      | toprot : WriteString("protected 'to-file'");
      | tobad : WriteString("bad 'to-file'"); WriteRes(toRes);
      | toold : WriteString("existing 'to-file' not replaced");
      | opfail :
         IF operation = COPY THEN WriteString("copy") ELSE WriteString("rename") END;
         WriteString(" operation failed");
         IF fromRes <> done THEN WriteString(" 'from-file'"); WriteRes(fromRes) END;
         IF (operation = COPY) AND (toRes <> done) THEN
           WriteString(" 'to-file'"); WriteRes(toRes);
         END;
      END;
      WriteLn;
    END;
  END FileOperation;

  PROCEDURE AllNames;
    VAR
      number, version : CARDINAL;
      ok : BOOLEAN;
      merged : FileName;
      legal : BOOLEAN;
      ix : CARDINAL;
  BEGIN (* AllNames *)
    entertable := samedevice AND (operation = COPY);
    IF entertable THEN
      FOR ix := 0 TO fileTableLength DO fileTable[ix] := {} END;
    END;
    FindNames(from.device, from.name, equalopt=equal);
    NextName(ok, found.name, number, version);
    WHILE proceed AND ok DO
      IF NOT (entertable AND (number MOD bits IN fileTable[number DIV bits])) THEN
        INC(count);
        UpdatePositions(legal);
        IF legal THEN
          MergeNames(merged, legal);
        END;
        IF legal THEN
          FileOperation(number, version, merged);
        ELSE
          WriteString(" ---- illegal new file name derived from: ");
          WriteString(found.name);
          WriteLn;
        END;
      END;
      IF proceed THEN NextName(ok, found.name, number, version) END;
    END; (* WHILE *)
  END AllNames;

  PROCEDURE Analyse(VAR matching, samedevice: BOOLEAN);
    VAR ix : CARDINAL;
        ok : BOOLEAN;

    PROCEDURE MatchValues(frompos, topos, level: CARDINAL): BOOLEAN;
      VAR ix : CARDINAL;
    BEGIN (* MatchValues *)
      LOOP
        maxprot := level;
        to.prot[level] := topos;
        from.prot[level] := frompos;
        INC(level);
        IF topos = to.max THEN
          IF frompos = from.max THEN RETURN TRUE;
          ELSIF from.val[frompos] THEN RETURN FALSE;
          ELSE
            WHILE (frompos < from.max) AND NOT from.val[frompos] DO
              INC(frompos);
            END;
          END;
        ELSIF frompos = from.max THEN
          IF NOT to.val[topos] THEN
            REPEAT INC(topos) UNTIL (topos = to.max) OR to.val[topos];
          ELSE
            RETURN FALSE;
          END;
        ELSIF to.val[topos] THEN
          IF from.val[frompos] THEN
            INC(topos);
            INC(frompos);
            WHILE frompos < from.max DO
              IF MatchValues(frompos, topos, level) THEN RETURN TRUE END;
              INC(frompos);
            END;
          ELSE
            INC(frompos);
            IF MatchValues(frompos, topos + 1, level) THEN
              RETURN TRUE;
            ELSE
              ix := frompos;
              WHILE (ix < from.max) AND NOT from.val[ix] DO INC(ix) END;
              WHILE ix > frompos DO
                IF MatchValues(ix, topos, level) THEN RETURN TRUE END;
                DEC(ix);
              END;
              RETURN MatchValues(frompos, topos, level);
            END;
          END;
        ELSE
          IF from.val[frompos] THEN
            REPEAT INC(topos) UNTIL (topos = to.max) OR to.val[topos];
          ELSE
            ix := frompos;
            REPEAT
              INC(ix); INC(topos);
            UNTIL (ix = from.max) OR from.val[ix] OR (topos = to.max) OR to.val[topos];
            WHILE ix > frompos DO
              IF MatchValues(ix, topos, level) THEN RETURN TRUE END;
              DEC(ix);
            END;
            RETURN MatchValues(frompos, topos, level);
          END;
        END;
      END; (* LOOP *)
    END MatchValues;

    PROCEDURE AnalyseName(VAR desc: NameDescriptor; restricted: BOOLEAN);
      VAR ch : CHAR;
    BEGIN (* AnalyseName *)
      WITH desc DO
        max := 1;
        WHILE max <= maxpos DO
          val[max] := FALSE;
          pos[max] := 0;
          INC(max);
        END;
        len := 0;
        max := 1;
        pos[max] := len;
        WHILE (len <= HIGH(name)) AND (name[len] <> 0C) DO
          ch := name[len];
          IF (ch = '*') OR (ch = '%') THEN
            IF restricted THEN
              IF ch = '%' THEN ok := FALSE;
              ELSIF NOT val[max] THEN
                IF (pos[max] + 1 < len) OR (len = 1) THEN ok := FALSE END;
              END;
            END;
            val[max] := TRUE;
          ELSIF ch = '.' THEN
            INC(max);
            pos[max] := len;
          ELSE
            IF restricted AND val[max] THEN ok := FALSE END;
          END;
          INC(len);
        END;
        INC(max); pos[max] := len;
      END; (* WITH *)
    END AnalyseName;

  BEGIN (* Analyse *)
    ok := TRUE;
    AnalyseName(from, FALSE);
    AnalyseName(to, TRUE);
    matching := ok AND MatchValues(1, 1, 1);
    samedevice := TRUE;
    ix := 0;
    WHILE (ix < HIGH(from.device)) AND (from.device[ix] <> 0C) DO
      IF from.device[ix] <> to.device[ix] THEN samedevice := FALSE END;
      INC(ix);
    END;
    IF (ix < HIGH(from.device)) AND (to.device[ix] <> 0C) THEN samedevice := FALSE END;
    IF (operation = RENAME) AND NOT samedevice THEN
      matching := FALSE;
      WriteString(" ---- incompatible devices");
      WriteLn;
    ELSIF NOT ok THEN
      WriteString(" ---- illegal wildcards in 'to-name'");
      WriteLn;
    ELSIF NOT matching THEN
      WriteString(" ---- file names do not match");
      WriteLn;
    END;
  END Analyse;

  PROCEDURE InputControl(display: ARRAY OF CHAR; VAR desc: NameDescriptor);
    CONST
      default = "DK.*.*";

    VAR
      termstat : Termination;
      cancel : BOOLEAN;
      oldqueryopt, oldequalopt, oldreplopt, oldtermopt : OptionKind;
      inputName : ARRAY [0 .. devicelength + namelength - 1] OF CHAR;

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
      oldreplopt := replopt;
      oldtermopt := termopt;
      WITH desc DO
        LOOP
          WriteString(display);
          FileNameAndOptions(default, inputName, termstat, TRUE);
          WriteLn;
          IF termstat = normal THEN
            queryopt := oldqueryopt;
            equalopt := oldequalopt;
            replopt := oldreplopt;
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

BEGIN (* CopRen *)
  InitOption(query, "QUERY", 1, 5);
  InitOption(noquery, "NOQUERY", 3, 7);
  InitOption(equal, "EQUAL", 1, 5);
  InitOption(noequal, "NOEQUAL", 3, 7);
  InitOption(replace, "REPLACE", 1, 7);
  InitOption(noreplace, "NOREPLACE", 3, 9);
  InitOption(continue, "CONTINUE", 1, 8);
  InitOption(terminate, "TERMINATE", 1, 9);
  LOOP
    proceed := TRUE;
    queryopt := query;
    equalopt := noequal;
    replopt := nooption;
    termopt := terminate;
    IF operation = COPY THEN InputControl(" copy from> ", from);
    ELSE InputControl(" rename from> ", from);
    END;
    LOOP
      InputControl(" to> ", to);
      IF NOT proceed THEN EXIT END;
      Analyse(matching, samedevice);
      IF matching THEN EXIT END;
    END; (* LOOP *) 
    IF NOT proceed THEN EXIT END;
    IF operation = COPY THEN WriteString(" copy");
    ELSE WriteString(" rename");
    END;
    IF samedevice THEN
      WriteString(" on device :  ");
      WriteString(from.device);
    ELSE
      WriteString(" from device :  ");
      WriteString(from.device);
      WriteString("  to device :  ");
      WriteString(to.device);
    END;
    WriteLn;
    count := 0;
    AllNames;
    IF count = 0 THEN
      WriteString(" ---- no file found");
      WriteLn;
    END;
    IF termopt = terminate THEN EXIT END;
  END; (* LOOP *)
END CopRen.
