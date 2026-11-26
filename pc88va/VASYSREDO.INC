; SPDX-License-Identifier: MIT
; Build final metadata block images without changing the live volume.
; A refresh can touch at most 32 FAT blocks and 3 root blocks. The log
; adds a table and the original IPL block zero, fitting in two clusters.
TXMAX   EQU     35
TXSEG   DW      0
TXPLAN  DB      0
TXUSED  DW      0
TXBLOCK DW      0
TXENTRY DW      TXRUN-TXIPL,0
TXTAB   DW      128 DUP (0)

TXBEGIN:MOV     [TXUSED],0
        MOV     [TXPLAN],1
        RET

; Match pending transactions before interpreting the IPL as foreign.
TXRESUME:
        MOV     SI,OFFSET TXIPL
        XOR     DI,DI
        MOV     CX,TXDATA-TXIPL
        REPE    CMPSB
        JNE     TXNONE
        CALL    TXREPLAY
        D5CF    TXERR
        JMP     HIPLCHECK
TXNONE: CLC
        RET
TXERR:  MOV     DX,OFFSET TXBROKEN
        STC
        RET

TXREPLAY:
        PUSH    DS
        MOV     AX,[WORKSEG]
        MOV     [TXENTRY+2],AX
        MOV     ES,[BMBUFSEG]
        MOV     BH,[FTARGET]
        OR      BH,80H
        XOR     BL,BL
        XOR     BP,BP
        MOV     DS,AX
        CLD
        CALL    DWORD PTR CS:[TXENTRY]
        POP     DS
        RET

; WRITEBLOCK interception. Store (or replace) the image for this block.
TXWRITE:PUSH    SI
        PUSH    DI
        PUSH    BX
        PUSH    AX
        PUSH    DS
        PUSH    ES
        SHL     AX,1
        SHL     AX,1
        ADD     AX,BX
        XOR     BX,BX
TXFIND: CMP     BX,[TXUSED]
        JE      TXADD
        CMP     AX,[TXTAB+BX]
        JE      TXWIMAGE
        ADD     BX,4
        JMP     SHORT TXFIND
TXADD:  CMP     BX,TXMAX*4
        JAE     TXWFAIL
        MOV     [TXTAB+BX],AX
        ADD     [TXUSED],4
TXWIMAGE:
        MOV     SI,BP
        MOV     DI,BX
        MOV     CL,6
        SHL     DI,CL
        MOV     AX,[TXSEG]
        PUSH    ES
        POP     DS
        MOV     ES,AX
        MOV     CX,128
        REP     MOVSW
        CLC
        JMP     SHORT TXWRET
TXWFAIL:STC
TXWRET: POP     ES
        POP     DS
        POP     AX
        POP     BX
        POP     DI
        POP     SI
        RET

; READSEC interception. Read the disk sector, then overlay planned
; writes to it, including previous changes to the same FAT12 byte.
TXREAD: CALL    BMREAD
        JC      TXRRET
        PUSH    AX
        PUSH    BX
        PUSH    SI
        PUSH    DI
        SHL     AX,1
        SHL     AX,1
        XOR     BX,BX
TXRLOOP:CMP     BX,[TXUSED]
        JAE     TXRDONE
        MOV     DI,[TXTAB+BX]
        SUB     DI,AX
        CMP     DI,4
        JAE     TXRNEXT
        MOV     SI,BX
        MOV     CL,6
        SHL     SI,CL
        MOV     CL,8
        SHL     DI,CL
        ADD     DI,BP
        PUSH    DS
        MOV     DS,[TXSEG]
        MOV     CX,128
        REP     MOVSW
        POP     DS
TXRNEXT:ADD     BX,4
        JMP     SHORT TXRLOOP
TXRDONE:POP     DI
        POP     SI
        POP     BX
        POP     AX
        CLC
TXRRET: RET

; RFCL is reserved (still free in both FATs) by the caller. Only the
; final block-zero write arms replay. TXREPLAY restores it last.
TXCOMMIT:
        MOV     [TXPLAN],0
        MOV     AX,[RFCL]
        CALL    D5JRLBA
        MOV     [TXBASE],AX
        MOV     AX,[D5SPC]
        SHL     AX,1
        SHL     AX,1
        MOV     [TXSPAN],AX
        MOV     AX,[TXUSED]
        SHR     AX,1
        SHR     AX,1
        INC     AX
        MOV     [TXCOUNT],AX
        CMP     AX,[TXSPAN]
        JB      TXSINGLE
        CALL    RFFREE
        D5CF    RFERROR
        CALL    D5JRLBA
        MOV     [TXBASE+2],AX
TXSINGLE:
        MOV     AX,[DATA0]
        SHL     AX,1
        SHL     AX,1
        MOV     [TXLIMIT],AX
        ; Add the original IPL as the last image. Read the full sector
        ; into the aligned work buffer, then copy just block zero.
        MOV     BX,[TXUSED]
        MOV     WORD PTR [TXTAB+BX],0
        MOV     ES,[WORKSEG]
        XOR     AX,AX
        XOR     BP,BP
        CALL    BMREAD
        D5CF    RFERROR
        MOV     DI,[TXUSED]
        MOV     CL,6
        SHL     DI,CL
        MOV     ES,[TXSEG]
        PUSH    DS
        MOV     DS,[WORKSEG]
        XOR     SI,SI
        MOV     CX,128
        REP     MOVSW
        POP     DS
        MOV     [TXBLOCK],1
TXSTAGE:
        MOV     BP,[TXBLOCK]
        DEC     BP
        MOV     CL,8
        SHL     BP,CL
        MOV     ES,[TXSEG]
        PUSH    DS
        PUSH    ES
        POP     DS
        MOV     SI,BP
        MOV     CX,256
        CALL    CRC16
        POP     DS
        MOV     BX,[TXBLOCK]
        SHL     BX,1
        SHL     BX,1
        MOV     [TXTAB+BX-2],DX
        MOV     AX,[TXBASE]
        MOV     BX,[TXBLOCK]
        CMP     BX,[TXSPAN]
        JB      TXSTAGE1
        SUB     BX,[TXSPAN]
        MOV     AX,[TXBASE+2]
TXSTAGE1:
        MOV     DX,BX
        SHR     DX,1
        SHR     DX,1
        ADD     AX,DX
        AND     BX,3
        CALL    BMWRITE
        D5CF    RFERROR
        INC     [TXBLOCK]
        MOV     AX,[TXBLOCK]
        CMP     AX,[TXCOUNT]
        JBE     TXSTAGE
        MOV     SI,OFFSET TXTAB
        MOV     CX,256
        CALL    CRC16
        MOV     [TXSUM],DX
        MOV     ES,[RFSEG]
        XOR     DI,DI
        MOV     SI,OFFSET TXTAB
        MOV     CX,128
        REP     MOVSW
        MOV     AX,[TXBASE]
        XOR     BX,BX
        XOR     BP,BP
        CALL    BMWRITE
        D5CF    RFERROR
        MOV     ES,[WORKSEG]
        XOR     DI,DI
        MOV     SI,OFFSET TXIPL
        MOV     CX,128
        REP     MOVSW
        XOR     AX,AX
        XOR     BX,BX
        XOR     BP,BP
        CALL    BMWRITE
        D5CF    TXERR
        CALL    TXREPLAY
        D5CF    TXERR
        RET

        INCLUDE VASYSIPL.INC
