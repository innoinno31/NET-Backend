// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title NuclearCertificationStorage
 * @author Franck
 * @notice Contrat de stockage pour la certification nucléaire
 * @dev Implémente les structures de données, les enums, les events et les mappings
 */
contract NuclearCertificationStorage is AccessControl, ERC721 {
    /** Enums */
    enum CertificationSteps {
        Registered,
        DocumentsPending,
        ReadyForReview,
        UnderReview,
        Certified,
        Rejected
    }

    enum DocumentType {
        Certification,
        LabReport,
        TechFile,
        Compliance,
        RegulatoryReview
    }

    enum DocumentStatus {
        Submitted,
        Pending,
        Verified,
        Rejected,
        Deprecated
    }

    enum EquipmentStatus {
        Registered,
        Pending,
        Certified,
        Rejected,
        Deprecated
    }

    /** Structures */
    struct CertificationData {
        bytes32 hashGlobal;
        uint256 timestamp;
        address certifier;
    }

    struct Plant {
        uint256 id;
        string name;
        string description;
        string location;
        uint256 registeredAt;
        bool isActive;
    }

    struct Actor {
        uint256 id;
        string name;
        address actorAddress;
        bytes32 role;
        uint256 registeredAt;
        uint256 plantId;
    }

    struct Equipment {
        uint256 id;
        string name;
        string description;
        CertificationSteps currentStep;
        EquipmentStatus status;
        uint256 registeredAt;
        uint256 certifiedAt;
        uint256 rejectedAt;
        uint256 pendingAt;
        uint256 deprecatedAt;
        string finalCertificationHash;
    }

    struct Document {
        uint256 id;
        string name;
        string description;
        DocumentType docType;
        DocumentStatus status;
        address submitter;
        uint256 submittedAt;
        uint256 verifiedAt;
        uint256 rejectedAt;
        uint256 pendingAt;
        uint256 deprecatedAt;
        string ipfsHash;
    }
    
    /** Events */
    event EquipmentRegistered(
        uint256 indexed equipmentId,
        string name,
        address registeredBy,
        uint256 timestamp
    );

    event EquipmentStepUpdated(
        uint256 indexed equipmentId,
        CertificationSteps previousStep,
        CertificationSteps newStep,
        address updatedBy,
        uint256 timestamp
    );

    event DocumentSubmitted(
        uint256 indexed documentId,
        uint256 indexed equipmentId,
        DocumentType docType,
        address submitter,
        uint256 timestamp
    );

    event DocumentStatusChanged(
        uint256 indexed documentId,
        DocumentStatus previousStatus,
        DocumentStatus newStatus,
        address updatedBy,
        uint256 timestamp
    );

    event EquipmentStatusChanged(
        uint256 indexed equipmentId,
        EquipmentStatus previousStatus,
        EquipmentStatus newStatus,
        address updatedBy,
        uint256 timestamp
    );

    event PlantRegistered(
        uint256 indexed plantId,
        string name,
        address registeredBy,
        uint256 timestamp
    );

    event HashGlobalGenerated(
        uint256 indexed equipmentId,
        bytes32 hashGlobal,
        address certifier,
        uint256 timestamp
    );

    event RoleAssigned(
        address indexed actor,
        bytes32 indexed role,
        address indexed assignedBy,
        uint256 timestamp
    );
    
    event RoleRevoked(
        address indexed actor,
        bytes32 indexed role,
        address indexed revokedBy,
        uint256 timestamp
    );
    
    event DocumentVerified(
        uint256 indexed documentId,
        uint256 indexed equipmentId,
        address indexed verifier,
        uint256 timestamp
    );
    
    event DocumentRejected(
        uint256 indexed documentId,
        uint256 indexed equipmentId,
        address indexed rejector,
        string reason,
        uint256 timestamp
    );
    
    event CertificationStarted(
        uint256 indexed equipmentId,
        address indexed initiator,
        uint256 timestamp
    );
    
    event CertificationCompleted(
        uint256 indexed equipmentId,
        address indexed certifier,
        bytes32 hashGlobal,
        uint256 timestamp
    );
    
    event CertificationRejected(
        uint256 indexed equipmentId,
        address indexed rejector,
        string reason,
        uint256 timestamp
    );
    
    event IntegrityVerified(
        uint256 indexed equipmentId,
        bytes32 hashGlobal,
        bool isValid,
        address verifier,
        uint256 timestamp
    );

    /** Custom errors */
    error EquipmentNotFound(uint256 equipmentId);
    error EquipmentAlreadyExists(uint256 equipmentId);
    error EquipmentNotPending(uint256 equipmentId);
    error EquipmentAlreadyRejected(uint256 equipmentId);
    error EquipmentDeprecated(uint256 equipmentId);
    error EquipmentAlreadyCertified(uint256 equipmentId);
    error EquipmentNotUnderReview(uint256 equipmentId);

    error DocumentNotFound(uint256 documentId);
    error DocumentAlreadyExists(uint256 documentId);
    error DocumentNotPending(uint256 documentId);
    error DocumentAlreadyRejected(uint256 documentId);
    error DocumentDeprecated(uint256 documentId);
    error DocumentTypeNotExpected(uint256 equipmentId, DocumentType docType);
    error DocumentSubmissionNotAllowed(uint256 equipmentId);
    error MissingRequiredDocuments(uint256 equipmentId);

    error UnauthorizedRole(address caller);
    error RoleAlreadyAssigned(address actor, bytes32 role);
    error RoleNotAllowedForAction(bytes32 role);
    error ActorNotRegistered(address actor);
    error UnauthorizedDocumentAccess(uint256 documentId, address caller);
    error SoulboundTokenNonTransferableAndNotBurnable(uint256 tokenId);

    error InvalidOperation(string message);
    error PlantNotFound(uint256 plantId);
    error InvalidInput(string reason);
    error ActionNotAllowedInCurrentStep(uint256 equipmentId, CertificationSteps step);

    // Define roles
    bytes32 public constant PLANT_OPERATOR_ADMIN = keccak256("PLANT_OPERATOR_ADMIN");
    bytes32 public constant MANUFACTURER = keccak256("MANUFACTURER");
    bytes32 public constant LABORATORY = keccak256("LABORATORY");
    bytes32 public constant REGULATORY_AUTHORITY = keccak256("REGULATORY_AUTHORITY");
    bytes32 public constant CERTIFICATION_OFFICER = keccak256("CERTIFICATION_OFFICER");

    /** Id Counters */
    uint256 private nextEquipmentId;
    uint256 private nextPlantId;
    uint256 private nextDocumentId;
    uint256 private nextActorId;

    /** Mappings */
    mapping(address => uint256[]) private _actorToPlants;
    mapping(uint256 => Plant) private _plants;
    mapping(uint256 => Equipment) private _equipments;
    mapping(uint256 => Document) private _documents;
    mapping(uint256 => uint256) private _equipmentToPlant;
    mapping(uint256 => uint256[]) private _plantToEquipments;
    mapping(uint256 => uint256) private _documentToEquipment;
    mapping(uint256 => uint256[]) private _equipmentToDocuments;
    mapping(uint256 => CertificationData) private _equipmentCertifications;
    mapping(DocumentType => mapping(bytes32 => bool)) private _documentAccessByRole;
    
    // Array to store all plant IDs for retrieval
    uint256[] private _allPlantIds;

    // Mapping to store actors
    mapping(uint256 => Actor) private _actors;
    
    // Array to store all actor IDs for retrieval
    uint256[] private _allActorIds;

    /**
     * @notice Contract constructor
     * @dev Sets the deployer as default admin and initializes the ERC721 contract
     */
    constructor() ERC721("Nuclear Equipment Traceability", "NET") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Plant Operator Admin is the admin for the other roles
        _setRoleAdmin(MANUFACTURER, PLANT_OPERATOR_ADMIN);
        _setRoleAdmin(LABORATORY, PLANT_OPERATOR_ADMIN);
        _setRoleAdmin(REGULATORY_AUTHORITY, PLANT_OPERATOR_ADMIN);
        _setRoleAdmin(CERTIFICATION_OFFICER, PLANT_OPERATOR_ADMIN);
        
        // 1. Safety Authority - full access to all documents
        _documentAccessByRole[DocumentType.Certification][REGULATORY_AUTHORITY] = true;
        _documentAccessByRole[DocumentType.LabReport][REGULATORY_AUTHORITY] = true;
        _documentAccessByRole[DocumentType.TechFile][REGULATORY_AUTHORITY] = true;
        _documentAccessByRole[DocumentType.Compliance][REGULATORY_AUTHORITY] = true;
        _documentAccessByRole[DocumentType.RegulatoryReview][REGULATORY_AUTHORITY] = true;
        
        // 2. Operator Admin - full access (equipment owner)
        _documentAccessByRole[DocumentType.Certification][PLANT_OPERATOR_ADMIN] = true;
        _documentAccessByRole[DocumentType.LabReport][PLANT_OPERATOR_ADMIN] = true;
        _documentAccessByRole[DocumentType.TechFile][PLANT_OPERATOR_ADMIN] = true;
        _documentAccessByRole[DocumentType.Compliance][PLANT_OPERATOR_ADMIN] = true;
        _documentAccessByRole[DocumentType.RegulatoryReview][PLANT_OPERATOR_ADMIN] = true;
        
        // 3. Certification Officer (Bureau Veritas) - full access for certification
        _documentAccessByRole[DocumentType.Certification][CERTIFICATION_OFFICER] = true;
        _documentAccessByRole[DocumentType.LabReport][CERTIFICATION_OFFICER] = true;
        _documentAccessByRole[DocumentType.TechFile][CERTIFICATION_OFFICER] = true;
        _documentAccessByRole[DocumentType.Compliance][CERTIFICATION_OFFICER] = true;
        _documentAccessByRole[DocumentType.RegulatoryReview][CERTIFICATION_OFFICER] = true;
        
        // 4. Manufacturer - only tech files and final certification
        _documentAccessByRole[DocumentType.Certification][MANUFACTURER] = true;
        _documentAccessByRole[DocumentType.TechFile][MANUFACTURER] = true;
        
        // 5. Laboratory  - only lab reports and final certification
        _documentAccessByRole[DocumentType.Certification][LABORATORY] = true;
        _documentAccessByRole[DocumentType.LabReport][LABORATORY] = true;
    }

    /**
     * @notice Gets the next plant ID and increments the counter
     * @return The next plant ID
     */
    function getNextPlantId() internal returns (uint256) {
        return nextPlantId++;
    }

    /**
     * @notice Gets the next equipment ID and increments the counter
     * @return The next equipment ID
     */
    function getNextEquipmentId() internal returns (uint256) {
        return nextEquipmentId++;
    }

    /**
     * @notice Gets the next document ID and increments the counter
     * @return The next document ID
     */
    function getNextDocumentId() internal returns (uint256) {
        return nextDocumentId++;
    }

    /**
     * @notice Gets the next actor ID and increments the counter
     * @return The next actor ID
     */
    function getNextActorId() internal returns (uint256) {
        return nextActorId++;
    }

    /**
     * @notice Gets an equipment by ID 
     * @param _equipmentId Equipment ID
     * @return The equipment data
     */
    function getEquipment(uint256 _equipmentId) external view returns (Equipment memory) {
        return _equipments[_equipmentId];
    }

    /**
     * @notice Gets a document by ID
     * @param _documentId Document ID 
     * @return The document data
     */
    function getDocument(uint256 _documentId) external view returns (Document memory) {
        return _documents[_documentId];
    }

    /**
     * @notice Gets the plant information
     * @param _plantId Plant ID
     * @return The plant data
     */
    function getPlant(uint256 _plantId) external view returns (Plant memory) {
        return _plants[_plantId];
    }

    /**
     * @notice Gets documents associated with an equipment
     * @param _equipmentId Equipment ID
     * @return Array of document IDs
     */
    function getEquipmentDocuments(uint256 _equipmentId) external view returns (uint256[] memory) {
        return _equipmentToDocuments[_equipmentId];
    }

    /**
     * @notice Gets certification data for an equipment
     * @param _equipmentId Equipment ID
     * @return The certification data
     */
    function getEquipmentCertification(uint256 _equipmentId) external view returns (CertificationData memory) {
        return _equipmentCertifications[_equipmentId];
    }

    /**
     * @notice Checks if a role has access to a document type
     * @param _docType Document type
     * @param _role Role to check
     * @return True if access is allowed
     */
    function hasDocumentAccess(DocumentType _docType, bytes32 _role) external view returns (bool) {
        return _documentAccessByRole[_docType][_role];
    }

    /**
     * @notice Creates a new plant
     * @param _creator Address of the plant creator
     * @param _name Plant name
     * @param _description Plant description
     * @param _location Plant location
     * @param _isActive Plant active status
     * @return The plant ID
     */
    function createPlant(
        address _creator,
        string memory _name,
        string memory _description,
        string memory _location,
        bool _isActive
    ) external returns (uint256) {
        uint256 plantId = nextPlantId++;
        
        Plant memory newPlant = Plant({
            id: plantId,
            name: _name,
            description: _description,
            location: _location,
            registeredAt: block.timestamp,
            isActive: _isActive
        });
        
        _plants[plantId] = newPlant;
        _actorToPlants[_creator].push(plantId);
        
        // Add the new plant ID to the list of all plant IDs
        _allPlantIds.push(plantId);
        
        emit PlantRegistered(
            plantId,
            _name,
            _creator,
            block.timestamp
        );
        
        return plantId;
    }

    /**
     * @notice Creates a new equipment
     * @param _creator Address of the equipment creator (owner)
     * @param _name Equipment name
     * @param _description Equipment description
     * @param _plantId Plant ID
     * @return The equipment ID
     */
    function createEquipment(
        address _creator,
        string memory _name,
        string memory _description,
        uint256 _plantId
    ) external returns (uint256) {
        if (bytes(_name).length == 0) {
            revert InvalidInput("Name cannot be empty");
        }
        
        if (_plants[_plantId].registeredAt == 0) {
            revert PlantNotFound(_plantId);
        }
        
        uint256 equipmentId = nextEquipmentId++;
        
        Equipment memory newEquipment = Equipment({
            id: equipmentId,
            name: _name,
            description: _description,
            currentStep: CertificationSteps.Registered,
            status: EquipmentStatus.Registered,
            registeredAt: block.timestamp,
            certifiedAt: 0,
            rejectedAt: 0,
            pendingAt: 0,
            deprecatedAt: 0,
            finalCertificationHash: ""
        });
        
        _equipments[equipmentId] = newEquipment;
        _equipmentToPlant[equipmentId] = _plantId;
        _plantToEquipments[_plantId].push(equipmentId);
        
        _safeMint(_creator, equipmentId);
        
        emit EquipmentRegistered(equipmentId, _name, _creator, block.timestamp);
        
        return equipmentId;
    }

    /**
     * @notice Creates a new document
     * @param _submitter Address of the document submitter
     * @param _equipmentId Equipment ID
     * @param _docType Document type
     * @param _name Document name
     * @param _description Document description
     * @param _ipfsHash IPFS hash
     * @return The document ID
     */
    function createDocument(
        address _submitter,
        uint256 _equipmentId,
        DocumentType _docType,
        string memory _name,
        string memory _description,
        string memory _ipfsHash
    ) external returns (uint256) {
        if (_equipments[_equipmentId].registeredAt == 0) {
            revert EquipmentNotFound(_equipmentId);
        }
        
        uint256 documentId = nextDocumentId++;
        
        Document memory newDocument = Document({
            id: documentId,
            name: _name,
            description: _description,
            docType: _docType,
            status: DocumentStatus.Submitted,
            submitter: _submitter,
            submittedAt: block.timestamp,
            verifiedAt: 0,
            rejectedAt: 0,
            pendingAt: 0,
            deprecatedAt: 0,
            ipfsHash: _ipfsHash
        });
        
        _documents[documentId] = newDocument;
        _equipmentToDocuments[_equipmentId].push(documentId);
        _documentToEquipment[documentId] = _equipmentId;
        
        emit DocumentSubmitted(documentId, _equipmentId, _docType, _submitter, block.timestamp);
        
        return documentId;
    }

    /**
     * @notice Updates an equipment status
     * @param _updater Address of the updater
     * @param _equipmentId Equipment ID
     * @param _newStatus New status
     * @param _newStep New certification step
     */
    function updateEquipmentStatus(
        address _updater,
        uint256 _equipmentId,
        EquipmentStatus _newStatus,
        CertificationSteps _newStep
    ) external {
        if (_equipments[_equipmentId].registeredAt == 0) {
            revert EquipmentNotFound(_equipmentId);
        }
        
        Equipment storage equipment = _equipments[_equipmentId];
        EquipmentStatus oldStatus = equipment.status;
        CertificationSteps oldStep = equipment.currentStep;
        
        equipment.status = _newStatus;
        equipment.currentStep = _newStep;
        
        // Update timestamps based on status
        if (_newStatus == EquipmentStatus.Registered) {
            equipment.registeredAt = block.timestamp;
        } else if (_newStatus == EquipmentStatus.Pending) {
            equipment.pendingAt = block.timestamp;
        } else if (_newStatus == EquipmentStatus.Certified) {
            equipment.certifiedAt = block.timestamp;
        } else if (_newStatus == EquipmentStatus.Rejected) {
            equipment.rejectedAt = block.timestamp;
        } else if (_newStatus == EquipmentStatus.Deprecated) {
            equipment.deprecatedAt = block.timestamp;
        }
        
        emit EquipmentStatusChanged(
            _equipmentId,
            oldStatus,
            _newStatus,
            _updater,
            block.timestamp
        );
        
        emit EquipmentStepUpdated(
            _equipmentId,
            oldStep,
            _newStep,
            _updater,
            block.timestamp
        );
    }

    /**
     * @notice Checks compatibility with various interfaces
     * @param interfaceId Interface ID to check
     * @return bool True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Override to prevent any equipment transfer (Soul Bound Token)
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        // We allow minting
        if (from == address(0)) {
            return super._update(to, tokenId, auth);
        }
        
        // Otherwise, prevent any transfer or burn
        revert SoulboundTokenNonTransferableAndNotBurnable(tokenId);
    }

    /**
     * @dev Override to prevent any transfer approval
     */
    function approve(address, uint256 tokenId) public virtual override {
        revert SoulboundTokenNonTransferableAndNotBurnable(tokenId);
    }

    /**
     * @dev Override to prevent any global approval
     */
    function setApprovalForAll(address, bool) public virtual override {
        revert SoulboundTokenNonTransferableAndNotBurnable(0);
    }

    /**
     * @notice Converts a bytes32 to a hexadecimal string
     * @param _bytes32 bytes32 value to convert
     * @return Hexadecimal string representation of the bytes32 value
     */
    function bytes32ToHexString(bytes32 _bytes32) public pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory hexString = new bytes(66); // "0x" + 64 characters
        
        hexString[0] = "0";
        hexString[1] = "x";
        
        for (uint256 i = 0; i < 32; i++) {
            uint8 value = uint8(_bytes32[i]);
            hexString[2 + i * 2] = hexChars[uint8(value >> 4)];
            hexString[3 + i * 2] = hexChars[uint8(value & 0x0f)];
        }
        
        return string(hexString);
    }

    /**
     * @notice Gets all plant IDs registered in the contract
     * @return Array of all plant IDs
     */
    function getAllPlantIds() external view returns (uint256[] memory) {
        return _allPlantIds;
    }

    /**
     * @notice Gets all actor IDs registered in the contract
     * @return Array of all actor IDs
     */
    function getAllActorIds() external view returns (uint256[] memory) {
        return _allActorIds;
    }

    /**
     * @notice Gets the equipment IDs associated with a specific plant
     * @param _plantId The ID of the plant
     * @return Array of equipment IDs
     */
    function getPlantEquipmentIds(uint256 _plantId) external view returns (uint256[] memory) {
        return _plantToEquipments[_plantId];
    }

    /**
     * @notice Gets an actor by ID
     * @param _actorId Actor ID
     * @return The actor data
     */
    function getActor(uint256 _actorId) external view returns (Actor memory) {
        return _actors[_actorId];
    }

    /**
     * @notice Creates a new actor
     * @param _name Actor name
     * @param _actorAddress Actor address
     * @param _role Actor role
     * @param _plantId Plant ID (0 si non associé à une centrale spécifique)
     * @return The actor ID
     */
    function createActor(
        string memory _name,
        address _actorAddress,
        bytes32 _role,
        uint256 _plantId
    ) external returns (uint256) {
        uint256 actorId = nextActorId++;
        
        Actor memory newActor = Actor({
            id: actorId,
            name: _name,
            actorAddress: _actorAddress,
            role: _role,
            registeredAt: block.timestamp,
            plantId: _plantId
        });
        
        _actors[actorId] = newActor;
        _allActorIds.push(actorId);
        
        return actorId;
    }

    function grantRoleWithCaller(bytes32 role, address account, address caller) external {
        require(hasRole(getRoleAdmin(role), caller), "Caller doesn't have admin role");
        _grantRole(role, account);
    }

    function revokeRoleWithCaller(bytes32 role, address account, address caller) external {
        require(hasRole(getRoleAdmin(role), caller), "Caller doesn't have admin role");
        _revokeRole(role, account);
    }
} 