; SPDX-License-Identifier: MIT
; SASI refresh planner and legacy VASYS.JRN replay (fix 1/2).
; New transactions use physical afterimages and replay before DOS boot.
RFNAME  DB      'VASYS   JRN'
RFNAMES DB      'IO      SYS','MSDOS   SYS','COMMAND COM'
RFSEG   DW      0
RFROOT  DW      0
RFCL    DW      0
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
RFSLOT  DW      NSYS+1 DUP (0FFFFH)
RFEND   DW      0
RFEND0  DW      0
RFMAX   DW      0
RFVACAT DW      0
RFPAIR  DW      0
RFROOTMAX DW    0
RFSAVEDEND DW   0
RFGAP   DW      0FFFFH
RFPROVREC DW    0
RFPROVIDX DW    0
RFPROVPREV DW   0
RFJHEAD DW      0
RFJNEXT DW      0
RFJCOUNT DW     0
RFJSIZE DW      0,0
RFJEXIST DB     0
RFDAMAGED DB    0
RFJTAG  EQU     3454H
; Journal layout, three records. Old and new FAT12 chain lists each have
; space for eight clusters (source and destination files < 64 KiB).
RF_SIG  EQU     0
RF_CRC  EQU     254
RF_FIRST EQU    4
RF_LEN  EQU     68
RF_SLOT EQU     0
RF_NEW  EQU     2               ;32-byte replacement dirent.
RF_OLD  EQU     34              ;8 words + terminator.
RF_ALLOC EQU    52              ;8 words (any unused words remain zero).

RFERROR:MOV     DX,OFFSET RFMSG
        STC
        RET

; Look for a plan left by an interrupted refresh. Only owned IPLs call
; this entry point. Journal removal is the last write in the operation.
RFRECOVER:
        MOV     SI,OFFSET RFNAME
        CALL    FIND
        D5CF    RFERROR
        CMP     AX,0FFFFH
        JE      RFNONE
        MOV     [RFROOT],AX
        CMP     WORD PTR [MATCH+12],RFJTAG
        JE      RFNONE         ;Owned staging file, not the fix-1/2 log.
        CMP     BYTE PTR [MATCH+11],7
        D5NZ    RFERROR
        CMP     WORD PTR [MATCH+12],5356H
        D5NZ    RFERROR
        MOV     AX,WORD PTR [MATCH+14]
        CMP     AX,2
        JB      RFERROR
        CMP     AX,[D5CLMAX]
        JBE     RFREAD
        JMP     RFERROR
RFREAD: MOV     [RFCL],AX
        MOV     AX,WORD PTR [MATCH+26]
        OR      AX,WORD PTR [MATCH+28]
        OR      AX,WORD PTR [MATCH+30]
        D5NZ    RFERROR
        MOV     AX,[RFCL]
        CALL    D5JRLBA
        MOV     ES,[RFSEG]
        XOR     BP,BP
        CALL    READSEC
        D5CF    RFERROR
        CMP     WORD PTR ES:[RF_SIG],3552H
        D5NZ    RFERROR
        CMP     WORD PTR ES:[RF_SIG+2],AX  ;Bind plan to its data LBA.
        D5NZ    RFERROR
        CALL    RFCRC
        CMP     DX,ES:[RF_CRC]
        D5NZ    RFERROR
        JMP     RFAPPLY
RFNONE: CLC
        RET

RFCRC:  PUSH    DS
        PUSH    ES
        POP     DS
        XOR     SI,SI
        MOV     CX,RF_CRC
        CALL    CRC16
        POP     DS
        RET

RFFIND: MOV     SI,OFFSET RFNAMES
        MOV     BX,[RFIDX]
        MOV     AL,11
        MUL     BL
        ADD     SI,AX
        JMP     FIND

RFNEW:  CALL    RFFATSAME
        D5CF    RFERROR
        CALL    RFPICKSLOTS
        D5CF    D5PASS
        MOV     ES,[RFSEG]
        XOR     DI,DI
        XOR     AX,AX
        MOV     CX,128
        REP     STOSW
        MOV     [RFIDX],0
        MOV     [RFREC],RF_FIRST
