; SPDX-License-Identifier: MIT
;
; Shared routines of the PC-88VA FORMAT and SYS commands.  They use only
; MS-DOS 2.0 calls and the ROM floppy BIOS (INT 80h), so the same programs
; run on MS-DOS 2.0 and 4.0.  Included in a .COM program with DS = CS.
; VABOOT.INC is generated from VABOOT.ASM by the build and defines
; BOOTCODE, the 1024-byte boot sector.

FDMODE  EQU     23H             ;INT 80h disk mode: 2HD, 1024-byte sectors.
SECLEN  EQU     3               ;Sector length code for 1024 bytes.
SECSIZ  EQU     1024
SECTRK  EQU     8
NTRACKS EQU     160             ;80 cylinders, 2 heads.
NSECT   EQU     1280
NFAT    EQU     2
FATSEC  EQU     2
ROOTSEC EQU     6
ROOTENT EQU     192
MEDIA   EQU     0FEH

DRV     DB      0               ;Target drive, 0 = A:.
TRIES   DB      0

; Print the '$'-terminated string at DS:DX.
PUTS:   MOV     AH,09H
        INT     21H
        RET

CRLF:   MOV     DX,OFFSET S_CRLF
        JMP     PUTS
S_CRLF  DB      13,10,'$'

; Print DX:AX as an unsigned decimal number.
PUTDEC: PUSH    BX
        PUSH    CX
        PUSH    SI
        MOV     SI,OFFSET NUMEND
        MOV     BX,10
PUTDE1: MOV     CX,AX           ;DX:AX / 10, remainder in CX.
        MOV     AX,DX
        XOR     DX,DX
        DIV     BX
        XCHG    AX,CX
        DIV     BX
        XCHG    CX,DX           ;DX:AX = quotient, CX = remainder.
        ADD     CL,'0'
        DEC     SI
        MOV     [SI],CL
        MOV     CX,AX
        OR      CX,DX
        JNZ     PUTDE1
        MOV     DX,SI
        CALL    PUTS
        POP     SI
        POP     CX
        POP     BX
        RET
NUMBUF  DB      10 DUP (' ')
NUMEND  DB      '$'

; Read a line from the keyboard until ENTER, discarding typeahead first.
WAITENT:
        MOV     AX,0C08H
        INT     21H
WAITEN1:
        CMP     AL,13
        JE      WAITEN2
        MOV     AH,08H
        INT     21H
        JMP     WAITEN1
WAITEN2:
        JMP     CRLF

; Parse "d:" at the command tail.  On return CF=1 if absent or not A:/B:,
; else [DRV] is set and SI points after the colon.
GETDRV: MOV     SI,81H
GETDR1: LODSB
        CMP     AL,' '
        JE      GETDR1
        CMP     AL,9
        JE      GETDR1
        AND     AL,0DFH
        SUB     AL,'A'
        CMP     AL,1
        JA      GETDR9
        CMP     BYTE PTR [SI],':'
        JNE     GETDR9
        INC     SI
        MOV     [DRV],AL
        CLC
        RET
GETDR9: STC
        RET

; Select the 2HD disk mode for [DRV].
SETMODE:
        PUSH    DS
        PUSH    ES
        MOV     AH,0AH
        MOV     AL,FDMODE
        MOV     CH,[DRV]
        INT     80H
        POP     ES
        POP     DS
        RET

; Read (AH=81h) or write (AH=82h) one sector: AX = LBA, ES:BX = buffer.
; CF=1 and AH = ROM status on error.
RDSEC:  MOV     DL,81H
        JMP     SHORT XFER
WRSEC:  MOV     DL,82H
XFER:   PUSH    BX
        PUSH    CX
        PUSH    DX
        PUSH    BP
        MOV     BP,BX
        MOV     [TRIES],3
        MOV     [XOP],DL
XFER1:  PUSH    AX
        XOR     DX,DX
        MOV     CX,SECTRK
        DIV     CX
        INC     DL
        MOV     DH,DL           ;Sector.
        MOV     CL,AL           ;Track = cylinder * 2 + head.
        MOV     BH,AL
        SHR     BH,1            ;Cylinder.
        MOV     BL,AL
        AND     BL,1            ;Head.
        MOV     CH,[DRV]
        MOV     DL,SECLEN
        MOV     AH,[XOP]
        MOV     AL,1
        PUSH    DS
        PUSH    ES
        INT     80H
        POP     ES
        POP     DS
        JNC     XFER2
        MOV     [XSTAT],AH
        POP     AX
        DEC     [TRIES]
        JNZ     XFER1
        MOV     AH,[XSTAT]
        STC
        JMP     SHORT XFER3
XFER2:  POP     AX
        CLC
XFER3:  POP     BP
        POP     DX
        POP     CX
        POP     BX
        RET
XOP     DB      0
XSTAT   DB      0

; Format track AL (cylinder * 2 + head) of [DRV], filling with E5h.
; CF=1 and AH = ROM status on error.
FMTTRK: PUSH    CX
        PUSH    DX
        MOV     CL,AL
        MOV     CH,[DRV]
        MOV     DL,SECLEN
        MOV     AX,03E5H
        PUSH    DS
        PUSH    ES
        INT     80H
        POP     ES
        POP     DS
        POP     DX
        POP     CX
        RET

