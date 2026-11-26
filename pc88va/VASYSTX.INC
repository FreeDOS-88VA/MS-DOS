; SPDX-License-Identifier: MIT
; Build final metadata block images without changing the live volume.
; A refresh can touch all 32 FAT blocks plus five root blocks. The
; table and images live beyond the end of the fixed NEC BPB, never in
; DOS-allocatable space. The smallest documented tail has 396 blocks.
TXMAX   EQU     37
TXANCHOR EQU    39              ;Last block of the 40-block private span.
TXGUARDS EQU    (TXMAX+1)*4
TXTAIL  DW      4950,9900,19800,39593
TXOWNER DB      'VA SYS SASI REDO',1
TXOWNLEN EQU    $-TXOWNER
TXTAILPOS DW    0
TXOLDCRC EQU    743BH
TXOLDENTRY EQU  36H
TXSEG   DW      0
TXPLAN  DB      0
TXUSED  DW      0
TXBLOCK DW      0
TXENTRY DW      TXRUN-TXIPL,0
TXTAB   DW      128 DUP (0)

TXBEGIN:MOV     AX,[TXSEG]
        ADD     AX,(TXMAX+1)*16
        MOV     DX,OFFSET S_NOMEM
        CMP     DS:[2],AX
        JB      TXNOMEM
        MOV     [TXUSED],0
        MOV     [TXPLAN],1
        CLC
TXNOMEM:RET

; Match pending transactions before interpreting the IPL as foreign.
TXRESUME:
        PUSH    AX
        MOV     SI,OFFSET TXMAGIC
        MOV     DI,TXMAGIC-TXIPL
        MOV     CX,5
        REPE    CMPSB
        JNE     TXOLD
        MOV     SI,OFFSET TXIPL
        XOR     DI,DI
        MOV     CX,TXDATA-TXIPL
        REPE    CMPSB
        JNE     TXRECOVER
        PUSH    DS
        PUSH    ES
        POP     DS
        MOV     SI,256
        MOV     CX,256
        CALL    CRC16
        CMP     DX,DS:[TXHELPCRC-TXIPL]
        POP     DS
        JNE     TXRECOVER
        CALL    TXFLUSH
        CALL    TXREPLAY
        JNC     TXCHECK
        JMP     SHORT TXRECOVER
TXOLD:  ; Recognize the fix-3 replay IPL by the immutable code CRC.
        PUSH    DS
        MOV     DS,[WORKSEG]
        XOR     SI,SI
        MOV     CX,242
        CALL    CRC16
        POP     DS
        CMP     DX,TXOLDCRC
        JNE     TXNONE
        MOV     WORD PTR [TXENTRY],TXOLDENTRY
        CALL    TXFLUSH
        CALL    TXREPLAY
        MOV     WORD PTR [TXENTRY],TXRUN-TXIPL
        JC      TXRECOVER
TXCHECK:POP     AX
        JMP     HIPLCHECK
TXRECOVER:
        POP     AX
        JMP     TXREPAIR
TXNONE: POP     AX
        CLC
        RET
TXERR:  MOV     DX,OFFSET TXBROKEN
        STC
        RET

TXFLUSH:MOV     AH,0DH
        INT     21H
        CLD
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

; Only the block-zero write arms replay. TXREPLAY restores it last.
TXCOMMIT:
        MOV     [TXPLAN],0
        XOR     BH,BH
        MOV     BL,[FTYPE]
        SHL     BX,1
        MOV     AX,[TXTAIL+BX]
        MOV     [TXBASE],AX
        CALL    TXTAILCHECK
        D5CF    D5PASS
        MOV     AX,[DATA0]
        SHL     AX,1
        SHL     AX,1
        MOV     [TXLIMIT],AX
        MOV     AX,[TXUSED]
        SHR     AX,1
        SHR     AX,1
        INC     AX
        MOV     [TXCOUNT],AX
        MOV     [TXBLOCK],0
