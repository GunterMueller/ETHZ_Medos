MODULE hwtest;

(* a collection of testprograms simulating some tough
 situation in the computer *)

(*   Jirka Hoppe, Institut fur Informatik, ETH Zuerich  *)
(*   Version  11/12/81  *)

 FROM SYSTEM IMPORT ADDRESS, WORD, TSIZE, ADR;
 FROM Terminal IMPORT Read, BusyRead, Write, WriteLn, WriteString, ReadAgain;
 FROM Program IMPORT AllocateHeap, DeallocateHeap;
 FROM Frames IMPORT Allocate, ChangeSize, Deallocate;

 
 VAR low, high : ADDRESS;     (* limits for the test *)
     bank0Low, bank0High, bank1Low, bank1High : ADDRESS; (* low and high banks limits *)
     lowBank   : BOOLEAN;     (* TRUE if we test the lower bank *)
     fp        : CARDINAL;    (* frame pointer *)
     highFp    : CARDINAL;    (* frame pointer to the high memory *)
     errcnt    : CARDINAL;    (* error count *)
     stopflag  : BOOLEAN;     (* halt after an error *)
     toBoot    : BOOLEAN;     (* if disk was not ready, boot the machine *)

(*----------------------------------------------*)
MODULE RenameInput;
  (* renames input procedures so that standart I/O and my own routines 
     could be used *)
  IMPORT BusyRead;
  EXPORT  Key;

  PROCEDURE Key(): BOOLEAN;
    VAR ch: CHAR;
  BEGIN BusyRead(ch);
    RETURN(ch<>0C)
  END Key;

END RenameInput;

(*------------------------------------------------*)

MODULE HPHEX;
  (* formated hexadecimal I/O *)
  IMPORT Write;
  EXPORT  hexout;


  PROCEDURE hexout(n : CARDINAL);
    VAR help1, help2:CARDINAL;
    BEGIN help1 := 1000h;
      REPEAT help2 := (n DIV help1) MOD 16; 
        help1:= help1 DIV 16;
        IF help2 <= 9 THEN Write( CHAR(help2+30h))
                      ELSE Write( CHAR(help2+37h))
        END
      UNTIL help1 = 0;
    END hexout;

END HPHEX;

(*------------------------------------------*)

MODULE limits;
  IMPORT ADDRESS, ADR, AllocateHeap, DeallocateHeap, Allocate, ChangeSize,
         highFp, hexout, Write;
  EXPORT getlimits;

  PROCEDURE getlimits(VAR bank0Low, bank0High, bank1Low, bank1High : ADDRESS);
    VAR help : ADDRESS;
        oldHigh, oldLow : CARDINAL;
        done : BOOLEAN;
    BEGIN    
     bank0High := AllocateHeap(0); (* dummy allocate to get the high limit *)
     help      := AllocateHeap(177777b); (* a big number *)
     help      := DeallocateHeap(1000); (* return some heap for local variables *)
     bank0Low  := help;

     Allocate(highFp, 4); (*try a small amount *)
     (* try by a binary search to find the largest possible frame *)
     oldHigh := 4 * (100000b-2 -highFp); (* this is the possible largest frame *)
     oldLow := 0;
     LOOP
       bank1High := (oldHigh DIV 2) + (oldLow DIV 2);
       ChangeSize(highFp, bank1High, done);
       IF ((oldHigh - oldLow) < 100) AND done THEN EXIT END;
       IF done THEN oldLow := bank1High + 1 ELSE oldHigh := bank1High -1 END; 
     END;

     bank1Low := 0;
    END getlimits;

END limits;

(*-----------------------------------------*)

MODULE randomnumbers;
  EXPORT random1, random2,  setrnd1, setrnd2;

  VAR x:ARRAY [1..55] OF CARDINAL;
      x55, x24 : CARDINAL;
      r2 : CARDINAL;

  PROCEDURE random1():CARDINAL;
    VAR help : CARDINAL;
    BEGIN help := x[x55] + x[x24]; x[x55] := help;
      x55 := (x55 MOD 55) + 1; x24 := (x24 MOD 55) + 1;
      RETURN(help)
    END random1;

  PROCEDURE random2(): CARDINAL;
    (* r2 := 8293*r2 + 1 *)
     BEGIN r2 := 2765*r2 +1; RETURN(r2) END random2;
  
  PROCEDURE setrnd1(value : CARDINAL);
    BEGIN FOR x55 := 1 TO 55 DO x[x55] := x55 + value + 100h*x55 END;
      x55 := 55; x24 := 55-24; x[1] := 0FFFFh;
    END setrnd1;

  PROCEDURE setrnd2(value : CARDINAL);
    BEGIN r2 := value END setrnd2;

