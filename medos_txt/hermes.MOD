 MODULE hermes;
(* ein sehr einfaches Programm zum uebertragen
verschiedener Files zwischen zwei computers '...'*)

(*  author Jirka Hoppe
    Institut fuer Informatik
    ETH  Zuerich *)

(* Version 3/5/82 *)

FROM SYSTEM IMPORT WORD, TSIZE, ADR;
FROM Terminal IMPORT Read, Write, WriteString, WriteLn;
FROM FileSystem IMPORT File, Response, Close, Lookup, Rename, Create,
                       SetRead, SetWrite, SetOpen, Command;
FROM FileNames IMPORT ReadFileName;
FROM Options IMPORT FileNameAndOptions, GetOption, Termination;
FROM FileMessage IMPORT WriteResponse;
FROM ByteBlockIO IMPORT ReadBytes, WriteBytes;
FROM CardinalIO IMPORT ReadOct, WriteOct;
 
CONST maxretransmission = 3;
     bufsize            =128;
 
 
TYPE
  PacketType = (AreYouHere,   (* inquire on activity *)
                LastBadBlock, (* the last block was somehow bad *)
                FileAction,   (* Lookup, Close,...*)
                FileActionResult,(* result of Lookup, Close, ... *)
                FileData,     (* data block *)
                NextData,     (* give me next data *)
                Abort,        (* abort session *)
                Kill);        (* kill the whole session *)
 
  PacketResult = ( pOK,       (* packet was received OK *)
                   badflag,   (* bad start flag *)
                   ptimeout,  (* timeout *)
                   badpacket, (* length err, flag err *)  
                   badxsum);  (* xsum error *)
 
  FileName = ARRAY [0..32] OF CHAR;
 
  FileCommand = (OpenWrite, OpenRead, CloseF, CheckOpen(*check if file already exists*) );
 
  buffer = ARRAY [0..bufsize-1] OF WORD;
 
  string = ARRAY [0..79] OF CHAR;
 
  onetwothree = (one, two, three);  (* help type *)
 
  packet = RECORD
             length : CARDINAL; (* the length of the packet *)
             CASE onetwothree OF
             one  : bytes : ARRAY [0..2*bufsize+10] OF CHAR  |
             two  : words : ARRAY [0..bufsize+5] OF CARDINAL|
             three: pxsum  : CARDINAL; (* checksum up to length *)
                    seqnr  : CARDINAL;
                    CASE pt : PacketType OF
                    AreYouHere:  IamMaster : BOOLEAN    |
                    LastBadBlock:                       |
                    FileAction: Fcmd : FileCommand;
                                fn   : FileName         |
                    FileActionResult : Fres : Response  |
                    FileData :  nrbytes : CARDINAL;
                                buff:     buffer        |
                    NextData :                          |
                    Abort    : msg: string              |            
                    Kill:
                    END
              END
            END (* packet *);

VAR
  inp, outp    : packet;
  master       : BOOLEAN;  (* true => accept file names; 
                           be master for openconnection *)
  datamaster   : BOOLEAN; (* true => write on disk; read line;;
                           false=> read disk; write line *)
  fromfn, tofn, defaultfn : FileName;
  abort        : BOOLEAN; (* transmittion should be aborted *)
  stop         : BOOLEAN; (* stop session *)
  killSlave    : BOOLEAN; (* send a kill packet to slave *)
  f            : File;    (* general file used for receiving and transmitting *)
  feof         : BOOLEAN; (* eof encountered *)
  debugOn      : BOOLEAN; (* set by option for debug output *)
  noQuerry     : BOOLEAN; (* set by option for no replace querry *)

(*$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$*)

MODULE Instructions;
  (* implements some hardware instructions *)
  IMPORT WORD;
  EXPORT PUT, GET;

  PROCEDURE PUT(chan : CARDINAL; value : WORD);
  (*----------*)
  CODE 241b
  END PUT;

  PROCEDURE GET(chan : CARDINAL; VAR value : WORD);
  (*---------*)
  CODE 240b
  END GET;
END Instructions;

(*$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$*)
 
MODULE ByteDriver;
IMPORT PUT, GET;
EXPORT SendByte, ReceiveByte, TimeOutLength, TimeOut, TimeOutOn;

VAR  TimeOut : BOOLEAN; (* FALSE => a byte has been received,
                           TRUE  => time out *)
     TimeOutOn : BOOLEAN; (* TRUE => activate time out *)
     dummy   : CARDINAL;
     MaxTime : CARDINAL; (* current length of the time out *)
 
