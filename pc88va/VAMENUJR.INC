; SPDX-License-Identifier: MIT
; Initial menu-file allocation journal. Used only for the first capture.
; A zero-length root entry names the two staged (initially free) clusters.
; The journal is replaced by BOOTMENU.DAT only after both FAT copies and
; BOOTMENU.SYS are committed. Retry SYS before other writes to this volume.
JRNAME  DB      'BOOTMENUJRN'
JRSLOT  DW      0
JRCL    DW      0,0             ;State, stage.
JRCOPY  DW      0
JRCUR   DW      0
JRSCAN  DW      0
JRMARK  DB      0
JRSRC   DW      0
JRLEN   DW      0

D5JRNEW:
        CALL    D5JRPAIR
        D5CF    D5NOROOM
        CALL    D5JRCLUSTERS
        D5CF    D5NOROOM
        ; Prepare the menu image and saved IPL before changing allocation.
        MOV     ES,[BMSTSEG]
        PUSH    DS
        PUSH    ES
        POP     DS
        XOR     SI,SI
        MOV     CX,ST_CSUM
        CALL    CRC16
        MOV     ES:[ST_CSUM],DX
        POP     DS
        MOV     AX,[JRCL]
        CALL    D5JRLBA
        XOR     BP,BP
D5JRSAVEST:
        PUSH    BP
        CALL    D5STORESEC
        POP     BP
        D5CF    D5IOERR
        ADD     BP,1024
        INC     AX
        CMP     BP,4096
        JB      D5JRSAVEST
        MOV     AX,[JRCL+2]
        CALL    D5JRLBA
        CALL    D5WRITESTAGE
        D5CF    D5IOERR
        MOV     AX,[JRSLOT]
        CALL    GETSLOT
        D5CF    D5IOERR
        MOV     SI,OFFSET JRNAME
        CALL    D5JRDIR
        MOV     WORD PTR ES:[DI+12],354AH
        MOV     BX,[JRCL]
        MOV     ES:[DI+14],BX
        MOV     BX,[JRCL+2]
        MOV     ES:[DI+16],BX
        CALL    PUTSLOT
        D5CF    D5IOERR
        CALL    D5JRFINISH
        D5CF    D5IOERR
        RET

D5WRITESTAGE:
        MOV     [JRSCAN],AX
        MOV     [JRSRC],OFFSET MENUBINARY
        MOV     [JRLEN],MENUSIZE
D5JRSAVEBIN:
        MOV     ES,[BMBUFSEG]
        XOR     DI,DI
        XOR     AX,AX
        MOV     CX,512
        REP     STOSW
        MOV     SI,[JRSRC]
        MOV     CX,[JRLEN]
        CMP     CX,1024
        JBE     D5JRBINCOPY
        MOV     CX,1024
D5JRBINCOPY:XOR  DI,DI
        SUB     [JRLEN],CX
        REP     MOVSB
        MOV     [JRSRC],SI
        XOR     BP,BP
        MOV     AX,[JRSCAN]
        CALL    D5STORESEC
        D5CF    D5IOERR
        INC     [JRSCAN]
        CMP     [JRLEN],0
        JNE     D5JRSAVEBIN
        CLC
        RET

; Detect an interrupted first capture before any DOS allocation.
D5JRRECOVER:
        MOV     SI,OFFSET JRNAME
        CALL    FIND
        D5CF    D5JRERR
        CMP     AX,0FFFFH
        D5Z     D5JROK
        CMP     [D5OP],0
        D5NZ    D5JRERR
        CMP     [D5IPL],1
        D5NZ    D5JRERR
        CMP     [MATCH+11],7
        D5NZ    D5JRERR
        CMP     WORD PTR [MATCH+12],354AH
        D5NZ    D5JRERR
        MOV     BX,WORD PTR [MATCH+26]
        OR      BX,WORD PTR [MATCH+28]
        OR      BX,WORD PTR [MATCH+30]
        D5NZ    D5JRERR
        MOV     [JRSLOT],AX
        MOV     AX,WORD PTR [MATCH+14]
        CALL    D5JRCLVALID
        D5CF    D5JRERR
        MOV     [JRCL],AX
        MOV     AX,WORD PTR [MATCH+16]
        CALL    D5JRCLVALID
        D5CF    D5JRERR
        MOV     [JRCL+2],AX
        CMP     AX,[JRCL]
        D5Z     D5JRERR
        CALL    D5JRLBA
        CALL    D5CHECKSTAGE
        D5CF    D5JRERR
        MOV     AX,[JRCL]
        CALL    D5JRLBA
        CALL    D5LOADSTATE
        D5CF    D5JRERR
        CMP     [COUNT],1
        D5NZ    D5JRERR
        CMP     WORD PTR ES:[ST_OWNER],0
        D5NZ    D5JRERR
        CMP     WORD PTR ES:[ST_PHASE],0103H
        D5NZ    D5JRERR
        MOV     BL,1
        CALL    IDOK
        D5CF    D5JRERR
        CALL    D5MATCHIPL
        D5CF    D5JRERR
        JMP     SHORT D5JRFINISH

