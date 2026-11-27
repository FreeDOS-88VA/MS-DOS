; SPDX-License-Identifier: MIT
; SASI SYS: preflight, claim unreferenced chains, fill, publish, release.
; No loader or on-disk redo state is involved.
RFNAMES DB      'IO      SYS','MSDOS   SYS','COMMAND COM'
RFSEG   DW      0
RFSCAN  DW      2
RFREC   DW      0
RFIDX   DW      0
RFLEFT  DW      0
RFBYTES DW      0
RFCLIDX DW      0
RFLBA   DW      0
RFDATA  DW      0
RFFAT   DW      0
RFLINK  DW      0
RFFPOS  DW      0
RFKEEP  DW      0
RFSRC   DW      NSYS DUP (0)
RFSLOT  DW      NSYS DUP (0FFFFH)
RFEND   DW      0
RFMAX   DW      0
RFVACAT DW      0
RFPAIR  DW      0
RFROOTMAX DW    0
RFSAVEDEND DW   0
RFGAP   DW      0FFFFH
RFDAMAGED DB    0
RFCAPNEW DB     0
RFFIND2 DB      0
RFDUP   DW      0FFFFH
RFDUPIDX DW     0FFFFH
RFDUPALT DW     0FFFFH
RFDUPPAIR DW    0FFFFH
RFMVSRC DW      0FFFFH
RFMVDST DW      0
RFMVCUR DW      0
RFMVSEC DW      0
RFMVFROM DW     0
RFMVTO  DW      0
RF_FIRST EQU    0
RF_LEN  EQU     66
RF_NEW  EQU     0               ;32-byte replacement dirent.
RF_OLD  EQU     32              ;8 words + terminator.
RF_ALLOC EQU    50              ;8 words, padded with zeros.
RF_MOVE EQU     NSYS*RF_LEN
RF_LIMIT EQU    RF_MOVE+RF_LEN

RFERROR:MOV     DX,OFFSET RFMSG
        STC
        RET

RFFIND: MOV     SI,OFFSET RFNAMES
        MOV     BX,[RFIDX]
        MOV     AL,11
        MUL     BL
        ADD     SI,AX
        MOV     [RFDUP],0FFFFH
        MOV     [RFFIND2],1
        CALL    FIND
        MOV     [RFFIND2],0
        RET

RFNEW:  CALL    RFAUDIT
        D5CF    D5PASS
        ; Reserve the existing capture path's slots and clusters in the
        ; plan so capture itself cannot collide with the new DOS files.
        CMP     [D5CAP],0
        JE      RFCAPPLANNED
        CMP     [D5RESUME],0
        JNE     RFCAPPLANNED
        CMP     [D5PRESENT],0
        JNE     RFCAPPLANNED
        CALL    D5JRPAIR
        D5CF    D5NOROOM
        CALL    D5JRCLUSTERS
        D5CF    D5NOROOM
        MOV     ES,[RFSEG]
        MOV     BX,[JRCL]
        MOV     SI,[JRCL+2]
        MOV     AL,ES:[BX+RF_MAP]
        OR      AL,ES:[SI+RF_MAP]
        D5NZ    RFERROR
        MOV     [RFCAPNEW],1
RFCAPPLANNED:
        CALL    RFPICKSLOTS
        D5CF    D5PASS
        MOV     ES,[RFSEG]
        XOR     DI,DI
        XOR     AX,AX
        MOV     CX,RF_LIMIT/2
        REP     STOSW
        MOV     [RFIDX],0
        MOV     [RFREC],RF_FIRST
RFPREP: MOV     BX,[RFIDX]
        SHL     BX,1
        CALL    HDLOADONE
        D5CF    D5PASS
        MOV     BX,[RFIDX]
        SHL     BX,1
        MOV     AX,[RFSRC+BX]
        CMP     AX,0FFFFH
        JE      RFPREPSLOT
        CALL    RFGETMATCH
        D5CF    RFERROR
        MOV     BX,[RFIDX]
        SHL     BX,1
        MOV     AX,[RFSRC+BX]
RFPREPSLOT:
        MOV     ES,[RFSEG]
        MOV     DI,[RFREC]
        CMP     AX,0FFFFH
        JE      RFMISSING
        TEST    BYTE PTR [MATCH+11],18H
        D5NZ    RFERROR
        PUSH    DI
        ADD     DI,RF_NEW
        MOV     SI,OFFSET MATCH
        MOV     CX,16
        REP     MOVSW
        POP     DI
        CALL    RFSAVEOLD
        JC      RFBADOLD
        JMP     SHORT RFMETA
