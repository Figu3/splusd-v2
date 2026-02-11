import { http, createConfig } from "wagmi";
import { injected } from "wagmi/connectors";
import { defineChain } from "viem";

export const plasma = defineChain({
  id: 9745,
  name: "Plasma",
  nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.plasma.io/v1/plasma"] },
  },
  blockExplorers: {
    default: { name: "PlasmaExplorer", url: "https://plasmascan.to" },
  },
});

export const config = createConfig({
  chains: [plasma],
  connectors: [
    injected({ target: "metaMask" }), // Rabby overrides MetaMask provider
    injected(), // Catches Fordefi or any other injected wallet
  ],
  transports: {
    [plasma.id]: http(),
  },
  ssr: true,
});
