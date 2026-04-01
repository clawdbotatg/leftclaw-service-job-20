import { GenericContractsDeclaration } from "~~/utils/scaffold-eth/contract";

const externalContracts = {
  8453: {
    StakingContract: {
      address: "0x2a70a42BC0524aBCA9Bff59a51E7aAdB575DC89A",
      abi: [
        {
          inputs: [
            { name: "_amount", type: "uint256" },
            { name: "poolId", type: "uint256" },
          ],
          name: "deposit",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [
            { name: "_amount", type: "uint256" },
            { name: "poolId", type: "uint256" },
          ],
          name: "withdraw",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [{ name: "poolId", type: "uint256" }],
          name: "poolInfo",
          outputs: [
            { name: "stakingToken", type: "address" },
            { name: "rewardToken", type: "address" },
            { name: "lastRewardTimestamp", type: "uint256" },
            { name: "accRewardPerShare", type: "uint256" },
            { name: "startTimestamp", type: "uint256" },
            { name: "endTimestamp", type: "uint256" },
            { name: "precision", type: "uint256" },
            { name: "totalStaked", type: "uint256" },
            { name: "totalRewards", type: "uint256" },
            { name: "feeCollector", type: "address" },
          ],
          stateMutability: "view",
          type: "function",
        },
      ] as const,
    },
    TUSD: {
      address: "0xcb8D2c6229fA4a7d96B242345551E562E0e2fc76",
      abi: [
        {
          inputs: [{ name: "account", type: "address" }],
          name: "balanceOf",
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [
            { name: "spender", type: "address" },
            { name: "amount", type: "uint256" },
          ],
          name: "approve",
          outputs: [{ name: "", type: "bool" }],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [
            { name: "owner", type: "address" },
            { name: "spender", type: "address" },
          ],
          name: "allowance",
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "decimals",
          outputs: [{ name: "", type: "uint8" }],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "symbol",
          outputs: [{ name: "", type: "string" }],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "name",
          outputs: [{ name: "", type: "string" }],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "totalSupply",
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
          type: "function",
        },
      ] as const,
    },
  },
  31337: {
    StakingContract: {
      address: "0x2a70a42BC0524aBCA9Bff59a51E7aAdB575DC89A",
      abi: [
        {
          inputs: [
            { name: "_amount", type: "uint256" },
            { name: "poolId", type: "uint256" },
          ],
          name: "deposit",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [
            { name: "_amount", type: "uint256" },
            { name: "poolId", type: "uint256" },
          ],
          name: "withdraw",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [{ name: "poolId", type: "uint256" }],
          name: "poolInfo",
          outputs: [
            { name: "stakingToken", type: "address" },
            { name: "rewardToken", type: "address" },
            { name: "lastRewardTimestamp", type: "uint256" },
            { name: "accRewardPerShare", type: "uint256" },
            { name: "startTimestamp", type: "uint256" },
            { name: "endTimestamp", type: "uint256" },
            { name: "precision", type: "uint256" },
            { name: "totalStaked", type: "uint256" },
            { name: "totalRewards", type: "uint256" },
            { name: "feeCollector", type: "address" },
          ],
          stateMutability: "view",
          type: "function",
        },
      ] as const,
    },
    TUSD: {
      address: "0xcb8D2c6229fA4a7d96B242345551E562E0e2fc76",
      abi: [
        {
          inputs: [{ name: "account", type: "address" }],
          name: "balanceOf",
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [
            { name: "spender", type: "address" },
            { name: "amount", type: "uint256" },
          ],
          name: "approve",
          outputs: [{ name: "", type: "bool" }],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [
            { name: "owner", type: "address" },
            { name: "spender", type: "address" },
          ],
          name: "allowance",
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "decimals",
          outputs: [{ name: "", type: "uint8" }],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "symbol",
          outputs: [{ name: "", type: "string" }],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "name",
          outputs: [{ name: "", type: "string" }],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "totalSupply",
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
          type: "function",
        },
      ] as const,
    },
  },
} as const;

export default externalContracts satisfies GenericContractsDeclaration;
