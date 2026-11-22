; SASI fixed disks through INT 81h (602HDD, Function details).
; All addresses passed to the ROM are relative 256-byte block numbers.
HDTABLE DW      HDINIT,HDMEDIA,HDBUILD,CMDERR,HDREAD,CMDERR,HDOK,HDOK
        DW      HDNOWRITE,HDNOWRITE,HDOK,HDOK,CMDERR

HDBPS   EQU     0
HDTOT16 EQU     8
HDMEDIAID EQU   10
HDTOT32 EQU     21
HDTARGET EQU    25
HDSCALE EQU     26              ;Physical blocks per logical sector.
HDPREFIX EQU    27              ;Physical volume start, 0 or 4.
HDSIZE  EQU     28
HDUNITSIZE EQU  2
HDBPBS  DB      HDUNITSIZE*HDSIZE DUP (0)
HDARRAY DW      HDBPBS,HDBPBS+HDSIZE
HDMEM   DW      0               ;End of conventional memory, paragraphs.
HDBUF   DW      0               ;512-byte aligned offset within HDBUFAREA.
HDBUFAREA DB    1023 DUP (0)    ;CS:0 is aligned (BIOSSEG=1000h).

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

HDNEXT  DB      0
HDTYPE  DB      0
HDSKIP  DB      13,10,'SASI target '
HDSKIPN DB      '0',': unrecognized or unreadable volume',13,10,0

; Called before SYSINIT moves the kernel. Only publish recognized units.
HDDISCOVER:
        MOV     AX,OFFSET HDBUFAREA+511
        AND     AX,0FE00H
        MOV     [HDBUF],AX
        MOV     DI,OFFSET HDBPBS
HDPROBE:
        MOV     BH,[HDNEXT]
        MOV     AH,09H
        CALL    HDROM
        JC      HDABSENT
        CMP     AL,0FFH         ;vaeg can return success with no target.
        JNE     HDPRESENT
HDABSENT:JMP    HDPROBEN
HDPRESENT:
        CMP     AL,4
        JAE     HDPROBEB
        MOV     [HDTYPE],AL
        PUSH    CS
        POP     ES
        MOV     BP,[HDBUF]
        MOV     BH,[HDNEXT]
        OR      BH,80H
        MOV     AX,8102H
        MOV     CX,4
        XOR     DX,DX
        CALL    HDROM
        JC      HDPROBEB
        MOV     SI,[HDBUF]
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
        CMP     [HDUNITS],0
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
HDVCAP: XOR     BX,BX
        MOV     BL,[HDTYPE]
        SHL     BX,1
        SHL     BX,1
        MOV     AX,[SI+19]
        XOR     DX,DX
        OR      AX,AX
        JNZ     HDVTOTAL
        MOV     AX,[SI+32]
        MOV     DX,[SI+34]
        CMP     DX,1            ;All supported geometries have <128K sectors.
        JA      HDVFAIL
HDVTOTAL:
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
        JAE     HDVFAIL
        CMP     AX,4085
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

; Preserve caller state except AX (ROM status/type) and flags.
HDROM:  PUSH    BX
        PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        PUSH    [CALLFL]
        POPF
        INT     81H
        CLD
        POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     SI
        POP     DX
        POP     CX
        POP     BX
        RET

HDINIT: LDS     BX,[PTRSAV]
        MOV     AL,CS:[HDUNITS]
        MOV     [BX+INITUNITS],AL
        MOV     WORD PTR [BX+INITBPB],OFFSET HDARRAY
        MOV     WORD PTR [BX+INITBPB+2],CS
HDOK:   XOR     AL,AL
        JMP     EXIT

; Lookup with AL = subunit, SI = resident record on return.
HDFIND: CMP     AL,[HDUNITS]
        JB      HDFOUND
        POP     AX              ;Discard near return address.
        JMP     BADUNIT
HDFOUND:MOV     BL,HDSIZE
        MUL     BL
        MOV     SI,AX
        ADD     SI,OFFSET HDBPBS
        RET