END randomnumbers;

(*-----------------------------------------------------*)

MODULE instructions;
  (* defines some instruction that are not accessible from MODULA *)
  IMPORT WORD, ADDRESS;
  EXPORT LXFW, SXFW, CardinalTestOff, Boot, GET;

  PROCEDURE LXFW(fp: CARDINAL; offset : ADDRESS) : WORD;
    (* load indexed frame word *)
    CODE 203b
    END LXFW;

  PROCEDURE SXFW(fp : CARDINAL; offset : ADDRESS;  val : WORD);
    (* store indexed frame word *)
    CODE 223b
    END SXFW;

  PROCEDURE CardinalTestOff;
    CODE 247b; 2b; 265b; 147b; 7b; 335b; 320b; 167b
    END CardinalTestOff;

  PROCEDURE Boot(trackNr : CARDINAL);
    CODE 247b; 0
  END Boot;

  PROCEDURE GET(chan : CARDINAL; VAR value : WORD);
  (*---------*)
  CODE 240b
  END GET;

END instructions;

(*---------------------------------------------*)

TYPE testtype = (pat, adrs, rndval, rndacs, rowtst);

PROCEDURE MemError(tt:testtype; adr : ADDRESS; exp, act : CARDINAL);
  BEGIN WriteString('error in ');
    CASE tt OF
    pat    : WriteString('pattern')  |
    adrs   : WriteString('addressing')  |
    rndval : WriteString('rnd value')  |
    rndacs : WriteString('rnd access')  |
    rowtst : WriteString('row test')
    END;
    WriteString(' adr='); hexout(CARDINAL(adr));
    WriteString(' exp='); hexout(exp);
    WriteString(' act='); hexout(act);
    WriteString(' reread='); hexout(CARDINAL(LXFW(fp, adr))); WriteLn;
    INC(errcnt);
    stopflag := Key();
  END MemError;
 
PROCEDURE pattern( value : CARDINAL);
  (* fill the whole memory with a uniform pattern *)
  VAR adr : ADDRESS; help : CARDINAL;
  BEGIN adr := low;
    REPEAT (*adr^ := WORD(value);*) SXFW(fp, adr, value);
      INC(adr, TSIZE(WORD))
    UNTIL adr>=high;
    adr := low;
    REPEAT
      (* help := CARDINAL(adr^); *) help := CARDINAL(LXFW(fp, adr));
      IF value <> help THEN MemError(pat,adr, value, help) END;
      INC(adr, TSIZE(WORD));
    UNTIL (adr >=high) OR stopflag;
  END pattern;

PROCEDURE addressing;
  (* write into each memory cell its address *)
  VAR adr: ADDRESS; help : CARDINAL;
  BEGIN adr := low;
    REPEAT (*adr^ := WORD(adr);*) SXFW(fp, adr, adr);
      INC(adr, TSIZE(WORD))
    UNTIL adr >=high;
    adr := low;
    REPEAT
      (*help := CARDINAL(adr^); *) help := CARDINAL(LXFW(fp, adr));
      IF help <> CARDINAL(adr) THEN MemError(adrs,adr, CARDINAL(adr), help) END;
      INC(adr, TSIZE(WORD));
    UNTIL (adr >=high) OR stopflag;
  END addressing;

PROCEDURE randomvalues(value : CARDINAL);
  (* random values into consecutive memory cells *)
  VAR adr: ADDRESS; help1, help2: CARDINAL;
  BEGIN adr := low;  setrnd1(value);
    REPEAT help1 := (random1());
      (* adr^:=WORD(help1);*) SXFW(fp, adr, help1); 
      INC(adr, TSIZE(WORD))
    UNTIL adr >=high;
    adr := low; setrnd1(value);
    REPEAT
      (*help1 := CARDINAL(adr^);*) help1 := CARDINAL(LXFW(fp, adr));
      help2 := random1();
      IF help1 <> help2 THEN MemError(rndval,adr, help2, help1) END;
      INC(adr, TSIZE(WORD));
    UNTIL (adr >=high) OR stopflag;
  END randomvalues;

