        TITLE   IO.SYS BIOS part for the NEC PC-88VA (MS-DOS 4.0 experiment)

; SPDX-License-Identifier: MIT
;
; Adapted from v2.0/pc88va/VAIO.ASM (itself derived from the MS-DOS 2.0
; SKELIO.ASM) for the MS-DOS 4.0 SYSINIT.  It replaces the IBM PC BIOS
; part of IO.SYS (MSBIO1 ... MSINIT); link order is
; VAIO - SYSINIT1 - SYSCONF - SYSINIT2 - SYSIMES.
;
; VABOOT loads IO.SYS at BIOSSEG:0 with MSDOS.SYS following it and passes
; the MSDOS.SYS segment in DX.  The firmware keeps its work areas below
; BIOSSEG, so nothing is placed there.

BIOSSEG EQU     1000H           ;Load segment of IO.SYS.
NUNITS  EQU     2               ;Floppy drives A: and B:.
SECSIZ  EQU     1024            ;2HD: 1024-byte sectors,
SECTRK  EQU     8               ;  8 sectors per track,
NHEADS  EQU     2               ;  2 heads.
FDMODE  EQU     23H             ;INT 80h AH=0Ah mode: 2HD, 1024 bytes.
SECLEN  EQU     3               ;Sector length code for 1024 bytes.

; Keep CODE as the first segment of the link.
CODE    SEGMENT BYTE PUBLIC 'CODE'
CODE    ENDS

SYSINITSEG SEGMENT PUBLIC 'SYSTEM_INIT'
        EXTRN   SYSINIT:FAR
        EXTRN   CURRENT_DOS_LOCATION:WORD
        EXTRN   FINAL_DOS_LOCATION:WORD
        EXTRN   DEVICE_LIST:DWORD
        EXTRN   MEMORY_SIZE:WORD
        EXTRN   DEFAULT_DRIVE:BYTE
SYSINITSEG ENDS

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE,ES:NOTHING,SS:NOTHING

        PUBLIC  RE_INIT
        PUBLIC  Int19sem,MulTrk_flag,EC35_Flag,KEYRD_Func,KEYSTS_Func
        IRP     AA,<02,08,09,0A,0B,0C,0D,0E,70,72,73,74,76,77>
        PUBLIC  Int19OLD&AA
        ENDM

        ORG     0

INIT:   JMP     HWINIT

        SUBTTL  Device driver headers.
        PAGE

DEVSTART LABEL  WORD
CONDEV: DW      AUXDEV,BIOSSEG
        DW      8003H           ;Character device, console input/output.
        DW      STRATEGY
        DW      CON_INT
        DB      'CON     '

AUXDEV: DW      PRNDEV,BIOSSEG
        DW      8000H
        DW      STRATEGY
        DW      AUX_INT
        DB      'AUX     '

PRNDEV: DW      TIMDEV,BIOSSEG
        DW      8000H
        DW      STRATEGY
        DW      PRN_INT
        DB      'PRN     '

TIMDEV: DW      DSKDEV,BIOSSEG
        DW      8008H           ;Character device, clock.
        DW      STRATEGY
        DW      TIM_INT
        DB      'CLOCK$  '

DSKDEV: DW      -1,-1           ;Last device.
        DW      2040H           ;Block device, media byte from the BPB,
                                ;generic IOCTL (DOS 3.2 driver).
        DW      STRATEGY
        DW      DSK_INT
        DB      NUNITS
        DB      7 DUP (0)

        SUBTTL  Dispatch tables.
        PAGE

DSKTBL: DW      DSK_INIT        ;0  - Initialize driver.
        DW      MEDIAC          ;1  - Media check.
        DW      GET_BPB         ;2  - Build BPB.
        DW      CMDERR          ;3  - IOCTL input.
        DW      DSK_RED         ;4  - Read.
        DW      BUS_EXIT        ;5  - Non-destructive read.
        DW      EXIT            ;6  - Input status.
        DW      EXIT            ;7  - Input flush.
        DW      DSK_WRT         ;8  - Write.
        DW      DSK_WRT         ;9  - Write with verify.
        DW      EXIT            ;10 - Output status.
        DW      EXIT            ;11 - Output flush.
        DW      EXIT            ;12 - IOCTL output.

CONTBL: DW      EXIT            ;0  - Initialize.
        DW      EXIT            ;1
        DW      EXIT            ;2
        DW      CMDERR          ;3
        DW      CON_READ        ;4  - Read.
        DW      CON_RDND        ;5  - Non-destructive read.
        DW      EXIT            ;6
        DW      CON_FLSH        ;7  - Input flush.
        DW      CON_WRIT        ;8  - Write.
        DW      CON_WRIT        ;9  - Write with verify.
        DW      EXIT            ;10 - Output status.
        DW      EXIT            ;11
        DW      EXIT            ;12

AUXTBL: DW      EXIT            ;0
        DW      EXIT            ;1
        DW      EXIT            ;2
        DW      CMDERR          ;3
        DW      AUX_READ        ;4  - Read: end of file.
        DW      BUS_EXIT        ;5  - Nothing waiting.
        DW      EXIT            ;6
        DW      EXIT            ;7
        DW      EXIT            ;8  - Write: discarded.
        DW      EXIT            ;9
        DW      EXIT            ;10
        DW      EXIT            ;11
        DW      EXIT            ;12

