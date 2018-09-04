(*******************************************************************************
AAAAAAAA         Asssembler for one Micro-Instruction / Part of         AAAAAAAA
AAAAAAAA         MIA / Version 19 / 20.07.81 / G. Schild                AAAAAAAA
*******************************************************************************)

IMPLEMENTATION MODULE Assembler;

FROM BinFile    IMPORT Store, Update, Code, mcmSize;
FROM TextIO     IMPORT Print, PrintChar, PutHex,
                       SkipPage, Error, ErrorList, lineSize;
FROM Labels     IMPORT InsertLab, FixLab, SetLocalChar, Label, Response;
FROM MapHandler IMPORT EnterMap, mapSize;

CONST origin         = ".ORG";
      mapSymbol      = ".MAP";
      noOperation    = ".NOP";
      tMinus         = ".$T-";
      tPlus          = ".$T+";
      lMinus         = ".$L-";
      lPlus          = ".$L+";
      lStar          = ".$L*";
      null           = "0   ";
      one            = "1   ";
      commentPoint   = ".   ";
      commentAsterik = "*   ";
      commentDollar  = "$   ";
      slow           = "S   ";
      nothing        = " -  ";
      minus          = "-   ";
      equals         = "=   ";
      blanks         = "    ";
      comma          = ",";

TYPE  Alfa          = ARRAY [0..3] OF CHAR;
      DestinTyp     = (LQ,L,LBA,LB,LBQ2,LB2,L2BQ,L2B);
      FctTyp        = (add,subr,subs,logor,logand,notand,xor,notxor);
      SourceTyp     = (AQ,AB,ZQ,ZB,ZA,DA,DQ,DZ);
      CarryTyp      = (C,NC,One,Zero);
      PortTyps      = (R0,R1,R2,R3,R4,R5,R6,R7,R10,R11,R12,R13,R14,R15,R16,R17,
                      dontcare,RM,RP,RH,RS,RG,RL,RT);
      PortTyp       = [R0..dontcare];
      ShiftTyps     = (rotcnt,maskcnt,rotreg,maskreg,nosh);
      ShiftTyp      = [rotcnt..maskreg];
      ProgTyp       = (clrloop,return,reg1,call,cont,loop,reg2,jump);
      BusDestinTyp  = (ALUdst,MDdst,PCdst,MARdst,SCRdst,MDSTdst,IOAdst,IODdst,INMdst,
                      dst11,dst12,dst13,dst14,BNKdst,Fdst,NULdst);
      BusSourceTyp  = (ALUsrc,MDsrc,PCsrc,IR4src,IR8src,IR8Msrc,IRSsrc,IODsrc,INMsrc,
                      src11,src12,src13,src14,src15,Fsrc,NULsrc);
      CondCodRegTyp = (reql,carry,zero,over,firstbit,sign,bit8,stkem);
      CondCodTyp    = SET OF CondCodRegTyp;
      Instr    = RECORD
                   loadAdr : CARDINAL;              (* mcm-addres of instruction *)
                   pg : ProgTyp;                              (* program control *)
                   speed : BOOLEAN;                               (* micro clock *)
                   CASE regular : BOOLEAN OF
                        TRUE : dst  : DestinTyp;              (* alu destination *)
                               fct  : FctTyp;                    (* alu function *)
                               rs   : SourceTyp;                   (* alu source *)
                               ca   : CarryTyp;                 (* carry control *)
                               a,b  : PortTyp;                 (* port addresses *)
                               sh   : ShiftTyp;                 (* shift control *)
                               st   : BOOLEAN;                  (* stack control *)
                               scnt : [0..0FH];                   (* shift count *)
                               CASE E : BOOLEAN OF
                                    TRUE : n:CARDINAL                (* constant *)
                                         |
                                    FALSE: bd : BusDestinTyp; (* bus destination *)
                                           bs : BusSourceTyp;      (* bus source *)
                                    END
                                   |
                        FALSE : pa : CARDINAL;                (* program address *)
                                p  : BOOLEAN;                (* polarity of jump *)
                                cc : CondCodTyp           (* condition code mask *)
                        END
                    END;

