; SPDX-License-Identifier: MIT
; COM probe for VAIO CON input. Run CONKEY for assertions or CONKEY K
; to print the raw byte stream (lowercase q ends the dump).
CODE    SEGMENT
        ASSUME  CS:CODE,DS:CODE
        ORG     100H

START:  CMP     BYTE PTR DS:[82H],'K'
        JNE     CHECKS
        JMP     DUMPKEY
CHECKS: MOV     DX,OFFSET READY
        CALL    PRINT

        MOV     BL,1
        MOV     AH,07H
        INT     21H             ;F1: ESC, then S must still be pending.
        CMP     AL,1BH
        JE      FIRSTOK
        JMP     FAIL
FIRSTOK:CALL    WAITING
        CALL    WAITING         ;Status must not consume S.
        MOV     AH,08H
        INT     21H
        CMP     AL,'S'
        JNE     FAIL
        CALL    EMPTY

        INC     BL              ;F2: nonblocking direct input, two bytes.
POLL:   MOV     AX,0600H
        MOV     DL,0FFH
        INT     21H
        JZ      POLL
        CMP     AL,1BH
        JNE     FAIL
        CALL    WAITING
        MOV     AH,06H
        MOV     DL,0FFH
        INT     21H
        JZ      FAIL
        CMP     AL,'T'
        JNE     FAIL
        CALL    EMPTY

        INC     BL              ;F3: consume ESC, then flush pending U.
        MOV     AH,08H
        INT     21H
        CMP     AL,1BH
        JNE     FAIL
        CALL    WAITING
        MOV     AX,0C06H
        MOV     DL,0FFH
        INT     21H
        JNZ     FAIL
        CALL    EMPTY

        INC     BL              ;Shift+F3 followed by ordinary lowercase a.
        MOV     SI,OFFSET EXPECTED
NEXT:   MOV     AH,07H
        INT     21H
        CMP     AL,[SI]
        JNE     FAIL
        INC     SI
        CMP     SI,OFFSET EXPECTEND
        JE      PASSED
        CMP     BYTE PTR [SI],'a'
        JE      NEXT            ;The ordinary key need not have arrived yet.
        CALL    WAITING
        JMP     SHORT NEXT

PASSED: MOV     DX,OFFSET OK
        CALL    PRINT
        MOV     AX,4C00H
        INT     21H

WAITING:
        MOV     AH,0BH
        INT     21H
        CMP     AL,0FFH
        JNE     FAIL
        RET
EMPTY:  MOV     AH,0BH
        INT     21H
        OR      AL,AL
        JNZ     FAIL
        RET

FAIL:   ADD     BL,'0'
        MOV     [FAILNUM],BL
        MOV     DX,OFFSET ERRMSG
        CALL    PRINT
        MOV     AX,4C01H
        INT     21H

DUMPKEY:
        MOV     DX,OFFSET RAWMSG
        CALL    PRINT
RAWNEXT:
        MOV     AH,07H
        INT     21H
        CMP     AL,'q'
        JE      RAWEND
        MOV     BL,AL
        MOV     DL,AL
        MOV     CL,4
        SHR     DL,CL
        CALL    HEXOUT
        MOV     DL,BL
        AND     DL,0FH
        CALL    HEXOUT
        MOV     DL,' '
        MOV     AH,02H
        INT     21H
        JMP     SHORT RAWNEXT
RAWEND: MOV     DX,OFFSET RAWDONE
        CALL    PRINT
        MOV     AX,4C00H
        INT     21H

HEXOUT: ADD     DL,'0'
        CMP     DL,'9'
        JBE     DIGIT
        ADD     DL,'A'-'9'-1
DIGIT:  MOV     AH,02H
        INT     21H
        RET
PRINT:  MOV     AH,09H
        INT     21H
        RET

EXPECTED DB     'copy a'
EXPECTEND LABEL BYTE
READY   DB      'F1 F2 F3 Shift+F3 a',13,10,'$'
OK      DB      'PASS: 07 08 06 0B 0C',13,10,'$'
ERRMSG  DB      'FAIL: stage '
FAILNUM DB      '?',13,10,'$'
RAWMSG  DB      'Raw CON (q exits):',13,10,'$'
RAWDONE DB      13,10,'$'
CODE    ENDS
        END START
