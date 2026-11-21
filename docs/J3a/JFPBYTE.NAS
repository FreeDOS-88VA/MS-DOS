; Test DOS CON byte delivery in ROM JFP mode. No firmware access here.
; Wait for FIRST, enter and confirm nihon; repeat at SECOND. After FLUSHED,
; toggle back to narrow and type x. No keystroke may remain after each stage.
cpu 8086
org 100h
    jmp start

start:
    mov ax,3521h
    int 21h
    mov [old21],bx
    mov [old21+2],es
    mov ax,2521h
    mov dx,monitor
    int 21h
    mov dx,first
    call print
    mov si,expected
.read:
    call read
    cmp al,[si]
    jne fail
    inc si
    cmp si,expected+4
    je .done
    call ready
    call ready
    jmp short .read
.done:
    call empty
    mov dx,second
    call print
    call read
    cmp al,93h
    jne fail
    call ready
    mov ax,0c06h
    mov dl,0ffh
    int 21h
    jnz fail
    call empty
    mov dx,flushed
    call print
    call read
    cmp al,'x'
    jne fail
    call empty
    cmp byte [file_calls],0
    jne fail
    call unhook
    mov dx,passed
    call print
    mov ax,4c00h
    int 21h

read:
    mov ah,7
    int 21h
    ret
ready:
    mov ah,0bh
    int 21h
    cmp al,0ffh
    jne fail
    ret
empty:
    mov ah,0bh
    int 21h
    or al,al
    jnz fail
    ret
print:
    mov ah,9
    int 21h
    ret
fail:
    call unhook
    mov dx,failed
    call print
    mov ax,4c01h
    int 21h

unhook:
    push ds
    lds dx,[old21]
    mov ax,2521h
    int 21h
    pop ds
    ret
monitor:
    pushf
    cmp ah,3ch                   ; File create/open/close/read/write/seek.
    jb .chain
    cmp ah,42h
    ja .chain
    mov byte [cs:file_calls],1
.chain:
    popf
    jmp far [cs:old21]

old21 dd 0
file_calls db 0
expected db 93h,0fah,96h,7bh
first db 'FIRST',13,10,'$'
second db 'SECOND',13,10,'$'
flushed db 'FLUSHED',13,10,'$'
passed db 'PASS: JFP bytes, status and flush',13,10,'$'
failed db 'FAIL: JFP byte test',13,10,'$'
