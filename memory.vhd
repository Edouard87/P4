-- Adapted from Example 12-15 of Quartus Design and Synthesis handbook.
-- Modified to otuput 32 bits of data on read (although it remains byte addressible under the hood).
-- Assumes the read addresses are byte-aligned.
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY memory IS
	GENERIC(
		ram_size : INTEGER := 32768;
		mem_delay : time := 1 ns;
		clock_period : time := 1 ns -- No touchie! (1 GHz)
	);
	PORT (
		clock: IN STD_LOGIC;
		writedata: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		address: IN INTEGER RANGE 0 TO ram_size-1;
		memwrite: IN STD_LOGIC;
		memread: IN STD_LOGIC;
		readdata: OUT STD_LOGIC_VECTOR (31 DOWNTO 0);
		waitrequest: OUT STD_LOGIC
	);
END memory;

ARCHITECTURE rtl OF memory IS
	TYPE MEM IS ARRAY(ram_size-1 downto 0) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL ram_block: MEM;
	SIGNAL read_address_reg: INTEGER RANGE 0 to ram_size-1;
	SIGNAL write_waitreq_reg: STD_LOGIC := '1';
	SIGNAL read_waitreq_reg: STD_LOGIC := '1';
	SIGNAL write_active: STD_LOGIC := '0';
	SIGNAL write_base_addr_reg: INTEGER RANGE 0 to ram_size-1 := 0;
	SIGNAL write_data_reg: STD_LOGIC_VECTOR(31 DOWNTO 0) := (others => '0');
	SIGNAL write_byte_index: INTEGER RANGE 0 to 3 := 0;
BEGIN
	--This is the main section of the SRAM model
	mem_process: PROCESS (clock)
	BEGIN
		--Using the cheap trick to initialize the SRAM in simulation
		IF(now < 1 ps)THEN
			For i in 0 to ram_size-1 LOOP
				ram_block(i) <= (others => '0');
			END LOOP;
		end if;

		--This is the actual synthesizable SRAM block
		IF (clock'event AND clock = '1') THEN
			read_address_reg <= address;

			IF (write_active = '0') THEN
				IF (memwrite = '1') THEN
					write_active <= '1';
					write_base_addr_reg <= address;
					write_data_reg <= writedata;
					write_byte_index <= 0;
					write_waitreq_reg <= '1';
				END IF;
			ELSE
				case write_byte_index is
					when 0 =>
						ram_block(write_base_addr_reg) <= write_data_reg(7 downto 0);
						write_byte_index <= 1;
					when 1 =>
						ram_block(write_base_addr_reg + 1) <= write_data_reg(15 downto 8);
						write_byte_index <= 2;
					when 2 =>
						ram_block(write_base_addr_reg + 2) <= write_data_reg(23 downto 16);
						write_byte_index <= 3;
					when others =>
						ram_block(write_base_addr_reg + 3) <= write_data_reg(31 downto 24);
						write_active <= '0';
						write_byte_index <= 0;
						write_waitreq_reg <= '0';
				end case;
			END IF;

			IF (write_waitreq_reg = '0') THEN
				write_waitreq_reg <= '1';
			END IF;

			IF (memread = '1') THEN
				read_waitreq_reg <= '0';
			ELSE
				read_waitreq_reg <= '1';
			END IF;
		END IF;
	END PROCESS;
	readdata <= ram_block(read_address_reg + 3) &
				ram_block(read_address_reg + 2) &
				ram_block(read_address_reg + 1) &
				ram_block(read_address_reg);


	--The waitrequest signal is used to vary response time in simulation
	--Read and write should never happen at the same time.
	waitrequest <= write_waitreq_reg and read_waitreq_reg;


END rtl;
