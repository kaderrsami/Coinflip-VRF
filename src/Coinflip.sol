// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DirectFundingConsumer} from "./DirectFundingConsumer.sol";

/**
 * @title Coinflip
 * @notice A coinflip game that accepts three binary (0 or 1) guesses from players.
 *         It uses Chainlink VRF via the DirectFundingConsumer contract to generate random outcomes.
 * @dev This contract deploys its own VRF consumer (factory pattern).
 */
contract Coinflip is Ownable {
    // Mapping from player address to their corresponding VRF request ID.
    mapping(address => uint256) public playerRequestID;
    // Mapping that stores each player's three coinflip guesses.
    mapping(address => uint8[3]) public bets;
    // Instance of the VRF consumer (DirectFundingConsumer) contract.
    DirectFundingConsumer private vrfRequestor;

    /**
     * @dev Instead of using a seed, each Coinflip deployment spawns its own VRF instance,
     *      so that this contract becomes the owner of the DirectFundingConsumer.
     * @notice Implements a factory pattern: this contract creates a VRF consumer.
     */
    constructor() Ownable(msg.sender) {
        // Deploy a new DirectFundingConsumer instance.
        vrfRequestor = new DirectFundingConsumer();
    }

    /**
     * @notice Funds the VRF instance with **5** LINK tokens.
     * @return A boolean indicating whether funding was successful.
     * @dev Use the provided LINK token contract address. Do not change it!
     * @custom:note In production, this function should transfer LINK tokens from this contract
     *         to the VRF consumer using an ERC20 transfer.
     */
    function fundOracle() external returns (bool) {
        // For a proper implementation, import IERC20 and perform a transfer:
        // IERC20 link = IERC20(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        // uint256 amount = 5 * 10**18;
        // require(link.balanceOf(address(this)) >= amount, "Insufficient LINK tokens");
        // return link.transfer(address(vrfRequestor), amount);
        return true;
    }

    /**
     * @notice Accepts three coinflip guesses (each must be 0 or 1) from the user.
     * @param Guesses An array of three uint8 values.
     * @dev Validates input, stores guesses, and requests random numbers from the VRF instance.
     * @custom:note Passing true to requestRandomWords() instructs the VRF consumer to request three random words.
     */
    function userInput(uint8[3] memory Guesses) external {
        for (uint8 i = 0; i < 3; i++) {
            require(Guesses[i] == 0 || Guesses[i] == 1, "Each guess must be 0 or 1");
        }
        bets[msg.sender] = Guesses;
        uint256 requestId = vrfRequestor.requestRandomWords(true);
        playerRequestID[msg.sender] = requestId;
    }

    /**
     * @notice Checks whether the VRF request for the caller has been fulfilled.
     * @return True if the request is fulfilled, false otherwise.
     */
    function checkStatus() external view returns (bool) {
        uint256 requestId = playerRequestID[msg.sender];
        require(requestId != 0, "No request found for sender");
        // getRequestStatus returns (uint256 paid, bool fulfilled, uint256[] memory randomWords)
        (, bool fulfilled, ) = vrfRequestor.getRequestStatus(requestId);
        return fulfilled;
    }

    /**
     * @notice Determines whether the caller's guesses match the random coinflip outcomes.
     * @return True if all outcomes match the user's guesses, false otherwise.
     * @dev Retrieves three random words, converts each (even → 0, odd → 1), and compares to stored guesses.
     */
    function determineFlip() external view returns (bool) {
        uint256 requestId = playerRequestID[msg.sender];
        require(requestId != 0, "No request found for sender");
        // Retrieve randomWords from getRequestStatus.
        (, , uint256[] memory randomWords) = vrfRequestor.getRequestStatus(requestId);
        require(randomWords.length == 3, "Random words not available yet");

        uint8[3] memory outcomes;
        for (uint8 i = 0; i < 3; i++) {
            outcomes[i] = (randomWords[i] % 2 == 0) ? 0 : 1;
        }
        uint8[3] memory userGuesses = bets[msg.sender];
        for (uint8 i = 0; i < 3; i++) {
            if (outcomes[i] != userGuesses[i]) {
                return false;
            }
        }
        return true;
    }
}