TIMTBL: DW      EXIT            ;0
        DW      EXIT            ;1
        DW      EXIT            ;2
        DW      CMDERR          ;3
        DW      TIM_RED         ;4  - Read date and time.
        DW      BUS_EXIT        ;5
        DW      EXIT            ;6
        DW      EXIT            ;7
        DW      TIM_WRT         ;8  - Set date and time.
        DW      TIM_WRT         ;9
        DW      EXIT            ;10
        DW      EXIT            ;11
        DW      EXIT            ;12

PRNTBL: DW      EXIT            ;0
        DW      EXIT            ;1
        DW      EXIT            ;2
        DW      CMDERR          ;3
        DW      EXIT            ;4
        DW      BUS_EXIT        ;5
        DW      EXIT            ;6
        DW      EXIT            ;7
        DW      EXIT            ;8  - Write: discarded.
        DW      EXIT            ;9
        DW      EXIT            ;10
        DW      EXIT            ;11
        DW      EXIT            ;12

        SUBTTL  Strategy and interrupt routines.
        PAGE

IODAT   STRUC
CMDLEN  DB      ?               ;Length of this command.
UNIT    DB      ?               ;Sub-unit.
CMD     DB      ?               ;Command code.
STATUS  DW      ?               ;Status.
        DB      8 DUP (?)
MEDIA   DB      ?               ;Media descriptor or returned character.
TRANS   DD      ?               ;Transfer address.
COUNT   DW      ?               ;Count of blocks or characters.
START   DW      ?               ;First block to transfer.
IODAT   ENDS

; Initialization, media check and BPB replies.
INITUNITS EQU   13
INITBRK   EQU   14
INITBPB   EQU   18
MEDSTAT   EQU   14
BPBPTR    EQU   18

PTRSAV  DD      0               ;Request packet pointer.
SAVESP  DW      0               ;DOS stack during a request.
SAVESS  DW      0
SAVEAX  DW      0
SAVEFL  DW      0               ;Flags across an SS:SP switch.
        DW      256 DUP (0)     ;Private request stack.
STKTOP  LABEL   WORD

STRATP  PROC    FAR
STRATEGY:
        MOV     WORD PTR CS:[PTRSAV],BX
        MOV     WORD PTR CS:[PTRSAV+2],ES
        RET
STRATP  ENDP

CON_INT:
        PUSH    SI
        MOV     SI,OFFSET CONTBL
        JMP     SHORT ENTRY

AUX_INT:
        PUSH    SI
        MOV     SI,OFFSET AUXTBL
        JMP     SHORT ENTRY

PRN_INT:
        PUSH    SI
        MOV     SI,OFFSET PRNTBL
        JMP     SHORT ENTRY

TIM_INT:
        PUSH    SI
        MOV     SI,OFFSET TIMTBL
        JMP     SHORT ENTRY

DSK_INT:
        PUSH    SI
        MOV     SI,OFFSET DSKTBL

; The DOS stack is shallow and the ROM services need more, so requests
; run on a private stack.  Mask IRQs explicitly: vaeg can deliver one
; between MOV SS and MOV SP despite the expected interrupt shadow.
ENTRY:  MOV     CS:[SAVESP],SP
        MOV     CS:[SAVESS],SS
        MOV     CS:[SAVEAX],AX
        MOV     AX,CS
        PUSHF
        CLI
        POP     CS:[SAVEFL]
        MOV     SS,AX
        MOV     SP,OFFSET STKTOP
        PUSH    CS:[SAVEFL]
        POPF
        MOV     AX,CS:[SAVEAX]
        CLD
        PUSH    AX
        PUSH    CX
        PUSH    DX
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        PUSH    BX

        LDS     BX,CS:[PTRSAV]
        MOV     AL,[BX.UNIT]
        MOV     AH,[BX.MEDIA]
        MOV     CX,[BX.COUNT]
        MOV     DX,[BX.START]
        XCHG    DI,AX
        MOV     AL,[BX.CMD]
        XOR     AH,AH
        CMP     AL,12
        JA      HICMD
        ADD     SI,AX
        ADD     SI,AX
        XCHG    AX,DI
        LES     DI,[BX.TRANS]
        PUSH    CS
        POP     DS
        JMP     WORD PTR [SI]

; Commands above 12 exist only for the disk: 19 generic IOCTL and
; 23/24 get/set logical drive map.
HICMD:  CMP     SI,OFFSET DSKTBL
        JNE     CMDERR
        XCHG    AX,DI           ;AL = unit, DI = command.
        PUSH    CS
        POP     DS
        CMP     DI,19
        JNE     HICMD1
        JMP     DSK_GIO
HICMD1: CMP     DI,23
        JB      CMDERR
        CMP     DI,24
        JA      CMDERR
        JMP     DSK_OWN

BUS_EXIT:
        MOV     AH,00000011B    ;Busy and done.
        JMP     SHORT EXIT1

CMDERR: MOV     AL,3            ;Unknown command.

ERR_EXIT:
        MOV     AH,10000001B    ;Error and done.
        JMP     SHORT EXIT1

