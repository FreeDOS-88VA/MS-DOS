; Project kana front end with a headless JFP conversion backend.
; Reading cells hold a Shift-JIS word (lead in AH) or zero-extended ASCII.
FEPMax  EQU     30              ;Fits on one system row, including the prefix.
FEPWIDE DB      0
FEPDRAWN DB     0               ;System row taken from the soft-key renderer.
FEPLEN  DW      0               ;Reading size in bytes (even).
FEPPC   DW      0               ;Unresolved suffix length (0..4).
FEPPEND DB      4 DUP (0)
FEPCELLS DW     FEPMax DUP (0)
FEPREAD DW      0               ;Next uncached confirmed byte, or zero.
FEPCHOICE DB    0               ;0 none, 1 BIOS, 2 whole-reading user word.
FEPKATA DB      0               ;Explicit F7, independent of the backend.
FEPFOCUS DW     0               ;BIOS focus start:length in full-width cells.
FEPCOUNT DB     0               ;Validated candidate length in cells.
FEPINPUT DB     2*FEPMax+1 DUP (0) ;Immutable ASCIIZ full-width reading.
FEPWORKMAX EQU  128             ;60 full-width cells + NUL fit.
FEPWORK DB      FEPWORKMAX DUP (0)
FEPGUARD DB     0
FEPVISIBLE EQU  72              ;Leave room for prefix, focus and cursor.
FEPPFX  DB      '[H] '
FEPBUF  DB      FEPVISIBLE+1 DUP (0) ;Unmarked candidate or editable reading.
FEPCVIEW DB     '[C] ',FEPVISIBLE+3 DUP (0) ;Candidate display with focus.
; Same fixed record layout as VAJFP's version-1 file, without the header.
FEPUFIELD EQU   60
FEPUREC EQU     2+2*FEPUFIELD
FEPUCAP EQU     8*FEPUREC
FEPUEND DW      OFFSET FEPUDATA
FEPUSLOT DW     0               ;Current/last matching user-record offset.
FEPUBRIDGE DB   0               ;Can return from BIOS to the user prefix.
FEPUFOCUS DW    0
FEPUFIRST DB    FEPVISIBLE+1 DUP (0) ;Initial BIOS result for reverse crossing.
FEPUDATA DB     FEPUCAP DUP (0)

; Pump only after a primitive get. CF=0 returns the original AX for the
; ordinary VAIO decoder; CF=1 means project consumed the physical key.
FEPKEY: PUSH    CS
        POP     DS
        CLD
        MOV     BX,[FEPLEN]
        OR      BX,[FEPPC]
        CMP     AH,7BH          ;ZENKAKU, 603KEYB scan table.
        JNE     FEPKEY1
        OR      BX,BX           ;Like the ROM, don't switch mid-reading.
        JNZ     FEPUSED
        XOR     [FEPWIDE],1
FEPUSED:STC
        RET
FEPKEY1:CMP     [FEPWIDE],0
        JNE     FEPKEY2
        CLC
        RET
FEPKEY2:OR      BX,BX
        JZ      FEPCHAR
        CMP     AL,1BH          ;ESC
        JE      FEPKEYDROP
        CMP     AL,3            ;Pending Ctrl-C cancels; idle Ctrl-C breaks DOS.
        JNE     FEPKEYBS
FEPKEYDROP:JMP  FEPDROP
FEPKEYBS:
        CMP     [FEPCHOICE],0
        JE      FEPKEYREAD
        MOV     CL,7            ;Kpfrwd: Right.
        CMP     AH,3CH
        JE      FEPKEYPHRASE
        INC     CL              ;Kpback: Left.
        CMP     AH,3BH
        JE      FEPKEYPHRASE
        INC     CL              ;LongB: Shift+Right.
        CMP     AH,0ACH
        JE      FEPKEYPHRASE
        INC     CL              ;ShortB: Shift+Left.
        CMP     AH,0ABH
        JNE     FEPKEYREAD
FEPKEYPHRASE:
        JMP     FEPPHRASE
FEPKEYREAD:
        CMP     AL,8
        JNE     FEPKEYCR
        JMP     FEPBS
