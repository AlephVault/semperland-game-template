// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SemperlandPersona is Ownable {
    enum Color {
        Black,
        Blue,
        DarkBrown,
        Green,
        LightBrown,
        Pink,
        Purple,
        Red,
        White,
        Yellow
    }

    enum Sex {
        Male,
        Female
    }

    enum Body {
        White,
        Black,
        Yellow,
        Orange,
        Blue,
        Red,
        Green,
        Purple
    }

    enum ClothType {
        Standard,
        Simple
    }

    enum TraitType {
        Arms,
        Boots,
        Chest,
        Hair,
        HairTail,
        Hat,
        LongShirt,
        Pants,
        Shirt,
        Shoulder,
        Waist,
        Cloth,
        Necklace,
        Cloak
    }

    struct Trait {
        uint128 lotId;
        uint120 itemId;
        Color color;
    }

    struct Persona {
        string name;
        Sex sex;
        Body body;
        ClothType clothType;
        Trait hair;
        Trait hairTail;
        Trait necklace;
        Trait hat;
    }

    struct SimpleClothing {
        Trait cloth;
    }

    struct StandardClothing {
        Trait boots;
        Trait pants;
        Trait shirt;
        Trait chest;
        Trait waist;
        Trait arms;
        Trait longShirt;
        Trait shoulders;
        Trait cloak;
        bool bootsOverPants;
    }

    struct TraitsLot {
        string name;
        string url;
    }

    struct TraitAvailability {
        Sex sex;
        TraitType traitType;
        uint120 traitId;
        uint256 colors;
    }

    struct Delegation {
        uint256 validSince;
        uint256 validUntil;
        uint256 nonce;
        uint8 signatureScheme;
        bytes32 authDataHash;
    }

    struct SignatureAuthorization {
        uint256 validSince;
        uint256 validUntil;
        uint8 signatureScheme;
        bytes authData;
        bytes signature;
    }

    uint8 public constant SIGNATURE_SCHEME_ECDSA = 1;
    uint128 public constant DEFAULT_LOT_ID = 1;
    uint256 public constant ALL_COLORS = (1 << 10) - 1;

    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant EIP712_NAME_HASH = keccak256("SemperlandPersona");
    bytes32 private constant EIP712_VERSION_HASH = keccak256("1");
    bytes32 private constant TRAIT_TYPEHASH =
        keccak256("Trait(uint128 lotId,uint120 itemId,uint8 color)");
    bytes32 private constant PERSONA_TYPEHASH =
        keccak256(
            "Persona(string name,uint8 sex,uint8 body,uint8 clothType,bytes32 hair,bytes32 hairTail,bytes32 necklace,bytes32 hat)"
        );
    bytes32 private constant SIMPLE_CLOTHING_TYPEHASH = keccak256("SimpleClothing(bytes32 cloth)");
    bytes32 private constant STANDARD_CLOTHING_TYPEHASH =
        keccak256(
            "StandardClothing(bytes32 boots,bytes32 pants,bytes32 shirt,bytes32 chest,bytes32 waist,bytes32 arms,bytes32 longShirt,bytes32 shoulders,bytes32 cloak,bool bootsOverPants)"
        );
    bytes32 private constant REGISTER_TYPEHASH =
        keccak256(
            "RegisterFor(address target,bytes32 personaHash,bytes32 simpleHash,bytes32 standardHash,uint256 validSince,uint256 validUntil,uint256 nonce,uint8 signatureScheme,bytes32 authDataHash)"
        );
    bytes32 private constant UPDATE_TYPEHASH =
        keccak256(
            "UpdateFor(address target,bytes32 personaHash,bytes32 simpleHash,bytes32 standardHash,uint256 validSince,uint256 validUntil,uint256 nonce,uint8 signatureScheme,bytes32 authDataHash)"
        );
    bytes32 private constant CHANGE_NAME_TYPEHASH =
        keccak256(
            "ChangeNameFor(address target,bytes32 nameHash,uint256 validSince,uint256 validUntil,uint256 nonce,uint8 signatureScheme,bytes32 authDataHash)"
        );

    uint128 public nextLotId;

    mapping(string normalizedName => address owner) public personasNames;
    mapping(address account => Persona persona) public personas;
    mapping(address account => SimpleClothing simpleClothing) public simpleClothing;
    mapping(address account => StandardClothing standardClothing) public standardClothing;
    mapping(uint128 lotId => TraitsLot lot) public lots;
    mapping(uint128 lotId => mapping(Sex sex => mapping(TraitType traitType => mapping(uint120 traitId => uint256 colors))))
        public availableTraits;
    mapping(uint128 lotId => bool isDefault) public defaultLots;
    mapping(address account => mapping(uint128 lotId => bool isAllowed)) public allowedLots;
    mapping(address account => uint256 nonce) public nonces;

    bytes32 private immutable _domainSeparator;
    uint256 private immutable _domainChainId;

    error InvalidName();
    error PersonaAlreadyRegistered(address account);
    error PersonaNotRegistered(address account);
    error NameAlreadyRegistered(string normalizedName, address currentOwner);
    error InvalidClothingArguments();
    error InvalidLot(uint128 lotId);
    error InvalidColors(uint256 colors);
    error InvalidTrait(TraitType traitType, uint128 lotId, uint120 itemId, Color color);
    error InvalidValidityWindow();
    error UnsupportedSignatureScheme(uint8 signatureScheme);
    error InvalidSignature();

    event TraitsLotRegistered(uint128 indexed lotId, string name, string url);
    event TraitsLotUpdated(uint128 indexed lotId, string name, string url);
    event TraitColorsAdded(
        uint128 indexed lotId,
        Sex sex,
        TraitType traitType,
        uint120 traitId,
        uint256 colorsBeingAdded,
        uint256 colorsAfter
    );
    event DefaultLotSet(uint128 indexed lotId, bool allowed);
    event PersonaLotSet(address indexed account, uint128 indexed lotId, bool allowed);
    event PersonaRegistered(address indexed account, string normalizedName);
    event PersonaUpdated(address indexed account);
    event PersonaNameChanged(address indexed account, string oldNormalizedName, string newNormalizedName);

    constructor(TraitAvailability[] memory defaultTraits)
        Ownable(msg.sender)
    {
        _domainChainId = block.chainid;
        _domainSeparator = _buildDomainSeparator();
        nextLotId = DEFAULT_LOT_ID;
        _registerTraitsLot("Default", "local://default");
        defaultLots[DEFAULT_LOT_ID] = true;
        emit DefaultLotSet(DEFAULT_LOT_ID, true);

        for (uint256 i = 0; i < defaultTraits.length; i++) {
            TraitAvailability memory item = defaultTraits[i];
            _addAvailableTraitColors(DEFAULT_LOT_ID, item.sex, item.traitType, item.traitId, item.colors);
        }
    }

    function register(
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_
    ) external {
        _registerFor(msg.sender, persona, simpleClothing_, standardClothing_);
    }

    function registerFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_,
        SignatureAuthorization calldata authorization
    ) external {
        bytes32 structHash =
            _hashRegisterFor(target, persona, simpleClothing_, standardClothing_, authorization);
        _verifyAuthorization(target, structHash, authorization);
        _registerFor(target, persona, simpleClothing_, standardClothing_);
    }

    function update(
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_
    ) external {
        _updateFor(msg.sender, persona, simpleClothing_, standardClothing_);
    }

    function updateFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_,
        SignatureAuthorization calldata authorization
    ) external {
        bytes32 structHash =
            _hashUpdateFor(target, persona, simpleClothing_, standardClothing_, authorization);
        _verifyAuthorization(target, structHash, authorization);
        _updateFor(target, persona, simpleClothing_, standardClothing_);
    }

    function changeName(string memory newName) external {
        _changeNameFor(msg.sender, newName);
    }

    function changeNameFor(
        address target,
        string memory newName,
        SignatureAuthorization calldata authorization
    ) external {
        string memory normalizedName = _normalizeName(newName);
        bytes32 structHash = _hashChangeNameFor(target, normalizedName, authorization);
        _verifyAuthorization(target, structHash, authorization);
        _changeNameFor(target, newName);
    }

    function registerTraitsLot(string memory name, string memory url) external onlyOwner returns (uint128 lotId) {
        lotId = _registerTraitsLot(name, url);
    }

    function updateTraitsLot(uint128 lotId, string memory name, string memory url) external onlyOwner {
        _requireRegisteredLot(lotId);
        if (bytes(name).length == 0) revert InvalidName();
        lots[lotId] = TraitsLot({name: name, url: url});
        emit TraitsLotUpdated(lotId, name, url);
    }

    function addAvailableTraitColors(
        uint128 lotId,
        Sex sex,
        TraitType traitType,
        uint120 traitId,
        uint256 colors
    ) external onlyOwner {
        _addAvailableTraitColors(lotId, sex, traitType, traitId, colors);
    }

    function setDefaultLot(uint128 lotId, bool allowed) external onlyOwner {
        _requireRegisteredLot(lotId);
        defaultLots[lotId] = allowed;
        emit DefaultLotSet(lotId, allowed);
    }

    function setAllowedLot(address account, uint128 lotId, bool allowed) external onlyOwner {
        _requireRegisteredLot(lotId);
        allowedLots[account][lotId] = allowed;
        emit PersonaLotSet(account, lotId, allowed);
    }

    function personaExists(address account) public view returns (bool) {
        return bytes(personas[account].name).length != 0;
    }

    function isLotAllowed(address account, uint128 lotId) public view returns (bool) {
        return defaultLots[lotId] || allowedLots[account][lotId];
    }

    function normalizeName(string memory name) external pure returns (string memory) {
        return _normalizeName(name);
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _registerFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_
    ) private {
        if (personaExists(target)) revert PersonaAlreadyRegistered(target);

        string memory normalizedName = _normalizeName(persona.name);
        address currentOwner = personasNames[normalizedName];
        if (currentOwner != address(0)) revert NameAlreadyRegistered(normalizedName, currentOwner);

        persona.name = normalizedName;
        _storePersona(target, persona, simpleClothing_, standardClothing_);
        personasNames[normalizedName] = target;

        emit PersonaRegistered(target, normalizedName);
    }

    function _updateFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_
    ) private {
        if (!personaExists(target)) revert PersonaNotRegistered(target);

        persona.name = personas[target].name;
        _storePersona(target, persona, simpleClothing_, standardClothing_);

        emit PersonaUpdated(target);
    }

    function _changeNameFor(address target, string memory newName) private {
        if (!personaExists(target)) revert PersonaNotRegistered(target);

        string memory oldNormalizedName = personas[target].name;
        string memory newNormalizedName = _normalizeName(newName);
        address currentOwner = personasNames[newNormalizedName];
        if (currentOwner != address(0) && currentOwner != target) {
            revert NameAlreadyRegistered(newNormalizedName, currentOwner);
        }

        delete personasNames[oldNormalizedName];
        personasNames[newNormalizedName] = target;
        personas[target].name = newNormalizedName;

        emit PersonaNameChanged(target, oldNormalizedName, newNormalizedName);
    }

    function _storePersona(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_
    ) private {
        _validatePersonaTraits(target, persona.sex, persona);

        if (persona.clothType == ClothType.Simple) {
            if (simpleClothing_.length != 1 || standardClothing_.length != 0) revert InvalidClothingArguments();
            _validateTrait(target, persona.sex, TraitType.Cloth, simpleClothing_[0].cloth);
            simpleClothing[target] = simpleClothing_[0];
            delete standardClothing[target];
        } else {
            if (simpleClothing_.length != 0 || standardClothing_.length != 1) revert InvalidClothingArguments();
            _validateStandardClothing(target, persona.sex, standardClothing_[0]);
            standardClothing[target] = standardClothing_[0];
            delete simpleClothing[target];
        }

        personas[target] = persona;
    }

    function _validatePersonaTraits(address target, Sex sex, Persona memory persona) private view {
        _validateTrait(target, sex, TraitType.Hair, persona.hair);
        _validateTrait(target, sex, TraitType.HairTail, persona.hairTail);
        _validateTrait(target, sex, TraitType.Necklace, persona.necklace);
        _validateTrait(target, sex, TraitType.Hat, persona.hat);
    }

    function _validateStandardClothing(address target, Sex sex, StandardClothing memory clothing) private view {
        _validateTrait(target, sex, TraitType.Boots, clothing.boots);
        _validateTrait(target, sex, TraitType.Pants, clothing.pants);
        _validateTrait(target, sex, TraitType.Shirt, clothing.shirt);
        _validateTrait(target, sex, TraitType.Chest, clothing.chest);
        _validateTrait(target, sex, TraitType.Waist, clothing.waist);
        _validateTrait(target, sex, TraitType.Arms, clothing.arms);
        _validateTrait(target, sex, TraitType.LongShirt, clothing.longShirt);
        _validateTrait(target, sex, TraitType.Shoulder, clothing.shoulders);
        _validateTrait(target, sex, TraitType.Cloak, clothing.cloak);
    }

    function _validateTrait(address target, Sex sex, TraitType traitType, Trait memory trait) private view {
        if (trait.lotId == 0) return;
        if (trait.itemId == 0 || !isLotAllowed(target, trait.lotId)) {
            revert InvalidTrait(traitType, trait.lotId, trait.itemId, trait.color);
        }

        uint256 colors = availableTraits[trait.lotId][sex][traitType][trait.itemId];
        if ((colors & (1 << uint8(trait.color))) == 0) {
            revert InvalidTrait(traitType, trait.lotId, trait.itemId, trait.color);
        }
    }

    function _registerTraitsLot(string memory name, string memory url) private returns (uint128 lotId) {
        if (bytes(name).length == 0) revert InvalidName();

        lotId = nextLotId;
        lots[lotId] = TraitsLot({name: name, url: url});
        nextLotId = lotId + 1;

        emit TraitsLotRegistered(lotId, name, url);
    }

    function _addAvailableTraitColors(
        uint128 lotId,
        Sex sex,
        TraitType traitType,
        uint120 traitId,
        uint256 colors
    ) private {
        _requireRegisteredLot(lotId);
        if (traitId == 0) revert InvalidTrait(traitType, lotId, traitId, Color.Black);
        if (colors == 0 || (colors & ~ALL_COLORS) != 0) revert InvalidColors(colors);

        uint256 colorsAfter = availableTraits[lotId][sex][traitType][traitId] | colors;
        availableTraits[lotId][sex][traitType][traitId] = colorsAfter;

        emit TraitColorsAdded(lotId, sex, traitType, traitId, colors, colorsAfter);
    }

    function _requireRegisteredLot(uint128 lotId) private view {
        if (bytes(lots[lotId].name).length == 0) revert InvalidLot(lotId);
    }

    function _verifyAuthorization(
        address target,
        bytes32 structHash,
        SignatureAuthorization calldata authorization
    ) private {
        if (
            authorization.validSince > authorization.validUntil ||
            block.timestamp < authorization.validSince ||
            block.timestamp > authorization.validUntil
        ) {
            revert InvalidValidityWindow();
        }
        if (authorization.signatureScheme != SIGNATURE_SCHEME_ECDSA) {
            revert UnsupportedSignatureScheme(authorization.signatureScheme);
        }

        address signer = ECDSA.recover(_hashTypedDataV4(structHash), authorization.signature);
        if (signer != target) revert InvalidSignature();

        nonces[target]++;
    }

    function _hashRegisterFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_,
        SignatureAuthorization calldata authorization
    ) private view returns (bytes32) {
        return _hashDelegatedClothingAction(
            REGISTER_TYPEHASH,
            target,
            _hashPersona(persona, true),
            _hashSimpleClothingArray(simpleClothing_),
            _hashStandardClothingArray(standardClothing_),
            _delegation(target, authorization)
        );
    }

    function _hashUpdateFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_,
        SignatureAuthorization calldata authorization
    ) private view returns (bytes32) {
        return _hashDelegatedClothingAction(
            UPDATE_TYPEHASH,
            target,
            _hashPersona(persona, false),
            _hashSimpleClothingArray(simpleClothing_),
            _hashStandardClothingArray(standardClothing_),
            _delegation(target, authorization)
        );
    }

    function _hashChangeNameFor(
        address target,
        string memory normalizedName,
        SignatureAuthorization calldata authorization
    ) private view returns (bytes32) {
        Delegation memory delegation_ = _delegation(target, authorization);
        return keccak256(
            abi.encode(
                CHANGE_NAME_TYPEHASH,
                target,
                keccak256(bytes(normalizedName)),
                delegation_.validSince,
                delegation_.validUntil,
                delegation_.nonce,
                delegation_.signatureScheme,
                delegation_.authDataHash
            )
        );
    }

    function _delegation(
        address target,
        SignatureAuthorization calldata authorization
    ) private view returns (Delegation memory) {
        return Delegation({
            validSince: authorization.validSince,
            validUntil: authorization.validUntil,
            nonce: nonces[target],
            signatureScheme: authorization.signatureScheme,
            authDataHash: keccak256(authorization.authData)
        });
    }

    function _hashDelegatedClothingAction(
        bytes32 typeHash,
        address target,
        bytes32 personaHash,
        bytes32 simpleHash,
        bytes32 standardHash,
        Delegation memory delegation_
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                typeHash,
                target,
                personaHash,
                simpleHash,
                standardHash,
                delegation_.validSince,
                delegation_.validUntil,
                delegation_.nonce,
                delegation_.signatureScheme,
                delegation_.authDataHash
            )
        );
    }

    function _hashTypedDataV4(bytes32 structHash) private view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }

    function _domainSeparatorV4() private view returns (bytes32) {
        if (block.chainid == _domainChainId) return _domainSeparator;
        return _buildDomainSeparator();
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, EIP712_NAME_HASH, EIP712_VERSION_HASH, block.chainid, address(this))
        );
    }

    function _normalizeName(string memory name) private pure returns (string memory) {
        bytes memory raw = bytes(name);
        uint256 length = raw.length;
        if (length < 3 || length > 32) revert InvalidName();
        if (!_isNameStart(raw[0])) revert InvalidName();

        bytes memory normalized = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            bytes1 char = raw[i];
            if (i == 0) {
                if (!_isNameStart(char)) revert InvalidName();
            } else if (!_isNamePart(char)) {
                revert InvalidName();
            }

            normalized[i] = _toLower(char);
        }

        return string(normalized);
    }

    function _isNameStart(bytes1 char) private pure returns (bool) {
        return char == 0x5f || (char >= 0x41 && char <= 0x5a) || (char >= 0x61 && char <= 0x7a);
    }

    function _isNamePart(bytes1 char) private pure returns (bool) {
        return _isNameStart(char) || (char >= 0x30 && char <= 0x39);
    }

    function _toLower(bytes1 char) private pure returns (bytes1) {
        if (char >= 0x41 && char <= 0x5a) {
            return bytes1(uint8(char) + 32);
        }
        return char;
    }

    function _hashTrait(Trait memory trait) private pure returns (bytes32) {
        return keccak256(abi.encode(TRAIT_TYPEHASH, trait.lotId, trait.itemId, uint8(trait.color)));
    }

    function _hashPersona(Persona memory persona, bool includeName) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PERSONA_TYPEHASH,
                includeName ? keccak256(bytes(_normalizeName(persona.name))) : keccak256(bytes("")),
                uint8(persona.sex),
                uint8(persona.body),
                uint8(persona.clothType),
                _hashTrait(persona.hair),
                _hashTrait(persona.hairTail),
                _hashTrait(persona.necklace),
                _hashTrait(persona.hat)
            )
        );
    }

    function _hashSimpleClothingArray(SimpleClothing[] memory clothing) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](clothing.length);
        for (uint256 i = 0; i < clothing.length; i++) {
            hashes[i] = keccak256(abi.encode(SIMPLE_CLOTHING_TYPEHASH, _hashTrait(clothing[i].cloth)));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _hashStandardClothingArray(StandardClothing[] memory clothing) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](clothing.length);
        for (uint256 i = 0; i < clothing.length; i++) {
            hashes[i] = keccak256(
                abi.encode(
                    STANDARD_CLOTHING_TYPEHASH,
                    _hashTrait(clothing[i].boots),
                    _hashTrait(clothing[i].pants),
                    _hashTrait(clothing[i].shirt),
                    _hashTrait(clothing[i].chest),
                    _hashTrait(clothing[i].waist),
                    _hashTrait(clothing[i].arms),
                    _hashTrait(clothing[i].longShirt),
                    _hashTrait(clothing[i].shoulders),
                    _hashTrait(clothing[i].cloak),
                    clothing[i].bootsOverPants
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }
}
