
MODULE disktest;
  (* a collection of test programs to maintain and test
     the  disk HB 120 through HP   
     Jirka Hoppe   28/1/83 *)

  FROM SYSTEM IMPORT ADR, ADDRESS, WORD;

 
CONST bufflen=127; (*length of the buffer for disk data *)  
      READ = 0A0h; WRITE = 0A1h;

VAR buffer      : ARRAY [0..bufflen] OF CARDINAL;
    indirect    : BOOLEAN; (*indirect mode of commands*)
    maxerrors   : CARDINAL (* max nr of error messages pro case *);
    maxtest     : CARDINAL; (* max number of tests during one session *)

MODULE instructions;
  (* implements some hardware instructions *)
  IMPORT WORD;
  EXPORT PUT, GET, CardinalTestOff;

  PROCEDURE PUT(chan : CARDINAL; value : WORD);
  (*----------*)
  CODE 241b
  END PUT;

  PROCEDURE GET(chan : CARDINAL; VAR value : WORD);
  (*---------*)
  CODE 240b
  END GET;

  PROCEDURE CardinalTestOff;
  (* turn off the trap *)
  CODE 247b; 2b; 265b; 147b; 7b; 335b; 320b; 167b
  END CardinalTestOff;

END instructions;

(**********************************************)

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


(***************************************************)

MODULE indirectCommands;
  (* implements an indirect macro command *)
  IMPORT Write;
  EXPORT PutInString, ReadFromString, inx;
  CONST maxcom = 60;
  VAR commands : ARRAY [0..maxcom] OF CHAR; (*store macro*)
      inx : CARDINAL (*index in commands*);
 
  PROCEDURE PutInString(ch:CHAR);
    BEGIN IF inx<maxcom THEN commands[inx] := ch; INC(inx) 
          ELSE Write(7c) (*bell*); commands[inx]:=15c
          END 
    END PutInString;

  PROCEDURE ReadFromString(VAR ch : CHAR);
    BEGIN ch := commands[inx]; Write(ch);
      IF ch=15c THEN inx := 0 ELSE INC(inx) END
    END ReadFromString;

BEGIN inx := 0 END indirectCommands; 

(************************************************) 
 
MODULE HPHEX;
  (* implements a formatted input/output to the HPterminal *)
  IMPORT Write, Read, ReadFromString, indirect;
  EXPORT hexin, hexout, WriteLn,Print, Println;


  PROCEDURE hexin(VAR n:CARDINAL; VAR delim:CHAR);
    VAR ch:CHAR; help:CARDINAL;
    BEGIN n:=0;
      IF indirect THEN ReadFromString(ch) ELSE Read(ch) END;
      WHILE ((ch>='0')AND(ch<='9')) OR ((ch>='A') AND (ch<='F')) DO
        IF ch <= '9' THEN help:=CARDINAL(ch)-30h
                     ELSE help:=CARDINAL(ch)-37h
        END;
        n:=n*16+help;
        IF indirect THEN ReadFromString(ch) ELSE Read(ch) END;
      END;
      delim := ch
    END hexin;

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

  PROCEDURE WriteLn;
    BEGIN Write(15c); Write(12c) END WriteLn;

  PROCEDURE Print(x: ARRAY OF CHAR);
      VAR i: CARDINAL;
    BEGIN i := 0;
      LOOP
        IF x[i] = 0C THEN EXIT END;
        Write(x[i]);
        INC(i);
        IF i> HIGH(x) THEN EXIT END;
      END;
    END Print;

  PROCEDURE Println(x: ARRAY OF CHAR);
    BEGIN Print(x); WriteLn END Println;
  
END HPHEX;

(****************************************************)

MODULE randomnumbers;
  EXPORT random1, random2,  setrnd1, setrnd2;

  VAR x:ARRAY [1..55] OF CARDINAL;
      x55, x24 : CARDINAL;
      r2, i, j : CARDINAL;

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
    BEGIN FOR x55 := 1 TO 55 DO x[x55] := x55 * value + 5555h END;
      x55 := 55; x24 := 55-24;
      FOR i := 0 TO 100 DO j := random1() END;
    END setrnd1;

  PROCEDURE setrnd2(value : CARDINAL);
    BEGIN r2 := value END setrnd2;

END randomnumbers;

(*************************************************)