PROCEDURE SendByte( b : CHAR);
  VAR st : BITSET;
  BEGIN
    REPEAT GET(5, st) UNTIL 15 IN st;
    PUT(4, b)
  END SendByte;

PROCEDURE ReceiveByte( VAR b : CHAR);
  VAR st : BITSET; retry : CARDINAL;
  BEGIN retry := MaxTime;
    LOOP
      GET(5, st);
      IF 14 IN st THEN GET(4,b); TimeOut := FALSE; EXIT END;
      IF 14 IN st THEN GET(4,b); TimeOut := FALSE; EXIT END;
      IF TimeOutOn THEN DEC(retry) END;
      IF 14 IN st THEN GET(4,b); TimeOut := FALSE; EXIT  END;
      IF retry = 0 THEN TimeOut := TRUE; EXIT END
    END
   END ReceiveByte;

PROCEDURE TimeOutLength(length : CARDINAL);
  BEGIN MaxTime := length END TimeOutLength;

BEGIN GET(4,dummy); (* reset uart *)
END ByteDriver;

(*$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$*)

PROCEDURE DisplayPacket( VAR p : packet);
  BEGIN
   WriteOct(p.words[0]); WriteOct(p.words[1]); 
   WriteOct(p.words[2]); WriteOct(p.words[3]);
   WriteOct(p.words[4]); WriteOct(p.words[5]); WriteLn;
   WITH p DO
    WriteString('length='); WriteOct(length);
    WriteString(' xsum  ='); WriteOct(pxsum);
    WriteString(' seqnr ='); WriteOct(seqnr); WriteLn;
    WriteString('type  =');
    CASE pt OF
    AreYouHere : WriteString('are you here ') ;
                 IF NOT IamMaster THEN WriteString(' no') END;
                 WriteString(' master')     |
    LastBadBlock: WriteString('last bad block') |
    FileAction: WriteString('file action ') ;
                CASE Fcmd OF
                OpenWrite : WriteString('open write') |
                OpenRead  : WriteString('open read')  |
                CloseF    : WriteString('close file') |
                CheckOpen :WriteString('check open')
                ELSE WriteString('illegal command')
                END;
                WriteString(' filename=');
                WriteString(fn); |
    FileActionResult : WriteString('file result '); WriteResponse(Fres);  |
    FileData:   WriteString('data');
                WriteString(' #bytes='); WriteOct(nrbytes); WriteLn;
                WriteOct(CARDINAL(buff[0])); WriteOct(CARDINAL(buff[1]));         |
    NextData:   WriteString('next data ');                    |
    Abort:      WriteString('abort:'); WriteString(p.msg)    |
    Kill:       WriteString('KILL!!')
    ELSE        WriteString('illegal type '); WriteOct(CARDINAL(pt))
    END;
    WriteLn;
   END (*with*)
  END DisplayPacket;

 
