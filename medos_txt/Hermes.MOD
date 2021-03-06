IMPLEMENTATION MODULE Hermes; (* WW 27.6.83 *)

(* ein sehr einfaches Programm zum uebertragen
verschiedener Files zwischen zwei computers '...'*)

(*  author Jirka Hoppe
    Institut fuer Informatik
    ETH  Zuerich
    Version 3/5/82 *)

FROM SYSTEM IMPORT ADR;
FROM Terminal IMPORT Read, Write, WriteString, WriteLn;
FROM FileSystem IMPORT File, Response, Reset,
Lookup,ReadChar,WriteChar,Close;
FROM FileMessage IMPORT WriteResponse;
FROM ByteBlockIO IMPORT ReadBytes, WriteBytes;
FROM CardinalIO IMPORT ReadOct, WriteOct;

FROM HermesByte IMPORT TimeOutLength;
FROM HermesLine IMPORT PacketResult, PacketType, bufsize, buffer, packet,
                       FileName, FileCommand, string,
                       transmit, receive;
 
CONST
  maxretransmission = 3;

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
  feof         : BOOLEAN; (* eof encountered *)
  debugOn      : BOOLEAN; (* set by option for debug output *)
  noQuerry     : BOOLEAN; (* set by option for no replace querry *)

 
PROCEDURE SendLastBadBlock;
BEGIN
  outp.pt := LastBadBlock; transmit(outp)
END SendLastBadBlock;
 

PROCEDURE SendAbortPacket(s : string);
BEGIN
  outp.pt := Abort; outp.msg := s; transmit(outp)
END SendAbortPacket;


PROCEDURE OpenLine (datamaster: BOOLEAN; VAR abort: BOOLEAN);
VAR res : PacketResult;
BEGIN
      outp.seqnr := 0;
      IF datamaster THEN outp.pt := AreYouHere; outp.IamMaster := TRUE;
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
 

PROCEDURE Main;
VAR
  res : PacketResult;
  ch : CHAR;
  i : CARDINAL;
BEGIN
    stop := FALSE;
    debugOn := FALSE;
    killSlave := FALSE;
    TimeOutLength(0FFFFh);
    master := TRUE;
    abort := FALSE;
END Main;

 
PROCEDURE InitConnection (VAR ok: BOOLEAN);
BEGIN
  OpenLine(master,abort);
  ok := NOT abort;
END InitConnection;
 

PROCEDURE XferFile (from: FileName; VAR f: File; VAR ok: BOOLEAN);

  PROCEDURE OpenConnectionMaster (fromfn: FileName);
  VAR
    ch : CHAR;
    retransmission : CARDINAL;
    res : PacketResult;
  BEGIN
      datamaster := TRUE;

      (* open the local file *)
      Reset(f);
      IF f.res <> done THEN
        WriteString(' local file');
        WriteResponse(f.res);
        WriteLn;
        abort := TRUE;
        RETURN
      END;

      outp.Fcmd := OpenRead;
      outp.fn := fromfn;
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


  PROCEDURE DataXferMaster;
    (* master reads from network and writes on his disk *)
  VAR
    blocknr : CARDINAL;
    retransmission : CARDINAL;
    res : PacketResult;
  BEGIN
      blocknr := 1; feof := FALSE;
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
                WriteString('done'); EXIT
              END
            END ;
            DEC(retransmission);
            IF retransmission = 0 THEN WriteString('pech gehabt');
              abort := TRUE ; RETURN;
            END;
          END; (* loop *)
        END (* feof *);
  END DataXferMaster;


BEGIN (* XferFile *)
  OpenConnectionMaster(from);
  IF NOT abort THEN DataXferMaster; END;
  ok := NOT abort;
END XferFile;


BEGIN
  Main;
END Hermes.