VAR destinTab    : ARRAY DestinTyp OF Alfa;
    fctTab       : ARRAY FctTyp OF Alfa;
    sourceTab    : ARRAY SourceTyp OF Alfa;
    carryTab     : ARRAY CarryTyp OF Alfa;
    portTab      : ARRAY PortTyps OF Alfa;
    shiftTab     : ARRAY ShiftTyps OF Alfa;
    progTab      : ARRAY ProgTyp OF Alfa;
    busDestinTab : ARRAY BusDestinTyp OF Alfa;
    busSourceTab : ARRAY BusSourceTyp OF Alfa;
    registerName : ARRAY PortTyp OF CHAR;
    teston       : BOOLEAN;
    r, qreg      : PortTyp;
    mcmAddress   : CARDINAL;
    answer       : Response;


PROCEDURE Equal(l1,l2:Alfa):BOOLEAN;
VAR n : CARDINAL;
BEGIN
FOR n := 0 TO 3 DO IF l1[n] <> l2[n] THEN RETURN FALSE END END;
RETURN TRUE
END Equal;

PROCEDURE GenCode(i:Instr);
VAR c:Code;
BEGIN
WITH i DO
  IF regular 
  THEN
    c[0] := ORD(dst) * 20h + ORD(fct) * 4 + ORD(rs) DIV 2;
    c[1] := (ORD(rs) MOD 2) * 80h + ORD(ca) * 20h
            + (ORD(a) MOD 10h) * 2 + (ORD(b) MOD 10h) DIV 8;
    c[2] := (ORD(b) MOD 8) * 20h + ORD(sh) * 8 + ORD(pg);
    c[3] := ORD(speed) * 80h + 40h (*reg*) + (1-ORD(st))  * 20h + ORD(E) *10h + scnt;
    IF E THEN c[4] := n ELSE c[4] := ORD(bd) * 10h + ORD(bs) END
  ELSE
    c[0] := pa DIV 10h;
    c[1] := (pa MOD 10h) * 10h + (1-ORD(p)) * 8 + ORD(reql IN cc) * 4 + 
            ORD(carry IN cc) * 2 + ORD(zero IN cc);
    c[2] := ORD(over IN cc) * 80h +ORD(firstbit IN cc) * 40h + ORD(sign IN cc) * 20h +
            ORD(bit8 IN cc) * 10h +ORD(stkem IN cc) * 8 + ORD(pg); 
    c[3] := ORD(speed) * 80h + 20h (* stack disable *);
    c[4] := 0Fh    (* for practical purpose *)
  END;
  Store(c,loadAdr)
  END
END GenCode;

