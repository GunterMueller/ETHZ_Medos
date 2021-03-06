(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          FileMessage                 *
*                                      *
*          Version 2    9.3.81         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

IMPLEMENTATION MODULE FileMessage;

  FROM Terminal IMPORT Write, WriteString;

  FROM CardinalIO IMPORT WriteOct;

  FROM FileSystem IMPORT Response;


  PROCEDURE WriteResponse(r: Response); 
  BEGIN 
    Write(' ');
    CASE r OF 
      done:            WriteString('done') |
      notdone:         WriteString('not done') |
      notsupported:    WriteString('not supported') |
      callerror:       WriteString('calling error') |
      unknownmedium:   WriteString('unknown medium') |
      unknownfile:     WriteString('unknown file') |
      paramerror:      WriteString('parameter error') |
      toomanyfiles:    WriteString('too many files') |
      eom:             WriteString('end of medium') |
      deviceoff:       WriteString('device off') |
      softparityerror: WriteString('memory parity error') |
      softprotected:   WriteString('software protected') |
      softerror:       WriteString('software error') |
      hardparityerror: WriteString('disk parity error') |
      hardprotected:   WriteString('protected pack') |
      timeout:         WriteString('timeout') |
      harderror:       WriteString('hardware error')
    ELSE
      WriteString('- FileMessage.WriteResponse:');
      WriteOct(ORD(r));
    END
  END WriteResponse;

END FileMessage.

