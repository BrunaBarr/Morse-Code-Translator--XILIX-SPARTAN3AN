-------------------------------------------------------------------------------
-- File       : tb_morse_top.vhd
-- Description: System testbench for morse_top.
--   * A keyboard model types keys (make code + F0 + code, like a real one).
--   * An LCD model listens to LCD_E/RS/DB exactly like the HD44780 does,
--     keeps its own DD RAM, and checks the setup time and the E pulse width.
--   * After each group of keys, the test compares what the "display" shows
--     with the expected text.
--   The LCD waits and the PS/2 timeout are shortened with the generics so
--   the whole simulation runs in a few seconds.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_morse_top is
end entity tb_morse_top;

architecture sim of tb_morse_top is

  constant CLK_PERIOD : time := 20 ns;
  constant PS2_HALF   : time := 20 us;

  signal clk     : std_logic := '0';
  signal btn     : std_logic := '0';
  signal ps2_c   : std_logic := '1';
  signal ps2_d   : std_logic := '1';
  signal lcd_e   : std_logic;
  signal lcd_rs  : std_logic;
  signal lcd_rw  : std_logic;
  signal lcd_db  : std_logic_vector(7 downto 0);
  signal done    : boolean := false;

  -- LCD model state
  type ddram_t is array (0 to 127) of std_logic_vector(7 downto 0);
  signal ddram     : ddram_t := (others => x"20");
  type cmd_log_t is array (0 to 6) of std_logic_vector(7 downto 0);
  signal init_cmds : cmd_log_t := (others => x"00");
  signal timing_errors : natural := 0;

  -- scan codes used in the test
  subtype sc_t is std_logic_vector(7 downto 0);
  constant K_S : sc_t := x"1B";  constant K_O : sc_t := x"44";
  constant K_E : sc_t := x"24";  constant K_SPACE : sc_t := x"29";
  constant K_BS : sc_t := x"66"; constant K_F1 : sc_t := x"05";
  constant K_DOT : sc_t := x"49"; constant K_DASH : sc_t := x"4E";
  constant K_ENTER : sc_t := x"5A"; constant K_TAB : sc_t := x"0D";
  constant K_ESC : sc_t := x"76";
  type sc_array is array (natural range <>) of sc_t;
  constant LETTERS_A_TO_R : sc_array :=
    (x"1C", x"32", x"21", x"23", x"24", x"2B", x"34", x"33", x"43",
     x"3B", x"42", x"4B", x"3A", x"31", x"44", x"4D", x"15", x"2D");

  procedure ps2_send(signal c, d : out std_logic; constant b : in sc_t) is
    variable p     : std_logic := '1';
    variable frame : std_logic_vector(10 downto 0);
  begin
    for i in 0 to 7 loop p := p xor b(i); end loop;
    frame := '1' & p & b & '0';
    for i in 0 to 10 loop
      d <= frame(i);
      wait for PS2_HALF / 2; c <= '0';
      wait for PS2_HALF;     c <= '1';
      wait for PS2_HALF / 2;
    end loop;
    d <= '1';
    wait for 60 us;
  end procedure;

  -- press and release a key, like a real keyboard does
  procedure press(signal c, d : out std_logic; constant k : in sc_t) is
  begin
    ps2_send(c, d, k);
    ps2_send(c, d, x"F0");
    ps2_send(c, d, k);
  end procedure;

  function pad16(s : string) return string is
    variable r : string(1 to 16) := (others => ' ');
  begin
    for i in 1 to s'length loop
      r(i) := s(s'low + i - 1);
    end loop;
    return r;
  end function;

begin

  clk <= not clk after CLK_PERIOD / 2 when not done else '0';

  dut : entity work.morse_top
    generic map (
      LCD_POWERUP => 100, LCD_SETUP => 4, LCD_PULSE => 16, LCD_CMD => 50,
      LCD_INIT => 200, LCD_CLEAR => 100, PS2_TIMEOUT => 5_000)
    port map (
      CLK_50MHZ => clk, BTN_WEST => btn,
      PS2_CLK1 => ps2_c, PS2_DATA1 => ps2_d,
      LCD_E => lcd_e, LCD_RS => lcd_rs, LCD_RW => lcd_rw, LCD_DB => lcd_db);

  -----------------------------------------------------------------------------
  -- LCD model (HD44780, 8-bit bus): the LCD latches the bus when E falls
  -----------------------------------------------------------------------------
  lcd_model : process (lcd_e)
    variable addr    : natural range 0 to 127 := 0;
    variable n_cmd   : natural := 0;
    variable t_rise  : time := 0 ns;
  begin
    if rising_edge(lcd_e) then
      t_rise := now;
      -- setup: RS and DB must be stable at least 40 ns before E rises
      if lcd_db'last_event < 40 ns or lcd_rs'last_event < 40 ns then
        report "LCD setup time violated" severity error;
        timing_errors <= timing_errors + 1;
      end if;
    elsif falling_edge(lcd_e) then
      if now - t_rise < 230 ns then
        report "LCD E pulse too short" severity error;
        timing_errors <= timing_errors + 1;
      end if;
      if lcd_rw /= '0' then
        report "LCD_RW must stay at 0" severity error;
      end if;
      if lcd_rs = '0' then                     -- command
        if n_cmd <= 6 then
          init_cmds(n_cmd) <= lcd_db;
          n_cmd := n_cmd + 1;
        end if;
        if lcd_db(7) = '1' then                -- Set DD RAM address
          addr := to_integer(unsigned(lcd_db(6 downto 0)));
        elsif lcd_db = x"01" then              -- Clear Display
          ddram <= (others => x"20");
          addr := 0;
        end if;
      else                                     -- data: write character
        ddram(addr) <= lcd_db;
        addr := (addr + 1) mod 128;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Test sequence
  -----------------------------------------------------------------------------
  stim : process
    variable errors : natural := 0;

    -- what the LCD model is showing right now
    impure function screen_line(first : natural) return string is
      variable s : string(1 to 16);
    begin
      for i in 0 to 15 loop
        s(i + 1) := character'val(to_integer(unsigned(ddram(first + i))));
      end loop;
      return s;
    end function;

    procedure check_lcd(constant tag : in string;
                        constant l1, l2 : in string) is
    begin
      wait for 150 us;                          -- let the LCD refresh
      if screen_line(0) /= pad16(l1) or screen_line(64) /= pad16(l2) then
        report tag & ": LCD shows [" & screen_line(0) & "] ["
          & screen_line(64) & "], expected [" & pad16(l1) & "] ["
          & pad16(l2) & "]" severity error;
        errors := errors + 1;
      else
        report tag & ": OK  [" & screen_line(0) & "] [" & screen_line(64) & "]";
      end if;
    end procedure;

    type cmd_exp_t is array (0 to 6) of std_logic_vector(7 downto 0);
    constant INIT_EXPECTED : cmd_exp_t :=
      (x"30", x"30", x"30", x"38", x"06", x"0C", x"01");

  begin
    -- 0. power up -------------------------------------------------------------
    wait for 200 us;
    for i in 0 to 6 loop
      if init_cmds(i) /= INIT_EXPECTED(i) then
        report "LCD init command " & integer'image(i) & " is wrong"
          severity error;
        errors := errors + 1;
      end if;
    end loop;
    check_lcd("power up", "", "TX> digite texto");

    -- 1. TX mode: type "SOS" ------------------------------------------------
    press(ps2_c, ps2_d, K_S);
    press(ps2_c, ps2_d, K_O);
    press(ps2_c, ps2_d, K_S);
    check_lcd("TX SOS", "SOS", "TX> S = ...");

    -- 2. space and E, then backspace ----------------------------------------
    press(ps2_c, ps2_d, K_SPACE);
    press(ps2_c, ps2_d, K_E);
    check_lcd("TX space E", "SOS E", "TX> E = .");
    press(ps2_c, ps2_d, K_BS);
    check_lcd("TX backspace", "SOS ", "TX> E = .");

    -- 3. keys that must be ignored in TX mode --------------------------------
    press(ps2_c, ps2_d, K_F1);
    press(ps2_c, ps2_d, K_DOT);
    check_lcd("TX ignored keys", "SOS ", "TX> E = .");

    -- 4. switch to RX mode ------------------------------------------------------
    press(ps2_c, ps2_d, K_TAB);
    check_lcd("RX mode", "SOS ", "RX> . - e Enter");

    -- 5. .-. + Enter = R -------------------------------------------------------
    press(ps2_c, ps2_d, K_DOT);
    press(ps2_c, ps2_d, K_DASH);
    press(ps2_c, ps2_d, K_DOT);
    check_lcd("RX typing", "SOS ", "RX> .-._");
    press(ps2_c, ps2_d, K_ENTER);
    check_lcd("RX decode R", "SOS R", "RX> .-.   = R");

    -- 6. -- + Enter = M ---------------------------------------------------------
    press(ps2_c, ps2_d, K_DASH);
    press(ps2_c, ps2_d, K_DASH);
    press(ps2_c, ps2_d, K_ENTER);
    check_lcd("RX decode M", "SOS RM", "RX> --    = M");

    -- 7. .-.- is not a letter -> '?' --------------------------------------------
    press(ps2_c, ps2_d, K_DOT);
    press(ps2_c, ps2_d, K_DASH);
    press(ps2_c, ps2_d, K_DOT);
    press(ps2_c, ps2_d, K_DASH);
    press(ps2_c, ps2_d, K_ENTER);
    check_lcd("RX invalid", "SOS RM?", "RX> .-.-  = ?");

    -- 8. backspace erases the '?' of the text -----------------------------------
    press(ps2_c, ps2_d, K_BS);
    check_lcd("RX backspace text", "SOS RM", "RX> . - e Enter");

    -- 9. backspace erases a symbol: -.  BS  .. -> -.. = D ------------------------
    press(ps2_c, ps2_d, K_DASH);
    press(ps2_c, ps2_d, K_DOT);
    press(ps2_c, ps2_d, K_BS);
    check_lcd("RX backspace symbol", "SOS RM", "RX> -_");
    press(ps2_c, ps2_d, K_DOT);
    press(ps2_c, ps2_d, K_DOT);
    press(ps2_c, ps2_d, K_ENTER);
    check_lcd("RX decode D", "SOS RMD", "RX> -..   = D");

    -- 10. a 6th symbol is ignored: ...... -> ..... = 5 ---------------------------
    for i in 1 to 6 loop
      press(ps2_c, ps2_d, K_DOT);
    end loop;
    check_lcd("RX 6 symbols", "SOS RMD", "RX> ....._");
    press(ps2_c, ps2_d, K_ENTER);
    check_lcd("RX decode 5", "SOS RMD5", "RX> ..... = 5");

    -- 11. Esc clears, Tab goes back to TX ----------------------------------------
    press(ps2_c, ps2_d, K_ESC);
    check_lcd("RX esc", "", "RX> . - e Enter");
    press(ps2_c, ps2_d, K_TAB);
    check_lcd("back to TX", "", "TX> digite texto");

    -- 12. 18 letters: line 1 scrolls to the left ---------------------------------
    for i in LETTERS_A_TO_R'range loop
      press(ps2_c, ps2_d, LETTERS_A_TO_R(i));
    end loop;
    check_lcd("TX scroll", "CDEFGHIJKLMNOPQR", "TX> R = .-.");

    -- 13. reset button ------------------------------------------------------------
    btn <= '1';
    wait for 1 us;
    btn <= '0';
    wait for 200 us;
    check_lcd("after reset", "", "TX> digite texto");

    ---------------------------------------------------------------------------
    report "tb_morse_top finished: " & integer'image(errors) & " error(s), "
      & integer'image(timing_errors) & " LCD timing error(s)";
    done <= true;
    wait;
  end process;

end architecture sim;