RFMISSING:
        ADD     DI,RF_NEW
        MOV     AX,[RFIDX]
        MOV     CL,11
        MUL     CL
        MOV     SI,OFFSET RFNAMES
        ADD     SI,AX
        MOV     CX,11
        REP     MOVSB
        JMP     SHORT RFMETA
RFBADOLD:
        MOV     [RFDAMAGED],1  ;Do not free any part of an untrusted chain.
RFMETA: MOV     ES,[RFSEG]
        MOV     DI,[RFREC]
        MOV     WORD PTR ES:[DI+RF_NEW+30],0
        MOV     BX,[RFIDX]
        SHL     BX,1
        MOV     AX,[SYSTIME+BX]
        MOV     ES:[DI+RF_NEW+22],AX
        MOV     AX,[SYSDATE+BX]
        MOV     ES:[DI+RF_NEW+24],AX
        MOV     AX,[SYSATTR+BX]
        MOV     ES:[DI+RF_NEW+11],AL
        MOV     AX,[SYSSIZE+BX]
        MOV     ES:[DI+RF_NEW+28],AX
        OR      AX,AX
        D5Z     RFERROR
        DEC     AX
        XOR     DX,DX
        DIV     [BMCLBYTES]
        INC     AX
        MOV     [RFLEFT],AX
        CALL    RFALLOCATE
        D5CF    D5PASS
        INC     [RFIDX]
        ADD     [RFREC],RF_LEN
        CMP     [RFIDX],NSYS
        JAE     RFTESTPLAN
        JMP     RFPREP
RFTESTPLAN:
        CALL    RFPLANMOVE
        D5CF    D5PASS
        CALL    RFDUPCHECK
        D5CF    RFERROR
        CALL    RFCHECKOLD
        ; All refusal checks above. Synchronize the recognized one-entry
        ; mirror lag before making any further allocations.
        MOV     BX,[RFMIRROR]
        OR      BX,BX
        JZ      RFSTART
        MOV     DX,[RFMLINK]
        CALL    RFFATSET
        D5CF    RFERROR
RFSTART:CALL    D5CAPTURE
        D5CF    D5PASS
        CALL    RFCLAIMFAT
        D5CF    D5PASS
        MOV     AX,[RFGAP]
        CMP     AX,0FFFFH
        JE      RFSTARTMOVE
        CALL    RFDELSLOT
        D5CF    RFERROR
RFSTARTMOVE:
        CALL    RFCOPYMOVE
        D5CF    RFERROR
        MOV     AX,[RFDUPALT]
        CMP     AX,0FFFFH
        JE      RFNODUPRETIRE
        CALL    RFDELSLOT
        D5CF    RFERROR
RFNODUPRETIRE:
        MOV     [RFIDX],0
        MOV     [RFREC],RF_FIRST
RFCOPYFILE:
        MOV     BX,[RFIDX]
        SHL     BX,1
        CALL    HDLOADONE
        D5CF    D5PASS
        MOV     ES,[RFSEG]
        MOV     DI,[RFREC]
        MOV     BX,[RFIDX]
        SHL     BX,1
        MOV     AX,[SYSSIZE+BX]
        CMP     AX,ES:[DI+RF_NEW+28]
        D5NZ    RFERROR
        MOV     [RFLEFT],AX
        MOV     [RFDATA],0
        ADD     DI,RF_ALLOC
        MOV     [RFCLIDX],DI
RFSTAGE:MOV     ES,[RFSEG]
        MOV     DI,[RFCLIDX]
        MOV     AX,ES:[DI]
        ADD     [RFCLIDX],2
        CALL    D5JRLBA
        MOV     [RFLBA],AX
        MOV     AX,[D5SPC]
        MOV     [RFBYTES],AX    ;Sectors left in the current cluster.
RFSECT: MOV     ES,[BMBUFSEG]
        XOR     DI,DI
        XOR     AX,AX
        MOV     CX,512
        REP     STOSW
        XOR     DI,DI
        MOV     CX,[RFLEFT]
        CMP     CX,1024
        JBE     RFCOPY
        MOV     CX,1024
