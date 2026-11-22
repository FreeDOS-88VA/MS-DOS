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

DSKDEV: DW      -1,-1           ;HWINIT may append HDDDEV.
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
        JMP     SHORT ENTRY

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
; 23/24 get/set logical drive map. Only the linked HDDDEV can enter
; with HDTABLE; the optional tail is not called on a floppy-only boot.
HICMD:  CMP     SI,OFFSET HDTABLE
        JNE     HIFLOP
        XCHG    AX,DI           ;AL = unit, DI = command.
        PUSH    CS
        POP     DS
        JMP     HDHIGH
HIFLOP: CMP     SI,OFFSET DSKTBL
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
ESCOCTETS EQU   96             ;Hard bound, including discarded parameters.
ESCSTATE DB     0              ;0=idle, 1=ESC, 2=CSI, 3/4=direct, 5=ESC ).
ESCBUDGET DB    0              ;Byte budget left in the current CSI.
ESCPRIV DB      0              ;0, '>', '?', or -1 for invalid parameters.
ESCN    DB      0              ;Index of current parameter (8 slots).
ESCARGS DB      8 DUP (0)      ;Values saturate at 255; no unbounded buffer.
ESCROW  DB      0
ESCSAVED DW     0              ;Askloc coordinates for CSI s/u.
ESCREPNEXT DW   0              ;One pending CSI 6n response, 0 when empty.
ESCREP  DB      1BH,'[00;00R'
ESCREPEND LABEL BYTE
OUTLEAD DB      0              ;Pending Shift-JIS lead, across CON writes.
OUTWRAP DB      0              ;Logical column 81; BIOS cursor is at 80.
OUTGRAPH DB     0              ;ESC )3: display high bytes as ANK.
ESCSWRAP DB     0              ;Saved logical column, if beyond the edge.
LABELON DB      -1              ;-1 until initialized, 0 hidden, 10 shown.
JFPMODE DB      0               ;0 plain, 1 ROM, 2 ROM reservation, 3 project.
JFPLABEL DB     10              ;Requested label layout while row is reserved.
JFPDIRTY DB     0               ;The ROM may have drawn on the label row.
JFPTRAIL DB     0               ;Second byte of a cached Shift-JIS word.
JFPDRAIN DB     0               ;A confirmed ROM word still follows the current one.
JFPSHIFT DB     0               ;Shift state of our last idle label repaint.
JFPSEEN DB      0               ;After ROM use, idle plain labels may need help.
SYSTEXT EQU     80*25*2         ;System split follows the full main buffer.

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
        CMP     CL,0F0H         ;Private VA JFP mode handshake, not NEC KEY.
        JNE     KINOP
        CMP     AX,4A46H
        JNE     KINOP
        JMP     JFPINT
KINOP:  IRET
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
        MOV     [JFPDIRTY],1
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

; INT DC / CL=F0h, AX=4A46h. Reply AX=464Ah, BX=current mode.
; BX request: 0=query, 1=reserve for ROM, 2=commit ROM, 3=release,
; 4=commit master-disabled project FEP from reservation. Reply 3=project.
; 5=replace project dictionary (ES:SI validated records, DX byte size).
;    AX=554Ah on successful copy; BX still reports mode.
; Only JFP.COM calls the transition operations. No DOS or JFP reset here.
JFPINT: PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        PUSH    CS
        POP     DS
        CMP     BX,1
        JNE     JFPTEST2
        JMP     JFPRESV
JFPTEST2:CMP    BX,2
        JNE     JFPTEST3
        JMP     JFPCOMMIT
JFPTEST3:CMP    BX,3
        JE      JFPREL
        CMP     BX,4
        JE      JFPPROJECT
        CMP     BX,5
        JNE     JFPREPLY
        JMP     JFPLOAD
JFPPROJECT:CMP  [JFPMODE],2
        JNE     JFPREPLY
        XOR     CX,CX           ;GetJFP: require the expected master-off mode.
        INT     8DH
        CMP     AX,8F80H
        JNE     JFPREPLY
        CALL    JFPCLEAR
        MOV     CS:[JFPMODE],3
        MOV     CS:[JFPSEEN],1
        MOV     CS:[JFPDIRTY],1
        CALL    JFPRIDLE
JFPREPLY:JMP    JFPACK
JFPREL: CMP     [JFPMODE],3
        JE      JFPENDP
        CMP     [JFPMODE],0
        JNE     JFPOFF
        JMP     JFPACK
JFPENDP:CALL    FEPFLUSH
        MOV     [FEPUEND],OFFSET FEPUDATA
        MOV     [FEPWIDE],0
        MOV     [JFPMODE],0
        MOV     AL,[JFPLABEL]
        MOV     AH,2FH
        CALL    LABELMODE
        JMP     JFPACK
JFPOFF: MOV     [JFPMODE],0
        MOV     [JFPSEEN],1
        CALL    JFPCLEAR
        MOV     AX,2F00H        ;Back to the ROM's plain-mode label renderer.
        INT     83H
        MOV     AX,2F0AH
        INT     83H
        MOV     AL,[JFPLABEL]
        MOV     AH,2FH
        CALL    LABELMODE
        CMP     [LABELON],10
        JNE     JFPACK
        MOV     [JFPDIRTY],1    ;Some ROM states leave the row blank on exit.
        CALL    JFPRIDLE        ;No composition check on the plain path.
        JMP     SHORT JFPACK
JFPRESV:CMP     [JFPMODE],0
        JNE     JFPACK
        CALL    JFPROW
        CMP     [LABELON],10
        JNE     JFPACK
        MOV     [JFPMODE],2
        JMP     SHORT JFPACK
JFPCOMMIT:
        CMP     [JFPMODE],2
        JNE     JFPACK
        MOV     AH,0EH          ;KyBook: reject an uninitialized main path.
        INT     82H
        MOV     BX,DX
        MOV     AX,ES:[BX+01DEH] ;Documented JFPAddr field, 603KEYB §6.3.5.
        OR      AX,ES:[BX+01E0H]
        JZ      JFPACK
        MOV     DX,0440H        ;Check both documented conversion buffers.
        MOV     ES,DX
        MOV     AX,ES:[0]
        OR      AX,ES:[2]
        JZ      JFPACK
        MOV     AX,ES:[4]
        OR      AX,ES:[6]
        JZ      JFPACK
        MOV     CS:[JFPMODE],1
        CALL    JFPCLEAR
        MOV     CS:[JFPDIRTY],1
        CALL    JFPREFRESH
