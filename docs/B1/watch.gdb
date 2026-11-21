set pagination off
set confirm off
set environment SDL_VIDEODRIVER dummy
set environment SDL_AUDIODRIVER dummy
break *debug_harness_after_frame if $edi == 550
run
set $r = (unsigned short *)&upd9002_core_context
set $m = (unsigned char *)&mem
x/8hx $m + 0x108e0
watch -l *(unsigned int *)($m+0x108e2)
continue
printf "CS:IP=%04x:%04x SS:SP=%04x:%04x FLAGS=%04x\n", $r[9],$r[13],$r[10],$r[4],$r[12]
print/x *(unsigned short *)&upd9002_step_start_cs
print/x *(unsigned short *)&upd9002_step_start_ip
bt 12
