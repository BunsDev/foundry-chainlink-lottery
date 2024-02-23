// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /* Redefine events to be used in Test */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    uint256 deployerKey;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    //create new account and new player to test
    address public PLAYER_MAIN = makeAddr("player");
    address public PLAYER1 = makeAddr("player1");
    address public PLAYER2 = makeAddr("player2");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    modifier raffleEnteredAndTimePassedWithMainPlayer() {
        vm.prank(PLAYER_MAIN);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier raffleEnteredAndTimePassedWithMultiplePlayers() {
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: entranceFee}();
        vm.prank(PLAYER2);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    // this code sets up testing environment
    function setUp() external {
        // deploy contract for testing
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
            // deployerKey

        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER_MAIN, STARTING_USER_BALANCE);
        vm.deal(PLAYER1, STARTING_USER_BALANCE);
        vm.deal(PLAYER2, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN); //Access raffle state in any raffle contract
    }

    /** enterRaffle Test */
    function testRaffleRevertWhenInsufficientFunds() public {
        vm.prank(PLAYER_MAIN);
        vm.expectRevert(Raffle.Raffle__InsufficientEth.selector);
        raffle.enterRaffle();
    }

    function testPlayersEntering() public {
        vm.prank(PLAYER_MAIN);
        raffle.enterRaffle{value: entranceFee}();
        address recordedPlayer = raffle.getPlayer(0);
        assert(recordedPlayer == PLAYER_MAIN);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER_MAIN);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER_MAIN);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testUnableToEnterRaffleWhenCalculating()
        public
        raffleEnteredAndTimePassedWithMultiplePlayers
    {
        raffle.performUpkeep(""); // entire development of Interactions are for performUpkeep! Crazy!
        vm.expectRevert(Raffle.Raffle__RafleNotOpen.selector);
        vm.prank(PLAYER_MAIN);
        raffle.enterRaffle{value: entranceFee}();
    }

    /** checkUpkeep tests */

    function testCheckUpkeepForTrueOpenState() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert (This asserts not false being true)
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen()
        public
        raffleEnteredAndTimePassedWithMultiplePlayers
    {
        raffle.performUpkeep("");
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfOnlyOnePlayerJoined()
        public
        raffleEnteredAndTimePassedWithMainPlayer
    {
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    // testCheckUpkeepReturnsFalseIfNotEnoughTimePassed
    function testCheckUpkeepReturnsFalseIfNotEnoughTimePassed() public {
        vm.prank(PLAYER_MAIN);
        raffle.enterRaffle{value: entranceFee}();
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded == false);
    }

    // testCheckUpkeepReturnsTrueWhenParametersAreGood
    function testCheckUpkeepReturnsTrueWhenParametersAreGood()
        public
        raffleEnteredAndTimePassedWithMultiplePlayers
    {
        raffle.getRaffleState() == Raffle.RaffleState.OPEN;
        address(raffle).balance > 0;
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    /** performUpkeep Tests */
    function testPerformUpkeepTrueOnlyIfCheckUpkeepIsTrue()
        public
        raffleEnteredAndTimePassedWithMultiplePlayers
    {
        raffle.performUpkeep("");
    }

    // function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
    //     // Arrange
    //     uint256 currentBalance = 0;
    //     uint256 numPlayers = 0;
    //     uint256 raffleState = 0;

    //     // Act
    //     vm.expectRevert();
    //     (bool revertsAsExpected, ) = address(raffle).call(
    //         abi.encodeWithSelector(
    //             Raffle.Raffle__UpkeepNotNeeded.selector,
    //             currentBalance,
    //             numPlayers,
    //             raffleState
    //         )
    //     );

    //     // Assert
    //     assert(revertsAsExpected);
    // }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestid()
        public
        raffleEnteredAndTimePassedWithMultiplePlayers
    {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();

        // Assert to compare if there are any values, which is why larger than zero
        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEnteredAndTimePassedWithMultiplePlayers skipFork {
        //Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassedWithMainPlayer
        skipFork
    {
        // Arrange
        uint256 additionalEntrants = 10;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        assert(
            raffle.getRecentWinner().balance ==
                STARTING_USER_BALANCE + prize - entranceFee
        );
    }
}