JFPACK: MOV     AX,464AH
JFPACKAX:XOR    BX,BX
        MOV     BL,CS:[JFPMODE]
        POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     SI
        POP     DX
        POP     CX
        IRET

JFPLOAD:CMP     [JFPMODE],3
        JNE     JFPACK
        CMP     [FEPCHOICE],0   ;Never invalidate a live candidate cursor.
        JNE     JFPACK
        CMP     DX,FEPUCAP
        JA      JFPACK
        MOV     AX,SI
        ADD     AX,DX
        JC      JFPACK
        MOV     CX,DX
JFPLOADN:JCXZ   JFPLOADC
        SUB     CX,FEPUREC
        JNC     JFPLOADN
        JMP     SHORT JFPACK
JFPLOADC:
        PUSH    ES              ;Source ES:SI, destination CS:DI.
        PUSH    DS
        POP     ES
        POP     DS
        CLD
        MOV     DI,OFFSET FEPUDATA
        MOV     CX,DX
        REP     MOVSB
        MOV     CS:[FEPUEND],DI ;Publish only once the whole copy is resident.
        MOV     AX,554AH
        JMP     SHORT JFPACKAX

JFPROW: MOV     AL,[LABELON]
        MOV     [JFPLABEL],AL
        MOV     AX,2F0AH
        JMP     LABELMODE

JFPCLEAR:
        MOV     CS:[CHAR],0
        MOV     CS:[JFPTRAIL],0
        MOV     CS:[JFPDRAIN],0
        MOV     CS:[KEYNEXT],0
        MOV     CS:[ESCREPNEXT],0
        RET

; Redraw the idle row without SftCtl/DefSft: while enabled those calls
; can leave ROM mode labels in the row or move composition inline.
; As in ESCBOUNDARY, save/restore the V3 window with IRQs masked.
; The text and attribute planes are 8000h bytes apart. Reproduce the
; J0.4 six-cell label fields (including the leading FEh display marker).
JFPREFRESH:
        CALL    JFPIDLE
        JE      JFPRIDLE
        RET
JFPRIDLE:MOV    AH,0BH          ;PrmSfts: left/right Shift in bits 0/1.
        INT     82H
        AND     AL,3
        CMP     AL,CS:[JFPSHIFT]
        JE      JFPRSAME
        MOV     CS:[JFPSHIFT],AL
        MOV     CS:[JFPDIRTY],1
JFPRSAME:CMP    CS:[JFPDIRTY],0
        JE      JFPRRET
        MOV     CS:[JFPDIRTY],0
        MOV     SI,OFFSET CONKEYS
        OR      AL,AL
        JZ      JFPRMAP
        ADD     SI,10*16
JFPRMAP:MOV     AX,0A000H
        MOV     ES,AX
        PUSHF
        CLI
        CLD
        MOV     DX,0152H
        IN      AX,DX
        PUSH    AX
        AND     AH,0F0H
        OR      AH,1            ;SMBC=1 maps TVRAM.
        OUT     DX,AX
        MOV     DI,SYSTEXT
        MOV     CX,80
        MOV     AX,20H
        REP     STOSW
        MOV     DI,SYSTEXT+8000H
        MOV     CX,80
        MOV     AX,70H
        REP     STOSW
        CMP     CS:[OUTGRAPH],0
        JE      JFPRFIELDS
        MOV     WORD PTR ES:[SYSTEXT+2],'g'
JFPRFIELDS:
        MOV     DI,SYSTEXT+8
        MOV     BX,10
JFPBOX: MOV     CX,6
        XOR     AH,AH
JFPBOXB:MOV     AL,CS:[SI]
        INC     SI
        STOSW
        MOV     WORD PTR ES:[DI+8000H-2],74H ;Mode 1, white reverse.
        LOOP    JFPBOXB
        ADD     SI,10           ;Next 16-byte key slot.
        ADD     DI,2            ;One space between fields.
        DEC     BX
        CMP     BX,5
        JNE     JFPBOXN
        ADD     DI,6            ;Three more spaces between the two groups.
JFPBOXN:OR      BX,BX
        JNZ     JFPBOX
        POP     AX
        OUT     DX,AX
        POPF
JFPRRET:RET

; Inspect the documented JFP work area (618JFP §6.18.6).
; ZF=1 if the conversion input buffer is empty. Preserve AX/BX.
JFPIDLE:MOV     DX,0440H
        MOV     ES,DX
        LES     DI,ES:[0]
        CMP     BYTE PTR ES:[DI],0
        RET

; Main SnsChar may consume a raw key without returning a character.
; In idle kana the ROM reserves some DOS soft keys for its own modes.
; Save those keys for DOS, but not ahead of a reading or a confirmed word.
JFPSENSE:
        PUSHF
        CLI
        CALL    JFPPOLL
        JC      JFPSNONE
        POPF
        CLC
        JMP     SHORT JFPSDRAW
JFPSNONE:POPF
        STC
JFPSDRAW:PUSHF
        PUSH    AX
        PUSH    BX
        CALL    JFPREFRESH
        POP     BX
        POP     AX
        POPF
        RET

JFPPOLL:MOV     AH,0AH
        INT     82H
        JNC     JFPHASRAW
        CMP     CS:[JFPDRAIN],0 ;Without raw input, only drain committed words.
        JNE     JFPMAIN
        STC
        RET
