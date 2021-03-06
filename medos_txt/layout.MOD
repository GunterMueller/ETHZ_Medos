MODULE layout;   (* Ch. Jacobi 13.2.82 *)
                 

  FROM WindowHandler IMPORT 
    Window, WindowDescriptor, BlockDescriptor, Mode, SignalSet,
    CloseWindow, Clear, WriteChar, UseForDefault,
    SelectWindow, FullScreen, DefaultWindow, OpenWindow, 
    WindowSignal, IgnoreWindowSignal, NextDown;
  FROM Terminal IMPORT Read, Write, WriteString, WriteLn, ReadAgain;
  FROM CursorStuff IMPORT MenuSelection;
  FROM WindowDialogue IMPORT 
    InstallWindow, CreateInstallWindow, RemoveWindow, InstallKeyboard,
    DialogLoop;
  FROM FileSystem IMPORT 
    File, Lookup, Create, Close, ReadWord, Response, Rename;
  FROM OutFile IMPORT
    WriteLine, WriteText,  
    WriteInt, WriteCard, WriteOct;
  FROM FileNames IMPORT
    ReadFileName;
  FROM OutWindow IMPORT WriteS, WriteC;

  CONST nameAndVersion = "layout V1.0; 20.Feb.82";

  PROCEDURE LayOut;
    VAR
      w: Window;
      ok: BOOLEAN;
      f: File; 
      fn: ARRAY [0..40] OF CHAR;
      ch: CHAR;
  BEGIN
    WriteString("layout"); WriteLn;
    LOOP ok := FALSE;
      WriteString('file>');
      ReadFileName(fn, 'DK..TEXT');
      Read(ch);
      IF ch=33C THEN 
        WriteString(' no file'); RETURN
      END;
      Lookup(f, fn, TRUE);
      IF f.res=done THEN ok := TRUE; EXIT
      ELSE                
        WriteString(' not done'); WriteLn;
      END;
    END;
    WriteText(f, "Window - layout", 0); WriteLine(f);
    w := NextDown(NIL);
    WHILE w<>NIL DO
      WriteText(f, w^.header, 24);
      WriteLine(f);
      WriteText(f, "  ", 4);
      WriteCard(f, w^.outerblk.x, 0);
      WriteCard(f, w^.outerblk.y, 0);
      WriteCard(f, w^.outerblk.w, 0);
      WriteCard(f, w^.outerblk.h, 0);
      WriteLine(f);
      WriteText(f, "  ", 4);
      WriteOct(f, w^.outerblk.x, 0);
      WriteOct(f, w^.outerblk.y, 0);
      WriteOct(f, w^.outerblk.w, 0);
      WriteOct(f, w^.outerblk.h, 0);
      WriteLine(f);
      w := NextDown(w);
    END;
    WriteText(f, "end", 0); WriteLine(f);
    Close(f);
    WriteString("end layout"); WriteLn;
  END LayOut;

  CONST EOL = 36C;

  VAR
    done0: BOOLEAN;
    default, cur: Window;


  PROCEDURE KeyProc;
    VAR ch: CHAR;
  BEGIN
    Read(ch);
    WriteChar(cur, ch)
  END KeyProc;


  PROCEDURE Alfa(VAR m: Window);
  BEGIN
    WriteS(m, 'The alphabet');
    WriteChar(m, EOL);
    WriteS(m, 'abcdefghijklmnopqrstuvwxyz');
    WriteChar(m, EOL);
    WriteS(m, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
    WriteChar(m, EOL );
    WriteS(m, '1234567890');
    WriteChar(m, EOL);
    WriteS(m, '!"#$%&'); WriteS(m, "'()=~|-^\{@[_+*};:]<>?,./");
    WriteChar(m, EOL);
  END Alfa;

  PROCEDURE Border(W: Window);
  BEGIN
    WriteS(W, "border: ");
    WriteC(W, W^.outerblk.x, 0);
    WriteC(W, W^.outerblk.y, 0);
    WriteC(W, W^.outerblk.w, 0);
    WriteC(W, W^.outerblk.h, 0);
    WriteChar(W, EOL);
  END Border;


  PROCEDURE Inner(W: Window);
  BEGIN
    WriteS(W, "inside: ");
    WriteC(W, W^.innerblk.x, 0);
    WriteC(W, W^.innerblk.y, 0);
    WriteC(W, W^.innerblk.w, 0);
    WriteC(W, W^.innerblk.h, 0);
    WriteChar(W, EOL);
  END Inner;



  PROCEDURE POpenWindow;
    VAR done0: BOOLEAN;
        wptr: Window;
        name: ARRAY [0..23] OF CHAR;

    PROCEDURE ReadString(VAR name: ARRAY OF CHAR);
      VAR i : CARDINAL; ch: CHAR;
    BEGIN
      i := 0;
      WHILE i<=HIGH(name) DO
        Read(ch); Write(ch);
        IF ch=33c THEN name[0] := 0c; ReadAgain; RETURN END;
        IF ch=EOL THEN name[i] := 0c; RETURN END;
        name[i] := ch;
        INC(i)
      END
    END ReadString;

  BEGIN (*POpenWindow*)
    WriteString('OpenWindow'); WriteLn;
    WriteString('window name: ');
    ReadString(name); WriteLn;
    CreateInstallWindow(wptr, name, {1..5, 15}, HandleWindowDialog,
      SignalSet{moved, fontchanged, changed}, 
      TRUE, IgnoreWindowSignal, done0);
    IF done0 THEN cur := wptr END
  END POpenWindow;



  PROCEDURE HandleWindowDialog(w: Window; r: CARDINAL);
    VAR ch: CHAR;
  BEGIN
    cur :=  w;
    InstallKeyboard(KeyProc);
    IF r IN {1..3} THEN
      WriteString(cur^.header); WriteLn;
      CASE MenuSelection(" MENU | alfa| clear| border| inside| layout| open") OF
        2: Alfa(cur) |
        3: Clear(cur)|
        4: Border(cur)|
        5: Inner(cur)|
        6: LayOut|
        7: POpenWindow 
        ELSE
      END;
    ELSIF r=5 THEN
      CloseWindow(cur);
      cur := DefaultWindow();
    END
  END HandleWindowDialog;

  VAR i, j: CARDINAL;
BEGIN
  OpenWindow(default, 20, 40, 300, 170, 'LAYOUT', done0);
  IF NOT done0 THEN i := 0; j := 0;
     LOOP
       OpenWindow(default, i, j, 40, 30, 'LAYOUT', done0);
       IF done0 THEN EXIT END;
       INC(j, 10);
       IF j>1000 THEN
         j := 0;
         INC(i, 10);
         IF i>1000 THEN EXIT END;
       END
     END
  END;
  IF done0 THEN
    InstallWindow(default, 
      {0..5, 15}, HandleWindowDialog,
      SignalSet{moved, fontchanged, changed}, done0);
  END;
  IF NOT done0 THEN
    WriteString("** LAYOUT not opened"); WriteLn; HALT
  END;
  InstallKeyboard(KeyProc);
  UseForDefault(default);
  cur := default;
  WriteString(nameAndVersion); WriteLn; 
  DialogLoop(TRUE);   
  cur := FullScreen(); CloseWindow(cur);
END layout.



 