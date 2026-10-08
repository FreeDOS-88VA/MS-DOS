        TITLE   FORMAT for MS-DOS on the PC-88VA

; SPDX-License-Identifier: MIT
;
; FORMAT d: [/S] [/V:label]
;
; Formats a 2HD diskette in drive A: or B: with 1024-byte sectors, 8
; sectors per track, 80 cylinders and 2 heads (1,280 sectors), writes the
; PC-88VA boot sector, two empty FATs and an empty root directory.  /S also
; copies IO.SYS, MSDOS.SYS and COMMAND.COM from the current drive; /V sets
; a volume label.  Uses only MS-DOS 2.0 calls and the ROM floppy BIOS.

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE

        ORG     100H

START:  JMP     MAIN

        INCLUDE VADISK.INC

OPTSYS  DB      0
LBLNAME DB      11 DUP (' ')
HASLBL  DB      0
WORKSEG DW      0               ;8 KB sector buffer.

S_USAGE DB      'Usage: FORMAT A:|B: [/S] [/V:label]',13,10,'$'
S_INS1  DB      'Insert new diskette for drive $'
S_INS2  DB      ':',13,10,'and press ENTER when ready...$'
S_FMT   DB      'Formatting...$'
S_TRK   DB      13,'Formatting... track $'
S_DONE  DB      13,'Format complete               ',13,10,'$'
S_WP    DB      13,10,'Write protect error',13,10,'Format terminated',13,10,'$'
S_FAIL  DB      13,10,'Format failure',13,10,'$'
S_TOT   DB      ' bytes total disk space',13,10,'$'
S_SYS   DB      ' bytes used by system',13,10,'$'
S_AVL   DB      ' bytes available on disk',13,10,'$'
S_CUR   DB      'Cannot format the current drive with /S',13,10,'$'

; The system files are loaded after the program and may pass the top of
; the .COM segment, so run on a stack inside the program.
MAIN:   MOV     SP,OFFSET STKTOP
        CLD
        CALL    GETDRV
        JC      USAGE
OPT1:   LODSB
        CMP     AL,' '
        JE      OPT1
        CMP     AL,9
        JE      OPT1
        CMP     AL,13
        JE      OPTEND
        CMP     AL,'/'
        JNE     USAGE
        LODSB
        AND     AL,0DFH
        CMP     AL,'S'
        JNE     OPT2
        MOV     [OPTSYS],1
        JMP     OPT1
OPT2:   CMP     AL,'V'
        JNE     USAGE
        CMP     BYTE PTR [SI],':'
        JNE     USAGE
        INC     SI
        MOV     [HASLBL],1
        MOV     DI,OFFSET LBLNAME
        MOV     CX,11
OPT3:   LODSB
        CMP     AL,' '
        JBE     OPT4
        CMP     AL,'/'
        JE      OPT4
        CMP     AL,'a'
        JB      OPT3A
        CMP     AL,'z'
        JA      OPT3A
        SUB     AL,20H
OPT3A:  JCXZ    OPT3
        STOSB
        DEC     CX
        JMP     OPT3
OPT4:   DEC     SI
        JMP     OPT1
USAGE:  MOV     DX,OFFSET S_USAGE
        CALL    PUTS
        MOV     AX,4C01H
        INT     21H

OPTEND: MOV     AX,OFFSET ENDPROG+15
        MOV     CL,4
        SHR     AX,CL
        MOV     BX,CS
        ADD     AX,BX
        MOV     [WORKSEG],AX
        ADD     AX,200H
        MOV     [NEXTSEG],AX
        CMP     [OPTSYS],0
        JE      ASK
        MOV     AH,19H          ;Current drive is the source.
        INT     21H
        CMP     AL,[DRV]
        JNE     LOADIT
        MOV     DX,OFFSET S_CUR
        CALL    PUTS
        MOV     AX,4C01H
        INT     21H
LOADIT: ADD     AL,'A'
        MOV     CX,NSYS
        CALL    LOADSYS
        JNC     ASK
        CALL    PUTS
        MOV     AX,4C01H
        INT     21H

ASK:    MOV     DX,OFFSET S_INS1
        CALL    PUTS
        MOV     DL,[DRV]
        ADD     DL,'A'
        MOV     AH,02H
        INT     21H
        MOV     DX,OFFSET S_INS2
        CALL    PUTS
        CALL    WAITENT
        CALL    SETMODE

; Physical format.
        XOR     BX,BX
TRK1:   PUSH    BX
        MOV     DX,OFFSET S_TRK
        CALL    PUTS
        MOV     AX,BX
        XOR     DX,DX
        CALL    PUTDEC
        POP     BX
        MOV     AL,BL
        CALL    FMTTRK
        JNC     @F
        JMP     FMTERR
@@:
        INC     BX
        CMP     BX,NTRACKS
        JB      TRK1
        MOV     DX,OFFSET S_DONE
        CALL    PUTS

