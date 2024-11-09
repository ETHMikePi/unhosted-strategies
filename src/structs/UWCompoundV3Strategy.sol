// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {CometHelpers} from "./helpers/CometHelpers.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LibBit} from "solady/utils/LibBit.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IComet} from "./interfaces/external/compound/IComet.sol";
import {WrappedETH} from "./interfaces/external/common/WrappedETH.sol";

import {IUWDeposit} from "./interfaces/IUWDeposit.sol";
import {IUWDepositBeneficiary} from "./interfaces/IUWDepositBeneficiary.sol";
import {IUWWithdraw} from "./interfaces/IUWWithdraw.sol";
import {IUWBorrow} from "./interfaces/IUWBorrow.sol";
import {IUWRepay} from "./interfaces/IUWRepay.sol";
import {IUWDebtReport} from "./interfaces/IUWDebtReport.sol";
import {IUWDebtHealthReport} from "./interfaces/IUWDebtHealthReport.sol";
import {IUWAssetsReport, Asset} from "./interfaces/IUWAssetsReport.sol";
import {UWBaseStrategy} from "./abstract/UWBaseStrategy.sol";
import {UWConstants} from "./libraries/UWConstants.sol";
import {IUWErrors} from "./interfaces/IUWErrors.sol";

contract UWCompoundV3Strategy is
    IUWDeposit,
    IUWDepositBeneficiary,
    IUWWithdraw,
    IUWBorrow,
    IUWRepay,
    IUWAssetsReport,
    IUWDebtReport,
    IUWDebtHealthReport,
    UWBaseStrategy,
    CometHelpers
{
    // ╭─ Immutable Properties ───────────────────────────────────────────╮
    /// @notice the implementation of wrapped ether to use.
    WrappedETH internal immutable WETH;
    // ╰─ Immutable Properties ───────────────────────────────────────────╯

    constructor(WrappedETH _weth) {
        WETH = _weth;
    }

    receive() external payable {}

    // ╭─ External & Public Functions ────────────────────────────────────╮
    /// @notice Deposit an asset into a compound comet.
    /// @param position the comet to use.
    /// @param asset the asset to deposit.
    /// @param amount the amount of the asset to deposit.
    function deposit(
        bytes32 position,
        address asset,
        uint256 amount
    ) external payable override {
        IComet _comet = IComet(address(uint160(uint256(position))));
        _depositTo(_comet, asset, amount, address(this));
    }

    /// @notice Deposit an asset into a compound comet.
    /// @param position the comet to use.
    /// @param asset the asset to deposit.
    /// @param amount the amount of the asset to deposit.
    /// @param beneficiary the address to perform the deposit for.
    function depositTo(
        bytes32 position,
        address asset,
        uint256 amount,
        address beneficiary
    ) external payable {
        IComet _comet = IComet(address(uint160(uint256(position))));
        _depositTo(_comet, asset, amount, beneficiary);
    }

    /// @notice Withdraw an asset from a compound comet.
    /// @param position the comet to use.
    /// @param asset the asset to withdraw.
    /// @param amount the amount of the asset to withdraw.
    function withdraw(
        bytes32 position,
        address asset,
        uint256 amount
    ) external override {
        IComet _comet = IComet(address(uint160(uint256(position))));
        _withdrawTo(_comet, asset, amount, address(this));
    }

    /// @notice Withdraw an asset from a compound comet.
    /// @param position the comet to use.
    /// @param asset the asset to withdraw.
    /// @param amount the amount of the asset to withdraw.
    /// @param beneficiary the recipient of the withdrawn assets.
    function withdrawTo(
        bytes32 position,
        address asset,
        uint256 amount,
        address beneficiary
    ) external override {
        IComet _comet = IComet(address(uint160(uint256(position))));
        _withdrawTo(_comet, asset, amount, beneficiary);
    }

    /// @notice Repay the base token for a compound comet.
    /// @param position the comet to use.
    /// @param asset the base asset to repay.
    /// @param amount the amount of the asset to repay.
    function repay(bytes32 position, address asset, uint256 amount) external {
        IComet _comet = IComet(address(uint160(uint256(position))));

        // We check that this asset is the base asset, which means this is likely a repayment.
        if (
            _comet.baseToken() !=
            (asset == UWConstants.NATIVE_ASSET ? address(WETH) : asset)
        ) {
            revert IUWErrors.UNSUPPORTED_ASSET(asset);
        }

        // Check that the user is able to repay.
        if (_balanceOf(asset, address(this)) < amount) {
            uint256 _balance = _balanceOf(asset, address(this));
            uint256 _borrowAmount = _comet.borrowBalanceOf(address(this));
            revert IUWErrors.ASSET_AMOUNT_OUT_OF_BOUNDS(
                asset,
                0,
                _borrowAmount < _balance ? _borrowAmount : _balance,
                amount
            );
        }

        // Compound handles repay the same as deposit, but we don't expose this behavior to UIs.
        _depositTo(_comet, asset, amount, address(this));
    }

    /// @notice Borrow an asset from a compound comet.
    /// @param position the comet to use.
    /// @param asset the base asset to borrow.
    /// @param amount the amount of the asset to borrow.
    function borrow(
        bytes32 position,
        address asset,
        uint256 amount
    ) external override {
        borrowTo(position, asset, amount, address(this));
    }

    /// @notice Borrow an asset from a compound comet.
    /// @param position the comet to use.
    /// @param asset the base asset to borrow.
    /// @param amount the amount of the asset to borrow.
    /// @param beneficiary the recipient of the borrowed assets.
    function borrowTo(
        bytes32 position,
        address asset,
        uint256 amount,
        address beneficiary
    ) public override {
        IComet _comet = IComet(address(uint160(uint256(position))));

        // We check that the comet supports the asset the user is trying to borrow.
        if (
            _comet.baseToken() !=
            (asset == UWConstants.NATIVE_ASSET ? address(WETH) : asset)
        ) {
            revert IUWErrors.UNSUPPORTED_ASSET(asset);
        }

        // Check that the borrow is above the min borrow.
        if (_comet.baseBorrowMin() > amount) {
            revert IUWErrors.ASSET_AMOUNT_OUT_OF_BOUNDS(
                asset,
                _comet.baseBorrowMin(),
                type(uint256).max,
                amount
            );
        }

        _withdrawTo(_comet, asset, amount, beneficiary);
    }
    // ╰─ External & Public Functions ────────────────────────────────────╯

    // ╭─ View Functions ─────────────────────────────────────────────────╮
    /// @notice Reports on the amount of the users assets that are in this strategy.
    /// @param position the position to check.
    /// @return _assets of the position.
    function assets(
        bytes32 position
    ) external view returns (Asset[] memory _assets) {
        IComet _comet = IComet(address(uint160(uint256(position))));
        IComet.UserBasic memory _ub = _comet.userBasic(address(this));

        // Count the number of assets that we have in this comet.
        uint256 _assetsIn = _ub.assetsIn;
        uint8 _na = uint8(LibBit.popCount(_assetsIn));
        // Size the array accordingly.
        _assets = new Asset[](_na);

        for (uint8 _i; _i < _na; _i++) {
            // Find the index of an asset we have in this comet.
            uint8 _assetIndex = uint8(LibBit.ffs(_assetsIn));
            // Flip it to zero so we don't check the same asset multiple times.
            _assetsIn = _assetsIn & ~(1 << _assetIndex);
            // Get the asset information and balance and add it to our array of assets.
            IComet.AssetInfo memory _asset = _comet.getAssetInfo(_assetIndex);
            _assets[_i] = Asset({
                asset: _asset.asset,
                amount: _comet.collateralBalanceOf(address(this), _asset.asset)
            });
        }
    }

    /// @notice Reports on the amount debt the user has to this strategy.
    /// @param position the position to check.
    /// @return _assets assets of the position.
    function debt(
        bytes32 position
    ) external view returns (Asset[] memory _assets) {
        IComet _comet = IComet(address(uint160(uint256(position))));

        // In compound the only token that can be debt is the base asset.
        uint256 _borrowBalance = _comet.borrowBalanceOf(address(this));

        // Only add the base token if there is debt.
        if (_borrowBalance > 0) {
            _assets = new Asset[](1);
            _assets[0] = Asset({
                asset: _comet.baseToken(),
                amount: _borrowBalance
            });
        }
    }

    /// @notice Reports the health of a position.
    /// @param position the position to check.
    /// @return current an amount that represents the current debt.
    /// @return max an amount at (or above) its no longer possible to take out additional debt against this position.
    /// @return liquidatable an amount at which the position is at risk of being liquidated.
    function debtHealth(
        bytes32 position
    ) external view returns (uint256, uint256, uint256) {
        IComet _comet = IComet(address(uint160(uint256(position))));
        IComet.UserBasic memory _ub = _comet.userBasic(address(this));
        IComet.TotalsBasic memory _tb = _comet.totalsBasic();

        int256 liquidity = (presentValue(
            _ub.principal,
            _tb.baseSupplyIndex,
            _tb.baseBorrowIndex
        ) * signed256(_comet.getPrice(_comet.baseTokenPriceFeed()))) /
            int256(uint256(_comet.baseScale()));

        int256 borrowLiquidity = liquidity;
        int256 zeroPoint = liquidity * -1;

        uint8 _na = _comet.numAssets();
        for (uint8 _i; _i < _na; _i++) {
            // TODO: add `isInAsset` optimization.
            IComet.AssetInfo memory _asset = _comet.getAssetInfo(_i);

            uint256 newAmount = (_comet.collateralBalanceOf(
                address(this),
                _asset.asset
            ) * _comet.getPrice(_asset.priceFeed)) / _asset.scale;

            liquidity += signed256(
                mulFactor(newAmount, _asset.liquidateCollateralFactor)
            );
            borrowLiquidity += signed256(
                mulFactor(newAmount, _asset.borrowCollateralFactor)
            );
        }

        return (
            unsigned256(zeroPoint),
            unsigned256(zeroPoint + borrowLiquidity),
            unsigned256(zeroPoint + liquidity)
        );
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IUWDeposit).interfaceId ||
            interfaceId == type(IUWDepositBeneficiary).interfaceId ||
            interfaceId == type(IUWWithdraw).interfaceId ||
            interfaceId == type(IUWBorrow).interfaceId ||
            interfaceId == type(IUWRepay).interfaceId ||
            interfaceId == type(IUWAssetsReport).interfaceId ||
            interfaceId == type(IUWDebtReport).interfaceId ||
            interfaceId == type(IUWDebtHealthReport).interfaceId ||
            UWBaseStrategy.supportsInterface(interfaceId);
    }
    // ╰─ View Functions ─────────────────────────────────────────────────╯

    // ╭─ Internal Functions ─────────────────────────────────────────────╮
    function _depositTo(
        IComet _comet,
        address _asset,
        uint256 _amount,
        address _beneficiary
    ) internal {
        // Handle the native asset and normalize it.
        if (_asset == UWConstants.NATIVE_ASSET) {
            // Wrap ETH
            WETH.deposit{value: _amount}();
            // Continue as normal but set the token to be used to WETH.
            _asset = address(WETH);
        }

        // Approve the asset to be deposited.
        // TODO: Handle the max uint256 scenario.
        SafeTransferLib.safeApproveWithRetry(_asset, address(_comet), _amount);

        // Perform the deposit.
        _comet.supplyTo(_beneficiary, _asset, _amount);
    }

    function _withdrawTo(
        IComet _comet,
        address _asset,
        uint256 _amount,
        address _beneficiary
    ) internal {
        // If the asset we are borrowing is an ERC20 we can exit early.
        if (_asset != UWConstants.NATIVE_ASSET)
            return _comet.withdrawTo(_beneficiary, _asset, _amount);

        // Borrow WETH.
        _comet.withdrawTo(address(this), address(WETH), _amount);

        // Unwrap the WETH.
        WETH.withdraw(_amount);

        // Send it to the beneficiary if we are not the beneficiary.
        if (_beneficiary != address(this))
            SafeTransferLib.safeTransferETH(_beneficiary, _amount);
    }
    // ╰─ Internal Functions ─────────────────────────────────────────────╯
}