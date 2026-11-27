        TITLE   SASI IPL for MS-DOS on the PC-88VA
; SPDX-License-Identifier: MIT
; The V3 ROM reads the first two physical blocks at 3000:0 from SASI
; target 0. The remaining two blocks are ours to load. Logical sectors
; are 1 KiB and start at physical block 0; FAT 1 starts at block 4.

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME CS:CODE,DS:CODE
        ORG     0
IPL:    CLI
        MOV     AX,CS
        MOV     SS,AX
        MOV     SP,1000H
        MOV     DS,AX
        MOV     ES,AX
        STI
        CLD
        MOV     AX,8102H
        MOV     CX,2
        XOR     DX,DX
        MOV     BP,512
        CALL    READROM
        JC      FAIL
        JMP     STAGE2

; ROM relative addressing. Preserve loop state and segment registers.
READROM:PUSH    AX
        PUSH    BX
        PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        MOV     BX,8000H        ;Relative addressing, target 0.
        INT     81H
        POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     SI
        POP     DX
        POP     CX
        POP     BX
        POP     AX
        CLD
        RET
FAIL:   PUSH    CS
        POP     DS
        MOV     SI,OFFSET MSG
        MOV     DX,8000H
        MOV     AH,2
        INT     83H
HALT:   CLI
        HLT
        JMP     SHORT HALT
; AX = logical LBA, ES:BP = 1 KiB aligned DMA buffer. No transfer
; can cross a physical 64 KiB boundary, including the last file sector.
READSEC:MOV     CX,AX
        XOR     DX,DX
        SHL     CX,1
        RCL     DX,1
        SHL     CX,1
        RCL     DX,1
        PUSH    AX
        MOV     AX,8104H
        CALL    READROM
        POP     AX
        RET

MSG     DB      'Cannot boot MS-DOS from SASI target 0',13,10,0
MENUNAME DB     'BOOTMENUSYS'
        INCLUDE VAMENUSZ.INC     ;Generated from VAMENU.ASM.

; The distribution embeds the exact length and CRC of our second stage.
; Never execute a partial read, bad chain, or mismatching stage image.
TRYMENU:MOV     [LOADSEG],3800H
        MOV     [LOADSIZE],4096
        MOV     SI,OFFSET DATNAME
        CALL    LOADFILE
        JC      MENUERR
        PUSH    [FIRSTLBA]
        MOV     [LOADSEG],3400H
        MOV     [LOADSIZE],MENUSIZE
        MOV     SI,OFFSET MENUNAME
        CALL    LOADFILE
        POP     BX
        JC      MENUERR
        PUSH    DS
        MOV     AX,3400H
        MOV     DS,AX
        XOR     SI,SI
        MOV     CX,MENUSIZE
        CALL    CRC16
        POP     DS
        CMP     DX,MENUCRC
        JNE     MENUERR
        MOV     AX,BX            ;State file's first logical sector.
        MOV     BX,[ROOTLBA]
        MOV     CX,[DATALBA]
        DB      09AH            ;CALL FAR 3400:0000, RETF to DOS on return.
        DW      0,3400H
MENUEND:PUSH    CS
        POP     DS
        CLD
        RET
MENUERR:MOV     SI,OFFSET MENUBAD
        MOV     DX,8000H
        MOV     AH,2
        INT     83H
        JMP     SHORT MENUEND
        ORG     255
MENUFLAG DB     0               ;Opt-in; a plain FORMAT /S stays on the D4 path.
        ORG     512
STAGE2: MOV     AX,0900H
        XOR     BX,BX
        INT     81H
        PUSH    CS
        POP     DS
        PUSH    CS
        POP     ES
        CLD
        JC      BADGEOM
        CMP     AL,4
        JAE     BADGEOM
        ADD     AL,0D0H
        MOV     AH,0FFH
        MOV     [FATID],AX
        SUB     AL,0D0H
        MOV     AH,10
        MUL     AH
        MOV     SI,AX
        ADD     SI,OFFSET GEOM
        MOV     DI,OFFSET SPF
        MOV     CX,5
        REP     MOVSW
        MOV     BP,2000H         ;FAT at 3000:2000..2FFF.
        MOV     AX,1
