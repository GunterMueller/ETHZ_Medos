(***************************************
*                                      *
*          M E D O S - 2               *
*          *************               *
*                                      *
*                                      *
*          ProgramMessage              *
*                                      *
*          Version 2    9.3.80         *    
*                                      *
*                                      *
*          Svend Erik Knudsen          *
*          Institut fuer Informatik    *
*          ETH-Zuerich                 *
*          CH-8092 Zuerich             *
*                                      *
***************************************)

IMPLEMENTATION MODULE ProgramMessage;

  FROM Terminal IMPORT Write, WriteString;
  FROM CardinalIO IMPORT WriteOct;
  FROM Program IMPORT Status;

  PROCEDURE WriteStatus(st: Status);
  BEGIN
    Write(' ');
    CASE st OF
      normal:               WriteString('normal') |
      instructionerr:       WriteString('instruction error') |
      priorityerr:          WriteString('priority error') |
      spaceerr:             WriteString('stack overflow') |
      rangeerr:             WriteString('range error') |
      addressoverflow:      WriteString('address overflow') |
      realoverflow:         WriteString('REAL overflow') |
      cardinaloverflow:     WriteString('CARDINAL overflow') |
      integeroverflow:      WriteString('INTEGER overflow') | 
      functionerr:          WriteString('function return error') | 
      halted:               WriteString('HALT called') | 
      asserted:             WriteString('Assertion error') | 
      warned:               WriteString('warning') | 
      stopped:              WriteString('stopped') | 
      callerr:              WriteString('Call error') |
      programnotfound:      WriteString('program not found') |
      programalreadyloaded: WriteString('program already loaded') |
      modulenotfound:       WriteString('module not found') |
      incompatiblemodule:   WriteString('incompatible module') |
      maxspaceerr:          WriteString('not enough space') |
      maxmoduleerr:         WriteString('too many modules') |
      codekeyerr:           WriteString('illegal type of code') |
      filestructureerr:     WriteString('error in filestructure') |
      fileerr:              WriteString('some file error') |
      loaderr:              WriteString('some load error') 
    ELSE 
      WriteString('- ProgramMessage.WriteStatus:');
      WriteOct(CARDINAL(st)) 
    END; 
  END WriteStatus; 
 
END ProgramMessage. 
