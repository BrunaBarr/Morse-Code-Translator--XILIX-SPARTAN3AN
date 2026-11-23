-------------------------------------------------------------------------------
-- File       : lcd_ctrl.vhd
-- Project    : Morse code translator (EEL480 - TP1)
-- Description: Controller for the 2x16 character LCD of the Spartan-3A
--              Starter Kit (Sitronix ST7066U, HD44780 compatible), using the
--              8-bit data interface (UG334, chapter 5).
--
-- The rest of the design only has to put the text in line1_i and line2_i.
-- This block:
--   1. waits for the display to power up,
--   2. sends the initialization commands,
--   3. then rewrites the 32 characters forever (about 600 times per second),
--      so any change in line1_i / line2_i shows up automatically.
--
-- Write cycle (LCD_RW is always '0' because we never read the display):
--
--   LCD_RS, LCD_DB  ==X=========== valid ===========X==
--   LCD_E           ______/‾‾‾‾‾‾‾‾‾‾\_______________
--                   |setup|  pulse   |  wait (execution time)  |
--                   >40ns   >230ns     >40us (>1.64ms after Clear)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library work;
use work.morse_pkg.all;

entity lcd_ctrl is
  generic (
    POWERUP_CYCLES : natural := 1_000_000;  -- 20 ms   (datasheet: > 15 ms)
    SETUP_CYCLES   : natural := 4;          -- 80 ns   (> 40 ns)
    PULSE_CYCLES   : natural := 16;         -- 320 ns  (> 230 ns)
    CMD_CYCLES     : natural := 2_500;      -- 50 us   (> 40 us)
    INIT_CYCLES    : natural := 250_000;    -- 5 ms    (> 4.1 ms)
    CLEAR_CYCLES   : natural := 100_000     -- 2 ms    (> 1.64 ms)
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    line1_i : in  lcd_line_t;               -- text of the top line
    line2_i : in  lcd_line_t;               -- text of the bottom line
    lcd_e   : out std_logic;
    lcd_rs  : out std_logic;                -- '0' = command, '1' = data
    lcd_rw  : out std_logic;                -- always '0' (write)
    lcd_db  : out std_logic_vector(7 downto 0)
  );
end entity lcd_ctrl;

architecture rtl of lcd_ctrl is

  -- Timing state machine (one write to the LCD = SETUP -> PULSE -> WAIT)
  type state_t is (S_POWERUP, S_SETUP, S_PULSE, S_WAIT);
  signal state : state_t := S_POWERUP;

  -- Largest wait we may need (sizes the timer).
  function max_of(a, b, c, d : natural) return natural is
    variable m : natural := a;
  begin
    if b > m then m := b; end if;
    if c > m then m := c; end if;
    if d > m then m := d; end if;
    return m;
  end function max_of;
  constant MAX_WAIT : natural :=
    max_of(POWERUP_CYCLES, INIT_CYCLES, CLEAR_CYCLES, 4 * CMD_CYCLES);

  signal timer : natural range 0 to MAX_WAIT := 0;

  -- Step of the write sequence:
  --   0 to 6  : initialization commands (sent once)
  --   7       : "Set DD RAM address" 0x00 (start of line 1)
  --   8 to 23 : the 16 characters of line 1
  --   24      : "Set DD RAM address" 0x40 (start of line 2)
  --   25 to 40: the 16 characters of line 2
  --   after 40, go back to 7 (refresh forever)
  constant STEP_LINE1_ADDR : natural := 7;
  constant STEP_LINE2_ADDR : natural := 24;
  constant STEP_LAST       : natural := 40;
  signal step : natural range 0 to STEP_LAST := 0;

  -- What to send in the current step (combinational)
  signal cur_rs   : std_logic;
  signal cur_db   : std_logic_vector(7 downto 0);
  signal cur_wait : natural range 0 to MAX_WAIT;

  -- Registered outputs (no glitches on the pins)
  signal e_r  : std_logic := '0';
  signal rs_r : std_logic := '0';
  signal db_r : std_logic_vector(7 downto 0) := (others => '0');

begin

  -----------------------------------------------------------------------------
  -- Sequence table: step -> (RS, data byte, wait after the write)
  -----------------------------------------------------------------------------
  sequence : process (step, line1_i, line2_i)
  begin
    cur_rs   <= '0';
    cur_db   <= x"00";
    cur_wait <= CMD_CYCLES;

    case step is
      -- Initialization for the 8-bit interface. The first three 0x30 are
      -- the "wake up" sequence of the HD44780 (they work whatever state the
      -- controller is in).
      when 0 => cur_db <= x"30"; cur_wait <= INIT_CYCLES;     -- wake up
      when 1 => cur_db <= x"30"; cur_wait <= 4 * CMD_CYCLES;  -- wake up
      when 2 => cur_db <= x"30";                              -- wake up
      when 3 => cur_db <= x"38";  -- Function Set: 8 bits, 2 lines, 5x8 font
      when 4 => cur_db <= x"06";  -- Entry Mode: increment, no display shift
      when 5 => cur_db <= x"0C";  -- Display ON, cursor OFF, blink OFF
      when 6 => cur_db <= x"01"; cur_wait <= CLEAR_CYCLES;    -- Clear Display

      when STEP_LINE1_ADDR => cur_db <= x"80";  -- Set DD RAM address 0x00
      when STEP_LINE2_ADDR => cur_db <= x"C0";  -- Set DD RAM address 0x40

      when others =>
        cur_rs <= '1';                          -- character data
        if step < STEP_LINE2_ADDR then
          cur_db <= line1_i(step - STEP_LINE1_ADDR - 1);
        else
          cur_db <= line2_i(step - STEP_LINE2_ADDR - 1);
        end if;
    end case;
  end process sequence;

  -----------------------------------------------------------------------------
  -- Timing state machine
  -----------------------------------------------------------------------------
  timing : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= S_POWERUP;
        step  <= 0;
        timer <= 0;
        e_r   <= '0';
      else
        case state is

          when S_POWERUP =>
            e_r <= '0';
            if timer = POWERUP_CYCLES - 1 then
              timer <= 0;
              state <= S_SETUP;
            else
              timer <= timer + 1;
            end if;

          when S_SETUP =>                  -- put RS and DB on the bus
            -- Load the bus ONLY in the first cycle. If we loaded it on every
            -- cycle, a change of the text in the last setup cycle would
            -- reach the pins just 20 ns before E rises (setup violation).
            if timer = 0 then
              rs_r <= cur_rs;
              db_r <= cur_db;
            end if;
            e_r  <= '0';
            if timer = SETUP_CYCLES - 1 then
              timer <= 0;
              state <= S_PULSE;
            else
              timer <= timer + 1;
            end if;

          when S_PULSE =>                  -- E high: the LCD reads the bus
            e_r <= '1';
            if timer = PULSE_CYCLES - 1 then
              timer <= 0;
              state <= S_WAIT;
            else
              timer <= timer + 1;
            end if;

          when S_WAIT =>                   -- E low: wait for the LCD to finish
            e_r <= '0';
            if timer = cur_wait - 1 then
              timer <= 0;
              state <= S_SETUP;
              if step = STEP_LAST then
                step <= STEP_LINE1_ADDR;   -- refresh again
              else
                step <= step + 1;
              end if;
            else
              timer <= timer + 1;
            end if;

        end case;
      end if;
    end if;
  end process timing;

  lcd_e  <= e_r;
  lcd_rs <= rs_r;
  lcd_rw <= '0';
  lcd_db <= db_r;

end architecture rtl;
