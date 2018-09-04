IMPLEMENTATION MODULE Jdisk;
  (* author Jirka Hoppe *)
  (* Version 9/5/83 *)

  FROM Terminal IMPORT Write, WriteString, WriteLn;
  FROM CardinalIO IMPORT WriteOct;
  FROM SYSTEM IMPORT ADDRESS, WORD;
 (* EXPORT  diskdriver, readwrite, dkerrors, disktype;*)

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

 (*  TYPE
  readwrite = (dkread, dkwrite);
  dkerrors    = (ok, notready, dkfault, parity, timout, badseek,
                 recparity, badsect);
  disktype = (removable, fixed);
*)
VAR
  oldtrack : CARDINAL ; (* keeps the current position of a head *)
  softTimeOut : CARDINAL;
 
(*---------*)
MODULE instructions;
  (* implements some hardware instructions *)
  IMPORT WORD, ADDRESS;
  EXPORT PUT, GET;

  PROCEDURE PUT(chan : CARDINAL; value : WORD);
  (*----------*)
  CODE 241b
  END PUT;

  PROCEDURE GET(chan : CARDINAL; VAR value : WORD);
  (*---------*)
  CODE 240b
  END GET;

END instructions;

(*-----------------------*)
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

PROCEDURE WaitSeek(VAR er : dkerrors);
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

PROCEDURE diskdriver( disktyp : disktype; rw : readwrite ; dkadr : CARDINAL;
                      buffadr: ADDRESS; VAR er : dkerrors);

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
  END diskdriver;


PROCEDURE printstatus(st:BITSET);
  BEGIN WriteOct(CARDINAL(st) MOD 100h); Write(' ');
    IF 14 IN st THEN WriteString(' fault,') END;
    IF 12 IN st THEN WriteString(' write prot,') END;
    IF 11 IN st THEN WriteString(' time out,') END;
    IF 10 IN st THEN WriteString(' CRC err,') END;
    IF NOT(9 IN st) THEN WriteString(' Xfer not cmpltd,') END;
    IF NOT(8 IN st) THEN WriteString(' SRW not rdy') END;  WriteLn;
  END printstatus;

PROCEDURE PrintError(er : dkerrors; sect : CARDINAL);
  VAR stat : BITSET;
  BEGIN
      WriteString('disk error on sect='); WriteOct(sect);
      Write(' ');
      CASE er OF
      notready : WriteString('not ready') |
      dkfault  : WriteString('fault')|
      parity   : WriteString('parity err')|
      timout   : WriteString('time out')  |
      badseek  : WriteString('bad adr') |
      recparity: WriteString('recovered parity error') |
      illsect  : WriteString('invalid sect') |
      softtimeout : WriteString('soft timeout') |
      writeprot: WriteString('write protected') |
      doubleillsect: WriteString('double invalid sect')
      ELSE       WriteString('unknown')
      END;
      PUT(command, init); PUT(command, faultrst); WriteLn;
      REPEAT GET(status, stat) UNTIL {rdysrw, fault}*stat <> {};
      oldtrack := NILtrack
  END PrintError; 

VAR stat : BITSET;
  
BEGIN
  PUT(command, init); PUT(command, faultrst); PUT(command, badscrst); 
  REPEAT GET(status, stat) UNTIL {rdysrw, fault}*stat <> {};
  oldtrack := NILtrack;
END Jdisk.
