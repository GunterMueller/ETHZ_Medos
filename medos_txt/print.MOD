MODULE print; (* CHR/ BF: 13.6. 82/ 5.7.82: V4 *) 
FROM SYSTEM         IMPORT ADDRESS,ADR,WORD;
FROM Storage        IMPORT ALLOCATE;
FROM Printer        IMPORT Activate,Getstatus,StartPrint,Diagnostic;
FROM FileSystem     IMPORT File,Response,
                           Lookup,Rename,SetRead,GetPos,SetPos,Close,ReadChar;
FROM ByteBlockIO    IMPORT ReadBytes;
FROM FileNames      IMPORT ReadFileName;
FROM Screen         IMPORT Font,Bitmap,Mode,BlockDescriptor, CreateBitmap,
                           Replicate,DisplayChar, FontHeight, LoadFont;
FROM ScreenResources0 IMPORT UseBitmap;
FROM Terminal       IMPORT Read,BusyRead,ReadAgain, Write, WriteLn,WriteString;
FROM Monitor        IMPORT Time,GetTime;
FROM Options        IMPORT FileNameAndOptions, GetOption, Termination;
FROM SEK            IMPORT TestDK;

CONST initheight     = 64;
      length         = 2048;
      bandwidth      = 32;
      rightmargin    = 100;
      chwidth        = 16;
      startband      = 130;
      ESC            = 33c;

TYPE  Filename = ARRAY[0..31] OF CHAR;
      Emptyblock = ARRAY [0..4095] OF CARDINAL;
      Epoint =     POINTER TO Emptyblock;

