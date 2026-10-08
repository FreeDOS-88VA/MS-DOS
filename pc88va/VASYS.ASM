        TITLE   SYS for MS-DOS on the PC-88VA

; SPDX-License-Identifier: MIT
;
; SYS d:
;
; Makes a formatted 2HD diskette in drive A: or B: bootable: writes the
; PC-88VA boot code (keeping the BPB of the disk) and copies IO.SYS and
; MSDOS.SYS from the current drive.  The boot code loads the files through
; the FAT, so they need not be first on the disk.  Uses only MS-DOS 2.0
; calls and the ROM floppy BIOS.

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE

        ORG     100H

START:  JMP     MAIN

        INCLUDE VADISK.INC

WORKSEG DW      0

S_USAGE DB      'Usage: SYS A:|B:',13,10,'$'
S_SAME  DB      'Cannot SYS to the current drive',13,10,'$'
S_BAD   DB      'Target disk is not a PC-88VA 2HD MS-DOS disk',13,10,'$'
S_IOERR DB      'Disk error on the target drive',13,10,'$'

; The system files are loaded after the program and may pass the top of
; the .COM segment, so run on a stack inside the program.
MAIN:   MOV     SP,OFFSET STKTOP
        CLD
        CALL    GETDRV
        JNC     @F
        JMP     USAGE
@@:
        MOV     AX,OFFSET ENDPROG+15
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
        JMP     SHORT ERROR
LOADIT: ADD     AL,'A'
        MOV     CX,2            ;IO.SYS and MSDOS.SYS.
        CALL    LOADSYS
        JC      ERROR

        CALL    SETMODE
        MOV     ES,[WORKSEG]
        XOR     AX,AX
        XOR     BX,BX
        CALL    RDSEC
        MOV     DX,OFFSET S_IOERR
        JC      ERROR
        CMP     WORD PTR ES:[11],SECSIZ ;Bytes per sector.
        JNE     BADDISK
        CMP     WORD PTR ES:[24],SECTRK ;Sectors per track.
        JNE     BADDISK
        CMP     WORD PTR ES:[26],2      ;Heads.
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
        MOV     CX,2
        CALL    SAVESYS
        JC      ERROR
        MOV     DX,OFFSET S_SYSOK
        CALL    PUTS
        MOV     AX,4C00H
        INT     21H

BADDISK:
        MOV     DX,OFFSET S_BAD
ERROR:  PUSH    CS
        POP     ES
        CALL    PUTS
        MOV     AX,4C01H
        INT     21H
USAGE:  MOV     DX,OFFSET S_USAGE
        JMP     ERROR

        DW      256 DUP (0)
STKTOP  LABEL   WORD

ENDPROG LABEL   BYTE

CODE    ENDS

        END     START
