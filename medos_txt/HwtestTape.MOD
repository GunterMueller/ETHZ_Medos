MODULE hwtest;

(* a collection of testprograms simulating some tough
 situation in the computer *)

(*   Jirka Hoppe, Institut fur Informatik, ETH Zuerich  *)
(*   Version  27/1/83  *)

 FROM SYSTEM IMPORT ADDRESS, WORD, TSIZE, ADR;
 TYPE  bmd = RECORD start : ADDRESS;
                    w: CARDINAL;
                    h: CARDINAL;
                    position : CARDINAL;
             END;

 
 VAR low, high : ADDRESS;     (* limits for the test *)
     bank0Low, bank0High, bank1Low, bank1High : ADDRESS; (* low and high banks limits *)
     lowBank   : BOOLEAN;     (* TRUE if we test the lower bank *)
     fp        : CARDINAL;    (* frame pointer *)
     errcnt    : CARDINAL;    (* error count *)
     stopflag  : BOOLEAN;     (* halt after an error *)
     pbmd      : POINTER TO bmd; (* keeps local bmd for the test area *)
     allign    : ARRAY [0..7] OF WORD; (* used to alling the bmd *)


MODULE Instructions;
  (* defines some instruction that are not accessible from MODULA *)
  IMPORT WORD, ADDRESS;
  EXPORT LXFW, SXFW, CardinalTestOff, GET, PUT;

  PROCEDURE LXFW(fp: CARDINAL; offset : ADDRESS) : CARDINAL;
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


  PROCEDURE GET(chan : CARDINAL; VAR value : WORD);
  (*---------*)
  CODE 240b
  END GET;

  PROCEDURE PUT(chan : CARDINAL; value : WORD);
  (*----------*)
  CODE 241b
  END PUT;

END Instructions;

(*----------------------------------------------*)
MODULE HP; 
  IMPORT GET, PUT;
  EXPORT Write, Read, Key;

  CONST LineStatus = 5; LineData = 4;
        FreeBit = 15; DoneBit = 14;

  PROCEDURE Write(ch: CHAR);
    VAR Status: BITSET;
  BEGIN 
    REPEAT GET(LineStatus,Status) UNTIL FreeBit IN Status;
    PUT(LineData,ch)
  END Write;

  PROCEDURE Read(VAR ch: CHAR);
    VAR Status: BITSET;
  BEGIN 
    REPEAT GET(LineStatus,Status); UNTIL DoneBit IN Status;
    GET(LineData,ch);
    IF ch >= 'a' THEN ch := CAP(ch) END;
    Write(ch)
  END Read;

  PROCEDURE Key(): BOOLEAN;
    VAR Status: BITSET;
  BEGIN
    GET(LineStatus,Status); RETURN DoneBit IN Status;
  END Key;

END HP;

(*------------------------------------------------*)

MODULE HPHEX;
  (* implements a formatted input/output to the HPterminal *)
  IMPORT Write, Read, WORD;
  EXPORT hexin, hexout, WriteString, WriteLn;


  PROCEDURE hexin(VAR n:WORD; VAR delim:CHAR);
    VAR ch:CHAR; help:CARDINAL;
    BEGIN n:=WORD(0);
      Read(ch);
      IF (ch >= 'a') AND (ch<>177c) THEN ch := CAP(ch) END;
      WHILE (((ch>='0')AND(ch<='9')) OR ((ch>='A') AND (ch<='F'))) OR (ch=177c) DO
        IF ch = 177c THEN n :=WORD(CARDINAL(n) DIV 16);
        ELSE
          IF ch <= '9' THEN help:=CARDINAL(ch)-30h
                       ELSE help:=CARDINAL(ch)-37h
          END;
          n:=WORD(CARDINAL(n)*16+help);
        END;
        Read(ch);
        IF (ch >= 'a') AND (ch<>177c) THEN ch := CAP(ch) END;
      END;
      delim := ch
    END hexin;

  PROCEDURE hexout(n : WORD);
  VAR buff : ARRAY [1..4] OF CHAR; i : CARDINAL;  nn : CARDINAL;
      help : CARDINAL;
  BEGIN nn := CARDINAL(n);
    FOR i := 1 TO 4 DO
      help := nn MOD 16; nn := nn DIV 16;
      IF help <= 9 THEN buff[i] := CHAR(help+30h)
                   ELSE buff[i] := CHAR(help+37h)
      END
    END;
    FOR i := 4 TO 1 BY -1 DO Write(buff[i]) END;
    END hexout;

  PROCEDURE WriteLn;
    BEGIN Write(15c); Write(12c)
    END WriteLn;
  
