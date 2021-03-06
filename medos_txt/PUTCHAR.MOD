MODULE PUTCHAR;

FROM InOut IMPORT
  OpenInput,OpenOutput,CloseInput,CloseOutput,
  Read,Write,WriteString,Done,EOL;

CONST
  StringBoLn = " m";
  StringEoLn = "  n";

VAR
  ch : CHAR;

BEGIN
  OpenInput("DIR");
  OpenOutput("COM");
  WriteString(StringBoLn);
  REPEAT
    Read(ch);
    IF ch = EOL THEN WriteString(StringEoLn) END;
    Write(ch);
    IF (ch = EOL) AND Done THEN WriteString(StringBoLn) END;
  UNTIL NOT Done;
  CloseInput;
  CloseOutput;
END PUTCHAR.

