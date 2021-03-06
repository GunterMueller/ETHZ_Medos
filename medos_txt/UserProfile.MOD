IMPLEMENTATION  MODULE UserProfile; (* Werner Winiger 27.6.83 
                       ===========  *)

  FROM FileSystem IMPORT
    File, Response, Create, Lookup, Close, Rename, Reset, 
    SetPos, GetPos, ReadChar, WriteChar, Again;
    

  CONST
    EOL = 36c;
    NoBlank = 377c;
  VAR
    userProfile: ARRAY [1..2] OF File;
    from,to: [1..2];
    itemFound,
    endOfGroup,
    userProfileOpen,
    userProfileWriting: BOOLEAN;
    posHigh,posLow: CARDINAL;

  PROCEDURE Copy;
    (*
      copy the rest of userProfile[from] to userProfile[to] *)
    VAR
      ch: CHAR;
  BEGIN
    LOOP 
      ReadChar(userProfile[from],ch);
      IF userProfile[from].eof THEN EXIT; END;
      WriteChar(userProfile[to],ch);
    END;
  END Copy;

  PROCEDURE SetReading;
    VAR
      temp: [1..2];
  BEGIN
    IF userProfileWriting THEN
      Copy;
      Rename(userProfile[from],"");
      Rename(userProfile[to],"DK.User.Profile");
      temp := to;
      to := from;
      from := temp;
      userProfileWriting := FALSE;
    END;
    itemFound := FALSE; 
  END SetReading;

  PROCEDURE FindChar (specific,stopChar: CHAR; incl,copy: BOOLEAN; VAR found: BOOLEAN);
    VAR
      ch: CHAR;
  BEGIN
    found := FALSE;
    LOOP 
      ReadChar(userProfile[from],ch);
      IF userProfile[from].eof THEN RETURN; END;
      IF ch = stopChar THEN
        Again(userProfile[from]);
        RETURN;
      END;
      IF specific = NoBlank THEN IF ch <> ' ' THEN EXIT; END;
      ELSE IF ch = specific THEN EXIT; END;
      END;
      IF copy THEN WriteChar(userProfile[to],ch); END;
    END;
    found := TRUE;
    IF incl THEN IF copy THEN WriteChar(userProfile[to],ch); END;
    ELSE Again(userProfile[from]);
    END;
  END FindChar;

  PROCEDURE SearchGroup (VAR gr: ARRAY OF CHAR; copy: BOOLEAN; VAR ok: BOOLEAN);
    (*
      search group g; return FALSE if EOF(userProfile[from]) is encountered;
      position userProfile[from] after the second '"', if g is found;       *)

    VAR
      ch: CHAR;
      i: CARDINAL;
  BEGIN
    REPEAT
      FindChar('"',0c,TRUE,copy,ok);
      IF ok THEN
        i := 0;
        LOOP 
          ReadChar(userProfile[from],ch);
          IF copy THEN WriteChar(userProfile[to],ch); END;
          IF ch = '"' THEN
            ok := (i > HIGH(gr)) OR (gr[i] = 0c);
            EXIT;
          END;
          IF (i > HIGH(gr)) OR (ch <> gr[i]) THEN
            FindChar('"',0c,TRUE,copy,ok); (* skip rest of group id *)
            ok := FALSE;
            EXIT;
          END;
          INC(i);
        END;
      ELSE
        RETURN;
      END;
    UNTIL ok;
  END SearchGroup;

  PROCEDURE SearchItem (VAR it: ARRAY OF CHAR; copy: BOOLEAN;  
                        VAR ok: BOOLEAN; VAR posHigh,posLow: CARDINAL);
    VAR
      ch: CHAR;
      i: CARDINAL;
  BEGIN
    REPEAT
      FindChar("'",'"',TRUE,copy,ok);
      IF ok THEN
        GetPos(userProfile[from],posHigh,posLow);
        IF posHigh <> 0 THEN HALT; END; (* user profile must not exceed 32K *)
        DEC(posLow);
        i := 0;
        LOOP 
          ReadChar(userProfile[from],ch);
          IF copy THEN WriteChar(userProfile[to],ch); END;
          IF ch = "'" THEN
            ok := (i > HIGH(it)) OR (it[i] = 0c);
            EXIT;
          END;
          IF (i > HIGH(it)) OR (ch <> it[i]) THEN
            FindChar("'",'"',TRUE,copy,ok); (* skip rest of group id *)
            ok := FALSE;
            EXIT;
          END;
          INC(i);
        END;
      ELSE
        RETURN;
      END;
    UNTIL ok;
  END SearchItem;

  PROCEDURE LookupUserProfile (new: BOOLEAN; VAR ok: BOOLEAN);
  BEGIN
    IF userProfileOpen THEN
      SetReading;
      ok := TRUE;
    ELSE
      from := 1;
      to := 2;
      Lookup(userProfile[from],"DK.User.Profile",new);
      Create(userProfile[to],"DK");
      ok := (userProfile[from].res = done) AND
            (userProfile[to].res = done);
      userProfileOpen := ok;
    END;
    itemFound := FALSE;
    endOfGroup := TRUE;
  END LookupUserProfile;

  PROCEDURE CloseUserProfile; 
  BEGIN
    IF userProfileOpen THEN
      SetReading;
      Close(userProfile[from]);
      Close(userProfile[to]);
      userProfileOpen := FALSE;
    END;
  END CloseUserProfile;

  PROCEDURE SetReadPos (groupId, itemId: ARRAY OF CHAR; VAR ok: BOOLEAN);
  BEGIN
    ok := FALSE;
    IF userProfileOpen THEN
      SetReading;
      Reset(userProfile[from]);
      SearchGroup(groupId,FALSE,ok);
      IF ok THEN
        GetPos(userProfile[from],posHigh,posLow);
        IF (itemId[0] <> 0c) THEN
          SearchItem(itemId,FALSE,ok,posHigh,posLow);
          IF ok THEN itemFound := TRUE; END;
        END;
      END;
    END;
    endOfGroup := NOT ok;
  END SetReadPos;

  PROCEDURE SetWritePos (groupId, itemId: ARRAY OF CHAR; VAR ok: BOOLEAN); 
    VAR
      itemFound,
      charFound: BOOLEAN;
      hi,lo: CARDINAL;
