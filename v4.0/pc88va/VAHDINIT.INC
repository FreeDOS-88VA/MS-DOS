; Boot-only SASI discovery, overwritten by SYSINIT.
; Capacity in physical blocks: minimum of manual and vaeg per type.
HDCAPS  DD      20196,40920,81180,162360
; Fixed NEC BPBs: one reserved logical sector, FAT12, no VBR or table.
HDNEC   LABEL   BYTE
        DW      1024
        DB      8
        DW      1
        DB      2
        DW      608,4950
        DB      0D0H
        DW      1,1,1
        DD      0,0
        DW      1024
        DB      8
        DW      1
        DB      2
        DW      992,9900
        DB      0D1H
        DW      2,1,1
        DD      0,0
        DW      1024
        DB      8
        DW      1
        DB      2
        DW      1504,19800
        DB      0D2H
        DW      4,1,1
        DD      0,0
        DW      1024
        DB      16
        DW      1
        DB      2
        DW      3072,39593
        DB      0D3H
        DW      4,1,1
        DD      0,0

HDBOOTTARGET DB 0FFH           ;FFh means floppy boot.
HDBOOTDRV DB    1              ;A: unless the IPL specifies SASI.
HDNEXT  DB      0
HDTYPE  DB      0
HDSKIP  DB      13,10,'SASI target '
HDSKIPN DB      '0',': unrecognized or unreadable volume',13,10,0

; Read two blocks into boot-only, page-safe DMA storage.
        DB      ((-($-INIT)) AND 511) DUP (0)
HDPROBEBUF DB   512 DUP (0)

; Called by HWINIT before DOS moves. DS = CS; return DI just past the
; packed records and link the fixed disk header only for accepted units.
HDDISCOVER:
        MOV     DI,OFFSET HDBPBS
HDPROBE:
        XOR     BX,BX
        XOR     CX,CX
        XOR     DX,DX
        MOV     BH,[HDNEXT]
        MOV     AX,0900H
        CALL    HDROM
        JC      HDABSENT
        CMP     AL,0FFH         ;vaeg can return success with no target.
        JNE     HDPRESENT
HDABSENT:JMP    HDPROBEN
HDPRESENT:
        CMP     AL,4
        JB      HDTYPEOK
        JMP     HDPROBEB
HDTYPEOK:MOV    [HDTYPE],AL
        PUSH    CS
        POP     ES
        MOV     BP,OFFSET HDPROBEBUF
        MOV     BH,[HDNEXT]
        OR      BH,80H
        MOV     AX,8102H
        MOV     CX,4
        XOR     DX,DX
        CALL    HDROM
        JC      HDPROBEB
        MOV     SI,OFFSET HDPROBEBUF
        MOV     AL,[SI]
        CMP     AL,0D0H
        JB      HDPROBEV
        CMP     AL,0D3H
        JA      HDPROBEV
        SUB     AL,0D0H
        CMP     AL,[HDTYPE]
        JNE     HDPROBEB
        CMP     WORD PTR [SI+1],0FFFFH
        JNE     HDPROBEB
        MOV     AH,25
        MUL     AH
        ADD     AX,OFFSET HDNEC
        MOV     SI,AX
        MOV     CX,4            ;Scale = 4, prefix = 0.
        JMP     SHORT HDPROBEC
HDPROBEV:
        CALL    HDVALID
        JC      HDPROBEB
        ADD     SI,11
        MOV     CX,0402H        ;Scale = 2, prefix = 4.
HDPROBEC:
        PUSH    DI
        MOV     AX,CX
        MOV     CX,25
        REP     MOVSB
        POP     DI
        MOV     AL,[HDNEXT]
        MOV     [DI+HDTARGET],AL
        MOV     CL,AL
        CMP     AL,[HDBOOTTARGET]
        JNE     HDNOTBOOT
        CMP     AH,0            ;NEC layout has no physical prefix.
        JNE     HDNOTBOOT
        MOV     AL,[HDUNITS]
        ADD     AL,3            ;A: and B: precede the fixed units.
        MOV     [HDBOOTDRV],AL
HDNOTBOOT:
        MOV     AL,1
        SHL     AL,CL
        OR      [SASIMAP],AL
        ; The scale is derived from the copied sector size.
        MOV     AL,[DI+1]
        MOV     [DI+HDSCALE],AL
        MOV     AL,AH
        MOV     [DI+HDPREFIX],AL
        ADD     DI,HDSIZE
        INC     [HDUNITS]
        JMP     SHORT HDPROBEN
HDPROBEB:
        MOV     AL,[HDNEXT]
        ADD     AL,'0'
        MOV     [HDSKIPN],AL
        PUSH    DI
        MOV     SI,OFFSET HDSKIP
HDMSG:  LODSB
        OR      AL,AL
        JZ      HDMSGE
        PUSH    SI
        CALL    OUTCHR
        POP     SI
        JMP     SHORT HDMSG
