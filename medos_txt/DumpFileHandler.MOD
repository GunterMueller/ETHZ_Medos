IMPLEMENTATION MODULE DumpFileHandler;  (* Ch. Jacobi 6.6.81; additions H.K. Buehrer *)
 (* (*$T-*) (*$R-*) *)

  FROM SYSTEM IMPORT WORD, ADDRESS;
  FROM FileSystem IMPORT 
    File, Lookup, SetRead, ReadWord, Response, SetPos;
  FROM OutTerminal IMPORT WriteT;
  FROM FileNames IMPORT ReadFileName;
  FROM Terminal IMPORT Read, WriteLn, WriteString;
  FROM Program IMPORT Status, Terminate;
  FROM ByteBlockIO IMPORT ReadBytes;
  
  CONST ESC = 33C;

  VAR
    dumpfile, dumpfile1: File; 
    isFile: BOOLEAN;
    lastAddress, lastAddress1: CARDINAL;


  PROCEDURE OpenDumpFile(query: BOOLEAN);
    (* opens dumpfile and dumpfile1(128K) *)
    VAR 
      default: BOOLEAN;
      fn: ARRAY [0..40] OF CHAR; 
      ch: CHAR;
  BEGIN 
    isFile := TRUE;
    IF query THEN
      REPEAT
        WriteString("dumpfile (DK.PC.DumpFile):"); WriteLn;
        ReadFileName(fn, 'DK.PC.DumpFile'); Read(ch);
        IF ch = ESC THEN Terminate(normal) 
        END;
        IF fn[0] = 0C THEN
          fn := 'DK.PC.DumpFile'; WriteString(fn);
          default := TRUE
        ELSE
          default := FALSE
        END;
        Lookup(dumpfile, fn, FALSE);
        IF dumpfile.res <> done THEN
          WriteString('-- not found');   
        END;
        WriteLn;
      UNTIL dumpfile.res = done;
      IF default THEN
        Lookup(dumpfile1, "DK.PC.Dump1File", FALSE);
        default := (dumpfile1.res = done)
      END;
      IF NOT default THEN
        LOOP
          WriteString("dumpfile (128K):"); WriteLn;
          ReadFileName(fn, 'DK.PC.Dump1File'); Read(ch);
          IF ch = ESC THEN WriteString('no file'); WriteLn; EXIT END;
          Lookup(dumpfile1, fn, FALSE);
          IF dumpfile1.res <> done THEN
            WriteString('-- not found'); WriteLn 
          ELSE WriteLn; EXIT
          END;
        END
      END
    ELSE (*no query *)
      Terminate(normal)                             (* ?? *)
    END
  END OpenDumpFile;


  PROCEDURE Mem(addr: ADDRESS): CARDINAL;
    VAR w: CARDINAL;
  BEGIN 
    IF isFile THEN
      IF (addr<=lastAddress) OR ((addr-lastAddress)<>1) THEN
        SetPos(dumpfile, addr DIV 100000B, (addr MOD 100000B)*2);
      END;
      lastAddress := addr;
      ReadWord(dumpfile, w);
      RETURN w;
    ELSIF addr<>NIL THEN
      RETURN CARDINAL(addr^)
    ELSE RETURN 0
    END
  END Mem;


  PROCEDURE Code(f, pc: CARDINAL): CARDINAL;
  BEGIN
    IF f < ((177777B DIV 2 - 1) - (pc DIV 4)) THEN
      IF ODD(pc) THEN RETURN Mem(f*2 + pc DIV 2) MOD 400B
      ELSE RETURN Mem(f*2 + pc DIV 2) DIV 400B
      END;
    ELSE
      WriteString("-- code in upper memory bank; not supported"); WriteLn;
      WriteString("   bad dumpfile"); WriteLn;
      RETURN 0;
    END;
  END Code;


  PROCEDURE ReadMemBlock(fp, n: CARDINAL; dest: ADDRESS);
    VAR addr, bytes: CARDINAL;
  BEGIN
    IF isFile THEN
      addr := 4*(fp MOD 40000B);
      CASE fp DIV 40000B OF
      0: IF (addr<=lastAddress) OR ((addr-lastAddress)<>1) THEN
           SetPos(dumpfile, addr DIV 100000B, (addr MOD 100000B)*2);
         END;
         ReadBytes(dumpfile, dest, 2*n, bytes);
         IF bytes<>2*n THEN lastAddress := 177777B
         ELSE lastAddress := addr+n-1 (*reading 177777B^ does NOT occur*)
         END |
      1: IF (addr<=lastAddress1) OR ((addr-lastAddress1)<>1) THEN
           SetPos(dumpfile1, addr DIV 100000B, (addr MOD 100000B)*2);
         END;
         ReadBytes(dumpfile1, dest, 2*n, bytes);
         IF bytes<>2*n THEN lastAddress1 := 177777B
         ELSE lastAddress1 := addr+n-1 (*reading 177777B^ does NOT occur*)
         END
      ELSE (*3 and 4'th memory bank does not exist*)
      END
  (*ELSE ignored now*)
    END
  END ReadMemBlock;


BEGIN 
  isFile := FALSE;
  lastAddress := 177777B; lastAddress1 := 177777B;
END DumpFileHandler.

