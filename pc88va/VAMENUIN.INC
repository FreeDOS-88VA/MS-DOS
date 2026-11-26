; SPDX-License-Identifier: MIT
; SYS-side installer. Called after validating the mounted NEC volume and
; reserving physically aligned IPL(1 KiB), DMA(1 KiB), state(4 KiB).
        INCLUDE VAMENUSZ.INC

D5CF    MACRO   destination
        LOCAL   okay
        JNC     okay
        JMP     destination
okay:
        ENDM
D5NZ    MACRO   destination
        LOCAL   okay
        JZ      okay
        JMP     destination
okay:
        ENDM

D5Z     MACRO   destination
        LOCAL   okay
        JNZ     okay
        JMP     destination
okay:
        ENDM

D5OP    DB      0
D5IPL   DB      0               ;0 blank, 1 foreign/old, 2 plain, 3 enabled.
D5DELETE DB     0
D5PRESENT DB    0
D5CAP   DB      0               ;entry ID for new or pending capture.
D5RESUME DB     0
D5CAPPAIR DB    0               ;Standalone first capture (no DOS files).
D5STAGE DW      0
D5STAGESLOT DW  0
D5UPGRADE DB    0
D5REPLAYED DB   0
D5SPC   DW      0
D5SPF   DW      0
D5FILE  DW      0
D5SIZE  DW      0
D5POS   DW      0
D5PAR   DW      0
D5END   DB      0
D5LABEL DB      16,0,16 DUP (0)
D5LABELDEF DB   'PC-Engine 0',0
D5DAT   DB      'BOOTMENUDAT'
D5SYS   DB      'BOOTMENUSYS'

D5ARGS: LODSB
        CMP     AL,'/'
        JNE     D5ARGERR
        LODSB
        AND     AL,0DFH
        CMP     AL,'D'
        JE      D5ARGD
        CMP     AL,'L'
        JE      D5ARGOP
        CMP     AL,'P'
        JE      D5ARGOP
        CMP     AL,'C'
        JNE     D5ARGERR
D5ARGOP:MOV     [D5OP],AL
D5ARGTAIL:
        LODSB
        CMP     AL,13
        JE      D5ARGOK
        CMP     AL,' '
        JE      D5ARGTAIL
        CMP     AL,9
        JE      D5ARGTAIL
D5ARGERR:STC
        RET
D5ARGD: MOV     [D5OP],AL
D5ARGNUM:
        LODSB
        CMP     AL,' '
        JE      D5ARGNUM
        CMP     AL,9
        JE      D5ARGNUM
        SUB     AL,'1'
        CMP     AL,MAXID-1
        JA      D5ARGERR
        INC     AL
        MOV     [D5DELETE],AL
        JMP     SHORT D5ARGTAIL
D5ARGOK:CLC
        RET

; Preserve D4 recognition of blank and old IPLs; a D5 installation
; ignores block 1, so its final publication need only write block 0.
D5TYPE: PUSH    AX
        MOV     ES,[WORKSEG]
        MOV     SI,OFFSET HDBOOTCODE
        XOR     DI,DI
        MOV     CX,255
        REPE    CMPSB
        JNE     D5TOLD
        MOV     SI,OFFSET HDBOOTCODE+512
        MOV     DI,512
        MOV     CX,256
        REPE    CMPSW
        JNE     D5TOLD
        POP     AX
        MOV     AL,2
        CMP     BYTE PTR ES:[255],0
        JE      D5TRET
        INC     AL
D5TRET: RET
D5TOLD: ; Released D4 and D5 IPLs (our own code only).
        PUSH    DS
        PUSH    ES
        POP     DS
        XOR     SI,SI
        MOV     CX,255
        CALL    CRC16
        MOV     BX,DX
        MOV     SI,512
        MOV     CX,512
        CALL    CRC16
        POP     DS
        POP     AX
        CMP     BX,1A57H       ;D4: keep its IPL on DOS refresh.
        JNE     D5TV0
        CMP     DX,0A31AH
        JNE     D5TRET
        MOV     AL,2
        RET
D5TV0:  CMP     BX,0D7F5H      ;Original D5 and fix 1 share the stage ABI.
        JE      D5TOLDMENU
        CMP     BX,5434H
        JNE     D5TRET
D5TOLDMENU:CMP  DX,2F41H
        JNE     D5TRET
        MOV     AL,2
        CMP     BYTE PTR ES:[255],0
        JE      D5TRET
        CMP     BYTE PTR ES:[255],1
        JNE     D5TRET
        MOV     AL,3
        MOV     [D5UPGRADE],1
        RET