VAR   schirm:               Bitmap;
      bmp: ADDRESS;
      schrift:              Font;
      blk:                  BlockDescriptor;
      spfile,text:    File;
      value,i,k,fh,maxpage,maxline,
      leftmargin,pag,cops:  CARDINAL;
      tab:                  ARRAY[0..100] OF CARDINAL;
      header:               ARRAY[0..131] OF CHAR;
      ch:                   CHAR;
      v:                    BITSET;
      t,spool,bool:         BOOLEAN;
      badr,bim:             ADDRESS;
      p,q,r:                Epoint;
      daytime:              Time;
      opt:                  ARRAY[0..20] OF CHAR; (* option *)
      term:                 Termination; (* for options *)
      optLength:            CARDINAL; (* length of option *)
      headerFlag, leftMFlag:BOOLEAN; (* flags for options *)


  PROCEDURE PUT(chan: CARDINAL; value: WORD);
    CODE
      241b;
    END PUT;

  PROCEDURE GET(chan: CARDINAL; VAR value: WORD);
    CODE
      240b;
    END GET;


  PROCEDURE Wstring(str:ARRAY OF CHAR;num:CARDINAL);
  BEGIN
    WriteString(str);
    IF num =1 THEN WriteLn END
  END Wstring;

  PROCEDURE Copystring(str1:ARRAY OF CHAR;dst:CARDINAL;str2:ARRAY OF CHAR;
                       VAR str3:ARRAY OF CHAR);
  VAR i,j:CARDINAL;
  BEGIN
    IF dst<>0 THEN FOR i:=0 TO dst-1 DO str3[i]:=str1[i] END END;
    i:=dst;j:=0;
    LOOP
      FOR j:=0 TO HIGH(str2) DO
       IF str2[j]=0C THEN EXIT END;
       str3[i]:=str2[j];INC(i);
      END; EXIT
    END
  END Copystring;
    

  PROCEDURE GetText(VAR dn: BOOLEAN);

  VAR ch:   CHAR;
      fn:   Filename;
      nopage: BOOLEAN;

    PROCEDURE Header(f: Filename);
    VAR daytime: Time;
        i,k: CARDINAL;
    BEGIN
      GetTime (daytime);
      FOR i:= 1 TO 131 DO header[i]:= ' ' END;
      Copystring(header,0,'Diser                      ',header);
      Copystring(header,30,fn,header);
      i:= daytime.day MOD 32;
      IF i > 9 THEN header[68]:= CHAR(i DIV 10 + ORD('0')) END;
      header[69]:= CHAR(i MOD 10 + ORD('0')); header[67] := '/';
      i:= daytime.day DIV 32; k:= i MOD 16;
      IF k > 9 THEN header[65]:= '1' END;
      header[66]:= CHAR(k MOD 10 + ORD('0')); header[70] := '/';
      i:= i DIV 16; header[71]:= CHAR(i DIV 10 + ORD('0'));
      header[72]:= CHAR(i MOD 10 + ORD('0'));
      Copystring(header,maxline-12,'Page ',header);
      header[maxline+1]:= 36C;
    END Header;

    PROCEDURE GetNext;
    BEGIN
      REPEAT
        ReadChar(spfile,ch);
        IF spfile.eof THEN
          spool:= FALSE;
          Rename(spfile,'DK')
        ELSE
          i:= 0;
          WHILE ch <> ' ' DO
            fn[i]:= ch; INC(i);
            ReadChar(spfile,ch)
          END;
          fn[i]:= 0C;
          Wstring(fn,0); 
          Lookup(text,fn,FALSE);
          IF text.res <> done THEN
            WHILE ch <> 36C DO
              ReadChar(spfile,ch)
            END;
            Wstring(' not  found',1);
          ELSE
            Wstring(' in print',1);
          END;
        END;
        IF spfile.eof AND (text.res <> done) THEN 
          spool:= FALSE;
          Rename(spfile,'DK')
        END;
      UNTIL (text.res = done) OR NOT spool;
      IF (text.res = done) AND spool THEN
        ReadChar(spfile,ch);
        IF ch = 'N' THEN
          maxpage:= 70;       (* set maximum lines per page *)
          ReadChar(spfile,ch);
        ELSE
          maxpage:= 67;
        END;
        leftmargin:= 0;
        FOR i:= 1 TO 3 DO
          ReadChar(spfile,ch);
          leftmargin:= leftmargin * 10 + ORD(ch) - ORD('0');
        END;
        leftmargin:= leftmargin + startband;
        maxline:= (length - (startband + leftmargin)) DIV chwidth;
        ReadChar(spfile,ch);
        IF maxpage = 67 THEN Header(fn) END;
        ReadChar(spfile,ch);
        cops:= ORD(ch) - ORD('0');
        ReadChar(spfile,ch);
      END;
    END GetNext;

  PROCEDURE GetNum (VAR c: CARDINAL);
    VAR
      i: CARDINAL;
  BEGIN
    i := 1;
    LOOP 
      IF opt[i] = 0c THEN RETURN END;
      IF (opt[i] >= '0') AND (opt[i] <= '9') THEN EXIT; END;
      INC(i);
    END;
    c := 0;
    REPEAT
      c := 10 * c + CARDINAL(opt[i]) - CARDINAL('0');
      INC(i);
    UNTIL (opt[i] < '0') OR (opt[i] > '9')
  END GetNum;
        
  BEGIN
    WriteLn;
    dn:= TRUE;
    IF spool THEN GetNext END;
    IF NOT spool THEN
      REPEAT
        REPEAT
          Wstring('Print: (ESC to quit) > ',0);
          LOOP
            BusyRead(ch); bool := TestDK(TRUE);
            IF NOT bool THEN
              WriteLn;
              Wstring('Statistik: ',0); Wdec(pag); Wstring(' Page',0);
              IF pag <> 1 THEN Write('s') END;
              Wstring(' printed.',1);
              HALT;
            END;
            IF ch <> 0c THEN ReadAgain; EXIT END;
          END;
          FileNameAndOptions('DK.MOD', fn, term, TRUE); 
          IF term = esc THEN dn := FALSE; WriteLn
          ELSE
            Lookup(text,fn,FALSE);
            IF text.res <> done THEN
              IF ch = ESC THEN
                Wstring('esc',0); 
                dn:= FALSE;
              ELSE
                Wstring('   File not found',0); 
              END;
            END;
            Write(36C);
          END;
        UNTIL (text.res = done) OR NOT dn;

        headerFlag := TRUE; leftmargin := 100; cops := 1;
        LOOP
          GetOption(opt, optLength);
          IF optLength = 0 THEN EXIT END;  (* the last option *)
          IF CAP(opt[0]) = 'N' THEN headerFlag := FALSE
          ELSIF CAP(opt[0]) = 'M' THEN GetNum(leftmargin);
          ELSIF CAP(opt[0]) = 'C' THEN GetNum(cops);
          ELSE Wstring('illegal option: ', 0);
            Wstring(opt, 0); WriteLn; EXIT
          END;
        END; (*optionloop*)
        leftmargin := leftmargin + startband;
        IF cops > 10 THEN
          cops := 10;
        END;
        IF dn THEN
          nopage:= FALSE;
          IF cops = 0 THEN
            nopage:= TRUE;
            Close(text)
          END;
          IF NOT nopage THEN
            maxline:= (length - (startband + leftmargin)) DIV chwidth;
            Write(36C);
            IF headerFlag THEN
              maxpage:= 67;
              Header(fn);
            ELSE 
              maxpage:= 70;
            END;
          END;
        END;
      UNTIL ((text.res = done) AND NOT nopage) OR NOT dn;
      IF text.res = done THEN
        Wstring('Textfile in print ',1);
      END;
    END;
  END GetText;

  PROCEDURE Wdec(c: CARDINAL);
  VAR m,h,i: CARDINAL;
      b:   BOOLEAN;
  BEGIN
    m:= 10000; b:= FALSE;
    FOR i:= 0 TO 4 DO
      h:= c DIV m;
      IF h <> 0 THEN b:= TRUE; END;
      IF b THEN 
        Write(CHR(h + ORD('0')));
        c:=c - h*m;
      END;
      m:= m DIV 10;
    END;
    IF NOT b THEN Write('0'); END;
  END Wdec;

  PROCEDURE Rdec(de:CARDINAL):CARDINAL;
  CONST max = 1000;
  VAR s,i: CARDINAL;
  BEGIN
    s:= 0; i:= 0;
    REPEAT
      Read(ch); 
      IF (ch >= '0') AND (ch <= '9') AND (s < max) THEN
        Write(ch);
        s:=s*10 +(ORD(ch)-ORD('0')); INC(i);
      END;
    UNTIL (ch < '0') OR (ch > '9');
    IF i=0 THEN Wdec(de); RETURN de ELSE RETURN s; END;
  END Rdec;
  
  PROCEDURE PrintText(VAR do: BOOLEAN);
  
  VAR   page:            ARRAY [0..80*120] OF CHAR;
        blk:             BlockDescriptor;
        h,i,k,l,z,actno,
        index,tempindex,num:      CARDINAL;
        c: CHAR;

    PROCEDURE Markpos(VAR f:File; VAR ind:CARDINAL);
    VAR   i,j,line: CARDINAL;
          ch:       CHAR;
    BEGIN
      SetRead(f);
      ind:= 0; tab[0]:= 0;
      WHILE NOT f.eof DO
        ReadChar(f,ch);
        WHILE NOT f.eof DO
          line:= 0;
          WHILE (line < maxpage) AND (NOT f.eof) DO
            j:= 0; 
            WHILE (ch <> 36C) AND (ch <> 14C) AND (j < maxline) AND (NOT f.eof) DO
              INC(j); ReadChar(f,ch)
            END;
            IF ch <> 14C THEN INC(line) ELSE line:= maxpage END;
            IF NOT f.eof THEN ReadChar(f,ch) END;
          END;
          INC(ind);
          GetPos(f,h,tab[ind]);
          DEC(tab[ind]);
        END;
      END;
      INC(tab[ind]);(*otherwise the last character gets lost*)
    END Markpos;

  BEGIN
    GetText(do); h:= 0;
    IF do THEN
      maxline:= (length - (startband + leftmargin)) DIV chwidth;
      Markpos(text,index);
      Diagnostic (Getstatus());
      Activate;
      REPEAT 
        tempindex:= index;  
        WHILE (tempindex > 0) DO
          IF tab[tempindex-1] > tab[tempindex] THEN 
            DEC(h); num:= tab[tempindex]+(0ffffh - tab[tempindex-1]);
          ELSE
            num:= tab[tempindex] - tab[tempindex-1];
          END;
          SetPos(text,h,tab[tempindex-1]);
          ReadBytes(text,ADR(page),num,actno);
          INC(pag);
          p^:= r^;

          blk.x:= leftmargin; blk.y:= bandwidth; blk.w:= length; blk.h:= bandwidth;
          badr:= bim;
          StartPrint;
          IF maxpage = 67 THEN 
            header[maxline-3]:= CHAR(tempindex MOD 10 + ORD('0'));
            IF tempindex > 9 THEN 
              header[maxline-4]:= CHAR(tempindex DIV 10 + ORD('0'))
            ELSE 
              header[maxline-4]:= ' ' 
            END;
            FOR z:=0 TO maxline DO DisplayChar(schirm,blk,schrift,header[z]) END;
            REPEAT GET(40b,v); UNTIL 15 IN v;
            PUT(41b,badr);
            FOR z:= 1 TO 2 DO
              IF badr = bim THEN
              INC(badr,1024); blk.y:= 0; q^:= r^;
              ELSE
                badr:= bim; blk.y:= bandwidth; p^:= r^;
              END;
              REPEAT GET(40b,v); UNTIL 15 IN v;
              PUT(41b,badr);
            END;
          END;
          z:=0;
          FOR i:= 0 TO maxpage DO
            IF badr = bim THEN
              INC(badr,1024); blk.y:= 0; q^:= r^;
            ELSE
              badr:= bim; blk.y:= bandwidth; p^:= r^;
            END;
            blk.x:= leftmargin; blk.w:= length; k:= 0;
            ch:= page[z];
            IF (ch = 36C) THEN  INC(z); ch:= page[z] END;
            WHILE (k <= maxline) AND (ch <> 36C) AND (ch <> 14C) AND (z < actno) DO
              DisplayChar(schirm,blk,schrift,ch); INC(k); INC(z); ch:= page[z];
              INC(blk.x); DEC(blk.w);
            END;
            REPEAT GET(40b,v); UNTIL 15 IN v;
            PUT(41b,badr);
          END;
          DEC(tempindex);
        END;
        Diagnostic (Getstatus());
        DEC(cops);
        BusyRead(c);
        IF ((c <> ESC) AND (c <> 0c)) OR ((c = ESC) AND (cops = 0)) THEN 
          ReadAgain;
        END;
      UNTIL (cops = 0) OR (c = ESC);
    END;
  END PrintText;
    
  VAR bmmem: ARRAY [1..initheight*((length+15) DIV 16)+3] OF CARDINAL;
             (*used to allocate the buffer in the lower part of the memory*)
      