MODULE HBdisk;
  (* Version 4/11/80 *)

  IMPORT Write, Print, WriteLn, hexout;
  IMPORT PUT, GET, ADDRESS;
  EXPORT  DiskDriver, ReadWrite, DkErrors, DiskType,
          settrack, diskread, diskwrite, PrintError, printstatus;

  CONST
  (* I/O channel assigments *)
  (* I/O destinations *)
  command =  9; 
  dataout =  8;
  trackh  = 10;
  trackl  = 11;
  sector  = 12;
  (* I/O sources *)
  status  =  9;
  datain  =  8;

  (* commands  - used on I/O channel 'command' *)
  init    =  7;   (* initialize disk + controller *)
  faultrst=  6;   (* reset the fault condition *)
  clradr  =  5;   (* reset the adr counter of the internal memory *)
  badscrst=  4;   (* reset bad sector *)

  (* status bits - on I/O channel 'status' *)
  badsec  = 15;   (* bad sector *)
  fault   = 14;   (* fault condition *)
  seekrdy = 13;   (* ready to start the seek sequence *)
  wrprt   = 12;   (* write protected *)
  timeout = 11;   (* time out *)
  crcerr  = 10;   (* cyclic redundancy check error *)
  xfercmpl=  9;   (* transfer completed *)
  rdysrw  =  8;   (* ready to seek, read or write *)

  NILtrack= 0FFFFh;(* that is a nonexisting track *)

 TYPE
  ReadWrite = (dkread, dkwrite);
  DkErrors    = (ok, notready, dkfault, parity, timout, badseek,
                 recparity, illsect, softtimeout, writeprot, doubleillsect);
  DiskType = (removable, fixed);

  VAR oldtrack : CARDINAL ; (* keeps the current position of a head *)
      softTimeOut : CARDINAL;
 
  MODULE interpreter;
    (* describes routines which are implemented as macro instructionen
       in the interpreter *)
    IMPORT ADDRESS, status, trackh, trackl, PUT, GET;
    EXPORT settrack, diskread, diskwrite;

    PROCEDURE settrack(track : CARDINAL);
      (* wait until disk is ready to accept the seek sequence *)
      CODE 0A4H   
      END settrack;

    PROCEDURE diskread(p: ADDRESS);
      (* copy data from the internal buffer of the disk controller *)
      CODE 0A2H
      END diskread;

    PROCEDURE diskwrite(p: ADDRESS);
      (* copy data to the internal buffer of the disk controller
         handle preamble and synch word *)
      CODE 0A3H
      END diskwrite;

  END interpreter;

PROCEDURE PhysicalSector(track, sector : CARDINAL) : CARDINAL;
  BEGIN
    IF track <= 29 THEN RETURN ( (sector * 3) MOD 48 ) + ( (sector * 3 ) DIV 48 ) 
                   ELSE RETURN ( (sector * 12) MOD 48 ) + ( (sector * 12 ) DIV 48 )
    END
  END PhysicalSector;

PROCEDURE WaitSeek(VAR er : DkErrors);
(* waits until seek ready *)
BEGIN softTimeOut := 0;
  REPEAT GET(status, stat); INC(softTimeOut)
  UNTIL ({rdysrw, fault}*stat <> {}) OR (softTimeOut = 0FFFFH);
  IF fault IN stat THEN er := badseek; oldtrack := NILtrack;
    ResetFault;
  ELSIF softTimeOut = 0FFFFh THEN er := softtimeout 
  END;
END WaitSeek;

PROCEDURE ResetFault;
  BEGIN PUT(command,init); PUT(command, faultrst);
      REPEAT GET(status, stat) UNTIL {rdysrw, fault}*stat <> {};
      oldtrack := NILtrack
  END ResetFault;

PROCEDURE DiskDriver( disktyp : DiskType; rw : ReadWrite ; dkadr : CARDINAL;
                      buffadr: ADDRESS; VAR er : DkErrors);

  CONST  maxretry = 1;
         read     = 80h; (* read function *)
         write    = 40h; (* write function*)
 
  VAR stat,stat1 : BITSET   (* used to get status *);
      retry: CARDINAL (* retry count *);
      track, sect:CARDINAL;
 
  BEGIN er:=ok;
    GET(status, stat);
    IF NOT (rdysrw IN stat) THEN er := notready; RETURN END;

    IF fault IN stat THEN  ResetFault  END;
    IF badsec IN stat THEN PUT(command, badscrst) (*reset bad sector*) END;
    GET(status, stat);
    IF fault IN stat THEN er := dkfault; RETURN END;

    track := dkadr DIV 48;
    sect := PhysicalSector(track, dkadr MOD 48) ;
    IF disktyp=fixed THEN track := track + 4000h;(* switch on disk1 *) END;

    LOOP (* to handle bad sectors *)
      settrack(track);

      IF rw = dkread THEN
