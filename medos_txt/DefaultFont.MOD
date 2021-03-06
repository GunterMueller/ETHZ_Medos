IMPLEMENTATION MODULE DefaultFont;  (* Werner Winiger 14.6.82
                      ===========      for the system of june 1982
                                       with an extended GACHA12 as default font *)

  FROM SYSTEM IMPORT ADR;

  CONST
    FontLength = 2612b;

  VAR
    FontSpace: ARRAY [0..FontLength+3] OF CARDINAL;

  PROCEDURE Initialize;
    VAR
      f,d,i: CARDINAL;
  BEGIN
    f := ADR(FontSpace);
    d := ((f + 3) DIV 4) * 4 - f;     (* difference between f and the next   *)
    IF d <> 0                         (* address which is a multiple of four *)
    THEN
      i := FontLength+1;              (* the font must be aligned *)
      REPEAT
        DEC(i);
        FontSpace[i+d] := FontSpace[i];
      UNTIL i = 0;
    END;
    defaultFont := (f + d + 4) DIV 4; (* defaultFont is a framepointer which points *)
  END Initialize;                     (* to the 1st location of the pointertable in *)
                                      (* the font (located at word 4 of the fontfile *)
BEGIN
  Initialize;
END DefaultFont.
