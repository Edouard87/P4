--Immediate value generator

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity immediate_gen is
    port (
        instruction : in  std_logic_vector(31 downto 0);
        imm_out     : out std_logic_vector(31 downto 0)
    );
end entity immediate_gen;

architecture rtl of immediate_gen is
    -- Opcode field
    alias opcode : std_logic_vector(6 downto 0) is instruction(6 downto 0);
begin

    process(instruction, opcode)
    begin
        case opcode is

            -- I-type: addi, xori, ori, andi, slti, lw, jalr
            -- imm = sign_extend( inst[31:20] )
            when "0010011" |   -- OP-IMM  (addi, xori, ori, andi, slti)
                 "0000011" |   -- LOAD    (lw)
                 "1100111" =>  -- JALR
                imm_out <= (31 downto 12 => instruction(31)) & instruction(31 downto 20);

            -- S-type: sw
            -- imm = sign_extend( inst[31:25] & inst[11:7] )
            when "0100011" =>  -- STORE
                imm_out <= (31 downto 12 => instruction(31))
                         & instruction(31 downto 25)
                         & instruction(11 downto 7);


            -- B-type: beq, bne, blt, bge
            -- imm = sign_extend( inst[31] & inst[7] & inst[30:25] & inst[11:8] & 0 )
            -- NLSB is always 0 (halfword aligned), not stored in instruction.
            when "1100011" =>  -- BRANCH
                imm_out <= (31 downto 13 => instruction(31))
                         & instruction(31)
                         & instruction(7)
                         & instruction(30 downto 25)
                         & instruction(11 downto 8)
                         & '0';

            -- U-type: lui, auipc
            -- imm = inst[31:12] & 12'b0   (already upper 20 bits, no sign ext needed)
            when "0110111" |   -- LUI
                 "0010111" =>  -- AUIPC
                imm_out <= instruction(31 downto 12) & (11 downto 0 => '0');

            -- J-type: jal
            -- imm = sign_extend( inst[31] & inst[19:12] & inst[20] & inst[30:21] & 0 )
            when "1101111" =>  -- JAL
                imm_out <= (31 downto 21 => instruction(31))
                         & instruction(31)
                         & instruction(19 downto 12)
                         & instruction(20)
                         & instruction(30 downto 21)
                         & '0';

            -- R-type: add, sub, mul, or, and, sll, srl, sra — no immediate
            -- Return zero; the ALU operand mux will select rs2 data instead.
            when others =>
                imm_out <= (others => '0');

        end case;
    end process;

end architecture rtl;