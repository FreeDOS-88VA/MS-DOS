; SPDX-License-Identifier: MIT
; Validate all names, recorded slots, metadata and chains before writing.
; In phase 1 only a prefix of the park/activate sequence may be done.
; CAPSKIP != 0 checks just the old parked sets during foreign capture.
CHECKFILES:
        MOV     [PARKED],0
        MOV     [ACTIVE],0
        MOV     [FILEID],0
CFILE:  MOV     [UNUSEDREAL],0FFFFH
        CMP     [CAPSKIP],0
        JNE     CINIT
        CALL    NAMES
        MOV     SI,[REALPTR]
        CALL    FIND
        JC      CFERR
        MOV     [UNUSEDREAL],AX
CINIT:  MOV     [SETID],1
        JMP     SHORT CSET
CFERR:  STC
        RET
CSET:   MOV     BL,[SETID]
        CMP     BL,[CAPSKIP]
        JNE     CLABEL
        JMP     CNEXT
CLABEL:
        CALL    LABELPTR
        CMP     BYTE PTR ES:[DI],0
        JE      CNEXT
        CALL    NAMES
        CALL    FIND
        JC      CFERR
        MOV     BL,[SETID]
        CMP     BYTE PTR ES:[ST_PHASE],1
        JNE     CCLEAN
        CMP     BL,ES:[ST_OWNER]
        JE      COWNER
        CMP     BL,ES:[ST_NEXT]
        JNE     CPARK
        CMP     AX,0FFFFH
        JNE     CPARK
        MOV     DL,[ACTIVE]
        CMP     DL,[FILEID]
        JNE     CFERR
        INC     [ACTIVE]
        JMP     SHORT CREAL
COWNER: CMP     AX,0FFFFH
        JE      CREAL
        MOV     DL,[PARKED]
        CMP     DL,[FILEID]
        JNE     CFERR
        INC     [PARKED]
        JMP     SHORT CPARK
CCLEAN: CMP     BL,ES:[ST_OWNER]
        JNE     CPARK
        CMP     AX,0FFFFH
        JNE     CFERR
CREAL:  MOV     SI,[REALPTR]
        CALL    FIND
        JC      CFERR
        CMP     AX,[UNUSEDREAL]
        JNE     CFERR
        MOV     [UNUSEDREAL],0FFFFH
        JMP     SHORT CRECORD
CPARK:  OR      [ATTR],2
CRECORD:CALL    CHECKRECORD
        JC      CHECKBAD
CNEXT:  INC     [SETID]
        CMP     [SETID],MAXID
        JA      CNAMEDONE
        JMP     CSET
CNAMEDONE:
        CMP     [UNUSEDREAL],0FFFFH
        JNE     CHECKBAD
        INC     [FILEID]
        CMP     [FILEID],4
        JAE     CFEND
        JMP     CFILE
CFEND:  CMP     [ACTIVE],0
        JE      CFOK
        CMP     BYTE PTR ES:[ST_OWNER],0
        JE      CFOK
        CMP     [PARKED],4
        JNE     CHECKBAD
CFOK:   CLC
        RET
CHECKBAD:STC
        RET

CHECKRECORD:
        CMP     AX,0FFFFH
        JE      CHECKBAD
        MOV     DL,[ATTR]
        CMP     DL,[MATCH+11]
        JNE     CHECKBAD
        PUSH    AX
        CALL    FILEREC
        POP     AX
        CMP     AX,ES:[DI]
        JNE     CHECKBAD
        MOV     SI,OFFSET MATCH+12
        MOV     CX,20
        CALL    CRC16
        CMP     DX,ES:[DI+2]
        JNE     CHECKBAD

; Count exactly ceil(size / bytes_per_cluster) links. A repeated
; cluster cannot end at EOC, so the count bounds cycles as well.
CHECKCHAIN:
        MOV     AX,WORD PTR [MATCH+28]
        MOV     DX,WORD PTR [MATCH+30]
        MOV     BX,AX
        OR      BX,DX
        JZ      CHECKBAD
        SUB     AX,1
        SBB     DX,0
        CMP     DX,[BMCLBYTES]
        JAE     CHECKBAD
        DIV     [BMCLBYTES]
        CMP     AX,[D5CLMAX]
        JAE     CHECKBAD
        INC     AX
        PUSH    ES
        PUSH    DI
        MOV     CX,AX
        MOV     BX,WORD PTR [MATCH+26]
CHAINLOOP:
        CMP     BX,2
        JB      CHAINERR
        CMP     BX,[D5CLMAX]
        JA      CHAINERR
        PUSH    CX
        XOR     AX,AX           ;First FAT.
        CALL    BMFATGET
        POP     CX
        JC      CHAINEND
        MOV     BX,DX
        LOOP    CHAINLOOP
        CMP     DX,0FF8H
        JMP     SHORT CHAINEND
CHAINERR:STC
CHAINEND:POP    DI
        POP     ES
        RET

; BX cluster, AX FAT-relative base (0 or SPF); DX receives FAT12 link.
BMFATGET:
        MOV     DI,BX
        SHR     DI,1
        ADD     DI,BX
        PUSH    BX
        MOV     BX,DI
        MOV     CL,10
        SHR     BX,CL
        ADD     AX,BX
        POP     BX
        INC     AX
        AND     DI,1023
        MOV     ES,[BMBUFSEG]
        XOR     BP,BP
        CALL    READSEC
        JC      FATRET
        MOV     DL,ES:[DI]
        INC     DI
        CMP     DI,1024
        JB      FATHIGH
        INC     AX
        CALL    READSEC
        JC      FATRET
        XOR     DI,DI
FATHIGH:MOV     DH,ES:[DI]
        TEST    BL,1
        JZ      FATMASK
        MOV     CL,4
        SHR     DX,CL
FATMASK:AND     DX,0FFFH
FATRET: RET

BMGEOMETRY:
        MOV     BX,OFFSET D5GEOM
        MOV     AX,[DATA0]
BMGEOM1:CMP     AX,[BX+4]
        JE      BMGEOM2
        ADD     BX,10
        CMP     BX,OFFSET GEOMEND
        JB      BMGEOM1
        STC
        RET
BMGEOM2:MOV     AX,[BX+6]
        MOV     [D5CLMAX],AX
        MOV     AX,[BX+8]
        MOV     CL,10
        SHL     AX,CL
        MOV     [BMCLBYTES],AX
        CLC
        RET

CAPSKIP DB      0
PARKED  DB      0
ACTIVE  DB      0
UNUSEDREAL DW   0
D5CLMAX DW      0
BMCLBYTES DW    0
D5GEOM  DW      1,3,22,617,8
        DW      2,5,36,1234,8
        DW      4,9,56,2469,8
        DW      4,9,105,2469,16
GEOMEND LABEL   WORD
