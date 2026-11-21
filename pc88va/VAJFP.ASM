; JFP.COM for MS-DOS/VA. Run only as a foreground DOS command.
; ResJFP can open DOS files; neither VAIO's CON path nor INT DC calls it.
CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     100H

START:  CLD
        MOV     SI,81H
        XOR     CX,CX
        MOV     CL,BYTE PTR DS:[80H]
SKIP:   JCXZ    USAGE
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
        CMP     DI,3
        JAE     USAGE
        AND     AL,0DFH
        MOV     [ARG+DI],AL
        INC     DI
        LOOP    PARSE
        JMP     SHORT SELECT
TAIL:   DEC     CX
TAIL1:  JCXZ    SELECT
        LODSB
        CMP     AL,' '
        JE      TAILNEXT
        CMP     AL,9
        JNE     USAGE
TAILNEXT: LOOP  TAIL1
SELECT: CMP     WORD PTR [ARG],'NO'
        JNE     NOTON
        CMP     DI,2
        JE      ENABLE
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

PROJECT:CALL    QUERY
        MOV     BX,4
        CALL    VAIO
        CMP     BX,3
        JNE     BUSY
        MOV     DX,OFFSET FEPMSG
        JMP     SUCCESS
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
        CMP     BX,3
        JE      BUSY
        CMP     BX,1
        JNE     RESERVE
        JMP     ENABLED
RESERVE:
        ; A DOS abort must not leave INT 21h pointing into freed COM RAM.
        ; DOS restores INT 23h/24h from our PSP at process exit.
        MOV     DX,OFFSET KEEPGOING
        MOV     AX,2523H
        INT     21H
        MOV     DX,OFFSET FAILIO
        MOV     AX,2524H
        INT     21H
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
        JZ      INITERR
        CMP     [OPENERR],0
        JNE     BADFILES
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
BADFILES:
        CALL    ROMOFF
        MOV     DX,OFFSET FILEMSG
        JMP     SHORT ROLLBACK
ROMERR: CALL    ROMOFF
INITERR:MOV     DX,OFFSET INITMSG
ROLLBACK:
        MOV     BX,3
        CALL    VAIO
        JMP     SHORT FAIL

QUERY:  XOR     BX,BX
        CALL    VAIO
        CMP     AX,464AH
        JE      QUERYOK
        MOV     DX,OFFSET NODRV
        JMP     SHORT FAIL
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
        MOV     CS:[MISSING],1
        JMP     SHORT OPENRET
OPENOK: AND     WORD PTR [BP+6],0FFFEH
OPENRET:POP     BP
        IRET
OPENHOOK ENDP

SUCCESS:XOR     AL,AL
        JMP     SHORT PRINT
FAIL:   MOV     AL,1
PRINT:  PUSH    AX
        MOV     AH,9
        INT     21H
        POP     AX
        MOV     AH,4CH
        INT     21H

ARG     DB      3 DUP (0)
OLD21   DD      0
MISSING DB      0
OPENERR DB      0
ROMOK   DB      0
HELPMSG DB      'Usage: JFP ON | ROM | FEP | OFF',13,10
        DB      'ROM allows missing default files and uses the built-in dictionary.',13,10,'$'
OFFMSG  DB      'JFP off; plain CON input.',13,10,'$'
FEPMSG  DB      'Project FEP on. ZENKAKU: kana; F7: katakana; HENKAN: candidates.',13,10,'$'
BUSYMSG DB      'Cannot select input mode. Use JFP OFF before switching.',13,10,'$'
ONMSG   DB      'JFP on. ZENKAKU: kana; HENKAN: convert; KETTEI: confirm.',13,10,'$'
ROMMSG  DB      'JFP on (ROM fallback: default file missing).',13,10,'$'
FILEMSG DB      'JFP default-file open failed; plain CON input.',13,10,'$'
INITMSG DB      'Cannot initialize JFP; plain CON input.',13,10,'$'
NODRV   DB      'VAIO JFP interface not installed.',13,10,'$'

CODE    ENDS
        END     START