EXITP   PROC    FAR
EXIT:   MOV     AH,00000001B    ;Done.
; ROM services may return with DF set; DOS string instructions expect
; DF=0, so clear it on every return.
EXIT1:  CLD
        LDS     BX,CS:[PTRSAV]
        MOV     [BX.STATUS],AX
        POP     BX
        POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     DX
        POP     CX
        POP     AX
        PUSHF
        CLI
        POP     CS:[SAVEFL]
        MOV     SS,CS:[SAVESS]
        MOV     SP,CS:[SAVESP]
        PUSH    CS:[SAVEFL]
        POPF
        POP     SI
        RET
EXITP   ENDP

; Called by SYSINIT after DOS initialization with all registers to be
; preserved.  DOS sets INT 2Ah-3Fh to its own handlers; give INT 33h back
; to the ROM mouse BIOS.
REINITP PROC    FAR
RE_INIT:
        PUSH    AX
        PUSH    DS
        XOR     AX,AX
        MOV     DS,AX
        MOV     AX,WORD PTR CS:[OLD33]
        MOV     DS:[33H*4],AX
        MOV     AX,WORD PTR CS:[OLD33+2]
        MOV     DS:[33H*4+2],AX
        ; DCh is free on VA/VA2 (technical manual 2.1, C0h-FFh).
        PUSHF
        CLI
        MOV     WORD PTR DS:[0DCH*4],OFFSET KEYINT
        MOV     DS:[0DCH*4+2],CS
        POPF
        POP     DS
        POP     AX
        RET
REINITP ENDP

OLD33   DD      0               ;ROM mouse BIOS vector.

; Variables that the MS-DOS 4.0 SYSINIT expects in the BIOS.  They serve
; the IBM hardware stacks (unused here: no STACKS= by default for this
; model byte), MULTITRACK=, 3.5-inch drive flags and extended keyboard
; selection, none of which this BIOS uses.
Int19sem DB     0
        IRP     AA,<02,08,09,0A,0B,0C,0D,0E,70,72,73,74,76,77>
Int19OLD&AA DD  -1
        ENDM
MulTrk_flag DW  0
EC35_Flag DB    0
KEYRD_Func DB   0
KEYSTS_Func DB  1

        SUBTTL  Console.
        PAGE

CHAR    DB      0               ;Cached ordinary character, or 0.
KEYNEXT DW      0               ;Offset of next string byte, or 0.
OUTBUF  DB      0,0             ;NUL-terminated output string.
ESCSTATE DB     0              ;Pending CON escape prefix (see OUTCHR).
OUTLEAD DB      0              ;Pending Shift-JIS lead, across CON writes.
LABELON DB      -1              ;-1 until initialized, 0 hidden, 10 shown.

; NEC CON key table: 20 x 16 bytes followed by 11 x 6 bytes. Each
; slot has a NUL terminator; the F-key prefix is display metadata.
NECFKEY MACRO   field,letter
        DB      0FEH,field,1BH,letter,8 DUP (0)
        ENDM

CONKEYS LABEL   BYTE
        NECFKEY <' C1  '>,'S'
        NECFKEY <' CU  '>,'T'
        NECFKEY <' CA  '>,'U'
        NECFKEY <' S1  '>,'V'
        NECFKEY <' SU  '>,'W'
        NECFKEY <'VOID '>,'E'
        NECFKEY <'NWL  '>,'J'
        NECFKEY <'INS  '>,'P'
        NECFKEY <'REP  '>,'Q'
        NECFKEY <' ^Z  '>,'Z'
        DB      'dir a:',0DH,9 DUP (0)
        DB      'dir b:',0DH,9 DUP (0)
        DB      'copy ',11 DUP (0)
        DB      'del ',12 DUP (0)
        DB      'ren ',12 DUP (0)
        DB      'chkdsk a:',0DH,6 DUP (0)
        DB      'chkdsk b:',0DH,6 DUP (0)
        DB      'type ',11 DUP (0)
        DB      'date',0DH,11 DUP (0)
        DB      'time',0DH,11 DUP (0)
CONEDIT LABEL   BYTE
        DB      6 DUP (0)       ;ROLL UP
        DB      6 DUP (0)       ;ROLL DOWN
        DB      1BH,'P',4 DUP (0) ;INS
        DB      1BH,'D',4 DUP (0) ;DEL
        DB      0BH,5 DUP (0)   ;UP
        DB      08H,5 DUP (0)   ;LEFT
        DB      0CH,5 DUP (0)   ;RIGHT
        DB      0AH,5 DUP (0)   ;DOWN
        DB      1AH,5 DUP (0)   ;HOME/CLR
        DB      6 DUP (0)       ;HELP
        DB      1EH,5 DUP (0)   ;SHIFT+HOME/CLR

; NEC INT DCh programmable keys, DS:DX = buffer. AX and flags unchanged.
; AX=0 is the compact table; FFh uses PC-98 ordering, including slots
; for keys not wired up on VA (zero on read, ignored on write).
KEYINT  PROC    FAR
        CMP     CL,0CH
        JE      KIENTER
        CMP     CL,0DH
        JE      KIENTER
        IRET
