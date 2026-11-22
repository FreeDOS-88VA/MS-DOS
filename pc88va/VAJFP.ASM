; JFP.COM for MS-DOS/VA. Run only as a foreground DOS command.
; ResJFP can open DOS files; neither VAIO's CON path nor INT DC calls it.
CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     100H

START:  MOV     AX,[2]          ;PSP end segment (exclusive).
        MOV     BX,CS
        SUB     AX,BX
        CMP     AX,COMPARAS
        JAE     STARTOK
        MOV     DX,OFFSET UPLOADMSG
        JMP     FAIL
STARTOK:MOV     SP,OFFSET STACKTOP
        CLD
        MOV     SI,81H
        XOR     CX,CX
        MOV     CL,BYTE PTR DS:[80H]
SKIP:   JCXZ    USAGE_NEAR
        LODSB
        DEC     CX
        CMP     AL,' '
        JE      SKIP
        CMP     AL,9
        JE      SKIP
        DEC     SI
        INC     CX
        XOR     DI,DI
PARSE:  LODSB
        CMP     AL,' '
        JE      TAIL
        CMP     AL,9
        JE      TAIL
        CMP     DI,4
        JAE     USAGE_NEAR
        AND     AL,0DFH
        MOV     [ARG+DI],AL
        INC     DI
        LOOP    PARSE
        JMP     SHORT COMMAND
TAIL:   DEC     CX
COMMAND:CMP     DI,3
        JNE     TAIL1
        CMP     WORD PTR [ARG],'DA'
        JNE     NOTADD
        CMP     [ARG+2],'D'
        JNE     TAIL1
        JMP     ADDWORD
NOTADD: CMP     WORD PTR [ARG],'ED'
        JNE     TAIL1
        CMP     [ARG+2],'L'
        JNE     TAIL1
        JMP     DELWORD
TAIL1:  JCXZ    SELECT
        LODSB
        CMP     AL,' '
        JE      TAILNEXT
        CMP     AL,9
        JNE     USAGE_NEAR
TAILNEXT: LOOP  TAIL1
SELECT: CMP     DI,4
        JNE     MODEON
        CMP     WORD PTR [ARG],'IL'
        JNE     USAGE_NEAR
        CMP     WORD PTR [ARG+2],'TS'
        JNE     USAGE_NEAR
        JMP     LISTWORDS
USAGE_NEAR:JMP  USAGE
MODEON: CMP     WORD PTR [ARG],'NO'
        JNE     NOTON
        CMP     DI,2
        JE      PROJECT         ;ON is the project FEP, like explicit FEP.
NOTON:  CMP     WORD PTR [ARG],'OR'
        JNE     NOTROM
        CMP     [ARG+2],'M'
        JNE     USAGE
        MOV     [ROMOK],1
        JMP     SHORT ENABLE
NOTROM: CMP     WORD PTR [ARG],'EF'
        JNE     NOTFEP
        CMP     [ARG+2],'P'
        JE      PROJECT
NOTFEP: CMP     WORD PTR [ARG],'FO'
        JNE     USAGE
        CMP     [ARG+2],'F'
        JE      DISABLE
USAGE:  MOV     DX,OFFSET HELPMSG
        JMP     FAIL

PROJECT:MOV     [HEADLESS],1
        JMP     SHORT ENABLE
DISABLE:
        CALL    SETUPIO
        CALL    QUERY
        OR      BX,BX
        JZ      DISABLED
        CMP     BX,1
        JNE     RELEASE
        CALL    ROMOFF
RELEASE:MOV     BX,3
        CALL    VAIO
        CALL    FREEBLOCK
        JNC     DISABLED
        JMP     FEPUPLOADERR
DISABLED:
        MOV     DX,OFFSET OFFMSG
        JMP     SUCCESS

ENABLE: CALL    QUERY
        OR      BX,BX
        JNZ     CHECKMODE
        JMP     RESERVE
CHECKMODE:CMP   [HEADLESS],0
        JE      CHECKROM
        CMP     BX,3
        JNE     BUSY
        JMP     FEPENABLED
CHECKROM:CMP    BX,1
        JNE     BUSY
        JMP     ENABLED
BUSY:   MOV     DX,OFFSET BUSYMSG
        JMP     FAIL
