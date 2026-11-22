        TITLE   INT 80h READ ID probe for PC-88VA
; SPDX-License-Identifier: MIT
; FDPROBE > IDS.BIN, with the test disk in B:. One 12-byte record per
; attempt: track, mode, FM flag, carry, AH, ST0/ST1/ST2, C/H/R/N.
CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG 100H
START:  CLD
        MOV AH,0DH              ;Get documented BIOS work-relative pointer.
        INT 80H
        MOV [BOOKSEG],ES
        MOV [BOOKOFF],DX
        MOV SI,DX
        MOV AX,ES:[SI]
        MOV [MODESAV],AH
        MOV AL,ES:[SI+4]
        MOV [SURFSAV],AL
        OR BYTE PTR ES:[SI+4],2
        MOV DI,OFFSET ROWS
        MOV SI,OFFSET TRACKS
TRACK1: LODSB
        CMP AL,0FFH
        JNE TRACK2
        JMP NEAR PTR DONE
TRACK2: MOV [TRACK],AL
        MOV BX,OFFSET MODES
MODE1:  MOV AL,[BX]
        INC BX
        CMP AL,0FFH
        JNE MODE2
        JMP SHORT TRACK1
MODE2:  MOV [MODE],AL
        MOV AH,0AH
        MOV CH,1
        PUSH BX
        CALL BIOS
        POP BX
        MOV BYTE PTR [FM],0
TRYFM:  MOV BYTE PTR [LEFT],42
ID1:    MOV CH,1
        MOV CL,[TRACK]
        MOV DL,[FM]
        MOV AH,85H
        PUSH BX
        CALL BIOS
        PUSHF
        MOV [DI+4],AH
        MOV [DI+5],AL
        MOV [DI+6],BH
        MOV [DI+7],BL
        MOV [DI+8],CH
        MOV [DI+9],CL
        MOV [DI+10],DH
        MOV [DI+11],DL
        MOV AX,WORD PTR [TRACK]
        MOV [DI],AX
        MOV AL,[FM]
        MOV [DI+2],AL
        POP AX
        AND AL,1
        MOV [DI+3],AL
        ADD DI,12
        POP BX
        OR AL,[DI-8]
        JNZ NEXTFM
        CMP BYTE PTR [LEFT],42
        JE FIRST
        CMP CX,[FIRSTCH]
        JNE NEXTID
        CMP DX,[FIRSTRN]
        JE NEXTFM
        JMP SHORT NEXTID
FIRST:  MOV [FIRSTCH],CX
        MOV [FIRSTRN],DX
NEXTID: DEC BYTE PTR [LEFT]
        JNZ ID1
NEXTFM: XOR BYTE PTR [FM],80H
        JS TRYFM
        JMP NEAR PTR MODE1
DONE:   MOV AL,[MODESAV]
        CMP AL,0FFH
        JE RESTORE
        MOV AH,0AH
        MOV CH,1
        CALL BIOS
RESTORE:MOV ES,[BOOKSEG]
        MOV SI,[BOOKOFF]
        MOV AL,[MODESAV]
        MOV ES:[SI+1],AL
        MOV AL,[SURFSAV]
        MOV ES:[SI+4],AL
        MOV CX,DI
        SUB CX,OFFSET ROWS
        MOV DX,OFFSET ROWS
        MOV BX,1
        MOV AH,40H
        INT 21H
        JC ERROR1
        CMP AX,CX
        JNE ERROR1
        MOV AX,4C00H
        INT 21H
ERROR1: MOV AX,4C01H
        INT 21H

BIOS:   PUSH DS
        PUSH ES
        PUSH SI
        PUSH DI
        PUSH BP
        INT 80H
        POP BP
        POP DI
        POP SI
        POP ES
        POP DS
        RET
BOOKSEG DW 0
BOOKOFF DW 0
MODESAV DB 0
SURFSAV DB 0
TRACK   DB 0
MODE    DB 0
FM      DB 0
LEFT    DB 0
FIRSTCH DW 0
FIRSTRN DW 0
MODES   DB 23H,12H,01H,0FFH
TRACKS  DB 0,1,2,3,4,78,79,80,81,152,153,154,158,159,0FFH
ROWS    DB 14*6*42*12 DUP (?)
CODE    ENDS
        END START