RFCOPY: SUB     [RFLEFT],CX
        MOV     SI,[RFDATA]
        ADD     [RFDATA],CX
        MOV     BX,[RFIDX]
        SHL     BX,1
        PUSH    DS
        MOV     DS,[SYSSEG+BX]
        REP     MOVSB
        POP     DS
        MOV     AX,[RFLBA]
        XOR     BP,BP
        CALL    D5STORESEC
        D5CF    RFERROR
        CMP     [RFLEFT],0
        JE      RFSTAGED
        INC     [RFLBA]
        DEC     [RFBYTES]
        JNZ     RFSECT
        JMP     RFSTAGE
RFSTAGED:
        INC     [RFIDX]
        ADD     [RFREC],RF_LEN
        CMP     [RFIDX],NSYS
        JAE     RFFINAL
        JMP     RFCOPYFILE
RFFINAL:CALL    RFROOTS
        D5CF    RFERROR
        CALL    RFRELEASE
        D5CF    D5PASS
        CMP     [RFDAMAGED],0
        JE      RFREADY
        MOV     DX,OFFSET RFLEFTMSG
        CALL    PUTS
RFREADY:CLC
        RET

RFPICKSLOTS:
        MOV     [RFIDX],0
RFSLOTLOOK:
        CALL    RFFIND
        D5CF    RFERROR
        MOV     [RFEND],BX
        MOV     BX,[RFIDX]
        SHL     BX,1
        MOV     [RFSRC+BX],AX
        MOV     [RFSLOT+BX],AX
        CMP     [RFDUP],0FFFFH
        JE      RFSLOTNEXT
        CMP     BX,4
        D5Z     RFERROR
        CMP     [RFDUPIDX],0FFFFH
        D5NZ    RFERROR
        MOV     [RFDUPIDX],BX
        MOV     AX,[RFDUP]
        MOV     [RFDUPPAIR],AX
RFSLOTNEXT:
        INC     [RFIDX]
        CMP     [RFIDX],NSYS
        JB      RFSLOTLOOK
        MOV     AX,[DATA0]
        SUB     AX,[ROOT]
        MOV     CL,5
        SHL     AX,CL
        MOV     [RFROOTMAX],AX
        CMP     [RFCAPNEW],0
        JE      RFSLOTCAPOK
        MOV     AX,[JRSLOT]
        ADD     AX,2
        CMP     AX,[RFEND]
        JBE     RFSLOTCAPOK
        MOV     [RFEND],AX
RFSLOTCAPOK:
        CALL    RFDUPOPT
        D5CF    RFERROR
        MOV     AX,[RFSLOT]
        MOV     DX,[RFSLOT+2]
        CMP     AX,0FFFFH
        JE      RFWANTIO
        CMP     DX,0FFFFH
        JE      RFWANTDOS
        XOR     AX,DX
        AND     AX,0FFF8H
        D5Z     RFWANTCMD
        MOV     AX,DX
        CALL    RFVACBLOCK
        D5CF    RFERROR
        CMP     AX,0FFFFH
        JNE     RFGOTIO
        MOV     AX,[RFSLOT]
        JMP     SHORT RFWANTDOS
RFWANTIO:
        MOV     AX,DX
        CMP     AX,0FFFFH
        JE      RFWANTPAIR
        CALL    RFVACBLOCK
        D5CF    RFERROR
        CMP     AX,0FFFFH
        JE      RFWANTPAIR
RFGOTIO:MOV     [RFSLOT],AX
        JMP     RFWANTCMD
RFWANTDOS:
        CALL    RFVACBLOCK
        D5CF    RFERROR
        CMP     AX,0FFFFH
        JNE     RFGOTDOS
        CMP     [RFSRC+2],0FFFFH
        D5NZ    RFNOROOM
        JMP     SHORT RFWANTPAIR
RFGOTDOS:MOV    [RFSLOT+2],AX
        JMP     SHORT RFWANTCMD
RFWANTPAIR:
        MOV     [RFSLOT],0FFFFH
        MOV     [RFSLOT+2],0FFFFH
        MOV     [RFPAIR],0