(* disk read *)
        (* wait interrupt *)
        WaitSeek(er);
        IF (er=dkfault) OR (er=softtimeout) THEN RETURN END;
        retry := maxretry;
        LOOP           
          PUT(sector,sect+read);
          (* wait interrupt *)
          REPEAT GET(status, stat) UNTIL {xfercmpl, timeout}*stat <> {};
          IF timeout IN stat THEN er := timout; RETURN END;
          IF NOT (crcerr IN stat) THEN EXIT END;
          er := recparity;
          IF retry = 0 THEN er := parity; EXIT END;
          DEC(retry);
        END;
        diskread(buffadr)
      ELSE
 (* disk write *)
        GET(status, stat);
        IF wrprt IN stat THEN er := writeprot; RETURN END;
        diskwrite(buffadr);
        (* wait seek interrupt *)
        WaitSeek(er);
        IF (er=dkfault) OR (er=softtimeout) THEN RETURN END;
        PUT(sector,sect+write);
        (* wait interrupt *)
        REPEAT GET(status, stat) UNTIL {xfercmpl, timeout}*stat <> {};
        IF timeout IN stat THEN er := timout; RETURN END;
      END;

      IF badsec IN stat THEN
         er := illsect; PUT(command,badscrst); 
         IF sect < 48 THEN sect := 48
         ELSE sect := 49
         END
      ELSE EXIT (* loop for bad sector*)
      END
    END (* loop for bad sectors *);
  END DiskDriver;


PROCEDURE printstatus(st:BITSET);
  BEGIN hexout(CARDINAL(st) MOD 100h); Write(' ');
    IF 14 IN st THEN Print(' fault,') END;
    IF 12 IN st THEN Print(' write prot,') END;
    IF 11 IN st THEN Print(' time out,') END;
    IF 10 IN st THEN Print(' CRC err,') END;
    IF NOT(9 IN st) THEN Print(' Xfer not cmpltd,') END;
    IF NOT(8 IN st) THEN Print(' SRW not rdy') END;  WriteLn;
  END printstatus;

PROCEDURE PrintError(er : DkErrors; sect : CARDINAL);
  VAR stat : BITSET;
  BEGIN
      Print('disk error on sect='); hexout(sect);
      Write(' ');
      CASE er OF
      notready : Print('not ready') |
      dkfault  : Print('fault')|
      parity   : Print('parity err')|
      timout   : Print('time out')  |
      badseek  : Print('bad adr') |
      recparity: Print('recovered parity error') |
      illsect  : Print('invalid sect') |
      softtimeout : Print('soft timeout') |
      writeprot: Print('write protected') |
      doubleillsect: Print('double invalid sect')
      ELSE       Print('unknown')
      END;
      PUT(command, init); PUT(command, faultrst); WriteLn;
      REPEAT GET(status, stat) UNTIL {rdysrw, fault}*stat <> {};
      oldtrack := NILtrack
  END PrintError; 

VAR stat : BITSET;
  
BEGIN
  PUT(command, init); PUT(command, faultrst); PUT(command, badscrst); 
  oldtrack := NILtrack;
END HBdisk;

(*************************************************)

VAR ch:CHAR; (* used all over the main program *)
    i, j:CARDINAL; (*used in the main program*)
    er        : DkErrors;
    anyerrors : BOOLEAN; (*any errors were encountered in a test*)
    rereadcount : CARDINAL;(* number of reread operations*)
    interleav : CARDINAL; (*interleaving factor for speeding up sequential access*)
    tr,sc     : CARDINAL; (* track, sector used for sequential access*)

MODULE FillCompare;
  (* fill and compare the main buffer *)
  IMPORT buffer, Write, Key, maxerrors, anyerrors;
  FROM HPHEX IMPORT hexin,hexout,WriteLn, Print;
  EXPORT fill, compare;

  VAR i : CARDINAL;
      nrerrors : CARDINAL; (* nr of errors messages *)

  PROCEDURE fill(n: CARDINAL);
    BEGIN i:= 0;
      REPEAT buffer[i] := n+i; INC(i) UNTIL i>127;
    END fill;

  PROCEDURE compare(n:CARDINAL);
    BEGIN i := 0; nrerrors := 0;
      LOOP
        IF nrerrors>=maxerrors THEN Print('too many errors');
          WriteLn; EXIT
        END;
        IF buffer[i] <> n+i THEN
           Print('sect='); hexout(n); 
           Print(' inx='); hexout(i);
           Print(' act='); hexout(buffer[i]);
           Print(' exp='); hexout(n+i);
           WriteLn; INC(nrerrors); anyerrors := TRUE;
        END;
        INC(i); 
        IF (i>127) OR Key() THEN EXIT END;
      END
    END compare;

