-------------------------------------------------------------------------------
-- File: ps2_rx.vhd
-- Description: PS/2 receiver (keyboard -> FPGA only).
--
-- The keyboard sends 11-bit frames, least significant data bit first
-- Outputs:
--   data_o  : last byte received (scan code)
--   valid_o : 1-cycle pulse when data_o holds a new, correct byte
--   error_o : 1-cycle pulse when a frame had a wrong start/stop/parity bit
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity ps2_rx is
  generic (
    -- If no clock edge arrives for this many cycles in the middle of a frame,
    -- the frame is discarded. 100_000 cycles = 2 ms at 50 MHz (a whole frame
    -- takes at most about 1.1 ms, so this only fires on real errors, e.g.
    -- when the keyboard is plugged in while the FPGA is running).
    TIMEOUT_CYCLES : natural := 100_000
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                      -- synchronous, active High
    ps2_clk  : in  std_logic;                      -- from the keyboard
    ps2_data : in  std_logic;                      -- from the keyboard
    data_o   : out std_logic_vector(7 downto 0);
    valid_o  : out std_logic;
    error_o  : out std_logic
  );
end entity ps2_rx;

architecture rtl of ps2_rx is

  -- Receiver states:
  --   S_IDLE  : waiting for a start bit
  --   S_RECV  : shifting in data, parity and stop bits
  --   S_CHECK : whole frame received, verify it
  type state_t is (S_IDLE, S_RECV, S_CHECK);
  signal state : state_t := S_IDLE;

  -- Two-flip-flop synchronizers (avoid metastability).
  signal clk_sync  : std_logic_vector(1 downto 0) := "11";
  signal data_sync : std_logic_vector(1 downto 0) := "11";

  -- Glitch filter: ps2_clk only changes after 8 equal samples in a row.
  signal clk_hist  : std_logic_vector(7 downto 0) := (others => '1');
  signal clk_filt  : std_logic := '1';
  signal clk_prev  : std_logic := '1';
  signal fall_edge : std_logic;

  -- Shift register for the 10 bits after the start bit:
  --   sr(7 downto 0) = D7..D0, sr(8) = parity, sr(9) = stop
  signal sr        : std_logic_vector(9 downto 0) := (others => '0');
  signal bit_cnt   : natural range 0 to 10 := 0;
  signal timer     : natural range 0 to TIMEOUT_CYCLES := 0;

  signal data_r    : std_logic_vector(7 downto 0) := (others => '0');
  signal valid_r   : std_logic := '0';
  signal error_r   : std_logic := '0';

begin

  -----------------------------------------------------------------------------
  -- Input conditioning: synchronizer + glitch filter + edge detector
  -----------------------------------------------------------------------------
  conditioning : process (clk)
  begin
    if rising_edge(clk) then
      clk_sync  <= clk_sync(0)  & ps2_clk;
      data_sync <= data_sync(0) & ps2_data;

      clk_hist <= clk_hist(6 downto 0) & clk_sync(1);
      if clk_hist = x"FF" then
        clk_filt <= '1';
      elsif clk_hist = x"00" then
        clk_filt <= '0';
      end if;

      clk_prev <= clk_filt;
    end if;
  end process conditioning;

  -- A falling edge happened when the filtered clock was '1' and is now '0'.
  fall_edge <= clk_prev and not clk_filt;

  -----------------------------------------------------------------------------
  -- Frame receiver (finite state machine)
  -----------------------------------------------------------------------------
  receiver : process (clk)
    variable parity_v : std_logic;
  begin
    if rising_edge(clk) then
      -- Default values: the pulses last only one clock cycle.
      valid_r <= '0';
      error_r <= '0';

      if rst = '1' then
        state   <= S_IDLE;
        bit_cnt <= 0;
        timer   <= 0;
      else
        case state is

          when S_IDLE =>
            -- A falling edge with data = '0' is a start bit.
            if fall_edge = '1' and data_sync(1) = '0' then
              bit_cnt <= 0;
              timer   <= 0;
              state   <= S_RECV;
            end if;

          when S_RECV =>
            if fall_edge = '1' then
              -- Shift right: the first bit received ends up in sr(0).
              sr      <= data_sync(1) & sr(9 downto 1);
              timer   <= 0;
              if bit_cnt = 9 then        -- this was the 10th bit (stop bit)
                state <= S_CHECK;
              else
                bit_cnt <= bit_cnt + 1;
              end if;
            elsif timer = TIMEOUT_CYCLES then
              state <= S_IDLE;           -- frame lost: start over
            else
              timer <= timer + 1;
            end if;

          when S_CHECK =>
            -- Odd parity: the number of '1's in D7..D0 plus the parity bit
            -- must be odd, i.e. the XOR of those 9 bits must be '1'.
            parity_v := '0';
            for i in 0 to 8 loop
              parity_v := parity_v xor sr(i);
            end loop;

            if parity_v = '1' and sr(9) = '1' then
              data_r  <= sr(7 downto 0);
              valid_r <= '1';
            else
              error_r <= '1';
            end if;
            state <= S_IDLE;

        end case;
      end if;
    end if;
  end process receiver;

  data_o  <= data_r;
  valid_o <= valid_r;
  error_o <= error_r;

end architecture rtl;
