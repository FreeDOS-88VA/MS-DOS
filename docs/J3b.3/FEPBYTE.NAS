; Converted-byte/status/flush test, with the same monitor as FEPMON.
; At FIRST type ZENKAKU, NIHONGO, HENKAN, KETTEI. At PENDING convert
; NIHONGO and hold Shift to trigger a flush without a data key. At SECOND
; convert/confirm NIHONGO again. At FLUSHED convert KANJI, then edit
; with A and confirm (no width toggle).
cpu 8086
org 100h
    call install
    mov dx,first
    call print
    call empty
.wait:
    call status
    jz .wait
    call ready
    call direct
    jz fail
    cmp al,[expected]
    jne fail
    mov si,expected+1
.sequence:
    call ready
    call ready
    mov ah,07h
    int 21h
    cmp al,[si]
    jne fail
    inc si
    cmp si,expected_end
    jb .sequence
    call empty
    call direct
    jnz fail
    mov dx,pending
    call print
.pending:
    call empty                 ; The candidate is not ready until confirmed.
    mov ah,0bh
    int 82h
    test al,3
    jz .pending
    call flush
    mov dx,second
    call print
    mov ah,07h
    int 21h
    cmp al,[expected]
    jne fail
    call ready                 ; Cache the trail, then discard it too.
    call flush
    mov dx,flushed
    call print
    mov si,edited
.edited_sequence:
    mov ah,07h
    int 21h
    cmp al,[si]
    jne fail
    inc si
    cmp si,edited_end
    jb .edited_sequence
    call empty
    call check_off
    call uninstall
    call report
    mov dx,passed
    call print
    mov ax,4c00h
    int 21h
ready:
    call status
    cmp al,0ffh
    jne fail
    ret
empty:
    call status
    jnz fail
    ret
status:
    mov ah,0bh
    int 21h
    or al,al
    ret
direct:
    mov ah,06h
    mov dl,0ffh
    int 21h
    ret
flush:
    mov ax,0c06h
    mov dl,0ffh
    int 21h
    jnz fail
    jmp short empty
print:
    mov ah,9
    int 21h
    ret
fail:
    call uninstall
    call report
    mov dx,failed
    call print
    mov ax,4c01h
    int 21h

expected db 93h,0fah,96h,7bh,8ch,0eah ; 日本語, the gate's typed fixture.
expected_end:
edited db 82h,0a9h,82h,0f1h,82h,0b6h,82h,0a0h ; かんじあ
edited_end:
first db 'FIRST',13,10,'$'
pending db 'PENDING',13,10,'$'
second db 'SECOND',13,10,'$'
flushed db 'FLUSHED',13,10,'$'
passed db 'PASS: FEP status, bytes and flush',13,10,'$'
failed db 'FAIL: FEP byte test',13,10,'$'
%include 'MONITOR.INC'
