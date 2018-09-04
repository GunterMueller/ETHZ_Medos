(********************************
*                               * 
*    Screen                     *
*    ******                     *
*                               *
*    Version 3   28.10.81       *
*                               *
*    Christian Jacobi           * 
*    Institut fuer Informatik   *
*    ETH-Zuerich                *
*    CH-8092 Zuerich            *
*                               *
********************************) 

IMPLEMENTATION MODULE Screen;  (* Ch. Jacobi  9.2.82 modifed 1.11.82*)

  (*$T-*) (*$R-*)

  (* 
     since Screen is no more resident, occurence of traps is tolerated;
     firmware too generates traps;
     the multiple RETURNS only because of efficiency 
  *)


  FROM SYSTEM IMPORT ADDRESS, WORD, ADR, TSIZE;
  FROM ScreenDriver2 IMPORT
   sysBMD, sysF, maxHeight, maxWidth, 
   BitmapDescriptor, FontDefaults, fontHint, actualDefaultsRec,
   bitmapHint, absWindow, absLine,
   ScreenProc, DefaultsRecord, SetDefaultRec, ShowBm;
  FROM Monitor IMPORT TermProcedure, SharedLevel, CurrentLevel;
  FROM Terminal IMPORT WriteString, WriteLn;
  FROM FileSystem IMPORT File, ReadWord, Response, Lookup, Close;
  FROM Frames IMPORT nil, Allocate, Deallocate;
  IMPORT ScreenDriver2;

  CONST debug = FALSE;
        interruptable = FALSE;  (* but makes everything slloooww *)
  (*

    format of fonts
    ===============

       4 word header:     length       (16-bit)
                          checksum     (16-bit) [over 4 word header and firm font]
                          baseline     ( 8-bit) | height   ( 8-bits)
                          proportional ( 1-bit) | maxwidth (15-bits) [two's complement]

       firm font:         character table followed by character info:
             TYPE ChPointer = POINTER [selfrelative] TO [w-field of] ChDesc;
             TYPE ChDesc = RECORD 
                             pat: ARRAY [1..height] OF BITSET;
                             w:   CARDINAL; [w>=0: width;
                                             w <0: use 1's complement of w 
                                                   as index to extend]
                             skip, height: [0..255] {packed;
                                                     skip means empty bottom lines}
                           END;
             TYPE font =  RECORD
                            chtable: ARRAY [0..255] OF ChPointer;
                            extend:  ARRAY [256..   ] OF ChPointer;
                            characterInfo: ARRAY [..] OF WORD
                          END;
                        
       trailer:           FontTailInfo

    - firmware:
        access with a framepointer pointing to firm font part.
        ONLY THIS PART IS USED BY FIRMWARE

    - ScreenDriver: 
        access with a framepointer pointing to firm font part.
        but uses also the header !!

    - on the file:
        a font file contains the 4 word header followed by the firm font

    - inside of this module:
        the system font 0 is: 4 word header + firm font
        all other fonts:      4 word header + firm font + trailer
        the trailer is used only inside this module;
        it may be freely changed

        REASON OF TRAILER:
          the font description array elements should be as small as possible
          the trailers memory is used only for defined fonts 

  *)



  (****************************************************)
  (* global definitions                               *)
  (****************************************************)


  CONST 
    maxSubBM  = 40;
    maxHardBM = 15;
    maxFont   = 15;
  
    fontNameLength = 16; (*length of fontname in characters*)
    
    levMod = 32;

  TYPE

    Bitmap = [0..maxSubBM];       
    Font   = [0..maxFont];


    BitmapRecord =
      RECORD
        hardAddr:  ADDRESS;         (*itself or father if subBitmap;
                                      pointer to a BitmapDescriptor*)
        subBlock:  BlockDescriptor; (*in absolute coordinates*)
        maxX:      CARDINAL;        (*in absolute coordinates*) 
        maxY:      CARDINAL;        (*in absolute coordinates*)
        father:    Bitmap;          (*or itself if not subBitmap; but not grandfather*)
        level:     CARDINAL;        (* 177777B if illegal else MOD levMod = sharedlevel*)
      END;                          (* >=levMod: memory not managed by Screen *)  


    FontRecord =
      RECORD
        hardFAddr: CARDINAL;  (*framepointer to firm font*)
        fLevel:    CARDINAL;  (* 177777B if illegal else MOD levMod = sharedlevel*)
      END;                    (* >=levMod: memory not managed by Screen *)


    FontTailInfo =
      RECORD
        fname: ARRAY [0..fontNameLength-1 + 1] OF CHAR; (*name // 0C*)
      END;

 
  CONST

    systemFont = 0;          
    systemBM   = 0;          


  VAR 

    (* descriptors *)
    BMD:   ARRAY Bitmap OF BitmapRecord; 
    hbmd:  ARRAY [0..maxHardBM] OF BitmapDescriptor;
    FONTD: ARRAY Font   OF FontRecord;

    (* state *)
    currentDefaultFont: Font;
    currentDefaultBM:   Bitmap;
    showBM:   Bitmap;
  
    (* "constants" *)
    emptyBlock:     BlockDescriptor;
    systemFontTail: FontTailInfo;
    illegalFont:    Font;
    illegalBitmap:  Bitmap;
    illegalbmd:     BitmapDescriptor;


  PROCEDURE LXFW(frame, offset: CARDINAL): CARDINAL;
  CODE 203B
  END LXFW;


  PROCEDURE SXFW(frame, offset, w: CARDINAL);
  CODE 223B
  END SXFW;


  PROCEDURE MOVF(dframe, doffset, sframe, soffset, num: CARDINAL);
  CODE 337B
  END MOVF;


  PROCEDURE AbsBlock(VAR abs: BlockDescriptor; 
               bm: Bitmap; VAR rel: BlockDescriptor);
    (*clips a relative block rel according to the Bitmap bm 
      and compute its absolute coordinates abs according to
      the main father Bitmap of bm*)
  BEGIN
    WITH (*$T+*) BMD[bm] (*$T-*) DO
      IF (rel.x<subBlock.w) AND (rel.y<subBlock.h) THEN
        abs := rel;
        INC(abs.x, subBlock.x);
        INC(abs.y, subBlock.y);
        IF abs.w>(maxX-abs.x) THEN
          abs.w := maxX-abs.x
        END;
        IF abs.h>(maxY-abs.y) THEN
          abs.h := maxY-abs.y
        END;
        RETURN
      ELSE
        abs := emptyBlock
      END
    END
  END AbsBlock;


  PROCEDURE GetTail(f: Font; VAR tail: FontTailInfo);
    VAR fp: CARDINAL;
  BEGIN 
    IF (*$T+*) FONTD[f].fLevel (*$T-*) >=levMod THEN 
      IF f=systemFont THEN tail := systemFontTail
      ELSE tail.fname := "- user defined -" END 
    ELSE
      fp := FONTD[f].hardFAddr-1;
      MOVF(0, ADR(tail), 
         fp, LXFW(fp, 0),
         TSIZE(FontTailInfo))
    END
  END GetTail;


  PROCEDURE PutTail(f: Font; VAR tail: FontTailInfo);
    VAR fp: CARDINAL;
  BEGIN 
    IF (*$T+*) FONTD[f].fLevel (*$T-*) >=levMod THEN
      IF f=systemFont THEN systemFontTail := tail END;
    ELSE
      fp := FONTD[f].hardFAddr-1;
      MOVF(fp, LXFW(fp, 0),
         0, ADR(tail), 
         TSIZE(FontTailInfo))
    END
  END PutTail;



  (****************************************************)
  (* basic operations                                 *)
  (****************************************************)



  PROCEDURE DisplayChar(VAR bm: Bitmap; VAR lineBlk: BlockDescriptor;
                        VAR f: Font; ch: CHAR);
     
    VAR abs: BlockDescriptor; dx, x1: CARDINAL;

    PROCEDURE DCH(bma: WORD; font: WORD; VAR line: BlockDescriptor; ch: CHAR);
    CODE 345B
    END DCH;
    
  BEGIN
    IF bm<=maxHardBM THEN
      DCH(BMD[bm].hardAddr, (*$T+*) FONTD[f].hardFAddr (*$T-*), lineBlk, ch);
      RETURN
    ELSE 
(* inline for speed reason only
      AbsBlock(abs, bm, lineBlk); x1 := abs.x;
      DCH(BMD[bm].hardAddr, (*$T+*) FONTD[f].hardFAddr (*$T-*), abs, ch);
      dx := abs.x-x1;
      INC(lineBlk.x, dx);
      lineBlk.w := CARDINAL(INTEGER(lineBlk.w)-INTEGER(dx));
*)
      WITH (*$T+*) BMD[bm] (*$T-*) DO
        IF (lineBlk.x<subBlock.w) AND (lineBlk.y<subBlock.h) THEN
          x1 := lineBlk.x+subBlock.x; abs.x := x1; abs.w := lineBlk.w;
          abs.y := lineBlk.y+subBlock.y; abs.h := lineBlk.h;
          IF (lineBlk.w>(maxX-x1)) OR (lineBlk.h>(maxY-abs.y)) THEN
            RETURN
          END;
          DCH(hardAddr, (*$T+*) FONTD[f].hardFAddr (*$T-*), abs, ch);
          INC(lineBlk.x, abs.x-x1);
          lineBlk.w := CARDINAL(INTEGER(lineBlk.w)-INTEGER(abs.x-x1));
        END
      END
    END
  END DisplayChar;



  PROCEDURE Replicate(VAR bm: Bitmap; VAR destBlk: BlockDescriptor;
                      m: Mode; VAR pattern: ARRAY OF WORD);

    VAR abs: BlockDescriptor; c, h: CARDINAL;

    PROCEDURE REPL(m: Mode; bm: WORD; patAddr: WORD; VAR dest: BlockDescriptor);
    CODE 343B
    END REPL;

  BEGIN
    IF interruptable THEN
      IF bm<=maxHardBM THEN abs := destBlk
        ELSE AbsBlock(abs, bm, destBlk)
      END;
      IF abs.w<5 THEN (*speed !!*)
        REPL(m, BMD[bm].hardAddr, ADR(pattern), abs);
        RETURN
      END;
      c := CARDINAL(pattern[0]); 
      h := abs.h;
      abs.h := h MOD c;
      IF abs.h>0 THEN
        REPL(m, BMD[bm].hardAddr, ADR(pattern), abs);
        INC(abs.y, abs.h); 
      END;
      abs.h := c;
      FOR h := 1 TO (h DIV c) DO
        REPL(m, BMD[bm].hardAddr, ADR(pattern), abs);
        INC(abs.y, c);
      END;
    ELSE
      IF bm<=maxHardBM THEN
        REPL(m, BMD[bm].hardAddr, ADR(pattern), destBlk);
        RETURN
      END;
        AbsBlock(abs, bm, destBlk);
        REPL(m, BMD[bm].hardAddr, ADR(pattern), abs);
    END
  END Replicate;



  PROCEDURE BlockTransfer(VAR dbm: Bitmap; VAR destBlk: BlockDescriptor;
                           m: Mode; VAR sbm: Bitmap; VAR sourceBlk: BlockDescriptor);

    VAR ab, ab2: BlockDescriptor; h: CARDINAL;
    
    PROCEDURE BBLT(m: Mode; dbma: WORD; VAR s,d: BlockDescriptor; sbma: WORD );
    CODE 344B
    END BBLT;

  BEGIN
    IF interruptable THEN 
      IF sbm<=maxHardBM THEN ab := sourceBlk 
        ELSE AbsBlock(ab, sbm, sourceBlk)
      END;
      IF dbm<=maxHardBM THEN ab2 := destBlk 
        ELSE AbsBlock(ab2, dbm, destBlk)
      END;
      h := ab2.h;
      IF h=0 THEN RETURN END;
      ab.h := 1; ab2.h := 1;
      IF ab2.y<=ab.y THEN
        FOR h := 1 TO h DO
          BBLT(m, BMD[dbm].hardAddr, ab, ab2, BMD[sbm].hardAddr);
          INC(ab.y); INC(ab2.y)
        END; 
        RETURN
      END; 
        INC(ab.y, h); INC(ab2.y, h);
        FOR h := 1 TO h DO
          DEC(ab.y); DEC(ab2.y);
          BBLT(m, BMD[dbm].hardAddr, ab, ab2, BMD[sbm].hardAddr);
        END
    ELSE (* NOT interruptable *)
      IF sbm<=maxHardBM THEN
        IF dbm<=maxHardBM THEN
          BBLT(m, BMD[dbm].hardAddr, sourceBlk, 
                                     destBlk, BMD[sbm].hardAddr);
          RETURN
        END;
          AbsBlock(ab, dbm, destBlk);
          BBLT(m, BMD[dbm].hardAddr, sourceBlk, ab, BMD[sbm].hardAddr);
          RETURN
      END;
        AbsBlock(ab, sbm, sourceBlk);
        IF dbm<=maxHardBM THEN
          BBLT(m, BMD[dbm].hardAddr, ab, destBlk, BMD[sbm].hardAddr);
          RETURN
        END;
          AbsBlock(ab2, dbm, destBlk);
          BBLT(m, BMD[dbm].hardAddr, ab, ab2, BMD[sbm].hardAddr);
    END
  END BlockTransfer;



  PROCEDURE DisplayDot(VAR bm: Bitmap; xx, yy: CARDINAL; m: Mode);

    PROCEDURE DDT(m: Mode; bma: WORD; xx, yy: CARDINAL);
    CODE 342B
    END DDT;

  BEGIN
    IF bm<=maxHardBM THEN
      DDT(m, BMD[bm].hardAddr, xx, yy);
      RETURN
    ELSE
      WITH (*$T+*) BMD[bm] (*$T-*) DO
        IF (xx<subBlock.w) AND (yy<subBlock.h) THEN
          DDT(m, hardAddr, xx+subBlock.x, yy+subBlock.y);
        END 
      END 
    END 
  END DisplayDot;




  (****************************************************)
  (* bitmap handling                                  *)
  (****************************************************)



  PROCEDURE CreateBitmap(VAR bm: Bitmap; w, h: CARDINAL;
                         VAR done: BOOLEAN);
    VAR 
      c, size, addr: CARDINAL;
  BEGIN
    done := FALSE; bm := illegalBitmap;

    (* compute c := free slot *)
    c := 0;
    LOOP
      IF c>maxHardBM THEN RETURN END;
      IF BMD[c].level=177777B THEN EXIT END; 
      INC(c)
    END;

    IF (w>0) AND (h>0) THEN 
      w := (w + 15) DIV 16 * 16;
      size :=  w DIV 16 * h; 
      Allocate(addr, size);
      IF addr<>nil THEN
        WITH BMD[c] DO
          hardAddr := ADR(hbmd[c]);
          subBlock.x := 0; 
          subBlock.y := 0;
          subBlock.w := w; maxX := w;
          subBlock.h := h; maxY := h;
          father := c;
          level := SharedLevel();
          WITH hbmd[c] DO
            bwidth    := w DIV 16;
            bheigth   := h - 2;
            bposition := 0;
            bAdr      := addr MOD 40000B * 4 + addr DIV 40000B;
          END;
          bm := c;
          done := TRUE;
        END
      END 
    END;
  END CreateBitmap;


  PROCEDURE CreateSubBitmap(VAR bm: Bitmap; VAR parent: Bitmap;
                            location: BlockDescriptor; VAR done: BOOLEAN);
    VAR c: CARDINAL; lFather: CARDINAL; abs: BlockDescriptor;
  BEGIN
    done := FALSE; bm := illegalBitmap;
    IF (parent>maxSubBM) OR (BMD[parent].level=177777B) THEN 
      RETURN
    END;

    (* compute c := free slot *)
    c := maxHardBM+1;
    LOOP
      IF c>maxSubBM THEN RETURN END;
      IF BMD[c].level=177777B THEN EXIT END; 
      INC(c)
    END;

    bm := c;
    WITH BMD[c] DO
      father := parent;
      AbsBlock(subBlock, parent, location) ;
      IF (subBlock.w=0) OR (subBlock.h=0) THEN
        IllegalizeBitmap(c); RETURN 
      END;
      maxX := subBlock.x+subBlock.w;
      maxY := subBlock.y+subBlock.h;
      lFather := parent;
      WHILE lFather>maxHardBM DO
        lFather := BMD[lFather].father
      END;
      hardAddr := BMD[lFather].hardAddr;
      level := SharedLevel();
      done := TRUE;
    END;
  END CreateSubBitmap;


  PROCEDURE ReturnBitmap(VAR bm: Bitmap);
    VAR c, b: Bitmap; l: CARDINAL;
        size: CARDINAL; temp: ADDRESS;
    (* can't return the default bitmap nor the system bitmap *)
  BEGIN
    l := SharedLevel();
    IF bm<=maxSubBM THEN
      WITH BMD[bm] DO
        IF ((level MOD levMod)>=l) AND (bm<>systemBM) THEN 
          IF bm=currentDefaultBM THEN  
            b := systemBM; SetDefaultBitmap(b) 
          END;
          FOR c := maxHardBM+1 TO maxSubBM DO
            IF (level<>177777B) AND (BMD[c].level<>177777B) AND (BMD[c].father = bm)
            AND (c<>bm) THEN
              b := c; ReturnBitmap(b)
            END;
          END;
          IF bm=showBM THEN b := systemBM; ShowBitmap(b) END;
          IF (bm<=maxHardBM) AND (level<levMod) THEN
            c := hbmd[bm].bAdr;
            c := c DIV 4 + (c MOD 4)*40000B;
            Deallocate(c);
          END;
          IllegalizeBitmap(bm)
        END 
      END
    END; 
    bm := illegalBitmap;
  END ReturnBitmap;


  PROCEDURE ShowBitmap(VAR bm: Bitmap);
  BEGIN
    IF (*$T+*) BMD[bm].level=177777B (*$T-*) THEN HALT END;
    IF bm<=maxHardBM THEN 
      ShowBm(hbmd[bm]);
      showBM := bm;
    ELSE
      ShowBitmap(BMD[bm].father)
    END
  END ShowBitmap;


  PROCEDURE GetMaxBlock(VAR b: BlockDescriptor; VAR bm: Bitmap);
  BEGIN
    GetRealBlock(b, bm);
    b.x := 0;
    b.y := 0;
  END GetMaxBlock;


  PROCEDURE IsSubBitmap(VAR bm: Bitmap): BOOLEAN;
  BEGIN 
    IF debug AND (*$T+*) (BMD[bm].level=177777B) (*$T-*) THEN HALT END;
    RETURN (bm>maxHardBM) AND (bm<=maxSubBM)
  END IsSubBitmap;


  PROCEDURE GetRealFather(VAR fbm, bm: Bitmap);
    VAR lbm: CARDINAL;
  BEGIN 
    IF debug AND (*$T+*) (BMD[bm].level=177777B) (*$T-*) THEN HALT END;
    lbm := bm;
    WHILE lbm>maxHardBM DO lbm := BMD[lbm].father END;
    fbm := lbm
  END GetRealFather;

  
  PROCEDURE GetRealBlock(VAR blk: BlockDescriptor; VAR bm: Bitmap);
  BEGIN 
    IF debug AND (*$T+*) (BMD[bm].level=177777B) (*$T-*) THEN HALT END;
    IF bm<=maxSubBM THEN
      blk := BMD[bm].subBlock;
    ELSE
      blk := emptyBlock
    END
  END GetRealBlock;




  (****************************************************)
  (* font handling                                    *)
  (****************************************************)


  
  PROCEDURE FontNumber(VAR name: ARRAY OF CHAR): Font;

    PROCEDURE EqualString(VAR s1: ARRAY OF CHAR; s2: ARRAY OF CHAR): BOOLEAN;
      VAR i: CARDINAL;
    BEGIN
      i := 0;
      LOOP
        IF i>HIGH(s1) THEN 
          RETURN (i>HIGH(s2)) OR (s2[i]=0C)
        END;
        IF i>HIGH(s2) THEN 
          RETURN (s1[i]=0C)
        END;
        IF s1[i]<>s2[i] THEN RETURN FALSE END;
        IF s1[i]=0C THEN RETURN TRUE END;
        INC(i)
      END
    END EqualString;

    VAR
      c: Font;
      tail: FontTailInfo;
  BEGIN
    c := 0;
    LOOP
      IF c>maxFont THEN c := illegalFont; EXIT END;
      IF ((c=systemFont) OR (FONTD[c].hardFAddr<>FONTD[systemFont].hardFAddr)) 
         AND (FONTD[c].hardFAddr<177777B) AND (FONTD[c].fLevel<177777B)
      THEN
        GetTail(c, tail);
        IF EqualString(name, tail.fname) THEN EXIT END
      END;
      INC(c)
    END;
    RETURN c
  END FontNumber;


  PROCEDURE FontValid(frame: CARDINAL): BOOLEAN;
    (* structure at frame [firm font] looks like a font*)
    VAR i, checksum, word: CARDINAL;
  BEGIN
    DEC(frame);
    checksum := 0;
    FOR i := 0 TO LXFW(frame, 0)-1 DO
      word := LXFW(frame, i);
      IF checksum<=(177777B-word) THEN checksum := checksum+word
      ELSE checksum := checksum - (177777B-word) - 1
      END
    END;
    RETURN checksum = 0
  END FontValid;


  PROCEDURE SimpleLoadFont(VAR c: CARDINAL; VAR fi: File; VAR okdone: BOOLEAN);
    VAR length, addr, i, w: CARDINAL;
  BEGIN
    okdone := FALSE;

    IF (fi.res<>done) THEN RETURN END;
    ReadWord(fi, length);
    Allocate(addr, length+TSIZE(FontTailInfo));
    IF addr=nil THEN RETURN END;
    SXFW(addr, 0, length);
    i := 1;
    WHILE i<length DO
      ReadWord(fi, w);
      SXFW(addr, i, w);
      INC(i)
    END;

    IF (fi.res=done) AND FontValid(addr+1) THEN
      WITH FONTD[c] DO
        hardFAddr := addr+1; (*gives a framepointer to firm font*)
        fLevel := SharedLevel();
      END;
      okdone := TRUE;
    ELSE
      Deallocate(addr);
    END;
  END SimpleLoadFont;


  PROCEDURE LoadFont(VAR f: Font; name: ARRAY OF CHAR; VAR ok: BOOLEAN);
    VAR
      loaded: BOOLEAN;
      fn: ARRAY [-3..fontNameLength-1+5] OF CHAR; (*name//".SCF"//0C*)
      F: File;
      tail: FontTailInfo;
      i, j, c: CARDINAL;
  BEGIN
    ok := FALSE; f := illegalFont;

    (*compute c := free slot*)
    c := 1;
    LOOP
      IF c>maxFont THEN RETURN END;
      IF FONTD[c].fLevel=177777B THEN EXIT END; 
      c := c+1
    END;
 
    i := FontNumber(name);
    IF (name[0]=0C) OR (i=systemFont) THEN c := systemFont; ok := TRUE;
    ELSIF i<=maxFont THEN
      FONTD[c] := FONTD[i];
      FONTD[c].fLevel := SharedLevel();
      ok := TRUE
    ELSE
      (* compute fn := filename(name) *)
      fn[-3] := "D"; fn[-2] := "K"; fn[-1] := ".";  
      i := 0;
      WHILE (i<=HIGH(name)) AND (i<fontNameLength) AND (name[i]<>0c) DO
        fn[i] := name[i]; i := i+1
      END;
      fn[i] := ".";
      fn[i+1] := "S"; fn[i+2] := "C"; fn[i+3] := "F";  
      fn[i+4] := 0C;

      Lookup(F, fn, FALSE);
      IF F.res=done THEN SimpleLoadFont(c, F, ok) END;
      Close(F);
      IF ok THEN
        FOR j := 0 TO i DO tail.fname[j] := fn[j] END;
        FOR j := i TO fontNameLength DO tail.fname[i] := 0C; END;
        PutTail(c, tail)
      END
    END;
    IF ok THEN f := c;
(**)  IF FontWidth(f)=0 THEN ok := FALSE; ReturnFont(f) END; 
      (*eliminate line later, when all fonts are ok; checksum is enough test*)
    END;
  END LoadFont;


  PROCEDURE ReturnFont(VAR f: Font);
    VAR l, i: CARDINAL;
  BEGIN
    IF f<=maxFont THEN
      WITH FONTD[f] DO
        IF ((fLevel MOD levMod)>= SharedLevel()) AND (f<>systemFont) THEN
          IF f=currentDefaultFont THEN 
            currentDefaultFont := systemFont; 
            FontDefaults(FONTD[0].hardFAddr);
          END;

          IF (hardFAddr<>sysF) AND (fLevel<levMod) THEN
            i := 0;
            FOR l := 1 TO maxFont DO 
              IF FONTD[l].hardFAddr=hardFAddr THEN i := i+1 END
            END;
            IF i=1 THEN l := hardFAddr-1; Deallocate(l) END;
          END;

          IllegalizeFont(f);
         END
      END
    END;
    f := illegalFont
  END ReturnFont;


  PROCEDURE GetFontName(VAR name: ARRAY OF CHAR; VAR f: Font);
    (* returns empty name if font is illegal *)

    PROCEDURE AssignString(VAR res: ARRAY OF CHAR; source: ARRAY OF CHAR);
      VAR i: CARDINAL;
    BEGIN
      i  := 0;
      WHILE (i<=HIGH(res)) AND (i<=HIGH(source)) AND (source[i]<>0C) DO
        res[i] := source[i];
        INC(i) 
      END;
      IF i<=HIGH(res) THEN
        res[i] := 0C;
      END;
    END AssignString;

    VAR tail: FontTailInfo;
  BEGIN
    IF (f>maxFont) OR (FONTD[f].fLevel=177777B) THEN
       name[0] := 0c
    ELSE
      GetTail(f, tail);
      AssignString(name, tail.fname)
    END
  END GetFontName;



  (****************************************************)
  (* font operators                                   *)
  (****************************************************)



  PROCEDURE Proportional(VAR f: Font): BOOLEAN;
  BEGIN
    IF debug AND ( (*$T+*) FONTD[f].fLevel=177777B (*$T-*) ) THEN HALT END;
    RETURN INTEGER(LXFW(FONTD[f].hardFAddr-1, 3))<0
  END Proportional;
 

  PROCEDURE FontHeight(VAR f: Font): CARDINAL;
  BEGIN
    IF debug AND ( (*$T+*) FONTD[f].fLevel=177777B (*$T-*) ) THEN HALT END;
    RETURN LXFW(FONTD[f].hardFAddr-1, 2) MOD 256
  END FontHeight;


  PROCEDURE FontBaseLine(VAR f: Font): CARDINAL;
  BEGIN
    IF debug AND ( (*$T+*) FONTD[f].fLevel=177777B (*$T-*) ) THEN HALT END;
    RETURN LXFW(FONTD[f].hardFAddr-1, 2) DIV 256
  END FontBaseLine;


  PROCEDURE FontWidth(VAR f: Font): CARDINAL;
  BEGIN
    IF debug AND ( (*$T+*) FONTD[f].fLevel=177777B (*$T-*) ) THEN HALT END;
    RETURN ABS(INTEGER(LXFW(FONTD[f].hardFAddr-1, 3)));
  END FontWidth;


  PROCEDURE CharWidth(VAR f: Font; ch: CHAR): CARDINAL;
    VAR offset, ffrm, width: CARDINAL;
  BEGIN
    IF debug AND ( (*$T+*) FONTD[f].fLevel=177777B (*$T-*) ) THEN HALT END;
    width := 0;
    ffrm := FONTD[f].hardFAddr;
    LOOP
      offset := LXFW(ffrm, ORD(ch) + LXFW(ffrm, ORD(ch)) );
      IF INTEGER(offset)>=0 THEN
        RETURN width+offset
      END; 
      INC(width, 16);
      ch := CHAR(-INTEGER(offset)-1 (*one's complement!*) )
    END
  END CharWidth;



  (****************************************************)
  (* defaults                                         *)
  (****************************************************)



  PROCEDURE GetDefaultBitmap(VAR bm: Bitmap);
  BEGIN
    ScreenDriver2.actualDefaultsRec.getDefaultBitmap(bm)
  END GetDefaultBitmap;


  PROCEDURE SetDefaultBitmap(VAR bm: Bitmap);
  BEGIN
    ScreenDriver2.actualDefaultsRec.setDefaultBitmap(bm)
  END SetDefaultBitmap;


  PROCEDURE GetDefaultFont(VAR f: Font);
  BEGIN 
    ScreenDriver2.actualDefaultsRec.getDefaultFont(f)
  END GetDefaultFont;


  PROCEDURE SetDefaultFont(VAR f: Font);
  BEGIN 
    ScreenDriver2.actualDefaultsRec.setDefaultFont(f)
  END SetDefaultFont;


  PROCEDURE GetDotPos(VAR x, y: CARDINAL);
  BEGIN
    ScreenDriver2.actualDefaultsRec.getDotPos(x, y)
  END GetDotPos;


  PROCEDURE SetDotPos(x, y: CARDINAL);
  BEGIN
    ScreenDriver2.actualDefaultsRec.setDotPos(x, y)
  END SetDotPos;


  PROCEDURE GetSystemBitmap(VAR bm: Bitmap);
  BEGIN 
    bm := systemBM
  END GetSystemBitmap;


  PROCEDURE GetSystemFont(VAR f: Font);
  BEGIN 
    f := systemFont
  END GetSystemFont;


  PROCEDURE XGetDotPos(VAR x, y: CARDINAL);
  BEGIN
    x := ScreenDriver2.absLine.x-absWindow.x;
    y := ScreenDriver2.absLine.y+FontBaseLine(currentDefaultFont)-absWindow.y
  END XGetDotPos;


  PROCEDURE XSetDotPos(x, y: CARDINAL);
    VAR bl: CARDINAL;
  BEGIN bl := FontBaseLine(currentDefaultFont);
    IF (x<=absWindow.w) AND (y<=absWindow.h) THEN
      absLine.x := x+absWindow.x;
      absLine.y := y+absWindow.y;
      IF absLine.y>bl THEN DEC(absLine.y, bl) ELSE absLine.y := 0 END;
      FontDefaults(FONTD[currentDefaultFont].hardFAddr); (*resets position*)
    END
  END XSetDotPos;


  PROCEDURE XGetDefaultFont(VAR f: Font);
  BEGIN 
    f := currentDefaultFont
  END XGetDefaultFont;


  PROCEDURE XGetDefaultBitmap(VAR bm: Bitmap);
  BEGIN
    bm := currentDefaultBM
  END XGetDefaultBitmap;


  PROCEDURE XSetDefaultBitmap(VAR bm: Bitmap); 
    (* garanties inside but not necessary nice position*)
    VAR lh: CARDINAL;
  BEGIN 
    IF (*$T+*) (BMD[bm].level=177777B) (*$T-*) THEN HALT END;
    currentDefaultBM := bm;
    absWindow := ScreenDriver2.BlockDescriptor(BMD[bm].subBlock);
    bitmapHint := BMD[bm].hardAddr;
    FontDefaults(FONTD[currentDefaultFont].hardFAddr); (*resets position*)
  END XSetDefaultBitmap;



  PROCEDURE XSetDefaultFont(VAR f: Font);
    VAR c, bl: CARDINAL;
  BEGIN
    IF (*$T+*) FONTD[f].fLevel=177777B (*$T-*) THEN HALT
    ELSE
      c := absLine.y+FontBaseLine(currentDefaultFont);
      currentDefaultFont := f;
      bl := FontBaseLine(currentDefaultFont);
      IF c>bl THEN absLine.y := c-bl ELSE absLine.y := 0 END;
      FontDefaults(FONTD[f].hardFAddr);
    END
  END XSetDefaultFont;



  (****************************************************)
  (* privates                                         *)
  (****************************************************)


  PROCEDURE GetBmdA(VAR bm: Bitmap; VAR bmda: ADDRESS);
  BEGIN 
    IF debug AND (*$T+*) (BMD[bm].level=177777B) (*$T-*) THEN HALT END;
    (*$T+*) bmda := BMD[bm].hardAddr (*$T-*)
  END GetBmdA; 


  PROCEDURE GetFfpA(VAR f: Font; VAR ffpa: ADDRESS);
  BEGIN
    IF debug AND ( (*$T+*) FONTD[f].fLevel=177777B (*$T-*) ) THEN HALT END;
    ffpa := (*$T+*) ADR(FONTD[f].hardFAddr) (*$T-*) 
  END GetFfpA;


(*
  PROCEDURE BitmapLevel(VAR bm: Bitmap): CARDINAL;
  BEGIN 
    RETURN (*$T+*) BMD[bm].level MOD levMod (*$T-*)
  END BitmapLevel;


  PROCEDURE FontLevel(VAR f: Font): CARDINAL;
  BEGIN 
    RETURN (*$T+*) FONTD[f].fLevel MOD levMod (*$T-*)
  END FontLevel;
*)


  PROCEDURE UseBitmap(VAR bm: Bitmap; w, h: CARDINAL;
                      at, size: CARDINAL; VAR done: BOOLEAN);
    VAR c, csize: CARDINAL;
  BEGIN
    done := FALSE; bm := illegalBitmap;

    (* compute c := free slot *)
    c := 0;
    LOOP
      IF c>maxHardBM THEN RETURN END;
      IF BMD[c].level=177777B THEN EXIT END; 
      INC(c)
    END;
    IF (w>0) AND (h>0) THEN 
      w := (w + 15) DIV 16 * 16;
      csize :=  w DIV 16 * h; 
      IF size>=csize THEN
        WITH BMD[c] DO
          hardAddr := ADR(hbmd[c]);
          subBlock.x := 0; 
          subBlock.y := 0;
          subBlock.w := w; maxX := w;
          subBlock.h := h; maxY := h;
          father := c;
          level := SharedLevel() + levMod;
          WITH hbmd[c] DO
            bwidth    := w DIV 16;
            bheigth   := h - 2;
            bposition := 0;
            bAdr      := at MOD 40000B * 4 + at DIV 40000B;
          END;
          bm := c;
          done := TRUE;
        END (*with BMD*)
      END 
    END
  END UseBitmap;


  PROCEDURE UseFont(VAR f: Font; name: ARRAY OF CHAR; 
                    at, size: CARDINAL; VAR done: BOOLEAN);
    VAR c: CARDINAL;
  BEGIN
    done := FALSE; f := illegalFont;

    (*compute c := free slot*)
    c := 1;
    LOOP
      IF c>maxFont THEN RETURN END;
      IF FONTD[c].fLevel=177777B THEN EXIT END; 
      c := c+1
    END;

    IF  FontValid(at+1) THEN
      WITH FONTD[c] DO
        fLevel := SharedLevel()+levMod;
        hardFAddr := at+1; (*gives a framepointer to firm font*)
        f := c; done := TRUE;
      END;
    END
  END UseFont;



  (****************************************************)
  (* system state                                     *)
  (****************************************************)


  PROCEDURE IllegalizeFont(f: Font);
  BEGIN
    IF (f<=maxFont) AND (f<>systemFont) THEN
      WITH FONTD[f] DO
        hardFAddr := sysF;
        fLevel    := 177777B;
      END
    END
  END IllegalizeFont;


  PROCEDURE IllegalizeBitmap(bm: Bitmap);
  BEGIN
    IF (bm<=maxSubBM) AND (bm<>systemBM) THEN
      WITH BMD[bm] DO
        hardAddr := ADR(illegalbmd);
        subBlock := emptyBlock;
        maxX     := 0;
        maxY     := 0;
        father   := 0;
        level    := 177777B;
      END 
    END;
  END IllegalizeBitmap;


  PROCEDURE InitStructures;
    VAR c: CARDINAL;
    VAR defRec: DefaultsRecord;
  BEGIN
    c := 177777B;          (*trick to bypass compiler message*)
    illegalFont := c;
    illegalBitmap := c;

    WITH defRec DO
      getDefaultFont :=   ScreenProc(XGetDefaultFont); 
      setDefaultFont :=   ScreenProc(XSetDefaultFont); 
      getDefaultBitmap := ScreenProc(XGetDefaultBitmap);
      setDefaultBitmap := ScreenProc(XSetDefaultBitmap);
      getDotPos := XGetDotPos;
      setDotPos := XSetDotPos;
    END;
    SetDefaultRec(defRec);

    illegalbmd := sysBMD;
    WITH illegalbmd DO
      bwidth := 0; bheigth := 0;
    END;
 
    FOR c := 0 TO maxSubBM DO IllegalizeBitmap(c) END;
   
    hbmd[0] := sysBMD;

    WITH BMD[0] DO
      hardAddr := ADR(hbmd[0]); 
      maxX := maxWidth;
      maxY := maxHeight;
      WITH subBlock DO 
        x := 0; y := 0; w := maxWidth; h := maxHeight 
      END; 
      father := 0;
      level := SharedLevel();
    END;

    FOR c := 1 TO maxFont DO
      IllegalizeFont(c);
    END;

    WITH FONTD[systemFont] DO
      hardFAddr := sysF;
      fLevel := SharedLevel()+levMod;
    END; 
  END InitStructures;


  PROCEDURE ReturnLevel;
    VAR
      c, l: CARDINAL;
      bm: Bitmap;
  BEGIN
    l := CurrentLevel();
    IF (currentDefaultFont>maxFont) OR
       ((FONTD[currentDefaultFont].fLevel MOD levMod)>=l) THEN
      currentDefaultFont := systemFont;
    END;
    IF (currentDefaultBM>maxSubBM) OR ((BMD[currentDefaultBM].level MOD levMod)>=l) THEN
      currentDefaultBM := systemBM;
    END;
    FOR c := 1 TO maxSubBM DO
      IF (BMD[c].level MOD levMod)>=l THEN
        (*bitmap memory is returned by memory handler*)
        IllegalizeBitmap(c);
      END;
    END;
    FOR c := 1 TO maxFont DO
      IF (FONTD[c].fLevel MOD levMod)>=l THEN
        (*font memory is returned by memory handler*)
        IllegalizeFont(c)
      END;
    END;
    c := 0; ShowBitmap(c)
  END ReturnLevel;


BEGIN
  WITH emptyBlock DO
    x := 0; y := 0; w := 0; h := 0 
  END;
  InitStructures;
  currentDefaultBM := systemBM;
  currentDefaultFont := systemFont;
  systemFontTail.fname := "GACHA14";
  TermProcedure(ReturnLevel);
END Screen.

