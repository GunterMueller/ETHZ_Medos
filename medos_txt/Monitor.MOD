(***************************************
*                                      *
*          M E D O S - 2V4             *
*          ***************             *
*                                      *
*                                      *
*          Monitor:                    *
*                                      *
*          Module hideing proces-      *
*          ses within MEDOS-2.         *
*                                      *
*          Version 2  20.11.82         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

IMPLEMENTATION MODULE Monitor;

  IMPORT SYSTEM;

  MODULE Scheduler;

    FROM SYSTEM IMPORT
      PROCESS, TRANSFER, ADDRESS;

    IMPORT Status;
 
    EXPORT
      Call, Terminate, TermProcedure,
      CurrentLevel, SharedLevel,
      Create, WaitInterrupt, Kill, Stop, CheckStop,
      cpudev, clkdev;
   
    CONST maxtermtab = 15;
    VAR  termtab: ARRAY [0 .. maxtermtab] OF PROC;
         termtop: CARDINAL;

    CONST maxprog = 15;
    VAR   curprog: CARDINAL;
          sharedprog: ARRAY [0 .. maxprog] OF CARDINAL;

     
    MODULE PrioScheduler[15];

      IMPORT
        PROCESS, TRANSFER, ADDRESS,
        Status;

      EXPORT
        Create, WaitInterrupt,
        PrioCall, Terminate, Kill, Stop, CheckStop,
        activeprog,
        cpudev, clkdev;


      CONST
        user    = 6;
        cpudev  = 7;
        clkdev  = 12;
        dev15   = 15;

        readw   = 240B;
        writew  = 241B;
        sys     = 247B; dump = 1; 
        trap    = 304B;


      TYPE 
        ProcessDesc = RECORD 
                        driver: PROCESS; 
                        interrupted: PROCESS; 
                      END; 
        ProcessIndex = [cpudev .. dev15];

        StatusSet = SET OF Status;
        Process = RECORD
                    g: ADDRESS;
                    l: ADDRESS;
                    ra: CARDINAL;
                    prio: BITSET;
                    s: ADDRESS;
                    h: ADDRESS;
                    cause: Status;
                    trapdisable: StatusSet;
                  END; 
        ProcessPointer = POINTER TO Process;

      VAR 
        usermask[3]: BITSET;
        level0mask: BITSET;

        curproc: [user .. dev15];

        iv[16B]: ARRAY ProcessIndex OF ProcessDesc;

        killstatus: Status;
        terminating: BOOLEAN;
        stoping: BOOLEAN;

        father: PROCESS;
        son[5]: PROCESS;

        activeprog: CARDINAL;

        dft[40B]: ARRAY [0..255] OF ADDRESS;
        residentmodules[15B]: CARDINAL;
        highestdf: ADDRESS;


      PROCEDURE Put(channel: CARDINAL; c: CARDINAL);
      CODE writew
      END Put;

      PROCEDURE Get(channel: CARDINAL; VAR bs: BITSET);
      CODE readw
      END Get;

      PROCEDURE DiskReset;

        CONST
          command  = 9;
          status   = 9;
          init     = 7; faultreset = 6; invsecreset = 4;
          readysrw = 8;

        VAR statusbits: BITSET;

      BEGIN
        Put(command, init);
        Put(command, faultreset);
        Put(command, invsecreset);
        REPEAT Get(status, statusbits) UNTIL readysrw IN statusbits;
      END DiskReset;

      PROCEDURE Dump;
      CODE sys; dump
      END Dump;

      PROCEDURE Trap(st: Status);
      CODE trap;
      END Trap;

      PROCEDURE Create(pix: ProcessIndex; VAR p: PROCESS); 
      BEGIN 
        EXCL(level0mask, pix);
        WITH iv[pix] DO 
          curproc := pix; 
          TRANSFER(interrupted, p); 
        END 
      END Create; 


      PROCEDURE WaitInterrupt; 
        VAR myix: ProcessIndex; 
      BEGIN; 
        myix := curproc; 
        curproc := user;
        EXCL(usermask, myix); 
        WITH iv[myix] DO TRANSFER(driver, interrupted) END; 
        INCL(usermask, myix);
        curproc := myix; 
      END WaitInterrupt; 

   
      PROCEDURE PrioCall(VAR p: PROCESS; VAR st: Status); 

        VAR
          grandfather: PROCESS; 
          myprog: CARDINAL;

      BEGIN
        myprog := activeprog;
        INC(activeprog);
        grandfather := father; 
        TRANSFER(father, p); 
        father := grandfather; 
        activeprog := myprog; 
        p := son;
        st := killstatus;
        IF activeprog = 0 THEN
          usermask := usermask + level0mask; (* reset overwritten devicemask *)
          Put(30B, 0);                       (* stop ether net interface *)
        END;
      END PrioCall; 

  
      PROCEDURE ResidentExecuted(): BOOLEAN;
        VAR pp: ProcessPointer;
      BEGIN
        pp := ProcessPointer(iv[curproc].interrupted);
        RETURN (pp^.g <= highestdf) AND (pp^.g <> dft[0]);
      END ResidentExecuted;


      PROCEDURE Kill;
        (* Should only be called from a driver process *)
        VAR pp: ProcessPointer;
      BEGIN
        WITH iv[curproc] DO
          son := interrupted;
          pp := ProcessPointer(son);
          killstatus := pp^.cause; 
          IF NOT (killstatus IN StatusSet{normal, warned}) THEN
            DiskReset; Dump
          END;
          IF (activeprog = 0) OR
             ResidentExecuted() AND NOT terminating AND
             (killstatus IN StatusSet{instructionerr..functionerr})
          THEN
            LOOP END (* should never happen *)
          END;
          stoping := FALSE;
          terminating := FALSE;
          interrupted := father;
        END;
      END Kill; 


      PROCEDURE Terminate(st: Status);
        (* Should only be called from a user program *)
      BEGIN 
        IF st > callerr THEN st := callerr END;
        terminating := TRUE;
        Trap(st);
      END Terminate;


      PROCEDURE CheckStop;

        VAR
          pp: ProcessPointer;
          p: PROCESS;

      BEGIN
        IF stoping THEN
          IF activeprog = 0 THEN stoping := FALSE
          ELSIF curproc = user THEN
            stoping := FALSE; Terminate(stopped)
          ELSIF NOT ResidentExecuted() THEN
            WITH iv[curproc] DO
              pp := ProcessPointer(interrupted);
              WITH pp^ DO
                IF NOT (stopped IN trapdisable) THEN
                  stoping := FALSE;
                  cause := stopped;
                  p := interrupted;
                  interrupted := iv[cpudev].driver;
                  iv[cpudev].interrupted := p;
                END;
              END;
            END;
          END;
        END;
      END CheckStop;


      PROCEDURE Stop;
      BEGIN
        stoping := TRUE;
        CheckStop
      END Stop;


    BEGIN
      curproc := user;      (* current process is the user process *)
      terminating := FALSE; (* we are not terminating just now *)
      stoping := FALSE;     (* we are not trying to stop a level *) 
      activeprog := 0;      (* currently running level *)
      highestdf := dft[residentmodules-1];
      level0mask := {0..15};
    END PrioScheduler;


    PROCEDURE Call(VAR p: PROCESS; shared: BOOLEAN; VAR st: Status);
      VAR mytermtop, c: CARDINAL;
    BEGIN
      IF curprog < maxprog THEN
        mytermtop := termtop;
        IF shared THEN
          sharedprog[curprog+1] := sharedprog[curprog]
        ELSE sharedprog[curprog+1] := curprog+1;
        END;
        INC(curprog);
        PrioCall(p, st);
        termtop := mytermtop;
        WHILE curprog > activeprog DO
          c := termtop;
          WHILE c > 0 DO
            DEC(c); termtab[c];
          END;
          DEC(curprog);
        END;
      ELSE st := callerr
      END;
    END Call;


    PROCEDURE CurrentLevel(): CARDINAL;
    BEGIN
      RETURN curprog 
    END CurrentLevel;


    PROCEDURE SharedLevel(): CARDINAL;
    BEGIN
      RETURN sharedprog[curprog]
    END SharedLevel;


    PROCEDURE TermProcedure(t: PROC);
    BEGIN
      IF termtop > maxtermtab THEN HALT END;
      termtab[termtop] := t; INC(termtop);
    END TermProcedure;
 
 
  BEGIN
    curprog := 0;       (* current programlevel is 0 *)
    sharedprog[0] := 0; (* shared level of main program = 0 *)
    termtop := 0;       (* top of termtab *)
  END Scheduler; 


  MODULE Timer[15]; 

    IMPORT Time; 

    EXPORT SetTime, GetTime, TickTime;  

    VAR 
      tim: Time; 


    PROCEDURE Days(y, m: CARDINAL): CARDINAL;
    BEGIN
      IF m < 8 THEN
        IF ODD(m) THEN RETURN 31
        ELSIF m = 2 THEN
          IF y MOD 4 = 0 THEN RETURN 29 ELSE RETURN 28 END;
        ELSE RETURN 30
        END
      ELSIF ODD(m) THEN RETURN 30
      ELSE RETURN 31
      END
    END Days;

 
    PROCEDURE TickTime; 

      CONST tickperiod = 20; (* msec *)
 
      VAR y, m, d: CARDINAL;
 
    BEGIN
      WITH tim DO 
        INC(millisecond, tickperiod);  
        IF millisecond >= 60000 THEN 
          DEC(millisecond, 60000); INC(minute);
          IF minute >= 1440 THEN 
            DEC(minute, 1440); 
            IF day <> 0 THEN 
              y := day DIV 1000B; 
              m := day DIV 40B MOD 20B; 
              d := day MOD 40B; 
              INC(d); 
              IF d > Days(y, m) THEN 
                d := 1; INC(m);
                IF m > 12 THEN 
                  m := 1; y := (y+1) MOD 200B; 
                END 
              END;
              day := (y * 20B + m) * 40B + d; 
            END 
          END 
        END 
      END 
    END TickTime; 


    PROCEDURE SetTime(t: Time); 

      VAR y, m, d: CARDINAL;
 
    BEGIN 
      WITH t DO 
        y := day DIV 1000B; 
        m := day DIV 40B MOD 20B;  
        d := day MOD 40B; 
        IF (d > 0) AND (m > 0) AND (m <=12) AND (d <= Days(y, m)) AND
           (minute < 1440) AND (millisecond < 60000) 
        THEN
          tim := t 
        END 
      END 
    END SetTime; 

     
    PROCEDURE GetTime(VAR t: Time);
    BEGIN 
      t := tim;
    END GetTime; 


  BEGIN 
    WITH tim DO  
      day := 0;  
      minute := 0; 
      millisecond := 0; 
    END; 
  END Timer; 


  MODULE Keyboard;

    FROM SYSTEM IMPORT WORD;
    FROM Scheduler IMPORT Stop, CheckStop; 
    IMPORT Status, Terminate; 
 
    EXPORT Read, CheckKeyboard; 

    CONST 
      kbsreg = 1; kbdreg = 2; 
      bufsize = 128; 
      escchar = 3C; 

    VAR 
      buf: ARRAY [1..bufsize] OF CHAR;
      ix, ox: [0..bufsize];


    PROCEDURE Read(VAR ch: CHAR);
    BEGIN
      CheckStop;
      IF ix = ox THEN ch := 0C;
      ELSE ch := buf[ox]; ox := ox MOD bufsize + 1;
        IF ch = 15C THEN ch := 36C
        ELSIF ch = 36C THEN ch := 15C
        END;
      END;
    END Read;
     

    PROCEDURE CheckKeyboard;

      CONST readw = 240B;

      VAR
        kbs: BITSET; 
        ch: CHAR; 
        newix: [0..bufsize]; 

      PROCEDURE Get(channel: CARDINAL; VAR w: WORD);
      CODE readw
      END Get;

    BEGIN
      Get(kbsreg, kbs); 
      IF 15 IN kbs THEN 
        Get(kbdreg, ch); 
        IF ch = escchar THEN 
          ox := ix; Stop;
        ELSIF ch <> 0C THEN
          newix := ix MOD bufsize + 1;  
          IF newix <> ox THEN buf[ix] := ch; ix := newix END; 
        END 
      END;
    END CheckKeyboard;

   
  BEGIN
    ix := 1; ox := 1;
  END Keyboard;


  MODULE Clock[15];

    FROM SYSTEM IMPORT
      PROCESS, NEWPROCESS, WORD, ADR; 
    FROM Scheduler IMPORT
      Create, WaitInterrupt, CheckStop, clkdev; 
    FROM Timer IMPORT TickTime; 
    FROM Keyboard IMPORT CheckKeyboard; 
     
    CONST
      processsize = 100;
      writew      = 241B;
 
    VAR 
      area: ARRAY [1..processsize] OF WORD; 
      p: PROCESS; 
 
    PROCEDURE ClockDriver;

      PROCEDURE Put(channel: CARDINAL; c: CARDINAL);
      CODE writew
      END Put;

    BEGIN 
      LOOP 
        WaitInterrupt;
        Put(3, 0);
        CheckStop; 
        TickTime; 
        CheckKeyboard; 
      END 
    END ClockDriver; 
 
 
  BEGIN
    NEWPROCESS(ClockDriver, ADR(area), processsize, p); 
    Create(clkdev, p); 
  END Clock;


  MODULE TrapHandler[15];

    FROM SYSTEM IMPORT
      PROCESS, NEWPROCESS, WORD, ADR;
    FROM Scheduler IMPORT
      Create, cpudev, Kill, WaitInterrupt; 
 
    CONST processsize = 100;
 
    VAR
      area: ARRAY [1..processsize] OF WORD;
      p: PROCESS;
 
    PROCEDURE CPUDriver; 
    BEGIN 
      LOOP 
        WaitInterrupt;
        Kill
      END 
    END CPUDriver; 
 

  BEGIN
    NEWPROCESS(CPUDriver, ADR(area), processsize, p); 
    Create(cpudev, p);   
  END TrapHandler;


END Monitor.

