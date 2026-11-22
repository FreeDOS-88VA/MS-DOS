; SPDX-License-Identifier: MIT
; Shared SYS/FORMAT SASI installation helpers. DS = CS. WORKSEG must
; name an allocated, physically 1 KiB-aligned scratch sector.
FTARGET DB      0
FTYPE   DB      0
FBLOCK  DW      0
HFLAGS  DW      0245H
FIO     DW      0
HDANSWER DB     8,0,8 DUP (0)
S_HDIPL DB      'Warning: replacing a nonblank, foreign or older SASI IPL.',13,10,'$'
S_HDPROMPT DB   'Type Y and press Enter to replace the IPL: $'
S_HDCON DB      'SASI installation requires console input.',13,10,'$'
S_HDCANCEL DB   'System transfer cancelled.',13,10,'$'
S_HDT1  DB      'To boot this disk in vaeg, attach it as SASI target 0.',13,10,'$'

; BL = one-based DOS drive; CL = private function. FIO is the packet.
HIOCTL: MOV     CH,08H
        XOR     BH,BH
        MOV     DX,OFFSET FIO
        MOV     AX,440DH
        INT     21H
        RET

HPROBE: XOR     BX,BX
        MOV     BH,[FTARGET]
        MOV     AX,0900H
        CALL    HROM
        JC      HPROBER
        CMP     AL,4            ;Also excludes AL=FFh for absent target.
        CMC
HPROBER:RET

HREAD:  MOV     AX,8104H
        JMP     SHORT HXFER
HWRITE: MOV     AX,8204H
HXFER:  XOR     DX,DX
        XOR     BP,BP
        MOV     CX,[FBLOCK]
        MOV     BH,[FTARGET]
        OR      BH,80H
HROM:   PUSH    DS
        PUSH    ES
        PUSH    [HFLAGS]
        POPF
        CLC
        INT     81H
        CLD
        POP     ES
        POP     DS
        RET

; Read the reserved area. On success AL=0 for ours/blank, 1 otherwise.
HIPLCHECK:
        MOV     ES,[WORKSEG]
        MOV     [FBLOCK],0
        CALL    HREAD
        JC      HIPLRET
        XOR     DI,DI
        MOV     SI,OFFSET HDBOOTCODE
        MOV     CX,512
        REPE    CMPSW
        JE      HIPLOK
        XOR     DI,DI
        MOV     AL,ES:[DI]
        CMP     AL,0
        JE      HIPLBLANK
        CMP     AL,0E5H
        JNE     HIPLFOREIGN
HIPLBLANK:
        MOV     CX,1024
        REPE    SCASB
        JNE     HIPLFOREIGN
HIPLOK: XOR     AL,AL
        RET
HIPLFOREIGN:
        MOV     AL,1
        CLC
HIPLRET:RET

HIPLWRITE:
        MOV     ES,[WORKSEG]
        XOR     DI,DI
        MOV     SI,OFFSET HDBOOTCODE
        MOV     CX,512
        REP     MOVSW
        MOV     [FBLOCK],0
        JMP     HWRITE

; CF=0 only when stdin is the console. Return error message on failure.
HCONFSTDIN:
        MOV     AX,4400H
        XOR     BX,BX
        INT     21H
        JC      HCONFERR
        AND     DL,81H
        CMP     DL,81H
        JE      HCONFOK
HCONFERR:
        MOV     DX,OFFSET S_HDCON
        STC
HCONFOK:RET

; CF=0 only for a single Y (case-insensitive) followed by Enter.
HYES:   MOV     DX,OFFSET HDANSWER
        MOV     AX,0C0AH
        INT     21H
        CALL    CRLF
        CMP     [HDANSWER+1],1
        JNE     HYESNO
        MOV     AL,[HDANSWER+2]
        AND     AL,0DFH
        CMP     AL,'Y'
        JE      HYESOK
HYESNO: STC
HYESOK: RET

HNOTE:  CMP     [FTARGET],0
        JE      HNOTER
        MOV     DX,OFFSET S_HDT1
        CALL    PUTS
HNOTER: RET