RFPREP: MOV     BX,[RFIDX]
        SHL     BX,1
        CALL    HDLOADONE
        D5CF    D5PASS
        CALL    RFFIND
        D5CF    RFERROR
        MOV     ES,[RFSEG]
        MOV     DI,[RFREC]
        MOV     BX,[RFIDX]
        SHL     BX,1
        MOV     DX,[RFSLOT+BX]
        MOV     ES:[DI+RF_SLOT],DX
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
        CMP     WORD PTR [MATCH+30],0
        JNE     RFBADOLD
        CALL    CHECKCHAIN
        JC      RFBADOLD
        ADD     DI,RF_OLD
        MOV     [RFCLIDX],DI
        MOV     BX,WORD PTR [MATCH+26]
RFOLD:  MOV     ES,[RFSEG]
        MOV     DI,[RFCLIDX]
        MOV     ES:[DI],BX
        ADD     [RFCLIDX],2
        XOR     AX,AX
        CALL    BMFATGET
        D5CF    RFERROR
        MOV     BX,DX
        CMP     DX,0FF8H
        JB      RFOLD
        JMP     SHORT RFMETA
RFMISSING:
        ADD     DI,RF_NEW
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
        ADD     [RFJCOUNT],AX
        ADD     DI,RF_ALLOC
        MOV     [RFCLIDX],DI
RFALLOCATE:
        CALL    RFNEXTCL
        D5CF    D5PASS
        MOV     ES,[RFSEG]
        MOV     DI,[RFCLIDX]
        MOV     ES:[DI],AX
        ADD     [RFCLIDX],2
        DEC     [RFLEFT]
        JNZ     RFALLOCATE
        MOV     DI,[RFREC]
        MOV     AX,ES:[DI+RF_ALLOC]
        MOV     ES:[DI+RF_NEW+26],AX
        INC     [RFIDX]
        ADD     [RFREC],RF_LEN
        CMP     [RFIDX],NSYS
        JAE     RFTESTPLAN
        JMP     RFPREP
RFTESTPLAN:
        CALL    RFPLANNEW
        D5CF    D5PASS
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
RFFINAL:CALL    TXBEGIN
        D5CF    D5PASS
        CALL    RFPUBLISH
        D5CF    D5PASS
        CALL    TXCOMMIT
        D5CF    D5PASS
        CMP     [RFDAMAGED],0
        JE      RFREADY
        MOV     DX,OFFSET RFLEFTMSG
        CALL    PUTS
RFREADY:CLC
        RET

; Select slots without changing the target. The two kernels share a
; block even if one or both entries have been deleted.
RFPICKSLOTS:
        MOV     [RFIDX],0
RFSLOTLOOK:
        CALL    RFFIND
        D5CF    RFERROR
        MOV     [RFEND],BX
        MOV     [RFEND0],BX
        MOV     BX,[RFIDX]
        SHL     BX,1
        MOV     [RFSRC+BX],AX
        MOV     [RFSLOT+BX],AX
        INC     [RFIDX]
        CMP     [RFIDX],NSYS
        JB      RFSLOTLOOK
        MOV     AX,[DATA0]
        SUB     AX,[ROOT]
        MOV     CL,5
        SHL     AX,CL
        MOV     [RFROOTMAX],AX
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
        D5NZ    RMROOM
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
RFSLOTROOM:JMP  RMROOM
RFPAIRFOUND:
        MOV     [RFSLOT+2],AX
RFWANTCMD:
        CMP     [RFSLOT+4],0FFFFH
        JNE     RFJLOCATE
        CALL    RFVACALL
        D5CF    RFERROR
        CMP     AX,0FFFFH
        D5Z     D5NOROOM
        MOV     [RFSLOT+4],AX
