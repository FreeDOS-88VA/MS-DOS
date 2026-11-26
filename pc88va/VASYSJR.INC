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

RFNEW:  MOV     ES,[RFSEG]
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
        MOV     ES,[RFSEG]
        MOV     SI,OFFSET RFNAMES
        MOV     BX,[RFIDX]
        MOV     AL,11
        MUL     BL
        ADD     SI,AX
        CALL    FIND
        D5CF    RFERROR
        CMP     AX,0FFFFH
        D5Z     RFERROR
        TEST    BYTE PTR [MATCH+11],18H
        D5NZ    RFERROR
        CMP     WORD PTR [MATCH+30],0
        D5NZ    RFERROR
        MOV     DI,[RFREC]
        MOV     ES:[DI+RF_SLOT],AX
        PUSH    DI
        ADD     DI,RF_NEW
        MOV     SI,OFFSET MATCH
        MOV     CX,16
        REP     MOVSW
        POP     DI
        CALL    CHECKCHAIN
        D5CF    RFERROR
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
        PUSH    DX
        MOV     AX,[D5SPF]
        CALL    BMFATGET
        POP     AX
        D5CF    RFERROR
        CMP     AX,DX
        D5NZ    RFERROR
        MOV     BX,DX
        CMP     DX,0FF8H
        JB      RFOLD
        MOV     ES,[RFSEG]
        MOV     DI,[RFREC]
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
        MOV     [RFLEFT],AX
        MOV     [RFDATA],0
        ADD     DI,RF_ALLOC
        MOV     [RFCLIDX],DI
RFSTAGE:CALL    RFFREE
        D5CF    RFERROR
        MOV     ES,[RFSEG]
        MOV     DI,[RFCLIDX]
        MOV     ES:[DI],AX
        ADD     [RFCLIDX],2
        CMP     [RFDATA],0
        JNE     RFCLLBA
        MOV     DI,[RFREC]
        MOV     ES:[DI+RF_NEW+26],AX
RFCLLBA:CALL    D5JRLBA
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
        JE      RFPLAN
        MOV     ES,[RFSEG]
        JMP     RFPREP
RFPLAN: CALL    RFFREE
        D5CF    RFERROR
        MOV     [RFCL],AX
        CALL    RFVALID
        D5CF    RFERROR
        CALL    TXBEGIN
        D5CF    D5PASS
        CALL    RFCLAIMS
        MOV     [TXPLAN],0
        D5CF    D5PASS
        JMP     TXCOMMIT

; Roll forward from the immutable plan. New clusters are never shared
; with the old files; the live kernel names are changed in one write.
RFAPPLY:CALL    RFVALID
        D5CF    RFERROR
        CALL    RFCLAIMS
        D5CF    D5PASS
        MOV     AX,[RFROOT]
        CALL    GETSLOT
        D5CF    RFERROR
        MOV     BYTE PTR ES:[DI],0E5H
        CALL    PUTSLOT
        D5CF    RFERROR
        RET
RFCLAIMS:MOV    [RFREC],RF_FIRST
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
        MOV     ES,[RFSEG]
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
        CALL    PUTSLOT
        D5CF    RFERROR
        MOV     [RFREC],RF_FIRST
RFRELEASE:
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
        JB      RFRELEASE
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
