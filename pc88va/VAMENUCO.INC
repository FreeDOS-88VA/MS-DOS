; SPDX-License-Identifier: MIT
; Shared boot-menu filesystem and transaction routines. When included
; by SYS, omit the standalone boot entry point and BIOS user interface.
        INCLUDE VAMENUST.INC

        IFNDEF  MENUDOS
; Far call from VAHDBOOT: AX = state LBA, BX = root LBA, CX = data LBA.
; ES/DS are scratch; the caller restores DS if we return to DOS.
MAIN:   PUSH    CS
        POP     DS
        MOV     [STATE],AX
        MOV     [ROOT],BX
        MOV     [DATA0],CX
        MOV     ES,[BMSTSEG]
        CALL    VALIDATE
        JNC     VALID
BADMENU:MOV     SI,OFFSET BADMSG
        JMP     SHORT DOSMSG
VALID:  CMP     BYTE PTR ES:[ST_PHASE],2
        JNE     UNPREP
        MOV     SI,OFFSET PREPMSG
        JMP     SHORT DOSMSG
UNPREP: CMP     BYTE PTR ES:[ST_PHASE],0
        JE      READY
        MOV     SI,OFFSET PENDMSG
DOSMSG: CALL    PRINT
        RETF
READY:  CALL    CHECKFILES
        JC      BADMENU
        CMP     [COUNT],0
        JE      JUSTDOS
        CALL    CHOOSE
        CALL    SWITCH
        JC      BADMENU
        CMP     [CHOICE],DOSID
        JNE     CHAINIPL
JUSTDOS:RETF

; The old IPL remains unchanged in memory until the transaction commits.
CHAINIPL:
        MOV     BL,[CHOICE]
        CALL    IPLPTR
        MOV     DS,AX
        MOV     AX,3000H
        MOV     ES,AX
        XOR     DI,DI
        MOV     CX,512
        REP     MOVSW
        CLI
        MOV     SS,AX
        MOV     SP,0FFFAH
        MOV     DS,AX
        XOR     BX,BX
        XOR     CX,CX
        XOR     DX,DX
        MOV     AX,2
        STI
        DB      0EAH
        DW      0,3000H
        ENDIF

; DS=CS, ES=STATESEG. Check the metadata before using any of its fields.
VALIDATE:
        MOV     [COUNT],0
        CMP     WORD PTR ES:[ST_SIG1],4256H
        JNE     VREJECT
        CMP     WORD PTR ES:[ST_SIG2],314DH
        JE      VCRC
VREJECT:STC
        RET
VCRC:
        PUSH    DS
        PUSH    ES
        POP     DS
        XOR     SI,SI
        MOV     CX,ST_CSUM
        CALL    CRC16
        POP     DS
        CMP     DX,ES:[ST_CSUM]
        JNE     INVALID
        CMP     BYTE PTR ES:[ST_PHASE],3
        JA      INVALID
        MOV     BL,ES:[ST_OWNER]
        CALL    IDOK
        JC      INVALID
        MOV     BL,ES:[ST_LAST]
        CALL    IDOK
        JC      INVALID
        MOV     BL,1
VLOOP:  CALL    ENTRY
        CMP     BYTE PTR ES:[DI+EN_LABEL],0
        JE      VNEXT
        INC     [COUNT]
        MOV     CX,16
        MOV     SI,DI
VLABEL: MOV     AL,ES:[SI]
        OR      AL,AL
        JZ      VLEND
        CMP     AL,20H
        JB      INVALID
        CMP     AL,7EH
        JA      INVALID
        INC     SI
        LOOP    VLABEL
        JMP     SHORT INVALID
VLEND:  MOV     DX,ES:[DI+EN_CSUM]
        PUSH    DX
        CALL    IPLPTR
        PUSH    DS
        MOV     DS,AX
        MOV     CX,1024
        CALL    CRC16
        POP     DS
        POP     AX
        CMP     DX,AX
        JNE     INVALID
