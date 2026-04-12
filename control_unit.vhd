-- Control Unit
-- Decodes opcode (bits 6:0), funct3 (bits 14:12), funct7 (bits 31:25) and
-- produces all control signals needed by the datapath.
--
-- Output signals:
--   reg_write   : write result to register file in WB stage
--   mem_read    : read from data memory in MEM stage  (lw)
--   mem_write   : write to data memory in MEM stage   (sw)
--   branch      : instruction is a branch (beq/bne/blt/bge)
--   jump        : instruction is jal or jalr
--   alu_src     : 0 = operand_b is rs2,  1 = operand_b is immediate
--   wb_src      : 0 = write-back from ALU result
--                 1 = write-back from data memory
--                 2 = write-back from PC+4  (jal / jalr)
--   pc_src      : 0 = PC+4 (normal), 1 = branch/jump target (from EX stage)
--   alu_ctrl    : 4-bit ALU operation (see alu_ctrl_pkg)
--   is_jalr     : flag so the datapath knows to use rs1+imm as target, not PC+imm
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_ctrl_pkg.all;

entity control_unit is
    port (
        instruction : in  std_logic_vector(31 downto 0);

        -- Register file
        reg_write   : out std_logic;

        -- Memory
        mem_read    : out std_logic;
        mem_write   : out std_logic;

        -- PC / branch
        branch      : out std_logic;
        jump        : out std_logic;
        is_jalr     : out std_logic;

        -- ALU operand mux
        alu_src     : out std_logic;   -- 0 = rs2, 1 = immediate
        use_pc_a    : out std_logic;   -- 1 = use PC as operand_a  (auipc)

        -- Write-back source mux
        wb_src      : out std_logic_vector(1 downto 0);
            -- "00" = ALU result
            -- "01" = memory read data
            -- "10" = PC + 4  (link register for jal/jalr)

        -- ALU operation
        alu_ctrl    : out std_logic_vector(3 downto 0)
    );
end entity control_unit;

architecture rtl of control_unit is
    alias opcode : std_logic_vector(6 downto 0) is instruction(6 downto 0);
    alias funct3 : std_logic_vector(2 downto 0) is instruction(14 downto 12);
    alias funct7 : std_logic_vector(6 downto 0) is instruction(31 downto 25);
begin

    decode : process(instruction, opcode, funct3, funct7)
    begin
        reg_write  <= '0';
        mem_read   <= '0';
        mem_write  <= '0';
        branch     <= '0';
        jump       <= '0';
        is_jalr    <= '0';
        alu_src    <= '0';
        use_pc_a   <= '0';
        wb_src     <= "00";
        alu_ctrl   <= ALU_ADD;

        case opcode is

            -- R-type: add, sub, mul, or, and, sll, srl, sra
            when "0110011" =>
                reg_write <= '1';
                alu_src   <= '0';   -- operand_b = rs2
                wb_src    <= "00";  -- write ALU result
                case funct3 is
                    when "000" =>
                        if funct7 = "0000001" then
                            alu_ctrl <= ALU_MUL;   -- mul
                        elsif funct7 = "0100000" then
                            alu_ctrl <= ALU_SUB;   -- sub
                        else
                            alu_ctrl <= ALU_ADD;   -- add
                        end if;
                    when "110" => alu_ctrl <= ALU_OR;
                    when "111" => alu_ctrl <= ALU_AND;
                    when "001" => alu_ctrl <= ALU_SLL;
                    when "101" =>
                        if funct7 = "0100000" then
                            alu_ctrl <= ALU_SRA;
                        else
                            alu_ctrl <= ALU_SRL;
                        end if;
                    when others => alu_ctrl <= ALU_ADD;
                end case;

            -- I-type ALU: addi, xori, ori, andi, slti
            when "0010011" =>
                reg_write <= '1';
                alu_src   <= '1';   -- operand_b = immediate
                wb_src    <= "00";
                case funct3 is
                    when "000" => alu_ctrl <= ALU_ADD;  -- addi
                    when "100" => alu_ctrl <= ALU_XOR;  -- xori
                    when "110" => alu_ctrl <= ALU_OR;   -- ori
                    when "111" => alu_ctrl <= ALU_AND;  -- andi
                    when "010" => alu_ctrl <= ALU_SLT;  -- slti
                    when others => alu_ctrl <= ALU_ADD;
                end case;


            -- Load: lw

            when "0000011" =>
                reg_write <= '1';
                mem_read  <= '1';
                alu_src   <= '1';   -- address = rs1 + imm
                wb_src    <= "01";  -- write memory data
                alu_ctrl  <= ALU_ADD;

            -- Store: sw

            when "0100011" =>
                mem_write <= '1';
                alu_src   <= '1';   -- address = rs1 + imm
                alu_ctrl  <= ALU_ADD;


            -- Branch: beq, bne, blt, bge
            -- ALU computes rs1 - rs2; branch logic inspects zero/negative flags.

            when "1100011" =>
                branch   <= '1';
                alu_src  <= '0';    -- compare rs1, rs2
                alu_ctrl <= ALU_SUB;

            -- JAL

            when "1101111" =>
                reg_write <= '1';
                jump      <= '1';
                wb_src    <= "10";  -- rd = PC + 4
                alu_ctrl  <= ALU_ADD;  -- ALU computes PC + imm (branch adder used)

            -- JALR

            when "1100111" =>
                reg_write <= '1';
                jump      <= '1';
                is_jalr   <= '1';
                alu_src   <= '1';   -- target = rs1 + imm  (computed by ALU)
                wb_src    <= "10";  -- rd = PC + 4
                alu_ctrl  <= ALU_ADD;

            -- LUI

            when "0110111" =>
                reg_write <= '1';
                alu_src   <= '1';   -- operand_b = upper immediate
                wb_src    <= "00";
                alu_ctrl  <= ALU_LUI;

            -- AUIPC
            when "0010111" =>
                reg_write <= '1';
                alu_src   <= '1';   -- operand_b = upper immediate
                use_pc_a  <= '1';  -- operand_a = PC (not rs1)
                wb_src    <= "00";
                alu_ctrl  <= ALU_ADD;

            when others => null;  -- NOP / undefined: all signals stay at default

        end case;
    end process decode;

end architecture rtl;