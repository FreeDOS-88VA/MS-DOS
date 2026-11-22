; SASI fixed disks through INT 81h (602HDD, Function details).
; All addresses passed to the ROM are relative 256-byte block numbers.
HDDDEV: DW      -1,-1
        DW      2842H           ;FAT media byte, open/close, IOCTL, long LBA.
        DW      STRATEGY,HDD_INT
HDUNITS DB      0
        DB      7 DUP (0)

HDD_INT:
        PUSH    SI
        MOV     SI,OFFSET HDTABLE
        JMP     ENTRY

HDTABLE DW      HDINIT,HDMEDIA,HDBUILD,CMDERR,HDREAD,CMDERR,HDOK,HDOK
        DW      HDWRITE,HDWRITE,HDOK,HDOK,CMDERR

HDTOT16 EQU     8
HDMEDIAID EQU   10
HDTOT32 EQU     21
HDTARGET EQU    25
HDSCALE EQU     26              ;Physical blocks per logical sector.
HDPREFIX EQU    27              ;Physical volume start, 0 or 4.
HDSIZE  EQU     28
HDUNITSIZE EQU  2
HDMEM   DW      0               ;End of conventional memory, paragraphs.

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
        CLC
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
        MOV     AL,1
        TEST    BYTE PTR [SI+HDTARGET],80H
        JZ      HDMEDSTAT
        NEG     AL              ;Changed: DOS must not reuse the old BPB.
HDMEDSTAT:
        LDS     BX,[PTRSAV]
        MOV     [BX+MEDSTAT],AL
        JMP     HDOK
HDBUILD:CALL    HDFIND
        TEST    BYTE PTR [SI+HDTARGET],80H
        JNZ     HDNOTRDY
        LDS     BX,[PTRSAV]
        MOV     AL,CS:[SI+HDMEDIAID]
        MOV     [BX.MEDIA],AL
        MOV     [BX+BPBPTR],SI
        MOV     WORD PTR [BX+BPBPTR+2],CS
        JMP     HDOK
HDNOTRDY:
        MOV     AL,2
        JMP     ERR_EXIT

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
        CMP     AH,0F0H         ;VA FORMAT: identify physical SASI target.
        JE      HDIDENT
        CMP     AH,0F1H         ;Quarantine this unit until reboot.
        JE      HDLOCK
        CMP     AH,0F2H         ;SYS: identify an online NEC-layout unit.
        JE      HDNECID
        CMP     AH,60H
        JE      HDGDP
        CMP     AH,67H
        JNE     HDUNK
        JMP     GIO_GAF
HDUNK:  JMP     CMDERR
HDNECID:CMP     BYTE PTR [SI+HDPREFIX],0
        JNE     HDUNK
        TEST    BYTE PTR [SI+HDTARGET],80H
        JNZ     HDUNK
HDIDENT:MOV     AL,[SI+HDTARGET]
        AND     AL,1
        MOV     AH,0D4H
        MOV     ES:[DI],AX
        JMP     HDOK
HDLOCK: MOV     AL,[SI+HDTARGET]
        AND     AL,1
        MOV     AH,0D4H
        CMP     AX,ES:[DI]      ;Must match the target the user confirmed.
        JNE     HDUNK
        OR      BYTE PTR [SI+HDTARGET],80H
        JMP     HDOK
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
HDWRITE:MOV     [HDOP],82H       ;No ROM write-with-verify operation.
        JMP     SHORT HDIO
HDREAD: MOV     [HDOP],81H
HDIO:   CALL    HDFIND
        TEST    BYTE PTR [SI+HDTARGET],80H
        JZ      HDREADY
        MOV     AL,2
        JMP     HDERROR
HDREADY:OR      CX,CX
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
        JMP     HDERROR
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
        CMP     [HDOP],82H
        JNE     HDBOUNCER
        PUSH    DS
        PUSH    ES
        PUSH    SI
        PUSH    DI
        PUSH    ES
        PUSH    CS
        POP     ES
        POP     DS
        MOV     SI,DI
        MOV     DI,OFFSET HDBUF
        MOV     CX,128
        REP     MOVSW
        POP     DI
        POP     SI
        POP     ES
        POP     DS
HDBOUNCER:
        PUSH    ES
        PUSH    CS
        POP     ES
        MOV     BP,OFFSET HDBUF
        MOV     AL,1
        CALL    HDTRANSFER
        POP     ES
        JC      HDFAULT
        CMP     [HDOP],82H
        JE      HDADVANCE
        PUSH    SI
        PUSH    DI
        MOV     SI,OFFSET HDBUF
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
HDFAULT:XOR     AL,AL           ;Write protection.
        CMP     AH,05H
        JE      HDERROR
        MOV     AL,2            ;Not ready / no drive.
        CMP     AH,04H
        JE      HDERROR
        CMP     AH,0DH
        JE      HDERROR
        MOV     AL,4            ;CRC error.
        CMP     AH,06H
        JE      HDERROR
        CMP     AH,07H
        JE      HDERROR
        MOV     AL,11           ;Read fault.
        CMP     [HDOP],81H
        JE      HDERROR
        MOV     AL,10           ;Write fault.
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

; Align to a physical block; CS:0 is aligned (BIOSSEG=1000h).
        DB      ((-($-INIT)) AND 255) DUP (0)
HDBUF   DB      256 DUP (0)
HDARRAY DW      HDBPBS,HDBPBS+HDSIZE
; Keep the packed records last: SYSINIT can overwrite unused records.
HDBPBS  DB      HDUNITSIZE*HDSIZE DUP (0)
