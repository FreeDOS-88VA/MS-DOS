; SPDX-License-Identifier: MIT
; Fresh SASI volume: allocate consecutive whole clusters, but write only
; sectors containing file data. At most 3 * 8 clusters are needed, so
; all chain entries fit in the first FAT sector on every size.
HCLBLOCKS DW    32             ;Physical blocks per cluster (64 on 40 MB).
HSTART  DW      NSYS DUP (0)   ;Starting cluster per staged file.
HNEXTCL DW      2
HLEFT   DW      0
HSEG    DW      0
HFIDX   DW      0
HDNAMES DB      'IO      SYS','MSDOS   SYS','COMMAND COM'

HFILES: CMP     [FTYPE],3
        JNE     HFILE
        MOV     [HCLBLOCKS],64
HFILE:  MOV     BX,[HFIDX]
        MOV     AX,[SYSSIZE+BX]
        MOV     [HLEFT],AX
        MOV     AX,[SYSSEG+BX]
        MOV     [HSEG],AX
        MOV     AX,[HNEXTCL]
        MOV     [HSTART+BX],AX
        SUB     AX,2
        MUL     [HCLBLOCKS]
        ADD     AX,[FEND]
        MOV     [FBLOCK],AX
        MOV     AX,[HCLBLOCKS]
        MOV     CL,8
        SHL     AX,CL           ;Bytes per cluster.
        MOV     CX,AX
        MOV     AX,[HLEFT]
        DEC     AX
        XOR     DX,DX
        DIV     CX
        INC     AX
        ADD     [HNEXTCL],AX
HFDATA: CALL    CLRBUF
        MOV     CX,[HLEFT]
        CMP     CX,1024
        JBE     HFDLEN
        MOV     CX,1024
HFDLEN: SUB     [HLEFT],CX
        XOR     SI,SI
        XOR     DI,DI
        MOV     AX,[HSEG]
        PUSH    DS
        MOV     DS,AX
        REP     MOVSB
        POP     DS
        CALL    HWRITE
        JNC     HFDNEXT
        JMP     HFAIL
HFDNEXT:ADD     [HSEG],40H
        ADD     [FBLOCK],4
        CMP     [HLEFT],0
        JNE     HFDATA
        ADD     [HFIDX],2
        CMP     [HFIDX],NSYS*2
        JAE     HFDONE
        JMP     HFILE
HFDONE: RET

; Append system entries after any volume label in the first root sector.
HDROOTFILES:
        XOR     DI,DI
        CMP     [HASLBL],0
        JE      HDRSTART
        MOV     DI,32
HDRSTART:MOV    SI,OFFSET HDNAMES
        XOR     BX,BX
HDRENTRY:PUSH   DI
        XOR     AX,AX
        MOV     CX,16
        REP     STOSW
        POP     DI
        MOV     CX,11
        REP     MOVSB
        MOV     AX,[SYSATTR+BX]
        STOSB
        MOV     AX,[SYSTIME+BX]
        MOV     ES:[DI+10],AX
        MOV     AX,[SYSDATE+BX]
        MOV     ES:[DI+12],AX
        MOV     AX,[HSTART+BX]
        MOV     ES:[DI+14],AX
        MOV     AX,[SYSSIZE+BX]
        MOV     ES:[DI+16],AX
        ADD     DI,20
        ADD     BX,2
        CMP     BX,NSYS*2
        JB      HDRENTRY
        RET

HDFATFILES:
        XOR     SI,SI
HDFFILE:MOV     BX,[HSTART+SI]
        MOV     DX,[HNEXTCL]
        CMP     SI,(NSYS-1)*2
        JE      HDFCL
        MOV     DX,[HSTART+SI+2]
HDFCL:  MOV     AX,BX
        INC     AX
        CMP     AX,DX
        JB      HDFPACK
        MOV     AX,0FFFH
HDFPACK:MOV     DI,BX
        SHR     DI,1
        ADD     DI,BX
        TEST    BL,1
        JNZ     HDFODD
        AND     WORD PTR ES:[DI],0F000H
        JMP     SHORT HDFOR
HDFODD: MOV     CL,4
        SHL     AX,CL
        AND     WORD PTR ES:[DI],000FH
HDFOR:  OR      ES:[DI],AX
        INC     BX
        CMP     BX,DX
        JB      HDFCL
        ADD     SI,2
        CMP     SI,NSYS*2
        JB      HDFFILE
        RET
