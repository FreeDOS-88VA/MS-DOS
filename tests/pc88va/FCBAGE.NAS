; B4 probe: the FCB SFT open age across failed FCB I/O (FCBIO2.ASM).
; nasm -f bin FCBAGE.NAS -o FCBAGE.COM
; Boot with FCBS=2,0 and the B: disk from fcb-age-media.py: BAD.DAT's data
; sector cannot be read, DENY.DAT is read-only, NEXT.DAT is readable.
; Run FCBAGE (or FCBAGE >AGE.LOG). All printed values are hex words.
; READ/WRITE lines: open age before and after the failed call, AL, CX,
; extended error (INT 21h/59h), INT 24 count and the INT 24 error (DI).
; SFT lines: each FCB cache entry as offset:ref-count LRU open-age name.
; READ/WRITE lines also give sf_LRU before and after the failed call.
; Exit code 0 = PASS; otherwise bit 1 = open age lost, bit 2 = LRU stale
; (both expected before the B4 fix), 1 = some other step failed (the step
; letter is printed).
bits 16
cpu 8086
org 100h
    push cs
    pop ds
    mov ah,52h
    int 21h
    ; DOS 4 list of lists (INC/SYSVAR.INC): +16h is the CDS list,
    ; +1Ah (SYSI_FCB) points to the separate FCB SFT cache.
    les di,[es:bx+1ah]
    cmp word [es:di+4],2
    jne failure
    add di,6
    mov [cache],di
    mov [cache+2],es

    mov ax,3524h
    int 21h
    mov [old24],bx
    mov [old24+2],es
    mov dx,critical
    mov ax,2524h
    int 21h
    mov dx,dma
    mov ah,1ah
    int 21h

    mov byte [step],'B'
    mov dx,bad
    call open
    call show
    ; A failed FCB read: BAD.DAT's data sector is missing (INT 24, Fail).
    mov si,read_msg
    mov ah,27h
    call try_io
    cmp word [critical_count],0
    je failure
    call show

    mov byte [step],'D'
    mov dx,deny
    call open
    call show
    ; The cache still has a free entry, so this open must use it and keep
    ; BAD (an open FCB whose last call failed) in the cache.
    mov dx,bad
    call find
    jnc .kept
    mov byte [lru_fail],1
    mov si,bad_evicted
    call print
    jmp .opened
.kept:
    mov si,free_used
    call print
.opened:
    mov dx,deny
    call find
    jc failure
    ; A refused FCB write: DENY.DAT is read-only (access denied, no INT 24).
    mov si,write_msg
    mov ah,28h
    call try_io
    call show

    ; Fill the two-entry cache with FCBs whose last I/O succeeded:
    ; DENY is read first, so it is the least recently used entry.
    mov byte [step],'E'
    mov dx,deny
    call good_read
    mov dx,next
    call open
    mov dx,next
    call good_read
    mov dx,deny
    call find
    jc failure
    mov [deny_slot],di
    call show
    ; Opening a third file must evict DENY and reuse its entry.
    mov byte [step],'F'
    mov dx,bad
    call open
    cmp di,[deny_slot]
    jne failure
    mov dx,deny
    call find
    jnc failure
    mov dx,next
    call find
    jc failure
    call show
    mov si,evicted
    call print
    ; The evicted FCB must still read (the SFT is regenerated from the FCB).
    mov byte [step],'G'
    mov dx,deny
    call good_read
    mov dx,deny
    call find
    jc failure
    call show
    ; Close every FCB (an evicted one is regenerated first), then the
    ; cache must hold no live entry; reopen and close once more.
    mov byte [step],'H'
    mov dx,deny
    call close
    mov dx,next
    call close
    mov dx,bad
    call close
    call empty
    mov dx,next
    call open
    mov dx,next
    call good_read
    mov dx,next
    call close
    call empty
    call show
    mov si,followup
    call print
    mov si,age_kept
    cmp byte [age_fail],0
    je .age
    mov si,age_lost
