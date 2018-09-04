IMPLEMENTATION MODULE EditFonts; (* vs I.11         Werner Winiger 14.6.82
                      =========  *)

  FROM Screen IMPORT
    Font, LoadFont, Proportional, CharWidth, FontWidth, FontHeight,
    GetSystemFont;


  PROCEDURE LoadFonts (VAR name: ARRAY OF CHAR);
  VAR
    ok: BOOLEAN;

  BEGIN
    GetSystemFont(defaultFont);
    IF name[0] = 0c THEN
      editFont := defaultFont;
    ELSE
      LoadFont(editFont,name,ok);
      IF (NOT ok) OR Proportional(editFont) THEN editFont := defaultFont; END;
    END;

    charSize := FontWidth(editFont);
    lineSize := FontHeight(editFont) + 1;
    menuCharSize := FontWidth(defaultFont);
    menuLineSize := FontHeight(defaultFont) + 1;

    controlCharsAvailable := (CharWidth(editFont,202c) 
                             * CharWidth(editFont,2c)) # 0;
  END LoadFonts;

END EditFonts.
