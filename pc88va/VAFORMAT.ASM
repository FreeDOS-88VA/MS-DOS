        TITLE   FORMAT for MS-DOS on the PC-88VA

; SPDX-License-Identifier: MIT
;
; FORMAT A:|B: [/S] [/V:label]
; FORMAT d:|/H0|/H1 [/V:label]  (SASI, NEC VA FAT12)
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

S_USAGE DB      'Usage: FORMAT A:|B: [/S] [/V:label]',13,10
        DB      '       FORMAT d:|/H0|/H1 [/V:label] (SASI)',13,10,'$'
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
        MOV     SI,81H          ;DISKCOPY's GETDRV only accepts A:/B:.
FMTSKIP:LODSB
        CMP     AL,' '
        JE      FMTSKIP
        CMP     AL,9
        JE      FMTSKIP
        CMP     AL,'/'
        JE      FMTRAW
        AND     AL,0DFH
        SUB     AL,'A'
        CMP     AL,25
        JA      USAGE
        CMP     BYTE PTR [SI],':'
        JNE     USAGE
        INC     SI
        MOV     [DRV],AL
        JMP     SHORT OPT1
FMTRAW: LODSB
        AND     AL,0DFH
        CMP     AL,'H'
        JNE     USAGE
        LODSB
        SUB     AL,'0'
        CMP     AL,1
        JA      USAGE
        MOV     [FTARGET],AL
        MOV     [DRV],0FFH
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
        CMP     [DRV],1
        JBE     @F
        JMP     SASIFORM
@@:     CMP     [OPTSYS],0
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
        CALL    ROOTLABEL
ROOT2:  MOV     AX,1+NFAT*FATSEC
        XOR     BX,BX
        CALL    WRSEC
        JNC     @F
        JMP     FMTERR
@@:     PUSH    CS
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
        JMP     SHORT REPORT

; Write one standard FAT volume-label entry at ES:0.
ROOTLABEL:
        XOR     AX,AX
        XOR     DI,DI
        MOV     CX,16
        REP     STOSW
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
        RET

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

; SASI layout (602HDD section 6.2.3; D2 NEC BPB table). All metadata is
; below physical block 420. The first FAT signature is written last.
FTARGET DB      0
FTYPE   DB      0
FBLOCK  DW      0
FFAT2   DW      0
FROOT   DW      0
FEND    DW      0
FIO     DW      0
HFLAGS  DW      0245H          ;ROM call flags as in the resident driver.
FANSWER DB      8,0,8 DUP (0)
FFATS   DB      1,2,4,4         ;1024-byte sectors per FAT.
FROOTS  DB      19,31,47,96     ;32 root entries per sector.
S_HSYS  DB      '/S is not supported for SASI disks.',13,10,'$'
S_HBAD  DB      'No supported SASI disk for this selection.',13,10,'$'
S_HMNT  DB      'Target is already mounted. Use its DOS drive letter.',13,10,'$'
S_HCUR  DB      'Cannot format the current or boot drive.',13,10,'$'
S_HWARN DB      'ALL DATA ON FIXED DISK $'
S_HTARG DB      ' (SASI target $'
S_HWRAW DB      'SASI target $'
S_HWEND DB      ' WILL BE LOST',13,10,'Type Y and press Enter to continue: $'
S_HSTOP DB      'Format cancelled.',13,10,'$'
S_HCON  DB      'SASI FORMAT requires console input.',13,10,'$'
S_HMEM  DB      'Not enough memory for the SASI format buffer.',13,10,'$'
S_HFAT  DB      'Writing FATs...',13,10,'$'
S_HROOT DB      'Writing root directory...',13,10,'$'
S_HDONE DB      'Format complete. Reboot before accessing the disk.',13,10,'$'
S_HFAIL DB      'SASI format failed. Reboot before accessing the disk.',13,10,'$'

SASIFORM:
        CMP     [OPTSYS],0
        JE      HBUFFER
        MOV     DX,OFFSET S_HSYS
        JMP     HREFUSE
