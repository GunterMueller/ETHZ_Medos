IMPLEMENTATION MODULE EditFiles; (* vs I.11         Werner Winiger 28.2.83
                      =========   *)
 
  FROM SYSTEM IMPORT
    ADR, ADDRESS;
  FROM FileSystem IMPORT
    File, Response, Flag, Rename, Lookup, Create, Close, Length,
    SetPos, GetPos, SetOpen, SetModify, Reset, Doio, ReadChar, WriteChar;
  FROM EditDisplay IMPORT
    SysErr, Options, optionSet;
  FROM FileNames IMPORT
    Identifiers, IdentifierPosition;

  CONST
    SectorSize = 256;
    new   = TRUE;
    old   = FALSE;
    NULL  = 0c;
    EOF   = 34c;
    EOL   = 36c;
    DEL   = 177c;
    BLANK = " ";

  TYPE
    FilePtr = POINTER TO File;
    Sector  = ARRAY [0..SectorSize-1] OF CHAR;
    FileName = ARRAY [0..31] OF CHAR;

  VAR
    CF             : FilePtr;
    nextFno        : [0 .. maxFileNo+1];
    MacroFile,
    WF, OutF, BF   : File;
    InF            : ARRAY [firstFno..maxFileNo] OF File;
    Name           : ARRAY [firstFno..maxFileNo] OF FileName;
    alreadyWritten : ARRAY [firstFno..maxFileNo] OF BOOLEAN;
    lastbuf        : Sector;
    BX, WX, bufpos,
    block, byte,
    pos            : CARDINAL;
    outputName     : FileName;
    doio,
    fromInsFile    : BOOLEAN;


  PROCEDURE Assign (VAR to: ARRAY OF CHAR; from: ARRAY OF CHAR);
    VAR
      highTo, highFrom, i: CARDINAL;
  BEGIN
    i := 0;
    highTo := HIGH(to);
    highFrom := HIGH(from);
    LOOP
      to[i] := from[i];
      IF from[i] = 0c THEN RETURN; END;
      IF i = highTo THEN RETURN; END;
      INC(i);
      IF i > highFrom THEN to[i] := 0c; RETURN; END;
    END;
  END Assign;


  PROCEDURE GetName (f: FileNo; VAR name: ARRAY OF CHAR);
  BEGIN (*  -------                                   *)
    IF f = 0 THEN Assign(name, "DK.Temp.MOD");
    ELSE Assign(name, Name[f]);
    END;
  END GetName;

  PROCEDURE Equal (VAR s1,s2: ARRAY OF CHAR): BOOLEAN;
    VAR (*  -----                         *)
      i,h: CARDINAL;
  BEGIN
    h := HIGH(s2);
    IF h <> HIGH(s1) THEN RETURN(FALSE); END;
    i := 0;
    LOOP
      IF s1[i] <> s2[i] THEN RETURN(FALSE); END;
      IF (s1[i] = 0c) OR (i = h) THEN RETURN(TRUE); END;
      INC(i);
    END;
  END Equal;

                          (* access to the inputfiles InF[i] as CF^ *)

  PROCEDURE OpenFile (name: ARRAY OF CHAR; VAR f: FileNo; VAR l: CARDINAL);
  BEGIN (*  --------                                                    *)
    IF nextFno > maxFileNo THEN 
      f := 0; l := 1;
      RETURN
    END;

    f := firstFno;
    LOOP
      IF f = nextFno THEN EXIT; END;
      IF Equal(name,Name[f]) THEN
        IF alreadyWritten[f] THEN
          f := 0; l := 2;
        ELSE
          CF := FilePtr(ADR(InF[f]));
          Length(CF^,block,l);
        END;
        RETURN;
      END;
      INC(f);
    END;

    CF := FilePtr(ADR(InF[nextFno]));
    Lookup(CF^,name,old);
    IF CF^.res = done THEN
      Length(CF^,block,l);
      IF block > 0 THEN
        f := 0; l := 3;
        Close(CF^);
      ELSE
        Assign(Name[f],name);
        INC(nextFno);
      END;
    ELSE
      f := 0; l := 0;
    END;
  END OpenFile;
 
  PROCEDURE thisCH (fn, chn: CARDINAL): CHAR;
    VAR (*  ------                  *)
      ch: CHAR;
  BEGIN
    pos := chn;
    fromInsFile := fn = InsFno;
    IF fromInsFile
    THEN CF := FilePtr(ADR(WF));
    ELSE CF := FilePtr(ADR(InF[fn]));
    END;

    IF fromInsFile & (pos >= bufpos)
    THEN
      ch := lastbuf[pos-bufpos];
    ELSE
      SetPos(CF^,0,pos);
      ReadChar(CF^,ch);
    END;
    INC(pos);
    RETURN ch;
  END thisCH;

  PROCEDURE nextCH  (): CHAR;
    VAR (*  ------  *)
      ch: CHAR;
  BEGIN
    IF fromInsFile & (pos >= bufpos)
    THEN ch := lastbuf[pos-bufpos];
    ELSE ReadChar(CF^,ch);
    END;
    INC(pos);
    RETURN ch;
  END nextCH;

  PROCEDURE prevCH (): CHAR;
    VAR (*  ------ *)
      ch: CHAR;
  BEGIN
    IF fromInsFile & (pos > bufpos+1)
    THEN
      ch := lastbuf[pos-bufpos-2];
    ELSE
      SetPos(CF^,0,pos-2);
      ReadChar(CF^,ch);
    END;
    DEC(pos);
    RETURN ch;
  END prevCH;

  PROCEDURE AppendBAK (VAR fn: FileName; VAR extpos: CARDINAL);
  BEGIN
    extpos := Identifiers(fn);
    extpos := IdentifierPosition(fn,extpos-1);
    fn[extpos] := 'B';
    IF extpos < 31 THEN 
      fn[extpos+1] := 'A';
      IF extpos < 30 THEN 
        fn[extpos+2] := 'K';
        IF extpos < 29 THEN 
          fn[extpos+3] := NULL;
        END;
        extpos := extpos+2;
      ELSE
        extpos := extpos+1;
      END;
    END;
  END AppendBAK;

  PROCEDURE RenameInputFile (f: FileNo; VAR ok: BOOLEAN);
    VAR (*  ---------------                           *)
      F: File;
      fN: FileName;
      extpos,i: CARDINAL;
  BEGIN
    fN := outputName;
    AppendBAK(fN,extpos);
    i := 0;
    ok := TRUE;
    LOOP
      Lookup(F,fN,old);
      IF F.res = done THEN
        Rename(F,'');
        Close(F);
      END;
      Rename(InF[f],fN);
      IF InF[f].res = done THEN EXIT; END;
      IF InF[f].res = softprotected THEN ok := FALSE; EXIT; END;
      INC(i);
      fN[extpos] := CHAR(CARDINAL(fN[extpos])+i);
    END;
  END RenameInputFile;

  PROCEDURE CloseFiles;
    VAR (*  ----------  *)
      i: CARDINAL;
  BEGIN
    FOR i := firstFno TO nextFno-1 DO Close(InF[i]); END;
    Rename(BF,''); Close(BF);
    Close(WF);
  END CloseFiles;

                                        (* access to Edit.INS as WF *)
  PROCEDURE PutChar (ch: CHAR);
  BEGIN (*  -------         *)
    lastbuf[WX] := ch;
    INC(WX);
    IF WX = SectorSize
    THEN
      SetOpen(WF);
      SetPos(WF,0,bufpos);
      FOR WX := 0 TO SectorSize-1 DO 
        WriteChar(WF,lastbuf[WX]); 
        IF WF.res <> done THEN SysErr('WriteChar on Edit.INS not done'); END;
      END;
      SetOpen(WF);
      INC(bufpos,SectorSize);
      WX := 0;
    END;
  END PutChar;

  PROCEDURE DelChar;
    VAR (*  -------  *)
      ch:CHAR;
  BEGIN
    IF WX > 0
    THEN 
      DEC(WX);
    ELSE
      DEC(bufpos,SectorSize);
      SetOpen(WF);
      SetPos(WF,0,bufpos);
      FOR WX := 0 TO SectorSize-1 DO 
        ReadChar(WF,ch); lastbuf[WX] := ch;
      END;
      SetOpen(WF);
      WX := SectorSize-1;
    END;
  END DelChar;

  PROCEDURE CharPos (): CARDINAL;
  BEGIN (*  ------- *)
    RETURN (bufpos+WX);
  END CharPos;

                               (* access to the outputfiles as OutF *)

  PROCEDURE OpenOutputFile (name: ARRAY OF CHAR; backup: BOOLEAN; VAR ok: BOOLEAN);
    VAR (*  --------------                                                      *)
      f: [0 .. maxFileNo+1];
  BEGIN
    IF backup THEN
      f := firstFno;
      WHILE f < nextFno DO
        IF Equal(name,Name[f]) THEN
          IF alreadyWritten[f] THEN
            ok := FALSE;
            RETURN;
          END;
        END;
        INC(f);
      END;
      ok := TRUE;
      Assign(outputName,name);
      Create(OutF,"DK");
      IF OutF.res <> done THEN SysErr('create not done'); END;
    ELSE
      Lookup(OutF,name,new);
      ok := (OutF.res = done) AND OutF.new;
      IF ok THEN Assign(outputName,name); 
      ELSE Close(OutF);
      END;
    END;
  END OpenOutputFile;

  PROCEDURE CloseOutputFile (f: FileNo; VAR ok: BOOLEAN);
    VAR (*  ---------------                           *)
      F: File;
      bakname: FileName;
      ex: CARDINAL;
  BEGIN
    IF f = 0 THEN
      Lookup(F,outputName,FALSE); 
      IF F.res = done THEN
        Close(F);
        Assign(bakname,outputName);
        AppendBAK(bakname,ex);
        Lookup(F,bakname,FALSE);
        Rename(F,'');
        Close(F);
        Lookup(F,outputName,FALSE);
        Rename(F,bakname);
      END;
      Close(F);
    ELSE
      RenameInputFile(f,ok);
      IF NOT ok THEN RETURN; END;
      alreadyWritten[f] := TRUE;
    END;
    Rename(OutF,outputName);
    Close(OutF);
    ok := TRUE;
  END CloseOutputFile;

  PROCEDURE OutChar (ch: CHAR);
  BEGIN (*  -------         *)
    WriteChar(OutF,ch);
  END OutChar;

                                   (* access to the Edit.RPL as BF *)
  PROCEDURE BkRead (): CARDINAL;
    VAR (*  ------ *)
      ch: CHAR;
  BEGIN
    IF macro THEN
      ReadChar(MacroFile,ch);
    ELSE
      ReadChar(BF,ch);
      IF learning THEN WriteChar(MacroFile,ch); END;
      IF BF.eof THEN ch := EOF; END;
    END;
    RETURN CARDINAL(ch);
  END BkRead;

  PROCEDURE BkSwitch;  (*from read to write*)
  BEGIN (*  --------                       *)
    SetOpen(BF);
    GetPos(BF,block,BX);
    replay := FALSE;
  END BkSwitch;

  PROCEDURE BkWrite (x: CARDINAL);
  BEGIN (*  -------            *)
    IF learning THEN WriteChar(MacroFile,CHAR(x)); END;
    WriteChar(BF,CHAR(x));
    IF BF.res <> done THEN SysErr('WriteChar on replay-file not done'); END;
    INC(BX);
    IF BX MOD 16 = 0 THEN doio := TRUE; END;
  END BkWrite;

  PROCEDURE BkSave;
  BEGIN (*  ------  *)
    IF doio THEN
      SetOpen(BF);
      doio := FALSE;
    END;
  END BkSave;


  PROCEDURE InitLearning;
  BEGIN (*  ------------ *)
    learning := TRUE;
    Reset(MacroFile);
  END InitLearning;


  PROCEDURE InitMacro;
  BEGIN (*  --------- *)
    macro := TRUE;
    Reset(MacroFile);
  END InitMacro;


  PROCEDURE InitMacroFile;
  BEGIN (*  -------------  *)
    Create(MacroFile,'DK');
    IF MacroFile.res <> done THEN SysErr('create macrofile not done'); END;

    WriteChar(MacroFile,0c);
    WriteChar(MacroFile,2c);        (* B2 *)
    WriteChar(MacroFile,0c);        (* area *)
    WriteChar(MacroFile,4c);        (* WINDOW *)

    WriteChar(MacroFile,0c);
    WriteChar(MacroFile,4c);        (* B3 *)
    WriteChar(MacroFile,2c);        (* area *)
    WriteChar(MacroFile,21c);       (* Mline *)
    WriteChar(MacroFile,50c);       (* Mcol *)
    WriteChar(MacroFile,1c);        (* McolSel *)
    WriteChar(MacroFile,21c);       (* Mline *)
    WriteChar(MacroFile,50c);       (* Mcol *)

    WriteChar(MacroFile,'.');       (* . *)
    WriteChar(MacroFile,EOL);       (* RETURN *)

    WriteChar(MacroFile,0c);
    WriteChar(MacroFile,2c);        (* B2 *)
    WriteChar(MacroFile,0c);        (* area *)
    WriteChar(MacroFile,3c);        (* FIND *)

    WriteChar(MacroFile,0c);
    WriteChar(MacroFile,1c);        (* B1 *)
    WriteChar(MacroFile,2c);        (* area *)
    WriteChar(MacroFile,21c);       (* Mline *)
    WriteChar(MacroFile,50c);       (* Mcol *)
    WriteChar(MacroFile,1c);        (* McolSel *)
    WriteChar(MacroFile,21c);       (* Mline *)
    WriteChar(MacroFile,50c);       (* Mcol *)

    WriteChar(MacroFile,22c);       (* PRINT *)
  END InitMacroFile;


  PROCEDURE InitEditFiles;
  BEGIN (*  -------------  *)
    Lookup(BF,'DK.Edit.I11.RPL',new);
    IF BF.res <> done THEN SysErr('open Edit.I11.RPL not done'); END;
    replay := NOT BF.new;
    BX := 0;

    Create(WF,'DK');
    IF WF.res <> done THEN SysErr('create insertfile not done'); END;
    bufpos := 0;
    WX := 0;
    PutChar(EOF);

    IF MacEnbl IN optionSet THEN InitMacroFile; END;
    macro := FALSE;
    learning := FALSE;
    doio := FALSE;

    FOR nextFno := firstFno TO maxFileNo DO 
      Name[nextFno][0] := 0c; 
      alreadyWritten[nextFno] := FALSE;
    END;
    nextFno := firstFno;
  END InitEditFiles;

END EditFiles.
