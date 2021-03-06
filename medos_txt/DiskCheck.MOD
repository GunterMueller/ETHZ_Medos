MODULE DiskCheck;
(* author Jirka Hoppe
          Institut for Informatics
          ETH Zurich *)
(* version 9/5/83 *)
(* this program checks the consistency of a disk
   small problems may be corrected by this program
   for big problems use the program 'DiskPatch'  *)

FROM SYSTEM IMPORT ADR, ADDRESS, WORD;
FROM JIO IMPORT ReadEcho, WriteOct, WriteStringLn;
FROM Terminal IMPORT Write, Read, BusyRead, WriteLn, WriteString;
FROM Jdisk IMPORT readwrite, dkerrors, disktype, diskdriver, PrintError;
FROM DiskSystem IMPORT FileNumber, FDKind, Minute, Page, FileDesc, nofile, fname,
                NameKind, ExternalName, Name,
                InitVolume, ReadFileDesc, WriteFileDesc, ReadName, WriteName;

CONST
  maxsector = 37631; (* maximal sector number *)
  maxFile   = 767  ;  (* maximal number of files *)
  maxFilePage=392*12-1; (* number of pages used by the file system *)
  maxIB     = 95;    (* maximal number of single illegal blocks *)
  maxDIB    =  95;   (* maximal number of double illegal blocks *)
  (*  addresses of fixed files *)
  StartBoot1= 0;     (* start sector of boot1 file *)
  EndBoot1  = 191;   (* end of boot1 *)
  EndBoot2  = 1439;  (* end of boot2 *)
  StartDir  = 43200b;(* start of directory *)
  EndDir    = 44577b;(* end of directory *)
  StartNameD= 44600b;(* start of name directory *)
  EndNameDir= 44737b;(* end of name directory *)

TYPE dkerrset = SET OF dkerrors;

