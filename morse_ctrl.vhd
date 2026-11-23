-------------------------------------------------------------------------------
-- File       : morse_ctrl.vhd
-- Project    : Morse code translator (EEL480 - TP1)
-- Description: Main control unit (finite state machine + text buffer).
--
-- Two modes, toggled with the TAB key:
--
--   TX (text -> Morse): the user types letters/digits. Each character is
--       added to line 1 and its Morse code is shown on line 2.
--         LCD:  |SOS             |
--               |TX> S = ...     |
--
--   RX (Morse -> text): the user types '.' and '-' (up to 5 symbols) and
--       confirms with ENTER. The decoded character ('?' if invalid) is added
--       to line 1.
--         LCD:  |SOS R           |
--               |RX> .-.   = R   |
--
--   Keys valid in both modes: SPACE adds a space, BACKSPACE erases,
--   ESC clears everything, TAB switches the mode.
--
-- Structure: the FSM (control) decides WHAT to do with each key and raises
-- one of three "actions" (append / backspace / clear). The text buffer
-- (datapath) at the end of the process carries the action out.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.morse_pkg.all;

entity morse_ctrl is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    -- key events from kbd_decoder
    key_valid_i : in  std_logic;
    key_ascii_i : in  std_logic_vector(7 downto 0);
    -- Morse code of key_ascii_i, from morse_encoder
    enc_len_i   : in  unsigned(2 downto 0);
    enc_code_i  : in  std_logic_vector(4 downto 0);
    enc_valid_i : in  std_logic;
    -- symbols typed in RX mode, to morse_decoder, and its answer
    sym_len_o   : out unsigned(2 downto 0);
    sym_code_o  : out std_logic_vector(4 downto 0);
    dec_char_i  : in  std_logic_vector(7 downto 0);
    -- text for the display
    line1_o     : out lcd_line_t;
    line2_o     : out lcd_line_t
  );
end entity morse_ctrl;

architecture rtl of morse_ctrl is

  -- S_TX_IDLE : TX mode, nothing typed yet (shows a hint)
  -- S_TX_SHOW : TX mode, showing the last character and its code
  -- S_RX_INPUT: RX mode, collecting dots and dashes
  -- S_RX_SHOW : RX mode, showing the code that was just decoded
  type state_t is (S_TX_IDLE, S_TX_SHOW, S_RX_INPUT, S_RX_SHOW);
  signal state : state_t := S_TX_IDLE;

  -- Text buffer (line 1)
  signal text_r   : lcd_line_t := BLANK_LINE;
  signal text_cnt : natural range 0 to 16 := 0;   -- characters in use

  -- Last character typed in TX mode
  signal last_char : std_logic_vector(7 downto 0) := ASC_SPACE;
  signal last_len  : unsigned(2 downto 0) := (others => '0');
  signal last_code : std_logic_vector(4 downto 0) := (others => '0');

  -- Symbols typed in RX mode and the result of the last decoding
  signal sym_len  : natural range 0 to MORSE_MAX := 0;
  signal sym_code : std_logic_vector(4 downto 0) := (others => '0');
  signal res_char : std_logic_vector(7 downto 0) := ASC_SPACE;

  -- Writes the symbols of a Morse code as '.' and '-' into an LCD line,
  -- starting at column "col".
  procedure put_code(variable l    : inout lcd_line_t;
                     constant col  : in    natural;
                     constant len  : in    natural;
                     constant code : in    std_logic_vector(4 downto 0)) is
  begin
    for k in 0 to MORSE_MAX - 1 loop
      if k < len then
        if code(4 - k) = '1' then
          l(col + k) := ASC_DASH;
        else
          l(col + k) := ASC_DOT;
        end if;
      end if;
    end loop;
  end procedure put_code;

