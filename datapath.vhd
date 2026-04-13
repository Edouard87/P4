
-- RISC-V 5-Stage Pipelined Datapath
--
-- Stages: IF → ID → EX → MEM → WB


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_ctrl_pkg.all;

entity datapath is
    generic (
        MEM_SIZE : integer := 32768   -- No touchie. Will break things.
    );
    port (
        clk   : in std_logic;
        reset : in std_logic -- Reset signal for datapath. Active high.
    );
end entity datapath;

architecture rtl of datapath is

	 --Component Declaration

    component memory is
        generic (
            ram_size     : integer := 32768;
            mem_delay    : time    := 3 ns; -- For testing purposes, we set the memory delay to be short.
            clock_period : time    := 1 ns
        );
        port (
            clock       : in  std_logic;
            writedata   : in  std_logic_vector(31 downto 0);
            address     : in  integer range 0 to 32767;
            memwrite    : in  std_logic;
            memread     : in  std_logic;
            readdata    : out std_logic_vector(31 downto 0);
            waitrequest : out std_logic
        );
    end component;

    component register_file is
        port (
            clk       : in  std_logic;
            reset     : in  std_logic;
            rs1_addr  : in  std_logic_vector(4 downto 0);
            rs1_data  : out std_logic_vector(31 downto 0);
            rs2_addr  : in  std_logic_vector(4 downto 0);
            rs2_data  : out std_logic_vector(31 downto 0);
            rd_addr   : in  std_logic_vector(4 downto 0);
            rd_data   : in  std_logic_vector(31 downto 0);
            reg_write : in  std_logic
        );
    end component;

    component alu is
        port (
            operand_a : in  std_logic_vector(31 downto 0);
            operand_b : in  std_logic_vector(31 downto 0);
            alu_ctrl  : in  std_logic_vector(3  downto 0);
            result    : out std_logic_vector(31 downto 0);
            zero      : out std_logic;
            negative  : out std_logic
        );
    end component;

    component control_unit is
        port (
            instruction : in  std_logic_vector(31 downto 0);
            reg_write   : out std_logic;
            mem_read    : out std_logic;
            mem_write   : out std_logic;
            branch      : out std_logic;
            jump        : out std_logic;
            is_jalr     : out std_logic;
            alu_src     : out std_logic;
            use_pc_a    : out std_logic;
            wb_src      : out std_logic_vector(1 downto 0);
            alu_ctrl    : out std_logic_vector(3 downto 0)
        );
    end component;

    component immediate_gen is
        port (
            instruction : in  std_logic_vector(31 downto 0);
            imm_out     : out std_logic_vector(31 downto 0)
        );
    end component;

    component hazard_unit is
        port (
            idex_reg_write  : in  std_logic;
            idex_rd         : in  std_logic_vector(4 downto 0);
            exmem_reg_write : in  std_logic;
            exmem_rd        : in  std_logic_vector(4 downto 0);
            ifid_rs1        : in  std_logic_vector(4 downto 0);
            ifid_rs2        : in  std_logic_vector(4 downto 0);
            pc_write        : out std_logic;
            if_id_write     : out std_logic;
            id_ex_flush     : out std_logic
        );
    end component;

    -- NOP instruction: addi x0, x0, 0  →  opcode=0010011, funct3=000, rd=rs1=0, imm=0
    constant NOP_INSTR : std_logic_vector(31 downto 0) := x"00000013";

    -- IF stage signals
    signal pc_reg        : unsigned(31 downto 0) := (others => '0'); -- Current PC.
    signal pc_next       : unsigned(31 downto 0);
    signal pc_plus4      : unsigned(31 downto 0);

    signal imem_waitrequest : std_logic; -- Gets set to zero and back to one after a successful memory transaction.
    signal imem_read : std_logic := '0'; -- Set high to start an IF read, then deasserted while memory is busy.

    -- Instruction memory wiring (byte-wide, word-aligned access across 4 ports)
    -- We instantiate 4 memory bytes and assemble a 32-bit word.
    signal imem_addr     : integer range 0 to MEM_SIZE-1;
    signal imem_rd        : std_logic_vector(31 downto 0); -- Full content of insurction memory at
                                                           -- consecutive memory addresses for a given address.
    signal if_instruction : std_logic_vector(31 downto 0);

    -- IF/ID pipeline register

    signal ifid_pc4      : unsigned(31 downto 0) := (others => '0');
    signal ifid_instr    : std_logic_vector(31 downto 0) := NOP_INSTR;


    -- ID stage signals

    -- Instruction field aliases on ifid_instr
    signal id_rs1_addr   : std_logic_vector(4 downto 0);
    signal id_rs2_addr   : std_logic_vector(4 downto 0);
    signal id_rd_addr    : std_logic_vector(4 downto 0);
    signal id_rs1_data   : std_logic_vector(31 downto 0);
    signal id_rs2_data   : std_logic_vector(31 downto 0);
    signal id_imm        : std_logic_vector(31 downto 0);

    -- Control signals (combinational, from control_unit)
    signal id_reg_write  : std_logic;
    signal id_mem_read   : std_logic;
    signal id_mem_write  : std_logic;
    signal id_branch     : std_logic;
    signal id_jump       : std_logic;
    signal id_is_jalr    : std_logic;
    signal id_alu_src    : std_logic;
    signal id_use_pc_a   : std_logic;   -- auipc: substitute PC for rs1
    signal id_wb_src     : std_logic_vector(1 downto 0);
    signal id_alu_ctrl   : std_logic_vector(3 downto 0);

    -- Hazard unit outputs
    signal pc_write      : std_logic; -- WE on the PC process. Will prevent the PC from advancing if a hazard
                                      -- is detected.
    signal if_id_write   : std_logic;
    signal id_ex_flush   : std_logic; -- Writeback has not completed and we need the value before we can
                                      -- read from the register file. A NOP should be inserted if this is
                                      -- set to high.

    -- ID/EX pipeline register

    signal idex_pc4      : unsigned(31 downto 0) := (others => '0');
    signal idex_pc       : unsigned(31 downto 0) := (others => '0');  -- PC (for auipc/jal)
    signal idex_rs1_data : std_logic_vector(31 downto 0) := (others => '0');
    signal idex_rs2_data : std_logic_vector(31 downto 0) := (others => '0');
    signal idex_imm      : std_logic_vector(31 downto 0) := (others => '0');
    signal idex_rs1_addr : std_logic_vector(4 downto 0)  := (others => '0');
    signal idex_rs2_addr : std_logic_vector(4 downto 0)  := (others => '0');
    signal idex_rd       : std_logic_vector(4 downto 0)  := (others => '0');
    -- Control signals carried through
    signal idex_reg_write : std_logic := '0';
    signal idex_mem_read  : std_logic := '0';
    signal idex_mem_write : std_logic := '0';
    signal idex_branch    : std_logic := '0';
    signal idex_jump      : std_logic := '0';
    signal idex_is_jalr   : std_logic := '0';
    signal idex_alu_src   : std_logic := '0';
    signal idex_wb_src    : std_logic_vector(1 downto 0) := "00";
    signal idex_alu_ctrl  : std_logic_vector(3 downto 0) := ALU_ADD;
    signal idex_funct3    : std_logic_vector(2 downto 0) := "000";  -- for branch decode
    signal idex_use_pc_a  : std_logic := '0';  -- 1 = use PC as ALU operand_a (auipc)


    -- EX stage signals

    -- Forwarding mux outputs
    signal ex_operand_a  : std_logic_vector(31 downto 0);  -- after PC-override mux (auipc)
    signal ex_operand_b_reg : std_logic_vector(31 downto 0); -- rs2 after forwarding
    signal ex_operand_b  : std_logic_vector(31 downto 0);  -- after alu_src mux
    signal ex_alu_result : std_logic_vector(31 downto 0);
    signal ex_zero       : std_logic;
    signal ex_negative   : std_logic;

    -- Branch / jump target computation (dedicated adder)
    signal ex_branch_target : unsigned(31 downto 0);
    signal ex_jalr_target   : unsigned(31 downto 0);
    signal ex_jump_target   : unsigned(31 downto 0);

    -- Branch taken logic
    signal ex_branch_taken  : std_logic;
    signal ex_pc_src        : std_logic;   -- 1 = take jump/branch target




    -- EX/MEM pipeline register

    signal exmem_pc4         : unsigned(31 downto 0) := (others => '0');
    signal exmem_branch_target : unsigned(31 downto 0) := (others => '0');
    signal exmem_jump_target : unsigned(31 downto 0) := (others => '0');
    signal exmem_alu_result  : std_logic_vector(31 downto 0) := (others => '0');
    signal exmem_rs2_data    : std_logic_vector(31 downto 0) := (others => '0');
    signal exmem_rd          : std_logic_vector(4 downto 0)  := (others => '0');
    signal exmem_branch_taken : std_logic := '0';
    signal exmem_reg_write   : std_logic := '0';
    signal exmem_mem_read    : std_logic := '0';
    signal exmem_mem_waitrequest : std_logic; -- Waitrequest signal from data memory unit indicating whether a transaction has
                                              -- completed.
    signal exmem_mem_write   : std_logic := '0';
    signal exmem_wb_src      : std_logic_vector(1 downto 0) := "00";
    signal exmem_jump        : std_logic := '0';
    signal exmem_pc_src      : std_logic := '0';

    -- MEM stage signals
    -- Data memory wiring (byte-wide, word-aligned)
    signal dmem_addr     : integer range 0 to MEM_SIZE-1;
    signal dmem_wr0, dmem_wr1, dmem_wr2, dmem_wr3 : std_logic_vector(7 downto 0); -- TODO
    signal dmem_rd0, dmem_rd1, dmem_rd2, dmem_rd3 : std_logic_vector(7 downto 0);
    signal mem_read_data : std_logic_vector(31 downto 0); -- Data returned from the data memory unit
                                                          -- when set to read data.

    -- MEM/WB pipeline register
    signal memwb_mem_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal memwb_alu_result: std_logic_vector(31 downto 0) := (others => '0');
    signal memwb_pc4       : unsigned(31 downto 0) := (others => '0');
    signal memwb_rd        : std_logic_vector(4 downto 0)  := (others => '0');
    signal memwb_reg_write : std_logic := '0';
    signal memwb_wb_src    : std_logic_vector(1 downto 0) := "00";

    -- WB stage signals
    signal wb_data         : std_logic_vector(31 downto 0);

