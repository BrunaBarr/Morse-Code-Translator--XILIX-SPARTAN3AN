-------------------------------------------------------------------------------
-- File       : morse_pkg.vhd
-- Description: Types, constants and helper functions shared by all blocks.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package morse_pkg is

  -- One line of the 2x16 character LCD: 16 ASCII characters of 8 bits each.
  type lcd_line_t is array (0 to 15) of std_logic_vector(7 downto 0);

  -- ASCII codes used by the design. The keyboard decoder translates the
  -- special keys into standard ASCII control codes, so every other block
  -- only has to deal with ASCII.
  constant ASC_BS    : std_logic_vector(7 downto 0) := x"08";  -- Backspace
  constant ASC_TAB   : std_logic_vector(7 downto 0) := x"09";  -- Tab
  constant ASC_ENTER : std_logic_vector(7 downto 0) := x"0D";  -- Enter
  constant ASC_ESC   : std_logic_vector(7 downto 0) := x"1B";  -- Escape
  constant ASC_SPACE : std_logic_vector(7 downto 0) := x"20";  -- ' '
  constant ASC_DASH  : std_logic_vector(7 downto 0) := x"2D";  -- '-'
  constant ASC_DOT   : std_logic_vector(7 downto 0) := x"2E";  -- '.'
  constant ASC_EQUAL : std_logic_vector(7 downto 0) := x"3D";  -- '='
  constant ASC_QMARK : std_logic_vector(7 downto 0) := x"3F";  -- '?'
  constant ASC_UNDER : std_logic_vector(7 downto 0) := x"5F";  -- '_'

  -- A line filled with spaces.
  constant BLANK_LINE : lcd_line_t := (others => ASC_SPACE);

  -- Morse representation used everywhere in the design:
  --   len  : number of symbols (1 to 5; 0 means "no code")
  --   code : 5 bits, FIRST symbol in bit 4, '0' = dot, '1' = dash.
  --          Bits that are not used (below the last symbol) must be '0'.
  --   Example: 'A' = .-  -> len = 2, code = "01000"
  constant MORSE_MAX : natural := 5;

  -- Converts a text constant (up to 16 characters) into an LCD line,
  -- padding the rest with spaces. Only used with constant strings, so the
  -- synthesizer evaluates it at compile time (no hardware is generated).
  function to_line(s : string) return lcd_line_t;

end package morse_pkg;

package body morse_pkg is

  function to_line(s : string) return lcd_line_t is
    variable line_v : lcd_line_t := BLANK_LINE;
  begin
    for i in 0 to 15 loop
      if i < s'length then
        line_v(i) := std_logic_vector(
                       to_unsigned(character'pos(s(s'low + i)), 8));
      end if;
    end loop;
    return line_v;
  end function to_line;

end package body morse_pkg;
