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
HDIDX   DW      0
S_USAGE DB      'Usage: SYS d: [/L | /P | /C | /D n] (switches for SASI only)',13,10,'$'
S_SAME  DB      'Cannot SYS to the current drive',13,10,'$'
S_BAD   DB      'Target disk is not a PC-88VA 2HD MS-DOS disk',13,10,'$'
S_IOERR DB      'Disk error on the target drive',13,10,'$'
S_NEC   DB      'Target is not a mounted NEC-layout SASI volume',13,10,'$'
S_BOOT  DB      'Cannot SYS to the boot drive',13,10,'$'
S_JRDONE DB     'Boot-menu switch recovered; DOS files unchanged.',13,10,'$'
D5BADMSG DB     'Inconsistent or missing SASI boot-menu files; no new IPL installed.',13,10,'$'
D5NOTPC DB      'Expected a complete PC-Engine set and a replaced PC-Engine IPL.',13,10,'$'
D5ROOM  DB      'No free boot-menu entry or root directory slot.',13,10,'$'
D5NEED  DB      'Boot MS-DOS from the menu to park the active set before preparing.',13,10,'$'
D5LABELASK DB   'Label (up to 15 ASCII characters, Enter for PC-Engine n): $'
D5BADLABEL DB   'Label must be printable ASCII.',13,10,'$'
D5PREPDONE DB   'Prepared for another PC-Engine SYS. Use SYS d: /C to cancel.',13,10,'$'
D5CANDONE DB    'Preparation cancelled.',13,10,'$'
D5DELDONE DB    'Entry unregistered. Parked system and startup files were retained.',13,10,'$'
D5PAIRHDR DB    'Startup names (if present):',13,10,'$'
D5PAIRDOS DB    '0 MS-DOS',13,10,'$'
D5PAIRREAL DB   '  CONFIG.SYS / AUTOEXEC.BAT',13,10,'$'
D5PAIRPARK DB   '  VACFG0.SYS / VAEXEC0.BAT',13,10,'$'
D5NONE  DB      'No PC-Engine entries.',13,10,'$'
D5WAIT  DB      'Boot-menu update pending.',13,10,'$'
RFMSG   DB      'Cannot safely refresh the SASI boot files.',13,10,'$'
TXROOM  DB      'Free a root directory entry in either DOS kernel block and retry SYS.',13,10,'$'
TXBROKEN DB     'Cannot recover the SASI boot-file transaction.',13,10,'$'

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
        DEC     SI
        CALL    D5ARGS
        JNC     SYSMAIN
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
        CMP     [D5OP],0
        JNE     LOADIT
        CMP     [DRV],1
        JA      LOADIT          ;SASI may need journal recovery first.
        CMP     AL,[DRV]
        JNE     LOADIT
        MOV     DX,OFFSET S_SAME
        JMP     ERROR
LOADIT: ADD     AL,'A'
        MOV     [SOURCE],AL
        CMP     [DRV],1
        JA      HDSYS
        CMP     [D5OP],0
        JNE     USAGE
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
        JMP     SHORT HDALLOC
NOTNEC: MOV     DX,OFFSET S_NEC
        JMP     ERROR
HDALLOC:MOV     AX,[WORKSEG]
        ADD     AX,63
        AND     AX,0FFC0H
        MOV     [WORKSEG],AX
        ADD     AX,64
        MOV     [BMBUFSEG],AX
        ADD     AX,64
        MOV     [BMSTSEG],AX
        ADD     AX,256
        MOV     [RFSEG],AX
        ADD     AX,64
        ; The redo buffer and LOADSYS staging share the same space.
        ; Never plan a transaction while the source bytes are needed.
        MOV     [TXSEG],AX
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
        JNC     HDFATID
        JMP     HDSYSIO
HDFATID:MOV     AL,[FTYPE]
        ADD     AL,0D0H
        MOV     AH,0FFH
        CMP     WORD PTR ES:[0],AX
        JNE     NOTNEC
        CMP     BYTE PTR ES:[2],0FFH
        JNE     NOTNEC
        CALL    HIPLCHECK
        JNC     HDRESUME
        JMP     HDSYSIO
HDRESUME:CALL   TXRESUME
        JC      HDEARLYERR
HDTYPE: CALL    D5TYPE
        MOV     [D5IPL],AL
        CMP     [D5OP],0
        JE      HDNORMAL
        CALL    D5COMMAND
        JC      HDEARLYERR
        MOV     AX,4C00H
        INT     21H
