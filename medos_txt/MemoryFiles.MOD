(**********************************************
*                                             *
*          MemoryFiles                        *
*                                             *
*                                             *
*          by S. Grossen                      *
*                                             *
*          created on             10.4.1981   *
*                                             *
*          version  2              4.6.1981   *
*          version  3  (by SEK)   9.11.1981   *
*          version  4  (by SEK)    5.6.1982   *
*                                             *
**********************************************)

IMPLEMENTATION MODULE MemoryFiles;

FROM FileSystem IMPORT File, Command, Response, Flag, FlagSet, CreateMedium;
FROM Frames IMPORT Allocate, Deallocate, FramePointer, nil;
FROM SYSTEM IMPORT WORD, ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM Terminal IMPORT WriteString, WriteLn;


CONST datalength=256;       (* Blocklaenge in Buchstaben      *)
      datalengthdiv2=128;   (* Blocklaenge in Worten          *)
      AdrTabLe=8;           (* Laenge der Blockadresstabellen *)
      compdatalength=256;   (* 2**16 DIV datalength           *)


TYPE  filestatus=(opened,reading,writing,modifying);

      MemFile=POINTER TO filedesc;

      BlkAdrPtr=POINTER TO BlockAdr;

      filedesc=RECORD
            LeBlock, LelastB, PosBlock, PosinB, BlkNr: CARDINAL;
            fst: filestatus;
            bufadr: POINTER TO ARRAY[1..datalengthdiv2] OF WORD;
            AdrBlk, BlockList: BlkAdrPtr;
            nextDesc: MemFile
         END;

      BlockAdr=RECORD
            AdrList: ARRAY[0..AdrTabLe-1] OF FramePointer;
            nextBlkAdr: BlkAdrPtr;
         END;


VAR   STAMM, actual, prev: MemFile;
      def: BOOLEAN;


PROCEDURE FileCommand(VAR f: File);

  VAR
    i, BlkNrDIV, PosBlockDIV: CARDINAL;
    fp: FramePointer;
 
  PROCEDURE CuttoPos(VAR f:File);
 
  VAR   fl, fr: BlkAdrPtr;
        i, j: CARDINAL;
      
  BEGIN 
    WITH f DO
      WITH actual^ DO
        fr:=BlockList;
        FOR i:=1 TO PosBlock DIV AdrTabLe DO fr:=fr^.nextBlkAdr END;
        fl:=fr;
        FOR i:=PosBlock+1 TO LeBlock DO 
          j:=i MOD AdrTabLe;
          IF j=0 THEN fr:=fr^.nextBlkAdr
          END;
          Deallocate(fr^.AdrList[j])
        END;
        fl:=fl^.nextBlkAdr;
          FOR i:=(PosBlock+1) DIV AdrTabLe+1 TO LeBlock DIV AdrTabLe DO
          fr:=fl;fl:=fl^.nextBlkAdr;
          DISPOSE(fr)
        END;
        LeBlock:=PosBlock;LelastB:=PosinB;eof:=TRUE
      END
    END
  END CuttoPos;


PROCEDURE MoveFrame(tfp: FramePointer; tfoff: CARDINAL;
                    ffp: FramePointer; ffoff: CARDINAL; Length: CARDINAL);
CODE
  337B
END MoveFrame;



