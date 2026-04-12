# VHDL Processor

Assuming you are running Linux/MacOS, begin by compiling a basic RISC-V machine code script using the assembler in `riscv_assembler` using the command:

```bash
$ python ./riscv_assembler/assembler.py ./riscv_assembler/simple_add.s program.txt
```

Ensure that `program.txt` is in the current directory. Now, open Modelsim and change the current directory to this directory. Once that is done, run the test script with:

```bash
$ source testbech.tcl 
```

This loads the program in `program.txt` into the processor's memory, waits 10,000 clock cycles, and outputs the contents of the registers in `register_file.txt` and the output of the processor's data memory in `memory.txt`. 

Note that the `memory.txt` file has a line for every 32-bit word in data memory. Generating this file may take some time. To skip this step, set `no_memory_dump` to 1:

```bash
$ set no_memory_dump 1
$ source testbench.tcl
```

Also, the script outputs the contents of all registers into `register_file.txt`, including `x0`, which always has a value of zero. If you pefer to specify the register you want to start at, you can set `reg_index_start`:

```bash
$ set reg_index_start 1
$ source testbench.tcl
```