D5GEOMSET:
        MOV     AL,[FTARGET]
        OR      AL,80H
        MOV     [BMTARGET],AL
        MOV     AL,[FTYPE]
        MOV     AH,10
        MUL     AH
        MOV     BX,AX
        MOV     AX,[D5GEOM+BX]
        MOV     [D5SPF],AX
        MOV     AX,[D5GEOM+BX+2]
        MOV     [ROOT],AX
        MOV     AX,[D5GEOM+BX+4]
        MOV     [DATA0],AX
        MOV     AX,[D5GEOM+BX+6]
        MOV     [D5CLMAX],AX
        MOV     AX,[D5GEOM+BX+8]
        MOV     [D5SPC],AX
        MOV     AH,0DH           ;Drop DOS buffers before raw directory access.
        INT     21H
        JMP     BMGEOMETRY

D5SETUP:CALL    D5GEOMSET
        D5CF    D5ERROR
        CALL    D5OPEN
        JC      D5SETRET
        CMP     BYTE PTR ES:[ST_PHASE],1
        JE      D5REPLAYOP
        CMP     BYTE PTR ES:[ST_PHASE],4
        JNE     D5SETOK
D5REPLAYOP:
        CMP     [D5IPL],3
        D5NZ    D5ERROR
        CMP     [D5OP],0
        JE      D5REPLAY
        CMP     [D5OP],'L'
        D5NZ    D5ERROR
D5REPLAY:CMP    BYTE PTR ES:[ST_PHASE],4
        JE      D5REPLAYDEL
        CALL    RECOVERSW
        JMP     SHORT D5REPLAYEND
D5REPLAYDEL:CALL RECOVERDEL
D5REPLAYEND:
        D5CF    D5ERROR
        MOV     [D5REPLAYED],1
D5SETOK:CLC
D5SETRET:RET

D5ERROR:MOV     DX,OFFSET D5BADMSG
        STC
        RET
D5PCERR:MOV     DX,OFFSET D5NOTPC
        STC
        RET
D5NOROOM:MOV    DX,OFFSET D5ROOM
        STC
        RET
D5NEEDOS:MOV    DX,OFFSET D5NEED
        STC
        RET

; Both optional files must fit within a single ordinary FAT12 cluster.
; Calculate the physical location from FAT1; require EOC and exact size.
D5LOCATE:
        CALL    FIND
        D5CF    D5LOCERR
        CMP     AX,0FFFFH
        D5Z     D5LOCOK
        MOV     BL,[MATCH+11]
        AND     BL,0DFH
        CMP     BL,7
        D5NZ    D5LOCERR
        CMP     WORD PTR [MATCH+30],0
        D5NZ    D5LOCERR
        OR      DX,DX
        JNZ     D5LOCSIZE
        MOV     DX,WORD PTR [MATCH+28]  ;Older stage, still one cluster.
        CMP     DX,1
        JB      D5LOCERR
        CMP     DX,4096
        JA      D5LOCERR
D5LOCSIZE:CMP   WORD PTR [MATCH+28],DX
        JNE     D5LOCERR
        MOV     AX,WORD PTR [MATCH+26]
        CMP     AX,2
        JB      D5LOCERR
        CMP     AX,[D5CLMAX]
        JA      D5LOCERR
        MOV     [D5FILE],AX
        MOV     DI,AX
        SHR     DI,1
        ADD     DI,AX
        MOV     AX,DI
        MOV     CL,10
        SHR     AX,CL
        INC     AX
        AND     DI,1023
        MOV     ES,[BMBUFSEG]
        XOR     BP,BP
        CALL    READSEC
        JC      D5LOCERR
        XOR     DX,DX
        MOV     DL,ES:[DI]
        INC     DI
        CMP     DI,1024
        JB      D5FATEND
        INC     AX
        CMP     AX,[D5SPF]
        JA      D5LOCERR
        CALL    READSEC
        JC      D5LOCERR
        XOR     DI,DI
D5FATEND:MOV    DH,ES:[DI]
        MOV     AX,[D5FILE]
        TEST    AL,1
        JZ      D5EVEN
        MOV     CL,4
        SHR     DX,CL
D5EVEN: AND     DX,0FFFH
        CMP     DX,0FF8H
        JB      D5LOCERR
        SUB     AX,2
        MUL     [D5SPC]
        ADD     AX,[DATA0]
D5LOCOK:CLC
        RET
D5LOCERR:STC
        RET