HDNORMAL:MOV    AX,3305H
        INT     21H
        DEC     DL
        CMP     DL,[DRV]
        JNE     HDSELSRC
        JMP     HDLOCAL
HDSELSRC:MOV    AL,[SOURCE]
        SUB     AL,'A'
        CMP     AL,[DRV]
        JNE     HDCHKSRC
        JMP     HDSOURCED
HDCHKSRC:CMP     [D5IPL],1
        JNE     HDPLAN
        CALL    HCONFSTDIN
        JNC     HDCONFIRMED
HDEARLYERR:JMP  HDSYSERR
HDCONFIRMED:MOV DX,OFFSET S_HDIPL
        CALL    PUTS
        MOV     DX,OFFSET S_HDPROMPT
        CALL    PUTS
        CALL    HYES
        MOV     DX,OFFSET S_HDCANCEL
        JC      HDEARLYERR
HDPLAN: CALL    D5PLAN
        JC      HDEARLYERR
        CMP     [D5IPL],2
        JB      HDCOPY
        CALL    RFRECOVER
        JC      HDEARLYERR
        CALL    RFSLOTS
        JC      HDEARLYERR
HDCOPY: CMP     [D5IPL],2
        JB      HDINSTALL
        CALL    RFNEW
        JC      HDEARLYERR
        JMP     SHORT HDPUBLISH
HDINSTALL:
        ; Check all source files before writing the capture marker.
        MOV     [HDIDX],0
HDTEST: MOV     BX,[HDIDX]
        CALL    HDLOADONE
        JC      HDEARLYERR
        ADD     [HDIDX],2
        CMP     [HDIDX],NSYS*2
        JB      HDTEST
        CALL    D5CAPTURE
        JC      HDEARLYERR
        MOV     [HDIDX],0
HDSAVE: MOV     BX,[HDIDX]
        CALL    HDLOADONE
        JC      HDEARLYERR
        PUSH    CS
        POP     ES
        MOV     AX,[HDIDX]
        MOV     [SYSIDX],AX
        MOV     AL,[DRV]
        ADD     AL,'A'
        MOV     [SYSLTR],AL
        MOV     [SYSCNT],1
        CALL    SAVES1
        JC      HDSYSERR
        ADD     [HDIDX],2
        CMP     [HDIDX],NSYS*2
        JB      HDSAVE
        MOV     AH,0DH
        INT     21H
HDPUBLISH:CALL  D5COMMIT
        JC      HDSYSERR
        CMP     [D5IPL],2
        JAE     HDDONE
        CALL    RFSLOTS
        JC      HDSYSERR
HDDONE: CALL    HNOTE
        JMP     SUCCESS
; Load only source file BX (an even index). The one staging window is
; available for the next file as soon as its current data is written.
HDLOADONE:
        MOV     AX,[TXSEG]
        MOV     [NEXTSEG],AX
        MOV     [SYSIDX],BX
        MOV     [SYSCNT],1
        MOV     AL,[SOURCE]
        MOV     [SYSLTR],AL
        JMP     LOADS1
HDLOCAL:MOV     DX,OFFSET S_BOOT
        JMP     SHORT HDJRONLY
HDSOURCED:MOV   DX,OFFSET S_SAME
HDJRONLY:CMP    [D5IPL],3
        JNE     HDSYSERR
        PUSH    DX
        CALL    D5SETUP
        POP     BX
        JC      HDSYSERR
        CMP     [D5REPLAYED],0
        JNE     HDJRDONE
        MOV     DX,BX
        JMP     SHORT HDSYSERR
HDJRDONE:MOV    DX,OFFSET S_JRDONE
        CALL    PUTS
        MOV     AX,4C00H
        INT     21H
HDSYSIO:MOV     DX,OFFSET S_IOERR
HDSYSERR:JMP    ERROR

MENUDOS EQU     1
SYSREDO EQU     1
        INCLUDE VAMENUCO.INC
        INCLUDE VAMENUIN.INC
        INCLUDE VASYSJR.INC
        INCLUDE VASYSMOV.INC
        INCLUDE VASYSTX.INC
        DW      256 DUP (0)
STKTOP  LABEL   WORD
ENDPROG LABEL   BYTE
CODE    ENDS
        END     START
