(*******************************************************************************
********************************************************************************
***                                                                          ***
***                       Main Module                                        ***
***                                                                          ***
***                       MM      MM  IIII   AAAAAAAA                        ***
***                       MMM    MMM  IIII  AAAAAAAAAA                       ***
***                       MMMM  MMMM   II   AA      AA                       ***
***                       MM MMMM MM   II   AA      AA                       ***
***                       MM  MM  MM   II   AAAAAAAAAA                       ***
***                       MM      MM   II   AAAAAAAAAA                       ***
***                       MM      MM   II   AA      AA                       ***
***                       MM      MM   II   AA      AA                       ***
***                       MM      MM  IIII  AA      AA                       ***
***                       MM      MM  IIII  AA      AA                       ***
***                                                                          ***
***                           Micro  -  ASSEMBLER                            ***
***                            for   L I L I T H                             ***
***                                                                          ***
***                       Version 20           9.04.82                       ***
***                       W. Winiger         G. Schild                       ***
***                                                                          ***
********************************************************************************
********************************************************************************

                History
                =======
                13: T-
                14: speed field implemented (bit 15 of the UInstr )
                15: speed categories implemented
                16: P and M registers introduced
                    opcodes printed in listing
                    binary code written in the MOTOROLA format
                                split in five files
                17: bus destination BNK added
                    random access map concept introduced
                18: translated into MODULA2
                               split in seven modules
                    reduced speed categories (only "-" and "S"=slow)
                    local label concept introduced.
                                according options added
                                (.$L-   .$L+   .$L* )
                    binary code and map written in the format for 
                                the PROMBurner
                                united binary code in one file
                19: binary code written optional in the PROMBurner format
                                or in MOTOROLA format on five files
                                or both
                20: input may come from several files                   *)



MODULE MIA;

FROM Terminal   IMPORT Read, Write, WriteString, WriteLn;
FROM FileNames  IMPORT ReadFileName, Identifiers, IdentifierPosition;
FROM Options    IMPORT FileNameAndOptions, Termination;
FROM FileSystem IMPORT File, Response, Lookup;
FROM LongFiles  IMPORT FileName, LongFileName, maxNumberOfFiles, OpenNextInputFile;
FROM TextIO     IMPORT GetLine, Print, PrintChar, WriteList,
                       NewPage, ErrorNotes, LineCount, Correct, fullPage, eol;
FROM BinFile    IMPORT WriteCode, WriteMotorola;
FROM Labels     IMPORT OpenJump, PrintLabList;
FROM MapHandler IMPORT PrintMap, WriteMap;
FROM Assembler  IMPORT GetAnInstr;

CONST titel = "     LABEL     K DST FCT RS C  A  B  SHFT SP PC S E BD  BS   COMMENT              USED REGS";
     

VAR mapName, codeName,
    mot1Name, mot2Name, mot3Name, mot4Name, mot5Name : FileName;
    inputName, listName : LongFileName;
    term : Termination;
    inputLine : ARRAY [0..79] OF CHAR;
    enoughInputFiles,
    found,
    allIsDone : BOOLEAN;
    f, i, p, q : CARDINAL;
    ch : CHAR;