RFJLOCATE:
        MOV     SI,OFFSET RFNAME
        CALL    FIND
        D5CF    RFERROR
        CMP     AX,0FFFFH
        JE      RFJNEW
        CMP     WORD PTR [MATCH+12],RFJTAG
        D5NZ    RFJERROR
        MOV     DL,[MATCH+11]
        AND     DL,0DFH
        CMP     DL,7
        D5NZ    RFJERROR
        MOV     [RFJEXIST],1
        MOV     DX,WORD PTR [MATCH+26]
        MOV     [RFJHEAD],DX
        MOV     [RFJNEXT],DX
        MOV     DX,WORD PTR [MATCH+28]
        MOV     [RFJSIZE],DX
        MOV     DX,WORD PTR [MATCH+30]
        MOV     [RFJSIZE+2],DX
        JMP     SHORT RFJFOUND
RFJNEW: CALL    RFVACALL
        D5CF    RFERROR
        CMP     AX,0FFFFH
        D5Z     D5NOROOM
RFJFOUND:MOV    [RFSLOT+6],AX
        CLC
        RET
RFJERROR:MOV    DX,OFFSET RFJMSG
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

RFNEXTCL:
        CMP     [RFJEXIST],0
        JNE     RFJOCCUPIED
        CALL    RFFREE
        D5CF    RFERROR
        CMP     [RFJHEAD],0
        JNE     RFNCDONE
        MOV     [RFJHEAD],AX
RFNCDONE:CLC
        RET
RFJOCCUPIED:
        MOV     BX,[RFJNEXT]
        CMP     BX,2
        JB      RFJFAIL
        CMP     BX,[D5CLMAX]
        JA      RFJFAIL
        XOR     AX,AX
        CALL    BMFATGET
        JC      RFJFAIL
        MOV     [RFJNEXT],DX
        MOV     AX,BX
        CLC
        RET
RFJFAIL:JMP     RFJERROR

RFPLANNEW:
        CMP     [RFDAMAGED],0
        JE      RFMARKLISTS
        ; A damaged chain can run into another old DOS chain. Without
        ; a reliable owner list, do not release any of those clusters.
        MOV     ES,[RFSEG]
        XOR     AX,AX
        MOV     DI,RF_FIRST+RF_OLD
        MOV     BX,NSYS
RFDROPOLD:
        MOV     CX,9
        REP     STOSW
        ADD     DI,RF_LEN-18
        DEC     BX
        JNZ     RFDROPOLD
RFMARKLISTS:
        ; Check all old/new lists for overlap before writes. Prebuild the
        ; final images too, catching memory and planner limits up front.
        MOV     ES,[RFSEG]
        MOV     DI,256
        XOR     AX,AX
        MOV     CX,156
        REP     STOSW
        MOV     SI,RF_FIRST+RF_OLD
RFPLANLIST:
        MOV     CX,17
RFPLANCL:
        LODS    WORD PTR ES:[SI]
        OR      AX,AX
        JZ      RFPLANNEXT
        MOV     BX,AX
        PUSH    CX
        CALL    RFMARK
        POP     CX
        D5CF    RFERROR
RFPLANNEXT:
        LOOP    RFPLANCL
        ADD     SI,RF_OLD
        CMP     SI,RF_FIRST+NSYS*RF_LEN+RF_OLD
        JB      RFPLANLIST
        MOV     AX,[RFJCOUNT]
        MUL     [BMCLBYTES]
        CMP     [RFJEXIST],0
        JE      RFPLANPROV
        CMP     [RFJNEXT],0FF8H
        D5CF    RFJERROR
        CMP     AX,[RFJSIZE]
        D5NZ    RFJERROR
        CMP     DX,[RFJSIZE+2]
        D5NZ    RFJERROR
        JMP     SHORT RFPLANFINAL
RFPLANPROV:
        MOV     [RFJSIZE],AX
        MOV     [RFJSIZE+2],DX
RFPLANFINAL:
        CALL    TXBEGIN
        D5CF    D5PASS
        CALL    RFPUBLISH
        MOV     [TXPLAN],0
        D5CF    D5PASS
        CMP     [RFJEXIST],0
        JE      RFPROVISION
        CLC
        RET

