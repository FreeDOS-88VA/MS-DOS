        TITLE   SYS for MS-DOS on the PC-88VA
; SPDX-License-Identifier: MIT
; Transfer the system from the current drive to a 2HD floppy or a
; mounted NEC-layout SASI volume. Both IPLs follow the FAT.

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     100H
START:  JMP     MAIN
        INCLUDE VADISK.INC
        INCLUDE VAHDINST.INC

WORKSEG DW      0
SOURCE  DB      0
S_USAGE DB      'Usage: SYS d: (2HD floppy or NEC SASI)',13,10,'$'
S_SAME  DB      'Cannot SYS to the current drive',13,10,'$'
S_BAD   DB      'Target disk is not a PC-88VA 2HD MS-DOS disk',13,10,'$'
S_IOERR DB      'Disk error on the target drive',13,10,'$'
S_NEC   DB      'Target is not a mounted NEC-layout SASI volume',13,10,'$'
S_BOOT  DB      'Cannot SYS to the boot drive',13,10,'$'

; Use an internal stack; staging system files may cross the COM segment.
MAIN:   MOV     SP,OFFSET STKTOP
        CLD
        CALL    GETDRV
        JNC     SYSARG
        JMP     USAGE
SYSARG: LODSB
        CMP     AL,' '
        JE      SYSARG
        CMP     AL,9
        JE      SYSARG
        CMP     AL,13
        JE      SYSMAIN
        JMP     USAGE
SYSMAIN:MOV     AX,OFFSET ENDPROG+15
        MOV     CL,4
        SHR     AX,CL
        MOV     BX,CS
        ADD     AX,BX
        MOV     [WORKSEG],AX
        ADD     AX,40H
        MOV     [NEXTSEG],AX
        MOV     AH,19H
        INT     21H
        CMP     AL,[DRV]
        JNE     LOADIT
        MOV     DX,OFFSET S_SAME
        JMP     ERROR
LOADIT: ADD     AL,'A'
        MOV     [SOURCE],AL
        CMP     [DRV],1
        JBE     FLOPPY
        JMP     HDSYS
FLOPPY: MOV     CX,NSYS         ;Include COMMAND.COM for standalone boot.
        CALL    LOADSYS
        JC      ERROR
        CALL    SETMODE
        MOV     ES,[WORKSEG]
        XOR     AX,AX
        XOR     BX,BX
        CALL    RDSEC
        MOV     DX,OFFSET S_IOERR
        JC      ERROR
        CMP     WORD PTR ES:[11],SECSIZ
        JNE     BADDISK
        CMP     WORD PTR ES:[24],SECTRK
        JNE     BADDISK
        CMP     WORD PTR ES:[26],2
        JNE     BADDISK
        XOR     AL,AL
        CALL    PUTBOOT
        XOR     AX,AX
        XOR     BX,BX
        CALL    WRSEC
        MOV     DX,OFFSET S_IOERR
        JC      ERROR
        PUSH    CS
        POP     ES
        MOV     AH,0DH
        INT     21H
        MOV     AL,[DRV]
        ADD     AL,'A'
        MOV     CX,NSYS
        CALL    SAVESYS
        JC      ERROR
SUCCESS:MOV     DX,OFFSET S_SYSOK
        CALL    PUTS
        MOV     AX,4C00H
        INT     21H

BADDISK:MOV     DX,OFFSET S_BAD
ERROR:  PUSH    CS
        POP     ES
        CALL    PUTS
        MOV     AX,4C01H
        INT     21H
USAGE:  MOV     DX,OFFSET S_USAGE
        JMP     ERROR

HDSYS:  MOV     BL,[DRV]
        INC     BL
        MOV     CL,0F2H
        CALL    HIOCTL
        JC      NOTNEC
        MOV     AX,[FIO]
        CMP     AH,0D4H
        JNE     NOTNEC
        CMP     AL,2
        JAE     NOTNEC
        MOV     [FTARGET],AL
        MOV     AX,3305H
        INT     21H
        DEC     DL
        CMP     DL,[DRV]
        JNE     HDALLOC
        MOV     DX,OFFSET S_BOOT
        JMP     ERROR
NOTNEC: MOV     DX,OFFSET S_NEC
        JMP     ERROR
HDALLOC:MOV     AX,[WORKSEG]
        ADD     AX,63
        AND     AX,0FFC0H
        MOV     [WORKSEG],AX
        ADD     AX,64
        MOV     [NEXTSEG],AX
        CMP     AX,DS:[2]
        JBE     HDVALID
        MOV     DX,OFFSET S_NOMEM
        JMP     ERROR
HDVALID:CALL    HPROBE
        JC      NOTNEC
        MOV     [FTYPE],AL
        MOV     ES,[WORKSEG]
        MOV     [FBLOCK],4
        CALL    HREAD
        JC      HDSYSIO
        MOV     AL,[FTYPE]
        ADD     AL,0D0H
        MOV     AH,0FFH
        CMP     WORD PTR ES:[0],AX
        JNE     NOTNEC
        CMP     BYTE PTR ES:[2],0FFH
        JNE     NOTNEC
        CALL    HIPLCHECK
        JC      HDSYSIO
        OR      AL,AL
        JZ      HDCOPY
        CALL    HCONFSTDIN
        JC      HDSYSERR
        MOV     DX,OFFSET S_HDIPL
        CALL    PUTS
        MOV     DX,OFFSET S_HDPROMPT
        CALL    PUTS
        CALL    HYES
        MOV     DX,OFFSET S_HDCANCEL
        JC      HDSYSERR
HDCOPY: MOV     AL,[SOURCE]
        MOV     CX,NSYS
        CALL    LOADSYS
        JC      HDSYSERR
        PUSH    CS
        POP     ES
        MOV     AL,[DRV]
        ADD     AL,'A'
        MOV     CX,NSYS
        CALL    SAVESYS
        JC      HDSYSERR
        MOV     AH,0DH
        INT     21H
        CALL    HIPLWRITE
        JC      HDSYSIO
        CALL    HNOTE
        JMP     SUCCESS
HDSYSIO:MOV     DX,OFFSET S_IOERR
HDSYSERR:JMP    ERROR

        DW      256 DUP (0)
STKTOP  LABEL   WORD
ENDPROG LABEL   BYTE
CODE    ENDS
        END     START
