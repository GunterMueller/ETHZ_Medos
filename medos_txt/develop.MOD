MODULE develop; (* Werner Winiger 1.4.83

  3.6.83: when asked for a filename ESC lets you exit from the program
          terminal output is interpreted only during compilation *)

FROM Program IMPORT
  Status, Call;
FROM ProgramMessage IMPORT
  WriteStatus;
FROM Terminal IMPORT
  Read, Write, WriteString, WriteLn;
FROM FileSystem IMPORT
  File, Response, Lookup, Close;
FROM FileNames IMPORT
  ReadFileName;
FROM CursorStuff IMPORT
  MenuSelection;
IMPORT TerminalBase;
IMPORT Terminal;

CONST
  FF = 14c;
  CAN = 30c;
  ESC = 33c;
  commands = "|edit|compile|execute|debug|newfile|EXIT";
  commandLength = 40;

TYPE
  FileName = ARRAY [0..31] OF CHAR;

VAR
  name: FileName;
  menuString: ARRAY [0..commandLength+31] OF CHAR;
  ch: CHAR;
  esc: BOOLEAN;


MODULE OwnTerminal;

FROM TerminalBase IMPORT
  Read, Write, AssignRead, AssignWrite;
FROM Terminal IMPORT
  WriteString;

EXPORT DepositChar, DepositFileName, StartTracing, StopTracing, CompilerErrors;

CONST
  bufferLength = 40;

VAR
  buffer: ARRAY [1..bufferLength] OF CHAR;
  bufferContent,
  in, out: CARDINAL;

  tracing,
  lastChWasDash,
  errors: BOOLEAN;


PROCEDURE DepositChar (ch: CHAR);
BEGIN
  IF bufferContent < bufferLength THEN
    INC(bufferContent);
    buffer[in] := ch;
    in := (in MOD bufferLength) + 1;
  END;
END DepositChar;


PROCEDURE DepositFileName (s: ARRAY OF CHAR);
VAR i: CARDINAL;
BEGIN
  i := 3;
  LOOP
    IF s[i] = 0c THEN EXIT; END;
    DepositChar(s[i]);
    INC(i);
    IF i > HIGH(s) THEN EXIT; END;
  END;
END DepositFileName;


PROCEDURE FetchChar (VAR ch: CHAR);
BEGIN
  IF bufferContent = 0 THEN
    ch := 0c;
  ELSE
    DEC(bufferContent);
    ch := buffer[out];
    out := (out MOD bufferLength) + 1;
  END;
END FetchChar;


PROCEDURE KeyboardInput (VAR ch: CHAR);
BEGIN
  FetchChar(ch);
  IF ch = 0c THEN Read(ch); END;
END KeyboardInput;


PROCEDURE InitBuffer;
BEGIN
  bufferContent := 0;
  in := 1;
  out := 1;
END InitBuffer;


PROCEDURE StartTracing;
BEGIN
  errors := FALSE;
  lastChWasDash := FALSE;
  tracing := TRUE;
END StartTracing;


PROCEDURE StopTracing;
BEGIN
  tracing := FALSE;
END StopTracing;


PROCEDURE CompilerErrors (): BOOLEAN;
BEGIN
  IF errors THEN
    errors := FALSE;
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END;
END CompilerErrors;


PROCEDURE TerminalOutput (ch: CHAR);
BEGIN
  Write(ch);
  IF tracing THEN
    IF ch = '-' THEN
      IF lastChWasDash THEN errors := TRUE; END;
      lastChWasDash := TRUE;
    ELSE
      lastChWasDash := FALSE;
    END;
  END;
END TerminalOutput;


PROCEDURE InitOwnTerminal;
VAR ok: BOOLEAN;
BEGIN
  InitBuffer;
  AssignRead(KeyboardInput,ok);
  IF NOT ok THEN
    WriteString("assign to read not done ");
    HALT;
  END;

  errors := FALSE;
  lastChWasDash := FALSE;
  tracing := FALSE;;
  AssignWrite(TerminalOutput,ok);
  IF NOT ok THEN
    WriteString("assign to write not done ");
    HALT;
  END;
END InitOwnTerminal;

BEGIN
  InitOwnTerminal;
END OwnTerminal;