begin

  -----------------------------------------------------------------------------
  -- FSM + text buffer
  -----------------------------------------------------------------------------
  control : process (clk)
    variable do_append : boolean;   -- add new_char to the end of the text
    variable do_back   : boolean;   -- erase the last character of the text
    variable do_clear  : boolean;   -- erase the whole text
    variable new_char  : std_logic_vector(7 downto 0);
    variable sym_bit   : std_logic;
  begin
    if rising_edge(clk) then
      -- defaults
      do_append := false;
      do_back   := false;
      do_clear  := false;
      new_char  := ASC_SPACE;

      if rst = '1' then
        state    <= S_TX_IDLE;
        sym_len  <= 0;
        sym_code <= (others => '0');
        do_clear := true;

      elsif key_valid_i = '1' then

        -- Keys that behave the same way in every state ------------------------
        if key_ascii_i = ASC_ESC then
          do_clear := true;
          sym_len  <= 0;
          sym_code <= (others => '0');
          if state = S_TX_IDLE or state = S_TX_SHOW then
            state <= S_TX_IDLE;
          else
            state <= S_RX_INPUT;
          end if;

        elsif key_ascii_i = ASC_TAB then
          sym_len  <= 0;
          sym_code <= (others => '0');
          if state = S_TX_IDLE or state = S_TX_SHOW then
            state <= S_RX_INPUT;
          else
            state <= S_TX_IDLE;
          end if;

        -- Keys that depend on the state --------------------------------------
        else
          case state is

            when S_TX_IDLE | S_TX_SHOW =>
              if enc_valid_i = '1' then          -- letter or digit
                new_char  := key_ascii_i;
                do_append := true;
                last_char <= key_ascii_i;        -- remembered for line 2
                last_len  <= enc_len_i;
                last_code <= enc_code_i;
                state     <= S_TX_SHOW;
              elsif key_ascii_i = ASC_SPACE then
                do_append := true;               -- new_char is already ' '
              elsif key_ascii_i = ASC_BS then
                do_back := true;
              end if;                            -- other keys: ignored

            when S_RX_INPUT | S_RX_SHOW =>
              if key_ascii_i = ASC_DOT or key_ascii_i = ASC_DASH then
                if key_ascii_i = ASC_DASH then
                  sym_bit := '1';
                else
                  sym_bit := '0';
                end if;

                if state = S_RX_SHOW then
                  -- first symbol of a new character
                  sym_code <= sym_bit & "0000";
                  sym_len  <= 1;
                  state    <= S_RX_INPUT;
                elsif sym_len < MORSE_MAX then
                  -- symbol number sym_len goes to bit 4 - sym_len
                  sym_code(4 - sym_len) <= sym_bit;
                  sym_len <= sym_len + 1;
                end if;                          -- 5 symbols already: ignore

              elsif key_ascii_i = ASC_ENTER then
                if state = S_RX_INPUT and sym_len > 0 then
                  res_char  <= dec_char_i;       -- decoder output ('?' if bad)
                  new_char  := dec_char_i;
                  do_append := true;
                  state     <= S_RX_SHOW;
                end if;

              elsif key_ascii_i = ASC_SPACE then
                do_append := true;
                if state = S_RX_SHOW then
                  sym_len  <= 0;
                  sym_code <= (others => '0');
                  state    <= S_RX_INPUT;
                end if;

              elsif key_ascii_i = ASC_BS then
                if state = S_RX_INPUT and sym_len > 0 then
                  -- erase the last symbol (it is in bit 5 - sym_len)
                  sym_code(5 - sym_len) <= '0';
                  sym_len <= sym_len - 1;
                else
                  do_back  := true;              -- erase a text character
                  sym_len  <= 0;
                  sym_code <= (others => '0');
                  state    <= S_RX_INPUT;
                end if;
              end if;

          end case;
        end if;
      end if;

      -- Datapath: text buffer ------------------------------------------------
      if do_clear then
        text_r   <= BLANK_LINE;
        text_cnt <= 0;
      elsif do_append then
        if text_cnt < 16 then
          text_r(text_cnt) <= new_char;
          text_cnt         <= text_cnt + 1;
        else
          -- line full: scroll everything one position to the left
          for i in 0 to 14 loop
            text_r(i) <= text_r(i + 1);
          end loop;
          text_r(15) <= new_char;
        end if;
      elsif do_back then
        if text_cnt > 0 then
          text_r(text_cnt - 1) <= ASC_SPACE;
          text_cnt             <= text_cnt - 1;
        end if;
      end if;
    end if;
  end process control;

  -----------------------------------------------------------------------------
  -- Line 2 composer (combinational): builds the status line from the state
  -----------------------------------------------------------------------------
  compose : process (state, last_char, last_len, last_code,
                     sym_len, sym_code, res_char)
    variable l : lcd_line_t;
  begin
    case state is

      when S_TX_IDLE =>
        l := to_line("TX> digite texto");

      when S_TX_SHOW =>                          -- "TX> A = .-"
        l    := to_line("TX>   =");
        l(4) := last_char;
        put_code(l, 8, to_integer(last_len), last_code);

      when S_RX_INPUT =>                         -- "RX> .-._"
        if sym_len = 0 then
          l := to_line("RX> . - e Enter");       -- hint
        else
          l := to_line("RX>");
          put_code(l, 4, sym_len, sym_code);
          l(4 + sym_len) := ASC_UNDER;           -- cursor
        end if;

      when S_RX_SHOW =>                          -- "RX> .-.   = R"
        l := to_line("RX>");
        put_code(l, 4, sym_len, sym_code);
        l(10) := ASC_EQUAL;
        l(12) := res_char;

    end case;
    line2_o <= l;
  end process compose;

  -- outputs
  line1_o    <= text_r;
  sym_len_o  <= to_unsigned(sym_len, 3);
  sym_code_o <= sym_code;

end architecture rtl;