FEPENABLED:
        CALL    SETUPIO
        CALL    LOADDICT
        JNC     FEPLOADOK
        MOV     AH,9            ;Warn, then replace any old table with empty.
        INT     21H
        MOV     [DICTEND],OFFSET RECORDS
FEPLOADOK:
        XOR     DI,DI           ;Try reuse (or detach for an empty table).
        CALL    INSTALLDICT
        CMP     AX,554AH
        JE      FEPFREEOLD
        CMP     AX,4E4AH        ;Larger block needed, old table untouched.
        JNE     FEPUPLOADERR
        PUSH    DS
        POP     ES
        MOV     BX,COMPARAS
        MOV     AH,4AH          ;Return unused COM arena before allocating.
        INT     21H
        JC      FEPUPLOADERR
        CALL    ALLOCBLOCK
        JC      FEPUPLOADERR
        PUSH    AX
        MOV     DI,AX
        DEC     AX
        MOV     ES,AX
        MOV     WORD PTR ES:[1],8 ;DOS system owner, not our transient PSP.
        CALL    INSTALLDICT
        POP     DX
        CMP     AX,554AH
        JE      FEPFREEOLD
        MOV     BX,DX           ;New block was never published.
        CALL    FREEBLOCK
FEPUPLOADERR:
        MOV     DX,OFFSET UPLOADMSG
        JMP     FAIL
FEPFREEOLD:
        CALL    FREEBLOCK
        JC      FEPUPLOADERR
FEPMESSAGE:
        MOV     DX,OFFSET FEPMSG
        JMP     SUCCESS
RESERVE:CALL    SETUPIO
        MOV     BX,1
        CALL    VAIO
        CMP     BX,2
        JE      INITROM
        MOV     DX,OFFSET INITMSG
        JMP     FAIL