FATLOOP:CALL    READSEC
        JC      BADGEOM
        ADD     BP,1024
        INC     AX
        CMP     AX,[SPF]
        JBE     FATLOOP
        MOV     AX,[FATID]
        CMP     WORD PTR DS:[2000H],AX
        JNE     BADGEOM
        CMP     BYTE PTR DS:[2002H],0FFH
        JNE     BADGEOM
        CMP     [MENUFLAG],0
        JE      DOSBOOT
        CALL    TRYMENU
DOSBOOT:MOV     [LOADSIZE],0
        MOV     [LOADSEG],1000H
        MOV     SI,OFFSET IONAME
        CALL    LOADFILE
        JC      BADGEOM
        PUSH    [LOADSEG]
        MOV     SI,OFFSET DOSNAME
        CALL    LOADFILE
        POP     DX
        JC      BADGEOM
        MOV     AX,5648H         ;VAIO SASI boot marker; BL = target.
        XOR     BX,BX
        DB      0EAH
        DW      0,1000H
BADGEOM:JMP     FAIL

LOADFILE:
        PUSH    CS
        POP     ES
        MOV     BP,1000H         ;One root sector at a time.
        MOV     AX,[ROOTLBA]
ROOTSEC:CALL    READSEC
        JC      BADFILE
        MOV     DI,BP
ROOTENT:CMP     BYTE PTR [DI],0
        JE      BADFILE
        TEST    BYTE PTR [DI+11],18H
        JNZ     ROOTNEXT
        PUSH    SI
        PUSH    DI
        MOV     CX,11
        REPE    CMPSB
        POP     DI
        POP     SI
        JE      FOUND
ROOTNEXT:
        ADD     DI,32
        CMP     DI,1400H
        JB      ROOTENT
        INC     AX
        CMP     AX,[DATALBA]
        JB      ROOTSEC
BADFILE:STC
        RET
FOUND:  CMP     WORD PTR [DI+30],0
        JNE     BADFILE
        MOV     AX,[DI+28]
        CMP     [LOADSIZE],0
        JE      SIZEOK
        MOV     BL,[DI+11]
        AND     BL,0DFH         ;DOS sets archive on write.
        CMP     BL,7
        JNE     BADFILE
        CMP     AX,[LOADSIZE]
        JNE     BADFILE
SIZEOK: OR      AX,AX
        JZ      BADFILE
        DEC     AX
        MOV     CL,10
        SHR     AX,CL
        INC     AX
        MOV     [LEFTSEC],AX
        MOV     BX,[DI+26]
        MOV     [FIRSTLBA],0
        XOR     BP,BP
CLUSTER:CMP     BX,2
        JB      BADFILE
        CMP     BX,[MAXCL]
        JA      BADFILE
        LEA     AX,[BX-2]
        MUL     [SPC]
        ADD     AX,[DATALBA]
        CMP     [FIRSTLBA],0
        JNE     GOTLBA
        MOV     [FIRSTLBA],AX
GOTLBA: MOV     DI,[SPC]
FILESEC:MOV     ES,[LOADSEG]
        CALL    READSEC
        JC      BADFILE
        ADD     [LOADSEG],40H
        INC     AX
        DEC     [LEFTSEC]
        JZ      CHAIN
        DEC     DI
        JNZ     FILESEC
CHAIN:  MOV     SI,BX
        SHR     SI,1
        ADD     SI,BX
        MOV     AX,[SI+2000H]
        TEST    BL,1
        JZ      CHAIN1
        MOV     CL,4
        SHR     AX,CL
CHAIN1: AND     AX,0FFFH
        MOV     BX,AX
        CMP     [LEFTSEC],0
        JNE     CLUSTER          ;Size bounds even a cyclic chain.
        CMP     AX,0FF8H        ;CF directly reports a missing EOC.
        RET

        INCLUDE VACRC16.INC

; FAT length, first root and data sectors, largest full cluster, SPC.
GEOM    DW      1,3,22,617,8
        DW      2,5,36,1234,8
        DW      4,9,56,2469,8
        DW      4,9,105,2469,16
SPF     DW      0
ROOTLBA DW      0
DATALBA DW      0
MAXCL   DW      0
SPC     DW      0
FATID   DW      0
LOADSEG DW      0
LEFTSEC DW      0
LOADSIZE DW     0
FIRSTLBA DW     0
DATNAME DB      'BOOTMENUDAT'
MENUBAD DB      'Boot menu unavailable; starting MS-DOS.',13,10,0
IONAME  DB      'IO      SYS'
DOSNAME DB      'MSDOS   SYS'
        ORG     1023
        DB      0
CODE    ENDS
        END     IPL
