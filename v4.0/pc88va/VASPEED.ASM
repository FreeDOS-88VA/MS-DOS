        TITLE   SPEED for the NEC PC-88VA
; SPDX-License-Identifier: MIT
; Set the baud rate of the built-in AUX/COM1 device. The DOS driver
; already initialized 8N1 at boot; do not reset it or flush RX here.

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE
        ORG     100H
START:
        CLD
        XOR     CX,CX
        MOV     CL,BYTE PTR DS:[80H]
        MOV     SI,81H
        JCXZ    USAGE
SKIP:   LODSB
        CMP     AL,' '
        JE      SPACE
        CMP     AL,9
        JNE     NUMBER
SPACE:  LOOP    SKIP
        JMP     SHORT USAGE
NUMBER: XOR     DI,DI
        MOV     BX,10
DIGIT:  SUB     AL,'0'
        CMP     AL,9
        JA      USAGE
        XOR     AH,AH
        XCHG    AX,DI
        MUL     BX
        JC      USAGE
        ADD     DI,AX
        JC      USAGE
        DEC     CX
        JZ      FIND
        LODSB
        CMP     AL,' '
        JE      TRAIL
        CMP     AL,9
        JNE     DIGIT
TRAIL:  DEC     CX
        JZ      FIND
        LODSB
        CMP     AL,' '
        JE      TRAIL
        CMP     AL,9
        JE      TRAIL
        JMP     SHORT USAGE
FIND:   MOV     SI,OFFSET RATES
        MOV     CX,9
        MOV     DH,1
LOOK:   LODSW
        CMP     AX,DI
        JE      SETRATE
        INC     DH
        LOOP    LOOK
USAGE:  MOV     DX,OFFSET HELPMSG
        JMP     SHORT ERROR
SETRATE:MOV     AH,8            ;$BRATE, technical manual 6.10.3(9).
        PUSH    DS
        INT     8AH
        POP     DS
        JNC     OK
        MOV     DX,OFFSET BIOSMSG
ERROR:  MOV     AH,9
        INT     21H
        MOV     AX,4C01H
        INT     21H
OK:     MOV     AX,4C00H
        INT     21H

RATES   DW      75,150,300,600,1200,2400,4800,9600,19200
HELPMSG DB      'Usage: SPEED baud (AUX/COM1, 8N1)',13,10
        DB      'Baud: 75 150 300 600 1200 2400 4800 9600 19200',13,10,'$'
BIOSMSG DB      'Serial BIOS rejected the baud rate.',13,10,'$'
CODE    ENDS
        END     START
