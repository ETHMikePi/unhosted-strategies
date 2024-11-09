// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUWDeposit} from "./interfaces/IUWDeposit.sol";
import {IUWDebtReport} from "./interfaces/IUWDebtReport.sol";
import {IUWAssetsReport, Asset} from "./interfaces/IUWAssetsReport.sol";
import {UWBaseStrategy} from "./abstract/UWBaseStrategy.sol";
import {UWConstants} from "./libraries/UWConstants.sol";
import {IUWErrors} from "./interfaces/IUWErrors.sol";

interface ILido is IERC20 {
    function submit(address _referral) external payable returns (uint256);
    function getPooledEthByShares(
        uint256 _sharesAmount
    ) external view returns (uint256);
}

interface IwstETH is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    function getStETHByWstETH(
        uint256 _wstETHAmount
    ) external view returns (uint256);
}

contract UWLidoStrategy is
    IUWAssetsReport,
    IUWDebtReport,
    IUWDeposit,
    UWBaseStrategy
{
    /// @notice the LIDO proxy
    ILido internal immutable LIDO;

    /// @notice the wrapped stETH token.
    IwstETH internal immutable WSTETH;

    /// @notice the refferal that gets used when submitting ether to LIDO.
    address internal immutable referral;

    constructor(ILido _lido, IwstETH _wstETH, address _referral) {
        LIDO = _lido;
        WSTETH = _wstETH;
        referral = _referral;
    }

    /// @notice Deposit Ether into LIDO.
    /// @param position choose which asset to receive stETH or wstETH.
    /// @param asset UWConstants.NATIVE_ASSET is the only asset supported.
    /// @param amount the amount of ether to deposit.
    function deposit(
        bytes32 position,
        address asset,
        uint256 amount
    ) external payable override {
        // Only native Ether is supported.
        if (asset != UWConstants.NATIVE_ASSET)
            revert IUWErrors.UNSUPPORTED_ASSET(asset);
        // Check that the position is one of the two available options.
        if (
            address(uint160(uint256(position))) != address(LIDO) &&
            address(uint160(uint256(position))) != address(WSTETH)
        ) {
            revert IUWErrors.INVALID_POSITION(position);
        }

        // Check that the amount to deposit is within the allowed bound of Lido and that the user has enough balance
        if (
            amount < 100 wei ||
            amount > address(this).balance ||
            amount > 1000 ether
        ) {
            revert IUWErrors.ASSET_AMOUNT_OUT_OF_BOUNDS(
                asset,
                100 wei,
                address(this).balance < 1000 ether
                    ? address(this).balance
                    : 1000 ether,
                amount
            );
        }

        // Perform the ETH -> stETH deposit
        uint256 _receivedAmount = LIDO.submit{value: amount}(referral);

        // If the position was for wstETH, then we perform the stETH -> wstETH
        if (address(uint160(uint256(position))) == address(WSTETH)) {
            LIDO.approve(address(WSTETH), _receivedAmount);
            WSTETH.wrap(_receivedAmount);
        }
    }

    /// @notice Reports on the amount of the users assets that are in this strategy.
    /// @param position the position to check.
    /// @return assets of the position.
    function assets(bytes32 position) external view returns (Asset[] memory) {
        // Tracks the amount of Ether that is the backing asset.
        uint256 _amount;

        // If this is the stETH position
        if (address(uint160(uint256(position))) == address(LIDO)) {
            _amount = LIDO.balanceOf(address(this));
            // If this is the wstETH position.
        } else if (address(uint160(uint256(position))) == address(WSTETH)) {
            _amount = LIDO.getPooledEthByShares(
                WSTETH.getStETHByWstETH(WSTETH.balanceOf(address(this)))
            );
        } else {
            revert IUWErrors.INVALID_POSITION(position);
        }

        Asset[] memory _assets = new Asset[](1);
        _assets[0] = Asset({asset: UWConstants.NATIVE_ASSET, amount: _amount});
        return _assets;
    }

    /// @notice Reports on the debt the user has to this strategy (and position).
    /// @param position the position to check.
    /// @return debt assets of the position.
    function debt(bytes32 position) external view returns (Asset[] memory) {
        // Tracks the position.
        address _position = address(uint160(uint256(position)));

        // Check that the position is one of the two available options.
        if (_position != address(LIDO) && _position != address(WSTETH)) {
            revert IUWErrors.INVALID_POSITION(position);
        }

        Asset[] memory _assets = new Asset[](1);
        _assets[0] = Asset({
            asset: _position,
            amount: IERC20(_position).balanceOf(address(this))
        });
        return _assets;
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IUWDeposit).interfaceId ||
            interfaceId == type(IUWAssetsReport).interfaceId ||
            interfaceId == type(IUWDebtReport).interfaceId ||
            UWBaseStrategy.supportsInterface(interfaceId);
    }
}
