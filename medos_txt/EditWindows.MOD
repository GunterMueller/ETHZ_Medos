IMPLEMENTATION MODULE EditWindows; (* vs I.11      NW 22.1.80, WW 24.6.82
                      ===========  *)

  FROM Storage IMPORT
    DEALLOCATE;
  FROM EditHeap IMPORT
    ALLOCATE;
  FROM EditDisplay IMPORT
    lines, columns, Mline, Mcol, McolSel,
    Options, optionSet, ClearMark, SetMark, SetCaret, ClearCaret,
    Invert, InvertCursor, NewWindowBar, MoveWindowBar, DeleteWindowBar,
    ClearLines, CopyL, PreviousChar, empty, PaintLine, PaintCH,
    ShowFileName;
  FROM EditFiles IMPORT
    FileNo, GetName, OpenOutputFile, CloseOutputFile;
  FROM EditDocuments IMPORT
    maxDocNo, DocNo, CharNo, createDoc, inputDoc, outputDoc, thisChar,
    nextChar, prevChar, currentIndex, length, insertChar, delChar,
    delete, insertBuffer, selectBuffer, readBuffer, InitEditDocuments;

  CONST
    EOF   = 34c;
    EOL   = 36c;
    maxLine = 75;

  TYPE
    WindowPtr      = POINTER TO WindowHandle;
    WindowHandle   = RECORD
                       doc: DocNo;
                       firstLine, lastLine: CARDINAL;
                       bar: CARDINAL;
                       next: WindowPtr
                     END ;

    DocumentHandle = RECORD
                       firstWindow: WindowPtr;
                       fno: FileNo;
                     END ;
 
    Position       = RECORD  (*marker position*)
                       l, x: CARDINAL;  (*line- and char number*)
                       d: DocNo; n: CharNo;
                       ch: CHAR
                     END ;

  VAR
    doc        : ARRAY DocNo OF DocumentHandle;
    cur,
    sel1, sel2 : Position;
    win        : ARRAY [0..maxLine] OF WindowPtr;
    chn        : ARRAY [0..maxLine] OF CharNo;
    leng       : ARRAY [0..maxLine] OF CARDINAL;


  PROCEDURE Locate (L,C: CARDINAL; VAR P: Position);
    VAR (*  ------                               *)
      x0: CARDINAL;
  BEGIN
    WITH P DO
      l := L; x:= C;
      ch := PreviousChar(l,x);
      d := win[l]^.doc; 
      n := chn[l]+x;
    END;
  END Locate;

  PROCEDURE ClearSection (L0,L1: CARDINAL);
    VAR (*  ------------                *)
      L: CARDINAL;
  BEGIN
    InvertCursor;
    ClearLines(L0,L1);
    FOR L := L0 TO L1 DO chn[L] := 0; leng[L0] := 0; END;
    InvertCursor;
  END ClearSection;

  PROCEDURE CopyLine (from, to: CARDINAL);  (*ev inline in Scroll*)
  BEGIN (*  --------                   *)
    InvertCursor;
    CopyL(from,to);
    chn[to] := chn[from];
    leng[to] := leng[from];
    InvertCursor;
  END CopyLine;

  (*$T- the following procedures refer to
    thisChar, nextChar, prevChar *)

  PROCEDURE Paint (L0: CARDINAL);
    VAR (*  -----             *)
      L1,x0,l : CARDINAL;
      ch      : CHAR;
      n       : CharNo;
  BEGIN
    InvertCursor;
    L1 := win[L0]^.lastLine;
    n := chn[L0];
    ch := thisChar(win[L0]^.doc, n);
    REPEAT
      x0 := L0*columns;
      chn[L0] := n;

      PaintLine(L0);
      l := 0;
      LOOP
        INC(l);
        PaintCH(ch,x0);
        IF ch # EOF THEN
          ch := nextChar();
          IF x0 = 0 THEN (* cleared by PaintCH to indicate EOL or "line full" *)
            leng[L0] := l;
            INC(L0);
            EXIT;
          END;
        ELSE
          leng[L0] := l;
          WHILE (L0 < L1) DO
            INC(L0); chn[L0] := 0; leng[L0] := 0;
            IF NOT empty(L0) THEN ClearLines(L0,L0); END;
          END;
          InvertCursor;
          RETURN;
        END;
      END; (* LOOP *)
      n := currentIndex;
    UNTIL (L0 > L1)  OR (chn[L0] = n);
    InvertCursor;
  END Paint;