FEPKEYCR:
        CMP     AL,0DH
        JE      FEPKEYENTER
        CMP     AH,51H          ;KETTEI / NFER (unshifted)
        JNE     FEPKEYF7
FEPKEYENTER:JMP FEPENTER
FEPKEYF7:CMP    AH,68H          ;F7 (leave its DOS meaning alone when idle)
        JNE     FEPKEYNEXT
        JMP     FEPTOCAT
FEPKEYNEXT:CMP  AH,35H          ;HENKAN / XFER
        JNE     FEPKEYPREV
        JMP     FEPNEXTKEY
FEPKEYPREV:CMP  AH,0A5H         ;Shift+HENKAN
        JNE     FEPCHAR
        JMP     FEPPREVKEY
FEPCHAR:CMP     AL,0A1H
        JB      FEPASCII
        CMP     AL,0DFH
        JBE     FEPDIRECT
FEPASCII:
        CMP     AL,'-'
        JE      FEPLONG
        CMP     AL,27H          ;Only n' consumes an apostrophe.
        JNE     FEPLETTER
        CMP     [FEPPC],1
        JNE     FEPOTHER
        CMP     [FEPPEND],'n'
        JE      FEPADD
        JMP     SHORT FEPOTHER
FEPLETTER:
        MOV     DL,AL
        OR      DL,20H
        CMP     DL,'a'
        JB      FEPOTHER
        CMP     DL,'z'
        JA      FEPOTHER
        MOV     AL,DL
FEPADD: CMP     [FEPLEN],2*FEPMax
        JAE     FEPUSED2
        CALL    FEPEDIT
        MOV     BX,[FEPPC]
        MOV     [FEPPEND+BX],AL
        INC     [FEPPC]
        CALL    FEPROM
        JMP     FEPDRAW
FEPOTHER:
        OR      BX,BX
        JNZ     FEPUSED2        ;Other DOS editing/function keys are idle-only.
FEPRAW: CLC
        RET
FEPUSED2:STC
        RET
FEPDROP:CALL    FEPRESET
        JMP     SHORT FEPUSED2
FEPBS:  CALL    FEPEDIT
        CMP     [FEPPC],0
        JE      FEPBSK
        DEC     [FEPPC]
        JMP     FEPDRAW
FEPBSK: SUB     [FEPLEN],2
        JMP     FEPDRAW
FEPLONG:CALL    FEPEDIT
        CALL    FEPFINAL
        MOV     AX,815BH
        CALL    FEPAPPEND
        JMP     FEPDRAW
FEPDIRECT:
        PUSH    AX
        CALL    FEPEDIT
        CALL    FEPFINAL
        POP     AX
        CALL    FEPKANA
        JMP     FEPDRAW

FEPTOCAT:
        CALL    FEPEDIT
        CALL    FEPFINAL
        MOV     [FEPKATA],1
        JMP     FEPDRAW
FEPNEXTKEY:
        CMP     [FEPCHOICE],0
        JE      FEPFIRST
        CALL    FEPNEXT
        JMP     SHORT FEPDRAW
FEPPREVKEY:
        CMP     [FEPCHOICE],0
        JE      FEPFIRST
        CALL    FEPPREV
        JMP     SHORT FEPDRAW
FEPPHRASE:
        CMP     [FEPCHOICE],2   ;Whole-reading user words have no phrases.
        JE      FEPDRAW
        MOV     [FEPUBRIDGE],0 ;Stay in BIOS once navigating its phrases.
        CALL    FEPSUG
        JMP     SHORT FEPDRAW
FEPFIRST:
        CALL    FEPFINAL
        MOV     [FEPKATA],0
        CALL    FEPREADING
        CALL    FEPBEGIN
FEPDRAW:CALL    FEPRENDER
        STC
        RET

FEPENTER:
        ; Like NEC 3.3D NECAIK, Return during composition only confirms.
        CALL    FEPFINAL
        CMP     [FEPCHOICE],0
        JE      FEPENTER0
        CALL    FEPCOMMIT
        JMP     SHORT FEPENTER1
FEPENTER0:
        CALL    FEPBUILD