MODULE LineDriver;
  IMPORT PacketResult, SendByte, ReceiveByte, TimeOut, TimeOutOn, packet, PacketType,
         DisplayPacket, TSIZE, WriteString, WriteOct, WriteLn, Write, onetwothree,
         debugOn, TimeOutLength;
  EXPORT transmit, receive;

  CONST flag = 137c;
 
  PROCEDURE PacketLength ( VAR p : packet) : CARDINAL;
    (* compute the length of the packet *)
    BEGIN
      CASE p.pt OF
      AreYouHere   : RETURN ( TSIZE(packet, three, AreYouHere  ))  |
      LastBadBlock : RETURN ( TSIZE(packet, three, LastBadBlock))  |
      FileAction   : RETURN ( TSIZE(packet, three, FileAction  ))  |
      FileActionResult : RETURN ( TSIZE(packet, three, FileActionResult )) |
      FileData     : RETURN ( TSIZE(packet, three, FileData    ))  |
      NextData     : RETURN ( TSIZE(packet, three, NextData    ))  |
      Abort        : RETURN ( TSIZE(packet, three, Abort       ))  |
      Kill         : RETURN ( TSIZE(packet, three, Kill        ))
      END
    END PacketLength;

  PROCEDURE PacketXsum ( VAR p : packet; VAR xs : CARDINAL);
    (* compute the packet checksum *)
    VAR i, pl, xsl : CARDINAL;
    BEGIN xsl := p.length; pl := PacketLength(p) - 2;
      FOR i := 1 TO pl DO
        xsl := CARDINAL( BITSET(xsl) / (*XOR*) BITSET( p.words[i]))
      END;
      xs := xsl;
    END PacketXsum;

  PROCEDURE SkipPacket; 
    (* skip the rest of the packet *)
    VAR b : CHAR;
    BEGIN TimeOutOn := TRUE; TimeOutLength(8000h);
      REPEAT ReceiveByte(b) UNTIL TimeOut;
       TimeOutLength(0FFFFh)
    END SkipPacket;
 
  PROCEDURE transmit( VAR p : packet);
    VAR i, pl : CARDINAL;
    BEGIN pl := PacketLength(p); p.length := pl;
      PacketXsum(p, p.pxsum);
      IF debugOn THEN WriteString('.....xmit->');   DisplayPacket(p); END;
      SendByte(flag);
      SendByte( CHAR (pl));
      FOR i := 0 TO 2*pl-3 DO SendByte(p.bytes[i]) END;
    END transmit;

  PROCEDURE receiv( VAR p : packet; VAR res : PacketResult;
                     timeouton : BOOLEAN);
    VAR b : CHAR; i, pl, xs : CARDINAL;
    BEGIN
      TimeOutOn := timeouton;
      ReceiveByte( b );  (* wait flag *)
      IF TimeOut THEN res := ptimeout; RETURN END;
      IF b<>flag THEN SkipPacket; res := badflag; RETURN END;

      TimeOutOn := TRUE; (*allways time out *)
      ReceiveByte( b );  (* lenght *)
      IF TimeOut THEN res := badpacket; RETURN END;
      pl := 2 * CARDINAL(b)-2; p.length := CARDINAL(b);

      i := 0;
      LOOP 
        ReceiveByte(b); p.bytes[i] := b;
        IF TimeOut THEN res := badpacket; RETURN END;
        INC(i);
        IF i = pl THEN res := pOK; EXIT END;
      END;

      PacketXsum(p, xs);
      IF xs <> p.pxsum THEN res := badxsum END;

    END receiv;

 PROCEDURE  receive( VAR p : packet; VAR res : PacketResult;
                      timeouton : BOOLEAN);
   BEGIN receiv(p, res, timeouton);
     IF debugOn THEN
       WriteString('....received->');  DisplayPacket(p);
       WriteString('---');
       CASE res OF
       pOK      : WriteString('pOK')        |
       badflag  : WriteString('bad flag')   |
       ptimeout : WriteString('time out')   |
       badpacket: WriteString('bad packet') |
       badxsum  : WriteString('bad xsum')
       END;
       WriteLn;
     END;
     IF (res=pOK) AND (p.pt<>LastBadBlock) THEN Write('.')
     ELSE Write('-')
     END;
   END receive;
 
END LineDriver;
 
PROCEDURE SendLastBadBlock;
  BEGIN
    outp.pt := LastBadBlock; transmit(outp)
  END SendLastBadBlock;
 
PROCEDURE SendAbortPacket(s : string);
  BEGIN
    outp.pt := Abort; outp.msg := s; transmit(outp)
  END SendAbortPacket;

