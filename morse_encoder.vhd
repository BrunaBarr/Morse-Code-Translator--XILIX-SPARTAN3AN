-------------------------------------------------------------------------------
-- File: morse_encoder.vhd
-- Project: Morse code translator (EEL480 - TP1)
-- Description: Combinational ROM: ASCII character -> Morse code.
--              Covers A-Z and 0-9 (International Morse Code, ITU-R M.1677).
--
-- Output format (see morse_pkg):
--   len_o   : number of symbols (1 to 5), 0 when the character has no code
--   code_o  : first symbol in bit 4, '0' = dot, '1' = dash, unused bits = '0'
--   valid_o : '1' when char_i is a letter or a digit
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity morse_encoder is
  port (
    char_i  : in  std_logic_vector(7 downto 0);
    len_o   : out unsigned(2 downto 0);
    code_o  : out std_logic_vector(4 downto 0);
    valid_o : out std_logic
  );
end entity morse_encoder;

architecture rtl of morse_encoder is
begin

  -- Purely combinational: every input is in the sensitivity list and every
  -- output gets a value on every path (so no latches are inferred).
  process (char_i)
    variable len_i  : natural range 0 to 5;
    variable code_i : std_logic_vector(4 downto 0);
  begin
    case char_i is
      when x"41" => len_i := 2; code_i := "01000";  -- A  .-
      when x"42" => len_i := 4; code_i := "10000";  -- B  -...
      when x"43" => len_i := 4; code_i := "10100";  -- C  -.-.
      when x"44" => len_i := 3; code_i := "10000";  -- D  -..
      when x"45" => len_i := 1; code_i := "00000";  -- E  .
      when x"46" => len_i := 4; code_i := "00100";  -- F  ..-.
      when x"47" => len_i := 3; code_i := "11000";  -- G  --.
      when x"48" => len_i := 4; code_i := "00000";  -- H  ....
      when x"49" => len_i := 2; code_i := "00000";  -- I  ..
      when x"4A" => len_i := 4; code_i := "01110";  -- J  .---
      when x"4B" => len_i := 3; code_i := "10100";  -- K  -.-
      when x"4C" => len_i := 4; code_i := "01000";  -- L  .-..
      when x"4D" => len_i := 2; code_i := "11000";  -- M  --
      when x"4E" => len_i := 2; code_i := "10000";  -- N  -.
      when x"4F" => len_i := 3; code_i := "11100";  -- O  ---
      when x"50" => len_i := 4; code_i := "01100";  -- P  .--.
      when x"51" => len_i := 4; code_i := "11010";  -- Q  --.-
      when x"52" => len_i := 3; code_i := "01000";  -- R  .-.
      when x"53" => len_i := 3; code_i := "00000";  -- S  ...
      when x"54" => len_i := 1; code_i := "10000";  -- T  -
      when x"55" => len_i := 3; code_i := "00100";  -- U  ..-
      when x"56" => len_i := 4; code_i := "00010";  -- V  ...-
      when x"57" => len_i := 3; code_i := "01100";  -- W  .--
      when x"58" => len_i := 4; code_i := "10010";  -- X  -..-
      when x"59" => len_i := 4; code_i := "10110";  -- Y  -.--
      when x"5A" => len_i := 4; code_i := "11000";  -- Z  --..
      when x"30" => len_i := 5; code_i := "11111";  -- 0  -----
      when x"31" => len_i := 5; code_i := "01111";  -- 1  .----
      when x"32" => len_i := 5; code_i := "00111";  -- 2  ..---
      when x"33" => len_i := 5; code_i := "00011";  -- 3  ...--
      when x"34" => len_i := 5; code_i := "00001";  -- 4  ....-
      when x"35" => len_i := 5; code_i := "00000";  -- 5  .....
      when x"36" => len_i := 5; code_i := "10000";  -- 6  -....
      when x"37" => len_i := 5; code_i := "11000";  -- 7  --...
      when x"38" => len_i := 5; code_i := "11100";  -- 8  ---..
      when x"39" => len_i := 5; code_i := "11110";  -- 9  ----.
      when others => len_i := 0; code_i := "00000";  -- no Morse code
    end case;

    len_o  <= to_unsigned(len_i, 3);
    code_o <= code_i;
    if len_i = 0 then
      valid_o <= '0';
    else
      valid_o <= '1';
    end if;
  end process;

end architecture rtl;
