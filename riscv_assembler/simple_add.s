main:
    addi a0, x0, 5
    addi a1, x0, 6
    add a2, a0, a1
    j stop

stop:
    j stop
