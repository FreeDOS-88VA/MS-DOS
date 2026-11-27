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
        CALL    BMGEOMETRY
        JC      BADMENU
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
        CMP     BYTE PTR ES:[ST_PHASE],4
        JNE     BMSWITCH
        CALL    RECOVERDEL
        JNC     READY
        JMP     SHORT BADMENU
BMSWITCH:CMP    BYTE PTR ES:[ST_PHASE],1
        JNE     CAPWAIT
        CALL    RECOVERSW
        JNC     READY
        JMP     SHORT BADMENU
CAPWAIT:MOV     SI,OFFSET PENDMSG
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
        JNE     VREJECT
        CMP     BYTE PTR ES:[ST_VER],STATEVER
        JA      VREJECT
        CMP     BYTE PTR ES:[ST_FLAGS],1
        JA      VREJECT
        CMP     BYTE PTR ES:[ST_PHASE],4
        JA      VREJECT
        JNE     VSWITCH
        CMP     BYTE PTR ES:[ST_VER],STATEVER
        JNE     VREJECT
        CMP     BYTE PTR ES:[ST_NEXT],0
        JNE     VREJECT
        CMP     BYTE PTR ES:[ST_OWNER],0
        JE      VREJECT
        JMP     SHORT VOWNER
VSWITCH:CMP     BYTE PTR ES:[ST_PHASE],1
        JNE     VOWNER
        MOV     BL,ES:[ST_NEXT]
        CMP     BL,ES:[ST_OWNER]
        JE      INVALID
        CALL    IDOK
        JC      INVALID
VOWNER:
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

        INCLUDE VAMENUCK.INC
        INCLUDE VAMENUPS.INC

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
        IFDEF   SYSSWAP
        JE      FFIRST
        CMP     [RFFIND2],0
        JE      FERR
        CMP     [RFDUP],0FFFFH
        JNE     FERR
        MOV     [RFDUP],BX
        JMP     SHORT FSKIP
FFIRST:
        ELSE
        JNE     FERR
        ENDIF
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
        JNE     SWDEFAULT
        CLC
        RET
SWDEFAULT:MOV   ES:[ST_LAST],BL
        JMP     SAVE
MOVESET:MOV     ES:[ST_NEXT],BL
        CALL    PSOWNERS
        CALL    PSPLAN
        JNC     SWMARK
        RET
SWMARK:
        MOV     BYTE PTR ES:[ST_PHASE],1
        MOV     BYTE PTR ES:[ST_VER],STATEVER
        IFDEF   MENUDOS
        MOV     AL,[KEEPDEFAULT]
        MOV     ES:[ST_FLAGS],AL
        ENDIF
        CALL    SAVE
        JNC     RECOVERSW
        RET
RECOVERSW:
        CALL    CHECKFILES
        JNC     SWCHECK
        RET
SWCHECK:CMP     BYTE PTR ES:[ST_VER],STATEVER
        JB      SWCORE
        CALL    PSOWNERS
        CALL    PSCHECK
        JC      SWBAD
        CMP     [PSSTART],0
        JE      SWCORE
        CMP     BYTE PTR ES:[ST_OWNER],0
        JE      SWTARGET
        CMP     [PARKED],4
        JNE     SWBAD
SWTARGET:CMP    BYTE PTR ES:[ST_NEXT],0
        JE      SWCORE
        CMP     [ACTIVE],4
        JE      SWCORE
SWBAD:  STC
        RET
SWCORE: MOV     AL,ES:[ST_OWNER]
        MOV     [SETID],AL
        MOV     [ACTIVATE],0
        CALL    RENAMESET
        JC      SWERR
        MOV     AL,ES:[ST_NEXT]
        MOV     [SETID],AL
        MOV     [ACTIVATE],1
        CALL    RENAMESET
        JC      SWERR
        CMP     BYTE PTR ES:[ST_VER],STATEVER
        JB      SWLAST
        CALL    PSAPPLY
        JC      SWERR
SWLAST: MOV     BL,ES:[ST_NEXT]
        CMP     BYTE PTR ES:[ST_FLAGS],0
        JNE     SWOWNER
        MOV     ES:[ST_LAST],BL
