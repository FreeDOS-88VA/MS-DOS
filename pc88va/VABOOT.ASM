        TITLE   Boot sector for MS-DOS on the PC-88VA

; SPDX-License-Identifier: MIT
;
; The ROM loads this 1024-byte sector at 3000:0000 and jumps to it.  It
; finds IO.SYS and MSDOS.SYS in the root directory, loads both through the
; FAT to BIOSSEG:0 (MSDOS.SYS right after the last sector of IO.SYS) and
; enters IO.SYS with DX = MSDOS.SYS segment and SS:SP = 3000:1000, a stack
; that IO.SYS and SYSINIT keep using during initialization.  The files may
; lie anywhere on the disk.  FORMAT and SYS write this code and keep the
; BPB of the disk (offsets 3-61); the 55AAh signatures sit at 510 and 1022.

BOOTSEG EQU     3000H
BIOSSEG EQU     1000H
ROOTBUF EQU     1000H           ;Root directory buffer (to 5FFFh).
FATBUF  EQU     6000H           ;FAT buffer (to 0BFFFh).
FDMODE  EQU     23H             ;INT 80h disk mode: 2HD, 1024-byte sectors.
SECLEN  EQU     3               ;Sector length code for 1024 bytes.

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE

        ORG     0

BOOT:   JMP     SHORT START
        NOP
OEM     DB      'MSDOS-VA'
BPS     DW      1024            ;Bytes per sector.
SPC     DB      1               ;Sectors per cluster.
RESSEC  DW      1               ;Reserved sectors.
NFATS   DB      2               ;FATs.
ROOTENT DW      192             ;Root directory entries.
TOTSEC  DW      1280            ;Total sectors.
MEDIA   DB      0FEH            ;Media descriptor.
SPF     DW      2               ;Sectors per FAT.
SPT     DW      8               ;Sectors per track.
HEADS   DW      2               ;Heads.
HIDDEN  DD      0
BIGTOT  DD      0
DRIVE   DB      0
        DB      0
EXTSIG  DB      29H
SERIAL  DD      0
VOLUME  DB      'NO NAME    '
FSTYPE  DB      'FAT12   '

; Working variables (offset 62 onwards is boot code).
START:  CLI
        MOV     AX,CS
        MOV     DS,AX
        MOV     ES,AX
        MOV     SS,AX
        MOV     SP,1000H
        STI
        CLD
        MOV     AH,0AH          ;Select the disk mode of drive A:.
        MOV     AL,FDMODE
        XOR     CH,CH
        INT     80H

; First root directory sector and first data sector.
        MOV     AL,[NFATS]
        CBW
        MUL     [SPF]
        ADD     AX,[RESSEC]
        MOV     [ROOTLBA],AX
        MOV     BX,AX
        MOV     AX,[ROOTENT]
        MOV     CL,5
        SHL     AX,CL           ;Root bytes.
        ADD     AX,[BPS]
        DEC     AX
        XOR     DX,DX
        DIV     [BPS]
        MOV     [ROOTN],AX
        ADD     AX,BX
        MOV     [DATALBA],AX

        MOV     AX,[ROOTLBA]    ;Read the root directory.
        MOV     CX,[ROOTN]
        MOV     DI,ROOTBUF
        CALL    READN
        MOV     AX,[RESSEC]     ;Read the first FAT.
        MOV     CX,[SPF]
        MOV     DI,FATBUF
        CALL    READN

        MOV     AX,BIOSSEG
        MOV     [LOADSEG],AX
        MOV     SI,OFFSET IONAME
        CALL    LOADF
        MOV     AX,[LOADSEG]
        MOV     [DOSSEGV],AX
        MOV     SI,OFFSET DOSNAME
        CALL    LOADF
        MOV     DX,[DOSSEGV]
        DB      0EAH            ;JMP BIOSSEG:0
        DW      0,BIOSSEG

; Find the 11-byte name at DS:SI in the root and load the file at LOADSEG.
LOADF:  MOV     DI,ROOTBUF
        MOV     BX,[ROOTENT]
LOADF1: PUSH    SI
        PUSH    DI
        MOV     CX,11
        REPE    CMPSB
        POP     DI
        POP     SI
        JE      LOADF2
        ADD     DI,32
        DEC     BX
        JNZ     LOADF1
        JMP     FAIL
LOADF2: MOV     AX,[DI+26]      ;First cluster.
LOADF3: CMP     AX,2
        JAE     LOADF6
        JMP     FAIL
LOADF6: CMP     AX,0FF8H
        JAE     LOADF5
        PUSH    AX
        SUB     AX,2
        MOV     CL,[SPC]
        XOR     CH,CH
        MUL     CX
        ADD     AX,[DATALBA]
        PUSH    ES
        MOV     ES,[LOADSEG]
        XOR     DI,DI
        CALL    READN           ;Advances ES:DI past the cluster.
        MOV     AX,DI
        MOV     CL,4
        SHR     AX,CL
        MOV     DX,ES
        ADD     AX,DX
        MOV     [LOADSEG],AX
        POP     ES
        POP     AX
        MOV     BX,AX           ;Next FAT12 entry.
        SHR     BX,1
        ADD     BX,AX
        MOV     DX,[FATBUF+BX]
        TEST    AL,1
        JZ      LOADF4
        MOV     CL,4
        SHR     DX,CL
LOADF4: AND     DX,0FFFH
        MOV     AX,DX
        JMP     LOADF3
LOADF5: RET

; Read CX sectors from LBA AX to ES:DI; DI advances by the bytes read.
READN:  JCXZ    READN9
READN1: PUSH    AX
        PUSH    CX
        MOV     [TRIES],3
READN2: PUSH    AX
        XOR     DX,DX
        DIV     [SPT]
        INC     DL
        MOV     [SECTOR],DL
        XOR     DX,DX
        DIV     [HEADS]         ;AX = cylinder, DX = head.
        MOV     BH,AL
        MOV     BL,DL
        SHL     AL,1
        OR      AL,DL
        MOV     CL,AL           ;Track = cylinder * 2 + head.
        XOR     CH,CH           ;Drive A:.
        MOV     DH,[SECTOR]
        MOV     DL,SECLEN
        MOV     BP,DI
        MOV     AX,8101H        ;Read one sector to ES:BP.
        PUSH    DS
        PUSH    ES
        INT     80H
        POP     ES
        POP     DS
        POP     AX
        JNC     READN3
        DEC     [TRIES]
        JNZ     READN2
        JMP     SHORT FAIL
READN3: POP     CX
        POP     AX
        ADD     DI,[BPS]
        INC     AX
        LOOP    READN1
READN9: RET

FAIL:   PUSH    CS
        POP     DS
        MOV     SI,OFFSET FAILMSG
        MOV     DX,8000H
        MOV     AH,02H
        INT     83H
FAIL1:  CLI
        HLT
        JMP     FAIL1

IONAME  DB      'IO      SYS'
DOSNAME DB      'MSDOS   SYS'

        IF      ($-BOOT) GT 510
        .ERR
        ENDIF
        ORG     510
        DB      55H,0AAH

FAILMSG DB      13,10,'Non-system disk or disk error',13,10,0
ROOTLBA DW      0
ROOTN   DW      0
DATALBA DW      0
LOADSEG DW      0
DOSSEGV  DW      0
TRIES   DB      0
SECTOR  DB      0

        IF      ($-BOOT) GT 1022
        .ERR
        ENDIF
        ORG     1022
        DB      55H,0AAH

CODE    ENDS

        END
