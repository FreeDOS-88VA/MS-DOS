; Scratch feasibility probe, not a DOS CON regression test.
; Assemble to ROMROWS.COM and run on the J2c graph build with labels shown.
; Capture at each of three Space prompts: Crtctl alone, 19+1, then 24+1.
org 100h
bits 16
cpu 8086
    mov ax,2414h          ; CRT 80 columns, 20 rows
    int 83h
    call pause
    mov bp,layout20
    call split
    mov dx,3b12h          ; 20-row mode: physical row 19, column 60
    call marker
    call pause
    mov ax,2404h          ; CRT 80 columns, 25 rows
    int 83h
    mov bp,layout25
    call split
    mov dx,3b17h          ; 25-row mode: physical row 24, column 60
    call marker
    call pause
    mov ax,4c00h
    int 21h
split:
    push cs
    pop es
    mov ax,1d00h
    mov cx,2
    int 83h
    jc fail
    mov ax,2f0ah
    int 83h
    jc fail
    ret
marker:
    mov ah,08h
    int 83h
    mov ax,0500h
    mov dx,70h
    int 83h
    mov ax,0100h
    mov dx,'R'
    int 83h
    ret
pause:
    mov ah,08h
    int 21h
    cmp al,' '
    jne pause
    ret
fail:
    mov ax,4c01h
    int 21h
layout20: db 00h,0,0,0,19,11h,07h,0, 41h,0,0,0,1,10h,07h,0
layout25: db 00h,0,0,0,24,11h,07h,0, 41h,0,0,0,1,10h,07h,0