SWOWNER:MOV     ES:[ST_OWNER],BL
        MOV     BYTE PTR ES:[ST_PHASE],0
        MOV     BYTE PTR ES:[ST_FLAGS],0
        MOV     BYTE PTR ES:[ST_NEXT],0
        JMP     SHORT SAVE
SWOK:   CLC
SWERR:  RET

; An active entry can be removed even with damaged core files. Leave
; them alone as in fix 1, but park its pair and restore the DOS pair.
RECOVERDEL:
        CALL    PSOWNERS
        CALL    PSCHECK
        JC      SWERR
        CALL    PSAPPLY
        JC      SWERR
        MOV     BL,ES:[ST_OWNER]
        MOV     BYTE PTR ES:[ST_OWNER],0
        MOV     BYTE PTR ES:[ST_PHASE],0
UNREGISTER:
        DEC     [COUNT]
        CALL    ENTRY
        MOV     BYTE PTR ES:[DI],0
        CMP     BL,ES:[ST_LAST]
        JNE     SAVE
        MOV     BYTE PTR ES:[ST_LAST],0
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
        JC      RDONE
        PUSH    SI
        PUSH    DI
        MOV     CX,11
        REPE    CMPSB
        POP     DI
        POP     SI
        JE      REXIT           ;Already done; preflight checked attributes.
        PUSH    DI
        MOV     CX,11
        REP     MOVSB
        MOV     DL,[ATTR]
        MOV     ES:[DI],DL
        POP     DI
        CALL    PUTSLOT
        JMP     SHORT RDONE
REXIT:  CLC
RDONE:  POP     ES
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
READSEC:
BMREAD: PUSH    BX
        XOR     BX,BX
        MOV     CX,8104H
        JMP     SHORT TRANSFER
WRITEBLOCK:
BMWRITE:PUSH    BX
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
        PUSH    DS
        PUSH    ES
        MOV     AH,0CH          ;Primitive keyboard buffer flush (603KEYB).
        INT     82H
        POP     ES
        POP     DS
        CLD
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
CHOSEN: MOV     SI,OFFSET NEWLINE
        JMP     PRINT
TICK:   CALL    CLOCK
        JC      FORCEOS
        SUB     DL,[STARTSEC]
        JNC     NOWRAP
        ADD     DL,60
NOWRAP: CMP     DL,11          ;First boundary can be arbitrarily close.
        JAE     CHOSEN
        MOV     AL,11
        SUB     AL,DL
        CMP     AL,[REMAIN]
        JE      POLLMORE
        MOV     [REMAIN],AL
        AAM
        ADD     AX,3030H
        CMP     AH,'0'
        JNE     TIMEPRINT
        MOV     AH,' '
TIMEPRINT:
        MOV     [SECONDS],AH
        MOV     [SECONDS+1],AL
        MOV     SI,OFFSET UPDLINE
        CALL    PRINT
POLLMORE:DEC    DI
        JNZ     POLL
FORCEOS:MOV     [CHOICE],DOSID
        JMP     SHORT CHOSEN
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
; original word and the mapping before re-enabling interrupts.
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
        IFDEF   MENUDOS
KEEPDEFAULT DB  0
        ENDIF
        IFNDEF  MENUDOS
STARTSEC DB     0
MAP     DB      5 DUP (0)
HEADER  DB      'MS-DOS 4.0 VA boot menu  ',0
VANAME  DB      '[PC-88VA]',13,10,0
VA2NAME DB      '[PC-88VA2/VA3/VA-91]',13,10,0
UNKNOWN DB      '[PC-88VA?]',13,10,0
PREFIX  DB      '0: ',0
DOSLINE DB      'MS-DOS'
NEWLINE DB      13,10,0
UPDLINE DB      13
DEFAULT DB      'Enter = '
DEFNUM  DB      '0 (automatic in '
SECONDS DB      '11'
        DB      ' seconds)',0
REMAIN  DB      11
BADMSG  DB      'Inconsistent boot menu; starting MS-DOS.',13,10,0
PREPMSG DB      'PC-Engine installation prepared; starting MS-DOS.',13,10,0
PENDMSG DB      'Boot menu update interrupted; starting MS-DOS.',13,10,0
        ENDIF
