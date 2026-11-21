; DOS byte/status/flush test. Send ZENKAKU, NIHONGO, KETTEI at FIRST.
; At PENDING type SHI, then hold Shift to signal a flush without a data key.
; At SECOND type NIHONGO, KETTEI again. At FLUSHED type A, KETTEI (no toggle).
cpu 8086
org 100h
    mov dx,first
    call print
    call empty
.wait:
    call status
    jz .wait
    call ready                  ; Repeated peeks must not advance a byte.
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
    jnz fail                    ; KETTEI must not queue a CR or a space.
    mov dx,pending
    call print
.pending:
    call empty                  ; Pending reading must never report ready.
    mov ah,0bh                  ; Primitive Shift state, not a CON byte.
    int 82h
    test al,3
    jz .pending
    call flush
    mov dx,second
    call print
    mov ah,07h
    int 21h
    cmp al,82h
    jne fail
    call ready                  ; At least one trail remains to discard.
    call flush
    mov dx,flushed
    call print
    mov ah,07h
    int 21h
    cmp al,82h
    jne fail
    call ready
    call direct
    jz fail
    cmp al,0a0h                 ; A still entered kana after both flushes.
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

expected db 82h,0c9h,82h,0d9h,82h,0f1h,82h,0b2h
expected_end:
first db 'FIRST',13,10,'$'
pending db 'PENDING',13,10,'$'
second db 'SECOND',13,10,'$'
flushed db 'FLUSHED',13,10,'$'
passed db 'PASS: FEP status, bytes and flush',13,10,'$'
failed db 'FAIL: FEP byte test',13,10,'$'
