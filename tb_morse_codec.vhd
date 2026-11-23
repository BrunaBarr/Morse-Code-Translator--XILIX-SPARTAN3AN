-------------------------------------------------------------------------------
-- File       : tb_morse_codec.vhd
-- Description: Self-checking testbench for morse_encoder and morse_decoder.
--   1. Round trip: for every letter and digit, encode then decode and check
--      that we get the same character back.
--   2. Spot checks of known codes (A, S, O, 0, 5).
--   3. Exhaustive: all 62 possible sequences of 1 to 5 symbols; exactly 36
--      must decode to a character, the other 26 must give '?'.
--   4. Characters without Morse code must give valid = '0'.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_morse_codec is
end entity tb_morse_codec;

architecture sim of tb_morse_codec is

  signal enc_char  : std_logic_vector(7 downto 0) := x"00";
  signal enc_len   : unsigned(2 downto 0);
  signal enc_code  : std_logic_vector(4 downto 0);
  signal enc_valid : std_logic;

  signal dec_len   : unsigned(2 downto 0) := (others => '0');
  signal dec_code  : std_logic_vector(4 downto 0) := (others => '0');
  signal dec_char  : std_logic_vector(7 downto 0);

  function chr(v : std_logic_vector(7 downto 0)) return character is
  begin
    return character'val(to_integer(unsigned(v)));
  end function;

begin

  u_enc : entity work.morse_encoder
    port map (char_i => enc_char, len_o => enc_len,
              code_o => enc_code, valid_o => enc_valid);

  u_dec : entity work.morse_decoder
    port map (len_i => dec_len, code_i => dec_code, char_o => dec_char);

  stim : process
    variable errors : natural := 0;
    variable found  : natural := 0;
    variable c      : natural;

    -- checks the encoder output for one character
    procedure check_code(ch : character; len : natural; code : string) is
      variable exp : std_logic_vector(4 downto 0);
    begin
      for i in 0 to 4 loop
        if code(code'low + i) = '1' then exp(4 - i) := '1';
        else exp(4 - i) := '0'; end if;
      end loop;
      enc_char <= std_logic_vector(to_unsigned(character'pos(ch), 8));
      wait for 10 ns;
      if to_integer(enc_len) /= len or enc_code /= exp then
        report "wrong code for " & ch severity error;
        errors := errors + 1;
      end if;
    end procedure;

  begin
    ---------------------------------------------------------------------------
    -- 1. round trip
    ---------------------------------------------------------------------------
    for i in 0 to 35 loop
      if i < 10 then c := 16#30# + i;         -- '0'..'9'
      else           c := 16#41# + i - 10;    -- 'A'..'Z'
      end if;
      enc_char <= std_logic_vector(to_unsigned(c, 8));
      wait for 10 ns;
      dec_len  <= enc_len;
      dec_code <= enc_code;
      wait for 10 ns;
      if enc_valid /= '1' then
        report "no code for " & chr(enc_char) severity error;
        errors := errors + 1;
      elsif dec_char /= enc_char then
        report "round trip failed: " & chr(enc_char) & " -> " & chr(dec_char)
          severity error;
        errors := errors + 1;
      end if;
    end loop;

    ---------------------------------------------------------------------------
    -- 2. spot checks                     (1 = dash, 0 = dot, first on the left)
    ---------------------------------------------------------------------------
    check_code('A', 2, "01000");  -- .-
    check_code('S', 3, "00000");  -- ...
    check_code('O', 3, "11100");  -- ---
    check_code('0', 5, "11111");  -- -----
    check_code('5', 5, "00000");  -- .....
    check_code('Q', 4, "11010");  -- --.-

    ---------------------------------------------------------------------------
    -- 3. exhaustive decoder test
    ---------------------------------------------------------------------------
    for len in 1 to 5 loop
      for pattern in 0 to 2**len - 1 loop
        dec_len  <= to_unsigned(len, 3);
        -- place the pattern in the top "len" bits, the rest stays '0'
        dec_code <= std_logic_vector(to_unsigned(pattern * 2**(5 - len), 5));
        wait for 10 ns;
        if dec_char /= x"3F" then
          found := found + 1;
        end if;
      end loop;
    end loop;
    if found /= 36 then
      report "expected 36 valid codes, found " & integer'image(found)
        severity error;
      errors := errors + 1;
    end if;

    -- length 0 and 6 are never valid
    dec_len <= "000"; wait for 10 ns;
    if dec_char /= x"3F" then errors := errors + 1;
      report "len 0 should give ?" severity error; end if;
    dec_len <= "110"; wait for 10 ns;
    if dec_char /= x"3F" then errors := errors + 1;
      report "len 6 should give ?" severity error; end if;

    -- garbage after the last symbol must be ignored: len 2, ".-" + "111"
    dec_len <= "010"; dec_code <= "01111"; wait for 10 ns;
    if dec_char /= x"41" then errors := errors + 1;
      report "mask test failed" severity error; end if;

    ---------------------------------------------------------------------------
    -- 4. characters without Morse code
    ---------------------------------------------------------------------------
    for i in 0 to 3 loop
      case i is
        when 0      => enc_char <= x"20";  -- ' '
        when 1      => enc_char <= x"2E";  -- '.'
        when 2      => enc_char <= x"61";  -- 'a' (lower case is not used)
        when others => enc_char <= x"0D";  -- Enter
      end case;
      wait for 10 ns;
      if enc_valid /= '0' then
        errors := errors + 1;
        report "unexpected code for ASCII " &
          integer'image(to_integer(unsigned(enc_char))) severity error;
      end if;
    end loop;

    ---------------------------------------------------------------------------
    report "tb_morse_codec finished: " & integer'image(errors) & " error(s), "
      & integer'image(found) & " valid codes found";
    wait;
  end process;

end architecture sim;