HDMEDIA:CALL    HDFIND
        LDS     BX,[PTRSAV]
        MOV     BYTE PTR [BX+MEDSTAT],1
        JMP     HDOK
HDBUILD:CALL    HDFIND
        LDS     BX,[PTRSAV]
        MOV     AL,CS:[SI+HDMEDIAID]
        MOV     [BX.MEDIA],AL
        MOV     [BX+BPBPTR],SI
        MOV     WORD PTR [BX+BPBPTR+2],CS
        JMP     HDOK

HDHIGH: CMP     DI,13
        JB      HDUNK
        CMP     DI,15
        JBE     HDOK            ;Open/close and non-removable (not busy).
        CMP     DI,23
        JB      HDIOCTL
        CMP     DI,24
        JA      HDUNK
        JMP     DSK_OWN
HDIOCTL:CMP     DI,19
        JNE     HDUNK
        CALL    HDFIND
        LDS     BX,[PTRSAV]
        CMP     BYTE PTR [BX+13],8
        JNE     HDUNK
        MOV     AH,[BX+14]
        LES     DI,[BX+19]
        PUSH    CS
        POP     DS
        CMP     AH,60H
        JE      HDGDP
        CMP     AH,67H
        JNE     HDUNK
        JMP     GIO_GAF
HDUNK:  JMP     CMDERR
HDGDP:  MOV     BYTE PTR ES:[DI+1],5 ;Fixed disk.
        MOV     WORD PTR ES:[DI+2],1 ;Non-removable.
        MOV     AX,[SI+HDTOT16]
        XOR     DX,DX
        OR      AX,AX
        JNZ     HDGDPC
        MOV     AX,[SI+HDTOT32]
        MOV     DX,[SI+HDTOT32+2]
HDGDPC: SUB     AX,1            ;Floor((total-1)/sectors_per_cyl)+1.
        SBB     DX,0
        PUSH    AX
        PUSH    DX
        MOV     AX,[SI+13]
        MUL     WORD PTR [SI+15]
        MOV     BX,AX
        MOV     CX,DX
        POP     DX
        POP     AX
        OR      CX,CX
        JNZ     HDGDP1          ;Track geometry larger than typical volume.
        CMP     DX,BX
        JAE     HDGDPM
        DIV     BX
        INC     AX
        JNZ     HDGDP2
HDGDPM: MOV     AX,0FFFFH
        JMP     SHORT HDGDP2
HDGDP1: MOV     AX,1
HDGDP2: MOV     ES:[DI+4],AX
        MOV     BYTE PTR ES:[DI+6],0
        ADD     DI,7
        MOV     CX,25
        REP     MOVSB
        XOR     AL,AL
        MOV     CX,6
        REP     STOSB
        JMP     HDOK

HDOP    DB      81H
HDBLOCK DW      0,0             ;Current physical block index.
HDLEFT  DW      0               ;Physical blocks remaining (DMA RAM bound).
HDNOWRITE:
        XOR     AL,AL           ;Write protected until write is enabled.
        JMP     HDERROR
HDREAD: CALL    HDFIND
        OR      CX,CX
        JNZ     HDLBA
        JMP     HDOK
HDLBA:  XOR     AX,AX
        CMP     DX,0FFFFH
        JNE     HDSTART
        LDS     BX,[PTRSAV]
        CMP     BYTE PTR [BX],30
        JAE     HDLONG
        JMP     HDBOUNDS
HDLONG: MOV     DX,[BX+26]
        MOV     AX,[BX+28]
        PUSH    CS
        POP     DS
HDSTART:                        ;AX:DX = sector, CX = count.
        MOV     BX,DX
        MOV     BP,AX
        ADD     BX,CX
        ADC     BP,0
        JC      HDBOUNDS
        CMP     WORD PTR [SI+HDTOT16],0
        JE      HDLARGE
        OR      BP,BP
        JNZ     HDBOUNDS
        CMP     BX,[SI+HDTOT16]
        JA      HDBOUNDS
        JMP     SHORT HDSCALEIT
