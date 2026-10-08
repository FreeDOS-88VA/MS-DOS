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
; run on a private stack.  MOV SS inhibits interrupts for one instruction.
ENTRY:  MOV     CS:[SAVESP],SP
        MOV     CS:[SAVESS],SS
        MOV     CS:[SAVEAX],AX
        MOV     AX,CS
        MOV     SS,AX
        MOV     SP,OFFSET STKTOP
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
        MOV     SS,CS:[SAVESS]
        MOV     SP,CS:[SAVESP]
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

CHAR    DB      0               ;One-character type-ahead.
OUTBUF  DB      0,0             ;NUL-terminated output string.

; Return ZF=1 if no character is waiting, else ZF=0 and AL = character.
; Read the primitive KB queue (functions 0Ah and 09h), which bypasses the
; Japanese front-end processor; keys without an internal code are dropped.
CISTAT: MOV     AL,CS:[CHAR]
        OR      AL,AL
        JNZ     CISTA9
        PUSH    BX
        PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
CISTA1: MOV     AH,0AH          ;Sense the KB queue: CF=1 if empty.
        INT     82H
        JC      CISTA8
        MOV     AH,09H          ;Take the key code.
        INT     82H
        OR      AL,AL           ;AL = internal code.
        JZ      CISTA1
        MOV     CS:[CHAR],AL
CISTA8: MOV     AL,CS:[CHAR]
        POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     SI
        POP     DX
        POP     CX
        POP     BX
        OR      AL,AL
CISTA9: RET

CINP:   CALL    CISTAT
        JZ      CINP
        MOV     CS:[CHAR],0
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
        STOSB
        LOOP    CON_REA1
CON_REA9:
        JMP     EXIT

CON_FLSH:
        MOV     [CHAR],0
CON_FLS1:
        CALL    CISTAT
        JZ      CON_FLS9
        MOV     [CHAR],0
        JMP     CON_FLS1
CON_FLS9:
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

; Write AL through the text BIOS.  Like the FreeDOS PC-88VA console,
; pass CR, LF, BS and printable ASCII and drop other control codes.
OUTCHR: CMP     AL,0DH
        JE      OUTCH1
        CMP     AL,0AH
        JE      OUTCH1
        CMP     AL,08H
        JE      OUTCH1
        CMP     AL,20H
        JB      OUTCH9
        CMP     AL,7EH
        JA      OUTCH9
OUTCH1: PUSH    AX
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
        MOV     [OUTBUF],AL
        MOV     SI,OFFSET OUTBUF
        MOV     DX,8000H
        MOV     AH,02H
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
OUTCH9: RET

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
        PUSH    CS
        POP     DS
        MOV     BP,DX
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
