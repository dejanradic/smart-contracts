pragma solidity ^0.4.19;

import '../ExchangeInterface.sol';
import '../thirdparty/CentralizedExchange.sol';
import '../../assets/Asset.sol';

contract CentralizedAdapter is ExchangeInterface {

  event OrderUpdated(uint id);

  // VIEW METHODS

  function getLastOrderId(address onExchange)
      constant
      returns (uint)
  {
      return CentralizedExchange(onExchange).getLastOrderId();
  }
  function isActive(address onExchange, uint id)
      constant
      returns (bool)
  {
      return CentralizedExchange(onExchange).isActive(id);
  }
  function getOwner(address onExchange, uint id)
      constant
      returns (address)
  {
      return CentralizedExchange(onExchange).getOwner(id);
  }
  function getOrder(address onExchange, uint id)
      constant
      returns (address, address, uint, uint)
  {
      var (
          sellQuantity,
          sellAsset,
          buyQuantity,
          buyAsset
      ) = CentralizedExchange(onExchange).getOrder(id);
      return (
          sellAsset,
          buyAsset,
          sellQuantity,
          buyQuantity
      );
  }
  function getTimestamp(address onExchange, uint id)
      constant
      returns (uint)
  {
      var (, , , , , , timestamp) = CentralizedExchange(onExchange).orders(id);
      return timestamp;
  }

  // NON-CONSTANT METHODS

  /// @notice Makes an order on the given exchange
  /// @dev Only use this in context of a delegatecall, as spending of sellAsset need to be approved first
  /// @param onExchange Address of the exchange
  /// @param sellAsset Asset (as registered in Asset registrar) to be sold
  /// @param buyAsset Asset (as registered in Asset registrar) to be bought
  /// @param sellQuantity Quantity of sellAsset to be sold
  /// @param buyQuantity Quantity of buyAsset to be bought
  /// @return Order id
  function makeOrder(
      address onExchange,
      address sellAsset,
      address buyAsset,
      uint sellQuantity,
      uint buyQuantity
  )
      external returns (uint id)
  {
      id = CentralizedExchange(onExchange).deposit(
          Asset(sellAsset),
          Asset(buyAsset),
          sellQuantity,
          buyQuantity
      );
      OrderUpdated(id);
  }

  /// @notice Takes an order on the given exchange
  /// @dev For this subset of adapter no immediate settlement can be expected
  /// @param onExchange Address of the exchange
  /// @param id Order id
  /// @param quantity Quantity of order to be executed (For partial taking)
  /// @return Whether the takeOrder is successfully executed
  function takeOrder(
      address onExchange,
      uint id,
      uint quantity
  )
      external returns (bool success)
  {
      throw;
  }

  /// @notice Cancels an order on the given exchange
  /// @dev Only use this in context of a delegatecall, as spending of sellAsset need to be approved first
  /// @param onExchange Address of the exchange
  /// @param id Order id
  /// @return Whether the order is successfully cancelled
  function cancelOrder(
      address onExchange,
      uint id
  )
      external returns (bool success)
  {
      success = CentralizedExchange(onExchange).withdraw(id);
      OrderUpdated(id);
  }
}
