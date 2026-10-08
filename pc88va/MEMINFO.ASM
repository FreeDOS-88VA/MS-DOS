        TITLE   MEMINFO - report the DOS memory layout

; SPDX-License-Identifier: MIT
;
; Writes the DOS version, PSP, List of Lists, device chain, memory arena,
; largest free block and RAM-resident interrupt vectors to standard output.
; Uses only calls present in MS-DOS 2.0 (AH=52h is undocumented there).

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE

        ORG     100H

START:  CLD
        MOV     DI,OFFSET BUF
        MOV     SI,OFFSET S_VER
        CALL    PUTS
        MOV     AH,30H
        INT     21H
        CALL    HEXB            ;Major.
        MOV     AL,'.'
        STOSB
        MOV     AL,AH
        CALL    HEXB            ;Minor.
        CALL    NL

        MOV     SI,OFFSET S_PSP
        CALL    PUTS
        MOV     AX,CS
        CALL    HEXW
        CALL    NL

        MOV     AH,52H
        PUSH    ES
        INT     21H
        MOV     WORD PTR [LOL],BX
        MOV     WORD PTR [LOL+2],ES
        MOV     AX,ES:[BX-2]
        MOV     [FIRSTMCB],AX
        POP     ES
        MOV     SI,OFFSET S_LOL
        CALL    PUTS
        MOV     AX,WORD PTR [LOL+2]
        CALL    HEXW
        MOV     AL,':'
        STOSB
        MOV     AX,WORD PTR [LOL]
        CALL    HEXW
        CALL    NL

; Device chain: the NUL header follows the List of Lists at +17h in 2.x
; and at +22h in 3.x and later.
        MOV     SI,OFFSET S_DEV
        CALL    PUTS
        CALL    NL
        MOV     AH,30H
        INT     21H
        MOV     BX,17H
        CMP     AL,3
        JB      DEV0
        MOV     BX,22H
DEV0:   PUSH    DS
        LDS     SI,[LOL]
        ADD     SI,BX
        MOV     CX,40
DEV1:   MOV     AX,DS
        CALL    HEXW
        MOV     AL,':'
        STOSB
        MOV     AX,SI
        CALL    HEXW
        MOV     AL,' '
        STOSB
        MOV     AX,[SI+4]
        CALL    HEXW
        MOV     AL,' '
        STOSB
        PUSH    SI
        PUSH    CX
        ADD     SI,10
        MOV     CX,8
DEV2:   LODSB
        CMP     AL,20H
        JB      DEV3
        CMP     AL,7EH
        JBE     DEV4
DEV3:   MOV     AL,'.'
DEV4:   STOSB
        LOOP    DEV2
        POP     CX
        POP     SI
        CALL    NL
        CMP     WORD PTR [SI],0FFFFH
        JE      DEV5
        LDS     SI,[SI]
        LOOP    DEV1
DEV5:   POP     DS

; Memory arena.
        MOV     SI,OFFSET S_MCB
        CALL    PUTS
        CALL    NL
        MOV     AX,[FIRSTMCB]
        MOV     CX,100
MCB1:   PUSH    CX
        PUSH    ES
        MOV     ES,AX
        MOV     DL,ES:[0]
        MOV     BX,ES:[1]
        MOV     CX,ES:[3]
        POP     ES
        PUSH    AX
        CALL    HEXW
        MOV     AL,' '
        STOSB
        MOV     AL,DL
        STOSB
        MOV     AL,' '
        STOSB
        MOV     AX,BX
        CALL    HEXW
        MOV     AL,' '
        STOSB
        MOV     AX,CX
        CALL    HEXW
        CALL    NL
        POP     AX
        ADD     AX,CX
        INC     AX
        POP     CX
        CMP     DL,'M'
        JNE     MCB2
        LOOP    MCB1
MCB2:
        MOV     SI,OFFSET S_OWN
        CALL    PUTS
        PUSH    ES
        MOV     AX,CS
        DEC     AX
        MOV     ES,AX
        MOV     AX,ES:[3]
        POP     ES
        CALL    HEXW
        CALL    NL

        MOV     SI,OFFSET S_FREE
        CALL    PUTS
        MOV     BX,0FFFFH
        MOV     AH,48H
        INT     21H
        MOV     AX,BX
        CALL    HEXW
        CALL    NL

; Interrupt vectors that point into conventional memory.
        MOV     SI,OFFSET S_VEC
        CALL    PUTS
        CALL    NL
        XOR     BX,BX
VEC1:   PUSH    DS
        XOR     AX,AX
        MOV     DS,AX
        MOV     DX,[BX]
        MOV     AX,[BX+2]
        POP     DS
        CMP     AX,0A000H
        JAE     VEC2
        PUSH    AX
        MOV     AX,BX
        SHR     AX,1
        SHR     AX,1
        CALL    HEXB
        MOV     AL,'='
        STOSB
        POP     AX
        CALL    HEXW
        MOV     AL,':'
        STOSB
        MOV     AX,DX
        CALL    HEXW
        CALL    NL
VEC2:   ADD     BX,4
        CMP     BX,400H
        JB      VEC1

        MOV     CX,DI
        SUB     CX,OFFSET BUF
        MOV     DX,OFFSET BUF
        MOV     BX,1
        MOV     AH,40H
        INT     21H
        MOV     AX,4C00H
        INT     21H

PUTS:   LODSB
        OR      AL,AL
        JZ      PUTS9
        STOSB
        JMP     PUTS
PUTS9:  RET

NL:     MOV     AX,0A0DH
        STOSW
        RET

HEXW:   PUSH    AX
        MOV     AL,AH
        CALL    HEXB
        POP     AX
HEXB:   PUSH    AX
        PUSH    CX
        MOV     CL,4
        SHR     AL,CL
        CALL    NIB
        POP     CX
        POP     AX
        PUSH    AX
        CALL    NIB
        POP     AX
        RET
NIB:    AND     AL,0FH
        ADD     AL,'0'
        CMP     AL,'9'
        JBE     NIB9
        ADD     AL,7
NIB9:   STOSB
        RET

S_VER   DB      'DOS version ',0
S_PSP   DB      'PSP ',0
S_LOL   DB      'List of lists ',0
S_DEV   DB      'Devices (header attr name):',0
S_MCB   DB      'Arena (MCB type owner paragraphs):',0
S_OWN   DB      'Own block paragraphs ',0
S_FREE  DB      'Largest free paragraphs ',0
S_VEC   DB      'Vectors in RAM:',0
LOL     DD      0
FIRSTMCB DW     0

BUF     LABEL   BYTE

CODE    ENDS

        END     START
