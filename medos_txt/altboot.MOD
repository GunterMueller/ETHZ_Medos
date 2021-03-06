(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          AlternateBoot:              *
*                                      *
*          AlternateBoot boots the     *
*          mashine from the            *
*          alternate bootfile          *
*          (PC.BootFile.Back).         *
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

MODULE AlternateBoot;

  CONST
    SYS   = 247B;
    boot  = 0;
    track = 26;

  PROCEDURE BootCall(tr: CARDINAL);
  CODE
    SYS; boot;
  END BootCall;

BEGIN
  BootCall(track);
END AlternateBoot.
