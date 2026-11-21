; J2a output probe (COM, 8086); no Japanese keyboard input required.
; W wrap, S split writes, I malformed/single bytes, C lead before CLS,
; R VA-only ESC fallback; P VA-only raw text BIOS; G VA-only gaiji.
; Assemble with nasm -f bin.
        cpu 8086
        org 100h
        cmp byte [80h], 2
        jb exit
        mov al, [82h]
        and al, 0dfh
        cmp al, 'W'
        je wrap
        cmp al, 'S'
        je split
        cmp al, 'I'
        je invalid
        cmp al, 'C'
        je clear
        cmp al, 'R'
        je replay
        cmp al, 'P'
        je native
        cmp al, 'G'
        jne exit
        jmp gaiji
exit:   mov ax, 4c00h
        int 21h

wrap:   mov dx, edge
        mov cx, edge_end - edge
        call write
        jmp short exit

split:  mov dx, prefix02
        call dollar
        mov dl, 95h
        call byteout
        mov dl, 5ch
        call byteout
        mov dx, prefix40
        call dollar
        mov dx, pair
        mov cx, 1
        call write
        mov dx, pair+1
        mov cx, 1
        call write
        mov dx, tail
        call dollar
        jmp short exit

invalid:
        mov dx, cases
        mov cx, cases_end - cases
        call write
        jmp short exit

clear:  mov dx, cls
        mov cx, cls_end - cls
        call write
        jmp short exit

replay: mov dx, mismatch
        mov cx, mismatch_end - mismatch
        call write
        jmp short exit

native: mov dx, chu_label
        call dollar
        mov di, native_codes
.chu:   mov dx, [di]
        xor ah, ah
        call textbios
        add di, 2
        cmp di, native_end
        jb .chu
        mov dx, put_label
        call dollar
        mov si, native_string
        mov dx, 8000h
        mov ah, 2
        call textbios
        mov dx, tail
        call dollar
        jmp exit

; Test-only font registration for the first ordinary RAM gaiji at JIS 7621.
; Wait for a capture, then restore the original full-width bitmap.
gaiji:  push ds
        pop es
        mov bp, oldfont
        mov dx, 0eb9fh
        mov ah, 23h
        call textbios
        mov bp, testfont
        mov dx, 0eb9fh
        mov ax, 2100h
        call textbios
        mov dx, gaiji_label
        call dollar
        mov dx, 0eb9fh
        xor ah, ah
        call textbios
        mov dx, gaiji_text
        call dollar
        mov ah, 7
        int 21h
        push ds
        pop es
        mov bp, oldfont
        mov dx, 0eb9fh
        mov ax, 2100h
        call textbios
        jmp exit

textbios:
        push ds
        push es
        push si
        push di
        int 83h
        pop di
        pop si
        pop es
        pop ds
        ret
byteout:mov ah, 2
        int 21h
        ret
dollar: mov ah, 9
        int 21h
        ret
write:  mov bx, 1
        mov ah, 40h
        int 21h
        ret

edge:   db 13,10
        times 79 db 'A'
        db 95h,5ch,'Z',13,10
edge_end:
prefix02: db '02: $'
prefix40: db '!',13,10,'40: $'
pair:   db 83h,5ch
tail:   db '!',13,10,'$'
cases:
        db 'X-CR:',95h,13,'Z',13,10
        db 'X-LF:',95h,10,'Y',13,10
        db 'DEL:[',95h,7fh,'z]',13,10
        db 'LONE:[',5ch,']',13,10
        db 'HIGH:[',80h,'|',0a0h,'|',0a1h,'|',0b6h,'|',0dfh,'|',0fdh,'|',0feh,'|',0ffh,']',13,10
        db 'EXT:[',0ebh,40h,'|',0f0h,40h,'|',0fch,0fch,']',13,10
cases_end:
cls:    db 'MUST DISAPPEAR',95h,27,'[2J',27,'[H','CLS OK',13,10
cls_end:
mismatch: db 'REPLAY: ',27,'[>',95h,5ch,'!',13,10
mismatch_end:
chu_label: db 'Chuput: $'
put_label: db 13,10,'Putstr: $'
native_codes: dw '[',80h,'|',0a0h,'|',0a1h,'|',0b6h,'|',0dfh,'|',0fdh,'|',0feh,'|',0ffh,'|',0eb40h,'|',0f040h,'|',0fcfch,']'
native_end:
native_string: db '[',80h,'|',0a0h,'|',0a1h,'|',0b6h,'|',0dfh,'|',0fdh,'|',0feh,'|',0ffh,'|',0ebh,40h,'|',0f0h,40h,'|',0fch,0fch,']',0
gaiji_label: db 'Chuput: $'
gaiji_text: db ' / CON: ',0ebh,9fh,'!',13,10,'$'
oldfont: times 32 db 0
testfont:
        dw 0,0,0ffffh,08001h,04002h,02004h,01008h,00810h
        dw 00420h,00240h,00180h,00180h,00240h,00420h,0ffffh,0
