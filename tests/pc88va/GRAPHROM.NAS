; nasm -f bin GRAPHROM.NAS -o GRAPHROM.COM
; GRAPHROM: direct VA INT 83h Litout with DH=0.
; GRAPHROM N: DOS CON AH=02h after ESC )3; Space steps through label
; hide/show and ESC )0. The final page verifies that the pair is kanji again.
org 100h
cpu 8086
bits 16

%macro send 1+
    mov dx, %%data
    mov cx, %%end-%%data
    mov bx, 1
    mov ah, 40h
    int 21h
    jmp short %%end
%%data: db %1
%%end:
%endmacro

    mov al,[82h]
    and al,0dfh
    cmp al,'N'
    jne .va
    inc byte [dos]
    send 27,'[>1l',27,'[2J',27,')3','DOS CON graph',13,10
    jmp short .table
.va:
    send 27,'[>1l',27,'[2J','VA ROM Litout (single byte)',13,10
.table:
    send '80-8F '
    mov dl,80h
    call glyphs
    send 13,10,'90-9F '
    mov dl,90h
    call glyphs
    send 13,10,'E0-EF '
    mov dl,0e0h
    call glyphs
    send 13,10,'F0-FF '
    mov dl,0f0h
    call glyphs
    send 13,10,'95 5C '
    mov dl,95h
    call output
    mov dl,5ch
    call output
    send '|',13,10,'Space to continue',13,10
    call pause
    cmp byte [dos],0
    je quit
    send 27,'[>1h','LABELS HIDDEN',13,10
    call pause
    send 27,'[>1l','LABELS SHOWN',13,10
    call pause
    send 27,'[>1h',27,')0',27,'[>1l','KANJI: ',95h,5ch,'|',13,10
    call pause
quit:
    mov ax,4c00h
    int 21h

pause:
    mov ah,08h
    int 21h
    cmp al,' '
    jne pause
    ret

glyphs:
    mov cx,16
.next:
    push dx
    push cx
    call output
    mov dl,'|'
    call output
    pop cx
    pop dx
    inc dl
    loop .next
    ret

output:
    cmp byte [dos],0
    je .literal
    mov ah,02h
    int 21h
    ret
.literal:
    xor dh,dh
    mov ah,01h
    int 83h
    ret

dos: db 0