PROCEDURE WriteString(s : ARRAY OF CHAR);
(*------------------*)
  VAR i : CARDINAL;
BEGIN 
  i := 0;
  WHILE (i<=HIGH(s)) AND (s[i]<>0c) DO Write(s[i]); INC(i) END
END WriteString;

END HPHEX;

(*------------------------------------------*)

MODULE Limits;
  IMPORT ADDRESS, ADR;
  EXPORT GetLimits;

  PROCEDURE GetLimits(VAR bank0Low, bank0High, bank1Low, bank1High : ADDRESS);
    BEGIN
      (* be very careful if you change this constants *)
      bank0Low  := 10240; (*  20*512 *)
      bank0High := 64000; (* 125*512 *)
      bank1Low  :=     0;
      bank1High := 64000;
    END GetLimits;

END Limits;

(*-----------------------------------------*)

MODULE RandomNumbers;
  IMPORT WORD;
  EXPORT random1, random2,  setrnd1, setrnd2;

  VAR x:ARRAY [1..55] OF CARDINAL;
      x55, x24 : CARDINAL;
      r2 : CARDINAL;

  PROCEDURE random1(): CARDINAL;
    VAR help : CARDINAL;
    BEGIN help := x[x55] + x[x24]; x[x55] := help;
      x55 := (x55 MOD 55) + 1; x24 := (x24 MOD 55) + 1;
      RETURN(help)
    END random1;

  PROCEDURE random2(): CARDINAL;
    (* r2 := 8293*r2 + 1 *)
     BEGIN r2 := 2765*r2 +1; RETURN(r2) END random2;
  
  PROCEDURE setrnd1(value : WORD);
    BEGIN
      FOR x55 := 1 TO 55 DO
        x[x55] := x55 + CARDINAL(value) + 100h*x55
      END;
      x55 := 55; x24 := 55-24; x[1] := 0FFFFh;
    END setrnd1;

  PROCEDURE setrnd2(value : WORD);
    BEGIN r2 := CARDINAL(value) END setrnd2;

END RandomNumbers;

(*-----------------------------------------------------*)


TYPE testtype = (pat, adrs, rndval, rndacs, rowtst);

PROCEDURE MemError(tt:testtype; adr : ADDRESS; exp, act : WORD);
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
    REPEAT (*adr^ := value;*) SXFW(fp, adr, value); INC(adr)
    UNTIL adr>=high;
    adr := low;
    REPEAT
      (* help := adr^; *) help := LXFW(fp, adr);
      IF value <> help THEN MemError(pat,adr, value, help) END;
      INC(adr);
    UNTIL (adr >=high) OR stopflag;
  END pattern;

PROCEDURE addressing;
  (* write into each memory cell its address *)
  VAR adr: ADDRESS; help : CARDINAL;
  BEGIN adr := low;
    REPEAT (*adr^ := adr;*) SXFW(fp, adr, adr); INC(adr)
    UNTIL adr >=high;
    adr := low;
    REPEAT
      (*help := adr^; *) help := LXFW(fp, adr);
      IF help <> CARDINAL(adr) THEN MemError(adrs,adr, adr, help) END;
      INC(adr);
    UNTIL (adr >=high) OR stopflag;
  END addressing;

PROCEDURE randomvalues(value : CARDINAL);
  (* random values into consecutive memory cells *)
  VAR adr: ADDRESS; help1, help2: CARDINAL;
  BEGIN adr := low;  setrnd1(value);
    REPEAT help1 := random1();
      (* adr^:=help1;*) SXFW(fp, adr, help1); 
      INC(adr)
    UNTIL adr >=high;
    adr := low; setrnd1(value);
    REPEAT
      (*help1 := adr^;*) help1 := LXFW(fp, adr);
      help2 := random1();
      IF help1 <> help2 THEN MemError(rndval,adr, help2, help1) END;
      INC(adr);
    UNTIL (adr >=high) OR stopflag;
  END randomvalues;

