; SPDX-License-Identifier: MIT
; Temporary target-0 IPL. SYS arms it with one physical write only after
; the complete redo log is durable. SYS and the ROM use the same replay
; routine. No code or data from the log is executed except the restored IPL.
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
        PUSH    CS
        CALL    TXRUN
        JC      TXHALT
        ; The last image is the original block zero. Copy it from the
        ; DMA buffer while executing outside the overwritten block.
        MOV     SI,TXTRAMP-TXIPL
        MOV     DI,200H
        MOVSW
        MOVSW
        MOV     SI,BP
        XOR     DI,DI
        PUSH    DI
        MOV     CX,128
        MOV     DX,200H
        JMP     DX
TXTRAMP:REP     MOVSW
        RET
TXHALT: HLT
        JMP     SHORT TXHALT

; Enter at CS:(TXRUN-TXIPL), DS=CS, ES:BP = 512-byte aligned scratch,
; BX = ROM addressing mode and drive. Leave final image at ES:BP.
TXRUN:  XOR     DI,DI
        ADD     BP,256
        CALL    TXLOAD
        LEA     BP,[BP-256]
        JC      TXFAIL
        LEA     SI,[BP+256]
        CALL    TXCRC
        CMP     DX,DS:[TXSUM-TXIPL]
        JNE     TXFAIL
        LEA     SI,[BP+256]
TXSTEP: INC     DI
        CMP     DI,TXMAX+2
        JAE     TXFAIL
        CALL    TXLOAD
        JC      TXFAIL
        PUSH    SI
        MOV     SI,BP
        CALL    TXCRC
        POP     SI
        CMP     DX,ES:[SI+2]
        JNE     TXFAIL
        XOR     DX,DX
        MOV     CX,ES:[SI]
        CMP     DI,DS:[TXCOUNT-TXIPL]
        JE      TXLAST
        CMP     CX,4
        JB      TXFAIL
        CMP     CX,DS:[TXLIMIT-TXIPL]
        JAE     TXFAIL
        MOV     AX,8201H
        PUSH    CS
        CALL    TXIO
        JC      TXFAIL
        ADD     SI,4
        JMP     SHORT TXSTEP
TXLAST: OR      CX,CX
        JNZ     TXFAIL
        MOV     AX,8201H
        JMP     SHORT TXIO
TXFAIL: STC
        RETF

TXLOAD: MOV     CX,DS:[TXBASE-TXIPL]
        MOV     AX,DI
        CMP     AX,DS:[TXSPAN-TXIPL]
        JB      TXADDR
        SUB     AX,DS:[TXSPAN-TXIPL]
        MOV     CX,DS:[TXBASE+2-TXIPL]
TXADDR: XOR     DX,DX
        SHL     CX,1
        RCL     DX,1
        SHL     CX,1
        RCL     DX,1
        ADD     CX,AX
        ADC     DX,0
        MOV     AX,8101H
        PUSH    CS
        CALL    TXIO
        RET
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
        RETF

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
TXDATA  LABEL   BYTE
TXBASE  DW      0,0
TXSPAN  DW      0
TXCOUNT DW      0
TXLIMIT DW      0
TXSUM   DW      0
        DB      (256-($-TXIPL)) DUP (0)
