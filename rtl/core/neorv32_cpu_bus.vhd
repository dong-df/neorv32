-- #################################################################################################
-- # << NEORV32 - Bus Interface Unit >>                                                            #
-- # ********************************************************************************************* #
-- # Instruction and data bus interfaces.                                                          #
-- # ********************************************************************************************* #
-- # BSD 3-Clause License                                                                          #
-- #                                                                                               #
-- # Copyright (c) 2020, Stephan Nolting. All rights reserved.                                     #
-- #                                                                                               #
-- # Redistribution and use in source and binary forms, with or without modification, are          #
-- # permitted provided that the following conditions are met:                                     #
-- #                                                                                               #
-- # 1. Redistributions of source code must retain the above copyright notice, this list of        #
-- #    conditions and the following disclaimer.                                                   #
-- #                                                                                               #
-- # 2. Redistributions in binary form must reproduce the above copyright notice, this list of     #
-- #    conditions and the following disclaimer in the documentation and/or other materials        #
-- #    provided with the distribution.                                                            #
-- #                                                                                               #
-- # 3. Neither the name of the copyright holder nor the names of its contributors may be used to  #
-- #    endorse or promote products derived from this software without specific prior written      #
-- #    permission.                                                                                #
-- #                                                                                               #
-- # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS   #
-- # OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF               #
-- # MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE    #
-- # COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,     #
-- # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE #
-- # GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED    #
-- # AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING     #
-- # NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED  #
-- # OF THE POSSIBILITY OF SUCH DAMAGE.                                                            #
-- # ********************************************************************************************* #
-- # The NEORV32 Processor - https://github.com/stnolting/neorv32              (c) Stephan Nolting #
-- #################################################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cpu_bus is
  generic (
    CPU_EXTENSION_RISCV_C : boolean := true; -- implement compressed extension?
    MEM_EXT_TIMEOUT       : natural := 15 -- cycles after which a valid bus access will timeout
  );
  port (
    -- global control --
    clk_i          : in  std_ulogic; -- global clock, rising edge
    rstn_i         : in  std_ulogic; -- global reset, low-active, async
    ctrl_i         : in  std_ulogic_vector(ctrl_width_c-1 downto 0); -- main control bus
    -- cpu instruction fetch interface --
    fetch_pc_i     : in  std_ulogic_vector(data_width_c-1 downto 0); -- PC for instruction fetch
    instr_o        : out std_ulogic_vector(data_width_c-1 downto 0); -- instruction
    i_wait_o       : out std_ulogic; -- wait for fetch to complete
    --
    ma_instr_o     : out std_ulogic; -- misaligned instruction address
    be_instr_o     : out std_ulogic; -- bus error on instruction access
    -- cpu data access interface --
    addr_i         : in  std_ulogic_vector(data_width_c-1 downto 0); -- ALU result -> access address
    wdata_i        : in  std_ulogic_vector(data_width_c-1 downto 0); -- write data
    rdata_o        : out std_ulogic_vector(data_width_c-1 downto 0); -- read data
    mar_o          : out std_ulogic_vector(data_width_c-1 downto 0); -- current memory address register
    d_wait_o       : out std_ulogic; -- wait for access to complete
    --
    ma_load_o      : out std_ulogic; -- misaligned load data address
    ma_store_o     : out std_ulogic; -- misaligned store data address
    be_load_o      : out std_ulogic; -- bus error on load data access
    be_store_o     : out std_ulogic; -- bus error on store data access
    -- instruction bus --
    i_bus_addr_o   : out std_ulogic_vector(data_width_c-1 downto 0); -- bus access address
    i_bus_rdata_i  : in  std_ulogic_vector(data_width_c-1 downto 0); -- bus read data
    i_bus_wdata_o  : out std_ulogic_vector(data_width_c-1 downto 0); -- bus write data
    i_bus_ben_o    : out std_ulogic_vector(03 downto 0); -- byte enable
    i_bus_we_o     : out std_ulogic; -- write enable
    i_bus_re_o     : out std_ulogic; -- read enable
    i_bus_cancel_o : out std_ulogic; -- cancel current bus transaction
    i_bus_ack_i    : in  std_ulogic; -- bus transfer acknowledge
    i_bus_err_i    : in  std_ulogic; -- bus transfer error
    i_bus_fence_o  : out std_ulogic; -- fence operation
    -- data bus --
    d_bus_addr_o   : out std_ulogic_vector(data_width_c-1 downto 0); -- bus access address
    d_bus_rdata_i  : in  std_ulogic_vector(data_width_c-1 downto 0); -- bus read data
    d_bus_wdata_o  : out std_ulogic_vector(data_width_c-1 downto 0); -- bus write data
    d_bus_ben_o    : out std_ulogic_vector(03 downto 0); -- byte enable
    d_bus_we_o     : out std_ulogic; -- write enable
    d_bus_re_o     : out std_ulogic; -- read enable
    d_bus_cancel_o : out std_ulogic; -- cancel current bus transaction
    d_bus_ack_i    : in  std_ulogic; -- bus transfer acknowledge
    d_bus_err_i    : in  std_ulogic; -- bus transfer error
    d_bus_fence_o  : out std_ulogic  -- fence operation
  );