medosBUG: CHAR;
  BEGIN
    ok := FALSE;
    IF userProfileOpen THEN
      SetReading;
ReadChar(userProfile[from],medosBUG); (* Reset doesn't clear the again flag of the file *)
      Reset(userProfile[from]);
      Reset(userProfile[to]);
      IF groupId[0] = 0c THEN
        Copy;
        ok := TRUE;
        userProfileWriting := TRUE;
      ELSE
        SearchGroup(groupId,TRUE,ok);
        IF ok THEN
          userProfileWriting := TRUE;
          IF itemId[0] <> 0c THEN
            SearchItem(itemId,TRUE,itemFound,hi,lo);
            IF itemFound THEN
              FindChar(NoBlank,EOL,FALSE,TRUE,charFound);
              FindChar(EOL,0c,TRUE,FALSE,charFound);
            ELSE
              FindChar('"',0c,FALSE,TRUE,charFound);
              WriteItemId(itemId);
            END;
          ELSE
            FindChar('"',0c,FALSE,TRUE,charFound);
          END;
        END;
      END;
    END;
  END SetWritePos;

  PROCEDURE ReadItem (VAR itemId, value: ARRAY OF CHAR; VAR eog: BOOLEAN); 
    VAR
      ch: CHAR;
      i: CARDINAL;
      ok: BOOLEAN;
  BEGIN
    eog := TRUE;
    IF endOfGroup THEN RETURN; END;
    IF userProfileOpen AND (NOT userProfileWriting) THEN
      IF itemFound THEN
        SetPos(userProfile[from],posHigh,posLow);
        itemFound := FALSE;
      END;
      FindChar("'",'"',TRUE,FALSE,ok);
      eog := NOT ok;
      IF ok THEN
        i := 0;
        LOOP 
          ReadChar(userProfile[from],ch);
          itemId[i] := ch;
          IF ch = "'" THEN
            itemId[i] := 0c;
            EXIT;
          END;
          INC(i);
          IF i > HIGH(itemId) THEN
            FindChar("'",'"',TRUE,FALSE,ok);
            EXIT;
          END;
        END; (* LOOP *)

        IF ok THEN
          FindChar(NoBlank,0c,FALSE,FALSE,ok);
          IF NOT ok THEN
            eog := TRUE;
            endOfGroup := TRUE;
            RETURN;
          END;
          i := 0;
          LOOP
            ReadChar(userProfile[from],ch);
            IF userProfile[from].eof OR (ch = EOL) THEN
              WHILE (i > 0) AND (value[i-1] = ' ') DO DEC(i); END;
              value[i] := 0c; 
              EXIT;
            END;
            value[i] := ch;
            IF i = HIGH(value) THEN EXIT; END;
            INC(i);
          END;
        ELSE
          eog := TRUE;
        END;
      END;
    END;
    endOfGroup := eog;
  END ReadItem;

  PROCEDURE WriteGroupId (groupId: ARRAY OF CHAR); 
    VAR i: CARDINAL;
  BEGIN
    IF userProfileOpen AND userProfileWriting THEN
      WriteChar(userProfile[to],'"');
      i := 0;
      WHILE (i <= HIGH(groupId)) AND (groupId[i] <> 0c) DO
        WriteChar(userProfile[to],groupId[i]);
        INC(i);
      END;
      WriteChar(userProfile[to],'"');
      WriteChar(userProfile[to],EOL);
    END;
  END WriteGroupId;

  PROCEDURE WriteItemId (itemId: ARRAY OF CHAR); 
    VAR i: CARDINAL;
  BEGIN
    IF userProfileOpen AND userProfileWriting THEN
      WriteChar(userProfile[to],"'");
      i := 0;
      WHILE (i <= HIGH(itemId)) AND (itemId[i] <> 0c) DO
        WriteChar(userProfile[to],itemId[i]);
        INC(i);
      END;
      WriteChar(userProfile[to],"'");
      WriteChar(userProfile[to],' ');
    END;
  END WriteItemId;

  PROCEDURE WriteItem (value: ARRAY OF CHAR);
    VAR i: CARDINAL;
  BEGIN
    IF userProfileOpen AND userProfileWriting THEN
      i := 0;
      WHILE (i <= HIGH(value)) AND (value[i] <> 0c) DO
        WriteChar(userProfile[to],value[i]);
        INC(i);
      END;
      WriteChar(userProfile[to],EOL);
    END;
  END WriteItem;

BEGIN
  userProfileOpen := FALSE;
  userProfileWriting := FALSE;
END UserProfile.
