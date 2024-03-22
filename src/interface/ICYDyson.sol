// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ICYDyson {
    // Error declarations can be included if they will be used externally.
    error VaultNotWhitelisted();

    // Function signatures
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
    function addVault(address _vault) external;
    function removeVault(address _vault) external;

    // Admin role identifier function for external access
    function ADMIN_ROLE() external view returns (bytes32);
}
