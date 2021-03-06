 MODULE DiskPatch; (* version 9/5/83 *)

(* Copyrigth Jirka Hoppe 
   Institut for informatics
   ETH Zurich - Switzerland
   ne aby na tenhle program nekdo sahal !!!!! *)
 
(* this is a very, very dangerous program, that might destroy the whole disk
   be therefore really sure, that you know how to handle it,
   good luck *)

FROM SYSTEM IMPORT ADR, ADDRESS, WORD;
FROM Monitor IMPORT Time, GetTime;

FROM Jdisk IMPORT readwrite, dkerrors, disktype, diskdriver, PrintError;
FROM Terminal IMPORT Write, Read, BusyRead, WriteLn, WriteString;
FROM JIO IMPORT ReadEcho, ReadOct, WriteOct, WriteStringLn, delim;

FROM DiskSystem IMPORT FileNumber, FDKind, Minute, Page, FileDesc, nofile, fname,
                NameKind, ExternalName, Name,
                InitVolume, ReadFileDesc, WriteFileDesc, ReadName, WriteName;

CONST
  EOL       = 36c;

  maxsector = 37631; (* maximal sector number *)
  maxFile   = 767  ;  (* maximal number of files *)
  maxFilePage=392*12-1; (* number of pages used by the file system *)
  maxIB     = 95;    (* maximal number of single illegal blocks *)
  maxDIB    =  95;   (* maximal number of double illegal blocks *)
  pageNil   = 4704*13;(* nil page pointer *)
  (*  addresses of fixed files *)
  StartBoot1= 0;     (* start sector of boot1 file *)
  EndBoot1  = 191;   (* end of boot1 *)
  StartDump1= 192;   (* start dump1 *)
  EndDump1  = 1247;  (* end dump1 *)
  StartBoot2= 1248;  (* start of boot2 *)
  EndBoot2  = 1439;  (* end of boot2 *)
  StartDir  = 43200b;(* start of directory *)
  EndDir    = 44577b;(* end of directory *)
  StartNameD= 44600b;(* start of name directory *)
  EndNameDir= 44737b;(* end of name directory *)
  StartBackD= 36768; (* start of back up directory *)
  EndBackD  = 37535; (* end of back up directory *)
  StartBND  = 37536; (* start of name directory back up *)
  EndBND    = 37631; (* end of name directory back up *)

TYPE IBarray = ARRAY [0..95] OF CARDINAL; (* illegal block array *)
     String  = ARRAY [0..80] OF CHAR;
     dkerrset= SET OF dkerrors; 

VAR dummy : ARRAY [0..127] OF CARDINAL; (* never keeps any info *)
    sector: ARRAY [0..127] OF CARDINAL; (* keeps the last read sector *)
    directory : FileDesc;               (* local copy of a directory segment *)
    NameBlock : ARRAY [0..7] OF Name;   (* local copy of a name directory segment *)
    illblock  : IBarray;                (* list of invalid blocks *)
    inxIB     : CARDINAL;               (* index in illblock *)
    DoubleIllBlock : IBarray;           (* list of double illegal blocks *)
    inxDIB    : CARDINAL;               (* index in DoubleIllBlock *)
    currentdisk: disktype;              (* removable, fixed *)
    ch        : CHAR;                   (* used everywhere *)
    InspBase  : ADDRESS;                (* relative address used for inspect *)
    CrntSect  : CARDINAL;               (* current working sector *)
    CrntDir   : CARDINAL;               (* current directory sector in the variable
                                           directory *)
    CrntNDir  : CARDINAL;               (* current name directory sector *)
    time      : Time;                   (* current day and time *)

(*$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$*)
 
MODULE Instructions;
  (* implements some hardware instructions *)
  IMPORT WORD;
  EXPORT PUT, GET, Boot;

  PROCEDURE PUT(chan : CARDINAL; value : WORD);
  (*----------*)
  CODE 241b
  END PUT;

  PROCEDURE GET(chan : CARDINAL; VAR value : WORD);
  (*---------*)
  CODE 240b
  END GET;

  PROCEDURE Boot(trackNr : CARDINAL);
    CODE 247b; 0
  END Boot;

END Instructions;

(*$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$*)

PROCEDURE Key(): BOOLEAN;
(*----------- TRUE if key was hit *)
  VAR ch: CHAR;
BEGIN BusyRead(ch);
  RETURN(ch<>0C)
END Key;

PROCEDURE GlobalMenu;
(*-----------------*)
  BEGIN
    WriteStringLn('B bad block link');
    WriteStringLn('C character dump');
    WriteStringLn('D disk switch; removable/fixed');
    WriteStringLn('G get file to sector');
    WriteStringLn('F find name');
    WriteStringLn('I Inspect');
    WriteStringLn('K Consistency check');
    WriteStringLn('L iLlegal block bild up');
    WriteStringLn('N Name directory update');
    WriteStringLn('O Octal dump');
    WriteStringLn('R Read sector');
    WriteStringLn('S Set illegal block info into directory');
    WriteStringLn('T Transfer between disks');
    WriteStringLn('U Update directory');
    WriteStringLn('W Write sector');
    WriteStringLn('X disk Xfer');
    WriteStringLn('Z Zero directory');
    WriteStringLn('+ calculator');
  END GlobalMenu;

