transcript on

if {![file exists work]} {
    vlib work
}

vmap work work

vcom alu.vhd
vcom memory.vhd
vcom register_file.vhd
vcom immediate_gen.vhd
vcom control_unit.vhd
vcom hazard_unit.vhd
vcom datapath.vhd
vcom cpu.vht

vsim work.cpu_tb

# Add Waves

add wave sim:/cpu_tb/clk
add wave sim:/cpu_tb/reset
add wave sim:/cpu_tb/dp/imem_addr
add wave sim:/cpu_tb/dp/imem_read 
add wave sim:/cpu_tb/dp/imem_waitrequest
add wave -divider Data
add wave sim:/cpu_tb/dp/exmem_mem_waitrequest
add wave sim:/cpu_tb/dp/mem_read_data 
add wave sim:/cpu_tb/dp/memwb_mem_data
add wave sim:/cpu_tb/dp/memwb_reg_write 
add wave sim:/cpu_tb/dp/dmem_addr
add wave sim:/cpu_tb/dp/dmem_stall 
add wave sim:/cpu_tb/dp/exmem_rs2_data
add wave sim:/cpu_tb/dp/memwb_rd
add wave sim:/cpu_tb/dp/ex_operand_a 
add wave sim:/cpu_tb/dp/ex_operand_b

add wave sim:cpu_tb/dp/pc_write
add wave sim:cpu_tb/dp/if_id_write
add wave sim:cpu_tb/dp/id_ex_flush 

add wave -divider RS2
add wave sim:/cpu_tb/dp/id_rs2_data
add wave sim:/cpu_tb/dp/idex_rs2_data
add wave sim:/cpu_tb/dp/exmem_rs2_data

add wave -divider IF
add wave -hex sim:/cpu_tb/dp/pc_reg
add wave -hex sim:/cpu_tb/dp/if_instruction

add wave -divider EX
add wave -hex sim:/cpu_tb/dp/ex_alu_result

add wave -divider WB
add wave -hex sim:/cpu_tb/dp/wb_data

add wave -divider IMEM

set program_file "program.txt"

if {![file exists $program_file]} {
    error "Program file not found: $program_file"
}

set fh [open $program_file r]
set lines [split [read $fh] "\n"]
close $fh

set instr_index 0

foreach raw_line $lines {
    set line [string trim $raw_line]

    if {$line eq ""} {
        continue
    }

    if {![regexp {^[01]{32}$} $line]} {
        error "Invalid machine-code line at instruction $instr_index: $line"
    }

    set base_addr [expr {$instr_index * 4}]

    set byte3 [string range $line 0 7]
    set byte2 [string range $line 8 15]
    set byte1 [string range $line 16 23]
    set byte0 [string range $line 24 31]

    # Force the signals after the RAM was initialized to zeroes so that the program doesn't
    # get squished by the init values (hence the 10 ps delay on these force commands). 
    force -deposit sim:/cpu_tb/dp/IMEM/ram_block\($base_addr\) 2#$byte0 10 ps
    force -deposit sim:/cpu_tb/dp/IMEM/ram_block\([expr {$base_addr + 1}]\) 2#$byte1 10 ps
    force -deposit sim:/cpu_tb/dp/IMEM/ram_block\([expr {$base_addr + 2}]\) 2#$byte2 10 ps
    force -deposit sim:/cpu_tb/dp/IMEM/ram_block\([expr {$base_addr + 3}]\) 2#$byte3 10 ps

    incr instr_index
}

echo "Loaded $instr_index instruction(s) from $program_file"

# Reset signal for one clock cycle.
force -deposit sim:/cpu_tb/reset 1 0 ns, 0 1 ns

# Run for the required amount of time.
run 10000 ns

# Dump Register File Contents.
if {![info exists reg_index_start]} {
    set reg_index_start 0
}

set reg_dump_file "register_file.txt"
set reg_fh [open $reg_dump_file w]

for {set i $reg_index_start} {$i < 32} {incr i} {
    set reg_value [examine -radix binary sim:/cpu_tb/dp/RF/registers\($i\)]
    puts $reg_fh $reg_value
}

close $reg_fh
echo "Wrote register file contents to $reg_dump_file"

# Dump Data Memory Contents.
if {![info exists no_memory_dump]} {
    set no_memory_dump 0
}

if {$no_memory_dump == 0} {
    # We want dumping!
    set mem_dump_file "memory.txt"
    set mem_fh [open $mem_dump_file w]
    set mem_size 32768

    for {set addr 0} {$addr < $mem_size} {incr addr 4} {
        set byte0 [examine -radix binary sim:/cpu_tb/dp/DMEM/ram_block\($addr\)]
        set byte1 [examine -radix binary sim:/cpu_tb/dp/DMEM/ram_block\([expr {$addr + 1}]\)]
        set byte2 [examine -radix binary sim:/cpu_tb/dp/DMEM/ram_block\([expr {$addr + 2}]\)]
        set byte3 [examine -radix binary sim:/cpu_tb/dp/DMEM/ram_block\([expr {$addr + 3}]\)]
        puts $mem_fh "${byte3}${byte2}${byte1}${byte0}"
    }

    close $mem_fh
    echo "Wrote data memory contents to $mem_dump_file"
}