HDLARGE:CMP     BP,[SI+HDTOT32+2]
        JA      HDBOUNDS
        JB      HDSCALEIT
        CMP     BX,[SI+HDTOT32]
        JA      HDBOUNDS
HDSCALEIT:
        ; Discovery bound the entire volume to the SENSE capacity.
        MOV     BP,AX
        MOV     AX,DX
        XOR     BX,BX
        MOV     BL,[SI+HDSCALE]
        SHL     AX,1
        RCL     BP,1
        CMP     BL,2
        JE      HDADD
        SHL     AX,1
        RCL     BP,1
HDADD:  ADD     AL,[SI+HDPREFIX]
        ADC     AH,0
        ADC     BP,0
        MOV     [HDBLOCK],AX
        MOV     [HDBLOCK+2],BP
        MOV     AX,CX
        MUL     BX
        OR      DX,DX
        JNZ     HDBOUNDS
        MOV     [HDLEFT],AX
        MOV     BX,16
        MUL     BX              ;Transfer length in paragraphs.
        OR      DX,DX
        JNZ     HDBOUNDS
        MOV     BP,AX
        MOV     AX,DI
        MOV     CL,4
        SHR     AX,CL
        MOV     BX,ES
        ADD     BX,AX
        JC      HDBOUNDS
        AND     DI,15           ;Canonical ES:DI, no offset wrap.
        MOV     ES,BX
        ADD     BX,BP
        JC      HDBOUNDS
        OR      DI,DI
        JZ      HDENDMEM
        INC     BX
        JZ      HDBOUNDS
HDENDMEM:
        CMP     BX,[HDMEM]
        JBE     HDLOOP
HDBOUNDS:MOV    AL,8            ;Sector not found / invalid transfer range.
        JMP     SHORT HDERROR
HDZERO: JMP     HDOK

HDLOOP: MOV     AX,ES
        MOV     CL,4
        SHL     AX,CL
        ADD     AX,DI
        NEG     AX
        OR      AX,AX
        JNZ     HDPAGE
        MOV     AH,255          ;At boundary, cap the ROM count at 255.
HDPAGE: XOR     AL,AL
        MOV     CL,8
        SHR     AX,CL
        JZ      HDBOUNCE
        CMP     AX,[HDLEFT]
        JBE     HDDIRECT
        MOV     AX,[HDLEFT]
HDDIRECT:
        MOV     BP,DI
        CALL    HDTRANSFER
        JC      HDFAULT
        JMP     SHORT HDADVANCE
HDBOUNCE:
        ; Even one physical block crosses the page: DMA to a safe
        ; resident buffer, then copy it with the CPU.
        PUSH    ES
        PUSH    CS
        POP     ES
        MOV     BP,[HDBUF]
        MOV     AL,1
        CALL    HDTRANSFER
        POP     ES
        JC      HDFAULT
        PUSH    SI
        PUSH    DI
        MOV     SI,[HDBUF]
        MOV     CX,128
        REP     MOVSW
        POP     DI
        POP     SI
HDADVANCE:
        XOR     AH,AH
        ADD     [HDBLOCK],AX
        ADC     [HDBLOCK+2],0
        SUB     [HDLEFT],AX
        JZ      HDZERO
        MOV     CL,4
        SHL     AX,CL
        MOV     BX,ES
        ADD     BX,AX
        MOV     ES,BX
        JMP     HDLOOP
HDFAULT:MOV     AL,11           ;Read fault unless a specific code matches.
        CMP     AH,0DH
        JNE     HDERROR
        MOV     AL,2            ;Not ready.
HDERROR:LDS     BX,[PTRSAV]
        MOV     [BX.COUNT],0
        JMP     ERR_EXIT

; Preserve transfer count on success. HDROM preserves carry.
HDTRANSFER:
        MOV     BH,[SI+HDTARGET]
        OR      BH,80H
        MOV     CX,[HDBLOCK]
        MOV     DX,[HDBLOCK+2]
        MOV     AH,[HDOP]
        PUSH    AX
        CALL    HDROM
        POP     BX
        MOV     AL,BL
        RET