BEGIN
  bmp := (ADR(bmmem)+3) DIV 4 * 4;
  UseBitmap(schirm, length, initheight,
    bmp DIV 4, initheight*((length+15) DIV 16), t);
  IF NOT t THEN Wstring('No space for Bitmap',1); HALT END;
  NEW(r);
  FOR i:=0 TO 4095 DO r^[i]:= 0; END;
  p:=ADDRESS(bmp);
  q:=ADDRESS(bmp + 4096);
  bim:= ADDRESS(bmp DIV 4);
  LoadFont(schrift,"GACHA26",t);
  IF t THEN
    fh:= FontHeight(schrift);
    fh:= fh + (fh DIV 6);
      spool:= TRUE;
      Lookup(spfile,'DK.SYS.Files.to.LBPrint',FALSE);
      IF spfile.res <> done THEN spool:= FALSE END;
      pag:= 0;
      REPEAT
        PrintText(t);
        Close(text); 
      UNTIL  NOT t;
      Write(14c); (* ctrl L *)
      Wstring('              Statistik: ',0); Wdec(pag); Wstring(' Page',0);
      IF pag <> 1 THEN Write('s') END;
      Wstring(' printed.',1);
(*%
      Write('*');
      REPEAT BusyRead(ch); bool := TestDK(TRUE) UNTIL ch <> 0c; 
      IF ch <> ESC THEN ReadAgain END;
*)
(*%
      cops := 0;
      pag := 0;
      LOOP
        bool := TestDK(TRUE);
        IF NOT bool THEN HALT END;
        BusyRead(ch);
        IF ch <> 0c THEN 
          IF ch <> ESC THEN ReadAgain END;
          EXIT;
        END;
        INC(pag);
        IF pag = 20 THEN INC(cops); pag := 0; END;
        IF cops > 1000 THEN EXIT END;
      END;
*)

  ELSE Wstring('Font not loaded',1);
  END;
END print.
