# Deployment Guide

## Prerequisites

- Foundry (latest version)
- Go 1.21+ for AVS components
- Node.js 18+ for frontend components
- EigenLayer Testnet Access
- Circle Developer Account

## Environment Setup

1. Copy `.env.example` to `.env`
2. Fill in your environment variables
3. Ensure you have sufficient ETH for gas fees
4. Verify all required addresses are correct

## Deployment Scripts

### Local Development (Anvil)

```bash
# Start Anvil
anvil

# Deploy to Anvil
forge script script/DeployAnvil.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

### Testnet Deployment

```bash
# Deploy to Sepolia
forge script script/DeployTestnet.s.sol --rpc-url $RPC_URL_SEPOLIA --broadcast --verify

# Deploy to Goerli
forge script script/DeployTestnet.s.sol --rpc-url $RPC_URL_GOERLI --broadcast --verify
```

### Mainnet Deployment

```bash
# Deploy to mainnet
forge script script/DeployMainnet.s.sol --rpc-url $RPC_URL_MAINNET --broadcast --verify
```

## Post-Deployment Steps

1. **Verify Contracts**: Check all contracts on Etherscan
2. **Transfer Ownership**: Move ownership to multisig wallet
3. **Set Up Monitoring**: Configure alerts and monitoring
4. **Initialize Protocols**: Add supported yield protocols
5. **Test Integration**: Verify all integrations work correctly

## Security Checklist

- [ ] All contracts verified on Etherscan
- [ ] Ownership transferred to multisig
- [ ] Timelock contracts configured
- [ ] Emergency pause functions tested
- [ ] Monitoring and alerts configured
- [ ] Documentation updated with addresses

## Troubleshooting

### Common Issues

1. **Gas Estimation Failed**: Increase gas limit or check gas price
2. **Contract Verification Failed**: Check constructor parameters
3. **Transaction Reverted**: Check prerequisites and dependencies
4. **RPC Errors**: Verify RPC URL and network connectivity

### Support

For deployment issues, contact the development team or check the troubleshooting guide.