BEGIN
WriteString(" MIA VS.20 (8.4.82)");
WriteLn;
(* get the input-file-name and
compose the name of the files to be generated *)
f := 0;
enoughInputFiles := FALSE;
  REPEAT (* open the inputfiles *)
  INC(f);
    LOOP (* open one file *)
      LOOP (* read a valid filename *)
      Write(" ");
      Write(CHAR(f + ORD('0')));
      WriteString(". input file > ");
      IF f = 1 THEN
      FileNameAndOptions("DK.Interpreter.MIC",inputName[f],term,FALSE);
      ELSE
      FileNameAndOptions(inputName[f-1],inputName[f],term,FALSE);
      END;
        CASE term OF
        normal: EXIT; |
        empty: 
          IF f = 1 THEN
          WriteString(" ---- empty filename");
          WriteLn;
          ELSE
          q := Identifiers(inputName[f-1]);
          p := IdentifierPosition(inputName[f-1],q)-1;
            IF inputName[f-1][p] = CHAR(f-1 + ORD('0')) THEN
            inputName[f] := inputName[f-1];
            inputName[f][p] := CHAR(ORD(inputName[f][p])+1);
            WriteString(inputName[f]);
            EXIT;
            ELSE
            WriteString(" ---- empty filename");
            WriteLn;
            END;  
          END; |
        can: 
        WriteLn; |
        esc: 
        enoughInputFiles := TRUE;
        EXIT;
        END;
        WriteLn;
      END; (* read a valid filename LOOP *)
  
      IF enoughInputFiles 
      THEN 
        IF f=1 
        THEN RETURN;
        ELSE EXIT; 
        END;
      END;
    OpenNextInputFile(inputName[f],found);
      IF found THEN 
      EXIT 
      END;
    WriteString(" ---- file not found");
    WriteLn;
    END; (* open one file LOOP *)
    WriteLn;
  IF f = maxNumberOfFiles 
  THEN 
  enoughInputFiles := TRUE; 
  INC(f); (* enough INC's := TRUE too *)
  END;
  UNTIL enoughInputFiles;
DEC(f);

WriteLn;
q := Identifiers(inputName[1])-1;
  IF q = 1 (* the input-file has no extension *)
  THEN WriteString(" give your file a name with an extension, please");
  WriteLn;
  RETURN;
  ELSE p := IdentifierPosition(inputName[1],q)
  END;
mapName := inputName[1];
mapName[p]    := "M";
mapName[p+1]  := "A";
mapName[p+2]  := "P";
mapName[p+3]  := 0C;
codeName := inputName[1];
codeName[p]   := "B";
codeName[p+1] := "I";
codeName[p+2] := "N";
codeName[p+3] := 0C;
mot1Name := inputName[1];
mot1Name[p]   := "B";
mot1Name[p+1] := "M";
mot1Name[p+2] := "1";
mot1Name[p+3] := 0C;
mot2Name := mot1Name;
mot2Name[p+2] := "2";
mot3Name := mot1Name;
mot3Name[p+2] := "3";
mot4Name := mot1Name;
mot4Name[p+2] := "4";
mot5Name := mot1Name;
mot5Name[p+2] := "5";
  FOR i := 1 TO f DO
  q := Identifiers(inputName[i])-1; 
  IF q = 1 THEN WriteString(" give your file a name with an extension, please"); END;
  p := IdentifierPosition(inputName[i],q);
  listName[i] := inputName[i];
  listName[i][p]   := "L";
  listName[i][p+1] := "S";
  listName[i][p+2] := "T";
(*
  this algorithm overwrites the first three characters of the extension of every
  filename; if the filenames were distinct only within this area, MIA will have 
  troubles 
*)
  END;

(* assembling run : line after line *) 
  WriteString(" reading and assembling input"); WriteLn;
  REPEAT
  GetLine(inputLine,allIsDone);
    IF LineCount() = fullPage
    THEN NewPage; Print(titel); PrintChar(eol) 
    END;
  GetAnInstr(inputLine)
  UNTIL allIsDone;

(* termination of the program including writing of the files *)
IF OpenJump() THEN PrintLabList END;
PrintMap;
  IF Correct()
  THEN 
  WriteString(" writing map file"); WriteLn;
  WriteMap(mapName);
  WriteString(" regular format (for PROMBurner), Motorola format, or both (-/m/b)> ");
  Read(ch); Write(ch); WriteLn;
    CASE ch OF
    "m" : WriteString(" writing Motorola files"); WriteLn;
          WriteMotorola(mot1Name,mot2Name,mot3Name,mot4Name,mot5Name)
        |
    "b" : WriteString(" writing Motorola files"); WriteLn;
          WriteMotorola(mot1Name,mot2Name,mot3Name,mot4Name,mot5Name);
          WriteString(" writing code file"); WriteLn; WriteCode(codeName)
    ELSE WriteString(" writing code file"); WriteLn; WriteCode(codeName)
    END
  ELSE
  WriteString("   ---- error"); WriteLn;
  ErrorNotes
  END;
WriteString(" writing listing"); WriteLn;
WriteList(listName);
WriteString(" end MIA"); WriteLn;
END MIA.