KIENTER:PUSH    AX
        PUSH    BX
        PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    ES
        PUSH    DS
        CLD
        MOV     DI,DX           ;Caller buffer, kept in ES:DI.
        PUSH    DS
        POP     ES
        PUSH    CS
        POP     DS
        MOV     DL,CL           ;Operation, preserved by helpers.
        MOV     BX,AX           ;Slot number or bulk selector.
        CMP     BX,0FFH
        JE      KIFULL
        CMP     BX,3AH
        JE      KICTRL
        CMP     BX,39H
        JA      KIDONE
        CMP     BX,1
        JB      KICOMPACT
        CMP     BX,31
        JBE     KISINGLE
        MOV     CX,16
        CALL    KIZERO
        JMP     SHORT KIDONE
KICTRL: MOV     CX,11*16
        CALL    KIZERO
        JMP     SHORT KIDONE
KISINGLE:
        MOV     DH,BL
        CALL    KISLOT
        JMP     SHORT KIDONE
KICOMPACT:
        MOV     BX,1
        MOV     DH,31
        CALL    KIRANGE
        JMP     SHORT KIDONE
KIFULL: MOV     BX,1
        MOV     DH,10
        CALL    KIRANGE
        MOV     CX,5*16         ;VF1–VF5.
        CALL    KIZERO
        MOV     DH,20
        CALL    KIRANGE
        MOV     CX,5*16         ;Shift+VF1–VF5.
        CALL    KIZERO
        MOV     DH,31
        CALL    KIRANGE
        MOV     CX,15*16        ;Ctrl+F1–F10 and Ctrl+VF1–VF5.
        CALL    KIZERO
KIDONE: POP     DS
        POP     ES
        POP     DI
        POP     SI
        POP     DX
        POP     CX
        POP     BX
        POP     AX
        IRET
KEYINT  ENDP

KIZERO: CMP     DL,0CH
        JNE     KISKIP
        XOR     AL,AL
        REP     STOSB
        RET
KISKIP: ADD     DI,CX
        RET

; Transfer BX through DH inclusive. BX advances to the next selector.
KIRANGE:CALL    KISLOT
        INC     BX
        CMP     BL,DH
        JBE     KIRANGE
        RET

KISLOT: MOV     AX,BX
        DEC     AX
        CMP     BX,20
        JA      KIEDIT
        MOV     CL,4
        SHL     AX,CL
        ADD     AX,OFFSET CONKEYS
        MOV     CX,16
        JMP     SHORT KIXFER
KIEDIT: SUB     AX,20
        MOV     CL,6
        MUL     CL
        ADD     AX,OFFSET CONEDIT
        MOV     CX,6
KIXFER: MOV     SI,AX
        CMP     DL,0DH
        JE      KIWRITE
        REP     MOVSB
        RET
KIWRITE:MOV     [KEYNEXT],0     ;Drop an in-flight expanded string only.
        DEC     CX              ;Never store a nonzero final byte.
KIWCOPY:MOV     AL,ES:[DI]
        MOV     [SI],AL
        INC     DI
        INC     SI
        LOOP    KIWCOPY
        MOV     BYTE PTR [SI],0
        INC     DI
        CMP     [LABELON],-1
        JE      KIWBCK
        ; ES:DX = new ROM definition; CL = ROM soft-key number.
        ; DefSft is display-only (ROM expansion remains off).
        PUSH    BX
        PUSH    DX
        PUSH    DI
        PUSH    ES
        MOV     DX,SI
        SUB     DX,15
        CMP     BX,20
        JBE     KIROM
        ADD     DX,10
KIROM:  MOV     CX,BX
        CALL    ROMKEY
        POP     ES
        POP     DI
        POP     DX
        POP     BX
KIWBCK: RET

; DefSft is also used by INITTEXT. Keep DS and BP across the ROM call.
ROMKEY: PUSH    DS
        PUSH    BP
        PUSH    CS
        POP     ES
        MOV     AH,03H
        INT     82H
        CLD
        POP     BP
        POP     DS
        RET

; Peek: ZF=1 if no character is waiting, else ZF=0 and AL = byte.
; A selected string takes precedence over any later primitive queue
; entries. Status can cache a key but never advances its string.
CISTAT: MOV     AL,CS:[CHAR]
        OR      AL,AL
        JZ      CISTAP
        RET
CISTAP: PUSH    BX
        MOV     BX,CS:[KEYNEXT]
        OR      BX,BX
        JZ      CISTA0
        MOV     AL,CS:[BX]
        OR      AL,AL
        JZ      CISTAZ
        POP     BX
        RET
CISTAZ: MOV     CS:[KEYNEXT],0
CISTA0: PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
; PrmSnsK/PrmGetK bypass the JFP. Decode AH before falling back to AL,
; so a known special scan always uses the CON definition.
CISTA1: MOV     AH,0AH
        INT     82H
        JNC     CISTAG
        XOR     AL,AL
        JMP     CISTAR
CISTAG: MOV     AH,09H
        INT     82H
        MOV     DL,AL           ;Save internal code for ordinary keys.
        MOV     AL,AH
        SUB     AL,62H
        CMP     AL,10
        JB      CISTAF
        SUB     AL,20H
        CMP     AL,10
        JAE     CISTAE
        ADD     AL,10