D5OPEN: CALL    D5JRRECOVER
        D5CF    D5ERROR
        MOV     ES,[BMSTSEG]
        XOR     AX,AX
        MOV     DI,AX
        MOV     CX,2048
        REP     STOSW
        MOV     SI,OFFSET D5DAT
        CALL    FIND
        D5CF    D5ERROR
        CMP     AX,0FFFFH
        JNE     D5OPENFULL
        MOV     [D5STAGE],0FFFFH
        JMP     D5NOSTATE
D5OPENFULL:
        MOV     SI,OFFSET D5SYS
        MOV     DX,MENUSIZE
        CMP     [D5UPGRADE],0
        JNE     D5OPENOLD
        CMP     [D5IPL],1
        JNE     D5OPENLOC
D5OPENOLD:XOR   DX,DX
D5OPENLOC:CALL  D5LOCATE
        D5CF    D5ERROR
        MOV     [D5STAGE],AX
        MOV     BX,[SLOT]
        MOV     [D5STAGESLOT],BX
        CMP     AX,0FFFFH
        JE      D5OPENST
        CMP     [D5UPGRADE],0
        JNE     D5OPENST
        CMP     [D5IPL],1
        JE      D5OPENST        ;Foreign IPL is checked against saved capture.
        CALL    D5CHECKSTAGE
        D5CF    D5ERROR
        JMP     SHORT D5OPENST
D5CHECKSTAGE:
        MOV     ES,[BMBUFSEG]
        MOV     [D5SIZE],MENUSIZE
        MOV     [D5POS],AX
        XOR     DX,DX
D5VERIFY:
        MOV     AX,[D5POS]
        XOR     BP,BP
        CALL    READSEC
        JC      D5CHECKRET
        PUSH    DS
        PUSH    ES
        POP     DS
        XOR     SI,SI
        MOV     CX,CS:[D5SIZE]
        CMP     CX,1024
        JBE     D5CRCB
        MOV     CX,1024
D5CRCB: CALL    CRC16B
        POP     DS
        SUB     [D5SIZE],1024
        JBE     D5CRCFIN
        INC     [D5POS]
        JMP     SHORT D5VERIFY
D5CRCFIN:CMP    DX,MENUCRC
        JE      D5CHECKOK
        STC
D5CHECKOK:
D5CHECKRET:RET
D5OPENST:MOV    SI,OFFSET D5DAT
        MOV     DX,4096
        CALL    D5LOCATE
        D5CF    D5ERROR
        MOV     ES,[BMSTSEG]
        CMP     AX,0FFFFH
        JE      D5NOSTATE
        MOV     [STATE],AX
        MOV     [D5PRESENT],1
        CMP     [D5STAGE],0FFFFH
        D5Z     D5ERROR
        CALL    D5LOADSTATE
        D5CF    D5ERROR
        RET
D5LOADSTATE:
        MOV     ES,[BMSTSEG]
        XOR     BP,BP
D5RSTATE:CALL   READSEC
        JC      D5STATERET
        INC     AX
        ADD     BP,1024
        CMP     BP,4096
        JB      D5RSTATE
        JMP     VALIDATE
D5STATERET:RET
D5NOSTATE:
        CMP     [D5IPL],3
        D5Z     D5ERROR
        MOV     WORD PTR ES:[ST_SIG1],4256H
        MOV     WORD PTR ES:[ST_SIG2],314DH
        MOV     BYTE PTR ES:[ST_VER],STATEVER
        CLC
        RET

; Non-writing preflight, including all four names and the user's label.
D5PLAN: CALL    D5SETUP
        D5CF    D5PASS
        CMP     [D5IPL],1
        JE      D5FOREIGN
        CMP     [D5PRESENT],0
        JNE     D5OWN
        CALL    CHECKFILES
        D5CF    D5PCERR
        RET
D5OWN:  CMP     [D5IPL],3
        D5NZ    D5ERROR
        CMP     BYTE PTR ES:[ST_PHASE],2
        D5Z     D5PCERR
        CMP     BYTE PTR ES:[ST_PHASE],0
        D5NZ    D5ERROR
        CALL    CHECKFILES
        D5CF    D5ERROR
D5PASS: RET
D5FOREIGN:
        CMP     [D5PRESENT],0
        JE      D5NEW
        CMP     BYTE PTR ES:[ST_PHASE],2
        JE      D5NEW
        CMP     BYTE PTR ES:[ST_PHASE],3
        JE      D5PENDING
        CMP     BYTE PTR ES:[ST_PHASE],0
        D5NZ    D5ERROR
        MOV     BL,ES:[ST_LAST]
        OR      BL,BL
        JE      D5BADPCE
        CALL    D5MATCHIPL
        D5CF    D5ERROR
        CALL    CHECKFILES
        D5CF    D5ERROR
        RET