JFPHASRAW:
        CMP     CS:[JFPDRAIN],0
        JNE     JFPRAW
        CALL    JFPIDLE
        JNE     JFPRAW
        CMP     AL,03H          ;DOS break, ESC prefix, ordinary Backspace.
        JE      JFPPRIM
        CMP     AL,1BH
        JE      JFPPRIM
        CMP     AL,08H
        JE      JFPPRIM
        CMP     AH,8BH          ;Shift+F10 may also be consumed in narrow mode.
        JE      JFPPRIM
        MOV     ES,DX
        TEST    BYTE PTR ES:[10H],1  ;Active width (documented mode byte).
        JZ      JFPRAW
        CMP     AH,36H          ;ROLL, INS, DEL.
        JB      JFPRAW
        CMP     AH,39H
        JBE     JFPPRIM
        CMP     AH,67H          ;F6–F10.
        JB      JFPRAW
        CMP     AH,6BH
        JBE     JFPPRIM
        CMP     AH,82H          ;Shift+F1–F10.
        JB      JFPRAW
        CMP     AH,8BH
        JA      JFPRAW
JFPPRIM:MOV     AH,09H
        INT     82H
        MOV     BX,AX           ;Normalize scan/internal code to main ABI.
        XOR     AH,AH
        RET
JFPRAW: MOV     CS:[JFPDIRTY],1
JFPMAIN:MOV     AH,01H
        INT     82H
        JC      JFPNODATA
        XOR     AH,AH           ;Sensed ready: GetChar cannot block.
        INT     82H
        OR      AH,AH
        JZ      JFPHAVE
        CALL    JFPMORE
JFPHAVE:CLC
        RET
JFPNODATA:
        MOV     CS:[JFPDRAIN],0
        STC
        RET

; Tested ROMs retain the just-returned word in the conversion output
; buffer, clearing earlier words in place. A following word must reach
; CON before we reserve an idle raw key. Bound the scan by SetJFP's
; indirect limit, and leave the BIOS in charge if it doesn't match.
JFPMORE:MOV     CS:[JFPDRAIN],1
        MOV     DX,0440H
        MOV     ES,DX
        LES     DI,ES:[4]
        MOV     CX,30
JFPMLOOP:
        CMP     WORD PTR ES:[DI],0
        JNE     JFPMFOUND
        ADD     DI,2
        LOOP    JFPMLOOP
        RET
JFPMFOUND:
        CMP     ES:[DI],AX
        JNE     JFPMRET
        CMP     CX,1            ;Last slot: don't read beyond the limit.
        JE      JFPMLAST
        CMP     WORD PTR ES:[DI+2],0
        JNE     JFPMRET
JFPMLAST:MOV    CS:[JFPDRAIN],0
JFPMRET:RET

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
        JZ      CISTARP
        MOV     AL,CS:[BX]
        OR      AL,AL
        JZ      CISTAZ
        POP     BX
        RET
CISTAZ: MOV     CS:[KEYNEXT],0
CISTARP:MOV     BX,CS:[FEPREAD]
        OR      BX,BX
        JZ      CISTAREP
        CALL    FEPBYTE
        POP     BX
        OR      AL,AL
        RET
CISTAREP:MOV    BX,CS:[ESCREPNEXT]
        OR      BX,BX
        JZ      CISTA0
        MOV     AL,CS:[BX]      ;After an active key string, before a new key.
        POP     BX
        RET
CISTA0: PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
; PrmSnsK/PrmGetK bypass the JFP. Decode AH before falling back to AL,
; so a known special scan always uses the CON definition.
CISTA1: CMP     CS:[JFPMODE],1
        JE      CISTAJ
        CMP     CS:[FEPDRAWN],0
        JNE     CISTAPRIM
        CMP     CS:[JFPSEEN],0
        JE      CISTAPRIM
        CMP     CS:[LABELON],10
        JNE     CISTAPRIM
        ; VA may stop updating the shifted labels even after ROM master-off.
        ; On a post-JFP plain read, retain the primitive queue and repaint.
        MOV     AH,0AH
        INT     82H
        PUSHF
        JC      CISTADRAW
        MOV     CS:[JFPDIRTY],1
CISTADRAW:
        CALL    JFPRIDLE        ;No input state or JFP BIOS access.
        POPF
        JMP     SHORT CISTAPRD
CISTAPRIM:
        MOV     AH,0AH
        INT     82H
CISTAPRD:JNC    CISTAG
CISTAEMPTY:
        XOR     AL,AL
        JMP     CISTAR
CISTAG: MOV     AH,09H
        INT     82H
        CMP     CS:[JFPMODE],3
        JNE     CISTASCAN
        CALL    FEPKEY
        JNC     CISTASCAN       ;Unclaimed primitive AX: use the VAIO table.
        MOV     BX,CS:[FEPREAD]
        OR      BX,BX
        JZ      CISTA1
        CALL    FEPBYTE
        JMP     CISTAR
CISTAJ: CALL    JFPSENSE
        JC      CISTAEMPTY
        OR      AH,AH
        JNZ     CISTAPAIR
        CMP     BX,0FFFFH       ;Generated character, no physical scan.
        JNE     CISTAMAIN             ;Use the main path's returned BH.
        CMP     AL,3            ;ROM already handled Ctrl-C in composition.
        JE      CISTA1          ;Do not break the DOS line as well.
        JMP     SHORT CISTABYTE
CISTAPAIR:
        MOV     CS:[JFPTRAIL],AL
        MOV     AL,AH
        JMP     SHORT CISTABYTE
CISTAMAIN:
        MOV     AH,BH
CISTASCAN:
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
        JNZ     CISTABYTE
        JMP     CISTA1          ;Unknown scan without an internal code.
CISTABYTE:
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
CINP1:  CMP     CS:[CHAR],0
        JE      CINPR
        MOV     AH,CS:[JFPTRAIL] ;Promote trail only when lead is consumed.
        MOV     CS:[CHAR],AH
        MOV     CS:[JFPTRAIL],0
        RET
CINPR:  INC     CS:[ESCREPNEXT]
        CMP     CS:[ESCREPNEXT],OFFSET ESCREPEND
        JNE     CINPR9
        MOV     CS:[ESCREPNEXT],0
CINPR9: RET

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
        CMP     [JFPMODE],3
        JNE     CON_FLROM
        CALL    FEPFLUSH
        JMP     EXIT
