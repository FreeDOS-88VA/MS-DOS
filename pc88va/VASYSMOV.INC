; SPDX-License-Identifier: MIT
; Bring the two kernel names into a common physical root block without
; touching a PC-Engine or user slot. Keep the original dirent verbatim.
RMIO    DW      0
RMDOS   DW      0
RMEND   DW      0
RMSRC   DW      0
RMDST   DW      0
RMLIMIT DW      0
RMENTRY DB      32 DUP (0)

RFSLOTS:PUSH    ES
        CALL    RMPAIR
        POP     ES
        RET
RMPAIR: MOV     SI,OFFSET RFNAMES
        CALL    FIND
        D5CF    RFERROR
        CMP     AX,0FFFFH
        D5Z     RFERROR
        MOV     [RMIO],AX
        MOV     SI,OFFSET RFNAMES+11
        CALL    FIND
        D5CF    RFERROR
        CMP     AX,0FFFFH
        D5Z     RFERROR
        MOV     [RMDOS],AX
        MOV     [RMEND],BX
        XOR     AX,[RMIO]
        AND     AX,0FFF8H
        JZ      RMOK
        MOV     AX,[RMDOS]
        CALL    RMFREE
        JC      RMDISK
        MOV     DX,[RMIO]
        CMP     AX,0FFFFH
        JNE     RMCHOSEN
        MOV     AX,[RMIO]
        CALL    RMFREE
        JC      RMDISK
        MOV     DX,[RMDOS]
        CMP     AX,0FFFFH
        JE      RMROOM
RMCHOSEN:
        MOV     [RMDST],AX
        MOV     [RMSRC],DX
        MOV     AX,DX
        CALL    GETSLOT
        D5CF    RFERROR
        PUSH    DS
        PUSH    ES
        POP     DS
        PUSH    CS
        POP     ES
        MOV     SI,DI
        MOV     DI,OFFSET RMENTRY
        MOV     CX,16
        REP     MOVSW
        POP     DS
        TEST    BYTE PTR [RMENTRY+11],18H
        D5NZ    RFERROR
        CALL    TXBEGIN
        D5CF    D5PASS
        CALL    RMMOVE
        MOV     [TXPLAN],0
        D5CF    RFERROR
        JMP     TXCOMMIT
RMOK:   CLC
        RET
RMDISK: JMP     RFERROR
RMROOM: MOV     DX,OFFSET TXROOM
        STC
        RET

RMMOVE: MOV     AX,[RMDST]
        CALL    GETSLOT
        JC      RMMRET
        PUSH    DI
        MOV     SI,OFFSET RMENTRY
        MOV     CX,16
        REP     MOVSW
        POP     DI
        CALL    PUTSLOT
        JC      RMMRET
        MOV     AX,[RMSRC]
        CALL    GETSLOT
        JC      RMMRET
        MOV     BYTE PTR ES:[DI],0E5H
        CALL    PUTSLOT
RMMRET: RET

; AX names the block to search. An end marker is usable only when the
; following entry is also zero (or the marker is the final root slot).
RMFREE: AND     AX,0FFF8H
        MOV     [RMDST],AX
        ADD     AX,8
        MOV     [RMLIMIT],AX
RMNEXT: MOV     AX,[RMDST]
        CMP     AX,[RMEND]
        JA      RMNONE
        CMP     AX,[RMLIMIT]
        JAE     RMNONE
        CALL    GETSLOT
        JC      RMMRET
        CMP     BYTE PTR ES:[DI],0E5H
        JE      RMFOUND
        CMP     BYTE PTR ES:[DI],0
        JE      RMTERM
        INC     [RMDST]
        JMP     SHORT RMNEXT
RMTERM: MOV     BX,[DATA0]
        SUB     BX,[ROOT]
        MOV     CL,5
        SHL     BX,CL
        MOV     AX,[RMDST]
        INC     AX
        CMP     AX,BX
        JAE     RMFOUND
        CALL    GETSLOT
        JC      RMMRET
        CMP     BYTE PTR ES:[DI],0
        JE      RMFOUND
RMNONE: MOV     AX,0FFFFH
        CLC
        RET
RMFOUND:MOV     AX,[RMDST]
        CLC
        RET
