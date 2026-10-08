; SPDX-License-Identifier: MIT
;
; Floppy media check and sector transfer through the PC-88VA ROM floppy
; BIOS (INT 80h), shared by the MS-DOS 2.0 and 4.0 BIOS parts.  Included in
; the CODE segment with DS = CS; the including file defines NUNITS, SECTRK,
; SECSIZ, FDMODE, SECLEN, CALLFL, PTRSAV, MEDSTAT, BADUNIT, EXIT and
; ERR_EXIT, and the request field COUNT.

OPCODE  DB      0               ;81H read, 82H write (no ROM retries).
DRIVE   DB      0
TRACK   DB      0               ;Cylinder * 2 + head.
SECTOR  DB      0               ;1-based first sector.
NSECT   DB      0               ;Sectors in this ROM call.
TRIES   DB      0
XSTAT   DB      0
MODEOK  DB      NUNITS DUP (0)  ;Disk mode selected for the unit.

; Media check.  The ROM reports whether the drive door may have opened
; since the previous check of the same drive; it cannot tell while the
; motor is off.  "Not changed" lets DOS keep its buffers, "don't know"
; makes it check the disk.
MEDIAC: CMP     AL,NUNITS
        JAE     MEDC9
        MOV     CH,AL
        MOV     AH,09H
        PUSH    CS:[CALLFL]
        POPF
        INT     80H
        MOV     AL,1            ;Not changed.
        JNC     MEDC1
        MOV     AL,0            ;Don't know.
MEDC1:  LDS     BX,CS:[PTRSAV]
        MOV     BYTE PTR [BX+MEDSTAT],AL
        MOV     AL,0
        JMP     EXIT
MEDC9:  JMP     BADUNIT

; AL = unit, ES:DI = transfer address, CX = sectors, DX = first sector.
DSK_RED:
        MOV     [OPCODE],81H
        JMP     SHORT DSK_COM
DSK_WRT:
        MOV     [OPCODE],82H
DSK_COM:
        CMP     AL,NUNITS
        JAE     MEDC9
        CALL    DSK_XFER
        JC      DSK_ERR
        MOV     AL,0
        JMP     EXIT
DSK_ERR:
        LDS     BX,CS:[PTRSAV]
        MOV     [BX.COUNT],0
        JMP     ERR_EXIT

; Transfer CX sectors from logical sector DX of unit AL to or from ES:DI
; with ROM operation [OPCODE].  The sectors of one track go in one ROM
; call, split where the buffer crosses a 64 KB physical boundary.
; CF=1 and AL = DOS error code on failure.
DSK_XFER:
        MOV     [DRIVE],AL
        JCXZ    DSK_X9
        JMP     SHORT DSK_RUN
DSK_X9: CLC
        RET
DSK_RUN:
        PUSH    CX              ;Sectors still to transfer.
        MOV     AX,DX
        AND     AL,SECTRK-1
        MOV     BL,SECTRK
        SUB     BL,AL           ;Sectors left on this track.
        XOR     BH,BH
        INC     AL
        MOV     [SECTOR],AL
        CMP     CX,BX
        JBE     DSK_R1
        MOV     CX,BX
DSK_R1: PUSH    CX              ;Sectors that fit below the next 64 KB.
        MOV     AX,ES
        MOV     CL,4
        SHL     AX,CL
        ADD     AX,DI
        NEG     AX
        MOV     BX,AX
        MOV     CL,10
        SHR     BX,CL
        POP     CX
        OR      AX,AX
        JZ      DSK_R3          ;Exactly on a boundary: 64 KB available.
        OR      BX,BX
        JNZ     DSK_R2
        MOV     BX,1            ;A sector straddles it: one at a time.
DSK_R2: CMP     CX,BX
        JBE     DSK_R3
        MOV     CX,BX
DSK_R3: MOV     [NSECT],CL
        MOV     AX,DX
        MOV     CL,3            ;Divide by SECTRK.
        SHR     AX,CL
        MOV     [TRACK],AL
        MOV     [TRIES],3
DSK_TRY:
        PUSH    DX
        PUSH    DI
        PUSH    ES
        PUSH    DS
        MOV     BL,[DRIVE]
        XOR     BH,BH
        CMP     BYTE PTR [MODEOK+BX],0
        JNE     DSK_T1
        MOV     AH,0AH          ;Select the 2HD/1024-byte mode once.
        MOV     AL,FDMODE
        MOV     CH,BL
        PUSH    CS:[CALLFL]
        POPF
        INT     80H
        POP     DS
        PUSH    DS
        JC      DSK_FAIL
        OR      AH,AH
        JNZ     DSK_FAIL
        MOV     BL,[DRIVE]
        XOR     BH,BH
        MOV     BYTE PTR [MODEOK+BX],1
DSK_T1: MOV     BP,DI           ;ES:BP = transfer address.
        MOV     AL,[TRACK]
        MOV     CL,AL
        MOV     CH,[DRIVE]
        MOV     BH,AL
        SHR     BH,1            ;Cylinder.
        MOV     BL,AL
        AND     BL,1            ;Head.
        MOV     DH,[SECTOR]
        MOV     DL,SECLEN
        MOV     AH,[OPCODE]
        MOV     AL,[NSECT]
        PUSH    CS:[CALLFL]
        POPF
        INT     80H
        JC      DSK_FAIL
        OR      AH,AH
        JNZ     DSK_FAIL
        POP     DS
        POP     ES
        POP     DI
        POP     DX
        MOV     AL,[NSECT]
        XOR     AH,AH
        ADD     DX,AX
        MOV     CL,6            ;1024 bytes = 64 paragraphs.
        SHL     AX,CL
        MOV     BX,ES
        ADD     BX,AX
        MOV     ES,BX
        POP     CX
        MOV     AL,[NSECT]
        XOR     AH,AH
        SUB     CX,AX
        JZ      DSK_X8
        JMP     DSK_RUN
DSK_X8: CLC
        RET

DSK_FAIL:
        MOV     CS:[XSTAT],AH
        POP     DS
        POP     ES
        POP     DI
        POP     DX
        MOV     BL,[DRIVE]      ;Select the mode again on the retry.
        XOR     BH,BH
        MOV     BYTE PTR [MODEOK+BX],0
        DEC     [TRIES]
        JZ      DSK_F0
        JMP     DSK_TRY
DSK_F0: POP     CX
        MOV     AL,[XSTAT]      ;Map the ROM status to a DOS error.
        MOV     BX,OFFSET ERRMAP
DSK_FL1:
        MOV     AH,[BX]
        INC     BX
        CMP     AH,0FFH
        JE      DSK_FL2
        CMP     AH,AL
        JE      DSK_FL3
        INC     BX
        JMP     DSK_FL1
DSK_FL2:
        MOV     BL,11           ;Read fault.
        CMP     [OPCODE],82H
        JNE     DSK_FL4
        MOV     BL,10           ;Write fault.
        JMP     SHORT DSK_FL4
DSK_FL3:
        MOV     BL,[BX]
DSK_FL4:
        MOV     AL,BL
        STC
        RET

; ROM floppy status, DOS error code.
ERRMAP  DB      03H,2, 04H,2, 05H,0, 06H,4, 07H,4, 08H,8, 09H,6, 0AH,6
        DB      0BH,7, 0CH,8, 0FFH
