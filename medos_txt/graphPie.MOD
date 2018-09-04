IMPLEMENTATION MODULE graphPie;

  (* Copyright: DISER AG *)
  (* Author: Leo Geissmann, DISER Zurich *)
  (* Version: 1 *)
  (* Date: 83.09.02 *)
  (* Purpose: Painting of a pie diagram in a window *)

  IMPORT
    Screen,
    WindowHandler,
    MathLib0,
    graphPattern;

  FROM Screen IMPORT
    Bitmap, CreateBitmap, ReturnBitmap;

  FROM WindowHandler IMPORT
    BlockDescriptor, Replicate, BlockTransfer, DisplayDot, Mode,
    Window, OpenBitmapWindow, CloseWindow;

  FROM MathLib0 IMPORT
    sin, cos, arctan, sqrt;

  FROM graphPattern IMPORT
    PaintPattern;

  TYPE
    FullPattern =
      RECORD
        height : CARDINAL; (* pattern height *)
        pattern : BITSET; (* pattern *)
      END;

  VAR
    diagramwindow : Window; (* window of displayed diagram *)
    diagramblock : BlockDescriptor; (* block of pie in diagram *)
    piebitmap : Bitmap; (* bitmap used for pie shape *)
    piewindow : Window; (* window overlaid to pie bitmap *)
    pieblock : BlockDescriptor; (* block for pie shape *)
    pieradius : CARDINAL; (* radius of the pie; 0 means not initialized *)
    slicebitmap : Bitmap; (* bitmap used for slice generation *)
    slicewindow : Window; (* window overlaid to slice bitmap *)
    sliceblock : BlockDescriptor; (* block for slice generation *)
    pi025 : REAL; (* value pi/4 *)
    percentangle : REAL; (* angle for slice of one percent *)
    oldpercent : REAL; (* old total percent of assigned slices *)
    oldangle : REAL;   (* old total angle of assigned slices *)
    startangle : REAL; (* initial angle value for slice assignment *)
    fullpat : FullPattern; (* pattern *)

  PROCEDURE InitPie(
              wind : Window; (* where the pie must be painted *)
              x0, y0 : CARDINAL; (* coordinates of origin *)
              radius : CARDINAL; (* radius of the pie *)
              VAR ok : BOOLEAN); (* pie correctly initialized *)

    PROCEDURE PaintPie;
      VAR
        xo, yo : CARDINAL; (* original coordinates of pie circle *)
        nextyo : CARDINAL; (* next yo coordinate *)
        ysqr : CARDINAL;   (* square of y-coordinate *)
        xdec : CARDINAL;   (* decrement of ysqr by incrementing x-coordinate *)
        lineblock : BlockDescriptor; (* block of a vertical line *)
    BEGIN (* PaintPie *)
      xo := 0;
      yo := radius;
      ysqr := radius * radius;
      xdec := 1;
      lineblock.w := 1; (* remains constant *)
      (* paint shape without border into pie window *)
      (* paint border into diagram window *)
      WHILE xo < radius DO
        (* calculate new yo coordinate, i.e. inner yo *)
        ysqr := ysqr - xdec;
        nextyo := TRUNC(sqrt(FLOAT(ysqr)) + 0.5);
        xdec := xdec + 2;
        (* paint shape *)
        lineblock.x := radius - xo;
        lineblock.y := radius - yo + 1; (* without border *)
        lineblock.h := 2 * yo - 1;
        Replicate(piewindow, lineblock, replace, fullpat);
        lineblock.x := radius + xo;
        Replicate(piewindow, lineblock, replace, fullpat);
        (* display border points *)
        FOR yo := yo TO nextyo BY -1 DO
          DisplayDot(diagramwindow, x0 - xo, y0 - yo, replace);
          DisplayDot(diagramwindow, x0 - xo, y0 + yo, replace);
          DisplayDot(diagramwindow, x0 + xo, y0 - yo, replace);
          DisplayDot(diagramwindow, x0 + xo, y0 + yo, replace);
        END;
        (* new coordinates *)
        xo := xo + 1;
        yo := nextyo;
      END;
      (* complete border points *)
      lineblock.x := x0 - xo;
      lineblock.y := y0 - yo;
      lineblock.h := 2 * yo + 1;
      Replicate(diagramwindow, lineblock, replace, fullpat);
      lineblock.x := x0 + xo;
      Replicate(diagramwindow, lineblock, replace, fullpat);
      (* invert pie shape *)
      Replicate(piewindow, pieblock, invert, fullpat);
    END PaintPie;

  BEGIN (* InitPie *)
    diagramwindow := wind;
    (* return possibly allocated slicebitmap *)
    IF pieradius > 0 THEN
      CloseWindow(piewindow);
      ReturnBitmap(piebitmap);
      CloseWindow(slicewindow);
      ReturnBitmap(slicebitmap);
    END;
    (* check on enough space *)
    ok := (radius <= x0) AND (x0 + radius < diagramwindow^.innerblk.w) AND
          (radius <= y0) AND (y0 + radius < diagramwindow^.innerblk.h);
    IF ok THEN
      WITH diagramblock DO
        x := x0 - radius;
        y := y0 - radius;
        w := 2 * radius + 1;
        h := 2 * radius + 1;
      END;
      Replicate(diagramwindow, diagramblock, erase, fullpat);
      pieradius := radius;
      (* initialize pie shape *)
      CreateBitmap(piebitmap, diagramblock.w, diagramblock.h, ok);
      IF ok THEN
        OpenBitmapWindow(piewindow, piebitmap, ok);
        WITH pieblock DO
          x := 0;
          y := 0;
          w := diagramblock.w;
          h := diagramblock.h;
        END;
        Replicate(piewindow, pieblock, erase, fullpat);
      END;
      (* initialize slice operations *)
      CreateBitmap(slicebitmap, diagramblock.w, diagramblock.h, ok);
      IF ok THEN
        OpenBitmapWindow(slicewindow, slicebitmap, ok);
        WITH sliceblock DO
          x := 0;
          y := 0;
          w := diagramblock.w;
          h := diagramblock.h;
        END;
      END;
      startangle := 10.0 * pi025; (* = 2.5 * 4 * pi025 *)
      oldangle := 0.0;
      oldpercent := 0.0;
    END;
    IF ok THEN PaintPie ELSE pieradius := 0 END;
  END InitPie;

  PROCEDURE PieSlice(
              percent : REAL; (* size of slice in percent *)
              patnum : CARDINAL); (* number of pattern of slice *)
    VAR
      angle : REAL; (* angle of a slice border *)

    PROCEDURE VerticalShadow(
                m : REAL; (* factor in equation y = m * x *)
                upper : BOOLEAN; (* shadow in upper part *)
                modus : Mode); (* modus for replication of shadow *)
      VAR
        xo , yo : CARDINAL; (* original coordinates of pie circle *)
        yb : CARDINAL; (* block coordinate *)
        rad : REAL;
        lineblock : BlockDescriptor; (* block of a vertical line *)
    BEGIN (* VerticalShadow *)
      rad := FLOAT(pieradius);
      lineblock.x := pieradius;
      IF upper THEN lineblock.y := pieradius ELSE lineblock.y := 0 END;
      lineblock.w := 1; (* remains constant *)
      lineblock.h := pieradius + 1;
      Replicate(slicewindow, lineblock, modus, fullpat);
      FOR xo := 1 TO pieradius DO
        yb := TRUNC(m * FLOAT(xo) + rad);
        lineblock.x := pieradius + xo;
        IF upper THEN
          lineblock.y := yb;
          lineblock.h := 2 * pieradius - yb + 1;
        ELSE
          lineblock.h := yb + 1;
        END;
        Replicate(slicewindow, lineblock, modus, fullpat);
        lineblock.x := pieradius - xo;
        IF upper THEN
          lineblock.y := 2 * pieradius - yb;
          lineblock.h := yb + 1;
        ELSE
          lineblock.h := 2 * pieradius - yb + 1;
        END;
        Replicate(slicewindow, lineblock, modus, fullpat);
      END;
    END VerticalShadow;

    PROCEDURE HorizontalShadow(
                m : REAL; (* factor in equation x = m * y *)
                right : BOOLEAN; (* shadow in right part *)
                modus : Mode); (* modus for replication of shadow *)
      VAR
        xo , yo : CARDINAL; (* original coordinates of pie circle *)
        xb : CARDINAL; (* block coordinate *)
        rad : REAL;
        lineblock : BlockDescriptor; (* block of a vertical line *)
    BEGIN (* HorizontalShadow *)
      rad := FLOAT(pieradius);
      IF right THEN lineblock.x := pieradius ELSE lineblock.x := 0 END; 
      lineblock.y := pieradius;
      lineblock.w := pieradius + 1;
      lineblock.h := 1; (* remains constant *)
      Replicate(slicewindow, lineblock, modus, fullpat);
      FOR yo := 1 TO pieradius DO
        xb := TRUNC(m * FLOAT(yo) + rad);
        lineblock.y := pieradius + yo;
        IF right THEN
          lineblock.x := xb;
          lineblock.w := 2 * pieradius - xb + 1;
        ELSE
          lineblock.w := xb + 1;
        END;
        Replicate(slicewindow, lineblock, modus, fullpat);
        lineblock.y := pieradius - yo;
        IF right THEN
          lineblock.x := 2 * pieradius - xb;
          lineblock.w := xb + 1;
        ELSE
          lineblock.w := 2 * pieradius - xb + 1;
        END;
        Replicate(slicewindow, lineblock, modus, fullpat);
      END;
    END HorizontalShadow;

  BEGIN (* PieSlice *)
    IF pieradius <> 0 THEN (* assume pie initialized *)
      (* set up generation area *)
      IF oldpercent + percent >= 99.95 THEN percent := 100.05 - oldpercent END;
      IF percent > 10.0E-5 THEN
        Replicate(slicewindow, sliceblock, erase, fullpat);
        angle := startangle - oldangle;
        CASE TRUNC((angle + pi025) / (2.0 * pi025))  MOD 4 OF
          0 : VerticalShadow(sin(angle) / cos(angle), FALSE, paint);
        | 1 : HorizontalShadow(cos(angle) / sin(angle), TRUE, paint);
        | 2 : VerticalShadow(sin(angle) / cos(angle), TRUE, paint);
        | 3 : HorizontalShadow(cos(angle) / sin(angle), FALSE, paint);
        END;
        oldpercent := oldpercent + percent;
        oldangle := oldpercent * percentangle;
        angle := startangle - oldangle;
        IF percent < 50.0 THEN
          CASE TRUNC((angle + pi025) / (2.0 * pi025)) MOD 4 OF
            0 : VerticalShadow(sin(angle) / cos(angle), FALSE, erase);
          | 1 : HorizontalShadow(cos(angle) / sin(angle), TRUE, erase);
          | 2 : VerticalShadow(sin(angle) / cos(angle), TRUE, erase);
          | 3 : HorizontalShadow(cos(angle) / sin(angle), FALSE, erase);
          END;
        ELSE
          CASE TRUNC((angle + pi025) / (2.0 * pi025)) MOD 4 OF
            0 : VerticalShadow(sin(angle) / cos(angle), TRUE, paint);
          | 1 : HorizontalShadow(cos(angle) / sin(angle), FALSE, paint);
          | 2 : VerticalShadow(sin(angle) / cos(angle), FALSE, paint);
          | 3 : HorizontalShadow(cos(angle) / sin(angle), TRUE, paint);
          END;
        END;
        (* paint pie shape *)
        BlockTransfer(slicewindow, sliceblock, erase, piewindow, pieblock);
        (* paint pattern *)
        PaintPattern(patnum, slicewindow, sliceblock, erase);
        (* paint slice in diagram *)
        BlockTransfer(diagramwindow, diagramblock, paint, slicewindow, sliceblock);
      END;
    END;
  END PieSlice;

BEGIN (* graphPie *)
  fullpat.height := 1;
  fullpat.pattern := {0 .. 15};
  pieradius := 0; (* no pie initialized *)
  pi025 := arctan(1.0);
  percentangle := 0.08 * pi025; (* pi025 = 12.5 % *)
END graphPie.
