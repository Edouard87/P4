-- Inputs:
--   operand_a  : 32-bit first operand  (typically rs1 or PC)
--   operand_b  : 32-bit second operand (typically rs2 or immediate)
--   alu_ctrl   : 4-bit control word selecting the operation
--
-- Outputs:
--   result     : 32-bit ALU result
--   zero       : high when result = 0 (used by branch logic)
--   negative   : high when result(31) = 1 (signed MSB, used by branch logic)
--
-- ALU Control Encoding (defined in alu_ctrl_pkg):
--   0000  ADD    result = a + b           (add, addi, lw, sw, jalr, auipc)
--   0001  SUB    result = a - b           (sub, beq/bne/blt/bge compare)
--   0010  MUL    result = a * b (low 32)  (mul)
--   0011  OR     result = a | b           (or, ori)
--   0100  AND    result = a & b           (and, andi)
--   0101  XOR    result = a ^ b           (xori ? xor is a VHDL reserved word)
--   0110  SLL    result = a << b[4:0]     (sll)
--   0111  SRL    result = a >> b[4:0]     (logical, srl)
--   1000  SRA    result = a >>> b[4:0]    (arithmetic, sra)
--   1001  SLT    result = 1 if a < b (signed)   (slti)
--   1010  LUI    result = b               (lui ? pass upper-immediate through)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--Constants
package alu_ctrl_pkg is
    constant ALU_ADD  : std_logic_vector(3 downto 0) := "0000";
    constant ALU_SUB  : std_logic_vector(3 downto 0) := "0001";
    constant ALU_MUL  : std_logic_vector(3 downto 0) := "0010";
    constant ALU_OR   : std_logic_vector(3 downto 0) := "0011";
    constant ALU_AND  : std_logic_vector(3 downto 0) := "0100";
    constant ALU_XOR  : std_logic_vector(3 downto 0) := "0101";
    constant ALU_SLL  : std_logic_vector(3 downto 0) := "0110";
    constant ALU_SRL  : std_logic_vector(3 downto 0) := "0111";
    constant ALU_SRA  : std_logic_vector(3 downto 0) := "1000";
    constant ALU_SLT  : std_logic_vector(3 downto 0) := "1001";
    constant ALU_LUI  : std_logic_vector(3 downto 0) := "1010";
end package alu_ctrl_pkg;

--Entity
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_ctrl_pkg.all;

entity alu is
    port (
        operand_a  : in  std_logic_vector(31 downto 0);  -- rs1 (or PC for auipc/jal)
        operand_b  : in  std_logic_vector(31 downto 0);  -- rs2 or immediate
        alu_ctrl   : in  std_logic_vector(3  downto 0);  -- operation select

        result     : out std_logic_vector(31 downto 0);  -- ALU output
        zero       : out std_logic;                       -- result == 0
        negative   : out std_logic                        -- result(31) (signed MSB)
    );
end entity alu;


architecture rtl of alu is

    signal result_int : std_logic_vector(31 downto 0);

    -- Signed and unsigned views of inputs (needed for SLT, SRA, MUL)
    signal a_signed   : signed(31 downto 0);
    signal b_signed   : signed(31 downto 0);
    signal a_unsigned : unsigned(31 downto 0);
    signal b_unsigned : unsigned(31 downto 0);

    -- Shift amount is always the lower 5 bits of operand_b
    signal shamt      : natural range 0 to 31;

    -- 64-bit product for MUL (we keep the low 32 bits per RV32I M-extension)
    signal mul_result : signed(63 downto 0);

begin

    -- Type casts (combinational, no logic cost)
    a_signed   <= signed(operand_a);
    b_signed   <= signed(operand_b);
    a_unsigned <= unsigned(operand_a);
    b_unsigned <= unsigned(operand_b);
    shamt      <= to_integer(unsigned(operand_b(4 downto 0)));
    mul_result <= a_signed * b_signed;

    -- -------------------------------------------------------------------------
    -- Main ALU operation select
    -- -------------------------------------------------------------------------
    alu_proc : process(alu_ctrl, operand_a, operand_b,
                       a_signed, b_signed, a_unsigned, b_unsigned,
                       shamt, mul_result)
    begin
        case alu_ctrl is

            -- ADD: a + b
            -- Used by: add, addi, lw (addr calc), sw (addr calc),
            --          jalr (target addr), auipc (PC + imm)
            when ALU_ADD =>
                result_int <= std_logic_vector(a_unsigned + b_unsigned);

            -- SUB: a - b
            -- Used by: sub
            -- Also driven by branch comparator in control unit (beq, bne, blt, bge)
            when ALU_SUB =>
                result_int <= std_logic_vector(a_unsigned - b_unsigned);

            -- MUL: a * b (low 32 bits, signed × signed per RV32M)
            -- Used by: mul
            when ALU_MUL =>
                result_int <= std_logic_vector(mul_result(31 downto 0));

            -- OR: a | b
            -- Used by: or, ori
            when ALU_OR =>
                result_int <= operand_a or operand_b;

            -- AND: a & b
            -- Used by: and, andi
            when ALU_AND =>
                result_int <= operand_a and operand_b;

            -- XOR: a ^ b
            -- Used by: xori
            when ALU_XOR =>
                result_int <= operand_a xor operand_b;

            -- SLL: logical left shift by shamt
            -- Used by: sll
            when ALU_SLL =>
                result_int <= std_logic_vector(shift_left(a_unsigned, shamt));

            -- SRL: logical right shift by shamt (zero-fills from MSB)
            -- Used by: srl
            when ALU_SRL =>
                result_int <= std_logic_vector(shift_right(a_unsigned, shamt));

            -- SRA: arithmetic right shift by shamt (sign-extends from MSB)
            -- Used by: sra
            when ALU_SRA =>
                result_int <= std_logic_vector(shift_right(a_signed, shamt));

            -- SLT: set if a < b (signed comparison)
            -- Used by: slti
            -- Returns 1 if a_signed < b_signed, else 0
            when ALU_SLT =>
                if a_signed < b_signed then
                    result_int <= (0 => '1', others => '0');  -- 32'b1
                else
                    result_int <= (others => '0');             -- 32'b0
                end if;

            -- LUI: pass operand_b straight through
            -- The immediate (already shifted to [31:12] by the decode stage)
            -- is written directly into rd with no arithmetic.
            -- Used by: lui
            when ALU_LUI =>
                result_int <= operand_b;

            -- Undefined encodings
            when others =>
                result_int <= (others => '0');

        end case;
    end process alu_proc;

    --Output assignments
    result   <= result_int;
    zero     <= '1' when result_int = x"00000000" else '0';
    negative <= result_int(31);

end architecture rtl;