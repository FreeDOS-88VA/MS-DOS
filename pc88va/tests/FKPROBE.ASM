; SPDX-License-Identifier: MIT
; J0.1 ROM probe. Run on a disposable boot: changes BIOS state, does not
; restore the screen layout or key definitions. See docs/J0-probe.md.
; MASM 5.10 / LINK 3.65 / EXE2BIN; no product objects linked.

CODE    SEGMENT PARA PUBLIC 'CODE'
        ASSUME  CS:CODE, DS:CODE
        ORG     100H

START:  PUSH    CS
        POP     DS
        CLD
        MOV     SI,81H                  ;First nonblank in the PSP tail.
        XOR     CH,CH
        MOV     CL,[80H]
ARG:    JCXZ    USAGE
        LODSB
        CMP     AL,' '
        LOOPE   ARG
        JE      USAGE
        AND     AL,0DFH
        MOV     [MODE],AL
        CMP     AL,'B'
        JE      BLOCKING
        CMP     AL,'R'
        JNE     SCREEN
        JMP     KEYS
SCREEN: CMP     AL,'P'
        JE      SETUP
        CMP     AL,'N'
        JE      SETUP
        CMP     AL,'S'
        JE      SETUP
        CMP     AL,'X'
        JE      SETUP
        CMP     AL,'K'
        JE      SETUP
        CMP     AL,'F'
        JE      SETUP
        CMP     AL,'M'
        JE      SETUP
USAGE:  MOV     SI,OFFSET HELP
        CALL    TEXT
QUIT:   MOV     AX,4C00H
        INT     21H

BLOCKING:
        MOV     SI,OFFSET WAITGET       ;No screen/JFP/KB init or sense.
        CALL    TEXT
        XOR     AX,AX
        CALL    KB
        MOV     DI,OFFSET GETAX
        CALL    PAIR
        MOV     SI,OFFSET GETONLY
        CALL    TEXT
        JMP     QUIT

SETUP:  CMP     [MODE],'X'
        JE      SPLIT
        MOV     AX,0004H                ;80 cols, 25 lines, 1 system row.
        INT     94H                     ;InitScr; starts with line hidden.
        MOV     AX,010AH                ;AlcSysL: display ten, shift-aware.
        INT     94H
        JMP     LABELS
SPLIT:  MOV     AX,2404H                ;CrtCtl: 80x25, text on.
        INT     83H
        PUSH    CS                      ;Text BIOS path, without InitScr.
        POP     ES
        MOV     BP,OFFSET FRAMEBUFS
        MOV     CX,2
        MOV     AX,1C00H                ;Allocfb: main and system buffers.
        INT     83H
        JC      SPLITFAIL
        MOV     BP,OFFSET SUBSCREENS
        MOV     CX,2
        MOV     AX,1D00H                ;Spltscn: main screen is current.
        INT     83H
        JNC     LABELS
SPLITFAIL: JMP  SPLITERR
LABELS: MOV     AX,2F0AH                ;SftCtl: explicitly check CF.
        INT     83H
        MOV     AL,'0'
        ADC     AL,0
        PUSH    CS
        POP     DS
        MOV     [SFTCF],AL
        CLD

        MOV     CX,1
        MOV     SI,OFFSET PLAIN
        CMP     [MODE],'N'
        JE      PREFIXED
        CMP     [MODE],'F'
        JNE     DEFF1
PREFIXED:
        MOV     SI,OFFSET NECFORM
DEFF1:  CALL    DEF
        MOV     DI,OFFSET DEFS
NEXTDEF:
        MOV     CX,[DI]
        JCXZ    SHOW
        MOV     SI,[DI+2]
        CALL    DEF
        ADD     DI,4
        JMP     NEXTDEF
SHOW:   MOV     AX,0200H                ;ExpCtrl: expand soft strings.
        CALL    KB
        MOV     AL,[MODE]
        MOV     [SETMODE],AL
        MOV     SI,OFFSET SETMSG
        CALL    TEXT

        CMP     [MODE],'K'
        JE      KEYS
        CMP     [MODE],'F'
        JE      KEYS
        CMP     [MODE],'M'
        JNE     NOTMEM
        JMP     MEMORY
NOTMEM: CMP     [MODE],'S'
        JE      STARTSC
        CMP     [MODE],'X'
        JE      STARTSC
        JMP     QUIT
STARTSC: MOV    BP,1
SCROLL: MOV     AX,BP
        MOV     DI,OFFSET LINENO
        CALL    HEX4
        MOV     DX,OFFSET LINEBUF
        MOV     CX,LINELEN
        MOV     BX,1                    ;DOS stdout, must not redirect.
        MOV     AH,40H                  ;Use VAIO CON, not our TEXT helper.
        PUSH    BP
        INT     21H
        POP     BP
        JC      WRITEERR
        CMP     AX,LINELEN
        JNE     WRITEERR
        INC     BP
        CMP     BP,41
        JB      SCROLL
        JMP     QUIT
