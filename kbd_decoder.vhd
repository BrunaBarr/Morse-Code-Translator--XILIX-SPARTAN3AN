-------------------------------------------------------------------------------
-- File       : kbd_decoder.vhd
-- Project    : Morse code translator (EEL480 - TP1)
-- Description: Turns the byte stream of a PS/2 keyboard (scan code set 2)
--              into "key pressed" events carrying an ASCII code.
--
-- What the keyboard sends:
--   key pressed          : <code>            e.g. 'A' -> 1C
--   key released         : F0 <code>         e.g. 'A' -> F0 1C
--   extended key pressed : E0 <code>         e.g. keypad Enter -> E0 5A
--   extended key released: E0 F0 <code>
--   key held down        : <code> repeated about every 100 ms (typematic)
--
-- Only key presses of known keys produce an event. Releases are ignored.
-- Special keys are mapped to ASCII control codes (see morse_pkg).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library work;
use work.morse_pkg.all;

entity kbd_decoder is
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    code_i       : in  std_logic_vector(7 downto 0);  -- byte from ps2_rx
    code_valid_i : in  std_logic;                     -- 1-cycle pulse
    ascii_o      : out std_logic_vector(7 downto 0);  -- ASCII of the key
    key_valid_o  : out std_logic                      -- 1-cycle pulse
  );
end entity kbd_decoder;

architecture rtl of kbd_decoder is

  -- S_NORMAL   : next byte is a normal scan code (or a prefix)
  -- S_BREAK    : got F0, next byte is the code of a released key (ignore it)
  -- S_EXT      : got E0, next byte is an extended code (or F0)
  -- S_EXT_BREAK: got E0 F0, next byte is a released extended key (ignore it)
  type state_t is (S_NORMAL, S_BREAK, S_EXT, S_EXT_BREAK);
  signal state : state_t := S_NORMAL;

  signal ascii_r : std_logic_vector(7 downto 0) := (others => '0');
  signal valid_r : std_logic := '0';

  constant PREFIX_BREAK : std_logic_vector(7 downto 0) := x"F0";
  constant PREFIX_EXT   : std_logic_vector(7 downto 0) := x"E0";
  constant NO_KEY       : std_logic_vector(7 downto 0) := x"00";

  -- Scan code set 2 -> ASCII (upper case). Returns x"00" for keys we do not
  -- use. Codes taken from UG334, Figure 8-3 (same for US and ABNT2 layouts).
  function scan_to_ascii(code : std_logic_vector(7 downto 0))
    return std_logic_vector is
  begin
    case code is
      -- letters
      when x"1C" => return x"41";  -- A
      when x"32" => return x"42";  -- B
      when x"21" => return x"43";  -- C
      when x"23" => return x"44";  -- D
      when x"24" => return x"45";  -- E
      when x"2B" => return x"46";  -- F
      when x"34" => return x"47";  -- G
      when x"33" => return x"48";  -- H
      when x"43" => return x"49";  -- I
      when x"3B" => return x"4A";  -- J
      when x"42" => return x"4B";  -- K
      when x"4B" => return x"4C";  -- L
      when x"3A" => return x"4D";  -- M
      when x"31" => return x"4E";  -- N
      when x"44" => return x"4F";  -- O
      when x"4D" => return x"50";  -- P
      when x"15" => return x"51";  -- Q
      when x"2D" => return x"52";  -- R
      when x"1B" => return x"53";  -- S
      when x"2C" => return x"54";  -- T
      when x"3C" => return x"55";  -- U
      when x"2A" => return x"56";  -- V
      when x"1D" => return x"57";  -- W
      when x"22" => return x"58";  -- X
      when x"35" => return x"59";  -- Y
      when x"1A" => return x"5A";  -- Z
      -- digits (main row)
      when x"45" => return x"30";  -- 0
      when x"16" => return x"31";  -- 1
      when x"1E" => return x"32";  -- 2
      when x"26" => return x"33";  -- 3
      when x"25" => return x"34";  -- 4
      when x"2E" => return x"35";  -- 5
      when x"36" => return x"36";  -- 6
      when x"3D" => return x"37";  -- 7
      when x"3E" => return x"38";  -- 8
      when x"46" => return x"39";  -- 9
      -- digits (numeric keypad, sent without E0)
      when x"70" => return x"30";  -- keypad 0
      when x"69" => return x"31";  -- keypad 1
      when x"72" => return x"32";  -- keypad 2
      when x"7A" => return x"33";  -- keypad 3
      when x"6B" => return x"34";  -- keypad 4
      when x"73" => return x"35";  -- keypad 5
      when x"74" => return x"36";  -- keypad 6
      when x"6C" => return x"37";  -- keypad 7
      when x"75" => return x"38";  -- keypad 8
      when x"7D" => return x"39";  -- keypad 9
      -- Morse symbols
      when x"49" => return ASC_DOT;    -- '.' (main keyboard)
      when x"71" => return ASC_DOT;    -- '.' / ',' (keypad)
      when x"6D" => return ASC_DOT;    -- '.' (keypad, ABNT2 only)
      when x"4E" => return ASC_DASH;   -- '-' (main keyboard)
      when x"7B" => return ASC_DASH;   -- '-' (keypad)
      -- control keys
      when x"29" => return ASC_SPACE;  -- Space
      when x"5A" => return ASC_ENTER;  -- Enter
      when x"66" => return ASC_BS;     -- Backspace
      when x"0D" => return ASC_TAB;    -- Tab
      when x"76" => return ASC_ESC;    -- Esc
      when others => return NO_KEY;
    end case;
  end function scan_to_ascii;

begin

  process (clk)
    variable ascii_v : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      valid_r <= '0';                       -- default: no event

      if rst = '1' then
        state <= S_NORMAL;
      elsif code_valid_i = '1' then
        case state is

          when S_NORMAL =>
            if code_i = PREFIX_BREAK then
              state <= S_BREAK;
            elsif code_i = PREFIX_EXT then
              state <= S_EXT;
            else
              ascii_v := scan_to_ascii(code_i);
              if ascii_v /= NO_KEY then
                ascii_r <= ascii_v;
                valid_r <= '1';
              end if;
            end if;

          when S_BREAK =>
            state <= S_NORMAL;              -- released key: ignore the code

          when S_EXT =>
            if code_i = PREFIX_BREAK then
              state <= S_EXT_BREAK;
            else
              -- The only extended key we use is the keypad Enter (E0 5A).
              -- Arrows, Insert, Delete, etc. are ignored.
              if code_i = x"5A" then
                ascii_r <= ASC_ENTER;
                valid_r <= '1';
              end if;
              state <= S_NORMAL;
            end if;

          when S_EXT_BREAK =>
            state <= S_NORMAL;              -- released extended key: ignore

        end case;
      end if;
    end if;
  end process;

  ascii_o     <= ascii_r;
  key_valid_o <= valid_r;

end architecture rtl;