PROCEDURE GetAnInstr(line:ARRAY OF CHAR);
VAR actuelInstr : Instr;
    outputLine  : ARRAY [0..lineSize] OF CHAR;
    registerUsed: ARRAY PortTyp OF BOOLEAN;
    noError     : BOOLEAN;
    labelIdent  : Label;
    symbol      : Alfa;
    ch          : CHAR;
    linePos,startPos,i,j,endPos:CARDINAL;

  PROCEDURE Scan;
  BEGIN
  i := linePos;
  WHILE line[i] = " " DO INC(i) END;
  ch := line[i]
  END Scan;

  PROCEDURE GetLabel;
  BEGIN
  FOR i := 0 TO 9 DO labelIdent[i] := " " END;
  WHILE line[linePos] = " " DO INC(linePos) END;
  IF line[linePos] = 0C THEN Error(21,startPos); RETURN END;
  startPos := linePos+5;
  i := 0;
    LOOP
    IF (line[linePos]=' ') OR (line[linePos] = 0C) THEN EXIT END;
    IF i = 10 THEN Error(22,startPos) END;
    IF i < 10 THEN labelIdent[i] := line[linePos] END;
    INC(linePos);
    INC(i)
    END;
  END GetLabel;

  PROCEDURE GetAlfa;
  BEGIN
  FOR i := 0 TO 3 DO symbol[i] := " " END;
  WHILE line[linePos] = " " DO INC(linePos) END;
  IF line[linePos] = 0C THEN Error(21,startPos); RETURN END;
  startPos := linePos+5;
  i := 0;
    LOOP
    IF (line[linePos] = " ") OR (line[linePos] = 0C) THEN EXIT END;
    IF i = 4 THEN Error(22,startPos) END;
    IF i < 4 THEN symbol[i] := line[linePos] END;
    INC(linePos);
    INC(i)
    END
  END GetAlfa;

  PROCEDURE GetChar;
  BEGIN
    LOOP
    IF line[linePos] <> " " THEN EXIT END;
    INC(linePos)
    END;
  startPos := linePos+5;
  ch := line[linePos];
  INC(linePos)
  END GetChar;

  PROCEDURE GetOctal(VAR n:CARDINAL);
  BEGIN
  WHILE line[linePos] = " " DO INC(linePos) END;
  startPos := linePos+5;
  n := 0;
    LOOP
    IF (line[linePos] = " ") OR (line[linePos] = comma)
       OR (line[linePos] = 0C) THEN EXIT
    ELSIF (line[linePos] >= "0") AND (line[linePos] <= "7")
      THEN n := n*8 + ORD(line[linePos]) - ORD("0")
    ELSE Error(23,startPos)
    END;
    INC(linePos)
    END;
  END GetOctal;

  PROCEDURE GetPort(VAR p:PortTyp);
  VAR pp : PortTyps;
  BEGIN
  Scan;
  IF (ORD(ch) < ORD("8")) AND (ORD(ch) > 2Fh)
  THEN GetOctal(j);
    IF j > 17B THEN Error(6,i+5); RETURN END;
    p := R0;
    FOR j := 1 TO j DO INC(p) END;
  ELSE GetAlfa;
    IF Equal(symbol,minus) THEN p := dontcare; RETURN END;
    pp := RM;
    p := R11;
    LOOP
    IF Equal(symbol,portTab[pp]) THEN EXIT END;
    IF pp = RT THEN Error(6,startPos); EXIT END;
    INC(p); INC(pp)
    END
  END;
  registerUsed[p] := TRUE
  END GetPort;

  PROCEDURE GetProg(VAR pc:ProgTyp);
  BEGIN
  GetAlfa;
  pc := clrloop;
    LOOP
    IF Equal(symbol,progTab[pc]) THEN EXIT END;
    IF pc = jump THEN Error(9,startPos); EXIT END;
    INC(pc)
    END
  END GetProg;

  PROCEDURE RegularInstr;
  VAR sc  : ShiftTyps;
      lma : ARRAY [0..3] OF CHAR;
      i   : CARDINAL;
  BEGIN
    WITH actuelInstr DO
    loadAdr := mcmAddress;
    PutHex(loadAdr,lma);
    FOR i := 0 TO 3 DO outputLine[i] := lma[i] END;
    regular := TRUE;

    GetAlfa;                                                         (* destination *)
    dst := LQ;
      LOOP
      IF Equal(symbol,destinTab[dst]) THEN EXIT END;
      IF dst = L2B THEN Error(2,startPos); EXIT END;
      INC(dst)
      END;
    IF (dst = LQ) OR (dst = LBQ2) OR (dst = L2BQ)
    THEN registerUsed[qreg] := TRUE END;

    GetAlfa;                                                            (* function *)
    fct := add;
      LOOP
      IF Equal(symbol,fctTab[fct]) THEN EXIT END;
      IF fct = notxor THEN Error(3,startPos); EXIT END;
      INC(fct)
      END;

    GetAlfa;                                                              (* source *)
    rs := AQ;
      LOOP
      IF Equal(symbol,sourceTab[rs]) THEN EXIT END;
      IF rs = DZ THEN Error(4,startPos); EXIT END;
      INC(rs)
      END;
    IF (rs = AQ) OR (rs = ZQ) OR (rs = DQ)
    THEN registerUsed[qreg] := TRUE END;

    GetAlfa;                                                               (* carry *)
    ca := C;
      LOOP
      IF Equal(symbol,carryTab[ca]) THEN EXIT END;
      IF ca = Zero THEN Error(5,startPos); EXIT END;
      INC(ca)
      END;

    GetPort(a);                                                            (* ports *)
    IF (teston) AND ((a = dontcare) =
      ((dst = LBA) OR (rs = AQ) OR (rs = AB) OR (rs = ZA) OR (rs = DA)))
    THEN Error(30,startPos) END;
    GetPort(b);
    IF (teston) AND 
       ((b = dontcare) = (NOT(dst = LQ) AND NOT(dst = L) OR (rs = AB) OR (rs = ZB)))
    THEN Error(30,startPos) END;

    GetAlfa;                                                       (* shift control *)
    sc := rotcnt;
      LOOP
      IF Equal(symbol,shiftTab[sc]) THEN EXIT END;
      IF sc = nosh THEN Error(7,startPos); EXIT END;
      INC(sc)
      END;
    IF sc = nosh THEN sh := maskcnt ELSE sh := sc END;

    Scan;                                                           (* shift count *)
      IF (ch >= "0") AND (ch <= "7")
      THEN GetOctal(j);
        IF j > 17B
        THEN Error(10,startPos)
        ELSE scnt := j
        END
      ELSE GetAlfa;
        IF Equal(symbol,minus)
        THEN IF (sc = rotcnt) OR (sc = maskcnt)
          THEN Error(29,startPos)
          ELSE scnt := 0 
          END
        ELSE Error(10,startPos)
        END
      END;

    GetAlfa;                                                               (* speed *)
    IF Equal(symbol,slow) THEN speed := TRUE
    ELSIF Equal(symbol,minus) THEN speed := FALSE
    ELSE Error(33,startPos)
    END;

    GetProg(pg);                                                 (* program control *)
    IF pg = call THEN Error(20,startPos) END;

    GetAlfa;                                                               (* stack *)
    IF Equal(symbol,"S   ") THEN st := TRUE
    ELSIF Equal(symbol,minus) THEN st := FALSE
    ELSE Error(8,startPos)
    END;

    GetAlfa;                                                  (* constant enable bit*)
      IF Equal(symbol,one)
      THEN E := TRUE;                                                   (* constant *)
        GetOctal(n);
        IF n > 377B THEN Error(24,startPos) END;
          IF teston AND (rs <> DA) AND (rs <> DQ) AND (rs <> DZ)
          THEN Error(30,startPos)
          END;
      ELSIF Equal(symbol,null)
        THEN E := FALSE;                                         (* bus destination *)
        GetAlfa;
        IF Equal(symbol,"POP ")
        THEN bd := NULdst;
          IF teston
          THEN IF NOT st THEN Error(31,startPos)  END;
               IF (rs <> DA) AND (rs <> DQ) AND (rs <> DZ) THEN Error(4,startPos)  END
          END
        ELSIF Equal(symbol,"PSH ")
        THEN bd := ALUdst;
          IF teston
          THEN IF NOT st THEN Error(31,startPos)  END;
               IF (rs = DA) OR (rs = DQ) OR (rs = DZ) THEN Error(4,startPos)  END
          END
        ELSE bd := ALUdst;
          LOOP
          IF Equal(symbol,busDestinTab[bd]) THEN EXIT END;
          IF bd = NULdst THEN Error(15,startPos); EXIT END;
          INC(bd)
          END;
          IF (teston) AND (((bd = ALUdst) OR (st)) <>
             ((rs = DA) OR (rs = DQ) OR (rs = DZ)))
          THEN Error(4,startPos)
          END
        END;
      GetAlfa;                                                        (* bus source *)
      bs := ALUsrc;
        LOOP
        IF Equal(symbol,busSourceTab[bs]) THEN EXIT END;
        IF bs = NULsrc THEN Error(16,startPos); EXIT END;
        INC(bs)
        END;        
      ELSE Error(1,startPos)
      END

    END; (* WITH actuelInstr *)
  linePos := lineSize-4;
    FOR r := R0 TO dontcare DO 
    IF registerUsed[r]
    THEN outputLine[linePos] := registerName[r]; INC(linePos,2)
    END
    END;
  IF noError THEN GenCode(actuelInstr) END;
  INC(mcmAddress)
  END RegularInstr;

  PROCEDURE JumpInstr;
  VAR cr  : CondCodRegTyp;
      lma : ARRAY [0..3] OF CHAR;
      i   : CARDINAL;
  BEGIN
    WITH actuelInstr DO
    loadAdr := mcmAddress;
    PutHex(loadAdr,lma);
    FOR i := 0 TO 3 DO outputLine[i] := lma[i] END;
    regular := FALSE;

    Scan;                                                        (* program address *)
      IF (ch >= "0") AND (ch <= "7")
      THEN GetOctal(pa);
      IF pa > mcmSize THEN Error(27,startPos) END
      ELSE GetLabel;
      pa := FixLab(labelIdent,mcmAddress)
      END;

    GetChar;                                                      (* condition code *)
    cc := CondCodTyp{};
      IF ch = "T"
      THEN p := FALSE
      ELSE 
        IF ch = "-"
        THEN p := FALSE;
        ch := line[linePos];
        INC(linePos)
        ELSE p := TRUE
        END;
        LOOP
        IF ch = " " THEN EXIT
        ELSIF ch = "R" THEN INCL(cc,reql)
        ELSIF ch = "C" THEN INCL(cc,carry)
        ELSIF ch = "Z" THEN INCL(cc,zero)
        ELSIF ch = "V" THEN INCL(cc,over)
        ELSIF ch = "F" THEN INCL(cc,firstbit)
        ELSIF ch = "S" THEN INCL(cc,sign)
        ELSIF ch = "H" THEN INCL(cc,bit8)
        ELSIF ch = "E" THEN INCL(cc,stkem)
        ELSE Error(19,startPos) END;
        ch := line[linePos];
        INC(linePos)
        END
      END;

    GetAlfa;                                                              (* speed *)
      IF Equal(symbol,slow) THEN speed := TRUE
      ELSIF Equal(symbol,minus) THEN speed := FALSE
      ELSE Error(33,startPos)
      END;

    GetProg(pg)                                                 (* program control *)

    END;
  outputLine[endPos] := 0C;
  IF noError THEN GenCode(actuelInstr) END;
  INC(mcmAddress);
  END JumpInstr;

  PROCEDURE PseudoInstr(select:CHAR);
  BEGIN
    CASE select OF
    "." : GetAlfa;
          IF Equal(symbol,origin) THEN GetOctal(j);                        (* .ORG *)
                                       IF j < mcmSize 
                                       THEN mcmAddress := j
                                       ELSE Error(28,startPos)
                                       END
          ELSIF Equal(symbol,noOperation) THEN Update(0,mcmAddress);       (* .NOP *)
                                               INC(mcmAddress)
          ELSIF Equal(symbol,mapSymbol) THEN LOOP                          (* .MAP *)
                                             GetOctal(j);
                                               IF j <= mapSize
                                               THEN EnterMap(mcmAddress,j)
                                               ELSE Error(25,startPos)
                                               END;
                                             GetChar;
                                             IF ch <> comma THEN EXIT END
                                             END
          ELSIF Equal(symbol,tPlus) THEN teston := TRUE                    (* .$T+ *)
          ELSIF Equal(symbol,tMinus) THEN teston := FALSE                  (* .$T- *)
          ELSIF Equal(symbol,lPlus) THEN GetAlfa;                          (* .$L+ *)
                                         SetLocalChar(symbol[0],TRUE,answer);
                                            IF answer = warning
                                            THEN Error(18,startPos)
                                            END
          ELSIF Equal(symbol,lStar) THEN GetAlfa;                          (* .$L* *)
                                         SetLocalChar(symbol[0],FALSE,answer);
                                            IF answer = warning
                                            THEN Error(18,startPos)
                                            END
          ELSIF Equal(symbol,lMinus) THEN SetLocalChar(" ",TRUE,answer);   (* .$L- *)
                                             IF answer = warning
                                             THEN Error(18,startPos)
                                             END
          ELSIF Equal(symbol,commentPoint) THEN                         (* comment *)
          ELSE Error(32,startPos)
          END
        |
    "*" : GetAlfa;                                                      (* comment *)
          IF NOT Equal(symbol,commentAsterik) THEN Error(32,startPos) END
        |
    "$" : GetAlfa;                                          (* comment - skip page *)
          IF Equal(symbol,commentDollar)
          THEN SkipPage
          ELSE Error(32,startPos)
          END
        |
    "=" : GetAlfa;                                               (* external label *)
          IF NOT Equal(symbol,equals) THEN Error(32,startPos) END;
          GetOctal(j);
          InsertLab(labelIdent,j,answer);
            CASE answer OF
            twice    : Error(26,startPos)
                     |
            overflow : Error(27,startPos)
                     |
            warning  : Error(18,startPos)
            ELSE
            END
    ELSE RETURN                                                     (* empty line *)
    END;
  outputLine[endPos] := 0C
  END PseudoInstr;

