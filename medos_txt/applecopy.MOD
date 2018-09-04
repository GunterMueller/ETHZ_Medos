(********************************************)
(*                                          *)
             MODULE applecopy;
(*                                          *)
(*                                          *)
(*      RO/CHR/BF last update: 6.7.82       *)
(*   On Lilith:                             *)
(*          use the /la option to           *)
(*          compile this program            *)
(*                                          *)
(*   On APPLE:                              *)
(*      assemble 'BACKASM.TEXT'             *)
(*      compile  'APCOP.TEXT' (PASCAL)      *)
(*                                          *)
(*      link 'BACKASM.CODE' to 'APCOP.CODE' *)
(*                     --> 'APPLECOPY.CODE' *)
(*                                          *)
(********************************************)



FROM Terminal      IMPORT Read,BusyRead,Write,WriteString,WriteLn;
FROM OutTerminal   IMPORT WriteC;
FROM FileNames     IMPORT ReadFileName;
FROM NameSearch    IMPORT FindNames,NextName;
FROM FileSystem    IMPORT File,Close,Lookup,SetWrite,SetRead,Length,Response,
                          Command, DirectoryCommand, FileCommand, ReadChar;
FROM ByteIO        IMPORT WriteByte,ReadByte;
FROM Screen        IMPORT BlockDescriptor,Bitmap,GetDefaultBitmap,Mode;
FROM WindowHandler IMPORT Window,WindowDescriptor,Replicate,FreeLines,
                          OpenWindow,UseForDefault,WriteChar,SetPos,GetPos,
                          Clear,ClearLines,FullScreen,CloseWindow;
FROM CursorStuff   IMPORT xpos,ypos,buttons,InstallCursor,SimpleMove,
                          TrackCursor,MenuSelection,GetMouse;
FROM CursorRelations IMPORT DownCharPos,Inside;
IMPORT V24;

CONST endfilenamecommand =  15c;
      sendblockcommand   = 122c;
      receiveblockcommand= 127c; (* W *)
      closefilecommand   = 103c;
      resetcommand       =  33c;
      endoftransm        = 105c;
      filenamestart      = 106c;
      endofstring        =   0c;
      esc                =  33c;
      dle                =  20c;
      err                =  25c;
      del                = 177c;
      eol                =  36c;
      eof                =  37c;
      lop                =  21c; (*line open *)
      maxAppleFiles      =   60; (*max number of files on an apple diskette  ?????*)
      maxLilithFiles     =  767; (*max number of files on Lilith disk*)
      blocksize          =  512;
      namelength         =   31;  (*??????*)



TYPE  entry = ARRAY[0..15] OF CHAR;
      Name = ARRAY[0..namelength] OF CHAR;
      Direction = (up,down,flip);

