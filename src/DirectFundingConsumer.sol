// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ConfirmedOwner} from "@chainlink/contracts@1.2.0/src/v0.8/shared/access/ConfirmedOwner.sol";
import {LinkTokenInterface} from "@chainlink/contracts@1.2.0/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {VRFV2PlusWrapperConsumerBase} from "@chainlink/contracts@1.2.0/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import {VRFV2PlusClient} from "@chainlink/contracts@1.2.0/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title DirectFundingConsumer
 * @notice This contract demonstrates how to request randomness directly from the VRF v2 plus wrapper using LINK or native (ETH) payments.
 * @dev Hard-coded for the Sepolia network. Follow these steps:
 *   1) Deploy this contract to Sepolia.
 *   2) Fund it with at least 3 LINK (for the cost of random requests).
 *   3) Call requestRandomWords(enableNativePayment=false) to pay in LINK (or true to pay in ETH).
 *   4) Check Etherscan for the RequestSet and RequestFulfilled events.
 */
contract DirectFundingConsumer is VRFV2PlusWrapperConsumerBase, ConfirmedOwner {
    // --------------------------------------------------------------------------------
    // Events
    // --------------------------------------------------------------------------------
    /**
     * @dev Emitted when a randomness request is created.
     * @param requestId The unique ID for this VRF request.
     * @param numWords How many random words were requested.
     */
    event RequestSet(uint256 requestId, uint32 numWords);

    /**
     * @dev Emitted when the randomness request is fulfilled.
     * @param requestId The same ID that was returned during the request.
     * @param randomWords The random words returned by Chainlink VRF.
     * @param payment How much was paid (in LINK wei) for this request.
     */
    event RequestFulfilled(
        uint256 requestId,
        uint256[] randomWords,
        uint256 payment
    );

    // --------------------------------------------------------------------------------
    // Structs
    // --------------------------------------------------------------------------------
    struct RequestStatus {
        uint256 paid;        // Amount paid in LINK (wei).
        bool fulfilled;      // Whether the request has been successfully fulfilled.
        uint256[] randomWords;
    }

    // --------------------------------------------------------------------------------
    // Storage
    // --------------------------------------------------------------------------------
    mapping(uint256 => RequestStatus) public s_requests; // requestId -> requestStatus
    uint256[] public requestIds;
    uint256 public lastRequestId;

    // How much gas for the callback. Adjust as needed.
    uint32 public callbackGasLimit = 100000;
    // Number of confirmations to wait before fulfilling the request.
    uint16 public requestConfirmations = 3;
    // How many random words to request per call.
    uint32 public numWords = 2;

    /**
     * @dev Sepolia addresses for LINK Token & VRF v2 Wrapper.
     *      (Ensure these match the current Chainlink docs.)
     */
    address public linkAddress = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address public wrapperAddress = 0x195f15F2d49d693cE265b4fB0fdDbE15b1850Cc1;

    // --------------------------------------------------------------------------------
    // Constructor
    // --------------------------------------------------------------------------------
    constructor()
        ConfirmedOwner(msg.sender)
        VRFV2PlusWrapperConsumerBase(wrapperAddress)
    {}

    // --------------------------------------------------------------------------------
    // External Functions
    // --------------------------------------------------------------------------------

    /**
     * @notice Creates a request for random words from the VRF.
     * @param enableNativePayment Whether to pay VRF fees in ETH (true) or LINK (false).
     * @return requestId ID of the randomness request.
     */
    function requestRandomWords(
        bool enableNativePayment
    ) external onlyOwner returns (uint256) {
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(
            VRFV2PlusClient.ExtraArgsV1({nativePayment: enableNativePayment})
        );

        uint256 requestId;
        uint256 reqPrice;

        if (enableNativePayment) {
            (requestId, reqPrice) = requestRandomnessPayInNative(
                callbackGasLimit,
                requestConfirmations,
                numWords,
                extraArgs
            );
        } else {
            (requestId, reqPrice) = requestRandomness(
                callbackGasLimit,
                requestConfirmations,
                numWords,
                extraArgs
            );
        }

        s_requests[requestId] = RequestStatus({
            paid: reqPrice,
            randomWords: new uint256[](0),
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;

        emit RequestSet(requestId, numWords);
        return requestId;
    }

    /**
     * @notice The VRF coordinator calls this function to return the random words.
     * @dev Only the VRF coordinator can call this.
     * @param _requestId The ID of the randomness request.
     * @param _randomWords The random words generated by VRF.
     */
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].paid > 0, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;

        emit RequestFulfilled(
            _requestId,
            _randomWords,
            s_requests[_requestId].paid
        );
    }

    /**
     * @notice Retrieves the status of a randomness request.
     * @param _requestId The ID of the request.
     * @return paid Amount paid in LINK (wei).
     * @return fulfilled True if the request is fulfilled.
     * @return randomWords The random words returned by VRF.
     */
    function getRequestStatus(
        uint256 _requestId
    )
        external
        view
        returns (uint256 paid, bool fulfilled, uint256[] memory randomWords)
    {
        require(s_requests[_requestId].paid > 0, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.paid, request.fulfilled, request.randomWords);
    }

    /**
     * @notice Withdraws all LINK tokens from this contract to the owner.
     */
    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    /**
     * @notice Withdraws native ETH from the contract.
     * @param amount The amount in wei to withdraw.
     */
    function withdrawNative(uint256 amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "withdrawNative failed");
    }

    // --------------------------------------------------------------------------------
    // Fallback/Receive
    // --------------------------------------------------------------------------------
    event Received(address sender, uint256 amount);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}