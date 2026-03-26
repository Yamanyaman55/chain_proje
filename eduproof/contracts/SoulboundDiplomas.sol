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
    mapping(address => string) public walletToName; // 1 Wallet -> 1 Isim

    event DiplomaMinted(address indexed graduate, uint256 tokenId, string degree);
    event DiplomaRevoked(uint256 tokenId);

    /**
     * @dev Gelen stringin SADECE büyük harflerden (A-Z, Türkçe dahil) ve boşluktan oluştuğunu kontrol eder.
     * Rakamlara veya özel karakterlere izin vermez.
     */
    function _isUppercaseAndValid(string memory str) internal pure returns (bool) {
        bytes memory bStr = bytes(str);
        if (bStr.length == 0) return false;

        for (uint i = 0; i < bStr.length; i++) {
            uint8 b = uint8(bStr[i]);

            // ASCII Bosluk (Space)
            if (b == 0x20) continue;

            // ASCII A-Z
            if (b >= 0x41 && b <= 0x5A) continue;

            // UTF-8 Turkce Buyuk Harfler (Ç, Ğ, İ, Ö, Ş, Ü)
            if (b == 0xC3 || b == 0xC4 || b == 0xC5) {
                if (i + 1 < bStr.length) {
                    uint8 nextB = uint8(bStr[i+1]);
                    if (b == 0xC3 && nextB == 0x87) { i++; continue; } // Ç
                    if (b == 0xC4 && nextB == 0x9E) { i++; continue; } // Ğ
                    if (b == 0xC4 && nextB == 0xB0) { i++; continue; } // İ
                    if (b == 0xC3 && nextB == 0x96) { i++; continue; } // Ö
                    if (b == 0xC5 && nextB == 0x9E) { i++; continue; } // Ş
                    if (b == 0xC3 && nextB == 0x9C) { i++; continue; } // Ü
                }
            }

            // Gecersiz bir byte bulunursa islem basarisiz olur (Kucuk harf, sayi, isaret vb.)
            return false;
        }
        return true;
    }

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
        require(_isUppercaseAndValid(graduateName), "Isim sadece buyuk harflerden olusmalidir.");
        
        // --- Sovereign Identity Check ---
        // 1. Bu kimlik daha önce başka bir cüzdana bağlandı mı?
        if (identityToWallet[identityHash] == address(0)) {
            // İlk kez bağlanıyor, cüzdanın da boş olması lazım
            require(walletToIdentity[graduate] == bytes32(0), "Bu cuzdan zaten baska bir kimlige atanmis.");
            identityToWallet[identityHash] = graduate;
            walletToIdentity[graduate] = identityHash;
            walletToName[graduate] = graduateName;
        } else {
            // Bu kimlik zaten bir cüzdana bağlı, o zaman cüzdan eşleşmeli
            require(identityToWallet[identityHash] == graduate, "Bu kimlik baska bir cuzdan adresi ile eslesmis.");
            // 2. Diploma için aynı isim girilmelidir
            require(keccak256(bytes(walletToName[graduate])) == keccak256(bytes(graduateName)), "Girilen isim, bu cuzdanin kayitli ilk ismiyle birebir ayni olmalidir.");
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
        walletToName[newWallet] = walletToName[oldWallet];
        walletToName[oldWallet] = "";

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