D5PENDING:
        MOV     BL,ES:[ST_NEXT]
        OR      BL,BL
        JE      D5BADPCE
        CALL    IDOK
        D5CF    D5ERROR
        CALL    D5MATCHIPL
        D5CF    D5ERROR
        MOV     AL,ES:[ST_NEXT]
        MOV     [D5CAP],AL
        MOV     [D5RESUME],1
        JMP     D5CAPCHECK
D5BADPCE:JMP    D5PCERR
D5NEW:  CALL    D5AVAILABLE
        D5CF    D5NOROOM
D5FOUNDID:
        CALL    D5CAPCHECK
        JNC     D5CAPROOM
        CMP     [D5PRESENT],0
        JNE     D5BADPCE
        ; Plain D4 upgrades need no menu when all four names are absent.
        CALL    CHECKFILES
        D5CF    D5PCERR
        RET
D5CAPROOM:
        CMP     [D5PRESENT],0
        JNE     D5GETLABEL
        ; No menu: the existing startup pair is presumed PC-Engine's
        ; only if neither DOS kernel name exists. Persist this decision
        ; before transferring DOS, so retry cannot change the owner.
        MOV     SI,OFFSET RFNAMES
        CALL    FIND
        D5CF    D5ERROR
        CMP     AX,0FFFFH
        JNE     D5CAPDOSEND
        MOV     SI,OFFSET RFNAMES+11
        CALL    FIND
        D5CF    D5ERROR
        CMP     AX,0FFFFH
        JNE     D5CAPDOSEND
        MOV     [D5CAPPAIR],1
D5CAPDOSEND:MOV SI,OFFSET D5SYS
        CALL    FIND
        D5CF    D5ERROR
        CMP     AX,0FFFFH
        D5NZ    D5NOROOM
D5GETLABEL:
        MOV     AL,[SETID]
        MOV     [D5CAP],AL
        ADD     AL,'0'
        MOV     [D5LABELDEF+10],AL
        MOV     DX,OFFSET D5LABELASK
        CALL    PUTS
        MOV     DX,OFFSET D5LABEL
        MOV     AX,0C0AH
        INT     21H
        CALL    CRLF
        MOV     SI,OFFSET D5LABELDEF
        CMP     [D5LABEL+1],0
        JE      D5LABCP
        MOV     SI,OFFSET D5LABEL+2
        XOR     BH,BH
        MOV     BL,[D5LABEL+1]
        MOV     BYTE PTR [SI+BX],0
D5LABCP:MOV     ES,[BMSTSEG]
        MOV     BL,[D5CAP]
        CALL    ENTRY
D5LABL: LODSB
        STOSB
        OR      AL,AL
        JZ      D5LABELGOOD
        CMP     AL,20H
        JB      D5LABELFAIL
        CMP     AL,7EH
        JBE     D5LABL
D5LABELFAIL:MOV DX,OFFSET D5BADLABEL
        STC
        RET
D5LABELGOOD:CLC
        RET

; Skip occupied IDs and the retained names of unregistered entries.
D5AVAILABLE:
        MOV     [SETID],1
D5IDTRY:MOV     BL,[SETID]
        CALL    ENTRY
        CMP     BYTE PTR ES:[DI],0
        JNE     D5IDNEXT
        MOV     [FILEID],0
D5IDNAME:CALL   NAMES
        CALL    FIND
        JC      D5IDERR
        CMP     AX,0FFFFH
        JNE     D5IDNEXT
        INC     [FILEID]
        CMP     [FILEID],4
        JB      D5IDNAME
        XOR     BX,BX
        CALL    D5IDPAIR
        JC      D5IDERR
        CMP     AX,0FFFFH
        JNE     D5IDNEXT
        MOV     BX,2
        CALL    D5IDPAIR
        JC      D5IDERR
        CMP     AX,0FFFFH
        JNE     D5IDNEXT
        CLC
        RET
D5IDNEXT:INC    [SETID]
        CMP     [SETID],MAXID
        JBE     D5IDTRY
D5IDERR:STC
        RET
D5IDPAIR:MOV    AL,[SETID]
        CALL    PSNAME
        JMP     FIND

; D5 saves all four blocks, but boot publication can already have
; replaced blocks 2..3. Restart identifies the still-foreign entry by
; its unchanged first two blocks; do not use signatures from NEC media.
D5MATCHIPL:
        CALL    IPLPTR
        PUSH    DS
        PUSH    ES
        MOV     DS,AX
        MOV     ES,CS:[WORKSEG]
        XOR     DI,DI
        MOV     CX,256
        REPE    CMPSW
        POP     ES
        POP     DS
        D5NZ    D5LOCERR
        CLC
        RET

