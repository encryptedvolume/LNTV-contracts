// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721} from "@openzeppelin-contracts-5.5.0/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin-contracts-5.5.0/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.5.0/utils/ReentrancyGuard.sol";

/// @title Transient Ranked Auction
/// @notice Fully onchain ranked auction using a sorted doubly linked list.
///         Supports any number of tokens between 2 and 512 (inclusive).
/// @author mpeyfuss
contract TLRankedAuction is Ownable, ReentrancyGuard {
    /////////////////////////////////////////////////////////////////////
    // Types
    /////////////////////////////////////////////////////////////////////

    enum AuctionState {
        CONFIGURING,
        LIVE,
        SETTLING,
        SETTLED
    }

    struct BidNode {
        uint128 amount;
        uint32 next;
        uint32 prev;
        uint32 rank;
        bool claimed;
    }

    struct BidView {
        uint32 bidId;
        address bidder;
        uint128 amount;
        uint32 next;
        uint32 prev;
        uint32 rank;
        bool claimed;
    }

    /////////////////////////////////////////////////////////////////////
    // Storage
    /////////////////////////////////////////////////////////////////////

    // constants
    uint256 public constant GAS_GRIEFING_LIMIT = 1e5;
    uint256 public constant EXTENSION_TIME = 5 minutes;
    uint256 public constant EXTENSION_HARD_CAP = 2 hours;
    uint128 public constant BASIS = 10_000;
    uint128 public constant CREATE_BID_BPS = 250; // 2.5%
    uint128 public constant INCREASE_BID_BPS = 50; // 0.5%
    uint256 public constant MAX_TOKENS = 512; // upper bound to keep looped external calls manageable

    // immutable storage set on initialization
    IERC721 public immutable NFT_CONTRACT;
    uint128 public immutable START_BID;
    uint32 public immutable NUM_TOKENS; // capped by MAX_TOKENS in the constructor

    // auction state
    AuctionState public state;

    // storage for setting up the auction
    uint64 public openAt;
    uint64 public duration;
    uint64 public hardEndAt;
    uint256[] public prizeTokenIds;

    // storage for bids
    mapping(uint32 => BidNode) private _bids;
    mapping(uint32 => address) private _bidders;
    uint32 public nextBidId = 1;
    uint32 public listSize;
    uint32 public head;
    uint32 public tail;

    // storage for settling the auction
    uint128 public clearingPrice;
    uint32 public lastProcessedId;
    uint32 public nextRank = 1;
    uint32 public nextUnallocatedRank;
    uint256 public pendingProceeds;

    // refund bucket if auto-payout fails
    mapping(address => uint256) public pendingRefunds; // user address => amount of refund they can reclaim

    // nft bucket if transfer on claim fails
    mapping(uint256 => address) public pendingNfts; // token id => user that can reclaim it

    /////////////////////////////////////////////////////////////////////
    // Events
    /////////////////////////////////////////////////////////////////////

    event AuctionConfigured(uint64 openAt, uint64 duration);
    event AuctionExtended(uint64 newDuration);
    event AuctionReset();
    event AuctionSettling(uint256 clearingPrice);
    event AuctionSettled();
    event BidCreated(address indexed bidder, uint32 indexed bidId, uint256 amount);
    event BidIncreased(address indexed bidder, uint32 indexed bidId, uint256 newAmount);
    event BidRanked(uint32 indexed bidId, uint32 rank);
    event BidRemoved(address indexed bidder, uint32 indexed bidId, uint256 amount);
    event PrizeTokenEscrowed(uint256 indexed tokenId);
    event PrizeTokenClaimed(address indexed winner, uint256 indexed tokenId, uint256 refund);
    event PrizeTokenWithdrawn(address indexed recipient, uint256 indexed tokenId);
    event PrizeTokenRescued(address indexed winner, address indexed recipient, uint256 indexed tokenId);
    event PrizeTokenTransferFailed(address indexed winner, uint256 indexed tokenId);
    event RefundQueued(address indexed user, uint256 amount);
    event RefundWithdrawn(address indexed user, address indexed recipient, uint256 amount);

    /////////////////////////////////////////////////////////////////////
    // Errors
    /////////////////////////////////////////////////////////////////////

    error AddMore();
    error AuctionNotEnded();
    error BidClaimed();
    error BidMore();
    error BiddingEnded();
    error BiddingNotOpen();
    error BidsHaveBeenPlaced();
    error DepositAllPrizeTokens();
    error InvalidAddress();
    error InvalidBid();
    error InvalidNftContract();
    error InvalidRank();
    error InvalidStartBid();
    error InvariantBroken();
    error NotAllowed();
    error NotBidder();
    error NothingToWithdraw();
    error ProcessAtLeastOne();
    error TooFewTokens();
    error TooManyTokens();
    error WithdrawalFailed();

    /////////////////////////////////////////////////////////////////////
    // Constructor
    /////////////////////////////////////////////////////////////////////

    constructor(address owner_, address nftContract, uint128 startBid, uint32 numTokens) Ownable(owner_) {
        if (numTokens < 2) revert TooFewTokens();
        if (numTokens > MAX_TOKENS) revert TooManyTokens();
        if (startBid < BASIS) revert InvalidStartBid();
        if (nftContract.code.length == 0) revert InvalidNftContract(); // simple check for code is typically fine
        NFT_CONTRACT = IERC721(nftContract);
        START_BID = startBid;
        NUM_TOKENS = numTokens;
    }

    /////////////////////////////////////////////////////////////////////
    // Bid Functions
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to create a bid, using a hint bid id to lower gas consumption.
    /// @dev If `hintBidId` is invalid, it will walk the entire list. Otherwise, will walk UP or DOWN from the hint.
    function createBid(uint32 hintBidId) external payable nonReentrant {
        // check auction is open
        _checkAuctionOpen();

        // check min bid
        uint128 amount = uint128(msg.value);
        uint128 minBid = _getMinBid();
        if (amount < minBid) revert BidMore();

        // insert bid
        uint32 bidId = nextBidId;
        unchecked {
            nextBidId = bidId + 1;
        }
        _insertBid(hintBidId, bidId, msg.sender, amount);

        // extend duration if needed
        _extendAuctionDuration();

        // remove tail, if needed
        _removeTailAndRefund();

        emit BidCreated(msg.sender, bidId, amount);
    }

    /// @notice Function to add onto a bid, again using a hint bid id for a new insertion point.
    /// @dev Removes the bid from it's current position and then inserts it again using the hint.
    ///      There's no need to remove the tail as we aren't increasing the list size.
    ///      The bid must increase over itself by `INCREASE_BID_BPS` and can extend the auction
    ///      if the position of the bid changes in the list.
    function increaseBid(uint32 bidId, uint32 hintBidId) external payable nonReentrant {
        // check auction is open
        _checkAuctionOpen();

        // ensure bid is a real bid in the list
        if (!_isBidInList(bidId)) revert InvalidBid();

        // cache storage pointer
        BidNode storage bid = _bids[bidId];

        // ensure the bidder is the one calling this function
        address bidder = _bidders[bidId];
        if (msg.sender != bidder) revert NotBidder();

        // cache bid amount
        uint128 bidAmount = bid.amount;

        // make sure enough eth was sent
        if (msg.value < _getMinBidIncrease(bidAmount)) revert AddMore();

        // calculate the new bid amount
        uint128 newBidAmount = bidAmount + uint128(msg.value);

        // cache the old bid pointers
        uint32 oldNextId = bid.next;
        uint32 oldPrevId = bid.prev;

        // pop the bid
        _popBid(bidId);

        // insert bid again
        _insertBid(hintBidId, bidId, bidder, newBidAmount);

        // extend auction duration, only if the bid position has changed
        if (oldNextId != bid.next || oldPrevId != bid.prev) {
            _extendAuctionDuration();
        }

        emit BidIncreased(bidder, bidId, newBidAmount);
    }

    /// @dev Internal helper to ensure the auction is open
    function _checkAuctionOpen() internal view {
        if (state != AuctionState.LIVE) revert NotAllowed();
        if (block.timestamp < uint256(openAt)) revert BiddingNotOpen();
        uint256 endTime = uint256(openAt + duration);
        if (block.timestamp > endTime) revert BiddingEnded();
    }

    /// @dev Internal helper to extend the auction on bid or bid increase, if needed.
    ///      This is an anti-snipe measure and the hard end cap stops a DOS attack.
    function _extendAuctionDuration() internal {
        // check end time
        uint256 endTime = uint256(openAt + duration);
        uint256 timeRemaining = endTime - block.timestamp;
        if (timeRemaining >= EXTENSION_TIME) return;

        // calculate desired end time
        uint256 desiredEndTime = block.timestamp + EXTENSION_TIME;

        // check against the hard cap
        uint256 newEnd = desiredEndTime > hardEndAt ? hardEndAt : desiredEndTime;

        // if doesn't change anything, return
        if (newEnd <= endTime) return;

        // extend duration
        duration = uint64(newEnd) - openAt;
        emit AuctionExtended(duration);
    }

    /// @dev Internal helper function to insert a bid.
    function _insertBid(uint32 hintBidId, uint32 bidId, address bidder, uint128 amount) internal {
        uint32 prevId = _findInsertionSpot(hintBidId, amount);
        uint32 nextId;

        // save new bid
        if (prevId == 0) {
            // new head
            nextId = head;
            head = bidId;
        } else {
            // middle/end insertion
            nextId = _bids[prevId].next;
            _bids[prevId].next = bidId;
        }
        _bids[bidId] = BidNode({amount: amount, next: nextId, prev: prevId, rank: 0, claimed: false});
        _bidders[bidId] = bidder;

        if (nextId == 0) {
            // new tail, no need to make a reverse link to the new bid
            tail = bidId;
        } else {
            // middle insertion so make sure the reverse link to the new bid is set
            _bids[nextId].prev = bidId;
        }

        // increase list size
        unchecked {
            ++listSize;
        }
    }

    /// @dev Internal helper to find the insertion spot
    ///      Returns the bid to insert AFTER
    ///      Returning 0 means new head.
    ///      Returning anything else is the new insertion spot.
    function _findInsertionSpot(uint32 hintBidId, uint128 amount) internal view returns (uint32) {
        uint32 listSize_ = listSize; // cache for gas

        // special case: new head
        if (listSize_ == 0 || amount > _getHeadBid()) return 0;

        // determine start spot
        uint32 current = hintBidId;
        if (current == 0 || !_isBidInList(current)) {
            // invalid bid, start at head
            current = head;
        }

        // walk the list
        if (amount <= _bids[current].amount) {
            // walk down
            for (uint256 i = 0; i < listSize_; ++i) {
                uint32 next = _bids[current].next;
                if (next == 0 || amount > _bids[next].amount) {
                    return current;
                }
                current = next;
            }
        } else {
            // walk up
            for (uint256 i = 0; i < listSize_; ++i) {
                uint32 prev = _bids[current].prev;
                if (prev == 0 || amount <= _bids[prev].amount) {
                    return prev;
                }
                current = prev;
            }
        }

        // if get here, should revert
        revert InvariantBroken();
    }

    /// @dev Internal helper to pop a bid from the list
    function _popBid(uint32 bidId) internal {
        // cache data
        uint32 prevId = _bids[bidId].prev;
        uint32 nextId = _bids[bidId].next;

        // adjust next bid
        if (nextId == 0) {
            // bid was the tail - set new tail
            tail = prevId;
        } else {
            _bids[nextId].prev = prevId;
        }

        // adjust prev bid
        if (prevId == 0) {
            // bid was the head - set new head
            head = nextId;
        } else {
            _bids[prevId].next = nextId;
        }

        // adjust bid pointers
        _bids[bidId].next = 0;
        _bids[bidId].prev = 0;

        // adjust list listSize
        unchecked {
            --listSize;
        }
    }

    /// @dev Internal helper function to remove the tail and refund.
    function _removeTailAndRefund() internal {
        // only remove tail if listSize is greater than the number of tokens
        if (listSize <= NUM_TOKENS) return;

        // get old tail
        uint32 oldTailId = tail;
        BidNode memory oldTail = _bids[oldTailId];
        address oldTailBidder = _bidders[oldTailId];

        // set new tail
        uint32 newTail = oldTail.prev;
        tail = newTail;
        _bids[newTail].next = 0;

        // delete old tail
        delete _bids[oldTailId];
        delete _bidders[oldTailId];
        unchecked {
            --listSize;
        }

        // refund ETH
        _tryRefundEth(oldTailBidder, uint256(oldTail.amount));

        emit BidRemoved(oldTailBidder, oldTailId, oldTail.amount);
    }

    /////////////////////////////////////////////////////////////////////
    // Settlement Functions
    /////////////////////////////////////////////////////////////////////

    /// @notice function to kick off the settlling of the auction
    /// @dev Anyone can call this after the preconditions are met
    ///      The clearing price is the tail bid only if all tokens are allocated.
    ///      Otherwise, the clearing price is the start price. This means that
    ///      the starting price should always be set to something you're okay
    ///      settling at unless you're confident it'll sell out.
    function startSettlingAuction() external nonReentrant {
        if (state != AuctionState.LIVE) revert NotAllowed();
        uint64 endTime = openAt + duration;
        if (block.timestamp <= uint256(endTime)) revert AuctionNotEnded();

        if (listSize == 0) {
            state = AuctionState.SETTLED;
            clearingPrice = START_BID;
            nextUnallocatedRank = 1;

            emit AuctionSettling(clearingPrice);
            emit AuctionSettled();
        } else {
            state = AuctionState.SETTLING;
            clearingPrice = listSize < NUM_TOKENS ? START_BID : _getTailBid();
            unchecked { 
                pendingProceeds = uint256(listSize) * uint256(clearingPrice);
                nextUnallocatedRank = listSize + 1;
            }
            
            emit AuctionSettling(clearingPrice);
        }
    }

    /// @notice Function to batch process ranks of bids.
    /// @dev Walks DOWN the list from the head to the tail and updates `lastProcessedId` to handle batches.
    function processRanks(uint32 numToProcess) external nonReentrant {
        if (state != AuctionState.SETTLING) revert NotAllowed();

        // cap numToProcess
        uint32 alreadyProcessed;
        unchecked {
            alreadyProcessed = nextRank - 1;
        }
        uint32 remaining = listSize > alreadyProcessed ? (listSize - alreadyProcessed) : 0;
        if (numToProcess > remaining) {
            numToProcess = remaining;
        }
        if (numToProcess == 0) revert ProcessAtLeastOne();

        // check that the last processed id has been ranked
        if (lastProcessedId != 0 && _bids[lastProcessedId].rank != (nextRank - 1)) revert InvariantBroken(); // something went wrong if reverts

        // start at head or the bid after the last processed
        uint32 current = lastProcessedId == 0 ? head : _bids[lastProcessedId].next;
        uint32 processedId = lastProcessedId;

        // process ranks
        for (uint256 i = 0; i < numToProcess; ++i) {
            if (current == 0) revert InvariantBroken(); // safety measure to catch regression
            uint32 rank = nextRank;
            unchecked { 
                nextRank = rank + 1;
            }
            _bids[current].rank = rank;
            processedId = current;
            current = _bids[current].next;
            emit BidRanked(processedId, rank);
        }

        // store last processed id once
        lastProcessedId = processedId;

        // settle if at the tail
        if (processedId == tail) {
            // move to next auction state
            state = AuctionState.SETTLED;
            emit AuctionSettled();
        }
    }

    /// @notice Function to claim the result of a bid.
    /// @dev Can be called by anyone but only sends out the NFT & refund to the bidder.
    ///      Auction must be settled in order to call this.
    function claim(uint32 bidId) external nonReentrant {
        if (state != AuctionState.SETTLED) revert NotAllowed();

        // get bid information
        BidNode storage storedBid = _bids[bidId];
        address bidder = _bidders[bidId];

        // check if bid valid or already claimed
        if (storedBid.rank == 0) revert InvalidBid();
        if (storedBid.claimed) revert BidClaimed();

        // mark claimed
        storedBid.claimed = true;

        // claim prize & refund
        uint256 prizeTokenId;
        uint256 refund;
        unchecked {
            prizeTokenId = prizeTokenIds[storedBid.rank - 1]; // minus one since rank is one based, but array is zero based
            refund = uint256(storedBid.amount - clearingPrice);
        }
        if (refund > 0) {
            _tryRefundEth(bidder, refund);
        }
        try NFT_CONTRACT.safeTransferFrom(address(this), bidder, prizeTokenId) {
            // success
            emit PrizeTokenClaimed(bidder, prizeTokenId, refund);
        } catch {
            // flag nft as needing rescuing
            pendingNfts[prizeTokenId] = bidder;
            emit PrizeTokenTransferFailed(bidder, prizeTokenId);
        }
    }

    /// @notice Function to withdraw left over prize tokens after the auction has been settled.
    /// @dev Uses a separate rank counter than what's used during `processRanks` for separation of concerns
    ///      and invariant tracking.
    function withdrawLeftOverPrizeTokens(address tokenRecipient, uint256 numToProcess)
        external
        nonReentrant
        onlyOwner
    {
        if (state != AuctionState.SETTLED) revert NotAllowed();
        if (listSize == NUM_TOKENS) revert NothingToWithdraw();
        if (tokenRecipient == address(0)) revert InvalidAddress();

        // cap numToProcess
        uint32 alreadyProcessed;
        uint32 remaining;
        unchecked {
            alreadyProcessed = nextUnallocatedRank - 1;
            remaining = NUM_TOKENS - alreadyProcessed;
        }
        if (numToProcess > remaining) {
            numToProcess = remaining;
        }
        if (numToProcess == 0) revert ProcessAtLeastOne();

        // withdraw prize tokens
        for (uint256 i = 0; i < numToProcess; ++i) {
            uint32 rank = nextUnallocatedRank;
            uint256 prizeTokenId;
            unchecked { 
                nextUnallocatedRank = rank + 1;
                prizeTokenId = prizeTokenIds[rank - 1]; // rank is ones based
            }
            NFT_CONTRACT.safeTransferFrom(address(this), tokenRecipient, prizeTokenId);

            emit PrizeTokenWithdrawn(tokenRecipient, prizeTokenId);
        }
    }

    /// @notice Function to withdraw pending proceeds.
    /// @dev The owner can withdraw prior to people claiming their winning tokens, but it is safe
    ///      since `pendingProceeds` is calculated before the contract enters the `SETTLING` state.
    function withdrawPendingProceeds(uint256 amount, address payoutAddress) external nonReentrant onlyOwner {
        if (state != AuctionState.SETTLED) revert NotAllowed();
        if (payoutAddress == address(0)) revert InvalidAddress();

        // calculate amount to withdraw
        uint256 amountToWithdraw = amount > pendingProceeds ? pendingProceeds : amount;
        if (amountToWithdraw == 0) revert NothingToWithdraw();

        // effects
        unchecked {
            pendingProceeds -= amountToWithdraw;
        }

        // withdraw
        (bool success,) = payoutAddress.call{value: amountToWithdraw}("");
        if (!success) {
            revert WithdrawalFailed();
        }
    }

    /////////////////////////////////////////////////////////////////////
    // Setup Functions
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to deposit token ids into the contract, in batches if necessary.
    /// @dev The contract must be given approval by the nft owner to escrow the tokens.
    ///      Owner can escrow from any approved token owner; this is an intentional admin workflow.
    ///      The tokens should be deposited in the order in which they should be distributed based on rank.
    ///      i.e. [1,2,3] rather than [3,2,1] if rank one should get token id 1.
    function depositPrizeTokens(address tokenOwner, uint256[] calldata tokenIdsToAdd) external nonReentrant onlyOwner {
        if (state != AuctionState.CONFIGURING) revert NotAllowed();
        if (prizeTokenIds.length + tokenIdsToAdd.length > NUM_TOKENS) revert TooManyTokens();
        if (tokenOwner == address(this)) revert InvalidAddress();

        for (uint256 i = 0; i < tokenIdsToAdd.length; ++i) {
            uint256 prizeTokenId = tokenIdsToAdd[i];
            // effect
            prizeTokenIds.push(prizeTokenId);
            // interaction
            // safe to use just `transferFrom` here as we are escrowing them in this contract
            NFT_CONTRACT.transferFrom(tokenOwner, address(this), prizeTokenId);

            emit PrizeTokenEscrowed(prizeTokenId);
        }
    }

    /// @notice Function for the owner to remove prize tokens if not done in the right order.
    /// @dev Not allowed unless configuring.
    function withdrawPrizeTokens(address tokenRecipient, uint256 numToWithdraw) external nonReentrant onlyOwner {
        if (state != AuctionState.CONFIGURING) revert NotAllowed();
        if (tokenRecipient == address(0)) revert InvalidAddress();
        if (numToWithdraw > prizeTokenIds.length) {
            numToWithdraw = prizeTokenIds.length;
        }

        while (numToWithdraw > 0) {
            uint256 prizeTokenId = prizeTokenIds[prizeTokenIds.length - 1];
            prizeTokenIds.pop();

            NFT_CONTRACT.safeTransferFrom(address(this), tokenRecipient, prizeTokenId);
            emit PrizeTokenWithdrawn(tokenRecipient, prizeTokenId);

            unchecked {
                --numToWithdraw;
            } // safe because we cap it to the length of the array
        }
    }

    /// @notice Function to setup the auction and enable bidding.
    /// @dev Can only be called after the tokens deposited meet the expected number.
    ///      If the order isn't correct, use the `withdrawPrizeTokens` function and deposit again.
    ///      If `openAt_` is less than the current block timestamp, set to the current block timestamp.
    ///      Similarly, if `duration_` is less than `EXTENSION_TIME`, set to `EXTENSION_TIME`
    function setupAuction(uint64 openAt_, uint64 duration_) external nonReentrant onlyOwner {
        if (state != AuctionState.CONFIGURING) revert NotAllowed();
        if (prizeTokenIds.length != NUM_TOKENS) revert DepositAllPrizeTokens();

        state = AuctionState.LIVE;
        if (openAt_ < block.timestamp) {
            openAt_ = uint64(block.timestamp);
        }
        if (duration_ < EXTENSION_TIME) {
            duration_ = uint64(EXTENSION_TIME);
        }
        openAt = openAt_;
        duration = duration_;
        hardEndAt = openAt + duration + uint64(EXTENSION_HARD_CAP);

        emit AuctionConfigured(openAt_, duration_);
    }

    /// @notice Function to reset an auction back to `CONFIGURING` in case of error in setup.
    /// @dev This can only be done before any bid comes in and can only be called by the owner.
    function resetAuction() external nonReentrant onlyOwner {
        if (state != AuctionState.LIVE) revert NotAllowed();
        if (listSize > 0) revert BidsHaveBeenPlaced();

        state = AuctionState.CONFIGURING;
        openAt = 0;
        duration = 0;
        hardEndAt = 0;

        emit AuctionReset();
    }

    /////////////////////////////////////////////////////////////////////
    // Reclaim Functions
    /////////////////////////////////////////////////////////////////////

    /// @notice Function for someone to manually pull a refund that reverted prior.
    function rescueRefund(address recipient) external nonReentrant {
        if (recipient == address(0)) revert InvalidAddress();
        uint256 refund = pendingRefunds[msg.sender];
        if (refund == 0) revert NothingToWithdraw();

        // clear pending refund for msg sender
        pendingRefunds[msg.sender] = 0;

        // refund to the specified recipient
        (bool success,) = recipient.call{value: refund}("");
        if (success) {
            emit RefundWithdrawn(msg.sender, recipient, refund); // emit event based on msg sender
        } else {
            revert WithdrawalFailed();
        }
    }

    /// @notice Function to rescue an nft that failed to transfer on claim.
    /// @dev In practice, this shouldn't happen, but you never know.
    ///      The caller must be the rightful reclaimer, but they can specify a new token recipient.
    function rescueNft(address recipient, uint256 tokenId) external nonReentrant {
        if (recipient == address(0)) revert InvalidAddress();
        address pendingNftOwner = pendingNfts[tokenId];
        if (pendingNftOwner == address(0)) revert NothingToWithdraw();
        if (pendingNftOwner != msg.sender) revert NotAllowed();

        // clear pending nft
        pendingNfts[tokenId] = address(0);

        // send NFT
        NFT_CONTRACT.safeTransferFrom(address(this), recipient, tokenId);

        emit PrizeTokenRescued(msg.sender, recipient, tokenId);
    }

    /////////////////////////////////////////////////////////////////////
    // View Functions
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to get important auction info.
    function getAuctionInfo()
        external
        view
        returns (
            AuctionState state_,
            uint64 openAt_,
            uint64 duration_,
            uint64 hardEndAt_,
            uint128 clearingPrice_,
            uint32 listSize_,
            uint32 head_,
            uint32 tail_
        )
    {
        state_ = state;
        openAt_ = openAt;
        duration_ = duration;
        hardEndAt_ = hardEndAt;
        clearingPrice_ = clearingPrice;
        listSize_ = listSize;
        head_ = head;
        tail_ = tail;
    }

    /// @notice Function to get the minimum bid amount.
    function getMinBid() external view returns (uint128) {
        return _getMinBid();
    }

    /// @notice Function to calculate the minimum bid increase amount.
    function getMinBidIncrease(uint128 amount) external pure returns (uint128) {
        return _getMinBidIncrease(amount);
    }

    /// @notice Function to get the tail bid amount.
    function getTailBid() external view returns (uint128) {
        return _getTailBid();
    }

    /// @notice Function to get the head bid amount.
    function getHeadBid() external view returns (uint128) {
        return _getHeadBid();
    }

    /// @notice Function to get a full bid in detail.
    function getDetailedBid(uint32 bidId) public view returns (BidView memory) {
        BidNode memory storedBid = _bids[bidId];
        address bidder = _bidders[bidId];
        return BidView({
            bidId: bidId,
            bidder: bidder,
            amount: storedBid.amount,
            next: storedBid.next,
            prev: storedBid.prev,
            rank: storedBid.rank,
            claimed: storedBid.claimed
        });
    }

    /// @notice Function to get full bids as an array with pagination.
    function getBids(uint32 startBidId, uint32 limit)
        external
        view
        returns (BidView[] memory bids, uint32 numReturned)
    {
        bids = new BidView[](limit);
        uint32 current = startBidId == 0 ? head : startBidId;
        numReturned = 0;
        for (uint256 i = 0; i < limit; ++i) {
            if (current == 0) break;
            bids[i] = getDetailedBid(current);
            unchecked {
                ++numReturned;
            }
            current = bids[i].next;
        }
    }

    /// @notice Function to get the prize token for a rank.
    function getPrizeTokenIdForRank(uint32 rank) external view returns (uint256) {
        if (rank > NUM_TOKENS || rank == 0) revert InvalidRank();
        unchecked {
            return prizeTokenIds[rank - 1]; // rank is one based
        }
    }

    /////////////////////////////////////////////////////////////////////
    // Helper Functions
    /////////////////////////////////////////////////////////////////////

    /// @dev Helper function to get the minimum bid to be valid on bid creation.
    function _getMinBid() internal view returns (uint128) {
        if (listSize < NUM_TOKENS) {
            // underallocated list has min bid of `START_BID`
            return START_BID;
        } else {
            // fully allocated list has a min bid above tail bid to prevent bid pollution (outbid by 1 wei)
            uint256 tailBid = uint256(_bids[tail].amount);
            return uint128(tailBid + tailBid * CREATE_BID_BPS / BASIS);
        }
    }

    /// @dev Helper function to get the minimum bid increase amount to be valid on bid increase.
    function _getMinBidIncrease(uint128 bidAmount) internal pure returns (uint128) {
        return uint128(uint256(bidAmount) * INCREASE_BID_BPS / BASIS);
    }

    /// @dev Helper function to get the tail bid.
    function _getTailBid() internal view returns (uint128) {
        return _bids[tail].amount;
    }

    /// @dev Helper function to get the head bid.
    function _getHeadBid() internal view returns (uint128) {
        return _bids[head].amount;
    }

    /// @dev Helper function to determine if a bid is in the list
    function _isBidInList(uint32 bidId) internal view returns (bool) {
        // reject if bidder not stored
        if (_bidders[bidId] == address(0)) return false;

        // head & tail are always in the list if they exist
        if (bidId == head || bidId == tail) return true;

        // return true if pointers exist
        return _bids[bidId].prev != 0 || _bids[bidId].next != 0;
    }

    /// @dev Helper function to try to refund eth with gas griefing protection.
    function _tryRefundEth(address to, uint256 refund) internal {
        (bool success,) = to.call{value: refund, gas: GAS_GRIEFING_LIMIT}("");
        if (!success) {
            pendingRefunds[to] += refund;
            emit RefundQueued(to, refund);
        }
    }
}
