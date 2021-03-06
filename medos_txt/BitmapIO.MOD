IMPLEMENTATION MODULE BitmapIO; (* Werner Winiger 8.10.82 *)
                                (* V4-version supporting  *)
                                (* both screen variants   *)

  FROM SYSTEM IMPORT
    ADDRESS, ADR, WORD, TSIZE;
  FROM Screen IMPORT
    Bitmap;
  FROM ScreenResources0 IMPORT
    PToBMD;
  FROM FileSystem IMPORT
    File, Reset, Length, Response, ReadWord, WriteWord;
  FROM ByteBlockIO IMPORT
    ReadBytes, WriteBytes;

  CONST
    FileKey = 341b;
    CurrentVersion = 0;

  TYPE
    BitmapPtr = POINTER TO BitmapDescriptor;
    BitmapDescriptor = RECORD
      address: ADDRESS;
      width,
      height : CARDINAL;
      layout : BITSET;
    END;

    BitmapFileHeader = RECORD
      key,
      version,
      width,
      height : CARDINAL;
    END;


PROCEDURE ReadBitmap (VAR f: File; VAR bm: Bitmap);
  (*
  reads binary data from file f into the bitmap bm. *)

  VAR
    header       : BitmapFileHeader;
    bmdPtr       : BitmapPtr;
    bitmapAddress: CARDINAL;
    hi,lo,i,j,
    actualLength : CARDINAL;
    fileLength,
    fileWidth,
    bitmapLines,
    bitmapWidth,
    lines, words : CARDINAL;
    frame        : ADDRESS;
    offset       : CARDINAL;
    w            : WORD;

  PROCEDURE SXFW (fr: ADDRESS; offs: CARDINAL; w: WORD);
  CODE
    223b;
  END SXFW;

BEGIN
  bmdPtr := BitmapPtr(PToBMD(bm));
  bitmapAddress := bmdPtr^.address;
  Reset(f);
  IF f.res = done THEN
    Length(f,hi,lo);
    IF hi > 0 THEN
      IF hi > 1 THEN HALT; END;
      fileLength := 8000h + lo DIV 2;
    ELSE
      fileLength := lo DIV 2;
    END;
    ReadBytes(f,ADR(header),2*TSIZE(BitmapFileHeader),actualLength);
    IF actualLength < 2*TSIZE(BitmapFileHeader) THEN HALT; END;
    WITH header DO
      IF key = FileKey THEN
        IF width MOD 16 # 0 THEN HALT; END;
        IF version # CurrentVersion THEN HALT; END;
        DEC(fileLength,actualLength DIV 2);
      ELSE
        width := 768;
        height := 592;
        Reset(f);
      END;
      fileWidth := width DIV 16;
    END;
    WITH bmdPtr^ DO
      bitmapLines := (height+2) DIV 2 * 2;
      bitmapWidth := width;
    END;
    frame := (bitmapAddress DIV 4) + 4000h * (bitmapAddress MOD 4);
    offset := 0;
    IF fileWidth = bitmapWidth THEN 
(* file and bitmap have the same dimension *)
      lines := fileLength DIV fileWidth;
      IF lines >= bitmapLines THEN 
        lines := bitmapLines;
        words := 0;
      ELSE 
        words := fileLength MOD fileWidth;
        IF words > bitmapWidth THEN words := bitmapWidth; END;
      END;
      FOR i := 1 TO lines DO
        IF bitmapAddress MOD 4 = 0 THEN (* bitmap is in bank 0 *)
          ReadBytes(f,bitmapAddress,2*bitmapWidth,actualLength);
          INC(bitmapAddress,bitmapWidth);
          INC(offset,bitmapWidth);
        ELSE
          FOR j := 1 TO bitmapWidth DO
            ReadWord(f,w);
            SXFW(frame,offset,w);
            INC(offset);
          END;
        END;
      END;
      FOR i := 1 TO words DO
        ReadWord(f,w);
        SXFW(frame,offset,w);
        INC(offset);
      END;
    ELSIF fileWidth < bitmapWidth THEN
