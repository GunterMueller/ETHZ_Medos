MODULE SkyllaPrintFile;
(* Program: Companion program to Skylla for generating a print file.
   Date:    11.4.83
   Author:  N.Wirth
            Institut fur Informatik, ETH Zurich
            Switzerland  *)

  FROM Terminal IMPORT Read, Write, WriteString, WriteLn;
  FROM FileSystem IMPORT File, Response, Create, Lookup,
       ReadChar, ReadWord, WriteWord, SetOpen, Rename, Close;
  FROM Profile IMPORT
    OpenProfile, FindKey, GetFileName, GetNumber, GetString, CloseProfile;

  CONST maxF = 7; maxFC = "7";  (*max font*)
      NameLeng = 27; PnoY = 144;
      defaulty = 3; defaultY = 8; defaultFont = 6;
      NofParas = 64; NofLines = 128; NofChars = 13000; NofTabs = 10;
      DEL = 177C; US = 37C; EOL = 36C; EOP = 35C; ESC = 33C;

      nil = 0C; eob = 1C; stl = 2C; fon = 3C;
      hsp = 4C; vsp = 5C; xsp = 6C; ysp = 7C; wsp = 10C;

  TYPE SetMode = (copy, adjust, center);

       ParaDesc = RECORD Y: CARDINAL END ;

       LineDesc = RECORD indent, height: CARDINAL;
                    spacewidth, remspaces: CARDINAL
                  END ;

  VAR ch: CHAR;
      mode: SetMode; altpn: BOOLEAN;
      i, j, i0, i1, nw, nl, np, pno, tem: CARDINAL;
      x, x0, x1, y, space, Yspace, yspace, wspx: CARDINAL;
      curInd, curHeight, curFont, curTab, tabOrg, copies: CARDINAL;
      TopMargin, Bottom: CARDINAL;
      LeftMargin, RightMargin: CARDINAL;
      PageNumber, PageCount: CARDINAL;

      para: ARRAY [0..NofParas-1] OF ParaDesc;
      line: ARRAY [0..NofLines-1] OF LineDesc;
      text: ARRAY [0..NofChars-1] OF CHAR;
      wspace: ARRAY [0..3] OF CARDINAL;
      FontHeight, BaseHeight: ARRAY [0..maxF] OF CARDINAL;
      CharWidth: ARRAY [0..maxF],[0C..237C] OF CARDINAL;
      tab:  ARRAY [0..NofTabs-1] OF CARDINAL;

      open: BOOLEAN;
      in, fnt, out: File;
      name: ARRAY [0..NameLeng] OF CHAR;
      key:  ARRAY [0..3] OF CHAR;

  PROCEDURE ReadFileName(ext: ARRAY OF CHAR);
    VAR i,j: CARDINAL;
  BEGIN i := 3; j := 0;
    REPEAT Read(ch);
      IF ch = DEL THEN
        IF i > 3 THEN Write(DEL); i := i-1 END
      ELSIF (ch >= ".") & (i < NameLeng) THEN
        IF i < NameLeng THEN Write(ch); name[i] := ch; i := i+1 END
      END
    UNTIL ch <= " ";
    IF (3 < i) & (i < NameLeng) & (name[i-1] = ".") THEN
      REPEAT ch := ext[j]; j := j+1;
        Write(ch); name[i] := ch; i := i+1
      UNTIL (j > HIGH(ext)) OR (i = NameLeng)
    END ;
    name[i] := 0C
  END ReadFileName;

  PROCEDURE ReadNumber(VAR n: CARDINAL);
    VAR i,j: CARDINAL;
        dig: ARRAY [0..7] OF CHAR;
  BEGIN i := 0; j := 0; n := 0;
    REPEAT Read(ch);
      IF ("0" <= ch) & (ch <= "9") THEN
        dig[i] := ch; i := i+1; Write(ch)
      ELSIF (ch = DEL) & (i > 0) THEN
        i := i-1; Write(DEL)
      END
    UNTIL ch <= "-";
    WHILE j < i DO
      n := 10*n + CARDINAL(dig[j]) - 60B; j := j+1
    END
  END ReadNumber;

  PROCEDURE WriteNumber(n: CARDINAL);
    VAR i: CARDINAL; d: ARRAY [0..3] OF CARDINAL;
  BEGIN i := 0;
    REPEAT d[i] := n MOD 10; n := n DIV 10; i := i+1
    UNTIL n = 0;
    REPEAT i := i-1; Write(CHAR(d[i]+60B))
    UNTIL i = 0
  END WriteNumber;

  PROCEDURE OutPage;
    VAR i, i0, j, k, r, rsp, spw, dx, x, y, buf, curfnt: CARDINAL;
        ch: CHAR; loaded : BOOLEAN;
  BEGIN i := 0; j := 0; k := 0; x := 0; y := 0;
    LOOP ch := text[i];
      IF ch >= " " THEN i0 := i;
        REPEAT i := i+1; ch := text[i]
        UNTIL (ch < " ") & ((ch # hsp) OR (spw >= 76B));
        WriteWord(out, 400B + curfnt);  (*text block*)
        WriteWord(out, x); WriteWord(out, y);
        buf := i-i0; loaded := TRUE;
        WHILE i0 < i DO
          ch := text[i0]; i0 := i0+1;
          IF ch = hsp THEN
            IF r >= rsp THEN dx := spw
              ELSE dx := spw+1; r := r+1
            END ;
            ch := CHAR(300B + dx); x := x + dx
          ELSE
            x := CharWidth[curfnt, ch] + x
          END ;
          IF loaded THEN
            WriteWord(out, buf*400B + CARDINAL(ch))
          ELSE
            buf := CARDINAL(ch)
          END ;
          loaded := NOT loaded
        END ;
        IF loaded THEN WriteWord(out, buf*400B) END
      ELSE
        CASE ch OF
        nil: |
        eob: EXIT |
        stl: WITH line[j] DO
               spw := spacewidth; rsp := remspaces;
               x := indent; y := y + height
             END ;
             r := 0; j := j+1 |
        fon: i := i+1; curfnt := CARDINAL(text[i]) |
        hsp: IF r >= rsp THEN x := x + spw
               ELSE x := x + spw + 1; r := r+1
             END |
        vsp, wsp: y := y + para[k].Y; k := k+1 |
        xsp: i := i+2; x := CARDINAL(text[i-1])*400B + CARDINAL(text[i]) |
        ysp: i := i+1; y := y + CARDINAL(text[i])
        END ;
        i := i+1
      END
    END ;
    WriteWord(out, 2000B + copies);  (*page block*)
    WriteWord(out, PageNumber); WriteWord(out, 0);
    PageNumber := PageNumber + 1; PageCount := PageCount + copies
  END OutPage;

  PROCEDURE InitPage;
    VAR j,w,h: CARDINAL;
        d: ARRAY [0..7] OF CHAR;
  BEGIN i := 0; np := 0; nl := 0; y := TopMargin; h := y;
    IF (pno > 0) & (y > PnoY) THEN  (*generate page number*)
      j := 0; w := pno;
      text[i] := fon; text[i+1] := 0C; text[i+2] := stl; i := i+3;
      REPEAT d[j] := CHAR(w MOD 10 + 60B); w := w DIV 10; j := j+1
      UNTIL w = 0;
      REPEAT j := j-1; text[i] := d[j]; i := i+1;
        w := w + CharWidth[0, d[j]]
      UNTIL j = 0;
      WITH line[0] DO
        IF NOT altpn OR ODD(pno) THEN
          indent := RightMargin - w
        ELSE indent := LeftMargin
        END ;
        height := PnoY; spacewidth := 0; remspaces := 0
      END ;
      pno := pno+1; nl := 1; h := TopMargin - PnoY
    END ;
    text[i] := ysp; text[i+1] := CHAR(h);
    text[i+2] := fon; text[i+3] := CHAR(curFont); i := i+4
  END InitPage;

  PROCEDURE AdjustPage;
    VAR h,k,q,r: CARDINAL;
  BEGIN text[i] := eob;
    IF np > 0 THEN
      q := (Bottom - y) DIV np;
      r := (Bottom - y) MOD np;
      FOR k := 0 TO np-1 DO
        h := para[k].Y + q;
        IF k < r THEN para[k].Y := h+1
                 ELSE para[k].Y := h
        END
      END
    END ;
    OutPage; InitPage
  END AdjustPage;

  PROCEDURE AdjustLine;
    VAR j, q, r: CARDINAL; ch: CHAR;
  BEGIN
    IF nw > 1 THEN
      q := (RightMargin - x0) DIV (nw-1) + space;
      r := (RightMargin - x0) MOD (nw-1)
    ELSE nw := 1; q := space; r := 0
    END ;
    WITH line[nl] DO
      indent := curInd; height := curHeight;
      spacewidth := q; remspaces := r
    END ;
    nl := nl+1; x := curInd + x - x1;
    nw := 0; j := i0+1;
    WHILE (j < i) & (text[j] = " ") DO
      text[j] := nil; x := x - CharWidth[curFont," "]; j := j+1
    END ;
    IF y + curHeight > Bottom THEN
      ch := text[i0]; j := i; i := i0; AdjustPage;
      text[i0] := ch; text[i] := stl; i := i+1;
      WHILE i1 < j DO
        text[i] := text[i1]; i := i+1; i1 := i1+1
      END
    ELSE text[i0] := stl
    END ;
    y := y + curHeight
  END AdjustLine;

  PROCEDURE ReadNum(VAR num: CARDINAL);
  BEGIN num := 0;
    REPEAT ReadChar(in,ch) UNTIL ch # " ";
    WHILE ("0" <= ch) & (ch <= "9") DO
      num := 10*num + CARDINAL(ch) - 60B; ReadChar(in,ch)
    END ;
    num := num*3
  END ReadNum;

  PROCEDURE ReadTabs;
    VAR k, t: CARDINAL;
  BEGIN k := 0;
    REPEAT ReadNum(t); t := t + tabOrg;
      IF t > RightMargin THEN t := RightMargin END ;
      tab[k] := t; k := k+1
    UNTIL (ch = ".") OR (k = NofTabs)
  END ReadTabs;

  PROCEDURE SetParams(m: SetMode; font, dY, dy: CARDINAL);
  BEGIN ReadChar(in,ch);
    mode := m; Yspace := 3*dY; yspace := 3*dy;
    curHeight := FontHeight[font] + 3*dy; curInd := LeftMargin;
    IF font # curFont THEN
      curFont := font; text[i] := fon; text[i+1] := CHAR(font); i := i+2
    END
  END SetParams;

  PROCEDURE CheckPageEnd;
  BEGIN
    IF y + 3*curHeight > Bottom THEN
      text[i] := eob; OutPage; InitPage
    END ;
  END CheckPageEnd;

  PROCEDURE FormatLine;
  BEGIN
    WHILE ch # EOL DO
      IF ch = "a" THEN mode := adjust; ReadChar(in,ch)
      ELSIF ch = "n" THEN mode := copy; ReadChar(in,ch)
      ELSIF ch = "c" THEN mode := center; ReadChar(in,ch)
      ELSIF ch = "+" THEN
        SetParams(adjust, 0, defaultY, defaulty)
      ELSIF ch = "-" THEN
        SetParams(copy, 6, defaultY, defaulty)
      ELSIF ch = "=" THEN
        SetParams(copy, 7, defaultY, defaulty)
      ELSIF ch = "/" THEN
        SetParams(copy, 0, defaultY, defaulty)
      ELSIF ch = "A" THEN
        SetParams(copy, 5, 24, 5); CheckPageEnd
      ELSIF ch = "B" THEN
        SetParams(copy, 4, 18, 4); CheckPageEnd
      ELSIF ch = "C" THEN
        SetParams(copy, 2, 12, defaulty); CheckPageEnd
      ELSIF ch = "<" THEN
        SetParams(adjust, 3, 4, 2)
      ELSIF ch = "T" THEN
        SetParams(center, 7, 10, defaulty)
      ELSIF ch = ":" THEN
        SetParams(center, 0, defaultY, defaulty)
      ELSIF ch = "x" THEN
        ReadNum(curInd); curInd := curInd + LeftMargin
      ELSIF ch = "y" THEN
        ReadNum(yspace);
        curHeight := FontHeight[curFont] + yspace
      ELSIF ch = "Y" THEN
        ReadNum(Yspace)
      ELSIF ch = "w" THEN
        ReadNum(wspace[wspx]); wspx := wspx + 1
      ELSIF ch = "f" THEN
        ReadChar(in,ch);
        IF ("0" <= ch) & (ch <= maxFC) THEN
          curFont := CARDINAL(ch) - 60B; ReadChar(in,ch);
          curHeight := FontHeight[curFont] + yspace;
          text[i] := fon; text[i+1] := CHAR(curFont); i := i+2
        END
      ELSIF ch = "t" THEN
        ReadTabs; mode := copy
      ELSIF ch = "p" THEN
        ReadChar(in,ch);
        IF y > TopMargin THEN
          text[i] := eob; OutPage; InitPage
        END
      ELSIF ch = "i" THEN pno := pno+1; ReadChar(in,ch)
      ELSE ReadChar(in,ch)
      END
    END ;
    space := CharWidth[curFont, " "]; ReadChar(in,ch)
  END FormatLine;

  PROCEDURE ProcessFile;
    VAR h: CARDINAL;
  BEGIN PageNumber := 0; 
    FOR i := 0 TO NofTabs-1 DO tab[i] := 60*i END ;
    i := 0; wspx := 0;
    SetParams(copy, defaultFont, defaultY, defaulty);
    space := CharWidth[0, " "];
    InitPage;
    REPEAT  (*next paragraph*)
      WHILE ch = EOP DO
        ReadChar(in,ch); FormatLine
      END ;
      WHILE (wspx > 0) & (wspace[0] + y <= Bottom) DO
        text[i] := wsp; i := i+1; y := y + wspace[0];
        para[np].Y := wspace[0]; np := np+1; h := 0;
        wspx := wspx - 1;
        WHILE h < wspx DO
          wspace[h] := wspace[h+1]; h := h+1
        END
      END ;
      IF y > TopMargin THEN (*Y space*)
        IF y + Yspace <= Bottom THEN
          text[i] := vsp; i := i+1; y := y + Yspace;
          para[np].Y := Yspace; np := np+1
        ELSE AdjustPage
        END ;
        IF np = NofParas THEN
          WriteString(" too many paragraphs"); HALT
        END
      END ;
      IF mode # adjust THEN
        LOOP (*next line*)
          IF ch > EOP THEN
            IF y + curHeight > Bottom THEN AdjustPage END ;
            x := curInd; y := y + curHeight; curTab := 0;
            text[i] := stl; i := i+1;
            LOOP (*chars*)
              IF ch >= " " THEN
                IF ch < 240C THEN
                  x := CharWidth[curFont,ch] + x;
                  IF x <= RightMargin THEN
                    text[i] := ch; i := i+1
                  END
                END
              ELSIF ch = US THEN ReadChar(in,ch);
                IF ("0" <= ch) & (ch <= maxFC) THEN
                  IF curHeight >= FontHeight[CARDINAL(ch)-60B] THEN
                    curFont := CARDINAL(ch)-60B;
                    text[i] := fon; text[i+1] := CHAR(curFont); i := i+2
                  END
                ELSIF ch = " " THEN (*tab*)
                  x := tab[curTab]; curTab := curTab + 1;
                  text[i] := xsp; text[i+1] := CHAR(x DIV 400B);
                  text[i+2] := CHAR(x MOD 400B); i := i+3
                END
              ELSIF ch = EOL THEN ReadChar(in,ch); EXIT
              ELSIF (ch = EOP) OR in.eof THEN EXIT
              END ;
              ReadChar(in,ch)
            END ;
            WITH line[nl] DO
              IF (mode = center) & (x <= RightMargin) THEN
                indent := (RightMargin-x) DIV 2 + curInd
              ELSE indent := curInd
              END ;
              height := curHeight; spacewidth := 0; remspaces := 0
            END ;
            nl := nl+1
          ELSIF (ch = EOP) OR in.eof THEN EXIT
          END
        END
      ELSIF mode = adjust THEN
        IF y + curHeight > Bottom THEN AdjustPage END ;
        x := curInd; x0 := x; text[i] := stl; i := i+1;
        y := y + curHeight; nw := 0;
        LOOP (*next word*)
          i1 := i; x1 := x;
          LOOP (*leading chars*)
            IF ch > " " THEN EXIT
            ELSIF ch = " " THEN
              IF x + CharWidth[curFont," "] > RightMargin THEN
                i := i1; x := x1; AdjustLine; x1 := x; i1 := i
              ELSE
                text[i] := " "; i := i+1; x := CharWidth[curFont," "] + x
              END ;
              ReadChar(in,ch)
            ELSIF ch = EOL THEN i := i1; x := x1; ReadChar(in,ch);
              IF ch = EOL THEN EXIT END
            ELSIF ch = US  THEN ReadChar(in,ch);
              IF ("0" <= ch) & (ch <= maxFC) THEN
                IF curHeight >= FontHeight[CARDINAL(ch)-60B] THEN
                  curFont := CARDINAL(ch)-60B;
                  text[i] := fon; text[i+1] := CHAR(curFont);
                  i := i+2; i1 := i; x1 := x
                END 
              END ;
              ReadChar(in,ch)
            ELSIF (ch = EOP) OR in.eof THEN
              i := i1; x := x1; EXIT
            END
          END ;
          IF ch < " " THEN EXIT END ;
          LOOP (*word chars*)
            IF ch > " " THEN
              IF ch < 240C THEN
                IF x + CharWidth[curFont,ch] > RightMargin THEN AdjustLine END ;
                text[i] := ch; i := i+1; x := CharWidth[curFont,ch] + x
              END
            ELSIF ch = US  THEN ReadChar(in,ch);
              IF ("0" <= ch) & (ch <= maxFC) THEN
                IF curHeight >= FontHeight[CARDINAL(ch)-60B] THEN
                  curFont := CARDINAL(ch)-60B;
                  text[i] := fon; text[i+1] := CHAR(curFont); i := i+2
                END 
              END
            ELSIF (ch >= EOP) OR in.eof THEN EXIT
            END ;
            ReadChar(in,ch)
          END ;
          IF ch = " " THEN ReadChar(in,ch)
          ELSIF ch = EOL THEN
            ReadChar(in,ch);
            IF ch = EOL THEN  (*double EOL*)
              ReadChar(in,ch); EXIT
            ELSIF ch = EOP THEN EXIT
            END
          ELSIF (ch = EOP) OR in.eof THEN EXIT
          END ;
          nw := nw+1; i0 := i; text[i] := hsp; i := i+1;
          x0 := x; x := x + space
        END (*word loop*) ;
        WITH line[nl] DO
          indent := curInd;
          height := curHeight; spacewidth := space; remspaces := 0
        END ;
        nl := nl+1
      END (*paragraph*)
    UNTIL in.eof;
    text[i] := eob; OutPage
  END ProcessFile;

BEGIN WriteString(" SkyllaPrintFile 4.3   Profile? (-/a) ");
  REPEAT Read(ch) UNTIL (ch <= " ") OR (ch = "a");
  IF ch = "a" THEN Write("a"); OpenProfile('"Skylla1"')
              ELSE OpenProfile('"Skylla"')
  END ;
  WriteLn; name := "DK.";
  WriteString("out> "); ReadFileName("PRT"); Lookup(out, name, TRUE);
  IF out.res = done THEN
    WriteLn; WriteWord(out, 162703B); (*header*)
    open := TRUE; i := 0; key := "'F*'";
    REPEAT key[2] := CHAR(i+60B); FindKey(key);
      GetFileName(name, "WID"); Lookup(fnt, name, FALSE);
      IF fnt.res = done THEN
        WriteWord(out, 1400B + i); (*font block*)
        j := 3;
        REPEAT tem := CARDINAL(name[j])*400B; j := j+1;
          IF name[j] >= "0" THEN
            WriteWord(out, tem + CARDINAL(name[j])); j := j+1; tem := 0
          END
        UNTIL name[j] < "0";
        WriteWord(out, tem);
        ReadWord(fnt, FontHeight[i]); ReadWord(fnt, BaseHeight[i]);
        FOR ch := 0C TO 237C DO ReadWord(fnt, CharWidth[i,ch]) END ;
        Close(fnt); i := i+1
      ELSE
        WriteLn; WriteString(name); WriteString(" missing"); open := FALSE
      END
    UNTIL (i > maxF) OR NOT open;
    FindKey("'Size'"); GetNumber(TopMargin); GetNumber(Bottom);
    GetNumber(LeftMargin); GetNumber(RightMargin);
    FindKey("'TabOrg'"); GetNumber(tabOrg);
    IF tabOrg # 0 THEN tabOrg := LeftMargin END ;
    CloseProfile; PageCount := 0;
    LOOP WriteString("in> "); ReadFileName("TEXT");
      IF ch = 33C THEN Write("|"); EXIT END ;
      Lookup(in, name, FALSE);
      IF in.res = done THEN
        WriteString(" pno = "); ReadNumber(i); Write(ch);
        IF ch # "*" THEN
          pno := i; altpn := ch = "-"
        END ;
        WriteString(" copies> ");
        REPEAT Read(ch) UNTIL ("0" <= ch) & (ch <= "9");
        Write(ch); copies := CARDINAL(ch) - 60B;
        IF copies > 0 THEN ProcessFile END ;
        Close(in); WriteLn
      ELSE WriteString(" not found"); WriteLn
      END
    END ;
    Close(out); WriteNumber(PageCount); WriteString(" pages to print")
  ELSE  WriteString(" output not opened")
  END ;
  WriteLn
END SkyllaPrintFile.
