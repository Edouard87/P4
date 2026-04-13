main:
    # Load random data in memory
    addi a1, x0, 8
    addi a2, x0, 5
    sw a2, 0(a1)
    # Do rome random stuff
    slti a3, a2 10
    # Load a word from memory
    lw a4, 0(a1)

stop:
    j stop