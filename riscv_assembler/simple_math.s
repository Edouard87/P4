main:
    addi a0, x0, 5
    addi a1, x0, 6
    add a2, a0, a1
    addi a3, a1, 7
    sub a3, a1, a2
    mul a4, a1, a2
    or a5, a1, a2
    and a6, a1, a2
    sll a7, a1, a2
    srl x18, a1, a2
    sra x19, a1, a2

stop:
    j stop
