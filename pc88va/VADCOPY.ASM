        TITLE   PC-88VA BIOS disk copy
; SPDX-License-Identifier: MIT
; M2 read side. Assemble MASM, LINK then convert to a .COM at ORG 100h.
CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME CS:CODE,DS:CODE,SS:CODE
        ORG 100H

DISKMODE EQU    0               ;601FDD, BIOS Work Area (GET BOOK relative)
SURFMODE EQU    4
BIOSMODE EQU    5
USERPARM EQU    0BH
NIDMAX  EQU     40

START:  MOV     SP,OFFSET STACKTOP
        CLD
        MOV     SI,81H
        CALL    SPACE
        LODSB
        AND     AL,0DFH
        SUB     AL,'A'
        CMP     AL,1
        JA      USAGE
        MOV     [DRIVE],AL
        LODSB
        CMP     AL,':'
        JNE     USAGE
        CALL    SPACE
        LODSW
        AND     AH,0DFH
        CMP     AX,'T/'
        JNE     USAGE
        CALL    SPACE
        CMP     BYTE PTR [SI],13
        JNE     USAGE
        ; Round the first free paragraph up to a physical 1K boundary.
        ; Allocate a 1K slot per ID, so no transfer crosses a DMA page.
        MOV     AX,OFFSET STACKTOP+15
        MOV     CL,4
        SHR     AX,CL
        MOV     DX,CS
        ADD     AX,DX
        ADD     AX,63
        AND     AX,0FFC0H
        MOV     [BUFSEG],AX
        ADD     AX,NIDMAX*64
        CMP     AX,DS:[2]
        JBE     INIT
        MOV     DX,OFFSET NOMEN
        JMP     FAIL
USAGE:  MOV     DX,OFFSET HELP
FAIL:   CALL    MESSAGE
        MOV     AX,4C01H
        INT     21H
INIT:   MOV     AH,0DH          ;GET BOOK
        INT     80H
        PUSH    CS
        POP     DS
        MOV     [BOOKSEG],ES
        MOV     [BOOKOFF],DX
        MOV     SI,DX
        MOV     AX,ES:[SI+SURFMODE]
        MOV     [SAVCTL],AX
        MOV     AX,ES:[SI+USERPARM]
        MOV     WORD PTR [SAVPARM],AX
        MOV     AX,ES:[SI+USERPARM+2]
        MOV     WORD PTR [SAVPARM+2],AX
        MOV     AL,ES:[SI+USERPARM+4]
        MOV     [SAVPARM+4],AL
        MOV     BL,[DRIVE]
        XOR     BH,BH
        MOV     DI,SI
        MOV     AL,ES:[DI+BX+DISKMODE]
        MOV     [SAVMODE],AL
        CALL    DETECT
        JNC     SCAN0
        MOV     DX,OFFSET NOIDS
        CALL    MESSAGE
        JMP     ABORT
SCAN0:  MOV     BYTE PTR [TRACK],0
SCAN:   CALL    COLLECT
        JNC     SCAN1
        MOV     BYTE PTR [NUMIDS],0
        CALL    ASKERROR
SCAN1:  CALL    READTRACK
        CALL    REPORT
        INC     [TRACK]
        MOV     AL,[TRACK]
        CMP     AL,[LIMIT]
        JB      SCAN
        CALL    RESTMODE
        MOV     DX,OFFSET DONE
        MOV     CX,DONEEND-DONE
        CALL    STDOUT
        MOV     AX,4C00H
        INT     21H
ABORT:  CALL    RESTMODE
        MOV     AX,4C01H
        INT     21H

SPACE:  CMP     BYTE PTR [SI],' '
        JE      SPACE1
        CMP     BYTE PTR [SI],9
        JNE     SPACE2
SPACE1: INC     SI
        JMP     SPACE
SPACE2: RET

; Media inference: 2HD first if current mode is 2HD, otherwise after
; the lower densities. Probe cylinder 1 before accepting 2DD, since
; the 2DD setting may read every other cylinder of some 2D media.
DETECT: CMP     BYTE PTR [SAVMODE],20H
        JB      DETLOW
        CMP     BYTE PTR [SAVMODE],30H
        JAE     DETLOW
        CALL    TRYHD
        JNC     DETOK