RFPAIRLOOP:
        MOV     AX,[RFPAIR]
        CMP     AX,[RFROOTMAX]
        JAE     RFSLOTROOM
        MOV     DX,[RFEND]
        MOV     [RFSAVEDEND],DX
        CALL    RFVACBLOCK
        D5CF    RFERROR
        CMP     AX,0FFFFH
        JE      RFPAIRNEXT
        MOV     [RFSLOT],AX
        CALL    RFVACBLOCK
        D5CF    RFERROR
        CMP     AX,0FFFFH
        JNE     RFPAIRFOUND
        MOV     AX,[RFSAVEDEND]
        CMP     AX,[RFSLOT]
        JNE     RFPAIRRESTORE
        ; If the end marker is the block's only vacancy and stands in
        ; its last slot, consume it as a deleted entry to use the next block.
        MOV     DX,[RFPAIR]
        ADD     DX,7
        CMP     AX,DX
        JNE     RFPAIRRESTORE
        MOV     [RFGAP],AX
        INC     AX
RFPAIRRESTORE:
        MOV     [RFSLOT],0FFFFH
        MOV     [RFEND],AX
RFPAIRNEXT:
        ADD     [RFPAIR],8
        JMP     SHORT RFPAIRLOOP
RFSLOTROOM:JMP  RFNOROOM
RFPAIRFOUND:
        MOV     [RFSLOT+2],AX
RFWANTCMD:
        ; If a sole surviving kernel must move into a newly selected
        ; block, publish it into the earlier of the two vacancies.
        MOV     AX,[RFSRC]
        MOV     DX,[RFSRC+2]
        CMP     AX,0FFFFH
        JE      RFCMDIOABSENT
        CMP     DX,0FFFFH
        JNE     RFCMDLOOK
        CMP     AX,[RFSLOT]
        JE      RFCMDLOOK
        MOV     AX,[RFSLOT]
        CMP     AX,[RFSLOT+2]
        JBE     RFCMDLOOK
        JMP     SHORT RFCMDSWAP
RFCMDIOABSENT:
        CMP     DX,0FFFFH
        JE      RFCMDLOOK
        CMP     DX,[RFSLOT+2]
        JE      RFCMDLOOK
        MOV     AX,[RFSLOT]
        CMP     AX,[RFSLOT+2]
        JAE     RFCMDLOOK
RFCMDSWAP:
        XCHG    AX,[RFSLOT+2]
        MOV     [RFSLOT],AX
RFCMDLOOK:
        CMP     [RFSLOT+4],0FFFFH
        JNE     RFSLOTDONE
        CALL    RFVACALL
        D5CF    RFERROR
        CMP     AX,0FFFFH
        D5Z     D5NOROOM
        MOV     [RFSLOT+4],AX
RFSLOTDONE:
        CLC
        RET
RFNOROOM:
        MOV     DX,OFFSET RFROOM
        CMP     [D5CAP],0
        JE      RFSLOTREFUSE
        MOV     DX,OFFSET RFCAPWARN
RFSLOTREFUSE:
        STC
        RET

RFVACBLOCK:
        AND     AX,0FFF8H
        MOV     DX,AX
        ADD     DX,8
        JMP     SHORT RFVAC
RFVACALL:
        XOR     AX,AX
        MOV     DX,[RFROOTMAX]
RFVAC:  MOV     [RFVACAT],AX
        MOV     [RFMAX],DX
RFVACLOOP:
        MOV     AX,[RFVACAT]
        CMP     AX,[RFMAX]
        JAE     RFVACNONE
        CMP     AX,[RFEND]
        JA      RFVACNONE
        CMP     AX,[RFSLOT]
        JE      RFVACNEXT
        CMP     AX,[RFSLOT+2]
        JE      RFVACNEXT
        CMP     AX,[RFSLOT+4]
        JE      RFVACNEXT
        CMP     [RFCAPNEW],0
        JE      RFVACGET
        MOV     BX,[JRSLOT]
        CMP     AX,BX
        JE      RFVACNEXT
        INC     BX
        CMP     AX,BX
        JE      RFVACNEXT
RFVACGET:
        CALL    GETSLOT
        JC      RFVACRET
        MOV     AX,[RFVACAT]
        CMP     AX,[RFEND]
        JE      RFVACTERM
        CMP     BYTE PTR ES:[DI],0E5H
        JE      RFVACOK
RFVACNEXT:
        INC     [RFVACAT]
        JMP     SHORT RFVACLOOP
RFVACTERM:
        CMP     BYTE PTR ES:[DI],0
        JNE     RFVACNONE
        INC     AX
        CMP     AX,[RFROOTMAX]
        JAE     RFVACEXTEND
        CALL    GETSLOT
        JC      RFVACRET
        CMP     BYTE PTR ES:[DI],0
        JNE     RFVACNONE