TXPREIMAGE:
        MOV     BX,[TXBLOCK]
        CMP     BX,[TXUSED]
        JAE     TXORIGINAL
        MOV     AX,[TXTAB+BX]
        MOV     SI,AX
        AND     SI,3
        MOV     CL,8
        SHL     SI,CL
        SHR     AX,1
        SHR     AX,1
        MOV     ES,[BMBUFSEG]
        XOR     BP,BP
        CALL    BMREAD
        D5CF    RFERROR
        PUSH    DS
        PUSH    ES
        POP     DS
        MOV     CX,256
        CALL    CRC16
        POP     DS
        MOV     BX,[TXBLOCK]
        SHR     BX,1
        MOV     [TXTAB+TXGUARDS+BX],DX
        ADD     [TXBLOCK],4
        JMP     SHORT TXPREIMAGE
TXORIGINAL:
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
        MOV     SI,OFFSET TXHELP
        MOV     CX,256
        CALL    CRC16
        MOV     [TXHELPCRC],DX
        MOV     ES,[BMBUFSEG]
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
        MOV     CX,256
        REP     MOVSW
        XOR     AX,AX
        MOV     BX,1
        MOV     BP,256
        CALL    BMWRITE
        D5CF    TXERR
        XOR     BX,BX
        XOR     BP,BP
        CALL    BMWRITE
        D5CF    TXERR
        CALL    TXREPLAY
        D5CF    TXERR
        RET

; Do not overwrite an unrecognized use of the physical tail. An
; ownership marker may be left after any cut; it is outside the BPB.
TXTAILCHECK:
        MOV     ES,[BMBUFSEG]
        ADD     AX,TXANCHOR/4
        XOR     BP,BP
        CALL    BMREAD
        D5CF    TXTAILBAD
        MOV     DI,(TXANCHOR MOD 4)*256
        MOV     SI,OFFSET TXOWNER
        MOV     CX,TXOWNLEN
        REPE    CMPSB
        JE      TXTAILOK
        MOV     AX,[TXBASE]
        MOV     [TXTAILPOS],AX
TXTAILSCAN:
        CALL    BMREAD
        D5CF    TXTAILBAD
        XOR     DI,DI
TXTAILBLK:
        MOV     AL,ES:[DI]
        OR      AL,AL
        JZ      TXTAILFILL
        CMP     AL,0E5H
        JNE     TXTAILBAD
TXTAILFILL:
        MOV     CX,256
        REPE    SCASB
        JNE     TXTAILBAD
        CMP     DI,1024
        JB      TXTAILBLK
        INC     [TXTAILPOS]
        MOV     AX,[TXTAILPOS]
        SUB     AX,[TXBASE]
        CMP     AX,(TXANCHOR+1)/4
        MOV     AX,[TXTAILPOS]
        JB      TXTAILSCAN
        XOR     DI,DI
        XOR     AX,AX
        MOV     CX,128
        REP     STOSW
        XOR     DI,DI
        MOV     SI,OFFSET TXOWNER
        MOV     CX,TXOWNLEN
        REP     MOVSB
        MOV     AX,[TXBASE]
        ADD     AX,TXANCHOR/4
        MOV     BX,TXANCHOR MOD 4
        CALL    BMWRITE
        JC      TXTAILBAD
TXTAILOK:CLC
        RET
TXTAILBAD:
        MOV     DX,OFFSET TXTAILMSG
        STC
        RET

; Damaged log: do not guess at FAT repair. Require identical FATs,
; complete non-overlapping DOS chains and a valid menu (if present).
TXREPAIR:
        CALL    D5GEOMSET
        D5CF    TXERR
        CALL    RFFATSAME
        D5CF    TXERR
        MOV     ES,[RFSEG]
        MOV     DI,256
        XOR     AX,AX
        MOV     CX,156
        REP     STOSW
        MOV     [RFIDX],0