FEPENTER1:
        CALL    FEPRESET        ;Does not overwrite the materialized bytes.
        MOV     [FEPREAD],OFFSET FEPBUF
        STC
        RET

; The status path caches one byte. Only CINP removes CHAR; no new key is
; examined until all confirmed bytes have been read.
FEPBYTE:MOV     AL,CS:[BX]
        MOV     CS:[CHAR],AL
        INC     BX
        CMP     BYTE PTR CS:[BX],0
        JNE     FEPB1
        XOR     BX,BX
FEPB1:  MOV     CS:[FEPREAD],BX
        RET

; Flush in project mode never interprets the discarded keys or changes width.
FEPFLUSH:
        CALL    JFPCLEAR
        MOV     [FEPREAD],0
        CALL    FEPRESET
FEPFL1: MOV     AH,0AH
        INT     82H
        JC      FEPFL2
        MOV     AH,09H
        INT     82H
        JMP     SHORT FEPFL1
FEPFL2: PUSH    CS
        POP     DS
        RET
FEPRESET:
        CALL    FEPEDIT
        MOV     [FEPLEN],0
        MOV     [FEPPC],0
        JMP     FEPRESTORE
FEPEDIT:
        MOV     [FEPKATA],0
        CMP     [FEPCHOICE],0
        JE      FEPEDITDONE
        JMP     FEPCANCEL
FEPEDITDONE:RET

; 618JFP section 6.18.3. Serialize at the CON request boundary; never
; invoke reset, file services or learning here. Begin accepts only full-
; width hiragana (plus the prolonged sound mark). All Sug calls see the
; same input and output buffers throughout a session. A bounded, exact
; whole-reading user prefix precedes BIOS ordering and endpoint semantics.
FEPBEGIN:
        JCXZ    FEPBADREAD
        MOV     DI,OFFSET FEPINPUT
FEPIN1: LODSW
        CMP     AX,815BH        ;Prolonged sound mark.
        JE      FEPIN2
        CMP     AX,829FH
        JB      FEPBADREAD
        CMP     AX,82F1H
        JA      FEPBADREAD
FEPIN2: MOV     [DI],AH
        MOV     [DI+1],AL
        ADD     DI,2
        LOOP    FEPIN1
        MOV     BYTE PTR [DI],0
        MOV     [FEPUBRIDGE],0
        MOV     BX,OFFSET FEPUDATA
        MOV     DX,FEPUREC
        CALL    FEPUFIND
        JNC     FEPSTARTBIOS
        JMP     FEPUAPPLY
FEPBADREAD:RET
FEPSTARTBIOS:
        ; Discard the prior session's entire output, including terminators.
        MOV     DI,OFFSET FEPWORK
        PUSH    DS
        POP     ES
        MOV     CX,FEPWORKMAX
        MOV     AL,0FFH
        REP     STOSB
        MOV     [FEPGUARD],0A5H
        MOV     CL,4            ;Sug1st.
        JMP     FEPSUG
FEPNEXT:CMP     [FEPCHOICE],2
        JE      FEPUNEXT
        MOV     CL,5            ;SugNxt.
        JMP     FEPSUG
FEPPREV:CMP     [FEPCHOICE],2
        JNE     FEPBIOSPREV
        JMP     FEPUPREV
FEPBIOSPREV:CMP [FEPUBRIDGE],0
        JNE     FEPUBACK
        MOV     CL,6            ;SugPrv.
        JMP     FEPSUG

FEPUNEXT:MOV    BX,[FEPUSLOT]
        ADD     BX,FEPUREC
        MOV     DX,FEPUREC
        CALL    FEPUFIND
        JC      FEPUAPPLY
        MOV     [FEPCHOICE],0   ;Even an invalid BIOS result needs QuitJFP.
        CALL    FEPSTARTBIOS
        CMP     [FEPCHOICE],1
        JNE     FEPURET
        MOV     [FEPUBRIDGE],1
        MOV     AX,[FEPFOCUS]
        MOV     [FEPUFOCUS],AX
        MOV     SI,OFFSET FEPBUF
        MOV     DI,OFFSET FEPUFIRST
        CALL    FEPVISLEN
        REP     MOVSB           ;FEPSUG left ES=DS on success.
        RET
