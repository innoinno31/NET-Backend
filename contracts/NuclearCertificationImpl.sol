// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.28;

import "./NuclearCertificationStorage.sol";

// Custom Errors 
error EquipmentNotFound(uint256 equipmentId);
error EquipmentNotPending(uint256 equipmentId);
error EquipmentAlreadyDeprecated(uint256 equipmentId);
error EquipmentAlreadyCertified(uint256 equipmentId);
error EquipmentNotUnderReview(uint256 equipmentId);
error DocumentNotFound(uint256 documentId);
error UnauthorizedDocumentAccess(uint256 documentId, address caller);
error PlantNotFound(uint256 plantId);
error InvalidInput(string reason);
error ActionNotAllowedInCurrentStep(uint256 equipmentId, NuclearCertificationStorage.CertificationSteps step);
error UnauthorizedRole(address caller);
error RoleAlreadyAssigned(address actor, bytes32 role);

/**
 * @title NuclearCertificationImpl
 * @author Franck
 * @notice Implementation contract for nuclear certification
 * @dev Uses a proxy pattern to reference the storage contract instead of inheritance
 */
contract NuclearCertificationImpl {
    // Reference to the storage contract
    NuclearCertificationStorage public storageContract;

    // Constants from the storage contract for easier access
    bytes32 public constant PLANT_OPERATOR_ADMIN = keccak256("PLANT_OPERATOR_ADMIN");
    bytes32 public constant MANUFACTURER = keccak256("MANUFACTURER");
    bytes32 public constant LABORATORY = keccak256("LABORATORY");
    bytes32 public constant REGULATORY_AUTHORITY = keccak256("REGULATORY_AUTHORITY");
    bytes32 public constant CERTIFICATION_OFFICER = keccak256("CERTIFICATION_OFFICER");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant IMPL_ROLE = keccak256("IMPL_ROLE");

    event IntegrityVerified(
        uint256 indexed equipmentId,
        bytes32 hashGlobal,
        bool isValid,
        address verifier,
        uint256 timestamp
    );

    event ReviewStarted(
        uint256 indexed equipmentId,
        address indexed reviewer,
        uint256 timestamp
    );

    /**
     * @dev finalHash The final hash of the certification
     */
    event CertificationFinalized(
        uint256 indexed equipmentId, 
        address indexed finalizer, 
        bool approved, 
        bytes32 finalHash,
        string reason,
        uint256 timestamp
    );

    event EquipmentDeprecated(
        uint256 indexed equipmentId,
        address indexed deprecatedBy,
        uint256 timestamp
    );

    /**
     * @notice Initialize the contract with a reference to the storage contract
     * @param _storageAddress Address of the storage contract
     */
    constructor(address _storageAddress) {
        require(_storageAddress != address(0), "Storage address cannot be zero");
        storageContract = NuclearCertificationStorage(_storageAddress);
    }

    /**
     * @notice Get an equipment by its ID
     * @param _equipmentId Equipment ID
     * @return The equipment data
     */
    function getEquipment(uint256 _equipmentId)
        internal
        view
        returns (NuclearCertificationStorage.Equipment memory)
    {
        return storageContract.getEquipment(_equipmentId);
    }

    /**
     * @notice Get a document by its ID
     * @param _documentId Document ID
     * @return The document data
     */
    function getDocument(uint256 _documentId)
        public
        view
        returns (NuclearCertificationStorage.Document memory)
    {
        return storageContract.getDocument(_documentId);
    }

    /**
     * @notice Get equipment documents
     * @param _equipmentId Equipment ID
     * @return Array of document IDs
     */
    function getEquipmentDocs(uint256 _equipmentId)
        internal
        view
        returns (uint256[] memory)
    {
        return storageContract.getEquipmentDocuments(_equipmentId);
    }

    /** Modifiers */
    /**
     * @notice Verifies that the equipment is not already certified or under review
     * @dev Modifier to prevent modifications after final certification or during review
     * @param _equipmentId ID of the equipment to check
     */
    modifier notCertifiedOrUnderReview(uint256 _equipmentId) {
        NuclearCertificationStorage.Equipment memory equipment = getEquipment(_equipmentId);
        
        if (equipment.currentStep == NuclearCertificationStorage.CertificationSteps.UnderReview) {
            if (!storageContract.hasRole(REGULATORY_AUTHORITY, msg.sender)) {
                revert ActionNotAllowedInCurrentStep(_equipmentId, NuclearCertificationStorage.CertificationSteps.UnderReview);
            }
        }
        
        // Block modifications if equipment is certified except for regulatory authority and plant operator
        if (equipment.status == NuclearCertificationStorage.EquipmentStatus.Certified) {
            if (!storageContract.hasRole(REGULATORY_AUTHORITY, msg.sender) && 
                !storageContract.hasRole(PLANT_OPERATOR_ADMIN, msg.sender)) {
                revert EquipmentAlreadyCertified(_equipmentId);
            }
        }       
        _;
    }

    /**
     * @notice Verifies that the sender has certification officer role
     */
    modifier onlyCertificationOfficer() {
        if (!storageContract.hasRole(CERTIFICATION_OFFICER, msg.sender)) {
            revert UnauthorizedRole(msg.sender);
        }
        _;
    }

    /**
     * @notice Verifies that the equipment is not deprecated
     * @dev Modifier to prevent modifications with deprecated equipment
     * @param _equipmentId ID of the equipment to check
     */
    modifier notDeprecated(uint256 _equipmentId) {
        NuclearCertificationStorage.Equipment memory equipment = getEquipment(_equipmentId);
        
        if (equipment.status == NuclearCertificationStorage.EquipmentStatus.Deprecated) {
            revert EquipmentAlreadyDeprecated(_equipmentId);
        }      
        _;
    }

    /**
     * @notice Verifies that the sender is authorized to submit a document
     * @dev Modifier to prevent document submissions by unauthorized roles
     */
    modifier authorizedSubmitter() {
        require(
            storageContract.hasRole(MANUFACTURER, msg.sender) ||
            storageContract.hasRole(LABORATORY, msg.sender) ||
            storageContract.hasRole(PLANT_OPERATOR_ADMIN, msg.sender) ||
            storageContract.hasRole(REGULATORY_AUTHORITY, msg.sender),
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
            !storageContract.hasRole(PLANT_OPERATOR_ADMIN, msg.sender) && 
            !storageContract.hasRole(REGULATORY_AUTHORITY, msg.sender) && 
            !storageContract.hasRole(CERTIFICATION_OFFICER, msg.sender)
        ) {
            NuclearCertificationStorage.Document memory doc = getDocument(_documentId);

            // Manufacturers can only see their own documents + certification
            if (storageContract.hasRole(MANUFACTURER, msg.sender)) {
                if (doc.submitter != msg.sender && doc.docType != NuclearCertificationStorage.DocumentType.Certification) {
                    revert UnauthorizedRole(msg.sender);
                }
            } 
            // Labs can see their own documents + tech files + certification
            else if (storageContract.hasRole(LABORATORY, msg.sender)) {
                if (
                    doc.submitter != msg.sender && 
                    doc.docType != NuclearCertificationStorage.DocumentType.TechFile && 
                    doc.docType != NuclearCertificationStorage.DocumentType.Certification
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

    /**
     * @notice Verifies that the sender has a specific role
     * @param role The role to check
     */
    modifier onlyRole(bytes32 role) {
        require(storageContract.hasRole(role, msg.sender), "Caller doesn't have the required role");
        _;
    }

    /////////////////////////////////
    /////// Register Roles /////////
    /////////////////////////////////

    /**
     * @notice Registers a plant operator
     * @param _address Address of the operator to register
     * @param _plantId Associated plant ID
     * @param _name Operator's name
     */
    function registerPlantOperator(
        address _address,
        uint256 _plantId,
        string memory _name
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (storageContract.hasRole(PLANT_OPERATOR_ADMIN, _address)) {
            revert RoleAlreadyAssigned(_address, PLANT_OPERATOR_ADMIN);
        }

        storageContract.grantRoleWithCaller(PLANT_OPERATOR_ADMIN, _address, msg.sender);
        
        storageContract.createActor(_name, _address, PLANT_OPERATOR_ADMIN, _plantId);
    }

    /**
     * @notice Registers a manufacturer
     * @param _address Address of the manufacturer to register
     * @param _plantId Associated plant ID
     * @param _name Manufacturer's name
     */
    function registerManufacturer(
        address _address,
        uint256 _plantId,
        string memory _name
    )
        external
        onlyRole(PLANT_OPERATOR_ADMIN)
    {
        if (storageContract.hasRole(MANUFACTURER, _address)) {
            revert RoleAlreadyAssigned(_address, MANUFACTURER);
        }

        storageContract.grantRoleWithCaller(MANUFACTURER, _address, msg.sender);
        
        storageContract.createActor(_name, _address, MANUFACTURER, _plantId);
    }

    /**
     * @notice Registers a laboratory
     * @param _address Address of the laboratory to register
     * @param _plantId Associated plant ID
     * @param _name Laboratory's name
     */
    function registerLaboratory(
        address _address,
        uint256 _plantId,
        string memory _name
    )
        external
        onlyRole(PLANT_OPERATOR_ADMIN)
    {
        if (storageContract.hasRole(LABORATORY, _address)) {
            revert RoleAlreadyAssigned(_address, LABORATORY);
        }

        storageContract.grantRoleWithCaller(LABORATORY, _address, msg.sender);
        
        storageContract.createActor(_name, _address, LABORATORY, _plantId);
    }

    /**
     * @notice Registers a regulatory authority
     * @param _address Address of the authority to register
     * @param _plantId Associated plant ID
     * @param _name Authority's name
     */
    function registerRegulatoryAuthority(
        address _address,
        uint256 _plantId,
        string memory _name
    )
        external
        onlyRole(PLANT_OPERATOR_ADMIN)
    {
        if (storageContract.hasRole(REGULATORY_AUTHORITY, _address)) {
            revert RoleAlreadyAssigned(_address, REGULATORY_AUTHORITY);
        }

        storageContract.grantRoleWithCaller(REGULATORY_AUTHORITY, _address, msg.sender);
        
        storageContract.createActor(_name, _address, REGULATORY_AUTHORITY, _plantId);
    }

    /**
     * @notice Registers a certification officer
     * @param _address Address of the officer to register
     * @param _plantId Associated plant ID
     * @param _name Officer's name
     */
    function registerCertificationOfficer(
        address _address,
        uint256 _plantId,
        string memory _name
    )
        external
        onlyRole(PLANT_OPERATOR_ADMIN)
    {
        if (storageContract.hasRole(CERTIFICATION_OFFICER, _address)) {
            revert RoleAlreadyAssigned(_address, CERTIFICATION_OFFICER);
        }

        storageContract.grantRoleWithCaller(CERTIFICATION_OFFICER, _address, msg.sender);
        
        storageContract.createActor(_name, _address, CERTIFICATION_OFFICER, _plantId);
    }

    /////////////////////////////////
    /////// Getters ////////////////
    /////////////////////////////////

    /**
     * @notice Gets all documents linked to an equipment
     * @param _equipmentId The equipment identifier
     * @return An array of document identifiers
     */
    function getEquipmentDocuments(uint256 _equipmentId)
        public
        view
        returns (uint256[] memory)
    {
        return getEquipmentDocs(_equipmentId);
    }

    /**
     * @notice Gets the IPFS hashes of all documents linked to an equipment
     * @param _equipmentId The equipment identifier
     * @return An array of IPFS hashes
     */
    function getEquipmentDocumentHashes(uint256 _equipmentId)
        public
        view
        returns (string[] memory)
    {
        uint256[] memory docIds = getEquipmentDocs(_equipmentId);
        string[] memory hashes = new string[](docIds.length);
        
        for (uint256 i = 0; i < docIds.length; i++) {
            NuclearCertificationStorage.Document memory doc = getDocument(docIds[i]);
            hashes[i] = doc.ipfsHash;
        }
        
        return hashes;
    }

    /**
     * @notice Verifies the integrity of documents for a certified or deprecated equipment
     * @param _equipmentId The equipment identifier
     * @param _calculatedHash The global hash calculated off-chain
     * @return bool True if the hash matches, false otherwise
     */
    function verifyEquipmentIntegrity(uint256 _equipmentId, bytes32 _calculatedHash)
        public
        view
        returns (bool)
    {
        NuclearCertificationStorage.Equipment memory equipment = getEquipment(_equipmentId);
        
        if (equipment.registeredAt == 0) {
            revert EquipmentNotFound(_equipmentId);
        }
        
        // Check if the equipment is certified or deprecated
        if (equipment.status != NuclearCertificationStorage.EquipmentStatus.Certified &&
            equipment.status != NuclearCertificationStorage.EquipmentStatus.Deprecated) {
            revert ActionNotAllowedInCurrentStep(_equipmentId, equipment.currentStep);
        }
        
        bool isValid = equipment.finalCertificationHash == _calculatedHash;
        
        return isValid;
    }

    /**
     * @notice Verifies and logs equipment integrity
     * @param _equipmentId The equipment identifier
     * @param _calculatedHash The global hash calculated off-chain
     * @return bool True if the hash matches, false otherwise
     */
    function checkAndLogEquipmentIntegrity(uint256 _equipmentId, bytes32 _calculatedHash)
        external
        returns (bool)
    {
        bool isValid = verifyEquipmentIntegrity(_equipmentId, _calculatedHash);
        
        emit IntegrityVerified(_equipmentId, _calculatedHash, isValid, msg.sender, block.timestamp);
        
        return isValid;
    }

    /**
     * @notice Checks if the caller has access to a specific document based on roles and ownership
     * @param _documentId ID of the document to check
     * @return true if access is allowed, false otherwise
     */
    function isDocumentAccessible(uint256 _documentId)
        public
        view
        returns (bool)
    {
        NuclearCertificationStorage.Document memory doc = getDocument(_documentId);
        
        if (doc.submittedAt == 0) {
            return false;
        }

        // Plant Operators, Regulatory Authorities, and Certification Officers can see all documents
        if (
            storageContract.hasRole(PLANT_OPERATOR_ADMIN, msg.sender) || 
            storageContract.hasRole(REGULATORY_AUTHORITY, msg.sender) || 
            storageContract.hasRole(CERTIFICATION_OFFICER, msg.sender)
        ) {
            return true;
        }

        // Manufacturers can only see their own documents + certification
        if (storageContract.hasRole(MANUFACTURER, msg.sender)) {
            return doc.submitter == msg.sender || doc.docType == NuclearCertificationStorage.DocumentType.Certification;
        } 
        // Labs can see their own documents + tech files + certification
        else if (storageContract.hasRole(LABORATORY, msg.sender)) {
            return 
                doc.submitter == msg.sender || 
                doc.docType == NuclearCertificationStorage.DocumentType.TechFile || 
                doc.docType == NuclearCertificationStorage.DocumentType.Certification;
        }

        return false;
    }

    /**
     * @notice Checks if a specific user can view a document based on roles and ownership
     * @param _documentId ID of the document to check
     * @param _viewer Address of the user who wants to view the document
     * @return bool True if access is allowed, false otherwise
     */
    function canViewDocument(uint256 _documentId, address _viewer)
        public
        view
        returns (bool)
    {
        NuclearCertificationStorage.Document memory doc = getDocument(_documentId);
        
        if (doc.submittedAt == 0) {
            revert DocumentNotFound(_documentId);
        }
        
        // The submitter of a document can always access it
        if (doc.submitter == _viewer) {
            return true;
        }
        
        // Check access rules based on roles
        bytes32 role;
        
        if (storageContract.hasRole(PLANT_OPERATOR_ADMIN, _viewer)) role = PLANT_OPERATOR_ADMIN;
        else if (storageContract.hasRole(MANUFACTURER, _viewer)) role = MANUFACTURER;
        else if (storageContract.hasRole(LABORATORY, _viewer)) role = LABORATORY;
        else if (storageContract.hasRole(REGULATORY_AUTHORITY, _viewer)) role = REGULATORY_AUTHORITY;
        else if (storageContract.hasRole(CERTIFICATION_OFFICER, _viewer)) role = CERTIFICATION_OFFICER;
        else return false;
        
        return storageContract.hasDocumentAccess(doc.docType, role);
    }

    /**
     * @notice Retrieves a document if the caller is authorized to view it
     * @param _documentId ID of the document to retrieve
     * @return The requested document
     */
    function getDocumentIfAuthorized(uint256 _documentId)
        external
        view
        onlyDocumentAuthorized(_documentId)
        returns (NuclearCertificationStorage.Document memory)
    {
        return getDocument(_documentId);
    }

    /**
     * @notice Gets all plants registered in the storage contract
     * @return Array of Plant structs
     */
    function getAllPlants()
        external
        view
        returns (NuclearCertificationStorage.Plant[] memory)
    {
        uint256[] memory plantIds = storageContract.getAllPlantIds();
        NuclearCertificationStorage.Plant[] memory allPlants = new NuclearCertificationStorage.Plant[](plantIds.length);

        for (uint i = 0; i < plantIds.length; i++) {
            allPlants[i] = storageContract.getPlant(plantIds[i]);
        }

        return allPlants;
    }

    /**
     * @notice Vérifie si l'appelant est autorisé à consulter la liste des acteurs
     * @dev Seuls les rôles d'administration, d'opérateur de centrale et d'autorité réglementaire peuvent voir la liste
     */
    modifier canViewActors() {
        require(
            storageContract.hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
            storageContract.hasRole(PLANT_OPERATOR_ADMIN, msg.sender) ||
            storageContract.hasRole(REGULATORY_AUTHORITY, msg.sender),
            "Unauthorized: Cannot view actors list"
        );
        _;
    }

    /**
     * @notice Gets all actors with their roles
     * @dev Requires caller to have DEFAULT_ADMIN_ROLE, PLANT_OPERATOR_ADMIN, or REGULATORY_AUTHORITY
     * @return Array of Actor structs
     */
    function getAllActorsWithRoles()
        external
        view
        canViewActors
        returns (NuclearCertificationStorage.Actor[] memory)
    {
        uint256[] memory actorIds = storageContract.getAllActorIds();
        NuclearCertificationStorage.Actor[] memory allActors = new NuclearCertificationStorage.Actor[](actorIds.length);

        for (uint i = 0; i < actorIds.length; i++) {
            allActors[i] = storageContract.getActor(actorIds[i]);
        }

        return allActors;
    }

    /**
     * @notice Gets all actors associated with a specific plant
     * @dev Requires caller to have DEFAULT_ADMIN_ROLE, PLANT_OPERATOR_ADMIN, or REGULATORY_AUTHORITY
     * @param _plantId ID of the plant
     * @return Array of Actor structs
     */
    function getAllActorsWithRolesByPlant(uint256 _plantId)
        external
        view
        canViewActors
        returns (NuclearCertificationStorage.Actor[] memory)
    {
        uint256[] memory actorIds = storageContract.getPlantActorIds(_plantId);
        
        NuclearCertificationStorage.Actor[] memory plantActors = new NuclearCertificationStorage.Actor[](actorIds.length);
        
        for (uint i = 0; i < actorIds.length; i++) {
            plantActors[i] = storageContract.getActor(actorIds[i]);
        }
        
        return plantActors;
    }

    /**
     * @notice Vérifie si l'appelant est autorisé à consulter les documents d'une centrale
     * @dev Seuls les rôles d'administration, d'opérateur admin et d'autorité réglementaire peuvent voir les documents d'une centrale
     */
    modifier canViewPlantDocuments() {
        require(
            storageContract.hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
            storageContract.hasRole(PLANT_OPERATOR_ADMIN, msg.sender) ||
            storageContract.hasRole(REGULATORY_AUTHORITY, msg.sender),
            "Unauthorized: Cannot view plant documents"
        );
        _;
    }

    /**
     * @notice Gets all documents associated with a specific plant
     * @dev Requires caller to have DEFAULT_ADMIN_ROLE, PLANT_OPERATOR_ADMIN, or REGULATORY_AUTHORITY
     * @param _plantId ID of the plant
     * @return Array of Document structs
     */
    function getDocumentsByPlant(uint256 _plantId)
        external
        view
        canViewPlantDocuments
        returns (NuclearCertificationStorage.Document[] memory)
    {
        uint256[] memory equipmentIds = storageContract.getPlantEquipmentIds(_plantId);
        
        uint256 totalDocumentsCount = 0;
        for (uint i = 0; i < equipmentIds.length; i++) {
            totalDocumentsCount += storageContract.getEquipmentDocuments(equipmentIds[i]).length;
        }
        
        NuclearCertificationStorage.Document[] memory allPlantDocuments = new NuclearCertificationStorage.Document[](totalDocumentsCount);
        uint256 docIndex = 0;
        
        // Iterate through each equipment and add its documents to the array
        for (uint i = 0; i < equipmentIds.length; i++) {
            uint256[] memory docIds = storageContract.getEquipmentDocuments(equipmentIds[i]);
            for (uint j = 0; j < docIds.length; j++) {
                allPlantDocuments[docIndex] = storageContract.getDocument(docIds[j]);
                docIndex++;
            }
        }
        
        return allPlantDocuments;
    }

    /**
     * @notice Gets all equipment associated with a specific plant
     * @dev Requires caller to have DEFAULT_ADMIN_ROLE, PLANT_OPERATOR_ADMIN, or REGULATORY_AUTHORITY
     * @param _plantId ID of the plant
     * @return Array of Equipment structs
     */
    function getEquipmentByPlant(uint256 _plantId)
        external
        view
        canViewPlantDocuments
        returns (NuclearCertificationStorage.Equipment[] memory)
    {
        uint256[] memory equipmentIds = storageContract.getPlantEquipmentIds(_plantId);
        NuclearCertificationStorage.Equipment[] memory plantEquipment = new NuclearCertificationStorage.Equipment[](equipmentIds.length);

        for (uint i = 0; i < equipmentIds.length; i++) {
            plantEquipment[i] = storageContract.getEquipment(equipmentIds[i]);
        }

        return plantEquipment;
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
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        storageContract.createPlant(
            msg.sender,
            _name,
            _description,
            _location,
            _isActive
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
    )
        external
        onlyRole(PLANT_OPERATOR_ADMIN)
    {
        NuclearCertificationStorage.Plant memory plant = storageContract.getPlant(_plantId);
        
        if (bytes(_name).length == 0) {
            revert InvalidInput("Name cannot be empty");
        }
        
        if (plant.registeredAt == 0) {
            revert PlantNotFound(_plantId);
        }
        
        storageContract.createEquipment(msg.sender, _name, _description, _plantId);
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
        NuclearCertificationStorage.DocumentType _docType,
        string memory _name,
        string memory _description,
        string memory _ipfsHash
    )
        external
        authorizedSubmitter
        notCertifiedOrUnderReview(_equipmentId)
        notDeprecated(_equipmentId)
    {
        NuclearCertificationStorage.Equipment memory equipment = getEquipment(_equipmentId);
        
        if (equipment.registeredAt == 0) {
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
        
        storageContract.createDocument(
            msg.sender,
            _equipmentId,
            _docType,
            _name,
            _description,
            _ipfsHash
        );
    }

    /**
     * @notice Marks an equipment as ready for review by Plant Operator Admin
     * @param _equipmentId Equipment ID
     */
    function equipmentIsReadyForReview(uint256 _equipmentId)
        external
        onlyRole(PLANT_OPERATOR_ADMIN)
        notCertifiedOrUnderReview(_equipmentId)
        notDeprecated(_equipmentId)
    {
        NuclearCertificationStorage.Equipment memory equipment = getEquipment(_equipmentId);
        
        if (equipment.status != NuclearCertificationStorage.EquipmentStatus.Pending) {
            revert EquipmentNotPending(_equipmentId);
        }

        storageContract.updateEquipmentStatus(
            msg.sender,
            _equipmentId,
            NuclearCertificationStorage.EquipmentStatus.Pending, 
            NuclearCertificationStorage.CertificationSteps.ReadyForReview // Step is now ReadyForReview
        );        
    }

    /**
     * @notice Initiates the review of an equipment by the Regulatory Authority
     * @param _equipmentId ID of the equipment to review
     */
    function reviewEquipment(uint256 _equipmentId)
        external
        onlyRole(REGULATORY_AUTHORITY)
        notDeprecated(_equipmentId)
    {
        NuclearCertificationStorage.Equipment memory equipment = getEquipment(_equipmentId);

        if (equipment.currentStep != NuclearCertificationStorage.CertificationSteps.ReadyForReview) {
            revert ActionNotAllowedInCurrentStep(_equipmentId, equipment.currentStep);
        }

        storageContract.updateEquipmentStatus(
            msg.sender,
            _equipmentId,
            NuclearCertificationStorage.EquipmentStatus.Pending,
            NuclearCertificationStorage.CertificationSteps.UnderReview
        );

        emit ReviewStarted(_equipmentId, msg.sender, block.timestamp);
    }

    /**
     * @notice Finalizes the certification process for an equipment (Approve or Reject)
     * @param _equipmentId ID of the equipment
     * @param _approve True to approve, False to reject
     * @param _finalHash Hash of all document hashes (ignored if rejecting)
     * @param _reason Reason for rejection (ignored if approving)
     */
    function finalizeCertification(
        uint256 _equipmentId,
        bool _approve,
        bytes32 _finalHash,
        string memory _reason
    )
        external
        onlyRole(REGULATORY_AUTHORITY)
        notDeprecated(_equipmentId)
    {
        NuclearCertificationStorage.Equipment memory equipment = getEquipment(_equipmentId);

        if (equipment.currentStep != NuclearCertificationStorage.CertificationSteps.UnderReview) {
            revert EquipmentNotUnderReview(_equipmentId);
        }

        NuclearCertificationStorage.EquipmentStatus newStatus;
        NuclearCertificationStorage.CertificationSteps newStep;
        string memory finalReason = "";
        bytes32 eventHash = bytes32(0);

        if (_approve) {
            newStatus = NuclearCertificationStorage.EquipmentStatus.Certified;
            newStep = NuclearCertificationStorage.CertificationSteps.Certified;
            if (_finalHash == bytes32(0)) {
                revert InvalidInput("Final certification hash cannot be empty for approval");
            }
            storageContract.setFinalCertificationHash(_equipmentId, _finalHash);
            eventHash = _finalHash;
        } else {
            newStatus = NuclearCertificationStorage.EquipmentStatus.Rejected;
            newStep = NuclearCertificationStorage.CertificationSteps.Rejected;
            if (bytes(_reason).length == 0) {
                 revert InvalidInput("Rejection reason cannot be empty");
            }
            finalReason = _reason;
            storageContract.setRejectionReason(_equipmentId, finalReason);
            storageContract.setFinalCertificationHash(_equipmentId, bytes32(0));
        }

        storageContract.updateEquipmentStatus(
            msg.sender,
            _equipmentId,
            newStatus,
            newStep
        );

        emit CertificationFinalized(_equipmentId, msg.sender, _approve, eventHash, finalReason, block.timestamp);
    }

    /**
     * @notice Marks an equipment as deprecated by the Regulatory Authority
     * @param _equipmentId ID of the equipment to deprecate
     */
    function deprecateEquipment(uint256 _equipmentId)
        external
        onlyRole(REGULATORY_AUTHORITY)
    {
        NuclearCertificationStorage.Equipment memory equipment = getEquipment(_equipmentId);

        if (equipment.status == NuclearCertificationStorage.EquipmentStatus.Deprecated) {
            revert EquipmentAlreadyDeprecated(_equipmentId);
        }

        storageContract.updateEquipmentStatus(
            msg.sender,
            _equipmentId,
            NuclearCertificationStorage.EquipmentStatus.Deprecated,
            equipment.currentStep // Keep current step 
        );

        emit EquipmentDeprecated(_equipmentId, msg.sender, block.timestamp);
    }
} 