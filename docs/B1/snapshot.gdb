set pagination off
set confirm off
set environment SDL_VIDEODRIVER dummy
set environment SDL_AUDIODRIVER dummy
break *debug_harness_after_frame if $edi == 550 || $edi == 1400 || $edi == 1403 || $edi == 1410 || $edi == 1800
commands
silent
set $r = (unsigned short *)&upd9002_core_context
set $m = (unsigned char *)&mem
printf "frame=%d CS:IP=%04x:%04x SS:SP=%04x:%04x FLAGS=%04x IF=%d AX=%04x CX=%04x DX=%04x BX=%04x BP=%04x SI=%04x DI=%04x DS=%04x ES=%04x\n", $edi, $r[9], $r[13], $r[10], $r[4], $r[12], ($r[12]>>9)&1, $r[0], $r[1], $r[2], $r[3], $r[5], $r[6], $r[7], $r[11], $r[8]
x/16hx $m + ($r[10]*16 + $r[4])
continue
end
run