BEGIN (* GetAnInstr *)
noError := TRUE;
linePos := 0;
startPos := 0;
FOR i := 0 TO 4 DO outputLine[i] := " " END;
i := 0;
  LOOP
  outputLine[i+5] := line[i];
  INC(i);
  IF (i = 80) OR (line[i] = 0C) THEN EXIT END;
  END;
endPos := i+5;
FOR i := i+5 TO lineSize DO outputLine[i] := " " END;
FOR r := R0 TO qreg DO registerUsed[r] := FALSE END;
Scan;
  CASE ch OF
  "0" : GetAlfa;
        IF Equal(symbol,null)
        THEN JumpInstr
        ELSE Error(1,startPos)
        END
      |
  "1" : GetAlfa;
        IF Equal(symbol,one)
        THEN RegularInstr
        ELSE Error(1,startPos)
        END|
  "." : PseudoInstr(ch)
      |
  "*" : PseudoInstr(ch)
      |
  "$" : PseudoInstr(ch)
      |
  0C  : PseudoInstr(ch)
  ELSE
    GetLabel;
    Scan;
      CASE ch OF
      "0" : InsertLab(labelIdent,mcmAddress,answer);
            CASE answer OF
            twice    : Error(26,startPos)
                     |
            overflow : Error(27,startPos)
                     |
            warning  : Error(18,startPos)
            ELSE
            END;
            GetAlfa;
            IF Equal(symbol,null)
            THEN JumpInstr
            ELSE Error(1,startPos)
            END
          |
      "1" :InsertLab(labelIdent,mcmAddress,answer);
            CASE answer OF
            twice    : Error(26,startPos)
                     |
            overflow : Error(27,startPos)
                     |
            warning  : Error(18,startPos)
            ELSE
            END;
            GetAlfa;
            IF Equal(symbol,one)
            THEN RegularInstr
            ELSE Error(1,startPos)
            END
          | 
      "=" : PseudoInstr(ch)
      ELSE Error(1,linePos+6)
      END
  END;
