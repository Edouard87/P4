    addi a1, x0, 5
    addi a2, x0, 6
    bne a1, a2, anotherThing
    addi a1, x0, 7
    addi a1, x0, 8
anotherThing:
    mul a3, a1, a2
    sub a4, a1, a2
stop:
    j stop