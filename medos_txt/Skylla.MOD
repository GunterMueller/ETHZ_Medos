MODULE Skylla;
(* Program: A lister for formatted text.
            Companion program for printing the text is Zeus.
   Date:    7.12.82
   Author:  N.Wirth
            Institut fur Informatik, ETH Zurich
            Switzerland  *)

  FROM Terminal IMPORT Read, Write, WriteString, WriteLn;
  FROM FileSystem IMPORT
    File, Lookup, Response, ReadWord, ReadChar, Close;
  FROM Charybdis IMPORT
    ParaDesc, LineDesc,
    PageWidth, PageHeight, PrintPage, LoadFont,
    nil, eob, stl, fon, hsp, vsp, xsp, ysp, wsp;
  FROM Profile IMPORT
    OpenProfile, FindKey, GetFileName, GetNumber, CloseProfile;

  CONST maxF = 7; maxFC = "7";  (*max font*)
      NameLeng = 27;
      defaulty = 3; defaultY = 8; defaultFont = 6;
      NofParas = 32; NofLines = 64; NofChars = 8192; NofTabs = 10;
      DEL = 177C; US = 37C; EOL = 36C; EOP = 35C; ESC = 33C;

  TYPE SetMode = (copy, adjust, center);

  VAR ch: CHAR;
      mode: SetMode;
      i, i0, i1, nw, nl, np: CARDINAL;
      x, x0, x1, y, space, Yspace, yspace, wspx: CARDINAL;
      TopMargin, Bottom: CARDINAL;
      LeftMargin, RightMargin: CARDINAL;
      curInd, curHeight, curFont, curTab, tabOrg, tabBase: CARDINAL;

      para: ARRAY [0..NofParas-1] OF ParaDesc;
      line: ARRAY [0..NofLines-1] OF LineDesc;
      text: ARRAY [0..NofChars-1] OF CHAR;
      wspace: ARRAY [0..3] OF CARDINAL;
      FontWidth, FontHeight, BaseHeight: ARRAY [0..maxF] OF CARDINAL;
      CharWidth: ARRAY [0..maxF],[0C..237C] OF CARDINAL;
      tab:  ARRAY [0..NofTabs-1] OF CARDINAL;

      in, fnt: File;
      name: ARRAY [0..NameLeng] OF CHAR;
      key:  ARRAY [0..3] OF CHAR;
      loaded: BOOLEAN;

  PROCEDURE ReadFileName(ext: ARRAY OF CHAR);
    VAR i,j: CARDINAL;
  BEGIN i := 3; j := 0;
    REPEAT Read(ch);
      IF ch = DEL THEN
        IF i > 3 THEN Write(DEL); i := i-1 END
      ELSIF ch > " " THEN
        IF i < NameLeng THEN Write(ch); name[i] := ch; i := i+1 END
      END
    UNTIL ch <= " ";
    IF (i > 3) & (name[i-1] = ".") & (i < NameLeng) THEN
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
    UNTIL ch <= " ";
    WHILE j < i DO
      n := 10*n + CARDINAL(dig[j]) - 60B; j := j+1
    END
  END ReadNumber;

  PROCEDURE InitPage;
    VAR h: CARDINAL;
  BEGIN y := TopMargin; np := 0; nl := 0;
    text[0] := ysp; text[1] := CHAR(TopMargin);
    text[2] := fon; text[3] := CHAR(curFont); i := 4
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
    PrintPage(text, para, line); InitPage
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
      indent := curInd;
      height := curHeight;
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
    END
  END ReadNum;

  PROCEDURE ReadTabs;
    VAR k, t: CARDINAL;
  BEGIN k := 0;
    REPEAT ReadNum(t); t := t *6 DIV 5 + tabOrg;
      IF t < tabBase THEN t := 0 ELSE t := t - tabBase END ;
      IF t > RightMargin THEN t := RightMargin END ;
      tab[k] := t; k := k+1
    UNTIL (ch = ".") OR (k = NofTabs)
  END ReadTabs;

  PROCEDURE SetParams(m: SetMode; font, dY, dy: CARDINAL);
  BEGIN ReadChar(in,ch);
    mode := m; Yspace := dY; yspace := dy;
    curHeight := FontHeight[font] + dy; curInd := LeftMargin;
    IF font # curFont THEN
      curFont := font; text[i] := fon; text[i+1] := CHAR(font); i := i+2
    END
  END SetParams;

  PROCEDURE CheckPageEnd;
  BEGIN
    IF y + 3*curHeight > Bottom THEN
      text[i] := eob; PrintPage(text, para, line); InitPage
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
        ReadNum(curInd); curInd := (curInd *6 DIV 5) + LeftMargin
      ELSIF ch = "y" THEN
        ReadNum(yspace); 
        curHeight := FontHeight[curFont] + yspace
      ELSIF ch = "Y" THEN
        ReadNum(Yspace)
      ELSIF ch = "w" THEN
        ReadNum(wspace[wspx]);
        IF wspace[wspx] > 200 THEN wspace[wspx] := 200 END ;
        wspx := wspx + 1;
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
          text[i] := eob; PrintPage(text, para, line); InitPage
        END
      ELSE ReadChar(in,ch)
      END
    END ;
    space := CharWidth[curFont, " "]; ReadChar(in,ch)
  END FormatLine;

  PROCEDURE ProcessFile;
    VAR h: CARDINAL;
  BEGIN
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
              height := curHeight;
              spacewidth := 0; remspaces := 0
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
          height := curHeight;
          spacewidth := space; remspaces := 0
        END ;
        nl := nl+1
      END (*paragraph*)
    UNTIL in.eof;
    text[i] := eob; PrintPage(text, para, line)
  END ProcessFile;

BEGIN name[0] := "D"; name[1] := "K"; name[2] := ".";
  WriteString(" Skylla 4.6  Profile? (-/a) ");
  REPEAT Read(ch) UNTIL (ch <= " ") OR (ch = "a");
  IF ch = "a" THEN Write("a"); OpenProfile('"Skylla1"')
              ELSE OpenProfile('"Skylla"')
  END ;
  i := 0; key := "'F*'";
  REPEAT key[2] := CHAR(i+60B); FindKey(key);
    GetFileName(name, "SCF"); Lookup(fnt, name, FALSE);
    IF fnt.res # done THEN
      WriteString(name); WriteString(" missing"); loaded := FALSE
    ELSE
      LoadFont(i, fnt, FontWidth[i], FontHeight[i],
               BaseHeight[i], CharWidth[i], loaded);
      Close(fnt); i := i+1
    END
  UNTIL (i > maxF) OR NOT loaded;
  TopMargin := 0; Bottom := PageHeight;
  FindKey("'Width'"); GetNumber(x0);
  IF x0 <= PageWidth THEN
    LeftMargin := (PageWidth - x0) DIV 2
  ELSE LeftMargin := 0
  END ;
  RightMargin := PageWidth - LeftMargin;
  FindKey("'TabOrg'"); GetNumber(tabOrg);
  IF tabOrg # 0 THEN
    tabOrg := LeftMargin; tabBase := 0
  ELSE tabBase := (768-x0) DIV 2 - LeftMargin
  END ;
  CloseProfile; WriteLn;
  IF loaded THEN
    LOOP WriteString("in> "); ReadFileName("TEXT");
      IF ch = 33C THEN EXIT END ;
      Lookup(in, name, FALSE);
      IF in.res = done THEN
        ProcessFile; Close(in); Write(14C)
      ELSE WriteString(" not found"); WriteLn
      END
    END
  END ;
  WriteLn
END Skylla.