; Reserve the payload as one ordinary hidden/system/read-only file.
; This separate transaction never changes any live DOS file.
RFPROVISION:
        CALL    TXBEGIN
        D5CF    D5PASS
        MOV     [RFPROVREC],RF_FIRST
        MOV     [RFPROVPREV],0
RFPROVFILE:
        MOV     AX,[RFPROVREC]
        ADD     AX,RF_ALLOC
        MOV     [RFPROVIDX],AX
RFPROVLINK:
        MOV     ES,[RFSEG]
        MOV     SI,[RFPROVIDX]
        MOV     DX,ES:[SI]
        OR      DX,DX
        JZ      RFPROVNEXT
        MOV     BX,[RFPROVPREV]
        MOV     [RFPROVPREV],DX
        OR      BX,BX
        JZ      RFPROVINC
        CALL    RFFATSET
        D5CF    RFERROR
RFPROVINC:
        ADD     [RFPROVIDX],2
        MOV     AX,[RFPROVIDX]
        SUB     AX,[RFPROVREC]
        CMP     AX,RF_LEN
        JB      RFPROVLINK
RFPROVNEXT:
        ADD     [RFPROVREC],RF_LEN
        CMP     [RFPROVREC],RF_FIRST+NSYS*RF_LEN
        JB      RFPROVFILE
        MOV     BX,[RFPROVPREV]
        MOV     DX,0FFFH
        CALL    RFFATSET
        D5CF    RFERROR
        MOV     AX,[RFEND0]
        CMP     AX,[RFSLOT+6]
        JA      RFPROVDIR
        ; Publish any intervening free slots as deleted, not end markers.
RFPROVPAD:
        CMP     AX,[RFSLOT+6]
        JE      RFPROVDIR
        PUSH    AX
        CALL    RFDELSLOT
        POP     AX
        D5CF    RFERROR
        INC     AX
        JMP     SHORT RFPROVPAD
RFPROVDIR:
        MOV     AX,[RFSLOT+6]
        CALL    GETSLOT
        D5CF    RFERROR
        PUSH    AX
        PUSH    DI
        XOR     AX,AX
        MOV     CX,16
        REP     STOSW
        POP     DI
        PUSH    DI
        MOV     SI,OFFSET RFNAME
        MOV     CX,11
        REP     MOVSB
        MOV     AL,7
        STOSB
        MOV     AX,RFJTAG
        STOSW
        POP     DI
        MOV     AX,[RFJHEAD]
        MOV     ES:[DI+26],AX
        MOV     AX,[RFJSIZE]
        MOV     ES:[DI+28],AX
        MOV     AX,[RFJSIZE+2]
        MOV     ES:[DI+30],AX
        POP     AX
        CALL    PUTSLOT
        D5CF    RFERROR
        JMP     TXCOMMIT

RFPUBLISH:
        CALL    RFCLAIMFAT
        D5CF    RFERROR
        ; TXWRITE retains the first position of each physical block.
        ; Queue removal of the reservation before any replacement name.
        ; If they share a block, the final combined image is atomic.
        MOV     AX,[RFSLOT+6]
        CALL    RFDELSLOT
        D5CF    RFERROR
        MOV     AX,[RFGAP]
        CMP     AX,0FFFFH
        JE      RFDELMIO
        CALL    RFDELSLOT
        D5CF    RFERROR
RFDELMIO:
        MOV     AX,[RFSRC]
        CMP     AX,0FFFFH
        JE      RFDELMDOS
        CMP     AX,[RFSLOT]
        JE      RFDELMDOS
        CALL    RFDELSLOT
        D5CF    RFERROR
RFDELMDOS:
        MOV     AX,[RFSRC+2]
        CMP     AX,0FFFFH
        JE      RFPUBFILES
        CMP     AX,[RFSLOT+2]
        JE      RFPUBFILES
        CALL    RFDELSLOT
        D5CF    RFERROR
RFPUBFILES:
        CALL    RFROOTS
        D5CF    RFERROR
        JMP     RFRELEASE
RFDELSLOT:
        CALL    GETSLOT
        D5CF    RFERROR
        MOV     BYTE PTR ES:[DI],0E5H
        JMP     PUTSLOT

