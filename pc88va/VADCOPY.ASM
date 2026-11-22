        TITLE   PC-88VA BIOS disk copy
; SPDX-License-Identifier: MIT
; Assemble MASM, LINK then convert to a .COM at ORG 100h.
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
        CALL    GETDRV
        JC      USAGE
        MOV     [SOURCE],AL
        MOV     [DRIVE],AL
        CALL    SPACE
        CMP     BYTE PTR [SI],'/'
        JNE     ARG2
        LODSW
        AND     AH,0DFH
        CMP     AX,'T/'
        JNE     USAGE
        MOV     BYTE PTR [DIAG],1
        JMP     SHORT ARGEND
ARG2:   CALL    GETDRV
        JC      USAGE
        CMP     AL,[SOURCE]
        JE      USAGE
        MOV     [TARGET],AL
        CALL    SPACE
        CMP     BYTE PTR [SI],13
        JE      ARGEND
        LODSW
        AND     AH,0DFH
        CMP     AX,'V/'
        JNE     USAGE
        MOV     BYTE PTR [VERIFY],1
ARGEND: CALL    SPACE
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
        MOV     [STAGESEG],AX
        ADD     AX,64
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
        MOV     AX,ES:[SI+DISKMODE]
        MOV     WORD PTR [SAVMODES],AX
        CMP     BYTE PTR [DIAG],0
        JNE     STARTSRC
        MOV     DX,OFFSET SOURCEQ
        CALL    INSERT
STARTSRC:
        CALL    DETECT
        JNC     SOURCEMODE
        JMP     CANTMODE
SOURCEMODE:
        MOV     AL,[MODE]
        MOV     [SRCMODE],AL
        CMP     BYTE PTR [DIAG],0
        JNE     SCAN0
        MOV     AL,[TARGET]
        MOV     [DRIVE],AL
        MOV     DX,OFFSET TARGETQ
        CALL    INSERT
        CALL    CHECKTARGET
SCAN0:  MOV     BYTE PTR [TRACK],0
        JMP     SHORT SCAN
CHECKTARGET:
        CALL    USETARGET
        CALL    WRITEREADY
        CALL    DETECT
        JNC     TARGETMODE
        JMP     USETARGET       ;No readable IDs: allow blank media.
TARGETMODE:
        MOV     AL,[MODE]
        CMP     AL,[SRCMODE]
        JNE     MODEBAD
        RET
MODEBAD:MOV     DX,OFFSET MISMATCH
        JMP     COPYFAIL
SCAN:   CALL    USESOURCE
        CALL    COLLECT
        JNC     SCAN1
        MOV     BYTE PTR [NUMIDS],0
        CALL    ASKERROR
SCAN1:  CALL    READTRACK
        CMP     BYTE PTR [DIAG],0
        JE      SCANCOPY
        CALL    REPORT
        JMP     SHORT SCANNEXT
SCANCOPY:
        CALL    COPYTRACK
SCANNEXT:
        INC     [TRACK]
        MOV     AL,[TRACK]
        CMP     AL,[LIMIT]
        JB      SCAN
        CALL    RESTORE
        CMP     BYTE PTR [DIAG],0
        JE      COPYDONE
        MOV     DX,OFFSET DONE
        MOV     CX,DONEEND-DONE
        CALL    STDOUT
        JMP     SHORT SUCCESS
COPYDONE:
        MOV     DX,OFFSET COPIED
        CMP     BYTE PTR [IGNORED],0
        JE      COPYOK
        MOV     DX,OFFSET INCOMPLETE
        CALL    MESSAGE
        CALL    SUMMARY
        JMP     SHORT BADEND
COPYOK: CALL    MESSAGE
SUCCESS:MOV     AX,4C00H
        INT     21H
CANTMODE:
        MOV     DX,OFFSET NOIDS
COPYFAIL:
        CALL    MESSAGE
ABORT:  CALL    RESTORE
BADEND: MOV     AX,4C01H
        INT     21H

GETDRV: CALL    SPACE
        LODSB
        AND     AL,0DFH
        SUB     AL,'A'
        CMP     AL,1
        JA      BADDRV
        CMP     BYTE PTR [SI],':'
        JNE     BADDRV
        INC     SI
        CLC
        RET
BADDRV: STC
        RET
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
DETECT: CALL    SAVEDMODE
        CMP     AL,20H
        JB      DETLOW
        CMP     AL,30H
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
USESOURCE:
        MOV     AL,[SOURCE]
        JMP     SHORT USEMODE
USETARGET:
        MOV     AL,[TARGET]
USEMODE:MOV     [DRIVE],AL
        MOV     AL,[SRCMODE]
        CALL    SELECT
        JNC     USEOK
        JMP     CANTMODE
USEOK:  RET
SAVEDMODE:
        XOR     BX,BX
        MOV     BL,[DRIVE]
        MOV     AL,[SAVMODES+BX]
        RET
RESTORE:
        MOV     AL,[SOURCE]
        MOV     [DRIVE],AL
        CALL    RESTMODE
        CMP     BYTE PTR [DIAG],0
        JNE     REST9
        MOV     AL,[TARGET]
        MOV     [DRIVE],AL
