IMPLEMENTATION  MODULE ReadUserProfile; (* Werner Winiger 12.1.83 
                       ===============  *)

  FROM FileSystem IMPORT
    File, Response, Lookup, Close, Reset, SetPos, GetPos, ReadChar;

  CONST
    EOL = 36c;
  VAR
    userProfile: File;
    itemFound,
    endOfGroup,
    userProfileOpen: BOOLEAN;
    posHigh,posLow: CARDINAL;


  PROCEDURE FindChar (specific,stopChar: CHAR; VAR found: BOOLEAN);
    VAR
      ch: CHAR;
  BEGIN
    found := FALSE;
    LOOP 
      ReadChar(userProfile,ch);
      IF userProfile.eof THEN RETURN; END;
      IF ch = stopChar THEN RETURN; END;
      IF ch = specific THEN EXIT; END;
    END;
    found := TRUE;
  END FindChar;

  PROCEDURE SearchGroup (VAR gr: ARRAY OF CHAR; VAR ok: BOOLEAN);     (*
      search group g; return FALSE if EOF(userProfile) is encountered;
      position userProfile after the second '"', if g is found;       *)

    VAR
      ch: CHAR;
      i: CARDINAL;
  BEGIN
    REPEAT
      FindChar('"',0c,ok);
      IF ok THEN
        i := 0;
        LOOP 
          ReadChar(userProfile,ch);
          IF ch = '"' THEN
            ok := (i > HIGH(gr)) OR (gr[i] = 0c);
            EXIT;
          END;
          IF (i > HIGH(gr)) OR (ch # gr[i]) THEN
            FindChar('"',0c,ok); (* skip rest of group id *)
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

  PROCEDURE SearchItem (VAR it: ARRAY OF CHAR;  
                        VAR ok: BOOLEAN; VAR posHigh,posLow: CARDINAL);
    VAR
      ch: CHAR;
      i: CARDINAL;
  BEGIN
    REPEAT
      FindChar("'",'"',ok);
      IF ok THEN
        GetPos(userProfile,posHigh,posLow);
        IF posHigh # 0 THEN HALT; END; (* user profile must not exceed 32K *)
        DEC(posLow);
        i := 0;
        LOOP 
          ReadChar(userProfile,ch);
          IF ch = "'" THEN
            ok := (i > HIGH(it)) OR (it[i] = 0c);
            EXIT;
          END;
          IF (i > HIGH(it)) OR (ch # it[i]) THEN
            FindChar("'",'"',ok); (* skip rest of group id *)
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
      Reset(userProfile);
      ok := TRUE;
    ELSE
      Lookup(userProfile,"DK.User.Profile",FALSE);
      ok := (userProfile.res = done);
      userProfileOpen := ok;
    END;
    itemFound := FALSE;
    endOfGroup := TRUE;
  END LookupUserProfile;

  PROCEDURE CloseUserProfile; 
  BEGIN
    IF userProfileOpen THEN
      Close(userProfile);
      userProfileOpen := FALSE;
    END;
  END CloseUserProfile;

  PROCEDURE SetReadPos (groupId, itemId: ARRAY OF CHAR; VAR ok: BOOLEAN);
  BEGIN
    ok := FALSE;
    IF userProfileOpen THEN
      itemFound := FALSE;
      Reset(userProfile);
      SearchGroup(groupId,ok);
      IF ok THEN
        GetPos(userProfile,posHigh,posLow);
        IF (itemId[0] # 0c) THEN
          SearchItem(itemId,ok,posHigh,posLow);
          IF ok THEN itemFound := TRUE; END;
        END;
      END;
    END;
    endOfGroup := NOT ok;
  END SetReadPos;

  PROCEDURE ReadItem (VAR itemId, value: ARRAY OF CHAR; VAR eog: BOOLEAN);
    VAR
      ch: CHAR;
      i: CARDINAL;
      ok: BOOLEAN;
  BEGIN
    eog := TRUE;
    IF endOfGroup THEN RETURN; END;
    IF userProfileOpen THEN
      IF itemFound THEN
        SetPos(userProfile,posHigh,posLow);
        itemFound := FALSE;
      END;
      FindChar("'",'"',ok);
      eog := NOT ok;
      IF ok THEN
        i := 0;
        LOOP 
          ReadChar(userProfile,ch);
          itemId[i] := ch;
          IF ch = "'" THEN
            itemId[i] := 0c;
            EXIT;
          END;
          INC(i);
          IF i > HIGH(itemId) THEN
            FindChar("'",'"',ok);
            EXIT;
          END;
        END; (* LOOP *)

        IF ok THEN
          LOOP
            ReadChar(userProfile,ch);
            IF userProfile.eof THEN
              eog := TRUE;
              endOfGroup := TRUE;
              RETURN;
            END;
            IF ch # ' ' THEN EXIT; END;
          END;
          i := 0;
          LOOP
            value[i] := ch;
            IF i = HIGH(value) THEN EXIT; END;
            INC(i);
            ReadChar(userProfile,ch);
            IF userProfile.eof OR (ch = EOL) THEN
              WHILE (i > 0) AND (value[i-1] = ' ') DO DEC(i); END;
              value[i] := 0c; 
              EXIT;
            END;
          END;
        ELSE
          eog := TRUE;
        END;
      END;
    END;
    endOfGroup := eog;
  END ReadItem;

BEGIN
  userProfileOpen := FALSE;
END ReadUserProfile.