CON_FLROM:
        CALL    JFPCLEAR
        CMP     [JFPMODE],1
        JNE     CON_FLPR
        XOR     CX,CX           ;Preserve the width/controls across the flush.
        INT     8DH             ;GetJFP.
        PUSH    AX
        PUSH    DX
        MOV     AX,0400H        ;KbFlsh alone can leave confirmed ROM output.
        INT     82H
        POP     DX
        POP     AX
        MOV     CX,1
        INT     8DH             ;SetJFP reinitializes buffers; no file calls.
        MOV     AX,0201H
        INT     82H             ;Keep ROM expansion off.
        MOV     CS:[JFPDIRTY],1
        CALL    JFPREFRESH
        JMP     EXIT
CON_FLPR:
        CALL    CISTAT          ;Drain primitive queue, discarding strings.
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

; CON owns the NEC parser. Do not put incomplete escapes into the ROM's
; unrelated terminal parser. Preserve DOS's write-loop registers across it.
OUTCHR: CMP     [ESCSTATE],0
        JE      OUTNEW
        CALL    OUTSAVEALL
        JC      OUTNEW          ;Interrupted sequence: retry this byte.
        RET
OUTNEW: CMP     [OUTLEAD],0
        JE      OUTSINGLE
        CMP     AL,40H
        JB      OUTBAD
        CMP     AL,7FH
        JE      OUTBAD
        CMP     AL,0FCH
        JBE     OUTPAIR
OUTBAD: MOV     [OUTLEAD],0     ;Do not join bytes across controls or ESC.
        CMP     AL,7FH
        JNE     OUTSINGLE
        RET                     ;Retain J2a recovery for a bad DEL trail.
OUTSINGLE:
        CMP     AL,1BH
        JNE     OUTBYTE
        MOV     [ESCSTATE],1
        RET
OUTBYTE:
        CMP     AL,81H
        JB      OUTANK
        CMP     [OUTGRAPH],0
        JNE     OUTLIT         ;Litout keeps each high byte in one cell.
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

; Use the ROM's interpreted path only for controls shared with NEC.
OUTANK: CMP     AL,07H
        JB      OUTLIT
        CMP     AL,0AH
        JBE     OUTCH1
        CMP     AL,0CH
        JNE     OUTCR
        MOV     AL,' '          ;NEC FF is a blank cell, not VA's FF glyph/LF.
        JMP     SHORT OUTCH1
OUTCR:  CMP     AL,0DH
        JE      OUTCH1
        CMP     AL,0BH
        JE      OUTCONTROL
        CMP     AL,1AH
        JE      OUTCONTROL
        CMP     AL,1EH
        JE      OUTCONTROL
        CMP     AL,20H
        JB      OUTLIT
        CMP     AL,7FH
        JNE     OUTCH1
OUTLIT: PUSH    DX
        XOR     DX,DX
        MOV     DL,AL
        MOV     AH,01H         ;Litout: display a control as one glyph.
        CALL    OUTCALL
        POP     DX
        RET
OUTCONTROL:
        JMP     SHORT OUTSAVEALL
OUTCH1: MOV     AH,02H         ;Putstr, a single filtered byte.
OUTCALL:CLC
        JMP     SHORT OUTENTER
OUTSAVEALL:
        STC                     ;Select ESCPARSE, rather than raw ROM.
OUTENTER:
        PUSH    AX
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
        JNC     OUTRAW
        CALL    ESCPARSE
        JMP     OUTREGS
OUTRAW: CMP     AH,02H
        JNE     OUTGLYPH        ;Chuput pair or literal one-cell glyph.
        XOR     DX,DX           ;Putstr is one byte, no Shift-JIS argument.
        CMP     AL,0DH
        JE      OUTCRNOW
        CMP     AL,07H
        JB      OUTGLYPH
        CMP     AL,0AH
        JA      OUTGLYPH
        JE      OUTLF
        CMP     AL,08H
        JNE     OUTNORMAL      ;BEL, HT.
        CMP     [OUTWRAP],0
        JE      OUTNORMAL
        MOV     [OUTWRAP],0    ;BS from logical 81 stays on physical 80.
        JMP     OUTOK
OUTCRNOW:
        MOV     [OUTWRAP],0
OUTNORMAL:
        CALL    OUTWRITE
        JMP     OUTOK
OUTLF:  MOV     AH,0DH         ;Index scrolls even with ROM auto-scroll off.
        INT     83H
        JMP     OUTOK
OUTGLYPH:
        PUSH    AX
        PUSH    DX
        MOV     AH,26H         ;Askloc; actual position, including ROM callers.
        INT     83H
        POP     AX             ;Original DX (glyph/pair argument).
        CMP     DH,79
        JNE     OUTSPACE
        CMP     [OUTWRAP],0
        JNE     OUTGLINE
        OR      AH,AH
        JNZ     OUTEDGEPAIR
        JMP     SHORT OUTEDGE  ;A one-cell glyph fills the last column.
OUTEDGEPAIR:
        ; Reproduce the ROM's special space before a pre-wrapped pair.
        PUSH    AX
        PUSH    DX
        MOV     AX,0100H
        MOV     DX,00FEH
        INT     83H
        POP     DX
        MOV     AH,08H         ;Undo the filler write's ROM cursor advance.
        INT     83H
        POP     AX
OUTGLINE:
        PUSH    AX
        CALL    OUTNEXT
        POP     AX
        MOV     [OUTWRAP],0
        JMP     SHORT OUTGEND
OUTSPACE:
        MOV     [OUTWRAP],0
        CMP     DH,78
        JNE     OUTGEND
        OR      AH,AH
        JZ      OUTGEND
        ; A two-cell glyph starts at column 79. ROM wrap must be enabled
        ; for Chuput to draw both halves, but auto-scroll is disabled.
OUTEDGE:MOV     [OUTWRAP],1
        MOV     DH,79
        MOV     BX,DX
        MOV     DX,AX
        POP     AX
        PUSH    BX
        CALL    OUTWRITE
        POP     DX
        MOV     AH,08H         ;Return the cursor to the cell just filled.
        INT     83H
        JMP     SHORT OUTOK
OUTGEND:MOV     DX,AX
        POP     AX
        CALL    OUTWRITE
OUTOK:  CLC
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

OUTWRITE:
        CMP     AH,02H
        JNE     OUTINT
        MOV     [OUTBUF],AL
        MOV     SI,OFFSET OUTBUF
        MOV     DX,8000H
OUTINT: INT     83H
        RET