RESTMODE:
        CALL    SAVEDMODE
        CMP     AL,0FFH
        JNE     REST1
        MOV     AL,01H          ;Manual: FFh has hardware settings of 01h.
REST1:  MOV     AH,0AH
        MOV     CH,[DRIVE]
        CALL    BIOS
        LES     DI,DWORD PTR [BOOKOFF]
        CALL    SAVEDMODE
        MOV     ES:[DI+BX+DISKMODE],AL
REST9:  RET

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
        MOV     BYTE PTR [COMMAND],81H
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
        CALL    TRANSFER
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

; SI selects sector; ES:0 is the (aligned) DMA buffer.
TRANSFER:
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
        CALL    MAXCYL
        MOV     BYTE PTR [PARM+1],0FFH
        MOV     CH,[DRIVE]
        MOV     CL,[TRACK]
        XOR     BP,BP
        MOV     AL,1
        MOV     AH,[COMMAND]
        CALL    RAW
        JMP     STATUS
MAXCYL: MOV     AL,[LIMIT]
        SHR     AL,1
        DEC     AL
        MOV     [PARM],AL
        RET

; FORMAT takes only one physical N. Reject mixed N instead of writing
; an ID table whose data fields cannot be formatted to match the source.
COPYTRACK:
        XOR     CX,CX
        MOV     CL,[NUMIDS]
        JCXZ    COPYRET
        MOV     SI,OFFSET IDS+3
        MOV     AL,[SI]
CKSIZE: CMP     AL,[SI]
        JNE     MIXED
        ADD     SI,4
        LOOP    CKSIZE
        CALL    USETARGET
        CALL    FORMAT
        XOR     SI,SI
        MOV     AX,[BUFSEG]
        MOV     [SLOTSEG],AX
WRITE1: MOV     ES,[SLOTSEG]
        MOV     BYTE PTR [COMMAND],82H
        CALL    TRANSFER
        JNC     WRITE2
        CALL    WRITEERROR
        JMP     WRITE1
WRITE2: CMP     BYTE PTR [VERIFY],0
        JE      WRITE4
        MOV     ES,[STAGESEG]
        MOV     BYTE PTR [COMMAND],81H
        CALL    TRANSFER
        JC      VERIFYFAIL
        MOV     DI,SI
        SHL     DI,1
        SHL     DI,1
        MOV     CL,[IDS+DI+3]
        MOV     AX,128
        SHL     AX,CL
        MOV     CX,AX
        SHR     CX,1
        MOV     AX,[SLOTSEG]
        PUSH    DS
        PUSH    SI
        MOV     DS,AX
        XOR     SI,SI
        XOR     DI,DI
        REPE    CMPSW
        POP     SI
        POP     DS
        JNE     VERIFYFAIL
WRITE4: ADD     WORD PTR [SLOTSEG],64
        INC     SI
        MOV     AX,SI
        CMP     AL,[NUMIDS]
        JB      WRITE1
COPYRET:RET
MIXED:  PUSH    DS
        POP     ES
        MOV     DI,OFFSET MIXEDTRK
        MOV     AL,[TRACK]
        CALL    HEX
        MOV     DX,OFFSET MIXEDERR
        CALL    MESSAGE
        JMP     ASK1
VERIFYFAIL:
        MOV     DX,OFFSET VERIFYERR
        JMP     COPYFAIL

FORMAT: CALL    WRITEREADY
        MOV     ES,[STAGESEG]
        XOR     DI,DI
        MOV     SI,OFFSET IDS
        XOR     CX,CX
        MOV     CL,[NUMIDS]
        SHL     CX,1
        REP     MOVSW
        CALL    MAXCYL
        MOV     AL,[NUMIDS]
        MOV     [PARM+1],AL      ;FORMAT uses EOT as sector count.
        XOR     BX,BX
        MOV     BL,[IDS+3]
        MOV     DL,BL
        OR      DL,[FM]
        MOV     AL,[FORMATGAPS+BX]
        TEST    DL,80H
        JZ      FMTGAP
        MOV     AL,[FMFMTGAPS+BX]
FMTGAP: MOV     [PARM+3],AL
        MOV     CH,[DRIVE]
        MOV     CL,[TRACK]
        XOR     BP,BP
        MOV     AX,83E5H
        CALL    RAW
        CALL    STATUS
        JNC     COPYRET
        CALL    WRITEERROR
        JMP     FORMAT

; Ready and write-protect errors are tested before touching the target.
WRITEREADY:
        MOV     AH,07H          ;SENSE: AL = ST3, AH=1 means write protected.
        MOV     CH,[DRIVE]
        CALL    BIOS
        JC      RDYERR
        CMP     AH,1
        JE      RDYWP
        TEST    AL,40H
        JNZ     RDYWP
        TEST    AL,20H
        JZ      RDYNR
        RET
RDYNR:  MOV     AH,4
        JMP     SHORT RDYERR
RDYWP:  MOV     AH,5
RDYERR: CALL    WRITEERROR
        JMP     WRITEREADY
