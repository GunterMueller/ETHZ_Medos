(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          FileSystem:                 *
*                                      *
*          Interface for               *
*          - FileSystem users  and     *
*          - FileSystem drivers.       *
*                                      *
*          Version 2  30.05.81         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

IMPLEMENTATION MODULE FileSystem;
 
  IMPORT SYSTEM;

  IMPORT Monitor;


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
 

  MODULE MediumSwitch; 

    IMPORT
      File, 
      Response, Command,
      Flag, FlagSet,
      MediumType,
      FileProc, DirectoryProc,
      SetResponse;

    FROM SYSTEM IMPORT WORD;

    FROM Monitor IMPORT CurrentLevel, TermProcedure;
 
 
    EXPORT 
      MediumHint,
      CreateMedium, RemoveMedium,
      FileCommand, DirectoryCommand;

     
    CONST
      mediums   = 8;       (* maximal number of mediums *)
      mnlength  = 7;       (* maximal length of mediumnames *)

    TYPE
      MediumHint = CARDINAL;
      MediumName = ARRAY [0..mnlength-1] OF CHAR;
      MediumKind = (free, original); 

      MediumDesc = RECORD 
                     medtyp: MediumType;
                     medno: CARDINAL;
                     level: CARDINAL; (*program level of declaration*)
                     CASE mk: MediumKind OF
                       free: | 
                       original:
                         fp: FileProc;
                         dp: DirectoryProc      
                     END;  
                   END;  


    VAR 
      mtab: ARRAY [0..mediums-1] OF MediumDesc; 
      m: MediumHint;


    PROCEDURE Equal(mt1, mt2: MediumType): BOOLEAN; 
    BEGIN   
      RETURN (mt1[0] = mt2[0]) AND (mt1[1] = mt2[1]) 
    END Equal; 


    PROCEDURE LookupMedium(mn: MediumName; VAR found: BOOLEAN;
                               VAR mt: MediumType; VAR mno: CARDINAL);

      CONST
        cardnil = 177777B; (* = 65535 *)

      VAR
        ch, cch: CHAR;
        c: CARDINAL;

    BEGIN
      ch := mn[0]; cch := CAP(ch);
      found := ('A' <= cch) AND (cch <= 'Z');
      IF found THEN
        mt[0] := ch;
        ch := mn[1]; cch := CAP(ch); c := 2;
        IF ('A' <= cch) AND (cch <= 'Z') THEN
          mt[1] := ch;
          ch := mn[2]; c := 3;
        ELSE
          mt[1] := ' ';
        END;
        IF ('0' <= ch) AND (ch <= '9') THEN
          mno := 0;
          LOOP
            mno := 10 * mno + (CARDINAL(ch) - CARDINAL('0'));
            IF c >= mnlength THEN EXIT END;
            ch := mn[c]; INC(c);
            IF (ch < '0') OR ('9' < ch) THEN EXIT END;
            IF (mno > 6553) OR (mno = 6553) AND (ch >= '5') THEN
              found := FALSE; EXIT
            END;
          END;
        ELSE mno := cardnil;
        END;
        IF (c < mnlength) AND (ch <> 0C) AND (ch <> ' ') THEN
          found := FALSE
        END;
      END;
    END LookupMedium;

 
    PROCEDURE Check(mt: MediumType): BOOLEAN;  
       
      VAR ch, cch: CHAR;

    BEGIN 
      ch := mt[0]; cch := CAP(ch); 
      IF ('A' <= cch) AND (cch <= 'Z') THEN 
        ch := mt[1]; cch := CAP(ch); 
        RETURN ('A' <= cch) AND (cch <= 'Z') OR 
               ('0' <= ch) AND (ch <= '9') OR
               (ch = ' ') 
      ELSE 
        RETURN FALSE
      END 
    END Check; 


    PROCEDURE Search(mt: MediumType; mno: CARDINAL): MediumHint; 

      VAR m: MediumHint;
 
    BEGIN 
      FOR m := 0 TO mediums-1 DO
        WITH mtab[m] DO 
          IF (mk <> free) AND Equal(medtyp, mt) AND (medno = mno)
          THEN
            RETURN m;
          END; 
        END; 
      END; 
      RETURN mediums
    END Search;


    PROCEDURE TerminateLevel;

      VAR
        m: MediumHint;
        curlev: CARDINAL;

    BEGIN
      curlev := CurrentLevel();
      FOR m := 0 TO mediums - 1 DO
        WITH mtab[m] DO
          IF (mk <> free) AND (level >= curlev) THEN
            mk := free
          END
        END
      END
    END TerminateLevel;


    PROCEDURE CreateMedium(mt: MediumType; mno: CARDINAL;
                           fproc: FileProc; dproc: DirectoryProc;
                           VAR done: BOOLEAN);

      VAR m: MediumHint;
         
    BEGIN 
      done := FALSE; 
      IF Check(mt) THEN 
        IF Search(mt, mno) >= mediums THEN 
          m := 0;
          WHILE (m<mediums) AND (mtab[m].mk<>free) DO INC(m) END;
          IF m < mediums THEN 
            done := TRUE; 
            WITH mtab[m] DO 
              medtyp := mt; medno := mno;
              level := CurrentLevel(); 
              mk := original; 
              fp := fproc; 
              dp := dproc  
            END 
          END 
        END 
      END 
    END CreateMedium; 


    PROCEDURE RemoveMedium(mt: MediumType; mno: CARDINAL;
                           VAR done: BOOLEAN);
     
      VAR m: MediumHint; 

    BEGIN
      m := Search(mt, mno); 
      done := (m < mediums) AND (mtab[m].level = CurrentLevel()); 
      IF done THEN mtab[m].mk := free END  
    END RemoveMedium; 


    PROCEDURE FileCommand(VAR f: File); 
    BEGIN
      WITH f DO 
        LOOP
          IF mh < mediums THEN
            WITH mtab[mh] DO
              IF (mk = original) AND 
                 Equal(medtyp, mt) AND (medno = mediumno)
              THEN
                fp(f); RETURN 
              END
            END
          END;
          IF Check(mt) THEN 
            mh := Search(mt, mediumno); 
            IF mh >= mediums THEN
              SetResponse(f, unknownmedium); 
              RETURN
            END 
          ELSE  
            SetResponse(f, paramerror);
            RETURN 
          END 
        END 
      END 
    END FileCommand; 


    PROCEDURE DirectoryCommand(VAR f: File; fn: ARRAY OF CHAR);

      VAR
        mn: MediumName; empty, ok: BOOLEAN;
        mt1: MediumType; mno1: CARDINAL; found: BOOLEAN;
        ch, cch: CHAR;
        c, d: CARDINAL;

    BEGIN
      WITH f DO
 
        (* split mediumname from the filename *)
        c := 0; ok := TRUE;
        LOOP
          IF c > HIGH(fn) THEN EXIT END;
          ch := fn[c]; cch := CAP(ch);
          IF ((cch < 'A') OR ('Z' < cch)) AND
             ((c = 0) OR (ch < '0') OR ('9' < ch)) THEN
            EXIT
          END;
          IF c >= mnlength THEN ok := FALSE; EXIT END;
          mn[c] := ch; INC(c);
        END;
        empty := c = 0;
        IF c < mnlength THEN mn[c] := 0C END;
        IF (c <= HIGH(fn)) AND (fn[c] = '.') THEN INC(c) END;
        d := c;
        WHILE c <= HIGH(fn) DO
          fn[c-d] := fn[c]; INC(c);
        END;
        IF d > 0 THEN fn[c-d] := 0C END;

        IF ok THEN

          IF NOT empty THEN (* convert mn to (mt, mno) *)
            LookupMedium(mn, found, mt1, mno1);
            IF found THEN
              IF (com = create) OR (com = open) THEN
                mt := mt1; mediumno := mno1;
                FileCommand(f); RETURN;
              ELSIF com = lookup THEN
                mt := mt1; mediumno := mno1;
              ELSIF com = rename THEN 
                IF NOT Equal(mt, mt1) OR (mediumno <> mno1) THEN
                  SetResponse(f, paramerror); RETURN
                END;
              END;
            ELSE SetResponse(f, unknownmedium); RETURN;
            END;
          END;

          LOOP 
            IF mh < mediums THEN
              WITH mtab[mh] DO
                IF (mk = original) AND
                   Equal(medtyp, mt) AND (medno = mediumno)
                THEN
                  dp(f, fn); RETURN 
                END
              END
            END;
            IF Check(mt) THEN 
              mh := Search(mt, mediumno); 
              IF mh >= mediums THEN 
                SetResponse(f, unknownmedium); 
                RETURN 
              END 
            ELSE 
              SetResponse(f, paramerror); 
              RETURN 
            END; 
          END;
        ELSE SetResponse(f, paramerror);
        END;
      END; 
    END DirectoryCommand;   


  BEGIN 
    FOR m := 0 TO mediums-1 DO mtab[m].mk := free END;
    TermProcedure(TerminateLevel); 
  END MediumSwitch; 


  PROCEDURE Create(VAR f: File; mn: ARRAY OF CHAR); 
  BEGIN 
    WITH f DO
      com := create; DirectoryCommand(f, mn)
    END
  END Create; 


  PROCEDURE Close(VAR f: File); 
  BEGIN f.com := close; FileCommand(f) 
  END Close; 


  PROCEDURE Lookup(VAR f: File; fn: ARRAY OF CHAR; newfile: BOOLEAN); 
  BEGIN 
    WITH f DO 
      com := lookup; new := newfile; 
      DirectoryCommand(f, fn) 
    END 
  END Lookup; 


  PROCEDURE Rename(VAR f: File; fn: ARRAY OF CHAR); 
  BEGIN f.com := rename; DirectoryCommand(f, fn)
  END Rename;  
       
   
  PROCEDURE SetRead(VAR f: File);
  BEGIN f.com := setread; FileCommand(f); 
  END SetRead;


  PROCEDURE SetWrite(VAR f: File);
  BEGIN f.com := setwrite; FileCommand(f);
  END SetWrite;


  PROCEDURE SetModify(VAR f: File);
  BEGIN f.com := setmodify; FileCommand(f);
  END SetModify;


  PROCEDURE SetOpen(VAR f: File); 
  BEGIN f.com := setopen; FileCommand(f);
  END SetOpen;


  PROCEDURE Doio(VAR f: File);
  BEGIN f.com := doio; FileCommand(f);
  END Doio;


  PROCEDURE SetPos(VAR f: File; high, low: CARDINAL);
  BEGIN 
    WITH f DO 
      com := setpos;
      highpos := high; lowpos := low
    END;   
    FileCommand(f);  
  END SetPos;   


  PROCEDURE GetPos(VAR f: File; VAR high, low: CARDINAL);   
  BEGIN 
    WITH f DO  
      com := getpos; 
      FileCommand(f);
      high := highpos; low := lowpos; 
    END 
  END GetPos;


  PROCEDURE Length(VAR f: File; VAR high, low: CARDINAL);
  BEGIN 
    WITH f DO 
      com := length; 
      FileCommand(f);  
      high := highpos; low := lowpos; 
    END 
  END Length;


 
  MODULE Streams;
 
    IMPORT
      File, Response, Flag, FlagSet, 
      SetOpen, SetRead, SetWrite, Doio,
      SetPos,
      SetResponse;

    FROM SYSTEM IMPORT WORD, TSIZE, ADDRESS;

      
    EXPORT
      Reset, Again,
      ReadWord, WriteWord,
      ReadChar, WriteChar; 
   
 
    CONST
      eofc = 0C;


    PROCEDURE Reset(VAR f: File);
    BEGIN 
      SetOpen(f);
      SetPos(f, 0, 0)
    END Reset;


    PROCEDURE Again(VAR f: File);
    BEGIN
      WITH f DO
        IF rd IN flags THEN
          IF bufa < ela THEN INCL(flags, ag)
          ELSIF (bytemode IN flags) AND elodd THEN
            INCL(flags, ag)
          END
        END
      END
    END Again;
   
  
    PROCEDURE ReadWord(VAR f: File; VAR w: WORD);
    BEGIN
      WITH f DO    
        LOOP 
          IF flags*FlagSet{rd, bytemode, ag, ef} <> FlagSet{rd} THEN  
            IF NOT (rd IN flags) THEN
              IF wr IN flags THEN
                SetResponse(f, callerror);
              ELSE SetRead(f);  
              END
            END;
            IF eof THEN RETURN END;
            IF bytemode IN flags THEN 
              IF elodd THEN INC(ela, TSIZE(WORD)); elodd := FALSE END;
              IF inodd THEN INC(ina, TSIZE(WORD)); inodd := FALSE END;
              EXCL(flags, bytemode)
            END;
            IF ag IN flags THEN DEC(ela, TSIZE(WORD)); EXCL(flags, ag) END
          ELSIF ela >= ina THEN Doio(f)
          ELSE w := ela^; INC(ela, TSIZE(WORD)); RETURN
          END
        END (* loop *)  
      END
    END ReadWord;


    PROCEDURE ReadChar(VAR f: File; VAR ch: CHAR);

      PROCEDURE LXB(a: ADDRESS; oddpos: BOOLEAN): CHAR;
      CODE
        205B
      END LXB;

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
            IF eof THEN ch := eofc; RETURN END;
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
            ch := LXB(ela, TRUE);
            INC(ela, TSIZE(WORD)); elodd := FALSE;
            RETURN
          ELSE
            ch := LXB(ela, FALSE);
            elodd := TRUE;
            RETURN
          END;
        END; (* loop *)  
      END; 
    END ReadChar;

   
    PROCEDURE WriteWord(VAR f: File; w: WORD);
    BEGIN
      WITH f DO
        LOOP 
          IF flags*FlagSet{wr, bytemode, er} <> FlagSet{wr} THEN 
            IF NOT (wr IN flags) THEN
              IF rd IN flags THEN
                SetResponse(f, callerror); 
              ELSE SetWrite(f);
                IF elodd THEN INC(ela); elodd := FALSE END;
                EXCL(flags, bytemode);
              END;
            END;
            IF er IN flags THEN RETURN END; 
            IF bytemode IN flags THEN
              EXCL(flags, bytemode);
              elodd := FALSE
            END;
          ELSIF ela >= topa THEN Doio(f)  
          ELSE ela^ := w; INC(ela, TSIZE(WORD)); RETURN
          END 
        END (* loop *)   
      END
    END WriteWord;
   

    PROCEDURE WriteChar(VAR f: File; ch: CHAR);

      PROCEDURE SXB(a: ADDRESS; oddpos: BOOLEAN; ch: CHAR);
      CODE
        225B
      END SXB;

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
            SXB(ela, TRUE, ch);
            INC(ela, TSIZE(WORD)); elodd := FALSE;
            IF ela >= topa THEN Doio(f) END;
            RETURN
          ELSE
            SXB(ela, FALSE, ch);
            elodd := TRUE;
            RETURN
          END
        END
      END
    END WriteChar;

  END Streams;

END FileSystem.

