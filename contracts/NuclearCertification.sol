// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";


contract NuclearCertification is AccessControl, ERC721 {
    // Define roles
    bytes32 public constant PLANT_OPERATOR_ADMIN = keccak256("PLANT_OPERATOR_ADMIN"); 
    bytes32 public constant PLANT_OPERATOR = keccak256("PLANT_OPERATOR");
    bytes32 public constant MANUFACTURER = keccak256("MANUFACTURER");
    bytes32 public constant LABORATORY = keccak256("LABORATORY");
    bytes32 public constant REGULATORY_AUTHORITY = keccak256("REGULATORY_AUTHORITY");
    bytes32 public constant CERTIFICATION_OFFICER = keccak256("CERTIFICATION_OFFICER");

    // Id Counters
    uint256 private nextEquipmentId;
    uint256 private nextPlantId;
    uint256 private nextDocumentId;
    uint256 private nextActorId;



    enum Roles {
        PLANT_OPERATOR_ADMIN,
        PLANT_OPERATOR,
        MANUFACTURER,
        LABORATORY,
        REGULATORY_AUTHORITY,
        CERTIFICATION_OFFICER
    }

    enum CertificationSteps {
        Registered,
        RequirementsSubmitted,
        TechFileSubmitted,
        LabReportSubmitted,
        ComplianceSubmitted,
        UnderReview,
        Certified,
        Rejected
    }

    enum DocumentType {
        Certification,
        LabReport,
        TechFile,
        Compliance,
        ReviewComments
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

    // Mappings pour les acteurs
    mapping(Roles => Actor[]) public actorsByRole;
    mapping(address => Actor) public addressToActor;
    mapping(address => uint256[]) public actorToPlants;

    mapping(uint256 => Plant) public plants;
    mapping(uint256 => Equipment) public equipments;
    mapping(uint256 => uint256) public equipmentToPlant;

    // Tracking des équipements par plant
    mapping(uint256 => uint256[]) public plantToEquipments;

    mapping(uint256 => Document) public documents;
    mapping(uint256 => uint256) public documentToEquipment;


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
        Roles role;
        uint256 registeredAt;
    }


    // NFT EQUIPEMENT
    struct Equipment {
        uint256 id;
        string name;
        string description;
        CertificationSteps currentStep;
        EquipmentStatus status;
        string equipmentCode;
        uint256 registeredAt;
        uint256 certifiedAt;
        uint256 rejectedAt;
        uint256 pendingAt;
        uint256 deprecatedAt;
        string finalCertificationMerkleRoot;
    }


    // SBT DOCCUMENTS ( certification, lab report, tech file, compliance, review comments)
    struct Document {
        uint256 id;
        string name;
        string description;
        DocumentType docType;
        string baseURI;
        string documentURI;
        DocumentStatus status;
        string reviewComments;
        address submitter;
        uint256 submittedAt;
        uint256 verifiedAt;
        uint256 rejectedAt;
        uint256 pendingAt;
        uint256 deprecatedAt;
        string documentCode;
        string ipfsHash;
    }

    // Définir une structure TimeStamps
    struct TimeStamps {
        uint256 createdAt;
        uint256 registeredAt;
        uint256 submittedAt;
        uint256 verifiedAt;
        uint256 rejectedAt;
        uint256 certifiedAt;
        uint256 deprecatedAt;
    }

    // Events //
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

    /////////////////////////////////
    /////// CONSTRUCTOR ////////////
    /////////////////////////////////

    constructor() ERC721("Nuclear Equipment Traceability", "NET") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }


    /////////////////////////////////
    /////// Register Roles /////////
    /////////////////////////////////

    // Register Plant operator
    function registerPlantOperator(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PLANT_OPERATOR_ADMIN, _address);
        _grantRole(PLANT_OPERATOR, _address);
    }

    // Register Manufacturer
    function registerManufacturer(address _address) external onlyRole(PLANT_OPERATOR_ADMIN) {
        _grantRole(MANUFACTURER, _address);
    }

    // Register Laboratory
    function registerLaboratory(address _address) external onlyRole(PLANT_OPERATOR_ADMIN) {
        _grantRole(LABORATORY, _address);
    }

    // Register Regulatory Authority
    function registerRegulatoryAuthority(address _address) external onlyRole(PLANT_OPERATOR_ADMIN) {
        _grantRole(REGULATORY_AUTHORITY, _address);
    }

    // Register Certification Officer
    function registerCertificationOfficer(address _address) external onlyRole(PLANT_OPERATOR_ADMIN) {
        _grantRole(CERTIFICATION_OFFICER, _address);
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


    /////////////////////////////////
    /////// FUNCTIONS //////////////
    /////////////////////////////////


    // REGISTER PLANT
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

        // Stockage des données
        plants[plantId] = newPlant;
        actorToPlants[msg.sender].push(plantId);

        // Émission de l'événement
        emit PlantRegistered(
            plantId,
            _name,
            msg.sender,
            block.timestamp
        );
    }


    // REGISTER EQUIPMENT
    function registerEquipment(
        string memory _name,
        string memory _description,
        string memory _equipmentCode,
        uint256 _plantId
    ) external onlyRole(PLANT_OPERATOR) {
        require(bytes(_name).length > 0, unicode"Le nom ne peut pas être vide");
        require(bytes(_equipmentCode).length > 0, unicode"Le code d'équipement ne peut pas être vide");
        require(plants[_plantId].id != 0, unicode"La centrale n'existe pas");
        
        uint256 equipmentId = _getNextEquipmentId();
        
        Equipment memory newEquipment = Equipment({
            id: equipmentId,
            name: _name,
            description: _description,
            currentStep: CertificationSteps.Registered,
            status: EquipmentStatus.Registered,
            equipmentCode: _equipmentCode,
            registeredAt: block.timestamp,
            certifiedAt: 0,
            rejectedAt: 0,
            pendingAt: 0,
            deprecatedAt: 0,
            merkleRoot: ""
        });
        
        // Stockage des données
        equipments[equipmentId] = newEquipment;
        equipmentToPlant[equipmentId] = _plantId;
        plantToEquipments[_plantId].push(equipmentId);

        
        // Mint du NFT
        _safeMint(msg.sender, equipmentId);
        
        // Émission de l'événement
        emit EquipmentRegistered(equipmentId, _name, msg.sender, block.timestamp);
    }

    function registerDocument(
        uint256 _equipmentId,
        DocumentType _docType,
        string memory _documentURI,
        string memory _name,
        string memory _description,
        string memory _baseURI,
        string memory _ipfsHash,
        string memory _documentCode
    ) external {
        require(equipments[_equipmentId].id != 0, unicode"L'équipement n'existe pas")
        require(bytes(_name).length > 0, unicode"Le nom ne peut pas être vide")
        require(bytes(_description).length > 0, unicode"La description ne peut pas être vide")
        require(bytes(_baseURI).length > 0, unicode"Le baseURI ne peut pas être vide")
        require(bytes(_ipfsHash).length > 0, unicode"L'ipfsHash ne peut pas être vide")
        require(bytes(_documentCode).length > 0, unicode"Le code du document ne peut pas être vide")

        uint256 documentId = _getNextDocumentId()

        Document memory newDocument = Document({
            id: documentId,
            name: _name,
            description: _description,
            docType: _docType,
            baseURI: _baseURI,
            documentURI: _documentURI,
            status: DocumentStatus.Submitted,
            reviewComments: "",
            submitter: msg.sender,
            submittedAt: block.timestamp,
            verifiedAt: 0,
            rejectedAt: 0,
            pendingAt: 0,
            deprecatedAt: 0,
            documentCode: _documentCode,
            ipfsHash: _ipfsHash
        })

        documents[documentId] = newDocument
        documentToEquipment[documentId] = _equipmentId

        emit DocumentSubmitted(documentId, _equipmentId, _docType, msg.sender, block.timestamp)
    }



    function equipmentIsReadyForReview(uint256 _equipmentId) external onlyRole(PLANT_OPERATOR) {
        Equipment storage equipment = equipments[_equipmentId];
        require(equipment.status == EquipmentStatus.Pending, unicode"L'équipement n'est pas en attente de certification");

        equipment.currentStep = CertificationSteps.UnderReview;

        emit EquipmentStepUpdated(_equipmentId, equipment.currentStep, msg.sender, block.timestamp);
    }

    function finalCertification(uint256 _equipmentId, string memory _comments) external onlyRole(REGULATORY_AUTHORITY) {
        Equipment storage equipment = equipments[_equipmentId];
        require(equipment.status == EquipmentStatus.UnderReview, unicode"L'équipement n'est pas en attente de certification");

        equipment.reviewComments = _comments;

        equipment.currentStep = CertificationSteps.Certified;

        emit EquipmentStepUpdated(_equipmentId, equipment.currentStep, msg.sender, block.timestamp);
    }

    function rejectEquipment(uint256 _equipmentId, string memory _comments) external onlyRole(REGULATORY_AUTHORITY) {
        Equipment storage equipment = equipments[_equipmentId];
        require(equipment.status == EquipmentStatus.UnderReview, unicode"L'équipement n'est pas en attente de certification");

        equipment.reviewComments = _comments;

        equipment.currentStep = CertificationSteps.Rejected;

        emit EquipmentStepUpdated(_equipmentId, equipment.currentStep, msg.sender, block.timestamp);
    }

    function setMerkleRoot(uint256 _equipmentId, string memory _merkleRoot) external onlyRole(REGULATORY_AUTHORITY) {
        equipments[_equipmentId].merkleRoot = _merkleRoot;
    }






    /////////////////////////////////
    /////// Update Equipment ///////
    /////////////////////////////////

    function updateEquipmentStatus(uint256 _equipmentId, EquipmentStatus _newStatus) 
        external 
        onlyRole(CERTIFICATION_OFFICER) 
    {
        Equipment storage equipment = equipments[_equipmentId];
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
        }
        
        emit EquipmentStatusChanged(
            _equipmentId,
            oldStatus,
            _newStatus,
            msg.sender,
            block.timestamp
        );
    }

    function updateDocumentStatus(uint256 _documentId, DocumentStatus _newStatus) 
        external 
        onlyRole(CERTIFICATION_OFFICER) 
    {
        Document storage document = documents[_documentId];
        DocumentStatus oldStatus = document.status;
        document.status = _newStatus;
        
        // Automatic update of timestamps based on status
        if (_newStatus == DocumentStatus.Submitted) {
            document.submittedAt = block.timestamp;
        } else if (_newStatus == DocumentStatus.Pending) {
            document.pendingAt = block.timestamp;
        } else if (_newStatus == DocumentStatus.Verified) {
            document.verifiedAt = block.timestamp;
        } else if (_newStatus == DocumentStatus.Rejected) {
            document.rejectedAt = block.timestamp;
        }
        
        emit DocumentStatusChanged(_documentId, oldStatus, _newStatus, msg.sender, block.timestamp);
    }

    // Ajouter cette fonction pour la compatibilité ERC721/AccessControl
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}