.age:
    call print
    mov si,lru_fresh
    cmp byte [lru_fail],0
    je .lru
    mov si,lru_stale
.lru:
    call print
    mov al,[age_fail]
    shl al,1
    mov ah,[lru_fail]
    shl ah,1
    shl ah,1
    or al,ah
    push ax
    mov si,verdict_pass
    or al,al
    jz .verdict
    mov si,verdict_fail
.verdict:
    call print
    pop ax
    push ax
    xor ah,ah
    call hex
    mov si,newline
    call print
    pop ax
    jmp finish
failure:
    mov si,failed
    call print
    mov al,1
finish:
    cmp word [old24+2],0
    je .exit
    push ax
    push ds
    lds dx,[old24]
    mov ax,2524h
    int 21h
    pop ds
    pop ax
.exit:
    mov ah,4ch
    int 21h

open:
    push dx
    mov ah,0fh
    int 21h
    pop dx
    or al,al
    jnz failure
    call find
    jc failure
    ret

close:
    push dx
    mov ah,10h
    int 21h
    pop dx
    or al,al
    jnz failure
    call find
    jnc failure
    ret

good_read:
    mov bx,dx
    mov word [bx+21h],0       ; random record number
    mov word [bx+23h],0
    mov cx,1
    mov ah,27h
    int 21h
    or al,al
    jnz .bad
    cmp cx,1
    jne .bad
    ret
.bad:
    push cx
    xor ah,ah
    push ax
    mov si,read_fail
    call print
    pop ax
    call hex
    mov al,' '
    call putc
    pop ax
    call hex
    mov si,newline
    call print
    jmp failure

; Find the live FCB SFT by its 11-byte name. ES:DI -> match, CF if absent.
find:
    les di,[cache]
    mov bx,2
.loop:
    cmp word [es:di],0
    je .next
    test word [es:di+2],8000h
    jz .next
    push di
    add di,20h               ; sf_name, SF.INC
    mov si,dx
    inc si
    mov cx,11
    cld
    repe cmpsb
    pop di
    je .found
.next:
    add di,3bh               ; sizeof sf_entry, SF.INC
    dec bx
    jnz .loop
    stc
    ret
.found:
    clc
    ret

try_io:
    mov [fcb],dx
    mov [age_before],word 0
    mov bx,[es:di+17h]        ; sf_OpenAge = sf_position + 2
    mov [age_before],bx
    or bx,bx
    jz failure
    mov bx,[es:di+15h]        ; sf_LRU = sf_position (keep AH)
    mov [lru_before],bx
    mov [critical_count],word 0
    mov [critical_error],word 0ffffh
    push si
    mov cx,1
    int 21h
    xor ah,ah
    mov [status],ax
    mov [records],cx
    mov ax,5900h
    xor bx,bx
    int 21h
    mov [extended],ax
    mov dx,[fcb]
    call find
    jc failure
    mov ax,[es:di+17h]
    mov [age_after],ax
    cmp ax,[age_before]
    je .lru
    mov byte [age_fail],1
.lru:
    ; The entry must now carry the newest LRU count of all live entries,
    ; as after a successful call.
    mov ax,[es:di+15h]
    mov [lru_after],ax
    cmp ax,[lru_before]
    jbe .stale
    call newest
    jnc .report
.stale:
    mov byte [lru_fail],1
.report:
    pop si
    call print
    mov bx,age_before
    mov cx,9
.words:
    mov ax,[bx]
    call hex
    mov al,' '
    call putc
    add bx,2
    loop .words
    mov si,newline
    call print
    cmp word [status],1
    jne failure
    cmp word [records],0
    jne failure
    cmp word [extended],0
    je failure
    ret

; CF set if a live FCB SFT other than ES:DI has an LRU count above AX.
newest:
    push es
    push di
    push bx
    push cx
    mov bx,di
    les di,[cache]
    mov cx,2
.entry:
    cmp di,bx
    je .next
    cmp word [es:di],0
    je .next
    cmp [es:di+15h],ax
    ja .older
