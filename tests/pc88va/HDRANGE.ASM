; DOS COM test for a synthetic 40 MB FreeDOS-profile disk at D:.
; Specify C on the command line to test C: instead.
; Writes a pattern to the last sector and restores its original bytes.
; Run only with a disposable fixture (the out-of-range writes must fail).
CODE    SEGMENT PUBLIC 'CODE'
        ASSUME CS:CODE,DS:CODE
        ORG     100H
START:  MOV     SP,OFFSET STACKTOP
        CLD
        CMP     BYTE PTR DS:[82H],'C'
        JNE     FINDRAM
        DEC     [DRIVE]
FINDRAM:
        MOV     AX,CS
        ADD     AX,(FINISH-START+100H+128+15)/16
        ADD     AX,0FFFH
        AND     AX,0F000H       ;First physical 64 KiB boundary above us.
        ADD     AX,24           ;384 bytes of buffer above the boundary.
        CMP     AX,CS:[2]
        JBE     ALLOCOK
        JMP     FAIL
ALLOCOK:SUB     AX,32           ;Buffer starts 128 bytes before boundary.
        MOV     [BUFP],AX
        MOV     [ADDR+2],CS
        CALL    READSEC         ;Save original via an ordinary buffer.
        JC      FAIL

        MOV     AX,[BUFP]
        MOV     ES,AX
        XOR     DI,DI
        MOV     AX,0D257H
        MOV     CX,256
        REP     STOSW
        CALL    CROSSPTR
        CALL    WRITESEC
        JC      FAIL
        CALL    CROSSPTR
        MOV     ES,[BUFP]
        XOR     DI,DI
        XOR     AX,AX
        MOV     CX,256
        REP     STOSW
        CALL    READSEC
        JC      RESTFAIL
        MOV     ES,[BUFP]
        XOR     DI,DI
        MOV     AX,0D257H
        MOV     CX,256
        REPE    SCASW
        JNE     RESTFAIL
        CALL    ORIGINAL
        JC      FAIL

        INC     WORD PTR [LBA]  ;One sector beyond the declared end.
        CALL    BADRANGE
        JC      FAIL
        DEC     WORD PTR [LBA]
        INC     WORD PTR [NSEC] ;Start valid, exclusive end out of range.
        CALL    BADRANGE
        JC      FAIL
        MOV     WORD PTR [LBA],0FFFFH
        MOV     WORD PTR [LBA+2],0FFFFH
        CALL    BADRANGE         ;32-bit addition must not wrap.
        JC      FAIL
        MOV     DX,OFFSET PASSMSG
        XOR     BL,BL
        JMP     SHORT REPORT
RESTFAIL:CALL   ORIGINAL
FAIL:   MOV     DX,OFFSET FAILMSG
        MOV     BL,1
REPORT: MOV     AH,9
        INT     21H
        MOV     AL,BL
        MOV     AH,4CH
        INT     21H

CROSSPTR:
        MOV     WORD PTR [ADDR],0
        MOV     AX,[BUFP]
        MOV     [ADDR+2],AX
        RET
ORIGINAL:
        MOV     WORD PTR [ADDR],OFFSET BACKUP
        MOV     [ADDR+2],CS
        JMP     SHORT WRITESEC
BADRANGE:
        CALL    READSEC
        JNC     BADFAIL
        CMP     AL,8
        JNE     BADFAIL
        CALL    WRITESEC
        JNC     BADFAIL
        CMP     AL,8
        JNE     BADFAIL
        CLC
        RET
BADFAIL:STC
        RET
READSEC:MOV     AL,[DRIVE]
        MOV     BX,OFFSET LBA
        MOV     CX,0FFFFH
        INT     25H
        POP     DX              ;Discard the flags word left by INT 25h.
        CLD
        RET
WRITESEC:
        MOV     AL,[DRIVE]
        MOV     BX,OFFSET LBA
        MOV     CX,0FFFFH
        INT     26H
        POP     DX
        CLD
        RET

LBA     DD      81177
NSEC    DW      1
ADDR    DW      OFFSET BACKUP,0
BUFP    DW      0
DRIVE   DB      3
PASSMSG DB      'SASI cross-page read/write and range checks passed',13,10,'$'
FAILMSG DB      'SASI cross-page or range check failed',13,10,'$'
BACKUP  DB      1024 DUP (0)    ;Also safe for the two-sector invalid requests.
        DB      512 DUP (0)
STACKTOP LABEL WORD
FINISH  LABEL   BYTE
CODE    ENDS
        END     START