PROCEDURE Introduction;
(*-------------------*)
  (* prints a greeting, a warning, waits until the disk gets not ready
     that means the user changed the disk, and waits till the disk gets ready again *)
  VAR stat : BITSET;
  BEGIN
    WriteString('Welcome to this dangerous program'); WriteLn;
    WriteString('This program may destroy your disk'); WriteLn;
    WriteString('Do you know how to use this program? y/n/*');
    ReadEcho(ch); WriteLn;
    IF ch <> '*' THEN ch := CAP(ch) END;
    IF (ch <> 'Y') AND (ch <> '*') THEN
       WriteStringLn('so wait, next head crash will destroy it anyway');
       HALT
    END;

    IF ch <> '*' THEN
      WriteString('Switch therefore your disk off and take it out'); WriteLn;
      (* wait for disk not ready *)
      REPEAT GET(9, stat) UNTIL NOT (8 IN stat);
      WriteString('OK... now insert the new disk...'); WriteLn;
    END;

    (* wait for a ready disk *)
    REPEAT GET(9, stat) UNTIL 8 IN stat;
    WriteString('Is it really  the disk you want to destroy? y/n');
    ReadEcho(ch); ch := CAP(ch); WriteLn;
    IF ch <> 'Y' THEN WriteString('so wait, next head crash will destroy it anyway');
         WriteLn; HALT
    END;
    WriteString('GOD SAVE YOUR DISK'); WriteLn;
  END Introduction;

