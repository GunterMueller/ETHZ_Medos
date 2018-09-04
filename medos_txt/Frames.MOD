(***************************************
*                                      *
*          M E D O S - 2 V3            *
*          ****************            *
*                                      *
*          Frames:                     *
*          Allocator for fixed frames  *
*                                      *
*          Version 4  24.06.82         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

IMPLEMENTATION MODULE Frames;

  FROM SYSTEM IMPORT SIZE, ADR;
  FROM Monitor IMPORT
    CurrentLevel, SharedLevel,
    TermProcedure;

  CONST
    levels     = 16;

    highframe  = 1024 DIV 4 * 128 - 1;
    lowframe   = 1024 DIV 4 * 64;

    lowbound   = 0;  (* frame types *)
    fixed      = 1;
    free       = 2;
    highbound  = 255;

    versionno  = 0;  (* of this implementation of frames *)
    check      = 13;
   
  TYPE
    FrameDesc =
      RECORD
        size, prevsize: CARDINAL;
        CASE type: CARDINAL OF
          lowbound, highbound: version: CARDINAL
        END;
        level: CARDINAL;
      END;

  VAR
    fd: FrameDesc;


  PROCEDURE MOVF(dfp: FramePointer; doffset: CARDINAL;
                 sfp: FramePointer; soffset: CARDINAL; size: CARDINAL);
  CODE
    337B
  END MOVF;

  PROCEDURE GetFD(fp: FramePointer; VAR fd: FrameDesc);
  BEGIN
    MOVF(0, ADR(fd), fp, 0, 4);
    WITH fd DO
      IF (type MOD check <> 0) OR (type > (levels * 256 - 1) * check) OR
         (size = 0) OR (size > 16384) OR (fp + size > highframe+1) THEN
        HALT
      END;
      level := type DIV (256 * check);
      type := type DIV check MOD 256
    END
  END GetFD;

  PROCEDURE PutFD(fp: FramePointer; fd: FrameDesc);
  BEGIN
    WITH fd DO
      type := (type + level * 256) * check;
      MOVF(fp, 0, 0, ADR(fd), 4);
    END
  END PutFD;

  PROCEDURE Allocate(VAR fp: FramePointer; size: CARDINAL);

    VAR
      sl: CARDINAL;
      fd, nextfd: FrameDesc;
      needed: CARDINAL;

  BEGIN
    sl := SharedLevel();
    needed := size DIV 4 + 1;
    IF size MOD 4 <> 0 THEN INC(needed) END;
    IF (needed > 16384) OR (sl >= levels) THEN fp := nil
    ELSE
      fp := lowframe;
      LOOP
        GetFD(fp, fd); 
        IF fd.type >= free THEN
          IF fd.type <> free THEN fp := nil; EXIT END;
          IF fd.size >= needed THEN
            fd.type := fixed; fd.level := sl;
            IF fd.size > needed THEN
              WITH nextfd DO
                size := fd.size - needed; prevsize := 0;
                type := free; level := 0;
                PutFD(fp + needed, nextfd)
              END;
              fd.size := needed;
            END;
            PutFD(fp, fd);
            INC(fp);
            EXIT
          END;
        END;
        INC(fp, fd.size);
        IF fp > highframe THEN HALT END;
      END;
    END;
  END Allocate;

  PROCEDURE Deallocate(VAR fp: FramePointer);

    VAR
      prev, next: FramePointer;
      prevfd, fd, nextfd: FrameDesc;

  BEGIN
    IF fp <> nil THEN
      IF (fp <= lowframe+1) OR (highframe < fp) THEN HALT END;
      DEC(fp);
      GetFD(fp, fd);
      IF fd.type <> fixed THEN HALT END;
      fd.prevsize := 0;
      fd.type := free;
      fd.level := 0;
      prev := lowframe;
      LOOP
        GetFD(prev, prevfd);
        IF prev + prevfd.size >= fp THEN EXIT END;
        INC(prev, prevfd.size)
      END;
      IF (prevfd.type = free) AND (prev + prevfd.size = fp) THEN
        INC(fd.size, prevfd.size);
        fp := prev
      END;
      next := fp + fd.size;
      IF next > highframe THEN HALT END;
      GetFD(next, nextfd);
      IF nextfd.type = free THEN INC(fd.size, nextfd.size) END;
      PutFD(fp, fd);
      fp := nil
    END;
  END Deallocate;

  PROCEDURE ChangeSize(fp: FramePointer; newsize: CARDINAL; VAR done: BOOLEAN);

    VAR
      next: FramePointer;
      fd, nextfd: FrameDesc;
      needed: CARDINAL;

  BEGIN
    done := FALSE;
    IF fp <> nil THEN
      needed := newsize DIV 4 + 1;
      IF newsize MOD 4 <> 0 THEN INC(needed) END;
      IF needed <= 16384 THEN
        IF (fp <= lowframe+1) OR (highframe < fp) THEN HALT END;
        DEC(fp);
        GetFD(fp, fd);
        WITH fd DO
          IF type <> fixed THEN HALT END;
          IF size = needed THEN
            done := TRUE
          ELSE
            next := fp + size;
            IF next > highframe THEN HALT END;
            GetFD(next, nextfd);
            IF nextfd.type = free THEN
              INC(size, nextfd.size)
            END;
            IF size >= needed THEN
              IF size > needed THEN
                nextfd.size := size - needed;
                nextfd.prevsize := 0;
                nextfd.type := free;
                nextfd.level := 0;
                PutFD(fp + needed, nextfd);
                size := needed
              END;
              PutFD(fp, fd);
              done := TRUE
            END
          END
        END
      END
    END
  END ChangeSize;

  PROCEDURE Size(fp: FramePointer): CARDINAL;
    VAR fd: FrameDesc;
  BEGIN
    IF fp = nil THEN
      RETURN 0
    ELSE
      IF (fp <= lowframe) OR (highframe+1 < fp) THEN HALT END;
      GetFD(fp-1, fd);
      WITH fd DO
        IF (type <> fixed) OR (level > SharedLevel()) THEN HALT END;
        RETURN (size-1) * 4;
      END;
    END;
  END Size;

  PROCEDURE Reset;

    VAR
      fp: FramePointer; fd: FrameDesc;
      next: FramePointer; nextfd: FrameDesc;
      sl: CARDINAL;

  BEGIN
    sl := SharedLevel();
    IF CurrentLevel() = sl THEN
      fp := lowframe;
      LOOP
        IF fp > highframe THEN RETURN END;
        LOOP
          GetFD(fp, fd);
          IF (fd.type = free) OR (fd.level >= sl) THEN EXIT END;
          INC(fp, fd.size);
          IF fp > highframe THEN RETURN END
        END;
        next := fp + fd.size;
        LOOP
          IF next > highframe THEN HALT END;
          GetFD(next, nextfd);
          IF (nextfd.type <> free) AND (nextfd.level < sl) THEN EXIT END;
          INC(next, nextfd.size)
        END;
        IF (next - fp > fd.size) OR (fd.type <> free) THEN
          fd.size := next - fp;
          fd.type := free; fd.level := 0;
          PutFD(fp, fd)
        END;
        fp := next
      END
    END
  END Reset;

BEGIN
  WITH fd DO
    size := 1; prevsize := 0;
    type := lowbound; version := versionno;
    level := 0;
  END;
  PutFD(lowframe, fd);
  fd.type := highbound;
  PutFD(highframe, fd);
  fd.type := free; fd.size := highframe - (lowframe + 1);
  PutFD(lowframe + 1, fd);
  TermProcedure(Reset);
END Frames.
