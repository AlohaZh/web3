// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "@openzeppelin/contracts@5.4.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@5.4.0/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@5.4.0/access/AccessControl.sol";
import "@openzeppelin/contracts@5.4.0/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts@5.4.0/utils/Base64.sol";
import "@openzeppelin/contracts@5.4.0/utils/Strings.sol";

/// @title HKU Drone Club points, CPT (18 decimals).
contract ClubToken is ERC20, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    mapping(address => bool) public withdrawn;

    event PointsDistributed(address indexed admin, address indexed recipient, uint256 amount);
    event ClubWithdrawal(address indexed member, uint256 amountBurned);
    event MemberReadmitted(address indexed member);

    constructor() ERC20("Club Points", "CPT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _mint(msg.sender, 1000 * 10 ** decimals());
    }

    /// @notice Only a club administrator can issue additional points.
    function mint(address recipient, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(!withdrawn[recipient], "Member has withdrawn");
        require(amount > 0, "Amount must be positive");
        _mint(recipient, amount);
    }

    /// @notice Distribute the calling administrator's existing points (no new supply).
    function distribute(address recipient, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(!withdrawn[recipient], "Member has withdrawn");
        require(amount > 0, "Amount must be positive");
        _transfer(msg.sender, recipient, amount);
        emit PointsDistributed(msg.sender, recipient, amount);
    }

    /// @notice Burn approved points. The NFT contract spends only its user's allowance.
    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /// @notice Custom function: leave voluntarily and destroy ALL current points.
    /// @dev Does not destroy already owned NFTs or revoke administrator roles.
    function withdrawFromClub() external {
        require(!withdrawn[msg.sender], "Already withdrawn");
        uint256 amount = balanceOf(msg.sender);
        require(amount > 0, "No points to burn");
        withdrawn[msg.sender] = true;
        _burn(msg.sender, amount);
        emit ClubWithdrawal(msg.sender, amount);
    }

    /// @notice An administrator may readmit a former member; no points are restored.
    function readmitMember(address member) external onlyRole(ADMIN_ROLE) {
        require(withdrawn[member], "Member has not withdrawn");
        withdrawn[member] = false;
        emit MemberReadmitted(member);
    }
}

/// @title Campus-Memo: at most ten NFTs, each redeemed by burning 100 CPT.
contract CampusMemo is ERC721, ReentrancyGuard {
    using Strings for uint256;
    uint256 public constant MAX_SUPPLY = 10;
    uint256 public constant PRICE = 100 * 10 ** 18;
    ClubToken public immutable clubToken;
    uint256 public totalMinted;

    event MemoMinted(address indexed member, uint256 indexed tokenId, uint256 cost);

    constructor(address tokenAddress) ERC721("Campus-Memo", "CMEMO") {
        require(tokenAddress.code.length > 0, "Invalid token contract");
        clubToken = ClubToken(tokenAddress);
        require(clubToken.decimals() == 18, "Expected 18 decimals");
    }

    function mintMemo() external nonReentrant returns (uint256 tokenId) {
        require(!clubToken.withdrawn(msg.sender), "Member has withdrawn");
        require(totalMinted < MAX_SUPPLY, "Sold out");
        tokenId = ++totalMinted;
        clubToken.burnFrom(msg.sender, PRICE);
        _safeMint(msg.sender, tokenId);
        emit MemoMinted(msg.sender, tokenId, PRICE);
    }

    /// @notice Permanent, self-contained metadata; no hosting service is required.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600">',
            '<rect width="600" height="600" fill="#102c42"/>',
            '<circle cx="300" cy="260" r="145" fill="#177e89"/>',
            '<path d="M200 200L400 320M400 200L200 320" stroke="#ffffff" stroke-width="18"/>',
            '<g fill="none" stroke="#ffc857" stroke-width="14">',
            '<circle cx="200" cy="200" r="38"/><circle cx="400" cy="200" r="38"/>',
            '<circle cx="200" cy="320" r="38"/><circle cx="400" cy="320" r="38"/></g>',
            '<text x="300" y="465" text-anchor="middle" fill="white" font-family="sans-serif" font-size="34">HKU DRONE CLUB</text>',
            '<text x="300" y="520" text-anchor="middle" fill="#ffc857" font-family="sans-serif" font-size="26">Campus-Memo #',
            tokenId.toString(), '</text></svg>'
        );
        bytes memory metadata = abi.encodePacked(
            '{"name":"Campus-Memo #', tokenId.toString(),
            '","description":"HKU Drone Club commemorative NFT. Limited to 10; minted by burning 100 CPT.",',
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)),
            '","attributes":[{"trait_type":"Edition","value":', tokenId.toString(),
            '},{"trait_type":"Maximum supply","value":10}]}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(metadata));
    }
}
