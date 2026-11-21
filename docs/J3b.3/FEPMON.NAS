; Exercise the backend inside DOS buffered CON input, with the monitor
; installed. The runner supplies the reading, editing keys and two Returns.
cpu 8086
org 100h
    call install
    mov dx,ready
    mov ah,9
    int 21h
    mov dx,line
    mov ah,0ah
    int 21h
    call check_off
    call uninstall
    mov si,line+2
    xor bx,bx
    mov bl,[line+1]
    mov byte [si+bx],'$'
    mov dx,line+2
    mov ah,9
    int 21h
    mov dx,newline
    mov ah,9
    int 21h
    call report
    mov ax,4c00h
    int 21h

line db 80,0
     times 80 db 0
ready db 'MON READY',13,10,'$'
%include 'MONITOR.INC'