VAR sector : ARRAY [0..127] OF CARDINAL;
    directory : FileDesc;               (* local copy of a directory segment *)
    NameBlock : ARRAY [0..7] OF Name;   (* local copy of a name directory segment *)
    currentdisk : disktype;
    fixupOn    : BOOLEAN; (* we try some fix up's *)
    noQuery : BOOLEAN; (* do not ask for each fix, do it automaticaly *)
    ch : CHAR;

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

(*--------------------*)

PROCEDURE Key(): BOOLEAN;
(*----------- TRUE if key was hit *)
  VAR ch: CHAR;
BEGIN BusyRead(ch);
  RETURN(ch<>0C)
END Key;


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
(* tries to display the file name corresponding to the block directory sector 'sect' *)
VAR er : dkerrors;
BEGIN
  WriteString('file name=');
  diskdriver(currentdisk, dkread, StartNameD+(sect DIV 8), ADR(NameBlock), er);
  IF NOT(er IN dkerrset{ok, illsect, doubleillsect}) THEN
    PrintError( er, StartNameD+(sect DIV 8))
  END;
  IF NameBlock[sect MOD 8].fno=sect (* sector# match *) THEN DisplayName(sect MOD 8)
  ELSE WriteString('?????')
  END;
  WriteLn;
END DisplayFileName;

PROCEDURE GetSector(searched : CARDINAL);
(*---------------*)
(* this procedure searches for a file that contains a specific sector *)
  CONST nilPage=4704;(* this page is a NIL pointer *)
  VAR sect : CARDINAL; (* current sector *)
      i    : CARDINAL; (* index in directory blocks *)
      er   : dkerrors; (* disk error *)
BEGIN  searched := searched DIV 8; (* pages are allocated in blocks of 8 sectors *)
  sect := 0;
  LOOP
    diskdriver(currentdisk, dkread, StartDir+sect, ADR(directory), er);
    IF NOT(er IN dkerrset{ok, illsect, doubleillsect}) THEN PrintError( er, StartDir+sect)
    ELSIF directory.fdt <> 0 (* sector in use *) THEN
      FOR i := 0 TO 95 (* max page*) DO
        IF directory.pagetab[i] DIV 13 = searched THEN
          DisplayFileName(sect); EXIT
        END;
      END (* FOR *)
    END; (* IF er<>ok *)
    IF sect = maxFile THEN WriteStringLn('not allocated'); EXIT END;
    INC(sect);
  END (* LOOP *)
END GetSector;

PROCEDURE CheckSectors(low, high : CARDINAL);
(*------------------*)
(* check all sectors between low and high for HW errors *)
  VAR sect : CARDINAL; (* current sector *)
      er   : dkerrors; (* disk error *)
      ch : CHAR;
BEGIN
  FOR sect := low TO high DO
    diskdriver(currentdisk, dkread, sect, ADR(sector), er);
    IF NOT(er IN dkerrset{ok, illsect, doubleillsect}) THEN PrintError( er, sect);
      IF fixupOn THEN
        IF NOT  noQuery THEN WriteString('do you like like me to fix this sector?  y/n:');
          ReadEcho(ch); ch := CAP(ch); WriteLn;
        END;
        IF (ch='Y') OR noQuery THEN
          diskdriver(currentdisk, dkwrite, sect, ADR(sector), er);
          diskdriver(currentdisk, dkread, sect, ADR(sector), er);
          IF NOT(er IN dkerrset{ok, illsect, doubleillsect}) THEN
            PrintError( er, sect); WriteStringLn('this error was not fixed');
          END
        END
      END;
      IF Key() THEN Read(ch) END;
    END
  END;
END CheckSectors;

PROCEDURE Konsistency (*check*);
(*------------------*)
(* This procedure check if directory is in a consistent state *)
  CONST free = 0FFFFh; (* free entry in pageArray *)
        nilPage=4704*13;(* this page is a NIL pointer *)
  VAR sect : CARDINAL; (* current sector *)
      i    : CARDINAL; (* index in directory blocks *)
      j    : CARDINAL;
      help : CARDINAL;
      er   : dkerrors; (* disk error *)
      pageArray: ARRAY[0..maxFilePage] OF CARDINAL; (* list of all pages used by
                                           the file system *)

  BEGIN WriteString('checking your disk....'); WriteLn;
    CheckSectors(StartDir, EndDir); CheckSectors(StartNameD, EndNameDir);

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
                WriteString('double allocated page, page=');
                WriteOct(help*13,6);
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
      IF (er <> ok) AND (er<>illsect) THEN PrintError( er, StartNameD+i)
      ELSE
        FOR j := 0 TO 7 (* all entries within a sector *) DO
          WITH NameBlock[j] DO
            IF nk = fname (* entry is in use *) THEN
              IF fno > maxFile THEN
                WriteString('bad pointer: name->block directory, sector=');
                WriteOct(i,6); WriteLn;
                IF Key() THEN Read(ch) END;
              ELSE
                sect := fno;
                diskdriver(currentdisk, dkread, StartDir+sect, ADR(directory), er);
                IF (er <> ok) AND (er<>illsect) THEN PrintError( er, StartDir+sect);
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
              END (* IF fno < maxFile *)
            END (* IF entry in use *)
          END (* WITH *)
        END (* FOR *)
      END (* IF diskerrors *)
    END (* for all sectors *);

    (* now check if there are any hard errors in the boot area *)
    CheckSectors(0, EndBoot2);

    WriteString('done');
  END Konsistency;  

PROCEDURE CheckAllSectors;
  VAR sect : CARDINAL;
      er   : dkerrors;
      ch   : CHAR;
BEGIN
  sect := EndBoot2;
  REPEAT
    diskdriver(currentdisk, dkread, sect, ADR(sector), er);
    IF NOT(er IN dkerrset{ok, illsect, doubleillsect}) THEN
      PrintError(er,sect); GetSector(sect);
      IF fixupOn THEN 
        IF NOT noQuery THEN WriteString('do you like like me to fix this sector?  y/n:');
          ReadEcho(ch); ch := CAP(ch); WriteLn;
        END;
        IF (ch='Y') OR noQuery THEN
          diskdriver(currentdisk, dkwrite, sect, ADR(sector), er);
          diskdriver(currentdisk, dkread, sect, ADR(sector), er);
          IF NOT(er IN dkerrset{ok, illsect, doubleillsect}) THEN
            PrintError( er, sect); WriteStringLn('this sector was not fixed');
          END
        END
      END;
      IF Key() THEN Read(ch) END;
    END;
    INC(sect);
  UNTIL sect >= maxsector;
END CheckAllSectors;

BEGIN (* MAIN *)
  currentdisk := removable;
  WriteString('do you like to try some fixes?  y/n:'); 
  ReadEcho(ch); ch := CAP(ch); WriteLn;
  fixupOn := (ch='Y');
  IF fixupOn THEN
    WriteString('do you like to confirm all fixes? y/n:');
    ReadEcho(ch); ch := CAP(ch); WriteLn;
    noQuery := (ch='N');
  END;
  Konsistency;
  WriteLn;
  WriteStringLn('if no errors were reported above, your directory is OK');
  WriteStringLn('do you like all sectors to be checked for hardware errors?');
  WriteString('it will take about 5 minutes     Y/N? ');
  ReadEcho(ch); ch := CAP(ch); WriteLn;
  IF ch='Y' THEN CheckAllSectors; WriteStringLn('done') END;
END DiskCheck.
