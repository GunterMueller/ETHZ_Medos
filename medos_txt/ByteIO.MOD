(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          ByteIO:                     *
*                                      *
*          File i/o routines for       *
*          bytes (eight bit values).   *
*                                      *
*          Version 2   6.03.81         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

IMPLEMENTATION MODULE ByteIO;
 
  FROM FileSystem IMPORT
    File, Response, Flag, FlagSet, 
    SetOpen, SetRead, SetWrite, Doio;

  FROM SYSTEM IMPORT ADDRESS, WORD, TSIZE;

 
  CONST
    LXB = 205B;
    SXB = 225B;

  PROCEDURE SetResponse(VAR f: File; resp: Response);
  BEGIN 
    WITH f DO 
      res := resp;
      IF resp <> done THEN  
        eof := TRUE; 
        flags := flags + FlagSet{er, ef} 
      END
    END   
  END SetResponse; 

  PROCEDURE LoadByte(addr: ADDRESS; oddpos: BOOLEAN): WORD;
  CODE
    LXB
  END LoadByte;

  PROCEDURE StoreByte(addr: ADDRESS; oddpos: BOOLEAN; w: WORD);
  CODE
    SXB
  END StoreByte; 
 
   PROCEDURE ReadByte(VAR f: File; VAR w: WORD);
  BEGIN
    WITH f DO
      LOOP
        IF flags*FlagSet{rd, bytemode, ag, ef} <>
           FlagSet{rd, bytemode} THEN
          IF NOT (rd IN flags) THEN 
            IF wr IN flags THEN
              SetResponse(f, callerror);
            ELSE SetRead(f); INCL(flags, bytemode);
            END;
          END;
          IF eof THEN RETURN END;
          IF NOT (bytemode IN flags) THEN
            INCL(flags, bytemode); 
            elodd := FALSE
          END;
          IF ag IN flags THEN
            IF elodd THEN elodd := FALSE;
            ELSE DEC(ela, TSIZE(WORD)); elodd := TRUE
            END;
            EXCL(flags, ag);
          END;
        ELSIF (ela>=ina) AND ((elodd>=inodd) OR (ela>ina)) THEN Doio(f)
        ELSIF elodd THEN
          w := LoadByte(ela, TRUE);
          INC(ela, TSIZE(WORD)); elodd := FALSE;
          RETURN
        ELSE
          w := LoadByte(ela, FALSE);;
          elodd := TRUE;
          RETURN
        END;
      END; (* loop *)  
    END; 
  END ReadByte;

  PROCEDURE WriteByte(VAR f: File; w: WORD);
  BEGIN
    WITH f DO
      LOOP
        IF flags*FlagSet{wr, bytemode, er} <> FlagSet{wr, bytemode} THEN
          IF NOT (wr IN flags) THEN
            IF rd IN flags THEN
              SetResponse(f, callerror);
            ELSE SetWrite(f); INCL(flags, bytemode);
            END;
          END;
          IF er IN flags THEN RETURN END;
          IF NOT (bytemode IN flags) THEN
            INCL(flags, bytemode); elodd := FALSE 
          END; 
        ELSIF ela >= topa THEN Doio(f)
        ELSIF elodd THEN
          StoreByte(ela, TRUE, w);
          INC(ela, TSIZE(WORD)); elodd := FALSE;
          IF ela >= topa THEN Doio(f) END;
          RETURN
        ELSE
          StoreByte(ela, FALSE, w);
          elodd := TRUE;
          RETURN
        END
      END
    END
  END WriteByte;

END ByteIO.

