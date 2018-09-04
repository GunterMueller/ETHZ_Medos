MODULE SilCheck;   (*NW 9.5.82*)
  FROM SYSTEM IMPORT TSIZE;
  FROM Terminal IMPORT Read, Write, WriteString, WriteLn;
  FROM FileSystem IMPORT
       File, Response, Lookup, ReadWord, WriteWord, Rename, Close;
  FROM Memory IMPORT Init, New, Mark, Reset;

  CONST LineCode = 7;
    NameLeng = 27;
    DEL = 177C; ESC = 33C;

  TYPE Tree = POINTER TO TreeNode;
       TreeNode = RECORD
                     x, y, z: CARDINAL;
                     left, right: Tree
                  END ;

  VAR T, X, Y, W, H: CARDINAL;
    k,m,n: CARDINAL;
    ch: CHAR;
    root0, root1, root2: Tree;
    in, out: File;
    name: ARRAY [0..NameLeng] OF CHAR;

  PROCEDURE ReadFileName(ext: ARRAY OF CHAR);
    VAR i,j: CARDINAL;
  BEGIN i := 3; j := 0;
    WHILE i < k DO
      Write(name[i]); i := i+1
    END ;
    REPEAT Read(ch);
      IF ch = DEL THEN
        IF i > 3 THEN Write(DEL); i := i-1 END
      ELSIF ch > " " THEN
        IF i < NameLeng THEN Write(ch); name[i] := ch; i := i+1 END
      END
    UNTIL ch <= " ";
    k := i;
    IF (i > 3) & (name[i-1] = ".") & (i < NameLeng) THEN
      REPEAT ch := ext[j]; j := j+1;
        Write(ch); name[i] := ch; i := i+1
      UNTIL (j > HIGH(ext)) OR (i = NameLeng)
    END ;
    name[i] := 0C
  END ReadFileName;

  PROCEDURE WriteNumber(n: CARDINAL);
    VAR i: CARDINAL; d: ARRAY [0..3] OF CARDINAL;
  BEGIN i := 0; Write(" ");
    REPEAT d[i] := n MOD 10; n := n DIV 10; i := i+1
    UNTIL n = 0;
    REPEAT i := i-1; Write(CHAR(d[i]+60B))
    UNTIL i = 0
  END WriteNumber;

  PROCEDURE insert0(VAR t: Tree);
  BEGIN
    IF t # NIL THEN
      WITH t^ DO
        IF Y < y THEN insert0(left)
        ELSIF Y > y THEN insert0(right)
        ELSIF X < x THEN insert0(left)
        ELSE insert0(right)
        END
      END
    ELSE t := New(TSIZE(TreeNode));
      WITH t^ DO
        x := X; y := Y; z := W;
        left := NIL; right := NIL
      END
    END
  END insert0;

  PROCEDURE insert1(VAR t: Tree);
  BEGIN
    IF t # NIL THEN
      WITH t^ DO
        IF X < x THEN insert1(left)
        ELSIF X > x THEN insert1(right)
        ELSIF Y < y THEN insert1(left)
        ELSE insert1(right)
        END
      END
    ELSE t := New(TSIZE(TreeNode));
      WITH t^ DO
        x := X; y := Y; z := H;
        left := NIL; right := NIL
      END
    END
  END insert1;

  PROCEDURE insert2(VAR t: Tree);
  BEGIN
    IF t # NIL THEN
      WITH t^ DO
        IF X < x THEN insert2(left)
        ELSIF X > x THEN insert2(right)
        ELSIF Y < y THEN insert2(left)
        ELSE insert2(right)
        END
      END
    ELSE t := New(TSIZE(TreeNode));
      WITH t^ DO
        x := X; y := Y; z := W;
        left := NIL; right := NIL
      END
    END
  END insert2;

  PROCEDURE ReadFile;
    VAR tem: CARDINAL;
  BEGIN root0 := NIL; root1 := NIL; root2 := NIL; n := 0;
    ReadWord(in,X);
    WHILE NOT in.eof DO
      n := n+1; T := X DIV 10000B; X := X MOD 10000B;
      ReadWord(in,Y); ReadWord(in,W); ReadWord(in,H);
      IF T < 4 THEN
        REPEAT ReadWord(in, tem); ch := CHAR(tem DIV 400B);
          IF ch > 0C THEN
            ch := CHAR(tem MOD 400B)
          END
        UNTIL ch = 0C;
        insert2(root2)
      ELSIF T < 7 THEN (*Macro*)
        ReadWord(in,tem)
      ELSIF H = 1 THEN insert0(root0)
      ELSIF W = 1 THEN insert1(root1) 
      END ;
      ReadWord(in,X)
    END
  END ReadFile;

  PROCEDURE traverse0(t: Tree);
  BEGIN
    IF t # NIL THEN
      WITH t^ DO
        traverse0(left);
        IF (y = Y) & (x <= X) THEN
          WriteWord(out, 70000B + x); WriteWord(out, y);
          WriteWord(out, z); WriteWord(out, 2); m := m+1
        END ;
        Y := y; X := x+z;
        traverse0(right)
      END
    END
  END traverse0;

  PROCEDURE traverse1(t: Tree);
  BEGIN
    IF t # NIL THEN
      WITH t^ DO
        traverse1(left);
        IF (x = X) & (y <= Y) THEN
          WriteWord(out, 70000B + x); WriteWord(out, y);
          WriteWord(out, 2); WriteWord(out, z); m := m+1
        END ;
        X := x; Y := y+z;
        traverse1(right)
      END
    END
  END traverse1;

  PROCEDURE traverse2(t: Tree);
  BEGIN
    IF t # NIL THEN
      WITH t^ DO
        traverse2(left);
        IF (y = Y) & (x <= X) THEN
          WriteWord(out, 70000B + x); WriteWord(out, y-2);
          WriteWord(out, z); WriteWord(out, 2); m := m+1
        END ;
        Y := y; X := x+z;
        traverse2(right)
      END
    END
  END traverse2;

  PROCEDURE WriteFile;
  BEGIN m := 0;
    X := 0; Y := 0; traverse0(root0);
    X := 0; Y := 0; traverse1(root1);
    X := 0; Y := 0; traverse2(root2);
  END WriteFile;

BEGIN name[0] := "D"; name[1] := "K"; name[2] := "."; Init;
  LOOP k := 3; WriteString(" in> "); ReadFileName("SIL");
      IF ch = ESC THEN EXIT END ;
      Lookup(in, name, FALSE);
      IF in.res = done THEN
        WriteLn;
        WriteString("out> "); ReadFileName("CK.SIL"); WriteLn;
        Lookup(out, name, TRUE);
        IF out.res = done THEN
          ReadFile;
          WriteNumber(n); WriteString(" items read"); WriteLn;
          WriteFile;
          WriteNumber(m); WriteString(" overlaps detected");
          IF m = 0 THEN Rename(out, "  ") END ;
          Close(out)
        ELSE WriteString(" not done") 
        END ;
        Close(in); Reset
      ELSE WriteString(" not found");
      END ;
      WriteLn
  END ;
  WriteLn
END SilCheck.
