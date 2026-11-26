; SPDX-License-Identifier: MIT
; Startup files are mutable. Discover by name before a transaction and
; bind to their slots and metadata only until that transaction commits.
; FF in a participant ID means there is no such side (standalone capture).
PSIDS   DW      0               ;Outgoing ID, incoming ID.
PSMODE  DB      0               ;0 preflight/replay, 1 snapshot.
PSSTART DB      0               ;One or more startup renames completed.
PSIDX   DW      0               ;0/2 for CONFIG/AUTOEXEC, then 4/6 on activate.
PSSIDE  DB      0               ;0 outgoing, 1 incoming.
PSREAL  DW      0
PSRCRC  DW      0
PSDONE  DB      8 DUP (0)       ;Even bytes: 0 absent, 1 pending, 2 done.
PSNAMES DB      'CONFIG  SYS','AUTOEXECBAT'
PSCNAME DB      'VACFG0  SYS'
PSANAME DB      'VAEXEC0 BAT'

; AL=id, BX=0/2 (file). Return SI=park name. Only AX and SI clobbered.
PSNAME: ADD     AL,'0'
        MOV     SI,OFFSET PSCNAME
        CMP     BX,0
        JNE     PSNBAT
        MOV     [SI+5],AL
        RET
PSNBAT: MOV     SI,OFFSET PSANAME
        MOV     [SI+6],AL
        RET
PSROOT: MOV     SI,OFFSET PSNAMES
        TEST    BX,2
        JZ      PSNRET
        ADD     SI,11
PSNRET: RET

; AX=outgoing/incoming IDs. PSPLAN records a fresh snapshot; PSCHECK
; accepts exactly a prefix of the park-then-activate sequence.
PSPLAN: MOV     [PSMODE],1
        JMP     SHORT PSINIT
PSCHECK:MOV     [PSMODE],0
PSINIT: MOV     [PSIDS],AX
        MOV     [PSIDX],0
PSFILE: MOV     BX,[PSIDX]
        CALL    PSROOT
        CALL    PSFIND
        JC      PSBAD
        MOV     [PSREAL],AX
        MOV     [PSRCRC],DX
        MOV     [PSSIDE],0
        CALL    PSSCAN
        JC      PSBAD
        ADD     [PSIDX],4
        MOV     [PSSIDE],1
        CALL    PSSCAN
        JC      PSBAD
        CMP     [PSMODE],0
        JNE     PSNEXT
        CMP     [PSREAL],0FFFFH
        JNE     PSBAD
PSNEXT: SUB     [PSIDX],2
        CMP     [PSIDX],4
        JB      PSFILE
        CMP     [PSMODE],0
        JNE     PSOK
        XOR     BX,BX
        XOR     AL,AL
        MOV     [PSSTART],AL
PSORDER:MOV     AH,[PSDONE+BX]
        CMP     AH,2
        JA      PSBAD
        JE      PSLATE
        OR      AL,AH
        JMP     SHORT PSORDNEXT
PSLATE: OR      AL,AL
        JNZ     PSBAD
        MOV     [PSSTART],1
PSORDNEXT:ADD   BX,2
        CMP     BX,8
        JB      PSORDER
PSOK:   CLC
        RET
PSBAD:  STC
        RET

; Check one side of the current file. A real name must be consumed by
; exactly one recorded slot. An unrecorded parked name is a collision.
PSSCAN: XOR     BH,BH
        MOV     BL,[PSSIDE]
        MOV     AX,0FFFFH
        XOR     DX,DX
        CMP     BYTE PTR [PSIDS+BX],0FFH
        JNE     PSHAVEID
        JMP     PSABSENT
PSHAVEID:MOV    AL,BYTE PTR [PSIDS+BX]
        MOV     BX,[PSIDX]
        AND     BX,2
        CALL    PSNAME
        CALL    PSFIND
        JC      PSBAD
