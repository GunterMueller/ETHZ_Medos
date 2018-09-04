IMPLEMENTATION MODULE DecoStatistic; (* Ch. Jacobi 1.4.81*)

  FROM SYSTEM IMPORT 
    WORD;
  FROM FileSystem IMPORT 
    File, Lookup, Close, WriteWord;
  FROM DecoMachineDef IMPORT
    MnemoTab;
  FROM FileNames IMPORT
    ReadFileName, Identifiers, IdentifierPosition;
  

  PROCEDURE ReplaceExtension(newExt: ARRAY OF CHAR; VAR fn: ARRAY OF CHAR);
    VAR i, extPos: CARDINAL;
  BEGIN 
    i := Identifiers(fn);
    IF i=0 THEN extPos := 0
    ELSE
      extPos := IdentifierPosition(fn, i-1)
    END;
    i := 0;
    LOOP
      IF extPos>HIGH(fn) THEN EXIT END;
      IF i>HIGH(newExt) THEN 
        fn[extPos] := 0c; EXIT
      END;
      fn[extPos] := newExt[i];
      INC(i); INC(extPos)
    END 
  END ReplaceExtension;


    VAR InstructionCount: ARRAY [0..255] OF CARDINAL;
        icnt2: ARRAY [0..255] OF CARDINAL;

    VAR statf: File;
        name: ARRAY [0..24] OF CHAR;


    PROCEDURE InitStatistic(fn: ARRAY OF CHAR);
      VAR i: CARDINAL;
    BEGIN
      FOR i := 0 TO 255 DO InstructionCount[i] := 0; icnt2[i] := 0 END;
      ReplaceExtension("BNST", fn);  
      i := 0;
      LOOP 
        IF (i>HIGH(name))THEN EXIT END;
        IF (i>HIGH(fn)) THEN name[i] := 0c; EXIT END;
        name[i] := fn[i]; INC(i)
      END;
    END InitStatistic;

    PROCEDURE CloseStatistic;
      VAR i: INTEGER;
    BEGIN
      Lookup(statf, name, TRUE);  (* create new file *) 
      FOR i := 0 TO 255 DO
        WriteWord(statf, InstructionCount[i]); 
      END;
      FOR i := 0 TO 255 DO
        WriteWord(statf, icnt2[i]); 
      END;
      Close(statf);
    END CloseStatistic;
 
    PROCEDURE Count(inst: WORD);
      VAR i: CARDINAL;
    BEGIN
      i := CARDINAL(inst) MOD 400B;
      IF InstructionCount[i]<177777B THEN 
        INC(InstructionCount[i]) 
      ELSE 
        INC(icnt2[i]); 
        InstructionCount[i] := 0; 
      END;  
    END Count

END DecoStatistic.
