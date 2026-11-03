set_device -device_version C GW5AST-LV138PG484AC1/I0

add_file src/btn_debounce.v
add_file src/note_allocator_fixed.v
add_file src/a_b_adapter.v
add_file src/rom_wave_sine.v
add_file src/dds_multi.v
add_file src/adsr_event.v
add_file src/voice_lut.v
add_file src/synth_evt.v
add_file src/fx_chain_full.v
add_file src/audio_drive.v
add_file src/top_fx.v
add_file src/ip/gowin_osc.v
add_file src/ip/gowin_pll.v
add_file src/ip/gowin_clkdiv.v
add_file constraints/top.cst

set_option -top_module top_fx
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1

run syn
run pnr
exit
