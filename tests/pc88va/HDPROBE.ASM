; SPDX-License-Identifier: MIT
; Run only with disposable synthetic probe images: writes physical block 0.
; HDPROBE X also tries an out-of-range read (may not return on vaeg).
; Records: target, CF, AL, AH. One stderr dot per completed record.
CODE SEGMENT
ASSUME CS:CODE,DS:CODE
ORG 100H
BEGIN:  JMP RUN
; Type 2 uses vaeg's 615x4 geometry here (manual: 308x8).
CAPS    DD 20196,40920,81180,162360
TARGET  DB 0
TYPEID  DB 0
RESULT  DB 4 DUP (0)
MARKER  DB '.'
BUFSEG  DW 0
BLOCK   DD 0
RUN:
        CLI
        MOV SP,OFFSET STACKTOP
        STI
        MOV BX,CSIEND
        MOV CL,4
        SHR BX,CL
        MOV AH,4AH
        INT 21H
        JNC ALLOC
        JMP QUIT
ALLOC:  MOV BX,2000H
        MOV AH,48H
        INT 21H
        JNC ALIGNBUF
        JMP QUIT
ALIGNBUF:
        ADD AX,0FFFH
        AND AX,0F000H
        MOV [BUFSEG],AX
NEXT:
        XOR DX,DX
        XOR CX,CX
        MOV AX,0900H
        CALL BIOS
        CALL REPORT
        JC ABSENT
        CMP AH,0
        JNE ABSENT
        CMP AL,3
        JBE PRESENT
ABSENT: JMP SKIP
PRESENT:MOV [TYPEID],AL
        XOR BP,BP
        MOV WORD PTR [BLOCK],0
        MOV WORD PTR [BLOCK+2],0
        MOV AX,8102H            ;Two blocks in one DMA page.
        CALL DATAIO
        MOV BP,0FF00H
        MOV AX,8102H            ;Cross physical 64 KiB boundary.
        CALL DATAIO
        XOR BP,BP
        MOV ES,[BUFSEG]
        MOV WORD PTR ES:[0],0D258H
        MOV AX,8201H
        CALL DATAIO
        MOV WORD PTR ES:[0],0
        MOV AX,8101H
        CALL DATAIO
        MOV AX,ES:[0]
        CLC
        CALL REPORT
        XOR AH,AH
        MOV AL,[TYPEID]
        MOV SI,AX
        SHL SI,1
        SHL SI,1
        MOV AX,WORD PTR [CAPS+SI]
        MOV DX,WORD PTR [CAPS+SI+2]
        SUB AX,1
        SBB DX,0
        MOV WORD PTR [BLOCK],AX
        MOV WORD PTR [BLOCK+2],DX
        MOV AX,8101H            ;Last backing block.
        CALL DATAIO
        CMP BYTE PTR DS:[82H],'X'
        JNE SKIP
        ADD WORD PTR [BLOCK],1
        ADC WORD PTR [BLOCK+2],0
        MOV AX,8101H            ;One block past backing capacity.
        CALL DATAIO
SKIP:   INC [TARGET]
        CMP [TARGET],2
        JAE QUIT
        JMP NEXT
QUIT:   MOV AX,4C00H
        INT 21H
DATAIO:
        MOV CX,WORD PTR [BLOCK]
        MOV DX,WORD PTR [BLOCK+2]
        MOV ES,[BUFSEG]
        CALL BIOS
        JMP SHORT REPORT
BIOS:   PUSH DS
        PUSH ES
        PUSH BP
        XOR BX,BX
        MOV BH,[TARGET]
        TEST AH,80H
        JZ ISSUE
        OR BH,80H
ISSUE:  CLC
        STI
        INT 81H
        POP BP
        POP ES
        POP DS
        RET
REPORT: PUSHF
        PUSH AX
        PUSH BX
        PUSH CX
        PUSH DX
        MOV WORD PTR [RESULT+2],AX
        MOV AL,[TARGET]
        MOV [RESULT],AL
        MOV AL,0
        ADC AL,0
        MOV [RESULT+1],AL
        MOV BX,2
        MOV CX,1
        MOV DX,OFFSET MARKER
        MOV AH,40H
        INT 21H
        MOV BX,1
        MOV CX,4
        MOV DX,OFFSET RESULT
        MOV AH,40H
        INT 21H
        POP DX
        POP CX
        POP BX
        POP AX
        POPF
        RET
        DB 1024 DUP (0)
STACKTOP LABEL BYTE
CSIEND EQU ($-BEGIN+100H+15)
CODE ENDS
END BEGIN