; Roll forward from the immutable plan. New clusters are never shared
; with the old files; the live kernel names are changed in one write.
RFAPPLY:CALL    RFVALID
        D5CF    RFERROR
        CALL    RFCLAIMFAT
        D5CF    D5PASS
        CALL    RFROOTS
        D5CF    D5PASS
        CALL    RFRELEASE
        D5CF    D5PASS
        MOV     AX,[RFROOT]
        CALL    GETSLOT
        D5CF    RFERROR
        MOV     BYTE PTR ES:[DI],0E5H
        CALL    PUTSLOT
        D5CF    RFERROR
        RET
RFCLAIMFAT:
        MOV     [RFREC],RF_FIRST
RFCLAIM:MOV     BX,[RFREC]
        ADD     BX,RF_ALLOC
        MOV     [RFCLIDX],BX
RFCLAIM1:
        MOV     ES,[RFSEG]
        MOV     SI,[RFCLIDX]
        MOV     BX,ES:[SI]
        OR      BX,BX
        JZ      RFCLAIMDONE
        MOV     DX,0FFFH
        MOV     AX,SI
        SUB     AX,[RFREC]
        CMP     AX,RF_ALLOC+14
        JE      RFCLAIM2
        CMP     WORD PTR ES:[SI+2],0
        JE      RFCLAIM2
        MOV     DX,ES:[SI+2]
RFCLAIM2:CALL   RFFATSET
        D5CF    RFERROR
        ADD     [RFCLIDX],2
        MOV     AX,[RFCLIDX]
        SUB     AX,[RFREC]
        CMP     AX,RF_LEN
        JB      RFCLAIM1
RFCLAIMDONE:
        ADD     [RFREC],RF_LEN
        CMP     [RFREC],RF_FIRST+NSYS*RF_LEN
        JB      RFCLAIM
        CLC
        RET
RFROOTS:MOV     ES,[RFSEG]
        MOV     BX,ES:[RF_FIRST+RF_SLOT]
        XOR     BX,ES:[RF_FIRST+RF_LEN+RF_SLOT]
        AND     BX,0FFF8H
        D5NZ    RFERROR
        MOV     AX,ES:[RF_FIRST+RF_SLOT]
        CALL    GETSLOT
        D5CF    RFERROR
        MOV     SI,RF_FIRST+RF_NEW
        CALL    RFDIRENT
        PUSH    AX
        PUSH    ES
        MOV     ES,[RFSEG]
        MOV     DI,ES:[RF_FIRST+RF_LEN+RF_SLOT]
        AND     DI,31
        MOV     CL,5
        SHL     DI,CL
        POP     ES
        MOV     SI,RF_FIRST+RF_LEN+RF_NEW
        CALL    RFDIRENT
        POP     AX
        CALL    PUTSLOT
        D5CF    RFERROR
        MOV     ES,[RFSEG]
        MOV     AX,ES:[RF_FIRST+2*RF_LEN+RF_SLOT]
        CALL    GETSLOT
        D5CF    RFERROR
        MOV     SI,RF_FIRST+2*RF_LEN+RF_NEW
        CALL    RFDIRENT
        JMP     PUTSLOT
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
        CMP     [RFREC],RF_FIRST+NSYS*RF_LEN
        JB      RFRELFILE
        CLC
        RET

; Before any replay write, require the real names still to be at the
; expected slots with either the original or replacement head cluster.
; Also reject any repetition among the journal and six saved chains.
RFVALID:MOV     ES,[RFSEG]
        MOV     DI,256
        XOR     AX,AX
        MOV     CX,156
        REP     STOSW
        MOV     BX,[RFCL]
        CALL    RFMARK
        JNC     RFVFREE
        JMP     RFVERR
RFVFREE:MOV     BX,[RFCL]
        XOR     AX,AX
        CALL    BMFATGET
        JNC     RFVFIRST
        RET
