
--Register file, 32 Registers of 32 bits each

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity register_file is
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;

        -- Rs1
        rs1_addr   : in  std_logic_vector(4 downto 0);   -- Source register 1 address (0-31)
        rs1_data   : out std_logic_vector(31 downto 0);  -- Source register 1 data

        -- Rs2
        rs2_addr   : in  std_logic_vector(4 downto 0);   -- Source register 2 address (0-31)
        rs2_data   : out std_logic_vector(31 downto 0);  -- Source register 2 data

        --Write Back
        rd_addr    : in  std_logic_vector(4 downto 0);   -- Destination register address (0-31)
        rd_data    : in  std_logic_vector(31 downto 0);  -- Data to write
        reg_write  : in  std_logic                       -- Write enable (active high)
    );
end entity register_file;


architecture rtl of register_file is

    -- Register array, 32 registers of 32 bits
    type reg_array_t is array(0 to 31) of std_logic_vector(31 downto 0);
    signal registers : reg_array_t := (others => (others => '0'));

begin

    -- Synchronous Write Port
    -- Write on rising edge when reg_write is asserted.
    -- x0 is hardwired to zero and can never be written.
    write_proc : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                -- Clear all registers on reset
                registers <= (others => (others => '0'));
            elsif reg_write = '1' and rd_addr /= "00000" then
                registers(to_integer(unsigned(rd_addr))) <= rd_data;
            end if;
        end if;
    end process write_proc;

    -- Asynchronous Read on Rs1 and Rs2, we dont reaaally need a clock for this one
    -- x0 always returns 0 regardless of the register array contents.
    rs1_data <= (others => '0') when rs1_addr = "00000"
                else registers(to_integer(unsigned(rs1_addr)));

    rs2_data <= (others => '0') when rs2_addr = "00000"
                else registers(to_integer(unsigned(rs2_addr)));

end architecture rtl;