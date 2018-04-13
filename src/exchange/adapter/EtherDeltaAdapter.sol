pragma solidity ^0.4.20;

import "../thirdparty/EtherDelta.sol";
import "../../Fund.sol";
import "../../dependencies/DBC.sol";
import "ds-math/math.sol";

/// @title EtherDeltaAdapter Contract
/// @author Melonport AG <team@melonport.com>
/// @notice Adapter between Melon and EtherDelta

contract EtherDeltaAdapter is DSMath, DBC {

    event OrderUpdated(address exchange, uint orderId);

    //  METHODS

    // Responsibilities of makeOrder are:
    // - check price recent
    // - check risk management passes
    // - approve funds to be traded (if necessary)
    // - make order on the exchange
    // - check order was made (if possible)
    // - place asset in ownedAssets if not already tracked
    /// @notice Makes an order on the selected exchange
    /// @dev get/give is from maker's perspective
    /// @dev These orders are not expected to settle immediately
    /// @param orderAddresses [2] Asset to be sold (giveAsset)
    /// @param orderAddresses [3] Asset to be bought (getAsset)
    /// @param orderAddresses [4] Expiration timestamp
    /// @param orderAddresses [5] Nonce
    /// @param orderValues [0] Quantity of giveAsset to be sold
    /// @param orderValues [1] Quantity of getAsset to be bought
    function makeOrder(
        address targetExchange,
        address[5] orderAddresses,
        uint[6] orderValues,
        bytes32 identifier,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) {
        require(Fund(this).owner() == msg.sender);
        require(!Fund(this).isShutDown());

        //Using EtherDelta token type
        StandardToken giveAsset = StandardToken(orderAddresses[2]);
        StandardToken getAsset = StandardToken(orderAddresses[3]);

        uint giveQuantity = orderValues[0];
        uint getQuantity = orderValues[1];

        require(makeOrderPermitted(giveQuantity, giveAsset, getQuantity, getAsset));
        require(giveAsset.approve(targetExchange, giveQuantity));

        //Place the order on EtherDelta on-chain orderbook
        EtherDelta(targetExchange).order(getAsset, getQuantity, giveAsset, giveQuantity, orderValues[4], orderValues[5]);

        //independently derive the same order hash locally
        bytes32 orderHash = sha256(targetExchange, getAsset, getQuantity, giveAsset, giveQuantity, orderValues[4], orderValues[5]);

        //Check that the order indeed exists on EtherDelta's on-chain order book
        require(EtherDelta(targetExchange).orders(msg.sender, orderHash));  //defines success in EtherDelta

        require(
            Fund(this).isInAssetList(getAsset) ||
            Fund(this).getOwnedAssetsLength() < Fund(this).MAX_FUND_ASSETS()
        );

        Fund(this).addOpenMakeOrder(targetExchange, giveAsset, uint(orderHash));

        Fund(this).addAssetToOwnedAssets(getAsset);

        emit OrderUpdated(targetExchange, uint(orderHash));
    }

    // Responsibilities of takeOrder are:
    // - check not buying own fund tokens
    // - check price exists for asset pair
    // - check price is recent
    // - check price passes risk management
    // - approve funds to be traded (if necessary)
    // - take order from the exchange
    // - check order was taken (if possible)
    // - place asset in ownedAssets if not already tracked
    /// @notice Takes an active order on the selected exchange
    /// @dev These orders are expected to settle immediately
    /// @dev Get/give is from taker's perspective
    /// @param identifier Active order id
    /// @param orderValues [1] Buy quantity of what others are selling on selected Exchange
    function takeOrder(
        address targetExchange,
        address[5] orderAddresses,
        uint[6] orderValues,
        bytes32 identifier,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) {
        require(Fund(this).owner() == msg.sender);
        require(!Fund(this).isShutDown());
        var (pricefeed,,) = Fund(this).modules();

        //Using EtherDelta's token type
        StandardToken giveAsset = StandardToken(orderAddresses[2]);
        StandardToken getAsset = StandardToken(orderAddresses[3]);

        uint giveQuantity = orderValues[0];
        uint getQuantity = orderValues[1];

        require(giveAsset != address(this) && getAsset != address(this));
        require(address(getAsset) != address(giveAsset));
        require(pricefeed.existsPriceOnAssetPair(giveAsset, getAsset));

        require(giveAsset.approve(targetExchange, giveQuantity));
        require(takeOrderPermitted(giveQuantity, giveAsset, getQuantity, getAsset));
        require(EtherDelta(targetExchange).testTrade(getAsset, getQuantity, giveAsset, giveQuantity, orderValues[4], orderValues[5]), address(this)));
        EtherDelta(targetExchange).trade(getAsset, getQuantity, giveAsset, giveQuantity, orderValues[4], orderValues[5]);
        require(
            Fund(this).isInAssetList(getAsset) ||
            Fund(this).getOwnedAssetsLength() < Fund(this).MAX_FUND_ASSETS()
        );

        Fund(this).addAssetToOwnedAssets(getAsset);
        emit OrderUpdated(targetExchange, uint(identifier));
    }

    // responsibilities of cancelOrder are:
    // - check sender is this contract or owner, or that order expired
    // - remove order from tracking array
    // - cancel order on exchange
    /// @notice Cancels orders that were not expected to settle immediately
    /// @param targetExchange Address of the exchange
    /// @param orderAddresses [2] Asset for which we want to cancel an order
    /// @param identifier Order ID on the exchange
    function cancelOrder(
        address targetExchange,
        address[5] orderAddresses,
        uint[6] orderValues,
        bytes32 identifier,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        pre_cond(Fund(this).owner() == msg.sender ||
                 Fund(this).isShutDown()          ||
                 Fund(this).orderExpired(targetExchange, orderAddresses[2])
        )
    {
        require(uint(identifier) != 0);
        Fund(this).removeOpenMakeOrder(targetExchange, orderAddresses[2]);

        EtherDelta(targetExchange).cancelOrder(getAsset, getQuantity, giveAsset, giveQuantity, orderValues[4], orderValues[5], v, r, s);

        emit OrderUpdated(targetExchange, uint(identifier));
    }

    // TODO: Make deposit(), depositToken(), withdraw(), withdrawToken() for EtherDelta; may require small fund.sol changes

    // VIEW METHODS
    /// @dev needed to avoid stack too deep error
    // TODO: Make these general adapter functions to be inherited
    //function makeOrderPermitted();
    //function takeOrderPermitted();

}