; Both cluster identities and their contents are now known. First check
; that no final root name collides; then replay idempotent FAT claims.
D5JRFINISH:
        MOV     SI,OFFSET D5DAT
        CALL    FIND
        D5CF    D5JRERR
        CMP     AX,0FFFFH
        D5NZ    D5JRERR
        MOV     SI,OFFSET D5SYS
        CALL    FIND
        D5CF    D5JRERR
        MOV     BX,[JRSLOT]
        INC     BX
        CMP     AX,0FFFFH
        JE      D5JRSYSFREE
        CMP     AX,BX
        D5NZ    D5JRERR
        CMP     [MATCH+11],7
        D5NZ    D5JRERR
        MOV     AX,[JRCL+2]
        CMP     WORD PTR [MATCH+26],AX
        D5NZ    D5JRERR
        CMP     WORD PTR [MATCH+28],MENUSIZE
        D5NZ    D5JRERR
        CMP     WORD PTR [MATCH+30],0
        D5NZ    D5JRERR
        MOV     [JRMARK],1
        JMP     SHORT D5JRCLAIMALL
D5JRSYSFREE:
        MOV     AX,BX
        CALL    GETSLOT
        D5CF    D5JRERR
        CMP     BYTE PTR ES:[DI],0
        JE      D5JRCLAIMALL
        CMP     BYTE PTR ES:[DI],0E5H
        D5NZ    D5JRERR
D5JRCLAIMALL:
        MOV     [JRCOPY],0
        CALL    D5JRFATPAIR
        D5CF    D5JRERR
        MOV     AX,[D5SPF]
        MOV     [JRCOPY],AX
        CALL    D5JRFATPAIR
        D5CF    D5JRERR
        CMP     [JRMARK],0
        JNE     D5JRDATDIR
        MOV     AX,[JRSLOT]
        INC     AX
        CALL    GETSLOT
        D5CF    D5JRERR
        MOV     SI,OFFSET D5SYS
        CALL    D5JRDIR
        MOV     BX,[JRCL+2]
        MOV     ES:[DI+26],BX
        MOV     WORD PTR ES:[DI+28],MENUSIZE
        CALL    PUTSLOT
        D5CF    D5JRERR
D5JRDATDIR:
        MOV     AX,[JRSLOT]
        CALL    GETSLOT
        D5CF    D5JRERR
        MOV     SI,OFFSET D5DAT
        CALL    D5JRDIR
        MOV     BX,[JRCL]
        MOV     ES:[DI+26],BX
        MOV     WORD PTR ES:[DI+28],4096
        JMP     PUTSLOT

; Clear one dirent and apply read-only/system/hidden attributes.
D5JRDIR:PUSH    AX
        PUSH    DI
        XOR     AX,AX
        MOV     CX,16
        REP     STOSW
        POP     DI
        PUSH    DI
        MOV     CX,11
        REP     MOVSB
        MOV     BYTE PTR ES:[DI],7
        POP     DI
        MOV     WORD PTR ES:[DI+24],21H  ;1980-01-01.
        POP     AX
        RET

; Pick two consecutive unused root slots, leaving the next terminator
; intact. Never cross past the first end marker into nonzero stale data.
D5JRPAIR:
        XOR     AX,AX
        MOV     [JRSLOT],AX
D5JRPAIR1:
        MOV     AX,[JRSLOT]
        CALL    GETSLOT
        D5CF    D5JRERR
        MOV     DL,ES:[DI]
        CMP     DL,0E5H
        JE      D5JRPAIR2
        OR      DL,DL
        JNZ     D5JRPAIRNEXT