TXKERNEL:
        CALL    RFFIND
        D5CF    TXERR
        CMP     AX,0FFFFH
        D5Z     TXERR
        TEST    BYTE PTR [MATCH+11],18H
        D5NZ    TXERR
        CALL    TXMARKCHAIN
        D5CF    TXERR
        INC     [RFIDX]
        CMP     [RFIDX],NSYS
        JB      TXKERNEL
        MOV     SI,OFFSET RFNAME
        CALL    FIND
        D5CF    TXERR
        CMP     AX,0FFFFH
        JE      TXSTATE
        CMP     WORD PTR [MATCH+12],RFJTAG
        D5NZ    TXERR
        CALL    TXMARKCHAIN
        D5CF    TXERR
TXSTATE:MOV     [D5IPL],2
        MOV     [D5UPGRADE],1  ;Accept an older stage while reading state.
        CALL    D5OPEN
        D5CF    TXERR
        CMP     [D5PRESENT],0
        JE      TXPLAIN
        CMP     BYTE PTR ES:[ST_PHASE],0
        D5NZ    TXERR
        CALL    CHECKFILES
        D5CF    TXERR
        MOV     AX,[D5STAGE]
        CALL    D5CHECKSTAGE
        JC      TXSTAGEFIX
        MOV     AX,[D5STAGESLOT]
        CALL    GETSLOT
        D5CF    TXERR
        CMP     WORD PTR ES:[DI+28],MENUSIZE
        JE      TXMENUREADY
TXSTAGEFIX:
        CALL    D5STAGEFILE
        D5CF    TXERR
TXMENUREADY:
        MOV     [D5UPGRADE],0
        CALL    D5PUBLISH
        JMP     SHORT TXREPAIRED
TXMARKCHAIN:
        CALL    CHECKCHAIN
        D5CF    TXERR
        MOV     BX,WORD PTR [MATCH+26]
TXCHAIN:
        MOV     ES,[RFSEG]
        PUSH    BX
        CALL    RFMARK
        POP     BX
        D5CF    TXERR
        XOR     AX,AX
        CALL    BMFATGET
        D5CF    TXERR
        MOV     BX,DX
        CMP     DX,0FF8H
        JB      TXCHAIN
        CLC
        RET
TXPLAIN:CALL    CHECKFILES
        D5CF    TXERR
        ; Leave block zero armed until both trailing IPL blocks are ready.
        MOV     ES,[WORKSEG]
        XOR     DI,DI
        MOV     SI,OFFSET HDBOOTCODE
        MOV     CX,512
        REP     MOVSW
        XOR     AX,AX
        MOV     BX,2
        MOV     BP,512
        CALL    BMWRITE
        D5CF    TXERR
        INC     BX
        ADD     BP,256
        CALL    BMWRITE
        D5CF    TXERR
        XOR     BX,BX
        XOR     BP,BP
        CALL    BMWRITE
TXREPAIRED:
        D5CF    TXERR
        ; Block 1 is ignored by the published IPL; clear the helper only
        ; now so a cut cannot strand an armed IPL without its own code.
        MOV     BX,1
        MOV     BP,256
        CALL    BMWRITE
        D5CF    TXERR
        MOV     DX,OFFSET TXFIXED
        CALL    PUTS
        MOV     [D5UPGRADE],0
        MOV     [D5PRESENT],0  ;The normal path reopens the state.
        JMP     HIPLCHECK

RFFATSAME:
        MOV     AX,1
TXFAT:  MOV     ES,[WORKSEG]
        XOR     BP,BP
        CALL    BMREAD
        JC      TXFATRET
        ADD     AX,[D5SPF]
        MOV     ES,[BMBUFSEG]
        CALL    BMREAD
        JC      TXFATRET
        PUSH    DS
        MOV     DS,[WORKSEG]
        XOR     SI,SI
        XOR     DI,DI
        MOV     CX,512
        REPE    CMPSW
        POP     DS
        JNE     TXFATBAD
        SUB     AX,[D5SPF]
        INC     AX
        CMP     AX,[D5SPF]
        JBE     TXFAT
        CLC
TXFATRET:RET
TXFATBAD:STC
        RET

        INCLUDE VASYSIPL.INC
