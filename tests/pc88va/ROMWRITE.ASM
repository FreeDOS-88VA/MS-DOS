; MASM 5.10: assemble and link as a tiny COM (ORG 100h).
; No DOS output. Each phase clears the main split and writes 32 numbered
; lines; both must leave their last line visible and the labels intact.
CODE SEGMENT BYTE PUBLIC 'CODE'
        ASSUME CS:CODE,DS:CODE
        ORG 100H
START:  CALL    CLEAR
        MOV     BYTE PTR [PREFIX],'P'
        CALL    LINES
        CALL    PAUSE
        CALL    CLEAR
        MOV     BYTE PTR [PREFIX],'C'
        CALL    LINES
        CALL    PAUSE
        MOV     AX,4C00H
        INT     21H
CLEAR:  MOV     AX,1702H
        INT     83H
        MOV     AH,08H
        XOR     DX,DX
        INT     83H
        RET
LINES:  MOV     BL,1
LINE:   PUSH    BX
        MOV     AL,BL
        AAM
        ADD     AX,3030H
        MOV     [TENS],AH
        MOV     [ONES],AL
        MOV     SI,OFFSET PREFIX
        CMP     BYTE PTR [PREFIX],'C'
        JE      CHARS
        MOV     AX,0200H
        MOV     DX,8000H
        INT     83H
        JMP     SHORT NEXTLINE
CHARS:  LODSB
        OR      AL,AL
        JZ      NEXTLINE
        PUSH    SI
        XOR     DX,DX
        MOV     DL,AL
        XOR     AX,AX
        INT     83H
        POP     SI
        JMP     SHORT CHARS
NEXTLINE:
        POP     BX
        INC     BL
        CMP     BL,33
        JB      LINE
        RET
PAUSE:  MOV     AH,08H
        INT     21H
        CMP     AL,' '
        JNE     PAUSE
        RET
PREFIX  DB      'P'
TENS    DB      '0'
ONES    DB      '0',13,10,0
CODE ENDS
        END START