; Copy the boot code into the sector at ES:0, keeping bytes 3-61 (the BPB)
; when AL = 0, or taking the default BPB of BOOTCODE when AL = 1.
PUTBOOT:
        PUSH    CX
        PUSH    SI
        PUSH    DI
        MOV     SI,OFFSET BOOTCODE
        XOR     DI,DI
        OR      AL,AL
        JNZ     PUTBO1
        MOV     CX,3
        REP     MOVSB
        ADD     SI,59
        ADD     DI,59
        MOV     CX,SECSIZ-62
        REP     MOVSB
        JMP     SHORT PUTBO2
PUTBO1: MOV     CX,SECSIZ
        REP     MOVSB
PUTBO2: POP     DI
        POP     SI
        POP     CX
        RET

; System files: name offsets, attributes, sizes and load segments.
NSYS    EQU     3
SYSNAME DW      N_IO,N_DOS,N_CMD
SYSATTR DW      07H,07H,0
SYSSIZE DW      0,0,0
SYSSEG  DW      0,0,0
N_IO    DB      'X:\IO.SYS',0
N_DOS   DB      'X:\MSDOS.SYS',0
N_CMD   DB      'X:\COMMAND.COM',0
NEXTSEG DW      0               ;Next free paragraph.

; Read the first CX system files from drive letter AL into memory from
; [NEXTSEG].  CF=1 with DX = message on error.
LOADSYS:
        MOV     [SYSLTR],AL
        MOV     [SYSCNT],CX
        MOV     [SYSIDX],0
LOADS1: MOV     BX,[SYSIDX]
        MOV     SI,[SYSNAME+BX]
        MOV     AL,[SYSLTR]
        MOV     [SI],AL
        MOV     DX,SI
        MOV     AX,3D00H
        INT     21H
        MOV     DX,OFFSET S_NOSYS
        JC      LOADS9
        MOV     [HANDLE],AX
        MOV     AX,[NEXTSEG]
        MOV     [SYSSEG+BX],AX
        ADD     AX,1000H        ;Room for up to 64 KB below the memory top?
        MOV     DX,OFFSET S_NOMEM
        CMP     AX,DS:[2]
        JA      LOADS8
        MOV     BX,[SYSIDX]
        MOV     CX,0FFF0H
        PUSH    DS
        MOV     AX,[SYSSEG+BX]
        MOV     BX,[HANDLE]
        MOV     DS,AX
        XOR     DX,DX
        MOV     AH,3FH
        INT     21H
        POP     DS
        MOV     DX,OFFSET S_NOSYS
        JC      LOADS8
        MOV     BX,[SYSIDX]
        MOV     [SYSSIZE+BX],AX
        ADD     AX,15
        MOV     CL,4
        SHR     AX,CL
        ADD     [NEXTSEG],AX
        MOV     BX,[HANDLE]
        MOV     AH,3EH
        INT     21H
        ADD     [SYSIDX],2
        DEC     [SYSCNT]
        JNZ     LOADS1
        CLC
        RET
LOADS8: PUSH    DX
        MOV     BX,[HANDLE]
        MOV     AH,3EH
        INT     21H
        POP     DX
LOADS9: STC
        RET

; Write the first CX loaded system files to drive letter AL.  Existing
; copies are made writable and deleted first.  CF=1 with DX = message.
SAVESYS:
        MOV     [SYSLTR],AL
        MOV     [SYSCNT],CX
        MOV     [SYSIDX],0
SAVES1: MOV     BX,[SYSIDX]
        MOV     SI,[SYSNAME+BX]
        MOV     AL,[SYSLTR]
        MOV     [SI],AL
        MOV     DX,SI
        MOV     AX,4301H        ;Clear the attributes of an old copy.
        XOR     CX,CX
        INT     21H
        MOV     DX,SI
        MOV     AH,41H
        INT     21H
        MOV     DX,SI
        MOV     BX,[SYSIDX]
        MOV     CX,[SYSATTR+BX]
        MOV     AH,3CH
        INT     21H
        MOV     DX,OFFSET S_NOROOM
        JC      LOADS9
        MOV     [HANDLE],AX
        MOV     CX,[SYSSIZE+BX]
        PUSH    DS
        MOV     AX,[SYSSEG+BX]
        MOV     BX,[HANDLE]
        MOV     DS,AX
        XOR     DX,DX
        MOV     AH,40H
        INT     21H
        POP     DS
        MOV     DX,OFFSET S_NOROOM
        JC      LOADS8
        MOV     BX,[SYSIDX]
        CMP     AX,[SYSSIZE+BX]
        JNE     LOADS8
        MOV     BX,[HANDLE]
        MOV     AH,3EH
        INT     21H
        MOV     DX,OFFSET S_NOROOM
        JC      LOADS9
        ADD     [SYSIDX],2
        DEC     [SYSCNT]
        JNZ     SAVES1
        CLC
        RET

SYSLTR  DB      0
SYSCNT  DW      0
SYSIDX  DW      0
HANDLE  DW      0

S_NOSYS DB      'System files not found on the current drive',13,10,'$'
S_NOMEM DB      'Insufficient memory',13,10,'$'
S_NOROOM DB     'Cannot write the system files to the target disk',13,10,'$'
S_SYSOK DB      'System transferred',13,10,'$'

        INCLUDE VABOOT.INC