FEPUBACK:
        ; Do not ask BIOS to go before its first candidate: on VA2 it
        ; wraps for some readings despite the documented endpoint behavior.
        CALL    FEPUATFIRST
        JE      FEPUBACKUSER
        MOV     CL,6
        JMP     FEPSUG
FEPUBACKUSER:
        CALL    FEPCANCEL
        MOV     BX,[FEPUSLOT]
        JMP     SHORT FEPUAPPLY
FEPUATFIRST:
        MOV     AX,[FEPFOCUS]
        CMP     AX,[FEPUFOCUS]
        JNE     FEPURET
        PUSH    DS
        POP     ES
        MOV     SI,OFFSET FEPBUF
        MOV     DI,OFFSET FEPUFIRST
        CALL    FEPVISLEN
        REPE    CMPSB
FEPURET:RET
FEPVISLEN:XOR   CH,CH
        MOV     CL,[FEPCOUNT]
        SHL     CX,1
        INC     CX              ;Include terminator.
        RET

FEPUPREV:MOV    BX,[FEPUSLOT]
        SUB     BX,FEPUREC
        MOV     DX,-FEPUREC
        CALL    FEPUFIND
        JNC     FEPURET
FEPUAPPLY:
        MOV     [FEPUSLOT],BX
        LEA     SI,[BX+2+FEPUFIELD]
        MOV     DI,OFFSET FEPBUF
        XOR     CH,CH
        MOV     CL,[BX+1]
        MOV     AX,CX
        SHR     AX,1
        MOV     [FEPCOUNT],AL
        MOV     [FEPFOCUS],AX   ;Highlight the whole user word.
        PUSH    DS
        POP     ES
        REP     MOVSB
        MOV     BYTE PTR [DI],0
        MOV     [FEPCHOICE],2
        RET

; BX points at the first slot to test; DX is the signed slot stride.
; Return CF=1 with BX at a match. No DOS and no firmware calls.
FEPUFIND:
        PUSH    DS
        POP     ES
FEPUSCAN:CMP    BX,OFFSET FEPUDATA
        JB      FEPUNONE
        CMP     BX,[FEPUEND]
        JAE     FEPUNONE
        MOV     AX,[FEPLEN]
        CMP     AL,[BX]
        JNE     FEPUSKIP
        MOV     AL,[BX+1]       ;Defend the copy bound even for a bad caller.
        CMP     AL,2
        JB      FEPUSKIP
        CMP     AL,FEPUFIELD
        JA      FEPUSKIP
        TEST    AL,1
        JNZ     FEPUSKIP
        MOV     SI,OFFSET FEPINPUT
        LEA     DI,[BX+2]
        MOV     CX,[FEPLEN]
        REPE    CMPSB
        JE      FEPUFOUND
FEPUSKIP:ADD    BX,DX
        JMP     SHORT FEPUSCAN
FEPUNONE:CLC
        RET
FEPUFOUND:STC
        RET

FEPSUG: MOV     SI,OFFSET FEPINPUT
        MOV     DI,OFFSET FEPWORK
        CALL    FEPJFP
        MOV     [FEPFOCUS],AX
        CMP     [FEPGUARD],0A5H
        JNE     FEPCANCEL
        ; Accept only a nonempty, terminated full-width Shift-JIS result
        ; that fits the system row. Never display or queue partial output.
        MOV     SI,OFFSET FEPWORK
FEPOUT1:LODSB
        OR      AL,AL
        JZ      FEPOUT3
        CMP     SI,OFFSET FEPWORK+FEPVISIBLE
        JAE     FEPCANCEL
        CMP     AL,81H
        JB      FEPCANCEL
        CMP     AL,9FH
        JBE     FEPOUT2
        CMP     AL,0E0H
        JB      FEPCANCEL
        CMP     AL,0EFH
        JA      FEPCANCEL
FEPOUT2:LODSB
        CMP     AL,40H
        JB      FEPCANCEL
        CMP     AL,7FH
        JE      FEPCANCEL
        CMP     AL,0FCH
        JBE     FEPOUT1
        JMP     SHORT FEPCANCEL
