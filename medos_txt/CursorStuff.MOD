(********************************
*                               * 
*    CursorStuff                *
*    ***********                *
*                               *
*    Version 3   2.8.81         *
*                               *
*    Christian Jacobi           * 
*    Institut fuer Informatik   *
*    ETH-Zuerich                *
*    CH-8092 Zuerich            *
*                               *
********************************) 

IMPLEMENTATION MODULE CursorStuff;  (* Ch. Jacobi 2.8.81*)
  IMPORT 
    SYSTEM, Terminal, Monitor, Screen;

  (*$T-*)
  (*$R-*)
  MODULE MouseCoords;
    FROM SYSTEM IMPORT WORD;
    EXPORT QUALIFIED MouseState, windowx, windowy;
    (*windowx, windowy initialized outside*)

    VAR 
      newx, oldx, bigx, windowx,
      newy, oldy, bigy, windowy: INTEGER;
  
    PROCEDURE GET(chan: CARDINAL; VAR val: WORD); 
      CODE 240B
    END GET;

    PROCEDURE MouseState(VAR x, y, b: CARDINAL); 
    BEGIN
      GET(6, newx);
      IF newx-oldx>512 THEN bigx := bigx+newx-oldx-1024
        ELSIF oldx-newx>512 THEN bigx := bigx+newx-oldx+1024
        ELSE bigx := bigx+newx-oldx
      END;
      WHILE bigx<0 DO bigx := bigx+windowx END;
      WHILE bigx>=windowx DO bigx := bigx-windowx END;
      x := bigx; oldx := newx;
      GET(7, newy);
      IF newy-oldy>512 THEN bigy := bigy+newy-oldy-1024
        ELSIF oldy-newy>512 THEN bigy := bigy+newy-oldy+1024
        ELSE bigy := bigy+newy-oldy
      END;
      WHILE bigy<0 DO bigy := bigy+windowy END;
      WHILE bigy>=windowy DO bigy := bigy-windowy END;
      y := bigy; oldy := newy;
      GET(3, b)
    END MouseState;

  BEGIN oldx := 0; oldy := 0; bigx := 4000; bigy := 4000
  END MouseCoords;

  MODULE Cursor;
    IMPORT xpos, ypos, buttons;
    IMPORT MouseCoords;
    FROM Monitor IMPORT TermProcedure;
    FROM Terminal IMPORT BusyRead, ReadAgain;
    FROM Screen IMPORT
      Bitmap, BlockDescriptor, Mode, Replicate, GetSystemBitmap, GetMaxBlock;

    EXPORT
      TrackCursor, ReleaseCursor,
      GetMouse,
      InstallCursor, ArrowInvert, SimpleMove,
      xMax, yMax, fullbm, curPos;


    CONST
      xOff = 90;
      yOff = 90;

    (* xMax, yMax constant as soon as only one screen version exists*)

    TYPE 
      SquarePattern =
        RECORD
          size: [1..16];
          bits: ARRAY [1..16] OF BITSET;
        END;

    VAR 
      fullbm: Bitmap;
      curPos: BlockDescriptor;
      cursor, altCursor: SquarePattern;
      (*buttons: CARDINAL;(* B1 1 B2 2 B3 4 *)*)
      Invert, Move: PROC;

      xMax: CARDINAL;
      yMax: CARDINAL;

      arrowOn: BOOLEAN;
      arrowx, arrowy: CARDINAL;


    PROCEDURE GetMouse;
    BEGIN
      MouseCoords.MouseState(xpos, ypos, buttons);
      IF xpos<=xOff THEN xpos := 0 
      ELSE xpos := xpos-xOff;
        IF xpos>xMax THEN xpos := xMax END
      END;
      IF ypos<=yOff THEN ypos := 0 
      ELSE ypos := ypos-yOff;
        IF ypos>yMax THEN ypos := yMax END
      END;
    END GetMouse;


    PROCEDURE ResetMouse;
    BEGIN
      MouseCoords.windowx := xMax+2*xOff;
      MouseCoords.windowy := yMax+2*yOff;
      Invert := ArrowInvert;
      Move := SimpleMove;
      arrowOn := FALSE;
    END ResetMouse;


    PROCEDURE InstallCursor(inv, mov: PROC);
    BEGIN
      Invert := inv;
      Move := mov;
    END InstallCursor;

    
    PROCEDURE ArrowInvert;

      PROCEDURE SpecialCase;
        VAR 
          specCursor: SquarePattern;
          i: CARDINAL; 
      BEGIN 
        specCursor.size := 16;
        curPos.y := arrowy;
        IF arrowx<=xMax-15 THEN
          (*bottom but not right*)
          FOR i := 1 TO 16 DO specCursor.bits[i] := cursor.bits[17-i] END;
          curPos.x := arrowx
        ELSE
          (*bottom right corner*)
          FOR i := 1 TO 16 DO specCursor.bits[i] := altCursor.bits[17-i] END;
          curPos.x := arrowx-15
        END;
        Replicate(fullbm, curPos, invert, specCursor);
      END SpecialCase;
 
    BEGIN (*ArrowInvert*)
      IF arrowOn THEN arrowOn := FALSE
      ELSE arrowOn := TRUE;
        arrowx := xpos; arrowy := ypos 
      END;
      IF (arrowx<=xMax-15) AND (arrowy>=15) THEN
        curPos.x := arrowx; curPos.y := arrowy-15;
        Replicate(fullbm, curPos, invert, cursor);
      ELSIF arrowy>=15 THEN
        curPos.x := arrowx-15; curPos.y := arrowy-15;
        Replicate(fullbm, curPos, invert, altCursor);
      ELSE SpecialCase
      END;
    END ArrowInvert;


    PROCEDURE SimpleMove;
      VAR xx, yy: CARDINAL;
    BEGIN xx := xpos; yy := ypos;
      GetMouse;
      IF (xpos<>xx) OR (ypos<>yy) THEN
        Invert; Invert;
      END;
    END SimpleMove;


    PROCEDURE TrackCursor(): CARDINAL;
      VAR 
        ch: CHAR; 
        i, but: CARDINAL;
    BEGIN but := 0;
      BusyRead(ch);
      IF ch<>0C THEN ReadAgain; 
      ELSE
        GetMouse;  
        IF buttons<>0 THEN but := buttons
        ELSE
          Invert;
          LOOP
            BusyRead(ch);
            IF ch<>0C THEN ReadAgain; but := 0; EXIT END;
            Move;
            IF buttons<>0 THEN but := buttons; EXIT END;
          END;
          Invert;
        END;
        i := 1;
        IF but<>0 THEN
          LOOP
            IF ODD(but) THEN but := i; EXIT END;
            INC(i); but := but DIV 2
          END;
        END;
      END;  
      Move := SimpleMove;
      Invert := ArrowInvert;
      RETURN but
    END TrackCursor;


    PROCEDURE ReleaseCursor(wait: BOOLEAN; VAR but: BITSET);
      (* {1}: left button; {2}: middle; {3}: right; {0}: keyboard *)
      VAR ch: CHAR; i, oldb: CARDINAL; 
    BEGIN
      but := {}; 
      BusyRead(ch); GetMouse; 
      IF ch<>0C THEN ReadAgain; INCL(but, 0);
      ELSIF wait OR (buttons<>0) THEN 
        Invert;
        oldb := 177777B;
        LOOP
          BusyRead(ch);
          IF ch<>0C THEN 
            ReadAgain; INCL(but, 0);
            EXIT 
          END;
          Move;
          IF buttons<>oldb THEN
            IF buttons=0 THEN 
              IF wait THEN 
                wait := FALSE; but := {}; 
              ELSE EXIT
              END;
            ELSE
              i := 1; oldb := buttons;
              REPEAT 
                IF ODD(oldb) THEN INCL(but, i) END;
                INC(i); oldb := oldb DIV 2
              UNTIL oldb=0;
            END;
            oldb := buttons;
          END
        END;
        Invert;
      END;
      Move := SimpleMove;
      Invert := ArrowInvert;
    END ReleaseCursor;


  BEGIN (*Cursor*)
    WITH cursor DO
      size := 16;
      bits[ 1] := {0..7};
      bits[ 2] := {0..6};
      bits[ 3] := {0..5};
      bits[ 4] := {0..6};
      bits[ 5] := {0..7};
      bits[ 6] := {0..8};
      bits[ 7] := {0..1,3..9};
      bits[ 8] := {0,4..10};
      bits[ 9] := {5..11};
      bits[10] := {6..12};
      bits[11] := {7..13};
      bits[12] := {8..14};
      bits[13] := {9..15};
      bits[14] := {10..14};
      bits[15] := {11..13};
      bits[16] := {12};
    END;
    WITH altCursor DO
      size := 16;
      bits[ 1] := {8..15};
      bits[ 2] := {9..15};
      bits[ 3] := {10..15};
      bits[ 4] := {9..15};
      bits[ 5] := {8..15};
      bits[ 6] := {7..15};
      bits[ 7] := {6..12,14..15};
      bits[ 8] := {5..11,15};
      bits[ 9] := {4..10};
      bits[10] := {3..9};
      bits[11] := {2..8};
      bits[12] := {1..7};
      bits[13] := {0..6};
      bits[14] := {1..5};
      bits[15] := {2..4};
      bits[16] := {3};
    END;
    GetSystemBitmap(fullbm);
    GetMaxBlock(curPos, fullbm);
    WITH curPos DO 
      xMax := w-1; yMax := h-1;
      w := 16; h := 16
    END;
    ResetMouse;
    TermProcedure(ResetMouse)
  END Cursor;


  MODULE Menu;
    IMPORT xpos, ypos;
    IMPORT xMax, yMax, fullbm, curPos;
    IMPORT ReleaseCursor, InstallCursor, SimpleMove;
    FROM Terminal IMPORT WriteString;
    FROM Screen IMPORT
      Bitmap, Font, BlockDescriptor, Mode, GetSystemFont, LoadFont,
      Replicate, BlockTransfer, DisplayChar, CharWidth, CreateBitmap;

    EXPORT MenuSelection;


    CONST
      maxLine = 10;
      lineHeight = 19;
      bmWidth = 96;
      mHeight = maxLine*lineHeight+3;
      bmHeight = mHeight;


    TYPE
      EditorPattern = 
        RECORD 
          Len: CARDINAL;
          Pat: ARRAY[0..15]OF BITSET
        END;
      Pattern =
        RECORD
          a, b: CARDINAL
        END;

   
    VAR
      black, white: Pattern;
      menuCursor: EditorPattern;
      own: Bitmap;
      f: Font;
      done: BOOLEAN;
      lineNum: CARDINAL;
      commandBlock: BlockDescriptor;        (*contains complete menu*)
      saveBlock: BlockDescriptor;           
      commandLine: BlockDescriptor;
      activeCommandBlock: BlockDescriptor;  (*contains commands of menu*)
      menux, menuy: CARDINAL;
      menuOn: BOOLEAN;


    PROCEDURE InsidePoint(b: BlockDescriptor; x, y: CARDINAL): BOOLEAN;
      (* returns point (x,y) is inside of block b *)
    BEGIN
      RETURN (x >= b.x) AND (x-b.x < b.w)  
         AND (y >= b.y) AND (y-b.y < b.h)
    END InsidePoint;


    PROCEDURE MenuInvert;
    BEGIN 
      IF menuOn THEN menuOn := FALSE
      ELSE menuOn := TRUE;
        menux := xpos; menuy := ypos
      END;
      IF menux>(xMax-15) THEN curPos.x := menux-15
      ELSE curPos.x := menux END;
      IF menuy>(yMax-15) THEN curPos.y := yMax-15
      ELSE curPos.y := menuy END;
      IF InsidePoint(activeCommandBlock, curPos.x+8, curPos.y+8) THEN
        commandLine.y := ((curPos.y+8-activeCommandBlock.y) DIV lineHeight) * 
                           lineHeight  +  activeCommandBlock.y;
        Replicate(fullbm, commandLine, invert, black);
      ELSE
        Replicate(fullbm, curPos, invert, menuCursor);
      END;
    END MenuInvert;



    PROCEDURE MenuSelection(s: ARRAY OF CHAR): CARDINAL;
      VAR 
        but: BITSET;
        chosen: CARDINAL;
        highs: CARDINAL;
        wait: BOOLEAN;
        linemax, linesize: CARDINAL;


      PROCEDURE AnalyzeString(VAR s: ARRAY OF CHAR);
        VAR l: CARDINAL;
      BEGIN 
        highs := HIGH(s); 
        wait := (s[0]="*"); 
        l := ORD(wait);
        lineNum := 0;
        linemax := 0;
        REPEAT
          linesize := 0;
          WHILE (l<=highs) AND (s[l]<>0c) AND (s[l]<>"|") DO 
            INC(linesize, CharWidth(f, s[l]));
            INC(l);
          END;
          IF linesize>linemax THEN linemax := linesize END;
          INC(lineNum);
          INC(l); (* skip "|" *) 
        UNTIL (l>highs) OR (s[l-1]=0c) OR (lineNum=maxLine);
        INC(linemax, 8);
        IF linemax>bmWidth THEN linemax := bmWidth END;
        commandBlock.h := lineHeight * lineNum + 3;
        commandBlock.w := linemax; saveBlock.w := linemax;
        commandLine.w := linemax-8;
        saveBlock.h := commandBlock.h
      END AnalyzeString;


      PROCEDURE PaintText(VAR text: ARRAY OF CHAR);
        VAR 
           b: BlockDescriptor; 
          i, l: CARDINAL;
          ch: CHAR;
      BEGIN

        (*frame*)
        b := commandBlock;                         (*clear area*)
        Replicate(fullbm, b, replace, white);     
        b.w := 2;                                  (*left line*)
        Replicate(fullbm, b, replace, black);
        b.x := b.x+commandBlock.w-2;               (*right line*)
        Replicate(fullbm, b, replace, black);

        (*text*)
        b.y := b.y+b.h+1; b.h := lineHeight;
        i := ORD(wait);
        FOR l := 1 TO lineNum DO
          b.x := commandBlock.x+4;                 (*write text of 1 line*)
          b.y := b.y-lineHeight; 
          b.w := commandBlock.w-7;
          LOOP
            ch := text[i];
            IF (ch="|") OR (ch=0C) THEN INC(i); EXIT END;
            IF b.w < CharWidth(f, ch) THEN
              REPEAT INC(i) UNTIL ( (i>=highs) OR (text[i]="|") );
              INC(i);
              EXIT
            END;
            DisplayChar(fullbm, b, f, ch);
            INC(i); 
            IF i>highs THEN EXIT END;
          END;
        END;

        (*invert title*)
        b.x := commandBlock.x+2; b.w := commandBlock.w-4;
        b.y := commandBlock.y+commandBlock.h-lineHeight+1; b.h := lineHeight-1;
        Replicate(fullbm, b, invert, black);

        (*bottom line*)
        b.h := 2; b.y := commandBlock.y;                         
        Replicate(fullbm, b, replace, black); 
      END PaintText;


    BEGIN (*MenuSelection*)
      AnalyzeString(s);

      (*set position of menu*)
      IF ypos>(lineHeight DIV 3)*lineNum THEN
        DEC(ypos, (lineHeight DIV 3)*lineNum)
      ELSE ypos := 0 END;
      IF xpos>commandBlock.w+2 THEN DEC(xpos, commandBlock.w+2) ELSE xpos := 0 END;
      IF xpos<=xMax-commandBlock.w THEN commandBlock.x := xpos
      ELSE commandBlock.x := xMax-commandBlock.w END;
      IF ypos<=yMax-commandBlock.h THEN commandBlock.y := ypos
      ELSE commandBlock.y := yMax-commandBlock.h
      END;

      BlockTransfer(own, saveBlock, replace, fullbm, commandBlock);
      PaintText(s);

      (*set field for inverting texts*)
      activeCommandBlock := commandBlock;
      activeCommandBlock.y := commandBlock.y+4;
      activeCommandBlock.h := lineHeight * (lineNum-1);
      commandLine.x := commandBlock.x+4;
      
      menuOn := FALSE;
      InstallCursor(MenuInvert, SimpleMove);
      ReleaseCursor(wait, but);

      IF xpos>(xMax-15) THEN xpos := xMax-15 END;
      IF ypos>(yMax-15) THEN ypos := yMax-15 END; 

      IF 0 IN but THEN chosen := 0;
      ELSIF InsidePoint(activeCommandBlock, xpos+8, ypos+8) THEN
        chosen := lineNum-(ypos+8-activeCommandBlock.y) DIV lineHeight;
      ELSE  (*title or outside*)
        chosen := 1
      END;

      BlockTransfer(fullbm, commandBlock, replace, own, saveBlock);
      RETURN chosen
    END MenuSelection;


  BEGIN (*Menu*)
    WITH black DO
      a  := 1;
      b  := 177777B
    END;
    WITH white DO
      a  := 1; b  := 0
    END;
    WITH menuCursor DO
      Len := 16;
      Pat[ 0] := {};
      Pat[ 1] := {};
      Pat[ 2] := {};
      Pat[ 3] := {2..12};
      Pat[ 4] := {2..12};
      Pat[ 5] := {2..12};
      Pat[ 6] := {2..12};
      Pat[ 7] := {2..12};
      Pat[ 8] := {2..12};
      Pat[ 9] := {2..12};
      Pat[10] := {2..12};
      Pat[11] := {2..12};
      Pat[12] := {2..12};
      Pat[13] := {2..12};
      Pat[14] := {};
      Pat[15] := {};
    END;
    LoadFont(f, "HELVETICA14B", done);
    IF NOT done THEN GetSystemFont(f) END;
    CreateBitmap(own, bmWidth, bmHeight, done);
    IF NOT done THEN
      WriteString(" - bitmap not created"); HALT
    END;
    commandLine.h := lineHeight-3;
    saveBlock.x := 0; saveBlock.y := 0;
  END Menu;


END CursorStuff.



