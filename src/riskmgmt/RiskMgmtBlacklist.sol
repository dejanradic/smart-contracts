pragma solidity ^0.4.19;

import "./RiskMgmtInterface.sol";

/// @title Risk Management Contract
/// @dev isMakePermitted and isTakePermitted can be extended to define custom risk management logic using order and reference prices
/// @author Melonport AG <team@melonport.com>
contract RiskMgmtBlacklist is RiskMgmtInterface {

    mapping (address => bool) public blacklist;
    address public owner;
    
    function RiskMgmtBlacklist() public {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    function blacklist(address addr) public onlyOwner {
        require(addr != address(0));
        blacklist[addr] = true;
    }
    
    function unblacklist(address addr) public onlyOwner {
        require(addr != address(0));
        blacklist[addr] = false;
    }

    /// @notice Checks if the makeOrder price is reasonable and not manipulative
    /// @param orderPrice Price of Order
    /// @param referencePrice Reference price obtained through PriceFeed contract
    /// @param sellAsset Asset (as registered in Asset registrar) to be sold
    /// @param buyAsset Asset (as registered in Asset registrar) to be bought
    /// @param sellQuantity Quantity of sellAsset to be sold
    /// @param buyQuantity Quantity of buyAsset to be bought
    /// @return If makeOrder is permitted
    function isMakePermitted (
        uint orderPrice,
        uint referencePrice,
        address sellAsset,
        address buyAsset,
        uint sellQuantity,
        uint buyQuantity
    )
        view
        returns (bool)
    {
        return blacklist[buyAsset];
    }

    /// @notice Checks if the makeOrder price is reasonable and not manipulative
    /// @param orderPrice Price of Order
    /// @param referencePrice Reference price obtained through PriceFeed contract
    /// @param sellAsset Asset (as registered in Asset registrar) to be sold
    /// @param buyAsset Asset (as registered in Asset registrar) to be bought
    /// @param sellQuantity Quantity of sellAsset to be sold
    /// @param buyQuantity Quantity of buyAsset to be bought
    /// @return If takeOrder is permitted
    function isTakePermitted (
        uint orderPrice,
        uint referencePrice,
        address sellAsset,
        address buyAsset,
        uint sellQuantity,
        uint buyQuantity
    )
        view
        returns (bool)
    {
        return blacklist[buyAsset];
    }
}