WRITEERROR:
        PUSH    SI
        MOV     DX,OFFSET WRITEERR
        CMP     AH,5
        JE      WRITEWP
        CMP     AH,3
        JB      WRPROMPT
        CMP     AH,4
        JA      WRPROMPT
        MOV     DX,OFFSET NOTREADY
        JMP     SHORT WRPROMPT
WRITEWP:MOV     DX,OFFSET PROTECT
WRPROMPT:
        CALL    MESSAGE
WRKEY:  MOV     AH,07H
        INT     21H
        AND     AL,0DFH
        CMP     AL,'A'
        JNE     WRKEY1
        JMP     ABORT
WRKEY1: CMP     AL,'R'
        JNE     WRKEY
        POP     SI
        RET

; DX points at a prompt with a drive letter just before the colon.
INSERT: PUSH    DX
        CALL    MESSAGE
        MOV     AL,[DRIVE]
        ADD     AL,'A'
        MOV     [LETTER],AL
        MOV     DX,OFFSET INSERTEND
        CALL    MESSAGE
INSKEY: MOV     AH,07H
        INT     21H
        CMP     AL,27
        JNE     INSKEY1
        JMP     ABORT
INSKEY1:CMP     AL,13
        JNE     INSKEY
        POP     DX
        RET

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
        JMP     SHORT ASKKEY
ASK1:   PUSH    SI
ASKKEY:   MOV     AH,07H
        INT     21H
        OR      AL,20H
        CMP     AL,'a'
        JNE     ASK2
        JMP     ABORT
ASK2:   CMP     AL,'i'
        JNE     ASKKEY
        MOV     BYTE PTR [IGNORED],1
        XOR     BX,BX
        MOV     BL,[TRACK]
        MOV     BYTE PTR [MISSED+BX],1
        MOV     DX,OFFSET IGNORE
        CALL    MESSAGE
        POP     SI
        RET
; List every track affected by Ignore, including partial data reads.
SUMMARY:PUSH    DS
        POP     ES
        MOV     DI,OFFSET LINE
        XOR     BX,BX
SUM1:   CMP     BYTE PTR [MISSED+BX],0
        JE      SUM2
        MOV     AL,BL
        CALL    HEX
        MOV     AL,' '
        STOSB
SUM2:   INC     BX
        CMP     BL,[LIMIT]
        JB      SUM1
        MOV     AX,0A0DH
        STOSW
        MOV     AL,'$'
        STOSB
        MOV     DX,OFFSET LINE
        JMP     MESSAGE

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

HELP    DB      'Usage: DISKCOPY source: target: [/V]',13,10
        DB      '       DISKCOPY source: /T (read-only diagnostic)',13,10,'$'
NOMEN   DB      'Not enough conventional memory.',13,10,'$'
NOIDS   DB      'Cannot select or identify media mode.',13,10,'$'
SOURCEQ DB      'Insert SOURCE diskette in drive $'
TARGETQ DB      'Target data will be destroyed.',13,10
        DB      'Insert TARGET diskette in drive $'
INSERTEND LABEL BYTE
LETTER  DB      'A: and press ENTER (Esc aborts).',13,10,'$'
MISMATCH DB     'Source and target media modes differ.',13,10,'$'
MIXEDERR DB     'Track '
MIXEDTRK DB     '00: mixed sector sizes cannot be reproduced.',13,10
         DB     'Abort or Ignore (A/I)? $'
VERIFYERR DB    'Target sector verification failed.',13,10,'$'
WRITEERR DB     'Target write error. Retry or Abort (R/A)?',13,10,'$'
NOTREADY DB     'Target not ready. Retry or Abort (R/A)?',13,10,'$'
PROTECT DB      'Target is write protected. Retry or Abort (R/A)?',13,10,'$'
COPIED  DB      'Copy complete.',13,10,'$'
INCOMPLETE DB   'Copy incomplete. Tracks not fully reproduced (hex):',13,10,'$'
OUTERR  DB      'Cannot write diagnostic output.',13,10,'$'
BADREAD DB      'Read error on track '
BADTRK  DB      '00h (BIOS '
BADSTAT DB      '00h). Abort or Ignore (A/I)? $'
IGNORE  DB      'Ignore',13,10,'$'
DONE    DB      'DONE',13,10
DONEEND LABEL   BYTE
DRIVE   DB      0
MODE    DB      0
SOURCE  DB      0
TARGET  DB      0
SRCMODE DB      0
DIAG    DB      0
VERIFY  DB      0
IGNORED DB      0
MISSED  DB      160 DUP (0)
COMMAND DB      0
TRACK   DB      0
FM      DB      0
LIMIT   DB      0
NUMIDS  DB      0
BOOKOFF DW      0
BOOKSEG DW      0
SAVCTL  DW      0
SAVPARM DB      5 DUP (0)
SAVMODES DB     2 DUP (0)
PARM    DB      5 DUP (0)
READGAPS DB     07H,0EH,2AH,35H
FMGAPS   DB     07H,0EH,1BH,35H
FORMATGAPS DB   1BH,36H,50H,74H
FMFMTGAPS DB    1BH,2AH,3AH,74H
BUFSEG  DW      0
STAGESEG DW     0
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
