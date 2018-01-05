pragma solidity ^0.4.19;

import "../dependencies/DBC.sol";
import "../dependencies/ERC223Interface.sol";
import "./ERC223EscrowInterface.sol";

/// @title  ERC223 Temporary Single Asset Escrow Contract
/// @author Melonport AG <team@melonport.com>
/// @notice Temporarily hold tokens of a single asset being invested by tokenFallback method
/// @dev    Tokens sent here are retrievable by the escrowing account (Fund in our case)
contract ERC223Escrow is DBC, ERC223EscrowInterface {

    mapping (address => address) investorToEscrower;  // map from investor to Fund controlling the escrow
    mapping (address => uint) holdings;  // map from tokenSender to amount

    // PUBLIC METHODS

    /// @notice Puts assets in escrow, redeemable by the escrowing account
    /// @dev    Investors can only escrow one amount at a time now (remove limitation later)
    /// @param _from Address the tokens are being sent from (Fund in our case)
    /// @param _value Amount of token sent to this contract
    /// @param _data Data sent along with the transaction (should be the address of the investor)
    function tokenFallback(address _from, uint _value, bytes _data) {
        address investor = bytesToAddress(_data);
        address escrower = investorToEscrower[investor];
        require(escrower == 0x0); // investor has nothing in escrow
        holdings[investor] = _value;
    }

    /// @notice Retrieves the entire escrowed amount for a given investor
    /// @notice Callable only by the escrower, and transfers to escrower
    /// @param  ofInvestor Address of the investor requesting a subscription
    function retrieve(address ofInvestor, address ofToken) {
        address escrower = investorToEscrower[ofInvestor];
        require(msg.sender == escrower);
        uint escrowedAmount = holdings[ofInvestor];
        delete holdings[ofInvestor];
        delete investorToEscrower[ofInvestor];
        require(ERC223Interface(ofToken).transfer(escrower, escrowedAmount));
    }

    function bytesToAddress(bytes b) returns (address) {
        uint result = 0;
        for (uint i = b.length-1; i+1 > 0; i--) {
            uint c = uint(b[i]);
            uint to_inc = c * ( 16 ** ((b.length - i-1) * 2));
            result += to_inc;
        }
        return address(result);
    }

    // PUBLIC VIEW METHODS

    function getEscrowerForInvestor(address ofInvestor) public view returns (address) { return investorToEscrower[ofInvestor]; }
}