PROCEDURE OpenLine(datamaster: BOOLEAN);
  VAR res : PacketResult;
  BEGIN
      outp.seqnr := 0;
      IF master THEN outp.pt := AreYouHere; outp.IamMaster := TRUE;
        WriteString('opening line...'); WriteLn;
        LOOP
          transmit(outp); receive(inp, res, TRUE);
          IF res = pOK THEN
            IF inp.pt=Abort THEN abort := TRUE; EXIT
            ELSIF inp.pt=AreYouHere THEN
              IF inp.IamMaster THEN WriteString('there are two masters!');
                 abort := TRUE;
              ELSE WriteString('line opened'); WriteLn;
              END;
              EXIT
            END;
          END;
        END (* loop *);
      ELSE (*slave*)
        LOOP
          receive(inp, res, FALSE);
          IF (res=pOK) AND (inp.pt=AreYouHere) THEN
            outp.pt := AreYouHere; outp.IamMaster := FALSE; transmit(outp);
            EXIT;
          END
        END;
      END;
  END OpenLine;


  PROCEDURE OpenConnectionMaster;
    VAR ch : CHAR;
        retransmission : CARDINAL;
        res : PacketResult;
        term : Termination;
        optionString : ARRAY [0..20] OF CHAR;
        optionLength : CARDINAL;

    BEGIN
      WriteString('file transfer'); WriteLn;
      WriteString('from: ');
      

      LOOP
        Read(ch); ch := CAP(ch);
        IF ch = 'M'  THEN  WriteString('ME:'); datamaster := FALSE ; EXIT
        ELSIF ch = 'Y' THEN WriteString('YOU:'); datamaster := TRUE; EXIT
        ELSIF ch = 33c THEN 
          WriteLn; WriteString('type:'); WriteLn;
          WriteString('K or ESC   - to Kill the slave and exit'); WriteLn;
          WriteString('S          - to exit but let the slave Survive'); WriteLn;
          WriteString('other key  - to Return back to hermes'); WriteLn;
          Read(ch); ch := CAP(ch); Write(ch);
          IF (ch=33c) OR (ch = 'K') THEN stop := TRUE; killSlave := TRUE; RETURN
          ELSIF (ch = 'S') THEN stop := TRUE; RETURN;
          END;
        ELSE Write('?')
        END
      END;

      FileNameAndOptions('DK.', fromfn, term, TRUE);
      (* ReadFileName(fromfn,'DK.');*)  WriteLn;
      defaultfn := fromfn;
      (* get options *)
      debugOn := FALSE; noQuerry := FALSE;
      LOOP GetOption(optionString, optionLength);
        IF optionLength = 0 THEN EXIT END;
        IF CAP(optionString[0]) = 'D' THEN debugOn := TRUE
        ELSIF CAP(optionString[0]) = 'N' THEN noQuerry := TRUE
        ELSE WriteString('bad option'); WriteLn
        END
      END;