RFVFIRST:OR     DX,DX
        JNZ     RFVERR
        MOV     AX,[D5SPF]
        CALL    BMFATGET
        JC      RFVERR
        OR      DX,DX
        JNZ     RFVERR
        MOV     [RFREC],RF_FIRST
RFVROOT:MOV     ES,[RFSEG]
        MOV     DI,[RFREC]
        MOV     AX,ES:[DI+RF_SLOT]
        MOV     DX,ES:[DI+RF_OLD]
        MOV     BX,ES:[DI+RF_ALLOC]
        PUSH    DX
        CALL    GETSLOT
        POP     DX
        JC      RFVERR
        CMP     DX,ES:[DI+26]
        JE      RFVNAME
        CMP     BX,ES:[DI+26]
        JNE     RFVERR
RFVNAME:MOV     SI,[RFREC]
        ADD     SI,RF_NEW
        PUSH    DS
        MOV     DS,[RFSEG]
        MOV     CX,11
        REPE    CMPSB
        POP     DS
        JNE     RFVERR
        MOV     ES,[RFSEG]
        MOV     SI,[RFREC]
        ADD     SI,RF_OLD
        MOV     CX,17
RFVLIST:MOV     AX,ES:[SI]
        ADD     SI,2
        OR      AX,AX
        JZ      RFVNEXT
        MOV     BX,AX
        PUSH    CX
        CALL    RFMARK
        POP     CX
        JC      RFVERR
RFVNEXT:LOOP    RFVLIST
        ADD     [RFREC],RF_LEN
        CMP     [RFREC],RF_FIRST+NSYS*RF_LEN
        JB      RFVROOT
        CLC
        RET
RFVERR: STC
        RET
RFMARK: CMP     BX,2
        JB      RFVERR
        CMP     BX,[D5CLMAX]
        JA      RFVERR
        MOV     CL,BL
        AND     CL,7
        SHR     BX,1
        SHR     BX,1
        SHR     BX,1
        MOV     AL,1
        SHL     AL,CL
        TEST    ES:[BX+256],AL
        JNZ     RFVERR
        OR      ES:[BX+256],AL
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

RFFREE: MOV     BX,[RFSCAN]
        CMP     BX,[D5CLMAX]
        JA      RFFATERR
        INC     [RFSCAN]
        XOR     AX,AX
        CALL    BMFATGET
        JC      RFFATRET
        OR      DX,DX
        JNZ     RFFREE
        MOV     AX,[D5SPF]
        CALL    BMFATGET
        JC      RFFATRET
        OR      DX,DX
        JNZ     RFFREE
        MOV     AX,BX
        CLC
        RET
RFFATERR:STC
RFFATRET:RET

; Replace the chosen FAT12 entry in both copies without disturbing the
; neighboring nibble. Byte-wise RMW also handles physical boundaries.
RFFATSET:
        CMP     BX,2
        JB      RFFATERR
        CMP     BX,[D5CLMAX]
        JA      RFFATERR
        MOV     [RFLINK],DX
        MOV     AX,BX
        SHR     AX,1
        ADD     AX,BX
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
        CMP     AL,255
        JE      RFFATSPLIT
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
RFFATSPLIT:
        MOV     DX,[RFLINK]
        MOV     BX,[RFKEEP]
        CALL    RFFATBYTE
        JNC     RFSPLIT2
        RET
RFSPLIT2:
        MOV     AX,[RFFPOS]
        INC     AX
        MOV     DX,[RFLINK]
        MOV     DL,DH
        MOV     BX,[RFKEEP]
        MOV     BL,BH
RFFATBYTE:
        MOV     DI,AX
        AND     DI,1023
        MOV     CL,10
        SHR     AX,CL
        ADD     AX,[RFFAT]
        MOV     ES,[BMBUFSEG]
        XOR     BP,BP
        CALL    READSEC
        JNC     RFBYTEPUT
        RET
RFBYTEPUT:MOV   DH,ES:[DI]
        AND     BL,DH
        OR      BL,DL
        CMP     BL,DH
        JE      RFBYTEOK
        MOV     ES:[DI],BL
        JMP     PUTSLOT
RFBYTEOK:CLC
        RET
