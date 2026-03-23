// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SoulboundDiplomas
 * @dev Diplomaların transfer edilemediği (Soulbound), sadece üniversite tarafından verilen blokzincir sertifika sistemi.
 */
contract SoulboundDiplomas {
    string public name = "EduProof Soulbound Diploma";
    string public symbol = "ESBD";
    address public university;

    struct Diploma {
        string graduateName;
        string degree;
        string ipfsHash;
        uint256 timestamp;
        bytes32 identityHash; // KVKK uyumlu gizli kimlik parmak izi tc kimlik no hash 
        bool isValid;
    }

    uint256 private _nextTokenId;
    mapping(uint256 => Diploma) public diplomas;
    mapping(address => uint256[]) public holderToTokenIds;
    mapping(uint256 => address) public tokenIdToHolder;
    mapping(address => mapping(string => bool)) public hasDegree;
    
    // Sovereign Identity Mappings
    mapping(bytes32 => address) public identityToWallet; // 1 TC -> 1 Wallet
    mapping(address => bytes32) public walletToIdentity; // 1 Wallet -> 1 TC

    event DiplomaMinted(address indexed graduate, uint256 tokenId, string degree);
    event DiplomaRevoked(uint256 tokenId);

    modifier onlyUniversity() {
        require(msg.sender == university, "Sadece yetkili universite bu islemi yapabilir.");
        _;
    }

    constructor() {
        university = msg.sender;
    }

    /**
     * @dev Yeni bir diploma basar. Sadece üniversite yetkilisi yapabilir.
     */
    function mintDiploma(address graduate, string memory graduateName, string memory degree, string memory ipfsHash, bytes32 identityHash) public onlyUniversity {
        require(!hasDegree[graduate][degree], "Bu mezun zaten bu bolumden bir diplomaya sahip.");
        
        // --- Sovereign Identity Check ---
        // 1. Bu kimlik daha önce başka bir cüzdana bağlandı mı?
        if (identityToWallet[identityHash] == address(0)) {
            // İlk kez bağlanıyor, cüzdanın da boş olması lazım
            require(walletToIdentity[graduate] == bytes32(0), "Bu cuzdan zaten baska bir kimlige atanmis.");
            identityToWallet[identityHash] = graduate;
            walletToIdentity[graduate] = identityHash;
        } else {
            // Bu kimlik zaten bir cüzdana bağlı, o zaman cüzdan eşleşmeli
            require(identityToWallet[identityHash] == graduate, "Bu kimlik baska bir cuzdan adresi ile eslesmis.");
        }

        uint256 tokenId = ++_nextTokenId;
        diplomas[tokenId] = Diploma(graduateName, degree, ipfsHash, block.timestamp, identityHash, true);
        holderToTokenIds[graduate].push(tokenId);
        tokenIdToHolder[tokenId] = graduate;
        hasDegree[graduate][degree] = true;

        emit DiplomaMinted(graduate, tokenId, degree);
    }

    /**
     * @dev Sahte veya iptal edilen diplomayı geçersiz kılar.
     */
    function revokeDiploma(uint256 tokenId) public onlyUniversity {
        require(diplomas[tokenId].isValid, "Diploma zaten gecersiz.");
        diplomas[tokenId].isValid = false;
        
        emit DiplomaRevoked(tokenId);
    }

    /**
     * @dev Soulbound özelliği: Transfer fonksiyonları devre dışı bırakılmıştır.
     * Bu fonksiyonlar çağrıldığında hata verecektir veya kontratta hiç yoktur.
     */
    function transfer(address, uint256) public pure {
        revert("Bu bir Soulbound tokendir, transfer edilemez.");
    }

    function getDiploma(uint256 tokenId) public view returns (Diploma memory) {
        return diplomas[tokenId];
    }

    /**
     * @dev Bir adresin sahip olduğu tüm diploma ID'lerini döner.
     */
    function getHolderTokens(address holder) public view returns (uint256[] memory) {
        return holderToTokenIds[holder];
    }

    /**
     * @dev Cuzdan kaybi durumunda (Recovery) ogrencinin kimligi yeni bir cuzdanla degistirilir.
     * Eski cuzdandaki tum diplomalar yeni cuzdanina aktarilir.
     */
    function recoverWallet(bytes32 identityHash, address oldWallet, address newWallet) public onlyUniversity {
        require(identityToWallet[identityHash] == oldWallet, "Bu kimlik belirtilen eski cuzdanla eslesmiyor.");
        require(walletToIdentity[newWallet] == bytes32(0), "Yeni cuzdan baska bir kimlige kayitli.");

        // Kimlik atamasini guncelle
        identityToWallet[identityHash] = newWallet;
        walletToIdentity[newWallet] = identityHash;
        walletToIdentity[oldWallet] = bytes32(0);

        uint256[] memory tokens = holderToTokenIds[oldWallet];
        for(uint i = 0; i < tokens.length; i++) {
            uint256 tId = tokens[i];
            tokenIdToHolder[tId] = newWallet;
            holderToTokenIds[newWallet].push(tId);

            string memory dgr = diplomas[tId].degree;
            hasDegree[newWallet][dgr] = true;
            hasDegree[oldWallet][dgr] = false;
        }
        
        delete holderToTokenIds[oldWallet];
    }
}