; Wrap (or ESC E): return to column 1 and move down. Index explicitly
; scrolls within the current split even with automatic scrolling off.
OUTNEXT:MOV     AX,0000H
        MOV     DX,000DH
        INT     83H
        MOV     AH,0DH
        INT     83H
        RET

; AL = pending output byte; caller saved the write-loop registers.
; Carry = retry AL as ordinary output. All paths to ESCROM finish here.
ESCPARSE:
        CMP     [ESCSTATE],0
        JE      ESCCTL
        CMP     [ESCSTATE],2
        JNE     ESCNOTCSI
        JMP     ESCCSI
ESCNOTCSI:
        MOV     BL,[ESCSTATE]
        MOV     [ESCSTATE],0
        CMP     BL,1
        JE      ESCSHORT
        CMP     BL,3
        JE      ESCDIRROW
        CMP     BL,4
        JE      ESCDIRCOL
        JMP     ESCGMODE        ;ESC ) followed by a mode digit.
ESCDIRCOL:
        SUB     AL,20H
        MOV     DH,AL
        MOV     DL,[ESCROW]
        JMP     ESCLOCATE
ESCDIRROW:
        SUB     AL,20H
        MOV     [ESCROW],AL
        MOV     [ESCSTATE],4
        JMP     SHORT ESCDONE
ESCCTL: CMP     AL,0BH
        JNE     ESCCT1
        MOV     AX,0900H        ;VT moves up, not down, on NEC.
        MOV     CL,1
        JMP     ESCROM
ESCCT1: CMP     AL,1AH
        JE      ESCCLEAR
        JMP     ESCHOME         ;1Eh.
ESCSHORT:
        CMP     AL,'['
        JE      ESCSTART
        CMP     AL,'='
        JE      ESCADDR
        CMP     AL,')'
        JE      ESCGRAPH
        CMP     AL,'*'
        JE      ESCCLEAR
        CMP     AL,'D'
        JE      ESCINDEX
        CMP     AL,'M'
        JE      ESCRIND
        CMP     AL,'E'
        JNE     ESCDONE
        MOV     [OUTWRAP],0
        CALL    OUTNEXT
        JMP     ESCDONE
ESCINDEX:
        MOV     AH,0DH
        JMP     ESCROM
ESCRIND:MOV     AH,0EH
        JMP     ESCROM
ESCADDR:MOV     [ESCSTATE],3
        JMP     SHORT ESCDONE
ESCGRAPH:
        MOV     [ESCSTATE],5
        JMP     SHORT ESCDONE
ESCCLEAR:
        MOV     AX,1702H
        INT     83H
        JMP     ESCHOME
ESCSTART:
        MOV     [ESCSTATE],2
        MOV     [ESCN],0
        MOV     [ESCPRIV],0
        MOV     [ESCBUDGET],ESCOCTETS
        XOR     AX,AX
        MOV     WORD PTR [ESCARGS],AX
ESCDONE:CLC
        RET

ESCCSI: CMP     AL,40H          ;A final ends the sequence, known or not.
        JB      ESCPARAM
        CMP     AL,7EH
        JA      ESCRETRY
        MOV     [ESCSTATE],0
        JMP     ESCFINAL
ESCRETRY:
        ; Preserve J2a's literal [> before an interrupted Shift-JIS pair.
        CMP     [ESCBUDGET],ESCOCTETS-1
        JNE     ESCABORT
        CMP     [ESCPRIV],'>'
        JNE     ESCABORT
        MOV     AL,'['
        CALL    OUTCH1
        MOV     AL,'>'
        CALL    OUTCH1
ESCABORT:
        MOV     [ESCSTATE],0
        STC
        RET
ESCPARAM:
        CMP     AL,20H
        JB      ESCBREAK
        DEC     [ESCBUDGET]
        JZ      ESCABORT
        CMP     [ESCBUDGET],ESCOCTETS-64
        JE      ESCINVALID      ;Ignore overlong commands, but find the final.
        CMP     [ESCPRIV],-1
        JE      ESCDONE
        XOR     BX,BX
        MOV     BL,[ESCN]
        CMP     AL,'0'
        JB      ESCINVALID
        CMP     AL,'9'
        JA      ESCSEP
        SUB     AL,'0'
        MOV     CL,AL
        MOV     AL,[ESCARGS+BX]
        MOV     AH,10
        MUL     AH
        ADD     AL,CL
        ADC     AH,0
        JZ      ESCDIGIT
        MOV     AL,255
ESCDIGIT:
        MOV     [ESCARGS+BX],AL
        JMP     SHORT ESCDONE
ESCSEP: CMP     AL,';'
        JNE     ESCPRFX
        CMP     BL,7
        JAE     ESCINVALID
        INC     BX
        MOV     [ESCN],BL
        MOV     BYTE PTR [ESCARGS+BX],0
        CLC
        RET
ESCPRFX:CMP     [ESCBUDGET],ESCOCTETS-1
        JNE     ESCINVALID
        CMP     AL,'>'
        JE      ESCSET
        CMP     AL,'?'
        JNE     ESCINVALID
ESCSET: MOV     [ESCPRIV],AL
        JMP     ESCDONE
ESCINVALID:
        MOV     [ESCPRIV],-1
        JMP     ESCDONE
ESCBREAK:
        CMP     AL,1BH          ;NEC consumes a second ESC in a CSI.
        JNE     ESCABORT
        MOV     [ESCSTATE],0
        JMP     ESCDONE

ESCFINAL:
        MOV     CL,[ESCARGS]
        CMP     [ESCPRIV],0
        JE      ESCSTANDARD
        CMP     [ESCPRIV],'>'
        JNE     ESCNOOP
        CMP     [ESCN],0
        JNE     ESCNOOP
        CMP     AL,'h'
        JE      ESCPRIVH
        CMP     AL,'l'
        JNE     ESCNOOP
        MOV     AL,10
        JMP     SHORT ESCPRIVL
ESCPRIVH:XOR    AL,AL
ESCPRIVL:CMP    CL,1
        JNE     ESCCURSOR
        CMP     [JFPMODE],0
        JE      ESCLAYOUT
        MOV     [JFPLABEL],AL   ;Defer hide/show until the input mode is off.
        JMP     SHORT ESCNOOP