D5CAPCHECK:
        CMP     [D5RESUME],0
        JE      D5CCINIT
        MOV     AL,[D5CAP]
        MOV     [SETID],AL
D5CCINIT:
        MOV     AL,[SETID]
        MOV     [CAPSKIP],AL
        CALL    CHECKFILES
        MOV     AL,[CAPSKIP]
        MOV     [SETID],AL
        MOV     [CAPSKIP],0
        D5CF    D5CCERR
        MOV     [FILEID],0
D5CCFILE:CALL   NAMES
        CALL    FIND
        D5CF    D5CCERR
        MOV     [D5PAR],AX
        CMP     [D5RESUME],0
        JNE     D5CCREAL
        CMP     AX,0FFFFH
        D5NZ    D5CCERR
D5CCREAL:MOV    SI,[REALPTR]
        CALL    FIND
        D5CF    D5CCERR
        PUSH    AX
        CALL    FILEREC
        POP     AX
        CMP     [D5RESUME],0
        JE      D5CCNEW
        CMP     AX,0FFFFH
        JNE     D5CCBOTH
        MOV     AX,[D5PAR]
        OR      [ATTR],2
        JMP     SHORT D5CCSLOT
D5CCBOTH:CMP    [D5PAR],0FFFFH
        JNE     D5CCERR
D5CCSLOT:CMP    AX,ES:[DI]
        JNE     D5CCERR
        JMP     SHORT D5CCCHECK
D5CCNEW:MOV     ES:[DI],AX
        CMP     [D5PRESENT],0
        JE      D5CCCHECK
        XOR     BH,BH
        MOV     BL,[FILEID]
        SHL     BX,1
        CMP     AX,ES:[ST_PREP+BX]
        JNE     D5CCERR
D5CCCHECK:CMP   AX,0FFFFH
        JE      D5CCERR
        MOV     AL,[ATTR]
        CMP     AL,[MATCH+11]
        JNE     D5CCERR
        CALL    CHECKCHAIN
        JC      D5CCERR
        MOV     SI,OFFSET MATCH+12
        MOV     CX,20
        CALL    CRC16
        CMP     [D5RESUME],0
        JE      D5CCSUM
        CMP     DX,ES:[DI+2]
        JNE     D5CCERR
D5CCSUM:MOV     ES:[DI+2],DX
        INC     [FILEID]
        CMP     [FILEID],4
        JAE     D5CCDONE
        JMP     D5CCFILE
D5CCDONE:CLC
        RET
D5CCERR:STC
        RET

D5COMMIT:
        CMP     [D5CAP],0
        D5NZ    D5PARKCAP
        CMP     [D5PRESENT],0
        JNE     D5KEEPMENU
        CMP     [D5IPL],2
        JE      D5PARKOK       ;Already bootable; keep the DOS loader.
        CALL    HIPLWRITE
        D5CF    D5IOERR
        RET
D5KEEPMENU:
        CMP     [D5IPL],3
        D5NZ    D5NEWSTAGE
        CMP     [D5UPGRADE],0
        JE      D5UPSTATE
        CALL    D5NEWSTAGE
        D5CF    D5IOERR
D5UPSTATE:
        MOV     ES,[BMSTSEG]
        CMP     BYTE PTR ES:[ST_VER],STATEVER
        JE      D5PARKDOS
        MOV     BYTE PTR ES:[ST_VER],STATEVER
        CALL    SAVE
        D5CF    D5IOERR
D5PARKDOS:
        CMP     BYTE PTR ES:[ST_OWNER],0
        JE      D5PARKOK
        MOV     [KEEPDEFAULT],1  ;SYS is not a boot-menu selection.
        MOV     [CHOICE],0
        CALL    SWITCH
        D5CF    D5IOERR
D5PARKOK:CLC
        RET
D5IOERR:MOV     DX,OFFSET S_IOERR
        STC
        RET
; Journal capture before DOS file transfer can obscure first ownership.
D5CAPTURE:
        CMP     [D5CAP],0
        JE      D5PARKOK
        CMP     [D5RESUME],0
        JNE     D5PARKOK
        MOV     ES,[BMSTSEG]
        MOV     BL,[D5CAP]
        CALL    ENTRY
        PUSH    DI
        CALL    IPLPTR
        MOV     DI,SI
        PUSH    DS
        MOV     DS,[WORKSEG]
        XOR     SI,SI
        MOV     CX,512
        REP     MOVSW
        MOV     SI,0
        MOV     CX,1024
        CALL    CRC16
        POP     DS
        POP     DI
        MOV     ES:[DI+EN_CSUM],DX
        MOV     AL,[D5CAP]
        MOV     ES:[ST_NEXT],AL
        MOV     BYTE PTR ES:[ST_PHASE],3
        MOV     AL,[D5CAPPAIR]
        MOV     ES:[ST_CAPPAIR],AL
        OR      AL,AL
        JZ      D5CAPSAVE
        CALL    PSCAPIDS
        CALL    PSPLAN
        D5CF    D5ERROR