HBUFFER:MOV     AX,[WORKSEG]    ;Align physical DMA buffer to 1024 bytes.
        ADD     AX,63
        AND     AX,0FFC0H
        MOV     [WORKSEG],AX
        ADD     AX,64
        CMP     AX,DS:[2]       ;End of the DOS allocation (PSP:0002).
        JBE     HSELECT
        MOV     DX,OFFSET S_HMEM
        JMP     HREFUSE
HSELECT:CMP     [DRV],0FFH
        JE      HRAW
        MOV     BL,[DRV]
        INC     BL
        CALL    HIDENT
        JC      HBAD
        MOV     [FTARGET],AL
        MOV     AH,19H
        INT     21H
        INC     AL
        CALL    HPROTECT
        MOV     AX,3305H        ;DOS boot drive (one-based).
        INT     21H
        CMP     DL,1
        JB      HBAD
        CMP     DL,26
        JA      HBAD
        MOV     AL,DL
        CALL    HPROTECT
        JMP     SHORT HSENSE
HRAW:   MOV     BL,1            ;VA floppy driver knows the boot-time map.
        MOV     CL,0F0H
        CALL    HIOCTL
        JC      HBAD
        CMP     BYTE PTR [FIO+1],0D3H
        JNE     HBAD
        MOV     AL,1
        MOV     CL,[FTARGET]
        SHL     AL,CL
        TEST    BYTE PTR [FIO],AL
        JZ      HSENSE
        MOV     DX,OFFSET S_HMNT
        JMP     HREFUSE
HBAD:   MOV     DX,OFFSET S_HBAD
HREFUSE:CALL    PUTS
        MOV     AX,4C01H
        INT     21H

HSENSE: CALL    HPROBE
        JC      HBAD
        MOV     [FTYPE],AL
        MOV     AX,4400H        ;Don't take destructive confirmation from a file.
        XOR     BX,BX
        INT     21H
        JC      HNOCON
        AND     DL,81H          ;Character device with console input bit.
        CMP     DL,81H
        JE      HWARN
HNOCON: MOV     DX,OFFSET S_HCON
        JMP     HREFUSE
HWARN:  MOV     DX,OFFSET S_HWARN
        CALL    PUTS
        MOV     DX,OFFSET S_HWRAW
        CMP     [DRV],0FFH
        JE      HWRAW
        MOV     DL,[DRV]
        ADD     DL,'A'
        CALL    HCHAR
        MOV     DL,':'
        CALL    HCHAR
        MOV     DX,OFFSET S_HTARG
HWRAW:  CALL    PUTS
        MOV     DL,[FTARGET]
        ADD     DL,'0'
        CALL    HCHAR
        CMP     [DRV],0FFH
        JE      HWEND
        MOV     DL,')'
        CALL    HCHAR
HWEND:  MOV     DX,OFFSET S_HWEND
        CALL    PUTS
        MOV     DX,OFFSET FANSWER
        MOV     AX,0C0AH        ;Discard type-ahead before asking DOS for a line.
        INT     21H
        CALL    CRLF
        CMP     [FANSWER+1],1
        JNE     HCANCEL
        MOV     AL,[FANSWER+2]
        AND     AL,0DFH
        CMP     AL,'Y'
        JE      HCONFIRM
HCANCEL:MOV     DX,OFFSET S_HSTOP
        JMP     HREFUSE
HCONFIRM:
        CALL    HPROBE          ;Recheck BIOS type before committing.
        JC      HREFJ
        CMP     AL,[FTYPE]
        JNE     HREFJ
        CMP     [DRV],0FFH
        JE      HFORMAT
        MOV     AH,0DH          ;Flush DOS buffers before taking the unit offline.
        INT     21H
        MOV     BL,[DRV]
        INC     BL
        MOV     AL,[FTARGET]
        MOV     AH,0D4H
        MOV     [FIO],AX
        MOV     CL,0F1H
        CALL    HIOCTL
        JNC     HFORMAT
HREFJ:  JMP     HBAD