PROCEDURE randomAndWait(value : WORD);
  (* the same as reandomvalues but wait between write and check *)
  VAR adr: ADDRESS; help1, help2: CARDINAL;
  BEGIN adr := low;  setrnd1(value);
    REPEAT help1 := (random1());
      (* adr^:=WORD(help1);*) SXFW(fp, adr, help1); 
      INC(adr)
    UNTIL adr >=high;

    WriteString(' waiting..');
    help1 := 0;
    REPEAT INC(help1);
      help2 := 0;
      REPEAT INC(help2)
      UNTIL (help2=1000) OR Key();
    UNTIL (help1=100) OR Key();

    adr := low; setrnd1(value);
    REPEAT
      (*help1 := adr^;*) help1 := LXFW(fp, adr);
      help2 := random1();
      IF help1 <> help2 THEN MemError(rndval,adr, help2, help1) END;
      INC(adr);
    UNTIL (adr >=high) OR stopflag;
  END randomAndWait;

PROCEDURE randomaccess(value : CARDINAL);
  (* acces the memory in a random order ......*)
  CONST max=8000h;
  VAR adr : ADDRESS; help, i: CARDINAL;
  BEGIN  setrnd2(value); i := 0;
    REPEAT adr := ADDRESS(random2());
      IF (adr>=low) AND (adr<=high) THEN
        (*adr^ := WORD(i);*) SXFW(fp, adr, i)
      END;
      INC(i);
    UNTIL i>=max;
    i := 0; setrnd2(value);
    REPEAT adr := ADDRESS(random2());
      IF (adr>=low) AND (adr<=high) THEN
        (*help := adr^*) help := LXFW(fp, adr);
        IF (help <> i) THEN 
          MemError(rndacs, adr, adr, help)
        END; 
      END;
      INC(i);
    UNTIL (i>=max) OR stopflag;
  END randomaccess;

PROCEDURE rowtest;
  (* algorithmus:
     a/ fill a memory with a value (= all 0's or all 1's)
     b/ fill the bits of one memory-chip-row with the
        inverted value
     c/ read and compare the whole memory, but allways leave
        out the tested row
     d/ read and compare the tested row
 
     the algoritmus tests if there is no crosstalk on the
     sense lines in the memory and that the charges
     in each bit cell remain unchanged even if all bits
     in the neighbourhood change

     the test is runned twice for each row (all 0's and all 1's) *)

  VAR adr       : ADDRESS;
      i, j,k    : CARDINAL;
      leaveout  : CARDINAL;
      value, notvalue : CARDINAL;
      help      : CARDINAL;
 
  BEGIN i := 0;
    REPEAT  (* for all rows *)
      value := 0;
      FOR k := 1 TO 2 DO   (* twice for each row *)

       (* fill memory *)
       adr := low;
       REPEAT adr^:=WORD(value); INC(adr, TSIZE(WORD));
        IF adr = low+i THEN INC(adr, 511) (* leave out the tested row *)
        END 
       UNTIL adr>=high;

       (* fill the row with the inverted value *)
       notvalue := CARDINAL(BITSET(value) / (* XOR*) BITSET(0FFFFH));
       adr := low + i;
       REPEAT (* fill all 4 chips at once *)
         adr^ := WORD(notvalue); INC(adr, TSIZE(WORD))
       UNTIL adr >= (low + i + 512);

       leaveout := ( low + i) DIV 512;  (* this addresses will be left out *)

       (* check the memory but leave the tested row out *)
       adr := low;
       REPEAT
         IF (adr DIV 512) <> leaveout THEN
             help := CARDINAL(adr^);
             IF help <> value THEN
               WriteString('mem'); MemError(rowtst,adr, value, help) 
             END;
             INC(adr,1)
         ELSE INC(adr, 512) (* skip the whole row *)
         END;
       UNTIL (adr >= high) OR stopflag;

       (* now check the row *)
       adr := low + i;
       REPEAT  help := CARDINAL(adr^);
           IF help <> notvalue THEN
             WriteString('row') ; MemError(rowtst,adr, notvalue, help)
           END;
           INC(adr);
       UNTIL (adr >= (low+i+512)) OR stopflag;

       value := 0FFFFH;
     END (* for each row twice *);
    INC(i,512);
  UNTIL (( low + i + 512) >= high) OR Key();
  END rowtest;


(*-------end of memory tests ----------*)

 PROCEDURE error(nr, exp, act : WORD);
  BEGIN WriteString('#err '); hexout(nr);
    WriteString(' exp '); hexout(exp);
    WriteString(' act '); hexout(act); WriteLn;
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