(*$$$ WriteString('debug'); IF debugOn THEN Write('T') ELSE Write('F') END; Write(' ');
      WriteString('noQuerry'); IF noQuerry THEN Write('T') ELSE Write('F') END; WriteLn;*)

      WriteString ('to: ');
      IF datamaster THEN WriteString('ME:')
                    ELSE WriteString('YOU:')
      END;

      ReadFileName(tofn, defaultfn); Read(ch);
      IF tofn[0]=0c THEN tofn := defaultfn; WriteString(tofn); END;

      (* open the local file *)
      IF debugOn THEN WriteString(' local file: '); 
        IF datamaster THEN WriteString(tofn);
        ELSE WriteString(fromfn);
        END;
      END;
      IF datamaster THEN 
        IF NOT noQuerry THEN
          (* look if the file already exists *)
          Lookup(f, tofn, FALSE);
          IF f.res = done THEN
            WriteString('      replace?');
            Read(ch); ch := CAP(ch);
            IF ch='Y' THEN WriteString(' YES');
            ELSE abort := TRUE; WriteString(' no replace'); WriteLn; Close(f); 
              SendAbortPacket('no replace'); RETURN
            END;
          END;
          Close(f);
        END;
        Lookup(f, tofn, TRUE);
      ELSE  Lookup(f, fromfn, FALSE);
      END;
      IF f.res<>done THEN WriteString(' local file'); WriteResponse(f.res); WriteLn;
        abort := TRUE; RETURN
      END;
      IF debugOn THEN WriteString(' file action '); WriteResponse(f.res); WriteLn END;

      (* now send a packet to the other machine *)
      IF NOT datamaster AND NOT noQuerry THEN
      (* check if the file exist on the other computer *)
        LOOP
          outp.Fcmd := CheckOpen; outp.pt := FileAction; outp.fn := tofn;
          transmit(outp); receive(inp, res, TRUE);
          IF (res=pOK) THEN                                                       
            IF (inp.pt=Abort) THEN abort := TRUE; RETURN   
            ELSIF (inp.pt=FileActionResult) THEN
              IF inp.Fres=done THEN 
                WriteString('       replace?');
                Read(ch); ch := CAP(ch);
                IF ch='Y' THEN WriteString(' YES'); EXIT;
                ELSE WriteString(' no replace'); WriteLn; abort := TRUE;
                  SendAbortPacket('no replace'); RETURN
                END;
              ELSE EXIT
              END
            END
          END;
          DEC(retransmission);
          IF retransmission = 0 THEN WriteString('line down'); WriteLn;
                      abort := TRUE; SendAbortPacket('line down'); RETURN 
          END
        END (* retrans LOOP*)
      END; (* if remote querry necessary *)
      WriteLn;

      IF datamaster THEN outp.Fcmd := OpenRead;  outp.fn := fromfn
                    ELSE outp.Fcmd := OpenWrite; outp.fn := tofn
      END;
      IF debugOn THEN WriteString(' remote file:'); WriteString(outp.fn); WriteLn; END;
      outp.pt := FileAction;

      retransmission := maxretransmission;
      LOOP
        transmit(outp); receive(inp, res, TRUE);
        IF (res=pOK) THEN                                                       
          IF (inp.pt=Abort) THEN abort := TRUE; RETURN   
          ELSIF (inp.pt=FileActionResult) THEN
            IF debugOn OR (inp.Fres<>done) THEN 
              WriteString('remote file '); WriteResponse(inp.Fres); WriteLn
            END;
            IF NOT (inp.Fres=done) THEN abort := TRUE END;
            RETURN;
          END;
        END;
        DEC(retransmission);
        IF retransmission = 0 THEN WriteString('line down'); WriteLn;
                      abort := TRUE; SendAbortPacket('line down'); RETURN 
        END
      END;
    END OpenConnectionMaster;

  PROCEDURE OpenConnectionSlave;
    VAR res : PacketResult;
    BEGIN
      LOOP
        receive(inp, res, FALSE);
        IF (res=pOK) THEN                                                       
          IF (inp.pt=Abort) THEN abort := TRUE; RETURN
          ELSIF (inp.pt=Kill) THEN WriteLn; WriteString('transmission is finished');
              WriteLn;
              WriteString('you may use the machine again'); WriteLn; stop := TRUE; RETURN
          ELSIF inp.pt=AreYouHere THEN
            outp.pt := AreYouHere; outp.IamMaster := FALSE; transmit(outp);
          ELSIF (inp.pt=FileAction)
             AND ((inp.Fcmd=OpenWrite) OR (inp.Fcmd=OpenRead)) OR (inp.Fcmd=CheckOpen) THEN
               IF inp.Fcmd=CheckOpen THEN
                 Lookup(f, inp.fn, FALSE); 
                 outp.Fres := f.res;
                 Close(f)
               ELSIF inp.Fcmd=OpenWrite THEN
                 tofn := inp.fn; Lookup(f,inp.fn, TRUE); datamaster := TRUE;
                 outp.Fres := f.res;
               ELSE
                 Lookup(f, inp.fn, FALSE); datamaster := FALSE;
                 outp.Fres := f.res;
               END;
               IF debugOn THEN WriteResponse(f.res); WriteLn; END;
               outp.pt := FileActionResult;
               transmit(outp);
               abort := f.res <> done;
               IF (inp.Fcmd=OpenWrite) OR (inp.Fcmd=OpenRead) THEN EXIT END;
          ELSE SendLastBadBlock;
          END
        ELSE SendLastBadBlock
        END;
      END
    END OpenConnectionSlave;

  PROCEDURE DataXferMaster;
    (* master reads from network and writes on his disk *)
    VAR blocknr : CARDINAL;
        retransmission : CARDINAL;
        res : PacketResult;
    BEGIN  blocknr := 1; feof := FALSE;
      LOOP (* for a file *)
        LOOP (* for a block *)
          retransmission := maxretransmission;
          outp.pt := NextData;
          outp.seqnr := blocknr;
          transmit(outp);
          receive(inp, res, TRUE);
          IF (res = pOK) THEN
            IF (inp.pt=FileData) AND (inp.seqnr=blocknr) THEN
                 WriteBytes(f, ADR(inp.buff), inp.nrbytes);
                 IF debugOn THEN WriteResponse(f.res); WriteLn END;
                 IF inp.nrbytes < 2*bufsize THEN 
                   IF debugOn THEN WriteString('eof encountered'); WriteLn END;
                   feof := TRUE;
                 END;
                 EXIT  
            ELSIF inp.pt=Abort THEN abort := TRUE; RETURN
      (*    ELSIF (inp.pt <> LastBadBlock) THEN SendLastBadBlock *)
            END;
      (*  ELSE SendLastBadBlock; *)
          END;
          DEC(retransmission);
          IF retransmission = 0 THEN WriteString('line down'); WriteLn;
              abort := TRUE; SendAbortPacket('line down2'); RETURN
          END;
        END (* block loop *);
        INC(blocknr);
        IF feof THEN EXIT END
      END; (* all block of a file *)

        IF feof THEN 
          (*$$$ WriteString('tofn='); WriteString(tofn);*)
          Close(f);
          IF debugOn THEN WriteResponse(f.res); WriteLn END;
          retransmission := maxretransmission;
          LOOP
            WITH outp DO
             pt := FileAction; Fcmd := CloseF; fn := '   ';
            END;
            transmit(outp);
            receive(inp, res, TRUE);
            IF (res=pOK) THEN
              IF inp.pt = Abort THEN abort := TRUE; RETURN
              ELSIF (inp.pt=FileActionResult) AND (inp.Fres=done) THEN
                WriteString('done'); WriteLn; EXIT
              END
            END ;
            DEC(retransmission);
            IF retransmission = 0 THEN WriteString('pech gehabt');
              abort := TRUE ; RETURN;
            END;
          END; (* loop *)
        END (* feof *);
    END DataXferMaster;

