(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          S E K  or                   *
*          Sequential Executive        *
*          Kernel:                     *
*                                      *
*          Main program of MEDOS-2.    *
*          It initializes MEDOS-2      *
*          and controls the execution  *
*          of a sequence of programs.  *
*          SEK is privat to MEDOS-2.   *
*          Program SEK4.Comint and     *
*          SEK4.CommandFile are        *
*          overlays to SEK.            *
*                                      *
*          Version 4  18.06.82         *    
*          Version 42 20.11.82         *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

IMPLEMENTATION MODULE SEK;

  FROM Program IMPORT Call, Status, CurrentLevel; 
  FROM FileSystem IMPORT Response; 
  FROM DiskSystem IMPORT OpenVolume, CloseVolume;
  FROM D140Disk IMPORT DiskStatus; 
  FROM Terminal IMPORT Read, Write, WriteString, WriteLn;
  FROM DisplayDriver IMPORT MapHeight, ChangeBitmap;
  FROM UserIdentification IMPORT ResetUser;

 
  CONST
    loginname = 'SEK42.Comint';
    comintname = 'SEK42.Comint';
    errorname = 'SEK42.Comint';
    namelength = 16;
    paramlength = 64;
    ff = 14C;

  TYPE
    Name = ARRAY [0..namelength-1] OF CHAR; 
    Parameter = ARRAY [0..paramlength-1] OF CHAR; 
 
  VAR
    ch: CHAR; 
    res: Response; 
 
    comint: BOOLEAN;  
    nextprogram: Name;
    parameter: Parameter; 
    status: Status;
    errorExitLevel: CARDINAL;
    login: BOOLEAN;
    mountdk: BOOLEAN;
 
 
  PROCEDURE TestDK(actualstate: BOOLEAN): BOOLEAN;
    VAR gooddisk: BOOLEAN;
  BEGIN
    gooddisk := DiskStatus() = done;
    mountdk := mountdk OR NOT gooddisk;
    IF actualstate THEN RETURN gooddisk ELSE RETURN NOT mountdk END
  END TestDK;


  PROCEDURE PreviousStatus(): Status; 
  BEGIN 
    RETURN status 
  END PreviousStatus;


  PROCEDURE NextProgram(na: ARRAY OF CHAR);
    VAR c: CARDINAL;
  BEGIN
    c := 0;
    LOOP
      IF (c > HIGH(na)) OR (c >= namelength) THEN EXIT END;
      nextprogram[c] := na[c]; INC(c);
    END;
    IF c < namelength THEN nextprogram[c] := 0C END;
    comint := FALSE;
    parameter[0] := 0C
  END NextProgram; 


  PROCEDURE SetParameter(param: ARRAY OF CHAR);
    VAR c: CARDINAL;
  BEGIN
    c := 0;
    LOOP
      IF (c > HIGH(param)) OR (c >= paramlength) THEN EXIT END;
      parameter[c] := param[c]; INC(c);
    END;
    IF c < paramlength THEN parameter[c] := 0C END;
  END SetParameter;


  PROCEDURE GetParameter(VAR param: ARRAY OF CHAR);
    VAR c: CARDINAL;
  BEGIN
    c := 0;
    LOOP
      IF (c > HIGH(param)) OR (c >= paramlength) THEN EXIT END;
      param[c] := parameter[c]; INC(c);
    END;
    IF c < HIGH(param) THEN param[c] := 0C END;
  END GetParameter;


  PROCEDURE CallComint(loop: BOOLEAN; VAR st: Status);

    VAR
      cl, mapheight: CARDINAL;
      done: BOOLEAN;
      lst: Status;

  BEGIN
    cl := CurrentLevel();
    IF errorExitLevel >= cl THEN
      IF loop THEN errorExitLevel := 177777B
      ELSE errorExitLevel := cl
      END
    END;
    mapheight := MapHeight();
    LOOP (* Loop over the commands *)
      parameter[0] := 0C; status := normal;
      Call(comintname, FALSE, status);
      IF status <> normal THEN
        Call(errorname, FALSE, lst);
        EXIT;
      END;
      IF comint THEN EXIT END;
      WHILE TestDK(FALSE) AND NOT comint AND (status = normal) DO
        comint := TRUE;
        Call(nextprogram, FALSE, status);
        ChangeBitmap(mapheight, done);
        IF NOT TestDK(FALSE) THEN EXIT END;
        IF status <> normal THEN
          Call(errorname, FALSE, lst);
          IF errorExitLevel <= cl THEN EXIT END;
        END
      END;
      IF NOT loop THEN EXIT END;
    END;
    st := status;
  END CallComint;


  PROCEDURE Login(): BOOLEAN;
  BEGIN
    RETURN login;
  END Login;


  PROCEDURE LeaveLogin;
  BEGIN
    login := FALSE;
  END LeaveLogin;
 

BEGIN (* S E K *)

  (* loop over different mountings of volumes *)
  LOOP
    (* Open the DiskSystem such that we can use diskfiles. *)
    REPEAT UNTIL DiskStatus() = done;
    Write(ff); 
    WriteString('V4.2'); 
    OpenVolume(res); 
    IF res <> done THEN
      Write('/'); WriteLn;
      EXIT; (* we only try to open the volume once *) 
    ELSE
      Write('.'); WriteLn;
      mountdk := FALSE;
      login := TRUE;
      WHILE TestDK(FALSE) AND login DO
        ResetUser;
        NextProgram(loginname); status := normal;
        REPEAT
          comint := TRUE;
          Call(nextprogram, FALSE, status);
        UNTIL comint OR (status<>normal)
      END;
      WHILE TestDK(FALSE) DO CallComint(TRUE, status) END;
    END; (* if res <> done *)
    CloseVolume(res);
  END; (* loop *)

END SEK.