PROCEDURE menu;
  BEGIN WriteLn;
    WriteString('G get parameters'); WriteLn;
    WriteString('P pattern'); WriteLn;
    WriteString('S addressing'); WriteLn;
    WriteString('R random'); WriteLn;
    WriteString('X rnd access'); WriteLn;
    WriteString('W worst test'); WriteLn;
    WriteString('L Loop'); WriteLn;
    WriteString('+ arith'); WriteLn;
    WriteString('^ access'); WriteLn;
    WriteString('# error count'); WriteLn;
    WriteString('/ flip memory bank'); WriteLn;
  END menu;

PROCEDURE getparameters;
  VAR n : CARDINAL; ch : CHAR;
  BEGIN WriteLn;
    WriteString('low='); hexout(low);
    Read(ch);
    IF ch = ':' THEN hexin(n,ch); low:=ADDRESS(n) END;
    WriteLn;
    WriteString('high='); hexout(high);
    Read(ch);
    IF ch = ':' THEN hexin(n,ch); high:=ADDRESS(n) END;
    WriteLn;
    WriteString('frame pointer(4000)='); hexout(fp);
    Read(ch);
    IF ch = ':' THEN hexin(n,ch); fp:=ADDRESS(n) END;
    WriteLn;
    WriteString('ADR(bmd)='); hexout(CARDINAL(ADR(pbmd))); WriteLn;
    WriteString('ADR(map)='); hexout(initbmd.start);
    Read(ch);
    IF ch = ':' THEN hexin(n,ch); initbmd.start:=n END;
    WriteLn;
    WriteString('w='); hexout(initbmd.w);
    Read(ch);
    IF ch = ':' THEN hexin(n,ch); initbmd.w:=n END; 
    WriteLn;
    WriteString('h='); hexout(initbmd.h);
    Read(ch);
    IF ch = ':' THEN hexin(n,ch); initbmd.h:=n END; 
    WriteLn;
    WriteString('position='); hexout(initbmd.position);
    Read(ch);
    IF ch = ':' THEN hexin(n,ch); initbmd.position:=n END; 
    WriteLn;
    
    pbmd^ := initbmd;
  END getparameters;

VAR i,n : CARDINAL; ch : CHAR;  initbmd : bmd; adr : ADDRESS;


BEGIN (*main*)
  GetLimits(bank0Low, bank0High, bank1Low, bank1High);
  low := bank0Low; high := bank0High; fp := 0;
  lowBank := TRUE;

  CardinalTestOff;
  errcnt := 0;
  (* prepare bit map descriptor *)
  adr := ADR(allign);
  pbmd := adr + 4 - (adr MOD 4); 
  WITH initbmd DO
    start := low; w := 48; h := 590; position := 0
  END;
  pbmd^ := initbmd;
  PUT(0, pbmd);
  LOOP
    WriteLn; Write('>'); hexin(n,ch); stopflag := FALSE;
    CASE ch OF
    '?': menu()          |
    'G': getparameters   |
    'P': pattern(n)      |
    'S': addressing()    |
    'R': randomvalues(n) |
    'X': randomaccess(n) |
    'L': 
         LOOP 
           Write('+');
           arithmetic;                    IF Key() THEN EXIT END; 
           Write('^');
           access;                        IF Key() THEN EXIT END;
           Write('p');
           pattern(0); addressing();      IF Key() THEN EXIT END;
           Write('a');
           pattern(0FFFFh); addressing(); IF Key() THEN EXIT END;
           Write('r');
           pattern(0); randomvalues(n);   IF Key() THEN EXIT END; 
           Write('x');
           pattern(0); randomaccess(n);   IF Key() THEN EXIT END;
           INC(n); Write('R');
           pattern(0); randomAndWait(n);
           IF Key() THEN EXIT END;
           lowBank := NOT lowBank;
             IF lowBank THEN fp := 0; low := bank0Low; high := bank0High;
                WriteString('Low')
             ELSE fp := 4000h; low := bank1Low; high := bank1High;
               WriteString('High ')
             END;
          END; 
          WriteLn;
          WriteString('number of errors='); hexout(errcnt); WriteLn;
           |
    'W': rowtest |
    '+': arithmetic  |
    '^': access      |
    '#': WriteString('number of errors='); hexout(errcnt); WriteLn |
    '/': lowBank := NOT lowBank;
         WriteString('tested memory bank is now ');
         IF lowBank THEN fp := 0; low := bank0Low; high := bank0High;
           WriteString('LOW')
         ELSE fp := 4000h; low := bank1Low; high := bank1High;
           WriteString('HIGH ')
         END;
         WriteLn;
    ELSE Write('!')
    END
  END
END hwtest.