RFVACEXTEND:
        INC     [RFEND]
        MOV     AX,[RFVACAT]
RFVACOK:CLC
RFVACRET:RET
RFVACNONE:
        MOV     AX,0FFFFH
        CLC
        RET

RFDELSLOT:
        CALL    GETSLOT
        D5CF    RFERROR
        MOV     BYTE PTR ES:[DI],0E5H
        JMP     PUTSLOT

RFROOTS:MOV     AX,[RFSLOT]
        MOV     BX,AX
        XOR     BX,[RFSLOT+2]
        AND     BX,0FFF8H
        D5NZ    RFERROR
        XOR     AX,[RFSLOT+4]
        TEST    AX,0FFF8H
        JZ      RFROOTALL
        ; If only COMMAND is missing and in a different block, install
        ; it before switching the kernels; they are already visible.
        CMP     [RFSRC+4],0FFFFH
        JNE     RFROOTLATER
        CMP     [RFSRC],0FFFFH
        JE      RFROOTLATER
        CMP     [RFSRC+2],0FFFFH
        JE      RFROOTLATER
        CALL    RFROOTCMD
        D5CF    RFERROR
        XOR     DX,DX
        JMP     SHORT RFROOTPAIR
RFROOTLATER:
        MOV     DX,1
        JMP     SHORT RFROOTPAIR
RFROOTALL:
        MOV     DX,2
RFROOTPAIR:
        MOV     AX,[RFSLOT]
        CALL    GETSLOT
        D5CF    RFERROR
        MOV     SI,RF_NEW
        CALL    RFDIRENT
        MOV     DI,[RFSLOT+2]
        MOV     SI,RF_LEN+RF_NEW
        CALL    RFROOTENT
        CMP     DX,2
        JNE     RFROOTWRITE
        MOV     DI,[RFSLOT+4]
        MOV     SI,2*RF_LEN+RF_NEW
        CALL    RFROOTENT
RFROOTWRITE:
        CALL    PUTSLOT
        D5CF    RFERROR
        CMP     DX,1
        JE      RFROOTCMD
        CLC
        RET
RFROOTCMD:
        MOV     AX,[RFSLOT+4]
        CALL    GETSLOT
        D5CF    RFERROR
        MOV     SI,2*RF_LEN+RF_NEW
        CALL    RFDIRENT
        JMP     PUTSLOT
RFROOTENT:
        AND     DI,31
        MOV     CL,5
        SHL     DI,CL
        JMP     RFDIRENT
RFRELEASE:
        MOV     [RFREC],RF_FIRST
RFRELFILE:
        MOV     BX,[RFREC]
        ADD     BX,RF_OLD
        MOV     [RFCLIDX],BX
RFRELEASE1:
        MOV     ES,[RFSEG]
        MOV     SI,[RFCLIDX]
        MOV     BX,ES:[SI]
        OR      BX,BX
        JZ      RFRELDONE
        XOR     DX,DX
        CALL    RFFATSET
        D5CF    RFERROR
        ADD     [RFCLIDX],2
        JMP     SHORT RFRELEASE1
RFRELDONE:
        ADD     [RFREC],RF_LEN
        CMP     [RFREC],RF_LIMIT
        JB      RFRELFILE
        CLC
        RET

RFDIRENT:
        PUSH    DI
        PUSH    DS
        MOV     DS,[RFSEG]
        MOV     CX,16
        REP     MOVSW
        POP     DS
        POP     DI
        RET

RFFATERR:STC
RFFATRET:RET

; Replace the chosen FAT12 entry in both copies without disturbing the
; neighboring nibble. Split entries are excluded during preflight.
RFFATSET:
        CMP     BX,2
        JB      RFFATERR
        CMP     BX,[D5CLMAX]
        JA      RFFATERR
        MOV     [RFLINK],DX
        MOV     AX,BX
        SHR     AX,1
        ADD     AX,BX
        CMP     AL,0FFH
        JE      RFFATERR
        MOV     [RFFPOS],AX
        MOV     [RFKEEP],0F000H
        TEST    BL,1
        JZ      RFSETSTART
        MOV     [RFKEEP],000FH
        MOV     CL,4
        SHL     WORD PTR [RFLINK],CL
RFSETSTART:
        MOV     [RFFAT],1
        CALL    RFFATCOPY
        JNC     RFSETSECOND
        RET
RFSETSECOND:
        MOV     AX,[D5SPF]
        INC     AX
        MOV     [RFFAT],AX
