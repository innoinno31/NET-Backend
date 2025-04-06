// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title NuclearCertification
 * @author Franck
 * @notice Contract managing the certification of nuclear equipment as non-transferable NFTs
 * @dev Implements ERC721 with SBT restrictions and a role management system
 */
contract NuclearCertification is AccessControl, ERC721 {
    // Define roles
    bytes32 public constant PLANT_OPERATOR_ADMIN = keccak256("PLANT_OPERATOR_ADMIN");
    bytes32 public constant PLANT_OPERATOR = keccak256("PLANT_OPERATOR");
    bytes32 public constant MANUFACTURER = keccak256("MANUFACTURER");
    bytes32 public constant LABORATORY = keccak256("LABORATORY");
    bytes32 public constant REGULATORY_AUTHORITY = keccak256("REGULATORY_AUTHORITY");
    bytes32 public constant CERTIFICATION_OFFICER = keccak256("CERTIFICATION_OFFICER");

    /** Id Counters */
    uint256 private nextEquipmentId;
    uint256 private nextPlantId;
    uint256 private nextDocumentId;
    uint256 private nextActorId;

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

    /** Mappings */
    mapping(address => uint256[]) public actorToPlants;

    mapping(uint256 => Plant) public plants;
    mapping(uint256 => Equipment) public equipments;
    mapping(uint256 => Document) public documents;

    mapping(uint256 => uint256) public equipmentToPlant;
    mapping(uint256 => uint256[]) public plantToEquipments;

    mapping(uint256 => uint256) public documentToEquipment;
    mapping(uint256 => uint256[]) public equipmentToDocuments;

    mapping(uint256 => CertificationData) public equipmentCertifications;
    
    mapping(DocumentType => mapping(bytes32 => bool)) public documentAccessByRole;

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

    /** Events for role management */
    event RoleAssigned(address indexed actor, bytes32 indexed role, address indexed assignedBy, uint256 timestamp);
    event RoleRevoked(address indexed actor, bytes32 indexed role, address indexed revokedBy, uint256 timestamp);

    /** Events for detailed document tracking */
    event DocumentVerified(uint256 indexed documentId, uint256 indexed equipmentId, address indexed verifier, uint256 timestamp);
    event DocumentRejected(uint256 indexed documentId, uint256 indexed equipmentId, address indexed rejector, string reason, uint256 timestamp);

    /** Events for complete certification tracking */
    event CertificationStarted(uint256 indexed equipmentId, address indexed initiator, uint256 timestamp);
    event CertificationCompleted(uint256 indexed equipmentId, address indexed certifier, bytes32 hashGlobal, uint256 timestamp);
    event CertificationRejected(uint256 indexed equipmentId, address indexed rejector, string reason, uint256 timestamp);

    /** Event for integrity verification */
    event IntegrityVerified(uint256 indexed equipmentId, bytes32 hashGlobal, bool isValid, address verifier, uint256 timestamp);

    /** Custom errors */
    // Equipment
    error EquipmentNotFound(uint256 equipmentId);
    error EquipmentAlreadyExists(uint256 equipmentId);
    error EquipmentNotPending(uint256 equipmentId);
    error EquipmentAlreadyRejected(uint256 equipmentId);
    error EquipmentDeprecated(uint256 equipmentId);
    error EquipmentAlreadyCertified(uint256 equipmentId);
    error EquipmentNotUnderReview(uint256 equipmentId);

    // Document
    error DocumentNotFound(uint256 documentId);
    error DocumentAlreadyExists(uint256 documentId);
    error DocumentNotPending(uint256 documentId);
    error DocumentAlreadyRejected(uint256 documentId);
    error DocumentDeprecated(uint256 documentId);
    error DocumentTypeNotExpected(uint256 equipmentId, DocumentType docType);
    error DocumentSubmissionNotAllowed(uint256 equipmentId);
    error MissingRequiredDocuments(uint256 equipmentId);

    // Actors Roles
    error UnauthorizedRole(address caller);
    error RoleAlreadyAssigned(address actor, bytes32 role);
    error RoleNotAllowedForAction(bytes32 role);
    error ActorNotRegistered(address actor);
    error UnauthorizedDocumentAccess(uint256 documentId, address caller);
    error SoulboundTokenNonTransferableAndNotBurnable(uint256 tokenId);

    // Generic
    error InvalidOperation(string message);
    error PlantNotFound(uint256 plantId);
    error InvalidInput(string reason);
    error ActionNotAllowedInCurrentStep(uint256 equipmentId, CertificationSteps step);


    /**
     * @notice Contract constructor
     * @dev Sets the deployer as default admin and initializes the ERC721 contract
     */
    constructor() ERC721("Nuclear Equipment Traceability", "NET") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // 1. Safety Authority - full access to all documents
        documentAccessByRole[DocumentType.Certification][REGULATORY_AUTHORITY] = true;
        documentAccessByRole[DocumentType.LabReport][REGULATORY_AUTHORITY] = true;
        documentAccessByRole[DocumentType.TechFile][REGULATORY_AUTHORITY] = true;
        documentAccessByRole[DocumentType.Compliance][REGULATORY_AUTHORITY] = true;
        documentAccessByRole[DocumentType.RegulatoryReview][REGULATORY_AUTHORITY] = true;
        
        // 2. Operator - full access (equipment owner)
        documentAccessByRole[DocumentType.Certification][PLANT_OPERATOR] = true;
        documentAccessByRole[DocumentType.LabReport][PLANT_OPERATOR] = true;
        documentAccessByRole[DocumentType.TechFile][PLANT_OPERATOR] = true;
        documentAccessByRole[DocumentType.Compliance][PLANT_OPERATOR] = true;
        documentAccessByRole[DocumentType.RegulatoryReview][PLANT_OPERATOR] = true;
        
        // 3. Certification Officer (Bureau Veritas) - full access for certification
        documentAccessByRole[DocumentType.Certification][CERTIFICATION_OFFICER] = true;
        documentAccessByRole[DocumentType.LabReport][CERTIFICATION_OFFICER] = true;
        documentAccessByRole[DocumentType.TechFile][CERTIFICATION_OFFICER] = true;
        documentAccessByRole[DocumentType.Compliance][CERTIFICATION_OFFICER] = true;
        documentAccessByRole[DocumentType.RegulatoryReview][CERTIFICATION_OFFICER] = true;
        
        // 4. Manufacturer - only tech files and final certification
        documentAccessByRole[DocumentType.Certification][MANUFACTURER] = true;
        documentAccessByRole[DocumentType.TechFile][MANUFACTURER] = true;
        
        // 5. Laboratory  - only lab reports and final certification
        documentAccessByRole[DocumentType.Certification][LABORATORY] = true;
        documentAccessByRole[DocumentType.LabReport][LABORATORY] = true;
    }


    /** Modifiers */
    /**
     * @notice Verifies that the equipment is not already certified or under review
     * @dev Modifier to prevent modifications after final certification or during review
     * @param _equipmentId ID of the equipment to check
     */
    modifier notCertifiedOrUnderReview(uint256 _equipmentId) {
        Equipment memory equipment = equipments[_equipmentId];
        
        // Block modifications if equipment is under review except for regulatory authority
        if (equipment.currentStep == CertificationSteps.UnderReview) {
            if (!hasRole(REGULATORY_AUTHORITY, msg.sender)) {
                revert ActionNotAllowedInCurrentStep(_equipmentId, CertificationSteps.UnderReview);
            }
        }
        
        // Block modifications if equipment is certified except for regulatory authority and plant operator
        if (equipment.status == EquipmentStatus.Certified) {
            if (!hasRole(REGULATORY_AUTHORITY, msg.sender) && !hasRole(PLANT_OPERATOR, msg.sender)) {
                revert EquipmentAlreadyCertified(_equipmentId);
            }
        }       
        _;
    }

    /**
     * @notice Verifies that the equipment is not deprecated
     * @dev Modifier to prevent modifications with deprecated equipment
     * @param _equipmentId ID of the equipment to check
     */
    modifier notDeprecated(uint256 _equipmentId) {
        Equipment memory equipment = equipments[_equipmentId];
        
        if (equipment.status == EquipmentStatus.Deprecated) {
            revert EquipmentDeprecated(_equipmentId);
        }      
        _;
    }

    /**
     * @notice Verifies that the sender is authorized to submit a document
     * @dev Modifier to prevent document submissions by unauthorized roles
     */
    modifier authorizedSubmitter() {
        require(
            hasRole(MANUFACTURER, msg.sender) ||
            hasRole(LABORATORY, msg.sender) ||
            hasRole(PLANT_OPERATOR, msg.sender) ||
            hasRole(REGULATORY_AUTHORITY, msg.sender),
            "Unauthorized role"
        );
        _;
    }

    /**
     * @notice Verifies that the sender is authorized to access a specific document
     * @param _documentId ID of the document to check access for
     */
    modifier canAccessDocument(uint256 _documentId) {
        if (
            !hasRole(PLANT_OPERATOR, msg.sender) && 
            !hasRole(REGULATORY_AUTHORITY, msg.sender) && 
            !hasRole(CERTIFICATION_OFFICER, msg.sender)
        ) {
            Document memory doc = documents[_documentId];
            uint256 equipmentId = documentToEquipment[_documentId];

            // Manufacturers can only see their own documents + certification
            if (hasRole(MANUFACTURER, msg.sender)) {
                if (doc.submitter != msg.sender && doc.docType != DocumentType.Certification) {
                    revert UnauthorizedRole(msg.sender);
                }
            } 
            // Labs can see their own documents + tech files + certification
            else if (hasRole(LABORATORY, msg.sender)) {
                if (
                    doc.submitter != msg.sender && 
                    doc.docType != DocumentType.TechFile && 
                    doc.docType != DocumentType.Certification
                ) {
                    revert UnauthorizedRole(msg.sender);
                }
            } else {
                revert UnauthorizedRole(msg.sender);
            }
        }
        _;
    }

    /**
     * @notice Verifies that the sender is authorized to access a specific document
     * @param _documentId ID of the document to check access for
     */
    modifier onlyDocumentAuthorized(uint256 _documentId) {
        if (!canViewDocument(_documentId, msg.sender)) {
            revert UnauthorizedDocumentAccess(_documentId, msg.sender);
        }
        _;
    }

    /////////////////////////////////
    /////// Register Roles /////////
    /////////////////////////////////

    /**
     * @notice Registers a plant operator
     * @param _address Address of the operator to register
     */
    function registerPlantOperator(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (hasRole(PLANT_OPERATOR_ADMIN, _address)) {
            revert RoleAlreadyAssigned(_address, PLANT_OPERATOR_ADMIN);
        }
        if (hasRole(PLANT_OPERATOR, _address)) {
            revert RoleAlreadyAssigned(_address, PLANT_OPERATOR);
        }

        _grantRole(PLANT_OPERATOR_ADMIN, _address);
        _grantRole(PLANT_OPERATOR, _address);
        
        emit RoleAssigned(_address, PLANT_OPERATOR_ADMIN, msg.sender, block.timestamp);
        emit RoleAssigned(_address, PLANT_OPERATOR, msg.sender, block.timestamp);
    }

    /**
     * @notice Registers a manufacturer
     * @param _address Address of the manufacturer to register
     */
    function registerManufacturer(address _address) external onlyRole(PLANT_OPERATOR_ADMIN) {
        if (hasRole(MANUFACTURER, _address)) {
            revert RoleAlreadyAssigned(_address, MANUFACTURER);
        }

        _grantRole(MANUFACTURER, _address);

        emit RoleAssigned(_address, MANUFACTURER, msg.sender, block.timestamp);
    }

    /**
     * @notice Registers a laboratory
     * @param _address Address of the laboratory to register
     */
    function registerLaboratory(address _address) external onlyRole(PLANT_OPERATOR_ADMIN) {
        if (hasRole(LABORATORY, _address)) {
            revert RoleAlreadyAssigned(_address, LABORATORY);
        }

        _grantRole(LABORATORY, _address);

        emit RoleAssigned(_address, LABORATORY, msg.sender, block.timestamp);
    }

    /**
     * @notice Registers a regulatory authority
     * @param _address Address of the authority to register
     */
    function registerRegulatoryAuthority(address _address) external onlyRole(PLANT_OPERATOR_ADMIN) {
        if (hasRole(REGULATORY_AUTHORITY, _address)) {
            revert RoleAlreadyAssigned(_address, REGULATORY_AUTHORITY);
        }

        _grantRole(REGULATORY_AUTHORITY, _address);

        emit RoleAssigned(_address, REGULATORY_AUTHORITY, msg.sender, block.timestamp);
    }

    /**
     * @notice Registers a certification officer
     * @param _address Address of the officer to register
     */
    function registerCertificationOfficer(address _address) external onlyRole(PLANT_OPERATOR_ADMIN) {
        if (hasRole(CERTIFICATION_OFFICER, _address)) {
            revert RoleAlreadyAssigned(_address, CERTIFICATION_OFFICER);
        }

        _grantRole(CERTIFICATION_OFFICER, _address);

        emit RoleAssigned(_address, CERTIFICATION_OFFICER, msg.sender, block.timestamp);
    }

    /////////////////////////////////
    /////// Getters ////////////////
    /////////////////////////////////

    function _getNextPlantId() internal returns (uint256) {
        return nextPlantId++;
    }

    function _getNextEquipmentId() internal returns (uint256) {
        return nextEquipmentId++;
    }

    function _getNextDocumentId() internal returns (uint256) {
        return nextDocumentId++;
    }

    function _getNextActorId() internal returns (uint256) {
        return nextActorId++;
    }

    /**
     * @notice Gets all documents linked to an equipment
     * @param _equipmentId The equipment identifier
     * @return An array of document identifiers
     */
    function getEquipmentDocuments(uint256 _equipmentId) public view returns (uint256[] memory) {
        return equipmentToDocuments[_equipmentId];
    }

    /**
     * @notice Gets the IPFS hashes of all documents linked to an equipment
     * @param _equipmentId The equipment identifier
     * @return An array of IPFS hashes
     */
    function getEquipmentDocumentHashes(uint256 _equipmentId) public view returns (string[] memory) {
        uint256[] memory docIds = equipmentToDocuments[_equipmentId];
        string[] memory hashes = new string[](docIds.length);
        
        for (uint256 i = 0; i < docIds.length; i++) {
            hashes[i] = documents[docIds[i]].ipfsHash;
        }
        
        return hashes;
    }

    /**
     * @notice Verifies the integrity of documents for a certified equipment
     * @param _equipmentId The equipment identifier
     * @param _calculatedHash The global hash calculated off-chain
     * @return bool True if the hash matches, false otherwise
     */
    function verifyEquipmentIntegrity(uint256 _equipmentId, bytes32 _calculatedHash) public view returns (bool)
    {
        if (equipments[_equipmentId].id == 0) {
            revert EquipmentNotFound(_equipmentId);
        }
        
        // Check if the equipment is certified or deprecated
        if (equipments[_equipmentId].status != EquipmentStatus.Certified &&
            equipments[_equipmentId].status != EquipmentStatus.Deprecated) {
            revert ActionNotAllowedInCurrentStep(_equipmentId, equipments[_equipmentId].currentStep);
        }
        
        bool isValid = equipmentCertifications[_equipmentId].hashGlobal == _calculatedHash;
        
        return isValid;
    }

    function checkAndLogEquipmentIntegrity(uint256 _equipmentId, bytes32 _calculatedHash) external returns (bool)
    {
        bool isValid = verifyEquipmentIntegrity(_equipmentId, _calculatedHash);
        
        emit IntegrityVerified(_equipmentId, _calculatedHash, isValid, msg.sender, block.timestamp);
        
        return isValid;
    }

    /**
     * @notice Checks if the caller has access to a specific document
     * @param _documentId ID of the document to check
     * @return true if access is allowed, false otherwise
     */
    function isDocumentAccessible(uint256 _documentId) public view returns (bool) {
        if (documents[_documentId].id == 0) {
            return false;
        }

        // Plant Operators, Regulatory Authorities, and Certification Officers can see all documents
        if (
            hasRole(PLANT_OPERATOR, msg.sender) || 
            hasRole(REGULATORY_AUTHORITY, msg.sender) || 
            hasRole(CERTIFICATION_OFFICER, msg.sender)
        ) {
            return true;
        }

        Document memory doc = documents[_documentId];

        // Manufacturers can only see their own documents + certification
        if (hasRole(MANUFACTURER, msg.sender)) {
            return doc.submitter == msg.sender || doc.docType == DocumentType.Certification;
        } 
        // Labs can see their own documents + tech files + certification
        else if (hasRole(LABORATORY, msg.sender)) {
            return 
                doc.submitter == msg.sender || 
                doc.docType == DocumentType.TechFile || 
                doc.docType == DocumentType.Certification;
        }

        return false;
    }

    /**
     * @notice Checks if a user can access a document
     * @param _documentId ID of the document to check
     * @param _viewer Address of the user who wants to view the document
     * @return bool True if access is allowed, false otherwise
     */
    function canViewDocument(uint256 _documentId, address _viewer) public view returns (bool) {
        Document memory doc = documents[_documentId];
        
        // TODO: check if the document exists ? or should we revert and custom error ?
        if (doc.id == 0) {
            return false;
        }
        
        // The submitter of a document can always access it
        if (doc.submitter == _viewer) {
            return true;
        }
        
        // Check access rules based on roles
        bytes32 role;
        
        if (hasRole(PLANT_OPERATOR, _viewer)) role = PLANT_OPERATOR;
        else if (hasRole(MANUFACTURER, _viewer)) role = MANUFACTURER;
        else if (hasRole(LABORATORY, _viewer)) role = LABORATORY;
        else if (hasRole(REGULATORY_AUTHORITY, _viewer)) role = REGULATORY_AUTHORITY;
        else if (hasRole(CERTIFICATION_OFFICER, _viewer)) role = CERTIFICATION_OFFICER;
        else return false;
        
        return documentAccessByRole[doc.docType][role];
    }
    
    /**
     * @notice Retrieves a document if the user has access to it
     * @param _documentId ID of the document to retrieve
     * @return The requested document
     */
    function getDocument(uint256 _documentId) external view onlyDocumentAuthorized(_documentId) returns (Document memory) {
        return documents[_documentId];
    }
    
    /**
     * @notice Retrieves all documents of an equipment that the user has access to
     * @param _equipmentId ID of the equipment
     * @return The documents accessible by the user
     */
    function getAccessibleDocuments(uint256 _equipmentId) external view returns (Document[] memory) {
        if (equipments[_equipmentId].id == 0) {
            revert EquipmentNotFound(_equipmentId);
        }
        
        uint256[] memory docIds = equipmentToDocuments[_equipmentId];
        uint256 accessibleCount = 0;
        
        // We limit the number of documents to 100 to avoid gas issues
        for (uint256 i = 0; i < docIds.length && i < 100; i++) {
            if (canViewDocument(docIds[i], msg.sender)) {
                accessibleCount++;
            }
        }
        
        Document[] memory accessibleDocs = new Document[](accessibleCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < docIds.length && index < accessibleCount; i++) {
            if (canViewDocument(docIds[i], msg.sender)) {
                accessibleDocs[index++] = documents[docIds[i]];
            }
        }
        
        return accessibleDocs;
    }

    /////////////////////////////////
    /////// FUNCTIONS //////////////
    /////////////////////////////////

    /**
     * @notice Registers a new plant
     * @param _name Plant name
     * @param _description Plant description
     * @param _location Plant location
     * @param _isActive Plant activity status
     */
    function registerPlant(
        string memory _name,
        string memory _description,
        string memory _location,
        bool _isActive
    ) external onlyRole(PLANT_OPERATOR) {
        uint256 plantId = _getNextPlantId();

        Plant memory newPlant = Plant({
            id: plantId,
            name: _name,
            description: _description,
            location: _location,
            registeredAt: block.timestamp,
            isActive: _isActive
        });

        // Data storage
        plants[plantId] = newPlant;
        actorToPlants[msg.sender].push(plantId);

        // Event emission
        emit PlantRegistered(
            plantId,
            _name,
            msg.sender,
            block.timestamp
        );
    }

    /**
     * @notice Registers a new equipment
     * @param _name Equipment name
     * @param _description Equipment description
     * @param _plantId ID of the plant where the equipment is installed
     */
    function registerEquipment(
        string memory _name,
        string memory _description,
        uint256 _plantId
    ) external onlyRole(PLANT_OPERATOR) {
        if (bytes(_name).length == 0) {
            revert InvalidInput("Name cannot be empty");
        }
        
        if (plants[_plantId].id == 0) {
            revert PlantNotFound(_plantId);
        }
        
        uint256[] memory plantEquipments = plantToEquipments[_plantId];
        
        for (uint256 i = 0; i < plantEquipments.length; i++) {
            if (keccak256(bytes(equipments[plantEquipments[i]].name)) == keccak256(bytes(_name))) {
                revert InvalidInput("Equipment with this name already exists in the plant");
            }
        }
        
        uint256 equipmentId = _getNextEquipmentId();
        
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
        
        // Data storage
        equipments[equipmentId] = newEquipment;
        equipmentToPlant[equipmentId] = _plantId;
        plantToEquipments[_plantId].push(equipmentId);
        
        // NFT minting
        _safeMint(msg.sender, equipmentId);
        
        emit EquipmentRegistered(equipmentId, _name, msg.sender, block.timestamp);
    }

    /**
     * @notice Registers a new document linked to an equipment
     * @param _equipmentId ID of the concerned equipment
     * @param _docType Document type
     * @param _name Document name
     * @param _description Document description
     * @param _ipfsHash IPFS hash of the document
     */
    function registerDocument(
        uint256 _equipmentId,
        DocumentType _docType,
        string memory _name,
        string memory _description,
        string memory _ipfsHash
    ) external authorizedSubmitter notCertifiedOrUnderReview(_equipmentId) notDeprecated(_equipmentId) {
        if (equipments[_equipmentId].id == 0) {
            revert EquipmentNotFound(_equipmentId);
        }
        
        if (bytes(_name).length == 0) {
            revert InvalidInput("Name cannot be empty");
        }
        
        if (bytes(_description).length == 0) {
            revert InvalidInput("Description cannot be empty");
        }
        
        if (bytes(_ipfsHash).length == 0) {
            revert InvalidInput("IPFS hash cannot be empty");
        }
        
        // Check if a document with the same IPFS hash already exists
        uint256[] memory docs = equipmentToDocuments[_equipmentId];
        
        for (uint256 i = 0; i < docs.length; i++) {
            if (keccak256(bytes(documents[docs[i]].ipfsHash)) == keccak256(bytes(_ipfsHash))) {
                revert DocumentAlreadyExists(docs[i]);
            }
        }
        
        uint256 documentId = _getNextDocumentId();

        Document memory newDocument = Document({
            id: documentId,
            name: _name,
            description: _description,
            docType: _docType,
            status: DocumentStatus.Submitted,
            submitter: msg.sender,
            submittedAt: block.timestamp,
            verifiedAt: 0,
            rejectedAt: 0,
            pendingAt: 0,
            deprecatedAt: 0,
            ipfsHash: _ipfsHash
        });

        documents[documentId] = newDocument;
        
        // Add document to equipment's document list
        equipmentToDocuments[_equipmentId].push(documentId);
        
        // Update the documentToEquipment mapping
        documentToEquipment[documentId] = _equipmentId;

        emit DocumentSubmitted(documentId, _equipmentId, _docType, msg.sender, block.timestamp);
    }

    /**
     * @notice Gets all verified documents for an equipment
     * @param _equipmentId Equipment ID
     * @return An array of verified documents
     */
    function getVerifiedDocuments(uint256 _equipmentId) external view returns (Document[] memory) {
        uint256[] memory docIds = equipmentToDocuments[_equipmentId];
        uint256 verifiedCount;

        for (uint256 i = 0; i < docIds.length; i++) {
            if (documents[docIds[i]].status == DocumentStatus.Verified) {
                verifiedCount++;
            }
        }

        Document[] memory verifiedDocs = new Document[](verifiedCount);
        uint256 index = 0;

        for (uint256 i = 0; i < docIds.length; i++) {
            if (documents[docIds[i]].status == DocumentStatus.Verified) {
                verifiedDocs[index++] = documents[docIds[i]];
            }
        }

        return verifiedDocs;
    }


    /**
     * @notice Marks an equipment as ready for review
     * @param _equipmentId Equipment ID
     */
    function equipmentIsReadyForReview(uint256 _equipmentId) external onlyRole(PLANT_OPERATOR) notCertifiedOrUnderReview(_equipmentId) notDeprecated(_equipmentId) {
        Equipment storage equipment = equipments[_equipmentId];
        
        if (equipment.status != EquipmentStatus.Pending) {
            revert EquipmentNotPending(_equipmentId);
        }

        CertificationSteps previousStep = equipment.currentStep;
        equipment.currentStep = CertificationSteps.UnderReview;

        emit EquipmentStepUpdated(
            _equipmentId, 
            previousStep,
            equipment.currentStep,
            msg.sender, 
            block.timestamp
        );
    }

    /**
     * @notice Converts a bytes32 to a hexadecimal string
     * @param _bytes32 bytes32 value to convert
     * @return Hexadecimal string representation of the bytes32 value
     */
    function bytes32ToHexString(bytes32 _bytes32) internal pure returns (string memory) {
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
     * @notice Certifies an equipment after verification
     * @param _equipmentId Equipment ID
     * @param _comments Certification comments
     * @param _hashGlobal Global hash calculated off-chain of all documents
     */
    function finalCertification(uint256 _equipmentId, string memory _comments, bytes32 _hashGlobal) external onlyRole(REGULATORY_AUTHORITY) {
        Equipment storage equipment = equipments[_equipmentId];
        
        if (equipment.currentStep != CertificationSteps.UnderReview) {
            revert EquipmentNotUnderReview(_equipmentId);
        }

        // Store the global hash calculated off-chain
        equipment.finalCertificationHash = bytes32ToHexString(_hashGlobal);
        
        // Register certification data
        equipmentCertifications[_equipmentId] = CertificationData({
            hashGlobal: _hashGlobal,
            timestamp: block.timestamp,
            certifier: msg.sender
        });

        // Status update
        equipment.currentStep = CertificationSteps.Certified;
        equipment.status = EquipmentStatus.Certified;
        equipment.certifiedAt = block.timestamp;

        emit EquipmentStepUpdated(
            _equipmentId, 
            CertificationSteps.UnderReview,
            CertificationSteps.Certified,
            msg.sender, 
            block.timestamp
        );

        emit HashGlobalGenerated(
            _equipmentId,
            _hashGlobal,
            msg.sender,
            block.timestamp
        );

        // Create final certification document
        uint256 documentId = _getNextDocumentId();
        documents[documentId] = Document({
            id: documentId,
            name: string(abi.encodePacked("Final Certification - ", equipment.name)),
            description: _comments,
            docType: DocumentType.Certification,
            status: DocumentStatus.Verified,
            submitter: msg.sender,
            submittedAt: block.timestamp,
            verifiedAt: block.timestamp,
            rejectedAt: 0,
            pendingAt: 0,
            deprecatedAt: 0,
            ipfsHash: bytes32ToHexString(_hashGlobal)
        });

        equipmentToDocuments[_equipmentId].push(documentId);
        documentToEquipment[documentId] = _equipmentId;

        emit DocumentSubmitted(documentId, _equipmentId, DocumentType.Certification, msg.sender, block.timestamp);

        emit CertificationCompleted(_equipmentId, msg.sender, _hashGlobal, block.timestamp);
    }

    /**
     * @notice Rejects an equipment certification
     * @param _equipmentId Equipment ID
     * @param _comments Rejection comments
     */
    function rejectEquipment(uint256 _equipmentId, string memory _comments) external onlyRole(REGULATORY_AUTHORITY) {
        Equipment storage equipment = equipments[_equipmentId];
        
        if (equipment.currentStep != CertificationSteps.UnderReview) {
            revert EquipmentNotUnderReview(_equipmentId);
        }
        
        if (equipment.status == EquipmentStatus.Rejected) {
            revert EquipmentAlreadyRejected(_equipmentId);
        }
        
        // Create rejection document with comments
        uint256 documentId = _getNextDocumentId();
        Document memory rejectionDoc = Document({
            id: documentId,
            name: string(abi.encodePacked("Rejection - ", equipment.name)),
            description: _comments,
            docType: DocumentType.RegulatoryReview,
            status: DocumentStatus.Verified,
            submitter: msg.sender,
            submittedAt: block.timestamp,
            verifiedAt: block.timestamp,
            rejectedAt: block.timestamp,
            pendingAt: 0,
            deprecatedAt: 0,
            ipfsHash: ""
        });
        
        documents[documentId] = rejectionDoc;
        equipmentToDocuments[_equipmentId].push(documentId);
        documentToEquipment[documentId] = _equipmentId;

        equipment.currentStep = CertificationSteps.Rejected;
        equipment.status = EquipmentStatus.Rejected;
        equipment.rejectedAt = block.timestamp;

        emit EquipmentStepUpdated(
            _equipmentId, 
            CertificationSteps.UnderReview,
            CertificationSteps.Rejected,
            msg.sender, 
            block.timestamp
        );
        
        emit DocumentSubmitted(documentId, _equipmentId, DocumentType.RegulatoryReview, msg.sender, block.timestamp);

        emit CertificationRejected(_equipmentId, msg.sender, _comments, block.timestamp);
    }

    /**
     * @notice Deprecates a certified equipment by regulatory authority
     * @param _equipmentId Equipment ID
     * @param _reason Reason for deprecation
     */
    function deprecateEquipment(uint256 _equipmentId, string memory _reason) 
        external 
        onlyRole(REGULATORY_AUTHORITY) 
    {
        Equipment storage equipment = equipments[_equipmentId];
        
        if (equipment.id == 0) {
            revert EquipmentNotFound(_equipmentId);
        }
        
        // Check that it's not already deprecated
        if (equipment.status == EquipmentStatus.Deprecated) {
            revert InvalidOperation("Equipment is already deprecated");
        }
        
        EquipmentStatus oldStatus = equipment.status;
        equipment.status = EquipmentStatus.Deprecated;
        equipment.deprecatedAt = block.timestamp;
        
        // Create a document for tracking the deprecation
        uint256 documentId = _getNextDocumentId();
        
        Document memory deprecationDoc = Document({
            id: documentId,
            name: string(abi.encodePacked("Authority Deprecation - ", equipment.name)),
            description: _reason,
            docType: DocumentType.RegulatoryReview,
            status: DocumentStatus.Verified,
            submitter: msg.sender,
            submittedAt: block.timestamp,
            verifiedAt: block.timestamp,
            rejectedAt: 0,
            pendingAt: 0,
            deprecatedAt: block.timestamp,
            ipfsHash: ""
        });
        
        documents[documentId] = deprecationDoc;
        equipmentToDocuments[_equipmentId].push(documentId);
        documentToEquipment[documentId] = _equipmentId;
        
        emit EquipmentStatusChanged(
            _equipmentId,
            oldStatus,
            EquipmentStatus.Deprecated,
            msg.sender,
            block.timestamp
        );
        
        emit DocumentSubmitted(documentId, _equipmentId, DocumentType.RegulatoryReview, msg.sender, block.timestamp);
    }

    /**
     * @notice Deprecates a certified equipment by the plant operator
     * @param _equipmentId Equipment ID
     * @param _reason Reason for deprecation
     */
    function operatorDeprecateEquipment(uint256 _equipmentId, string memory _reason) 
        external 
        onlyRole(PLANT_OPERATOR) 
    {
        Equipment storage equipment = equipments[_equipmentId];
        
        if (equipment.id == 0) {
            revert EquipmentNotFound(_equipmentId);
        }
        
        // Check that it's not already deprecated
        if (equipment.status == EquipmentStatus.Deprecated) {
            revert InvalidOperation("Equipment is already deprecated");
        }
        
        EquipmentStatus oldStatus = equipment.status;
        equipment.status = EquipmentStatus.Deprecated;
        equipment.deprecatedAt = block.timestamp;
        
        // Create a document for tracking the deprecation
        uint256 documentId = _getNextDocumentId();
        Document memory deprecationDoc = Document({
            id: documentId,
            name: string(abi.encodePacked("Operator Deprecation - ", equipment.name)),
            description: _reason,
            docType: DocumentType.RegulatoryReview,
            status: DocumentStatus.Verified,
            submitter: msg.sender,
            submittedAt: block.timestamp,
            verifiedAt: block.timestamp,
            rejectedAt: 0,
            pendingAt: 0,
            deprecatedAt: block.timestamp,
            ipfsHash: ""
        });
        
        documents[documentId] = deprecationDoc;
        equipmentToDocuments[_equipmentId].push(documentId);
        documentToEquipment[documentId] = _equipmentId;
        
        emit EquipmentStatusChanged(
            _equipmentId,
            oldStatus,
            EquipmentStatus.Deprecated,
            msg.sender,
            block.timestamp
        );
        
        emit DocumentSubmitted(documentId, _equipmentId, DocumentType.RegulatoryReview, msg.sender, block.timestamp);
    }

    /**
     * @notice Verify document integrity and log the result as an event
     * @param _documentId ID of the document to verify
     * @param _providedHash IPFS hash to verify against the stored one
     * @return bool True if hashes match, false otherwise
     */
    function verifyAndLogDocumentIntegrity(uint256 _documentId, string memory _providedHash) 
        external 
        returns (bool) 
    {
        if (documents[_documentId].id == 0) {
            revert DocumentNotFound(_documentId);
        }
        
        uint256 equipmentId = documentToEquipment[_documentId];
        bool isValid = keccak256(bytes(documents[_documentId].ipfsHash)) == keccak256(bytes(_providedHash));
        
        // Convert string to bytes32 for the event
        bytes32 hashBytes = keccak256(bytes(_providedHash));
        
        emit IntegrityVerified(
            equipmentId,
            hashBytes,
            isValid,
            msg.sender,
            block.timestamp
        );
        
        return isValid;
    }

    /**
     * @notice Verify all documents of a certified equipment for integrity
     * @param _equipmentId ID of the equipment
     * @param _documentHashes Array of IPFS hashes in the same order as the documents
     * @return bool True if all hashes match, false otherwise
     */
    function verifyAllDocumentsIntegrity(uint256 _equipmentId, string[] memory _documentHashes) 
        external 
        view 
        returns (bool) 
    {
        if (equipments[_equipmentId].id == 0) {
            revert EquipmentNotFound(_equipmentId);
        }
        
        if (equipments[_equipmentId].status != EquipmentStatus.Certified) {
            revert ActionNotAllowedInCurrentStep(_equipmentId, equipments[_equipmentId].currentStep);
        }
        
        uint256[] memory docIds = equipmentToDocuments[_equipmentId];
        
        if (docIds.length != _documentHashes.length) {
            return false;
        }
        
        for (uint256 i = 0; i < docIds.length; i++) {
            if (keccak256(bytes(documents[docIds[i]].ipfsHash)) != keccak256(bytes(_documentHashes[i]))) {
                return false;
            }
        }
        
        return true;
    }

    /**
     * @notice Updates an equipment status
     * @param _equipmentId Equipment ID
     * @param _newStatus New status
     */
    function updateEquipmentStatus(uint256 _equipmentId, EquipmentStatus _newStatus) 
        external 
        onlyRole(CERTIFICATION_OFFICER)
        notCertifiedOrUnderReview(_equipmentId)
        notDeprecated(_equipmentId)
    {
        Equipment storage equipment = equipments[_equipmentId];
        
        if (equipment.id == 0) {
            revert EquipmentNotFound(_equipmentId);
        }
        
        EquipmentStatus oldStatus = equipment.status;
        equipment.status = _newStatus;
        
        // Automatic update of timestamps based on status
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
            msg.sender,
            block.timestamp
        );
    }

    /**
     * @notice Updates a document status
     * @param _documentId Document ID
     * @param _newStatus New status
     */
    function updateDocumentStatus(uint256 _documentId, DocumentStatus _newStatus) 
        external 
        onlyRole(CERTIFICATION_OFFICER) 
    {
        Document storage document = documents[_documentId];
        
        if (document.id == 0) {
            revert DocumentNotFound(_documentId);
        }
        
        if (document.status == DocumentStatus.Deprecated) {
            revert DocumentDeprecated(_documentId);
        }
        
        uint256 equipmentId = documentToEquipment[_documentId];
        
        if (equipments[equipmentId].status == EquipmentStatus.Certified) {
            if (!hasRole(REGULATORY_AUTHORITY, msg.sender) && !hasRole(PLANT_OPERATOR, msg.sender)) {
                revert EquipmentAlreadyCertified(equipmentId);
            }
        }
        
        if (equipments[equipmentId].status == EquipmentStatus.Deprecated) {
            revert EquipmentDeprecated(equipmentId);
        }
        
        if (equipments[equipmentId].currentStep == CertificationSteps.UnderReview) {
            if (!hasRole(REGULATORY_AUTHORITY, msg.sender)) {
                revert ActionNotAllowedInCurrentStep(equipmentId, CertificationSteps.UnderReview);
            }
        }
        
        DocumentStatus oldStatus = document.status;
        document.status = _newStatus;

        // Update timestamps based on new status
        if (_newStatus == DocumentStatus.Submitted) {
            document.submittedAt = block.timestamp;
        } else if (_newStatus == DocumentStatus.Pending) {
            document.pendingAt = block.timestamp;
        } else if (_newStatus == DocumentStatus.Verified) {
            document.verifiedAt = block.timestamp;
            emit DocumentVerified(_documentId, equipmentId, msg.sender, block.timestamp);
        } else if (_newStatus == DocumentStatus.Rejected) {
            document.rejectedAt = block.timestamp;
            emit DocumentRejected(_documentId, equipmentId, msg.sender, "", block.timestamp);
        } else if (_newStatus == DocumentStatus.Deprecated) {
            document.deprecatedAt = block.timestamp;
        }
        
        emit DocumentStatusChanged(_documentId, oldStatus, _newStatus, msg.sender, block.timestamp);
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
}