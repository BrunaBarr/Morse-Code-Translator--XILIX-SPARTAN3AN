-------------------------------------------------------------------------------
-- File       : morse_decoder.vhd
-- Description: Combinational ROM: Morse code -> ASCII character.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity morse_decoder is
  port (
    len_i  : in  unsigned(2 downto 0);
    code_i : in  std_logic_vector(4 downto 0);
    char_o : out std_logic_vector(7 downto 0)
  );
end entity morse_decoder;

architecture rtl of morse_decoder is
begin

  process (len_i, code_i)
    variable masked : std_logic_vector(4 downto 0);
    variable key    : std_logic_vector(7 downto 0);
  begin
    -- Force the unused bits to '0' so the table below always matches,
    -- even if the caller left garbage after the last symbol.
    -- Symbol k (k = 0 is the first) is stored in bit 4-k, so bit b is
    -- used only when 4-b < len.
    for b in 0 to 4 loop
      if (4 - b) < to_integer(len_i) then
        masked(b) := code_i(b);
      else
        masked(b) := '0';
      end if;
    end loop;

    -- A case expression must have a fixed size, so we build it in a
    -- variable: 3 bits of length followed by 5 bits of code.
    key := std_logic_vector(len_i) & masked;

    case key is
      when "01001000" => char_o <= x"41";  -- .-    -> A
      when "10010000" => char_o <= x"42";  -- -...  -> B
      when "10010100" => char_o <= x"43";  -- -.-.  -> C
      when "01110000" => char_o <= x"44";  -- -..   -> D
      when "00100000" => char_o <= x"45";  -- .     -> E
      when "10000100" => char_o <= x"46";  -- ..-.  -> F
      when "01111000" => char_o <= x"47";  -- --.   -> G
      when "10000000" => char_o <= x"48";  -- ....  -> H
      when "01000000" => char_o <= x"49";  -- ..    -> I
      when "10001110" => char_o <= x"4A";  -- .---  -> J
      when "01110100" => char_o <= x"4B";  -- -.-   -> K
      when "10001000" => char_o <= x"4C";  -- .-..  -> L
      when "01011000" => char_o <= x"4D";  -- --    -> M
      when "01010000" => char_o <= x"4E";  -- -.    -> N
      when "01111100" => char_o <= x"4F";  -- ---   -> O
      when "10001100" => char_o <= x"50";  -- .--.  -> P
      when "10011010" => char_o <= x"51";  -- --.-  -> Q
      when "01101000" => char_o <= x"52";  -- .-.   -> R
      when "01100000" => char_o <= x"53";  -- ...   -> S
      when "00110000" => char_o <= x"54";  -- -     -> T
      when "01100100" => char_o <= x"55";  -- ..-   -> U
      when "10000010" => char_o <= x"56";  -- ...-  -> V
      when "01101100" => char_o <= x"57";  -- .--   -> W
      when "10010010" => char_o <= x"58";  -- -..-  -> X
      when "10010110" => char_o <= x"59";  -- -.--  -> Y
      when "10011000" => char_o <= x"5A";  -- --..  -> Z
      when "10111111" => char_o <= x"30";  -- ----- -> 0
      when "10101111" => char_o <= x"31";  -- .---- -> 1
      when "10100111" => char_o <= x"32";  -- ..--- -> 2
      when "10100011" => char_o <= x"33";  -- ...-- -> 3
      when "10100001" => char_o <= x"34";  -- ....- -> 4
      when "10100000" => char_o <= x"35";  -- ..... -> 5
      when "10110000" => char_o <= x"36";  -- -.... -> 6
      when "10111000" => char_o <= x"37";  -- --... -> 7
      when "10111100" => char_o <= x"38";  -- ---.. -> 8
      when "10111110" => char_o <= x"39";  -- ----. -> 9
      when others => char_o <= x"3F";  -- '?' : not a valid letter/digit
    end case;
  end process;

end architecture rtl;