CISTAF: XOR     AH,AH
        MOV     CL,4
        SHL     AX,CL
        MOV     BX,OFFSET CONKEYS
        ADD     BX,AX
        CMP     BYTE PTR CS:[BX],0FEH
        JNE     CISTAS
        ADD     BX,6
        JMP     SHORT CISTAS

CISTAE: MOV     AL,AH           ;Shift and Ctrl arrows share base slots.
        CMP     AL,0AAH
        JB      CISTAB
        CMP     AL,0ADH
        JBE     CISTAX
        CMP     AL,0AEH
        JE      CISTAH
        CMP     AL,0BAH
        JB      CISTAA
        CMP     AL,0BDH
        JA      CISTAA
        SUB     AL,10H
CISTAX: SUB     AL,70H
CISTAB: SUB     AL,36H
        CMP     AL,10
        JB      CISTAI
CISTAA: MOV     AL,DL
        OR      AL,AL
        JZ      CISTA1          ;Unknown scan without an internal code.
        MOV     CS:[CHAR],AL
        JMP     SHORT CISTAR
CISTAH: MOV     AL,10           ;SHIFT+HOME/CLR follows HELP.
CISTAI: XOR     AH,AH
        MOV     BL,6
        MUL     BL
        MOV     BX,OFFSET CONEDIT
        ADD     BX,AX
CISTAS: MOV     AL,CS:[BX]
        OR      AL,AL
        JNZ     CISTAC
        JMP     CISTA1          ;Empty definition; try the next key.
CISTAC: MOV     CS:[KEYNEXT],BX
CISTAR: POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     SI
        POP     DX
        POP     CX
        POP     BX
        OR      AL,AL
        RET

CINP:   CALL    CISTAT
        JZ      CINP
        CMP     CS:[KEYNEXT],0
        JE      CINP1
        INC     CS:[KEYNEXT]
        RET
CINP1:  MOV     CS:[CHAR],0
        RET

CON_RDND:
        CALL    CISTAT
        JZ      CON_RDN2
        LDS     BX,CS:[PTRSAV]
        MOV     [BX.MEDIA],AL
        JMP     EXIT
CON_RDN2:
        JMP     BUS_EXIT

CON_READ:
        JCXZ    CON_REA9
CON_REA1:
        CALL    CINP
        CLD                     ;The keyboard BIOS may change DF.
        STOSB
        LOOP    CON_REA1
CON_REA9:
        JMP     EXIT

CON_FLSH:
        MOV     [CHAR],0
        MOV     [KEYNEXT],0
        CALL    CISTAT          ;Drain ROM queue, discarding whole strings.
        JNZ     CON_FLSH
        JMP     EXIT

CON_WRIT:
        JCXZ    CON_WRI9
        MOV     SI,DI
CON_WRI1:
        MOV     AL,ES:[SI]
        INC     SI
        CALL    OUTCHR
        LOOP    CON_WRI1
CON_WRI9:
        JMP     EXIT

; Only four CON sequences are special. Keep the pending prefix across
; requests; on a mismatch replay its printable bytes, then retry AL
; (which may itself be ESC). No other bytes go to the ROM's parser.
OUTCHR: CMP     [ESCSTATE],0
        JNE     OUTPEND
        JMP     OUTNEW