(* the file is narrower than the bitmap *)
      lines := fileLength DIV fileWidth;
      IF lines >= bitmapLines THEN
        lines := bitmapLines;
        words := 0;
      ELSE
        words := fileLength MOD fileWidth;
      END;
      FOR i := 1 TO lines DO
        IF bitmapAddress MOD 4 = 0 THEN (* bitmap is in bank 0 *)
          ReadBytes(f,bitmapAddress,2*fileWidth,actualLength);
          INC(bitmapAddress,bitmapWidth);
          INC(offset,bitmapWidth);
        ELSE
          FOR j := 1 TO fileWidth DO
            ReadWord(f,w);
            SXFW(frame,offset,w);
            INC(offset);
          END;
          INC(offset,bitmapWidth-fileWidth);
        END;
      END;
      FOR i := 1 TO words DO
        ReadWord(f,w);
        SXFW(frame,offset,w);
        INC(offset);
      END;
    ELSE
(* the file is taller than the bitmap *)
      lines := fileLength DIV fileWidth;
      IF lines >= bitmapLines THEN 
        lines := bitmapLines;
        words := 0;
      ELSE 
        words := fileLength MOD fileWidth;
        IF words > bitmapWidth THEN words := bitmapWidth; END;
      END;
      FOR i := 1 TO lines DO
        IF bitmapAddress MOD 4 = 0 THEN (* bitmap is in bank 0 *)
          ReadBytes(f,bitmapAddress,2*bitmapWidth,actualLength);
          INC(bitmapAddress,bitmapWidth);
          INC(offset,bitmapWidth);
          FOR j := 1 TO fileWidth-bitmapWidth DO
            ReadWord(f,w);
          END;
        ELSE
          FOR j := 1 TO bitmapWidth DO
            ReadWord(f,w);
            SXFW(frame,offset,w);
            INC(offset);
          END;
          FOR j := 1 TO fileWidth-bitmapWidth DO
            ReadWord(f,w);
          END;
        END;
      END;
      FOR i := 1 TO words DO
        ReadWord(f,w);
        SXFW(frame,offset,w);
        INC(offset);
      END;
    END;
  ELSE
    HALT;
  END;
END ReadBitmap;


PROCEDURE WriteBitmap (VAR f: File; VAR bm: Bitmap);
  (*
  writes the bitmap bm onto the file f.             *)

  VAR
    header       : BitmapFileHeader;
    bmdPtr       : BitmapPtr;
    bitmapAddress,
    bitmapLength : CARDINAL;
    frame        : ADDRESS;
    offset       : CARDINAL;

  PROCEDURE LXFW (fr: ADDRESS; offs: CARDINAL): WORD;
  CODE
    203b;
  END LXFW;

BEGIN
  bmdPtr := BitmapPtr(PToBMD(bm));
  bitmapAddress := bmdPtr^.address;
  WITH header DO
    key := FileKey;
    version := CurrentVersion;
    width := bmdPtr^.width * 16;
    height := (bmdPtr^.height+2) DIV 2 * 2;
    bitmapLength := bmdPtr^.width * height;
  END;
  WriteBytes(f,ADR(header),2*TSIZE(BitmapFileHeader));
  
  IF bitmapAddress MOD 4 = 0 THEN
    IF bitmapLength > 8000h THEN
      WriteBytes(f,bitmapAddress,8000h);
      INC(bitmapAddress,4000h);
      WriteBytes(f,bitmapAddress,8000h);
      INC(bitmapAddress,4000h);
      DEC(bitmapLength,8000h);
    END;
    WriteBytes(f,bitmapAddress,2*bitmapLength);
  ELSE
    frame := (bitmapAddress DIV 4) + 4000h * (bitmapAddress MOD 4);
    offset := 0;
    REPEAT
      WriteWord(f,LXFW(frame,offset));
      INC(offset);
      DEC(bitmapLength);
    UNTIL bitmapLength = 0;
  END;
END WriteBitmap;


END BitmapIO.
