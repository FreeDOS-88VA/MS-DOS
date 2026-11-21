        TITLE   VAKEY - display and change CON key definitions

; SPDX-License-Identifier: MIT
; KEY                  list the VA keys, with control bytes escaped
; KEY key definition   define one key (see help for escapes)
; KEY filename         load a VA key file
; KEY /SAVE filename   save all definitions

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     100H

KSIZE   EQU     20*16+11*6
FSIZE   EQU     6+KSIZE

START:  CLD
        ; Copy the length-delimited PSP tail to our own terminated buffer.
        XOR     CX,CX
        MOV     CL,DS:[80H]
        CMP     CX,127
        JBE     TAILOK
        JMP     USAGE
TAILOK: MOV     SI,81H
        MOV     DI,OFFSET TAILBUF
        REP     MOVSB
        XOR     AL,AL
        STOSB
        MOV     SI,OFFSET TAILBUF
        CALL    SPACE
        CMP     BYTE PTR [SI],0
        JNE     ARGS
        JMP     LIST
ARGS:   MOV     DI,SI
        CALL    TOKEN           ;DI = end of first word.
        MOV     BP,SI           ;BP = start of first word (in DS).
        MOV     AL,[DI]
        MOV     BYTE PTR [DI],0
        MOV     SI,DI
        OR      AL,AL
        JZ      NOREST
        INC     SI
        CALL    SPACE
NOREST: PUSH    SI              ;Rest of tail.
        MOV     SI,BP
        CMP     BYTE PTR [SI],'/'
        JE      SWITCH
        CMP     BYTE PTR [SI],0
        JE      BADARGS
        POP     DI
        CMP     BYTE PTR [DI],0
        JNE     DEFINE
        MOV     DX,SI
        JMP     LOAD
SWITCH: MOV     BX,OFFSET OPTSAVE
        CALL    SAME
        POP     SI
        JNE     CHECKHELP
        MOV     DX,SI
        CMP     BYTE PTR [SI],0
        JE      BADARGS
        CALL    TOKEN
        CMP     BYTE PTR [DI],0
        JE      SAVEARG
        MOV     BYTE PTR [DI],0
        MOV     SI,DI
        INC     SI
        CALL    SPACE
        CMP     BYTE PTR [SI],0
        JNE     BADARGS
SAVEARG:JMP     SAVE
CHECKHELP:
        CMP     WORD PTR DS:[BP],3F2FH ; /?
        JNE     BADARGS
        CMP     BYTE PTR DS:[BP+2],0
        JNE     BADARGS
        CMP     BYTE PTR [SI],0
        JNE     BADARGS
        XOR     AL,AL
        JMP     HELP
BADARGS:JMP     USAGE

DEFINE: ; Look up the name (case-insensitive), retaining the rest in DI.
        MOV     BX,OFFSET NAMES
        MOV     DX,1
FINDKEY:CALL    SAME
        JE      FOUND
FINDEND:MOV     AL,[BX]
        INC     BX
        OR      AL,AL
        JNZ     FINDEND
        INC     DX
        CMP     DX,32
        JB      FINDKEY
        JMP     USAGE
FOUND:  PUSH    DX              ;Save selector for INT DCh.
        MOV     SI,DI
        MOV     DI,OFFSET TABLE
        MOV     CX,15
        CMP     DX,20
        JBE     DEFBYTE
        MOV     CX,5
DEFBYTE:LODSB
        OR      AL,AL
        JZ      DEFDONE
        CMP     AL,'\'
        JNE     DEFPUT
        LODSB
        CMP     AL,'\'
        JE      DEFPUT
        CMP     AL,'r'
        JE      DEFCR
        CMP     AL,'e'
        JE      DEFESC
        CMP     AL,'x'
        JNE     BADDEF
        LODSB
        CALL    UNHEX
        JC      BADDEF
        MOV     AH,AL
        LODSB
        CALL    UNHEX
        JC      BADDEF
        SHL     AH,1
        SHL     AH,1
        SHL     AH,1
        SHL     AH,1
        OR      AL,AH
        JZ      BADDEF
        JMP     SHORT DEFPUT
DEFCR:  MOV     AL,13
        JMP     SHORT DEFPUT
