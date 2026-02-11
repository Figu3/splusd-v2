import { ConnectWallet } from "./components/ConnectWallet";
import { VaultStats } from "./components/VaultStats";
import { DonateYield } from "./components/DonateYield";

export default function Home() {
  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      {/* Header */}
      <header className="border-b border-zinc-800">
        <div className="max-w-2xl mx-auto px-4 py-4 flex items-center justify-between">
          <h1 className="text-lg font-semibold tracking-tight">
            splUSD v2
          </h1>
          <ConnectWallet />
        </div>
      </header>

      {/* Main */}
      <main className="max-w-2xl mx-auto px-4 py-8 space-y-6">
        <div>
          <h2 className="text-2xl font-bold">Donate Yield</h2>
          <p className="text-zinc-400 text-sm mt-1">
            Donate plUSD to the splUSD v2 vault. This increases the share price
            for all stakers.
          </p>
        </div>

        <VaultStats />
        <DonateYield />

        {/* Contract info */}
        <div className="text-xs text-zinc-600 space-y-1 pt-4 border-t border-zinc-800/50">
          <p>
            Vault:{" "}
            <a
              href="https://plasmascan.to/address/0x63C6798DD4C3fAFD6d787cDaFf85FEED82Da8442"
              target="_blank"
              rel="noopener noreferrer"
              className="text-zinc-500 hover:text-zinc-400 font-mono"
            >
              0x63C6...8442
            </a>
          </p>
          <p>
            plUSD:{" "}
            <a
              href="https://plasmascan.to/address/0xf91c31299E998C5127Bc5F11e4a657FC0cF358CD"
              target="_blank"
              rel="noopener noreferrer"
              className="text-zinc-500 hover:text-zinc-400 font-mono"
            >
              0xf91c...58CD
            </a>
          </p>
          <p>Chain: Plasma (9745)</p>
        </div>
      </main>
    </div>
  );
}