OUTPEND:CMP     [ESCSTATE],1   ;ESC
        JE      OUTCSI
        CMP     [ESCSTATE],2   ;ESC[
        JE      OUTARGS
        CMP     [ESCSTATE],3   ;ESC[>
        JE      OUTONE
        CMP     [ESCSTATE],4   ;ESC[>1
        JE      OUTLABEL
        CMP     AL,'J'         ;ESC[2
        JNE     OUTREPLAY
        MOV     AX,1702H       ;Erascn: clear current screen, not system row.
        JMP     SHORT OUTESC
OUTCSI: CMP     AL,'['
        JE      OUTNEXT
        JMP     SHORT OUTREPLAY
OUTARGS:CMP     AL,'>'
        JE      OUTNEXT
        CMP     AL,'2'
        JE      OUTTWO
        CMP     AL,'H'
        JNE     OUTREPLAY
        MOV     AH,08H         ;Locate: home (DX=0 below).
        JMP     SHORT OUTESC
OUTONE: CMP     AL,'1'
        JE      OUTNEXT
        JMP     SHORT OUTREPLAY
OUTLABEL:
        CMP     AL,'h'
        JE      OUTHIDE
        CMP     AL,'l'
        JNE     OUTREPLAY
        MOV     AX,2F0AH
        JMP     SHORT OUTESC
OUTHIDE:MOV     AX,2F00H
OUTESC: MOV     [ESCSTATE],0
        JMP     OUTCALL
OUTTWO: MOV     [ESCSTATE],5
        RET
OUTNEXT:INC     [ESCSTATE]
        RET

OUTREPLAY:
        PUSH    AX
        CMP     [ESCSTATE],1
        JE      OUTRESET
        MOV     AL,'['
        CALL    OUTCH1
        CMP     [ESCSTATE],2
        JE      OUTRESET
        MOV     AL,'2'
        CMP     [ESCSTATE],5
        JE      OUTLAST
        MOV     AL,'>'
        CALL    OUTCH1
        CMP     [ESCSTATE],4
        JNE     OUTRESET
        MOV     AL,'1'
OUTLAST:CALL    OUTCH1
OUTRESET:
        POP     AX
        MOV     [ESCSTATE],0
OUTNEW: CMP     [OUTLEAD],0
        JE      OUTSINGLE
        CMP     AL,40H
        JB      OUTBAD
        CMP     AL,7FH
        JE      OUTBAD
        CMP     AL,0FCH
        JBE     OUTPAIR
OUTBAD: MOV     [OUTLEAD],0     ;Do not join bytes across controls or ESC.
OUTSINGLE:
        CMP     AL,1BH
        JE      OUTNEXT
        CMP     AL,81H
        JB      OUTANK
        CMP     AL,9FH
        JBE     OUTSAVE
        CMP     AL,0E0H
        JB      OUTCH1          ;A0h-DFh (includes half-width kana).
        CMP     AL,0FCH
        JA      OUTCH1          ;FDh-FFh are single-byte codes here.
OUTSAVE:MOV     [OUTLEAD],AL
        RET
OUTPAIR:PUSH    DX
        MOV     DH,[OUTLEAD]
        MOV     DL,AL
        MOV     [OUTLEAD],0
        CMP     DH,0EFH         ;Chuput's documented lead range ends at EFh.
        JBE     OUTDBCS         ;Keep the two-column width for unsupported pairs.
        MOV     DX,8140H        ;Full-width space.
OUTDBCS:XOR     AH,AH           ;Chuput: DX = complete Shift-JIS character.
        CALL    OUTCALL
        POP     DX
        RET

; Keep the J0.4 control filter; allow the ROM's 80h ANK glyph too.
OUTANK:
        CMP     AL,0DH
        JE      OUTCH1
        CMP     AL,0AH
        JE      OUTCH1
        CMP     AL,08H
        JE      OUTCH1
        CMP     AL,20H
        JB      OUTCH9
        CMP     AL,7FH
        JE      OUTCH9
OUTCH1: MOV     AH,02H         ;Putstr, a single filtered byte.
OUTCALL:PUSH    AX
        PUSH    BX
        PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        PUSH    CS
        POP     DS
        CMP     AH,2FH
        JE      OUTMODE
        OR      AH,AH
        JZ      OUTINT          ;Chuput already has its character in DX.
        XOR     DX,DX          ;Locate coordinates (0,0).
        CMP     AH,02H
        JNE     OUTINT
        MOV     [OUTBUF],AL
        MOV     SI,OFFSET OUTBUF
        MOV     DX,8000H
OUTINT: INT     83H
        JMP     SHORT OUTREGS
OUTMODE:CALL    LABELMODE
OUTREGS:POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     SI
        POP     DX
        POP     CX
        POP     BX
        POP     AX
OUTCH9: RET

; The two layouts share the main framebuffer. The system buffer starts
; after all 25 main rows, so the split can change without copying text.
MAIN25  DB      00H,0,0,0,25,05H,07H,0
MAIN24  DB      00H,0,0,0,24,05H,07H,0  ;Wrap and vertical scroll.
        DB      41H,0,0,0,1,10H,07H,0   ;System line, attribute mode 1.

; AL = requested label count (0 or 10). Caller saves all registers.
LABELMODE:
        CMP     [LABELON],-1
        JE      LABELRET
        CMP     [LABELON],AL
        JE      LABELRET
        OR      AL,AL
        JNZ     LABELPOS
        INT     83H             ;SftCtl off while the system row exists.
        JC      LABELRET
LABELPOS:
        MOV     AH,26H          ;Askloc: Spltscn resets the cursor.
        INT     83H
        CMP     CS:[LABELON],0
        JNE     LABELEXP
        CMP     DL,24
        JNE     LABELSHR
        DEC     DL              ;When showing with cursor on row 25,
        PUSH    DX              ;scroll once to keep its text visible.
        MOV     AH,0DH          ;Index scrolls at the bottom margin.
        INT     83H
        POP     DX
LABELSHR:
        PUSH    DX
        CALL    SPLIT24
        JC      LABELPOP
        MOV     AX,2F0AH        ;SftCtl on, shift-aware.
        INT     83H
        MOV     BYTE PTR CS:[LABELON],10
        JMP     SHORT LABELPOP
LABELEXP:
        PUSH    DX
        MOV     BP,OFFSET MAIN25
        MOV     CX,1
        CALL    SETSPLIT
        JC      LABELREC
        MOV     DX,24           ;The old hidden row may contain stale
        MOV     AH,08H          ;text. Clear it before restoring cursor.
        INT     83H
        MOV     AX,1802H        ;Eralin: whole current line.
        INT     83H
        MOV     BYTE PTR CS:[LABELON],0
        JMP     SHORT LABELPOP
LABELREC:
        MOV     AX,2F0AH        ;Split rejected: keep labels on.
        INT     83H
LABELPOP:
        POP     DX
        MOV     AH,08H
        INT     83H
LABELRET: RET

SPLIT24:MOV     BP,OFFSET MAIN24
        MOV     CX,2
SETSPLIT:
        PUSH    CS
        POP     ES
        MOV     AX,1D00H        ;Spltscn: select main screen 0.
        INT     83H
        RET

        SUBTTL  AUX and clock.
        PAGE

AUX_READ:
        JCXZ    AUX_REA9
        MOV     AL,1AH          ;End of file.
        REP     STOSB
AUX_REA9:
        JMP     EXIT

; CLOCK$ reads and sets the PC-88VA calendar.
        INCLUDE VACLOCK.INC

TIM_RED:
        CALL    VA_RDCLK
        JMP     EXIT

TIM_WRT:
        CALL    VA_WRCLK
        JMP     EXIT

        SUBTTL  Floppy disk.
        PAGE

BPB     DW      SECSIZ          ;Bytes per sector.
        DB      1               ;Sectors per cluster.
        DW      1               ;Reserved sectors.
        DB      2               ;FATs.
        DW      192             ;Root directory entries.
        DW      1280            ;Total sectors.
        DB      0FEH            ;Media descriptor.
        DW      2               ;Sectors per FAT.
        DW      SECTRK          ;Sectors per track.
        DW      NHEADS          ;Heads.
        DD      0               ;Hidden sectors.
        DD      0               ;Total sectors when the word above is 0.

BPBTAB  DW      BPB,BPB

CALLFL  DW      0245H           ;Flags for ROM disk calls.

DSK_INIT:
        LDS     BX,[PTRSAV]
        MOV     BYTE PTR [BX+INITUNITS],NUNITS
        MOV     WORD PTR [BX+INITBPB],OFFSET BPBTAB
        MOV     WORD PTR [BX+INITBPB+2],CS
        MOV     AL,0
        JMP     EXIT

; Read the boot sector into the DOS buffer at ES:DI and keep its volume
; serial number, label and file system type for IOCTL "get media ID".
; The BPB itself is the fixed 2HD BPB.
GET_BPB:
        CMP     AL,NUNITS
        JAE     BADUNIT
        MOV     [GUNIT],AL
        MOV     [OPCODE],81H
        MOV     CX,1
        XOR     DX,DX
        PUSH    ES
        PUSH    DI
        CALL    DSK_XFER
        POP     DI
        POP     ES
        JC      GBPB_ERR
        CALL    MIDSLOT         ;SI = cache slot of the unit.
        MOV     BYTE PTR [SI],0
        CMP     BYTE PTR ES:[DI+38],29H
        JNE     GBPB1
        MOV     BYTE PTR [SI],1
        PUSH    DS
        PUSH    ES
        PUSH    DS              ;Copy ES:DI+39 to DS:SI+1.
        PUSH    ES
        POP     DS
        POP     ES
        XCHG    SI,DI
        INC     DI
        ADD     SI,39
        MOV     CX,23
        REP     MOVSB
        POP     ES
        POP     DS
GBPB1:  LDS     BX,[PTRSAV]
        MOV     [BX.MEDIA],0FEH
        MOV     WORD PTR [BX+BPBPTR],OFFSET BPB
        MOV     WORD PTR [BX+BPBPTR+2],CS
        MOV     AL,0
        JMP     EXIT
GBPB_ERR:
        JMP     ERR_EXIT

; SI = media ID cache slot of unit [GUNIT].
MIDSLOT:
        MOV     AL,24
        MUL     [GUNIT]
        ADD     AX,OFFSET MIDCACHE
        MOV     SI,AX
        RET

BADUNIT:
        MOV     AL,1
        JMP     ERR_EXIT

        INCLUDE VAFDXFER.INC

        SUBTTL  Generic IOCTL.
        PAGE

; Generic IOCTL for the disk (category 08h).  AL = unit, DS = CS.
DSK_GIO:
        CMP     AL,NUNITS
        JAE     GIO_BAD
        MOV     [GUNIT],AL
        LDS     BX,[PTRSAV]
        CMP     BYTE PTR [BX+13],08H
        JNE     GIO_BAD
        MOV     AH,[BX+14]
        LES     DI,[BX+19]
        PUSH    CS
        POP     DS
        CMP     AH,60H
        JE      GIO_GDP
        CMP     AH,61H
        JE      GIO_RD
        CMP     AH,41H
        JE      GIO_WR
        CMP     AH,66H
        JE      GIO_GMI
        CMP     AH,67H
        JE      GIO_GAF
        CMP     AH,40H          ;Set device parameters: nothing to change.
        JE      GIO_OK
        CMP     AH,47H          ;Set access flag: always accessible.
        JE      GIO_OK
GIO_BAD:
        JMP     CMDERR

; Get device parameters: 80-cylinder removable drive with the 2HD BPB.
GIO_GDP:
        MOV     BYTE PTR ES:[DI+1],1
        MOV     WORD PTR ES:[DI+2],0
        MOV     WORD PTR ES:[DI+4],80
        MOV     BYTE PTR ES:[DI+6],0
        ADD     DI,7
        MOV     SI,OFFSET BPB
        MOV     CX,25
        REP     MOVSB
        XOR     AL,AL
        MOV     CX,6
        REP     STOSB
GIO_OK: MOV     AL,0
        JMP     EXIT

GIO_GAF:
        MOV     BYTE PTR ES:[DI+1],1
        JMP     GIO_OK

; Read or write track: head, cylinder, first sector (0-based), count and
; transfer address in the packet at ES:DI.
GIO_RD: MOV     [OPCODE],81H
        JMP     SHORT GIO_TRK
GIO_WR: MOV     [OPCODE],82H
GIO_TRK:
        MOV     DX,ES:[DI+3]
        SHL     DX,1
        ADD     DX,ES:[DI+1]
        MOV     CL,3
        SHL     DX,CL
        ADD     DX,ES:[DI+5]
        MOV     CX,ES:[DI+7]
        LES     DI,ES:[DI+9]
        MOV     AL,[GUNIT]
        CALL    DSK_XFER
        JNC     GIO_OK
        JMP     ERR_EXIT

; Get media ID from the boot sector data cached by GET_BPB.
GIO_GMI:
        CALL    MIDSLOT
        CMP     BYTE PTR [SI],0
        JE      GIO_NMI
        INC     SI
        ADD     DI,2
        MOV     CX,23
        REP     MOVSB
        JMP     GIO_OK
GIO_NMI:
        MOV     AL,7            ;No extended BPB on this disk.
        JMP     ERR_EXIT

; Get/set logical drive map: each unit has a single drive letter.
DSK_OWN:
        LDS     BX,[PTRSAV]
        MOV     BYTE PTR [BX+1],0
        MOV     AL,0
        JMP     EXIT

GUNIT   DB      0
MIDCACHE DB     NUNITS*24 DUP (0) ;Per unit: valid flag, serial, label, type.

        SUBTTL  Initialization (overlaid by MSDOS.SYS).
        PAGE

RESEND  LABEL   BYTE            ;End of the resident BIOS.

; Entered from VABOOT with DX = MSDOS.SYS segment.  Keep the boot stack:
; SYSINIT moves MSDOS.SYS over this initialization code while it still
; uses the stack it inherits, so that stack must lie outside IO.SYS.
HWINIT: CLD
        XOR     AX,AX
        MOV     ES,AX
        MOV     AX,ES:[33H*4]
        MOV     WORD PTR CS:[OLD33],AX
        MOV     AX,ES:[33H*4+2]
        MOV     WORD PTR CS:[OLD33+2],AX
        PUSH    DX              ;Keep the loaded kernel segment.
        CALL    INITTEXT
        POP     BP
        CLD
        CALL    MEMSIZE         ;AX = memory size in paragraphs.
        MOV     CX,AX
        MOV     AX,OFFSET RESEND
        ADD     AX,15
        PUSH    CX
        MOV     CL,4
        SHR     AX,CL
        POP     CX
        MOV     DX,CS
        ADD     DX,AX           ;DX = final DOS segment.

        MOV     AX,SYSINITSEG
        MOV     DS,AX
        ASSUME  DS:SYSINITSEG
        MOV     [CURRENT_DOS_LOCATION],BP
        MOV     [FINAL_DOS_LOCATION],DX
        MOV     [MEMORY_SIZE],CX
        MOV     WORD PTR [DEVICE_LIST],OFFSET DEVSTART
        MOV     WORD PTR [DEVICE_LIST+2],CS
        MOV     [DEFAULT_DRIVE],0
        ASSUME  DS:CODE
        JMP     SYSINIT

; J0.1 text-BIOS split. Define the ROM strings for display only; the
; DOS input queue and expansion continue to use CONKEYS/CONEDIT.
TEXTBUFS DW     0
        DB      80,25
        DW      0FA0H           ;80 columns * 25 rows * 2 bytes.
        DB      80,1

INITTEXT:
        MOV     AX,2404H        ;CrtCtl: 80x25, text on, non-interlaced.
        INT     83H
        PUSH    CS
        POP     ES
        MOV     BP,OFFSET TEXTBUFS
        MOV     CX,2
        MOV     AX,1C00H        ;Allocfb: main and system buffers.
        INT     83H
        JC      INITTX9
        CALL    SPLIT24
        JC      INITTX9
        MOV     AX,0201H        ;ExpCtrl: disable ROM key expansion.
        INT     82H
        MOV     CX,1
        MOV     DX,OFFSET CONKEYS
INITKEY:PUSH    CX
        PUSH    DX
        CALL    ROMKEY
        POP     DX
        POP     CX
        ADD     DX,16
        CMP     CL,20
        JBE     INITKN
        SUB     DX,10           ;The 11 editing-key slots are 6 bytes.
INITKN: INC     CL
        CMP     CL,32
        JB      INITKEY
        MOV     AX,2F0AH
        INT     83H
        JC      INITTX9
        MOV     BYTE PTR CS:[LABELON],10
INITTX9:RET

; Measure writable conventional memory in 64 KB steps above IO.SYS.
; Each probed word is restored; backup memory settings are not used.
MEMSIZE:
        MOV     BX,2000H
MEMSZ1: MOV     ES,BX
        MOV     AX,ES:[0]
        MOV     WORD PTR ES:[0],5AA5H
        MOV     DX,ES:[0]
        MOV     WORD PTR ES:[0],0A55AH
        MOV     SI,ES:[0]
        MOV     ES:[0],AX
        CMP     DX,5AA5H
        JNE     MEMSZ9
        CMP     SI,0A55AH
        JNE     MEMSZ9
        ADD     BX,1000H
        CMP     BX,0A000H
        JB      MEMSZ1
MEMSZ9: MOV     AX,BX
        RET

CODE    ENDS

        END