RFFATCOPY:
        MOV     AX,[RFFPOS]
        MOV     DI,AX
        AND     DI,1023
        MOV     CL,10
        SHR     AX,CL
        ADD     AX,[RFFAT]
        MOV     ES,[BMBUFSEG]
        XOR     BP,BP
        CALL    READSEC
        JNC     RFSETWORD
        RET
RFSETWORD:MOV   DX,ES:[DI]
        AND     DX,[RFKEEP]
        OR      DX,[RFLINK]
        CMP     DX,ES:[DI]
        JE      RFBYTEOK
        MOV     ES:[DI],DX
        JMP     PUTSLOT
RFBYTEOK:CLC
        RET

; Save a structurally sound old chain, at most eight clusters.
RFSAVEOLD:
        CMP     WORD PTR [MATCH+30],0
        JNE     RFSAVEERR
        CALL    CHECKCHAIN
        JC      RFSAVEERR
        MOV     BX,WORD PTR [MATCH+26]
        MOV     SI,[RFREC]
        ADD     SI,RF_OLD
RFSAVELOOP:
        MOV     ES,[RFSEG]
        MOV     ES:[SI],BX
        ADD     SI,2
        MOV     ES,[RFFATSEG]
        CALL    RFGET
        MOV     BX,DX
        CMP     BX,0FF8H
        JB      RFSAVELOOP
        CLC
        RET
RFSAVEERR:STC
        RET

; Old entries with unexpected references or split FAT12 entries are
; intentionally not freed. We never garbage-collect anonymous chains.
RFCHECKOLD:
        MOV     ES,[RFSEG]
        MOV     DI,RF_OLD
RFCHECKNEXT:
        MOV     SI,DI
RFCHECKCL:
        MOV     BX,ES:[SI]
        OR      BX,BX
        JZ      RFCHECKDONE
        CMP     BYTE PTR ES:[BX+RF_MAP],1
        JNE     RFCHECKKEEP
        MOV     AX,BX
        CALL    D5JRCLVALID
        JC      RFCHECKKEEP
        ADD     SI,2
        JMP     SHORT RFCHECKCL
RFCHECKKEEP:
        MOV     WORD PTR ES:[DI],0
        MOV     [RFDAMAGED],1
RFCHECKDONE:
        ADD     DI,RF_LEN
        CMP     DI,RF_MOVE+RF_OLD
        JB      RFCHECKNEXT
        JA      RFCHECKRETURN
        CMP     [RFDUPALT],0FFFFH
        JNE     RFCHECKNEXT
RFCHECKRETURN:
        RET

; AX = number of clusters, RFREC = record. No disk writes here.
RFALLOCATE:
        MOV     [RFLEFT],AX
        MOV     DI,[RFREC]
        ADD     DI,RF_ALLOC
        MOV     [RFCLIDX],DI
RFALLOCLOOP:
        CALL    RFFREE
        D5CF    D5PASS
        MOV     ES,[RFSEG]
        MOV     DI,[RFCLIDX]
        MOV     ES:[DI],AX
        ADD     [RFCLIDX],2
        DEC     [RFLEFT]
        JNZ     RFALLOCLOOP
        MOV     DI,[RFREC]
        MOV     AX,ES:[DI+RF_ALLOC]
        MOV     ES:[DI+RF_NEW+26],AX
        CLC
        RET

RFFREE: MOV     BX,[RFSCAN]
        CMP     BX,[D5CLMAX]
        JA      RFNOSPACE
        INC     [RFSCAN]
        CMP     BX,[RFMIRROR]
        JE      RFFREE
        CMP     [RFCAPNEW],0
        JE      RFFREECHECK
        CMP     BX,[JRCL]
        JE      RFFREE
        CMP     BX,[JRCL+2]
        JE      RFFREE
RFFREECHECK:
        MOV     AX,BX
        CALL    D5JRCLVALID
        JC      RFFREE
        MOV     ES,[RFSEG]
        CMP     BYTE PTR ES:[BX+RF_MAP],0
        JNE     RFFREE
        MOV     ES,[RFFATSEG]
        CALL    RFGET
        OR      DX,DX
        JNZ     RFFREE
        MOV     AX,BX
        RET
RFNOSPACE:
        MOV     DX,OFFSET RFSPACE
        STC
        RET

