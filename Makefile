# AVS-Powered USDC Yield Hook - Makefile
# Comprehensive build, test, and deployment automation

.PHONY: help install build test coverage clean deploy-avs build-avs test-avs
.PHONY: test-unit test-integration test-fuzz test-fork test-fhe
.PHONY: coverage-html coverage-lcov deploy-local deploy-testnet deploy-mainnet
.PHONY: setup-fhe build-fhe

# Default target
help:
	@echo "AVS-Powered USDC Yield Hook - Available Commands:"
	@echo ""
	@echo "Development:"
	@echo "  install          Install all dependencies"
	@echo "  build           Build all contracts"
	@echo "  test            Run all tests"
	@echo "  coverage        Generate coverage report"
	@echo "  clean           Clean build artifacts"
	@echo ""
	@echo "AVS Development:"
	@echo "  build-avs       Build AVS components"
	@echo "  test-avs        Run AVS tests"
	@echo "  deploy-avs      Deploy AVS contracts"
	@echo ""
	@echo "Testing:"
	@echo "  test-unit       Run unit tests only"
	@echo "  test-integration Run integration tests only"
	@echo "  test-fuzz       Run fuzz tests only"
	@echo "  test-fork       Run fork tests only"
	@echo ""
	@echo "Coverage:"
	@echo "  coverage-html   Generate HTML coverage report"
	@echo "  coverage-lcov   Generate LCOV coverage report"
	@echo ""
	@echo "Deployment:"
	@echo "  deploy-local    Deploy to local network"
	@echo "  deploy-testnet  Deploy to testnet"
	@echo "  deploy-mainnet  Deploy to mainnet"

# Development Commands
install:
	@echo "Installing dependencies..."
	forge install
	cd avs && go mod download
	@echo "Dependencies installed successfully!"

build:
	@echo "Building contracts..."
	forge build
	@echo "Contracts built successfully!"

test:
	@echo "Running all tests..."
	forge test --gas-report
	@echo "All tests completed!"

coverage:
	@echo "Generating coverage report..."
	forge coverage --ir-minimum
	@echo "Coverage report generated!"

clean:
	@echo "Cleaning build artifacts..."
	forge clean
	cd avs && go clean
	@echo "Build artifacts cleaned!"

# AVS Development Commands
build-avs:
	@echo "Building AVS components..."
	cd avs && go build -o bin/operator ./cmd
	cd avs && go build -o bin/crosscow-avs ./cmd
	@echo "AVS components built successfully!"

test-avs:
	@echo "Running AVS tests..."
	cd avs && go test ./...
	@echo "AVS tests completed!"

deploy-avs:
	@echo "Deploying AVS contracts..."
	cd avs/contracts && forge script script/DeployAVS.s.sol --rpc-url $(RPC_URL) --broadcast
	@echo "AVS contracts deployed!"

# Testing Commands
test-unit:
	@echo "Running unit tests..."
	forge test --match-contract "Unit" --gas-report
	@echo "Unit tests completed!"

test-integration:
	@echo "Running integration tests..."
	forge test --match-contract "Integration" --gas-report
	@echo "Integration tests completed!"

test-fuzz:
	@echo "Running fuzz tests..."
	forge test --match-contract "Fuzz" --gas-report
	@echo "Fuzz tests completed!"

test-fork:
	@echo "Running fork tests..."
	forge test --match-contract "Fork" --fork-url $(MAINNET_RPC_URL) --gas-report
	@echo "Fork tests completed!"


# Coverage Commands
coverage-html:
	@echo "Generating HTML coverage report..."
	forge coverage --ir-minimum --report html
	@echo "HTML coverage report generated in coverage/"

coverage-lcov:
	@echo "Generating LCOV coverage report..."
	forge coverage --ir-minimum --report lcov
	@echo "LCOV coverage report generated in lcov.info"

# Deployment Commands
deploy-local:
	@echo "Deploying to local network..."
	forge script script/DeployYieldOptimizationHook.s.sol --rpc-url http://localhost:8545 --broadcast
	@echo "Deployed to local network!"

deploy-testnet:
	@echo "Deploying to testnet..."
	forge script script/DeployYieldOptimizationHook.s.sol --rpc-url $(TESTNET_RPC_URL) --broadcast --verify
	@echo "Deployed to testnet!"

deploy-mainnet:
	@echo "Deploying to mainnet..."
	forge script script/DeployYieldOptimizationHook.s.sol --rpc-url $(MAINNET_RPC_URL) --broadcast --verify
	@echo "Deployed to mainnet!"


# Environment Variables
# Set these in your .env file or export them
# RPC_URL=your_rpc_url
# MAINNET_RPC_URL=your_mainnet_rpc_url
# TESTNET_RPC_URL=your_testnet_rpc_url
# PRIVATE_KEY=your_private_key
# ETHERSCAN_API_KEY=your_etherscan_api_key

# Default values for testing
RPC_URL ?= http://localhost:8545
MAINNET_RPC_URL ?= https://eth-mainnet.g.alchemy.com/v2/your-api-key
TESTNET_RPC_URL ?= https://eth-sepolia.g.alchemy.com/v2/your-api-key