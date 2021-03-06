MODULE SIL;
(* Program: Simple ILustrator, an editor for line drawings.
   Date:    1.2.83
   Author:  N.Wirth
            Institut fur Informatik, ETH Zurich
            Switzerland  *)

  FROM Terminal IMPORT Read, Write, WriteString;
  FROM SilDisplay IMPORT
    BMWidth, FontHeight, PaintRectangle,
    ShowChar, UpLow, SetTicks, ClearMap, LoadFont;
  FROM SilInput IMPORT
    ReadKey, com, com1,
    CurrentFont, LineWidth, Grid, Umlaut, FontMenu;
  FROM SilObjects IMPORT
    DrawLine, MakeString, Fill, Backspace, CloseString,
    Select, Deselect, Move, Copy, Delete,
    MakeMacro, Rebuild, Input, Output,
    OpenMacro, CloseMacro, Restart;
  FROM Profile IMPORT
    OpenProfile, FindKey, GetFileName, GetString, GetNumber, CloseProfile;

  CONST X0 = 16; Y0 = 64;  (*origin coord. of messages*)
    NL = 27;    (*file name length*)

  VAR ticks, up, done: BOOLEAN;
    mac:  BITSET;
    X,Y:  INTEGER;   (*coord. of last char of file name*)
    H:    INTEGER;   (*font height*)
    name: ARRAY [0..NL] OF CHAR;
    K:    CARDINAL;  (*index of last char of file name*)
    pos:  ARRAY [0..NL] OF INTEGER;
    option: CHAR;

  PROCEDURE ClearMsg;
  BEGIN PaintRectangle(3,X0,Y0,X-X0,H)
  END ClearMsg;
 
  PROCEDURE msg(s: ARRAY OF CHAR);
    VAR i: CARDINAL;
  BEGIN ClearMsg; i := 0; X := X0; Y := Y0;
    REPEAT ShowChar(s[i],0,X,Y); i := i+1
    UNTIL i > HIGH(s)
  END msg;

  PROCEDURE reply;
  BEGIN
    IF done THEN msg("done") ELSE msg("NOT done") END
  END reply;

  PROCEDURE ReadFileName(default: ARRAY OF CHAR);
    VAR j,i: CARDINAL;
  BEGIN msg("file: "); i := 3; pos[2] := X;
    WHILE i < K DO
      ShowChar(name[i],0,X,Y); i := i+1
    END ;
    ReadKey;
    IF com > 40B THEN
      PaintRectangle(3, pos[2], Y0, X-X0, H);
      X := pos[2]; i := 3;
      WHILE (40B < com) & (com < 200B) DO
        IF com < 177B THEN
          IF i < NL THEN
            name[i] := CHAR(com); pos[i] := X; i := i+1;
            ShowChar(CHAR(com),0,X,Y)
          END
        ELSIF i > 3 THEN (*backspace*)
          i := i-1;
          PaintRectangle(3, pos[i], Y0, X-pos[i], H);
          X := pos[i]
        END ;
        ReadKey
      END
    END ;
    K := i;
    IF (name[i-1] = ".") & (i > 3) THEN
      j := 0;
      REPEAT name[i] := default[j];
        ShowChar(name[i],0,X,Y); i := i+1; j := j+1
      UNTIL (j > HIGH(default)) OR (i = NL)
    END ;
    name[i] := 0C
  END ReadFileName;

BEGIN WriteString(" SIL 5.0  option: (-/c) ");
  REPEAT Read(option) UNTIL (option <= " ") OR (option = "c");
  IF option = "c" THEN
    Write("c"); OpenProfile('"SILc"')
  ELSE
    OpenProfile('"SIL"')
  END ;
  name[0] := "D"; name[1] := "K"; name[2] := ".";
  mac := {}; done := TRUE;
  FindKey("'F0'"); GetFileName(name, "SCF"); LoadFont(0, name, done);
  FindKey("'F1'"); GetFileName(name, "SCF"); LoadFont(1, name, done);
  FindKey("'F2'"); GetFileName(name, "SCF"); LoadFont(2, name, done);
  FindKey("'F3'"); GetFileName(name, "SCF"); LoadFont(3, name, done);
  FindKey("'FMenu'"); GetString(FontMenu);
  FindKey("'M0'"); GetFileName(name, "SILM");
  IF name[3] # "0" THEN OpenMacro(0, name, done); INCL(mac, 0) END ;
  FindKey("'M1'"); GetFileName(name, "SILM");
  IF name[3] # "0" THEN OpenMacro(1, name, done); INCL(mac, 1) END ;
  CloseProfile; Write(14C);

  IF done THEN
    X := X0; H := FontHeight[0];
    Restart(FALSE);
    K := 3; ticks := TRUE; up := FALSE; SetTicks; com := 254B;
  LOOP
    IF com < 40B THEN
      IF com = 12B THEN Rebuild;
        IF ticks THEN SetTicks END
      ELSIF com = 16B THEN
        up := NOT up; UpLow(up); Rebuild;
        IF ticks THEN SetTicks END
      ELSIF com = 24B THEN
        IF ticks THEN Rebuild; ticks := FALSE
                 ELSE SetTicks; ticks := TRUE
        END
      ELSIF com = 25B THEN Umlaut := NOT Umlaut
      ELSIF com = 33B THEN Delete
      END ;
      ReadKey
    ELSIF com = 177B THEN Delete; ReadKey
    ELSIF com < 240B THEN
      Deselect; MakeString;
      REPEAT Fill(CHAR(com)); ReadKey;
        WHILE com = 177B DO
          Backspace; ReadKey
        END
      UNTIL (com < 40B) OR (com >= 240B);
      CloseString
    ELSE
      CASE com-240B OF
   0:   |
   1:   Deselect; DrawLine |
   2:   |
   3:   Move |
   4:   Deselect; Select |
   5:   Copy |
   6:   Select |
   7:   |
  10B:  Grid := com1 |
  11B:  LineWidth := com1 + 1 |
  12B:  CurrentFont := com1 |
  13B:  ReadFileName("SIL");
        IF com # 33B THEN
          Output(name, (BMWidth - 640) DIV 2, done)
        ELSE done := FALSE
        END ;
        reply |
  14B:  K := 3; ReadFileName("SIL");
        IF com # 33B THEN
          Input(name, (BMWidth - 640) DIV 2, done)
        ELSE done := FALSE
        END ;
        reply |
  15B:  IF 0 IN mac THEN
          Deselect; msg("Type code!"); ReadKey;
          ClearMsg; MakeMacro(com,0)
        END |
  16B:  IF 1 IN mac THEN
          Deselect; msg("Type code!"); ReadKey;
          ClearMsg; MakeMacro(com,1)
        END |
  17B:  msg("exit?"); ReadKey;
        IF com = 162B THEN
          Restart(TRUE);
          IF ticks THEN SetTicks END
        ELSIF com = 171B THEN EXIT
        END
      END ;
      ReadKey
    END
  END (*LOOP*) ;
    Write(14C)
  ELSE WriteString(" font or macro loading failed"); Write(36C)
  END ;
  IF 0 IN mac THEN CloseMacro(0) END ;
  IF 1 IN mac THEN CloseMacro(1) END
END SIL.
