# Makefile
.PHONY: all test clean

GNAT = gnatmake
OBJ_DIR = obj
BIN_DIR = bin

all: $(BIN_DIR)/main$(BIN_DIR)/tests

$(BIN_DIR)/main: src/main.adb src/maekawa.ads src/maekawa.adb
	mkdir -p $(OBJ_DIR) $(BIN_DIR)$(GNAT) -P maekawa.gpr src/main.adb

$(BIN_DIR)/tests: tests.adb src/maekawa.ads src/maekawa.adb
	mkdir -p $(OBJ_DIR) $(BIN_DIR)$(GNAT) -P maekawa.gpr tests.adb

test: $(BIN_DIR)/tests
	@echo "==============================="
	@echo "Running V&V Test Suite..."
	@echo "==============================="
	@./$(BIN_DIR)/tests

clean:
	rm -rf $(OBJ_DIR)/*$(BIN_DIR)/*