.next:
    add di,3bh
    loop .entry
    clc
    jmp .done
.older:
    stc
.done:
    pop cx
    pop bx
    pop di
    pop es
    ret

show:
    mov si,sft_msg
    call print
    jmp dump

; Fail unless every FCB cache entry has a zero reference count.
empty:
    push es
    push di
    les di,[cache]
    mov cx,2
.entry:
    cmp word [es:di],0
    jne failure
    add di,3bh
    loop .entry
    pop di
    pop es
    ret

; Print each FCB SFT: offset, ref count, LRU (sf_position), open age, name.
dump:
    push es
    push di
    push bx
    les di,[cache]
    mov bx,2
.entry:
    mov ax,di
    call hex
    mov al,':'
    call putc
    mov ax,[es:di]
    call hex
    mov al,' '
    call putc
    mov ax,[es:di+15h]
    call hex
    mov al,' '
    call putc
    mov ax,[es:di+17h]
    call hex
    mov al,' '
    call putc
    mov cx,11
    push di
    add di,20h
.name:
    mov al,[es:di]
    cmp al,' '
    jae .show
    mov al,'.'
.show:
    call putc
    inc di
    loop .name
    pop di
    mov al,' '
    call putc
    add di,3bh
    dec bx
    jnz .entry
    mov si,newline
    call print
    pop bx
    pop di
    pop es
    ret

critical:
    inc word [cs:critical_count]
    mov [cs:critical_error],di
    mov al,3                 ; Fail the request, not the process
    iret

print:
    lodsb
    or al,al
    jz .done
    call putc
    jmp print
.done:
    ret

hex:
    push cx
    mov cx,4
.digit:
    rol ax,1
    rol ax,1
    rol ax,1
    rol ax,1
    push ax
    and al,0fh
    cmp al,10
    jb .number
    add al,'A'-'0'-10
.number:
    add al,'0'
    call putc
    pop ax
    loop .digit
    pop cx
    ret

putc:
    push ax
    push dx
    mov dl,al
    mov ah,02h
    int 21h
    pop dx
    pop ax
    ret

%macro fcb_data 1
    db 2,%1                 ; B: + padded 11-byte name
    times 25 db 0
%endmacro
bad:  fcb_data 'BAD     DAT'
deny: fcb_data 'DENY    DAT'
next: fcb_data 'NEXT    DAT'
cache: dd 0
old24: dd 0
deny_slot: dw 0
fcb: dw 0
age_fail: db 0
; Print these seven words, in order.
age_before: dw 0
age_after: dw 0
status: dw 0
records: dw 0
extended: dw 0
critical_count: dw 0
critical_error: dw 0
lru_before: dw 0
lru_after: dw 0
lru_fail: db 0
read_msg: db 'READ  age b/a, AL CX ext I24n I24DI, LRU b/a: ',0
write_msg: db 'WRITE age b/a, AL CX ext I24n I24DI, LRU b/a: ',0
sft_msg: db 'SFT slot:ref LRU age name: ',0
read_fail: db 'Good read failed, AL CX: ',0
newline: db 13,10,0
evicted: db 'DENY evicted by BAD; NEXT kept',13,10,0
followup: db 'Regenerated read, closes, reopen OK; cache empty',13,10,0
age_kept: db 'Open age kept',13,10,0
age_lost: db 'OPEN AGE LOST',13,10,0
lru_fresh: db 'LRU fresh after failed I/O; free entry used',13,10,0
lru_stale: db 'LRU STALE after failed I/O',13,10,0
free_used: db 'DENY used the free entry; BAD kept',13,10,0
bad_evicted: db 'BAD EVICTED although an entry was free',13,10,0
verdict_pass: db 'FCBAGE PASS, exit ',0
verdict_fail: db 'FCBAGE FAIL, exit ',0
failed: db 'FCBAGE FAIL at step '
step: db '0',13,10,0
dma: times 128 db 0
