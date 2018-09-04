IMPLEMENTATION MODULE System;  (* Ch. Jacobi 23.10.79 *)
                               (* modified   25.9.80 to prototype 5 instructions *)

  (* modiffied by SEK: *)
  (* 12.10.80  semantic nonsens in ROUND and FLOAT. *)
  (* 12.10.80  syntax errors in ROUND and FLOAT:
               the compiler canot scan REAL constants. *)
  (* 17.10.80  ROUND and FLOAT corrected to work properly. *)
  (* 18.10.80  ROUND and FLOAT speed up *)
  (* 18.10.80  ROUND and FLOAT ===> TRAP(illegal instruction *)
  (* 20.10.80  CFLOAT and CFIX ===> Programmed in MODULA-2 *)
  (* 31.10.80  CARDINAL and INTEGER traps changable by overwriting word 15B *)
  (* 25.11.80  CFLOAT and CFIX ===> macro code with changed no's *)
  (* 01.04.81  NEWPROCESS enables traps unconditionally *)
  (* 26.05.81  CROUND AMD CFLOAT removed *)
  (* 26.05.81  Traps unconditonally enabled in NEWPROCESS *)
  (* 26.05.81  Number of resident modules in word 13D *)
  (* 26.05.81  H-register set according to size of memory *)
  (* 26.05.81  NEWPROCESS fixed to enable code to reside anywhere *)
  (* 01.06.82  Remove the setting of the H-register according to the memory size *)

  (* Implements the procedure NEWPROCESS
     which is in the standard module SYSTEM.

     This module must be module 0;                       (1,2)
     procedure EndProcess must have procedure number 1;  (2)
     procedure NEWPROCESS must have procedure number 2;  (2)

     reasons: 1: Used internally as constants
              2: Used as constants by the compiler

     The definition module is used to garantie the correct
     procedure numbers.

     NewProcess gives the new process the same interrupt mask
       as the calling procedure has.
       Prepare a call of EndProcess at end of coroutine.      *)

 
 
  FROM SYSTEM IMPORT ADR, ADDRESS, PROCESS, TRANSFER, TSIZE;

  TYPE ProcessMarkType =
          RECORD 
            pd: ProcessDescriptor;
            startProc: PROC;
            returnMark: ProcedureMark;
            emptyStackSize: CARDINAL;
          END;

       AddressOfProcessType = POINTER TO ProcessMarkType;

  CONST reserve     = 24;
        lxfw      = 203B;
        TRAP      = 304B;
        LLW       =  40B;
        end         =  0;  (*end*)
        storageChk  =  3;  (*storage overflow*)
        

  PROCEDURE LXFW(fp, offset: CARDINAL): CARDINAL;
  CODE lxfw
  END LXFW;

  PROCEDURE Service(errCode: CARDINAL);
    (* traps if trapvector is initialized, else loops in micro code*)
  CODE TRAP     
  END Service;

  PROCEDURE EndProcess;
    (* A call of this procedure is prepared by NEWPROCESS for
       the case a coroutine ends. 
       - No local variables: the "L"-register has value 0 !!!!! *)
  BEGIN
    Service(end) (* there is no return from service *)
  END EndProcess;

  PROCEDURE NewProcess(P: PROC; a: ADDRESS; size: CARDINAL;
                       VAR P1: PROCESS);

   VAR processPointer: AddressOfProcessType;    
       modNum,procNum: CARDINAL;
       ptr: ADDRESS;
       frame: CARDINAL;

  BEGIN
    IF (size<=reserve+TSIZE(ProcessMarkType))OR(a>177777B-size) THEN
      Service(storageChk) (*storage overflow*) 
    END;
    processPointer := AddressOfProcessType(a);
    modNum  := CARDINAL(P) DIV 400B;
    procNum := CARDINAL(P) MOD 400B;
    WITH processPointer^ DO

       pd.mark.g     := dataFrameTable[modNum];
       pd.mark.l     := CARDINAL(ADR(returnMark));
       frame         := CARDINAL(pd.mark.g^) DIV 2;
       pd.mark.pc    := LXFW(frame, procNum + 2*(CARDINAL(pd.mark.g^) - 2*frame));
       pd.mark.msk   := GetMask();  

       pd.h          := a+size;
       pd.trapMask   := {};  (* enable all traps anyway*)
       pd.errCode    := 0;
       pd.s          := CARDINAL(ADR(emptyStackSize)+1);

       startProc := P; (*for the debugger*)

       ptr := dataFrameTable[0];
       frame := CARDINAL(ptr^) DIV 2;  
       returnMark.pc := LXFW(frame, 2*(CARDINAL(ptr^)-2*frame) + CARDINAL(EndProcess))
                       + 100000B;   (*external flag*)
       returnMark.l  := 0;  (*used as end mark of procedure stack*)
       returnMark.g  := 0;  (*this module*)
       returnMark.msk:= {}; 

       emptyStackSize := 0;

    END;
    P1 := PROCESS(a);                       
  END NewProcess;

  MODULE Prio15[15];             (*must be 15, such that >= is gaaranteed*)
    IMPORT LLW;
    EXPORT GetMask;
    
    PROCEDURE GetMask(): BITSET; (*because of priority this is NOT inline*)
    CODE
      LLW; 3 
    END GetMask;

  END Prio15;

 
BEGIN
  residentModules := loadedModules;
  userProgram;         
  EndProcess;     
END System.
