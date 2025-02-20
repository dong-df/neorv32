# ================================================================================ #
# NEORV32 Application Software Makefile                                            #
# -------------------------------------------------------------------------------- #
# Do not edit this file! Use the re-defines in the project-local makefile instead. #
# -------------------------------------------------------------------------------- #
# The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              #
# Copyright (c) NEORV32 contributors.                                              #
# Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved.                  #
# Licensed under the BSD-3-Clause license, see LICENSE for details.                #
# SPDX-License-Identifier: BSD-3-Clause                                            #
# ================================================================================ #

# -----------------------------------------------------------------------------
# Default configuration (DO NOT EDIT THIS FILE! REDEFINE / OVERRIDE THE DEFAULT
# CONFIGURATION WHEN INCLUDING THIS MAKEFILE IN THE PROJECT-SPECIFIC MAKEFILE)
# -----------------------------------------------------------------------------

# User's application sources (*.c, *.cpp, *.s, *.S); add additional files here
APP_SRC ?= $(wildcard ./*.c) $(wildcard ./*.s) $(wildcard ./*.cpp) $(wildcard ./*.S)

# User's application include folders (don't forget the '-I' before each entry)
APP_INC ?= -I .
# User's application include folders - for assembly files only (don't forget the '-I' before each entry)
ASM_INC ?= -I .

# Build folder for output
BUILD_DIR ?= build

# Optimization
EFFORT ?= -Os

# Compiler toolchain prefix
RISCV_PREFIX ?= riscv-none-elf-

# CPU architecture and ABI
MARCH ?= rv32i_zicsr_zifencei
MABI  ?= ilp32

# User flags for additional configuration (will be added to compiler flags)
USER_FLAGS ?=

# Relative or absolute path to the NEORV32 home folder
NEORV32_HOME ?= ../../..
NEORV32_LOCAL_RTL ?= $(NEORV32_HOME)/rtl

# GDB arguments
GDB_ARGS ?= -ex "target extended-remote localhost:3333"

# GHDL simulation run arguments
GHDL_RUN_FLAGS ?=

# -----------------------------------------------------------------------------
# NEORV32 framework
# -----------------------------------------------------------------------------

# Path to NEORV32 linker script and startup file
NEORV32_COM_PATH = $(NEORV32_HOME)/sw/common
# Path to main NEORV32 library include files
NEORV32_INC_PATH = $(NEORV32_HOME)/sw/lib/include
# Path to main NEORV32 library source files
NEORV32_SRC_PATH = $(NEORV32_HOME)/sw/lib/source
# Path to NEORV32 executable generator
NEORV32_EXG_PATH = $(NEORV32_HOME)/sw/image_gen
# Path to NEORV32 rtl folder
NEORV32_RTL_PATH = $(NEORV32_LOCAL_RTL)
# Path to NEORV32 sim folder
NEORV32_SIM_PATH = $(NEORV32_HOME)/sim
# Marker file to check for NEORV32 home folder
NEORV32_HOME_MARKER = $(NEORV32_INC_PATH)/neorv32.h

# Core libraries (peripheral and CPU drivers)
CORE_SRC = $(wildcard $(NEORV32_SRC_PATH)/*.c)
# Application start-up code
CORE_SRC += $(NEORV32_COM_PATH)/crt0.S
# Linker script
LD_SCRIPT ?= $(NEORV32_COM_PATH)/neorv32.ld

# Main output files
APP_EXE  = neorv32_exe.bin
APP_ELF  = main.elf
APP_HEX  = neorv32_raw_exe.hex
APP_BIN  = neorv32_raw_exe.bin
APP_COE  = neorv32_raw_exe.coe
APP_MEM  = neorv32_raw_exe.mem
APP_MIF  = neorv32_raw_exe.mif
APP_ASM  = main.asm
APP_VHD  = neorv32_application_image.vhd
BOOT_VHD = neorv32_bootloader_image.vhd

# Binary main file
BIN_MAIN = $(BUILD_DIR)/main.bin

# Define all sources
SRC  = $(APP_SRC)
SRC += $(CORE_SRC)

# Define search path for prerequisites
VPATH = $(sort $(dir $(SRC)))

# Create the build directories if they don't exist
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Define all object files
OBJ := $(patsubst %,$(BUILD_DIR)/%.o,$(notdir $(SRC)))

# -----------------------------------------------------------------------------
# Tools and flags
# -----------------------------------------------------------------------------

# Compiler tools
CC      = $(RISCV_PREFIX)gcc
OBJDUMP = $(RISCV_PREFIX)objdump
OBJCOPY = $(RISCV_PREFIX)objcopy
READELF = $(RISCV_PREFIX)readelf
SIZE    = $(RISCV_PREFIX)size
GDB     = $(RISCV_PREFIX)gdb

# Host's native compiler
CC_HOST = gcc -Wall -O -g

# NEORV32 executable image generator
IMAGE_GEN = $(NEORV32_EXG_PATH)/image_gen

# Compiler & linker flags
CC_OPTS  = -march=$(MARCH) -mabi=$(MABI) $(EFFORT) -Wall -ffunction-sections -fdata-sections -nostartfiles -mno-fdiv
CC_OPTS += -mstrict-align -mbranch-cost=10 -Wl,--gc-sections -ffp-contract=off -g
CC_OPTS += $(USER_FLAGS)
LD_LIBS  = -lm -lc -lgcc
LD_LIBS += $(USER_LIBS)

# Actual flags passed to the compiler
CC_FLAGS = $(CC_OPTS)

# Allow users to use tool-specific flags
# Uses naming from https://www.gnu.org/software/make/manual/html_node/Implicit-Variables.html
NEO_CFLAGS   = $(CC_FLAGS) $(CFLAGS)
NEO_CXXFLAGS = $(CC_FLAGS) $(CXXFLAGS)
NEO_LDFLAGS  = $(CC_FLAGS) $(LDFLAGS)
NEO_ASFLAGS  = $(CC_FLAGS) $(ASFLAGS)

# -----------------------------------------------------------------------------
# Application output definitions
# -----------------------------------------------------------------------------

.PHONY: check info help elf_info clean clean_all
.DEFAULT_GOAL := help

asm:     $(APP_ASM)
elf:     $(APP_ELF)
exe:     $(APP_EXE)
hex:     $(APP_HEX)
bin:     $(APP_BIN)
coe:     $(APP_COE)
mem:     $(APP_MEM)
mif:     $(APP_MIF)
image:   $(APP_VHD)
install: image install-$(APP_VHD)
all:     $(APP_ASM) $(APP_EXE) $(APP_HEX) $(APP_BIN) $(APP_COE) $(APP_MEM) $(APP_MIF) $(APP_VHD) install hex bin

# -----------------------------------------------------------------------------
# Image generator targets
# -----------------------------------------------------------------------------

# Compile image generator
$(IMAGE_GEN): $(NEORV32_EXG_PATH)/image_gen.c
	@echo Compiling image generator...
	@$(CC_HOST) $< -o $(IMAGE_GEN)

# -----------------------------------------------------------------------------
# General targets: Assemble, compile, link, dump
# -----------------------------------------------------------------------------

# Compile app *.s sources (assembly)
$(BUILD_DIR)/%.s.o: %.s | $(BUILD_DIR)
	@$(CC) -c $(NEO_ASFLAGS) -I $(NEORV32_INC_PATH) $(ASM_INC) $< -o $@

# Compile app *.S sources (assembly + C pre-processor)
$(BUILD_DIR)/%.S.o: %.S | $(BUILD_DIR)
	@$(CC) -c $(NEO_ASFLAGS) -I $(NEORV32_INC_PATH) $(ASM_INC) $< -o $@

# Compile app *.c sources
$(BUILD_DIR)/%.c.o: %.c | $(BUILD_DIR)
	@$(CC) -c $(NEO_CFLAGS) -I $(NEORV32_INC_PATH) $(APP_INC) $< -o $@

# Compile app *.cpp sources
$(BUILD_DIR)/%.cpp.o: %.cpp | $(BUILD_DIR)
	@$(CC) -c $(NEO_CXXFLAGS) -I $(NEORV32_INC_PATH) $(APP_INC) $< -o $@

# Link object files and show memory utilization
$(APP_ELF): $(OBJ)
	@$(CC) $(NEO_LDFLAGS) -T $(LD_SCRIPT) $^ $(LD_LIBS) -o $@
	@echo "Memory utilization:"
	@$(SIZE) $(APP_ELF)

# Assembly listing file (for debugging)
$(APP_ASM): $(APP_ELF)
	@$(OBJDUMP) -d -S -z $< > $@

# Generate final executable from .text + .rodata + .data (in THIS order!)
$(BIN_MAIN): $(APP_ELF) | $(BUILD_DIR)
	@$(OBJCOPY) -I elf32-little $< -j .text   -O binary text.bin
	@$(OBJCOPY) -I elf32-little $< -j .rodata -O binary rodata.bin
	@$(OBJCOPY) -I elf32-little $< -j .data   -O binary data.bin
	@cat text.bin rodata.bin data.bin > $@
	@rm -f text.bin rodata.bin data.bin

# -----------------------------------------------------------------------------
# Application targets: Generate executable formats
# -----------------------------------------------------------------------------

# Generate NEORV32 executable image for upload via bootloader
$(APP_EXE): $(BIN_MAIN) $(IMAGE_GEN)
	@set -e
	@echo "Generating $(APP_EXE)"
	@$(IMAGE_GEN) -app_bin $< $@ $(shell basename $(CURDIR))
	@echo "Executable size in bytes:"
	@wc -c < $(APP_EXE)

# Generate NEORV32 executable VHDL boot image
$(APP_VHD): $(BIN_MAIN) $(IMAGE_GEN)
	@set -e
	@echo "Generating $(APP_VHD)"
	@$(IMAGE_GEN) -app_vhd $< $@ $(shell basename $(CURDIR))

# Generate NEORV32 RAW executable image in plain hex format
$(APP_HEX): $(BIN_MAIN) $(IMAGE_GEN)
	@set -e
	@echo "Generating $(APP_HEX)"
	@$(IMAGE_GEN) -raw_hex $< $@ $(shell basename $(CURDIR))

# Generate NEORV32 RAW executable image in binary format
$(APP_BIN): $(BIN_MAIN) $(IMAGE_GEN)
	@set -e
	@echo "Generating $(APP_BIN)"
	@$(IMAGE_GEN) -raw_bin $< $@ $(shell basename $(CURDIR))

# Generate NEORV32 RAW executable image in COE format
$(APP_COE): $(BIN_MAIN) $(IMAGE_GEN)
	@set -e
	@echo "Generating $(APP_COE)"
	@$(IMAGE_GEN) -raw_coe $< $@ $(shell basename $(CURDIR))

# Generate NEORV32 RAW executable image in MIF format
$(APP_MIF): $(BIN_MAIN) $(IMAGE_GEN)
	@set -e
	@echo "Generating $(APP_MIF)"
	@$(IMAGE_GEN) -raw_mif $< $@ $(shell basename $(CURDIR))

# Generate NEORV32 RAW executable image in MEM format
$(APP_MEM): $(BIN_MAIN) $(IMAGE_GEN)
	@set -e
	@echo "Generating $(APP_MEM)"
	@$(IMAGE_GEN) -raw_mem $< $@ $(shell basename $(CURDIR))

# -----------------------------------------------------------------------------
# BOOTROM / bootloader image targets
# -----------------------------------------------------------------------------

# Create local VHDL BOOTROM image
bl_image: $(BIN_MAIN) $(IMAGE_GEN)
	@set -e
	@echo "Generating $(BOOT_VHD)"
	@$(IMAGE_GEN) -bld_vhd $< $(BOOT_VHD) $(shell basename $(CURDIR))

# Install BOOTROM image to VHDL source directory
bootloader: bl_image
	@set -e
	@echo "Installing bootloader image to $(NEORV32_RTL_PATH)/core/$(BOOT_VHD)"
	@cp $(BOOT_VHD) $(NEORV32_RTL_PATH)/core/.

# -----------------------------------------------------------------------------
# Check toolchain
# -----------------------------------------------------------------------------

check: $(IMAGE_GEN)
ifneq ("$(wildcard $NEORV32_HOME_MARKER)", "")
	$(error NEORV32_HOME folder not found!)
endif
	@echo "---------------- Check: NEORV32_HOME folder ----------------"
	@echo "NEORV32_HOME: $(NEORV32_HOME)"
	@echo "---------------- Check: Shell ----------------"
	@echo ${SHELL}
	@readlink -f ${SHELL}
	@echo "---------------- Check: $(CC) ----------------"
	@$(CC) -v
	@echo "---------------- Check: $(OBJDUMP) ----------------"
	@$(OBJDUMP) -V
	@echo "---------------- Check: $(OBJCOPY) ----------------"
	@$(OBJCOPY) -V
	@echo "---------------- Check: $(READELF) ----------------"
	@$(READELF) -v
	@echo "---------------- Check: $(SIZE) ----------------"
	@$(SIZE) -V
	@echo "---------------- Check: NEORV32 image_gen ----------------"
	@$(IMAGE_GEN) -help
	@echo "---------------- Check: Host's native GCC ----------------"
	@$(CC_HOST) -v
	@echo
	@echo "Toolchain check OK"

# -----------------------------------------------------------------------------
# In-console simulation using default testbench and GHDL
# -----------------------------------------------------------------------------

sim: $(APP_VHD)
	@echo "Simulating processor using default testbench..."
	@sh $(NEORV32_SIM_PATH)/ghdl.sh $(GHDL_RUN_FLAGS)

# Install VHDL memory initialization file
install-$(APP_VHD): $(APP_VHD)
	@set -e
	@echo "Installing application image to $(NEORV32_RTL_PATH)/core/$(APP_VHD)"
	@cp $(APP_VHD) $(NEORV32_RTL_PATH)/core/.

# -----------------------------------------------------------------------------
# Regenerate HDL file lists
# -----------------------------------------------------------------------------

hdl_lists:
	@sh $(NEORV32_RTL_PATH)/generate_file_lists.sh

# -----------------------------------------------------------------------------
# Show final ELF details (just for debugging)
# -----------------------------------------------------------------------------

elf_info: $(APP_ELF)
	@$(OBJDUMP) -x $(APP_ELF)

elf_sections: $(APP_ELF)
	@$(READELF) -S $(APP_ELF)

# -----------------------------------------------------------------------------
# Run GDB
# -----------------------------------------------------------------------------

gdb: $(APP_ELF)
	@$(GDB) $(APP_ELF) $(GDB_ARGS)

# -----------------------------------------------------------------------------
# Clean up
# -----------------------------------------------------------------------------

clean:
	@rm -rf $(BUILD_DIR)
	@rm -f $(APP_EXE) $(APP_ELF) $(APP_HEX) $(APP_BIN) $(APP_COE) $(APP_MEM) $(APP_MIF) $(APP_ASM) $(APP_VHD) $(BOOT_VHD)
	@rm -f .gdb_history

clean_all: clean
	@rm -f $(IMAGE_GEN)
	@rm -rf $(NEORV32_SIM_PATH)/build

# -----------------------------------------------------------------------------
# Show configuration
# -----------------------------------------------------------------------------

info:
	@echo "******************************************************"
	@echo "Project / Makfile Configuration"
	@echo "******************************************************"
	@echo "Project folder: $(shell basename $(CURDIR))"
	@echo "Source files: $(APP_SRC)"
	@echo "Include folder(s): $(APP_INC)"
	@echo "ASM include folder(s): $(ASM_INC)"
	@echo "NEORV32 home folder (NEORV32_HOME): $(NEORV32_HOME)"
	@echo "IMAGE_GEN: $(IMAGE_GEN)"
	@echo "Core source files:"
	@echo "$(CORE_SRC)"
	@echo "Core include folder:"
	@echo "$(NEORV32_INC_PATH)"
	@echo "Search path (VPATH)"
	@echo "$(VPATH)"
	@echo "Project object files:"
	@echo "$(OBJ)"
	@echo "LIBGCC:"
	@$(CC) -print-libgcc-file-name
	@echo "SEARCH-DIRS:"
	@$(CC) -print-search-dirs
	@echo "USER_LIBS: $(USER_LIBS)"
	@echo "LD_LIBS: $(LD_LIBS)"
	@echo "MARCH: $(MARCH)"
	@echo "MABI: $(MABI)"
	@echo "CC: $(CC)"
	@echo "OBJDUMP: $(OBJDUMP)"
	@echo "OBJCOPY: $(OBJCOPY)"
	@echo "SIZE: $(SIZE)"
	@echo "DEBUGGER: $(GDB)"
	@echo "GDB_ARGS: $(GDB_ARGS)"
	@echo "GHDL_RUN_FLAGS: $(GHDL_RUN_FLAGS)"
	@echo "USER_FLAGS: $(USER_FLAGS)"
	@echo "CC_OPTS: $(CC_OPTS)"

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

help:
	@echo "NEORV32 Software Makefile"
	@echo "Find more information at https://github.com/stnolting/neorv32"
	@echo ""
	@echo "Targets:"
	@echo ""
	@echo "  help         - show this text"
	@echo "  check        - check toolchain"
	@echo "  info         - show makefile/toolchain configuration"
	@echo "  gdb          - start GNU debugging session"
	@echo "  asm          - compile and generate <$(APP_ASM)> assembly listing file for manual debugging"
	@echo "  elf          - compile and generate <$(APP_ELF)> ELF file"
	@echo "  exe          - compile and generate <$(APP_EXE)> executable image file for bootloader upload (includes a HEADER!)"
	@echo "  bin          - compile and generate <$(APP_BIN)> executable memory image"
	@echo "  hex          - compile and generate <$(APP_HEX)> executable memory image"
	@echo "  coe          - compile and generate <$(APP_COE)> executable memory image"
	@echo "  mem          - compile and generate <$(APP_MEM)> executable memory image"
	@echo "  mif          - compile and generate <$(APP_MIF)> executable memory image"
	@echo "  image        - compile and generate VHDL IMEM application boot image <$(APP_VHD)> in local folder"
	@echo "  install      - compile, generate and install VHDL IMEM application boot image <$(APP_VHD)>"
	@echo "  sim          - in-console simulation using default testbench (sim folder) and GHDL"
	@echo "  hdl_lists    - regenerate HDL file-lists (*.f) in NEORV32_HOME/rtl"
	@echo "  all          - exe + install + hex + bin + asm"
	@echo "  elf_info     - show ELF layout info"
	@echo "  elf_sections - show ELF sections"
	@echo "  clean        - clean up project home folder"
	@echo "  clean_all    - clean up project home folder and image generator"
	@echo "  bl_image     - compile and generate VHDL BOOTROM bootloader boot image <$(BOOT_VHD)> in local folder"
	@echo "  bootloader   - compile, generate and install VHDL BOOTROM bootloader boot image <$(BOOT_VHD)>"
	@echo ""
	@echo "Variables:"
	@echo ""
	@echo "  USER_FLAGS     - Custom toolchain flags [append only]: \"$(USER_FLAGS)\""
	@echo "  USER_LIBS      - Custom libraries [append only]: \"$(USER_LIBS)\""
	@echo "  EFFORT         - Optimization level: \"$(EFFORT)\""
	@echo "  MARCH          - Machine architecture: \"$(MARCH)\""
	@echo "  MABI           - Machine binary interface: \"$(MABI)\""
	@echo "  APP_INC        - C include folder(s) [append only]: \"$(APP_INC)\""
	@echo "  APP_SRC        - C source folder(s) [append only]: \"$(APP_SRC)\""
	@echo "  ASM_INC        - ASM include folder(s) [append only]: \"$(ASM_INC)\""
	@echo "  RISCV_PREFIX   - Toolchain prefix: \"$(RISCV_PREFIX)\""
	@echo "  NEORV32_HOME   - NEORV32 home folder: \"$(NEORV32_HOME)\""
	@echo "  GDB_ARGS       - GDB (connection) arguments: \"$(GDB_ARGS)\""
	@echo "  GHDL_RUN_FLAGS - GHDL simulation run arguments: \"$(GHDL_RUN_FLAGS)\""
	@echo ""
