; Gate-only monitor for JFP functions 03h..0Ah. Install from a COM before
; entering DOS input. Run with no TSRs and no Ctrl-Break/Ctrl-C taps.
; Scope counters to time inside the chained firmware call, not the outer
; DOS call or the VAIO painter. A nested INT 21h is counted AND blocked.
%macro vector 3
    mov ax,%1 + 3500h
    int 21h
    mov [%2],bx
    mov [%2+2],es
    mov dx,%3
    mov ax,%1 + 2500h
    int 21h
%endmacro
%macro restore 2
    lds dx,[%2]
    mov ax,%1 + 2500h
    int 21h
    push cs
    pop ds
%endmacro
install:
    vector 21h,old21,hook21
    vector 83h,old83,hook83
    vector 8dh,old8d,hook8d
    ; Positive control: both chains must see an interrupt in scope. The
    ; INT 21h request is harmless even if the hook failed to install.
    mov byte [active],1
    mov ah,30h
    int 21h
    mov ah,26h
    int 83h
    mov byte [active],0
    cmp word [dos],1
    jne .bad
    cmp word [text],1
    jne .bad
    mov word [dos],0
    mov word [text],0
    call check_off
    ret
.bad:
    call uninstall
    mov dx,selftest
    mov ah,9
    int 21h
    mov ax,4c02h
    int 21h

check_off:
    xor cx,cx
    int 8dh                      ; GetJFP, outside the measured scope.
    cmp ax,8f80h
    jne .bad
    ret
.bad:
    call uninstall
    mov dx,badmode
    mov ah,9
    int 21h
    mov ax,4c03h
    int 21h

uninstall:
    restore 8dh,old8d
    restore 83h,old83
    restore 21h,old21
    ret

hook21:
    pushf
    cmp byte [cs:active],0
    jne .nested
    popf
    jmp far [cs:old21]
.nested:
    inc word [cs:dos]
    popf
    push bp
    mov bp,sp
    or word [ss:bp+6],1
    pop bp
    mov ax,5
    iret

hook83:
    pushf
    cmp byte [cs:active],0
    je .chain
    inc word [cs:text]
.chain:
    popf
    jmp far [cs:old83]

hook8d:
    pushf
    cmp cl,3
    jb .chain
    cmp cl,0ah
    ja .chain
    push bx
    xor bx,bx
    mov bl,cl
    shl bx,1
    inc word [cs:calls+bx-6]
    pop bx
    inc byte [cs:active]
    popf
    ; Construct the interrupt frame for the old handler using the
    ; interrupted caller's FLAGS. Return its result flags to our caller.
    push bp
    mov bp,sp
    push word [ss:bp+6]
    mov bp,[ss:bp]
    call far [cs:old8d]
    pushf
    dec byte [cs:active]
    popf
    pop bp
    retf 2
.chain:
    popf
    jmp far [cs:old8d]

report:
    mov dx,summary
    mov ah,9
    int 21h
    mov si,calls
    mov cx,10
    cld
.word:
    lodsw
    push cx
    mov cx,4
.nibble:
    rol ax,1
    rol ax,1
    rol ax,1
    rol ax,1
    mov dl,al
    and dl,0fh
    add dl,'0'
    cmp dl,'9'
    jbe .digit
    add dl,7
.digit:
    push ax
    mov ah,2
    int 21h
    pop ax
    loop .nibble
    mov dl,' '
    mov ah,2
    int 21h
    pop cx
    loop .word
    mov dx,newline
    mov ah,9
    int 21h
    ret

old21 dd 0
old83 dd 0
old8d dd 0
active db 0
calls times 8 dw 0
dos dw 0
text dw 0
summary db 'MON: $'          ; 03..0A, nested INT 21h, nested INT 83h (hex words).
newline db 13,10,'$'
selftest db 'FAIL: monitor positive control',13,10,'$'
badmode db 'FAIL: ROM JFP not master-disabled',13,10,'$'
