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
        MOV     [RUN0],AX       ;Collect a run of consecutive clusters.
        MOV     [RUNN],0
LOADF7: INC     [RUNN]
        CALL    NEXTCL
        MOV     DX,[RUN0]
        ADD     DX,[RUNN]
        CMP     AX,DX
        JE      LOADF7
        PUSH    AX              ;First cluster of the next run.
        MOV     AX,[RUN0]
        SUB     AX,2
        MOV     CL,[SPC]
        XOR     CH,CH
        MUL     CX
        ADD     AX,[DATALBA]
        PUSH    AX
        MOV     AX,[RUNN]
        MUL     CX
        MOV     CX,AX
        POP     AX
        PUSH    ES
        MOV     ES,[LOADSEG]
        XOR     DI,DI
        CALL    READN
        MOV     [LOADSEG],AX
        POP     ES
        POP     AX
        JMP     LOADF3
LOADF5: RET

; AX = cluster; returns AX = next cluster from the FAT12 buffer.
NEXTCL: MOV     BX,AX
        SHR     BX,1
        ADD     BX,AX
        MOV     DX,[FATBUF+BX]
        TEST    AL,1
        JZ      NEXTC1
        MOV     CL,4
        SHR     DX,CL
NEXTC1: AND     DX,0FFFH
        MOV     AX,DX
        RET

; Read CX sectors from LBA AX to ES:DI, the sectors of one track in one
; ROM call.  ES is preserved; AX returns the segment that follows the data
; (for DI = 0).
READN:  PUSH    ES
        JMP     SHORT READN0
READN9: MOV     AX,ES
        POP     ES
        RET
READN0: OR      CX,CX
        JZ      READN9
        MOV     [LBA],AX
        MOV     [CNT],CX
        MOV     [TRIES],3
READN2: MOV     AX,[LBA]
        XOR     DX,DX
        DIV     [SPT]
        MOV     BX,[SPT]
        SUB     BX,DX           ;Sectors left on this track.
        CMP     BX,[CNT]
        JBE     READN4
        MOV     BX,[CNT]
READN4: MOV     [NREAD],BL
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
        MOV     AH,81H          ;Read AL sectors to ES:BP.
        MOV     AL,[NREAD]
        PUSH    DS
        PUSH    ES
        INT     80H
        POP     ES
        POP     DS
        JNC     READN3
        DEC     [TRIES]
        JNZ     READN2
        JMP     FAIL
READN3: MOV     AL,[NREAD]
        XOR     AH,AH
        ADD     [LBA],AX
        SUB     [CNT],AX
        MOV     CL,6            ;1024-byte sectors = 64 paragraphs.
        SHL     AX,CL
        MOV     DX,ES
        ADD     DX,AX
        MOV     ES,DX
        MOV     AX,[LBA]
        MOV     CX,[CNT]
        JMP     READN0

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
DOSSEGV DW      0
RUN0    DW      0
RUNN    DW      0
LBA     DW      0
CNT     DW      0
NREAD   DB      0
TRIES   DB      0
SECTOR  DB      0

        IF      ($-BOOT) GT 1022
        .ERR
        ENDIF
        ORG     1022
        DB      55H,0AAH

CODE    ENDS

        END