FEPOUT3:MOV     CX,SI
        SUB     CX,OFFSET FEPWORK
        CMP     CX,1
        JE      FEPCANCEL
        MOV     SI,OFFSET FEPWORK
        MOV     DI,OFFSET FEPBUF
        PUSH    DS
        POP     ES
        REP     MOVSB
        SUB     DI,OFFSET FEPBUF
        SHR     DI,1
        MOV     AX,DI
        MOV     [FEPCOUNT],AL
        MOV     [FEPCHOICE],1
        RET
FEPCANCEL:
        CMP     [FEPCHOICE],2
        JE      FEPCLEARCHOICE ;No BIOS session for a user word.
        PUSH    AX              ;FEPADD still needs the letter in AL.
        MOV     CL,3            ;QuitJFP: reset pending front-end state.
        CALL    FEPJFP
        POP     AX
FEPCLEARCHOICE:
        MOV     [FEPCHOICE],0
        MOV     [FEPUBRIDGE],0
        RET
FEPCOMMIT:
        ; §6.18.3 Decide learns; there is no documented non-learning
        ; Decide. Keep the validated snapshot and close like a cancel.
        JMP     FEPCANCEL
FEPJFP: PUSH    DS
        PUSH    ES
        XOR     CH,CH
        INT     8DH
        POP     ES
        POP     DS
        CLD
        RET

FEPBUILD:
        CALL    FEPREADING
        MOV     AL,[FEPKATA]
        MOV     BL,AL
        MOV     DI,OFFSET FEPBUF
        JCXZ    FEPFMT3
FEPFMT1:LODSW
        OR      AH,AH
        JZ      FEPFMT2
        CMP     AH,82H
        JNE     FEPFMTW
        OR      BL,BL
        JZ      FEPFMTW
        INC     AH
        SUB     AL,5FH          ;82 9F..F1 -> 83 40..93, skip trail 7Fh.
        CMP     AL,7FH
        JB      FEPFMTW
        INC     AL
FEPFMTW:MOV     [DI],AH
        INC     DI
FEPFMT2:MOV     [DI],AL
        INC     DI
        LOOP    FEPFMT1
FEPFMT3:MOV     BYTE PTR [DI],0
        RET
FEPREADING:
        MOV     SI,OFFSET FEPCELLS
        MOV     CX,[FEPLEN]
        SHR     CX,1
        RET

; Own just the visible system split. Disable the ROM's Shift-driven label
; renderer during composition and use documented text BIOS calls. Do not
; change DOS's main cursor or current attribute, or use the CON parser.
FEPRENDER:
        MOV     AX,[FEPLEN]
        OR      AX,[FEPPC]
        JZ      FEPRESTORE
        CMP     [FEPDRAWN],0
        JNE     FEPPAINT
        MOV     AX,2F00H
        INT     83H
        MOV     CS:[FEPDRAWN],1
FEPPAINT:
        MOV     AH,26H          ;Askloc main cursor as in GRAPHMARK.
        INT     83H
        PUSH    DX
        MOV     AX,1B01H        ;Chcsn, system split.
        INT     83H
        JC      FEPUIRET
        XOR     DX,DX
        MOV     AH,08H          ;Locate at column 1 of system row.
        INT     83H
        MOV     AX,1802H        ;Eralin, whole row.
        INT     83H
        PUSH    CS
        POP     DS
        CLD
        MOV     AL,[FEPCHOICE]
        OR      AL,AL
        JZ      FEPUIREADING
        CALL    FEPMARK
        MOV     SI,OFFSET FEPCVIEW
        JMP     SHORT FEPUIOUT
FEPUIREADING:
        CALL    FEPBUILD
        MOV     AL,'H'
        CMP     [FEPKATA],0
        JE      FEPUIWRITE
        MOV     AL,'K'
FEPUIWRITE:
        MOV     [FEPPFX+1],AL
        MOV     SI,OFFSET FEPPEND
        MOV     CX,[FEPPC]
        JCXZ    FEPUISTR
FEPUI1: LODSB
        MOV     [DI],AL
        INC     DI
        LOOP    FEPUI1
        MOV     BYTE PTR [DI],0