DEFESC: MOV     AL,1BH
DEFPUT: JCXZ    BADDEF
        STOSB
        DEC     CX
        JMP     SHORT DEFBYTE
BADDEF: POP     DX
        JMP     USAGE
DEFDONE:STOSB                   ;TABLE starts zeroed.
        POP     AX
        CMP     BYTE PTR [TABLE],0FEH
        JNE     DEFCALL
        CMP     AX,20           ;Only function keys have label metadata.
        JA      DEFCALL
        CMP     DI,OFFSET TABLE+7
        JAE     DEFCALL         ;FEh requires a full five-byte field.
        JMP     USAGE
DEFCALL:MOV     DX,OFFSET TABLE
        JMP     SETKEYS

LOAD:   MOV     AX,3D00H
        INT     21H
        JNC     OPENED
        JMP     IOERR
OPENED: MOV     BX,AX
        MOV     DX,OFFSET FILEBUF
        MOV     CX,FSIZE+1      ;Reject both short and oversized files.
        MOV     AH,3FH
        INT     21H
        CALL    CLOSEFILE
        MOV     SI,OFFSET MAGIC
        MOV     DI,OFFSET FILEBUF
        MOV     CX,6
        REPE    CMPSB
        JNE     FORMATERR
        XOR     AX,AX
        MOV     DX,OFFSET TABLE
SETKEYS:MOV     CL,0DH
        INT     0DCH
        JMP     SHORT SUCCESS

SAVE:   PUSH    DX
        CALL    GETKEYS
        POP     DX
        XOR     CX,CX
        MOV     AH,3CH
        INT     21H
        JC      IOERR
        MOV     BX,AX
        MOV     SI,OFFSET MAGIC
        MOV     DI,OFFSET FILEBUF
        MOV     CX,6
        REP     MOVSB
        MOV     CX,FSIZE
        MOV     DX,OFFSET FILEBUF
        MOV     AH,40H
        INT     21H
        CALL    CLOSEFILE
SUCCESS:XOR     AL,AL
EXIT:   MOV     AH,4CH
        INT     21H

; Close the handle even on a failed or short transfer.
CLOSEFILE:
        PUSHF
        PUSH    AX
        MOV     AH,3EH
        INT     21H
        JC      IOERR
        POP     AX
        POPF
        JC      IOERR
        CMP     AX,FSIZE
        JE      CLOSED
        CMP     DX,OFFSET FILEBUF
        JNE     IOERR
        CMP     CX,FSIZE+1      ;read rather than write
        JE      FORMATERR
IOERR:  MOV     DX,OFFSET ERRIO
        JMP     SHORT ERROR
FORMATERR:
        MOV     DX,OFFSET ERRFMT
ERROR:  MOV     AH,9
        INT     21H
        MOV     AL,1
        JMP     SHORT EXIT
CLOSED: RET

USAGE:  MOV     AL,1
HELP:   PUSH    AX
        MOV     DX,OFFSET HELPMSG
        MOV     AH,9
        INT     21H
        POP     AX
        JMP     SHORT EXIT

; One redirected DOS write per output line. Never print a raw control
; byte from a slot: a definition may itself contain CON escape commands.
LIST:   CALL    GETKEYS
        MOV     BP,OFFSET TABLE
        MOV     SI,OFFSET NAMES
        MOV     DX,1
LISTKEY:MOV     DI,OFFSET LINEBUF
        CALL    COPYZ
        MOV     AX,'  '
        STOSW
        PUSH    SI
        MOV     SI,BP
        MOV     CX,16
        CMP     DX,20
        JBE     LISTDEF
        MOV     CX,6
LISTDEF:ADD     BP,CX
LISTCH: LODSB
        OR      AL,AL
        JZ      LISTEND
        CMP     AL,20H
        JB      LISTHEX
        CMP     AL,7EH
        JA      LISTHEX
        CMP     AL,'\'
        JNE     LISTPUT
        STOSB
LISTPUT:STOSB
        JMP     SHORT LISTNEXT
