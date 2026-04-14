-- Hazard Detection Unit
--
-- Stalls whenever an instruction in ID reads a register that has not yet
-- been written back.  Without forwarding, a producing instruction must reach
-- WB before the consuming instruction can enter EX.
--
-- Hazard sources tracked:
--   ID/EX  stage producer  (instruction in EX)  -> WB is 2 cycles away
--   EX/MEM stage producer  (instruction in MEM) -> WB is 1 cycle away
--   MEM/WB stage producer
--
-- A stall is inserted by:
--   pc_write    = '0'  -> freeze PC
--   if_id_write = '0'  -> freeze IF/ID register
--   id_ex_flush = '1'  -> inject NOP bubble into ID/EX
--
-- The stall condition is re-evaluated every cycle

library ieee;
use ieee.std_logic_1164.all;

entity hazard_unit is
    port (
        -- ID/EX producer (instruction currently in EX stage)
        idex_reg_write  : in  std_logic;
        idex_rd         : in  std_logic_vector(4 downto 0);

        -- EX/MEM producer (instruction currently in MEM stage)
        exmem_reg_write : in  std_logic;
        exmem_rd        : in  std_logic_vector(4 downto 0);

        -- MEM/WB producer (instruction currently in WB stage)
        memwb_reg_write : in  std_logic;
        memwb_rd        : in  std_logic_vector(4 downto 0);

        -- IF/ID consumer (instruction currently in ID stage)
        ifid_rs1        : in  std_logic_vector(4 downto 0);
        ifid_rs2        : in  std_logic_vector(4 downto 0);

        -- Stall control outputs
        pc_write        : out std_logic;   -- 0 = freeze PC
        if_id_write     : out std_logic;   -- 0 = freeze IF/ID
        id_ex_flush     : out std_logic    -- 1 = insert NOP bubble into ID/EX
    );
end entity hazard_unit;

architecture rtl of hazard_unit is
begin

    process(idex_reg_write,  idex_rd,
            exmem_reg_write, exmem_rd,
            memwb_reg_write, memwb_rd,
            ifid_rs1, ifid_rs2)

        -- True if prod_rd (a register being written) conflicts with either
        -- source of the ID-stage instruction.  x0 never causes a hazard.
        function conflicts(prod_rd : std_logic_vector(4 downto 0);
                           rs1     : std_logic_vector(4 downto 0);
                           rs2     : std_logic_vector(4 downto 0)) return boolean is
        begin
            return prod_rd /= "00000"
               and (prod_rd = rs1 or prod_rd = rs2);
        end function;

        variable hazard : boolean;
    begin
        hazard := false;

        -- Instruction in EX writes rd -> consumer in ID needs to wait 2 cycles
        if idex_reg_write = '1' and conflicts(idex_rd, ifid_rs1, ifid_rs2) then
            hazard := true;
        end if;

        -- Instruction in MEM writes rd -> consumer in ID needs to wait 1 cycle
        if exmem_reg_write = '1' and conflicts(exmem_rd, ifid_rs1, ifid_rs2) then
            hazard := true;
        end if;

        -- Instruction in WB writes rd on this cycle -> consumer in ID must wait
        -- until the register file has been updated and the read data is stable.
        if memwb_reg_write = '1' and conflicts(memwb_rd, ifid_rs1, ifid_rs2) then
            hazard := true;
        end if;

        if hazard then
            pc_write    <= '0';
            if_id_write <= '0';
            id_ex_flush <= '1';
        else
            pc_write    <= '1';
            if_id_write <= '1';
            id_ex_flush <= '0';
        end if;
    end process;

end architecture rtl;
