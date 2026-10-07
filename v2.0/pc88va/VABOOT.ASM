        TITLE   Boot sector for the PC-88VA MS-DOS 2.0 experiment

; SPDX-License-Identifier: MIT
;
; The ROM loads this 1024-byte sector at 3000:0000 and jumps to it.  It
; reads the contiguous IO.SYS + MSDOS.SYS extent to BIOSSEG:0 and enters
; IO.SYS with DX = MSDOS.SYS segment.  The image builder fills the BPB
; (offsets 3-61), the three extent words and the 55AAh signatures.

BOOTSEG EQU     3000H
BIOSSEG EQU     1000H
SECTRK  EQU     8
SECLEN  EQU     3               ;1024-byte sectors.

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE

        ORG     0

BOOT:   JMP     SHORT START
        NOP
        DB      59 DUP (0)      ;BPB, written by the image builder.

; Offset 62: extent written by the image builder.
FIRST   DW      0               ;LBA of IO.SYS.
NSECT   DW      0               ;Sectors of IO.SYS + MSDOS.SYS.
IOSECT  DW      0               ;Sectors of IO.SYS.

CALLFL  DW      0245H           ;Flags for ROM disk calls.
TRACK   DB      0

START:  CLI
        MOV     AX,CS
        MOV     DS,AX
        MOV     SS,AX
        MOV     SP,1000H
        STI
        CLD
        MOV     AX,BIOSSEG
        MOV     ES,AX
        MOV     DX,[FIRST]
        MOV     CX,[NSECT]
        JCXZ    FAIL
NEXT:   PUSH    CX
        PUSH    DX
        PUSH    ES
        MOV     AX,DX
        MOV     CL,3            ;Divide by SECTRK.
        SHR     AX,CL
        MOV     [TRACK],AL
        AND     DL,SECTRK-1
        INC     DL
        MOV     DH,DL           ;Sector.
        MOV     BH,AL
        SHR     BH,1            ;Cylinder.
        MOV     BL,AL
        AND     BL,1            ;Head.
        MOV     CL,AL           ;Cylinder * 2 + head.
        MOV     CH,0            ;Drive A:.
        MOV     DL,SECLEN
        XOR     BP,BP
        MOV     AX,8101H        ;Read one sector to ES:BP.
        PUSH    DS
        PUSH    CALLFL
        POPF
        INT     80H
        POP     DS
        JC      FAIL
        OR      AH,AH
        JNZ     FAIL
        POP     ES
        POP     DX
        POP     CX
        MOV     AX,ES
        ADD     AX,1024/16
        MOV     ES,AX
        INC     DX
        LOOP    NEXT
        MOV     DX,[IOSECT]
        MOV     CL,6            ;1024 bytes = 64 paragraphs.
        SHL     DX,CL
        ADD     DX,BIOSSEG
        DB      0EAH            ;JMP BIOSSEG:0
        DW      0,BIOSSEG

FAIL:   CLI
        HLT
        JMP     FAIL

CODE    ENDS

        END