VNEXT:  INC     BL
        CMP     BL,MAXID
        JBE     VLOOP
        CLC
        RET
INVALID:STC
        RET

; BL = entry ID. ENTRY leaves BX alone; IPLPTR returns AX:SI.
IDOK:   OR      BL,BL
        JZ      IDGOOD
        CMP     BL,MAXID
        JA      INVALID
        CALL    ENTRY
        CMP     BYTE PTR ES:[DI],0
        JE      INVALID
IDGOOD: CLC
        RET
ENTRY:  MOV     AL,ENTRYLEN
        MOV     AH,BL
        DEC     AH
        MUL     AH
        ADD     AX,ST_ENT
        MOV     DI,AX
        RET
IPLPTR: XOR     AH,AH
        MOV     AL,BL
        MOV     CL,10
        SHL     AX,CL
        MOV     SI,AX
        MOV     AX,[BMSTSEG]
        RET

; Before even offering a choice, validate the free/occupied real names
; and each saved directory entry. Check duplicate names and unexpected
; parking aliases rather than letting an ambiguous rename proceed.
CHECKFILES:
        MOV     [SETID],1
CSET:   MOV     BL,[SETID]
        CALL    ENTRY
        CMP     BYTE PTR ES:[DI],0
        JNE     CINIT
        JMP     CNEXT
CINIT:  MOV     [FILEID],0
CFILE:  CALL    NAMES
        CALL    FIND
        JC      CFERR
        MOV     BL,[SETID]
        CMP     BL,ES:[ST_OWNER]
        JNE     CPARK
        INC     AX
        JNZ     CFERR           ;The owner must have no parked alias.
        MOV     SI,[REALPTR]
        CALL    FIND
        JC      CFERR
        MOV     DL,[ATTR]
        JMP     SHORT CRECORD
CFERR:  STC
        RET
CPARK:  MOV     DL,[ATTR]
        OR      DL,2
CRECORD:CMP     DL,[MATCH+11]
        JNE     CFERR
        PUSH    AX
        CALL    FILEREC
        POP     AX
        CMP     AX,ES:[DI]
        JNE     CFERR
        CMP     AX,0FFFFH
        JE      CFERR
        MOV     AX,WORD PTR [MATCH+28]
        OR      AX,WORD PTR [MATCH+30]
        JZ      CFERR
        MOV     SI,OFFSET MATCH+12
        MOV     CX,20
        CALL    CRC16
        CMP     DX,ES:[DI+2]
        JNE     CFERR
        INC     [FILEID]
        CMP     [FILEID],4
        JB      CFILE
CNEXT:  INC     [SETID]
        CMP     [SETID],MAXID
        JA      CEND
        JMP     CSET
CEND:   CMP     BYTE PTR ES:[ST_OWNER],0
        JNE     CFOK
        MOV     [FILEID],0
CFREE:  CALL    NAMES
        MOV     SI,[REALPTR]
        CALL    FIND
        JC      CFERR
        INC     AX
        JNZ     CFERR
        INC     [FILEID]
        CMP     [FILEID],4
        JB      CFREE
CFOK:   CLC
        RET

; Name helpers; FILEID is 0..3, SETID is 1..3 when producing a park name.
NAMES:  XOR     BH,BH
        MOV     BL,[FILEID]
        MOV     AL,[REALATTR+BX]
        MOV     [ATTR],AL
        MOV     AL,11
        MUL     BL
        ADD     AX,OFFSET REALNAME
        MOV     [REALPTR],AX
        MOV     AL,[SETID]
        ADD     AL,'0'
        MOV     [PARKNAME+2],AL
        ADD     BL,'0'
        MOV     [PARKNAME+3],BL
        MOV     SI,OFFSET PARKNAME
        RET
FILEREC:MOV     BL,[SETID]
        CALL    ENTRY
        XOR     AH,AH
        MOV     AL,[FILEID]
        SHL     AX,1
        SHL     AX,1
        ADD     DI,AX
        ADD     DI,EN_FILES
        RET