Print(outputLine);
ErrorList;
END GetAnInstr;

BEGIN
destinTab[LQ]          := "Q   ";
destinTab[L]           := minus;
destinTab[LBA]         := "B*  ";
destinTab[LB]          := "B   ";
destinTab[LBQ2]        := "BQR ";
destinTab[LB2]         := "BR  ";
destinTab[L2BQ]        := "BQL ";
destinTab[L2B]         := "BL  ";
fctTab[add]            := "+   ";
fctTab[subr]           := "-+  ";
fctTab[subs]           := minus;
fctTab[logor]          := "OR  ";
fctTab[logand]         := "&   ";
fctTab[notand]         := "-&  ";
fctTab[xor]            := "XOR ";
fctTab[notxor]         := "-XR ";
sourceTab[AQ]          := "AQ  ";
sourceTab[AB]          := "AB  ";
sourceTab[ZQ]          := "ZQ  ";
sourceTab[ZB]          := "ZB  ";
sourceTab[ZA]          := "ZA  ";
sourceTab[DA]          := "DA  ";
sourceTab[DQ]          := "DQ  ";
sourceTab[DZ]          := "DZ  ";
carryTab[C]            := "C   ";
carryTab[NC]           := "-C  ";
carryTab[One]          := one;
carryTab[Zero]         := null;
portTab[R0]            := null;
portTab[R1]            := "1   ";
portTab[R2]            := "2   ";
portTab[R3]            := "3   ";
portTab[R4]            := "4   ";
portTab[R5]            := "5   ";
portTab[R6]            := "6   ";
portTab[R7]            := "7   ";
portTab[R10]           := "10  ";
portTab[R11]           := "11  ";
portTab[R12]           := "12  ";
portTab[R13]           := "13  ";
portTab[R14]           := "14  ";
portTab[R15]           := "15  ";
portTab[R16]           := "16  ";
portTab[R17]           := "17  ";
portTab[RM]            := "M   ";
portTab[RP]            := "P   ";
portTab[RH]            := "H   ";
portTab[RS]            := "S   ";
portTab[RG]            := "G   ";
portTab[RL]            := "L   ";
portTab[RT]            := "T   ";
shiftTab[rotcnt]       := "R   ";
shiftTab[maskcnt]      := "M   ";
shiftTab[rotreg]       := "RR  ";
shiftTab[maskreg]      := "MR  ";
shiftTab[nosh]         := minus;
progTab[clrloop]       := "POP ";
progTab[return]        := "RTN ";
progTab[reg1]          := nothing;
progTab[call]          := "JSR ";
progTab[cont]          := minus;
progTab[loop]          := "LOP ";
progTab[reg2]          := nothing;
progTab[jump]          := "JMP ";
busDestinTab[ALUdst]   := "ALU ";
busDestinTab[MDdst]    := "MD  ";
busDestinTab[PCdst]    := "PC  ";
busDestinTab[MARdst]   := "MAR ";
busDestinTab[SCRdst]   := "SR  ";
busDestinTab[MDSTdst]  := "MDS ";
busDestinTab[IOAdst]   := "IOA ";
busDestinTab[IODdst]   := "IOD ";
busDestinTab[INMdst]   := "INM ";
busDestinTab[dst11]    := nothing;
busDestinTab[dst12]    := nothing;
busDestinTab[dst13]    := nothing;
busDestinTab[dst14]    := nothing;
busDestinTab[BNKdst]   := "BNK ";
busDestinTab[Fdst]     := "F   ";
busDestinTab[NULdst]   := minus;
busSourceTab[ALUsrc]   := "ALU ";
busSourceTab[MDsrc]    := "MD  ";
busSourceTab[PCsrc]    := "PC  ";
busSourceTab[IR4src]   := "IR4 ";
busSourceTab[IR8src]   := "IR  ";
busSourceTab[IR8Msrc]  := "IR- ";
busSourceTab[IRSsrc]   := "IR* ";
busSourceTab[IODsrc]   := "IOD ";
busSourceTab[INMsrc]   := "INM ";
busSourceTab[src11]    := nothing;
busSourceTab[src12]    := nothing;
busSourceTab[src13]    := nothing;
busSourceTab[src14]    := nothing;
busSourceTab[src15]    := nothing;
busSourceTab[Fsrc]     := 'F   ';
busSourceTab[NULsrc]   := minus;
registerName[R0]       := "0";
registerName[R1]       := "1";
registerName[R2]       := "2";
registerName[R3]       := "3";
registerName[R4]       := "4";
registerName[R5]       := "5";
registerName[R6]       := "6";
registerName[R7]       := "7";
registerName[R10]      := "8";
registerName[R11]      := "M";
registerName[R12]      := "P";
registerName[R13]      := "H";
registerName[R14]      := "S";
registerName[R15]      := "G";
registerName[R16]      := "L";
registerName[R17]      := "T";
registerName[dontcare] := "Q";
qreg       := dontcare;
teston     := TRUE;
mcmAddress := 0
END Assembler.
