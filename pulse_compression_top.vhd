library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pulse_compression_top is
    Generic (
        -- Delay in clock cycles (5ns each) after falling edge of T_on
        -- Example: 1000 = 5us delay after pulse_out drops
        G_DELAY_VAL : integer := 1000 
    );
    Port (
        sys_clk_p : in std_logic;
        sys_clk_n : in std_logic;
        reset_n   : in std_logic;
        pulse_out : out std_logic;           -- Physical 1us T_on pulse
        fir_i_d_out   : out std_logic_vector(63 downto 0); -- Peak Output
        fir_q_d_out   : out std_logic_vector(63 downto 0)
    );
end pulse_compression_top;

architecture Behavioral of pulse_compression_top is

     -- 1. Clock Wizard: Generates 200MHz from Differential Input
    component clk_wiz_0
    port (
        clk_out1 : out std_logic;
        resetn   : in std_logic;
        locked   : out std_logic;
        clk_in1_p : in std_logic;
        clk_in1_n : in std_logic
    );
    end component;
    
        -- 2. DDS: Streaming Phase, 200MHz Clk, 16-bit Sine
    COMPONENT dds_compiler_0
    PORT (
        aclk                : IN STD_LOGIC;
        s_axis_phase_tvalid : IN STD_LOGIC;
        s_axis_phase_tdata  : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        m_axis_data_tvalid  : OUT STD_LOGIC;
        m_axis_data_tdata   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
    END COMPONENT;
    
    COMPONENT dds_compiler_1
      PORT (
        aclk : IN STD_LOGIC;
        m_axis_data_tvalid : OUT STD_LOGIC;
        m_axis_data_tdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
      );
    END COMPONENT;
    
    COMPONENT dds_compiler_2
      PORT (
        aclk : IN STD_LOGIC;
        m_axis_data_tvalid : OUT STD_LOGIC;
        m_axis_data_tdata : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
      );
    END COMPONENT;
    
    COMPONENT cmpy_0
      PORT (
        aclk : IN STD_LOGIC;
        s_axis_a_tvalid : IN STD_LOGIC;
        s_axis_a_tready : OUT STD_LOGIC;
        s_axis_a_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        s_axis_b_tvalid : IN STD_LOGIC;
        s_axis_b_tready : OUT STD_LOGIC;
        s_axis_b_tdata : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        m_axis_dout_tvalid : OUT STD_LOGIC;
        m_axis_dout_tready : IN STD_LOGIC;
        m_axis_dout_tdata : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)
      );
    END COMPONENT;
    
        -- 3. FIR: Matched Filter (Clk=200MHz, Fsamp=40MHz, Real Input 16-bit)