D5CAPSAVE:
        CMP     [D5PRESENT],0
        JE      D5BOOTSTRAP
        ; Store the saved IPL first. It is not referenced by on-disk
        ; metadata until all four blocks are written successfully.
        MOV     BL,[D5CAP]
        CALL    IPLPTR
        XOR     AH,AH
        MOV     AL,BL
        ADD     AX,[STATE]
        MOV     BP,SI
        CALL    D5STORESEC
        D5CF    D5IOERR
        CALL    SAVE
        D5CF    D5IOERR
        RET
D5BOOTSTRAP:
        CMP     [D5STAGE],0FFFFH
        D5NZ    D5ERROR
        CALL    D5JRNEW
        D5CF    D5PASS
        JMP     D5OPEN
D5PARKCAP:
        MOV     ES,[BMSTSEG]
        CMP     BYTE PTR ES:[ST_VER],STATEVER
        JB      D5CAPCORE
        CMP     BYTE PTR ES:[ST_CAPPAIR],1
        JNE     D5CAPCORE
        CALL    PSCAPIDS
        CALL    PSCHECK
        D5CF    D5ERROR
D5CAPCORE:
        MOV     AL,[D5CAP]
        MOV     [SETID],AL
        MOV     [ACTIVATE],0
        CALL    RENAMESET
        D5CF    D5IOERR
        CMP     BYTE PTR ES:[ST_VER],STATEVER
        JB      D5CAPFINISH
        CMP     BYTE PTR ES:[ST_CAPPAIR],1
        JNE     D5CAPFINISH
        CALL    PSAPPLY
        D5CF    D5IOERR
D5CAPFINISH:
        MOV     BYTE PTR ES:[ST_CAPPAIR],0
        MOV     AL,[D5CAP]
        MOV     ES:[ST_LAST],AL
        MOV     BYTE PTR ES:[ST_PHASE],0
        MOV     BYTE PTR ES:[ST_NEXT],0
        CALL    SAVE
        D5CF    D5IOERR
; D5 IPL revisions differ only in block 0. Until the new stage and
; its directory size are published, a previous D5 IPL falls back to DOS.
D5NEWSTAGE:
        CALL    D5STAGEFILE
        D5CF    D5IOERR
        CALL    D5PUBLISH
        D5CF    D5IOERR
        MOV     ES,[BMSTSEG]
        MOV     BYTE PTR ES:[ST_VER],STATEVER
        JMP     SAVE
D5STAGEFILE:
        MOV     AX,[D5STAGE]
        CALL    D5WRITESTAGE
        D5CF    D5IOERR
        MOV     AX,[D5STAGESLOT]
        CALL    GETSLOT
        D5CF    D5IOERR
        MOV     WORD PTR ES:[DI+28],MENUSIZE
        JMP     PUTSLOT
D5PUBLISH:
        MOV     ES,[WORKSEG]
        XOR     DI,DI
        MOV     SI,OFFSET HDBOOTCODE
        MOV     CX,512
        REP     MOVSW
        MOV     BYTE PTR ES:[255],1
        XOR     AX,AX
        CMP     [D5UPGRADE],0
        JNE     D5PUBLISH0
        MOV     BX,2
        MOV     BP,512
        CALL    WRITEBLOCK
        D5CF    D5IOERR
        INC     BX
        ADD     BP,256
        CALL    WRITEBLOCK
        D5CF    D5IOERR
D5PUBLISH0:XOR  BX,BX
        XOR     BP,BP
        CALL    WRITEBLOCK
        D5CF    D5IOERR
        RET
D5STORESEC:
        XOR     BX,BX
D5WBLK: CALL    WRITEBLOCK
        JC      D5WEND
        ADD     BP,256
        INC     BX
        CMP     BX,4
        JB      D5WBLK
        CLC
D5WEND: RET