PSFOUND:MOV     BX,[PSIDX]
        MOV     DI,BX
        SHL     DI,1
        CMP     [PSMODE],0
        JE      PSCMP
        CMP     [PSSIDE],0
        JNE     PSSTORE
        CMP     AX,0FFFFH
        JNE     PSBAD           ;Never overwrite an outgoing park name.
        MOV     AX,[PSREAL]
        MOV     DX,[PSRCRC]
PSSTORE:MOV     ES:[DI+ST_PAIR],AX
        MOV     ES:[DI+ST_PAIR+2],DX
        CLC
        RET
PSCMP:  MOV     BYTE PTR [PSDONE+BX],0
        CMP     AX,0FFFFH
        JE      PSNOTPARK
        CMP     AX,ES:[DI+ST_PAIR]
        JNE     PSBAD
        MOV     AL,2            ;Outgoing parked: done.
        SUB     AL,[PSSIDE]     ;Incoming parked: pending.
        JMP     SHORT PSVERIFY
PSNOTPARK:
        MOV     AX,ES:[DI+ST_PAIR]
        CMP     AX,0FFFFH
        JE      PSOK
        CMP     AX,[PSREAL]
        JNE     PSBAD
        MOV     [PSREAL],0FFFFH
        MOV     DX,[PSRCRC]
        MOV     AL,1
        ADD     AL,[PSSIDE]
PSVERIFY:CMP    DX,ES:[DI+ST_PAIR+2]
        JNE     PSINVALID
        MOV     [PSDONE+BX],AL
PSVALID:CLC
        RET
PSINVALID:STC
        RET

PSABSENT:
        MOV     BX,[PSIDX]
        MOV     DI,BX
        SHL     DI,1
        CMP     [PSMODE],0
        JNE     PSSTORE
        MOV     BYTE PTR [PSDONE+BX],0
        CMP     AX,ES:[DI+ST_PAIR]
        JE      PSVALID
        JMP     SHORT PSINVALID

; FIND allows name collisions with non-files so they can be rejected.
; Ignore only the hidden bit in the fingerprint (the rename changes it).
PSFIND: CALL    FIND
        JC      PSINVALID
        XOR     DX,DX
        CMP     AX,0FFFFH
        JE      PSVALID
        TEST    BYTE PTR [MATCH+11],0D8H
        JNZ     PSINVALID
        AND     BYTE PTR [MATCH+11],0FDH
        PUSH    AX
        MOV     SI,OFFSET MATCH+11
        MOV     CX,21
        CALL    CRC16
        POP     AX
        CLC
        RET

; Preflight has checked both sides before any write. Rewrite only names
; and the hidden bit, one physical root block at a time.
PSAPPLY:XOR     BX,BX
PSWRITE:CMP     BYTE PTR [PSDONE+BX],1
        JNE     PSWNEXT
        MOV     [PSIDX],BX
        MOV     DI,BX
        SHL     DI,1
        MOV     AX,ES:[DI+ST_PAIR]
        PUSH    ES
        CALL    GETSLOT
        JC      PSWRET
        MOV     BX,[PSIDX]
        TEST    BX,4
        JNZ     PSWREAL
        PUSH    AX
        MOV     AL,BYTE PTR [PSIDS]
        AND     BX,2
        CALL    PSNAME
        POP     AX
        OR      BYTE PTR ES:[DI+11],2
        JMP     SHORT PSWCOPY
PSWREAL:CALL    PSROOT
        AND     BYTE PTR ES:[DI+11],0FDH
PSWCOPY:PUSH    DI
        MOV     CX,11
        REP     MOVSB
        POP     DI
        CALL    PUTSLOT
PSWRET: POP     ES
        JC      PSWEND
        MOV     BX,[PSIDX]
PSWNEXT:ADD     BX,2
        CMP     BX,8
        JB      PSWRITE
        CLC
PSWEND: RET

PSOWNERS:
        MOV     AL,ES:[ST_OWNER]
        MOV     AH,ES:[ST_NEXT]
        RET

; PC-Engine standalone capture only parks its pair. Prepared capture
; leaves the real DOS startup files untouched (stock SYS adds neither).
PSCAPIDS:MOV    AL,ES:[ST_NEXT]
        MOV     AH,0FFH
        RET