DETLOW: MOV     AL,12H
        CALL    SELECT
        JC      TRY2D
        MOV     BYTE PTR [TRACK],2
        CALL    FINDID
        JNC     DETOK
        INC     [TRACK]
        CALL    FINDID
        JNC     DETOK
TRY2D:  MOV     AL,01H
        CALL    SELECT
        JC      DETLAST
        CALL    FIRST4
        JNC     DETOK
DETLAST:CALL    TRYHD
DETOK:  RET
TRYHD:  MOV     AL,23H
        CALL    SELECT
        JC      DETOK
FIRST4: MOV     BYTE PTR [TRACK],0
DET1:   CALL    FINDID
        JNC     DETOK
        INC     [TRACK]
        CMP     BYTE PTR [TRACK],4
        JB      DET1
        STC
        RET
SELECT: MOV     [MODE],AL
        MOV     BYTE PTR [LIMIT],160
        CMP     AL,01H
        JNE     SEL1
        MOV     BYTE PTR [LIMIT],80
SEL1:   MOV     AH,0AH
        MOV     CH,[DRIVE]
        CALL    BIOS
        JMP     STATUS
RESTMODE:
        PUSH    AX
        MOV     AL,[SAVMODE]
        CMP     AL,0FFH
        JNE     REST1
        MOV     AL,01H          ;Manual: FFh has hardware settings of 01h.
REST1:  MOV     AH,0AH
        MOV     CH,[DRIVE]
        CALL    BIOS
        LES     DI,DWORD PTR [BOOKOFF]
        XOR     BX,BX
        MOV     BL,[DRIVE]
        MOV     AL,[SAVMODE]
        MOV     ES:[DI+BX+DISKMODE],AL
        POP     AX
        RET

; Collect one circular sequence of unique CHRN tuples. An immediate
; repeated tuple is a one-sector track; a repeat anywhere except the
; first tuple is ambiguous. Neither READ ID nor the BIOS exposes index.
COLLECT:MOV     BYTE PTR [NUMIDS],0
        CALL    FINDID
        JC      COLEND
        MOV     SI,OFFSET IDS
COL1:   CMP     DL,3
        JA      COLBAD
        XCHG    CH,CL           ;Store C,H,R,N in byte (not register) order.
        XCHG    DH,DL
        MOV     DI,OFFSET IDS
COL2:   CMP     DI,SI
        JE      COLNEW
        CMP     CX,[DI]
        JNE     COLNEXT
        CMP     DX,[DI+2]
        JNE     COLNEXT
        CMP     DI,OFFSET IDS
        JNE     COLBAD
        CLC
        RET
COLNEXT:ADD     DI,4
        JMP     COL2
COLNEW: CMP     BYTE PTR [NUMIDS],NIDMAX
        JAE     COLBAD
        MOV     [SI],CX
        MOV     [SI+2],DX
        ADD     SI,4
        INC     [NUMIDS]
        CALL    READID
        JNC     COL1
COLEND: RET
COLBAD: MOV     AH,0FFH
        STC
        RET
FINDID: MOV     BYTE PTR [FM],0
        CALL    READID
        JNC     COLEND
        MOV     BYTE PTR [FM],80H
READID: MOV     AH,85H
        MOV     CH,[DRIVE]
        MOV     CL,[TRACK]
        MOV     DL,[FM]
        CALL    RAW
STATUS: JC      COLEND
        OR      AH,AH
        JZ      COLEND
        STC
        RET

; Read one sector per call. EOT is max R for data, independent of the
; number of IDs. Preclear each slot so an ignored partial/no DMA leaves
; the bytes actually transferred followed by zeros, never stale data.
READTRACK:
        XOR     SI,SI
        MOV     AX,[BUFSEG]
        MOV     [SLOTSEG],AX
RD1:    XOR     BX,BX
        MOV     BL,[NUMIDS]
        CMP     SI,BX
        JB      RDSEC
        RET
RDSEC:  MOV     DI,SI
        SHL     DI,1
        SHL     DI,1
        MOV     CL,[IDS+DI+3]
        MOV     AX,128
        SHL     AX,CL
        MOV     [SECBYTES],AX
        MOV     CX,AX
        SHR     CX,1
        MOV     ES,[SLOTSEG]
        XOR     AX,AX
        XOR     DI,DI
        REP     STOSW
        MOV     DI,SI
        SHL     DI,1
        SHL     DI,1
        MOV     BX,WORD PTR [IDS+DI]
        XCHG    BL,BH           ;BH = C, BL = H
        MOV     DH,[IDS+DI+2]
        MOV     DL,[IDS+DI+3]
        MOV     AL,DL
        MOV     AH,[FM]
        OR      DL,AH
        PUSH    BX
        XOR     BX,BX
        MOV     BL,AL
        MOV     AL,[READGAPS+BX]
        OR      AH,AH
        JZ      RD2
        MOV     AL,[FMGAPS+BX]
