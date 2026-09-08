// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AuctionEdition } from "./AuctionEdition.sol";

/// @title RankedAuction
/// @notice 90 ranked NFT auction places and 10 reserved NFTs. Rank #1 pays its full bid; other winners pay the cutoff.
/// @dev Ranked-list mechanics adapted from Transient Labs TLRankedAuction (MIT), reference commit in NOTICE.md.
///      A bounded list keeps only the best 90 bids. No callbacks during bidding or settlement.
contract RankedAuction is ReentrancyGuard {
    enum Phase {
        Scheduled,
        Live,
        Ended,
        Settled
    }

    struct Config {
        address payoutWallet;
        uint96 royaltyBps;
        uint128 reservePrice;
        uint64 startTime;
        string metadataURI;
        string collectionName;
        string collectionSymbol;
    }

    struct Bid {
        address bidder;
        uint128 amount;
        uint256 prev;
        uint256 next;
        bool active;
        bool refundCredited;
        bool tokenClaimed;
        uint16 tokenId;
    }

    uint256 public constant SUPPLY = 90;
    uint256 public constant RESERVED_SUPPLY = 10;
    uint256 public constant AUCTION_DURATION = 48 hours;
    uint256 public constant EXTENSION_WINDOW = 10 minutes;
    uint256 public constant MAX_BID = type(uint128).max;
    uint256 public constant OUTBID_BPS = 500;
    uint256 public constant INCREASE_BPS = 250;
    uint256 public constant BPS = 10_000;

    AuctionEdition public immutable edition;
    address public payoutWallet;
    address public pendingPayoutWallet;
    uint128 public immutable reservePrice;
    uint64 public immutable startTime;
    uint256 public immutable initialEndTime;
    uint256 public endTime;
    bool public settled;
    uint256 public clearingPrice;
    uint256 public nextBidId = 1;
    uint256 public head;
    uint256 public tail;
    uint256 public activeCount;
    uint256 public unsoldRemaining;
    uint256 public reservedRemaining = RESERVED_SUPPLY;
    uint256 public tokensClaimed;

    /// @dev Before settlement: winning escrow. Afterwards: uncredited winner overpayments.
    uint256 public escrow;
    uint256 public totalRefunds;
    uint256 public pendingProceeds;
    mapping(uint256 => Bid) public bids;
    mapping(address => uint256) public refunds;

    error InvalidConfiguration();
    error BiddingClosed();
    error BidTooLow();
    error BidTooLarge();
    error InvalidBid();
    error Unauthorized();
    error AuctionNotEnded();
    error AlreadySettled();
    error NotSettled();
    error AlreadyClaimed();
    error InvalidBatch();
    error InvalidRecipient();
    error NothingToWithdraw();
    error TransferFailed();
    error InvalidPayoutWallet();
    error NoPendingPayoutWallet();

    event BidCreated(uint256 indexed id, address indexed bidder, uint256 amount);
    event BidIncreased(uint256 indexed id, uint256 amount);
    event BidDisplaced(uint256 indexed id, address indexed bidder, uint256 refund);
    event AuctionExtended(uint256 endTime);
    event AuctionSettled(uint256 clearingPrice, uint256 winners, uint256 proceeds);
    event RefundCredited(uint256 indexed id, address indexed bidder, uint256 amount);
    event TokensClaimed(uint256 indexed id, address indexed bidder, address indexed recipient, uint256 tokenId);
    event ReservedClaimed(address indexed recipient, uint256 firstTokenId, uint256 quantity);
    event UnsoldClaimed(address indexed recipient, uint256 firstTokenId, uint256 quantity);
    event RefundWithdrawn(address indexed bidder, address indexed recipient, uint256 amount);
    event ProceedsWithdrawn(address indexed recipient, uint256 amount);
    event PayoutWalletProposed(address indexed currentWallet, address indexed proposedWallet);
    event PayoutWalletChangeCancelled(address indexed cancelledWallet);
    event PayoutWalletChanged(address indexed previousWallet, address indexed newWallet);

    constructor(Config memory config) {
        if (config.reservePrice == 0 || config.startTime <= block.timestamp) revert InvalidConfiguration();
        payoutWallet = config.payoutWallet;
        reservePrice = config.reservePrice;
        startTime = config.startTime;
        initialEndTime = uint256(config.startTime) + AUCTION_DURATION;
        endTime = initialEndTime;
        edition =
            new AuctionEdition(config.collectionName, config.collectionSymbol, config.metadataURI, config.royaltyBps);
        _validatePayoutWallet(config.payoutWallet);
    }

    /// @notice Nominate a replacement for the shared auction/trading payout wallet. It must accept.
    function proposePayoutWallet(address proposed) external nonReentrant {
        if (msg.sender != payoutWallet) revert Unauthorized();
        _validatePayoutWallet(proposed);
        if (proposed == payoutWallet) revert InvalidPayoutWallet();
        pendingPayoutWallet = proposed;
        emit PayoutWalletProposed(payoutWallet, proposed);
    }

    /// @notice Cancels a nomination; the current wallet keeps all payout authority until acceptance.
    function cancelPayoutWalletChange() external nonReentrant {
        if (msg.sender != payoutWallet) revert Unauthorized();
        address proposed = pendingPayoutWallet;
        if (proposed == address(0)) revert NoPendingPayoutWallet();
        pendingPayoutWallet = address(0);
        emit PayoutWalletChangeCancelled(proposed);
    }

    /// @notice The nominated wallet accepts control of unwithdrawn proceeds and trading royalties.
    /// @dev No funds are sent and no third-party bidder/seller entitlements are reassigned.
    function acceptPayoutWallet() external nonReentrant {
        address proposed = pendingPayoutWallet;
        if (proposed == address(0) || msg.sender != proposed) revert Unauthorized();
        address previous = payoutWallet;
        payoutWallet = proposed;
        pendingPayoutWallet = address(0);
        emit PayoutWalletChanged(previous, proposed);
    }

    function phase() public view returns (Phase) {
        if (settled) return Phase.Settled;
        if (block.timestamp < startTime) return Phase.Scheduled;
        if (block.timestamp < endTime) return Phase.Live;
        return Phase.Ended;
    }

    /// @notice At capacity a new bid must exceed the current floor by 5%, rounded up.
    /// @dev May exceed MAX_BID: in that case no further new bid is possible, but settlement still is.
    function minimumBid() public view returns (uint256) {
        if (activeCount < SUPPLY) return reservePrice;
        uint256 floor = bids[tail].amount;
        return floor + minimumIncrement(floor, OUTBID_BPS);
    }

    function minimumIncrease(uint256 id) external view returns (uint256) {
        if (!bids[id].active) revert InvalidBid();
        return minimumIncrement(bids[id].amount, INCREASE_BPS);
    }

    function createBid() external payable nonReentrant returns (uint256 id) {
        _requireLive();
        if (msg.value > MAX_BID) revert BidTooLarge();
        if (msg.value < minimumBid()) revert BidTooLow();
        id = nextBidId++;
        bids[id] = Bid(msg.sender, uint128(msg.value), 0, 0, true, false, false, 0);
        escrow += msg.value;
        _insert(id);
        if (activeCount > SUPPLY) {
            uint256 displacedId = tail;
            Bid storage displaced = bids[displacedId];
            _unlink(displacedId);
            displaced.active = false;
            displaced.refundCredited = true;
            uint256 amount = displaced.amount;
            escrow -= amount;
            refunds[displaced.bidder] += amount;
            totalRefunds += amount;
            emit BidDisplaced(displacedId, displaced.bidder, amount);
        }
        _extend();
        emit BidCreated(id, msg.sender, msg.value);
    }

    /// @notice Add ETH to your active bid. Earlier bid IDs retain priority when totals tie.
    function increaseBid(uint256 id) external payable nonReentrant {
        _requireLive();
        Bid storage bid = bids[id];
        if (!bid.active) revert InvalidBid();
        if (bid.bidder != msg.sender) revert Unauthorized();
        if (msg.value > MAX_BID - bid.amount) revert BidTooLarge();
        if (msg.value < minimumIncrement(bid.amount, INCREASE_BPS)) revert BidTooLow();
        uint256 oldPrev = bid.prev;
        _unlink(id);
        bid.amount += uint128(msg.value);
        escrow += msg.value;
        _insert(id);
        if (oldPrev != bid.prev) _extend();
        emit BidIncreased(id, bid.amount);
    }

    /// @notice Anyone can finalize at/after endTime and assign the at most 90 token IDs. No receivers are called.
    function settle() external nonReentrant {
        if (settled) revert AlreadySettled();
        if (block.timestamp < endTime) revert AuctionNotEnded();
        settled = true;
        clearingPrice = activeCount < SUPPLY ? reservePrice : bids[tail].amount;
        uint256 gross = activeCount == 0 ? 0 : uint256(bids[head].amount) + clearingPrice * (activeCount - 1);
        pendingProceeds = gross;
        escrow -= gross;
        unsoldRemaining = SUPPLY - activeCount;
        uint256 id = head;
        for (uint256 rank = 1; id != 0; ++rank) {
            bids[id].tokenId = uint16(rank);
            id = bids[id].next;
        }
        emit AuctionSettled(clearingPrice, activeCount, gross);
    }

    /// @notice Final cost of this winning bid. The NFT #1 winner pays its full bid; all others pay clearingPrice.
    function winningBidCost(uint256 id) public view returns (uint256) {
        if (!settled) revert NotSettled();
        if (!bids[id].active) revert InvalidBid();
        return id == head ? bids[id].amount : clearingPrice;
    }

    /// @notice Anyone can credit winner overpayments; refunds always belong to the original bidder.
    /// @dev Independent of NFT delivery, so a rejecting ERC-721 receiver can still obtain its refund.
    function creditRefunds(uint256[] calldata ids) external nonReentrant {
        _requireSettledBatch(ids.length);
        uint256 credited;
        for (uint256 i; i < ids.length; ++i) {
            uint256 id = ids[i];
            Bid storage bid = bids[id];
            if (!bid.active) revert InvalidBid();
            if (bid.refundCredited) continue;
            bid.refundCredited = true;
            uint256 amount = uint256(bid.amount) - winningBidCost(id);
            credited += amount;
            refunds[bid.bidder] += amount;
            emit RefundCredited(id, bid.bidder, amount);
        }
        escrow -= credited;
        totalRefunds += credited;
    }

    /// @notice Only the winning bidder can claim its wins, choosing the receiving wallet.
    /// @dev Each failed delivery reverts this batch only. Retry individually or redirect; refunds are independent.
    function claimTokens(uint256[] calldata ids, address recipient) external nonReentrant {
        _requireSettledBatch(ids.length);
        if (recipient == address(0)) revert InvalidRecipient();
        uint256[] memory tokenIds = new uint256[](ids.length);
        for (uint256 i; i < ids.length; ++i) {
            Bid storage bid = bids[ids[i]];
            if (!bid.active) revert InvalidBid();
            if (bid.tokenClaimed) revert AlreadyClaimed();
            if (msg.sender != bid.bidder) revert Unauthorized();
            bid.tokenClaimed = true;
            tokenIds[i] = bid.tokenId;
            emit TokensClaimed(ids[i], bid.bidder, recipient, bid.tokenId);
        }
        tokensClaimed += ids.length;
        edition.mint(recipient, tokenIds);
    }

    function claimUnsold(uint256 quantity, address recipient) external nonReentrant {
        if (!settled) revert NotSettled();
        if (msg.sender != payoutWallet) revert Unauthorized();
        if (recipient == address(0)) revert InvalidRecipient();
        if (quantity == 0 || quantity > unsoldRemaining) revert InvalidBatch();
        uint256 firstTokenId = SUPPLY - unsoldRemaining + 1;
        uint256[] memory tokenIds = new uint256[](quantity);
        for (uint256 i; i < quantity; ++i) {
            tokenIds[i] = firstTokenId + i;
        }
        unsoldRemaining -= quantity;
        edition.mint(recipient, tokenIds);
        emit UnsoldClaimed(recipient, firstTokenId, quantity);
    }

    /// @notice Claim the 10 creator NFTs, IDs 91–100, independently of auction bidding and settlement.
    function claimReserved(uint256 quantity, address recipient) external nonReentrant {
        if (msg.sender != payoutWallet) revert Unauthorized();
        if (recipient == address(0)) revert InvalidRecipient();
        if (quantity == 0 || quantity > reservedRemaining) revert InvalidBatch();
        uint256 firstTokenId = SUPPLY + RESERVED_SUPPLY - reservedRemaining + 1;
        uint256[] memory tokenIds = new uint256[](quantity);
        for (uint256 i; i < quantity; ++i) {
            tokenIds[i] = firstTokenId + i;
        }
        reservedRemaining -= quantity;
        edition.mint(recipient, tokenIds);
        emit ReservedClaimed(recipient, firstTokenId, quantity);
    }

    function withdrawRefund(address payable recipient) external nonReentrant {
        uint256 amount = refunds[msg.sender];
        refunds[msg.sender] = 0;
        totalRefunds -= amount;
        _send(recipient, amount);
        emit RefundWithdrawn(msg.sender, recipient, amount);
    }

    function withdrawProceeds(address payable recipient) external nonReentrant {
        if (msg.sender != payoutWallet) revert Unauthorized();
        uint256 amount = pendingProceeds;
        pendingProceeds = 0;
        _send(recipient, amount);
        emit ProceedsWithdrawn(recipient, amount);
    }

    /// @notice Total protected ETH. Forced ETH is surplus, and never changes the clearing price or liabilities.
    function liabilities() public view returns (uint256) {
        return escrow + totalRefunds + pendingProceeds;
    }

    /// @notice Bounded ranking pagination; use the returned next ID for the next page.
    function rankedBids(uint256 first, uint256 limit) external view returns (uint256[] memory ids, uint256 next) {
        if (limit == 0 || limit > SUPPLY) revert InvalidBatch();
        next = first == 0 ? head : first;
        if (next != 0 && !bids[next].active) revert InvalidBid();
        uint256 count = 0;
        uint256 cursor = next;
        while (cursor != 0 && count < limit) {
            ++count;
            cursor = bids[cursor].next;
        }
        ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = next;
            next = bids[next].next;
        }
    }

    function _requireLive() private view {
        if (phase() != Phase.Live) revert BiddingClosed();
    }

    function _requireSettledBatch(uint256 length) private view {
        if (!settled) revert NotSettled();
        if (length == 0 || length > SUPPLY) revert InvalidBatch();
    }

    function minimumIncrement(uint256 amount, uint256 bps) private pure returns (uint256) {
        return (amount * bps + BPS - 1) / BPS;
    }

    /// @dev O(90) storage reads, O(1) writes. Stable ties by original ID, independent of insertion hints.
    function _insert(uint256 id) private {
        Bid storage bid = bids[id];
        uint256 current = head;
        uint256 previous;
        while (current != 0) {
            Bid storage other = bids[current];
            if (bid.amount > other.amount || (bid.amount == other.amount && id < current)) break;
            previous = current;
            current = other.next;
        }
        bid.prev = previous;
        bid.next = current;
        if (previous == 0) head = id;
        else bids[previous].next = id;
        if (current == 0) tail = id;
        else bids[current].prev = id;
        ++activeCount;
    }

    function _unlink(uint256 id) private {
        Bid storage bid = bids[id];
        if (bid.prev == 0) head = bid.next;
        else bids[bid.prev].next = bid.next;
        if (bid.next == 0) tail = bid.prev;
        else bids[bid.next].prev = bid.prev;
        bid.prev = 0;
        bid.next = 0;
        --activeCount;
    }

    function _extend() private {
        if (endTime - block.timestamp >= EXTENSION_WINDOW) return;
        endTime = block.timestamp + EXTENSION_WINDOW;
        emit AuctionExtended(endTime);
    }

    function _validatePayoutWallet(address wallet) private view {
        if (
            wallet == address(0) || wallet == address(this) || wallet == address(edition)
                || wallet == address(edition.marketplace())
        ) revert InvalidPayoutWallet();
    }

    function _send(address payable recipient, uint256 amount) private {
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
        if (amount == 0) revert NothingToWithdraw();
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) revert TransferFailed();
    }
}
