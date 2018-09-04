(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          Boot:                       *
*                                      *
*          Boot boots the mashine      *
*          from the normal bootfile    *
*          (PC.BootFile).              *
*                                      *
*          Version 2  13.10.80         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

MODULE Boot;

  CONST
    SYS   = 247B;
    boot  = 0;
    track = 0;

  PROCEDURE BootCall(tr: CARDINAL);
  CODE
    SYS; boot;
  END BootCall;

BEGIN
  BootCall(track);
END Boot.
