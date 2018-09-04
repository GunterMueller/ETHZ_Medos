IMPLEMENTATION MODULE NameSearch;         (* LG 18.08.82 *)

  FROM DiskSystem IMPORT Name, ReadName, fname;
  FROM FileSystem IMPORT File, FileCommand, DirectoryCommand, Command, Response;
  FROM Terminal IMPORT WriteString, WriteLn;

  (* (* definitions from definition module *)

  EXPORT QUALIFIED FindNames, NextName;

  PROCEDURE FindNames(device, searched: ARRAY OF CHAR; uplowEqual: BOOLEAN);

    (* Initialise searching on 'device' for file names   *)
    (* matching 'searched', which may contain wildcard   *)
    (* symbols. 'uplowEqual' handles matching of capital *)
    (* and lowercase letters.                            *)

  PROCEDURE NextName(VAR ok: BOOLEAN; VAR found: ARRAY OF CHAR;
                     VAR fileNo, versionNo: CARDINAL);

    (* Search next name according to values initialised   *)
    (* by a call of procedure 'FindNames'.                *)
    (* 'ok' indicates successful searching, 'found' is    *)
    (* the found name, 'fileNo' and 'versionNo' the       *)
    (* corresponding file information.                    *)

  (* end definitions *) *)

  CONST
    searchlength = 32;
    initpos = 177777B;

  VAR
    search : ARRAY [0 .. searchlength - 1] OF CHAR;
    minsearch : CARDINAL;    (* minimal position in 'search' *)
    maxsearch : CARDINAL;    (* maximal position in 'search' *)
    several : BOOLEAN;       (* several files searched *)
    equal : BOOLEAN;         (* matching information *)
    lastpos : CARDINAL;      (* last directory read position *)
    
  PROCEDURE FindNames(device, searched: ARRAY OF CHAR; uplowEqual: BOOLEAN);
    VAR ch : CHAR;
        ix : CARDINAL;
        wild : BOOLEAN;
  BEGIN (* FindNames *)
    ix := 0;
    wild := FALSE;
    WHILE (ix <= HIGH(search)) AND
          (ix <= HIGH(device)) AND
          (device[ix] <> ' ') AND (device[ix] <> 0C) DO
      search[ix] := device[ix];
      INC(ix);
    END;
    IF ix <= HIGH(search) THEN
      search[ix] := '.';
      INC(ix);
    END;
    minsearch := ix;
    maxsearch := ix;
    ix := 0;
    WHILE (maxsearch <= HIGH(search)) AND
          (ix <= HIGH(searched)) AND
          (searched[ix] <> ' ') AND (searched[ix] <> 0C) DO
      ch := searched[ix];
      IF (ch = '*') OR (ch = '%') THEN wild := TRUE;
      ELSIF uplowEqual AND ('a' <= ch) AND (ch <= 'z') THEN ch := CAP(ch);
      END;
      search[maxsearch] := ch;
      INC(maxsearch);
      INC(ix);
    END;
    IF maxsearch <= HIGH(search) THEN search[maxsearch] := 0C END;
    (* test on legal searched name *)
    IF wild OR uplowEqual THEN
      several := TRUE;
      (* check on device 'DK' *)
      IF (search[0] <> 'D') OR (search[1] <> 'K') OR (search[2] <> '.') THEN
        maxsearch := 0;
        WriteString(" ---- wildcards or equal option not supported on medium : ");
        WriteString(device);
        WriteLn;
      END;
    ELSE several := FALSE;
    END;
    IF maxsearch = minsearch THEN
      maxsearch := 0;
      WriteString(" ---- empty file name not supported");
      WriteLn;
    END;
    lastpos := initpos;
    equal := uplowEqual;
  END FindNames;

  PROCEDURE NextName(VAR ok: BOOLEAN; VAR found: ARRAY OF CHAR;
                     VAR fileNo, versionNo: CARDINAL);

    VAR
      resp : Response;
      nam : Name;
      maxfound : CARDINAL;

    PROCEDURE Match(searchix, foundix: CARDINAL): BOOLEAN;
      (* check match of strings in 'search' and 'found' *)
      (* algorithm allows fillers '*' in the string searched *)
      VAR ix : CARDINAL;
    BEGIN (* Match *)
      LOOP
        IF searchix = maxsearch THEN
          RETURN foundix = maxfound;
        END;
        IF search[searchix] = '*' THEN
          INC(searchix);
          ix := maxfound;
          WHILE ix > foundix DO
            IF Match(searchix,ix) THEN RETURN TRUE END;
            DEC(ix);
          END;
          IF (search[searchix]='.') AND ((searchix=1) OR (search[searchix-2]='.')) THEN
            (* leading string "*." could be handled as empty *)
            (* or string ".*." could be handled as "." *)
            INC(searchix);
          END;
          RETURN Match(searchix,foundix);
        ELSIF foundix = maxfound THEN
          IF (search[searchix] = '.') AND (searchix + 2 = maxsearch) THEN INC(searchix);
          ELSE RETURN FALSE;
          END;
        ELSIF (search[searchix] = found[foundix]) OR
              (search[searchix] = '%') OR
              equal AND ('a' <= found[foundix]) AND (found[foundix] <= 'z') AND
                (search[searchix] = CAP(found[foundix]))
        THEN
          INC(searchix);
          INC(foundix);
        ELSE RETURN FALSE;
        END;
      END; (* LOOP *)
    END Match;

    PROCEDURE LookupInfo;
      VAR f : File;
          ix : CARDINAL;
    BEGIN (* LookupInfo *)
      WITH f DO
        com := lookup; new := FALSE;
        DirectoryCommand(f, search);
        IF res = done THEN
          com := getinternal;
          FileCommand(f);
          ok := res = done;
          fileNo := fileno;
          versionNo := versionno;
          com := close;
          FileCommand(f);
        ELSE
          ok := FALSE;
        END;
      END; (* WITH *)
      IF ok THEN
        maxfound := 0;
        ix := minsearch;
        WHILE (maxfound <= HIGH(found)) DO
          IF ix < maxsearch THEN
            found[maxfound] := search[ix];
            INC(ix);
          ELSE found[maxfound] := ' ';
          END;
          INC(maxfound);
        END;
      END;
    END LookupInfo;

  BEGIN (* NextName *)
    IF lastpos = initpos THEN
      IF maxsearch = 0 THEN
        ok := FALSE;
        RETURN;
      ELSIF several THEN
        lastpos := 0;
      ELSE (* only one file *)
        LookupInfo;
        maxsearch := 0;
        RETURN;
      END;
    ELSE INC(lastpos);
    END;
    LOOP
      ReadName(lastpos,nam,resp);
      IF resp <> done THEN
        maxsearch := 0;
        lastpos := initpos;
        ok := FALSE;
        EXIT;
      END;
      WITH nam DO
        maxfound := 0;
        IF nk = fname THEN
          WHILE (maxfound<=HIGH(en)) AND (en[maxfound]<>' ') AND (maxfound<=HIGH(found))DO
            found[maxfound] := en[maxfound];
            INC(maxfound);
          END;
        END;
        IF (maxfound > 0) AND Match(minsearch,0) THEN
          (* fill up found with blancs *)
          WHILE maxfound <= HIGH(found) DO found[maxfound] := ' '; INC(maxfound) END;
          ok := TRUE;
          fileNo := fno;
          versionNo := vno;
          EXIT;
        END;
      END;
      INC(lastpos);
    END; (* LOOP *)
  END NextName;

END NameSearch.
