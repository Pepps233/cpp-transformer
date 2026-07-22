# Toolchain
CXX 	:= clang++
NVCC 	:= $(shell which nvcc)

# Flags
# -MMD -MP generate .d dependency files so edited headers trigger rebuilds.
# -MMD: track the headers, not system ones. -MP: emit phony targets for each header so deleting a header doesn't break the build.
CXXFLAGS := -std=c++17 -Wall -Wextra -Wpedantic -Iinclude -MMD -MP

# BUILD=debug (default) or BUILD=release
BUILD ?= debug
ifeq ($(BUILD),release)
CXXFLAGS += -O2 -DNDEBUG
else
CXXFLAGS += -O0 -g
endif

NVCCFLAGS := -std=c++17 -Iinclude -lineinfo
CUDA_ARCH ?= sm_75
NVCCFLAGS += -arch=$(CUDA_ARCH)
CUDA_LIBS := -lcudart -lcublas

# Sources

SRCS 	:= $(wildcard src/*.cpp)
OBJS 	:= $(patsubst src/%.cpp,build/%.o,$(SRCS))

CU_SRCS := $(wildcard src/cuda/*.cu)
CU_OBJS := $(patsubst src/cuda/%.cu,build/cuda/%.o,$(CU_SRCS))

TEST_SRCS := $(wildcard tests/test_*.cpp)
TEST_BINS := $(patsubst tests/%.cpp,bin/%,$(TEST_SRCS))

CU_TEST_SRCS := $(wildcard tests/test_*.cu)
CU_TEST_BINS := $(patsubst tests/%.cu,bin/%,$(CU_TEST_SRCS))

# Top-level targets

.PHONY: all test test-host test-cuda clean info

all: $(TEST_BINS)

# Host tests only, no GPU required.
test-host: $(TEST_BINS)
	@echo "=== host tests ==="
	@for t in $(TEST_BINS); do \
		echo "--- $$t"; \
		./$$t || exit 1; \
	done
	@echo "=== all host tests passed ==="

ifeq ($(NVCC),)
test-cuda:
	@echo "nvcc not found -- skipping CUDA tests."
else
test-cuda: $(CU_TEST_BINS)
	@echo "=== cuda tests ==="
	@for t in $(CU_TEST_BINS); do \
		echo "--- $$t"; \
		./$$t || exit 1; \
	done
	@echo "=== all cuda tests passed ==="
endif

test: test-host test-cuda

# Pattern rules

build/%.o: src/%.cpp | build
	$(CXX) $(CXXFLAGS) -c $< -o $@

build/cuda/%.o: src/cuda/%.cu | build/cuda
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

bin/%:tests /%.cpp $(OBJS) | bin
	$(CXX) $(CXXFLAGS) $< $(OBJS) -o $@

bin/%: tests/%.cu $(OBJS) $(CU_OBJS) | bin
	$(NVCC) $(NVCCFLAGS) $< $(OBJS) $(CU_OBJS) $(CUDA_LIBS) -o $@

# Directories

build build/cuda bin:
	@mkdir -p $@

# Utility

info:
	@echo "CXX       = $(CXX)"
	@echo "BUILD     = $(BUILD)"
	@echo "CXXFLAGS  = $(CXXFLAGS)"
	@echo "NVCC      = $(if $(NVCC),$(NVCC),<not found>)"
	@echo "SRCS      = $(SRCS)"
	@echo "TEST_SRCS = $(TEST_SRCS)"

clean:
	rm -rf build bin

# Auth-generated header dependencies
# Must come last. The leading '-' suppresses errors on the first build when no .d files exist yet.
-include $(OBJS:.o=.d)
-include $(CU_OBJS:.o=.d)
