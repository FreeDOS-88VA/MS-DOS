; SPDX-License-Identifier: MIT
; Temporary replay IPL. The ROM fetches both of these blocks. Ordinary
; DOS IPLs ignore block 1, so write the helper there before arming block 0.
TXIPL:  CLI
        MOV     AX,CS
        MOV     SS,AX
        MOV     SP,2000H
        MOV     DS,AX
        MOV     ES,AX
        STI
        CLD
        MOV     BX,8000H
        MOV     BP,1000H
        JMP     TXBOOT
TXMAGIC DB      'VATX4'

; Far entry, DS = IPL segment, ES:BP = aligned 512-byte scratch,
; BX = relative addressing and target. Return final IPL at ES:BP.
TXRUN:  XOR     DI,DI
        ADD     BP,256
        CALL    TXLOAD
        LEA     BP,[BP-256]
        JC      TXFAIL
        LEA     SI,[BP+256]
        CALL    TXCRC
        CMP     DX,DS:[TXSUM-TXIPL]
        JNE     TXFAIL
        ; Verify the entire log and the live preconditions before writing.
        XOR     AX,AX
        CALL    TXPASS
        JC      TXFAIL
        MOV     AX,1
        CALL    TXPASS
        RETF
TXFAIL: STC
        RETF

TXPASS: PUSH    AX
        XOR     DI,DI
        LEA     SI,[BP+256]
TXSTEP: INC     DI
        CMP     DI,TXMAX+2
        JAE     TXBAD
        CALL    TXLOAD
        JC      TXBAD
        CALL    TXBUFCRC
        CMP     DX,ES:[SI+2]
        JNE     TXBAD
        MOV     CX,ES:[SI]
        CMP     DI,DS:[TXCOUNT-TXIPL]
        JE      TXLAST
        CMP     CX,4
        JB      TXBAD
        CMP     CX,DS:[TXLIMIT-TXIPL]
        JAE     TXBAD
        JMP     SHORT TXGUARD
TXLAST: JC      TXBAD           ;Also require an exact final entry.
        JCXZ    TXACTION
TXBAD:  STC
        JMP     SHORT TXEND
TXGUARD:XOR     DX,DX
        POP     AX
        PUSH    AX
        OR      AX,AX
        JNZ     TXACTION
        MOV     AX,8101H
        CALL    TXIO
        JC      TXBAD
        CALL    TXBUFCRC
        CMP     DX,ES:[SI+2]    ;Already replayed before an interruption.
        JE      TXNEXT
        PUSH    DI
        DEC     DI
        SHL     DI,1
        CMP     DX,ES:[DI+BP+256+TXGUARDS]
        POP     DI
        JNE     TXBAD
        JMP     SHORT TXNEXT
TXACTION:
        POP     AX
        PUSH    AX
        OR      AX,AX
        JZ      TXNEXT
        XOR     DX,DX
        MOV     AX,8201H
        CALL    TXIO
        JC      TXBAD
TXNEXT: ADD     SI,4
        CMP     DI,DS:[TXCOUNT-TXIPL]
        JB      TXSTEP
        CLC
TXEND:  POP     AX
        RET

TXBUFCRC:
        PUSH    SI
        MOV     SI,BP
        CALL    TXCRC
        POP     SI
        RET
TXDATA  LABEL   BYTE
TXBASE  DW      0
TXCOUNT DW      0
TXLIMIT DW      0
TXSUM   DW      0
        DB      (256-($-TXIPL)) DUP (0)
TXHELP  LABEL   BYTE
TXBOOT: PUSH    CS
        CALL    TXRUN
        JC      TXHALT
        ; Execute in block 1 while replacing block 0 in memory.
        MOV     SI,BP
        XOR     DI,DI
        PUSH    DI
        MOV     CX,128
        REP     MOVSW
        RET
TXHALT: MOV     SI,TXMSG-TXIPL
        MOV     DX,8000H
        MOV     AH,2
        INT     83H
        CLI
TXWAIT: HLT
        JMP     SHORT TXWAIT
TXMSG   DB      'SASI redo failed. Boot the MS-DOS floppy and run SYS C:',13,10,0

TXLOAD: MOV     CX,DS:[TXBASE-TXIPL]
        XOR     DX,DX
        SHL     CX,1
        RCL     DX,1
        SHL     CX,1
        RCL     DX,1
        ADD     CX,DI
        ADC     DX,0
        MOV     AX,8101H
TXIO:   PUSH    BX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        INT     81H
        POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     SI
        POP     BX
        CLD
        RET
TXCRC:  MOV     CX,256
        XOR     DX,DX
TXCB:   DB      26H             ;ES: prefix for LODSB.
        LODSB
        XOR     DL,AL
        MOV     AH,8
TXCL:   SHR     DX,1
        JNC     TXCN
        XOR     DX,0A001H
TXCN:   DEC     AH
        JNZ     TXCL
        LOOP    TXCB
        RET
        DB      (512-($-TXIPL)) DUP (0)