D5JRPAIR2:
        MOV     AX,[JRSLOT]
        INC     AX
        CALL    GETSLOT
        D5CF    D5JRERR
        CMP     BYTE PTR ES:[DI],0E5H
        JE      D5JRPAIR3
        CMP     BYTE PTR ES:[DI],0
        JE      D5JRPAIR4
        OR      DL,DL
        D5Z     D5JRERR
D5JRPAIRNEXT:
        INC     [JRSLOT]
        JMP     SHORT D5JRPAIR1
D5JRPAIR3:
        OR      DL,DL
        JNZ     D5JROK
D5JRPAIR4:
        MOV     AX,[JRSLOT]
        ADD     AX,2
        MOV     BX,[DATA0]
        SUB     BX,[ROOT]
        MOV     CL,5
        SHL     BX,CL
        CMP     AX,BX
        JAE     D5JROK
        CALL    GETSLOT
        D5CF    D5JRERR
        CMP     BYTE PTR ES:[DI],0
        D5NZ    D5JRERR
D5JROK: CLC
        RET
D5JRERR:STC
        RET

; Obtain the first two clusters free in both FATs. Skip a FAT12 entry
; whose two bytes straddle a physical sector: every claim is one write.
D5JRCLUSTERS:
        MOV     [JRSCAN],2
        MOV     BX,OFFSET JRCL
D5JRCLLOOP:
        MOV     AX,[JRSCAN]
        CMP     AX,[D5CLMAX]
        JA      D5JRERR
        CALL    D5JRCLVALID
        JC      D5JRCLNEXT
        PUSH    BX
        MOV     [JRCOPY],0
        CALL    D5JRFATGET
        JC      D5JRCLFAIL
        OR      DX,DX
        JNZ     D5JRCLBUSY
        MOV     AX,[D5SPF]
        MOV     [JRCOPY],AX
        MOV     AX,[JRSCAN]
        CALL    D5JRFATGET
        JC      D5JRCLFAIL
        OR      DX,DX
        JNZ     D5JRCLBUSY
        POP     BX
        MOV     AX,[JRSCAN]
        MOV     [BX],AX
        ADD     BX,2
        CMP     BX,OFFSET JRCL+4
        JE      D5JROK
        JMP     SHORT D5JRCLNEXT
D5JRCLFAIL:POP  BX
        JMP     SHORT D5JRERR
D5JRCLBUSY:POP  BX
D5JRCLNEXT:INC  [JRSCAN]
        JMP     SHORT D5JRCLLOOP
D5JRCLVALID:
        CMP     AX,2
        JB      D5JRERR
        CMP     AX,[D5CLMAX]
        JA      D5JRERR
        MOV     DX,AX
        SHR     DX,1
        ADD     DX,AX
        CMP     DL,0FFH
        JE      D5JRERR
        CLC
        RET
D5JRLBA:SUB     AX,2
        MUL     [D5SPC]
        ADD     AX,[DATA0]
        RET
D5JRFATPAIR:
        MOV     AX,[JRCL]
        CALL    D5JRFATSET
        JC      D5JRFATRET
        MOV     AX,[JRCL+2]
D5JRFATSET:
        CALL    D5JRFATGET
        JC      D5JRFATRET
        CMP     DX,0FFFH
        D5Z     D5JROK
        OR      DX,DX
        D5NZ    D5JRERR
        MOV     DX,0FFFH
        TEST    [JRCUR],1
        JZ      D5JRFATPUT
        MOV     CL,4
        SHL     DX,CL
D5JRFATPUT:OR   ES:[DI],DX
        JMP     PUTSLOT
; Return the containing logical sector AX and ES:DI pointer, plus value DX.
D5JRFATGET:
        MOV     [JRCUR],AX
        MOV     DI,AX
        SHR     DI,1
        ADD     DI,AX
        MOV     AX,DI
        MOV     CL,10
        SHR     AX,CL
        INC     AX
        ADD     AX,[JRCOPY]
        AND     DI,1023
        MOV     ES,[BMBUFSEG]
        XOR     BP,BP
        CALL    READSEC
        JC      D5JRFATRET
        MOV     DX,ES:[DI]
        TEST    [JRCUR],1
        JZ      D5JRFATVAL
        MOV     CL,4
        SHR     DX,CL
D5JRFATVAL:AND  DX,0FFFH
D5JRFATRET:RET
