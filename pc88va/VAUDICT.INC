; Shared JFP v2 file payload / resident block layout.
; [reading bytes][word bytes][reading][word][total record bytes]
; The final byte permits a reverse walk without an offset array.
UDFIELD EQU     60
UDLIMIT EQU     64
UDV1REC EQU     2+2*UDFIELD
UDMAX   EQU     UDLIMIT*(UDV1REC+1)
UDHEAD  EQU     6
