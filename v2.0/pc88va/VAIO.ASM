        TITLE   IO.SYS for the NEC PC-88VA (MS-DOS 2.0 experiment)

; SPDX-License-Identifier: MIT
;
; Derived from v2.0/source/SKELIO.ASM, the skeletal MS-DOS 2.0 BIOS for
; the Altos ACS-86C.  The device request framework (strategy, dispatch
; tables, common exit) follows SKELIO; console, disk and initialization
; use the PC-88VA ROM BIOS instead of the Altos monitor.  Link order is
; VAIO - SYSINIT - SYSIMES, using the Microsoft-supplied 2.0 objects.
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
        DB      'CLOCK   '

DSKDEV: DW      -1,-1           ;Last device.
        DW      2000H           ;Block device, media byte from the BPB.
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
        JA      CMDERR
        ADD     SI,AX
        ADD     SI,AX
        XCHG    AX,DI
        LES     DI,[BX.TRANS]
        PUSH    CS
        POP     DS
        JMP     WORD PTR [SI]

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

REINITP PROC    FAR
RE_INIT:
        RET                     ;Nothing to do after DOS initialization.
REINITP ENDP

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

BPBTAB  DW      BPB,BPB

CALLFL  DW      0245H           ;Flags for ROM disk calls.
OPCODE  DB      0               ;81H read, 82H write.
DRIVE   DB      0
TRACK   DB      0               ;Cylinder * 2 + head.
SECTOR  DB      0               ;1-based sector.
TRIES   DB      0

DSK_INIT:
        LDS     BX,[PTRSAV]
        MOV     BYTE PTR [BX+INITUNITS],NUNITS
        MOV     WORD PTR [BX+INITBPB],OFFSET BPBTAB
        MOV     WORD PTR [BX+INITBPB+2],CS
        MOV     AL,0
        JMP     EXIT

; The ROM does not report changes; "don't know" lets DOS decide.
MEDIAC: CMP     AL,NUNITS
        JAE     BADUNIT
        LDS     BX,[PTRSAV]
        MOV     BYTE PTR [BX+MEDSTAT],0
        MOV     AL,0
        JMP     EXIT

GET_BPB:
        CMP     AL,NUNITS
        JAE     BADUNIT
        LDS     BX,[PTRSAV]
        MOV     [BX.MEDIA],0FEH
        MOV     WORD PTR [BX+BPBPTR],OFFSET BPB
        MOV     WORD PTR [BX+BPBPTR+2],CS
        MOV     AL,0
        JMP     EXIT

BADUNIT:
        MOV     AL,1
        JMP     ERR_EXIT

; AL = unit, ES:DI = transfer address, CX = sectors, DX = first sector.
DSK_RED:
        MOV     [OPCODE],81H
        JMP     SHORT DSK_COM
DSK_WRT:
        MOV     [OPCODE],82H
DSK_COM:
        CMP     AL,NUNITS
        JAE     BADUNIT
        MOV     [DRIVE],AL
        JCXZ    DSK_DONE
DSK_SEC:
        PUSH    CX
        MOV     AX,DX
        AND     AL,SECTRK-1
        INC     AL
        MOV     [SECTOR],AL
        MOV     AX,DX
        MOV     CL,3            ;Divide by SECTRK.
        SHR     AX,CL
        MOV     [TRACK],AL
        MOV     [TRIES],3
DSK_TRY:
        PUSH    DX
        PUSH    DI
        PUSH    ES
        PUSH    DS
        MOV     AH,0AH          ;Select the 2HD/1024-byte mode.
        MOV     AL,FDMODE
        MOV     CH,[DRIVE]
        PUSH    CS:[CALLFL]
        POPF
        INT     80H
        POP     DS
        PUSH    DS
        JC      DSK_FAIL
        OR      AH,AH
        JNZ     DSK_FAIL
        MOV     BP,DI           ;ES:BP = transfer address.
        MOV     AL,[TRACK]
        MOV     CL,AL
        MOV     CH,[DRIVE]
        MOV     BH,AL
        SHR     BH,1            ;Cylinder.
        MOV     BL,AL
        AND     BL,1            ;Head.
        MOV     DH,[SECTOR]
        MOV     DL,SECLEN
        MOV     AH,[OPCODE]
        MOV     AL,1
        PUSH    CS:[CALLFL]
        POPF
        INT     80H
        JC      DSK_FAIL
        OR      AH,AH
        JNZ     DSK_FAIL
        POP     DS
        POP     ES
        POP     DI
        POP     DX
        MOV     AX,ES           ;Advance by one sector.
        ADD     AX,SECSIZ/16
        MOV     ES,AX
        INC     DX
        POP     CX
        LOOP    DSK_SEC
DSK_DONE:
        MOV     AL,0
        JMP     EXIT

DSK_FAIL:
        POP     DS
        POP     ES
        POP     DI
        POP     DX
        DEC     [TRIES]
        JNZ     DSK_TRY
        POP     CX
        LDS     BX,CS:[PTRSAV]
        MOV     [BX.COUNT],0
        MOV     AL,11           ;Read fault.
        CMP     CS:[OPCODE],82H
        JNE     DSK_FL1
        MOV     AL,10           ;Write fault.
DSK_FL1:
        JMP     ERR_EXIT

        SUBTTL  Initialization (overlaid by MSDOS.SYS).
        PAGE

RESEND  LABEL   BYTE            ;End of the resident BIOS.

; Entered from VABOOT with DX = MSDOS.SYS segment.  Keep the boot stack:
; SYSINIT moves MSDOS.SYS over this initialization code while it still
; uses the stack it inherits, so that stack must lie outside IO.SYS.
HWINIT: CLD
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