; Find DS:SI within the root, including volume/directory entries (they
; can collide). Return slot or FFFFh, CF=1 on IO error or duplicates.
FIND:   PUSH    ES
        MOV     [SLOT],0FFFFH
        MOV     ES,[BMBUFSEG]
        MOV     AX,[ROOT]
        XOR     BX,BX
FSECT:  XOR     BP,BP
        CALL    READSEC
        JC      FERR
        XOR     DI,DI
FENTRY: CMP     BYTE PTR ES:[DI],0
        JE      FEND
        CMP     BYTE PTR ES:[DI],0E5H
        JE      FSKIP
        PUSH    SI
        PUSH    DI
        MOV     CX,11
        REPE    CMPSB
        POP     DI
        POP     SI
        JNE     FSKIP
        CMP     [SLOT],0FFFFH
        JNE     FERR
        MOV     [SLOT],BX
        PUSH    AX
        PUSH    DS
        PUSH    ES
        PUSH    SI
        PUSH    DI
        MOV     SI,DI
        PUSH    ES
        POP     DS
        PUSH    CS
        POP     ES
        MOV     DI,OFFSET MATCH
        MOV     CX,16
        REP     MOVSW
        POP     DI
        POP     SI
        POP     ES
        POP     DS
        POP     AX
FSKIP:  INC     BX
        ADD     DI,32
        CMP     DI,1024
        JB      FENTRY
        INC     AX
        CMP     AX,[DATA0]
        JB      FSECT
FEND:   MOV     AX,[SLOT]
        CLC
        JMP     SHORT FRET
FERR:   STC
FRET:   POP     ES
        RET

; Commit order: marker, park owner, activate target, final state.
; One 256-byte physical block is written for each root slot update.
SWITCH: MOV     BL,[CHOICE]
        CMP     BL,ES:[ST_OWNER]
        JNE     MOVESET
        CMP     BL,ES:[ST_LAST]
        JE      SWOK
        MOV     ES:[ST_LAST],BL
        JMP     SAVE
MOVESET:MOV     BYTE PTR ES:[ST_PHASE],1
        MOV     ES:[ST_NEXT],BL
        CALL    SAVE
        JC      SWERR
        MOV     AL,ES:[ST_OWNER]
        MOV     [SETID],AL
        MOV     [ACTIVATE],0
        CALL    RENAMESET
        JC      SWERR
        MOV     AL,[CHOICE]
        MOV     [SETID],AL
        MOV     [ACTIVATE],1
        CALL    RENAMESET
        JC      SWERR
        MOV     BL,[CHOICE]
        MOV     ES:[ST_LAST],BL
        MOV     ES:[ST_OWNER],BL
        MOV     BYTE PTR ES:[ST_PHASE],0
        MOV     BYTE PTR ES:[ST_NEXT],0
        JMP     SAVE
SWOK:   CLC
SWERR:  RET
SAVE:   PUSH    DS
        PUSH    ES
        POP     DS
        XOR     SI,SI
        MOV     CX,ST_CSUM
        CALL    CRC16
        MOV     ES:[ST_CSUM],DX
        POP     DS
        MOV     AX,[STATE]
        XOR     BX,BX
        XOR     BP,BP
        JMP     WRITEBLOCK

RENAMESET:
        CMP     [SETID],0
        JE      SWOK
        MOV     [FILEID],0
RFILE:  CALL    NAMES
        CMP     [ACTIVATE],0
        JNE     RREAL
        OR      [ATTR],2
        JMP     SHORT RLOAD
RREAL:  MOV     SI,[REALPTR]
RLOAD:  CALL    FILEREC
        MOV     AX,ES:[DI]
        PUSH    ES
        CALL    GETSLOT
        JC      REXIT
        PUSH    DI
        MOV     CX,11
        REP     MOVSB
        MOV     DL,[ATTR]
        MOV     ES:[DI],DL
        POP     DI
        CALL    PUTSLOT
