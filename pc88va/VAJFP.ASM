; JFP.COM for MS-DOS/VA. Run only as a foreground DOS command.
; ResJFP can open DOS files; neither VAIO's CON path nor INT DC calls it.
CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     100H

START:  CLD
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
BUSY:   MOV     DX,OFFSET BUSYMSG
        JMP     FAIL

DISABLE:
        CALL    QUERY
        OR      BX,BX
        JZ      DISABLED
        CMP     BX,1
        JNE     RELEASE
        CALL    ROMOFF
RELEASE:MOV     BX,3
        CALL    VAIO
DISABLED:
        MOV     DX,OFFSET OFFMSG
        JMP     SUCCESS

ENABLE: CALL    QUERY
        OR      BX,BX
        JZ      RESERVE
        CMP     [HEADLESS],0
        JE      CHECKROM
        CMP     BX,3
        JNE     BUSY
        JMP     FEPENABLED
CHECKROM:CMP    BX,1
        JNE     BUSY
        JMP     ENABLED
FEPENABLED:
        CALL    SETUPIO
        CALL    LOADDICT
        JNC     FEPLOADOK
        MOV     AH,9            ;Warn, then replace any old table with empty.
        INT     21H
        MOV     [DICTEND],OFFSET RECORDS
FEPLOADOK:
        MOV     SI,OFFSET RECORDS
        MOV     DX,[DICTEND]
        SUB     DX,SI
        PUSH    DS
        POP     ES
        MOV     BX,5
        CALL    VAIO
        CMP     AX,554AH
        JE      FEPMESSAGE
        MOV     DX,OFFSET UPLOADMSG
        JMP     FAIL
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

QUERY:  XOR     BX,BX
        CALL    VAIO
        CMP     AX,464AH
        JE      QUERYOK
        MOV     DX,OFFSET NODRV
        JMP     FAIL
QUERYOK:RET
VAIO:   MOV     AX,4A46H
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
UDFIELD EQU     60
UDREC   EQU     2+2*UDFIELD
UDMAX   EQU     8*UDREC
UDHEAD  EQU     6

ADDWORD:
DELWORD:MOV     DI,OFFSET PAIR+2
        CALL    TOKEN
        MOV     [PAIR],AL
        MOV     DI,OFFSET PAIR+2+UDFIELD
        CALL    TOKEN
        MOV     [PAIR+1],AL
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
        CMP     DI,OFFSET RECORDS+UDMAX
        JE      FULLDICT
        MOV     SI,BX
        MOV     CX,UDREC
        REP     MOVSB
        MOV     [DICTEND],DI
        JMP     SHORT SAVEWORD
REMOVEWORD:
        CMP     DI,[DICTEND]
        JE      NOWORD
        LEA     SI,[DI+UDREC]
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
        MOV     CL,[SI+1]
        LEA     DX,[SI+2+UDFIELD]
        CALL    STDOUT
        MOV     DX,OFFSET LISTCR
        MOV     CX,2
        CALL    STDOUT
        ADD     SI,UDREC
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
        MOV     [HADFILE],0
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
        MOV     DX,OFFSET FILEBUF
        MOV     CX,UDHEAD+UDMAX+1
        MOV     AH,3FH
        INT     21H
        PUSHF
        PUSH    AX
        MOV     AH,3EH
        INT     21H
        POP     BP
        JC      LDCLOSEERR
        POPF
        JC      LDIOERR
        CMP     BP,UDHEAD
        JB      LDBAD
        CMP     BP,UDHEAD+UDMAX
        JA      LDBAD
        ADD     BP,OFFSET FILEBUF
        CLD
        PUSH    DS
        POP     ES
        MOV     SI,OFFSET FILEBUF
        MOV     DI,OFFSET MAGIC
        MOV     CX,UDHEAD/2
        REPE    CMPSW
        JNE     LDBAD
LDRECORD:MOV    BX,[DICTEND]
        CMP     BX,BP
        JE      LDOK
        LEA     AX,[BX+UDREC]
        CMP     AX,BP
        JA      LDBAD
        MOV     SI,BX
        CALL    VALIDPAIR
        JC      LDBAD
        CALL    FINDPAIR
        CMP     DI,BX
        JNE     LDBAD
        ADD     [DICTEND],UDREC
        JMP     SHORT LDRECORD
LDOK:   CLC
        RET
LDCLOSEERR:POPF
        JMP     LDIOERR
LDBAD:  MOV     DX,OFFSET BADDICTMSG
        STC
        RET

; Find an exact, canonical record at DS:BX; ES=DS. Return DI or DICTEND.
FINDPAIR:MOV    DX,OFFSET RECORDS
FINDNEXT:MOV    DI,DX
        CMP     DI,[DICTEND]
        JE      FINDEND
        MOV     SI,BX
        MOV     CX,UDREC/2
        REPE    CMPSW
        JE      FINDFOUND
        ADD     DX,UDREC
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
        PUSH    CX
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
        POP     AX
        MOV     CX,UDFIELD
        SUB     CX,AX
        JCXZ    VDDONE
VDPAD:  LODSB
        OR      AL,AL
        JNZ     VDBAD
        LOOP    VDPAD
VDDONE: CLC
        RET
VDCELLBAD:POP   AX
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
FULLMSG DB      'User dictionary full (8 pairs).',13,10,'$'
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
MAGIC   DB      'JFPUD',1
PAIR    DB      UDREC DUP (0)
FILEBUF DB      'JFPUD',1
RECORDS DB      UDMAX+1 DUP (0)  ;Extra byte detects oversized files.

CODE    ENDS
        END     START
