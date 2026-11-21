set pagination off
set confirm off
set environment SDL_VIDEODRIVER dummy
set environment SDL_AUDIODRIVER dummy
break *debug_harness_after_frame if $edi == 550
run
set $r = (unsigned short *)&upd9002_core_context
set $m = (unsigned char *)&mem
printf "prompt BCON=%04x:%04x\n", *(unsigned short *)($m+0x108e4), *(unsigned short *)($m+0x108e2)
break *upd9002_core_interrupt if $r[9] == 0x1000 && $r[13] == 0x0322
commands
silent
printf "hardware vector=%02x CS:IP=%04x:%04x SS:SP=%04x:%04x FLAGS=%04x saved_SS:SP=%04x:%04x\n", $edi, $r[9], $r[13], $r[10], $r[4], $r[12], *(unsigned short *)($m+0x100e5), *(unsigned short *)($m+0x100e3)
disable 2
continue
end
break *debug_harness_after_frame if $edi == 1400 || $edi == 1403 || $edi == 1410 || $edi == 1800
commands
silent
printf "frame=%d BCON=%04x:%04x CS:IP=%04x:%04x SS:SP=%04x:%04x FLAGS=%04x IF=%d\n", $edi, *(unsigned short *)($m+0x108e4), *(unsigned short *)($m+0x108e2), $r[9], $r[13], $r[10], $r[4], $r[12], ($r[12]>>9)&1
if $r[9] == 0x1ff0
x/16hx $m + ($r[10]*16+$r[4])
x/12bx $m + ($r[9]*16+$r[13])
end
continue
end
continue