; Maintenance switches don't transfer DOS files or alter the IPL.
D5COMMAND:
        CALL    D5SETUP
        D5CF    D5PASS
        CMP     [D5OP],'L'
        JE      D5LIST
        CMP     [D5IPL],3
        D5NZ    D5ERROR
        CMP     [D5OP],'D'
        D5Z     D5REMOVE
        CMP     [D5OP],'C'
        D5Z     D5CANCEL
        JMP     D5PREP
D5LIST: CMP     [COUNT],0
        JNE     D5LSTART
        MOV     DX,OFFSET D5NONE
        JMP     D5SHOW
D5LSTART:
        CMP     BYTE PTR ES:[ST_PHASE],0
        JE      D5LFIRST
        MOV     DX,OFFSET D5WAIT
        CALL    PUTS
D5LFIRST:MOV    DX,OFFSET D5PAIRHDR
        CALL    PUTS
        MOV     DX,OFFSET D5PAIRDOS
        CALL    PUTS
        MOV     [SETID],0
        CALL    D5LPAIR
        MOV     [SETID],1
D5LENTRY:MOV    BL,[SETID]
        MOV     ES,[BMSTSEG]
        CALL    ENTRY
        CMP     BYTE PTR ES:[DI],0
        JE      D5LNEXT
        MOV     DL,[SETID]
        ADD     DL,'0'
        MOV     AH,02H
        INT     21H
        MOV     DL,' '
        MOV     AH,02H
        INT     21H
D5LCHAR:MOV     ES,[BMSTSEG]
        MOV     DL,ES:[DI]
        OR      DL,DL
        JZ      D5LEND
        INC     DI
        MOV     AH,02H
        INT     21H
        JMP     SHORT D5LCHAR
D5LEND: CALL    CRLF
        CALL    D5LPAIR
D5LNEXT:INC     [SETID]
        CMP     [SETID],MAXID
        JBE     D5LENTRY
        CLC
        RET
D5SHOW: CALL    PUTS
        CLC
        RET
D5LPAIR:MOV     ES,[BMSTSEG]
        CMP     BYTE PTR ES:[ST_PHASE],3
        JE      D5LPAIRRET      ;In-flight foreign capture has no stable names.
        MOV     AL,[SETID]
        MOV     DX,OFFSET D5PAIRREAL
        CMP     AL,ES:[ST_OWNER]
        JE      D5LPAIRSHOW
        ADD     AL,'0'
        MOV     [D5PAIRPARK+7],AL
        MOV     [D5PAIRPARK+21],AL
        MOV     DX,OFFSET D5PAIRPARK
D5LPAIRSHOW:JMP PUTS
D5LPAIRRET:RET
D5REMOVE:
        CMP     BYTE PTR ES:[ST_PHASE],0
        D5NZ    D5ERROR
        MOV     BL,[D5DELETE]
        CALL    IDOK
        D5CF    D5ERROR
        CMP     BL,ES:[ST_OWNER]
        JNE     D5UNREG
        CMP     BYTE PTR ES:[ST_VER],STATEVER
        D5NZ    D5ERROR
        MOV     BYTE PTR ES:[ST_NEXT],0
        CALL    PSOWNERS
        CALL    PSPLAN
        D5CF    D5ERROR
        MOV     BYTE PTR ES:[ST_PHASE],4
        CALL    SAVE
        D5CF    D5IOERR
        CALL    RECOVERDEL
        JMP     SHORT D5DELRESULT
D5UNREG:CALL    UNREGISTER
D5DELRESULT:
        D5CF    D5IOERR
        MOV     DX,OFFSET D5DELDONE
        JMP     D5SHOW

D5PREP: CMP     BYTE PTR ES:[ST_OWNER],0
        D5NZ    D5NEEDOS
        CALL    RFRECOVER
        D5CF    D5PASS
        MOV     ES,[BMSTSEG]
        CALL    RFSLOTS
        D5CF    D5PASS
        CMP     BYTE PTR ES:[ST_PHASE],2
        D5Z     D5VALIDP
        CMP     BYTE PTR ES:[ST_PHASE],0
        D5NZ    D5ERROR
        CALL    D5AVAILABLE
        D5CF    D5NOROOM
        CALL    CHECKFILES
        D5CF    D5ERROR
        ; Choose deleted/zero slots; never write beyond the root or
        ; expose a nonzero slot after replacing a directory terminator.
        XOR     BX,BX
        MOV     [D5PAR],BX
D5FREE: MOV     AX,[D5PAR]
        PUSH    BX
        PUSH    ES
        CALL    GETSLOT
        JNC     D5FREEOK
        POP     ES
        POP     BX
        JMP     D5NOROOM
D5FREEOK:MOV    DL,ES:[DI]
        POP     ES
        POP     BX
        OR      DL,DL
        JNZ     D5FREEDEL
        MOV     [D5END],1
        JMP     SHORT D5FREESAVE