RD2:    MOV     [PARM+2],AL
        MOV     AL,0FFH
        OR      BL,BL
        JNZ     RD3
        MOV     AL,80H
RD3:    MOV     [PARM+4],AL
        POP     BX
        MOV     AL,[LIMIT]
        SHR     AL,1
        DEC     AL
        MOV     [PARM],AL
        MOV     BYTE PTR [PARM+1],0FFH
        MOV     CH,[DRIVE]
        MOV     CL,[TRACK]
        XOR     BP,BP
        MOV     AX,8101H
        CALL    RAW
        CALL    STATUS
        MOV     [ERRORS+SI],AH
        JNC     HASH
        CALL    ASKERROR
HASH:   MOV     ES,[SLOTSEG]
        XOR     AX,AX
        XOR     BX,BX
        XOR     DI,DI
        MOV     CX,[SECBYTES]
HASH1:  ROL     AX,1
        MOV     BL,ES:[DI]
        INC     DI
        ADD     AX,BX
        LOOP    HASH1
        MOV     DI,SI
        SHL     DI,1
        MOV     [SUMS+DI],AX
        ADD     WORD PTR [SLOTSEG],64
        INC     SI
        JMP     RD1

; RAW uses scoped BIOS work changes so subsequent DOS requests are not
; made with our IDR or USERPARM overrides. BX/CX/DX are ROM outputs.
RAW:    PUSH    ES
        PUSH    DI
        PUSH    AX
        LES     DI,DWORD PTR [BOOKOFF]
        OR      BYTE PTR ES:[DI+SURFMODE],3
        MOV     BYTE PTR ES:[DI+BIOSMODE],0
        CMP     AH,85H
        JE      RAW1
        MOV     BYTE PTR ES:[DI+BIOSMODE],6  ;IDR + PARM
        MOV     AX,WORD PTR [PARM]
        MOV     ES:[DI+USERPARM],AX
        MOV     AX,WORD PTR [PARM+2]
        MOV     ES:[DI+USERPARM+2],AX
        MOV     AL,[PARM+4]
        MOV     ES:[DI+USERPARM+4],AL
RAW1:   POP     AX
        POP     DI
        POP     ES
        CALL    BIOS
        PUSH    ES
        PUSH    DI
        PUSH    AX
        LES     DI,DWORD PTR [BOOKOFF]
        MOV     AX,[SAVCTL]
        MOV     ES:[DI+SURFMODE],AX
        MOV     AX,WORD PTR [SAVPARM]
        MOV     ES:[DI+USERPARM],AX
        MOV     AX,WORD PTR [SAVPARM+2]
        MOV     ES:[DI+USERPARM+2],AX
        MOV     AL,[SAVPARM+4]
        MOV     ES:[DI+USERPARM+4],AL
        POP     AX
        POP     DI
        POP     ES
        RET
BIOS:   PUSH    DS
        PUSH    ES
        PUSH    SI
        PUSH    DI
        PUSH    BP
        INT     80H
        POP     BP
        POP     DI
        POP     SI
        POP     ES
        POP     DS
        RET

; Diagnostic format: TT DD CC [CHRN:SSSS:AA ...] (all hex).
; TT physical track, DD 00 MFM/80 FM, CC count, SSSS payload sum,
; AA BIOS status. DD is irrelevant for tracks with no readable IDs.
REPORT: PUSH    DS
        POP     ES
        MOV     DI,OFFSET LINE
        MOV     AL,[TRACK]
        CALL    HEX
        MOV     AL,' '
        STOSB
        MOV     AL,[FM]
        CALL    HEX
        MOV     AL,' '
        STOSB
        MOV     AL,[NUMIDS]
        CALL    HEX
        XOR     SI,SI