SPLITERR:
        MOV     SI,OFFSET SPLERR
        JMP     FAILED
WRITEERR:
        MOV     SI,OFFSET WRERR
FAILED: CALL    TEXT
        MOV     AX,4C01H
        INT     21H

KEYS:   MOV     SI,OFFSET KEYMSG
        CMP     [MODE],'R'
        JNE     PROMPT
        MOV     SI,OFFSET RAWMSG
PROMPT: CALL    TEXT
POLL:   MOV     AX,0100H                ;SnsChar: nondestructive poll.
        CMP     [MODE],'R'
        JNE     SENSE
        MOV     AH,0AH                  ;Control: primitive sense/get.
SENSE:  CALL    KB
        JC      EMPTY
        MOV     DI,OFFSET SNSAX
        CALL    PAIR
        XOR     AX,AX                   ;GetChar; only after sense CF=0.
        CMP     [MODE],'R'
        JNE     TAKE
        MOV     AH,09H
TAKE:   CALL    KB
        MOV     DI,OFFSET TAKEAX
        CALL    PAIR
        MOV     [BUSY],1
        PUSH    AX
        MOV     SI,OFFSET KEYROW
        CALL    TEXT
        POP     AX
        CMP     [MODE],'R'
        JNE     CHECKQ
        XOR     AH,AH                   ;Primitive AH is the scan code.
CHECKQ: CMP     AX,'q'
        JNE     POLL
        JMP     QUIT
EMPTY:  CMP     [BUSY],0
        JE      POLL
        MOV     [BUSY],0
        MOV     SI,OFFSET EMPTYMSG
        CALL    TEXT
        JMP     POLL

MEMORY: MOV     AX,4400H                ;What will COMMAND CLS see?
        MOV     BX,1
        INT     21H
        JC      SKIPIO
        MOV     AX,DX
        MOV     DI,OFFSET STDIO
        CALL    HEX4
        MOV     SI,OFFSET STDBOOK
        CALL    TEXT
SKIPIO: MOV     AH,2BH                  ;Text Getbook -> ES:DX.
        INT     83H
        MOV     AX,ES
        MOV     DI,OFFSET TEXTSEG
        CALL    FARHEX
        MOV     SI,OFFSET TEXTBOOK
        CALL    TEXT

        MOV     AH,0EH                  ;KB KyBook -> ES:DX.
        INT     82H
        MOV     AX,ES
        MOV     DI,OFFSET KBSEG
        CALL    FARHEX
        MOV     SI,OFFSET KBADDR
        CALL    TEXT

        MOV     AX,00ABH                ;Read only; compare our own F1.
        MOV     ES,AX
        MOV     SI,OFFSET PLAIN        ;Mode M defines the plain F1.
        MOV     DI,1
        MOV     CX,3                    ;ESC S NUL, no other data printed.
        REPE    CMPSB
        MOV     AL,'0'
        JNE     MATCH
        INC     AL
MATCH:  MOV     [KBMATCH],AL
        MOV     SI,OFFSET KBBOOK
        CALL    TEXT

        MOV     DX,ES:[01DEH]           ;KB's JFP callback pointer.
        MOV     AX,ES:[01E0H]
        MOV     DI,OFFSET KBJFPSEG
        CALL    FARHEX
        MOV     SI,OFFSET KBJFP
        CALL    TEXT
        XOR     AX,AX
        MOV     ES,AX
        MOV     DX,ES:[8DH*4]
        MOV     AX,ES:[8DH*4+2]
        MOV     DI,OFFSET IVTJFPSEG
        CALL    FARHEX
        MOV     SI,OFFSET IVTJFP
        CALL    TEXT

        MOV     AX,0440H                ;JFP bookkeeping (manual 6.18.6).
        MOV     ES,AX
        XOR     BP,BP
        MOV     BX,OFFSET JFPNAMES
JFP:    MOV     DX,ES:[BP]
        MOV     AX,ES:[BP+2]
        MOV     DI,OFFSET JFPSEG
        CALL    FARHEX
        MOV     SI,[BX]
        CALL    TEXT
        MOV     SI,OFFSET JFPPTR
        CALL    TEXT
        ADD     BX,2
        ADD     BP,4
        CMP     BP,10H
        JB      JFP
        MOV     AL,ES:[11H]
        XOR     AH,AH
        MOV     DI,OFFSET JFPCTL
        CALL    HEX4
        MOV     SI,OFFSET JFPSTAT
        CALL    TEXT
        JMP     QUIT

; DefSft uses ES:DX (ES:DS in 603KEYB.TXT is a typo).
DEF:    PUSH    ES
        PUSH    CS
        POP     ES
        MOV     DX,SI
        MOV     AX,0300H
        CALL    KB
        POP     ES
        JNC     DEFOK
        MOV     [DEFCF],'1'
DEFOK:  RET

; Preserve caller registers other than AX and BX. Keep CF, clear DF.
KB:     PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        MOV     BX,0A55AH               ;Canary if a BIOS leaves BX alone.
        INT     82H
        POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     SI
        POP     DX
        POP     CX
        CLD
        RET