PROCEDURE DataXferSlave;
  (* slave reads disks and writes network*)
  VAR retransmission : CARDINAL;
      blocknr : CARDINAL;
      res : PacketResult;
      actcount : CARDINAL;
      mybuff : buffer;
  BEGIN
    blocknr :=0;
    LOOP
      receive(inp, res, FALSE);
      IF (res=pOK) THEN                                                         
        CASE inp.pt OF
        Abort: abort := TRUE; RETURN  
|       NextData:
          IF inp.seqnr = (blocknr+1) THEN
            ReadBytes(f, ADR(mybuff), 2*bufsize, actcount);
            INC(blocknr);
          ELSIF blocknr<>inp.seqnr THEN
              WriteString('out of sequence, myseq='); WriteOct(blocknr);
              WriteString(' req seg='); WriteOct(inp.seqnr); WriteLn;
              abort := TRUE; SendAbortPacket('wrong seq'); RETURN
          (* ELSE inp.seqnr=blocknr *)
          END;
          WITH outp DO
            pt := FileData; buff := mybuff; seqnr:=blocknr; nrbytes := actcount;
          END;
          transmit(outp); 
|       FileAction:                                                             
          IF (inp.Fcmd=CloseF) THEN
            Close(f);
            WITH outp DO
              pt := FileActionResult; Fres := f.res;
            END;
            transmit(outp);
            IF f.res=done THEN WriteString('done'); WriteLn; EXIT END
          ELSE SendLastBadBlock;
          END;
        ELSE IF inp.pt<>LastBadBlock THEN SendLastBadBlock END
        END; (* CASE type of the packet *)
      ELSE SendLastBadBlock;
      END (* packet OK *);
    END (* LOOP for file*)
  END DataXferSlave;
 
PROCEDURE main;
  VAR res : PacketResult;
  ch : CHAR; i : CARDINAL;
  BEGIN stop := FALSE; debugOn := FALSE; killSlave := FALSE; TimeOutLength(0FFFFh);
      WriteString('Are you master? ');
      LOOP
        Read(ch); ch := CAP(ch);
        IF (ch='Y') THEN WriteString('YES'); master := TRUE; EXIT
        ELSIF (ch='N') THEN WriteString('NO'); master := FALSE; EXIT
        ELSIF (ch=33c) THEN
          WriteLn; WriteString('type:'); WriteLn;
          WriteString('K or ESC   - to Kill the slave and exit'); WriteLn;
          WriteString('S          - to exit but let the slave Survive'); WriteLn;
          WriteString('other key  - to Return back to hermes'); WriteLn;
          Read(ch); ch := CAP(ch); Write(ch);
          IF (ch=33c) OR (ch = 'K') THEN stop := TRUE; killSlave := TRUE; EXIT
          ELSIF ch = 'S' THEN stop := TRUE; EXIT
          ELSE WriteString('Are you master? ');
          END;
        ELSE Write('?');
        END
      END;
      WriteLn;

      abort := FALSE;
 
    IF NOT stop THEN
      OpenLine(master);
      LOOP
        IF NOT abort THEN
          IF master THEN OpenConnectionMaster
                    ELSE OpenConnectionSlave
          END
        END;

        IF stop THEN
          IF  killSlave THEN outp.pt := Kill; transmit(outp) END;
          EXIT
        END;
        (* wait if master is changing *)
        IF NOT abort AND NOT master AND datamaster THEN
           FOR i := 0 TO 10000 DO i:=i END;
        END;

        IF NOT abort THEN
          IF datamaster THEN DataXferMaster
                        ELSE DataXferSlave
          END;
        END;
        IF abort THEN Close(f) END;
        abort := FALSE;
      END;
    END
  END main;

BEGIN main END hermes.

.EOF.
