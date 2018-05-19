pragma solidity ^0.4.19;
pragma experimental ABIEncoderV2;

contract AssetCategorization {
    
    struct Category {
        string name;
        string ipfsHash;
        string url;
    }
    
    struct CategoryIndex {
        uint index;
        bool exists;
    }
    
    address public owner;
    mapping (address => mapping(bytes32 => bool)) public assets;
    mapping (bytes32 => CategoryIndex) public categoryIndexes;
    Category[] public categories;

    constructor() public {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    function checkAsset(address asset, string categoryName) view public returns (bool) {
        bytes32 categoryHash = keccak256(categoryName);
        return assets[asset][categoryHash];
    }
    
    function addAsset(address asset, string categoryName) public onlyOwner {
       require(asset != address(0));
       bytes32 categoryHash = keccak256(categoryName);
       require(categoryIndexes[categoryHash].exists);
       assets[asset][categoryHash] = true;
    }
    
    function addCategory(string categoryName, string ipfsHash, string url) public onlyOwner {
        bytes32 categoryHash = keccak256(categoryName);
        require(categoryHash != keccak256(""));
        require(!categoryIndexes[categoryHash].exists);
      
        CategoryIndex memory ci = CategoryIndex(categories.length, true);
        categoryIndexes[categoryHash] = ci;
        
        categories.push(Category(categoryName, ipfsHash, url));
    }
    
    function removeAsset(address asset, string categoryName) public onlyOwner {
       require(asset != address(0));
       bytes32 categoryHash = keccak256(categoryName);
       assets[asset][categoryHash] = false;
    }
    
    function getCategory(string categoryName) view public returns (string, string, string) {
        bytes32 categoryHash = keccak256(categoryName);
        require(categoryIndexes[categoryHash].exists);
        uint index = categoryIndexes[categoryHash].index;
        Category cat = categories[index];
        return (cat.name, cat.ipfsHash, cat.url);
    }

}