; Format AX, BX into "0000 0000" at DS:DI without changing AX or BX.
PAIR:   CALL    HEX4
        INC     DI
        PUSH    AX
        MOV     AX,BX
        CALL    HEX4
        POP     AX
        RET

; Format AX:DX as a far pointer; HEX4 advances DI by four, preserves AX.
FARHEX: CALL    HEX4
        INC     DI
        MOV     AX,DX
HEX4:   PUSH    AX
        PUSH    BX
        PUSH    CX
        MOV     CX,4
DIGIT:  ROL     AX,1
        ROL     AX,1
        ROL     AX,1
        ROL     AX,1
        MOV     BL,AL
        AND     BL,0FH
        ADD     BL,'0'
        CMP     BL,'9'
        JBE     STORE
        ADD     BL,7
STORE:  MOV     [DI],BL
        INC     DI
        LOOP    DIGIT
        POP     CX
        POP     BX
        POP     AX
        RET

; Print diagnostics without DOS CON ever polling the primitive KB queue.
TEXT:   PUSH    AX
        PUSH    BX
        PUSH    CX
        PUSH    DX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        MOV     AX,0200H
        MOV     DX,8000H
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
        CLD
        RET

MODE    DB      0
BUSY    DB      0
PLAIN   DB      1BH,'S',0
NECFORM DB      0FEH,' C1  ',1BH,'S',0
F2STR   DB      'XYZ123!',0
SHF1    DB      'XY',0
INSSTR  DB      1BH,'P',0
DELSTR  DB      1BH,'D',0
UPSTR   DB      0BH,0
CLRSTR  DB      1AH,0
HOMESTR DB      1EH,0
DEFS    DW      2,F2STR,0BH,SHF1,17H,INSSTR,18H,DELSTR
        DW      19H,UPSTR,1DH,CLRSTR,1FH,HOMESTR,0
; Allocfb: TVRAM byte offset, width, height.
FRAMEBUFS DW    0
        DB      80,24
        DW      0FA0H
        DB      80,1
; Spltscn: type/buffer, origin, reserved, height, mode, color, reserved.
SUBSCREENS DB   00H,0,0,0,24,05H,07H,0  ;Main: wrap and vertical scroll.
        DB      41H,0,0,0,1,10H,07H,0  ;System: attribute mode 1.

HELP    DB      'FKPROBE P/plain N/prefix S/editor scroll X/text BIOS scroll',13,10
        DB      '        K/keys F/prefixed keys B/blocking R/raw M/memory',13,10,0
SETMSG  DB      'FKPROBE '
SETMODE DB      '?'
        DB      ' SftCtl CF='
SFTCF   DB      '0'
        DB      ' any DefSft CF='
DEFCF   DB      '0',13,10,0
LINEBUF DB      'DOS CON row '
LINENO  DB      '0000',13,10
LINELEN EQU     $-LINEBUF
SPLERR  DB      'Allocfb or Spltscn returned CF=1',13,10,0
WRERR   DB      'DOS write failed or short',13,10,0
WAITGET DB      'B: calling blocking GetChar (unmodified BIOS state)',13,10,0
GETONLY DB      'Get AX BX: '
GETAX   DB      '0000 0000',13,10,0
KEYMSG  DB      'Tap keys one at a time; q exits. S CF=0 rows:',13,10,0
RAWMSG  DB      'Primitive queue control. Tap keys one at a time; q exits.',13,10,0
KEYROW  DB      'S AX BX='
SNSAX   DB      '0000 0000  G AX BX='
TAKEAX  DB      '0000 0000',13,10,0
EMPTYMSG DB     'S CF=1 (empty)',13,10,0
STDBOOK DB      'DOS stdout IOCTL DX='
STDIO   DB      '0000',13,10,0
TEXTBOOK DB     'Text Getbook ES:DX='
TEXTSEG DB      '0000:0000',13,10,0
KBADDR  DB      'KB KyBook ES:DX='
KBSEG   DB      '0000:0000',13,10,0
KBBOOK  DB      'KB 00AB:0001 matches ESC S NUL: '
KBMATCH DB      '0',13,10,0
KBJFP   DB      'KB JFP callback='
KBJFPSEG DB     '0000:0000',13,10,0
IVTJFP  DB      'INT 8D vector='
IVTJFPSEG DB    '0000:0000',13,10,0
JFPNAMES DW     JFPIN,JFPOUT,JFPSTATUS,JFPDICT
JFPIN   DB      'JFP input   ',0
JFPOUT  DB      'JFP output  ',0
JFPSTATUS DB    'JFP status  ',0
JFPDICT DB      'JFP UDict   ',0
JFPPTR  DB      '-> '
JFPSEG  DB      '0000:0000',13,10,0
JFPSTAT DB      'JFP control byte='
JFPCTL  DB      '0000',13,10,0

CODE    ENDS
        END     START
