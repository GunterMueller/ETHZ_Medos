IMPLEMENTATION MODULE CursorRelations; (* Ch. Jacobi*)
  FROM WindowHandler IMPORT Window;
  FROM CursorStuff IMPORT xpos, ypos;
  FROM Screen IMPORT FontWidth, FontHeight;


  PROCEDURE Inside(w: Window): BOOLEAN;
  BEGIN
    WITH w^ DO
      RETURN (xpos>=innerblk.x) AND (ypos>=innerblk.y)
         AND (xpos-innerblk.x<innerblk.w) AND (ypos-innerblk.y<innerblk.h)
    END
  END Inside;
  

  PROCEDURE DownCharPos(w: Window): CARDINAL;
    VAR fontHeight: CARDINAL;
  BEGIN
    fontHeight := FontHeight(w^.font);
    RETURN (w^.innerblk.h-UpDotPos(w)+1) DIV (fontHeight+(fontHeight DIV 10)+1)
  END DownCharPos;


  PROCEDURE RightCharPos(w: Window): CARDINAL;
  BEGIN
    RETURN RightDotPos(w) DIV FontWidth(w^.font);  
  END RightCharPos;


  PROCEDURE UpDotPos(w: Window): CARDINAL;
  BEGIN
    IF Inside(w) THEN
      RETURN ypos-w^.innerblk.y
    ELSE 
      RETURN 0
    END
  END UpDotPos;


  PROCEDURE RightDotPos(w: Window): CARDINAL;
  BEGIN
    IF Inside(w) THEN
      RETURN xpos-w^.innerblk.x
    ELSE 
      RETURN 0
    END
  END RightDotPos;


END CursorRelations.

