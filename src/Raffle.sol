// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Raffle contract
 * @author rh_bdl
 * @notice This is a personal project to improve understanding of raffle and chainlink
 * @dev Implement Chainlink techs
 */

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {console} from "forge-std/console.sol";

contract Raffle is VRFConsumerBaseV2 {
    error Raffle__InsufficientEth();
    error Raffle__RafleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 contractBalance,
        uint256 numPlayers,
        RaffleState raffleState
    );

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    uint256 private s_lastTimestamp;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    bytes32 private immutable i_gasLane;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    address payable[] private s_players;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimestamp = block.timestamp;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__InsufficientEth();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RafleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev The following automation (upkeep) will only be called if the conditions below are met:
     * 1. Sufficient time has passed from the last timestamp.
     * 2. Enum, RaffleState is open.
     * 3. There's Eth AND Players available in the contract.
     * 4. Subscription has to be funded with LINK tokens.
     * @return upkeepNeeded
     * @return
     */

    function checkUpkeep(
        bytes memory /*checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 1; // More than 1 otherwise raffle is pointless
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) public {
        (bool upkeepNeeded, ) = checkUpkeep("");
        console.log(address(this));
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                RaffleState(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner]; // Need to reset index of winners here, otherwise the same players are playing.
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimestamp = block.timestamp;
        (bool success, ) = winner.call{value: address(this).balance}("");
        require(success, "Failed to send ETH");

        emit PickedWinner(winner);
    }

    /** Getter Functions */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimestamp;
    }
}
