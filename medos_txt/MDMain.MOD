(**********************************************)
(*                                            *)
(*     Debugger                               *)
(*     ********                               *)
(*                                            *)
(* diploma-work of Carl Binding               *)
(* diploma-work of Peter Karrer               *)
(* semester-work of HK. Buehrer               *)
(*  [all supervised by Ch. Jacobi]            *)
(*                                            *)
(* based on earlier work of                   *)
(*  Ch. Jacobi   (decoding of memory image)   *)
(*  H. Mueller   (early PDP-11 Debugger)      *)
(*  Don Abel     (thoughts of user interface) *)
(*  A. Ventura   (PDP-11 Debugger)            *)
(*  L. Geissmann (reference file)             *)
(*                                            *)
(*                                            *)
(**********************************************)

(* 16.6.82  Ch. Jacobi
   Warning to Source Users:

   For future improvements my feeling is
     that not additional features should be programmed, but that it should 
     be reprogrammed in a clean way first. At the moment I do not see when
     we will have time for that. The partition in the modules is not too bad,
     maybe its views could be reprogrammed independently. 

   Who does?: (Non of this ideas is in seriouse planning today)
     - I dream that the program-view is implemented with the standard editor.
       For this reason reprogramming the program-view gets low priority,
       however, it is a lack that the program-view needs a listing, and can
       not show the source.
       [Or should the line and PC-information be encoded in the reference files?].
     - the PC information in the listing should be updated even after
       code moving for introduction of long jumps [compiler].
     - Upper memory bank should be displayed also in the memory view.
     - Does the procedure chain and the load map really need be displayed
       in separate windows? (the separation of the "handler" modules
       MDModuleHandler and MDProchandler is ok, only the presentation
       could be merged).
     - Does the data window and variable window really need be 
       separate windows? 
     - Introduce a general number selection mechanism: Don't type in PC's
       or Line number's, but select any number (may be done also by typing 
       the number), do the operation with the selected number.
     - Use of internal file identification (replacing file names) for opening
       REF or LST files a second time. [Not done now, because the
       internal file identification is not supported correctly by the 
       (still experimental pre version of our) network].
     - Show the expression stack in the process view.
     - Should LST, REF information contain version keys?
     - Some views have too many global variables, whose information could be easily
       recomputed when needed.
     - Module "CardinalIO" should not be imported, since it is private.
*) 

MODULE MDMain;  (*[C. Binding]; reprogrammed by Ch. Jacobi 29.7.81;
                  modified by HK. Buehrer*)
(*$T-*) (*$R-*)
  FROM SYSTEM IMPORT ADR;
  FROM Monitor IMPORT TermProcedure;
  FROM Terminal IMPORT 
    Write, WriteString, WriteLn, BusyRead, Read;
  FROM WindowHandler IMPORT 
    Window, FullScreen, CloseWindow;
  FROM WindowDialogue IMPORT 
    DialogLoop, InstallKeyboard;

  FROM MDWhatToDebug IMPORT debuglife;
  FROM MDDialogView IMPORT InstallDialogCommand;
  FROM DumpFileHandler IMPORT Mem;
  FROM MDMapView IMPORT InitMapView, TerminateMapView;
  FROM MDProcView IMPORT DebugProcess;
  FROM Inspect IMPORT InitInspect, TerminateInspect; 
  FROM MDProcessView IMPORT InitProcessView, TerminateProcessView;
  FROM MDScreenView IMPORT InitScreenView,TerminateScreenView;
  FROM MDVarView IMPORT VarViewResetLevel;

  CONST
      (*System.*) AddrSavePRegister = 5;

  VAR dirtyStart[40B+2]: POINTER TO 
        RECORD
          skip: ARRAY [0..10] OF CARDINAL;
          x: CARDINAL;
        END;

  PROCEDURE TerminateDebugger;
    VAR dummy: Window; b: BOOLEAN;
  BEGIN
    dummy := FullScreen();
    CloseWindow(dummy);
  END TerminateDebugger;

  PROCEDURE Help;
    VAR ch: CHAR;
  BEGIN
    REPEAT BusyRead(ch) UNTIL ch=0C;
    WriteLn;
    WriteString("mouse buttons for window"); WriteLn;
    WriteString("specific commands"); WriteLn;
    WriteString("- middle: shows a menu"); WriteLn;
    WriteString("- left:   execute most"); WriteLn;
    WriteString("          important command "); WriteLn;
  END Help;

  PROCEDURE CleanUp;
  BEGIN
    TerminateMapView;
    TerminateInspect;
    TerminateProcessView;
    TerminateScreenView;
    VarViewResetLevel;
  END CleanUp;


BEGIN
  InstallDialogCommand(InitMapView," map");
  InstallDialogCommand(InitInspect," memory");
  InstallDialogCommand(InitProcessView," process");
  TermProcedure(CleanUp);
  InstallKeyboard(Help);
  IF debuglife THEN DebugProcess(dirtyStart^.x, TRUE);
  ELSE DebugProcess(Mem(AddrSavePRegister), TRUE);
  END;
  WriteString("start with mouse buttons"); WriteLn;
  DialogLoop(TRUE);
  TerminateDebugger
END MDMain.
