MODULE ShowPicture; (* Werner Winiger 15.6.1982 *)

  FROM FileSystem  IMPORT File, Response, Lookup, Close;
  FROM FileNames   IMPORT ReadFileName;
  FROM BitmapIO    IMPORT ReadBitmap;
  FROM Screen      IMPORT Bitmap, GetDefaultBitmap;
  FROM Terminal    IMPORT Read, ReadAgain, Write, WriteString, WriteLn;

  CONST
    EOL = 36c;
    ESC = 33c;
    FF  = 14c;

  TYPE
    FileName= ARRAY [0..31] OF CHAR;

  VAR
    bitmap: Bitmap;
    f     : File;
    fN    : FileName;
    ch    : CHAR;


BEGIN
  GetDefaultBitmap(bitmap);
  
  LOOP
    LOOP
      WriteString(' which one ? (ESC / filename) ');
      Read(ch);
      IF ch = ESC THEN Write(FF); RETURN;
      ELSE ReadAgain;
      END;
      ReadFileName(fN,'DK.Chillon.PICT'); 
      Read(ch);
      IF fN[0] = 0c THEN
        IF ch = ESC THEN Write(FF); RETURN;
        ELSIF (ch = ' ') OR (ch = EOL) THEN fN := 'DK.Chillon.PICT'; EXIT;
        ELSE WriteLn;
        END;
      ELSE 
        EXIT;
      END;
    END;

    Lookup(f,fN,FALSE);
    IF f.res = done THEN
      Write(FF);
      ReadBitmap(f,bitmap);
      Read(ch);
      Write(FF);
      Close(f);
      IF ch = ESC THEN EXIT; END;
    ELSE
      WriteString(' not found');
      WriteLn;
    END;
  END;
  Write(FF);
END ShowPicture.