end neorv32_cpu_bus;

architecture neorv32_cpu_bus_rtl of neorv32_cpu_bus is

  -- data interface registers --
  signal mar, mdo, mdi : std_ulogic_vector(data_width_c-1 downto 0);

  -- data access --
  signal d_bus_wdata : std_ulogic_vector(data_width_c-1 downto 0); -- write data
  signal d_bus_rdata : std_ulogic_vector(data_width_c-1 downto 0); -- read data
  signal d_bus_ben   : std_ulogic_vector(3 downto 0); -- write data byte enable

  -- misaligned access? --
  signal d_misaligned, i_misaligned : std_ulogic;

  -- bus arbiter --
  type bus_arbiter_t is record
    rd_req    : std_ulogic; -- read access in progress
    wr_req    : std_ulogic; -- write access in progress
    err_align : std_ulogic; -- alignment error
    err_bus   : std_ulogic; -- bus access error
    timeout   : std_ulogic_vector(index_size_f(MEM_EXT_TIMEOUT)-1 downto 0);
  end record;
  signal i_arbiter, d_arbiter : bus_arbiter_t;

begin

  -- Data Interface: Access Address ---------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  mem_adr_reg: process(rstn_i, clk_i)
  begin
    if rising_edge(clk_i) then
      if (ctrl_i(ctrl_bus_mar_we_c) = '1') then
        mar <= addr_i;
      end if;
    end if;
  end process mem_adr_reg;

  -- read-back for exception controller --
  mar_o <= mar;

  -- alignment check --
  misaligned_d_check: process(mar, ctrl_i)
  begin
    -- check data access --
    d_misaligned <= '0'; -- default
    case ctrl_i(ctrl_bus_size_msb_c downto ctrl_bus_size_lsb_c) is -- data size
      when "00" => -- byte
        d_misaligned <= '0';
      when "01" => -- half-word
        if (mar(0) /= '0') then
          d_misaligned <= '1';
        end if;
      when others => -- word
        if (mar(1 downto 0) /= "00") then
          d_misaligned <= '1';
        end if;
    end case;
  end process misaligned_d_check;


  -- Data Interface: Write Data -------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  mem_do_reg: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (ctrl_i(ctrl_bus_mdo_we_c) = '1') then
        mdo <= wdata_i;
      end if;
    end if;
  end process mem_do_reg;

  -- byte enable and output data alignment --
  byte_enable: process(mar, mdo, ctrl_i)
  begin
    case ctrl_i(ctrl_bus_size_msb_c downto ctrl_bus_size_lsb_c) is -- data size
      when "00" => -- byte
        d_bus_wdata(07 downto 00) <= mdo(07 downto 00);
        d_bus_wdata(15 downto 08) <= mdo(07 downto 00);
        d_bus_wdata(23 downto 16) <= mdo(07 downto 00);
        d_bus_wdata(31 downto 24) <= mdo(07 downto 00);
        d_bus_ben <= (others => '0');
        d_bus_ben(to_integer(unsigned(mar(1 downto 0)))) <= '1';
      when "01" => -- half-word
        d_bus_wdata(31 downto 16) <= mdo(15 downto 00);
        d_bus_wdata(15 downto 00) <= mdo(15 downto 00);
        if (mar(1) = '0') then
          d_bus_ben <= "0011"; -- low half-word
        else
          d_bus_ben <= "1100"; -- high half-word
        end if;
      when others => -- word
        d_bus_wdata <= mdo;
        d_bus_ben   <= "1111"; -- full word
    end case;
  end process byte_enable;


  -- Data Interface: Read Data --------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  mem_out_buf: process(clk_i)
  begin
    if rising_edge(clk_i) then
      -- memory data in register (MDI) --
      if (ctrl_i(ctrl_bus_mdi_we_c) = '1') then
        mdi <= d_bus_rdata;
      end if;
    end if;
  end process mem_out_buf;

  -- input data alignment and sign extension --
  read_align: process(mdi, mar, ctrl_i)
    variable signed_v : std_ulogic;
  begin
    signed_v := not ctrl_i(ctrl_bus_unsigned_c);
    case ctrl_i(ctrl_bus_size_msb_c downto ctrl_bus_size_lsb_c) is -- data size
      when "00" => -- byte
        case mar(1 downto 0) is
          when "00" =>
            rdata_o(31 downto 08) <= (others => (signed_v and mdi(07)));
            rdata_o(07 downto 00) <= mdi(07 downto 00); -- byte 0
          when "01" =>
            rdata_o(31 downto 08) <= (others => (signed_v and mdi(15)));
            rdata_o(07 downto 00) <= mdi(15 downto 08); -- byte 1
          when "10" =>
            rdata_o(31 downto 08) <= (others => (signed_v and mdi(23)));
            rdata_o(07 downto 00) <= mdi(23 downto 16); -- byte 2
          when others =>
            rdata_o(31 downto 08) <= (others => (signed_v and mdi(31)));
            rdata_o(07 downto 00) <= mdi(31 downto 24); -- byte 3
        end case;
      when "01" => -- half-word
        if (mar(1) = '0') then
          rdata_o(31 downto 16) <= (others => (signed_v and mdi(15)));
          rdata_o(15 downto 00) <= mdi(15 downto 00); -- low half-word
        else
          rdata_o(31 downto 16) <= (others => (signed_v and mdi(31)));
          rdata_o(15 downto 00) <= mdi(31 downto 16); -- high half-word
        end if;
      when others => -- word
        rdata_o <= mdi; -- full word
    end case;
  end process read_align;


  -- Instruction Interface: Check for Misaligned Access -------------------------------------
  -- -------------------------------------------------------------------------------------------
  misaligned_i_check: process(ctrl_i, fetch_pc_i)
  begin
    -- check instruction access --
    i_misaligned <= '0'; -- default
    if (CPU_EXTENSION_RISCV_C = true) then -- 16-bit and 32-bit instruction accesses
      i_misaligned <= '0'; -- no alignment exceptions possible
    else -- 32-bit instruction accesses only
      if (fetch_pc_i(1) = '1') then -- PC(0) is always zero
        i_misaligned <= '1';
      end if; 
    end if;
  end process misaligned_i_check;


  -- Instruction Fetch Arbiter --------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  ifetch_arbiter: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      i_arbiter.rd_req    <= '0';
      i_arbiter.wr_req    <= '0';
      i_arbiter.err_align <= '0';
      i_arbiter.err_bus   <= '0';
      i_arbiter.timeout   <= (others => '0');
    elsif rising_edge(clk_i) then
      i_arbiter.wr_req <= '0'; -- instruction fetch is read-only

      -- instruction fetch request --
      if (i_arbiter.rd_req = '0') then -- idle
        i_arbiter.rd_req    <= ctrl_i(ctrl_bus_if_c);
        i_arbiter.err_align <= i_misaligned;
        i_arbiter.err_bus   <= '0';
        i_arbiter.timeout   <= std_ulogic_vector(to_unsigned(MEM_EXT_TIMEOUT, index_size_f(MEM_EXT_TIMEOUT)));
      else -- in progress
        i_arbiter.timeout   <= std_ulogic_vector(unsigned(i_arbiter.timeout) - 1);
        i_arbiter.err_align <= (i_arbiter.err_align or i_misaligned)                                     and (not ctrl_i(ctrl_bus_ierr_ack_c));
        i_arbiter.err_bus   <= (i_arbiter.err_bus   or (not or_all_f(i_arbiter.timeout)) or i_bus_err_i) and (not ctrl_i(ctrl_bus_ierr_ack_c));
        if (i_arbiter.err_align = '1') or (i_arbiter.err_bus = '1') then -- any error?
          if (ctrl_i(ctrl_bus_ierr_ack_c) = '1') then -- wait for controller to acknowledge error
            i_arbiter.rd_req <= '0';
          end if;
        elsif (i_bus_ack_i = '1') then -- wait for normal termination
         i_arbiter.rd_req <= '0';
        end if;
      end if;

      -- cancel bus access --
      i_bus_cancel_o <= i_arbiter.rd_req and ctrl_i(ctrl_bus_ierr_ack_c);
    end if;
  end process ifetch_arbiter;


  -- wait for bus transaction to finish --
  i_wait_o <= i_arbiter.rd_req and (not i_bus_ack_i);

  -- output instruction fetch error to controller --
  ma_instr_o <= i_arbiter.err_align;
  be_instr_o <= i_arbiter.err_bus;

  -- instruction bus (read-only) --
  i_bus_addr_o  <= fetch_pc_i;
  i_bus_wdata_o <= (others => '0');
  i_bus_ben_o   <= (others => '0');
  i_bus_we_o    <= '0';
  i_bus_re_o    <= ctrl_i(ctrl_bus_if_c) and (not i_misaligned); -- no actual read when misaligned
  i_bus_fence_o <= ctrl_i(ctrl_bus_fencei_c);
  instr_o       <= i_bus_rdata_i;


  -- Data Access Arbiter --------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  data_access_arbiter: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      d_arbiter.rd_req    <= '0';
      d_arbiter.wr_req    <= '0';
      d_arbiter.err_align <= '0';
      d_arbiter.err_bus   <= '0';
      d_arbiter.timeout   <= (others => '0');
    elsif rising_edge(clk_i) then

      -- data access request --
      if (d_arbiter.wr_req = '0') and (d_arbiter.rd_req = '0') then -- idle
        d_arbiter.wr_req    <= ctrl_i(ctrl_bus_wr_c);
        d_arbiter.rd_req    <= ctrl_i(ctrl_bus_rd_c);
        d_arbiter.err_align <= d_misaligned;
        d_arbiter.err_bus   <= '0';
        d_arbiter.timeout   <= std_ulogic_vector(to_unsigned(MEM_EXT_TIMEOUT, index_size_f(MEM_EXT_TIMEOUT)));
      else -- in progress
        d_arbiter.timeout   <= std_ulogic_vector(unsigned(d_arbiter.timeout) - 1);
        d_arbiter.err_align <= (d_arbiter.err_align or d_misaligned)                                     and (not ctrl_i(ctrl_bus_derr_ack_c));
        d_arbiter.err_bus   <= (d_arbiter.err_bus   or (not or_all_f(d_arbiter.timeout)) or d_bus_err_i) and (not ctrl_i(ctrl_bus_derr_ack_c));
        if (d_arbiter.err_align = '1') or (d_arbiter.err_bus = '1') then -- any error?
          if (ctrl_i(ctrl_bus_derr_ack_c) = '1') then -- wait for controller to acknowledge error
            d_arbiter.wr_req <= '0';
            d_arbiter.rd_req <= '0';
          end if;
        elsif (d_bus_ack_i = '1') then -- wait for normal termination
          d_arbiter.wr_req <= '0';
          d_arbiter.rd_req <= '0';
        end if;
      end if;

      -- cancel bus access --
      d_bus_cancel_o <= (d_arbiter.wr_req or d_arbiter.rd_req) and ctrl_i(ctrl_bus_derr_ack_c);
    end if;
  end process data_access_arbiter;


  -- wait for bus transaction to finish --
  d_wait_o <= (d_arbiter.wr_req or d_arbiter.rd_req) and (not d_bus_ack_i);

  -- output data access error to controller --
  ma_load_o  <= d_arbiter.rd_req and d_arbiter.err_align;
  be_load_o  <= d_arbiter.rd_req and d_arbiter.err_bus;
  ma_store_o <= d_arbiter.wr_req and d_arbiter.err_align;
  be_store_o <= d_arbiter.wr_req and d_arbiter.err_bus;

  -- data bus --
  d_bus_addr_o  <= mar;
  d_bus_wdata_o <= d_bus_wdata;
  d_bus_ben_o   <= d_bus_ben;
  d_bus_we_o    <= ctrl_i(ctrl_bus_wr_c) and (not d_misaligned); -- no actual write when misaligned
  d_bus_re_o    <= ctrl_i(ctrl_bus_rd_c) and (not d_misaligned); -- no actual read when misaligned
  d_bus_fence_o <= ctrl_i(ctrl_bus_fence_c);
  d_bus_rdata   <= d_bus_rdata_i;


end neorv32_cpu_bus_rtl;