VAR f:                              File;
    fn,dfn,defaultname:             Name;
    ch,ch1,echo:                    CHAR;
    filelength,cksum,mb,nof,card:   CARDINAL;
    status:                         BITSET;
    error,uplowEqual,exit,windone:  BOOLEAN;
    buffer:                         ARRAY [0..511] OF CARDINAL;
    applefiles,lilithfiles,system,
    modewin,screen:                 Window;

    commfromfn,commtofn:            Name;
    commandmode,commfileerror:      BOOLEAN;
    commautoadjust:                 BOOLEAN;

    appledir:                       RECORD
                                      noOfEntries: CARDINAL;
                                      names: ARRAY [0..maxAppleFiles] OF entry;
                                      copied: ARRAY [0..maxAppleFiles] OF BOOLEAN;
                                    END;

    lilithdir:                      RECORD
                                      noOfEntries: CARDINAL;
                                      names:  ARRAY [0..maxLilithFiles] OF Name;
                                      copied: ARRAY [0..maxLilithFiles] OF BOOLEAN;
                                    END;
    maxNrOfLines: CARDINAL; (*nr of lines in the file-windows*)
    lilithtopline: CARDINAL;(* first filename in window is lilithdir.names[topline]*)
    appletopline: CARDINAL; (* first filename in window is appledir.names[topline] *)
    linepos: CARDINAL;
    bottom: CARDINAL;  (*nr of points from the bottom window border to the last line*)
    Cursor,black,Arrow: RECORD
                          Len : CARDINAL;
                          Pat : ARRAY [0..16] OF BITSET;
                        END;
    CursorBlock,ArrowBlock,lineBlock: BlockDescriptor;
    scroll0,scroll1,scrolllimit: CARDINAL;
    scroll: BOOLEAN;
    cursorwin: Window;
    x0,y0: CARDINAL; (*cursor*)
    on: BOOLEAN;     (*cursor*)
    mousebut,downpos: CARDINAL;
    fonthight : CARDINAL; (*hight of the font*)
    mouseWindowH: CARDINAL; (*width and hight of the mouse window*)

    textmode: BOOLEAN;

  PROCEDURE DrawCursor;  (* draw cursor with APPLE - shape *)
  (*this procedure is used by CursorStuff and has to be level 0 procedure*)
  BEGIN
    on := NOT on;
    IF on THEN
      x0 := xpos; y0 := ypos;
      IF x0 > (cursorwin^.innerblk.w - Cursor.Len) THEN
        x0 := cursorwin^.innerblk.w - Cursor.Len;
      END;
      IF y0 > (cursorwin^.innerblk.h - Cursor.Len) THEN
        y0 := cursorwin^.innerblk.h - Cursor.Len;
      END;
      CursorBlock.x := x0; CursorBlock.y := y0;
      ArrowBlock.x  := x0; ArrowBlock.y  := y0;
      IF ypos < scrolllimit THEN
        scroll := (scroll0 <= x0) AND (x0 < scroll1);
      ELSE
        scroll := FALSE;
      END;
    END;
    IF scroll THEN 
      Replicate(cursorwin,ArrowBlock,invert,Arrow);
    ELSE
      Replicate(cursorwin,CursorBlock,invert,Cursor);
    END;
  END DrawCursor;

  PROCEDURE DrawSelectCursor; (* invert current line *)
  (*this procedure is used by CursorStuff and has to be level 0 procedure*)
  BEGIN
    on := NOT on;
    IF on THEN
      downpos := (cursorwin^.innerblk.h -((ypos*mouseWindowH) DIV 64)) DIV fonthight;
      y0 := (maxNrOfLines - downpos) * fonthight + bottom;
      lineBlock.x := 0; lineBlock.y := y0;
      ArrowBlock.x  := xpos; ArrowBlock.y  := y0;
      scroll := (xpos <= fonthight) AND (y0 < scrolllimit);
    END;
    IF scroll THEN 
      Replicate(cursorwin,ArrowBlock,invert,Arrow);
    ELSE
      Replicate(cursorwin,lineBlock,invert,black);
    END;
  END DrawSelectCursor;

  PROCEDURE FileSelection(VAR win:Window; VAR linepos:CARDINAL);

  BEGIN
    cursorwin := win;
    lineBlock.h := fonthight;
    lineBlock.w := cursorwin^.innerblk.w;
    ch := ' ';
    on := FALSE;
    mouseWindowH := TRUNC((FLOAT(win^.innerblk.h - 2 * fonthight) /
                           FLOAT(screen^.innerblk.h))             * 64.0);
    REPEAT
      InstallCursor(DrawSelectCursor,SimpleMove);
      mousebut := TrackCursor();
      IF mousebut = 0 THEN
        Read(ch);
      ELSIF scroll AND (mousebut = 1) THEN
        xpos := win^.outerblk.x; (*scrolling in the appropriate window*)
        ypos := (maxNrOfLines-2)*fonthight+bottom-(downpos-3)*fonthight;
       (*really dirty!!!!*)
        Scroll(up);
      ELSIF scroll AND (mousebut = 3) THEN
        xpos := win^.outerblk.x; (*scrolling in the appropriate window*)
        ypos := (maxNrOfLines-2)*fonthight+bottom-(downpos-2)*fonthight;
        (*really dirty!!!!*)
        Scroll(down);
      ELSIF scroll THEN
        xpos := win^.outerblk.x; (*scrolling in the appropriate window*)
        ypos := (maxNrOfLines-2)*fonthight+bottom-(downpos-2)*fonthight;
        (*really dirty!!!!*)
        Scroll(flip);
      END;
    UNTIL ((mousebut > 0) AND NOT scroll) OR (ch = esc);
    IF (ch = esc) OR (downpos < 3) THEN
      linepos := 999;
    ELSE
      linepos := downpos - 3;
    END;
  END FileSelection;

    
    
  PROCEDURE WindowString(VAR w: Window; s: ARRAY OF CHAR; eols: CARDINAL);  
   VAR i: CARDINAL;
   BEGIN i:=0;
    WHILE (i <= HIGH(s)) AND (s[i] <> 0C) DO
        WriteChar(w,s[i]); INC(i)
    END;
    FOR i:= 1 TO eols DO
      WriteChar(w,eol)
    END
  END WindowString;


  PROCEDURE lineOpen():BOOLEAN;

  VAR count: CARDINAL;
      done : BOOLEAN;

  BEGIN
    count := 0; ch := 0c;
    V24.Write(lop);
    REPEAT
      V24.BusyRead(ch,done);
      INC(count);
      done := ch = lop;
    UNTIL done OR (count > 1000);
    IF NOT done THEN
      WriteString('applecopy version 0.4   26.1.83');WriteLn;
      WriteString('connect APPLE with LILITH and start the');WriteLn;
      WriteString('transfer program "APPLECOPY" on the APPLE');
      REPEAT
        V24.Write(lop);
        count := 0;
        REPEAT
          V24.BusyRead(ch,done);
          INC(count);
          done := ch = lop;
        UNTIL done OR (count > 1000);
        BusyRead(ch);
     UNTIL done OR (ch = esc);
    END;
    Clear(system);
    RETURN done;
  END lineOpen;


  PROCEDURE GetAppleDirectory;  (* Directory of #5: *)

  VAR pos,fcount: CARDINAL;
      error: BOOLEAN;

  BEGIN
    error := FALSE;
    Clear(applefiles);
    WindowString(applefiles,'Directory of drive #5 : ',0);
    V24.Write(esc);
    V24.Read(ch);
    IF ch = err THEN
      error := TRUE;
    ELSIF ch = eol THEN
      WindowString(applefiles,'No diskette in drive #5',1);
    ELSE

      WHILE (ch <> eol) AND (ch <> err) DO  (*read and display diskette name*)
        WriteChar(applefiles,ch);
        V24.Read(ch);
      END;
      fcount := 0;
      IF ch = err THEN
        WriteLn;
        WriteString('APPLE: error in directory of drive #5');
      ELSE
        SetPos(applefiles,2,0);
        V24.Read(ch);
        error := ch = err;
        WHILE (ch <> eof) AND NOT error DO  (*read filenames*)
          pos:= 0;
          WindowString(applefiles,'   ',0);
          WHILE (ch <> eol) AND NOT error DO
            WriteChar(applefiles,ch);
            appledir.names[fcount][pos] := ch;
            appledir.copied[fcount] := FALSE;
            INC(pos);
            V24.Read(ch);
            error := ch = err;
          END; (*while <> eol*)
          appledir.names[fcount][pos]:= 0c;
          IF NOT error THEN
            WriteChar(applefiles,ch);
            V24.Read(ch);
            error := ch = err;
            INC(fcount);
          END;
        END; (*while <> eof*)
      END; (*if ch = err*)
      appledir.noOfEntries := fcount;
      IF fcount < (maxNrOfLines - 2) THEN
        appletopline := 0;
      ELSE
        appletopline := fcount - (maxNrOfLines - 2);
      END;
    END;
    IF error THEN
      WriteLn;
      WriteString('APPLE: something wrong with directory of drive #5');
    END;
  END GetAppleDirectory;

  PROCEDURE fnok(fn: Name): BOOLEAN;
  VAR index,charcount: CARDINAL;
      endofname : BOOLEAN;
  BEGIN
    charcount := 0;
    endofname := FALSE;
    FOR index := 0 TO HIGH(fn) DO
      IF fn[index] = esc THEN RETURN(FALSE) END;
      IF ((fn[index] >= '0') AND (fn[index] <= '9')) OR
         ((fn[index] >= 'A') AND (fn[index] <= 'Z')) OR
         ((fn[index] >= 'a') AND (fn[index] <= 'z')) OR
         (fn[index] = '.')  THEN
         IF NOT endofname THEN charcount := index END;
      ELSE
        IF index > 2 THEN endofname := TRUE END;
      END;
    END;
    IF charcount > 17 THEN 
      WriteString('APPLE filename too long ');
      RETURN(FALSE);
    ELSE
      RETURN(TRUE);
    END;
  END fnok;
  
  PROCEDURE Preparedefaultname(VAR dfn: Name; fn: Name;VAR charcount: CARDINAL);
  (*generate shorter name if fn too long for apple*)
  VAR index: CARDINAL;
  BEGIN
    dfn := 'DK.';
    FOR index := 3 TO 31 DO dfn[index] := 0c END;
    charcount := 3;(*ignore 'DK.'*)
    WHILE (((fn[charcount] >= '0') AND (fn[charcount] <= '9')) OR
           ((fn[charcount] >= 'A') AND (fn[charcount] <= 'Z')) OR
           ((fn[charcount] >= 'a') AND (fn[charcount] <= 'z')) OR
           (fn[charcount] = '.')) AND (charcount <= 31) DO
      INC(charcount);
    END;
    DEC(charcount);
    IF charcount > 17 THEN  (*charcount > max namelength for the APPLE*)
      FOR index := 17 TO 14 BY -1 DO
        IF (fn[charcount] >= 'a') AND (fn[charcount] <= 'z') THEN
          dfn[index] := CAP(fn[charcount-(17-index)]);
        ELSE
          dfn[index] := fn[charcount-(17-index)];
        END;
      END;
      FOR index := 3 TO 13 DO
        IF (fn[index] >= 'a') AND (fn[index] <= 'z') THEN
          dfn[index] := CAP(fn[index]);
        ELSE
          dfn[index] := fn[index];
        END;
      END;
      dfn[18] := 0c;
      charcount := 17;
    ELSE
      FOR index := 3 TO charcount DO
        IF (fn[index] >= 'a') AND (fn[index] <= 'z') THEN
          dfn[index] := CAP(fn[index]);
        ELSE
          dfn[index] := fn[index];
        END;
      END;
    END;
    IF textmode THEN (*make sure that extension is TEXT*)
      IF charcount >= 4 THEN
        IF NOT((dfn[charcount-4]='.')AND(dfn[charcount-3]='T')AND
               (dfn[charcount-2]='E')AND(dfn[charcount-1]='X')AND
               (dfn[charcount]  ='T')) THEN
          IF charcount > 12 THEN charcount := 12 END;
          dfn[charcount+1] := '.'; dfn[charcount+2] := 'T';
          dfn[charcount+3] := 'E'; dfn[charcount+4] := 'X';
          dfn[charcount+5] := 'T'; dfn[charcount+6] :=  0c;
          charcount := charcount+5;
        END;
      ELSE
        dfn[charcount+1] := '.'; dfn[charcount+2] := 'T';
        dfn[charcount+3] := 'E'; dfn[charcount+4] := 'X';
        dfn[charcount+5] := 'T'; dfn[charcount+6] :=  0c;
        charcount := charcount+5;
      END;
    END;(*if textmode*)
  END Preparedefaultname;


  PROCEDURE backup(dirindex: CARDINAL);
  (*backup lilith file on an apple floppy whith 4-byte header*)
  VAR charcount,index,sendbyte,hilength,lolength: CARDINAL;
      exit: BOOLEAN;
      fn: Name;

    PROCEDURE GetAppleFileName(VAR exit: BOOLEAN);
    VAR index: CARDINAL;
    BEGIN
      Preparedefaultname(dfn,fn,charcount);
      IF commandmode AND commautoadjust THEN fn := dfn END;
      IF NOT commandmode OR (commandmode AND NOT fnok(fn)) THEN
        WriteLn;
        WriteString('APPLE filename (defaultname: ');
        FOR index := 3 TO charcount DO Write(dfn[index]) END;
        WriteString('):');
        ReadFileName(fn,dfn); Read(ch); Write(ch); (*read delimiter*)
        IF (fn[0] = endofstring) OR (fn[0] = ' ') THEN
          fn := dfn;
        END;
        exit := ch = esc;
        fn[0] := ' ';fn[1] := ' ';fn[2] := ' ';
        IF exit THEN WriteLn ELSE WriteString(fn) END;
      END;
    END GetAppleFileName;

  BEGIN
    error := FALSE;
    IF commandmode THEN
      fn := commfromfn;
    ELSE
      fn := 'DK.';
      FOR index := 3 TO namelength DO
        fn[index] := lilithdir.names[dirindex,index - 3];
      END;
    END;
    Lookup(f,fn,FALSE);
    IF f.res <> done THEN
      WriteString(fn);
      WriteString(': Lookup not done.'); error := TRUE; WriteLn;
    ELSE
      IF commandmode THEN fn := commtofn END;
      GetAppleFileName(exit);
      IF (fnok(fn)) AND NOT exit THEN
        IF commandmode THEN
          WriteString(' copy from ');
          WriteString(commfromfn);
          WriteString(' to');
          WriteString(fn);
        END;

        (*transfer filename*)
        index := 3;
        WriteLn; WriteString('I am working!   ');
        ch := filenamestart;
        REPEAT
          V24.Write(ch);
          V24.Read(echo);
          IF ch <> echo THEN error:=TRUE; WriteString('bad filename transfer') END;
          ch:=fn[index];
          INC(index);
          (*no check here for string overflow..don't do it*)
        UNTIL (ch = endofstring) OR error;

        IF NOT error THEN
          V24.Write(endfilenamecommand);
          V24.Read(ch);
          error := ch = endfilenamecommand;

          (*prepare and transfer 4-byte header*)
          SetRead(f);
          Length(f,hilength,lolength);
          V24.Write(receiveblockcommand);
          V24.Read(ch);
          IF ch <> receiveblockcommand THEN
            error:=TRUE;
          ELSE
            (*send header*)
            V24.Write(CHAR(lolength MOD 256));
            V24.Write(CHAR(lolength DIV 256));
            V24.Write(CHAR(hilength MOD 256));
            V24.Write(CHAR(hilength DIV 256));
            cksum:=((lolength MOD 256) + (lolength DIV 256) + 
                    (hilength MOD 256) + (hilength DIV 256)) MOD 256;
            index := 4;

            (*prepare flashing apple*)
            GetPos(system,linepos,card);
            CursorBlock.x := 106;
            CursorBlock.y := system^.innerblk.h - (linepos + 1) * fonthight + 3;

            (*send file*)
            LOOP
              IF (index MOD 128)=0 THEN Replicate(system,CursorBlock,invert,Cursor) END;  
              IF f.eof THEN sendbyte:=0 ELSE ReadByte(f,sendbyte) END;
              INC(index);
              cksum:=(cksum + sendbyte) MOD 256;
              V24.Write(CHAR(sendbyte));
              IF index = blocksize THEN

                (*send checksum*)
                V24.Write(CHAR(cksum));
                V24.Read(ch);
                error := ch = err;
                IF error THEN WriteString('checksum error '); EXIT END;
                IF f.eof THEN EXIT END;
                index := 0; cksum := 0;

                (*send ready for new block*)
                V24.Write(receiveblockcommand);
                V24.Read(ch);
                IF ch <> receiveblockcommand THEN 
                  error := TRUE; WriteString('bad echo'); EXIT
                END;

              END;
            END(*loop*);
          END; (*if ch <> receiveblockcommand*)
        END(*if*);
    
        IF NOT error THEN
          V24.Write(closefilecommand);
          V24.Read(ch);
          IF ch <> closefilecommand THEN
            error:=TRUE; WriteString('close file error')
          END;
        ELSE
          V24.Write(104c);(*close file without writing*)
          V24.Read(ch);
          IF ch <> 104c THEN
            error:=TRUE; WriteString('close file error')
          END;
        END;

        Close(f);
        IF error THEN
          WriteString(' file not copied to APPLE, maybe no space on diskette');
        ELSE
          WriteString('file copied to APPLE');
          IF NOT commandmode THEN
            lilithdir.copied[dirindex] := TRUE;
            OutListLilith(lilithtopline);
          END;
        END;
      ELSE (*apple filename too long*)
        Close(f);
      END;(*fnok*)
    END; (*f.res <> done*)
  END backup;

  PROCEDURE transferTEXT(dirindex: CARDINAL);
  (*transfer a TEXT file to the apple*)
  VAR charcount,index,sendbyte: CARDINAL;
      exit: BOOLEAN;
      fn: Name;

    PROCEDURE GetAppleFileName(VAR exit: BOOLEAN);
    VAR index: CARDINAL;
    BEGIN
      Preparedefaultname(dfn,fn,charcount);
      (*if user selects another extension than TEXT that's his business  *)
      (*in that case the APPLE opens a DATA file but there is no 'backup'*)
      (*header at the beginning of the file!                             *)
      IF commandmode AND commautoadjust THEN fn := dfn END;
      IF NOT commandmode OR (commandmode AND NOT fnok(fn)) THEN
        WriteLn;
        WriteString('APPLE filename (defaultname: ');
        FOR index := 3 TO charcount DO Write(dfn[index]) END;
        WriteString('):');
        ReadFileName(fn,dfn); Read(ch); Write(ch); (*read delimiter*)
        IF fn[0] = endofstring THEN
          fn := dfn;
        END;
        exit := ch = esc;
        fn[0] := ' ';fn[1] := ' ';fn[2] := ' ';
        IF exit THEN WriteLn ELSE WriteString(fn) END;
      END;
    END GetAppleFileName;

  BEGIN
    error := FALSE;
    IF commandmode THEN
      fn := commfromfn;
    ELSE
      fn := 'DK.';
      FOR index := 3 TO namelength DO
        fn[index] := lilithdir.names[dirindex,index-3];
      END;
    END;
    Lookup(f,fn,FALSE);
    IF f.res <> done THEN
      WriteString(fn);
      WriteString(': Lookup not done.'); error := TRUE; WriteLn;
    ELSE
      IF commandmode THEN fn := commtofn END;
      GetAppleFileName(exit);
      IF (fnok(fn)) AND NOT exit THEN
        IF commandmode THEN
          WriteString(' appleformat: copy from ');
          WriteString(commfromfn);
          WriteString(' to');
          WriteString(fn);
        END;

      (*transfer filename*)
      index := 3;
      WriteLn; WriteString('I am working    (appleformat, be patient!)  ');
      ch := filenamestart;
      REPEAT
        V24.Write(ch);
        V24.Read(echo);
        IF ch <> echo THEN error:=TRUE; WriteString('bad filename transfer') END;
        ch := fn[index];
        INC(index);
        (*no check here for string overflow..don't do it*)
      UNTIL (ch = endofstring) OR error;

      IF NOT error THEN
        V24.Write(endfilenamecommand);
        V24.Read(ch);
        error := ch = endfilenamecommand;
        SetRead(f);
        V24.Write('A');
        V24.Read(ch);
        IF ch <> receiveblockcommand THEN
          error:=TRUE;
        ELSE
          cksum := 0; index:=0;

          (*prepare flashing apple*)
          GetPos(system,linepos,card);
          CursorBlock.x := 106;
          CursorBlock.y := system^.innerblk.h - (linepos + 1) * fonthight + 3;

          (*send file*)
          LOOP
            IF (index MOD 128)=0 THEN Replicate(system,CursorBlock,invert,Cursor) END;
            IF f.eof THEN sendbyte := 3 ELSE ReadByte(f,sendbyte) END;
            IF sendbyte = 36B (*RT*) THEN sendbyte := 15B (*CR*) END;
            INC(index);
            cksum:=(cksum + sendbyte) MOD 256;
            V24.Write(CHAR(sendbyte));
            IF index = blocksize THEN

              (*send checksum*)
              V24.Write(CHAR(cksum));
              V24.Read(ch);
              error := ch = err;
              IF error THEN WriteString('checksum error '); EXIT END;
              IF f.eof THEN EXIT END;
              index := 0; cksum := 0;

              (*send ready for new block*)
              V24.Write('A');
              V24.Read(ch);
              IF ch <> receiveblockcommand THEN 
                error := TRUE; WriteString('bad echo'); EXIT
              END;

            END;
          END(*loop*);
        END; (*if ch <> receiveblockcommand*)
      END(*if*);

      IF NOT error THEN
        V24.Write(closefilecommand);
        V24.Read(ch);
        IF ch <> closefilecommand THEN
          error:=TRUE; WriteString('close file error')
        END;
      ELSE
        V24.Write(104c);(*close file without writing*)
        V24.Read(ch);
        IF ch <> 104c THEN
          error:=TRUE; WriteString('close file error')
        END;
      END;
      Close(f);
      IF error THEN
        WriteString(' file not copied to APPLE, maybe no space on diskette');
      ELSE
        WriteString('file copied to APPLE');
        IF NOT commandmode THEN
          lilithdir.copied[dirindex] := TRUE;
          OutListLilith(lilithtopline);
        END;
      END;
      ELSE (*apple filename too long*)
        Close(f);
      END;(*fnok*)
    END; (*f.res <> done*)
  END transferTEXT;



  PROCEDURE OutListLilith(VAR topline: CARDINAL);
  VAR index: CARDINAL;
  BEGIN
    IF lilithdir.noOfEntries > 0 THEN
      index := 0;
      SetPos(lilithfiles,2,0);
      ClearLines(lilithfiles,FreeLines(lilithfiles));
      WHILE (index<(maxNrOfLines-2))AND((index+topline)<lilithdir.noOfEntries) DO
        IF lilithdir.copied[index+topline] THEN
          WindowString(lilithfiles,' > ',0);
        ELSE
          WindowString(lilithfiles,'   ',0);
        END;
        WindowString(lilithfiles,lilithdir.names[index+topline],1);
        INC(index);
      END
    ELSE
      WriteString(' no files found. ');WriteLn;
    END
  END OutListLilith;


  PROCEDURE OutListApple(VAR topline: CARDINAL);
  VAR index: CARDINAL;
  BEGIN
    IF appledir.noOfEntries > 0 THEN
      index := 0;
      SetPos(applefiles,2,0);
      ClearLines(applefiles,FreeLines(applefiles));
      WHILE (index<(maxNrOfLines-2))AND((index+topline)<appledir.noOfEntries) DO
        IF appledir.copied[index+topline] THEN
          WindowString(applefiles,' > ',0);
        ELSE
          WindowString(applefiles,'   ',0);
        END;
        WindowString(applefiles,appledir.names[index+topline],1);
        INC(index);
      END;
    ELSE
      WriteString(' no files found. ');WriteLn;
    END
  END OutListApple;

  PROCEDURE Scroll(direction: Direction);
  VAR line: CARDINAL;
  BEGIN
    line := ((maxNrOfLines-2) * fonthight + bottom - ypos) DIV fonthight;
    IF xpos > 50 THEN  (*scroll inside lilithwindow*)
      IF lilithdir.noOfEntries > 0 THEN
        IF direction = up THEN
          IF (lilithtopline + line) >= lilithdir.noOfEntries THEN
            lilithtopline := lilithdir.noOfEntries - 1;
          ELSE
            lilithtopline := lilithtopline + line;
          END;
        ELSIF direction = down THEN
          IF (lilithtopline + line) >= (maxNrOfLines-2) THEN
            lilithtopline := lilithtopline + line - (maxNrOfLines-2);
          ELSE
            lilithtopline := 0;
          END;
        ELSE (*direction = flip*)
          lilithtopline := (lilithdir.noOfEntries*line) DIV (maxNrOfLines-2);
        END;
        OutListLilith(lilithtopline);
      END;
    ELSE (*scroll inside applewindow*)
      IF appledir.noOfEntries > 0 THEN
        IF direction = up THEN
          IF (appletopline + line) >= appledir.noOfEntries THEN
            appletopline := appledir.noOfEntries - 1;
          ELSE
            appletopline := appletopline + line;
          END;
        ELSIF direction = down THEN
          IF (appletopline + line) >= (maxNrOfLines-2) THEN
            appletopline := appletopline + line - (maxNrOfLines-2);
          ELSE
            appletopline := 0;
          END;
        ELSE (*direction = flip*)

        END;
        OutListApple(appletopline);
      END;
    END;
    REPEAT GetMouse UNTIL buttons = 0;
  END Scroll; 

  PROCEDURE FileSearch(VAR exit,uplowEqual: BOOLEAN;
                    VAR defaultname: Name);

      (* Selects new files according to the given string-sequences and '*'  *)
      (* and generates a new lilithdir table                                *)

  VAR namefound: Name;
      ok,oldlist: BOOLEAN;
      dummycard,numberoffiles: CARDINAL;

  PROCEDURE ReadName(VAR defaultname: Name;
                     VAR uplowEqual,exit,oldlist: BOOLEAN);
    VAR count: CARDINAL;
        name : Name;
    BEGIN
      count := 0;
      Read(ch);
      exit := ch = esc;
      oldlist := (ch = eol) OR (ch = ' ');
      WHILE NOT(oldlist OR exit OR (ch = eol) OR (ch = ' ')) DO
        IF ch = del THEN
          IF count > 0 THEN
            DEC(count); name[count] := endofstring; Write(del);
          END;
        ELSIF count > HIGH(name) THEN
          WriteString(' filename too long');WriteLn; exit := TRUE;
        ELSE
          Write(ch); name[count] := ch; INC(count);
        END;
        Read(ch);
        exit := ch = esc;
      END;(*WHILE*)
      name[count] := endofstring;
      IF (count = 0) AND (ch = eol) THEN
        name := defaultname;
      ELSE
        defaultname := name;
      END;
      uplowEqual := (count>1) AND (CAP(name[count-1]) ='E') AND (name[count-2] ='/');
      IF uplowEqual THEN name[count-2] := endofstring END;
    END ReadName;

  BEGIN (*FileSearch*)(*GetLilithDirectory*)
    WriteString('type return or a filename which may contain wildcard symbols:');
    WriteLn; ok := TRUE;
    ReadName(defaultname,uplowEqual,exit,oldlist);
    IF (NOT exit) AND (NOT oldlist) THEN
      numberoffiles := 0;
      WriteString('  searching..');
      FindNames("DK",defaultname,uplowEqual);
      WHILE ok DO
        NextName(ok,namefound,dummycard,dummycard);
        IF ok THEN
          lilithdir.names[numberoffiles] := namefound;
          lilithdir.copied[numberoffiles] := FALSE;
          INC(numberoffiles);
        END;
      END;
      lilithdir.noOfEntries := numberoffiles;
      FOR dummycard := 0 TO 12 DO Write(del) END;(*erase searching..*)
    END;
    lilithtopline := 0;
    IF NOT exit THEN OutListLilith(lilithtopline) END;
  END FileSearch;

  PROCEDURE restore(dirindex: CARDINAL);
  VAR nameindex: CARDINAL;
      cksum: CARDINAL;

    PROCEDURE ReadLilithFile;
    (* restore file which was backupt before*)
    VAR card,bufindex1,bufindex2 : CARDINAL;
    BEGIN
      bufindex1 := 4; bufindex2 := 4;
      CursorBlock.x := 106;
      GetPos(system,linepos,card);
      CursorBlock.y := system^.innerblk.h - (linepos + 1) * fonthight + 3;
      Replicate(system,CursorBlock,invert,Cursor);
      LOOP
        V24.Read(ch);
        buffer[bufindex1] := CARDINAL(ch);
        INC(bufindex1);
        IF (bufindex1 MOD 128)=0 THEN Replicate(system,CursorBlock,invert,Cursor)END;
        cksum:=(cksum + CARDINAL(ch)) MOD 256;
        IF bufindex1 = blocksize THEN
          V24.Read(ch);
          IF CARDINAL(ch) <> cksum THEN 
            error:=TRUE; WriteString(' checksum error'); EXIT;
          ELSE
            WHILE (filelength > 0) AND (bufindex2 < 512) DO
              WriteByte(f,buffer[bufindex2]);
              DEC(filelength); INC(bufindex2);
            END;
            bufindex2 := 0;
            IF filelength = 0 THEN EXIT END;
            cksum := 0; bufindex1 := 0;
            V24.Write(sendblockcommand);
            V24.Read(ch);
            IF ch <> sendblockcommand THEN
              error := TRUE; WriteString(' error: APPLE not responding.');
              EXIT;
            END;
          END;
        END(*if*);
      END(*loop*);
    END ReadLilithFile;

    PROCEDURE ReadAppleFile;
    (* 'restore' an APPLE-TEXTfile*)
    CONST RT = 36c; (*return*)
          CR = 15c;
    VAR count,indent,blkcount,bufindex: CARDINAL;
        endoffile, done, pendingindent: BOOLEAN;

    BEGIN
      pendingindent := FALSE;
      (*first read two headerblocks*)
      GetPos(system,linepos,card);
      CursorBlock.x := 106;
      CursorBlock.y := system^.innerblk.h - (linepos + 1) * fonthight + 3;
      Replicate(system,CursorBlock,invert,Cursor);
      count := 0;blkcount :=0;
      REPEAT
        V24.BusyRead(ch,done);
        IF done THEN count := 0 ELSE INC(count) END;
      UNTIL count > 1000;
      Replicate(system,CursorBlock,invert,Cursor);
      V24.Write(sendblockcommand);
      V24.Read(echo);
      IF echo <> sendblockcommand THEN
        error := TRUE;
        WriteString(' error: APPLE not responding');WriteLn;
      ELSE
        count := 0;
        REPEAT
          V24.BusyRead(ch,done);
          IF done THEN count := 0 ELSE INC(count) END;
        UNTIL count > 1000;
        Replicate(system,CursorBlock,invert,Cursor);

        (*now read TEXT*)
        V24.Write(sendblockcommand);
        V24.Read(echo);
        cksum := 0;
        IF echo <> sendblockcommand THEN
          WriteString(' error: APPLE not responding');WriteLn;
          error := TRUE;
        ELSE
          bufindex := 0; endoffile := FALSE; count := 0;

          REPEAT
            INC(blkcount);
            WHILE  (bufindex < 512) DO (*read block*)
              V24.Read(ch);
              cksum:=(cksum + CARDINAL(ch)) MOD 256;
              IF ch <> 3c THEN
                IF ch = CR THEN ch := RT END;
                buffer[bufindex] := CARDINAL(ch);
              ELSE
                endoffile := TRUE; (*never true, don't know why, BF*)
(*WriteString('textmode: eof detected');*)
              END;
              INC(bufindex);
              IF (bufindex MOD 128)=0 THEN
                Replicate(system,CursorBlock,invert,Cursor);
              END;
            END;(*read block*)
            V24.Read(ch); (*read cksum*)
            IF CARDINAL(ch) <> cksum THEN
              error := TRUE; endoffile := TRUE;
              WriteString('checksum error! ');
            END;

            count := 0; cksum := 0;
            REPEAT
              IF (buffer[count] = 20b) OR pendingindent THEN
                IF count = 511 THEN
                  pendingindent := TRUE;
                ELSE
                  IF NOT pendingindent THEN
                    INC(count);
                  ELSE
                    pendingindent := FALSE;
                  END;
                  IF buffer[count] < 32 THEN  (*%%%%????????*)
                    pendingindent := TRUE;
                  ELSE
                    FOR indent := 1 TO buffer[count] - 32 DO WriteByte(f,' ') END;
                  END;
                END;
              ELSE
                IF buffer[count] > 0 THEN WriteByte(f,buffer[count]) END;
              END;
              INC(count);
            UNTIL count >= bufindex;
            IF NOT (endoffile OR error) THEN
              bufindex := 0;
              V24.Write(sendblockcommand);
              V24.Read(echo);
              IF echo <> sendblockcommand THEN
                IF echo = 27c THEN
                  count := 0;
                  REPEAT
                    V24.BusyRead(ch,done);
                    IF NOT done THEN INC(count) ELSE count := 0 END;
                  UNTIL count > 1000;
                ELSE
                  WriteString(' apple not responding to sendblock command');WriteLn;
                  error := TRUE;
                END;
                endoffile := TRUE;
              END(*if*);
            ELSE
              WriteString('eof');
            END;
          UNTIL endoffile;
        END(*if echo <> sendblockcommand*);
      END(*if echo <> sendblockcommand*);
      Close(f); 
    END ReadAppleFile;


  BEGIN (*restore*)
    nameindex := 3; dfn := '   ';
    REPEAT
      dfn[nameindex]:= appledir.names[dirindex,nameindex - 3];
      INC(nameindex);
    UNTIL dfn[nameindex - 1] = endofstring;
    ch:=filenamestart; (*command for the apple to set name transfer mode*)
    nameindex := 3;
    REPEAT
      V24.Write(ch);
      V24.Read(echo);
      IF ch <> echo THEN
        error:=TRUE;
        WriteString('bad filename transfer'); WriteLn;
      END;
      ch := dfn[nameindex];
      INC(nameindex);
    UNTIL (ch = endofstring) OR error;
    IF NOT error THEN
      V24.Write(endfilenamecommand);
      V24.Read(echo);
      IF echo <> endfilenamecommand THEN 
        WriteString(' bad filename transfer'); WriteLn;
        error := TRUE;
      ELSE
        REPEAT
          IF commandmode THEN
            fn := commtofn;
            WriteString('Copy from ');
            WriteString(commfromfn);
            WriteString(' to ');
            WriteString(commtofn);
            WriteLn;
          ELSE
            WriteLn;
            WriteString('Lilith - Filename (defaultname:');
            WriteString(dfn);
            WriteString('): ');
            dfn[0] := 'D'; dfn[1] := 'K'; dfn[2] := '.';
            ReadFileName(fn,dfn); Read(ch);
            IF fn[0] = endofstring THEN fn := dfn; WriteString(fn) END;
            error := ch = esc;
            WriteLn;
          END;
          IF NOT error THEN
            Lookup(f,fn,TRUE);
            IF f.res <> done THEN WriteString(' lookup local file not done') END;
          END;
        UNTIL (f.res = done) OR error;
        IF NOT error THEN
          WriteString('I am working!   '); 
          SetWrite(f);
          V24.Write(sendblockcommand);
          V24.Read(echo);
          IF echo <> sendblockcommand THEN 
            error:=TRUE; WriteString(' bad echo');
          ELSE
            (*character counters are given a bias to compensate for length header*)
            (*header: 1st byte: low order byte of filelength (low word)          *)
            (*        2nd byte: high order byte of filelength (low word)         *)
            (*        3rd byte: low order byte of filelength (high word)         *)
            (*        4th byte: high order byte of filelength (high word)        *)
            V24.Read(ch);
            V24.Read(ch1);
            cksum:=(CARDINAL(ch)+CARDINAL(ch1)) MOD 256;
            filelength:=CARDINAL(ch1)*256 + CARDINAL(ch);
            (*most significant word of file length not supported currently,sorry *)
            (* That means your file can't be longer than 65k bytes *)
            V24.Read(ch);
            cksum:=(cksum + CARDINAL(ch)) MOD 256;
            V24.Read(ch);
            cksum:=(cksum + CARDINAL(ch)) MOD 256;

            IF (filelength = 1) OR textmode THEN
              IF NOT textmode THEN
                textmode := TRUE;
                Clear(modewin);
                WindowString(modewin,'  APPLE',1);
                WindowString(modewin,'TEXTfile',0);
              END;
              ReadAppleFile;
            ELSE
              ReadLilithFile;
            END;

          END;(*if echo <> sendblockcommand*)
        END;(*if echo <> endfilenamecommand*) 
      END;(*if not error*)
    END;(*if not error*)
    Close(f);
    V24.Write(closefilecommand);
    V24.Read(ch);
    IF ch <> closefilecommand THEN
      error := TRUE;
      WriteString(' APPLE: Close file error');
      WriteC(CARDINAL(ch),0);
    END;
    IF error THEN 
      WriteString(' not copied!');
    ELSE
      WriteString(' file copied to Lilith.');
      appledir.copied[dirindex] := TRUE;
      OutListApple(appletopline);
    END;
  END restore;

  PROCEDURE Commandfile;
  VAR commfile: File;       (*command file*)
      commfn: Name;         (*commandfile name*)
      dfn: Name;            (*default filename*)
      fromapple: BOOLEAN;   (*TRUE:restore from APPLE; FALSE: backup to APPLE*)
      applefilenr: CARDINAL;(*nr of the file to restore*)

    PROCEDURE Commandfilename(VAR commfn: Name; VAR exit: BOOLEAN);
    VAR dfn: Name;
    BEGIN
      dfn := 'DK..COM';
      WriteString('Commandfile: ');
      ReadFileName(commfn,dfn);
      Read(ch);
      exit := ch = esc;
      IF NOT exit THEN
        IF commfn[0] = 0c THEN
          commfn := dfn; WriteString(commfn);
        END;
      END;
    END Commandfilename;

    PROCEDURE GetDirection(VAR commfile: File; VAR fromapple,fileerror: BOOLEAN);
    BEGIN
      ReadChar(commfile,ch);
      fileerror := NOT((ch = 'b'(*backup*)) OR (ch = 'r'(*restore*)));
      IF NOT fileerror THEN
        fromapple := ch = 'r';
        WHILE NOT(commfile.eof OR (ch = eol) OR (ch = '/')) DO
          ReadChar(commfile,ch);
        END;
        IF (NOT fromapple) AND (ch = '/') THEN
          ReadChar(commfile,ch);
          commautoadjust := ch = 'a';
        END;
        WHILE NOT(commfile.eof OR (ch = eol)) DO ReadChar(commfile,ch) END;
        fileerror := commfile.eof;
      END;(*first character not b or r*)
    END GetDirection;

    PROCEDURE ReadNamesfromapple(VAR commfile: File;
                                 VAR commfromfn,commtofn: Name;
                                 VAR exit: BOOLEAN);
    (*read next line from commandfile. If tofn omitted use the fromfn as
      destination name.*)
    VAR index: CARDINAL;

    BEGIN
      ch := ' ';WriteLn;
      WHILE ((ch < 'A') OR (ch > 'z')) AND NOT commfile.eof DO
        ReadChar(commfile,ch);
      END;
      IF commfile.eof THEN
        exit := TRUE; WriteString('EOF commandfile');
      ELSE
        index := 0;
        WHILE (ch <> ' ') AND (ch <> eol) AND (index <= 17) AND NOT(commfile.eof) DO
          commfromfn[index] := ch;
          ReadChar(commfile,ch);
          INC(index);
        END; (*fromname read in*)
        WHILE (ch <> ' ') AND (ch <> eol) AND NOT(commfile.eof) DO
          ReadChar(commfile,ch);
        END; (*now first delimitter read in*)
        commfromfn[index] := 0c; (*stringterminator*)
        IF commfile.eof THEN
          exit := TRUE; WriteString('Commandfile: error in filestructure.');
        ELSE
          ReadChar(commfile,ch);(*read 1st char of tofilename or 2nd delimiter*)
          commtofn := 'DK.                           ';
          index := 3;
          IF (ch = ' ') OR (ch = eol) THEN
            WHILE commfromfn[index - 3] <> 0c DO
              commtofn[index] := commfromfn[index - 3]; INC(index);
            END;
          ELSE
            WHILE (ch<>' ') AND (ch<>eol) AND (index <= 24) AND NOT(commfile.eof) DO
              commtofn[index] := ch;
              ReadChar(commfile,ch);
              INC(index);
            END;
            IF index = 3 THEN
              WriteString('Commandfile: error in filestructure.');
              exit := TRUE;
            END;
            WHILE (ch<>eol) AND NOT(commfile.eof) DO ReadChar(commfile,ch) END;
          IF commfile.eof THEN exit := TRUE; WriteString('EOF commandfile.') END;
          END;
        END;
      END;
    END ReadNamesfromapple;

    PROCEDURE ReadNames(VAR commfile: File;
                        VAR commfromfn,commtofn: Name;
                        VAR textmode,exit: BOOLEAN);
    (*read next line from commandfile. If tofn omitted use the fromfn as
      destination name. Needs user input if filename too long for the APPLE.
      Option: /t set TEXTmode*)
    VAR index: CARDINAL;

    BEGIN
      ch := ' ';WriteLn;
      WHILE ((ch < 'A') OR (ch > 'z')) AND NOT commfile.eof DO
        ReadChar(commfile,ch);
      END;
      IF commfile.eof THEN
        exit := TRUE; WriteString('EOF commandfile.');
      ELSE
        commfromfn := 'DK.                           ';
        index := 3;
        WHILE (ch <> ' ') AND (ch <> eol) AND (index <= 24) AND NOT(commfile.eof)
              AND (ch <> '/') DO
          commfromfn[index] := ch;
          ReadChar(commfile,ch);
          INC(index);
        END; (*fromname read in*)
        IF ch = '/' THEN ReadChar(commfile,ch); textmode := ch = 't' END;
        WHILE (ch <> ' ') AND (ch <> eol) AND NOT(commfile.eof) DO
          ReadChar(commfile,ch);
        END; (*now first delimitter read in*)
        commfromfn[index] := 0c; (*stringterminator*)
        IF commfile.eof THEN
          exit := TRUE; WriteString('Commandfile: error in filestructure.');
        ELSE
          ReadChar(commfile,ch);(*read 1st char of tofilename or 2nd delimiter*)
          commtofn := '                              ';
          index := 3;
          IF (ch = ' ') OR (ch = eol) THEN
            commtofn := commfromfn;
            commtofn[0] := ' ';commtofn[1] := ' ';commtofn[2] := ' ';
          ELSE
            WHILE (ch<>' ') AND (ch<>eol) AND (index <= 30) AND NOT(commfile.eof) DO
              commtofn[index] := ch;
              ReadChar(commfile,ch);
              INC(index);
            END;
            IF index = 3 THEN
              WriteString('Commandfile: error in filestructure.');
              exit := TRUE;
            END;
            WHILE (ch<>eol) AND NOT(commfile.eof) DO ReadChar(commfile,ch) END;
          IF commfile.eof THEN exit := TRUE; WriteString('EOF commandfile') END;
          END;
        END;
      END;
    END ReadNames;

    PROCEDURE GetFileNr(VAR applefilenr: CARDINAL; fname: Name; VAR exit: BOOLEAN);
    VAR equal: BOOLEAN;

      PROCEDURE Compare(str1,str2: ARRAY OF CHAR; VAR equal: BOOLEAN);
      VAR index: CARDINAL;
      BEGIN (*Compare*)
        FOR index := 0 TO HIGH(str1) DO
          IF (str1[index] >= 'a') AND (str1[index] <= 'z') THEN
            str1[index] := CAP(str1[index]);
          END;
        END;
        FOR index := 0 TO HIGH(str2) DO
          IF (str2[index] >= 'a') AND (str2[index] <= 'z') THEN
            str2[index] := CAP(str2[index]);
          END;
        END;
        equal := TRUE; index := 0;
        WHILE equal AND (index <= HIGH(str1)) AND (index <= HIGH(str2))
              AND NOT((str1[index] = 0c) AND (str2[index] = 0c)) DO
          equal := str1[index] = str2[index];
          INC(index);
        END;
      END Compare;

    BEGIN (*GetFileNr*)
      IF appledir.noOfEntries > 0 THEN
        applefilenr := 0; equal := FALSE;
        WHILE (applefilenr < appledir.noOfEntries) AND NOT equal DO
          Compare(fname,appledir.names[applefilenr],equal); INC(applefilenr);
        END;
        IF applefilenr > 0 THEN DEC(applefilenr) END;
        exit := NOT equal;
      ELSE
        exit := TRUE;
      END;(*if appledir.noOfEntries > 0*)
      IF exit THEN 
        WriteString(fname);
        WriteString(' file not found.');
      END;
    END GetFileNr;

  BEGIN (*Commandfile*)
    exit := FALSE; commautoadjust := FALSE; textmode := FALSE; error := FALSE;
    Commandfilename(commfn,exit);
    IF NOT exit THEN
      Lookup(commfile,commfn,FALSE);
      IF commfile.res <> done THEN 
        WriteString(' Lookup not done');
      ELSE
        GetDirection(commfile,fromapple,commfileerror);
        IF commfileerror THEN
          WriteString('Commandfile: Syntax or length error.');WriteLn;
        ELSE
          commandmode := TRUE;
          IF fromapple THEN
            Clear(lilithfiles);
            SetPos(lilithfiles,2,0);
            WHILE NOT(exit OR commfile.eof) DO
              ReadNamesfromapple(commfile,commfromfn,commtofn,exit);
              IF NOT exit THEN GetFileNr(applefilenr,commfromfn,exit) END;
              IF NOT exit THEN
                restore(applefilenr);
                IF error THEN
                  WriteString('continue? (y/-): ');
                  Read(ch);
                  exit := ch <> 'y';
                  IF NOT exit THEN error := FALSE END;
                ELSE
                  WindowString(lilithfiles,commtofn,1);
                END;
              END;
            END;(*while*)
          ELSE
            Clear(lilithfiles);
            SetPos(lilithfiles,2,0);
            WHILE NOT(exit OR commfile.eof) DO
              ReadNames(commfile,commfromfn,commtofn,textmode,exit);
              IF NOT exit THEN
                IF textmode THEN transferTEXT(0) ELSE backup(0) END;;
                exit := error;
                IF NOT error THEN
                  WindowString(lilithfiles,'  > ',0);
                  WindowString(lilithfiles,commfromfn,1);
                  GetAppleDirectory;
                ELSE
                  WriteString('continue? (y/-): ');
                  Read(ch);
                  exit := ch <> 'y';
                  IF NOT exit THEN error := FALSE; GetAppleDirectory END;
                END;
              END;
            END;(*while*)
          END;(*if fromapple*)
          commandmode := FALSE;
        END;(*if commfileerror*)
        Close(commfile);
      END;(*lookup commfn done*)
    END;(*no commandfilename*)
  END Commandfile;


BEGIN(*applecopy*)
  fonthight := 16;
  screen:= FullScreen();
  WITH screen^.innerblk DO
    OpenWindow(system,0,h-75,w-76,75,'Dialog',windone);(*3 lines high*)
    IF NOT windone THEN HALT END;
    UseForDefault(system);
    OpenWindow(modewin,w-75,h-75,75,75,'  MODE',windone);
    IF NOT windone THEN HALT END;
    OpenWindow(applefiles,0,0,w DIV 2,h-76,'Apple Files :',windone);
    IF NOT windone THEN HALT END;
    OpenWindow(lilithfiles,w DIV 2,0,w DIV 2,h-76,'Lilith Files :',windone);
    IF NOT windone THEN HALT END;
  END;
  scrolllimit := applefiles^.innerblk.h - 2 * fonthight;
  maxNrOfLines := FreeLines(applefiles) + 1;
  bottom := applefiles^.innerblk.h - maxNrOfLines * fonthight;
  WITH Cursor DO
    Len := 10;
    Pat[ 0] := {5..6};
    Pat[ 1] := {4..5};
    Pat[ 2] := {4..5};
    Pat[ 3] := {1..2,4,7..8};
    Pat[ 4] := {0..9};
    Pat[ 5] := {0..9};
    Pat[ 6] := {0..9};
    Pat[ 7] := {0..9};
    Pat[ 8] := {1..8};
    Pat[ 9] := {3..4,7};
  END;
  WITH black DO
    Len := 15;
    FOR card := 0 TO 15 DO Pat[card] := {0..15} END;
  END;
  WITH CursorBlock DO
    w := Cursor.Len; h := w;
  END;
  WITH Arrow DO
    Len := 16;
    Pat[0]  := {};
    Pat[1]  := {};
    Pat[2]  := {7};
    Pat[3]  := {6..8};
    Pat[4]  := {5..9};
    Pat[5]  := {4..10};
    Pat[6]  := {6..8};
    Pat[7]  := {6..8};
    Pat[8]  := {6..8};
    Pat[9]  := {6..8};
    Pat[10] := {4..10};
    Pat[11] := {5..9};
    Pat[12] := {6..8};
    Pat[13] := {7};
    Pat[14] := {};
    Pat[15] := {};
  END;
  WITH ArrowBlock DO
    w := Arrow.Len; h := w;
  END;
  scroll0 := applefiles^.outerblk.x;
  scroll1 := applefiles^.innerblk.x + fonthight;

  V24.BusyRead(ch,error);
  dfn:= 'DK..MOD                         ';
  defaultname := '                                ';
  commfromfn := '                                ';
  commtofn := '                                ';
  commandmode := FALSE; commfileerror := FALSE;
  uplowEqual := FALSE;
  IF lineOpen() THEN

    (*initialize local directory tables*)
    GetAppleDirectory;
    lilithdir.noOfEntries := 0;
    FOR card := 0 TO maxLilithFiles DO
      lilithdir.names[card] := '';
      lilithdir.copied[card] := FALSE;
    END;
    textmode := FALSE;
    SetPos(modewin,1,0);
    WindowString(modewin,' backup',0);

    LOOP
      WriteLn;
      WriteString('Press button 2 to see the menu');
      error:= FALSE; ch := ' ';
      on := FALSE;
      scroll := FALSE;
      cursorwin := screen;
      REPEAT
        REPEAT
          InstallCursor(DrawCursor,SimpleMove);
          mousebut := TrackCursor();
          IF mousebut = 0 THEN
            Read(ch);
          ELSIF scroll THEN
            IF mousebut = 1 THEN
              Scroll(up);
            ELSIF mousebut = 3 THEN
              Scroll(down);
            ELSIF mousebut = 2 THEN
              Scroll(flip);
            END;
          END;
        UNTIL (NOT scroll AND (mousebut = 2)) OR (ch = esc);
        IF NOT(ch = esc) THEN
          mb := MenuSelection("   MENU   |   MODE   | AP --> LI | LI --> AP |AP FILELIST|COMMANDFILE|   EXIT   ");
          IF mb = 0 THEN Read(ch) END;
        END;(*ch#esc*)
      UNTIL (mb >= 2) OR (ch = esc);
      IF ch = esc THEN mb := 7 END;(*zzzzz.....*)
      Clear(system);
      CASE mb OF
        2:  textmode := NOT textmode; WriteLn; Clear(modewin);
            IF textmode THEN
              WriteString('Mode changed to "appleformat".');
              WindowString(modewin,'  APPLE',1);
              WindowString(modewin,'TEXTfile',0);
            ELSE
              WriteString('Mode changed to "backup".');
              SetPos(modewin,1,0);
              WindowString(modewin,' backup',0);
            END;
            |
        3:  LOOP
              WriteLn;
              WriteString('use mouse (left button) to select a file (ESC for no file)');
              FileSelection(applefiles,linepos);
              IF linepos + appletopline < appledir.noOfEntries THEN
                error:=FALSE;
                restore(linepos + appletopline);
              ELSE (*no selection*)
                EXIT;
              END; (*if selection done*)
            END;(*loop*)
            |
        4:  Clear(lilithfiles);
            WindowString(lilithfiles,'Files on Lilith : ',2);
            FileSearch(exit,uplowEqual,defaultname);
            IF NOT exit THEN 
              IF lilithdir.noOfEntries > 0 THEN 
                IF lilithdir.noOfEntries = 1 THEN
                  error:=FALSE;
                  IF textmode THEN transferTEXT(0) ELSE backup(0) END;
                  GetAppleDirectory;
                ELSE
                  LOOP
                    WriteLn;
                    WriteString('use mouse (left button) to select a file (ESC for no file)');
                    FileSelection(lilithfiles,linepos);
                    IF linepos + lilithtopline < lilithdir.noOfEntries THEN
                      error:=FALSE;
                      IF textmode THEN
                        transferTEXT(linepos + lilithtopline);
                      ELSE
                        backup(linepos + lilithtopline);
                      END;
                      GetAppleDirectory;
                    ELSE (*no selection*)
                      EXIT;
                    END;(*if fpos < nof*)
                  END;(*loop*)
                END;(*if nof = 1*)
              END;(*if nof > 0*)
            END;(*if not exit*)
            Clear(lilithfiles);
            |
        5:  GetAppleDirectory
            |
        6:  Commandfile;
            |
        7:  WriteString('Confirm ! (y|s|-)'); WriteLn;
            Read(ch);
            IF ch = 'y' THEN
              V24.Write(endoftransm);
              V24.Write(esc); 
              EXIT;
            ELSIF ch = 's' THEN
              EXIT; (*but let apple survive*) 
            END
      END;
    END;
  END;(*line open*)
  CloseWindow(screen);
  Write(14C);
END applecopy.