REXIT:  POP     ES
        JC      RERR
        INC     [FILEID]
        CMP     [FILEID],4
        JB      RFILE
        CLC
        RET
RERR:   STC
        RET

; Read root slot AX to ES:DI, ES is scratch; returns logical LBA AX.
GETSLOT:MOV     DI,AX
        AND     DI,31
        MOV     CL,5
        SHL     DI,CL
        SHR     AX,CL
        ADD     AX,[ROOT]
        CMP     AX,[DATA0]
        JAE     RERR
        MOV     ES,[BMBUFSEG]
        XOR     BP,BP
        JMP     READSEC
; Store the physical block containing ES:DI in root sector AX.
PUTSLOT:MOV     BX,DI
        MOV     CL,8
        SHR     BX,CL
        AND     DI,0FF00H
        MOV     BP,DI
        JMP     WRITEBLOCK

; AX = logical LBA, ES:BP = aligned DMA buffer. BX = block within
; logical sector on write. INT 81h uses a 32-bit physical block number.
READSEC:PUSH    BX
        XOR     BX,BX
        MOV     CX,8104H
        JMP     SHORT TRANSFER
WRITEBLOCK:
        PUSH    BX
        MOV     CX,8201H
TRANSFER:
        PUSH    AX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        XCHG    AX,CX
        XOR     DX,DX
        SHL     CX,1
        RCL     DX,1
        SHL     CX,1
        RCL     DX,1
        ADD     CX,BX           ;Aligned LBA * 4, BX <= 3, cannot carry.
        XOR     BL,BL
        MOV     BH,[BMTARGET]
        INT     81H
        CLD
        POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     SI
        POP     DX
        POP     AX
        POP     BX
        RET

        IFNDEF  MENUDOS
; Map compact displayed digits onto persistent IDs (DOS is always last).
CHOOSE: MOV     SI,OFFSET HEADER
        CALL    PRINT
        CALL    MODEL
        CALL    PRINT
        MOV     BL,1
        MOV     BH,1
OPTIONS:CALL    ENTRY
        CMP     BYTE PTR ES:[DI],0
        JE      ONEXT
        CALL    DIGIT
        PUSH    DS
        PUSH    ES
        POP     DS
        MOV     SI,DI
        CALL    PRINT
        POP     DS
        MOV     SI,OFFSET NEWLINE
        CALL    PRINT
        INC     BH
ONEXT:  INC     BL
        CMP     BL,MAXID
        JBE     OPTIONS
        XOR     BL,BL
        CALL    DIGIT
        MOV     SI,OFFSET DOSLINE
        CALL    PRINT
        MOV     SI,OFFSET DEFAULT
        CALL    PRINT
        MOV     BL,ES:[ST_LAST]
        MOV     [CHOICE],BL
        CALL    CLOCK
        JC      FORCEOS
        MOV     [STARTSEC],DL
        MOV     DI,0FFFFH       ;Finite even if the RTC is not advancing.
POLL:   MOV     AH,0AH
        INT     82H
        JC      TICK
        MOV     AH,09H
        INT     82H
        CMP     AL,13
        JE      CHOSEN
        SUB     AL,'1'
        CMP     AL,[COUNT]     ;1..number of entries + DOS.
        JA      TICK
        XOR     AH,AH
        MOV     BX,AX
        MOV     AL,[MAP+BX+1]
        MOV     [CHOICE],AL
CHOSEN: RET
TICK:   CALL    CLOCK
        JC      FORCEOS
        SUB     DL,[STARTSEC]
        JNC     NOWRAP
        ADD     DL,60
NOWRAP: CMP     DL,10
        JAE     CHOSEN
        DEC     DI
        JNZ     POLL
FORCEOS:MOV     [CHOICE],DOSID
        RET
CLOCK:  MOV     AH,2
        INT     8CH
        CMP     CH,24
        JAE     BADCLOCK
        CMP     CL,60
        JAE     BADCLOCK
        MOV     DL,DH
        CMP     DL,60
        CMC
        RET
