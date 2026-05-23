body = <<~MARKDOWN
  #__November 04, 2018__

  **_Building a royalty accounting system on Ethereum, geth, and Web3, and why the on-chain part turned out to be the easy part._**

  The product at Vezt is, on paper, simple: a songwriter or rights-holder takes a small piece of their future royalties on a specific song, fractionalizes it, and sells those fractions to fans on the platform. The fans hold an asset that pays them a share of whatever royalties the song generates from now until forever, prorated by how big a piece they bought. The rights-holder gets cash up front. The blockchain is there because (a) the asset needs to be transferrable, (b) the cap table for any given song can have thousands of owners, and (c) the trust story is much easier if the ownership ledger is not "Vezt's internal database."

  I have been heading engineering here for about a year now and we just closed our first round of song sales and pushed the first real royalty payouts to holders. This is a post about what we built and what I learned about putting actual money on a blockchain.

  ## The architecture

  Three layers:

  1. **On-chain (Ethereum)**: a Solidity contract per song that holds the cap table of fractional ownership.
  2. **Off-chain ledger (Postgres)**: the source of truth for everything that does not need to be on-chain, including identity, KYC state, USD balances, and the full royalty accrual history.
  3. **Reconciliation service**: a Node.js service that watches the chain for transfers, syncs them to the off-chain ledger, and (in the other direction) pushes payout events on-chain when royalty distributions occur.

  The mobile app (React Native) and the web app (React) both talk to the same GraphQL API. The API never talks to the chain directly. All chain interactions go through a dedicated transaction service that owns the hot wallet, manages nonces, and retries failed transactions. This separation has saved us several times.

  ## The smart contract

  The contract is, deliberately, the smallest interesting thing it can be. It is roughly an ERC-20-ish balance tracker, plus a deposit/distribute mechanism for royalties, plus a transfer restriction hook for compliance.

  ```solidity
  pragma solidity ^0.4.24;

  contract SongRights {
      address public issuer;
      uint256 public totalFractions;
      mapping(address => uint256) public balances;

      uint256 public undistributedPool;
      mapping(address => uint256) public lastClaimedSnapshot;
      uint256 public currentSnapshotId;
      mapping(uint256 => uint256) public snapshotPoolPerFraction;

      event Transfer(address indexed from, address indexed to, uint256 value);
      event Deposit(uint256 amount, uint256 snapshotId);
      event Claim(address indexed holder, uint256 amount, uint256 snapshotId);

      modifier onlyIssuer() {
          require(msg.sender == issuer, "issuer only");
          _;
      }

      function transfer(address to, uint256 value) external returns (bool) {
          require(balances[msg.sender] >= value, "insufficient balance");
          _settle(msg.sender);
          _settle(to);
          balances[msg.sender] -= value;
          balances[to] += value;
          emit Transfer(msg.sender, to, value);
          return true;
      }

      function deposit() external payable onlyIssuer {
          currentSnapshotId += 1;
          uint256 perFraction = msg.value / totalFractions;
          snapshotPoolPerFraction[currentSnapshotId] = perFraction;
          undistributedPool += msg.value;
          emit Deposit(msg.value, currentSnapshotId);
      }

      function _settle(address holder) internal {
          uint256 owed = 0;
          for (uint256 s = lastClaimedSnapshot[holder] + 1; s <= currentSnapshotId; s++) {
              owed += balances[holder] * snapshotPoolPerFraction[s];
          }
          lastClaimedSnapshot[holder] = currentSnapshotId;
          if (owed > 0) {
              undistributedPool -= owed;
              holder.transfer(owed);
              emit Claim(holder, owed, currentSnapshotId);
          }
      }
  }
  ```

  A few things to note about that contract:

  * **There is no `approve`/`transferFrom`.** This is deliberate. We are not trying to be a fully ERC-20-compliant token, because most exchanges would list it and then we would have a securities-law nightmare on our hands. The transfer surface is intentionally narrower than ERC-20.
  * **Snapshots are per-deposit, not per-block.** Each royalty deposit creates a snapshot, captures the per-fraction payout at that snapshot, and increments a counter. Holders settle their accrual lazily on any transfer (or by calling `_settle` directly via a `claim()` wrapper).
  * **The loop in `_settle` is dangerous.** If a holder hasn't claimed for hundreds of snapshots, the gas cost of settling balloons. We are mitigating this with a hard cap (auto-claim every N snapshots) and by having the reconciliation service push a `claim` for inactive holders proactively. The right fix is a Merkle-root distribution pattern; we are not there yet.

  ## geth and the JSON-RPC dance

  For the first six months we ran our own [geth](https://geth.ethereum.org/) node — a full node, not a light client. We did this for two reasons: latency on transaction submission, and not wanting our backend's availability to depend on a third party. Both reasons turned out to be wrong, but they were reasonable at the time.

  We wrote a small wrapper around the geth JSON-RPC interface that handled the things `web3.js` does badly:

  * **Nonce management.** Web3's default behavior of asking the node for the current nonce on every transaction is fine until you submit two transactions in the same block, at which point you get the same nonce back twice and the second one fails. We keep an in-process nonce counter for the hot wallet, with a periodic sync to the chain's view.
  * **Gas price strategy.** Tying gas price to a single oracle is asking for trouble. We compute a target based on the median gas price of the last ten blocks, with a per-transaction-type ceiling.
  * **Resubmission.** A transaction that doesn't land within a couple of blocks gets resubmitted with a bumped gas price and the same nonce. After three escalations it gets a "manual review" event published to PagerDuty.

  About six months in, we moved off our own geth node and onto [INFURA](https://infura.io/). The reasons:

  * Running a geth node in production is its own job. We had occasional sync failures, occasional database corruption, occasional times where geth would just stop accepting transactions for no reason we could diagnose. Every one of those is an outage where users can't buy fractions or claim royalties.
  * Latency to INFURA from our AWS region was, embarrassingly, lower than latency to our own node, because INFURA's edge is on top of CloudFront.
  * The cost was much, much lower than the operational cost of running our own node.

  The wrapper code we built around geth came with us, basically unchanged. The JSON-RPC interface is the same. The only thing we lost was the ability to use a few non-standard methods that INFURA does not expose, none of which we were actually using in production.

  ## The off-chain ledger

  Here is where I have to admit something. About 90% of the engineering work at Vezt is not on the blockchain. It is in the off-chain accounting ledger that tracks the USD side of everything.

  Royalties don't show up in ETH. They show up as wire transfers and ACH deposits from music publishers and PROs, denominated in dollars, attached to statements that look like the PDF you would have gotten in 1995. We have to:

  * Parse those statements into per-song accruals.
  * Match each accrual to the song's ownership cap table at the time the royalty was earned (which is not the same as the cap table now, because shares trade).
  * Compute the per-holder distribution.
  * Convert dollars to ETH (or hold them in a stablecoin until distribution).
  * Push the per-holder payouts to the chain in batches that don't blow the gas budget.

  The off-chain ledger looks like a classic double-entry accounting system. Every USD movement is a journal entry with debit and credit sides, every entry is associated with a song and a date range, and the reconciliation runs every night and screams loudly if any account has a balance that disagrees with the chain.

  Building this part properly is the difference between a fintech startup and a really expensive lawsuit. We hired an actual accountant in month four to help me build the chart of accounts and the close process. I wish we had done it in month one.

  ## What I would do differently

  **I would not have written my own ERC-20-ish contract.** OpenZeppelin's audited libraries exist for a reason. Our contract is short and we have had it externally audited, but every line of Solidity I write is a line that can lose user money. I would rather inherit from a battle-tested base and only override the things that need to be different.

  **I would have launched on a testnet for longer.** We were on Ropsten for about six weeks before mainnet, and that was not enough time. We caught several issues in the first month on mainnet that we should have caught on Ropsten. The cost of an additional two months on testnet is small. The cost of a bug on mainnet is, potentially, your entire user base.

  **I would have separated KYC from the contract entirely.** Right now there is no on-chain KYC check; the platform enforces it at the API layer before any transfer is brokered, but the contract itself will accept a transfer from any address to any address. That is fine for our current scale and our current jurisdiction. As we grow, we are going to need a transfer-restriction hook that calls into an on-chain KYC oracle, and the contract is not currently structured to make that easy.

  ## The thing nobody warned me about

  Smart contract development is not really like other software development. The build/test/deploy loop is slow, the tooling is immature, and the failure modes are catastrophic. But the bigger surprise has been that almost none of the hard work is on the chain. The hard work is identity, KYC, banking integrations, royalty data ingestion, fraud detection, customer support, and convincing songwriters that you are not a scam. The blockchain is the part of the iceberg above the water. Everything below it is what determines whether the product actually works.

  More writeups to come as we ship more songs. If you are working on something similar — fractional ownership, royalty distribution, on-chain compliance — please send me a note. There are not that many of us yet.
MARKDOWN

begin
  Post.create!(
    title: "Smart Contracts for Music Royalties: A Year of Vezt",
    created_at: "November 4, 2018",
    markdown_body: body,
    markdown_excerpt: "Building a royalty accounting system on Ethereum, geth, and Web3, and why the on-chain part turned out to be the easy part.",
    post_tags: "ethereum,solidity,web3,smart-contracts,fintech,blockchain,royalties"
  )
  puts "Imported Smart Contracts for Music Royalties: A Year of Vezt"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 04-11-2018-Smart-Contracts-for-Music-Royalties: #{e.message}"
rescue => e
  puts "Unexpected error importing 04-11-2018-Smart-Contracts-for-Music-Royalties: #{e.message}"
end
