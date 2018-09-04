MODULE setfont; (* WW 31.5.83 *)

FROM Terminal IMPORT Write, WriteString, WriteLn, Read;
FROM SEK IMPORT CallComint;
FROM Program IMPORT Status;
FROM Screen IMPORT Font, LoadFont, SetDefaultFont,
  Bitmap, BlockDescriptor, GetDefaultBitmap, GetMaxBlock,
  CreateSubBitmap, SetDefaultBitmap;
FROM FileNames IMPORT ReadFileName;

CONST
  FF = 14c;
VAR
  name: ARRAY[0..31] OF CHAR;
  ch: CHAR;
  f: Font;
  ok: BOOLEAN;
  st: Status;
  bm,
  new: Bitmap;
  blk: BlockDescriptor;


PROCEDURE ExtractFontName;
VAR
  i,j,
  ext: CARDINAL;
BEGIN
  i := 0;
  REPEAT INC(i); UNTIL name[i-1] = '.';
  j := i;
  REPEAT
    name[i-j] := name[i];
    IF name[i] = '.' THEN ext := i-j; END;
    INC(i);
  UNTIL (name[i] = 0c) OR (i > 31);
  name[ext] := 0c;
END ExtractFontName;


BEGIN
  WriteString(" which font should be default > ");
  ReadFileName(name, "DK.GACHA26.SCF");
  Read(ch);
  IF name[0] <> 0c THEN
    ExtractFontName;
    LoadFont(f, name, ok);
    IF ok THEN
      SetDefaultFont(f);
  
(*    if the video signal is used to be projected then only part of the screen
      should be used for visibility reasons:
  
      GetDefaultBitmap(bm);
      GetMaxBlock(blk,bm);
      WITH blk DO
        INC(x,10); INC(y,10);
        DEC(w,20); DEC(h,20);
      END;
      CreateSubBitmap(new,bm,blk,ok);
      IF ok THEN SetDefaultBitmap(new);
      ELSE WriteString(" shrink bitmap failed"); WriteLn;
      END;
*)  
      Write(FF);
      REPEAT
        CallComint(FALSE, st);
      UNTIL st = programalreadyloaded;
      Write(FF);
    ELSE
      WriteString(" font not loaded");
      WriteLn;
    END;
  ELSE
    WriteString(" no file");
    WriteLn;
  END;
END setfont.
