-------------------------------------------------------------------------------
-- File: morse_top.vhd
-- Description: Top level. Only connects the blocks to each other and to the
board pins 
-- User interface:
--   PS/2 keyboard : input (see morse_ctrl for the keys)
--   LCD           : output (line 1 = text, line 2 = Morse / mode)
--   BTN_WEST      : reset
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.morse_pkg.all;

entity morse_top is
  generic (
    -- The defaults are the real values for the board (50 MHz clock).
    -- The testbench uses much smaller numbers so the simulation is fast.
    LCD_POWERUP : natural := 1_000_000;
    LCD_SETUP   : natural := 4;
    LCD_PULSE   : natural := 16;
    LCD_CMD     : natural := 2_500;
    LCD_INIT    : natural := 250_000;
    LCD_CLEAR   : natural := 100_000;
    PS2_TIMEOUT : natural := 100_000
  );
  port (
    CLK_50MHZ : in  std_logic;
    BTN_WEST  : in  std_logic;
    PS2_CLK1  : in  std_logic;
    PS2_DATA1 : in  std_logic;
    LCD_E     : out std_logic;
    LCD_RS    : out std_logic;
    LCD_RW    : out std_logic;
    LCD_DB    : out std_logic_vector(7 downto 0)
  );
end entity morse_top;

architecture structural of morse_top is

  signal clk      : std_logic;
  signal rst_sync : std_logic_vector(1 downto 0) := "11";
  signal rst      : std_logic;

  -- ps2_rx -> kbd_decoder
  signal scan_code  : std_logic_vector(7 downto 0);
  signal scan_valid : std_logic;

  -- kbd_decoder -> morse_encoder / morse_ctrl
  signal key_ascii : std_logic_vector(7 downto 0);
  signal key_valid : std_logic;

  -- morse_encoder -> morse_ctrl
  signal enc_len   : unsigned(2 downto 0);
  signal enc_code  : std_logic_vector(4 downto 0);
  signal enc_valid : std_logic;

  -- morse_ctrl <-> morse_decoder
  signal sym_len   : unsigned(2 downto 0);
  signal sym_code  : std_logic_vector(4 downto 0);
  signal dec_char  : std_logic_vector(7 downto 0);

  -- morse_ctrl -> lcd_ctrl
  signal line1, line2 : lcd_line_t;

begin

  clk <= CLK_50MHZ;

  -- Reset synchronizer: the button is asynchronous to the clock.
  -- It starts at "11", so the design is also reset after configuration.
  process (clk)
  begin
    if rising_edge(clk) then
      rst_sync <= rst_sync(0) & BTN_WEST;
    end if;
  end process;
  rst <= rst_sync(1);

  u_ps2 : entity work.ps2_rx
    generic map (TIMEOUT_CYCLES => PS2_TIMEOUT)
    port map (
      clk      => clk,
      rst      => rst,
      ps2_clk  => PS2_CLK1,
      ps2_data => PS2_DATA1,
      data_o   => scan_code,
      valid_o  => scan_valid,
      error_o  => open           -- bad frames are dropped
    );

  u_kbd : entity work.kbd_decoder
    port map (
      clk          => clk,
      rst          => rst,
      code_i       => scan_code,
      code_valid_i => scan_valid,
      ascii_o      => key_ascii,
      key_valid_o  => key_valid
    );

  u_enc : entity work.morse_encoder
    port map (
      char_i  => key_ascii,
      len_o   => enc_len,
      code_o  => enc_code,
      valid_o => enc_valid
    );

  u_dec : entity work.morse_decoder
    port map (
      len_i  => sym_len,
      code_i => sym_code,
      char_o => dec_char
    );

  u_ctrl : entity work.morse_ctrl
    port map (
      clk         => clk,
      rst         => rst,
      key_valid_i => key_valid,
      key_ascii_i => key_ascii,
      enc_len_i   => enc_len,
      enc_code_i  => enc_code,
      enc_valid_i => enc_valid,
      sym_len_o   => sym_len,
      sym_code_o  => sym_code,
      dec_char_i  => dec_char,
      line1_o     => line1,
      line2_o     => line2
    );

  u_lcd : entity work.lcd_ctrl
    generic map (
      POWERUP_CYCLES => LCD_POWERUP,
      SETUP_CYCLES   => LCD_SETUP,
      PULSE_CYCLES   => LCD_PULSE,
      CMD_CYCLES     => LCD_CMD,
      INIT_CYCLES    => LCD_INIT,
      CLEAR_CYCLES   => LCD_CLEAR
    )
    port map (
      clk     => clk,
      rst     => rst,
      line1_i => line1,
      line2_i => line2,
      lcd_e   => LCD_E,
      lcd_rs  => LCD_RS,
      lcd_rw  => LCD_RW,
      lcd_db  => LCD_DB
    );

end architecture structural;
