; SPDX-License-Identifier: MIT
;
; CLOCK$ read and write through the PC-88VA calendar BIOS (INT 8Ch).
; Function 00h returns CX = year (1980-2079), DH = month, DL = day;
; 01h sets them.  Function 02h returns CH = hour, CL = minute, DH = second;
; 03h sets them.  The DOS CLOCK$ record is: days since 1-1-1980 (word),
; minutes, hours, hundredths, seconds.  Included in the CODE segment of an
; IO.SYS BIOS part with DS = CS; ES:DI addresses the 6-byte record.

MONTAB  DW      0,31,59,90,120,151,181,212,243,273,304,334

; Read the calendar into the record at ES:DI.
VA_RDCLK:
        MOV     AH,00H
        INT     8CH
        PUSH    DX
        MOV     AX,CX
        SUB     AX,1980
        MOV     BP,AX           ;BP = years since 1980.
        MOV     CX,365
        MUL     CX
        MOV     SI,AX
        MOV     AX,BP
        ADD     AX,3
        SHR     AX,1
        SHR     AX,1
        ADD     SI,AX           ;Leap days in earlier years.
        POP     DX
        MOV     BL,DH
        XOR     BH,BH
        DEC     BX
        SHL     BX,1
        ADD     SI,[MONTAB+BX]
        CMP     DH,2
        JBE     VA_RD1
        TEST    BP,3
        JNZ     VA_RD1
        INC     SI              ;After February of a leap year.
VA_RD1: MOV     AL,DL
        XOR     AH,AH
        DEC     AX
        ADD     SI,AX
        MOV     ES:[DI],SI
        MOV     AH,02H
        INT     8CH
        MOV     ES:[DI+2],CL
        MOV     ES:[DI+3],CH
        MOV     BYTE PTR ES:[DI+4],0
        MOV     ES:[DI+5],DH
        RET

; Set the calendar from the record at ES:DI.
VA_WRCLK:
        MOV     AX,ES:[DI]      ;Days since 1-1-1980.
        MOV     CX,1980
VA_WR1: MOV     BX,365
        TEST    CL,3
        JNZ     VA_WR2
        INC     BX
VA_WR2: CMP     AX,BX
        JB      VA_WR3
        SUB     AX,BX
        INC     CX
        JMP     VA_WR1
VA_WR3: MOV     BX,11*2         ;Find the month.
VA_WR4: MOV     DX,[MONTAB+BX]
        CMP     BX,2*2
        JB      VA_WR5
        TEST    CL,3
        JNZ     VA_WR5
        INC     DX              ;Leap day before March.
VA_WR5: CMP     AX,DX
        JAE     VA_WR6
        SUB     BX,2
        JMP     VA_WR4
VA_WR6: SUB     AX,DX
        INC     AX
        MOV     DL,AL           ;Day.
        SHR     BX,1
        INC     BX
        MOV     DH,BL           ;Month.
        MOV     AH,01H
        INT     8CH
        MOV     CH,ES:[DI+3]
        MOV     CL,ES:[DI+2]
        MOV     DH,ES:[DI+5]
        MOV     AH,03H
        INT     8CH
        RET