ESCLAYOUT:
        MOV     AH,2FH
        CALL    LABELMODE
        CALL    GRAPHMARK      ;Refresh also if graph was cleared while hidden.
        MOV     [JFPDIRTY],1    ;For the post-JFP plain label painter only.
ESCNOOP:CLC
        RET
ESCCURSOR:
        CMP     CL,5
        JNE     ESCNOOP
        ; NEC >5h suppresses the cursor, >5l restores it.
        OR      AL,AL
        JZ      ESCCUR0
        MOV     AL,3            ;Blinking block.
ESCCUR0:MOV     AH,25H
        JMP     ESCROM

ESCSTANDARD:
        CMP     AL,'H'
        JE      ESCPOSJ
        CMP     AL,'f'
        JNE     ESCNOTPOS
ESCPOSJ:JMP     ESCPOS
ESCNOTPOS:
        CMP     AL,'m'
        JNE     ESCONE
        JMP     ESCATTR
ESCONE: CMP     [ESCN],0
        JNE     ESCNOOP
        CMP     AL,'J'
        JE      ESCJERASE
        CMP     AL,'K'
        JE      ESCJERASE
        CMP     AL,'n'
        JNE     ESCNOTREP
        JMP     ESCREPORT
ESCNOTREP:
        CMP     AL,'s'
        JE      ESCSAVE
        CMP     AL,'u'
        JE      ESCREST
        CMP     AL,'L'
        JE      ESCJLINE
        CMP     AL,'M'
        JNE     ESCMOVE
ESCJLINE:JMP    ESCLINES
ESCMOVE:SUB     AL,'A'
        CMP     AL,3
        JA      ESCNOOP
        ADD     AL,09H          ;Goup, Godown, Goright, Goleft.
        MOV     AH,AL
        OR      CL,CL
        JNZ     ESCMOV1
        INC     CL
ESCMOV1:CMP     AH,0CH          ;Left from logical 81 takes one extra step.
        JNE     ESCMOV2
        CMP     [OUTWRAP],0
        JE      ESCMOV2
        MOV     [OUTWRAP],0
        DEC     CL
        JZ      ESCNOOP
ESCMOV2:CMP     CL,80           ;No movement needs more than 80 cells.
        JBE     ESCROM
        MOV     CL,80
        JMP     SHORT ESCROM
ESCJERASE:
        JMP     ESCERASE
ESCSAVE:MOV     AH,26H
        INT     83H
        MOV     [ESCSAVED],DX
        MOV     AL,[OUTWRAP]
        MOV     [ESCSWRAP],AL
        CLC
        RET
ESCREST:MOV     DX,[ESCSAVED]
        CALL    ESCLOCATE
        MOV     AL,[ESCSWRAP]
        MOV     [OUTWRAP],AL
        RET
ESCPOS: CMP     [ESCN],1
        JE      ESCXY
        CMP     [ESCBUDGET],ESCOCTETS ;A single numeric parameter is ignored.
        JE      ESCHOME
        CLC
        RET
ESCHOME:XOR     DX,DX
        JMP     SHORT ESCLOCATE
ESCXY:  MOV     DL,CL
        MOV     DH,[ESCARGS+1]
        OR      DL,DL
        JZ      ESCX
        DEC     DL
ESCX:   OR      DH,DH
        JZ      ESCLOCATE
        DEC     DH
ESCLOCATE:
        MOV     [OUTWRAP],0
        ; Clamp explicitly before calling Locate, which uses signed inputs
        ; on some ROM paths. The last visible row depends on LABELMODE.
        CMP     DH,79
        JBE     ESCLIMY
        MOV     DH,79
ESCLIMY:MOV     AL,23
        CMP     [LABELON],0
        JNE     ESCLIM
        INC     AL
ESCLIM: CMP     DL,AL
        JBE     ESCLOC
        MOV     DL,AL
ESCLOC: MOV     AH,08H
ESCROM: INT     83H
        CLC
        RET
ESCERASE:
        CMP     CL,2
        JBE     ESCERASE0
        CLC
        RET
ESCERASE0:
        MOV     AH,17H          ;Erascn / Eralin use only the main split.
        CMP     AL,'J'
        JE      ESCERASE1
        INC     AH
ESCERASE1:
        MOV     AL,CL
        CMP     AX,1702H        ;NEC's whole-screen erase homes the cursor.
        JE      ESCJCLEAR
        CMP     AL,2
        JE      ESCROM
        OR      AL,AL
        JNZ     ESCBOUNDARYJ
        CMP     [OUTWRAP],0
        JNE     ESCEDGESUFFIX
ESCBOUNDARYJ:
        JMP     ESCBOUNDARY
ESCEDGESUFFIX:
        ; At logical column 81 there are no cells left in this row.
        CMP     AH,18H          ;K0: nothing to erase.
        JE      ESCEDGEDONE
        MOV     AH,26H
        INT     83H
        MOV     AL,23
        CMP     [LABELON],0
        JNE     ESCEDGELIMIT
        INC     AL
ESCEDGELIMIT:
        CMP     DL,AL
        JAE     ESCEDGEDONE
        PUSH    DX              ;J0: erase from the next row's first cell.
        INC     DL
        XOR     DH,DH
        MOV     AH,08H
        INT     83H
        MOV     AX,1700H
        INT     83H
        POP     DX
        JMP     ESCLOC
ESCEDGEDONE:
        CLC
        RET
ESCJCLEAR:
        JMP     ESCCLEAR
ESCLINES:
        MOV     BL,15H          ;Insline / Delline.
        CMP     AL,'L'
        JE      ESCLINE0
        MOV     BL,13H
ESCLINE0:
        OR      CL,CL
        JNZ     ESCLINE1
        INC     CL
ESCLINE1:
        MOV     AH,26H
        INT     83H
        MOV     AL,24
        CMP     [LABELON],0
        JNE     ESCLINE2
        INC     AL
ESCLINE2:
        SUB     AL,DL           ;At most the rows left in the main split.
        CMP     CL,AL
        JBE     ESCLINE3
        MOV     CL,AL