PROCEDURE ComputeMenu;
VAR c: CARDINAL;

  PROCEDURE Append (VAR to: ARRAY OF CHAR; at: CARDINAL;
                    from: ARRAY OF CHAR);
  VAR c: CARDINAL;
  BEGIN
    c := 0;
    REPEAT
      to[at] := from[c];
      INC(c); INC(at);
    UNTIL c > HIGH(from);
    to[at] := 0c;
  END Append;

BEGIN
  menuString[0] := "*";
  c := 1;
  REPEAT
    menuString[c] := name[c+2];
    INC(c);
  UNTIL name[c+2] = 0c;
  Append(menuString,c,commands);
END ComputeMenu;


PROCEDURE GetFileName (known: BOOLEAN; VAR escaped: BOOLEAN);
VAR
  ch: CHAR;
  oldName: FileName;
  f: File;
BEGIN
  escaped := FALSE;
  IF known THEN
    WriteString("current file = ");
    WriteString(name);
    WriteLn;
    oldName := name;
  ELSE
    oldName := "DK..MOD";
  END;
  LOOP
    LOOP
      IF known THEN
        WriteString("enter new filename > ");
      ELSE
        WriteString("enter filename > ");
      END;
      ReadFileName(name,oldName);
      Read(ch);
      IF name[0] = 0c THEN
        IF ch = ESC THEN
          escaped := TRUE;
          RETURN;
        ELSIF (ch <> CAN) AND known THEN
          name := oldName;
          WriteString(" --- no new file");
          EXIT;
        END;
      ELSE
        EXIT;
      END;
      WriteLn;
    END;

    Lookup(f,name,FALSE);
    IF f.res = done THEN
      Close(f);
      EXIT;
    END;
    WriteString(" create new file ? (y/-)");
    Read(ch);
    Write(ch);
    IF CAP(ch) = "Y" THEN
      Lookup(f,name,TRUE);
      IF f.res <> done THEN
        WriteString(" create not done ! ");
        HALT;
      END;
      Close(f);
      EXIT;
    END;
    WriteLn;
  END;
  WriteLn;
  ComputeMenu;
END GetFileName;


PROCEDURE CallEditor (afterError: BOOLEAN);
VAR st: Status;
BEGIN
  DepositFileName(name);
  DepositChar(" ");
  IF afterError THEN DepositChar(22c); END;
  WriteString("loading editor ...");
  Call("edit",FALSE,st);
  IF st <> normal THEN
    WriteStatus(st);
    WriteLn;
  END;
END CallEditor;


PROCEDURE CallCompiler;
VAR st: Status;
BEGIN
  DepositFileName(name);
  DepositChar(" ");
  WriteString("loading compiler ...");
  WriteLn;
  StartTracing;
  Call("modula",FALSE,st);
  StopTracing;
  IF st = normal THEN
    IF CompilerErrors() THEN CallEditor(TRUE); END;
  ELSE
    WriteStatus(st);
    WriteLn;
  END;
END CallCompiler;


PROCEDURE ExecuteProgram;
VAR
  st: Status;
  c,extPos: CARDINAL;
  prog: FileName;
BEGIN
  c := 3;
  extPos := 0;
  REPEAT
    prog[c-3] := name[c];
    IF prog[c-3] = '.' THEN extPos := c-3; END;
    INC(c);
  UNTIL name[c] = 0c;
  prog[extPos] := 0c;
  WriteString("loading ");
  WriteString(prog);
  WriteLn;
  Call(prog,FALSE,st);
  IF st <> normal THEN
    WriteStatus(st);
    WriteLn;
    IF st < callerr THEN CallDebugger; END;
  END;
END ExecuteProgram;


PROCEDURE CallDebugger;
VAR st: Status;
BEGIN
  DepositChar(36c);
  DepositChar(36c);
  WriteString("loading debugger ...");
  Call("debug",FALSE,st);
  Write(FF);
  IF st <> normal THEN
    WriteStatus(st);
    WriteLn;
  END;
END CallDebugger;


BEGIN
  GetFileName(FALSE,esc);
  IF NOT esc THEN
    LOOP
      CASE MenuSelection(menuString) OF
      0: Read(ch); |
      1: |
      2: CallEditor(FALSE); |
      3: CallCompiler; |
      4: ExecuteProgram; |
      5: CallDebugger; |
      6: GetFileName(TRUE,esc);
         IF esc THEN EXIT; END; |
      7: EXIT;
      END;
    END;
  END;
  Write(FF);
END develop.
