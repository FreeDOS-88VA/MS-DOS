; SPDX-License-Identifier: MIT
; Preflight ownership. Count a reference for each FAT link and each live
; directory head, including files in reachable subdirectories. An old
; chain can be reclaimed only if each of its clusters has one reference.
RF_MAP  EQU     320
RFFATSEG DW     0
RFMIRROR DW     0
RFMLINK DW      0
RFSECTOR DW     0
RFBASE  DW      0
RFVDIR  DW      0
RFVCL   DW      0
RFVLEFT DW      0
RFVSEC  DW      0
RFVLBA  DW      0

RFAUDIT:
        MOV     ES,[RFSEG]
        MOV     DI,RF_MAP
        MOV     CX,[D5CLMAX]
        INC     CX
        XOR     AX,AX
        REP     STOSB
        MOV     [RFSECTOR],1
        MOV     [RFBASE],0
RFLOADFAT:
        MOV     AX,[RFSECTOR]
        MOV     BP,[RFBASE]
        MOV     ES,[RFFATSEG]
        CALL    READSEC
        D5CF    RFERROR
        ADD     AX,[D5SPF]
        MOV     ES,[HDSTAGE]
        CALL    READSEC
        D5CF    RFERROR
        ADD     [RFBASE],1024
        INC     [RFSECTOR]
        MOV     AX,[RFSECTOR]
        CMP     AX,[D5SPF]
        JBE     RFLOADFAT
        MOV     BX,2
RFCOUNT:
        MOV     ES,[RFFATSEG]
        CALL    RFGET
        MOV     AX,DX
        MOV     ES,[HDSTAGE]
        CALL    RFGET
        CMP     AX,DX
        JE      RFCOUNTLINK
        ; Recognize only the exact footprint of one interrupted paired
        ; write (a claim or release of an unreachable, unsplit entry).
        CMP     [RFMIRROR],0
        D5NZ    RFERROR
        TEST    AX,AX
        JZ      RFCOUNTDIFF
        TEST    DX,DX
        D5NZ    RFERROR
RFCOUNTDIFF:
        MOV     [RFMIRROR],BX
        MOV     [RFMLINK],AX
        MOV     AX,BX
        CALL    D5JRCLVALID
        D5CF    RFERROR
        MOV     AX,[RFMLINK]
        CALL    RFCHANGE        ;Normalize FAT2 in RAM for full comparison.
RFCOUNTLINK:
        MOV     SI,AX
        CALL    RFREF
        INC     BX
        CMP     BX,[D5CLMAX]
        JBE     RFCOUNT
        MOV     ES,[HDSTAGE]
        PUSH    DS
        MOV     DS,[RFFATSEG]
        XOR     SI,SI
        XOR     DI,DI
        MOV     CX,CS:[RFBASE]
        SHR     CX,1
        REPE    CMPSW
        POP     DS
        D5NZ    RFERROR
        MOV     AX,[ROOT]
RFROOTSCAN:
        CALL    RFSCANSEC
        D5CF    RFERROR
        JZ      RFDIRSCAN
        INC     AX
        CMP     AX,[DATA0]
        JB      RFROOTSCAN
RFDIRSCAN:
        MOV     [RFVDIR],2
RFDIRNEXT:
        MOV     ES,[RFSEG]
        MOV     SI,[RFVDIR]
        TEST    BYTE PTR ES:[SI+RF_MAP],80H
        JZ      RFDIRADVANCE
        TEST    BYTE PTR ES:[SI+RF_MAP],40H
        JNZ     RFDIRADVANCE
        OR      BYTE PTR ES:[SI+RF_MAP],40H
        MOV     [RFVCL],SI
        MOV     AX,[D5CLMAX]
        MOV     [RFVLEFT],AX
RFDIRCL:
        MOV     AX,[RFVCL]
        CALL    D5JRLBA
        MOV     [RFVLBA],AX
        MOV     AX,[D5SPC]
        MOV     [RFVSEC],AX
RFDIRSEC:
        MOV     AX,[RFVLBA]
        CALL    RFSCANSEC
        D5CF    RFERROR
        JZ      RFDIRSCAN       ;Another directory may now be known.
        INC     [RFVLBA]
        DEC     [RFVSEC]
        JNZ     RFDIRSEC
        MOV     ES,[RFFATSEG]
        MOV     BX,[RFVCL]
        CALL    RFGET
        CMP     DX,0FF8H
        JAE     RFDIRSCAN
        CMP     DX,2
        D5CF    RFERROR
        CMP     DX,[D5CLMAX]
        JBE     RFDIRLINK
        JMP     RFERROR