ESCLINE3:
        PUSH    DX
        MOV     AH,BL
        INT     83H
        POP     DX
        XOR     DH,DH           ;NEC returns to column 1.
        JMP     ESCLOCATE

ESCREPORT:
        CMP     CL,6
        JNE     ESCREPDONE
        CMP     [ESCREPNEXT],0  ;Do not replace an unread response.
        JNE     ESCREPDONE
        MOV     AH,26H
        INT     83H
        MOV     AL,DL
        INC     AL
        AAM
        ADD     AX,3030H
        XCHG    AH,AL
        MOV     WORD PTR [ESCREP+2],AX
        MOV     AL,DH
        INC     AL
        CMP     DH,79
        JNE     ESCREPCOL
        ADD     AL,[OUTWRAP]    ;NEC reports logical column 81 when pending.
ESCREPCOL:
        AAM
        ADD     AX,3030H
        XCHG    AH,AL
        MOV     WORD PTR [ESCREP+5],AX
        MOV     [ESCREPNEXT],OFFSET ESCREP
ESCREPDONE:
        CLC
        RET

; A partial Eras{lin,cn} does not clean up a neighboring kanji half on
; the VA ROM, unlike NEC CON. Compare the two TVRAM words at the boundary;
; only widen the erase for a matching left/right pair in the same row.
; AX = BIOS erase function+mode, BP saves it through Getadr.
ESCBOUNDARY:
        MOV     BP,AX
        MOV     AH,26H          ;Askloc.
        INT     83H
        CMP     AL,0
        JNE     ESCBLEFT
        OR      DH,DH           ;No neighbor before column 1.
        JZ      ESCBPLAIN
        MOV     SI,-2
        JMP     SHORT ESCBREAD
ESCBLEFT:CMP    DH,79           ;No neighbor after column 80.
        JAE     ESCBPLAIN
        MOV     SI,2
ESCBREAD:
        PUSH    DX
        MOV     AX,1A01H        ;Getadr: CX = physical TVRAM offset.
        INT     83H
        JC      ESCBFAIL
        ADD     SI,CX
        MOV     DI,CX
        MOV     AX,0A000H
        MOV     ES,AX
        PUSHF                   ;Preserve the caller's window across read.
        CLI
        MOV     DX,0152H        ;V3 memory-map register, word I/O.
        IN      AX,DX
        MOV     BX,AX
        AND     AH,0F0H
        OR      AH,1            ;SMBC=1 maps TVRAM; retain the other bits.
        OUT     DX,AX
        MOV     CX,ES:[DI]
        MOV     SI,ES:[SI]
        MOV     AX,BX
        OUT     DX,AX
        POPF
        POP     DX
        MOV     AX,CX
        MOV     BX,BP
        OR      BL,BL
        JNZ     ESCBCMP
        XCHG    AX,SI           ;AX = left word, SI = right word.
ESCBCMP:TEST    AH,AH
        JZ      ESCBPLAIN       ;ANK cannot be the left half.
        JS      ESCBPLAIN       ;Nor can another right half.
        OR      AH,80H
        CMP     AX,SI
        JNE     ESCBPLAIN
        PUSH    DX
        DEC     DH
        OR      BL,BL
        JZ      ESCBLOC
        ADD     DH,2
ESCBLOC:MOV     AH,08H
        INT     83H
        MOV     AX,BP
        INT     83H
        POP     DX
        JMP     ESCLOC          ;Restore the cursor after widening the range.
ESCBFAIL:POP    DX
ESCBPLAIN:
        MOV     AX,BP
        JMP     ESCROM

; Each NEC SGR starts at normal. All supported colors are one color
; against black, optionally reversed. Mode 1 stores each cell's color
; in the high nibble, plus HL/RV/BL/SE in the low nibble.
ESCATTR:XOR     BX,BX           ;BL = mode 1 effect bits.
        MOV     DL,7            ;White on black; graphics mode unchanged.
        XOR     CX,CX
        MOV     CL,[ESCN]
        INC     CX
        MOV     SI,OFFSET ESCARGS
        CLD
ESCAT1: LODSB
        CMP     AL,4
        JE      ESCATLINE
        CMP     AL,5
        JE      ESCATBLINK
        CMP     AL,7
        JE      ESCATREV
        CMP     AL,8
        JE      ESCATSEC
        CMP     AL,16
        JE      ESCATSEC
        CMP     AL,17
        JE      ESCATNEC
        CMP     AL,30
        JB      ESCATNEXT
        CMP     AL,37
        JBE     ESCATFG
        CMP     AL,40
        JB      ESCATNEXT
        CMP     AL,47
        JA      ESCATNEXT
        OR      BL,04H          ;NEC 4x = reverse in that color.
        SUB     AL,10
ESCATFG:SUB     AL,30
        JMP     SHORT ESCATCOL
ESCATNEC:
        MOV     AL,1
ESCATCOL:
        PUSH    BX
        MOV     BX,OFFSET ESCCOLORS
        XLAT
        POP     BX
        MOV     DL,AL
        JMP     SHORT ESCATNEXT
ESCATLINE:
        OR      BL,08H          ;HL at the final raster line.
        JMP     SHORT ESCATNEXT
ESCATBLINK:
        OR      BL,02H
        JMP     SHORT ESCATNEXT
ESCATREV:OR     BL,04H
        JMP     SHORT ESCATNEXT
ESCATSEC:OR     BL,01H
ESCATNEXT:
        LOOP    ESCAT1
        TEST    BL,01H          ;Secret also keeps the cell black if reversed.
        JZ      ESCATSET
        XOR     DL,DL
ESCATSET:
        MOV     CL,4
        SHL     DL,CL
        OR      DL,BL
        XOR     DH,DH
        MOV     AH,05H          ;Setatr, current attribute in mode 1.
        JMP     ESCROM
ESCCOLORS DB    0,2,4,6,1,3,5,7 ;NEC ANSI RGB order -> VA GRB bits.

; The two layouts share the main framebuffer. The system buffer starts
; after all 25 main rows, so the split can change without copying text.
MAIN25  DB      00H,0,0,0,25,11H,07H,0
MAIN24  DB      00H,0,0,0,24,11H,07H,0  ;Mode 1, word wrap, no auto-scroll.
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