(*$T+*)

  PROCEDURE ScanBack (L: CARDINAL; VAR n: CARDINAL);
    VAR (*  --------                             *)
      nl, nc: CARDINAL; CH: CHAR;
  BEGIN CH := thisChar(win[L]^.doc, chn[L]);
    CH := prevChar(); nl := n;
    WHILE (nl > 0) & (CH # EOF) DO
      DEC(nl); nc := columns;
      REPEAT
        DEC(nc);
        CH := prevChar();
      UNTIL (CH = EOL) OR (nc = 0) OR (CH = EOF);
    END ;
    CH := nextChar(); DEC(n,nl)
  END ScanBack;

  (*----------------------------------------------------------*)

  PROCEDURE PlaceCursor (L,x: CARDINAL);
  BEGIN (*  -----------              *)
    Locate(L,x,cur);
    SetCaret(cur.l,cur.x);
  END PlaceCursor;

  PROCEDURE MoveCaret (L,N: CARDINAL);
  BEGIN (*  ---------              *)
    LOOP
      IF N < chn[L]+leng[L] THEN
        WITH cur DO
          l := L;
          x := N-chn[L];
          ch := PreviousChar(l,x);
          n := N;
          SetCaret(l,x);
        END;
        EXIT;
      ELSIF L = win[L]^.lastLine THEN
        WITH cur DO
          l := L;
          x := leng[L];
          ch := PreviousChar(l,x);
          n := chn[L]+x;
          SetCaret(l,x);
        END;
        EXIT;
      ELSE
        INC(L);
      END;
    END;
  END MoveCaret;

VAR oldLine: CARDINAL;

  PROCEDURE ShowDocName (L: CARDINAL);
    VAR (*  -----------            *)
      name: ARRAY [0..31] OF CHAR;
  BEGIN
    GetName(doc[win[L]^.doc].fno,name);
    ShowFileName(name);
  END ShowDocName;
    

  PROCEDURE TraceCursor;
  BEGIN (*  -----------  *)
    ClearCaret;
    PlaceCursor(Mline,Mcol);
    IF oldLine # cur.l THEN
      oldLine := cur.l;
      ShowDocName(oldLine);
    END;
  END TraceCursor;

  MODULE WindowBar; (*
         =========   *)

    IMPORT ALLOCATE, DEALLOCATE, empty, lines,
      windowCount, windowOK, WindowPtr, win, chn, Mline, Deselect, ClearSection,
      DeleteWindowBar, NewWindowBar, MoveWindowBar, ScanBack,
      createDoc, inputDoc, maxDocNo, DocNo, doc, CharNo, Paint, PlaceCursor,
      ShowDocName, FileNo, currentIndex;

    EXPORT SetBar, RemoveBar, LastLine, MoveBar, LetBar,
      OpenWindow, ClearDocument, RemoveDocument, OpenDocument, InitWindowBar;

    VAR
      L0,L1,L1old,L2: CARDINAL;
      w0,w1: WindowPtr; d: DocNo;

    PROCEDURE SetBar (barType: CARDINAL);
    BEGIN (*  ------                  *)
      L1 := Mline;
      w0 := win[L1];
      L0 := w0^.firstLine;
      L2 := w0^.lastLine;
      NEW(w1);
      w1^.bar := NewWindowBar(L1,barType);
    END SetBar;

    PROCEDURE RemoveBar;
    BEGIN (*  ---------  *)
      DeleteWindowBar(w1^.bar);
      DISPOSE(w1);
    END RemoveBar;

    PROCEDURE OpenWindow;
      VAR (*  ----------  *)
        L: CARDINAL;
    BEGIN
      Deselect;
      INC(windowCount);
      WITH w1^ DO
        doc := w0^.doc; firstLine := L1+1; lastLine := L2;
        next := w0^.next
      END ;
      w0^.next := w1; w0^.lastLine := L1; INC(L1);
      FOR L := L1 TO L2 DO win[L] := w1 END ;
      IF empty(L1) THEN
        chn[L1] := chn[L0]; Paint(L1)
      END ;
      PlaceCursor(L1,0);
    END OpenWindow;

    PROCEDURE ClearDocument;
      VAR (*  -------------  *)
        w2,w3: WindowPtr;
        status: BOOLEAN;
    BEGIN
      d := 0;
      status := TRUE; (* there is a free document *)
      IF w0 = NIL THEN  (* the 1st document *)
        L1 := 0;
        L2 := lines-1;
      ELSE
        Deselect;
        WITH w0^ DO
          lastLine := L1; w2 := next; next := NIL;
        END;
        WHILE w2 # NIL DO
          DeleteWindowBar(w2^.bar); L2 := w2^.lastLine;
          DEC(windowCount);
          w3 := w2; w2 := w3^.next; DISPOSE(w3);
        END ;
        INC(L1);
        LOOP
          IF d = maxDocNo THEN status := FALSE; EXIT; END;
          IF doc[d].firstWindow = NIL THEN EXIT; END;
          INC(d);
        END;
      END;
      ClearSection(L1,L2);
(*    RETURN status; => to be interpreted by Edit.MOD *)
    END ClearDocument;

    PROCEDURE RemoveDocument;
      VAR (*  --------------  *)
        L: CARDINAL;
    BEGIN
      IF w0 = NIL THEN
        OpenDocument(0,0);
      ELSE
        DeleteWindowBar(w1^.bar);
        w0^.lastLine := L2;
        DEC(L1);
        L := L1;
        REPEAT
          INC(L);
          win[L] := w0;
          chn[L] := 0;
        UNTIL L = L2;
        IF empty(L1) THEN ClearSection(L1,L2) ELSE Paint(L1) END ;
        PlaceCursor(L1,0);
        ShowDocName(L1);
      END;
    END RemoveDocument;
      

    PROCEDURE OpenDocument (f: FileNo; fl: CARDINAL);
      VAR (*  ------------                        *)
        L: CARDINAL;
    BEGIN
      INC(windowCount);
      WITH w1^ DO
        doc := d; firstLine := L1; lastLine := L2;
        next := NIL
      END ;
      FOR L := L1 TO L2 DO win[L] := w1 END ;
      createDoc(d);
      WITH doc[d] DO
        fno := f;
        firstWindow := w1;
        IF (f # 0) AND (fl # 0) THEN inputDoc(d,f,fl); END;
      END;
      Paint(L1); PlaceCursor(L1,0);
    END OpenDocument;

    PROCEDURE LastLine (): BOOLEAN;
      VAR (*  -------- *)
        oldBar: BOOLEAN;
    BEGIN
      w0 := win[Mline];
      L1old := w0^.lastLine;
      oldBar := (Mline = L1old) AND (L1old # lines-1);
      IF oldBar THEN
        w1 := win[Mline+1];
        L0 := w0^.firstLine;
        L1 := w0^.lastLine;
        L2 := w1^.lastLine;
      END;
      RETURN oldBar;
    END LastLine;

    PROCEDURE MoveBar;
    BEGIN (*  -------  *)
      windowOK := (Mline > L0+2) & (Mline < L2-3);
      IF windowOK & NOT empty(Mline+1) THEN
        MoveWindowBar(w1^.bar, Mline);
        L1 := Mline;
      ELSE
        Mline := L1; (* read only !?! *)
      END
    END MoveBar;

    PROCEDURE LetBar;
      VAR (*  ------  *)
        L,n: CARDINAL;
    BEGIN
      Deselect;
      w0^.lastLine := L1; w1^.firstLine := L1+1;
      IF L1 < L1old THEN (*bar up*)
        FOR L := L1+1 TO L1old DO win[L] := w1 END ;
        n := L1old - L1; ScanBack(L1old+1, n);
        chn[L1+1] := currentIndex; Paint(L1+1)
      ELSIF L1 > L1old THEN (*bar down*)
        FOR L := L1old+1 TO L1 DO win[L] := w0 END ;
        IF chn[L1old] # 0
        THEN Paint(L1old);
        ELSE ClearSection(L1old+1,L1);
        END;
      END ;
      PlaceCursor(w1^.firstLine, 0);
      ShowDocName(w1^.firstLine);
    END LetBar;

    PROCEDURE InitWindowBar;
    BEGIN (*  -------------  *)
      w0 := NIL;
      NEW(w1);
      w1^.bar := NewWindowBar(CARDINAL(-1),0);
    END InitWindowBar;

  END WindowBar;


  PROCEDURE GetTypeAndName (VAR type: WindowType; VAR fN: ARRAY OF CHAR);
    VAR (*  -----------                                               *)
      w,w1: WindowPtr;
  BEGIN
    w := win[cur.l]; d := w^.doc; w1 := doc[d].firstWindow;
    IF w1 = w THEN  (*top window of document*)
      GetName(doc[d].fno,fN);
      IF d = 0 THEN type := TopWindow;
      ELSE type := DocWindow;
      END;
    ELSE
      type := SubWindow;
    END;
  END GetTypeAndName;


  PROCEDURE CloseWindow;
    VAR (*  ----------- *)
      w,w0,w1: WindowPtr;
      L,L1,L2: CARDINAL;
  BEGIN Deselect;
    w := win[cur.l]; d := w^.doc; w1 := doc[d].firstWindow;
    IF w1 = w THEN  (*top window of document*)
      IF d # 0 THEN  (*not master document*)
        WHILE w1^.next # NIL DO w1 := w1^.next END ;
        L1 := w^.firstLine -1; L2 := w1^.lastLine;
        w0 := win[L1]; w0^.lastLine := L2; L := L1;
        REPEAT INC(L); win[L] := w0 UNTIL L = L2;
        REPEAT DeleteWindowBar(w^.bar);
          DEC(windowCount);
          w1 := w; w := w^.next; DISPOSE(w1);
        UNTIL w = NIL;
        IF empty(L1) THEN ClearSection(L1,L2) ELSE Paint(L1) END ;
        PlaceCursor(L1,0);
        ShowDocName(L1);
      END
    ELSE (*merge subwindows*)
      WHILE w1^.next # w DO w1 := w1^.next END ;
      w1^.next := w^.next;
      L1 := w^.firstLine -1; L2 := w^.lastLine;
      w0 := win[L1]; w0^.lastLine := L2; L := L1;
      REPEAT INC(L); win[L] := w0 UNTIL L = L2;
      DeleteWindowBar(w^.bar); DISPOSE(w);
      DEC(windowCount);
      IF empty(L1) THEN ClearSection(L1,L2) ELSE Paint(L1) END ;
      PlaceCursor(L1,0)
    END ;
  END CloseWindow;

VAR d: DocNo; (* common variable of CloseWindow and PutDocument/BackupDocument *)

  PROCEDURE AlreadyWritten (fN: ARRAY OF CHAR): BOOLEAN;
    VAR (*  --------------                  *)
      ok: BOOLEAN;
  BEGIN
    OpenOutputFile(fN,TRUE,ok);
    RETURN NOT ok;
  END AlreadyWritten;

  PROCEDURE BackupDocument (VAR ok: BOOLEAN);
  BEGIN (*  --------------                *)
    outputDoc(d);
    CloseOutputFile(doc[d].fno, ok);
    IF ok THEN CloseWindow; END;
  END BackupDocument;

  PROCEDURE FileNameNew (fN: ARRAY OF CHAR): BOOLEAN;
    VAR (*  -----------                  *)
      ok: BOOLEAN;
  BEGIN
    OpenOutputFile(fN,FALSE,ok);
    RETURN ok;
  END FileNameNew;

  PROCEDURE PutDocument (VAR ok: BOOLEAN);
  BEGIN (*  -----------                *)
    outputDoc(d);
    CloseOutputFile(0,ok);
    IF ok THEN CloseWindow; END;
  END PutDocument;

  PROCEDURE ScrollUp;
    VAR (*  --------  *)
      w: WindowPtr;
      n,L0,L1,L2: CARDINAL;
  BEGIN Deselect;
    L1 := Mline; w := win[L1];
    L0 := w^.firstLine; L2 := w^.lastLine; n := L1-L0;
    IF NOT empty(L1) & (n > 0) THEN
      IF win[cur.l] = w THEN
        IF cur.l < L1 THEN cur.l := L0; cur.x := 0
          ELSE DEC(cur.l, n)
        END
      END ;
      REPEAT CopyLine(L1,L0); INC(L0); INC(L1)
      UNTIL L1 > L2;
      DEC(L0);
      IF NOT empty(L0) THEN
        Paint(L0) ELSE ClearSection(L0,L1-1)
      END;
    END;
    PlaceCursor(cur.l, cur.x);
    ShowDocName(cur.l);
  END ScrollUp;

  PROCEDURE ScrollDown;
    VAR (*  ----------  *)
      w: WindowPtr;
      L0,L1,L2,n: CARDINAL;
  BEGIN Deselect;
    L1 := Mline; w := win[L1];
    L0 := w^.firstLine; L2 := w^.lastLine; n := L2-L1;
    IF n > 0 THEN
      ScanBack(L0, n);
      IF n > 0 THEN L1 := L2-n;
        IF win[cur.l] = w THEN
          IF cur.l > L1 THEN cur.l := L2; cur.x := 0
            ELSE INC(cur.l, n)
          END
        END ;
        LOOP CopyLine(L1,L2);
          IF L1 = L0 THEN EXIT END ;
          DEC(L1); DEC(L2)
        END ;
        chn[L0] := currentIndex;
        Paint(L0);
      END
    END;
    PlaceCursor(cur.l, cur.x);
    ShowDocName(cur.l);
  END ScrollDown;

  PROCEDURE Flip;
    VAR (*  ----  *)
      L0,L1: CARDINAL; w: WindowPtr;
      n: CharNo; ch: CHAR;
  BEGIN Deselect;
    w := win[Mline];
    L0 := w^.firstLine; L1 := w^.lastLine;
    n := length(w^.doc) DIV (L1-L0+1);
    n := (n DIV (L1-L0+1) * (Mline-L0)) + (n * (Mline-L0));
    ch := thisChar(w^.doc, n);
    WHILE (ch <> EOF) AND (ch <> EOL) DO ch := prevChar() END ;
    ch := nextChar(); chn[L0] := currentIndex;
    Paint(L0); PlaceCursor(L0, 0);
    ShowDocName(L0);
  END Flip;

(* ----------------------------------------------------------- *)

  MODULE Select; (*
         ======   *)

    IMPORT DocNo, CharNo, Position, EOF, Mline, Mcol, McolSel, lines,
           win, chn, leng, cur, sel1, sel2, Options, optionSet,
           Locate, ClearCaret, SetCaret, Invert, ClearMark, SetMark,
           DeleteSection, SaveSection, InsertSection, Move, selected;

    EXPORT StartSelection, ContinueSelection, StopSelection, Deselect;

    VAR
      d: DocNo;
      n, selNo: CharNo;
      moveSelected, delSelected, copySelected: BOOLEAN;
      lastValidMline, lastValidMcol: CARDINAL;

  PROCEDURE Pat(): CARDINAL;
  BEGIN
    RETURN ORD(delSelected)+2*ORD(copySelected)+3*ORD(moveSelected);
  END Pat;

  PROCEDURE invertSel (fromCh,toCh,pat: CARDINAL);
    VAR l: CARDINAL;
  BEGIN
    l := 0;
    REPEAT
      IF win[l]^.doc # d THEN l := win[l]^.lastLine;
      ELSIF fromCh < chn[l] THEN
        IF toCh < chn[l] THEN l := win[l]^.lastLine;
        ELSIF toCh < chn[l]+leng[l] THEN 
          Invert(l,0,toCh-chn[l],pat);
          l := win[l]^.lastLine;
        ELSE Invert(l,0,leng[l]-1,pat);
        END;
      ELSIF fromCh < chn[l]+leng[l] THEN
        IF toCh < chn[l]+leng[l] THEN
          Invert(l,fromCh-chn[l],toCh-chn[l],pat);
          l := win[l]^.lastLine;
        ELSE Invert(l,fromCh-chn[l],leng[l]-1,pat);
        END;
      END;
      INC(l);
    UNTIL l >= lines;
  END invertSel;

  PROCEDURE ClearSel;
  BEGIN (*  --------  *)
    IF SelInv IN optionSet THEN invertSel(sel1.n,sel2.n,Pat());
    ELSE ClearMark(1); ClearMark(2);
    END;
    selected := FALSE;
    delSelected := FALSE;
    copySelected := FALSE;
    moveSelected := FALSE;
  END ClearSel;
    

  PROCEDURE Deselect;
  BEGIN (*  --------  *)
    ClearCaret;
    IF selected THEN ClearSel; END;
  END Deselect;

  PROCEDURE StartSelection;
    VAR (*  --------------  *)
      col: CARDINAL;
  BEGIN
    IF selected THEN ClearSel; END;
    col := Mcol + ORD(McolSel) - 1;
    lastValidMcol := col;
    lastValidMline := Mline;
    Locate(Mline, col, sel1);
    d := sel1.d; n := sel1.n;
    sel2 := sel1;
    selNo := n;
    IF SelInv IN optionSet THEN invertSel(n,n,0);
    ELSE SetMark(1, sel1.l, sel1.x); SetMark(2, sel2.l, sel2.x);
    END;
  END StartSelection;

  PROCEDURE ContinueSelection (button: CARDINAL);
    VAR (*  -----------------                 *)
      sel: Position;
      col: CARDINAL;
  BEGIN
    IF (KeySel IN optionSet) OR (ButSel IN optionSet) THEN
    CASE button OF
    8: (* delete selection *)
      IF copySelected THEN invertSel(sel1.n,sel2.n,6);
      ELSIF moveSelected THEN invertSel(sel1.n,sel2.n,5);
      ELSE invertSel(sel1.n,sel2.n,4);
      END; 
      delSelected := TRUE;
      copySelected := FALSE;
      moveSelected := FALSE; |
    9: (* copy selection *)
      IF delSelected THEN invertSel(sel1.n,sel2.n,6);
      ELSIF moveSelected THEN invertSel(sel1.n,sel2.n,4);
      ELSE invertSel(sel1.n,sel2.n,5);
      END; 
      delSelected := FALSE;
      copySelected := TRUE;
      moveSelected := FALSE; |
    10: (* move selection *)
      IF delSelected THEN invertSel(sel1.n,sel2.n,5);
      ELSIF copySelected THEN invertSel(sel1.n,sel2.n,4);
      ELSE invertSel(sel1.n,sel2.n,6);
      END;
      delSelected := FALSE;
      copySelected := FALSE;
      moveSelected := TRUE; |
    11:
      IF delSelected THEN invertSel(sel1.n,sel2.n,4);
      ELSIF copySelected THEN invertSel(sel1.n,sel2.n,5);
      ELSIF moveSelected THEN invertSel(sel1.n,sel2.n,6);
      END;
      delSelected := FALSE;
      copySelected := FALSE;
      moveSelected := FALSE;
    ELSE
    END; (* CASE *)
    END;

    col := Mcol + ORD(McolSel) - 1;
    Locate(Mline,col,sel);
    IF (sel.d = d) & (sel.n >= n) THEN
      IF SelInv IN optionSet THEN
        IF sel.n > selNo THEN
          invertSel(sel2.n+1,sel.n,Pat());
          selNo := sel.n;
          sel2 := sel;
        ELSIF sel.n < selNo THEN 
          invertSel(sel.n+1,sel2.n,Pat());
          selNo := sel.n;
          sel2 := sel;
        END;
      ELSE
        IF sel.n # selNo THEN
          ClearMark(2);
          selNo := sel.n;
          sel2 := sel;
          SetMark(2, sel2.l, sel2.x);
        END;
      END;
      lastValidMline := Mline;
      lastValidMcol := col;
    ELSE
      Mcol := lastValidMcol; (* read only !?! *)
      McolSel := TRUE; (* read only !?! *)
      Mline := lastValidMline; (* read only !?! *)
    END;
  END ContinueSelection;

  PROCEDURE StopSelection;
  BEGIN (*  -------------  *)
    selected := TRUE;
    IF sel2.ch = EOF THEN Deselect;
    ELSIF (KeySel IN optionSet) OR (ButSel IN optionSet) THEN
      IF delSelected THEN DeleteSection;
      ELSIF copySelected THEN SaveSection; InsertSection;
      ELSIF moveSelected THEN Move;
      END;
    END;
  END StopSelection;


  BEGIN
    selected := FALSE;
    delSelected := FALSE;
    copySelected := FALSE;
    moveSelected := FALSE;
  END Select;

(* ----------------------------------------------------------- *)


  PROCEDURE UpdateWindows (pos: BOOLEAN; dn: CARDINAL);
    VAR (*  -------------                           *)
      L0,L1,L2: CARDINAL; n: CharNo; w: WindowPtr;
  BEGIN
    L0 := cur.l; w := win[L0];
    w := doc[w^.doc].firstWindow; n := chn[L0];
    REPEAT L0 := w^.firstLine; L2 := w^.lastLine;
      WHILE empty(L2) DO DEC(L2) END ;
      IF chn[L2] >= n THEN
        WHILE chn[L0] < n DO INC(L0) END ;
        IF chn[L0] # n THEN 
          IF pos 
          THEN INC(chn[L0],dn);
          ELSE DEC(chn[L0],dn);
          END;    
        END;
        L1 := L0;
        WHILE L1 < L2 DO
          INC(L1);  
          IF pos 
          THEN INC(chn[L1],dn);
          ELSE DEC(chn[L1],dn);
          END;
        END ;
        Paint(L0)
      END ;
      w := w^.next
    UNTIL w = NIL
  END UpdateWindows;

  PROCEDURE nextLine;
    VAR (*  -------- *)
      L0: CARDINAL;
  BEGIN
    IF cur.l = win[cur.l]^.lastLine THEN (*move one line up*)
      L0 := win[cur.l]^.firstLine; chn[L0] := chn[L0+1];
      Paint(L0); DEC(cur.l);             (* CopyL ? *)
    END ;
    UpdateWindows(TRUE,1); PlaceCursor(cur.l+1, 0)
  END nextLine;

  PROCEDURE Insert (ch: CHAR);  (*ch is printable*)
  BEGIN (*  ------         *)
    Deselect;
    insertChar(ch, cur.d, cur.n);
    IF cur.x < columns-1 THEN
      UpdateWindows(TRUE,1); PlaceCursor(cur.l, cur.x+1)
    ELSE nextLine
    END
  END Insert;

  PROCEDURE InsertLine;
  BEGIN (*  ----------  *)
    Deselect;
    insertChar(EOL, cur.d, cur.n);
    nextLine
  END InsertLine;

  PROCEDURE Backspace;
    VAR (*  ---------  *)
      deleted: BOOLEAN;
  BEGIN
    IF (cur.x > 0) OR (cur.l > win[cur.l]^.firstLine) THEN
      delChar(cur.d, cur.n, deleted);
      IF deleted THEN
        Deselect;
        IF cur.x > 0 THEN
          PlaceCursor(cur.l, cur.x -1);
          ClearCaret;
          UpdateWindows(FALSE,1);
        ELSE
          PlaceCursor(cur.l-1, columns-1);
          ClearCaret;
          UpdateWindows(FALSE,1);
        END;
        SetCaret(cur.l,cur.x);
      END
    END
  END Backspace;
 
  PROCEDURE InsertSection;
    VAR (*  -------------  *)
      leng: CARDINAL;
  BEGIN
    Deselect;
    insertBuffer(cur.d, cur.n, leng);
    UpdateWindows(TRUE,leng);
    IF MovCar IN optionSet THEN MoveCaret(cur.l,cur.n+leng);
    ELSE SetCaret(cur.l,cur.x);
    END;
  END InsertSection;

  PROCEDURE DeleteSection;
  BEGIN (*  -------------  *)
    selectBuffer(sel1.d, sel1.n, sel2.n);
    Delete;
    PlaceCursor(sel1.l, sel1.x)
  END DeleteSection;

  PROCEDURE Delete;
    VAR (*  ------  *)
      L,L0,L1,L2: CARDINAL; n,dn: CharNo; w: WindowPtr;
  BEGIN
    Deselect;
    delete;
    dn := sel2.n - sel1.n + 1;
    w := doc[sel1.d].firstWindow; n := chn[sel1.l];
    REPEAT L := w^.firstLine; L2 := w^.lastLine;
      WHILE empty(L2) DO DEC(L2) END ;
      IF chn[L] <= n THEN
        IF chn[L2] >= n THEN (*chn[L] <= chn[sel1.l] <= chn[L2]*)
          WHILE chn[L] # n DO INC(L) END ;
          L0 := L+1;
          IF chn[L2] < chn[sel2.l] THEN
            L1 := L2 + 1; ELSE L1 := (sel2.l - sel1.l) + L0
          END;
          WHILE L0 < L1 DO
            chn[L0] := 0; leng[L0] := 0; INC(L0)
          END ;
          WHILE L0 <= L2 DO
            DEC(chn[L0], dn); INC(L0)
          END ;
          Paint(L)
        END
      ELSIF chn[L] <= chn[sel2.l] THEN
        (*chn[sel1.l] < chn[L] <= chn[sel2.l]*)
        chn[L] := chn[sel1.l]; Paint(L);
      ELSE (*chn[sel2.l] < chn[L]*)
        REPEAT
          DEC(chn[L],dn);
          INC(L);
        UNTIL L > L2;
      END ;
      w := w^.next
    UNTIL w = NIL;
  END Delete;

  PROCEDURE Move;
    VAR (*  ----  *)
      leng: CARDINAL;
  BEGIN
    selectBuffer(sel1.d, sel1.n, sel2.n);
    IF cur.d # sel1.d THEN
      Delete;
      InsertSection;
    ELSIF cur.n < sel1.n THEN
      Delete;
      insertBuffer(cur.d, cur.n, leng);
      UpdateWindows(TRUE,leng);
      IF MovCar IN optionSet THEN MoveCaret(cur.l,cur.n+leng);
      ELSE SetCaret(cur.l,cur.x);
      END;
    ELSIF cur.n > sel2.n THEN
      Delete;
      WITH cur DO
        n := n - (sel2.n - sel1.n + 1);
        WHILE chn[l] > n DO DEC(l); END;
        x := n - chn[l];
      END;
      insertBuffer(cur.d, cur.n, leng);
      UpdateWindows(TRUE,leng);
      IF MovCar IN optionSet THEN MoveCaret(cur.l,cur.n+leng);
      ELSE SetCaret(cur.l,cur.x);
      END;
    END;
  END Move;
    

  PROCEDURE SaveSection;
  BEGIN (*  ------------  *)
    Deselect;
    selectBuffer(sel1.d, sel1.n, sel2.n);
  END SaveSection;

  PROCEDURE ReadBuffer (VAR s: ARRAY OF CHAR; VAR length: CARDINAL);
  BEGIN (*  ----------                                           *)
    readBuffer(sel1.d, sel1.n, sel2.n, s, length);
  END ReadBuffer;

  PROCEDURE Find (s: ARRAY OF CHAR; length: CARDINAL; VAR found: BOOLEAN);
    VAR  (* ----                                                *)
      matching,k,j,L,L1: CARDINAL;
      firstCh, CH: CHAR;
  BEGIN 
    CH := thisChar(cur.d,cur.n);
    found := FALSE;
    firstCh := s[0];
    matching := 0;
    WHILE CH # EOF DO
      IF CH = firstCh
      THEN
        INC(matching); CH := nextChar();
        LOOP
          WHILE (matching < length) AND (CH = s[matching]) DO
            INC(matching); CH := nextChar();
          END;
          IF matching = length
          THEN
            found := TRUE; 
            CH := EOF;
            EXIT;
          ELSE
            k := 1;
            LOOP
              j := 0;
              WHILE (k+j < matching) AND (s[j] = s[k+j]) DO INC(j); END;
              IF k+j = matching
              THEN
                DEC(matching,k);
                EXIT;
              ELSE
                INC(k);
              END;
            END; (*LOOP*)
          END;
          IF matching = 0 THEN EXIT; END;
        END; (* LOOP*)
      ELSE
        CH := nextChar();
      END;
    END;

    Deselect;
    IF found THEN
      k := 0;
      WHILE (CH # EOL) AND (currentIndex # 0FFFFh) DO
        CH := prevChar();
        INC(k);
      END;
      L1 := win[cur.l]^.lastLine;
      L := win[cur.l]^.firstLine;
      L1 := (L1-L) DIV 2;
      IF currentIndex # 0FFFFh
      THEN chn[L] := currentIndex+1
      ELSE chn[L] := 0
      END;
      ScanBack(L,L1);
      chn[L] := currentIndex;
      Paint(L);
      INC(L,L1); DEC(k);
      PlaceCursor(L + k DIV columns, k MOD columns);
    END;
  END Find;

  PROCEDURE InitEditWindows;
    VAR (*  ---------------  *)
      d: DocNo;
  BEGIN
    InitEditDocuments;
    InitWindowBar;
    windowCount := 0;
    selected := FALSE;
    FOR d := 0 TO maxDocNo DO doc[d].firstWindow := NIL END ;
  END InitEditWindows;

END EditWindows.