INITROM:
        ; ResJFP has no returned error status. Observe the results of its
        ; documented default-file opens, with the old DOS vector chained.
        MOV     AX,3521H
        INT     21H
        MOV     WORD PTR [OLD21],BX
        MOV     WORD PTR [OLD21+2],ES
        MOV     DX,OFFSET OPENHOOK
        MOV     AX,2521H
        INT     21H
        MOV     CX,2            ;ResJFP (may call DOS on this program's stack).
        CALL    INTJFP
        LDS     DX,[OLD21]
        MOV     AX,2521H
        INT     21H
        PUSH    CS
        POP     DS
        ; KyBook: verify the documented keyboard-side link before KbFlsh
        ; or asking CON to use any main keyboard function.
        MOV     AH,0EH
        CALL    INTKB
        MOV     BX,DX
        MOV     AX,ES:[BX+01DEH]
        OR      AX,ES:[BX+01E0H]
        JNZ     INITLINK
        JMP     INITERR
INITLINK:CMP    [OPENERR],0
        JNE     BADFILES
        CMP     [HEADLESS],0
        JE      CHECKFILES
        ; FEP only qualifies conversion with the built-in dictionary.
        ; Require the two documented default-file attempts to have failed
        ; with missing-file errors; reject external dictionaries/gaiji.
        CMP     [OPENED],0
        JNE     FEPFILES
        CMP     [MISSING],2
        JNE     FEPFILES
        CALL    ROMOFF         ;KbFlsh + SetJFP, master disabled.
        XOR     CX,CX
        CALL    INTJFP          ;GetJFP
        CMP     AX,8F80H
        JNE     ROMERR
        MOV     BX,4
        CALL    VAIO
        CMP     BX,3
        JNE     ROMERR
        JMP     FEPENABLED
CHECKFILES:
        CMP     [MISSING],0
        JE      INITSET
        CMP     [ROMOK],0
        JE      BADFILES
INITSET:CALL    FLUSHKB
        MOV     AX,0F00H        ;Half-width alpha; ZENKAKU enters indirect kana.
        CALL    SETMODE         ;Disallow pop-ups, dictionary edit and gaiji.
        XOR     CX,CX
        CALL    INTJFP          ;GetJFP: check SetJFP took effect.
        CMP     AX,0F00H
        JNE     ROMERR
        MOV     AX,0201H        ;Expansion off (VAIO owns the key strings).
        CALL    INTKB
        MOV     BX,2
        CALL    VAIO
        CMP     BX,1
        JNE     ROMERR
        CMP     [MISSING],0
        JE      ENABLED
        MOV     DX,OFFSET ROMMSG
        JMP     SUCCESS
ENABLED:MOV     DX,OFFSET ONMSG
        JMP     SUCCESS
FEPFILES:
        CALL    ROMOFF
        MOV     DX,OFFSET FEPFILEMSG
        JMP     SHORT ROLLBACK
BADFILES:
        CALL    ROMOFF
        MOV     DX,OFFSET FILEMSG
        JMP     SHORT ROLLBACK
ROMERR: CALL    ROMOFF
INITERR:MOV     DX,OFFSET INITMSG
ROLLBACK:
        MOV     BX,3
        CALL    VAIO
        JMP     FAIL

INSTALLDICT:
        MOV     SI,OFFSET RECORDS
        MOV     DX,[DICTEND]
        SUB     DX,SI
        PUSH    DS
        POP     ES
        MOV     BX,5
        JMP     SHORT VAIO
ALLOCBLOCK:
        ; Place the long-lived block high, not directly after our COM.
        ; First fit there would strand the COM's arena below the table.
        MOV     AX,5800H        ;Get allocation strategy.
        INT     21H
        JC      ALOCRET
        PUSH    AX
        MOV     AX,5801H
        MOV     BX,2            ;Last fit, split from the high end.
        INT     21H
        JC      ALOCSETERR
        MOV     BX,[DICTEND]
        SUB     BX,OFFSET RECORDS-15
        MOV     CL,4
        SHR     BX,CL
        MOV     AH,48H
        INT     21H
        POP     BX              ;Original strategy. Preserve allocation result.
        PUSHF
        PUSH    AX
        MOV     AX,5801H
        INT     21H
        POP     AX
        POPF
ALOCRET:RET
ALOCSETERR:
        POP     AX
        STC
        RET
FREEBLOCK:
        OR      BX,BX           ;Also clears carry on the no-block path.
        JZ      FREEEND
        MOV     ES,BX
        MOV     AH,49H
        INT     21H
FREEEND:RET

QUERY:  XOR     BX,BX
        CALL    VAIO
        CMP     AX,474AH
        JE      QUERYOK
        MOV     DX,OFFSET NODRV
        JMP     FAIL
QUERYOK:RET
VAIO:   MOV     AX,4A47H
        MOV     CL,0F0H
        INT     0DCH
        RET

ROMOFF: CALL    FLUSHKB
        MOV     AX,8F80H        ;Master off; plain CON bypasses the ROM JFP.
SETMODE:MOV     DX,3C1EH
        MOV     CX,1
INTJFP: PUSH    DS
        INT     8DH
        POP     DS
        CLD
        RET
FLUSHKB:MOV     AX,0400H
INTKB:  PUSH    DS
        INT     82H
        POP     DS
        CLD
        RET

SETUPIO:
        ; Never abort while a DOS hook or a staged dictionary save is live.
        ; DOS restores INT 23h/24h from our PSP at process exit.
        MOV     DX,OFFSET KEEPGOING
        MOV     AX,2523H
        INT     21H
        MOV     DX,OFFSET FAILIO
        MOV     AX,2524H
        INT     21H
        RET

KEEPGOING:
        IRET                    ;Ignore DOS break during command startup.
FAILIO: MOV     AL,3            ;INT 24h: Fail, never Abort while hooked.
        IRET

; Observe AH=3Dh only during ResJFP. Preserve DOS's AX and carry, and
; leave the original caller's interrupt/direction flags in its frame.
OPENHOOK PROC   FAR
        PUSHF
        CMP     AH,3DH
        JE      OPENFILE
        POPF
        JMP     DWORD PTR CS:[OLD21]
OPENFILE:
        POPF
        PUSHF
        CALL    DWORD PTR CS:[OLD21]
        PUSH    BP
        MOV     BP,SP
        JNC     OPENOK
        OR      WORD PTR [BP+6],1
        CMP     AX,2            ;File not found.
        JE      OPENMISS
        CMP     AX,3            ;Path not found.
        JE      OPENMISS
        MOV     CS:[OPENERR],1
        JMP     SHORT OPENRET
OPENMISS:
        INC     CS:[MISSING]
        JMP     SHORT OPENRET
OPENOK: INC     CS:[OPENED]
        AND     WORD PTR [BP+6],0FFFEH
OPENRET:POP     BP
        IRET
OPENHOOK ENDP

; Project user dictionary. All of these entry points are foreground only.
        INCLUDE VAUDICT.INC

ADDWORD:
DELWORD:MOV     DI,OFFSET PAIR+2
        CALL    TOKEN
        MOV     [PAIR],AL
        CALL    TOKEN
        MOV     [PAIR+1],AL
        MOV     AX,DI
        SUB     AX,OFFSET PAIR-1
        MOV     [DI],AL
        CALL    SKIPSPACE
        JNC     BADPAIR
        MOV     SI,OFFSET PAIR
        CALL    VALIDPAIR
        JC      BADPAIR
        CALL    DICTOPEN
        MOV     BX,OFFSET PAIR
        CALL    FINDPAIR
        CMP     [ARG],'A'
        JNE     REMOVEWORD
        CMP     DI,[DICTEND]
        JNE     DUPWORD
        CMP     [DICTCOUNT],UDLIMIT
        JAE     FULLDICT
        MOV     SI,BX
        CALL    PAIRSIZE
        REP     MOVSB
        MOV     [DICTEND],DI
        JMP     SHORT SAVEWORD
REMOVEWORD:
        CMP     DI,[DICTEND]
        JE      NOWORD
        MOV     SI,DI
        CALL    PAIRSIZE
        ADD     SI,CX
        MOV     CX,[DICTEND]
        SUB     CX,SI
        REP     MOVSB
        MOV     [DICTEND],DI
SAVEWORD:CALL   SAVEDICT
        JNC     SAVEDWORD
        JMP     FAIL
SAVEDWORD:MOV   DX,OFFSET SAVEDMSG
        JMP     SUCCESS
DUPWORD:MOV     DX,OFFSET DUPMSG
        JMP     FAIL
FULLDICT:MOV    DX,OFFSET FULLMSG
        JMP     FAIL
NOWORD: MOV     DX,OFFSET NOMATCHMSG
        JMP     FAIL
BADPAIR:MOV     DX,OFFSET PAIRMSG
        JMP     FAIL

; Read at most CX bytes from the PSP tail. Leave SI/CX at the separator.
TOKEN:  CALL    SKIPSPACE
        JC      BADPAIR
        XOR     AX,AX
TOKEN1: MOV     DL,[SI]
        CMP     DL,' '
        JE      TOKENEND
        CMP     DL,9
        JE      TOKENEND
        CMP     AL,UDFIELD
        JAE     BADPAIR
        MOV     [DI],DL
        INC     DI
        INC     SI
        INC     AL
        LOOP    TOKEN1
TOKENEND:RET
SKIPSPACE:
        JCXZ    SPACEEOF
        CMP     BYTE PTR [SI],' '
        JE      SPACE1
        CMP     BYTE PTR [SI],9
        JE      SPACE1
        CLC
        RET
SPACE1: INC     SI
        DEC     CX
        JMP     SHORT SKIPSPACE
SPACEEOF:STC
        RET

LISTWORDS:
        CALL    DICTOPEN
        MOV     SI,OFFSET RECORDS
        CMP     SI,[DICTEND]
        JE      LISTEMPTY
LISTNEXT:XOR    CX,CX
        MOV     CL,[SI]
        LEA     DX,[SI+2]
        CALL    STDOUT
        MOV     DX,OFFSET LISTSEP
        MOV     CX,3
        CALL    STDOUT
        XOR     DX,DX
        MOV     DL,[SI]
        ADD     DX,SI
        ADD     DX,2
        MOV     CL,[SI+1]
        CALL    STDOUT
        MOV     DX,OFFSET LISTCR
        MOV     CX,2
        CALL    STDOUT
        CALL    PAIRSIZE
        ADD     SI,CX
        CMP     SI,[DICTEND]
        JB      LISTNEXT
        MOV     AX,4C00H
        INT     21H
LISTEMPTY:MOV   DX,OFFSET EMPTYMSG
        JMP     SUCCESS
STDOUT: MOV     BX,1
        MOV     AH,40H          ;Counted output, no string terminator.
        INT     21H
        JC      DICTERROR
        CMP     AX,CX
        JNE     DICTERROR
        RET

DICTOPEN:CALL   SETUPIO
        CALL    LOADDICT
        JNC     DICTOPENOK
        JMP     FAIL
DICTOPENOK:RET
DICTERROR:MOV   DX,OFFSET IOMSG
        JMP     FAIL

; Return CF + message on failure. Missing file is an empty table.
LDIOERR:MOV     DX,OFFSET IOMSG
        STC
        RET
LOADDICT:
        PUSH    DS
        POP     ES
        CLD
        MOV     [HADFILE],0
        MOV     [DICTCOUNT],0
        MOV     [DICTEND],OFFSET RECORDS
        ; VABOOT and VAIO's SYSINIT handoff boot A: (also when CWD differs).
        MOV     DX,OFFSET DICTORIG
        MOV     AX,3D00H
        INT     21H
        JNC     LDREAD
        CMP     AX,2
        JNE     LDIOERR
        PUSH    DS
        POP     ES
        CLD
        CLC
        RET
LDREAD: MOV     [HADFILE],1
        MOV     BX,AX
        MOV     DX,OFFSET READBUF
        MOV     CX,UDHEAD+UDMAX+1
        MOV     AH,3FH
        INT     21H
        PUSHF
        PUSH    AX
        MOV     AH,3EH
        INT     21H
        POP     BP
        JNC     LDCLOSED
        POPF
        JMP     LDIOERR
LDCLOSED:POPF
        JNC     LDSIZE
        JMP     LDIOERR
LDSIZE: CMP     BP,UDHEAD
        JB      LDBAD
        CMP     BP,UDHEAD+UDMAX
        JA      LDBAD
        ADD     BP,OFFSET READBUF
        CLD
        PUSH    DS
        POP     ES
        MOV     SI,OFFSET READBUF
        MOV     DI,OFFSET FILEBUF
        MOV     CX,UDHEAD-1
        REPE    CMPSB
        JNE     LDBAD
        LODSB
        CMP     AL,2
        JE      LDRECORD
        CMP     AL,1
        JNE     LDBAD
        CMP     BP,OFFSET READBUF+UDHEAD+8*UDV1REC
        JBE     LDRECORD
LDBAD:  MOV     DX,OFFSET BADDICTMSG
        STC
        RET
LDRECORD:CMP    SI,BP
        JNE     LDMORE
        CLC
        RET
LDMORE: CMP     [DICTCOUNT],UDLIMIT
        JAE     LDBAD
        MOV     DI,[DICTEND]
        CMP     BYTE PTR [READBUF+5],1
        JE      LDV1
        LEA     AX,[SI+5]       ;Minimum v2 record, including its trailer.
        CMP     AX,BP
        JA      LDBAD
        CMP     BYTE PTR [SI],UDFIELD
        JA      LDBAD
        CMP     BYTE PTR [SI+1],UDFIELD
        JA      LDBAD
        CALL    PAIRSIZE
        MOV     AX,SI
        ADD     AX,CX
        CMP     AX,BP
        JA      LDBAD
        MOV     BX,AX
        CMP     [BX-1],CL
        JNE     LDBAD
        REP     MOVSB
        JMP     SHORT LDVALID
LDV1:   LEA     AX,[SI+UDV1REC]
        CMP     AX,BP
        JA      LDBAD
        MOVSW
        XOR     AX,AX
        MOV     AL,[DI-2]
        CALL    V1FIELD
        JC      LDBAD
        MOV     BX,[DICTEND]
        MOV     AL,[BX+1]
        CALL    V1FIELD
        JC      LDBAD
        MOV     AX,DI
        SUB     AX,[DICTEND]
        INC     AX
        STOSB
LDVALID:PUSH    SI              ;Next source record.
        PUSH    DI              ;End of normalized record.
        MOV     BX,[DICTEND]
        MOV     SI,BX
        CALL    VALIDPAIR
        JC      LDINVALID
        CALL    FINDPAIR
        CMP     DI,BX
        JNE     LDINVALID
        POP     [DICTEND]
        POP     SI
        INC     [DICTCOUNT]
        JMP     LDRECORD
LDINVALID:
        POP     DI
        POP     SI
        JMP     LDBAD

V1FIELD:CMP     AL,UDFIELD
        JA      V1BAD
        MOV     CX,AX
        REP     MOVSB
        MOV     CX,UDFIELD
        SUB     CX,AX
        JCXZ    V1DONE
V1PAD:  CMP     BYTE PTR [SI],0
        JNE     V1BAD
        INC     SI
        LOOP    V1PAD
V1DONE: CLC
        RET
V1BAD:  STC
        RET

; DS:SI -> compact record, return byte count in CX. Preserve AX.
PAIRSIZE:
        PUSH    AX
        XOR     AX,AX
        MOV     AL,[SI]
        MOV     CX,AX
        MOV     AL,[SI+1]
        ADD     CX,AX
        ADD     CX,3
        POP     AX
        RET

; Find an exact, canonical record at DS:BX; ES=DS. Return DI or DICTEND.
FINDPAIR:MOV    DX,OFFSET RECORDS
FINDNEXT:MOV    DI,DX
        CMP     DI,[DICTEND]
        JE      FINDEND
        MOV     SI,DI
        CALL    PAIRSIZE
        MOV     AX,[SI]
        CMP     AX,[BX]
        JNE     FINDSKIP
        MOV     SI,BX
        REPE    CMPSB
        JE      FINDFOUND
        MOV     SI,DX
        CALL    PAIRSIZE
FINDSKIP:ADD    DX,CX
        JMP     SHORT FINDNEXT
FINDFOUND:MOV   DI,DX
FINDEND:RET

VALIDPAIR:
        XOR     CH,CH
        MOV     CL,[SI]
        MOV     DH,[SI+1]
        ADD     SI,2
        MOV     DL,1
        CALL    VALIDFIELD
        JC      VDBAD
        MOV     CL,DH           ;VALIDFIELD leaves CX=0 on success.
        XOR     DL,DL
VALIDFIELD:
        JCXZ    VDBAD
        CMP     CX,UDFIELD
        JA      VDBAD
        TEST    CL,1
        JNZ     VDBAD
VDCELL: LODSW
        XCHG    AL,AH
        OR      DL,DL
        JZ      VDLEAD
        CMP     AX,815BH
        JE      VDNEXT
        CMP     AX,829FH
        JB      VDCELLBAD
        CMP     AX,82F1H
        JA      VDCELLBAD
        JMP     SHORT VDNEXT
VDLEAD: CMP     AH,81H
        JB      VDCELLBAD
        CMP     AH,9FH
        JBE     VDTRAIL
        CMP     AH,0E0H
        JB      VDCELLBAD
        CMP     AH,0EFH
        JA      VDCELLBAD
VDTRAIL:CMP     AL,40H
        JB      VDCELLBAD
        CMP     AL,7FH
        JE      VDCELLBAD
        CMP     AL,0FCH
        JA      VDCELLBAD
VDNEXT: SUB     CX,2
        JNZ     VDCELL
        CLC
        RET
VDCELLBAD:
VDBAD:  STC
        RET

SAVEDICT:
        ; Create-new; never truncate a stale staging file or the original.
        MOV     DX,OFFSET DICTTEMP
        XOR     CX,CX
        MOV     AH,5BH
        INT     21H
        JC      SVERROR
        MOV     BX,AX
        MOV     DX,OFFSET FILEBUF
        MOV     CX,[DICTEND]
        SUB     CX,DX
        MOV     AH,40H
        INT     21H
        JC      SVSHORT
        CMP     AX,CX
        JE      SVWRITTEN
SVSHORT:MOV     AH,3EH
        INT     21H
        JMP     SHORT SVCLEAN
SVWRITTEN:MOV   AH,3EH
        INT     21H
        JC      SVCLEAN
        CMP     [HADFILE],0
        JE      SVPUBLISH
        MOV     DX,OFFSET DICTORIG
        MOV     DI,OFFSET DICTBAK
        CALL    RENAME
        JC      SVCLEAN
SVPUBLISH:MOV   DX,OFFSET DICTTEMP
        MOV     DI,OFFSET DICTORIG
        CALL    RENAME
        JNC     SVPUBLISHED
        CMP     [HADFILE],0
        JE      SVCLEAN
        MOV     DX,OFFSET DICTBAK
        MOV     DI,OFFSET DICTORIG
        CALL    RENAME
        JC      SVERROR         ;Leave both recovery files intact.
SVCLEAN:MOV     DX,OFFSET DICTTEMP
        MOV     AH,41H
        INT     21H
SVERROR:MOV     DX,OFFSET SAVERRMSG
        STC
        RET
SVPUBLISHED:
        CMP     [HADFILE],0
        JE      SVOK
        MOV     DX,OFFSET DICTBAK
        MOV     AH,41H
        INT     21H
        JC      SVERROR
SVOK:   CLC
        RET
RENAME: PUSH    DS
        POP     ES
        MOV     AH,56H
        INT     21H
        RET

SUCCESS:XOR     AL,AL
        JMP     SHORT PRINT
FAIL:   MOV     AL,1
PRINT:  PUSH    AX
        MOV     AH,9
        INT     21H
        POP     AX
        MOV     AH,4CH
        INT     21H

ARG     DB      4 DUP (0)
OLD21   DD      0
MISSING DB      0
OPENERR DB      0
ROMOK   DB      0
HEADLESS DB     0
OPENED  DB      0
HELPMSG DB      'Usage: JFP ON | ROM | FEP | OFF',13,10
        DB      '       JFP ADD reading word | DEL reading word | LIST',13,10
        DB      'ON selects FEP; ADD/DEL take full-width Shift-JIS.',13,10
        DB      'Run JFP ON again after editing the dictionary.',13,10
        DB      'ROM allows missing default files.',13,10,'$'
OFFMSG  DB      'JFP off; plain CON input.',13,10,'$'
FEPMSG  DB      'Project FEP on. ZENKAKU: kana; F7: katakana; HENKAN: candidates.',13,10,'$'
BUSYMSG DB      'Cannot select input mode. Use JFP OFF before switching.',13,10,'$'
ONMSG   DB      'JFP on. ZENKAKU: kana; HENKAN: convert; KETTEI: confirm.',13,10,'$'
ROMMSG  DB      'JFP on (ROM fallback: default file missing).',13,10,'$'
FEPFILEMSG DB   'FEP requires both default files absent; plain CON input.',13,10,'$'
FILEMSG DB      'JFP default-file open failed; plain CON input.',13,10,'$'
INITMSG DB      'Cannot initialize JFP; plain CON input.',13,10,'$'
NODRV   DB      'VAIO JFP interface not installed.',13,10,'$'
PAIRMSG DB      'Expected a full-width hiragana reading and full-width word (1-30 cells each).',13,10,'$'
DUPMSG  DB      'Dictionary pair already registered.',13,10,'$'
FULLMSG DB      'User dictionary full (64 pairs).',13,10,'$'
NOMATCHMSG DB   'Dictionary pair not found.',13,10,'$'
EMPTYMSG DB     'User dictionary empty.',13,10,'$'
SAVEDMSG DB     'User dictionary saved.',13,10,'$'
IOMSG   DB      'User dictionary I/O error.',13,10,'$'
BADDICTMSG DB   'Invalid JFPUSER.DIC.',13,10,'$'
SAVERRMSG DB    'Dictionary save error; check JFPUSER.DIC, .TMP and .BAK.',13,10,'$'
UPLOADMSG DB    'Cannot update resident user dictionary.',13,10,'$'
LISTSEP DB      ' : '
LISTCR  DB      13,10
DICTORIG DB     'A:\JFPUSER.DIC',0
DICTTEMP DB     'A:\JFPUSER.TMP',0
DICTBAK DB      'A:\JFPUSER.BAK',0
HADFILE DB      0
DICTEND DW      0
DICTCOUNT DB    0
FILEBUF DB      'JFPUD',2
; Scratch space above the COM image, supplied by DOS's COM arena.
RECORDS LABEL   BYTE
PAIR    EQU     RECORDS+UDMAX
READBUF EQU     PAIR+UDV1REC+1
STACKTOP EQU    READBUF+UDHEAD+UDMAX+1+2048
COMPARAS EQU    (STACKTOP-START+100H+15)/16

CODE    ENDS
        END     START