PROCEDURE randomAndWait(value : CARDINAL);
  (* the same as reandomvalues but wait between write and check *)
  VAR adr: ADDRESS; help1, help2: CARDINAL;
  BEGIN adr := low;  setrnd1(value);
    REPEAT help1 := (random1());
      (* adr^:=WORD(help1);*) SXFW(fp, adr, help1); 
      INC(adr, TSIZE(WORD))
    UNTIL adr >=high;

    WriteString(' waiting..');
    help1 := 0;
    REPEAT INC(help1);
      help2 := 0;
      REPEAT INC(help2)
      UNTIL (help2=1000) OR Key();
      IF help2<1000 THEN ReadAgain END;
    UNTIL (help1=100) OR Key();
    IF help1<100 THEN ReadAgain END;
    Write(177c); Write(177c); Write(177c); Write(177c); Write(177c);
    Write(177c); Write(177c); Write(177c); Write(177c); Write(177c);

    adr := low; setrnd1(value);
    REPEAT
      (*help1 := CARDINAL(adr^);*) help1 := CARDINAL(LXFW(fp, adr));
      help2 := random1();
      IF help1 <> help2 THEN MemError(rndval,adr, help2, help1) END;
      INC(adr, TSIZE(WORD));
    UNTIL (adr >=high) OR stopflag;
  END randomAndWait;

PROCEDURE randomaccess(value : CARDINAL);
  (* acces the memory in a random order ......*)
  CONST max=8000h;
  VAR adr : ADDRESS; help, i: CARDINAL;
  BEGIN  setrnd2(value); i := 0;
    REPEAT adr := ADDRESS(random2());
      IF (adr>=low) AND (adr<=high) THEN (*adr^ := WORD(i);*) SXFW(fp, adr, i) END;
      INC(i);
    UNTIL i>=max;
    i := 0; setrnd2(value);
    REPEAT adr := ADDRESS(random2());
      IF (adr>=low) AND (adr<=high) THEN
        (*help := CARDINAL(adr^)*) help := CARDINAL(LXFW(fp, adr));
        IF (help <> i) THEN 
          MemError(rndacs, adr, CARDINAL(adr), help)
        END; 
      END;
      INC(i);
    UNTIL (i>=max) OR stopflag;
  END randomaccess;


(*-------end of memory tests ----------*)

 PROCEDURE error(nr, exp, act : WORD);
  BEGIN WriteString('#err '); hexout(CARDINAL(nr));
    WriteString(' exp '); hexout(CARDINAL(exp));
    WriteString(' act '); hexout(CARDINAL(act)); WriteLn;
    INC(errcnt);
    stopflag := Key()
  END error;