COMPONENT fir_compiler_0
          PORT (
            aclk : IN STD_LOGIC;
            s_axis_data_tvalid : IN STD_LOGIC;
            s_axis_data_tready : OUT STD_LOGIC;
            s_axis_data_tdata : IN STD_LOGIC_VECTOR(39 DOWNTO 0);
            m_axis_data_tvalid : OUT STD_LOGIC;
            m_axis_data_tdata : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)
          );
        END COMPONENT;
        
        COMPONENT fir_compiler_1
          PORT (
            aclk : IN STD_LOGIC;
            s_axis_data_tvalid : IN STD_LOGIC;
            s_axis_data_tready : OUT STD_LOGIC;
            s_axis_data_tdata : IN STD_LOGIC_VECTOR(23 DOWNTO 0);
            m_axis_data_tvalid : OUT STD_LOGIC;
            m_axis_data_tdata : OUT STD_LOGIC_VECTOR(47 DOWNTO 0)
          );
        END COMPONENT;
        
        COMPONENT fir_compiler_2
          PORT (
            aclk : IN STD_LOGIC;
            s_axis_data_tvalid : IN STD_LOGIC;
            s_axis_data_tready : OUT STD_LOGIC;
            s_axis_data_tdata : IN STD_LOGIC_VECTOR(39 DOWNTO 0);
            m_axis_data_tvalid : OUT STD_LOGIC;
            m_axis_data_tdata : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)
          );
        END COMPONENT;
    
    -- Timing for 200MHz clock (5ns period)
    constant SAMPLE_CNT : integer := 400;   
    
    -- Internal Signals
    signal clk_200M      : std_logic;
    signal locked        : std_logic;
    signal pri_cnt       : integer range 0 to 20000 := 0;
    signal chirp_valid   : std_logic := '0';
    signal valid   : std_logic := '0';
    signal chirp_phase   : unsigned(31 downto 0) := x"06666666";
    constant STEP_VAL    : unsigned(31 downto 0) := x"00083127";
    
    -- DDS Start logic: Falling edge of T_on (cycle 200) + Generic delay
    
    constant PRI_MAX      : integer := 10000; -- 100us PRI (20000 * 5ns)
    constant TON_MAX      : integer := 2000;   -- 10us pulse_out (200 * 5ns)
    
    -- Timing for 40MHz Sampling Rate
    constant CLKS_PER_SAMPLE : integer := 5;   -- 200MHz / 40MHz
    constant TOTAL_SAMPLES   : integer := 400; -- 10us @ 40MHz
    
    -- Signals
    signal sample_tick_cnt : integer range 0 to 5 := 0;
    signal sample_en       : std_logic := '0';
    signal dds_sample_cnt  : integer range 0 to 401 := 0;
    signal dds_start_time  : integer ;
    
    signal dds_v_out  : std_logic;
    signal dds_d_out  : std_logic_vector(31 downto 0);
    signal dds_lo_v  : std_logic;

    signal dds_lo_data  : std_logic_vector(31 downto 0);   
    signal lpf_cos_data, lpf_sin_data  : std_logic_vector(47 downto 0);    
 
    
    signal mixed_data1,mixed_data2  : std_logic_vector(63 downto 0);
    signal mixed_lpf1, mixed_pc1 : std_logic;
    signal mixed_lpf2, mixed_pc2 : std_logic;

    signal mixed_ilpf ,mixed_qlpf : std_logic_vector(23 downto 0);
    
    signal fir_ipc_ready, fir_qpc_ready : std_logic;
    signal fir_ilpf_ready, fir_qlpf_ready : std_logic;

    signal fir_i_v_out, fir_q_v_out : std_logic;


begin

    -- Calculate the exact cycle when the DDS should wake up
    dds_start_time <= TON_MAX + G_DELAY_VAL;

    -- 1. Clock Generation Instance
    clk_gen : clk_wiz_0
    port map (
        clk_in1_p => sys_clk_p,
        clk_in1_n => sys_clk_n,
        resetn    => reset_n,
        clk_out1  => clk_200M,
        locked    => locked
    );
    

    -- 2. Master Timing and Pulse Control
       process(clk_200M)
    begin
        if rising_edge(clk_200M) then
            if reset_n = '0' or locked = '0' then
                pri_cnt         <= 0;
                sample_tick_cnt <= 0;
                dds_sample_cnt  <= 0;
                chirp_valid     <= '0';
                valid           <= '0';
            else
                -- 1. Master PRI Counter (Continuous 200MHz)
                if pri_cnt < PRI_MAX - 1 then
                    pri_cnt <= pri_cnt + 1; 
                else
                    pri_cnt <= 0;
                     
                end if;
        

--                 2. Create the 40MHz Sample Enable (1 tick every 5 clks)
                if sample_tick_cnt < CLKS_PER_SAMPLE - 1 then
                    sample_tick_cnt <= sample_tick_cnt + 1;
                    sample_en <= '0';
                else
                    sample_tick_cnt <= 0;
                    sample_en <= '1'; -- This is our 40MHz strobe
                end if;

                -- 3. Reference 1us Pulse (200MHz logic)
                if pri_cnt < TON_MAX then
                    pulse_out <= '1';
                    valid <= '0';
                else
                    pulse_out <= '0';
                    valid <= '1';
                end if;

                -- 4. 10us DDS Burst (Gated by 40MHz Enable)
                -- Start after delay, then count 400 samples at the 40MHz rate
                if pri_cnt >= dds_start_time and dds_sample_cnt < TOTAL_SAMPLES then
                    chirp_valid <= '1';
                    if sample_en = '1' then
