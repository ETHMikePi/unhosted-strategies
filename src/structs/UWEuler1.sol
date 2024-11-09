// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LibBit} from "solady/utils/LibBit.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

//Euler
import {IEuler} from "./interfaces/euler/IEuler.sol";
import {IEToken} from "./interfaces/euler/IEToken.sol";
import {IDToken} from "./interfaces/euler/IDToken.sol";
contract UWEulerStrategy is
    IUWDeposit,
    IUWDepositBeneficiary,
    IUWWithdraw,
    IUWBorrow,
    IUWRepay,
    IUWAssetsReport,
    IUWDebtReport,
    IUWDebtHealthReport,
    UWBaseStrategy
{
    // ╭─ Immutable Properties ───────────────────────────────────────────╮

    /// @notice Wrapped Ether to use
    WrappedETH public immutable WETH;

    /// @notice Euler adress
    IEuler public immutable euler;

    /// @notice Admin for emergency
    address public immutable admin;

    // ╰─ Immutable Properties ───────────────────────────────────────────╯

    constructor(WrappedETH _weth, IEuler _euler, address _admin) {
        // Adress Wrapped Ether
        WETH = _weth;

        // Adress Euler Contract
        euler = _euler;

        // Admin 
        admin = _admin;
    }
}

receive() external payable {}

    // ╭─ External & Public Functions ────────────────────────────────────╮

    /// @notice Deposit an asset into Euler.
    /// @param position the Euler position to use.
    /// @param asset the asset to deposit.
    /// @param amount the amount of the asset to deposit.
    function deposit(
        bytes32 position,
        address asset,
        uint256 amount
    ) external payable onlySinglePosition(position) {
        _depositTo(position, asset, amount, address(this));
    }

    /// @notice Deposit an asset into Euler for a beneficiary.
    /// @param position the Euler position to use.
    /// @param asset the asset to deposit.
    /// @param amount the amount of the asset to deposit.
    /// @param beneficiary the address to perform the deposit for.
    function depositTo(
        bytes32 position,
        address asset,
        uint256 amount,
        address beneficiary
    ) external payable onlySinglePosition(position) {
        _depositTo(position, asset, amount, beneficiary);
    }

    /// @notice Withdraw an asset from Euler.
    /// @param position the Euler position to use.
    /// @param asset the asset to withdraw.
    /// @param amount the amount of the asset to withdraw.
    function withdraw(
        bytes32 position,
        address asset,
        uint256 amount
    ) external onlySinglePosition(position) {
        _withdrawTo(position, asset, amount, address(this));
    }

    /// @notice Withdraw an asset from Euler to a beneficiary.
    /// @param position the Euler position to use.
    /// @param asset the asset to withdraw.
    /// @param amount the amount of the asset to withdraw.
    /// @param beneficiary the recipient of the withdrawn assets.
    function withdrawTo(
        bytes32 position,
        address asset,
        uint256 amount,
        address beneficiary
    ) external onlySinglePosition(position) {
        _withdrawTo(position, asset, amount, beneficiary);
    }

    /// @notice Repay a debt in Euler.
    /// @param position the Euler position to use.
    /// @param asset the base asset to repay.
    /// @param amount the amount of the asset to repay.
    function repay(
        bytes32 position,
        address asset,
        uint256 amount
    ) external onlySinglePosition(position) {
        _repayTo(position, asset, amount, address(this));
    }

    /// @notice Borrow an asset from Euler.
    /// @param position the Euler position to use.
    /// @param asset the asset to borrow.
    /// @param amount the amount of the asset to borrow.
    function borrow(
        bytes32 position,
        address asset,
        uint256 amount
    ) external onlySinglePosition(position) {
        _borrowTo(position, asset, amount, address(this));
    }

    /// @notice Borrow an asset from Euler for a beneficiary.
    /// @param position the Euler position to use.
    /// @param asset the asset to borrow.
    /// @param amount the amount of the asset to borrow.
    /// @param beneficiary the recipient of the borrowed assets.
    function borrowTo(
        bytes32 position,
        address asset,
        uint256 amount,
        address beneficiary
    ) external onlySinglePosition(position) {
        _borrowTo(position, asset, amount, beneficiary);
    }

    // ╰─ External & Public Functions ────────────────────────────────────╯

    // ╭─ View Functions ─────────────────────────────────────────────────╮

/// @notice Reports the amount of assets the user has in this strategy.
/// @param position The Euler position to check.
/// @return _assets The assets of the position.
function assets(
    bytes32 position
)
    external
    view
    onlySinglePosition(position)
    returns (Asset[] memory _assets)
{
    // Get all assets in this position in Euler.
    address[] memory eulerAssets = EULER_MARKETS.getAllETokens();
    _assets = new Asset[](eulerAssets.length);
    uint256 _n;

    for (uint256 i = 0; i < eulerAssets.length; i++) {
        address eTokenAddress = eulerAssets[i];
        uint256 balance = IEulerEToken(eTokenAddress).balanceOfUnderlying(address(this));

        if (balance > 0) {
            _assets[_n++] = Asset({
                asset: eTokenAddress,
                amount: balance
            });
        }
    }

    // Resize the assets to only contain filled asset structs.
    assembly {
        mstore(_assets, _n)
    }

    return _assets;
}

