IMPLEMENTATION MODULE MCP4Global;   (* Ch. Jacobi 5.4.81 *)
                                    (* mod: LG 12.11.82 *)
(* global variables and procedures 
   for Pass 4 of the Compiler for the Lilith Computer *)


  IMPORT 
    SYSTEM, CompFile, MCPublic, MCBase, MCP4CodeSys;
  FROM WriteStrings IMPORT 
    WriteString, WriteLn;

MODULE io;
  FROM SYSTEM IMPORT WORD;
  FROM CompFile IMPORT
    Reset, WriteWord, ReadWord, GetPos, SetPos, ModifyWord;
  FROM MCPublic IMPORT objFile, il1File, il2File;
  IMPORT flags, loadAddress;
  EXPORT 
    WriteCodeWord, ReadInputWord, WriteIntermediateWord, 
    CloseIO, MarkCodePos;

  VAR markhigh, marklow: CARDINAL;

  PROCEDURE WriteCodeWord(w: WORD);
  BEGIN
    WriteWord(objFile, w)
  END WriteCodeWord;

  PROCEDURE ReadInputWord(VAR w: WORD);
  BEGIN
    ReadWord(il1File, w)
  END ReadInputWord;

  PROCEDURE WriteIntermediateWord(w: WORD);
  BEGIN
    WriteWord(il2File, w)
  END WriteIntermediateWord;

  PROCEDURE MarkCodePos;
  BEGIN
    GetPos(objFile, markhigh, marklow)
  END MarkCodePos;
 
  PROCEDURE CloseIO;
  BEGIN
    (* code file *)
         IF (markhigh<>177777B) OR (marklow<>177777B) THEN
           Reset(objFile);
           SetPos(objFile, markhigh, marklow);
           ModifyWord(objFile, loadAddress);
           ModifyWord(objFile, flags);
         END;
         Reset(objFile);
    (* intermediate file for listing *)
         Reset(il2File);
    (* input file *)
  END CloseIO;

BEGIN  
  markhigh := 177777B; marklow := 177777B;
  (* open files *)
  (* Intermediate file for listing *)
       Reset(il2File);
  (* code file *)
       Reset(objFile);
  (* input file *)
       Reset(il1File);
END io;



MODULE Scanner;
  FROM MCBase IMPORT Symbol, Idptr, Stptr, Stringptr;
  FROM CompFile IMPORT ReadWord, EndFile;
  FROM io IMPORT ReadInputWord, WriteIntermediateWord;
  FROM Globals IMPORT CompilerError;
  FROM MCP4CodeSys IMPORT PC;
  FROM MCPublic IMPORT il1File;
  IMPORT
    loadAddress,
    sy, val, nptr, cstPtr, cString, 
    controlRangeCheck, arithmeticRangeCheck;
  EXPORT 
    GetSymbol, position, line;


  VAR
    position: CARDINAL; (* Position within a line; set for each Symbol *)
    line: CARDINAL;     (* line number; set for each Symbol *) 

 
    PROCEDURE PutLineHeader;
    BEGIN 
      WriteIntermediateWord(line);
      WriteIntermediateWord(CARDINAL(PC)+2*loadAddress);
    END PutLineHeader;


    PROCEDURE OptionCode;   
      (* Treat a compiler directive *)
    BEGIN  
      IF CHAR(val) = 'T' THEN GetSymbol;  
        controlRangeCheck := sy = plus   
      ELSIF CHAR(val) = 'R' THEN GetSymbol;  
        arithmeticRangeCheck := sy = plus   
      ELSE
        GetSymbol 
      END;  
      GetSymbol
    END OptionCode;  
  

    PROCEDURE GetSymbol;   
      (* Read one Symbol (skipping the eol)
         and set exported variables *)
    BEGIN
      REPEAT  
        (*ReadInputWord(i);*) ReadWord(il1File, position);
        IF EndFile(il1File) THEN sy := eop  
        ELSE  
          sy := Symbol(position DIV 400B)
        END;  
        IF sy<proceduresy THEN RETURN END;
        IF (sy=namesy) OR (sy=modulesy) OR (sy=proceduresy) THEN  
          ReadInputWord(nptr)   
        ELSIF sy = eol THEN 
          ReadInputWord(line); PutLineHeader 
        ELSIF sy = field THEN ReadInputWord(val)  
        ELSIF sy = option THEN  
          ReadInputWord(val);  
          OptionCode  
        ELSIF sy=anycon THEN  
          ReadInputWord(cstPtr);  
          ReadInputWord(cString); val := INTEGER(cString)  
        END;  
      UNTIL sy<>eol   
    END GetSymbol;  
  

BEGIN  (* init scanner *)
  controlRangeCheck := TRUE; 
  arithmeticRangeCheck := TRUE; 
  line := 1  
END Scanner;



MODULE Globals;
  FROM MCPublic IMPORT passerrs, compstat;
  FROM MCBase IMPORT procnumber;
  FROM io IMPORT WriteIntermediateWord;
  FROM Scanner IMPORT line, position;
  IMPORT 
    loadCount, level, spPosition, loadAddress,
    flags, WriteString, WriteLn;
  EXPORT 
    Error, CompilerError, Assert;


  PROCEDURE CompilerError;  

    PROCEDURE Debug;
      PROCEDURE WriteCardinal(value: CARDINAL);
        CONST length = 7;
        VAR i: CARDINAL;
            a: ARRAY [0..length-1] OF CHAR;
      BEGIN
        i := length; 
        REPEAT
          DEC(i);
          a[i] := CHAR(value MOD 10 + CARDINAL("0"));
          value := value DIV 10; 
        UNTIL value = 0;
        WHILE i>0 DO DEC(i); a[i] := " " END;
        WriteString(a);
      END WriteCardinal;
    BEGIN (*Debug*)
      WriteString("line "); WriteCardinal(line); 
      WriteString("   position "); WriteCardinal(position); WriteLn;
      WriteString("loadcount "); WriteCardinal(loadCount); 
      WriteString("   loadAddress "); WriteCardinal(loadAddress); WriteLn;
      WriteString("Its probably a hardware error;"); WriteLn;
      (*If YOU modify the compiler, please remove my name from the next line*)
      WriteString("If NOT, Chris needs the dump, the text written"); WriteLn;
      WriteString("out above and the source of your program"); WriteLn;
      WriteString("to debug the compiler"); WriteLn;
    END Debug;

  BEGIN (*CompilerError*)
    WriteString("Compiler Error "); WriteLn;  
    INCL(compstat, passerrs);  
    Debug;
    HALT (*produces a dump on the medos operative system!*)
  END CompilerError;  
  

  PROCEDURE Assert (fb: BOOLEAN); 
    (*see definition module*)
  BEGIN
    IF NOT fb THEN CompilerError END  
  END Assert;  


  PROCEDURE Error(n: INTEGER);   
  BEGIN  
    WriteIntermediateWord(-n);
    WriteIntermediateWord(position MOD 400B); 
    INCL(compstat, passerrs)  
  END Error;  
    

BEGIN  
  (* init global variables *)
  loadCount := 0;
  level := 0;  
  spPosition := 0;
  loadAddress := procnumber; 
                 (*follows the procedure offset table*)
  flags := {};
END Globals;


END MCP4Global.
