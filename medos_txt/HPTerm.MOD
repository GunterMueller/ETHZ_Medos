MODULE HPTerm; (* R. Ohran, MRI, 8 July 1982 *)

FROM Terminal IMPORT Read,BusyRead,WriteString,WriteLn;
FROM TextScreen IMPORT Write,FreeLines,SetPos,ClearLines;
IMPORT V24;
FROM FileNames IMPORT ReadFileName;
FROM FileSystem IMPORT File, SetRead, SetWrite,ReadWord,WriteWord,
                         Lookup, Response, Close,SetOpen,
                         WriteChar,Length;
FROM InOut IMPORT WriteOct;
IMPORT FileSystem;

CONST  cntrlz = 32C;
       cntrlc = 3C;
       cntrle = 5C;
       DC1= 21C;
       escape = 33C;
       cr=15C;
       lf = 12C;
       eol = 36C;
       cursortime = 2000;
       null=0C;

VAR inverted,got,fileopen,noexit:BOOLEAN;
    ch:CHAR;
    chcnt,fileend,fileptr,cursorcnt,n:CARDINAL;
    f:File;
    eflag:(normal,esc,s2,s3,s4,s5,s6);
    filestarts:ARRAY (ex,ifu,alu,hw,dsk,end) OF CARDINAL;
    internalfile:BOOLEAN;
    corefile:ARRAY[0..65000] OF CHAR;

  PROCEDURE strcmp(VAR S1,S2: ARRAY OF CHAR) : BOOLEAN;
  VAR
    Result : BOOLEAN;
    I : CARDINAL;
  BEGIN
    Result:=TRUE;
    I:=0;
    LOOP
      IF (S1[I]=null) OR (S2[I]=null) THEN EXIT; END;
      IF S1[I]#S2[I] THEN Result:=FALSE; END;
      INC(I);
    END;
    IF (S1[I]#null) OR (S2[I]#null) THEN Result:=FALSE; END;
    RETURN(Result);
  END strcmp;

PROCEDURE ReadChar( VAR f:File; VAR ch:CHAR);
BEGIN
  IF internalfile THEN ch:=corefile[fileptr];
    INC(fileptr)
  ELSE FileSystem.ReadChar(f,ch) END
END ReadChar;

PROCEDURE LoadFiles;
BEGIN
  fileptr:=0;
  Lookup(f,'DK.ex.MOT',FALSE);
  IF f.res = done THEN
    filestarts[ex]:=fileptr;
    REPEAT
      FileSystem.ReadChar(f,ch);corefile[fileptr]:=ch;INC(fileptr);
    UNTIL f.eof;
    Close(f)
  ELSE  WriteString('missing DK.ex.MOT file') END;
  Lookup(f,'DK.ifu.MOT',FALSE);
  IF f.res = done THEN
    filestarts[ifu]:=fileptr;
    REPEAT
      FileSystem.ReadChar(f,ch);corefile[fileptr]:=ch;INC(fileptr);
    UNTIL f.eof;
    Close(f)
  ELSE  WriteString('missing DK.ifu.MOT file') END;
  Lookup(f,'DK.alu.MOT',FALSE);
  IF f.res = done THEN
    filestarts[alu]:=fileptr;
    REPEAT
      FileSystem.ReadChar(f,ch);corefile[fileptr]:=ch;INC(fileptr);
    UNTIL f.eof;
    Close(f)
  ELSE  WriteString('missing DK.alu.MOT file') END;
  Lookup(f,'DK.hwtest.MOT',FALSE);
  IF f.res = done THEN
    filestarts[hw]:=fileptr;  
    REPEAT
      FileSystem.ReadChar(f,ch);corefile[fileptr]:=ch;INC(fileptr);
    UNTIL f.eof;
    Close(f)
  ELSE  WriteString('missing DK.hwtest.MOT file') END;
  Lookup(f,'DK.dsktst.MOT',FALSE);
  IF f.res = done THEN
    filestarts[dsk]:=fileptr;  
    REPEAT
      FileSystem.ReadChar(f,ch);corefile[fileptr]:=ch;INC(fileptr);
    UNTIL f.eof;
    Close(f);
  ELSE  WriteString('missing DK.dsktst.MOT file') END;
  filestarts[end]:=fileptr
END LoadFiles;

PROCEDURE Invalid(ch:CHAR);
BEGIN
  WriteLn;
  WriteString('invalid escape sequence!  ');
  WriteOct(CARDINAL(ch),3);
  eflag:=normal;
END Invalid;

PROCEDURE GetFile;
  CONST filenamelen=31;
  VAR name,filename,defaultfilename: ARRAY[0..filenamelen] OF CHAR;
  BEGIN
    IF fileopen THEN Close(f) END;
    LOOP  (*get file*)
      defaultfilename := "DK.ex.MOT";
      WriteString(" file>");
      ReadFileName(filename, defaultfilename);
      Read(ch); (*flush termination character*);Write(' ');
      IF filename[0] = 0C THEN
        WriteString(" No File");EXIT
      END;
      internalfile:=TRUE;
      name:='DK.ex';
      IF strcmp(filename,name) THEN
        fileptr:= filestarts[ex];fileend:=filestarts[ifu]; fileopen:=TRUE;EXIT
      END;
      name:='DK.ifu';
      IF strcmp(filename,name) THEN
        fileptr:= filestarts[ifu];fileend:=filestarts[alu];fileopen:=TRUE; EXIT
      END;
      name :='DK.alu';
      IF strcmp(filename,name) THEN
        fileptr:= filestarts[alu];fileend:=filestarts[hw];fileopen:=TRUE; EXIT
      END;
      name :='DK.hw';
      IF strcmp(filename,name) THEN
        fileptr:= filestarts[hw];fileend:=filestarts[dsk]; fileopen:=TRUE; EXIT
      END;
      name :='DK.dsk';
      IF strcmp(filename,name) THEN
        fileptr:= filestarts[dsk] ;fileend:=filestarts[end];fileopen:=TRUE;EXIT
      END;
      internalfile:=FALSE;
      Lookup(f, filename, FALSE);
      IF f.res <> done THEN WriteString('not found') 
      ELSE fileopen:=TRUE; SetRead(f); EXIT END;
    END (*loop*);
  END GetFile;

PROCEDURE SendLine;
BEGIN 
  IF NOT fileopen THEN GetFile END;
  IF (*still*)NOT fileopen THEN WriteString('Abort Load!!') ELSE
    LOOP
      IF (f.eof AND NOT internalfile) OR (internalfile AND (fileptr>=fileend)) THEN
        EXIT END;
      V24.BusyRead(ch,got);
      IF got THEN Write(ch);EXIT END;
      ReadChar(f,ch);
      eflag:=normal;
      IF ch= eol THEN V24.Write(cr); EXIT ELSE V24.Write(ch) END;
      IF ch = cr THEN EXIT END;
    END;(*loop*)
    IF (f.eof AND NOT internalfile) OR (internalfile AND (fileptr>=fileend)) THEN 
      WriteString('End of File');
      fileopen:=FALSE;
      IF NOT internalfile THEN Close(f) END;
    END
  END;
  Write('.');
END SendLine;

PROCEDURE SendFile;
BEGIN
  REPEAT
    SendLine;
    IF got THEN 
      fileopen:=FALSE;V24.Write(0C); 
      IF NOT internalfile THEN Close(f) END;
      eflag:=normal
    END;
  UNTIL NOT fileopen;
END SendFile;


BEGIN
  chcnt:=0;
  LoadFiles;
  cursorcnt:= cursortime;
  inverted:=FALSE;
  WriteLn;
  WriteString('HPTerminal Emulator, rev 1.5, 1 Oct 82');
  WriteLn;
  eflag:=normal;
  noexit:=TRUE;
  fileopen:=FALSE;
  WHILE noexit DO
    BusyRead(ch);
    IF ch<>0C THEN
      IF fileopen THEN 
        IF NOT internalfile THEN Close(f) END;
        fileopen:=FALSE END;
      IF ch = cntrle THEN noexit:=FALSE
        ELSIF ch = cntrlz THEN V24.Write(cntrlc) 
      ELSE V24.Write(ch) END
    END;
    V24.BusyRead(ch,got);
    IF got THEN
      CASE eflag OF
        esc:  IF ch= 145C THEN SendFile
              ELSIF ch= 46C THEN eflag:=s2
              ELSIF ch = '^' THEN eflag:=s6
              ELSIF ch=' ' THEN eflag:=normal
              ELSE Invalid(ch) 
              END |
        s2:   IF ch=160C THEN eflag:=s3 ELSE Invalid(ch) END |
        s3:   IF ch=60C THEN eflag:=s4 ELSE Invalid(ch) END |
        s4:   IF ch=122C THEN eflag:=s5 ELSE Invalid(ch) END  |
        s5:   IF ch=DC1 THEN SendLine; eflag:=normal ELSE Invalid(ch) END  |
        s6:   IF ch=DC1 THEN 
                 V24.Write(escape);
                 V24.Write('H');V24.Write('E');V24.Write('L');V24.Write('L');
                 V24.Write('O');V24.Write(' ');
                 eflag:=normal;
              ELSE Invalid(ch) END |
      normal: IF ch=33C THEN eflag:=esc ELSE 
                n:=FreeLines();
                IF n = 1 THEN SetPos(0,0);ClearLines(1) END;
                IF inverted THEN Write(' ');Write(177C);inverted:=FALSE END;
                IF ch<>12C THEN
                  IF ch=cr THEN Write(eol);chcnt:=0;ClearLines(1) 
                    ELSIF ch=eol THEN Write(eol);chcnt:=0;ClearLines(1)
                  ELSE Write(ch);INC(chcnt);
                    IF chcnt=80 THEN Write(eol);chcnt:=0;ClearLines(1) END
                  END
                END
              END 
        END (*case*)
      END (*if*);
      DEC(cursorcnt);
      IF cursorcnt = 0 THEN cursorcnt:=cursortime;
        IF inverted THEN Write('*');Write(177C) ELSE Write('*');Write(10C) END;
        inverted:= NOT inverted;
      END;
    END (*while*)
END HPTerm.   