--                        chirp_valid <= '1';
                        chirp_phase <= chirp_phase + STEP_VAL;
                        dds_sample_cnt <= dds_sample_cnt + 1;
--                    else 
--                       chirp_valid <= '0';
                    end if;
                else
                    chirp_valid <= '0';
                    -- Reset pulse counter when PRI restarts
                    if pri_cnt = 0 then
                        dds_sample_cnt <= 0;
                        chirp_phase <= x"06666666";
                    end if;
                end if;
            end if;
        end if;
    end process;

    
        -- 3. DDS Instance
    u_dds : dds_compiler_0 port map (
        aclk => clk_200M,
        s_axis_phase_tvalid => chirp_valid,
        s_axis_phase_tdata  => std_logic_vector(chirp_phase),
        m_axis_data_tvalid  => dds_v_out,
        m_axis_data_tdata   => dds_d_out
    );
    
    lo_dds : dds_compiler_1
      PORT MAP (
        aclk => clk_200M,
        m_axis_data_tvalid => dds_lo_v,
        m_axis_data_tdata => dds_lo_data
      );
      
      
      mult1 : cmpy_0
        PORT MAP (
          aclk => clk_200M,
          s_axis_a_tvalid => valid,
          s_axis_a_tready => open,
          s_axis_a_tdata => dds_d_out,
          s_axis_b_tvalid => valid,
          s_axis_b_tready => open,
          s_axis_b_tdata => dds_lo_data(15 downto 0), --COSINE
          m_axis_dout_tvalid => mixed_lpf1,
          m_axis_dout_tready => '1',
          m_axis_dout_tdata => mixed_data1
        );
        
        mult2 : cmpy_0
                PORT MAP (
                  aclk => clk_200M,
                  s_axis_a_tvalid => valid,
                  s_axis_a_tready => open,
                  s_axis_a_tdata => dds_d_out,
                  s_axis_b_tvalid => valid,
                  s_axis_b_tready => open,
                  s_axis_b_tdata => dds_lo_data(31 downto 16),--SINE
                  m_axis_dout_tvalid => mixed_lpf2,
                  m_axis_dout_tready => '1',
                  m_axis_dout_tdata => mixed_data2
                );
        
        mixed_ilpf <= mixed_data1(24 downto 1);
        mixed_qlpf <= mixed_data2(56 downto 33);
        
        
        u_fir_lpfcos : fir_compiler_1
          PORT MAP (
            aclk => clk_200M,
            s_axis_data_tvalid => mixed_lpf1,
            s_axis_data_tready => fir_ilpf_ready,
            s_axis_data_tdata => mixed_ilpf,
            m_axis_data_tvalid => mixed_pc1,
            m_axis_data_tdata => lpf_cos_data
          );
          
          
          u_fir_lpfsin : fir_compiler_1
            PORT MAP (
              aclk => clk_200M,
              s_axis_data_tvalid => mixed_lpf2,
              s_axis_data_tready => fir_qlpf_ready,
              s_axis_data_tdata => mixed_qlpf,
              m_axis_data_tvalid => mixed_pc2,
              m_axis_data_tdata => lpf_sin_data
            );

    u_fir_pccos : fir_compiler_0 port map (
        aclk => clk_200M,
        s_axis_data_tvalid => mixed_pc1,
        s_axis_data_tready => fir_ipc_ready,
        s_axis_data_tdata  => lpf_cos_data(40 downto 1), -- Cosine
        m_axis_data_tvalid => fir_i_v_out,
        m_axis_data_tdata  => fir_i_d_out
    );

    u_fir_pcsin : fir_compiler_2 port map (
        aclk => clk_200M,
        s_axis_data_tvalid => mixed_pc2,
        s_axis_data_tready => fir_qpc_ready,
        s_axis_data_tdata  => lpf_sin_data(40 downto 1), -- Sine
        m_axis_data_tvalid => fir_q_v_out,
        m_axis_data_tdata  => fir_q_d_out
    );
end Behavioral;