REP1:   CMP     BYTE PTR [NUMIDS],0
        JE      REP9
        MOV     AL,' '
        STOSB
        MOV     BX,SI
        SHL     BX,1
        SHL     BX,1
        MOV     AL,[IDS+BX]
        CALL    HEX
        MOV     AL,[IDS+BX+1]
        CALL    HEX
        MOV     AL,[IDS+BX+2]
        CALL    HEX
        MOV     AL,[IDS+BX+3]
        CALL    HEX
        MOV     AL,':'
        STOSB
        SHR     BX,1
        MOV     AL,BYTE PTR [SUMS+BX+1]
        CALL    HEX
        MOV     AL,BYTE PTR [SUMS+BX]
        CALL    HEX
        MOV     AL,':'
        STOSB
        MOV     AL,[ERRORS+SI]
        CALL    HEX
        INC     SI
        MOV     AX,SI
        CMP     AL,[NUMIDS]
        JB      REP1
REP9:   MOV     AX,0A0DH
        STOSW
        MOV     DX,OFFSET LINE
        MOV     CX,DI
        SUB     CX,DX
STDOUT: MOV     BX,1
        MOV     AH,40H
        INT     21H
        JC      OUTPUTBAD
        CMP     AX,CX
        JNE     OUTPUTBAD
        RET
OUTPUTBAD:
        MOV     DX,OFFSET OUTERR
        CALL    MESSAGE
        JMP     ABORT
HEX:    MOV     AH,AL
        MOV     CL,4
        SHR     AL,CL
        CALL    NIBBLE
        MOV     AL,AH
        AND     AL,0FH
NIBBLE: ADD     AL,'0'
        CMP     AL,'9'
        JBE     HEX1
        ADD     AL,7
HEX1:   STOSB
        RET

ASKERROR:
        PUSH    SI
        MOV     SI,AX
        PUSH    DS
        POP     ES
        MOV     DI,OFFSET BADTRK
        MOV     AL,[TRACK]
        CALL    HEX
        MOV     AX,SI
        MOV     DI,OFFSET BADSTAT
        MOV     AL,AH
        CALL    HEX
        MOV     DX,OFFSET BADREAD
        CALL    MESSAGE
ASK1:   MOV     AH,07H
        INT     21H
        OR      AL,20H
        CMP     AL,'a'
        JNE     ASK2
        JMP     ABORT
ASK2:   CMP     AL,'i'
        JNE     ASK1
        MOV     DX,OFFSET IGNORE
        CALL    MESSAGE
        POP     SI
        RET
; '$'-terminated diagnostic to stderr, keeping layout output separate.
MESSAGE:PUSH    DX
        MOV     SI,DX
MSG1:   LODSB
        CMP     AL,'$'
        JNE     MSG1
        POP     DX
        MOV     CX,SI
        SUB     CX,DX
        DEC     CX
        MOV     BX,2
        MOV     AH,40H
        INT     21H
        RET

HELP    DB      'Usage: DISKCOPY source: /T (read-only diagnostic)',13,10,'$'
NOMEN   DB      'Not enough conventional memory.',13,10,'$'
NOIDS   DB      'Cannot identify media mode (no readable IDs).',13,10,'$'
OUTERR  DB      'Cannot write diagnostic output.',13,10,'$'
BADREAD DB      'Read error on track '
BADTRK  DB      '00h (BIOS '
BADSTAT DB      '00h). Abort or Ignore (A/I)? $'
IGNORE  DB      'Ignore',13,10,'$'
DONE    DB      'DONE',13,10
DONEEND LABEL   BYTE
DRIVE   DB      0
MODE    DB      0
TRACK   DB      0
FM      DB      0
LIMIT   DB      0
NUMIDS  DB      0
BOOKOFF DW      0
BOOKSEG DW      0
SAVCTL  DW      0
SAVPARM DB      5 DUP (0)
SAVMODE DB      0
PARM    DB      5 DUP (0)
READGAPS DB     07H,0EH,2AH,35H
FMGAPS   DB     07H,0EH,1BH,35H
BUFSEG  DW      0
SLOTSEG DW      0
SECBYTES DW     0
IDS     DB      4*NIDMAX DUP (?)
ERRORS  DB      NIDMAX DUP (?)
SUMS    DW      NIDMAX DUP (?)
LINE    DB      10+17*NIDMAX DUP (?)
        DB      512 DUP (?)
STACKTOP LABEL  BYTE
CODE    ENDS
        END START