FEPUISTR:
        MOV     SI,OFFSET FEPPFX
FEPUIOUT:
        MOV     AX,0200H        ;Putstr, explicit mode-1 attribute.
        MOV     DX,0070H
        INT     83H
        MOV     AX,1B00H
        INT     83H
FEPUIRET:
        POP     DX
        MOV     AH,08H
        INT     83H
        PUSH    CS
        POP     DS
        RET
FEPRESTORE:
        CMP     [FEPDRAWN],0
        JE      FEPRRET
        MOV     [FEPDRAWN],0
        MOV     AX,2F0AH
        INT     83H
        MOV     CS:[JFPDIRTY],1
        CALL    JFPRIDLE        ;Overwrite all composition pixels now.
        PUSH    CS
        POP     DS
FEPRRET:RET

; VA and VA2 return AH=start, AL=length, reversed relative to the local
; 618JFP transcription. Use them only within the validated output span.
; The DOS delivery buffer never includes focus brackets.
FEPMARK:
        PUSH    DS
        POP     ES
        MOV     SI,OFFSET FEPBUF
        MOV     DI,OFFSET FEPCVIEW+4
        MOV     AX,[FEPFOCUS]
        OR      AL,AL
        JZ      FEPMARKREST
        MOV     BL,AH
        ADD     BL,AL
        JC      FEPMARKREST
        CMP     BL,[FEPCOUNT]
        JA      FEPMARKREST
        XOR     CX,CX
        MOV     CL,AH
        REP     MOVSW
        MOV     BYTE PTR [DI],'['
        INC     DI
        MOV     CL,AL
        REP     MOVSW
        MOV     BYTE PTR [DI],']'
        INC     DI
FEPMARKREST:
        LODSB
        STOSB
        OR      AL,AL
        JNZ     FEPMARKREST
        RET

; Parse a bounded prefix on each physical letter. Table entries are
; 4 lowercase ASCII bytes (zero-padded), then 1 or 2 hiragana trails.
; A trailing n waits for its context; doubled consonants leave the
; second letter pending for the following syllable. On a bad prefix,
; retain the unmatched first letter as literal ASCII and try the rest.
FEPROM: CMP     [FEPPC],0
        JNE     FEPROM0
        RET
FEPROM0:MOV     BX,OFFSET ROMAJI
        PUSH    DS
        POP     ES
FEPROM1:MOV     SI,OFFSET FEPPEND
        MOV     DI,BX
        MOV     CX,[FEPPC]
        REPE    CMPSB
        JNE     FEPROM4
        CMP     [FEPPC],4
        JE      FEPROM2
        CMP     BYTE PTR [DI],0
        JNE     FEPROMRT        ;An incomplete prefix.
FEPROM2:MOV     DX,[BX+4]
        MOV     [FEPPC],0
        OR      DH,DH
        JZ      FEPROM3
        CMP     [FEPLEN],2*(FEPMax-1)
        JAE     FEPROMRT        ;Keep a two-kana syllable atomic at the bound.
        MOV     AX,8200H
        MOV     AL,DL
        CALL    FEPAPPEND
        MOV     DL,DH
FEPROM3:MOV     AH,82H
        MOV     AL,DL
        JMP     FEPAPPEND
FEPROM4:ADD     BX,6
        CMP     BX,OFFSET ROMAJIEND
        JB      FEPROM1
        XOR     AX,AX
        MOV     AL,[FEPPEND]
        CMP     AL,'n'
        JNE     FEPROM5
        CMP     [FEPPC],1
        JE      FEPROMRT        ;Hold a single n until another key or confirm.
        MOV     AX,82F1H
        CMP     [FEPPEND+1],'n'
        JE      FEPROMNN
        CMP     [FEPPEND+1],27H
        JNE     FEPROM6
FEPROMNN:
        CALL    FEPSHIFT
        JMP     SHORT FEPROM6
FEPROM5:CMP     [FEPPC],2
        JB      FEPROM6
        CMP     AL,[FEPPEND+1]
        JNE     FEPROM6
        ; Single-letter vowels have already matched and are never pending.
        ; Only starters with a table prefix can double (not unmatched ASCII).
        MOV     BX,OFFSET ROMAJI