ESCGMODE:
        XOR     AH,AH
        CMP     AL,'0'
        JE      ESCGSET
        CMP     AL,'3'
        JNE     ESCGDONE
        INC     AH
ESCGSET:CMP     AH,[OUTGRAPH]
        JE      ESCGDONE
        MOV     [OUTGRAPH],AH
        CMP     [FEPDRAWN],0    ;Project composition owns the system row.
        JNE     ESCGDONE
        CMP     [JFPMODE],1
        JNE     ESCGROM
        MOV     [JFPDIRTY],1
        CALL    JFPREFRESH
        JMP     SHORT ESCGDONE
ESCGROM:CALL    GRAPHMARK
ESCGDONE:CLC
        RET

; The ROM owns the key labels starting at column 5. NEC puts 'g' at
; column 2, outside the key fields. Keep the main cursor and SGR intact.
GRAPHMARK:
        CMP     [LABELON],10
        JNE     GRAPHRET
        MOV     AH,26H          ;Save the main cursor.
        INT     83H
        PUSH    DX
        MOV     AX,1B01H        ;Chcsn: select the system split.
        INT     83H
        JC      GRAPHFAIL
        MOV     AH,08H
        MOV     DX,0100H        ;Locate at system column 2.
        INT     83H
        MOV     AL,' '
        CMP     [OUTGRAPH],0
        JE      GRAPHCHAR
        MOV     AL,'g'
GRAPHCHAR:
        MOV     [OUTBUF],AL
        MOV     AX,0200H        ;Putstr with white on black (mode 1).
        MOV     DX,0070H
        MOV     SI,OFFSET OUTBUF
        INT     83H
        MOV     AX,1B00H        ;Restore main split and cursor.
        INT     83H
        POP     DX
        MOV     AH,08H
        INT     83H
GRAPHRET: RET
GRAPHFAIL:
        POP     DX
        RET

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
        INCLUDE VAFEP.INC
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
        CMP     AH,0F0H         ;VA FORMAT: boot-time SASI mount bitmap.
        JE      GIO_SASI
        CMP     AH,60H
        JE      GIO_GDP
        CMP     AH,61H
        JE      GIO_RD
        CMP     AH,41H
        JE      GIO_WR
        CMP     AH,66H
        JNE     @F
        JMP     GIO_GMI
@@:     CMP     AH,67H
        JE      GIO_GAF
        CMP     AH,40H          ;Set device parameters: nothing to change.
        JE      GIO_OK
        CMP     AH,47H          ;Set access flag: always accessible.
        JE      GIO_OK
GIO_BAD:
        JMP     CMDERR
GIO_SASI:
        MOV     AX,WORD PTR [SASIMAP]    ;Low: mounted targets. High: interface tag.
        MOV     ES:[DI],AX
        JMP     GIO_OK

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

SASIMAP DB      0,0D3H         ;Available even when HDDDEV is overlaid.
RESEND  LABEL   BYTE            ;End of resident BIOS without SASI.

        INCLUDE VAHDD.INC       ;Kept only if at least one target mounts.

        SUBTTL  Initialization (overlaid by MSDOS.SYS).
        PAGE

        INCLUDE VAHDINIT.INC

; Entered from VABOOT with DX = MSDOS.SYS segment.  Keep the boot stack:
; SYSINIT moves MSDOS.SYS over this initialization code while it still
; uses the stack it inherits, so that stack must lie outside IO.SYS.
HWINIT: CLD
        CMP     AX,5648H        ;VAHDBOOT marker; BL is the SASI target.
        JNE     HWFLPY
        MOV     CS:[HDBOOTTARGET],BL
HWFLPY: XOR     AX,AX
        MOV     ES,AX
        MOV     AX,ES:[33H*4]
        MOV     WORD PTR CS:[OLD33],AX
        MOV     AX,ES:[33H*4+2]
        MOV     WORD PTR CS:[OLD33+2],AX
        PUSH    DX              ;Keep the loaded kernel segment.
        CALL    INITTEXT
        CLD
        CALL    MEMSIZE         ;AX = memory size in paragraphs.
        PUSH    CS
        POP     DS
        MOV     [HDMEM],AX
        CALL    HDDISCOVER      ;Before SYSINIT overlays the discarded tail.
        MOV     AL,[HDBOOTDRV]
        OR      AL,AL
        JZ      HDBOOTFAIL
        POP     BP
        MOV     CX,[HDMEM]
        ; SYSINIT moves DOS to this boundary before issuing device INIT.
        ; With no accepted unit, discard the whole optional SASI tail.
        MOV     AX,OFFSET RESEND
        CMP     [HDUNITS],0
        JE      HWEND
        MOV     AX,DI           ;End of the accepted BPB records.
HWEND:  ADD     AX,15
        PUSH    CX
        MOV     CL,4
        SHR     AX,CL
        POP     CX
        MOV     DX,CS
        ADD     DX,AX           ;DX = final DOS segment.

        MOV     BL,[HDBOOTDRV]
        MOV     AX,SYSINITSEG
        MOV     DS,AX
        ASSUME  DS:SYSINITSEG
        MOV     [CURRENT_DOS_LOCATION],BP
        MOV     [FINAL_DOS_LOCATION],DX
        MOV     [MEMORY_SIZE],CX
        MOV     WORD PTR [DEVICE_LIST],OFFSET DEVSTART
        MOV     WORD PTR [DEVICE_LIST+2],CS
        MOV     [DEFAULT_DRIVE],BL ;One-based SYSINIT boot drive.
        ASSUME  DS:CODE
        JMP     SYSINIT

HDBOOTFAIL:
        MOV     SI,OFFSET HDBOOTMSG
        MOV     DX,8000H
        MOV     AH,2
        INT     83H
HDSTOP: CLI
        HLT
        JMP     HDSTOP
HDBOOTMSG DB    13,10,'SASI boot volume did not mount',13,10,0

; J0.1 text-BIOS split. Define the ROM strings for display only; the
; DOS input queue and expansion continue to use CONKEYS/CONEDIT.
TEXTBUFS DW     0
        DB      80,25
        DW      SYSTEXT
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