; Take the original entry and allocate an independent temporary chain.
; The slot planner moves at most one existing kernel.
RFPLANMOVE:
        XOR     BX,BX
RFMVLOOK:
        MOV     AX,[RFSRC+BX]
        CMP     AX,0FFFFH
        JE      RFMVNEXT
        CMP     AX,[RFSLOT+BX]
        JNE     RFMVFOUND
RFMVNEXT:
        ADD     BX,2
        CMP     BX,4
        JB      RFMVLOOK
        CLC
        RET
RFMVFOUND:
        CMP     [RFDUPALT],0FFFFH
        D5NZ    RFERROR
        MOV     [RFMVSRC],AX
        MOV     DX,[RFSLOT+BX]
        MOV     [RFMVDST],DX
        CALL    RFGETMATCH
        D5CF    RFERROR
        MOV     ES,[RFSEG]
        MOV     SI,OFFSET MATCH
        MOV     DI,RF_MOVE+RF_NEW
        MOV     CX,16
        REP     MOVSW
        MOV     [RFREC],RF_MOVE
        CALL    RFSAVEOLD
        D5CF    RFERROR
        MOV     AX,WORD PTR [MATCH+28]
        DEC     AX
        XOR     DX,DX
        DIV     [BMCLBYTES]
        INC     AX
        JMP     RFALLOCATE

RFCOPYMOVE:
        CMP     [RFMVSRC],0FFFFH
        JE      RFMVDONE
        MOV     [RFMVCUR],0
RFMVCOPY:
        MOV     ES,[RFSEG]
        MOV     SI,[RFMVCUR]
        MOV     AX,ES:[SI+RF_MOVE+RF_OLD]
        OR      AX,AX
        JZ      RFMVPUBLISH
        CALL    D5JRLBA
        MOV     [RFMVFROM],AX
        MOV     AX,ES:[SI+RF_MOVE+RF_ALLOC]
        MOV     ES:[SI+RF_MOVE+RF_OLD],AX ;Release this copy after swap.
        CALL    D5JRLBA
        MOV     [RFMVTO],AX
        MOV     AX,[D5SPC]
        MOV     [RFMVSEC],AX
RFMVSECTOR:
        MOV     ES,[BMBUFSEG]
        XOR     BP,BP
        MOV     AX,[RFMVFROM]
        CALL    READSEC
        JC      RFMVDONE
        MOV     AX,[RFMVTO]
        CALL    D5STORESEC
        JC      RFMVDONE
        INC     [RFMVFROM]
        INC     [RFMVTO]
        DEC     [RFMVSEC]
        JNZ     RFMVSECTOR
        ADD     [RFMVCUR],2
        JMP     SHORT RFMVCOPY
RFMVPUBLISH:
        MOV     AX,[RFMVDST]
        CALL    GETSLOT
        JC      RFMVDONE
        MOV     SI,RF_MOVE+RF_NEW
        CALL    RFDIRENT
        CALL    PUTSLOT
        JC      RFMVDONE
        MOV     AX,[RFMVSRC]
        JMP     RFDELSLOT
RFMVDONE:
        RET

; A cut between the two relocation directory writes may leave a duplicate.
; Pick the copy adjacent to its partner (or a vacancy) and verify that
; discarding the other entry would not discard any distinct file bytes.
RFDUPOPT:
        MOV     BX,[RFDUPIDX]
        CMP     BX,0FFFFH
        JE      RFDUPOK
        MOV     AX,[RFSRC+BX]
        MOV     [RFDUPALT],AX
        XOR     BX,2
        MOV     DX,[RFSRC+BX]
        CMP     DX,0FFFFH
        JE      RFDUPOPTVAC
        XOR     DX,AX
        TEST    DX,0FFF8H
        JZ      RFDUPFIRST
        JMP     SHORT RFDUPSECOND
RFDUPOPTVAC:
        MOV     BX,[RFEND]
        PUSH    BX
        CALL    RFVACBLOCK
        POP     [RFEND]
        JC      RFDUPRET
        CMP     AX,0FFFFH
        JNE     RFDUPFIRST
RFDUPSECOND:
        MOV     BX,[RFDUPIDX]
        MOV     AX,[RFDUPPAIR]
        MOV     [RFSLOT+BX],AX
        MOV     [RFSRC+BX],AX
        CLC
        RET
RFDUPFIRST:
        MOV     AX,[RFDUPPAIR]
        MOV     [RFDUPALT],AX
