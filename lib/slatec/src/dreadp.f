*DECK DREADP
      SUBROUTINE DREADP (IPAGE, LIST, RLIST, LPAGE, IREC)
C***BEGIN PROLOGUE  DREADP
C***SUBSIDIARY
C***PURPOSE  Subsidiary to DSPLP
C***LIBRARY   SLATEC
C***TYPE      DOUBLE PRECISION (SREADP-S, DREADP-D)
C***AUTHOR  (UNKNOWN)
C***DESCRIPTION
C
C     READ RECORD NUMBER IRECN, OF LENGTH LPG, FROM UNIT
C     NUMBER IPAGEF INTO THE STORAGE ARRAY, LIST(*).
C     READ RECORD  IRECN+1, OF LENGTH LPG, FROM UNIT NUMBER
C     IPAGEF INTO THE STORAGE ARRAY RLIST(*).
C
C     TO CONVERT THIS PROGRAM UNIT TO DOUBLE PRECISION CHANGE
C     /REAL (12 BLANKS)/ TO /DOUBLE PRECISION/.
C
C***SEE ALSO  DSPLP
C***ROUTINES CALLED  XERMSG
C***REVISION HISTORY  (YYMMDD)
C   811215  DATE WRITTEN
C   890605  Corrected references to XERRWV.  (WRB)
C   891214  Prologue converted to Version 4.0 format.  (BAB)
C   900328  Added TYPE section.  (WRB)
C   900510  Convert XERRWV calls to XERMSG calls.  (RWC)
C***END PROLOGUE  DREADP
      INTEGER LIST(*)
      DOUBLE PRECISION RLIST(*)
      CHARACTER*8 XERN1, XERN2
C***FIRST EXECUTABLE STATEMENT  DREADP
      IPAGEF=IPAGE
      LPG   =LPAGE
      IRECN=IREC
      READ(IPAGEF,REC=IRECN,ERR=100)(LIST(I),I=1,LPG)
      READ(IPAGEF,REC=IRECN+1,ERR=100)(RLIST(I),I=1,LPG)
      RETURN
C
  100 WRITE (XERN1, '(I8)') LPG
      WRITE (XERN2, '(I8)') IRECN
      CALL XERMSG ('SLATEC', 'DREADP', 'IN DSPLP, LPG = ' // XERN1 //
     *   ' IRECN = ' // XERN2, 100, 1)
      RETURN
      END