; J3b.3 firmware monitor plus an outer DOS buffered-input scope. This
; also observes a software INT 21h made by project code outside INT 8Dh.
cpu 8086
org 100h
    jmp start
%include 'MONITOR.INC'

start:
    call install
    vector 21h,old_outer,hook_outer
    ; Positive control: fail a harmless DOS request outside INT 8Dh.
    mov byte [scope],2
    mov ax,3000h
    int 21h
    mov byte [scope],0
    jnc bad
    cmp ax,5
    jne bad
    cmp word [outer_dos],1
    jne bad
    mov word [outer_dos],0
    mov dx,ready
    mov ah,9
    int 21h
    mov dx,line
    mov ah,0ah
    mov byte [scope],1
    int 21h
    restore 21h,old_outer
    call check_off
    call uninstall
    mov bx,1
    xor cx,cx
    mov cl,[line+1]
    mov dx,line+2
    mov ah,40h
    int 21h
    mov dx,newline
    mov ah,9
    int 21h
    call report
    mov dx,outer_ok
    cmp word [outer_dos],0
    je print_exit
    mov dx,outer_fail
print_exit:
    mov ah,9
    int 21h
    xor al,al
    cmp word [outer_dos],0
    je exit
    inc al
exit:
    mov ah,4ch
    int 21h
bad:
    restore 21h,old_outer
    call uninstall
    mov dx,outer_bad
    mov ah,9
    int 21h
    mov ax,4c02h
    int 21h

hook_outer:
    pushf
    cmp byte [cs:scope],1
    je .enter
    cmp byte [cs:scope],2
    jne .chain
    inc word [cs:outer_dos]
    cmp byte [cs:active],0
    jne .chain                  ; Firmware hook also counts and blocks it.
    popf
    push bp
    mov bp,sp
    or word [ss:bp+6],1
    pop bp
    mov ax,5
    iret
.chain:
    popf
    jmp far [cs:old_outer]
.enter:
    mov byte [cs:scope],2
    popf
    push bp
    mov bp,sp
    push word [ss:bp+6]
    mov bp,[ss:bp]
    call far [cs:old_outer]
    mov byte [cs:scope],0
    pop bp
    retf 2

old_outer dd 0
outer_dos dw 0
scope db 0
line db 80,0
     times 80 db 0
ready db 'USER MON READY',13,10,'$'
outer_ok db 'OUTER INT 21h: zero (both controls passed)',13,10,'$'
outer_fail db 'OUTER INT 21h: nested call detected',13,10,'$'
outer_bad db 'OUTER INT 21h: positive control failed',13,10,'$'