FEPDOUBLE:
        CMP     AL,[BX]
        JE      FEPSOKU
        ADD     BX,6
        CMP     BX,OFFSET ROMAJIEND
        JB      FEPDOUBLE
        JMP     SHORT FEPROM6
FEPSOKU:MOV     AX,82C1H
FEPROM6:CALL    FEPAPPEND
        CALL    FEPSHIFT
        JMP     FEPROM
FEPROMRT:RET

FEPFINAL:
        CMP     [FEPPC],0
        JE      FEPFINRT
        XOR     AX,AX
        MOV     AL,[FEPPEND]
        CMP     [FEPPC],1
        JNE     FEPFIN1
        CMP     AL,'n'
        JNE     FEPFIN1
        MOV     AX,82F1H
FEPFIN1:CALL    FEPAPPEND
        CALL    FEPSHIFT
        JMP     SHORT FEPFINAL
FEPFINRT:RET
FEPSHIFT:
        DEC     [FEPPC]
        MOV     BX,WORD PTR [FEPPEND+1]
        MOV     WORD PTR [FEPPEND],BX
        MOV     BL,[FEPPEND+3]
        MOV     [FEPPEND+2],BL
        RET
FEPAPPEND:
        MOV     BX,[FEPLEN]
        CMP     BX,2*FEPMax
        JAE     FEPFULL
        MOV     [FEPCELLS+BX],AX
        ADD     [FEPLEN],2
FEPFULL:RET

; Decode the primitive half-width kana codes to standard full-width kana.
; A diacritic combines only with a preceding eligible cell. Shift-JIS
; has no hiragana U with dakuten; represent it as katakana VU (8394h).
FEPKANA:SUB     AL,0A1H
        XOR     AH,AH
        MOV     SI,AX
        SHL     SI,1
        MOV     AX,[KANAANK+SI]
        CMP     AL,4AH
        JB      FEPKADD
        CMP     AL,4BH
        JA      FEPKADD
        MOV     BX,[FEPLEN]
        OR      BX,BX
        JZ      FEPKADD
        MOV     DX,[FEPCELLS+BX-2]
        CMP     DH,82H
        JNE     FEPKADD
        MOV     CX,5
        MOV     SI,OFFSET KANAHA
FEPKHA: CMP     DL,[SI]
        JE      FEPKHA1
        INC     SI
        LOOP    FEPKHA
        CMP     AL,4BH
        JE      FEPKADD
        CMP     DL,0A4H
        JNE     FEPKDAK
        MOV     WORD PTR [FEPCELLS+BX-2],8394H
        RET
FEPKDAK:MOV     CX,15
        MOV     SI,OFFSET KANADAK
FEPKDK1:CMP     DL,[SI]
        JE      FEPKINC
        INC     SI
        LOOP    FEPKDK1
FEPKADD:JMP     FEPAPPEND
FEPKHA1:CMP     AL,4BH
        JNE     FEPKINC
        INC     DL
FEPKINC:INC     DL
        MOV     [FEPCELLS+BX-2],DX
        RET

KANAHA  DB      0CDH,0D0H,0D3H,0D6H,0D9H
KANADAK DB      0A9H,0ABH,0ADH,0AFH,0B1H,0B3H,0B5H,0B7H,0B9H,0BBH
        DB      0BDH,0BFH,0C2H,0C4H,0C6H
KANAANK DW      8142H,8175H,8176H,8141H,8145H,82F0H,829FH,82A1H
        DW      82A3H,82A5H,82A7H,82E1H,82E3H,82E5H,82C1H,815BH
        DW      82A0H,82A2H,82A4H,82A6H,82A8H,82A9H,82ABH,82ADH
        DW      82AFH,82B1H,82B3H,82B5H,82B7H,82B9H,82BBH,82BDH
        DW      82BFH,82C2H,82C4H,82C6H,82C8H,82C9H,82CAH,82CBH
        DW      82CCH,82CDH,82D0H,82D3H,82D6H,82D9H,82DCH,82DDH
        DW      82DEH,82DFH,82E0H,82E2H,82E4H,82E6H,82E7H,82E8H
        DW      82E9H,82EAH,82EBH,82EDH,82F1H,814AH,814BH