HFORMAT:MOV     ES,[WORKSEG]
        XOR     BX,BX
        MOV     BL,[FTYPE]
        XOR     AX,AX
        MOV     AL,FFATS[BX]
        SHL     AX,1
        SHL     AX,1
        ADD     AX,4
        MOV     [FFAT2],AX
        SHL     AX,1
        SUB     AX,4
        MOV     [FROOT],AX
        XOR     DX,DX
        MOV     DL,FROOTS[BX]
        SHL     DX,1
        SHL     DX,1
        ADD     DX,AX
        MOV     [FEND],DX

        MOV     DX,OFFSET S_HFAT
        CALL    PUTS
        CALL    CLRBUF
        MOV     [FBLOCK],8      ;Skip first logical sector of FAT 1.
HFAT:   MOV     AX,[FBLOCK]
        CMP     AX,[FROOT]
        JE      HROOT
        CMP     AX,[FFAT2]
        JE      HFATNEXT
        CALL    HWRITE
        JC      HFAIL
HFATNEXT:
        ADD     [FBLOCK],4
        JMP     HFAT
HROOT:  MOV     DX,OFFSET S_HROOT
        CALL    PUTS
        XOR     DI,DI
        MOV     CX,32
HENTRY: MOV     AL,0
        STOSB
        MOV     AL,0E5H         ;HDFORM: 00h then 31 E5h bytes per entry.
        PUSH    CX
        MOV     CX,31
        REP     STOSB
        POP     CX
        LOOP    HENTRY
HROOT1: CALL    HWRITE
        JC      HFAIL
        ADD     [FBLOCK],4
        MOV     AX,[FBLOCK]
        CMP     AX,[FEND]
        JB      HROOT1
        CMP     [HASLBL],0
        JE      HSIGN
        CALL    ROOTLABEL
        MOV     AX,[FROOT]
        MOV     [FBLOCK],AX
        CALL    HWRITE
        JC      HFAIL
HSIGN:  CALL    CLRBUF
        MOV     AL,[FTYPE]
        ADD     AL,0D0H
        MOV     ES:[0],AL
        MOV     WORD PTR ES:[1],0FFFFH
        MOV     AX,[FFAT2]
        MOV     [FBLOCK],AX
        CALL    HWRITE
        JC      HFAIL
        MOV     [FBLOCK],4
        CALL    HWRITE
        JC      HFAIL
        MOV     DX,OFFSET S_HDONE
        CALL    PUTS
        MOV     AX,4C00H
        INT     21H
HFAIL:  MOV     DX,OFFSET S_HFAIL
        CALL    PUTS
        MOV     AX,4C04H
        INT     21H

HCHAR:  MOV     AH,02H
        INT     21H
        RET

; AL = one-based current or boot letter; also catch an alias of the target.
HPROTECT:
        MOV     BL,AL
        DEC     AL
        CMP     AL,[DRV]
        JE      HCUR
        CALL    HIDENT
        JC      HOTHER
        CMP     AL,[FTARGET]
        JNE     HOTHER
HCUR:   MOV     DX,OFFSET S_HCUR
        JMP     HREFUSE
HOTHER: RET

HIDENT: MOV     [FIO],0         ;Require the driver to fill this packet.
        MOV     CL,0F0H
        CALL    HIOCTL
        JC      HIDA
        MOV     AX,[FIO]
        CMP     AH,0D4H
        JNE     HIDFAIL
        CMP     AL,2
        CMC
HIDA:   RET
HIDFAIL:STC
        RET
HIOCTL: MOV     CH,08H
        XOR     BH,BH
        MOV     DX,OFFSET FIO
        MOV     AX,440DH
        INT     21H
        RET

HPROBE: MOV     BH,[FTARGET]
        MOV     AX,0900H
        CALL    HROM
        JC      HIDA
        CMP     AL,4            ;Includes the ROM's AL=FFh (no target).
        CMC
        RET
HWRITE: XOR     DX,DX
        XOR     BP,BP
        MOV     CX,[FBLOCK]
        MOV     BH,[FTARGET]
        OR      BH,80H          ;Relative block addressing.
        MOV     AX,8204H        ;WRITE DATA, no retries, four blocks.
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

        DW      256 DUP (0)
STKTOP  LABEL   WORD

ENDPROG LABEL   BYTE

CODE    ENDS

        END     START