begin

    -- Instruction Memory (4 x 8-bit banks → 32-bit word)
    -- Byte address of instruction = pc_reg. Word address = pc_reg >> 2.
    -- Memory goes to 32768 B. As such, we need 15 bits to span the address space.
    -- The rest of the memory address bits are ignored.
    imem_addr <= to_integer(pc_reg(14 downto 0));  -- byte address, memory is byte indexed

    -- Memory returns 32-bit word here and assumes that the addresses are byte-aligned.
    -- Memory is byte-addressible under the hood.
    -- The smallest memory address is the least significant bit (little endian I think)
    IMEM : memory
    generic map (ram_size => MEM_SIZE)
    port map (
        clock => clk, writedata => x"00000000", address => imem_addr,
        memwrite => '0', memread => imem_read,
        readdata => if_instruction, waitrequest => imem_waitrequest -- Monitors the status of waitrequest.
    );

    -- Process to deassert and reassert imem_read so that the
    -- processor actually does the read. Otherwise, subsequent requests
    -- won't affect waitrequest.
    imem_read_proc : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                imem_read <= '1';
            elsif imem_waitrequest = '0' then
                -- When the transaction is done, set read to zero.
                imem_read <= '0';
            else
                -- Set read back to one so we keep going.
                imem_read <= '1';
            end if;
        end if;
    end process imem_read_proc;

    -- Data Memory (4 x 8-bit banks → 32-bit word)
    dmem_addr <= to_integer(unsigned(exmem_alu_result(14 downto 0)));

    DMEM : memory
        generic map (ram_size => MEM_SIZE)
        port map (
            clock => clk, writedata => exmem_rs2_data, address => dmem_addr,
            memwrite => exmem_mem_write, memread => exmem_mem_read,
            readdata => mem_read_data, waitrequest => exem_mem_waitrequest
        );

    -- Register File
    id_rs1_addr <= ifid_instr(19 downto 15);
    id_rs2_addr <= ifid_instr(24 downto 20);
    id_rd_addr  <= ifid_instr(11 downto  7);

    RF : register_file
        port map (
            clk       => clk,
            reset     => reset,
            rs1_addr  => id_rs1_addr,
            rs1_data  => id_rs1_data,
            rs2_addr  => id_rs2_addr,
            rs2_data  => id_rs2_data,
            rd_addr   => memwb_rd,
            rd_data   => wb_data,
            reg_write => memwb_reg_write
        );

    -- Immediate Generator
    IMMGEN : immediate_gen
        port map (
            instruction => ifid_instr,
            imm_out     => id_imm
        );

    -- Control Unit
    CU : control_unit
        port map (
            instruction => ifid_instr,
            reg_write   => id_reg_write,
            mem_read    => id_mem_read,
            mem_write   => id_mem_write,
            branch      => id_branch,
            jump        => id_jump,
            is_jalr     => id_is_jalr,
            alu_src     => id_alu_src,
            use_pc_a    => id_use_pc_a,
            wb_src      => id_wb_src,
            alu_ctrl    => id_alu_ctrl
        );

    -- Hazard Detection Unit
    HU : hazard_unit
        port map (
            idex_reg_write  => idex_reg_write,
            idex_rd         => idex_rd,
            exmem_reg_write => exmem_reg_write,
            exmem_rd        => exmem_rd,
            ifid_rs1        => id_rs1_addr,
            ifid_rs2        => id_rs2_addr,
            pc_write        => pc_write,
            if_id_write     => if_id_write,
            id_ex_flush     => id_ex_flush
        );

    -- ALU
    ALU_INST : alu
        port map (
            operand_a => ex_operand_a,
            operand_b => ex_operand_b,
            alu_ctrl  => idex_alu_ctrl,
            result    => ex_alu_result,
            zero      => ex_zero,
            negative  => ex_negative
        );

    -- EX Stage: Operand Muxes  (no forwarding — hazard unit stalls instead)

    -- operand_a: for AUIPC substitute the pipeline PC; otherwise use rs1 directly
    ex_operand_a <= std_logic_vector(idex_pc) when idex_use_pc_a = '1'
                    else idex_rs1_data;

    -- operand_b: ALU source mux — rs2 or sign-extended immediate
    ex_operand_b_reg <= idex_rs2_data;
    ex_operand_b     <= idex_imm when idex_alu_src = '1' else ex_operand_b_reg;

    -- EX Stage: Branch / Jump target adder
    -- branch target = ID/EX PC + sign_extended_imm
    -- jalr  target  = rs1 + imm  (already computed by ALU when is_jalr=1)
    ex_branch_target <= idex_pc + unsigned(idex_imm);
    ex_jalr_target   <= unsigned(ex_alu_result) and x"FFFFFFFE";  -- clear LSB per spec
    ex_jump_target   <= ex_jalr_target when idex_is_jalr = '1' else ex_branch_target;

    -- EX Stage: Branch decision
    -- ALU computed rs1 - rs2 (ALU_SUB). We inspect zero / negative flags.
    -- funct3 encoding:
    --   000 = beq  → take if zero=1
    --   001 = bne  → take if zero=0
    --   100 = blt  → take if negative=1  (signed less-than)
    --   101 = bge  → take if negative=0  (signed greater-or-equal)
    branch_proc : process(idex_branch, idex_jump, idex_funct3, ex_zero, ex_negative)
        variable cond : boolean;
    begin
        cond := false;
        if idex_branch = '1' then
            case idex_funct3 is
                when "000" => cond := (ex_zero     = '1');   -- beq
                when "001" => cond := (ex_zero     = '0');   -- bne
                when "100" => cond := (ex_negative = '1');   -- blt
                when "101" => cond := (ex_negative = '0');   -- bge
                when others => cond := false;
            end case;
        end if;
        if cond or (idex_jump = '1') then
            ex_branch_taken <= '1';
        else
            ex_branch_taken <= '0';
        end if;
    end process branch_proc;

    ex_pc_src <= ex_branch_taken;

    -- PC logic
    pc_plus4 <= pc_reg + 4;

    -- Branch/jump target comes from EX/MEM register (one cycle later than EX)
    -- pc_src in EX/MEM decides whether to take the branch target or PC+4
    pc_next <= exmem_jump_target when exmem_pc_src = '1' else pc_plus4;

    pc_proc : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                pc_reg <= (others => '0');
            elsif pc_write = '1' and imem_waitrequest = '0' then
                -- Only increment PC when instruction has arrived from memory and
                -- pc_write is enabled.
                pc_reg <= pc_next;
            end if;
        end if;
    end process pc_proc;

    -- IF/ID Pipeline Register
    ifid_proc : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' or exmem_pc_src = '1' then
                -- Flush on reset or taken branch (branch penalty = 2 bubbles,
                -- flush IF/ID to prevent wrong instructions from reaching ID)
                ifid_instr <= NOP_INSTR;
                ifid_pc4   <= (others => '0');
            elsif if_id_write = '1' and imem_waitrequest = '0' then
                ifid_instr <= if_instruction;
                ifid_pc4   <= pc_plus4;
            end if;
        end if;
    end process ifid_proc;

    -- ID/EX Pipeline Register
    idex_proc : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' or id_ex_flush = '1' or exmem_pc_src = '1' then
                -- Insert NOP bubble
                idex_pc4       <= (others => '0');
                idex_pc        <= (others => '0');
                idex_rs1_data  <= (others => '0');
                idex_rs2_data  <= (others => '0');
                idex_imm       <= (others => '0');
                idex_rs1_addr  <= (others => '0');
                idex_rs2_addr  <= (others => '0');
                idex_rd        <= (others => '0');
                idex_reg_write <= '0';
                idex_mem_read  <= '0';
                idex_mem_write <= '0';
                idex_branch    <= '0';
                idex_jump      <= '0';
                idex_is_jalr   <= '0';
                idex_alu_src   <= '0';
                idex_wb_src    <= "00";
                idex_alu_ctrl  <= ALU_ADD;
                idex_funct3    <= "000";
                idex_use_pc_a  <= '0';
            else
                idex_pc4       <= ifid_pc4;
                idex_pc        <= ifid_pc4 - 4;   -- Recover the decoded instruction's PC from IF/ID PC+4
                idex_rs1_data  <= id_rs1_data;
                idex_rs2_data  <= id_rs2_data;
                idex_imm       <= id_imm;
                idex_rs1_addr  <= id_rs1_addr;
                idex_rs2_addr  <= id_rs2_addr;
                idex_rd        <= id_rd_addr;
                idex_reg_write <= id_reg_write;
                idex_mem_read  <= id_mem_read;
                idex_mem_write <= id_mem_write;
                idex_branch    <= id_branch;
                idex_jump      <= id_jump;
                idex_is_jalr   <= id_is_jalr;
                idex_alu_src   <= id_alu_src;
                idex_wb_src    <= id_wb_src;
                idex_alu_ctrl  <= id_alu_ctrl;
                idex_funct3    <= ifid_instr(14 downto 12);
                idex_use_pc_a  <= id_use_pc_a;
            end if;
        end if;
    end process idex_proc;

    -- EX/MEM Pipeline Register
    exmem_proc : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                exmem_pc4          <= (others => '0');
                exmem_branch_target<= (others => '0');
                exmem_jump_target  <= (others => '0');
                exmem_alu_result   <= (others => '0');
                exmem_rs2_data     <= (others => '0');
                exmem_rd           <= (others => '0');
                exmem_branch_taken <= '0';
                exmem_pc_src       <= '0';
                exmem_reg_write    <= '0';
                exmem_mem_read     <= '0';
                exmem_mem_write    <= '0';
                exmem_wb_src       <= "00";
                exmem_jump         <= '0';
            else
                exmem_pc4          <= idex_pc4;
                exmem_branch_target<= ex_branch_target;
                exmem_jump_target  <= ex_jump_target;
                exmem_alu_result   <= ex_alu_result;
                exmem_rs2_data     <= ex_operand_b_reg;  -- forwarded rs2 (for sw)
                exmem_rd           <= idex_rd;
                exmem_branch_taken <= ex_branch_taken;
                exmem_pc_src       <= ex_pc_src;
                exmem_reg_write    <= idex_reg_write;
                exmem_mem_read     <= idex_mem_read;
                exmem_mem_write    <= idex_mem_write;
                exmem_wb_src       <= idex_wb_src;
                exmem_jump         <= idex_jump;
            end if;
        end if;
    end process exmem_proc;

    -- MEM/WB Pipeline Register
    memwb_proc : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                memwb_mem_data   <= (others => '0');
                memwb_alu_result <= (others => '0');
                memwb_pc4        <= (others => '0');
                memwb_rd         <= (others => '0');
                memwb_reg_write  <= '0';
                memwb_wb_src     <= "00";
            else
                memwb_mem_data   <= mem_read_data; -- Data from the memory unit if applicable.
                memwb_alu_result <= exmem_alu_result;
                memwb_pc4        <= exmem_pc4;
                memwb_rd         <= exmem_rd;
                memwb_reg_write  <= exmem_reg_write;
                memwb_wb_src     <= exmem_wb_src;
            end if;
        end if;
    end process memwb_proc;

    -- WB Stage: Write-back mux
    --   "00" = ALU result
    --   "01" = memory read data
    --   "10" = PC + 4  (jal / jalr link address)
    with memwb_wb_src select wb_data <=
        memwb_alu_result            when "00",
        memwb_mem_data              when "01",
        std_logic_vector(memwb_pc4) when "10",
        memwb_alu_result            when others;

end architecture rtl;
