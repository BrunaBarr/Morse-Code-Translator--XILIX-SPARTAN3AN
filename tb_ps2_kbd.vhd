-------------------------------------------------------------------------------
-- File       : tb_ps2_kbd.vhd
-- Description: Self-checking testbench for ps2_rx + kbd_decoder.
--              A procedure plays the role of the keyboard and sends real
--              PS/2 frames (start, 8 data bits LSB first, odd parity, stop)
--              with a 25 kHz clock.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ps2_kbd is
end entity tb_ps2_kbd;

architecture sim of tb_ps2_kbd is

  constant CLK_PERIOD : time := 20 ns;     -- 50 MHz
  constant PS2_HALF   : time := 20 us;     -- PS/2 clock: 25 kHz

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal ps2_clk  : std_logic := '1';
  signal ps2_data : std_logic := '1';

  signal scan_code  : std_logic_vector(7 downto 0);
  signal scan_valid : std_logic;
  signal scan_error : std_logic;
  signal ascii      : std_logic_vector(7 downto 0);
  signal key_valid  : std_logic;

  -- log of the key events seen at the output
  type log_t is array (0 to 31) of std_logic_vector(7 downto 0);
  signal log_mem    : log_t := (others => x"00");
  signal log_cnt    : natural := 0;
  signal err_cnt    : natural := 0;
  signal done       : boolean := false;

  -- Keyboard model: sends one byte. With good_parity = false the parity bit
  -- is inverted, to test the error detection.
  procedure ps2_send(signal c, d    : out std_logic;
                     constant b     : in  std_logic_vector(7 downto 0);
                     constant good_parity : in boolean := true) is
    variable p     : std_logic := '1';
    variable frame : std_logic_vector(10 downto 0);
  begin
    for i in 0 to 7 loop
      p := p xor b(i);                 -- odd parity
    end loop;
    if not good_parity then
      p := not p;
    end if;
    frame := '1' & p & b & '0';        -- bit 0 (start) is sent first
    for i in 0 to 10 loop
      d <= frame(i);                   -- data changes while the clock is high
      wait for PS2_HALF / 2;
      c <= '0';                        -- the host samples on this edge
      wait for PS2_HALF;
      c <= '1';
      wait for PS2_HALF / 2;
    end loop;
    d <= '1';
    wait for 100 us;                   -- gap between bytes
  end procedure;

begin

  clk <= not clk after CLK_PERIOD / 2 when not done else '0';

  u_rx : entity work.ps2_rx
    generic map (TIMEOUT_CYCLES => 5_000)    -- 100 us, enough for the test
    port map (clk => clk, rst => rst, ps2_clk => ps2_clk, ps2_data => ps2_data,
              data_o => scan_code, valid_o => scan_valid, error_o => scan_error);

  u_kbd : entity work.kbd_decoder
    port map (clk => clk, rst => rst, code_i => scan_code,
              code_valid_i => scan_valid, ascii_o => ascii,
              key_valid_o => key_valid);

  -- records every key event and every frame error
  monitor : process (clk)
  begin
    if rising_edge(clk) then
      if key_valid = '1' then
        log_mem(log_cnt) <= ascii;
        log_cnt <= log_cnt + 1;
      end if;
      if scan_error = '1' then
        err_cnt <= err_cnt + 1;
      end if;
    end if;
  end process;

  stim : process
    type exp_t is array (natural range <>) of std_logic_vector(7 downto 0);
    constant EXPECTED : exp_t := (x"41", x"20", x"0D", x"2E", x"2D", x"2D", x"30");
    variable errors : natural := 0;
  begin
    wait for 1 us;
    rst <= '0';
    wait for 10 us;

    ps2_send(ps2_clk, ps2_data, x"1C");                -- A pressed   -> 'A'
    ps2_send(ps2_clk, ps2_data, x"F0");                -- A released  -> nothing
    ps2_send(ps2_clk, ps2_data, x"1C");
    ps2_send(ps2_clk, ps2_data, x"29");                -- Space       -> ' '
    ps2_send(ps2_clk, ps2_data, x"F0");
    ps2_send(ps2_clk, ps2_data, x"29");
    ps2_send(ps2_clk, ps2_data, x"E0");                -- keypad Enter-> CR
    ps2_send(ps2_clk, ps2_data, x"5A");
    ps2_send(ps2_clk, ps2_data, x"E0");                -- released    -> nothing
    ps2_send(ps2_clk, ps2_data, x"F0");
    ps2_send(ps2_clk, ps2_data, x"5A");
    ps2_send(ps2_clk, ps2_data, x"E0");                -- up arrow    -> nothing
    ps2_send(ps2_clk, ps2_data, x"75");
    ps2_send(ps2_clk, ps2_data, x"1C", false);         -- bad parity  -> error
    ps2_send(ps2_clk, ps2_data, x"49");                -- '.'         -> '.'
    ps2_send(ps2_clk, ps2_data, x"4E");                -- '-'         -> '-'
    ps2_send(ps2_clk, ps2_data, x"7B");                -- keypad '-'  -> '-'
    ps2_send(ps2_clk, ps2_data, x"05");                -- F1          -> nothing
    ps2_send(ps2_clk, ps2_data, x"AA");                -- self-test OK-> nothing

    -- Broken frame: only the start bit and 3 data bits, then silence.
    -- The receiver must give up (timeout) and still read the next byte.
    for i in 0 to 3 loop
      ps2_data <= '0';
      wait for PS2_HALF / 2; ps2_clk <= '0';
      wait for PS2_HALF;     ps2_clk <= '1';
      wait for PS2_HALF / 2;
    end loop;
    ps2_data <= '1';
    wait for 300 us;
    ps2_send(ps2_clk, ps2_data, x"45");                -- '0'         -> '0'

    wait for 100 us;

    -- checks ----------------------------------------------------------------
    if log_cnt /= EXPECTED'length then
      report "expected " & integer'image(EXPECTED'length) & " keys, got "
        & integer'image(log_cnt) severity error;
      errors := errors + 1;
    else
      for i in EXPECTED'range loop
        if log_mem(i) /= EXPECTED(i) then
          report "key " & integer'image(i) & ": expected ASCII "
            & integer'image(to_integer(unsigned(EXPECTED(i)))) & ", got "
            & integer'image(to_integer(unsigned(log_mem(i)))) severity error;
          errors := errors + 1;
        end if;
      end loop;
    end if;
    if err_cnt /= 1 then
      report "expected 1 parity error, got " & integer'image(err_cnt)
        severity error;
      errors := errors + 1;
    end if;

    report "tb_ps2_kbd finished: " & integer'image(errors) & " error(s), "
      & integer'image(log_cnt) & " keys decoded, "
      & integer'image(err_cnt) & " frame error(s) detected";
    done <= true;
    wait;
  end process;

end architecture sim;