HDMSGE: POP     DI
HDPROBEN:
        INC     [HDNEXT]
        CMP     [HDNEXT],HDUNITSIZE
        JAE     HDPROBED
        JMP     HDPROBE
HDPROBED:
        CMP     [HDBOOTTARGET],0FFH
        JE      HDLINK
        CMP     [HDBOOTDRV],1
        JNE     HDLINK
        MOV     [HDBOOTDRV],0
HDLINK: CMP     [HDUNITS],0
        JE      HDPROBER
        MOV     WORD PTR [DSKDEV],OFFSET HDDDEV
        MOV     WORD PTR [DSKDEV+2],CS
HDPROBER:
        RET

; SI = block 4 VBR. Accept only a bounded FAT12/16 BPB, not a table,
; an extended partition, or an arbitrary boot sector claiming a size.
HDVALID:
        CMP     BYTE PTR [SI],0E9H
        JE      HDVJUMP
        CMP     BYTE PTR [SI],0EBH
        JNE     HDVFAIL
        CMP     BYTE PTR [SI+2],90H
        JNE     HDVFAIL
HDVJUMP:
        CMP     WORD PTR [SI+510],0AA55H
        JNE     HDVFAIL
        CMP     WORD PTR [SI+11],512
        JNE     HDVFAIL
        CMP     BYTE PTR [SI+16],2
        JNE     HDVFAIL
        CMP     BYTE PTR [SI+21],0F8H
        JNE     HDVFAIL
        MOV     AX,[SI+28]
        OR      AX,[SI+30]
        JNZ     HDVFAIL
        CMP     WORD PTR [SI+14],0
        JE      HDVFAIL
        CMP     WORD PTR [SI+22],0
        JE      HDVFAIL
        CMP     WORD PTR [SI+24],0
        JE      HDVFAIL
        CMP     WORD PTR [SI+26],0
        JE      HDVFAIL
        XOR     CX,CX
        MOV     CL,[SI+13]
        JCXZ    HDVFAIL
        CMP     CL,64           ;At most 32 KiB per cluster.
        JA      HDVFAIL
        MOV     AX,CX
        DEC     AX
        TEST    AX,CX
        JNZ     HDVFAIL
        JMP     SHORT HDVCAP
HDVFAIL:STC
        RET
HDVCAP: MOV     AX,[SI+19]
        XOR     DX,DX
        OR      AX,AX
        JZ      HDVEXT
        MOV     BX,[SI+32]
        OR      BX,[SI+34]
        JNZ     HDVFAIL
        JMP     SHORT HDVGETCAP
HDVEXT: MOV     AX,[SI+32]
        MOV     DX,[SI+34]
        CMP     DX,1            ;All supported geometries have <128K sectors.
        JA      HDVFAIL
HDVGETCAP:
        XOR     BX,BX
        MOV     BL,[HDTYPE]
        SHL     BX,1
        SHL     BX,1
        PUSH    DX
        PUSH    AX
        SHL     AX,1
        RCL     DX,1
        ADD     AX,4
        ADC     DX,0
        CMP     DX,WORD PTR [HDCAPS+BX+2]
        JB      HDVPOP
        JA      HDVCBAD
        CMP     AX,WORD PTR [HDCAPS+BX]
        JBE     HDVPOP
HDVCBAD:POP     AX
        POP     DX
        JMP     SHORT HDVFAIL
HDVPOP: POP     AX
        POP     DX
        MOV     BX,[SI+17]      ;Root entries must fill whole sectors.
        OR      BX,BX
        JZ      HDVFAIL
        TEST    BL,15
        JNZ     HDVFAIL
        SHR     BX,1
        SHR     BX,1
        SHR     BX,1
        SHR     BX,1
        ADD     BX,[SI+14]
        JC      HDVFAIL
        ADD     BX,[SI+22]
        JC      HDVFAIL
        ADD     BX,[SI+22]
        JC      HDVFAIL
        SUB     AX,BX
        SBB     DX,0
        JC      HDVFAIL
        CMP     DX,CX
        JAE     HDVFAIL
        DIV     CX
        OR      AX,AX
        JZ      HDVFAIL
        CMP     AX,65525
        JB      HDVCLUST
        JMP     HDVFAIL
HDVCLUST:CMP    AX,4085
        JAE     HDVF16
        ADD     AX,2
        MOV     BX,3
        MUL     BX
        INC     AX
        SHR     AX,1
        JMP     SHORT HDVFAT
HDVF16: ADD     AX,2
        XOR     DX,DX
        SHL     AX,1
        RCL     DX,1
HDVFAT: ADD     AX,511
        ADC     DX,0
        MOV     BX,512
        DIV     BX
        CMP     [SI+22],AX      ;CF if FAT cannot hold all entries.
        RET
