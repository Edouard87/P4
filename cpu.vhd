library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_ctrl_pkg.all;

entity cpu_tb is
end cpu_tb;

-- Code to test the CPU defined by datapath.vhd

architecture arch of cpu_tb is
    component datapath is
        port (
            clk   : in std_logic;
            reset : in std_logic
        );
    end component;

    constant clk_period : time := 1 ns; -- 1 GHz
    signal clk   : std_logic := '0';
    signal reset : std_logic := '0';

begin
    dp : datapath
        port map (
            clk   => clk,
            reset => reset
        );

    clock_gen : process
    begin
        clk <= '0';
        wait for clk_period / 2;
        clk <= '1';
        wait for clk_period / 2;
    end process;
end architecture arch;
