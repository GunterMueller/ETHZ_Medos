<this is more a guide than a commandfile;
 it calls old fashioned zeus and print.bitmap;
 the following four sections show the necessary user profile entries;
 the commandfile itself shows the correct page numbering>

"Skylla-for-HandBook" 
'F0'                TIMESROMAN12
'F1'                TIMESROMAN12I
'F2'                TIMESROMAN12B
'F3'                TIMESROMAN10
'F4'                TIMESROMAN16
'F5'                TIMESROMAN20
'F6'                HELVETICA12
'F7'                GACHA12
'Width'             626  (Skylla)
'Size'              224 2528 144 1704  (Zeus)
'TabOrg'            0

"Skylla1-for-HandBook" 
'F0'                TIMESROMAN14
'F1'                TIMESROMAN14I
'F2'                TIMESROMAN14B
'F3'                TIMESROMAN12
'F4'                TIMESROMAN18
'F5'                TIMESROMAN24
'F6'                DUMMY
'F7'                MATH16
'Width'             626  (Skylla)
'Size'              224 2528 144 1704  (Zeus)
'TabOrg'            0

"SIL-for-HandBook"
'F0'                HELVETICA12   9
'F1'                HELVETICA16   9
'F2'                HELVETICA20   9
'F3'                SYMBOL32      0
'FMenu'             Hel12|Hel16|Hel20|Sym32||
'M0'                0
'M1'                0

"SILc-for-HandBook"
'F0'                HELVETICA12   9
'F1'                HELVETICA8    6
'F2'                HELVETICA8I   6
'F3'                SYMBOL32      0
'FMenu'             Hel12|Hel8|Hel8i|Sym32||
'M0'                MACRO1
'M1'                MACRO2

<start of the actual commandfile>

print.bitmap
hand5.Fig1.PICT

print.bitmap
hand5.Fig2.PICT

print.bitmap
hand5.Fig3.PICT

print.bitmap
hand8.Fig1.PICT

print.bitmap
hand8.Fig2.PICT

silprint
c
hand9.Fig1.SIL
1


print.bitmap
hand9.Fig2.PICT

silprint

hand9.Fig3.SIL
1


silprint
c
hand14.Fig1.SIL
1
hand14.Fig2.SIL
1


zeus
a
hand.title.

1


zeus

hand0.
1-1hand1.
1001-1hand2.
2001-1hand3.
3001-1hand4.
4001-1hand5.
5001-1hand6.
6001-1hand7.
7001-1hand8.
8001-1hand9.
9001-1hand10.
10001-1hand11.
11001-1hand12.
12001-1hand13.
13001-1hand14.
14001-1

