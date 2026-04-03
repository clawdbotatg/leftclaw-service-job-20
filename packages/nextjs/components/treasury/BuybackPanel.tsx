"use client";

import { useState } from "react";
import { parseEther, parseUnits } from "viem";
import { useAccount } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

export const BuybackPanel = () => {
  const { address } = useAccount();
  const [inputType, setInputType] = useState<"weth" | "usdc">("weth");
  const [amount, setAmount] = useState("");
  const [error, setError] = useState<string | null>(null);

  const { data: isOperator } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "isOperator",
    args: [address],
  });

  const { data: cooldownRemaining } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getCooldownRemaining",
  });

  const { writeContractAsync, isMining } = useScaffoldWriteContract("TreasuryManagerV2");

  const hasCooldown = cooldownRemaining !== undefined && cooldownRemaining > 0n;

  const handleBuyback = async () => {
    if (!amount) return;
    const parsed = Number(amount);
    if (isNaN(parsed) || parsed <= 0) {
      setError("Enter a valid positive number");
      return;
    }
    setError(null);
    try {
      if (inputType === "weth") {
        await writeContractAsync({
          functionName: "buybackWithWETH",
          args: [parseEther(amount)],
        });
      } else {
        await writeContractAsync({
          functionName: "buybackWithUSDC",
          args: [parseUnits(amount, 6)],
        });
      }
      setAmount("");
    } catch (e: any) {
      setError(e?.shortMessage || e?.message || "Buyback failed");
    }
  };

  return (
    <div className="card bg-base-100 shadow-xl">
      <div className="card-body">
        <h2 className="card-title text-2xl mb-4">
          💰 Buyback ₸USD
          {!isOperator && <span className="badge badge-warning ml-2">Operator Only</span>}
        </h2>

        {/* Input type selector */}
        <div className="tabs tabs-boxed mb-4">
          <button
            className={`tab ${inputType === "weth" ? "tab-active" : ""}`}
            onClick={() => setInputType("weth")}
          >
            WETH
          </button>
          <button
            className={`tab ${inputType === "usdc" ? "tab-active" : ""}`}
            onClick={() => setInputType("usdc")}
          >
            USDC
          </button>
        </div>

        {/* Amount input */}
        <div className="form-control mb-4">
          <label className="label">
            <span className="label-text font-semibold">
              {inputType === "weth" ? "WETH Amount" : "USDC Amount"}
            </span>
            <span className="label-text-alt">
              Max per tx: {inputType === "weth" ? "0.5 ETH" : "2,000 USDC"}
            </span>
          </label>
          <input
            type="text"
            placeholder="0.0"
            className="input input-bordered w-full"
            value={amount}
            onChange={e => setAmount(e.target.value)}
          />
        </div>

        {error && (
          <div className="alert alert-error mb-4">
            <span>{error}</span>
          </div>
        )}

        {hasCooldown && (
          <div className="alert alert-warning mb-4">
            <span>⏳ Cooldown active — {Math.ceil(Number(cooldownRemaining || 0n) / 60)}m remaining</span>
          </div>
        )}

        <button
          className={`btn btn-accent w-full ${isMining ? "loading" : ""}`}
          disabled={!isOperator || isMining || !amount || hasCooldown}
          onClick={handleBuyback}
        >
          {isMining ? "Executing..." : `Buyback ₸USD with ${inputType.toUpperCase()}`}
        </button>
      </div>
    </div>
  );
};

export default BuybackPanel;