PROCEDURE DisplayName(i : CARDINAL);
(*-----------------*)
(* displays the i'th entry name in the NameBlock *)
  VAR j : CARDINAL;
  BEGIN
    WITH NameBlock[i] DO
      FOR j := 0 TO 23 DO
        IF en[j] >=' ' THEN Write(en[j]) ELSE Write('!') END;
      END;
    END;
  END DisplayName;

PROCEDURE DisplayFileName(sect : CARDINAL);
(*---------------------*)
(* tries to display the file name corresponding to the sector 'sect' *)
VAR er : dkerrors;
BEGIN
  WriteString('file name=');
  diskdriver(currentdisk, dkread, StartNameD+(sect DIV 8), ADR(NameBlock), er);
  IF er <> ok THEN PrintError( er, StartNameD+(sect DIV 8)) END;
  IF NameBlock[sect MOD 8].fno=sect (* sector# match *) THEN DisplayName(sect MOD 8)
  ELSE WriteString('?????')
  END;
  WriteLn;
END DisplayFileName;

PROCEDURE BadBlockLink;
(*------------------*)
(* inserts a specified bad block into the BadPages file *)
  VAR sect : CARDINAL; (* sector to be fixed *)
      i: CARDINAL; ch : CHAR; doIt : BOOLEAN; er: dkerrors;
BEGIN WriteString('ad block insert'); WriteLn;
  WriteString('which sector:'); ReadOct(sect); WriteLn;
  diskdriver( currentdisk, dkread, StartDir+4, ADR(directory), er);
  IF er <> ok THEN
    WriteString('problems... not done'); RETURN
  END;

  i := 0;
  LOOP
    IF directory.pagetab[i] = pageNil THEN doIt := TRUE; EXIT END;
    IF directory.pagetab[i] = sect DIV 10b * 13 THEN
      WriteStringLn('already linked'); doIt := FALSE
    END;
    IF i > 95 THEN WriteStringLn('too many bad blocks'); doIt := FALSE; EXIT END;
    INC(i);
  END;
  IF doIt THEN 
    directory.pagetab[i] := sect DIV 10b * 13;
    INC( directory.length.block,8);
    diskdriver( currentdisk, dkwrite, StartDir+4, ADR(directory), er);
    IF er <> ok THEN
      WriteStringLn('problems... not done')
    END;
  END
END BadBlockLink;

PROCEDURE CharDump;
(*--------------*)
  VAR i : CARDINAL; ch0, ch1 : CHAR;
  BEGIN WriteString('haracter dump'); WriteLn;
    FOR i := 0 TO 127 DO
      IF (i MOD 16) = 0 THEN WriteOct(i,7); WriteString(' *') END;
      ch1 := CHAR(sector[i] MOD 128);
      ch0 := CHAR((sector[i] DIV 256) MOD 128);
      IF (ch0 < ' ') OR (ch0=177c) THEN Write('.') ELSE Write(ch0) END;  
      IF (ch1 < ' ') OR (ch1=177c) THEN Write('.') ELSE Write(ch1) END;
      IF (i MOD 16) = 15 THEN Write('*'); WriteLn END;
    END
  END CharDump;

PROCEDURE DiskSwitch;
  VAR ch : CHAR;
BEGIN
  WriteString('current disk was ');
  IF currentdisk = removable THEN WriteString('removable')
  ELSE WriteString('fix')
  END;
  WriteLn;
  WriteString('current disk will be:  R(emovable)/F(ix)');
  LOOP
    Read(ch); IF ch >= 'a' THEN ch := CAP(ch) END;
    IF ch = 'R' THEN currentdisk := removable; EXIT
    ELSIF ch = 'F' THEN currentdisk := fixed; EXIT
    ELSIF (ch=' ') OR (ch=36c) THEN EXIT
    ELSE Write('?')
    END
  END;
  WriteLn;
  WriteString('current disk is now ');
  IF currentdisk = removable THEN WriteString('removable')
  ELSE WriteString('fix')
  END;
  WriteLn;
END DiskSwitch;

PROCEDURE GetSector;
(*---------------*)
(* this procedure searches for a file that contains a specific sector *)
  CONST nilPage=4704;(* this page is a NIL pointer *)
  VAR sect : CARDINAL; (* current sector *)
      i    : CARDINAL; (* index in directory blocks *)
      searched : CARDINAL; (* searched sector *)
      er   : dkerrors; (* disk error *)
BEGIN WriteStringLn('et file to sector');
  WriteString('which sector='); ReadOct(searched); WriteLn;
  searched := searched DIV 8; (* pages are allocated in blocks of 8 sectors *)
  sect := 0;
  LOOP
    diskdriver(currentdisk, dkread, StartDir+sect, ADR(directory), er);
    IF er <> ok THEN PrintError( er, StartDir+sect)
    ELSIF directory.fdt <> 0 (* sector in use *) THEN
      FOR i := 0 TO 95 (* max page*) DO
        IF directory.pagetab[i] DIV 13 = searched THEN
          WriteString('directory sector='); WriteOct(sect,6); WriteLn;
          DisplayFileName(sect); EXIT
        END;
      END (* FOR *)
    END; (* IF er<>ok *)
    IF sect = maxFile THEN WriteStringLn('not allocated'); EXIT END;
    INC(sect);
  END (* LOOP *)
END GetSector;


PROCEDURE FindName;
(*---------------*)
  (* find a given string in a name directory;
     reports its position *)
  CONST max = 23;
  VAR s : ARRAY [1..max+1] OF CHAR;
      i : CARDINAL; ch : CHAR;
      found : BOOLEAN;

  PROCEDURE search( VAR i : CARDINAL);
    VAR sect, j, k : CARDINAL; er : dkerrors;
    BEGIN found := FALSE;
      FOR sect := 0 TO 140b DO
        diskdriver(currentdisk, dkread, StartNameD+sect, ADR(NameBlock), er);
        IF er <> ok THEN PrintError( er, StartNameD+i) END;
        FOR j := 0 TO 7 DO
          k := 0;
          LOOP
            IF NameBlock[j].en[k] <> s[k+1] THEN  EXIT END;
            INC(k);
            IF k > max THEN found := TRUE; i := sect*8+j; RETURN END;
          END;
        END;
      END
    END search;

  BEGIN WriteString('ind a name'); WriteLn;
    WriteString('name=');
    FOR i := 1 TO max+1 DO s[i] := ' ' END;
    i := 0;
    LOOP Read(ch);
      IF ch = 36c THEN EXIT END;
      IF ch = 177c THEN
        IF i > 0 THEN s[i] := ' '; Write(177c); DEC(i); END;
      ELSIF i <= max THEN INC(i); s[i] := ch; Write(ch);
      END
    END;
    WriteLn;
    search(i);
    IF found THEN WriteString('sector number is='); WriteOct(i,6); WriteLn;
    ELSE WriteString('not found')
    END;
  END FindName;


PROCEDURE Inspect;
(*--------------*)
  VAR adr : ADDRESS; help : ADDRESS; help1 : CARDINAL;
  BEGIN WriteString('nspect');
    WriteLn;
    WriteString('address:'); ReadOct(adr); ch := delim; help := InspBase+adr;
    LOOP
      IF ch=33c THEN RETURN END;
      WriteOct(CARDINAL(help^),7); ReadEcho(ch);
      IF ch = ':' THEN  ReadOct(help1); ch := delim; help^ := WORD(help1) END;
      IF ch = ',' THEN INC(help); INC(adr); WriteLn;
          WriteOct(CARDINAL(adr),6); Write(' ')
        ELSE EXIT
      END
    END
  END Inspect;

PROCEDURE Konsistency (*check*);
(*------------------*)
(* This procedure check if directory is in a consistent state *)
  CONST free = 0FFFFh; (* free entry in pageArray *)
        nilPage=4704*13;(* this page is a NIL pointer *)
  VAR sect : CARDINAL; (* current sector *)
      i    : CARDINAL; (* index in directory blocks *)
      j    : CARDINAL;
      help : CARDINAL;
      ch   : CHAR; (* dummy for interruption *)
      er   : dkerrors; (* disk error *)
      pageArray: ARRAY[0..maxFilePage] OF CARDINAL; (* list of all pages used by
                                           the file system *)

  BEGIN WriteString('onsistency check'); WriteLn;

    (* check if no blocks are used by two files *)
    (* set all pages free *)
    FOR help := 0 TO maxFilePage DO pageArray[help] := free END;
    FOR sect := 0 TO maxFile DO
      diskdriver(currentdisk, dkread, StartDir+sect, ADR(directory), er);
      IF (er <> ok) AND (er<>illsect) THEN PrintError( er, StartDir+sect);
         DisplayFileName(sect); WriteLn;
         IF Key() THEN Read(ch) END;
      ELSE
        IF directory.filno<>sect THEN
          WriteString('bad fno='); WriteOct(directory.filno,6);
          WriteString(' on sector='); WriteOct(sect,6); WriteLn;
          DisplayFileName(sect);
          IF Key() THEN Read(ch) END;
        END;
        IF directory.fdt <> 0 (* sector in use *) THEN
          FOR i := 0 TO 95 (* max page*) DO
            help := directory.pagetab[i];
            (* all page pointers must be dividable by 13 *)
            IF (help MOD 13) <> 0 THEN WriteString('wrong page pointer, dir sector= ');
              WriteOct(sect,6); WriteString(' pointer='); WriteOct(help,6); WriteLn;
              DisplayFileName(sect);
              IF Key() THEN Read(ch) END;
            ELSIF help <> nilPage THEN
              help := help DIV 13;
              IF pageArray[help] <> free THEN
                WriteString('double allocated page, page='); WriteOct(help*13,6);
                WriteString(' dir entries:'); WriteOct(pageArray[help],6);
                Write(' '); WriteOct(sect,6); WriteLn;
                DisplayFileName(sect); DisplayFileName(pageArray[help]);
                IF Key() THEN Read(ch) END;
              ELSE pageArray[help] := sect
              END;
            END
          END (* for all pages *)
        END (* IF kind <> 0*)
      END; (* if er <> ok*)
    END; (* FOR *)

    (* now check if the information in the name directory corresponds to the
       information in the block directory 
       following fields are checked: kind, version *)
    FOR i := 0 TO maxFile DIV 8 (* 8 entries for one name dir sector *) DO
      diskdriver(currentdisk, dkread, StartNameD+i, ADR(NameBlock), er);
      IF (er <> ok)  AND (er<>illsect) THEN PrintError( er, StartNameD+i)
      ELSE
        FOR j := 0 TO 7 (* all entries within a sector *) DO
          WITH NameBlock[j] DO
            IF nk = fname (* entry is in use *) THEN
              sect := fno;
              diskdriver(currentdisk, dkread, StartDir+sect, ADR(directory), er);
              IF er <> ok THEN PrintError( er, StartDir+sect);
                IF Key() THEN Read(ch) END;
              ELSE
                IF directory.fdt = nofile THEN
                  WriteString('name dir points to free block, name dir sect=');
                  WriteOct(8*i+j,6); WriteString(' block dir sect=');
                  WriteOct(sect,6); WriteLn;
                  DisplayName(j); WriteLn;
                  IF Key() THEN Read(ch) END;
                END;
                IF vno<>directory.versno (* version # conflict *) THEN
                  WriteString('version# conflict, name dir sect='); WriteOct(8*i+j,6);
                  WriteString(' version='); WriteOct(vno,6); WriteLn;
                  WriteString(' block dir sect='); WriteOct(sect,6); 
                  WriteString(' version='); WriteOct(directory.versno,6); WriteLn;
                  DisplayName(j); WriteLn;
                  IF Key() THEN Read(ch) END;
               END;
              END (* IF diskerrors *)
            END (* IF entry in use *)
          END (* WITH *)
        END (* FOR *)
      END (* IF diskerrors *)
    END (* for all sectors *);

    (* now check if there are any hard errors in the boot area *)
    FOR sect := 0 TO EndBoot2 DO
      diskdriver(currentdisk, dkread, sect, ADR(sector), er);
      IF er <> ok THEN PrintError( er, sect);
        IF Key() THEN Read(ch) END;
      END
    END;

    WriteString('done');
  END Konsistency;  

PROCEDURE IllBlock;
(*---------------*)
(* builds a list of illegal block on the disk *)
  VAR i, sect : CARDINAL;
      er : dkerrors;
      AlreadyBadBlock : BOOLEAN; (* already one bad block was found in a track *)
      BadData : BOOLEAN; (* the sector contains bad data *)

  PROCEDURE DisplayBadBlocks(name : String; VAR array : IBarray; index : CARDINAL);
   VAR i : CARDINAL; NoBadBlocks : BOOLEAN;
    BEGIN WriteLn;
      WriteString('Nr of '); WriteString(name); WriteString(' bad blocks:');
      WriteOct(index,6); WriteLn;
      IF index > 0 THEN
        FOR i := 0 TO index-1 DO
          WriteOct(array[i],6); Write(' ');
          IF (i MOD 8) = 7 THEN WriteLn END
        END;
        WriteLn;
        NoBadBlocks := TRUE;
        WriteString('following '); WriteString(name);
        WriteString('  bad blocks are inside of a fixed files='); WriteLn;
        FOR i := 0 TO index-1 DO
          sect := array[i];
          IF (StartBoot1 <= sect) AND (sect <= EndBoot1) THEN
            WriteString('boot1 '); WriteOct(sect,6); WriteLn; NoBadBlocks := FALSE;
          ELSIF (StartDump1 <= sect) AND (sect <= EndDump1) THEN
            WriteString('dump1 '); WriteOct(sect,6); WriteLn; NoBadBlocks := FALSE;
          ELSIF (StartBoot2 <= sect) AND (sect <= EndBoot2) THEN
            WriteString('boot2 '); WriteOct(sect,6); WriteLn; NoBadBlocks := FALSE;
          ELSIF (StartDir <= sect) AND (sect <= EndDir) THEN
            WriteString('directory '); WriteOct(sect,6); WriteLn; NoBadBlocks := FALSE;
          ELSIF (StartNameD <= sect) AND (sect <= EndNameDir) THEN
            WriteString('name directory '); WriteOct(sect,6); WriteLn; NoBadBlocks := FALSE;
          ELSIF (StartBackD <= sect) AND (sect <= EndBackD) THEN
            WriteString('directory back up '); WriteOct(sect,6); WriteLn;NoBadBlocks := FALSE;
          ELSIF (StartBND <= sect) AND (sect <= EndBND) THEN
            WriteString('name directory back up '); WriteOct(sect,6); WriteLn;
            NoBadBlocks := FALSE;;
          END;
        END;
        IF NoBadBlocks THEN WriteString('none'); WriteLn END;
      END;
    END DisplayBadBlocks;

  BEGIN (* Illblock *) WriteLn;
    WriteString('illegal block build up'); WriteLn;
    WriteString('you will now overwrite the whole disk,  do you want it y/n ');
    ReadEcho(ch); ch := CAP(ch);
    IF ch <> 'Y' THEN RETURN END;
    WriteLn;

    inxIB := 0; inxDIB := 0;  (* reset both indexes *)
    FOR sect := 0 TO 127 DO sector[sect] := sect END;

    WriteString('writing all sectors....');
    (* write all sectors *)
    sect := maxsector + 1;
    REPEAT
     DEC(sect);
     sector[0] := sect; sector[127] := 177777b - sect;
     diskdriver(currentdisk, dkwrite, sect, ADR(sector), er);
     IF NOT (er IN dkerrset{ok, illsect, doubleillsect}) THEN PrintError(er, sect) END;
    UNTIL sect = 0;
    WriteLn;

    WriteString('reading all sectors....'); WriteLn;
    (* now read it again *);
    sect := 0;
    REPEAT
      IF (sect MOD 48) = 0 THEN AlreadyBadBlock := FALSE; END;
      diskdriver(currentdisk, dkread, sect, ADR(sector), er);
      IF NOT(er IN dkerrset{ok, illsect, doubleillsect}) THEN PrintError(er,sect) END;
      IF ((sector[0] <> sect) OR (sector[127] <> 177777b-sect)) 
           AND (er<>doubleillsect) THEN
           WriteString('bad data on sector:'); WriteOct(sect,6); WriteLn;
           BadData := TRUE
      ELSE BadData := FALSE
      END;

      IF er=doubleillsect THEN AlreadyBadBlock := TRUE END;
      IF (er <> ok) OR BadData THEN
        IF (NOT AlreadyBadBlock) AND (er=illsect) THEN
          IF inxIB > maxIB THEN WriteString('too many illegal blocks'); WriteLn
          ELSE illblock[inxIB] := sect; INC(inxIB);
            AlreadyBadBlock := TRUE
          END
        ELSE
          IF inxDIB > maxDIB THEN WriteString('too many illegal blocks'); WriteLn
          ELSE DoubleIllBlock[inxDIB] := sect; INC(inxDIB);
          END
        END;
      END;      
      INC(sect);
    UNTIL sect >= maxsector;

  (* display bad blocks *)
  DisplayBadBlocks('double', DoubleIllBlock, inxDIB);
  DisplayBadBlocks('single', illblock, inxIB);
  
  WriteString('now initiate the directory using the the "Z" command'); WriteLn;
  WriteString('and set the illegal block info into the directory ');
  WriteString('using the "S" command'); WriteLn;

  END IllBlock;

PROCEDURE NameDirUpdate;
(*--------------------*)
(* update the name directory *)

  PROCEDURE DisplayNDir;
    VAR i, j : CARDINAL;
    BEGIN
      FOR i := 0 TO 7 DO
        WITH NameBlock[i] DO
          WriteString('name('); WriteOct(i*16,3); WriteString(')='); DisplayName(i);
          WriteLn;
          WriteString('kind (');WriteOct(i*16+14b,3); WriteString(')='); WriteOct(nk,6);
          WriteString('  file#(');WriteOct(i*16+15b,3); WriteString(')='); WriteOct(fno,6);
          WriteString('  version#(');WriteOct(i*16+16b,3); WriteString(')=');WriteOct(vno,6);
          WriteString('  reserved(');WriteOct(i*16+17b,3); WriteString(')=');WriteOct(fres,6);
          WriteLn;
        END
      END
    END DisplayNDir;

  PROCEDURE NameChange;
  (*----------------- exchange the name of a file *)
    VAR i,j : CARDINAL; ch : CHAR;
  BEGIN
    LOOP
      WriteLn;
      WriteString('index of the name:');
      Read(ch);
      IF (ch >= '0') AND (ch <= '7') THEN EXIT END
    END;

    WITH NameBlock[ORD(ch) - ORD('0')] DO
      FOR i := 0 TO 23 DO
        IF en[i] >= ' ' THEN Write(en[i]) ELSE Write('!') END;
      END;
      Write(':');
      i := 0;
      LOOP
        Read(ch); 
        IF ch = EOL THEN EXIT
        ELSIF ch = 177c THEN
          IF i > 0 THEN Write(177c); DEC(i) END
        ELSIF ch >= '.' THEN Write(ch); en[i] := ch; INC(i)
        END;
        IF i > 23 THEN EXIT END
      END;
      FOR j := i TO 23 DO en[j] := ' ' END;
    END;
  END NameChange;
          
  PROCEDURE ReadSector;
  (*-----------------*)
    VAR i : CARDINAL; er : dkerrors; 
    BEGIN WriteString('ead sector'); WriteLn;
      WriteString('sector number='); ReadOct(i); ch := delim;
      IF (i=0) THEN
         IF (ch=',') THEN INC(CrntNDir); i := CrntNDir; WriteOct(i,6)
         ELSIF (ch = '=') THEN i := CrntNDir; WriteOct(i,6)
         END;
      END;
      CrntNDir := i;
      diskdriver(currentdisk, dkread, StartNameD+i, ADR(NameBlock), er);
      IF er <> ok THEN PrintError( er, StartNameD+i) END;
    END ReadSector;

  PROCEDURE WriteSector;
  (*------------------*)
    VAR i : CARDINAL; er : dkerrors;
    BEGIN WriteString('rite sector'); WriteLn;
      WriteString('sector number='); ReadOct(i); ch := delim;
      IF (i=0) AND (ch='=') THEN  i := CrntNDir; WriteOct(i,6) END;
      WriteString(' Y/N?');
      ReadEcho(ch); ch := CAP(ch);
      IF ch <> 'Y' THEN RETURN END;
      WriteLn; 
      diskdriver(currentdisk, dkwrite, StartNameD+i, ADR(NameBlock), er);
      IF er <> ok THEN PrintError(er, StartNameD+i) END;
    END WriteSector;

  BEGIN  (* name directory update *)
    WriteString('ame directory update'); WriteLn;
    WriteString('Display; NameChange; Inspect; Read; Write');
    LOOP
      WriteLn; WriteString('..');
      ReadEcho(ch); ch := CAP(ch);
      CASE ch OF
      'D': DisplayNDir |
      'N': NameChange |
      'I': InspBase := ADR(NameBlock); Inspect  |
      'R': ReadSector  |
      'W': WriteSector |
      33c: EXIT
      ELSE Write('?')
      END
    END 
  END NameDirUpdate;

PROCEDURE OctalDump;
(*----------------*)
  VAR i : CARDINAL;
  BEGIN WriteString('ctal dump'); WriteLn;
    FOR i := 0 TO 127 DO
      IF (i MOD 8) = 0 THEN WriteOct(i,6); Write(':') END;
      WriteOct(sector[i],6); Write(' ');
      IF (i MOD 8) = 7 THEN WriteLn END;
    END
  END OctalDump;

PROCEDURE ReadSector;
(*-----------------*)
  VAR i : CARDINAL; er : dkerrors; 
  BEGIN WriteString('ead sector'); WriteLn;
    WriteString('sector number='); ReadOct(i); ch := delim;
    IF (i=0) THEN
      IF (ch=',') THEN INC(CrntSect); i := CrntSect ; WriteOct(i,6)
      ELSIF (ch = '=') THEN i := CrntSect; WriteOct(i,6)
      END;
    END;
    CrntSect := i;
    diskdriver(currentdisk, dkread, i, ADR(sector), er);
    IF er <> ok THEN PrintError( er, i) END;
  END ReadSector;

PROCEDURE SetIlBlock;
(*-----------------*)
  VAR er : dkerrors; i : CARDINAL;
  BEGIN WriteString('et illegal blocks into directory'); WriteLn;
  (* set the information, that has already be prepared by the 'L' command
     into the directory file 'BAD.BLOCKS' *)
  (* update directory *)
    IF inxDIB > 0 THEN
      WriteString('did you already run the "L" command?  and'); WriteLn;
      WriteString('do you want to link the illegal blocks in a FS.BadPacges file? y/n ');
      ReadEcho(ch); ch := CAP(ch);
      IF ch <> 'Y' THEN WriteString('sorry..'); RETURN END;

      diskdriver( currentdisk, dkread, StartDir+4, ADR(directory), er);
      IF er <> ok THEN
        WriteString('problems... not done'); RETURN
      END;
 
      FOR i := 0 TO inxDIB-1 DO
        directory.pagetab[i] := DoubleIllBlock[i] DIV 10b * 13;
      END;
      directory.length.block := (inxDIB) * 10b;
      directory.length.byte  := 0;
 
      diskdriver( currentdisk, dkwrite, StartDir+4, ADR(directory), er);
      IF er <> ok THEN
        WriteString('problems... not done')
      END;
    ELSE WriteString('no double illegal blocks')
    END
  END SetIlBlock;

PROCEDURE Transfer;
(*---------------*)
 (* transfers a number of blocks between the upper and lower disk of the D140 *)
 VAR fromdisk, todisk : disktype;
     i, low, high : CARDINAL; ch : CHAR; er : dkerrors;
  BEGIN WriteString('ransfer between disks'); WriteLn;
    WriteString('source disk Fixed/Removable  => f/r:');
    LOOP
      ReadEcho(ch);
      IF ch='f' THEN fromdisk := fixed; todisk := removable; EXIT ;
      ELSIF ch = 'r' THEN fromdisk := removable; todisk := fixed; EXIT ;
      END;
      Write('?')
    END; WriteLn;
    WriteString('low limit:'); ReadOct(low); WriteLn;
    WriteString('high limit:'); ReadOct(high); WriteLn;

    FOR i := low TO high DO
      diskdriver(fromdisk, dkread, i, ADR(sector), er);
      IF er <> ok THEN PrintError(er, i) END;
      diskdriver(todisk, dkwrite, i, ADR(sector), er);
      IF er <> ok THEN PrintError(er, i) END;
    END;
  END Transfer;

PROCEDURE UpdateDir;
(*----------------*)
(* update main directory *) 

  PROCEDURE DisplayDirectory;
    VAR i : CARDINAL;
    BEGIN WriteString('isplay'); WriteLn;
      WITH directory DO
        WriteString('Directory sector number='); WriteOct(CrntDir,6); WriteLn; WriteLn;
        WriteString('reserved(0)    ='); WriteOct(reserved,6); WriteLn;
        WriteString('file#(1)       ='); WriteOct(filno,6); WriteLn;
        WriteString('Version Nr(2)  ='); WriteOct(versno,6); WriteLn;
        WriteString('kind(3)        ='); WriteOct(fdt,6); WriteLn;
        WriteString('length.block(4)='); WriteOct(length.block,6); WriteLn;
        WriteString('length.byte(5) ='); WriteOct(length.byte,6); WriteLn;
        WriteString('modification(6)='); WriteOct(modification,6); WriteLn;
        WriteString('referenced(7)  ='); WriteOct(referenced,6); WriteLn;
        WriteString('protection(10) ='); WriteOct(protection,6); WriteLn;
        WriteString('son tables(21) ='); WriteLn;
        FOR i := 1 TO 15 DO
          WriteOct(sontab[i],6); Write(' ');
          IF i=8 THEN WriteLn END
        END;
        WriteLn;
        WriteString('page table(40)='); WriteLn;
        FOR i := 0 TO 95 DO
          WriteOct(pagetab[i],6); Write(' ');
          IF (i MOD 8) = 7 THEN WriteLn END
        END;
      END (* with *)
    END DisplayDirectory;


  PROCEDURE ReadSector;
  (*-----------------*)
    VAR i : CARDINAL; er : dkerrors; 
    BEGIN WriteString('ead sector'); WriteLn;
      WriteString('sector number='); ReadOct(i); ch := delim;
      IF (i=0) THEN
        IF (ch=',') THEN INC(CrntDir); i := CrntDir; WriteOct(i,6)
        ELSIF (ch = '=') THEN i := CrntDir; WriteOct(i,6);
        END
      END;
      CrntDir := i;
      diskdriver(currentdisk, dkread, StartDir+i, ADR(directory), er);
      IF er <> ok THEN PrintError( er, StartDir+i) END;
    END ReadSector;

  PROCEDURE WriteSector;
  (*------------------*)
    VAR i : CARDINAL; er : dkerrors;
    BEGIN WriteString('rite sector'); WriteLn;
      WriteString('sector number='); ReadOct(i); ch := delim;
      IF (i=0) AND (ch='=') THEN  i := CrntDir; WriteOct(i,6) END;
      WriteString(' Y/N?');
      ReadEcho(ch); ch := CAP(ch);
      IF ch <> 'Y' THEN RETURN END;
      WriteLn; 
      diskdriver(currentdisk, dkwrite, StartDir+i, ADR(directory), er);
      IF er <> ok THEN PrintError(er, StartDir+i) END;
    END WriteSector;

  BEGIN WriteString('pdate directory'); WriteLn;
    WriteString('Display; Inspect; Read; Write'); WriteLn;
    LOOP WriteLn; WriteString('..');
      ReadEcho(ch); ch := CAP(ch);
      CASE ch OF
      'D': DisplayDirectory |
      'I': InspBase := ADR(directory); Inspect|
      'R': ReadSector|
      'W': WriteSector|
      33c: EXIT
      ELSE Write('?')
      END
    END
  END UpdateDir;

PROCEDURE WriteSector;
(*------------------*)
  VAR i : CARDINAL; er : dkerrors;
  BEGIN WriteString('rite sector'); WriteLn;
    WriteString('sector number='); ReadOct(i); ch := delim;
    IF (i=0) AND (ch='=') THEN  i := CrntSect; WriteOct(i,6) END;
    WriteString(' Y/N?');
    ReadEcho(ch); ch := CAP(ch);
    IF ch <> 'Y' THEN RETURN END;
    WriteLn;    
    diskdriver(currentdisk, dkwrite, i, ADR(sector), er);
    IF er <> ok THEN PrintError(er, i) END;
  END WriteSector;

PROCEDURE DiskXfer;
(*---------------*)
  BEGIN
    WriteString('not implemented yet'); WriteLn
  END DiskXfer;

PROCEDURE ZeroDirectory;
(*--------------------*)
(* initialise directory *)
  VAR er: dkerrors; i : CARDINAL;

  PROCEDURE InitFile(fnr, base, blocks : CARDINAL);
  (*---------------*)
    VAR i : CARDINAL;
    BEGIN
      diskdriver(currentdisk, dkread, StartDir+fnr, ADR(directory), er);
      IF er <> ok THEN PrintError(er, i) END;
      WITH directory DO
        fdt := 1; length.block := blocks; referenced := 1;       
        blocks := (blocks + 7) DIV 8;
        ctime.day := time.day;
        ctime.minute := time.minute;
        FOR i := 1 TO blocks DO
          pagetab[i-1] := (base + i - 1) * 13;
        END;
        FOR i := 1 TO 15 DO sontab[i] := 177777b END;
      END;
      diskdriver(currentdisk, dkwrite, StartDir+fnr, ADR(directory), er);
      IF er <> ok THEN PrintError(er, i) END;
    END InitFile;

  PROCEDURE InitName(name : ExternalName; filenr : CARDINAL);
  (*---------------*)
    VAR namesect : CARDINAL;
    BEGIN
      diskdriver(currentdisk, dkread, StartNameD+filenr DIV 8, ADR(NameBlock), er);
      IF er <> ok THEN PrintError(er, i) END;

      WITH NameBlock[filenr MOD 8] DO
        en:= name; nk := 1; fno := filenr; vno := 177777b; 
      END;

      diskdriver(currentdisk, dkwrite, StartNameD+filenr DIV 8, ADR(NameBlock), er);
      IF er <> ok THEN PrintError(er, i) END;
    END InitName;
  
      
  BEGIN WriteString('ero directory'); WriteLn;
    WriteString('you will now overwrite the whole directory,  do you want it y/n ');
    ReadEcho(ch); ch := CAP(ch);
    IF ch <> 'Y' THEN RETURN END;

    GetTime(time);

    WITH directory DO
      reserved := 0; (*filno will be set later *); versno := 177777b;
      FOR i := 0 TO 27 DO filler[i] := 0 END;
      FOR i := 0 TO 95 DO pagetab[i] := 4704*13 END;
      fdt := 0 (* nofile *);
    END;

    FOR i := 0 TO 767 DO
      directory.filno := i;
      diskdriver(currentdisk, dkwrite, StartDir+i, ADR(directory), er);
      IF er <> ok THEN PrintError(er, i) END;
    END;

     FOR i := 0 TO 7 DO
       WITH NameBlock[i] DO
         en := '                        ';
         nk := 0; fno := 0; vno := 0; fres := 0;
       END;
     END;

    FOR i := 0 TO 767 DIV 8 DO
      diskdriver(currentdisk, dkwrite, StartNameD+i, ADR(NameBlock), er);
      IF er <> ok THEN PrintError(er, i) END;
    END;
 
    InitFile(0, 2256, 768);   
    InitFile(1, 4596, 768);
    InitFile(2, 2352, 96);
    InitFile(3, 4692, 96);
    InitFile(4, 0,    0);
    InitFile(5, 0,    192);
    InitFile(6, 156,  192);
    InitFile(7, 24,   512);
    InitFile(8, 88,   512);
    InitName('FS.FileDirectory        ',0);
    InitName('FS.FileDirectory.Back   ',1);
    InitName('FS.NameDirectory        ',2);
    InitName('FS.NameDirectory.Back   ',3);
    InitName('FS.BadPages             ',4);
    InitName('PC.BootFile             ',5);
    InitName('PC.BootFile.Back        ',6);
    InitName('PC.DumpFile             ',7);
    InitName('PC.Dump1File            ',8);
 
  END ZeroDirectory;

PROCEDURE calculator;
(*-----------------*)
VAR x,y : CARDINAL; ch, ch1 : CHAR;
BEGIN WriteString(' octal calculator'); WriteLn;
  LOOP WriteString('..');
    ReadOct(x); ch := delim;
    IF ch = 33c THEN EXIT END;
    ReadOct(y); 
    CASE ch OF
       '+': WriteOct(x+y,6)
    |  '-': WriteOct(x-y,6)
    |  '*': WriteOct(x*y,6)
    |  '/': WriteOct(x DIV y,6)
    |  33c: EXIT
    ELSE Write('?')
    END;
    WriteLn;
  END
END calculator;
    

BEGIN (* MAIN *)
  Introduction; currentdisk := removable; 
  InspBase := ADR(sector);
  LOOP
    WriteLn; Write('>');
    ReadEcho(ch); IF ch>='a' THEN ch := CAP(ch) END;
    CASE ch OF
    'B': BadBlockLink |
    'C': CharDump   |
    'D': DiskSwitch |
    'G': GetSector  |
    'F': FindName   |
    'I': InspBase := ADR(sector); Inspect    |
    'K': Konsistency |
    'L': IllBlock   |
    'N': NameDirUpdate|
    'O': OctalDump  |
    'R': ReadSector |
    'S': SetIlBlock |
    'T': Transfer   |
    'U': UpdateDir  |
    'W': WriteSector|
    'X': DiskXfer   |
    'Z': ZeroDirectory|
    '+': calculator |
    '?': GlobalMenu |
    33c: WriteString('do you want to leave and boot? y/n:');
         ReadEcho(ch); ch := CAP(ch);
         IF ch = 'Y' THEN Boot(0) END
    ELSE Write('?')
    END;
  END;
END DiskPatch.