PROCEDURE arithmetic;
  (* test various arithmetic operations *)
  VAR i1, i2, i3 : INTEGER;
      c1, c2, c3, c4 : CARDINAL;
  BEGIN 
    (* carry test *)
    c1 := 8; c3 := c1 + c1;
    IF c3<>10h THEN error(10h, 10h, c3) END;
    c1 := 88h; c3 := c1 + c1;
    IF c3<>110h THEN error(11h, 110h, c3) END;
    c1 := 888h; c3 := c1 + c1;
    IF c3<>1110h THEN error(12h, 1110h, c3) END;
    c1 := 10h; c3 := c1-1;
    IF c3<>0Fh THEN error(15h, 0Fh, c3) END;
    c1 := 100h; c3 := c1-1;
    IF c3<>0FFh THEN error(16h, 0FFh, c3) END;
    c1 := 1000h; c3 := c1-1;
    IF c3<>0FFFh THEN error(17h, 0FFFh, c3) END;

    (* addition & subtraction test *)
    c1 := 0FFFFh; c2 := 0;
    REPEAT c3 := c1 + c2;
      IF c3 <> 0FFFFh THEN hexout(c1); Write('+'); hexout(c2);
                           Write('='); error(1Fh, 0FFFFh, c3)
      END;
      DEC(c1); INC(c2);
    UNTIL (c1=0) OR stopflag;

    (* multiplication *)
    (* use some prime numbers *)
    i1 := 137; i3 := i1*211;
    IF i3<>28907 THEN error(20h, 28907, i3) END;
    i1 := 127; i3 := i1*(-257);
    IF i3<>(-32639) THEN error(21h, -32639, i3) END;

    i1 := -107; i3 := i1*(-269); 
    IF i3<>28783 THEN error(22h, 28783, i3) END;
    (* division *)
    i1 := 25979; i3 := i1 DIV 83;
    IF i3<>313 THEN error(25h, 313, i3) END;
    i1 := 31363; i3 := i1 DIV (-79);
    IF i3<>(-397) THEN error(26h, -397, i3) END;
    i1 := -26057; i3 := i1 DIV (-71);
    IF i3<>367 THEN error(27h, 367, i3) END;

    (* mult and div *)
    c1 := 1; c2 := 500;
    REPEAT c3 := c1*c2; c4 := c3 DIV c2;
      IF c4 <> c1 THEN hexout(c1); Write('*'); hexout(c2);
                 Write('='); hexout(c3); Write('/'); hexout(c4); WriteLn;
                 INC(errcnt);
      END;
      INC(c1); DEC(c2);
    UNTIL (c1=500) OR stopflag;

    (* compare two random number generators *)
    c1 := 1; setrnd2(1); i := 0;
    REPEAT c3 := random2(); c1 := 2765*c1 +1;
      IF c1<>c3 THEN error(30h, c1, c3) END;
      INC(i)
    UNTIL (i=30000) OR stopflag;

    (* stack test *)
    c1 := 4000h; c2 := 1;
    (*the bloody compiler doesn't accept all 16 values*)
    c3 := c1  + (2000h + (1000h + (800h + (400h + (200h + (100h +
          (80h + (40h + (20h + (10h + (8 + (4 + (2 + c2)))))))))))));
    IF c3 <> 07FFFh THEN error(31h, 07fffh, c3) END;
  END arithmetic;

PROCEDURE access;
  CONST maxarr=200;
  VAR a : ARRAY [0..maxarr] OF CARDINAL;
      x24,x55 : CARDINAL;
      c1,c2, help1, help2 : CARDINAL;
  BEGIN 
    help2 := CARDINAL(ADR(a[0]));
    FOR c1 := 0 TO 1000 DO
      c2 := (random2()) MOD maxarr;
      help1 := CARDINAL(ADR(a[c2])); c2 := help2 + c2;
      IF c2 <> help1 THEN error(50h, c2, help1) END;
    END;

    FOR c1 := 0 TO maxarr DO a[c1] := c1 END;
    setrnd2(0);
    FOR c1 := 0 TO 1000 DO
      c2 := (random2()) MOD maxarr;
      help1 := a[c2];
      IF c2 <> help1 THEN error(51h, c2, help1) END;
    END;

    (* compare local array acces with global array *)
    (* compare two random number generators *)
    setrnd1(0);

    FOR c1 := 1 TO 55 DO a[c1] := c1 + 100h*c1 END;
    x55 := 55; x24 := 55-24; a[1] := 0FFFFh;
    FOR c2 := 0 TO 1000 DO 
      help1 := random1();
      help2 := a[x55] + a[x24]; a[x55] := help2;
      x55 := (x55 MOD 55) +1; x24 := (x24 MOD 55) + 1;
      IF help1 <> help2 THEN error(52h,help1, help2) END;
    END;
  END access;       

PROCEDURE CheckDisk;
BEGIN
  GET(9, stat); (* get disk status *)
  IF NOT( 8 IN stat) (* if disk off *) THEN toBoot := TRUE END;
END CheckDisk;

VAR i,n : CARDINAL; ch : CHAR;  adr : ADDRESS;
    stat : BITSET;

BEGIN (*main*)
  getlimits(bank0Low, bank0High, bank1Low, bank1High);
  low := bank0Low; high := bank0High; fp := 0;
  lowBank := FALSE;

  CardinalTestOff;
  errcnt := 0; toBoot := FALSE;
  WriteString('hardware test running....     '); 
     LOOP 
           lowBank := NOT lowBank;
             IF lowBank THEN fp := 0; low := bank0Low; high := bank0High;
               Write(177c); Write(177c); Write(177c); Write(177c); Write(177c);
               WriteString('Low  ')
             ELSE fp := highFp; low := bank1Low; high := bank1High;
               Write(177c);  Write(177c);  Write(177c);  Write(177c); Write(177c);
               WriteString('High ')
             END;
           Write('+');
           arithmetic;                    IF Key() THEN EXIT END; CheckDisk;
           Write(177c); Write('^');
           access;                        IF Key() THEN EXIT END; CheckDisk;
           Write(177c); Write('p');
           pattern(0); addressing();      IF Key() THEN EXIT END; CheckDisk;
           Write(177c); Write('a');
           pattern(0FFFFh); addressing(); IF Key() THEN EXIT END; CheckDisk;
           Write(177c); Write('r');
           pattern(0); randomvalues(n);   IF Key() THEN EXIT END; CheckDisk; 
           Write(177c); Write('x');
           pattern(0); randomaccess(n);   IF Key() THEN EXIT END; CheckDisk;
           INC(n); Write(177c); Write('R');
           pattern(0); randomAndWait(n); Write(177c);
           IF Key() THEN EXIT END; CheckDisk;
      END;
  WriteLn;
  WriteString('number of errors='); hexout(errcnt); WriteLn;
  IF toBoot THEN WriteString('disk was turned off'); WriteLn;
    WriteString('type blank to boot');
    Read(ch); Boot(0)
  END;
  ReadAgain;
  low := DeallocateHeap(bank0High-bank0Low);
  Deallocate(highFp)
END hwtest.