LISTHEX:CALL    PUTHEX
LISTNEXT:LOOP   LISTCH
LISTEND:MOV     AX,0A0DH
        STOSW
        PUSH    DX
        MOV     DX,OFFSET LINEBUF
        MOV     CX,DI
        SUB     CX,DX
        MOV     BX,1
        MOV     AH,40H
        INT     21H
        JC      IOERR
        CMP     AX,CX
        JNE     IOERR
        POP     DX
        POP     SI
        INC     DX
        CMP     DX,32
        JB      LISTKEY
        JMP     SUCCESS

GETKEYS:MOV     DX,OFFSET TABLE
        XOR     AX,AX
        MOV     CL,0CH
        INT     0DCH
        RET

SPACE:  CMP     BYTE PTR [SI],' '
        JE      SPCNEXT
        CMP     BYTE PTR [SI],9
        JNE     SPCEND
SPCNEXT:INC     SI
        JMP     SHORT SPACE
SPCEND: RET

TOKEN:  MOV     DI,SI
TOKNEXT:MOV     AL,[DI]
        CMP     AL,' '
        JE      TOKEND
        CMP     AL,9
        JE      TOKEND
        OR      AL,AL
        JZ      TOKEND
        INC     DI
        JMP     SHORT TOKNEXT
TOKEND: RET

; Compare two terminated tokens (DS:SI and DS:BX), preserving pointers.
SAME:   PUSH    SI
        PUSH    BX
SAMECH: LODSB
        CMP     AL,'a'
        JB      SAMECMP
        CMP     AL,'z'
        JA      SAMECMP
        SUB     AL,20H
SAMECMP:CMP     AL,[BX]
        JNE     SAMERET
        INC     BX
        OR      AL,AL
        JNZ     SAMECH
SAMERET:POP     BX
        POP     SI
        RET

COPYZ:  LODSB
        OR      AL,AL
        JZ      COPYEND
        STOSB
        JMP     SHORT COPYZ
COPYEND:RET

UNHEX:  SUB     AL,'0'
        CMP     AL,10
        JB      HEXOK
        ADD     AL,'0'
        AND     AL,0DFH
        SUB     AL,'A'
        CMP     AL,6
        JAE     HEXBAD
        ADD     AL,10
HEXOK:  CLC
        RET
HEXBAD: STC
        RET

PUTHEX: MOV     AH,AL
        MOV     AL,'\'
        STOSB
        MOV     AL,'x'
        STOSB
        MOV     AL,AH
        SHR     AL,1
        SHR     AL,1
        SHR     AL,1
        SHR     AL,1
        CALL    DIGIT
        MOV     AL,AH
        AND     AL,0FH
DIGIT:  ADD     AL,'0'
        CMP     AL,'9'
        JBE     DIGOUT
        ADD     AL,7
DIGOUT: STOSB
        RET

OPTSAVE DB      '/SAVE',0
MAGIC   DB      'VAKEY',1
NAMES   DB      'F1',0,'F2',0,'F3',0,'F4',0,'F5',0
        DB      'F6',0,'F7',0,'F8',0,'F9',0,'F10',0
        DB      'SF1',0,'SF2',0,'SF3',0,'SF4',0,'SF5',0
        DB      'SF6',0,'SF7',0,'SF8',0,'SF9',0,'SF10',0
        DB      'ROLLUP',0,'ROLLDOWN',0,'INS',0,'DEL',0
        DB      'UP',0,'LEFT',0,'RIGHT',0,'DOWN',0,'HOME',0,'HELP',0,'SHOME',0
HELPMSG DB      'KEY                 List definitions',13,10
        DB      'KEY SF1 dir b:\r    Set Shift+F1 (example)',13,10
        DB      'KEY filename        Load a VA key file',13,10
        DB      'KEY /SAVE filename  Save a VA key file',13,10
        DB      'KEY /?              Show this help',13,10
        DB      'Use \r for CR, \e for ESC, \xHH for a byte, \\ for backslash.',13,10
        DB      'Use \xFE followed by five label bytes at the start of an F-key.',13,10,'$'
ERRIO   DB      'KEY: DOS I/O error',13,10,'$'
ERRFMT  DB      'KEY: not a VA key file',13,10,'$'
TAILBUF DB      128 DUP (0)
LINEBUF DB      80 DUP (0)
FILEBUF DB      6 DUP (0)
TABLE   DB      KSIZE+1 DUP (0)
CODE    ENDS
        END     START
