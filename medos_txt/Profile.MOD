IMPLEMENTATION MODULE Profile;  (*NW 9.7.82*)
  FROM FileSystem IMPORT File, Response, Lookup, ReadChar, Close;
  FROM Terminal IMPORT WriteString, WriteLn;

  VAR f: File;

  PROCEDURE OpenProfile(title: ARRAY OF CHAR);
  BEGIN
    Lookup(f, "DK.User.Profile", FALSE);
    IF f.res = done THEN FindKey(title)
    ELSE WriteString(" user profile not found"); HALT
    END
  END OpenProfile;

  PROCEDURE FindKey(key: ARRAY OF CHAR);
    VAR i: CARDINAL; ch: CHAR;
  BEGIN i := 0;
    LOOP ReadChar(f,ch);
      IF f.eof THEN
        WriteString(key); WriteString(" not in profile"); HALT
      END ;
      IF ch = key[i] THEN i := i+1;
        IF i > HIGH(key) THEN EXIT END
      ELSE i := 0
      END
    END
  END FindKey;

  PROCEDURE GetString(VAR s: ARRAY OF CHAR);
    VAR i: CARDINAL; ch: CHAR;
  BEGIN i := 0;
    REPEAT ReadChar(f,ch) UNTIL ch # " ";
    WHILE ch > " " DO
      s[i] := ch; i := i+1; ReadChar(f,ch)
    END ;
    s[i] := 0C
  END GetString;

  PROCEDURE GetFileName(VAR name: ARRAY OF CHAR; ext: ARRAY OF CHAR);
    VAR i,j: CARDINAL; ch: CHAR;
  BEGIN i := 3; j := 0;
    REPEAT ReadChar(f,ch) UNTIL ch # " ";
    WHILE ch > " " DO
      name[i] := ch; i := i+1; ReadChar(f,ch)
    END ;
    name[i] := "."; i := i+1;
    WHILE j <= HIGH(ext) DO
      name[i] := ext[j]; i := i+1; j := j+1
    END ;
    name[i] := 0C
  END GetFileName;

  PROCEDURE GetNumber(VAR x: CARDINAL);
    VAR i: CARDINAL; ch: CHAR;
  BEGIN x := 0;
    REPEAT ReadChar(f,ch) UNTIL ch # " ";
    WHILE ("0" <= ch) & (ch <= "9") DO
      x := 10*x + (CARDINAL(ch) - CARDINAL("0")); ReadChar(f,ch)
    END
  END GetNumber;

  PROCEDURE CloseProfile;
  BEGIN Close(f)
  END CloseProfile;
END Profile.