; Project-written mappings from ordinary Hepburn/Kunrei spelling to the
; standard Shift-JIS kana chart. No dictionary or firmware table used.
RK      MACRO   spelling,k1,k2
        LOCAL   rkey
rkey:   DB      spelling
        IF      ($-rkey) LT 4
        DB      (4-($-rkey)) DUP (0)
        ENDIF
        DB      k1,k2
        ENDM
RBASE   MACRO   s,ka,ki,ku,ke,ko
        RK      <'&s&a'>,ka,0
        RK      <'&s&i'>,ki,0
        RK      <'&s&u'>,ku,0
        RK      <'&s&e'>,ke,0
        RK      <'&s&o'>,ko,0
        ENDM
RYOU    MACRO   s,k
        RK      <'&s&ya'>,k,0E1H
        RK      <'&s&yu'>,k,0E3H
        RK      <'&s&yo'>,k,0E5H
        ENDM
ROMAJI  LABEL   BYTE
        RK      'a',0A0H,0
        RK      'i',0A2H,0
        RK      'u',0A4H,0
        RK      'e',0A6H,0
        RK      'o',0A8H,0
        RBASE   k,0A9H,0ABH,0ADH,0AFH,0B1H
        RBASE   g,0AAH,0ACH,0AEH,0B0H,0B2H
        RBASE   s,0B3H,0B5H,0B7H,0B9H,0BBH
        RBASE   z,0B4H,0B6H,0B8H,0BAH,0BCH
        RBASE   t,0BDH,0BFH,0C2H,0C4H,0C6H
        RBASE   d,0BEH,0C0H,0C3H,0C5H,0C7H
        RBASE   n,0C8H,0C9H,0CAH,0CBH,0CCH
        RBASE   h,0CDH,0D0H,0D3H,0D6H,0D9H
        RBASE   b,0CEH,0D1H,0D4H,0D7H,0DAH
        RBASE   p,0CFH,0D2H,0D5H,0D8H,0DBH
        RBASE   m,0DCH,0DDH,0DEH,0DFH,0E0H
        RBASE   r,0E7H,0E8H,0E9H,0EAH,0EBH
        RK      'ya',0E2H,0
        RK      'yu',0E4H,0
        RK      'yo',0E6H,0
        RK      'wa',0EDH,0
        RK      'wo',0F0H,0
        RK      'shi',0B5H,0
        RK      'ji',0B6H,0
        RK      'chi',0BFH,0
        RK      'tsu',0C2H,0
        RK      'fu',0D3H,0
        RYOU    k,0ABH
        RYOU    g,0ACH
        RYOU    s,0B5H
        RYOU    z,0B6H
        RYOU    t,0BFH
        RYOU    d,0C0H
        RYOU    n,0C9H
        RYOU    h,0D0H
        RYOU    b,0D1H
        RYOU    p,0D2H
        RYOU    m,0DDH
        RYOU    r,0E8H
        RK      'sha',0B5H,0E1H
        RK      'shu',0B5H,0E3H
        RK      'sho',0B5H,0E5H
        RK      'ja',0B6H,0E1H
        RK      'ju',0B6H,0E3H
        RK      'jo',0B6H,0E5H
        RYOU    j,0B6H
        RK      'cha',0BFH,0E1H
        RK      'chu',0BFH,0E3H
        RK      'cho',0BFH,0E5H
        RBASE   x,9FH,0A1H,0A3H,0A5H,0A7H
        RBASE   l,9FH,0A1H,0A3H,0A5H,0A7H
        RK      'xya',0E1H,0
        RK      'xyu',0E3H,0
        RK      'xyo',0E5H,0
        RK      'lya',0E1H,0
        RK      'lyu',0E3H,0
        RK      'lyo',0E5H,0
        RK      'xwa',0ECH,0
        RK      'lwa',0ECH,0
        RK      'xtu',0C1H,0
        RK      'ltu',0C1H,0
        RK      'xtsu',0C1H,0
        RK      'ltsu',0C1H,0
ROMAJIEND LABEL BYTE