BADCLOCK:
        STC
        RET
DIGIT:  PUSH    BX
        MOV     AL,BH
        XOR     BH,BH
        XCHG    AL,BL
        MOV     [MAP+BX],AL
        ADD     BL,'0'
        MOV     [PREFIX],BL
        CMP     AL,ES:[ST_LAST]
        JNE     DPRINT
        MOV     [DEFNUM],BL
DPRINT: MOV     SI,OFFSET PREFIX
        CALL    PRINT
        POP     BX
        RET
; BNN Technical Manual 3.3 and 4.2.1; NEC VA2/VA3 specifications.
; Select text memory and probe its upper aperture, restoring both the
; original word and the mapping before re-enabling interrupts. ROM bank
; status can indicate an extension, but is not a unique board ID.
MODEL:  PUSH    ES
        PUSHF
        CLI
        MOV     DX,153H
        IN      AL,DX
        MOV     CL,AL
        AND     AL,0F0H
        OR      AL,1
        OUT     DX,AL
        MOV     AX,0D000H
        MOV     ES,AX
        MOV     BX,0FFFEH
        MOV     DI,ES:[BX]
        MOV     WORD PTR ES:[BX],0A55AH
        MOV     AX,ES:[BX]
        MOV     WORD PTR ES:[BX],05AA5H
        MOV     BX,ES:[BX]
        MOV     WORD PTR ES:[0FFFEH],DI
        MOV     SI,OFFSET UNKNOWN
        CMP     AX,0A55AH
        JNE     OPENBUS
        CMP     BX,05AA5H
        JNE     RESTMAP
        MOV     SI,OFFSET VA2NAME
        JMP     SHORT RESTMAP
OPENBUS:AND     AX,BX
        CMP     AX,0FFFFH
        JNE     RESTMAP
        MOV     DX,156H
        IN      AL,DX
        CMP     AL,0FFH
        JNE     RESTMAP
        MOV     SI,OFFSET VANAME
RESTMAP:MOV     DX,153H
        MOV     AL,CL
        OUT     DX,AL
        POPF
        POP     ES
        RET
PRINT:  PUSH    AX
        PUSH    BX
        PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        MOV     AH,2
        MOV     DX,8000H
        INT     83H
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

        ENDIF
        INCLUDE VACRC16.INC
; Name order is part of the state format.
REALNAME DB     'ENGINEIOSYS','PCENGINESYS','ADVGBIOSSYS','PCENGINECOM'
REALATTR DB     27H,27H,27H,21H
PARKNAME DB     'VA000000SYS'   ;Boot code fills the entry and file digits.
BMSTSEG DW      STATESEG
BMBUFSEG DW     3A00H
BMTARGET DB     80H
STATE   DW      0
ROOT    DW      0
DATA0   DW      0
COUNT   DB      0
SETID   DB      0
FILEID  DB      0
REALPTR DW      0
ATTR    DB      0
SLOT    DW      0
MATCH   DB      32 DUP (0)
CHOICE  DB      0
ACTIVATE DB     0
        IFNDEF  MENUDOS
STARTSEC DB     0
MAP     DB      5 DUP (0)
HEADER  DB      'MS-DOS 4.0 VA boot menu  ',0
VANAME  DB      '[PC-88VA]',13,10,0
VA2NAME DB      '[PC-88VA2/VA3]',13,10,0
UNKNOWN DB      '[PC-88VA?]',13,10,0
PREFIX  DB      '0: ',0
DOSLINE DB      'MS-DOS'
NEWLINE DB      13,10,0
DEFAULT DB      'Enter = '
DEFNUM  DB      '0 (automatic in 10 seconds)',13,10,0
BADMSG  DB      'Inconsistent boot menu; starting MS-DOS.',13,10,0
PREPMSG DB      'PC-Engine installation prepared; starting MS-DOS.',13,10,0
PENDMSG DB      'Boot menu update interrupted; starting MS-DOS.',13,10,0
        ENDIF