END FillCompare;


PROCEDURE testerror(ch: CHAR; sect : CARDINAL);
  BEGIN
    IF er<>ok THEN Write(ch);Write(' '); hexout(CARDINAL(er));
      PrintError(er,sect);
      WriteLn;
    END; 
  END testerror;

PROCEDURE PrintReread(i : CARDINAL);
  BEGIN Print('sector '); hexout(i); Println(' was reread');
  END PrintReread;

PROCEDURE randomtest;
  (* test random access with random data *)
  VAR sect, ii, iii ,k, nrerrors : CARDINAL;
  BEGIN setrnd2(i); ii := 0;
    REPEAT sect := random2();
      IF sect < 392*96 (*maxsector*) THEN
        buffer[0] := sect; setrnd1(ii+sect);
        FOR k := 1 TO 127 DO buffer[k] := random1() END;
        DiskDriver(currentDisk, dkwrite, sect, ADR(buffer), er); 
        testerror('W', sect);
      END;
      INC(ii);
    UNTIL (ii>maxtest) OR Key();        hexout(ii);
   IF Key() THEN Read(ch) END; (* clear Key *)
   (* 'ii' keeps now the number of written sectors *)

  (* now check all written sectors *)
    setrnd2(i); iii := 0; (* 'iii' is now used as a counter *)
    REPEAT  sect := random2();
      IF sect < 392*96 THEN
        anyerrors := FALSE; rereadcount := 0;
        LOOP (* many rereads *)
          DiskDriver(currentDisk, dkread, sect, ADR(buffer), er); 
          testerror('R', sect);
          IF buffer[0] <> sect THEN (*first location is the sector# *)
            Print('seek error, act='); hexout(buffer[0]);
            Print(' exp='); hexout(sect); WriteLn; anyerrors := TRUE;
          ELSE
            setrnd1(iii+sect); k := 1; nrerrors :=0;
            LOOP (* check the rest of the buffer *)
              IF nrerrors>maxerrors THEN 
                Print('too many errors');WriteLn; EXIT
              END;
              i := random1();
              IF buffer[k] <> i THEN
                Print('sect='); hexout(sect);
                Print(' inx='); hexout(k);
                Print(' act='); hexout(buffer[k]);
                Print(' exp='); hexout(i);   WriteLn;
                INC(nrerrors); anyerrors := TRUE;
              END;
              INC(k);
              IF (k>127) OR Key() THEN EXIT END;
            END (*test loop*)
          END; (* If sect ok *)
          IF (NOT anyerrors) OR (rereadcount >= 1) THEN EXIT; END;
          INC(rereadcount); PrintReread(sect);
        END (*reread loop*);
      END; (* IF sect < maxsector*)
      INC(iii);
    UNTIL (iii>=ii) OR Key();   hexout(iii);
  END randomtest;

PROCEDURE menu;
  BEGIN
    Println('tab loop macro');
    Println('G get');
    Println('H high limit 92ff');
    Println('I inspect');
    Println('J interleaving');
    Println('K seek');
    Println('L load');
    Println('M max errors');
    Println('N random');
    Println('O display buff');
    Println('P put');
    Println('Q which disk 0/1 ');
    Println('R read buff');
    Println('S save');
    Println('T 0<->i test');
    Println('U write up');
    Println('V read up');
    Println('W write buff');
    Println('X load - no display');
    Println('Y status');
    Println('Z reset'); 
    Println('= fill same'); 
    Println('+ fill incr');
  END menu;

PROCEDURE displaybuff;
  VAR i: CARDINAL;
  BEGIN WriteLn;
    FOR i := 0 TO bufflen DO hexout(buffer[i]); Write(' ');
      IF (i MOD 16) = 15 THEN (*WriteLn *)END;
    END;
    WriteLn;
  END displaybuff;

VAR
  currentDisk : DiskType; (* removable, fixed *)

BEGIN indirect := FALSE; maxerrors := 2; maxtest := 9200h;
      interleav := 1h; CardinalTestOff;
  LOOP WriteLn; Write('>'); hexin(i,ch);
    IF NOT indirect THEN (*input comes from keyboard*)
      IF ch=11c (*tab*) THEN (*read command string*)
        Write(' '); Write(':');
        inx := 0;
        REPEAT Read(ch); PutInString(ch) UNTIL ch=15C;
        indirect := TRUE; inx := 0
      END;
    ELSE (*indirect commands from string*)
      IF Key() THEN indirect := FALSE END;
    END;
    IF ch >= ' ' THEN
    CASE ch OF
    'P' : hexin(j,ch); PUT(i,j) |
    'G' :  GET(i,j) ;   hexout(j)|
    'J' : IF ((i DIV 2)*2<>i) AND ((i DIV 3)*3<>i) THEN
                interleav := i;
          ELSE
            Println('bad interleaving, must not be dividable by 2, 3');
          END |
    'K' : settrack(i);
          REPEAT GET(9,j) UNTIL{8,14,15}*BITSET(j)<>{}|
    'T' : 
          REPEAT fill(i);
            DiskDriver(currentDisk, dkwrite, i,ADR(buffer), er);
            testerror('W',i);
            DiskDriver(currentDisk, dkread,  0,ADR(buffer), er);
            testerror('R',0);
            IF (er=ok)OR(er=illsect) THEN compare(0) END;
            anyerrors := FALSE; rereadcount := 0;
            LOOP (* reread *)
              DiskDriver(currentDisk, dkread,  i,ADR(buffer), er);
              testerror('R',i); 
              IF (er=ok) OR (er=illsect) THEN compare(i) END;
              IF (NOT anyerrors) OR (rereadcount >= 1) THEN EXIT END;
              INC(rereadcount); PrintReread(i)
            END (* reread loop*);
            INC(i);
          UNTIL (i >=maxtest) OR Key() ;
          hexout(i) |
    'M' : maxerrors := i |
    'H' : maxtest := i  |
    'L' : DiskDriver(currentDisk, dkread, i,ADR(buffer), er);
          testerror('R',i);
          displaybuff  |
    'S' : DiskDriver(currentDisk, dkwrite, i,ADR(buffer), er);
           testerror('W',i)  |
    'I' : LOOP hexout(buffer[i]); Read(ch);
             IF ch=':' THEN hexin(buffer[i],ch) END;
             IF ch=',' THEN INC(i); WriteLn; hexout(i); Write(' ')
                       ELSE EXIT
             END
          END  |
    'O' : displaybuff  |
    'Q' : IF i = 0 THEN currentDisk :=  removable
          ELSE currentDisk := fixed
          END |
    'R' : diskread(ADR(buffer)); displaybuff  |
    'W' : diskwrite(ADR(buffer)) |
    'Y' : GET(9,j); printstatus(BITSET(j)) |
    'Z' : PUT(9,7); PUT(9,6) |
    'X' : DiskDriver(currentDisk, dkread,i,ADR(buffer),er)   |
    'N' : randomtest   |
    'U' : tr := (i DIV 48) * 48;
          REPEAT sc := 0;
            WHILE (sc < 48*interleav) AND (NOT Key()) DO
              i := tr + (sc MOD 48);
              fill(i); DiskDriver(currentDisk, dkwrite,i,ADR(buffer),er);
              testerror('W',i);
              sc := sc + interleav
            END;
            INC(tr,48);
          UNTIL (i>maxtest) OR Key();
         hexout(i) |
    'V' : tr := (i DIV 48) * 48;
          REPEAT sc := 0;
           WHILE (sc < 48*interleav) AND (NOT Key()) DO
             anyerrors := FALSE; rereadcount := 0;
             i := tr + (sc MOD 48);
             LOOP (*reread*) 
               DiskDriver(currentDisk, dkread,i, ADR(buffer),er);
               testerror('R',i);
               IF (er=ok) OR (er=illsect) THEN compare(i) END;
               IF (NOT anyerrors) OR (rereadcount >= 1) THEN EXIT END;
               INC(rereadcount); PrintReread(i)
             END (* reread loop*);
             sc := sc + interleav
           END;(*while*)
           INC(tr,48);
          UNTIL(i>maxtest) OR Key();
         hexout(i) |     
    '+' : FOR j := 0 TO 127 DO buffer[j] := i+j END |
    '=' : FOR j := 0 TO 127 DO buffer[j] := i END |
    '?' : menu() 
    ELSE Write('?');
    END (* CASE *)
    END (* IF ch >= 'A' *)
  END
END disktest.