RFDUPOK:CLC
RFDUPRET:RET

RFGETMATCH:
        CALL    GETSLOT
        JC      RFDUPRET
        PUSH    DS
        PUSH    ES
        POP     DS
        MOV     SI,DI
        PUSH    CS
        POP     ES
        MOV     DI,OFFSET MATCH
        MOV     CX,16
        REP     MOVSW
        POP     DS
        RET

RFDUPCHECK:
        MOV     AX,[RFDUPALT]
        CMP     AX,0FFFFH
        JE      RFDUPOK
        CALL    RFGETMATCH
        D5CF    RFERROR
        MOV     ES,[RFSEG]
        MOV     SI,OFFSET MATCH
        MOV     DI,RF_MOVE+RF_NEW
        MOV     CX,16
        REP     MOVSW
        MOV     [RFREC],RF_MOVE
        CALL    RFSAVEOLD
        D5CF    RFERROR
        MOV     BX,[RFDUPIDX]
        MOV     AX,[RFSRC+BX]
        CALL    RFGETMATCH
        D5CF    RFERROR
        MOV     ES,[RFSEG]
        MOV     SI,OFFSET MATCH
        MOV     DI,RF_MOVE+RF_NEW
        MOV     CX,26
        REPE    CMPSB
        D5NZ    RFERROR
        ADD     SI,2
        ADD     DI,2
        MOV     CX,4
        REPE    CMPSB
        D5NZ    RFERROR
        MOV     BX,WORD PTR [MATCH+26]
        CMP     BX,ES:[RF_MOVE+RF_OLD]
        D5Z     RFERROR
        MOV     AX,[RFDUPIDX]
        MOV     CL,RF_LEN/2
        MUL     CL
        ADD     AX,RF_OLD
        MOV     [RFMVCUR],AX
        MOV     [RFCLIDX],RF_MOVE+RF_OLD
RFDUPCL:
        MOV     ES,[RFSEG]
        MOV     SI,[RFCLIDX]
        MOV     AX,ES:[SI]
        OR      AX,AX
        JZ      RFDUPCLEAN
        CALL    D5JRLBA
        MOV     [RFMVFROM],AX
        MOV     SI,[RFMVCUR]
        MOV     AX,ES:[SI]
        OR      AX,AX
        D5Z     RFERROR
        CALL    D5JRLBA
        MOV     [RFMVTO],AX
        MOV     AX,[D5SPC]
        MOV     [RFMVSEC],AX
RFDUPSEC:
        MOV     ES,[HDSTAGE]
        XOR     BP,BP
        MOV     AX,[RFMVFROM]
        CALL    READSEC
        D5CF    RFERROR
        MOV     ES,[BMBUFSEG]
        MOV     AX,[RFMVTO]
        CALL    READSEC
        D5CF    RFERROR
        PUSH    DS
        MOV     DS,[HDSTAGE]
        XOR     SI,SI
        XOR     DI,DI
        MOV     CX,512
        REPE    CMPSW
        POP     DS
        D5NZ    RFERROR
        INC     [RFMVFROM]
        INC     [RFMVTO]
        DEC     [RFMVSEC]
        JNZ     RFDUPSEC
        ADD     [RFCLIDX],2
        ADD     [RFMVCUR],2
        JMP     RFDUPCL
RFDUPCLEAN:
        CLC
        RET

; Claim from tail to head. Each cut leaves only complete lost chains,
; and the single entry being mirrored has no incoming reference.
RFCLAIMFAT:
        MOV     [RFREC],RF_FIRST
RFCLAIM:
        MOV     AX,[RFREC]
        ADD     AX,RF_ALLOC+14
        MOV     [RFCLIDX],AX
        MOV     DX,0FFFH
RFCLAIMCL:
        MOV     ES,[RFSEG]
        MOV     SI,[RFCLIDX]
        MOV     BX,ES:[SI]
        OR      BX,BX
        JZ      RFCLAIMNEXT
        PUSH    BX
        CALL    RFFATSET
        POP     DX
        D5CF    RFERROR
RFCLAIMNEXT:
        SUB     [RFCLIDX],2
        MOV     AX,[RFREC]
        ADD     AX,RF_ALLOC
        CMP     [RFCLIDX],AX
        JAE     RFCLAIMCL
        ADD     [RFREC],RF_LEN
        CMP     [RFREC],RF_LIMIT
        JB      RFCLAIM
        CLC
        RET
