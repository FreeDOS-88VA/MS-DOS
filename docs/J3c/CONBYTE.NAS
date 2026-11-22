; Same INT 21h CON test for ROM and FEP. FIRST: convert/confirm nihongo.
; PENDING: convert but don't confirm; hold Shift to cause a flush.
; SECOND: convert/confirm again, peek and flush the cached trail.
; FLUSHED: type/confirm A in the retained kana width.
cpu 8086
org 100h
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
    call empty
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
    call ready
    call flush
    mov dx,flushed
    call print
    mov ah,07h
    int 21h
    cmp al,82h
    jne fail
    call ready
    mov ah,07h
    int 21h
    cmp al,0a0h
    jne fail
    call empty
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
    mov dx,failed
    call print
    mov ax,4c01h
    int 21h
expected db 93h,0fah,96h,7bh,8ch,0eah ; 日本語, typed fixture
expected_end:
first db 'FIRST',13,10,'$'
pending db 'PENDING',13,10,'$'
second db 'SECOND',13,10,'$'
flushed db 'FLUSHED',13,10,'$'
passed db 'PASS: CON status, bytes and flush',13,10,'$'
failed db 'FAIL: CON byte test',13,10,'$'