/// @notice Reports the amount of debt the user has in this strategy.
/// @param position The Euler position to check.
/// @return _assets The debt assets of the position.
function debt(
    bytes32 position
)
    external
    view
    onlySinglePosition(position)
    returns (Asset[] memory _assets)
{
  //Get all assets in this position in Euler.
    address[] memory eulerDebts = EULER_MARKETS.getAllDTokens();
    _assets = new Asset[](eulerDebts.length);
    uint256 _n;

    for (uint256 i = 0; i < eulerDebts.length; i++) {
        address dTokenAddress = eulerDebts[i];
        uint256 debtBalance = IEulerDToken(dTokenAddress).balanceOf(address(this));

        if (debtBalance > 0) {
            _assets[_n++] = Asset({
                asset: dTokenAddress,
                amount: debtBalance
            });
        }
    }

    // Resize the debt asset array to include only assets with debt.
    assembly {
        mstore(_assets, _n)
    }

    return _assets;
}

/// @notice Reports the health of a position.
/// @param position The Euler position to check.
/// @return current The current debt percentage.
/// @return max The maximum debt allowed.
/// @return liquidatable The threshold at which the position risks liquidation.
function debtHealth(
    bytes32 position
)
    external
    view
    onlySinglePosition(position)
    returns (uint256, uint256, uint256)
{
    IEulerEToken eToken = IEulerEToken(eTokens[position]);
    IEulerDToken dToken = IEulerDToken(dTokens[position]);

    uint256 totalCollateral = eToken.balanceOfUnderlying(address(this));
    uint256 totalDebt = dToken.balanceOf(address(this));
    uint256 collateralFactor = EULER_MARKETS.collateralFactor(eTokens[position]);

    // % debt now
    uint256 current = totalCollateral == 0 ? 0 : (totalDebt * 1e4) / totalCollateral;

    return (
        current,
        collateralFactor,
        collateralFactor * 85 / 100 // 85% max debt liquidation
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
        super.supportsInterface(interfaceId);
}

// ╰─ View Functions ─────────────────────────────────────────────────╯
// ╭─ Internal Functions ─────────────────────────────────────────────╮

/// @notice Deposits a specific asset to the Euler protocol on behalf of the beneficiary.
/// @param _asset The asset to deposit.
/// @param _amount The amount of the asset to deposit.
/// @param _beneficiary The address that will receive the benefit of this deposit.
function _depositTo(
    address _asset,
    uint256 _amount,
    address _beneficiary
) internal {
    // Manages the native asset and normalises it.
    if (_asset == UWConstants.NATIVE_ASSET) {
        WETH.deposit{value: _amount}();
        _asset = address(WETH);
    }

    // Gets the eToken associated with the asset in Euler.

    address eTokenAddress = EULER_MARKETS.underlyingToEToken(_asset);

    // Approves the deposit of the asset.
    SafeTransferLib.safeApproveWithRetry(_asset, eTokenAddress, _amount);

    // Make the deposit at Euler.
    IEulerEToken(eTokenAddress).deposit(_beneficiary, _amount);
}

/// @notice Withdraws a specific asset from the Euler protocol to the beneficiary.
/// @param _asset The asset to withdraw.
/// @param _amount The amount of the asset to withdraw.
/// @param _beneficiary The address that will receive the withdrawn asset.
function _withdrawTo(
    address _asset,
    uint256 _amount,
    address _beneficiary
) internal {
    // If the asset is not native, make the direct withdraw.
    if (_asset != UWConstants.NATIVE_ASSET) {
        address eTokenAddress = EULER_MARKETS.underlyingToEToken(_asset);
        IEulerEToken(eTokenAddress).withdraw(_beneficiary, _amount);
        return;
    }

    // Withdraw WETH.
    address eTokenAddress = EULER_MARKETS.underlyingToEToken(address(WETH));
    IEulerEToken(eTokenAddress).withdraw(address(this), _amount);

    // Unwrap WETH.
    WETH.withdraw(_amount);

    // Send ETH to the beneficiary if it is not the same address.
    if (_beneficiary != address(this)) {
        SafeTransferLib.safeTransferETH(_beneficiary, _amount);
    }
}

/// @notice Repays a specific amount of debt for a given asset on behalf of the beneficiary.
/// @param _asset The asset to repay.
/// @param _amount The amount of the asset to repay.
/// @param _beneficiary The address that receives the benefit of this repay action.
function _repayTo(
    address _asset,
    uint256 _amount,
    address _beneficiary
) internal {
    // Obtain the dToken associated with the asset in Euler.
    address dTokenAddress = EULER_MARKETS.underlyingToDToken(_asset);

    // Approves the payment of the asset debt.
    SafeTransferLib.safeApproveWithRetry(_asset, dTokenAddress, _amount);

    // Make the debt payment in Euler.
    IEulerDToken(dTokenAddress).repay(_beneficiary, _amount);
}

/// @notice Borrows a specific amount of a given asset from the Euler protocol on behalf of the beneficiary.
/// @param _asset The asset to borrow.
/// @param _amount The amount of the asset to borrow.
/// @param _beneficiary The address that will receive the borrowed asset.
function _borrowTo(
    address _asset,
    uint256 _amount,
    address _beneficiary
) internal {
    // Obtain the dToken associated with the asset in Euler.
    address dTokenAddress = EULER_MARKETS.underlyingToDToken(_asset);

    // If the asset is ERC20, apply for the loan directly.
    if (_asset != UWConstants.NATIVE_ASSET) {
        IEulerDToken(dTokenAddress).borrow(_beneficiary, _amount);
        return;
    }

    // Borrow WETH if the asset is native.
    IEulerDToken(dTokenAddress).borrow(address(this), _amount);

    // Unwrap WETH.
    WETH.withdraw(_amount);

    // Send ETH to the beneficiary if it is not the same address.
    if (_beneficiary != address(this)) {
        SafeTransferLib.safeTransferETH(_beneficiary, _amount);
    }
}
// ╰─ Internal Functions ─────────────────────────────────────────────╯