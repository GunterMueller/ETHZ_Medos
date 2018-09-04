MODULE Directory;                             (* LG 30.5.83 *)

  FROM DiskSystem IMPORT FileDesc, ReadFileDesc, FreePages;
  FROM FileSystem IMPORT Response, File, Lookup, Reset, WriteChar, Close;
  FROM Terminal IMPORT Read, BusyRead, Write, WriteString, WriteLn;
  FROM Monitor IMPORT Time, GetTime;
  FROM DisplayDriver IMPORT MapHeight, LineHeight;
  FROM NameSearch IMPORT FindNames, NextName;
  FROM Options IMPORT FileNameAndOptions, GetOption, Termination;
  FROM Conversions IMPORT ConvertCardinal;

  CONST
    optionlength = 10;
    devicelength = 8;
    namelength = 24;
    maxdirectory = 800;

  TYPE
    OptionKind = (nooption,
                  alpha, datesort, nosort,
                  today, nodate,
                  equal, noequal,
                  output, page, scroll,
                  short, norm, extra,
                  continue, terminate,
                  illegal);
    OptionText = ARRAY [0 .. optionlength-1] OF CHAR;
    Option = RECORD
               minlength : CARDINAL;
               maxlength : CARDINAL;
               text : OptionText;
             END;
    FileName = ARRAY [0 .. namelength - 1] OF CHAR;
    DeviceName = ARRAY [0 .. devicelength - 1] OF CHAR;
    NameDescriptor = RECORD
                       name : FileName;
                       device : DeviceName;
                       len : CARDINAL;
                     END;
    DirEntry = RECORD
                 name : FileName;
                 fnum : CARDINAL;
                 modif : CARDINAL;
                 cdate : CARDINAL;
                 mdate : CARDINAL;
                 blleng : CARDINAL;
                 byleng : CARDINAL;
                 prot : CARDINAL;
               END;

  VAR
    search : NameDescriptor;
    outFile : File;
    proceed : BOOLEAN;
    lines : CARDINAL;
    maxlines : CARDINAL;
    totfiles, totlength : CARDINAL;
    lstr : ARRAY [0..10] OF CHAR;
    options : ARRAY OptionKind OF Option;
    sortopt, dateopt, equalopt, outopt, infoopt, termopt : OptionKind;
    directory : ARRAY [1..maxdirectory] OF DirEntry;
    writeString : PROCEDURE (ARRAY OF CHAR);
    writeLine : PROCEDURE;
    time : Time;
    mindate : CARDINAL;
    maxdate : CARDINAL;

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
        alpha, datesort, nosort : sortopt := optkind;
      | today, nodate : dateopt := optkind;
      | equal, noequal : equalopt := optkind;
      | output, page, scroll : outopt := optkind;
      | short, norm, extra : infoopt := optkind;
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

  PROCEDURE NewLine;
    CONST escape = 33C;
          clear = 14C;
          unspecified = 0C;
    VAR ch : CHAR;
  BEGIN (* NewLine *)
    IF proceed THEN
      IF outopt = page THEN
        INC(lines);
        IF lines >= maxlines THEN
          WriteString(" ...");
          Read(ch);
          IF ch = escape THEN WriteLn; proceed := FALSE;
          ELSE
            Write(clear);
            lines := 1;
          END;
        END;
      ELSIF outopt = scroll THEN
        BusyRead(ch);
        IF (ch <> unspecified) AND (ch <> escape) THEN Read(ch) (* wait *) END;
        IF ch = escape THEN proceed := FALSE END;
      END;
    END;
  END NewLine;

  PROCEDURE OutString(str: ARRAY OF CHAR);
    VAR ix : CARDINAL;
  BEGIN (* OutString *)
    ix := 0;
    WHILE (ix <= HIGH(str)) AND (str[ix] <> 0C) DO
      WriteChar(outFile, str[ix]);
      INC(ix);
    END;
  END OutString;

  PROCEDURE OutLine;
    CONST eolc = 36C;
  BEGIN (* OutLine *)
    WriteChar(outFile, eolc);
  END OutLine;

  PROCEDURE ConvertDate(date, len: CARDINAL; VAR str: ARRAY OF CHAR);
    VAR day, month, year : CARDINAL;
        cnt, ix : CARDINAL;
        lstr : ARRAY [0..4] OF CHAR;
  BEGIN (* ConvertDate *)
    day := date MOD 40B;
    month := date DIV 40B MOD 20B;
    year := date DIV 1000B;
    IF day < 10 THEN cnt := 8 ELSE cnt := 9 END;
    IF cnt > HIGH(str) + 1 THEN date := 0;
    ELSIF len > HIGH(str) + 1 THEN len := HIGH(str);
    END;
    ix := 0;
    IF date <> 0 THEN
      WHILE len > cnt DO str[ix] := ' '; INC(ix); DEC(len) END;
      IF day >= 10 THEN str[ix] := CHAR(day DIV 10 + CARDINAL('0')); INC(ix) END;
      str[ix] := CHAR(day MOD 10 + CARDINAL('0')); INC(ix);
      CASE month OF
        1 : lstr := ".Jan.";
       |2 : lstr := ".Feb.";
       |3 : lstr := ".Mar.";
       |4 : lstr := ".Apr.";
       |5 : lstr := ".May.";
       |6 : lstr := ".Jun.";
       |7 : lstr := ".Jul.";
       |8 : lstr := ".Aug.";
       |9 : lstr := ".Sep.";
       |10 : lstr := ".Oct.";
       |11 : lstr := ".Nov.";
       |12 : lstr := ".Dec.";
      ELSE lstr := ".???.";
      END;
      FOR cnt := 0 TO 4 DO str[ix] := lstr[cnt]; INC(ix) END;
      str[ix] := CHAR(year DIV 10 + CARDINAL('0')); INC(ix);
      str[ix] := CHAR(year MOD 10 + CARDINAL('0')); INC(ix);
    END;
    IF ix <= HIGH(str) THEN str[ix] := 0C END;
  END ConvertDate;

  PROCEDURE WriteDirectory(VAR entry: DirEntry);
    VAR lstr : ARRAY [0..10] OF CHAR;
        len, lenup, lenlow : CARDINAL;
        ix : CARDINAL;

    CONST dirlength = 80;
    VAR dirstr : ARRAY [0..dirlength-1] OF CHAR;
        maxdirpos : CARDINAL;
        inspos : CARDINAL;

    PROCEDURE InsertDirStr(VAR str: ARRAY OF CHAR);
      VAR maxstr, ix, pos : CARDINAL;
    BEGIN (* InsertDirStr *)
      maxstr := HIGH(str);
      pos := inspos;
      IF pos <= dirlength THEN
        WHILE pos > maxdirpos DO dirstr[maxdirpos] := ' '; INC(maxdirpos) END;
        ix := 0;
        WHILE (pos < dirlength) AND (ix <= maxstr) AND (str[ix] <> 0C) DO
          dirstr[pos] := str[ix];
          INC(pos);
          INC(ix);
        END;
        IF pos > maxdirpos THEN maxdirpos := pos END;
        IF maxdirpos < dirlength THEN dirstr[maxdirpos] := 0C END;
      END;
    END InsertDirStr;

  BEGIN (* WriteDirectory *)
    NewLine;
    IF proceed THEN
      WITH entry DO
        dirstr := "";
        maxdirpos := 0;
        inspos := 0;
        IF infoopt <> short THEN
          IF prot <> 0 THEN lstr := " #"; InsertDirStr(lstr) END;
          INC(inspos, 3);
        ELSE
          ix := namelength - 1;
          WHILE (ix > 0 ) AND (name[ix] = ' ') DO name[ix] := 0C; DEC(ix) END;
        END;
        InsertDirStr(name);
        INC(inspos, namelength);
        (* length information *)
        len := blleng DIV 8;
        IF (blleng MOD 8 > 0) OR (byleng <> 0) THEN INC(len) END;
        IF infoopt <> short THEN
          ConvertCardinal(len, 5, lstr);
          InsertDirStr(lstr);
          INC(inspos, 5);
          IF infoopt = extra THEN
            lenup := blleng DIV 256;
            lenlow := blleng MOD 256 * 256 + byleng;
            lenup := lenup * 6 + lenlow DIV 10000; (* 6 = 65'536 DIV 10'000 *)
            lenlow := lenlow MOD 10000;
            FOR ix := 1 TO blleng DIV 256 DO (* add the remains *)
              INC(lenlow, 5536); (* 65'536 MOD 10'000 *)
              IF lenlow >= 10000 THEN DEC(lenlow, 10000); INC(lenup) END;
            END;
            IF lenup > 0 THEN
              ConvertCardinal(lenup, 4, lstr);
              InsertDirStr(lstr);
              ConvertCardinal(lenlow, 4, lstr);
              FOR ix := 0 TO 3 DO
                IF lstr[ix] = ' ' THEN lstr[ix] := '0' END;
              END;
            ELSE
              ConvertCardinal(lenlow, 4, lstr);
            END;
            INC(inspos, 4);
            InsertDirStr(lstr);
            INC(inspos, 4);
            ConvertCardinal(fnum, 6, lstr);
            InsertDirStr(lstr);
            INC(inspos, 6);
          END;
          (* date information *)
          INC(inspos, 2);
          ConvertDate(mdate, 10, lstr); (* last modification or creation *)
          InsertDirStr(lstr);
          INC(inspos, 10);
          IF (infoopt = extra) AND (modif > 0) THEN
            ConvertCardinal(modif, 5, lstr);
            InsertDirStr(lstr);
            INC(inspos, 5);
            ConvertDate(cdate, 10, lstr);
            InsertDirStr(lstr);
            INC(inspos, 10);
          END;
        END;
        writeString(dirstr);
        writeLine;
        INC(totlength, len);
      END;
    END;
  END WriteDirectory;

  PROCEDURE SortAndWriteDirectory;
    VAR ix : CARDINAL;
        table : ARRAY [1..maxdirectory] OF CARDINAL;

    PROCEDURE Greater(VAR entry1, entry2: DirEntry): BOOLEAN;
      TYPE CharKind = (nul, period, low, high, digit);
      VAR ix : CARDINAL;
          ch1, ch2 : CHAR;
          k1, k2 : CharKind;
          firstMismatch, greater : BOOLEAN;

      PROCEDURE Kind(ch: CHAR): CharKind;
      BEGIN (* Kind *)
        IF ('a' <= ch) AND (ch <= 'z') THEN RETURN low END;
        IF ('A' <= ch) AND (ch <= 'Z') THEN RETURN high END;
        IF ('0' <= ch) AND (ch <= '9') THEN RETURN digit END;
        IF ch = '.' THEN RETURN period END;
        IF ch = ' ' THEN RETURN nul END;
      END Kind;

    BEGIN (* Greater *)
      ix := 0;
      IF (sortopt = datesort) AND (entry1.mdate <> entry2.mdate) THEN
        RETURN entry1.mdate < entry2.mdate;
      END;
      firstMismatch := TRUE; greater := FALSE;
      LOOP
        IF ix > HIGH(entry1.name) THEN RETURN greater END;
        ch1 := entry1.name[ix]; ch2 := entry2.name[ix];
        IF ch1 <> ch2 THEN
          k1 := Kind(ch1); k2 := Kind(ch2);
          IF k1 <> k2 THEN
            IF firstMismatch THEN firstMismatch := FALSE; greater := k1 > k2 END;
            IF k1 = low THEN ch1 := CAP(ch1); k1 := high END;
            IF k2 = low THEN ch2 := CAP(ch2); k2 := high END;
          END;
          IF ch1 <> ch2 THEN RETURN (k1 > k2) OR (k1 = k2) AND (ch1 > ch2) END;
        ELSIF ch1 = ' ' THEN RETURN greater;
        ELSIF ch1 = '.' THEN
          IF NOT firstMismatch THEN RETURN greater END;
        END;
        INC(ix);
      END; (* LOOP *)
    END Greater;

    PROCEDURE QuickSort(left, right: CARDINAL);
      VAR ix1, ix2 : CARDINAL;
          mark, help : CARDINAL;
    BEGIN (* QuickSort *)
      ix1 := left; ix2 := right;
      mark := table[(left + right) DIV  2];
      REPEAT
        WHILE Greater(directory[mark], directory[table[ix1]]) DO INC(ix1) END;
        WHILE Greater(directory[table[ix2]], directory[mark]) DO DEC(ix2) END;
        IF ix1 <= ix2 THEN
          help := table[ix1]; table[ix1] := table[ix2]; table[ix2] := help;
          INC(ix1); DEC(ix2);
        END;
      UNTIL ix1 > ix2;
      IF left < ix2 THEN QuickSort(left, ix2) END;
      IF ix1 < right THEN QuickSort(ix1, right) END;
    END QuickSort;

  BEGIN (* SortAndWriteDirectory *)
    FOR ix := 1 TO totfiles DO table[ix] := ix END;
    QuickSort(1, totfiles);
    FOR ix := 1 TO totfiles DO WriteDirectory(directory[table[ix]]) END;
  END SortAndWriteDirectory;

  PROCEDURE AllNames;
    VAR
      found : FileName;
      number, version : CARDINAL;
      ok : BOOLEAN;
      entry : DirEntry;
      desc : FileDesc;
      resp : Response;
  BEGIN (* AllNames *)
    FindNames(search.device, search.name, equalopt=equal);
    NextName(ok, found, number, version);
    WHILE proceed AND ok DO
      ReadFileDesc(number, desc, resp);
      WITH entry DO
        name := found;
        fnum := number;
        modif := desc.modification;
        cdate := desc.ctime.day;
        IF modif > 0 THEN mdate := desc.mtime.day ELSE mdate := cdate END;
        blleng := desc.length.block;
        byleng := desc.length.byte;
        prot := desc.protection;
      END;
      IF (dateopt = nodate) OR (entry.mdate >= mindate) AND (entry.mdate <= maxdate) THEN
        INC(totfiles);
        IF sortopt <> nosort THEN directory[totfiles] := entry;
        ELSE WriteDirectory(entry);
        END;
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
      oldsortopt, olddateopt, oldequalopt, oldoutopt, oldinfoopt, oldtermopt : OptionKind;
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
        (* control on correct device *)
        IF NOT cancel THEN
          IF (len<>2) OR (device[0]<>'D') OR (device[1]<>'K') THEN cancel := TRUE END;
        END;
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
      oldsortopt := sortopt;
      olddateopt := dateopt;
      oldequalopt := equalopt;
      oldoutopt := outopt;
      oldinfoopt := infoopt;
      oldtermopt := termopt;
      WITH desc DO
        LOOP
          WriteString(display);
          FileNameAndOptions(default, inputName, termstat, TRUE);
          WriteLn;
          IF (termstat = normal) OR (termstat = empty) THEN
            IF termstat = empty THEN inputName := default END;
            sortopt := oldsortopt;
            dateopt := olddateopt;
            equalopt := oldequalopt;
            outopt := oldoutopt;
            infoopt := oldinfoopt;
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

  PROCEDURE OutputControl(display: ARRAY OF CHAR; VAR file: File);
    CONST
      default = "DK.DirectoryList.LST";

    VAR
      termstat : Termination;
      cancel : BOOLEAN;
      oldsortopt, olddateopt, oldequalopt, oldoutopt, oldinfoopt, oldtermopt : OptionKind;
      inputName : ARRAY[0 .. devicelength + namelength - 1] OF CHAR;

  BEGIN (* OutputControl *)
    IF proceed THEN
      oldsortopt := sortopt;
      olddateopt := dateopt;
      oldequalopt := equalopt;
      oldoutopt := outopt;
      oldinfoopt := infoopt;
      oldtermopt := termopt;
      LOOP
        WriteString(display);
        FileNameAndOptions(default, inputName, termstat, TRUE);
        WriteLn;
        IF (termstat = normal) OR (termstat = empty) THEN
          IF termstat = empty THEN
            inputName := default;
          END;
          sortopt := oldsortopt;
          dateopt := olddateopt;
          equalopt := oldequalopt;
          outopt := oldoutopt;
          infoopt := oldinfoopt;
          termopt := oldtermopt;
          InterpreteOptions(cancel);
          IF NOT cancel THEN
            Lookup(file, inputName, TRUE);
            IF file.res = done THEN
              Reset(file);
              EXIT;
            ELSE
              WriteString(" ---- file lookup or creation failed");
              WriteLn;
            END;
          END;
        ELSIF termstat = esc THEN
          proceed := FALSE; EXIT;
        END;
      END; (* LOOP *)
    END;
  END OutputControl;