D5FREEDEL:CMP   [D5END],0
        D5NZ    D5ERROR
        CMP     DL,0E5H
        JNE     D5FREENEXT
D5FREESAVE:MOV  AX,[D5PAR]
        MOV     ES:[ST_PREP+BX],AX
        ADD     BX,2
        CMP     BX,8
        JE      D5TERM
D5FREENEXT:INC  [D5PAR]
        JMP     SHORT D5FREE
D5TERM: CMP     [D5END],0
        JE      D5PREPMARK
        INC     AX
        MOV     BX,[DATA0]
        SUB     BX,[ROOT]
        MOV     CL,5
        SHL     BX,CL
        CMP     AX,BX
        JAE     D5PREPMARK      ;At the filesystem's final slot.
        PUSH    ES
        CALL    GETSLOT
        JC      D5TERMBAD
        CMP     BYTE PTR ES:[DI],0
        JE      D5TERMEND
D5TERMBAD:POP   ES
        JMP     D5ERROR
D5TERMEND:POP   ES
D5PREPMARK:MOV  BYTE PTR ES:[ST_PHASE],2
        CALL    SAVE
        D5CF    D5IOERR
        JMP     SHORT D5VALIDP
D5CANCEL:
        CMP     BYTE PTR ES:[ST_PHASE],2
        D5NZ    D5ERROR
D5VALIDP:MOV    [FILEID],0
D5PRECHECK:
        PUSH    ES
        CALL    D5EMPTY
        POP     ES
        D5CF    D5ERROR
        INC     [FILEID]
        CMP     [FILEID],4
        JB      D5PRECHECK
        MOV     [FILEID],0
D5PREWRITE:
        PUSH    ES
        CALL    D5EMPTY
        JC      D5PREERR
        CMP     [D5OP],'C'
        JE      D5ERASE
        OR      DL,DL
        JNZ     D5PNEXT
        PUSH    DI
        MOV     SI,[REALPTR]
        MOV     CX,11
        REP     MOVSB
        MOV     DL,[ATTR]
        MOV     ES:[DI],DL
        INC     DI
        PUSH    AX
        XOR     AX,AX
        MOV     CX,10
        REP     STOSW
        POP     AX
        POP     DI
        JMP     SHORT D5PSTORE
D5ERASE:OR      DL,DL
        JZ      D5PNEXT
        MOV     BYTE PTR ES:[DI],0E5H
D5PSTORE:CALL   PUTSLOT
        JC      D5PREERR
D5PNEXT:POP     ES
        INC     [FILEID]
        CMP     [FILEID],4
        JB      D5PREWRITE
        MOV     DX,OFFSET D5PREPDONE
        CMP     [D5OP],'C'
        JNE     D5PSHOW
        MOV     BYTE PTR ES:[ST_PHASE],0
        CALL    SAVE
        D5CF    D5IOERR
        MOV     DX,OFFSET D5CANDONE
D5PSHOW:JMP     D5SHOW
D5PREERR:POP    ES
        JMP     D5ERROR

; Validate one recorded placeholder or an available slot.
; Returns AX = LBA, ES:DI = directory entry, DL = 1 if present.
D5EMPTY:CALL    NAMES
        MOV     SI,[REALPTR]
        CALL    FIND
        JC      D5EMPTYBAD
        XOR     BH,BH
        MOV     BL,[FILEID]
        SHL     BX,1
        MOV     BX,ES:[ST_PREP+BX]
        XOR     DX,DX
        CMP     AX,0FFFFH
        JE      D5ESLOT
        CMP     AX,BX
        JNE     D5EMPTYBAD
        MOV     DL,[ATTR]
        CMP     DL,[MATCH+11]
        JNE     D5EMPTYBAD
        MOV     DX,WORD PTR [MATCH+26]
        OR      DX,WORD PTR [MATCH+28]
        OR      DX,WORD PTR [MATCH+30]
        JNZ     D5EMPTYBAD
        INC     DL
D5ESLOT:MOV     AX,BX
        CALL    GETSLOT
        JC      D5EMPTYBAD
        OR      DL,DL
        JNZ     D5EMPTYOK
        CMP     BYTE PTR ES:[DI],0
        JE      D5EMPTYOK
        CMP     BYTE PTR ES:[DI],0E5H
        JNE     D5EMPTYBAD
D5EMPTYOK:CLC
        RET
D5EMPTYBAD:STC
        RET

        INCLUDE VAMENUJR.INC
        INCLUDE VAMENUBIN.INC