; Boot sector.
        MOV     ES,[WORKSEG]
        MOV     AL,1
        CALL    PUTBOOT
        MOV     AH,2AH          ;Serial number from the date and time.
        INT     21H
        PUSH    CX
        PUSH    DX
        MOV     AH,2CH
        INT     21H
        POP     AX
        ADD     AX,CX
        MOV     ES:[39],AX
        POP     AX
        ADD     AX,DX
        MOV     ES:[41],AX
        CMP     [HASLBL],0
        JE      BOOT1
        MOV     SI,OFFSET LBLNAME
        MOV     DI,43
        MOV     CX,11
        REP     MOVSB
BOOT1:  XOR     AX,AX
        XOR     BX,BX
        CALL    WRSEC
        JNC     @F
        JMP     FMTERR
@@:

; FATs and root directory: clear the buffer, then write each sector.
        CALL    CLRBUF
        MOV     BYTE PTR ES:[0],MEDIA
        MOV     WORD PTR ES:[1],0FFFFH
        MOV     AX,1
        CALL    WRSEC           ;First sector of FAT 1.
        JNC     @F
        JMP     FMTERR
@@:
        MOV     AX,1+FATSEC
        CALL    WRSEC           ;First sector of FAT 2.
        JNC     @F
        JMP     FMTERR
@@:
        CALL    CLRBUF
        MOV     AX,2
        CALL    WRSEC
        JNC     @F
        JMP     FMTERR
@@:
        MOV     AX,2+FATSEC
        CALL    WRSEC
        JNC     @F
        JMP     FMTERR
@@:
        MOV     CX,ROOTSEC-1
        MOV     AX,1+NFAT*FATSEC+1
ROOT1:  CALL    WRSEC
        JNC     @F
        JMP     FMTERR
@@:
        INC     AX
        LOOP    ROOT1
        CMP     [HASLBL],0
        JE      ROOT2
        MOV     SI,OFFSET LBLNAME
        XOR     DI,DI
        MOV     CX,11
        REP     MOVSB
        MOV     BYTE PTR ES:[11],08H
        MOV     AH,2CH
        INT     21H
        MOV     AL,CL           ;Time: hour << 11 | minute << 5 | second / 2.
        XOR     AH,AH
        MOV     CL,5
        SHL     AX,CL
        MOV     BL,CH
        XOR     BH,BH
        MOV     CL,11
        SHL     BX,CL
        OR      AX,BX
        SHR     DH,1
        OR      AL,DH
        MOV     ES:[22],AX
        MOV     AH,2AH          ;Date: (year - 1980) << 9 | month << 5 | day.
        INT     21H
        SUB     CX,1980
        MOV     AX,CX
        MOV     CL,9
        SHL     AX,CL
        MOV     BL,DH
        XOR     BH,BH
        MOV     CL,5
        SHL     BX,CL
        OR      AX,BX
        OR      AL,DL
        MOV     ES:[24],AX
ROOT2:  MOV     AX,1+NFAT*FATSEC
        XOR     BX,BX
        CALL    WRSEC
        JC      FMTERR
        PUSH    CS
        POP     ES
        MOV     AH,0DH          ;Make DOS read the new disk.
        INT     21H

        CMP     [OPTSYS],0
        JE      REPORT
        MOV     AL,[DRV]
        ADD     AL,'A'
        MOV     CX,NSYS
        CALL    SAVESYS
        JNC     SYSOK
        CALL    PUTS
        MOV     AX,4C04H
        INT     21H
SYSOK:  MOV     DX,OFFSET S_SYSOK
        CALL    PUTS

REPORT: CALL    CRLF
        MOV     DL,[DRV]
        INC     DL
        MOV     AH,36H
        INT     21H
        MOV     DI,DX           ;Total clusters.
        MUL     CX              ;AX = bytes per cluster.
        MOV     SI,AX
        MUL     DI              ;Total bytes.
        PUSH    DX
        PUSH    AX
        CALL    PUTDEC
        MOV     DX,OFFSET S_TOT
        CALL    PUTS
        MOV     AX,SI
        MUL     BX              ;Free bytes.
        MOV     DI,AX
        MOV     BP,DX
        CMP     [OPTSYS],0
        JE      REPOR1
        POP     AX
        POP     DX
        PUSH    DX
        PUSH    AX
        SUB     AX,DI
        SBB     DX,BP
        CALL    PUTDEC
        MOV     DX,OFFSET S_SYS
        CALL    PUTS
REPOR1: POP     AX
        POP     DX
        MOV     AX,DI
        MOV     DX,BP
        CALL    PUTDEC
        MOV     DX,OFFSET S_AVL
        CALL    PUTS
        MOV     AX,4C00H
        INT     21H

FMTERR: PUSH    CS
        POP     ES
        MOV     DX,OFFSET S_FAIL
        CMP     AH,05H
        JNE     FMTER1
        MOV     DX,OFFSET S_WP
FMTER1: CALL    PUTS
        MOV     AX,4C04H
        INT     21H

; Clear the 1024-byte sector buffer at ES:0.
CLRBUF: PUSH    AX
        PUSH    CX
        PUSH    DI
        XOR     AX,AX
        XOR     DI,DI
        MOV     CX,SECSIZ/2
        REP     STOSW
        POP     DI
        POP     CX
        POP     AX
        XOR     BX,BX
        RET

        DW      256 DUP (0)
STKTOP  LABEL   WORD

ENDPROG LABEL   BYTE

CODE    ENDS

        END     START