BEGIN 
  WITH f DO
    res:=done;flags:=flags*FlagSet{bytemode};
    IF com<=open 
    THEN 
      NEW(actual);submedium:=actual;
      WITH actual^ DO
        NEW(bufadr);bufa:=bufadr;topa:=bufa+datalengthdiv2;
        ina:=bufa;inodd:=FALSE;ela:=bufa;elodd:=FALSE;eof:=TRUE;flags:=FlagSet{ef};
        LeBlock:=0;LelastB:=0;PosBlock:=0;
        fst:=opened;
        NEW(BlockList);
        FOR i := 0 TO AdrTabLe-1 DO BlockList^.AdrList[i] := nil END;
        BlockList^.nextBlkAdr := NIL;
        AdrBlk:=BlockList;
        Allocate(fp, datalengthdiv2);
        IF fp = nil THEN
          WriteString(' - MemoryFiles.FileCommand: memory full!'); WriteLn;
          HALT;
        END;
        BlockList^.AdrList[0] := fp;
        BlkNr:=0;nextDesc:=STAMM;STAMM:=submedium
      END
    END;
    actual:=STAMM;prev:=NIL;
    WHILE (actual<>submedium) AND (actual<>NIL) DO
      prev:=actual; (* wird beim Loeschen gebraucht  *)
      actual:=actual^.nextDesc
    END;
    IF actual=NIL
    THEN res:=unknownfile;INCL(flags,er);RETURN END;
    WITH actual^ DO
      def:=fst>=writing;
      PosinB:=(ela-bufa)*2;
      IF elodd THEN INC(PosinB) END;
      IF PosinB>=datalength
      THEN INC(PosBlock);PosinB:=0
      END;
      (* Position in Ordnung *)
      (* Laenge korrigieren, evt. neue Seite reservieren *)
      IF def
      THEN
        IF PosBlock>LeBlock
        THEN LeBlock:=PosBlock; LelastB:=PosinB;
          WITH AdrBlk^ DO
            IF PosBlock MOD AdrTabLe=0 THEN
              NEW(nextBlkAdr);
              FOR i := 0 TO AdrTabLe-1 DO nextBlkAdr^.AdrList[i] := nil END;
              nextBlkAdr^.nextBlkAdr := NIL;
            END;
            Allocate(fp, datalengthdiv2);
            IF fp = nil THEN
              WriteString(' - MemoryFiles.FileCommand: memory full'); WriteLn;
              HALT;
            END;
            IF PosBlock MOD AdrTabLe = 0 THEN
              nextBlkAdr^.AdrList[0] := fp
            ELSE AdrList[PosBlock MOD AdrTabLe] := fp
            END;
          END;
        ELSIF (PosBlock=LeBlock) AND (PosinB>LelastB)
        THEN LelastB:=PosinB
        END
      (* Laenge und Position aktualisiert *)
      END;   
      CASE com OF
        setpos:   PosinB:=lowpos MOD datalength;
                  PosBlock:=lowpos DIV datalength+compdatalength*highpos  |

        getpos:   highpos:=PosBlock DIV compdatalength;
                  lowpos:=PosBlock MOD compdatalength*datalength+PosinB   |
        length:   highpos:=LeBlock DIV compdatalength;
                  lowpos:=LeBlock MOD compdatalength*datalength+LelastB   |
        setpermanent,setprotect: res:=notsupported;on:=FALSE              |
        getpermanent,getprotect: on:=FALSE                   |
        doio,create,open:                                    |
        setopen:  fst:=opened                                |
        setread:  fst:=reading;INCL(flags,rd)                |
        setwrite: fst:=writing;INCL(flags,wr)    |
        setmodify:fst:=modifying;flags:=flags+FlagSet{rd,wr} |
        close:    DISPOSE(bufadr);bufa:=NIL;bufadr:=NIL      |
        lookup,rename: res:=notsupported
        ELSE res:=paramerror
      END;
      IF (PosBlock>LeBlock) OR ((PosBlock=LeBlock) AND (PosinB>=LelastB))
      THEN eof:=TRUE;PosBlock:=LeBlock;PosinB:=LelastB
      ELSE eof:=FALSE
      END;
      IF bufadr<>NIL
      THEN
        CASE fst OF
          opened,reading:   |
          writing:     IF NOT eof THEN CuttoPos(f) END;
                       def:=def AND (BlkNr<=LeBlock)   |
          modifying:   def:=def AND (BlkNr<>PosBlock)
        END;
        IF def THEN MoveFrame(AdrBlk^.AdrList[BlkNr MOD AdrTabLe], 0,
                              0, ADR(bufadr^), datalengthdiv2)
        END;
        IF BlkNr<>PosBlock
        THEN PosBlockDIV:=PosBlock DIV AdrTabLe;
          BlkNrDIV:=BlkNr DIV AdrTabLe;
          IF BlkNrDIV<PosBlockDIV
          THEN i:=BlkNrDIV+1
          ELSE i:=1;AdrBlk:=BlockList
          END;
          FOR i:=i TO PosBlockDIV DO
            AdrBlk:=AdrBlk^.nextBlkAdr
          END;
          BlkNr:=PosBlock;
          MoveFrame(0, ADR(bufadr^), AdrBlk^.AdrList[PosBlock MOD AdrTabLe], 0,
                    datalengthdiv2)
        END;
        bufa:=bufadr;topa:=bufa+datalengthdiv2;
        ela:=bufa+PosinB DIV 2;elodd:=ODD(PosinB);
        IF BlkNr=LeBlock
        THEN ina:=bufa+LelastB DIV 2;inodd:=ODD(LelastB)
        ELSE ina:=topa;inodd:=FALSE
        END
      ELSE (* -> bufa=NIL *)
        PosBlock:=0;PosinB:=0;CuttoPos(f);
        Deallocate(BlockList^.AdrList[0]);
        DISPOSE(BlockList);
        IF prev=NIL 
        THEN STAMM:=nextDesc
        ELSE prev^.nextDesc:=nextDesc
        END;
        DISPOSE(actual);topa:=NIL;ina:=NIL;inodd:=FALSE;
        ela:=NIL;elodd:=FALSE;eof:=TRUE;submedium:=NIL;
      END; (* IF bufadr<> NIL  *)
      IF res>notdone
      THEN INCL(flags,er)
      ELSE 
        IF elodd OR ODD(LelastB) THEN INCL(flags,bytemode) END;
        IF eof THEN INCL(flags,ef) END
      END
    END (* WITH actual^ *)
  END
END FileCommand;


PROCEDURE DirectoryCommand(VAR f:File;name:ARRAY OF CHAR);

BEGIN
  FileCommand(f)
END DirectoryCommand;

(* Initialisierung  *)
BEGIN CreateMedium('MF',177777B,FileCommand,DirectoryCommand,def);
  STAMM:=NIL
END MemoryFiles.
