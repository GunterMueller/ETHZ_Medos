IMPLEMENTATION MODULE CompFile;  (* LG 22.07.82 *)

  FROM SYSTEM IMPORT ADR, WORD, TSIZE;
  IMPORT FileSystem, Terminal;

  CONST
    maxfile = 10;
    maxname = 32;
    eofc = 0C;
    eofw = 0;

  TYPE
    File = POINTER TO FileDesc;  (* implementation of opaque type *)
    FileStatus = (nofile, idle, readc, writec, readw, writew, modifyw);
    FileKind = (undef, charf, wordf);
    FileName = ARRAY [0 .. maxname-1] OF CHAR;
    FileDesc = RECORD
                 status : FileStatus;
                 kind : FileKind;
                 file : FileSystem.File;
                 catalogued : BOOLEAN;
                 fname : FileName;
                 devlen : CARDINAL;
               END;
    PoolIndex = [0 .. maxfile-1];

  VAR
    pool : ARRAY PoolIndex OF FileDesc;
    failed : FileStatus; (* referenced for failed opening or creation *)
    pix : PoolIndex;

  PROCEDURE CheckFileName(VAR name: ARRAY OF CHAR; VAR fn: FileName;
                          VAR devicelength : CARDINAL; VAR ok: BOOLEAN);
    VAR ch : CHAR;
        ix : CARDINAL;
        maxix : CARDINAL;
        firstid : BOOLEAN;
  BEGIN (* CheckFileName *)
    maxix := HIGH(name);
    IF maxix >= maxname THEN maxix := maxname - 1 END;
    firstid := TRUE;
    ix := 0;
    LOOP
      IF ix > maxix THEN EXIT END;
      ch := name[ix];
      IF ch = '.' THEN
        IF firstid THEN devicelength := ix; firstid := FALSE END;
      ELSIF (ch = 0C) OR (ch = ' ') THEN
        EXIT;
      END;  
      fn[ix] := ch;
      INC(ix);
    END;
    ok := NOT firstid;
    IF ix <= maxix THEN fn[ix] := 0C END;
  END CheckFileName;

  PROCEDURE Error(VAR f: File);
  BEGIN (* Error *)
    Terminal.WriteString(" ---- illegal operation on a file");
    Terminal.WriteLn;
    HALT;
  END Error;

  PROCEDURE SetIdle(VAR f: File);
    (* Set file to idle mode at current position *)
  BEGIN (* SetIdle *)
    IF f^.status >= idle THEN
      WITH f^ DO
        IF status > idle THEN
          FileSystem.SetOpen(file);
          IF file.res <> FileSystem.done THEN Error(f) END;
          status := idle;
        END;
      END; (* WITH *)
    ELSE Error(f);
    END;
  END SetIdle;

  PROCEDURE OpenFile(VAR f: File; VAR name: ARRAY OF CHAR; new: BOOLEAN; VAR ok: BOOLEAN);
    (* Open a file *)
    VAR pix : [0 .. maxfile];
        ix : CARDINAL;
        fn : FileName;
  BEGIN (* OpenFile *)
    pix := 0;
    WHILE (pix < maxfile) AND (pool[pix].status <> nofile) DO INC(pix) END;
    IF pix < maxfile THEN
      ok := TRUE;
      WITH pool[pix] DO
        CheckFileName(name, fname, devlen, ok);
        IF ok THEN
          IF new THEN
            fn := fname;
            fn[devlen] := 0C;
            FileSystem.Create(file, fn);
          ELSE FileSystem.Lookup(file, fname, FALSE);
          END;
          IF file.res = FileSystem.done THEN
            status := idle;
            kind := undef;
            catalogued := NOT new;
          ELSE ok := FALSE;
          END;
        ELSE f := ADR(failed); Error(f);
        END;
      END; (* WITH *)
      IF ok THEN f := ADR(pool[pix]) ELSE f := ADR(failed) END;
    ELSE f := ADR(failed); Error(f);
    END;
  END OpenFile;

  PROCEDURE CloseFile(VAR f: File; remove: BOOLEAN; VAR ok: BOOLEAN);
    VAR ix : CARDINAL;
        device : FileName;
        dummy : FileSystem.File;
  BEGIN (* CloseFile *)
    SetIdle(f);
    WITH f^ DO
      ok := TRUE;
      IF remove = catalogued THEN
        device := fname;
        device[devlen] := 0C;
        IF remove THEN (* remove opened file *)
          FileSystem.Rename(file, device);
          IF file.res <> FileSystem.done THEN ok := FALSE END;
        ELSE (* catalog opened file *)
          FileSystem.Lookup(dummy, fname, FALSE);
          IF dummy.res = FileSystem.done THEN
            (* existing file will be replaced *)
            FileSystem.Rename(dummy, device);
            IF dummy.res <> FileSystem.done THEN ok := FALSE END;
          END;
          IF ok THEN
            FileSystem.Rename(file, fname);
            IF file.res <> FileSystem.done THEN
              (* save replaced file *)
              IF dummy.res = FileSystem.done THEN FileSystem.Rename(dummy, fname) END;
              ok := FALSE;
            END;
          END;
          IF dummy.res = FileSystem.done THEN FileSystem.Close(dummy) END;
        END;
      END;
      IF ok THEN
        FileSystem.Close(file);
        status := nofile;
      END;
    END; (* WITH *)
  END CloseFile;

  PROCEDURE Open(VAR f: File; name: ARRAY OF CHAR; VAR done: BOOLEAN);
    (* Open a file already existing in directory *)
  BEGIN (* Open *)
    OpenFile(f, name, FALSE, done);
  END Open;

  PROCEDURE Create(VAR f: File; name: ARRAY OF CHAR; VAR done: BOOLEAN);
    (* Open a new file *)
  BEGIN (* Create *)
    OpenFile(f, name, TRUE, done);
  END Create;

  PROCEDURE Close(VAR f: File; VAR done: BOOLEAN);
    (* Close a file, enter a new name into directory *)
  BEGIN (* Close *)
    CloseFile(f, FALSE, done);
  END Close;

  PROCEDURE Delete(VAR f: File; VAR done: BOOLEAN);
    (* Close a file, remove from directory *)
  BEGIN (* Delete *)
    CloseFile(f, TRUE, done);
  END Delete;

  PROCEDURE GetPos(VAR f: File; VAR highpos, lowpos: CARDINAL);
    (* Get current position of the file *)
  BEGIN (* GetPos *)
    WITH f^ DO
      IF status <> nofile THEN
        FileSystem.GetPos(file, highpos, lowpos);
        IF file.res <> FileSystem.done THEN Error(f) END;
      ELSE Error(f);
      END;
    END; (* WITH *)
  END GetPos;

  PROCEDURE SetPos(VAR f: File; highpos, lowpos: CARDINAL);
    (* Set file to indicated position *)
  BEGIN (* SetPos *)
    WITH f^ DO
      IF status <> nofile THEN
        FileSystem.SetPos(file, highpos, lowpos);
        IF file.res <> FileSystem.done THEN Error(f) END;
      ELSE Error(f);
      END;
    END; (* WITH *)
  END SetPos;

  PROCEDURE Reset(VAR f: File);
    (* Position the file at the beginning and set to idle mode *)
  BEGIN (* Reset *)
    SetIdle(f);
    SetPos(f, 0, 0);
  END Reset;

  PROCEDURE ReadChar(VAR f: File; VAR ch: CHAR);
    (* Read a character from file *)
  BEGIN (* ReadChar *)
    WITH f^ DO
      IF status <> readc THEN
        IF (status <> idle) OR (kind = wordf) THEN Error(f) END;
        kind := charf;
        status := readc;
        FileSystem.SetRead(file);
        IF file.res <> FileSystem.done THEN Error(f) END;
        INCL(file.flags, FileSystem.bytemode);
      END;
      (* read character *)
      IF (file.ela >= file.ina) AND
         ((file.elodd >= file.inodd) OR (file.ela > file.ina)) THEN
        FileSystem.Doio(file);
        IF FileSystem.er IN file.flags THEN Error(f) END;
        IF file.eof THEN ch := eofc; RETURN END;
      END;
      IF file.elodd THEN
        ch := CHAR(CARDINAL(file.ela^) MOD 400B);
        INC(file.ela, TSIZE(WORD)); file.elodd := FALSE;
        RETURN;
      ELSE
        ch := CHAR(CARDINAL(file.ela^) DIV 400B);
        file.elodd := TRUE;
        RETURN;
      END;
    END; (* WITH *)
  END ReadChar;

  PROCEDURE WriteChar(VAR f: File; ch: CHAR);
    (* Write a character to file *)
  BEGIN (* WriteChar *)
    WITH f^ DO
      IF status <> writec THEN
        IF (status <> idle) OR (kind = wordf) THEN Error(f) END;
        kind := charf;
        status := writec;
        FileSystem.SetWrite(file);
        IF file.res <> FileSystem.done THEN Error(f) END;
        INCL(file.flags, FileSystem.bytemode);
      END;
      (* write character *)
      IF file.ela >= file.topa THEN
        FileSystem.Doio(file);
        IF FileSystem.er IN file.flags THEN Error(f) END;
      END;
      IF file.elodd THEN
        file.ela^ := WORD(CARDINAL(file.ela^) DIV 400B * 400B + CARDINAL(ch) MOD 400B);
        INC(file.ela, TSIZE(WORD)); file.elodd := FALSE;
        RETURN;
      ELSE
        file.ela^ := WORD(CARDINAL(ch) MOD 400B * 400B);
        file.elodd := TRUE;
        RETURN;
      END;
    END; (* WITH *)
  END WriteChar;

  PROCEDURE ReadWord(VAR f: File; VAR w: WORD);
    (* Read a word from file *)
  BEGIN (* ReadWord *)
    WITH f^ DO
      IF status <> readw THEN
        IF (status <> idle) OR (kind = charf) THEN Error(f) END;
        kind := wordf;
        status := readw;
        FileSystem.SetRead(file);
        IF file.res <> FileSystem.done THEN Error(f) END;
        IF file.elodd OR file.inodd THEN Error(f) END;
      END;
      (* read word *)
      IF file.ela >= file.ina THEN
        FileSystem.Doio(file);
        IF FileSystem.er IN file.flags THEN Error(f) END;
        IF file.eof THEN w := WORD(eofw); RETURN END;
      END;
      w := file.ela^; INC(file.ela, TSIZE(WORD));
      RETURN;
    END; (* WITH *)
  END ReadWord;

  PROCEDURE WriteWord(VAR f: File; w: WORD);
    (* Write a word to file *)
  BEGIN (* WriteWord *)
    WITH f^ DO
      IF status <> writew THEN
        IF (status <> idle) OR (kind = charf) THEN Error(f) END;
        kind := wordf;
        status := writew;
        FileSystem.SetWrite(file);
        IF file.res <> FileSystem.done THEN Error(f) END;
        IF file.elodd THEN Error(f) END;
      END;
      (* write word *)
      IF file.ela >= file.topa THEN
        FileSystem.Doio(file);
        IF FileSystem.er IN file.flags THEN Error(f) END;
      END;
      file.ela^ := w; INC(file.ela, TSIZE(WORD));
      RETURN;
    END; (* WITH *)
  END WriteWord;

  PROCEDURE ModifyWord(VAR f: File; w: WORD);
    (* Modify a word on file *)
  BEGIN (* ModifyWord *)
    WITH f^ DO
      IF status <> modifyw THEN
        IF (status <> idle) OR (kind = charf) THEN Error(f) END;
        kind := wordf;
        status := modifyw;
        FileSystem.SetModify(file);
        IF file.res <> FileSystem.done THEN Error(f) END;
        IF file.elodd THEN Error(f) END;
      END;
      (* modify word *)
      IF file.ela >= file.topa THEN
        FileSystem.Doio(file);
        IF FileSystem.er IN file.flags THEN Error(f) END;
      END;
      file.ela^ := w; INC(file.ela, TSIZE(WORD));
      RETURN;
    END; (* WITH *)
  END ModifyWord;

  PROCEDURE EndFile(VAR f: File): BOOLEAN;
    (* End of file reached *)
  BEGIN (* EndFile *)
    IF f^.status <> nofile THEN RETURN f^.file.eof;
    ELSE Error(f);
    END;
  END EndFile;

BEGIN (* CompFile *)
  FOR pix := 0 TO maxfile - 1 DO pool[pix].status := nofile END;
  failed := nofile;
END CompFile.
