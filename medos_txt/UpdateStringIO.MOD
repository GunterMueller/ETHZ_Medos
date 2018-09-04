IMPLEMENTATION MODULE UpdateStringIO; (* WW 15.6.83 *)

VAR
  string: String40;
  stringIndex: CARDINAL;


PROCEDURE StartReadingFromString (s: String40);
BEGIN
  string := s;
  stringIndex := 0;
END StartReadingFromString;


PROCEDURE ReadFromString (VAR ch: CHAR);
BEGIN
  IF stringIndex < 40 THEN 
    ch := string[stringIndex];
    INC(stringIndex);
  ELSE
    ch := 0c;
  END;
END ReadFromString;


PROCEDURE StartWritingToString;
BEGIN
  stringIndex := 0;
END StartWritingToString;


PROCEDURE WriteToString (ch: CHAR);
BEGIN
  IF stringIndex < 40 THEN 
    string[stringIndex] := ch;
    INC(stringIndex);
  END;
END WriteToString;


PROCEDURE GetString (VAR s: String40);
BEGIN
  IF stringIndex < 40 THEN 
    string[stringIndex] := 0c;
  END;
  s := string;
END GetString;

END UpdateStringIO.