RFDIRLINK:
        MOV     [RFVCL],DX
        DEC     [RFVLEFT]
        D5Z     RFERROR
        JMP     SHORT RFDIRCL
RFDIRADVANCE:
        INC     [RFVDIR]
        MOV     AX,[RFVDIR]
        CMP     AX,[D5CLMAX]
        JA      RFDIRFINISH
        JMP     RFDIRNEXT
RFDIRFINISH:
        MOV     SI,[RFMIRROR]
        OR      SI,SI
        JZ      RFVGOOD
        CMP     BYTE PTR ES:[SI+RF_MAP],0
        D5NZ    RFERROR
        ; If FAT1 advanced a claim, its suffix must itself be an
        ; allocated, private lost chain. Never mirror a link into a
        ; live or already shared chain.
        MOV     SI,[RFMLINK]
        OR      SI,SI
        JZ      RFVGOOD
RFMSUFFIX:
        CMP     SI,0FF8H
        JAE     RFVGOOD
        CMP     SI,2
        D5CF    RFERROR
        CMP     SI,[D5CLMAX]
        JBE     RFMSLINK
        JMP     RFERROR
RFMSLINK:
        MOV     ES,[RFSEG]
        CMP     BYTE PTR ES:[SI+RF_MAP],1
        D5NZ    RFERROR
        MOV     BX,SI
        MOV     ES,[RFFATSEG]
        CALL    RFGET
        MOV     SI,DX
        JMP     SHORT RFMSUFFIX
RFVGOOD:CLC
        RET

; Scan a logical root/subdirectory sector. ZF marks the DOS terminator.
RFSCANSEC:
        MOV     ES,[BMBUFSEG]
        XOR     BP,BP
        CALL    READSEC
        JC      RFVRET
        XOR     DI,DI
RFSCANENT:
        CMP     BYTE PTR ES:[DI],0
        JE      RFVRET
        CMP     BYTE PTR ES:[DI],0E5H
        JE      RFSCANADV
        TEST    BYTE PTR ES:[DI+11],8
        JNZ     RFSCANADV
        CMP     BYTE PTR ES:[DI],'.'
        JE      RFSCANADV
        MOV     SI,ES:[DI+26]
        PUSH    ES
        MOV     DL,ES:[DI+11]
        CALL    RFREF
        TEST    DL,10H
        JZ      RFSCANPOP
        CMP     SI,2
        JB      RFSCANDIRERR
        CMP     SI,[D5CLMAX]
        JA      RFSCANDIRERR
        OR      BYTE PTR ES:[SI+RF_MAP],80H
RFSCANPOP:
        POP     ES
RFSCANADV:
        ADD     DI,32
        CMP     DI,1024
        JB      RFSCANENT
        OR      DI,DI           ;ZF clear.
RFVRET: RET
RFSCANDIRERR:
        POP     ES
        STC
        RET

RFREF:  MOV     ES,[RFSEG]
        CMP     SI,2
        JB      RFREFRET
        CMP     SI,[D5CLMAX]
        JA      RFREFRET
        MOV     DH,ES:[SI+RF_MAP]
        AND     DH,3FH
        CMP     DH,3FH
        JE      RFREFRET
        INC     BYTE PTR ES:[SI+RF_MAP]
RFREFRET:RET

; ES = resident FAT copy, BX = cluster; DX = entry, DI = byte offset.
RFGET:  MOV     DI,BX
        SHR     DI,1
        ADD     DI,BX
        MOV     DX,ES:[DI]
        TEST    BL,1
        JZ      RFGETMASK
        MOV     CL,4
        SHR     DX,CL
RFGETMASK:
        AND     DX,0FFFH
        RET

; Substitute entry AX at byte offset for cluster BX in the RAM copy ES.
RFCHANGE:
        CALL    RFGET
        MOV     DX,AX
        TEST    BL,1
        JNZ     RFCHANGEODD
        AND     WORD PTR ES:[DI],0F000H
        JMP     SHORT RFCHANGESTORE
RFCHANGEODD:
        MOV     CL,4
        SHL     DX,CL
        AND     WORD PTR ES:[DI],000FH
RFCHANGESTORE:
        OR      ES:[DI],DX
        RET