BEGIN (* Directory *)
  InitOption(alpha, "ALPHASORT", 1, 9);
  InitOption(datesort, "DATESORT", 1, 8);
  InitOption(nosort, "NOSORT", 3, 6);
  InitOption(today, "TODAY", 3, 5);
  InitOption(nodate, "NODATE", 3, 6);
  InitOption(equal, "EQUAL", 1, 5);
  InitOption(noequal, "NOEQUAL", 3, 7);
  InitOption(output, "OUTPUT", 1, 6);
  InitOption(page, "PAGE", 1, 4);
  InitOption(scroll, "SCROLL", 1, 6);
  InitOption(short, "SHORT", 2, 5);
  InitOption(norm, "NORMAL", 4, 6);
  InitOption(extra, "EXTRA", 2, 5);
  InitOption(continue, "CONTINUE", 1, 8);
  InitOption(terminate, "TERMINATE", 1, 9);
  LOOP
    proceed := TRUE;
    sortopt := nosort;
    dateopt := nodate;
    equalopt := noequal;
    outopt := page;
    infoopt := norm;
    termopt := terminate;
    InputControl(" directory> ", search);
    IF proceed AND (outopt = output) THEN
      OutputControl(" output file> ", outFile);
    END;
    IF NOT proceed THEN EXIT END;
    IF outopt = output THEN
      writeString := OutString;
      writeLine := OutLine;
    ELSE
      writeString := WriteString;
      writeLine := WriteLn;
    END;
    GetTime(time);
    IF dateopt = today THEN
      mindate := time.day;
      maxdate := time.day;
    ELSE 
      mindate := 0;
      maxdate := 65535;
    END;
    ConvertDate(time.day, 0, lstr);
    writeString(" directory : medium ");
    writeString(search.device);
    writeString("; selection ");
    writeString(search.name);
    writeString("; date ");
    ConvertDate(time.day, 0, lstr);
    writeString(lstr);
    writeLine;
    lines := 1;
    maxlines := MapHeight() DIV LineHeight();
    totfiles := 0;
    totlength := 0;
    AllNames;
    IF (sortopt <> nosort) AND (totfiles > 0) THEN SortAndWriteDirectory END;
    (* write statistics *)
    NewLine;
    IF proceed THEN
      ConvertCardinal(totfiles, 1, lstr);
      writeString(" Listed files: ");
      writeString(lstr);
      ConvertCardinal(totlength, 1, lstr);
      writeString("   Used space: ");
      writeString(lstr);
      ConvertCardinal(FreePages(), 1, lstr);
      writeString("   Free space: ");
      writeString(lstr);
      writeLine;
    END;
    IF outopt = output THEN
      IF outFile.res <> done THEN
        WriteString(" ---- unsuccessful writing on output file");
        WriteLn;
      ELSE
        ConvertCardinal(totfiles, 1, lstr);
        WriteString(" Listed files: ");
        WriteString(lstr);
        ConvertCardinal(totlength, 1, lstr);
        WriteString("   Used space: ");
        WriteString(lstr);
        ConvertCardinal(FreePages(), 1, lstr);
        WriteString("   Free space: ");
        WriteString(lstr);
        WriteLn;
      END;
      Close(outFile);
    END;
    IF termopt = terminate THEN EXIT END;
  END; (* LOOP *)
END Directory.
